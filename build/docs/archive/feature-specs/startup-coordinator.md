# Startup Coordinator Implementation Plan

**Project:** Contextify - Project Identity Pipeline Overhaul
**Date:** 2025-11-04
**Status:** Planning (No Code Changes)

---

## Executive Summary

This plan addresses critical race conditions and multiple sources of truth in Contextify's startup pipeline. The current architecture has three unsynchronized async pipelines managing project identity, leading to UI drift, unreliable unread counts, and monitoring instability.

**Core Solution:** Introduce a `StartupCoordinator` actor that provides a single source of truth (`ActiveProjectContext`) and enforces deterministic startup ordering.

---

## Issues Summary

### P0 (Merge Blockers)
1. **Multiple project authorities** - HUD path vs Switcher ID vs Monitor recomputation
2. **Non-deterministic startup** - Three racing pipelines (App init, ContentView, Window scene)
3. **Premature monitoring** - Timeline starts before observers react to project changes
4. **Switcher promotion gap** - Cannot activate projects not yet in DB

### P1 (Should Fix Soon)
5. NotificationCenter as implicit handshake (no ordering guarantees)
6. Monitor's start path is path-dependent with no retry
7. Cursor persistence depends on unstable ID

### P2 (Polish)
8. Deferred notifications increase unpredictability
9. Duplication suppression hides architectural issues

---

## Implementation Phases

### Phase 1: Foundation (New Components)
**Estimated Effort:** 4-6 hours
**Risk:** Low (additive only)

#### 1.1 Create `ActiveProjectContext` Model

**File:** `app/Sources/ContextifyCore/Models/ActiveProjectContext.swift` (NEW)

```swift
/// Single source of truth for active project identity
@frozen
public struct ActiveProjectContext: Sendable, Equatable {
    /// Stable database project ID (PRIMARY key)
    public let id: String

    /// Filesystem path (metadata, can change)
    public let path: String

    /// Display name (derived from path or user override)
    public let displayName: String

    /// Current git branch (if applicable)
    public let branch: String?

    /// Security-scoped bookmark data (sandboxed builds)
    public let bookmark: Data?

    /// Creation timestamp
    public let createdAt: Date

    public init(
        id: String,
        path: String,
        displayName: String,
        branch: String? = nil,
        bookmark: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.branch = branch
        self.bookmark = bookmark
        self.createdAt = createdAt
    }
}
```

**Validation:**
- [ ] Struct compiles with Sendable conformance
- [ ] Equatable works correctly for unit tests
- [ ] All properties immutable (let)

#### 1.2 Create `StartupCoordinator` Actor

**File:** `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift` (NEW)

**Responsibilities:**
1. Orchestrate HUD startup (path resolution, bookmark access)
2. Ensure project exists in DB via `TranscriptOrchestrator.getOrCreateProject`
3. Publish `ActiveProjectContext` via AsyncStream
4. Provide single-shot `ready()` method for initial context
5. Handle project switches with typed context updates

**API Surface:**

```swift
@MainActor
public final class StartupCoordinator: ObservableObject {
    public static let shared = StartupCoordinator()

    // Current context (nil until first resolution)
    @Published public private(set) var current: ActiveProjectContext?

    // Stream of context updates (for subscribers)
    public let updates: AsyncStream<ActiveProjectContext>
    private let continuation: AsyncStream<ActiveProjectContext>.Continuation

    // Dependencies (injected for testing)
    private let orchestrator: TranscriptOrchestrator
    private let hudPreferences: HUDPreferences

    private var isStarted = false

    public init(
        orchestrator: TranscriptOrchestrator = .shared,
        hudPreferences: HUDPreferences = .shared
    ) {
        self.orchestrator = orchestrator
        self.hudPreferences = hudPreferences

        var cont: AsyncStream<ActiveProjectContext>.Continuation!
        self.updates = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    /// Start coordinator (call once from app launch)
    public func start() async throws {
        guard !isStarted else { return }
        isStarted = true

        // Phase 1: Resolve project root
        let resolvedPath = try await resolveProjectRoot()

        // Phase 2: Ensure DB project exists
        let projectId = try await ensureProjectInDatabase(path: resolvedPath)

        // Phase 3: Resolve git branch
        let branch = await resolveGitBranch(path: resolvedPath)

        // Phase 4: Create context
        let context = ActiveProjectContext(
            id: projectId,
            path: resolvedPath,
            displayName: URL(fileURLWithPath: resolvedPath).lastPathComponent,
            branch: branch,
            bookmark: hudPreferences.projectRootBookmark
        )

        // Phase 5: Publish
        self.current = context
        continuation.yield(context)
    }

    /// Wait for initial context (blocking)
    public func ready() async throws -> ActiveProjectContext {
        if let current = current { return current }

        for await context in updates {
            return context
        }

        throw StartupError.contextNeverPublished
    }

    /// Switch to a new project (user action)
    public func switchProject(to path: String) async throws {
        let projectId = try await ensureProjectInDatabase(path: path)
        let branch = await resolveGitBranch(path: path)

        let context = ActiveProjectContext(
            id: projectId,
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            branch: branch
        )

        self.current = context
        continuation.yield(context)
    }

    // MARK: - Private Helpers

    private func resolveProjectRoot() async throws -> String {
        // Priority:
        // 1. CONTEXTIFY_PROJECT_ROOT env var
        // 2. Persisted bookmark/path
        // 3. CWD
        // 4. Error (no valid root)

        if let envRoot = ProcessInfo.processInfo.environment["CONTEXTIFY_PROJECT_ROOT"] {
            return envRoot
        }

        if let persistedPath = hudPreferences.projectRootPath {
            return persistedPath
        }

        let cwd = FileManager.default.currentDirectoryPath
        if cwd != "/" {
            return cwd
        }

        throw StartupError.noProjectRootAvailable
    }

    private func ensureProjectInDatabase(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent

        let project = try await orchestrator.getOrCreateProject(
            name: name,
            rootPath: path
        )

        return project.id
    }

    private func resolveGitBranch(path: String) async -> String? {
        // Use existing GitRepositoryResolver logic
        // Return branch name or nil if not a git repo
        return nil // TODO: integrate GitRepositoryResolver
    }
}

public enum StartupError: Error {
    case noProjectRootAvailable
    case contextNeverPublished
    case projectCreationFailed(String)
}
```

**Implementation Notes:**
- Use `@MainActor` to ensure all state mutations on main thread
- Make methods `async throws` for proper error propagation
- Use `AsyncStream` instead of NotificationCenter for typed coordination
- Inject dependencies for testability

**Validation:**
- [ ] Coordinator compiles with strict concurrency
- [ ] `ready()` blocks until context available
- [ ] `updates` stream works with multiple subscribers
- [ ] Error cases properly propagate

---

### Phase 2: Integration (Rewire Call Sites)

**Estimated Effort:** 6-8 hours
**Risk:** Medium (touches startup path)

#### 2.1 Update `ContextifyApp.swift`

**Current Issue:** Three parallel async tasks with no coordination

**Changes:**

```swift
// BEFORE (ContextifyApp.swift ~line 50-60)
WindowGroup {
    ContentView(model: model)
        .task {
            Task {
                await ProjectSwitcherState.shared.start()
            }
        }
}

// AFTER
WindowGroup {
    ContentView(model: model)
        .task {
            // PHASE 1: Start coordinator FIRST
            do {
                try await StartupCoordinator.shared.start()
            } catch {
                logger.error("Startup coordinator failed: \(error)")
                // Show error UI or fallback
            }

            // PHASE 2: Start dependent systems (now safe)
            await ProjectSwitcherState.shared.start()
            await initializeProjectsSystem()
        }
}
```

**Validation:**
- [ ] Coordinator starts before any other subsystem
- [ ] Error handling shows user-facing feedback
- [ ] No detached tasks remain in app init

#### 2.2 Update `ContentView.swift`

**Current Issue:** `waitForProjectRootReady()` returns early, premature monitoring

**Changes:**

```swift
// BEFORE (ContentView.swift ~line 100-120)
.task {
    await model.startup()
    await waitForProjectRootReady()
    TimelineIntegration.shared.startMonitoring()
}

// AFTER
.task {
    await model.startup()

    // Wait for coordinator to publish context
    do {
        let context = try await StartupCoordinator.shared.ready()

        // Start monitoring with stable project ID
        await TimelineIntegration.shared.startMonitoring(projectId: context.id)
    } catch {
        logger.error("Failed to get startup context: \(error)")
        model.showError("Could not initialize project monitoring")
    }
}

// DELETE: waitForProjectRootReady() method entirely
```

**Validation:**
- [ ] `waitForProjectRootReady()` removed from codebase
- [ ] Timeline starts with project ID, not path
- [ ] No toast/timeout machinery remains

#### 2.3 Update `ProjectSwitcherState.swift`

**Current Issue:** Doesn't create projects on root change, leaves `activeProjectId` stale

**Changes:**

```swift
// BEFORE (ProjectSwitcherState.swift ~line 150-170)
private func handleProjectRootChange(_ notification: Notification) {
    guard let projectURL = notification.object as? URL else { return }
    let projectPath = projectURL.path

    // Only refreshes, doesn't create
    Task {
        await refreshProjects()
        if let match = projects.first(where: { $0.rootPath == projectPath }) {
            activeProjectId = match.id
        }
    }
}

// AFTER
private var contextCancellable: Task<Void, Never>?

func start() async {
    // Subscribe to coordinator updates
    contextCancellable = Task { @MainActor in
        for await context in StartupCoordinator.shared.updates {
            await handleContextUpdate(context)
        }
    }

    // Get initial context
    if let context = StartupCoordinator.shared.current {
        await handleContextUpdate(context)
    }
}

@MainActor
private func handleContextUpdate(_ context: ActiveProjectContext) async {
    // Coordinator guarantees project exists in DB
    activeProjectId = context.id

    // Refresh project list to update UI
    await refreshProjects()
}

// DELETE: handleProjectRootChange (NotificationCenter observer)
```

**Validation:**
- [ ] Switcher always has valid `activeProjectId` after context update
- [ ] New projects appear immediately in switcher UI
- [ ] No lag between HUD path change and switcher activation

#### 2.4 Update `ConversationMonitor.swift`

**Current Issue:** Recomputes project ID, path-dependent, no retry on missing prerequisites

**Changes:**

```swift
// BEFORE (ConversationMonitor.swift ~line 200-250)
func startMonitoring() async {
    guard let projectRootURL = model.projectRootURL else {
        lastError = "No project root"
        return
    }

    let project = try? await orchestrator.getOrCreateProject(...)
    guard let project = project else { return }

    currentProjectId = project.id
    // ... start monitoring
}

// AFTER
func startMonitoring(projectId: String) async {
    // Accept project ID directly from coordinator
    currentProjectId = projectId

    // ... start monitoring with known ID
    await startMonitoringInternal()
}

@MainActor
private func handleContextUpdate(_ context: ActiveProjectContext) async {
    // Stop current monitoring
    await stopMonitoring()

    // Start with new context
    await startMonitoring(projectId: context.id)
}

// Initialize subscription in init or start
func subscribeToContextUpdates() {
    Task { @MainActor in
        for await context in StartupCoordinator.shared.updates {
            await handleContextUpdate(context)
        }
    }
}
```

**Validation:**
- [ ] Monitor never calls `getOrCreateProject` (coordinator owns this)
- [ ] Monitor starts immediately when given ID
- [ ] Switching projects cleanly stops/starts monitoring

---

### Phase 3: Remove Legacy Patterns

**Estimated Effort:** 2-3 hours
**Risk:** Low (cleanup)

#### 3.1 Remove `waitForProjectRootReady()`

**Files:**
- `Contextify/Contextify/ContentView.swift`

**Changes:**
- Delete entire method implementation
- Delete associated toast notifications
- Delete timeout logic

#### 3.2 Simplify NotificationCenter Usage

**Files:**
- `app/Sources/ContextifyCore/HUDCore.swift`

**Changes:**

```swift
// BEFORE (HUDCore.swift ~line 500)
private func postProjectRootDidChange() {
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        NotificationCenter.default.post(
            name: .projectRootDidChange,
            object: self.projectRootURL
        )
    }
}

// AFTER (keep for legacy UI, but simplify)
@MainActor
private func postProjectRootDidChange() {
    // Synchronous post (observers already installed by coordinator)
    NotificationCenter.default.post(
        name: .projectRootDidChange,
        object: self.projectRootURL
    )
}
```

**Note:** Keep `.projectRootDidChange` for legacy consumers (window title, etc), but startup path uses typed coordinator.

#### 3.3 Update HUD Path Changes to Notify Coordinator

**Files:**
- `app/Sources/ContextifyCore/HUDCore.swift`

**Changes:**

```swift
// In setProjectRoot or similar methods
@MainActor
func setProjectRoot(to url: URL) async {
    self.projectRootURL = url

    // Notify coordinator of user-initiated switch
    Task {
        try? await StartupCoordinator.shared.switchProject(to: url.path)
    }

    // Keep legacy notification for UI updates
    postProjectRootDidChange()
}
```

---

### Phase 4: Testing

**Estimated Effort:** 6-8 hours
**Risk:** Medium (requires comprehensive coverage)

#### 4.1 Unit Tests for `StartupCoordinator`

**File:** `Contextify/ContextifyTests/StartupCoordinatorTests.swift` (NEW)

**Test Cases:**

```swift
class StartupCoordinatorTests: XCTestCase {
    var coordinator: StartupCoordinator!
    var mockOrchestrator: MockTranscriptOrchestrator!
    var mockPreferences: MockHUDPreferences!

    override func setUp() {
        mockOrchestrator = MockTranscriptOrchestrator()
        mockPreferences = MockHUDPreferences()
        coordinator = StartupCoordinator(
            orchestrator: mockOrchestrator,
            hudPreferences: mockPreferences
        )
    }

    func testStartPublishesContext() async throws {
        // Given: persisted project path
        mockPreferences.projectRootPath = "/Users/test/project"
        mockOrchestrator.nextProjectId = "test-id-123"

        // When: start coordinator
        try await coordinator.start()

        // Then: context published
        let context = try await coordinator.ready()
        XCTAssertEqual(context.id, "test-id-123")
        XCTAssertEqual(context.path, "/Users/test/project")
    }

    func testReadyBlocksUntilContextAvailable() async throws {
        // Given: coordinator not started

        // When: call ready() in background
        let readyTask = Task {
            try await coordinator.ready()
        }

        // Then: should not complete immediately
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertFalse(readyTask.isCancelled)

        // When: start coordinator
        mockPreferences.projectRootPath = "/path"
        mockOrchestrator.nextProjectId = "id"
        try await coordinator.start()

        // Then: ready() completes
        let context = try await readyTask.value
        XCTAssertNotNil(context)
    }

    func testSwitchProjectUpdatesContext() async throws {
        // Given: initial context
        mockPreferences.projectRootPath = "/project1"
        mockOrchestrator.nextProjectId = "id1"
        try await coordinator.start()

        // When: switch to new project
        mockOrchestrator.nextProjectId = "id2"
        try await coordinator.switchProject(to: "/project2")

        // Then: context updated
        XCTAssertEqual(coordinator.current?.id, "id2")
        XCTAssertEqual(coordinator.current?.path, "/project2")
    }

    func testUpdatesStreamYieldsAllContexts() async throws {
        // Given: subscriber listening
        var contexts: [ActiveProjectContext] = []
        let subscription = Task {
            for await context in coordinator.updates {
                contexts.append(context)
                if contexts.count >= 2 { break }
            }
        }

        // When: start + switch
        mockPreferences.projectRootPath = "/p1"
        mockOrchestrator.nextProjectId = "id1"
        try await coordinator.start()

        mockOrchestrator.nextProjectId = "id2"
        try await coordinator.switchProject(to: "/p2")

        // Then: both contexts received
        try await subscription.value
        XCTAssertEqual(contexts.count, 2)
        XCTAssertEqual(contexts[0].id, "id1")
        XCTAssertEqual(contexts[1].id, "id2")
    }

    func testErrorWhenNoProjectRootAvailable() async {
        // Given: no persisted path, no env var, CWD is root
        mockPreferences.projectRootPath = nil

        // When/Then: start throws
        await assertThrowsError(try await coordinator.start()) { error in
            XCTAssertEqual(error as? StartupError, .noProjectRootAvailable)
        }
    }
}
```

#### 4.2 Integration Tests

**File:** `Contextify/ContextifyTests/StartupIntegrationTests.swift` (NEW)

**Test Cases:**

```swift
class StartupIntegrationTests: XCTestCase {
    func testFullStartupSequence() async throws {
        // Simulate full app launch sequence

        // Phase 1: Coordinator starts
        try await StartupCoordinator.shared.start()

        // Phase 2: Switcher starts
        await ProjectSwitcherState.shared.start()

        // Phase 3: Timeline starts
        let context = try await StartupCoordinator.shared.ready()
        // Mock timeline start...

        // Assert: no races, all IDs match
        XCTAssertEqual(ProjectSwitcherState.shared.activeProjectId, context.id)
    }

    func testBrandNewProjectActivation() async throws {
        // User selects a project not in DB

        // When: switch to new path
        try await StartupCoordinator.shared.switchProject(to: "/new/project")

        // Then: project appears in DB immediately
        let context = StartupCoordinator.shared.current!
        XCTAssertNotNil(context.id)

        // And: switcher reflects it
        await ProjectSwitcherState.shared.handleContextUpdate(context)
        XCTAssertEqual(ProjectSwitcherState.shared.activeProjectId, context.id)
    }

    func testRapidProjectSwitching() async throws {
        // Given: multiple quick switches

        for i in 1...5 {
            try await StartupCoordinator.shared.switchProject(to: "/project\(i)")
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Then: final context is correct, no crashes
        XCTAssertEqual(StartupCoordinator.shared.current?.path, "/project5")
    }
}
```

#### 4.3 Manual Testing Runbook

**Test Plan:** `build/notes/testing/startup-coordinator-runbook.md` (NEW)

```markdown
# Startup Coordinator Manual Testing Runbook

## Preconditions
- Clean database: `make clean-db`
- No persisted project root in UserDefaults
- Contextify not running

## Test Case 1: Cold Start with Persisted Bookmark

**Steps:**
1. Launch Contextify
2. Verify header shows project name immediately
3. Verify Switcher shows active project with correct name
4. Verify Timeline shows entries for that project
5. Check logs: coordinator should start before timeline

**Expected:**
- No "waiting for project root" toasts
- All UI elements show same project
- Logs show deterministic startup order

## Test Case 2: Brand New Project Selection

**Steps:**
1. Launch Contextify
2. Click "Set Project Root"
3. Select a folder NOT in database
4. Verify Switcher tabs update immediately
5. Verify Timeline switches to new project

**Expected:**
- Switcher shows new project as active
- No lag between selection and UI update
- Database contains new project entry

## Test Case 3: Rapid Project Switching

**Steps:**
1. Launch Contextify with project A
2. Switch to project B
3. Immediately switch to project C
4. Immediately switch back to A

**Expected:**
- No crashes or UI flicker
- Final state shows project A consistently
- No duplicate notifications in logs

## Test Case 4: Restart During Ingestion

**Steps:**
1. Start ingesting a large transcript
2. Force quit Contextify mid-ingestion
3. Relaunch
4. Verify cursor position restored
5. Verify project identity stable

**Expected:**
- Ingestion resumes from checkpoint
- Same project active as before quit
- No unread count drift

## Test Case 5: Multi-Window Stability (if applicable)

**Steps:**
1. Launch Contextify (window 1)
2. Open second window if supported
3. Switch project in window 1
4. Verify window 2 reflects change

**Expected:**
- Both windows show same active project
- Coordinator manages global state correctly
```

---

### Phase 5: Documentation

**Estimated Effort:** 2-3 hours
**Risk:** Low

#### 5.1 Architecture Documentation

**File:** `build/notes/technical-reference/startup-coordinator-architecture.md` (NEW)

**Contents:**
- Why we needed this (problem statement)
- How it works (data flow diagrams)
- Component responsibilities
- Extension points for future features
- Migration guide from old pattern

#### 5.2 Code Comments

**Files:**
- `StartupCoordinator.swift` - detailed header comment
- `ActiveProjectContext.swift` - property documentation
- Updated comments in `ContentView.swift`, `ProjectSwitcherState.swift`, `ConversationMonitor.swift`

#### 5.3 AGENTS.md Update

**File:** `AGENTS.md`

**Add Section:**

```markdown
## Startup Coordination (as of 2025-11)

**IMPORTANT:** All project identity flows through `StartupCoordinator.shared`.

**Do NOT:**
- Query `HUDViewModel.projectRootURL` to get project ID
- Call `TranscriptOrchestrator.getOrCreateProject` outside coordinator
- Use NotificationCenter for startup synchronization
- Implement custom "wait for ready" helpers

**Do:**
- Subscribe to `StartupCoordinator.shared.updates` for project changes
- Use `await StartupCoordinator.shared.ready()` to get initial context
- Pass `ActiveProjectContext.id` to downstream components
- Keep filesystem paths as metadata only

**Files:**
- Coordinator: `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`
- Context model: `app/Sources/ContextifyCore/Models/ActiveProjectContext.swift`
```

---

## Rollout Strategy

### Step 1: Branch and Setup (Day 1)

```bash
# Create feature branch
git checkout -b feat/startup-coordinator

# Verify build works
bash scripts/xc.sh build

# Create directory structure
mkdir -p app/Sources/ContextifyCore/Coordination
mkdir -p app/Sources/ContextifyCore/Models
```

### Step 2: Foundation (Day 1-2)

- Implement `ActiveProjectContext.swift`
- Implement `StartupCoordinator.swift`
- Add basic unit tests
- Verify compilation with no integration

**Merge Gate:**
- [ ] All tests pass
- [ ] No compiler warnings
- [ ] Coordinator can be instantiated in isolation

### Step 3: Integration (Day 2-3)

- Update `ContextifyApp.swift`
- Update `ContentView.swift`
- Update `ProjectSwitcherState.swift`
- Update `ConversationMonitor.swift`

**Merge Gate:**
- [ ] App launches successfully
- [ ] Manual test case 1 passes (cold start)
- [ ] No regressions in existing features

### Step 4: Cleanup (Day 3)

- Remove `waitForProjectRootReady()`
- Simplify notification posting
- Remove duplication suppression code

**Merge Gate:**
- [ ] All unit tests pass
- [ ] Integration tests pass
- [ ] Manual runbook complete

### Step 5: Documentation and Review (Day 4)

- Write architecture docs
- Update AGENTS.md
- Create PR with detailed summary
- Request review from team

**Merge Gate:**
- [ ] All tests passing in CI
- [ ] Manual testing complete
- [ ] Documentation reviewed
- [ ] No unresolved review comments

---

## Risk Mitigation

### Risk 1: Breaking Existing Workflows

**Mitigation:**
- Keep legacy NotificationCenter notifications initially
- Add feature flag: `USE_STARTUP_COORDINATOR` (default false in beta)
- Gradual rollout: enable for internal testing first

**Rollback Plan:**
- Feature flag can disable coordinator
- All old code paths remain intact during beta

### Risk 2: Unforeseen Race Conditions

**Mitigation:**
- Extensive logging in coordinator (debug builds)
- Add diagnostics endpoint: `GET /diagnostics/startup`
- Thread sanitizer enabled in CI

**Detection:**
- Unit tests with deliberate delays
- Stress test rapid project switching
- Monitor crash reports after release

### Risk 3: Performance Regression

**Mitigation:**
- Measure startup time before/after with Instruments
- Add telemetry for coordinator phases
- Target: <100ms overhead for coordinator initialization

**Acceptance Criteria:**
- Cold start: <2s from launch to timeline visible (no regression)
- Project switch: <500ms from click to UI update (no regression)

### Risk 4: Database Contention

**Mitigation:**
- Coordinator uses existing TranscriptOrchestrator (proven safe)
- No new DB writes added (just reordering existing)
- Test with large databases (>1000 projects)

---

## Merge Gate Checklist

**Block merge if ANY are unchecked:**

- [ ] `StartupCoordinator` emits `ActiveProjectContext` before any timeline/monitor starts
- [ ] `ProjectSwitcherState` sets `activeProjectId` from coordinator context (no HUD query)
- [ ] `ConversationMonitor` starts with `projectId` parameter (no path lookup)
- [ ] `waitForProjectRootReady()` deleted from codebase
- [ ] Manual selection of unknown project creates DB row immediately
- [ ] NotificationCenter posts synchronous on MainActor (or deprecated)
- [ ] All unit tests pass (min 90% coverage of new code)
- [ ] All integration tests pass
- [ ] Manual runbook completed successfully (all 5 test cases)
- [ ] No new compiler warnings
- [ ] Thread sanitizer clean (no data races)
- [ ] Documentation complete (architecture + AGENTS.md)
- [ ] PR description includes before/after flow diagrams
- [ ] At least 2 reviewers approved

---

## Timeline Estimate

**Total Effort:** 20-28 hours (2.5-3.5 developer days)

| Phase | Hours | Dependencies |
|-------|-------|--------------|
| Foundation | 4-6 | None |
| Integration | 6-8 | Foundation |
| Cleanup | 2-3 | Integration |
| Testing | 6-8 | Integration |
| Documentation | 2-3 | All |

**Critical Path:** Foundation → Integration → Testing

**Parallelizable:** Documentation can start during integration

---

## Success Metrics

**Immediate (Post-Merge):**
- Zero startup race crashes in first week
- <5% of beta users report project identity issues (down from ~20% currently)
- Startup time remains within 10% of baseline

**Medium-Term (1 month):**
- Unread count drift reports drop to zero
- Timeline monitoring stability >99.5% (currently ~95%)
- Zero "waiting for project root" timeout incidents

**Long-Term (3 months):**
- Foundation for multi-window support (if needed)
- Simplifies addition of project templates feature
- Reduces onboarding complexity for new contributors

---

## Open Questions

1. **TimelineIntegration.swift audit**: Need to verify "isActive" flag behavior
   - **Action:** Locate file and audit before Phase 2.3
   - **Owner:** TBD

2. **Backward compatibility**: Do we need to support pre-coordinator state migration?
   - **Decision:** No (per AGENTS.md - no backward compat)
   - **Status:** Closed

3. **Feature flag strategy**: How to gradually enable for users?
   - **Options:**
     a. Beta builds only initially
     b. Internal builds with flag, then flip for beta
     c. Immediate rollout (high confidence)
   - **Decision:** TBD (recommend option B)

4. **Git branch resolution**: Integrate existing `GitRepositoryResolver` or refactor?
   - **Action:** Use existing resolver, wrap in async context
   - **Status:** Documented in Phase 1.2

---

## References

**Source Documents:**
- Original technical briefing (this prompt)
- `build/notes/technical-reference/sql-backend-architecture.md`
- `build/notes/technical-reference/conversation-monitor-state-architecture.md`

**Related Code:**
- `app/Sources/ContextifyCore/HUDCore.swift` (HUDViewModel)
- `Contextify/Contextify/ProjectSwitcherState.swift`
- `Contextify/Contextify/ConversationMonitor.swift`
- `Contextify/Contextify/ContextifyApp.swift`
- `Contextify/Contextify/ContentView.swift`
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`

**Tools:**
- Xcode 16+ (macOS 26 SDK)
- Swift 6 (strict concurrency)
- XCTest for unit tests

---

## Next Steps

**Immediately:**
1. Review this plan with team
2. Confirm approach and timeline
3. Identify owner for TimelineIntegration.swift audit
4. Get approval to proceed

**Once Approved:**
1. Create feature branch
2. Start Phase 1 (Foundation)
3. Daily standup updates on progress
4. Post early draft PR for architecture review (after Phase 1)

---

**Plan Status:** DRAFT - Awaiting approval to proceed with implementation

**Last Updated:** 2025-11-04
