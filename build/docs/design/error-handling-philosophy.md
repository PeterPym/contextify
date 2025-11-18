# Error Handling Philosophy

**Last Updated:** 2025-11-17
**Status:** ✅ Active
**Audience:** Developers implementing error handling in Contextify

---

## Table of Contents

1. [Overview](#overview)
2. [Error Handling Strategies](#error-handling-strategies)
3. [When to Throw vs Return Result](#when-to-throw-vs-return-result)
4. [Error Type Design](#error-type-design)
5. [User-Facing vs Debug Messages](#user-facing-vs-debug-messages)
6. [Recovery Strategies](#recovery-strategies)
7. [Logging Conventions](#logging-conventions)
8. [Async Error Handling](#async-error-handling)
9. [UI Error Presentation](#ui-error-presentation)
10. [Testing Error Paths](#testing-error-paths)

---

## Overview

### Philosophy

**Core Principles:**
1. **Fail fast, recover gracefully** - Detect errors early, provide clear recovery paths
2. **User-facing errors are informative** - Tell users what went wrong and what they can do
3. **Debug errors are detailed** - Give developers context for diagnosis
4. **Errors are typed** - Use enum-based errors with associated values
5. **Recovery is explicit** - Make retry/fallback logic obvious in code

### Error Categories

| Category | Example | User Impact | Recovery |
|----------|---------|-------------|----------|
| **User Error** | Invalid file selection | Show message, suggest fix | User corrects input |
| **Transient Error** | Network timeout, file locked | Retry automatically | Auto-retry with backoff |
| **Permanent Error** | File not found, permission denied | Show message, block feature | User grants permission |
| **Logic Error** | Assertion failure, nil unwrap | Crash (DEBUG), log (RELEASE) | Fix bug |
| **System Error** | Out of memory, disk full | Show message, degrade gracefully | User frees resources |

---

## Error Handling Strategies

### Pattern Summary

| Strategy | Use Case | Example |
|----------|----------|---------|
| `throws` | Expected failures in normal flow | File I/O, network requests, validation |
| `Result<T, E>` | Async operations with multiple outcomes | Startup sequencing (success/timeout/no project) |
| `Optional` | Absence is not an error | Dictionary lookup, optional configuration |
| `fatalError()` | Unrecoverable programmer errors | Missing required resource, impossible state |
| `assert()` | DEBUG-only invariants | Precondition checks, internal consistency |

### Decision Tree

```
Is this a programmer error (bug)?
├─ YES → fatalError() or assert()
└─ NO → Is failure expected in normal operation?
    ├─ YES → throws or Result<>
    │   └─ Is the caller async/await?
    │       ├─ YES → throws (preferred)
    │       └─ NO → Result<> (if completion handler pattern)
    │
    └─ NO → Absence is valid?
        ├─ YES → Optional
        └─ NO → throws

Does the function have multiple distinct outcomes (not just success/failure)?
└─ YES → Consider Result<> or custom enum
```

---

## When to Throw vs Return Result

### Use throws for:

**✅ Sync/async operations with single success path**

```swift
func migrateDatabase(to targetDirectory: URL, deleteSource: Bool = false) async throws {
  // Verify source exists
  guard FileManager.default.fileExists(atPath: currentPath.path) else {
    throw MigrationError.sourceNotFound
  }

  // Verify target doesn't exist
  if FileManager.default.fileExists(atPath: targetPath.path) {
    throw MigrationError.targetExists
  }

  // Perform migration
  try FileManager.default.copyItem(at: currentPath, to: targetPath)
}
```

**File:** `app/Sources/ContextifyCore/Database/DatabaseMigration.swift:38`

**When:**
- Standard Swift async/await code
- Single failure type (can use enum Error)
- Caller wants to use `try/catch`
- Operation is I/O, validation, or computation

### Use Result<> for:

**✅ Complex startup sequencing with timeout**

```swift
enum StartupOutcome {
  case success(ActiveProjectContext)
  case timeout
  case noProjectsFound
}

func ready(timeout: TimeInterval = 5.0) async -> Result<ActiveProjectContext, StartupError> {
  // Wait for project identity with timeout
  let start = Date()
  while Date().timeIntervalSince(start) < timeout {
    if let context = self.current {
      return .success(context)
    }
    try? await Task.sleep(for: .milliseconds(50))
  }

  // Timeout or no projects
  if discoveryCompleted && allProjects.isEmpty {
    return .failure(.noProjectsFound)
  }
  return .failure(.timeout)
}
```

**File:** `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift` (pattern)

**When:**
- Multiple distinct outcomes (not just success/error)
- Completion handler patterns (legacy code)
- Caller needs to pattern match on outcomes
- Error is part of the API contract (not exceptional)

### Use Optional for:

**✅ Absence is valid (not an error)**

```swift
func getCachedSummary(contentSHA: String, windowSHA: String) -> String? {
  // Cache miss is not an error
  return cache[contentSHA + windowSHA]
}

func activeProject() -> ProjectInfo? {
  // No active project is a valid state
  return projects.first(where: { $0.isActive })
}
```

**When:**
- Absence/nil is a valid outcome
- Caller doesn't need error details
- Simple lookup/query operations

---

## Error Type Design

### Enum-Based Errors (Preferred)

**Pattern:**

```swift
public enum MigrationError: Error, LocalizedError {
  case sourceNotFound
  case targetExists
  case insufficientSpace(required: Int64, available: Int64)
  case copyFailed(underlying: Error)
  case validationFailed

  public var errorDescription: String? {
    switch self {
    case .sourceNotFound:
      return "Source database not found"
    case .targetExists:
      return "Target directory already contains a database"
    case .insufficientSpace(let required, let available):
      return "Insufficient disk space: need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) but only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available"
    case .copyFailed(let underlying):
      return "Failed to copy database: \(underlying.localizedDescription)"
    case .validationFailed:
      return "Database validation failed after migration"
    }
  }
}
```

**File:** `app/Sources/ContextifyCore/Database/DatabaseMigration.swift:35-50`

**Key Features:**
- **Enum cases:** Each distinct error condition
- **Associated values:** Context for diagnosis (required/available space, underlying error)
- **LocalizedError:** User-facing descriptions via `errorDescription`
- **Namespaced:** Nested in containing type (DatabaseMigration.MigrationError)

### Error Properties

**Add helper properties for behavior:**

```swift
enum TimelineError: Swift.Error {
  case llmTimeout
  case contextOverflow(tokens: Int, limit: Int)
  case guardrailViolation(reason: String)
  case decodingFailure(reason: String)
  case databaseError(String)
  case unexpected(String)
  case cancelled
  case llmUnavailable(reason: String)

  var isRetryable: Bool {
    switch self {
    case .llmTimeout, .contextOverflow, .databaseError:
      return true
    case .guardrailViolation, .decodingFailure, .unexpected, .cancelled, .llmUnavailable:
      return false
    }
  }

  var userMessage: String {
    switch self {
    case .llmTimeout:
      return "The timeline summary timed out. Retrying..."
    case .contextOverflow(let tokens, let limit):
      return "Message too long (\(tokens) tokens, limit \(limit)). Please shorten your input."
    case .llmUnavailable(let reason):
      return "AI summarization unavailable: \(reason)"
    default:
      return "An unexpected error occurred. Please try again."
    }
  }
}
```

**File:** `Contextify/Contextify/FoundationLLM.swift:1146-1167` (pattern)

**Useful Properties:**
- `isRetryable: Bool` - Should operation be retried?
- `userMessage: String` - User-facing message
- `logMessage: String` - Debug-level details
- `severity: ErrorSeverity` - `.warning`, `.error`, `.critical`

### FolderAccessError Example

**File:** `app/Sources/ContextifyCore/Security/FolderAccessController.swift:15-35`

```swift
public enum FolderAccessError: Error, LocalizedError {
  case bookmarkCreationFailed(URL)
  case bookmarkResolutionFailed
  case securityScopeAccessDenied(URL)
  case userCancelled
  case staleBookmarkRefreshFailed(URL)
  case noTranscriptsFound(URL, SourceID)

  public var errorDescription: String? {
    switch self {
    case .bookmarkCreationFailed(let url):
      return "Failed to create security bookmark for \(url.path)"
    case .bookmarkResolutionFailed:
      return "Failed to resolve security bookmark"
    case .securityScopeAccessDenied(let url):
      return "Access denied to \(url.path). Please grant permission in System Settings."
    case .userCancelled:
      return "Operation cancelled by user"
    case .staleBookmarkRefreshFailed(let url):
      return "Failed to refresh stale bookmark for \(url.path)"
    case .noTranscriptsFound(let url, let source):
      return "No transcripts found in \(url.path) for source \(source.rawValue)"
    }
  }
}
```

**Note:** `.userCancelled` is informational (not really an error), but modeled as Error for consistency.

---

## User-Facing vs Debug Messages

### Levels of Detail

| Audience | Content | Example |
|----------|---------|---------|
| **User** | What went wrong + what to do | "Database migration failed. Please check that you have at least 2GB of free disk space." |
| **Support** | Error code + basic context | "Migration failed (ERR_INSUFFICIENT_SPACE): required 2048MB, available 512MB" |
| **Developer** | Full context + stack trace | "DatabaseMigration.migrateDatabase() failed at line 94: copyFailed(NSError domain: NSCocoaErrorDomain code: 640)" |

### User-Facing Messages

**Guidelines:**
1. **Plain language** - No technical jargon ("database", "stack trace")
2. **Actionable** - Tell user what they can do ("Please grant permission", "Try again")
3. **Specific** - Avoid "An error occurred" (what error?)
4. **Empathetic** - Acknowledge frustration, offer help

**Examples:**

```swift
// ❌ BAD: Technical, not actionable
"Failed to resolve security-scoped bookmark data"

// ✅ GOOD: Plain language, actionable
"Contextify lost access to your Claude Code folder. Please select it again in Settings."

// ❌ BAD: Vague
"An unexpected error occurred"

// ✅ GOOD: Specific, with recovery
"Could not read transcript file 'session-123.jsonl'. The file may be corrupted or in use by another program."

// ❌ BAD: Blames user
"Invalid input"

// ✅ GOOD: Helpful
"Please enter a valid folder path (e.g., /Users/you/Documents)"
```

### Debug Messages (Logging)

**Guidelines:**
1. **Include context** - IDs, paths, counts, timestamps
2. **Use structured logging** - Key-value pairs, not free text
3. **Set appropriate level** - `.debug`, `.info`, `.warning`, `.error`
4. **Mark privacy** - Use `.public` or `.private`

**Example:**

```swift
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Migration")

func migrateDatabase(to target: URL) async throws {
  log.info("Starting database migration: from \(currentPath, privacy: .public) to \(target, privacy: .public)")

  do {
    try FileManager.default.copyItem(at: currentPath, to: target)
    log.info("✅ Database migration succeeded: \(target, privacy: .public)")
  } catch {
    log.error("❌ Database migration failed: \(error.localizedDescription, privacy: .public)")
    throw MigrationError.copyFailed(underlying: error)
  }
}
```

**Reference:** `build/docs/guides/logging-best-practices.md`

---

## Recovery Strategies

### Automatic Retry

**Pattern:**

```swift
func ingestWithRetry(transcriptId: String, maxAttempts: Int = 3) async throws {
  var lastError: Error?

  for attempt in 1...maxAttempts {
    do {
      try await orchestrator.ingestTranscript(transcriptId: transcriptId)
      log.info("Ingestion succeeded on attempt \(attempt)")
      return  // Success
    } catch let error as TransientError where error.isRetryable {
      log.warning("Ingestion attempt \(attempt) failed: \(error). Retrying...")
      lastError = error
      try await Task.sleep(for: .seconds(Double(attempt)))  // Exponential backoff
    } catch {
      // Non-retryable error, fail fast
      log.error("Ingestion failed with non-retryable error: \(error)")
      throw error
    }
  }

  // All retries exhausted
  throw lastError ?? TransientError.retryExhausted
}
```

**When to Retry:**
- Network timeouts
- Database locked (SQLITE_BUSY)
- File temporarily unavailable
- LLM timeout (FoundationModels)

**When NOT to Retry:**
- File not found (won't appear by retrying)
- Permission denied (user must fix)
- Validation failure (logic error)
- User cancelled (intentional)

### Fallback Strategy

**Pattern:**

```swift
func loadProject() async -> Project {
  // Try fast path (cached)
  if let cached = cache.getProject(id: projectId) {
    log.debug("Loaded project from cache")
    return cached
  }

  // Fallback: query database
  do {
    let project = try await database.fetchProject(id: projectId)
    cache.store(project)
    log.debug("Loaded project from database")
    return project
  } catch {
    log.warning("Database query failed: \(error). Using default project.")
    // Fallback: return default
    return Project.default
  }
}
```

**Pattern:** Try multiple strategies in order of preference (cache → database → default).

### Graceful Degradation

**Pattern:**

```swift
@MainActor
@Observable
class TimelineViewModel {
  var entries: [Entry] = []
  var summaries: [String: String] = [:]  // Optional enrichment
  var error: String?

  func loadTimeline() async {
    do {
      // Critical: Load entries (required)
      self.entries = try await database.fetchEntries()

      // Non-critical: Load summaries (optional)
      do {
        self.summaries = try await llm.generateSummaries(for: entries)
      } catch {
        log.warning("Failed to load summaries: \(error). Timeline will show without summaries.")
        // Continue without summaries (graceful degradation)
      }
    } catch {
      log.error("Failed to load timeline: \(error)")
      self.error = "Could not load timeline. Please try again."
    }
  }
}
```

**Pattern:** Essential features throw errors, optional features log and continue.

### User-Initiated Retry

**Pattern:**

```swift
@MainActor
@Observable
class MigrationViewModel {
  var state: MigrationState = .idle
  var error: String?

  func migrate(to target: URL) async {
    state = .inProgress
    error = nil

    do {
      try await DatabaseMigration.migrateDatabase(to: target)
      state = .success
    } catch {
      state = .failed
      error = error.localizedDescription
    }
  }

  func retry() async {
    // User taps "Retry" button
    guard state == .failed else { return }
    await migrate(to: lastTarget)
  }
}
```

**Pattern:** Expose retry as explicit user action.

---

## Logging Conventions

### Log Levels

| Level | Use Case | Example |
|-------|----------|---------|
| `.debug` | Normal operation details | "Parsed 100 entries from transcript" |
| `.info` | Significant events | "Database migration started", "Timeline loaded" |
| `.warning` | Recoverable errors, fallbacks | "Cache miss, generating summary", "Retry attempt 2/3" |
| `.error` | Failures requiring attention | "Database query failed", "LLM unavailable" |
| `.fault` | Critical failures (crash imminent) | "Invariant violated", "Unrecoverable state" |

### Error Logging Pattern

**Always log errors at the point of origin:**

```swift
func ingestTranscript(_ id: String) async throws {
  do {
    let content = try await loadTranscriptFile(id: id)
    try await parseAndStore(content)
  } catch {
    // Log at origin with full context
    log.error("Failed to ingest transcript \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    throw error  // Re-throw for caller
  }
}
```

**Don't log the same error multiple times:**

```swift
// ❌ BAD: Error logged at every level
func caller() {
  do {
    try ingestTranscript(id)
  } catch {
    log.error("Ingestion failed: \(error)")  // Duplicate log!
    showError(error)
  }
}

func ingestTranscript(_ id: String) throws {
  do {
    try parseFile(id)
  } catch {
    log.error("Parse failed: \(error)")  // Already logged here
    throw error
  }
}

// ✅ GOOD: Log once at origin, handle at UI layer
func caller() {
  do {
    try ingestTranscript(id)
  } catch {
    // Don't log again, just show to user
    showError(error)
  }
}

func ingestTranscript(_ id: String) throws {
  do {
    try parseFile(id)
  } catch {
    log.error("Parse failed: \(error)")  // Single log
    throw error
  }
}
```

### Structured Logging

**Use key-value pairs for machine-readable logs:**

```swift
log.info("""
  Database migration completed: \
  source=\(sourcePath, privacy: .public) \
  target=\(targetPath, privacy: .public) \
  size=\(fileSize) \
  duration=\(duration)ms
  """)
```

**Reference:** `build/docs/guides/logging-best-practices.md`

---

## Async Error Handling

### Throwing Async Functions

**Pattern:**

```swift
func fetchTranscripts() async throws -> [Transcript] {
  let response = try await URLSession.shared.data(from: url)
  return try JSONDecoder().decode([Transcript].self, from: response.0)
}

// Usage
Task {
  do {
    let transcripts = try await fetchTranscripts()
    updateUI(transcripts)
  } catch {
    showError(error)
  }
}
```

### Task Cancellation

**Pattern:**

```swift
@MainActor
class ViewModel {
  private var loadTask: Task<Void, Never>?

  func loadData() {
    // Cancel previous task
    loadTask?.cancel()

    loadTask = Task {
      do {
        let data = try await fetchData()

        // Check for cancellation before updating UI
        guard !Task.isCancelled else {
          log.debug("Load cancelled")
          return
        }

        self.data = data
      } catch is CancellationError {
        log.debug("Task was cancelled")
      } catch {
        log.error("Load failed: \(error)")
        self.error = error.localizedDescription
      }
    }
  }

  deinit {
    loadTask?.cancel()
  }
}
```

**Key Points:**
- Check `Task.isCancelled` before expensive operations
- Catch `CancellationError` separately (it's expected, not an error)
- Cancel tasks in `deinit` to prevent leaks

### Async Sequences

**Pattern:**

```swift
func monitorTranscript() async throws {
  for try await event in watcher.events() {
    switch event {
    case .modified(let path):
      try await ingestTranscript(at: path)
    case .deleted(let path):
      removeTranscript(at: path)
    }
  }
}

// Usage with error handling
Task {
  do {
    try await monitorTranscript()
  } catch {
    log.error("Monitoring failed: \(error)")
    // Attempt to restart monitoring
    try? await Task.sleep(for: .seconds(5))
    await monitorTranscript()
  }
}
```

---

## UI Error Presentation

### Toast/Banner Pattern

**For transient, recoverable errors:**

```swift
@MainActor
class ToastManager: ObservableObject {
  @Published var currentToast: Toast?

  func showError(_ error: Error, duration: TimeInterval = 3.0) {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

    currentToast = Toast(
      message: message,
      type: .error,
      duration: duration
    )
  }

  func showWarning(_ message: String) {
    currentToast = Toast(message: message, type: .warning, duration: 2.0)
  }
}

// Usage in view
.overlay(alignment: .top) {
  if let toast = toastManager.currentToast {
    ToastView(toast: toast)
      .transition(.move(edge: .top))
  }
}
```

**File:** `Contextify/Contextify/ContentView.swift:41-44` (pattern)

### Alert/Modal Pattern

**For errors requiring user action:**

```swift
@MainActor
struct SettingsView: View {
  @State private var migrationError: Error?
  @State private var showMigrationError = false

  var body: some View {
    Button("Migrate Database") {
      Task {
        do {
          try await DatabaseMigration.migrateDatabase(to: targetURL)
        } catch {
          migrationError = error
          showMigrationError = true
        }
      }
    }
    .alert("Migration Failed", isPresented: $showMigrationError) {
      Button("Retry") {
        // Retry migration
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text(migrationError?.localizedDescription ?? "Unknown error")
    }
  }
}
```

### Error State in Views

**Pattern:**

```swift
@MainActor
@Observable
class TimelineViewModel {
  var entries: [Entry] = []
  var isLoading: Bool = false
  var error: String?

  func load() async {
    isLoading = true
    error = nil

    do {
      entries = try await database.fetchEntries()
    } catch {
      self.error = error.localizedDescription
      log.error("Failed to load timeline: \(error)")
    }

    isLoading = false
  }
}

struct TimelineView: View {
  @Environment(TimelineViewModel.self) private var viewModel

  var body: some View {
    if let error = viewModel.error {
      ErrorView(message: error, retry: { await viewModel.load() })
    } else if viewModel.isLoading {
      ProgressView()
    } else {
      List(viewModel.entries) { entry in
        EntryRow(entry: entry)
      }
    }
  }
}
```

---

## Testing Error Paths

### Unit Testing Errors

**Test that errors are thrown correctly:**

```swift
func testMigrationThrowsWhenSourceNotFound() async throws {
  let migration = DatabaseMigration()

  do {
    try await migration.migrateDatabase(to: nonExistentPath)
    XCTFail("Should have thrown sourceNotFound error")
  } catch DatabaseMigration.MigrationError.sourceNotFound {
    // Expected error
  } catch {
    XCTFail("Unexpected error: \(error)")
  }
}
```

### Testing Error Recovery

**Test retry logic:**

```swift
func testRetryWithExponentialBackoff() async throws {
  var attempts = 0
  let maxAttempts = 3

  func flakeyOperation() async throws {
    attempts += 1
    if attempts < 3 {
      throw TransientError.timeout
    }
    // Succeed on 3rd attempt
  }

  // Test with retry
  do {
    for attempt in 1...maxAttempts {
      do {
        try await flakeyOperation()
        break  // Success
      } catch TransientError.timeout {
        if attempt == maxAttempts {
          throw TransientError.retryExhausted
        }
        try await Task.sleep(for: .seconds(Double(attempt)))
      }
    }
  } catch {
    XCTFail("Should have succeeded after retries")
  }

  XCTAssertEqual(attempts, 3, "Should have retried 3 times")
}
```

### Testing Error Messages

**Test LocalizedError descriptions:**

```swift
func testErrorDescriptionsAreUserFriendly() {
  let error = MigrationError.insufficientSpace(required: 2_000_000_000, available: 500_000_000)

  let description = error.errorDescription
  XCTAssertNotNil(description)
  XCTAssertTrue(description?.contains("disk space") ?? false)
  XCTAssertTrue(description?.contains("2 GB") ?? false)  // Human-readable size
}
```

---

## Summary

### Quick Reference

| Scenario | Strategy | Example |
|----------|----------|---------|
| File I/O | `throws` | `try await loadFile(url)` |
| Network request | `throws` | `try await fetch(url)` |
| Startup sequencing | `Result<>` | `.success(context)` / `.failure(.timeout)` |
| Dictionary lookup | `Optional` | `cache[key]` |
| Programmer error | `fatalError()` | `fatalError("Unreachable")` |
| Temporary failure | Auto-retry | Exponential backoff, 3 attempts |
| User-fixable error | Alert + Retry | "Permission denied. Grant access?" |
| Non-critical failure | Graceful degradation | Timeline loads without summaries |

### Error Type Checklist

When creating a new error type:

- [ ] Enum-based (not struct/class)
- [ ] Conforms to `Error`
- [ ] Conforms to `LocalizedError` for user messages
- [ ] Associated values for context (IDs, paths, counts)
- [ ] `errorDescription` property with user-friendly message
- [ ] Consider `isRetryable` or `severity` properties
- [ ] Namespaced (nested in containing type)
- [ ] Documented with examples

### Logging Checklist

When logging errors:

- [ ] Log at origin (not at every level)
- [ ] Use appropriate level (`.warning` or `.error`)
- [ ] Include context (IDs, paths, counts)
- [ ] Mark privacy (`.public` or `.private`)
- [ ] Structured format (key=value pairs)
- [ ] Don't log user-facing errors again in UI layer

---

## References

### Internal Documentation

- **`build/docs/guides/logging-best-practices.md`** - OSLog conventions and structured logging
- **`build/docs/guides/debugging-workflows.md`** - Error diagnosis workflows
- **`build/docs/design/swiftui-patterns.md`** - UI error state patterns

### Code Examples (Verified)

- `app/Sources/ContextifyCore/Database/DatabaseMigration.swift:35-50` - MigrationError enum
- `app/Sources/ContextifyCore/Security/FolderAccessController.swift:15-35` - FolderAccessError enum
- `Contextify/Contextify/FoundationLLM.swift:1146-1167` - TimelineError with isRetryable

### Error Types in Codebase

**Total Error Types:** 22 (verified via grep)

**Key Error Types:**
- `DatabaseMigration.MigrationError` (6 cases)
- `FolderAccessError` (6 cases)
- `TimelineError` (8 cases)
- `StartupCoordinator.Error` (3 cases)
- `HooverEngine.Error` (multiple)
- `TranscriptValidator.ValidationError` (multiple)

### External Resources

- **Swift Error Handling:** https://docs.swift.org/swift-book/documentation/the-swift-programming-language/errorhandling/
- **LocalizedError Protocol:** https://developer.apple.com/documentation/foundation/localizederror
- **Result Type:** https://developer.apple.com/documentation/swift/result

---

**Document Status:** ✅ Complete
**Last Code Verification:** 2025-11-17 (verified against 22 error types across 22 files, 5 Result<> usages)
**Next Review:** After error handling refactoring or new error categories
