# Startup Coordinator Architecture

**Status:** Implemented (2025-11-05)
**Version:** 1.0
**Related:** `implementation-plan.md`, `sql-backend-architecture.md`

---

## Executive Summary

The **Startup Coordinator** provides a single source of truth for project identity and deterministic startup sequencing across Contextify's subsystems (HUD, Project Switcher, Timeline Monitor).

**Key Benefits:**
- Eliminates race conditions from multiple async initialization pipelines
- Guarantees project exists in database before monitoring starts
- Provides stable project ID as primary identity (not filesystem path)
- Coordinates startup ordering: Coordinator → Switcher → Timeline
- Foundation for multi-window support and project templates

---

## Architecture Overview

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                   StartupCoordinator                         │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  Single Source of Truth: ActiveProjectContext         │ │
│  │  - id: String (stable DB primary key)                │ │
│  │  - path: String (filesystem location)                │ │
│  │  - displayName, branch, bookmark                     │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                              │
│  Published via AsyncStream<ActiveProjectContext>            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ├──→ ProjectSwitcherState (updates activeProjectId)
                              ├──→ ConversationMonitor (starts monitoring with projectId)
                              └──→ HUDViewModel (user-initiated switches)
```

### Data Flow

**App Launch Sequence:**

```
1. ContextifyApp.init()
   └─→ StartupCoordinator.shared.start()
       ├─→ Resolve project root (env var > bookmark > persisted path > CWD)
       ├─→ Ensure project in database (getOrCreateProject)
       ├─→ Resolve git branch (optional)
       ├─→ Create ActiveProjectContext
       └─→ Publish context via AsyncStream

2. ProjectSwitcherState.start() (after coordinator)
   └─→ Subscribe to coordinator.updates
       └─→ handleContextUpdate(context)
           ├─→ activeProjectId = context.id
           └─→ refreshProjects()

3. ContentView.task
   └─→ StartupCoordinator.shared.ready()  // Blocks until context available
       └─→ TimelineIntegration.startMonitoring(projectId: context.id)
```

**User-Initiated Project Switch:**

```
User action (e.g., "Set Project Root")
   └─→ HUDViewModel.setProjectRoot(url:)
       ├─→ Update local state (projectRootURL, branch)
       ├─→ StartupCoordinator.shared.switchProject(to: path)
       │   ├─→ Ensure project in database
       │   ├─→ Create new ActiveProjectContext
       │   └─→ Publish via AsyncStream
       └─→ Post .projectRootDidChange (legacy)

Coordinator publishes context
   ├─→ ProjectSwitcherState.handleContextUpdate(context)
   │   ├─→ activeProjectId = context.id
   │   └─→ refreshProjects()
   │
   └─→ ConversationMonitor.handleContextUpdate(context)
       ├─→ stopMonitoring()
       ├─→ clearEntries()
       └─→ startMonitoring(projectId: context.id)
```

---

## Key Design Decisions

### 1. Project ID as Primary Identity

**Before:**
- Multiple sources of truth: HUD path vs Switcher ID vs Monitor recomputation
- Path-dependent lookups created races (DB query may not reflect latest write)
- Filesystem paths are unstable (user can move/rename project)

**After:**
- Coordinator owns `getOrCreateProject()` database call
- Publishes stable `context.id` to all subscribers
- Filesystem path is metadata only
- All subsystems use ID for database queries

### 2. AsyncStream Instead of NotificationCenter

**Before:**
```swift
// Notification-based (timing-dependent, no ordering guarantees)
NotificationCenter.default.post(name: .projectRootDidChange, object: path)
```

**After:**
```swift
// Typed stream with guaranteed ordering
for await context in StartupCoordinator.shared.updates {
    await handleContextUpdate(context)
}
```

**Benefits:**
- Type-safe (compiler-enforced context structure)
- Sequential delivery (no duplicate/reordered events)
- Explicit dependencies (see who subscribes)
- No suppression logic needed (coordinator deduplicates)

### 3. Deterministic Startup Order

**Before:**
```swift
// Racing tasks - no ordering guarantee
Task { await model.startup() }
Task { ProjectSwitcherState.shared.start() }
Task { await initializeProjectsSystem() }
```

**After:**
```swift
// Sequential startup with explicit dependencies
Task {
    try await StartupCoordinator.shared.start()  // Phase 1: identity
    ProjectSwitcherState.shared.start()          // Phase 2: depends on identity
}

// ContentView.task waits for coordinator
let context = try await StartupCoordinator.shared.ready()
await timeline.startMonitoring(projectId: context.id)
```

### 4. Off-Main-Thread Database Operations

All database operations run on background threads:

```swift
private func ensureProjectInDatabase(path: String) async throws -> String {
    let result = await Task.detached(priority: .userInitiated) {
        let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
        return try orchestrator.getOrCreateProject(name: name, rootPath: path)
    }.value
    return result
}
```

**Why:**
- Avoids blocking main thread during startup
- Database I/O can be slow (especially on first launch)
- State updates still happen on MainActor

---

## API Reference

### ActiveProjectContext

```swift
@frozen
public struct ActiveProjectContext: Sendable, Equatable {
    public let id: String          // Stable DB primary key (never changes)
    public let path: String         // Filesystem location (can change)
    public let displayName: String  // UI display name
    public let branch: String?      // Git branch (nil if not a git repo)
    public let bookmark: Data?      // Security-scoped bookmark (sandboxed builds)
    public let createdAt: Date      // Context creation timestamp
}
```

**Key Properties:**
- `id` is the **primary identity** - use for all database queries
- `path` is **metadata** - do not use for lookups
- Immutable value type (thread-safe)

### StartupCoordinator

```swift
@MainActor
@Observable
public final class StartupCoordinator {
    static let shared: StartupCoordinator

    // Current context (observable)
    public private(set) var current: ActiveProjectContext?

    // Stream of context updates
    public let updates: AsyncStream<ActiveProjectContext>

    // Start coordinator (call once from app launch)
    public func start() async throws

    // Wait for initial context (blocking)
    public func ready() async throws -> ActiveProjectContext

    // Switch to new project (user action)
    public func switchProject(to path: String) async throws
}
```

**Usage Patterns:**

```swift
// Pattern 1: Start coordinator (app init)
try await StartupCoordinator.shared.start()

// Pattern 2: Block until ready (ContentView.task)
let context = try await StartupCoordinator.shared.ready()

// Pattern 3: Subscribe to updates (ProjectSwitcherState)
for await context in StartupCoordinator.shared.updates {
    await handleContextUpdate(context)
}

// Pattern 4: User-initiated switch (HUDViewModel)
try await StartupCoordinator.shared.switchProject(to: "/path/to/project")
```

---

## Migration Guide

### For New Components

**DO:**
```swift
// Subscribe to coordinator updates
Task {
    for await context in StartupCoordinator.shared.updates {
        self.activeProjectId = context.id
        await refreshData()
    }
}

// Use project ID from context
let context = try await StartupCoordinator.shared.ready()
await startWork(projectId: context.id)
```

**DON'T:**
```swift
// Query HUDViewModel for path (stale)
let path = HUDViewModel.shared.projectRootURL

// Call getOrCreateProject directly (coordinator owns this)
let projectId = try orchestrator.getOrCreateProject(...)

// Use NotificationCenter for startup (timing-dependent)
NotificationCenter.default.addObserver(forName: .projectRootDidChange ...)
```

### For Existing Code

**NotificationCenter observers are kept for backward compatibility:**
- `.projectRootDidChange` still fires (legacy consumers)
- New code should use coordinator AsyncStream
- Notifications will be deprecated in future version

**HUDViewModel still manages:**
- Git branch detection and watchers
- Security-scoped bookmarks
- Persisting paths to UserDefaults
- **But:** Coordinator calls `getOrCreateProject()` (not HUD)

---

## Extension Points

### Future Features Enabled by Coordinator

1. **Multi-Window Support**
   - Each window subscribes to same coordinator stream
   - All windows show same active project
   - Single switchProject() updates all windows

2. **Project Templates**
   ```swift
   extension StartupCoordinator {
       func createProjectFromTemplate(name: String, template: ProjectTemplate) async throws -> ActiveProjectContext
   }
   ```

3. **Recent Projects List**
   ```swift
   extension StartupCoordinator {
       var recentProjects: [ActiveProjectContext] { ... }
   }
   ```

4. **Project Bookmarks (Favorites)**
   ```swift
   extension StartupCoordinator {
       func addBookmark(_ context: ActiveProjectContext) async throws
       var bookmarkedProjects: [ActiveProjectContext] { ... }
   }
   ```

---

## Testing

### Unit Testing StartupCoordinator

```swift
func testStartPublishesContext() async throws {
    let coordinator = StartupCoordinator(/* inject mocks */)
    try await coordinator.start()

    let context = try await coordinator.ready()
    XCTAssertEqual(context.path, expectedPath)
}

func testSwitchProjectUpdatesContext() async throws {
    try await coordinator.start()
    try await coordinator.switchProject(to: "/new/project")

    XCTAssertEqual(coordinator.current?.path, "/new/project")
}
```

### Integration Testing

```swift
func testFullStartupSequence() async throws {
    // 1. Start coordinator
    try await StartupCoordinator.shared.start()

    // 2. Verify switcher receives context
    XCTAssertNotNil(ProjectSwitcherState.shared.activeProjectId)

    // 3. Verify timeline starts
    let context = try await StartupCoordinator.shared.ready()
    // ... assert timeline monitoring active
}
```

---

## Troubleshooting

### Common Issues

**Issue:** "No project root available" error on startup
**Cause:** No persisted path, no env var, CWD is root
**Fix:** Set `CONTEXTIFY_PROJECT_ROOT` env var or select project in UI

**Issue:** Switcher shows stale project after switch
**Cause:** Switcher not subscribed to coordinator updates
**Fix:** Ensure `subscribeToContextUpdates()` called in `start()`

**Issue:** Timeline starts before project selected
**Cause:** `ready()` called before `start()` completes
**Fix:** Ensure coordinator started in `ContextifyApp.init()` before ContentView.task

**Issue:** Database queries fail with "project not found"
**Cause:** Using path instead of ID for lookups
**Fix:** Use `context.id` for all database queries

---

## Performance Considerations

### Startup Time

**Target:** <100ms coordinator overhead (measured on Intel Mac, 2019)

**Breakdown:**
- Resolve project root: <10ms (UserDefaults read)
- Database getOrCreateProject: 20-50ms (SQLite write + read)
- Git branch detection: 10-30ms (file I/O + git subprocess)
- Context creation + publish: <5ms

**Optimization:**
- Database operations run on background thread
- Git detection parallelizable with other startup tasks
- Context caching prevents redundant work on re-entry

### Memory Usage

- `ActiveProjectContext`: ~200 bytes (small value type)
- `AsyncStream` continuation: ~80 bytes
- Total coordinator overhead: <1 KB

---

## Related Documentation

- **Original design spec:** `build/docs/archive/feature-specs/startup-coordinator.md`
- **SQL Backend:** `build/docs/architecture/sql-backend.md`
- **State Management:** `build/docs/architecture/conversation-monitor-state.md`
- **ProjectSwitcher integration:** `build/docs/architecture/project-switcher.md`
- **Implementation:** `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`

---

## Changelog

**v1.0 (2025-11-05):**
- Initial implementation
- Replaces notification-based startup with typed AsyncStream
- Coordinator owns `getOrCreateProject()` database call
- Project ID as stable primary identity
