# StartupCoordinator Implementation Guide

**Status:** Active (2025-11-17)
**Related:** `build/docs/architecture/startup-coordinator.md`, `StartupCoordinator.swift`
**Purpose:** Deep implementation guide for AsyncStream patterns, threading, error handling, and testing

---

## ⚠️ Phase 3 Role Change (Nov 2025)

**StartupCoordinator is now a legacy compatibility shim.** For new development, use `AppStateOrchestrator`.

**Integration with AppStateOrchestrator:**
- Receives `handleExternalProjectSwitch(id:path:)` calls from AppStateOrchestrator
- Publishes `ActiveProjectContext` updates for legacy subscribers (ConversationMonitor)
- Will be refactored/removed in Phase 4

**See:** `build/docs/architecture/startup-coordinator.md` for Phase 4 migration guide

---

## Executive Summary

This document provides implementation-level details for **StartupCoordinator** that go beyond the architectural overview. Read this when:
- Debugging startup sequencing issues
- Adding new coordinator subscribers
- Understanding multicast AsyncStream semantics
- Writing tests for startup flows
- Investigating threading/performance issues

**Related Architecture Doc:** `build/docs/architecture/startup-coordinator.md` - Read that first for high-level design.

---

## AsyncStream Publish/Subscribe Pattern

### Multicast Semantics (Critical Design Decision)

**The Problem:**
A single `AsyncStream` property creates **unicast** semantics where multiple subscribers compete for elements. If ProjectSwitcherState and ConversationMonitor both iterate the same stream, only ONE will receive each update (whichever calls `next()` first).

**The Solution:**
`updates()` is a **method** that returns a fresh `AsyncStream` backed by its own `NotificationCenter` observer:

```swift
// StartupCoordinator.swift:120-137
nonisolated public func updates() -> AsyncStream<ActiveProjectContext> {
    AsyncStream { continuation in
        // Fresh NotificationCenter observer per stream
        nonisolated(unsafe) let token = NotificationCenter.default.addObserver(
            forName: .activeProjectContextDidChange,
            object: nil,
            queue: .main  // ← Guarantees main thread delivery
        ) { note in
            if let ctx = note.object as? ActiveProjectContext {
                continuation.yield(ctx)
            }
        }

        continuation.onTermination = { _ in
            NotificationCenter.default.removeObserver(token)
        }
    }
}
```

**How It Works:**
1. Each subscriber calls `updates()` → gets unique `AsyncStream`
2. Each stream has its own `NotificationCenter` observer
3. When `publishContext()` posts notification → all observers fire → all streams yield
4. Late subscribers miss updates that occurred before subscription

**Why NotificationCenter Under the Hood?**
- Multicast semantics are free (NotificationCenter handles fan-out)
- Main queue delivery ensures thread-safe access
- Automatic observer cleanup via `onTermination`
- Familiar debugging (can monitor notifications in Console.app)

**Trade-off:**
NotificationCenter uses type-erased `Any` objects, requiring runtime cast:
```swift
if let ctx = note.object as? ActiveProjectContext {
    continuation.yield(ctx)
}
```
This is safe because we control the notification posting site.

---

## Sequencing Guarantees

### Ordering: Main Queue Serialization

**Question:** What if multiple `switchProject()` calls happen concurrently?

**Answer:** They execute serially because `publishContext()` posts to `NotificationCenter.default` on main queue:

```swift
// StartupCoordinator.swift:669
NotificationCenter.default.post(name: .activeProjectContextDidChange, object: context)
```

**Guarantee:** Notifications are delivered in posting order to all observers on the **same queue**. Since all observers run on `.main` queue, they see updates in order.

### Deduplication: Signature-Based Filtering

**Question:** What if the same project is switched to twice in a row?

**Answer:** `publishContext()` deduplicates by `(id, path)` tuple:

```swift
// StartupCoordinator.swift:649-654
if let sig = lastSignature, sig.id == context.id, sig.path == context.path {
    log.debug("🔇 Skipping duplicate context publish for project: \(context.id)")
    return
}
lastSignature = (id: context.id, path: context.path)
```

**Why Both id AND path?**
- `id` detects same database project
- `path` detects filesystem moves/renames (same id, different path)

**Consequence:** Subscribers never receive duplicate contexts for the same (id, path) tuple.

### Discovery Snapshot Handling

**Question:** What if discovery finds a newer project during startup?

**Answer:** `handleDiscoverySnapshot()` (lines 155-194) switches to discovery winner **only if**:
1. Not in sandboxed build (`Sandbox.isSandboxed` check)
2. First discovery snapshot hasn't been handled yet (`hasHandledDiscoverySnapshot`)
3. Not using explicit env var override (`initialResolutionSource != .envVar`)
4. Discovered project is newer than current (`candidateActivity > currentActivity`)

**Ordering:**
```
1. start() resolves initial project → publishes context
2. Discovery posts .projectsDiscoverySnapshot notification
3. handleDiscoverySnapshot() evaluates switch criteria
4. IF criteria met: switchProject(to: candidatePath) → publishes new context
5. Sets hasHandledDiscoverySnapshot = true (idempotent)
```

**Edge Case:** If `start()` hasn't published context yet, discovery snapshot is handled when it arrives.

---

## Error Handling & Recovery

### Error Types

```swift
// StartupCoordinator.swift:15-20
public enum StartupError: Error, Equatable {
    case noProjectRootAvailable
    case contextNeverPublished
    case projectCreationFailed(String)
    case invalidProjectRoot(String)
}
```

### Graceful Failure Strategy

**Philosophy:** Startup failures should **never crash the app**. Instead, enter "no project" state and show welcome modal.

**Implementation:**

```swift
// StartupCoordinator.swift:226-244
do {
    resolvedPath = try await resolveProjectRoot()
} catch StartupError.noProjectRootAvailable {
    // Graceful fallback: no project configured yet
    log.info("ℹ️  No project configured - entering discovery mode")

    isStarted = true  // ← Prevent infinite loops

    // Post notification to trigger welcome modal
    NotificationCenter.default.post(name: .startupRequiresWelcomeModal, object: nil)

    log.notice("⏸️  StartupCoordinator ready (no project - awaiting discovery)")
    return  // ← Exit early, current remains nil
}
```

**Recovery Path:**
1. User sees welcome modal
2. Discovery finds projects OR user manually selects folder
3. UI calls `switchProject(to: path)`
4. Coordinator publishes first context → subscribers activate

### Database Failures

**Question:** What if `getOrCreateProject()` fails (disk full, permissions error)?

**Answer:** Same graceful failure pattern:

```swift
// StartupCoordinator.swift:251-256
do {
    projectId = try await ensureProjectInDatabase(path: resolvedPath)
} catch {
    log.error("❌ Failed to create project in database: \(error)")
    isStarted = true
    NotificationCenter.default.post(name: .startupRequiresWelcomeModal, object: nil)
    return
}
```

**User sees:** Welcome modal with option to change database location or select different project.

### Timeout Handling: `ready()` Method

**Problem:** If `start()` never publishes context (due to bug), `ready()` would block forever.

**Solution:** Timeout guard with task cancellation:

```swift
// StartupCoordinator.swift:315-334
return try await withThrowingTaskGroup(of: ActiveProjectContext.self) { group in
    // Task 1: Timeout guard (5 seconds)
    group.addTask {
        try await Task.sleep(for: .seconds(5))
        throw StartupError.contextNeverPublished
    }

    // Task 2: Wait for first context
    group.addTask {
        for await ctx in self.updates() {
            return ctx
        }
        throw StartupError.contextNeverPublished
    }

    // Return first result (either context or timeout error)
    let first = try await group.next()!
    group.cancelAll()  // ← Cancel loser task
    return first
}
```

**Behavior:**
- If context arrives within 5 seconds → returns context, cancels timeout
- If 5 seconds elapse → throws error, cancels stream iteration
- Either way, both tasks are cancelled

---

## Threading & Concurrency

### Public API: @MainActor Isolated

All public methods are `@MainActor` isolated:
```swift
@MainActor
@Observable
public final class StartupCoordinator { ... }
```

**Consequence:** Callers must be on main thread or `await` the call:
```swift
// From ContentView.swift
let context = try await StartupCoordinator.shared.ready()
```

### Database Operations: Off-Main Thread

**Why:** SQLite I/O can block for 20-50ms (see Performance section). Blocking main thread causes UI jank.

**Pattern:**

```swift
// StartupCoordinator.swift:526-560
private func ensureProjectInDatabase(path: String) async throws -> String {
    let result = await Task(priority: .userInitiated) { () -> Result<String, Error> in
        // ↑ NOT Task.detached - inherits cancellation from parent

        do {
            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
            let projectId = try orchestrator.getOrCreateProject(name: name, rootPath: path)
            return .success(projectId)
        } catch {
            return .failure(error)
        }
    }.value

    switch result {
    case .success(let projectId):
        return projectId
    case .failure(let error):
        throw StartupError.projectCreationFailed(error.localizedDescription)
    }
}
```

**Key Details:**
- `Task(priority: .userInitiated)` - NOT `Task.detached` → inherits cancellation
- `Result<String, Error>` instead of throws → allows early cancellation check
- `.value` suspends main actor until background work completes

### Git Resolution: Configurable Priority

**Why:** Git operations involve file I/O (`findGitRoot()`) and subprocess (`git rev-parse`). Can be slow on network filesystems.

**Pattern:**

```swift
// StartupCoordinator.swift:593-630
private func resolveGitBranch(path: String) async -> String? {
    let priority: TaskPriority = ContextifyConfig.shared.gitHighPriorityEnabled
        ? .userInitiated
        : .utility

    let result = await Task.detached(priority: priority) {
        // ↑ Task.detached - does NOT inherit cancellation
        // (We always want git resolution to complete or cache might be stale)

        guard let gitRoot = GitRepositoryResolver.findGitRoot(startingAt: url) else {
            return nil
        }

        let info = GitRepositoryResolver.computeGitInfo(
            environment: ProcessInfo.processInfo.environment,
            persistedPath: path,
            currentRoot: gitRoot,
            autoPersist: false
        )

        return info.branch
    }.value

    return result
}
```

**Configuration:**
- `ContextifyConfig.shared.gitHighPriorityEnabled = true` → `.userInitiated` (faster, higher power)
- `ContextifyConfig.shared.gitHighPriorityEnabled = false` → `.utility` (slower, lower power)

**Trade-off:** `.userInitiated` completes faster but may drain battery on laptops.

### Task Cancellation Semantics

**Critical Difference:**

| Pattern | Cancellation Inherited? | Use When |
|---------|------------------------|----------|
| `Task { ... }` | ✅ Yes | Cancellable work (database queries) |
| `Task.detached { ... }` | ❌ No | Must-complete work (git resolution) |

**Why NOT inherit cancellation for git?**
If user switches project mid-resolution, we still want the git info cached for next time. Cancelling leaves stale cache.

---

## Performance Characteristics

### Target Latencies (2019 Intel Mac)

From architecture doc and code logs:

| Operation | Target | Typical |
|-----------|--------|---------|
| Resolve project root | <10ms | 5ms (UserDefaults read) |
| Database getOrCreateProject | <50ms | 20-50ms (SQLite write+read) |
| Git branch detection | <50ms | 10-30ms (file I/O + subprocess) |
| Context creation + publish | <5ms | 2-3ms |
| **Total startup overhead** | **<100ms** | **40-80ms** |

### Performance Logging

Coordinator uses **UIOPT-** prefix for performance-critical logs:

```swift
// StartupCoordinator.swift:521-567
log.info("[UIOPT-COORD-DB-FUNC-START] ensureProjectInDatabase() called")
// ... 40ms of work ...
log.info("[UIOPT-COORD-DB-FUNC-DONE] ensureProjectInDatabase() complete in 42ms")
```

**Log Analysis:**
```bash
# Filter for performance logs
log stream --predicate 'subsystem == "dev.contextify" AND category == "StartupCoordinator"' \
  | grep "UIOPT"

# Measure total switchProject() time
log stream --predicate 'subsystem == "dev.contextify" AND category == "StartupCoordinator"' \
  | grep -E "UIOPT-COORD-(START|DONE)"
```

**Bottlenecks:**
1. Database operations (20-50ms) - largest contributor
2. Git resolution (10-30ms) - network filesystems can spike to 500ms+
3. Security-scoped bookmark creation (5-10ms) - sandboxed builds only

**Optimization Opportunities:**
- Cache git branch in memory (avoid subprocess on every switch)
- Batch database writes (single transaction for multiple projects)
- Skip git resolution if path hasn't changed

---

## Testing Strategy

### Unit Testing: Mock Dependencies

**Challenge:** `StartupCoordinator.shared` is a singleton using real database.

**Solution:** Test coordinator behavior in isolation by injecting mocks.

**Example: Test AsyncStream multicast**

```swift
func testMultipleSubscribersReceiveAllUpdates() async throws {
    let coordinator = StartupCoordinator.shared

    // Start two concurrent subscribers
    var contexts1: [ActiveProjectContext] = []
    var contexts2: [ActiveProjectContext] = []

    async let subscriber1: Void = {
        for await ctx in coordinator.updates() {
            contexts1.append(ctx)
            if contexts1.count >= 2 { break }
        }
    }()

    async let subscriber2: Void = {
        for await ctx in coordinator.updates() {
            contexts2.append(ctx)
            if contexts2.count >= 2 { break }
        }
    }()

    // Trigger two switches
    try await coordinator.switchProject(to: "/path/one")
    try await coordinator.switchProject(to: "/path/two")

    // Both subscribers should receive both contexts
    _ = try await (subscriber1, subscriber2)

    XCTAssertEqual(contexts1.count, 2)
    XCTAssertEqual(contexts2.count, 2)
    XCTAssertEqual(contexts1[0].path, "/path/one")
    XCTAssertEqual(contexts1[1].path, "/path/two")
    XCTAssertEqual(contexts2[0].path, "/path/one")
    XCTAssertEqual(contexts2[1].path, "/path/two")
}
```

### Integration Testing: Full Startup Flow

**Test Scenario:** App launch with no persisted state

```swift
func testFirstLaunchTriggersWelcomeModal() async throws {
    // Clean slate: remove persisted path
    UserDefaults.standard.removeObject(forKey: "dev.contextify.project_root")

    // Expect welcome modal notification
    let expectation = XCTNSNotificationExpectation(
        name: .startupRequiresWelcomeModal
    )

    // Start coordinator
    await StartupCoordinator.shared.start()

    // Should post welcome modal notification
    await fulfillment(of: [expectation], timeout: 1.0)

    // Current should be nil (no project selected)
    XCTAssertNil(StartupCoordinator.shared.current)
}
```

**Test Scenario:** Startup with persisted project

```swift
func testStartupWithPersistedProject() async throws {
    // Setup: persist a project path
    let testPath = "/tmp/test-project"
    try FileManager.default.createDirectory(atPath: testPath, withIntermediateDirectories: true)
    UserDefaults.standard.set(testPath, forKey: "dev.contextify.project_root")

    // Start coordinator
    await StartupCoordinator.shared.start()

    // Wait for context
    let context = try await StartupCoordinator.shared.ready()

    // Should resolve to persisted path
    XCTAssertEqual(context.path, testPath)
    XCTAssertNotNil(context.id)  // DB project created
}
```

### Testing Deduplication

**Test Scenario:** Duplicate `switchProject()` calls

```swift
func testDuplicateSwitchDoesNotPublish() async throws {
    var receivedContexts: [ActiveProjectContext] = []

    // Subscribe to updates
    let subscription = Task {
        for await ctx in StartupCoordinator.shared.updates() {
            receivedContexts.append(ctx)
        }
    }

    // Switch to project A
    try await StartupCoordinator.shared.switchProject(to: "/path/A")

    // Duplicate switch to project A
    try await StartupCoordinator.shared.switchProject(to: "/path/A")

    // Switch to project B
    try await StartupCoordinator.shared.switchProject(to: "/path/B")

    subscription.cancel()

    // Should receive A once, B once (not A twice)
    XCTAssertEqual(receivedContexts.count, 2)
    XCTAssertEqual(receivedContexts[0].path, "/path/A")
    XCTAssertEqual(receivedContexts[1].path, "/path/B")
}
```

### Testing Timeout

**Test Scenario:** `ready()` timeout when `start()` never called

```swift
func testReadyTimeoutWhenNoContextPublished() async throws {
    let freshCoordinator = StartupCoordinator()  // NOT shared singleton

    // Call ready() without calling start()
    do {
        _ = try await freshCoordinator.ready()
        XCTFail("Expected timeout error")
    } catch StartupError.contextNeverPublished {
        // Expected
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}
```

### Performance Testing

**Test Scenario:** Startup completes within latency budget

```swift
func testStartupLatency() async throws {
    // Clean start
    await StartupCoordinator.shared.start()

    // Measure switchProject() latency
    let start = Date()
    try await StartupCoordinator.shared.switchProject(to: "/path/to/project")
    let elapsed = Date().timeIntervalSince(start)

    // Should complete within 200ms (2x target for test tolerance)
    XCTAssertLessThan(elapsed, 0.2, "switchProject took \(elapsed * 1000)ms")
}
```

---

## Common Pitfalls

### Pitfall 1: Using Single Shared AsyncStream Property

**Anti-pattern:**
```swift
// DON'T DO THIS
class StartupCoordinator {
    public let updates = AsyncStream<ActiveProjectContext> { continuation in
        // Single stream shared by all callers
    }
}

// Subscriber 1
for await ctx in StartupCoordinator.shared.updates { ... }

// Subscriber 2
for await ctx in StartupCoordinator.shared.updates { ... }
// ☠️ Only ONE subscriber receives each update!
```

**Correct pattern:**
```swift
// DO THIS
class StartupCoordinator {
    public func updates() -> AsyncStream<ActiveProjectContext> {
        // Fresh stream per caller
    }
}
```

### Pitfall 2: Calling `start()` Multiple Times Concurrently

**Problem:** If `start()` is called from multiple places before `isStarted = true`, multiple database writes can race.

**Mitigation:** `start()` is idempotent via `isStarted` guard:

```swift
guard !isStarted else {
    log.warning("StartupCoordinator.start() called while already started (no-op)")
    return
}
```

**Best Practice:** Call `start()` exactly once from `ContextifyApp.init()`.

### Pitfall 3: Blocking Main Thread in Subscribers

**Anti-pattern:**
```swift
for await context in StartupCoordinator.shared.updates() {
    // ☠️ Blocking database query on main thread!
    let transcripts = try dbManager.fetchTranscripts(projectId: context.id)
    self.transcripts = transcripts
}
```

**Correct pattern:**
```swift
for await context in StartupCoordinator.shared.updates() {
    // Run query off main thread
    let transcripts = await Task.detached {
        try dbManager.fetchTranscripts(projectId: context.id)
    }.value

    // Update state on main thread
    self.transcripts = transcripts
}
```

### Pitfall 4: Using Path Instead of ID for Queries

**Anti-pattern:**
```swift
let context = try await StartupCoordinator.shared.ready()
// ☠️ Using path for database lookup
let transcripts = try db.fetchTranscripts(rootPath: context.path)
```

**Correct pattern:**
```swift
let context = try await StartupCoordinator.shared.ready()
// ✅ Using stable ID for database lookup
let transcripts = try db.fetchTranscripts(projectId: context.id)
```

**Why:** Filesystem paths can change (user moves folder), but database ID is stable.

---

## Debugging Workflows

### Scenario: Subscriber Not Receiving Updates

**Symptoms:**
- ConversationMonitor shows stale project after switch
- Timeline never loads

**Debug Steps:**

1. **Verify subscription active:**
   ```swift
   log.info("📢 Subscribing to coordinator updates...")
   for await context in StartupCoordinator.shared.updates() {
       log.info("📬 Received context: \(context.id)")
   }
   ```

2. **Check logs for duplicate suppression:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "StartupCoordinator"' \
     | grep "Skipping duplicate"
   ```

3. **Monitor NotificationCenter:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify"' \
     | grep "activeProjectContextDidChange"
   ```

4. **Verify subscriber is on main thread:**
   ```swift
   for await context in StartupCoordinator.shared.updates() {
       precondition(Thread.isMainThread)  // Should always pass
   }
   ```

### Scenario: Startup Hangs at `ready()`

**Symptoms:**
- App shows blank screen on launch
- Timeline never appears

**Debug Steps:**

1. **Check if `start()` was called:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "StartupCoordinator"' \
     | grep "StartupCoordinator starting"
   ```

2. **Check for early return (no project):**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "StartupCoordinator"' \
     | grep "No project configured"
   ```

3. **Check for database failure:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "StartupCoordinator"' \
     | grep "Failed to create project"
   ```

4. **Check timeout:**
   After 5 seconds, `ready()` should throw. If app still hangs, caller isn't handling error:
   ```swift
   do {
       let context = try await StartupCoordinator.shared.ready()
   } catch {
       log.error("ready() failed: \(error)")  // ← Add this!
   }
   ```

### Scenario: Performance Regression (Slow Startup)

**Symptoms:**
- App launch takes >500ms
- UI feels sluggish after project switch

**Debug Steps:**

1. **Profile with UIOPT logs:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "StartupCoordinator"' \
     --level debug \
     | grep "UIOPT"
   ```

2. **Identify bottleneck:**
   ```
   [UIOPT-COORD-DB-FUNC-START] ensureProjectInDatabase() called
   [UIOPT-COORD-DB-FUNC-DONE] ensureProjectInDatabase() complete in 450ms  ← SLOW!
   ```

3. **Check git latency:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify" AND category == "StartupCoordinator"' \
     | grep "UIOPT-COORD-GIT"
   ```

4. **Profile with Instruments:**
   - Record Time Profiler trace during startup
   - Filter to `StartupCoordinator` stack frames
   - Identify hot paths

---

## Extension Points

### Adding New Subscribers

**Pattern:**
```swift
@MainActor
class MyNewFeature {
    private var coordinatorSubscription: Task<Void, Never>?

    func start() {
        coordinatorSubscription = Task {
            for await context in StartupCoordinator.shared.updates() {
                await handleProjectChange(context)
            }
        }
    }

    func stop() {
        coordinatorSubscription?.cancel()
    }

    private func handleProjectChange(_ context: ActiveProjectContext) async {
        // Your logic here - runs on main thread
        log.info("Project changed to: \(context.displayName)")
    }
}
```

### Adding Context Fields

**Example:** Add `color: NSColor` to ActiveProjectContext for project-specific theming.

**Steps:**

1. **Update struct:**
   ```swift
   @frozen
   public struct ActiveProjectContext: Sendable, Equatable {
       public let id: String
       public let path: String
       public let displayName: String
       public let branch: String?
       public let bookmark: Data?
       public let color: NSColor  // ← New field
       public let createdAt: Date
   }
   ```

2. **Update creation sites:**
   ```swift
   let context = ActiveProjectContext(
       id: projectId,
       path: path,
       displayName: displayName,
       branch: branch,
       bookmark: bookmark,
       color: .systemBlue,  // ← Provide value
       createdAt: Date()
   )
   ```

3. **Update subscribers:**
   Existing subscribers won't break (struct is still `Equatable`), but they can now access `context.color`.

### Adding Lifecycle Hooks

**Use Case:** Run custom logic before/after context publish.

**Pattern:**

```swift
// In StartupCoordinator
private var willPublishHandlers: [(ActiveProjectContext) -> Void] = []
private var didPublishHandlers: [(ActiveProjectContext) -> Void] = []

public func onWillPublish(_ handler: @escaping (ActiveProjectContext) -> Void) {
    willPublishHandlers.append(handler)
}

public func onDidPublish(_ handler: @escaping (ActiveProjectContext) -> Void) {
    didPublishHandlers.append(handler)
}

private func publishContext(_ context: ActiveProjectContext) async {
    // Call hooks
    willPublishHandlers.forEach { $0(context) }

    // Existing publish logic
    self.current = context
    NotificationCenter.default.post(name: .activeProjectContextDidChange, object: context)

    // Call hooks
    didPublishHandlers.forEach { $0(context) }
}
```

**Usage:**
```swift
StartupCoordinator.shared.onDidPublish { context in
    Analytics.track(event: "project_switch", properties: ["id": context.id])
}
```

---

## Related Documentation

- **Architecture:** `build/docs/architecture/startup-coordinator.md`
- **Source:** `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`
- **ActiveProjectContext:** Defined in StartupCoordinator.swift (lines 189-198 in architecture doc)
- **Database Integration:** `build/docs/architecture/sql-backend.md`
- **Testing Guide:** `build/docs/testing/first-run-qa-guide.md`

---

## Changelog

**2025-11-17:**
- Initial implementation guide created
- Documents AsyncStream multicast pattern
- Threading model and task cancellation semantics
- Error handling and graceful failure strategy
- Performance characteristics and logging
- Testing patterns and debugging workflows
