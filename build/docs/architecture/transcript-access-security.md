# Transcript Access Security Architecture

**Status:** Implemented (2025-11-12)
**Platforms:** macOS App Store (sandboxed) + DMG (unsandboxed)

---

## Problem Statement

Contextify ingests transcript files from external CLI tools:
- Claude Code: `~/.claude/projects/<hash>/*.jsonl`
- Codex CLI: `~/.codex/sessions/YYYY/MM/DD/*.jsonl`

In App Store (sandboxed) builds, these directories are outside the app's container. Accessing them requires:
1. User authorization via folder picker
2. Security-scoped bookmarks stored in app preferences
3. Active security scope when performing file I/O

**Without proper scoping:** File operations fail with `EPERM` ("Operation not permitted").

---

## Design Goals

1. **Separation of concerns:** Keep ContextifyCore sandbox-agnostic (no AppKit/sandbox types)
2. **Testability:** Core layer can be tested without App layer dependencies
3. **Type safety:** Avoid string-based provider IDs (use constants)
4. **Simplicity:** Synchronous API (permissions obtained upfront in onboarding)
5. **Performance:** No MainActor on I/O paths (runs on background threads)

---

## Architecture Overview

### Layer Separation

```
┌─────────────────────────────────────────────────────┐
│ App Layer (Contextify target)                       │
│ - Knows about FolderAccessController                │
│ - Knows about security-scoped bookmarks             │
│ - Implements SandboxTranscriptAccessProvider        │
└──────────────────┬──────────────────────────────────┘
                   │ injects TranscriptAccessProvider
                   ▼
┌─────────────────────────────────────────────────────┐
│ Core Layer (ContextifyCore framework)               │
│ - Defines TranscriptAccessProvider protocol         │
│ - TranscriptOrchestrator uses provider              │
│ - HooverEngine reads files (inside scope)           │
│ - No knowledge of sandbox or AppKit                 │
└─────────────────────────────────────────────────────┘
```

### Protocol Definition

**File:** `app/Sources/ContextifyCore/Projects/TranscriptAccessProvider.swift`

```swift
public protocol TranscriptAccessProvider: Sendable {
  func withAccess<T>(
    for provider: String,
    _ body: @Sendable (URL) throws -> T
  ) throws -> T
}
```

**Synchronous by design:**
- Onboarding obtains permissions upfront
- No async UI (folder picker) during file access
- Security scope just wraps the file I/O operation

---

## Implementation: DMG Builds

**Provider:** `PassthroughAccessProvider`

```swift
public struct PassthroughAccessProvider: TranscriptAccessProvider {
  public func withAccess<T>(
    for provider: String,
    _ body: @Sendable (URL) throws -> T
  ) throws -> T {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let root: URL
    switch provider {
    case TranscriptProviderID.claude:
      root = home.appendingPathComponent(".claude/projects")
    case TranscriptProviderID.codex:
      root = home.appendingPathComponent(".codex/sessions")
    default:
      root = home
    }
    return try body(root)
  }
}
```

**Behavior:**
- Direct filesystem access (no sandbox)
- No permission checks
- No security scope management
- Just resolves provider → root path and calls body

---

## Implementation: App Store Builds

**Provider:** `SandboxTranscriptAccessProvider`

**File:** `Contextify/Contextify/SandboxTranscriptAccessProvider.swift`

```swift
struct SandboxTranscriptAccessProvider: TranscriptAccessProvider {
  let claudeRoot: URL?
  let codexRoot: URL?

  init(claudeRoot: URL?, codexRoot: URL?) {
    self.claudeRoot = claudeRoot
    self.codexRoot = codexRoot

    // Start security-scoped access for both roots if available
    // This keeps access open for the lifetime of the provider
    if let claude = claudeRoot {
      _ = claude.startAccessingSecurityScopedResource()
    }
    if let codex = codexRoot {
      _ = codex.startAccessingSecurityScopedResource()
    }
  }

  func withAccess<T>(
    for provider: String,
    _ body: @Sendable (URL) throws -> T
  ) throws -> T {
    let root: URL
    switch provider {
    case TranscriptProviderID.claude:
      guard let url = claudeRoot else {
        throw FolderAccessError.securityScopeAccessDenied(...)
      }
      root = url
    case TranscriptProviderID.codex:
      guard let url = codexRoot else {
        throw FolderAccessError.securityScopeAccessDenied(...)
      }
      root = url
    default:
      assertionFailure("Unknown transcript provider")
      root = FileManager.default.homeDirectoryForCurrentUser
    }

    // Security scope already started in init, just return URL
    return try body(root)
  }
}
```

**Behavior:**
1. Built once during app init with security-scoped URLs from `FolderAccessController`
2. Starts security scope once in `init()` and keeps it active for provider lifetime
3. On `withAccess()`: returns the already-scoped URL directly (no per-call scope management)
4. Security scope remains active for the entire app session

**Design rationale:** Starting scope once at init simplifies the API and avoids per-call overhead. The provider is created during app startup and lives for the entire session, so scope lifetime matches app lifetime.

---

## Usage in TranscriptOrchestrator

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`

### Initialization

```swift
public final class TranscriptOrchestrator {
  private let accessProvider: TranscriptAccessProvider?

  public init(
    dbManager: DatabaseManager,
    accessProvider: TranscriptAccessProvider? = nil
  ) throws {
    self.accessProvider = accessProvider
    // ...
  }
}
```

### Discovery Wrapper

```swift
public func discoverTranscript(
  projectId: String,
  fileURL: URL,
  provider: String,
  ...
) throws {
  let needsScope = needsSecurityScope(provider: provider)

  if needsScope, let accessProvider {
    try accessProvider.withAccess(for: provider) { root in
      assert(fileURL.path.hasPrefix(root.path), "fileURL not under root")
      try self.doDiscoverTranscript(...)
    }
  } else {
    try self.doDiscoverTranscript(...)
  }
}
```

### Implementation

```swift
/// IMPORTANT: All file I/O on `fileURL` must complete synchronously.
/// Do not offload to background tasks that outlive this call.
private func doDiscoverTranscript(...) throws {
  // Get file attributes (inside scope)
  let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)

  // ... upsert transcript record

  // Hoover the file (inside scope)
  let sha256 = try hooverEngine.hooverTranscript(transcript, fileURL: fileURL, ...)

  // ... start watcher if needed
}
```

**All file I/O happens in `doDiscoverTranscript()`, which is called inside `withAccess()` for external providers.**

---

## TranscriptWatcher Re-ingestion

**File:** `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`

### Problem

TranscriptWatcher monitors transcript files for changes and triggers re-ingestion. It cannot directly call `hooverEngine` because that would bypass security scoping.

### Solution: Callback Pattern

```swift
public final class TranscriptWatcher {
  private var rehoover: ((String, URL, String, String?) throws -> Void)?

  public func setRehoover(_ callback: @escaping (String, URL, String, String?) throws -> Void) {
    self.rehoover = callback
  }
}
```

**In TranscriptOrchestrator (init):**

```swift
// Set re-hoover callback to route through discoverTranscriptInternal (synchronous)
watcher.setRehoover { [weak self] projectId, fileURL, provider, sessionId in
  try self?.discoverTranscriptInternal(
    projectId: projectId,
    fileURL: fileURL,
    provider: provider,
    providerSessionId: sessionId,
    startWatching: false,  // Already watching
    bypassScheduler: true
  )
}
```

**Effect:** All re-ingestion routes through `discoverTranscriptInternal()`, which applies security scoping via `accessProvider.withAccess()` for sandbox builds.

---

## App Initialization

**File:** `Contextify/Contextify/ContextifyApp.swift`

Provider creation happens in `buildAndConfigureAccessProvider()`:

```swift
@MainActor
private func buildAndConfigureAccessProvider() async -> TranscriptAccessProvider {
  // Return cached provider if already built
  if let existing = sharedAccessProvider {
    return existing
  }

  #if APPSTORE_BUILD
  let claudeAuth = await folderAccessController.authorization(for: .claude)
  let codexAuth  = await folderAccessController.authorization(for: .codex)

  var claudeURL: URL? = nil
  if let auth = claudeAuth, auth.status == .authorized {
    claudeURL = try? await folderAccessController.resolve(auth).url
  }

  var codexURL: URL? = nil
  if let auth = codexAuth, auth.status == .authorized {
    codexURL = try? await folderAccessController.resolve(auth).url
  }

  let provider = SandboxTranscriptAccessProvider(
    claudeRoot: claudeURL,
    codexRoot: codexURL
  )
  #else
  let provider = PassthroughAccessProvider()
  #endif

  await AppStateOrchestrator.shared.configureAccessProvider(provider)
  await ImageExtractor.shared.configure(accessProvider: provider)
  sharedAccessProvider = provider
  return provider
}
```

The provider is then used in `initializeProjectsSystem()`:

```swift
private func initializeProjectsSystem(existingProvider: TranscriptAccessProvider? = nil) async {
  // Reuse existing provider, or cached provider, or build new one
  let accessProvider: TranscriptAccessProvider
  if let existing = existingProvider {
    accessProvider = existing
  } else if let cached = sharedAccessProvider {
    accessProvider = cached
  } else {
    accessProvider = await buildAndConfigureAccessProvider()
  }

  // Initialize orchestrator with access provider
  let orchestrator = try TranscriptOrchestrator(
    dbManager: .shared,
    accessProvider: accessProvider
  )
  // ... configure other components
}
```

**Key points:**
- Provider is built once via `buildAndConfigureAccessProvider()` and cached in `sharedAccessProvider`
- `initializeProjectsSystem()` reuses the cached provider to avoid reconstruction
- Mid-session permission grants use separate `reconfigureAccessProvider()` method (see ContextifyApp.swift)

---

## Build Configuration

### APPSTORE_BUILD Flag

**Set via build script:** `scripts/xc.sh --dist=appstore`

**Effect:**
- Core uses flag to disable global discovery and FSEvents in sandbox
- App uses flag to choose `SandboxTranscriptAccessProvider` vs `PassthroughAccessProvider`

**In code:**
```swift
#if APPSTORE_BUILD
// Sandboxed behavior
#else
// DMG behavior
#endif
```

---

## Testing Strategy

### DMG Build (Regression Test)

```bash
bash scripts/xc.sh --dist=dmg Debug cleanrun
```

**Verify:**
- No permission prompts
- Discovery finds Claude + Codex projects
- Timeline populates
- FSEvents work
- Logs show: `[INIT] Created passthrough access provider (DMG build)`

### App Store Build (Security Scope Test)

```bash
bash scripts/xc.sh --dist=appstore Debug cleanrun
```

**Verify:**
- Onboarding shows permission step
- User grants Claude/Codex folder access
- Discovery succeeds
- Hoovering succeeds
- Logs show: `[INIT] Created sandbox access provider (claude: authorized, ...)`
- Logs show: `[HOOVER-FILE-SIZE] ...` (proves file access works)
- No "Operation not permitted" errors

### Partial Permissions Test

Grant only Claude permission, not Codex.

**Verify:**
- Claude transcripts hoovered successfully
- Codex transcripts skipped (no crash)
- Logs show: `(claude: authorized, codex: none)`

---

## Error Handling

### UI Paths (Explicit User Action)

**Example:** User clicks "Discover Projects" button

**Behavior:**
- `FolderAccessError.securityScopeAccessDenied` bubbles to `ProjectsViewModel`
- Shows error message to user: "Discovery failed: ..."
- User can retry after granting permissions

### Background Paths (Automatic)

**Example:** FSEvents detects file change (DMG only; disabled in sandbox)

**Behavior:**
- Catch `FolderAccessError` and log warning
- Continue processing other files
- No modal/alert (avoid spam)

---

## Common Pitfalls

### ❌ Storing URLs and Using Outside Scope

```swift
var savedURL: URL?
try accessProvider.withAccess(for: TranscriptProviderID.claude) { root in
  savedURL = root
}
// BAD: scope released, this will fail
let data = try Data(contentsOf: savedURL!)
```

**Fix:** Perform all file I/O inside `withAccess()` closure.

### ❌ Async Work After Scope Ends

```swift
try accessProvider.withAccess(for: TranscriptProviderID.claude) { root in
  Task {
    // BAD: This task outlives the scope
    let data = try Data(contentsOf: fileURL)
  }
}
```

**Fix:** All file I/O must complete synchronously before `withAccess()` returns.

### ❌ Using Raw Strings for Providers

```swift
try accessProvider.withAccess(for: "claude.code") { ... }  // Typo risk
```

**Fix:** Use `TranscriptProviderID.claude` constants.

---

## Future Enhancements

### Long-Lived FSEvents in Sandbox

**Current:** FSEvents disabled in App Store builds

**Possible approach:**
1. Start security scope once at app launch
2. Keep scope active for entire session
3. Re-enter scope on app resume/wake

**Trade-offs:**
- More complex lifetime management
- Resource held for entire session
- May conflict with user revoking permissions mid-session

### Remote Transcript Sources

Protocol is generic enough to support:
- S3/cloud storage (implement `RemoteAccessProvider`)
- SSH/SFTP (implement `RemoteAccessProvider`)
- Custom network protocols

Just need to implement `TranscriptAccessProvider` for the new source.

---

## References

- Security-scoped bookmarks: https://developer.apple.com/documentation/foundation/nsurl/1417051-startaccessingsecurityscopedreso
- App Sandbox: https://developer.apple.com/documentation/security/app_sandbox
- Related code:
  - `app/Sources/ContextifyCore/Projects/TranscriptAccessProvider.swift`
  - `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`
  - `Contextify/Contextify/SandboxTranscriptAccessProvider.swift`
