# Welcome Modal & First Launch Experience

**Status:** Required (Regression from StartupCoordinator refactor)
**Priority:** High
**Affects:** First-time users, clean database scenarios, post-refactor UX
**Created:** 2025-11-05

---

## Executive Summary

The StartupCoordinator refactor introduced a **critical UX regression** for first-launch scenarios where no project is configured. The coordinator now throws a fatal error when no project root is found, preventing the app from starting and displaying cryptic error messages to users. Meanwhile, project discovery runs silently in the background with no UI feedback, eventually populating project tabs but leaving no project selected.

**The problem:** Discovery and coordinator are decoupled - discovery finds projects, but coordinator has already failed before it can use them.

**The solution:** Implement a Welcome Modal with live discovery progress, graceful "no project" state handling in the coordinator, and automatic project selection after discovery completes.

---

## Problem Statement

### What Happens Now (Broken Flow)

**Scenario:** User launches Contextify for the first time (or with clean database)

1. **App Launch** (`ContextifyApp.init()`)
   - Calls `StartupCoordinator.shared.start()`

2. **Coordinator Resolution** (`StartupCoordinator.resolveProjectRoot()`)
   - Checks environment variable → ❌ Not set (users don't have this)
   - Checks bookmark → ❌ None (first launch)
   - Checks persisted path → ❌ None (clean database)
   - Checks CWD → ❌ Not a valid project (CWD is `/` or system directory)
   - **THROWS:** `StartupError.noProjectRootAvailable`

3. **Error Handling** (`ContextifyApp.init()` line 196)
   ```swift
   } catch {
       startupLog.error("❌ StartupCoordinator failed: \(error.localizedDescription)")
       // Continue anyway - ProjectSwitcherState will handle missing context gracefully
   }
   ```
   - Error logged but swallowed
   - User sees **toast notification**: "StartupCoordinator failed: The operation couldn't be completed. (ContextifyCore.StartupError error 2.)"
   - Toast disappears after 3 seconds
   - **No recovery UI shown**

4. **Discovery Runs Independently** (`ContextifyApp.initializeProjectsSystem()` line 307)
   - Discovery runs in `.task` block attached to main window
   - Scans `~/.claude/projects/*` for Claude Code projects
   - Parses JSONL files to extract project paths
   - Hovers transcripts into database
   - **NO UI FEEDBACK** - user sees nothing
   - Takes 5-30 seconds depending on project count

5. **Projects Appear** (after discovery completes)
   - Project tabs populate in switcher bar
   - **But no project is selected** (coordinator already failed)
   - User sees empty timeline with project tabs above
   - Must manually click a project tab

**Result:** Confusing, broken UX with no guidance

### Why This Is a Regression

**Before StartupCoordinator refactor:**
- App could launch without a configured project
- UI showed "Set Project Root" button
- Discovery populated projects
- User could select one or manually add a folder

**After StartupCoordinator refactor:**
- Coordinator **requires** a project to start
- Treats "no project" as fatal error
- Discovery happens but can't feed back to coordinator
- No UI for recovery

---

## Root Cause Analysis

### Architectural Mismatch

**Coordinator Philosophy:** Deterministic resolution from explicit sources
- Environment variable (dev override)
- Security-scoped bookmark (user-granted access)
- Persisted path (user-selected folder)
- Current working directory (runtime context)

**Discovery Philosophy:** Smart selection from automatic scanning
- Scan default locations (`~/.claude/projects/*`)
- Extract project paths from JSONL metadata
- Build database of available projects
- Present options to user

**The conflict:** Coordinator needs a project **before** anything starts. Discovery **finds** projects after app starts. These are fundamentally incompatible flows.

### Why Discovery Can't Run First

Discovery requires:
1. Database initialized (`DatabaseManager.shared`)
2. TranscriptOrchestrator available
3. Background tasks spawned (requires app lifecycle started)
4. File I/O operations (slow, must be async)

Coordinator runs:
1. Synchronously during app init
2. Before main window appears
3. Before task blocks execute
4. With expectation of immediate result

**Timing:** Coordinator finishes at T+0.1s. Discovery finishes at T+5-30s.

### State Isolation Problem

`ProjectsViewModel` owns discovery state:
```swift
@Observable
final class ProjectsViewModel {
    private(set) var isDiscovering = false
    private(set) var isIngesting = false
    private(set) var discoveryProgress: DiscoveryProgress?
    // ...
}
```

But `ContentView` doesn't have access:
```swift
struct ContentView: View {
    @Environment(HUDViewModel.self) private var model
    @Environment(ConversationMonitor.self) private var timeline
    @Environment(ProjectSwitcherState.self) private var projectSwitcher
    // ❌ No ProjectsViewModel!
}
```

`ProjectsViewModel` is only passed to the Projects window (`Window("Projects", id: "projects")`), not the main window.

**Result:** Discovery state exists but is invisible to main UI.

### No Feedback Loop

Discovery completes but has no way to notify coordinator:

```swift
// ContextifyApp.initializeProjectsSystem() - line 330
await vm.discoverProjects()
log.info("✅ Auto-discovery complete")

// Post notification for coordination
NotificationCenter.default.post(
    name: .projectsDiscoveryComplete,
    object: vm.projects
)
```

**But:** Nothing subscribes to `.projectsDiscoveryComplete`. Coordinator doesn't listen. No auto-selection happens.

---

## Design Goals

### User Experience Goals

1. **No Cryptic Errors**
   - Never show "StartupError error 2" to users
   - Provide clear, actionable messaging
   - Guide user through setup process

2. **Visible Progress**
   - Show when discovery is happening
   - Live updates: "Found 5 Claude Code projects"
   - Progress indicator during ingestion
   - Clear completion state

3. **Automatic Selection**
   - After discovery, auto-select most recent project
   - Deterministic: use `projects.last_viewed_ts` from database
   - Graceful degradation if no projects found

4. **Dismissible But Persistent**
   - User can dismiss modal and see main window
   - Main window shows loading state while discovery runs
   - Modal can be re-opened if user wants details

5. **Fast Path for Returning Users**
   - If coordinator resolves project successfully, skip modal entirely
   - Modal only shows on first launch or clean database
   - Subsequent launches instant

### Technical Goals

1. **Coordinator Tolerance**
   - Coordinator must **not fail** on missing project
   - Enter "no project selected" state gracefully
   - Remain responsive to future `switchProject()` calls

2. **State Unification**
   - Main window must access discovery state
   - Single source of truth for "is discovery running?"
   - Observable state flows to UI via SwiftUI environment

3. **Feedback Loop**
   - Discovery completion triggers coordinator update
   - Auto-selection implemented as `switchProject()` call
   - Coordinator publishes context, timeline starts monitoring

4. **Performance**
   - Discovery runs on background threads (already true)
   - UI remains responsive during ingestion
   - Progress updates throttled (max 1/sec)

---

## Solution Architecture

### Phase 1: Coordinator Graceful Failure

**File:** `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`

**Change:** Don't throw on missing project root

```swift
public func start() async throws {
    guard !isStarted else { return }

    log.info("🚀 StartupCoordinator starting...")

    // Phase 1: Resolve project root
    do {
        let resolvedPath = try await resolveProjectRoot()
        log.info("📁 Resolved project root: \(resolvedPath, privacy: .public)")

        // Continue with existing flow (phases 2-6)
        // ...

    } catch StartupError.noProjectRootAvailable {
        // NEW: Don't fail - enter "no project" mode
        log.info("ℹ️ No project root configured - entering discovery mode")
        self.current = nil  // Observable property - UI sees this
        isStarted = true

        // Post notification for UI to show welcome modal
        NotificationCenter.default.post(name: .startupRequiresWelcomeModal, object: nil)

        return  // Exit early without context
    }
}
```

**Impact:**
- `StartupCoordinator.shared.current` remains `nil` on first launch
- No fatal error thrown
- App can continue starting
- UI notified to show welcome modal

### Phase 2: Discovery State in Main Window

**File:** `Contextify/Contextify/ContextifyApp.swift`

**Change:** Initialize `ProjectsViewModel` early and pass to main window

```swift
@main
struct ContextifyApp: App {
    @State private var projectsViewModel: ProjectsViewModel?
    @State private var showWelcomeModal = false

    init() {
        // ... existing startup code ...

        // NEW: Initialize projects view model EARLY (before windows)
        Task { @MainActor in
            do {
                let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
                let discoveryService = ProjectDiscoveryService(
                    db: try DatabaseManager.shared.pool,
                    orchestrator: orchestrator
                )
                let vm = ProjectsViewModel(
                    discoveryService: discoveryService,
                    hudModel: HUDViewModel.shared
                )
                self.projectsViewModel = vm
            } catch {
                startupLog.error("Failed to init ProjectsViewModel: \(error)")
            }
        }
    }

    var body: some Scene {
        Window("Contextify", id: "main") {
            if let vm = projectsViewModel {
                ContentView()
                    .environment(model)
                    .environment(timeline)
                    .environment(vm)  // NEW: Pass to main window
                    .sheet(isPresented: $showWelcomeModal) {
                        WelcomeModalView()
                            .environment(vm)
                    }
            } else {
                // Transient state during early init
                ProgressView("Initializing...")
            }
        }
    }
}
```

**Impact:**
- Main window now has access to discovery state
- Can observe `vm.isDiscovering`, `vm.discoveryProgress`, etc.
- Both main window and Projects window share same VM instance

### Phase 3: Welcome Modal UI

**File:** `Contextify/Contextify/WelcomeModalView.swift` (new)

```swift
import SwiftUI

struct WelcomeModalView: View {
    @Environment(ProjectsViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Welcome to Contextify")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Scanning for Claude Code and Codex projects...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Discovery Progress
            if vm.isDiscovering {
                VStack(spacing: 12) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Discovering projects...")
                            .foregroundStyle(.secondary)
                    }

                    if !vm.projects.isEmpty {
                        Text("Found \(vm.projects.count) projects")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            // Ingestion Progress
            if vm.isIngesting, let progress = vm.discoveryProgress {
                VStack(spacing: 12) {
                    HStack {
                        ProgressView(value: Double(progress.projectsCompleted),
                                   total: Double(progress.projectsTotal))
                        Text("\(progress.projectsCompleted)/\(progress.projectsTotal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let currentProject = progress.currentProject {
                        Text("Ingesting: \(currentProject)")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            // Completion State
            if !vm.isDiscovering && !vm.isIngesting {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)

                    Text("Discovery Complete")
                        .font(.headline)

                    if !vm.projects.isEmpty {
                        Text("Found \(vm.projects.count) projects")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No projects found")
                            .foregroundStyle(.orange)
                        Text("You can add a project manually using File → Open Project")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Actions
            HStack {
                if !vm.isDiscovering && !vm.isIngesting {
                    Button("Get Started") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Dismiss") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(32)
        .frame(width: 480, height: 360)
    }
}
```

**Features:**
- Live progress updates during discovery
- Shows project count as it finds them
- Ingestion progress bar with current project name
- Dismissible - user can see main window while it runs
- "Get Started" button on completion

### Phase 4: Auto-Selection After Discovery

**File:** `Contextify/Contextify/ContextifyApp.swift`

**Add:** Auto-selection logic after discovery completes

```swift
private func initializeProjectsSystem() async {
    // ... existing discovery code ...

    await vm.discoverProjects()
    log.info("✅ Auto-discovery complete")

    // NEW: Auto-select most recent project if coordinator has no current
    if StartupCoordinator.shared.current == nil, !vm.projects.isEmpty {
        log.info("🎯 Auto-selecting most recent project after discovery")

        // Get most recent project (already sorted by display_order/last_activity)
        let mostRecent = vm.projects.first!

        do {
            try await StartupCoordinator.shared.switchProject(to: mostRecent.path.path)
            log.notice("✅ Auto-selected project: \(mostRecent.name)")
        } catch {
            log.error("Failed to auto-select project: \(error)")
        }
    }

    // Close welcome modal if it's showing
    await MainActor.run {
        self.showWelcomeModal = false
    }
}
```

**Logic:**
1. Check if coordinator has no current project
2. If discovery found projects, select first one (most recent by `last_viewed_ts`)
3. Call `coordinator.switchProject()` to establish context
4. Timeline monitoring will auto-start via coordinator subscription
5. Close welcome modal

### Phase 5: Loading Overlay for Main Window

**File:** `Contextify/Contextify/ContentView.swift`

**Add:** Loading overlay when discovery is running but modal dismissed

```swift
struct ContentView: View {
    @Environment(ProjectsViewModel.self) private var projectsVM

    var body: some View {
        ZStack {
            // Existing content
            VStack(spacing: 0) {
                // ... existing UI ...
            }

            // Loading overlay (when discovery running with no current project)
            if StartupCoordinator.shared.current == nil &&
               (projectsVM.isDiscovering || projectsVM.isIngesting) {
                discoveryLoadingOverlay
            }
        }
    }

    private var discoveryLoadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Discovering projects...")
                .font(.headline)

            if let progress = projectsVM.discoveryProgress {
                Text("\(progress.projectsCompleted) of \(progress.projectsTotal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
```

**Behavior:**
- If user dismisses modal while discovery running, main window shows loading overlay
- Overlay disappears when discovery completes and project auto-selected
- Prevents confusion of "why is the window empty?"

---

## Implementation Details

### Database Query for Most Recent Project

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`

**Add:** Method to get most recently viewed project

```swift
public func getMostRecentProject() throws -> Project? {
    try dbManager.pool.read { db in
        try Project
            .filter(Column("last_viewed_ts") != nil)
            .order(Column("last_viewed_ts").desc)
            .limit(1)
            .fetchOne(db)
    }
}
```

**Fallback:** If no `last_viewed_ts` set (all NULL), use project with most recent entry:

```swift
public func getProjectWithMostRecentActivity() throws -> Project? {
    try dbManager.pool.read { db in
        try Project
            .joining(required: Project.entries)
            .order(Column("entries.created_ts").desc)
            .limit(1)
            .fetchOne(db)
    }
}
```

### Notification Names

**File:** `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`

**Add:** Notification for welcome modal trigger

```swift
extension Notification.Name {
    /// Posted when startup requires welcome modal (no project configured).
    static let startupRequiresWelcomeModal = Notification.Name("dev.contextify.startupRequiresWelcomeModal")
}
```

### Discovery Progress Model

**Already exists** in `ProjectsViewModel`:

```swift
struct DiscoveryProgress {
    let phase: DiscoveryPhase
    let currentProject: String?
    let projectsCompleted: Int
    let projectsTotal: Int
    let message: String
}

enum DiscoveryPhase {
    case discovering
    case ingesting
    case complete
}
```

**Usage:** Progress handler in `discoverAllProjects()` already calls callback with updates.

---

## Edge Cases & Error Handling

### No Projects Found

**Scenario:** Discovery runs but finds no Claude Code or Codex projects.

**Handling:**
1. Welcome modal shows: "No projects found"
2. Guidance text: "You can add a project manually using File → Open Project"
3. "Get Started" button closes modal
4. Main window shows empty state with "Set Project Root" button
5. No auto-selection attempted

### Discovery Fails

**Scenario:** Exception during discovery (disk error, permission denied, etc.)

**Handling:**
1. Error captured in `ProjectsViewModel.errorMessage`
2. Welcome modal shows error icon and message
3. "Retry" button to re-run discovery
4. "Dismiss" button to close and proceed with empty state

**Code:**
```swift
// In WelcomeModalView
if let error = vm.errorMessage {
    VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        Text("Discovery failed")
            .font(.headline)
        Text(error)
            .font(.caption)
            .foregroundStyle(.secondary)

        Button("Retry") {
            Task { await vm.discoverProjects() }
        }
    }
}
```

### Coordinator Resolves Project Mid-Discovery

**Scenario:** User manually selects project while discovery is running.

**Handling:**
1. `coordinator.switchProject()` called
2. Context published
3. Discovery continues in background (doesn't hurt)
4. Welcome modal auto-closes (coordinator now has context)
5. Timeline starts monitoring selected project

**Guard:** Check `StartupCoordinator.shared.current == nil` before auto-selection.

### Discovery Completes But Coordinator Still Has Context

**Scenario:** User has persisted path, coordinator starts successfully, but discovery runs anyway.

**Handling:**
1. Welcome modal **never shown** (coordinator didn't post notification)
2. Discovery runs silently in background (updates project list)
3. No auto-selection (coordinator already has context)
4. Normal app flow

**Current behavior preserved.**

---

## Testing Plan

### Manual Testing Scenarios

1. **First Launch (Clean Database)**
   - Delete database: `./scripts/db_manager.sh clean --force`
   - Launch app
   - Verify: Welcome modal appears immediately
   - Verify: "Scanning for projects..." shown
   - Wait for discovery
   - Verify: Progress updates ("Found X projects", ingestion progress)
   - Verify: "Discovery Complete" state
   - Click "Get Started"
   - Verify: Modal closes, timeline shows most recent project

2. **First Launch, No Projects**
   - Clean database
   - Temporarily rename `~/.claude/projects` to `~/.claude/projects.bak`
   - Launch app
   - Verify: Welcome modal shows "No projects found"
   - Verify: Guidance text about manual addition
   - Click "Get Started"
   - Verify: Main window shows empty state with "Set Project Root" button
   - Restore `~/.claude/projects`

3. **Dismiss Modal During Discovery**
   - Clean database
   - Launch app
   - Wait for modal to appear
   - Click "Dismiss" immediately (while discovery running)
   - Verify: Main window shows loading overlay
   - Verify: Overlay shows progress updates
   - Wait for completion
   - Verify: Overlay disappears, timeline loads

4. **Subsequent Launch (Normal Flow)**
   - Launch app normally (with persisted project)
   - Verify: No welcome modal shown
   - Verify: Timeline appears immediately
   - Verify: Discovery runs in background (project list updates)

5. **Manual Project Selection During Discovery**
   - Clean database
   - Launch app (welcome modal appears)
   - While discovery running, click "Dismiss"
   - Use "File → Open Project" to manually select folder
   - Verify: Modal closes (if still showing)
   - Verify: Timeline loads for manually selected project
   - Verify: Discovery continues in background

### Unit Testing

**Test:** Coordinator tolerates missing project

```swift
func testCoordinatorGracefulFailure() async throws {
    // Clear all project sources
    ProcessInfo.processInfo.environment.removeValue(forKey: "CONTEXTIFY_PROJECT_ROOT")
    HUDPreferences.clearPersistedRoot()

    // Start coordinator
    try await StartupCoordinator.shared.start()

    // Should not throw, should have nil context
    XCTAssertNil(StartupCoordinator.shared.current)
}
```

**Test:** Auto-selection after discovery

```swift
func testAutoSelectionAfterDiscovery() async throws {
    // Set up test projects in database
    let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
    let projectId1 = try orchestrator.getOrCreateProject(name: "Project1", rootPath: "/tmp/p1")
    let projectId2 = try orchestrator.getOrCreateProject(name: "Project2", rootPath: "/tmp/p2")

    // Update last_viewed_ts (p2 more recent)
    try orchestrator.updateProjectLastViewed(projectId: projectId2, timestamp: Date())
    try orchestrator.updateProjectLastViewed(projectId: projectId1, timestamp: Date().addingTimeInterval(-3600))

    // Run discovery (will find projects from DB)
    let vm = ProjectsViewModel(...)
    await vm.discoverProjects()

    // Verify most recent selected
    let context = try await StartupCoordinator.shared.ready()
    XCTAssertEqual(context.path, "/tmp/p2")
}
```

---

## Migration Path

### For Existing Users

**Impact:** None. Existing users have persisted project paths or bookmarks.

**Flow:**
1. Coordinator resolves project from persisted path
2. `coordinator.start()` succeeds
3. Welcome modal never shown
4. App works exactly as before

### For New Users

**Impact:** Smooth onboarding experience.

**Flow:**
1. Download and launch Contextify
2. Welcome modal appears with "Scanning for projects..."
3. Watch progress as it finds Claude Code/Codex projects
4. App auto-selects most recent
5. Start using immediately

### For Developers (Clean Database)

**Current:** Cryptic error, manual project selection required
**After Fix:** Welcome modal, auto-discovery, auto-selection

---

## Performance Considerations

### Discovery Performance

**Current benchmarks** (from logs):
- Discovery phase: 0.5-2 seconds (depends on project count)
- Ingestion phase: 5-30 seconds (depends on transcript count)
- Database writes: Batched, non-blocking

**Impact on UI:**
- Welcome modal: No impact (runs in background Task)
- Loading overlay: No impact (UI still responsive)
- Auto-selection: <100ms (single coordinator call)

### Memory Impact

**ProjectsViewModel in main window:**
- Adds ~1KB per discovered project
- Typical: 10-50 projects = 10-50KB
- Progress state: Negligible (<1KB)

**Total memory delta:** <100KB

### Thread Safety

**All discovery operations:**
- Run on background threads (Task priority .utility)
- UI updates via `@MainActor` closures
- Database access via actor-isolated TranscriptOrchestrator
- No main thread blocking

---

## Security & Privacy

### File System Access

**Scanned locations:**
- `~/.claude/projects/*` (Claude Code)
- `~/.codex/sessions/*` (Codex CLI)

**Sandboxing:**
- Non-sandboxed builds: Direct file access (already works)
- Sandboxed builds: Requires user to grant access via folder picker first
  - Welcome modal includes "Grant Access" button for sandboxed builds
  - Security-scoped bookmark created and persisted

### Data Privacy

**No network access** during discovery:
- All operations local
- No telemetry
- No analytics

**Database privacy:**
- Local SQLite only
- User controls location (Settings > Database)
- Can be on encrypted volume

---

## Future Enhancements

### Multi-Provider Support

**Currently:** Only Claude Code discovery implemented
**Future:** Add Codex CLI, Cursor, other providers

**Welcome modal changes:**
- Show breakdown by provider: "Found 5 Claude Code, 3 Codex projects"
- Provider icons in progress view

### Smart Project Recommendations

**Currently:** Auto-selects most recent by `last_viewed_ts`
**Future:** ML-based recommendations

- Most frequently viewed
- Most active (recent entries)
- Currently open in other tools (detect via process list)

### Custom Discovery Locations

**Currently:** Fixed paths (`~/.claude/projects`)
**Future:** User-configurable scan paths

- Settings panel: "Add custom project directory"
- Scan arbitrary folders for transcript patterns

### Parallel Discovery

**Currently:** Sequential scan (one provider at a time)
**Future:** Parallel provider scanning

- Claude Code and Codex in parallel
- Faster overall discovery time

---

## Acceptance Criteria

- [ ] App launches successfully with clean database (no errors)
- [ ] Welcome modal appears on first launch
- [ ] Discovery progress shown with live updates
- [ ] Projects found and ingested with progress bar
- [ ] Most recent project auto-selected after discovery
- [ ] Timeline loads automatically for selected project
- [ ] Modal dismissible with loading overlay on main window
- [ ] No modal shown on subsequent launches (normal flow preserved)
- [ ] Error handling for "no projects found" scenario
- [ ] Error handling for discovery failures with retry option
- [ ] Manual project selection during discovery works correctly
- [ ] Performance acceptable (no UI blocking, <30s total discovery time)
- [ ] Thread-safe (no crashes, no data races)

---

## Implementation Checklist

See `build/notes/TODOS.md` for detailed task breakdown.

---

## References

- **Coordinator Architecture:** `build/notes/technical-reference/startup-coordinator-architecture.md`
- **Discovery Implementation:** `build/notes/technical-reference/project-discovery-implementation.md`
- **Database Schema:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
- **Window Architecture:** `build/notes/technical-reference/window-architectures.md`

---

## Appendix: Key Code Locations

**Startup Coordination:**
- `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift` (lines 137-181: `start()`)
- `Contextify/Contextify/ContextifyApp.swift` (lines 190-203: coordinator startup)

**Discovery:**
- `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift` (lines 25-85: `discoverAllProjects()`)
- `Contextify/Contextify/ProjectsViewModel.swift` (lines 63-112: `discoverProjects()`)

**UI:**
- `Contextify/Contextify/ContentView.swift` (lines 75-94: `.task` startup)
- `Contextify/Contextify/ContextifyApp.swift` (lines 307-345: `initializeProjectsSystem()`)

**Database:**
- `app/Sources/ContextifyCore/Database/Repositories.swift` (ProjectRepository)
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`
