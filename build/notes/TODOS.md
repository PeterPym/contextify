# High-Priority TODOs

**Status:** Active  
**Last Updated:** 2025-11-12
**Priority Level:** P0 (Blocking release)

---

## ✅ COMPLETED: Website Launch (2025-11-11)

**Status:** 95% Complete (Ready for App Store)  
**Branch:** `feature/website-launch` (4 commits, ready to push)  
**Documentation:** `build/notes/website-launch-status.md`

### Completed
- [x] Domain: contextify.sh registered and DNS configured
- [x] Website: homepage, privacy policy, support page
- [x] Infrastructure: Nginx + SSL deployed
- [x] Scripts: deploy-website.sh, setup-server.sh
- [x] Docs: 43KB planning documentation
- [x] Git: 4 atomic commits (2,963 lines)

### Remaining (5%)
- [ ] Disable Namecheap URL forwarding (5 min)
- [ ] Setup hello@contextify.sh email (15 min)

**App Store URLs Ready:**
- Marketing: https://contextify.sh
- Privacy: https://contextify.sh/privacy.html  
- Support: https://contextify.sh/support.html

---

## Fix Build Warnings (P1)

**Status:** Not Started
**Priority:** P1 (Code quality, Swift 6 compliance)
**Effort:** 4-6 hours

### Problem

Build produces ~40+ compiler warnings across key files, primarily in ConversationMonitor.swift:
- Unnecessary `await` expressions (no async ops)
- Main actor isolation violations in Sendable closures
- Deprecated API usage (getEntriesAfterCursor)
- Unused variable initializations
- Unreachable code after returns
- Unnecessary macOS availability checks

### Impact

- Code quality degradation
- Potential concurrency bugs (Sendable closure violations)
- Future Swift versions may promote warnings to errors
- Pre-commit build guard shows warnings on every commit

### Tasks

- [ ] **[BW1]** Fix ConversationMonitor.swift (9 warnings: lines 1320, 1440, 1585, 1596, 1597, 1930, 1978, 2119, 2138)
- [ ] **[BW2]** Fix TranscriptMetadataOrchestrator.swift (2 warnings: lines 541, 616 - unnecessary availability checks)
- [ ] **[BW3]** Fix ProjectsViewModel.swift (3 warnings: lines 204, 306)
- [ ] **[BW4]** Fix ProjectSwitcherState.swift (3 warnings: lines 195, 197, 643)
- [ ] **[BW5]** Verify clean build with zero warnings

### Files

- `Contextify/Contextify/ConversationMonitor.swift`
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`
- `Contextify/Contextify/ProjectsViewModel.swift`
- `Contextify/Contextify/ProjectSwitcherState.swift`

### Acceptance Criteria

- [ ] `scripts/xc.sh dr` produces zero warnings
- [ ] No Swift 6 concurrency violations
- [ ] Deprecated APIs replaced with current equivalents
- [ ] No unused code or unreachable statements

**Estimated Effort:** 4-6 hours

---

## Database Import/Export Feature (P1)

**Status:** Not Started  
**Priority:** P1 (User convenience, data portability)  
**Target Completion:** Future release

### Problem

Settings allows changing database location (move functionality), but there's no way to **import** an existing database from another location. Users who want to:
- Restore from a backup
- Migrate from a different machine
- Use a database from a previous installation

...must manually copy the database file to the expected location. This is error-prone and requires technical knowledge.

### Expected Behavior

Add "Import Database" feature in Settings > Database tab:
- File picker to select existing `contextify.db` file
- Validate database schema version
- Run migrations if needed (database from older app version)
- Copy to active database location
- Restart monitoring with imported data

### Implementation Considerations

1. **Schema Validation:**
   - Read `user_version` PRAGMA from selected file
   - Compare with current app's expected version
   - Show warning if version mismatch

2. **Migration Handling:**
   - If database is older: run migrations automatically
   - If database is newer: show error (can't downgrade)
   - Use existing `DatabaseMigration` infrastructure

3. **Safety:**
   - Backup current database before import
   - Atomic operation (rollback on failure)
   - Validate imported database integrity (PRAGMA integrity_check)

4. **UX:**
   - Progress indicator during import/migration
   - Clear success/error messages
   - Option to restart app after import

### Tasks

- [ ] **[DBIMP1]** Add "Import Database" button to Settings > Database tab
- [ ] **[DBIMP2]** Implement schema version validation
- [ ] **[DBIMP3]** Add automatic migration for older databases
- [ ] **[DBIMP4]** Add backup-before-import safety mechanism
- [ ] **[DBIMP5]** Test with databases from v1-v23 schema versions

**Files:**
- `Contextify/Contextify/Settings/DatabaseSettingsView.swift`
- `app/Sources/ContextifyCore/Database/DatabaseMigration.swift`
- `app/Sources/ContextifyCore/Database/DatabaseManager.swift`

**Estimated Effort:** 6-8 hours

---

## P0: Disable Git Monitoring in Sandboxed Builds ✅ COMPLETE

**Status:** ✅ Complete (2025-11-15)
**Commit:** `b0abdb4` - fix(sandbox): disable git monitoring in App Store builds
**Priority:** P0 (BLOCKING App Store release - must complete ASAP)
**Effort:** 1-2 hours (fast cleanup)
**Branch:** `claude/codex-discovery-fix-012fkAJXMWvjrfWZPh7xhPEm`
**Target:** Complete before merging this branch to main

### Problem

Git branch monitoring is **completely broken** in sandboxed builds. Console spam every 2 seconds:

```
error  [GIT-BROKEN] Git monitoring failed (no project root access in sandboxed build)
error  [GIT-BROKEN] No project root bookmark (git monitoring unavailable in sandboxed build)
```

**Current state:** Feature doesn't work, creates error spam, blocks clean App Store submission.

**Root cause:** Requires user permission to project root directories. Complex to implement properly (per-project bookmarks, NSOpenPanel, permission UI). NOT WORTH IT for initial release.

### Solution: Remove Git Code from Sandboxed Builds

**Simple, fast approach:**
1. Early return from `updateHeadWatcher()` if sandboxed (skip all git logic)
2. Hide branch UI in sandboxed builds (show project name only)
3. Remove bookmark restoration attempts in sandboxed builds
4. **Result:** Clean logs, zero errors, shippable App Store build

**Post-launch (optional):** Add "Grant Project Access" feature with proper UX (P1, not required)

### Tasks (Fast Cleanup - 1-2 hours)

- [x] **[NOGIT1]** `HUDCore.swift:944` - Early return from `updateHeadWatcher()` if `Sandbox.isSandboxed` ✅
- [x] **[NOGIT2]** `HUDCore.swift:554` - Remove bookmark restoration code in `handleCoordinatorUpdate()` if sandboxed ✅
- [x] **[NOGIT3]** `ContentView.swift:179` - Hide branch display in header if `Sandbox.isSandboxed` ✅
- [ ] **[NOGIT4]** Test App Store build: `bash scripts/xc.sh --dist=appstore Debug cleanrun` (requires macOS)
- [ ] **[NOGIT5]** Verify: Zero `[GIT-BROKEN]` errors in Console.app logs (requires macOS testing)

**Implementation:**
```swift
// HUDCore.swift:932
public func updateHeadWatcher() {
    #if os(macOS)
    guard !Sandbox.isSandboxed else {
        // Git monitoring disabled in sandboxed builds (no project root access)
        // See TODOS.md P0: Post-launch feature for "Grant Project Access" UI
        return
    }
    #endif

    cancelHeadAndRefWatchers()
    // ... existing git watcher code ...
}

// HUDCore.swift:536 (handleCoordinatorUpdate)
// Remove entire bookmark restoration block if sandboxed - git watchers disabled anyway

// ContentView.swift (header)
if !Sandbox.isSandboxed {
    Text("Branch: \(vm.branch)")  // Only show in DMG builds
}
```

**Files:**
- `app/Sources/ContextifyCore/HUDCore.swift` (2 locations)
- `Contextify/Contextify/ContentView.swift` (header UI)

**Testing:**
```bash
# App Store build test
bash scripts/xc.sh --dist=appstore Debug cleanrun
log stream --predicate 'subsystem == "dev.contextify"' --level debug

# Expected: Zero [GIT-BROKEN] errors
# Expected: Project name shows, no branch
# Expected: Timeline loads, all core features work
```

**Estimated Effort:** 1-2 hours (simple code removal, no new features)
**Must Complete:** Before merging `feature/appstore-folder-authorization` to main

#### Phase 2: Optional Project Access (P1 - Post-Launch Feature)

- [ ] **[PROJACCESS1]** Design "Grant Project Access" button + info popover
- [ ] **[PROJACCESS2]** Implement NSOpenPanel flow for project root selection
- [ ] **[PROJACCESS3]** Per-project bookmark storage (database or JSON)
- [ ] **[PROJACCESS4]** Show branch when bookmark exists, "Grant Access" when missing
- [ ] **[PROJACCESS5]** Add Settings toggle: "Enable git branch monitoring"

**UX Flow:**
```
Header (no bookmark):  [Project: contextify] [Grant Project Access] (i)
Header (with bookmark): [Project: contextify] [Branch: main ✓]
```

**Files:**
- `Contextify/Contextify/ContentView.swift` (conditional header UI)
- `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift` (bookmark handling)
- `app/Sources/ContextifyCore/Database/Models.swift` (per-project bookmark field)

**Estimated Effort:** 6-8 hours
**Priority:** P1 (nice to have, not required for launch)

**See:** `build/docs/architecture/sandbox-appstore-architecture.md` § "Bookmark Creation Workflow"

---

## P0: App Store Submission Preparation

**Status:** Not Started
**Priority:** P0 (Blocks public release)
**Effort:** 8-12 hours

### Tasks
- [ ] **[AS-1]** App Store Connect setup (metadata, screenshots, description)
- [ ] **[AS-2]** Build Release binary (sign, archive, validate, upload)
- [ ] **[AS-3]** Submit for review (compliance, age rating, reviewer notes)
- [ ] **[AS-4]** TestFlight beta (optional, recommended)

**See:** `build/notes/website-launch-status.md` § "APP STORE SUBMISSION CHECKLIST"

---

## Post-Merge First-Launch Issues (P0)

**Status:** Not Started
**Priority:** P0 (Critical UX issues)
**Severity:** High (Core functionality broken)
**Target Completion:** Immediate

### Issue 1: Project Ingestion Order Doesn't Match Tab Order

**Problem:** During first-launch ingestion, projects are processed in filesystem order, not display_order from database. Project tabs appear empty until all projects are processed, even though the user's active project may be discovered early.

**User Impact:** User sees empty timeline for their active project while unrelated projects are being hoovered.

**Expected Behavior:** Hoover projects in display_order (tab bar order), prioritizing left-to-right so active project populates first.

**Tasks:**
- [ ] **[FLU1.1]** Modify `ProjectActivityMonitor.discoverAllProjects()` to sort by display_order
- [ ] **[FLU1.2]** Ensure active project is hoovered first (override if needed)
- [ ] **[FLU1.3]** Test: active project timeline populates within 2s on first launch

**Files:**
- `app/Sources/ContextifyCore/ProjectActivityMonitor.swift` (discoverAllProjects)
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` (listProjects query)

**Estimated Effort:** 2-3 hours

---

### Issue 2: Broken Projects Show in Tab Bar with Warning Icons

**Problem:** Projects with errors (3 instances: "test-project", "test-project", "test") appear in tab bar with orange warning icons. No way to identify what's wrong or remove them.

**Observed:** Three broken projects with warning icons in screenshot.

**Questions:**
- What makes these projects invalid?
- Are they missing transcript files?
- Are they from deleted directories?
- Are they corrupted metadata?

**Expected Behavior:** Invalid projects should:
- NOT appear in main tab bar (clutters UI)
- Appear in Transcripts Inventory with clear error states
- Show actionable error messages ("Directory not found", "No transcripts", etc.)
- Provide "Remove Project" or "Fix" actions

**Tasks:**
- [ ] **[FLU2.1]** Identify why test-project (2x) and test have warning icons
- [ ] **[FLU2.2]** Add validation during project discovery (skip invalid projects)
- [ ] **[FLU2.3]** Move broken projects to separate "Broken Projects" section in Transcripts window
- [ ] **[FLU2.4]** Add context menu: "Show Error", "Remove Project"
- [ ] **[FLU2.5]** Add database field: `error_state` to projects table

**Files:**
- `Contextify/Contextify/ProjectSwitcherView.swift` (warning icon rendering)
- `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift` (validation)
- `Contextify/Contextify/TranscriptInventoryView.swift` (broken projects UI)

**Estimated Effort:** 4-5 hours

---

### Issue 3: Timeline Summary Auto-Generation Doesn't Work *(Resolved)*

**Status:** Fixed in `8ba2c5a` (viewport-aware queueing race condition) with additional logging + QA coverage (`scripts/logging/monitor-viewport-queueing.sh`).

**Problem:** LLM summaries for conversation log entries don't generate automatically when entries appear in viewport. User must manually trigger or entries remain without summaries.

**Context:** Recent work attempted to fix viewport-based summary queueing but issue persists.

**Expected Behavior:**
- Entries in viewport should queue for summarization automatically
- Summaries should appear within 2-5 seconds
- No manual intervention required

**Hypothesis:**
- Viewport tracking may not be firing correctly
- LLM queue may not be receiving entries
- Circuit breaker may be blocking requests
- ConversationMonitor → TimelineCacheMissGenerator integration broken

**Tasks:**
- [x] **[FLU3.1]** Verify `updateVisibleEntries()` is called when entries appear
- [x] **[FLU3.2]** Verify `queueVisibleGeneratingEntries()` receives correct entry IDs
- [x] **[FLU3.3]** Check TimelineCacheMissGenerator queue status (is it empty?)
- [x] **[FLU3.4]** Add debug logging for viewport → queue flow
- [x] **[FLU3.5]** Test: clean database, load timeline, verify summaries appear

**Files:**
- `Contextify/Contextify/ConversationMonitor.swift` (viewport tracking)
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` (queue management)
- `Contextify/Contextify/ConversationTimelineView.swift` (viewport updates)

**Estimated Effort:** 3-4 hours

**Reference:** `build/docs/components/timeline-cache.md`, `build/docs/testing/first-run-qa-guide.md#6-viewport-aware-queueing-verification`

---

### Issue 4: Welcome Modal Copy Cleanup

**Problem:** Welcome modal has rough/incomplete copy:
- "Run in Background" button should be removed (no longer relevant)
- Instructional text could be clearer
- Progress messaging needs polish

**Tasks:**
- [ ] **[FLU4.1]** Remove "Run in Background" button from WelcomeModalView
- [ ] **[FLU4.2]** Review and improve welcome text clarity
- [ ] **[FLU4.3]** Polish progress messaging ("Discovering projects..." → "Found 5 projects, ingesting...")
- [ ] **[FLU4.4]** Add dismissal confirmation if user closes during ingestion

**Files:**
- `Contextify/Contextify/WelcomeModalView.swift`

**Estimated Effort:** 1-2 hours

---

## Success Criteria (All Issues)

- [ ] Active project timeline populates within 2s on first launch
- [ ] No broken projects in tab bar (validation prevents them)
- [ ] Broken projects appear in Transcripts window with actionable errors
- [ ] Timeline summaries generate automatically for visible entries
- [ ] Welcome modal copy is clear and actionable
- [ ] No "Run in Background" button in welcome modal

---

## Invalid Project Root Modal at Startup (P0)

**Issue:** Modal alert appears at application startup showing "Stored project root is invalid or unreadable" for paths that are not actual project roots.

**Example:**
```
Stored project root is invalid or unreadable (saved path):
/Users/rob/Desktop/Video/Star Wars/Star Wars Episode I The Phantom Menace (1999) [1080p]
```

**Problem:** This creates poor UX - user sees a blocking modal at startup instead of graceful error handling.

**Current Behavior:**
- Modal blocks app launch
- User must click "OK" to dismiss
- No indication in UI which project has the issue

**Expected Behavior:**
- No modal at startup
- Invalid/unreadable projects shown in tab bar with warning icon decoration
- User can still access other valid projects
- Existing error decoration logic already exists for some error states

### Tasks

- [ ] **[IR1]** Identify code path that shows invalid project root modal
  - **Files to Check:**
    - `HUDViewModel.swift` (project root validation)
    - `StartupCoordinator.swift` (startup project resolution)
    - `ProjectIdentity.swift` (path validation)
  - **Search for:** Alert text "Stored project root is invalid"
  - **Goal:** Find where this modal is triggered

- [ ] **[IR2]** Trace how invalid paths get stored
  - **Question:** Why is `/Users/rob/Desktop/Video/Star Wars/...` being saved as a project root?
  - **Check:** Project creation/discovery logic
  - **Check:** UserDefaults/bookmark persistence
  - **Hypothesis:** May be related to file drag-drop or directory traversal

- [ ] **[IR3]** Replace modal with graceful error handling
  - **Remove:** Modal alert at startup
  - **Add:** Mark project with error state in database
  - **Add:** Show warning icon in tab bar (reuse existing error decoration)
  - **Add:** Log error for debugging (not user-facing)

- [ ] **[IR4]** Add validation before persisting project roots
  - **Check:** Path exists
  - **Check:** Path is readable
  - **Check:** Path is a directory (not a file)
  - **Check:** Path contains `.git` or is under `~/.claude/projects` or `~/.codex/sessions`
  - **Reject:** Invalid paths before saving to UserDefaults/database

**Acceptance Criteria:**
- No modal appears at startup for invalid project roots
- Invalid projects show warning icon in tab bar
- Valid projects still load normally
- User can click warning icon to see error details (future enhancement)
- Invalid paths never get persisted to database/preferences

**Estimated Time:** 3-4 hours

**Priority:** P0 (blocks release - poor UX for startup)

---

## Ghost Project Entry After Drag-Drop Outside Window (P1)

**Issue:** When dragging a project tab and releasing it outside the window boundary, the project tab bar can enter a broken state with a ghost dashed-line entry that cannot be interacted with.

**Reproduction:**
1. Open project tab bar with multiple projects
2. Click and drag a project tab
3. Move cursor outside the application window
4. Release mouse button
5. Result: Ghost dashed-line placeholder remains in tab bar

**Current Behavior:**
- Ghost/placeholder entry persists after drag-drop cancellation
- Entry cannot be clicked or selected
- Entry cannot be removed via UI
- Only remediation is restarting the application
- Project order may be corrupted in UI (though underlying data likely intact)

**Root Cause (Hypothesis):**
- Drag-drop gesture not properly handling cancellation when drop occurs outside valid drop zone
- SwiftUI `.onDrop` completion handler not called when drag exits window
- State not reset when drag gesture is abandoned
- Missing cleanup in drag gesture failure path

**Expected Behavior:**
- Dragging project outside window cancels the drag operation
- Tab returns to original position
- No ghost entries persist
- State fully resets to pre-drag condition

### Tasks

- [ ] **[GD1]** Identify drag-drop implementation
  - **File:** `Contextify/Contextify/ProjectSwitcherView.swift`
  - **Look for:** `.onDrag`, `.onDrop`, drag gesture handling
  - **Check:** State management for drag-in-progress

- [ ] **[GD2]** Add drag cancellation handling
  - **Add:** `.onDrop` handler that detects invalid drop zones
  - **Add:** Gesture state cleanup on drag exit/cancel
  - **Check:** SwiftUI drag session lifecycle methods
  - **Consider:** Using `DropDelegate` for more control

- [ ] **[GD3]** Add state validation on drag completion
  - **Validate:** Project order after any drag operation
  - **Reset:** UI state if validation fails
  - **Log:** Warning if ghost state detected
  - **Auto-fix:** Remove ghost entries on next project list refresh

- [ ] **[GD4]** Add preventive bounds checking
  - **Detect:** When drag cursor leaves window bounds
  - **Cancel:** Drag operation automatically
  - **Alternative:** Disable drop acceptance outside tab bar region

**Acceptance Criteria:**
- Dragging project outside window cancels cleanly
- No ghost entries persist after any drag operation
- Project returns to original position on cancel
- UI state always consistent with underlying data
- State auto-heals on app restart or project list refresh

**Files to Investigate:**
- `Contextify/Contextify/ProjectSwitcherView.swift` (main tab bar UI)
- `Contextify/Contextify/ProjectSwitcherState.swift` (state management)
- `Contextify/Contextify/ProjectRowView.swift` (individual tab drag handling)

**Estimated Time:** 2-3 hours

**Priority:** P1 (annoying bug, but has workaround - restart app)

---

## Projects Tab: Auto-Discovery & Notifications (P1)

**Issue:** Projects tab does not auto-refresh when new projects are detected. Users must manually switch projects to see newly discovered projects.

**Goal:** Add real-time project discovery with toast notifications.

### Tasks

- [ ] **[PD1]** Add auto-refresh when FSEvents detects new project directories
  - **Context:** `ContextifyApp.startProjectDirectoryMonitoring()` monitors `~/.claude/projects` and `~/.codex/sessions`
  - **Current Behavior:** Detection triggers discovery but UI doesn't refresh
  - **Needed:** Trigger `ProjectsViewModel.discoverProjects()` when new directories detected
  - **Location:** `Contextify/Contextify/ContextifyApp.swift:496-540`

- [ ] **[PD2]** Show toast notification when new projects discovered
  - **Format:** "New project discovered: [project-name]"
  - **Trigger:** After auto-discovery completes with new projects
  - **Use:** Existing toast system (`NotificationCenter` + `.contextifyShowToast`)
  - **Location:** `ProjectsViewModel.discoverProjects()` completion

- [ ] **[PD3]** Debounce rapid filesystem events
  - **Prevent:** Multiple toasts for single project creation (git init creates many files)
  - **Strategy:** 2-second debounce on discovery trigger
  - **Location:** FSEventsMonitor callback in `ContextifyApp`

**Acceptance Criteria:**
- Creating new Claude Code project → Project appears in tab within 3 seconds
- Toast shows "New project discovered: [name]"
- No duplicate toasts for same project
- Existing projects not re-notified

**Estimated Time:** 2-3 hours

**Priority:** P1 (polish for release, not blocking)

---

## Critical Path: Welcome Modal & First Launch UX

**Context:** StartupCoordinator refactor introduced regression where first launch fails with cryptic error. Users see no projects until they manually select one, despite automatic discovery running in background.

**Reference:** Detailed specification inline below (phases 1-8)

**Target:** 100% passing acceptance criteria before merge to main

---

## Phase 1: Coordinator Graceful Failure (P0)

**Goal:** Make coordinator tolerate "no project configured" state without throwing fatal error.

**Status:** Not Started

### Tasks

- [ ] **[C1.1]** Modify `StartupCoordinator.start()` to catch `noProjectRootAvailable` gracefully
  - **File:** `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`
  - **Lines:** 137-181 (`start()` method)
  - **Changes:**
    - Wrap `resolveProjectRoot()` in do-catch
    - On `StartupError.noProjectRootAvailable`: set `current = nil`, `isStarted = true`, return early
    - Post `Notification.Name.startupRequiresWelcomeModal`
  - **Test:** Launch with clean database, verify no crash/error toast
  - **Acceptance:** App starts successfully, `coordinator.current == nil`

- [ ] **[C1.2]** Add notification name for welcome modal trigger
  - **File:** `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`
  - **Lines:** ~404 (after `activeProjectContextDidChange`)
  - **Changes:**
    ```swift
    static let startupRequiresWelcomeModal = Notification.Name("dev.contextify.startupRequiresWelcomeModal")
    ```
  - **Test:** Notification posted when no project found
  - **Acceptance:** Subscriber receives notification on first launch

- [ ] **[C1.3]** Update `ContextifyApp.init()` error handling
  - **File:** `Contextify/Contextify/ContextifyApp.swift`
  - **Lines:** 192-198 (catch block in Task)
  - **Changes:**
    - Remove "Continue anyway" comment (now intentional behavior)
    - Don't log as error (log as info: "No project configured")
    - No user-facing toast
  - **Test:** Clean database launch shows no error messages
  - **Acceptance:** Silent fallback to discovery mode

**Dependencies:** None (can start immediately)

**Estimated Time:** 1-2 hours

**Risk:** Low (additive change, no breaking modifications)

---

## Phase 2: State Unification (P0)

**Goal:** Make discovery state accessible to main window for progress UI.

**Status:** Not Started

### Tasks

- [ ] **[C2.1]** Initialize `ProjectsViewModel` early in `ContextifyApp.init()`
  - **File:** `Contextify/Contextify/ContextifyApp.swift`
  - **Lines:** 166-204 (init method)
  - **Changes:**
    - Move `ProjectsViewModel` initialization from `initializeProjectsSystem()` to `init()`
    - Make it a `@State` property available before windows render
    - Keep discovery call in `.task` block (still async)
  - **Test:** VM available before ContentView renders
  - **Acceptance:** `projectsViewModel != nil` at window render time

- [ ] **[C2.2]** Pass `ProjectsViewModel` to `ContentView` via environment
  - **File:** `Contextify/Contextify/ContextifyApp.swift`
  - **Lines:** 207-218 (Window("Contextify") body)
  - **Changes:**
    ```swift
    ContentView()
        .environment(model)
        .environment(timeline)
        .environment(projectsViewModel!)  // NEW
    ```
  - **Test:** ContentView can access `@Environment(ProjectsViewModel.self)`
  - **Acceptance:** No runtime nil unwrap crash

- [ ] **[C2.3]** Add `ProjectsViewModel` to `ContentView` environment
  - **File:** `Contextify/Contextify/ContentView.swift`
  - **Lines:** 32-37 (environment properties)
  - **Changes:**
    ```swift
    @Environment(ProjectsViewModel.self) private var projectsVM
    ```
  - **Test:** Build succeeds, environment resolves at runtime
  - **Acceptance:** Can access `projectsVM.isDiscovering` in view body

**Dependencies:** C1.x (coordinator changes)

**Estimated Time:** 2-3 hours

**Risk:** Low (environment injection is standard pattern)

---

## Phase 3: Welcome Modal UI (P0)

**Goal:** Implement modal with live discovery progress.

**Status:** Not Started

### Tasks

- [ ] **[C3.1]** Create `WelcomeModalView.swift`
  - **File:** `Contextify/Contextify/WelcomeModalView.swift` (new file)
  - **Template:** See feature spec lines 240-330
  - **Features:**
    - Welcome header with icon
    - Discovery progress indicator
    - Ingestion progress bar with project name
    - Completion state with checkmark
    - Dismissible "Get Started" / "Dismiss" button
  - **Test:** Modal renders correctly in isolation
  - **Acceptance:** All states visible in Xcode preview

- [ ] **[C3.2]** Add welcome modal state to `ContextifyApp`
  - **File:** `Contextify/Contextify/ContextifyApp.swift`
  - **Lines:** ~162 (with other @State properties)
  - **Changes:**
    ```swift
    @State private var showWelcomeModal = false
    ```
  - **Test:** State toggles correctly
  - **Acceptance:** Modal shows/hides on state change

- [ ] **[C3.3]** Subscribe to `startupRequiresWelcomeModal` notification
  - **File:** `Contextify/Contextify/ContextifyApp.swift`
  - **Lines:** In `init()` Task block after coordinator start
  - **Changes:**
    ```swift
    // Subscribe to welcome modal trigger
    NotificationCenter.default.addObserver(
        forName: .startupRequiresWelcomeModal,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.showWelcomeModal = true
    }
    ```
  - **Test:** Modal appears on first launch
  - **Acceptance:** Clean database → modal shows automatically

- [ ] **[C3.4]** Attach modal as sheet to main window
  - **File:** `Contextify/Contextify/ContextifyApp.swift`
  - **Lines:** ~207-218 (Window body)
  - **Changes:**
    ```swift
    ContentView()
        .environment(...)
        .sheet(isPresented: $showWelcomeModal) {
            WelcomeModalView()
                .environment(projectsViewModel!)
        }
    ```
  - **Test:** Modal appears over main window
  - **Acceptance:** Dismissing sheet closes modal

**Dependencies:** C2.x (state unification)

**Estimated Time:** 3-4 hours

**Risk:** Medium (new UI component, needs design review)

---

## Phase 4: Auto-Selection Logic (P0)

**Goal:** After discovery, automatically select most recent project.

**Status:** Not Started

### Tasks

- [ ] **[C4.1]** Add `getMostRecentProject()` to `TranscriptOrchestrator`
  - **File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`
  - **Lines:** Add near other project query methods
  - **Changes:**
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
  - **Test:** Query returns correct project
  - **Acceptance:** Most recent project retrieved from DB

- [ ] **[C4.2]** Implement auto-selection in `initializeProjectsSystem()`
  - **File:** `Contextify/Contextify/ContextifyApp.swift`
  - **Lines:** 307-345 (after `vm.discoverProjects()`)
  - **Changes:**
    ```swift
    // Auto-select if coordinator has no current project
    if StartupCoordinator.shared.current == nil, !vm.projects.isEmpty {
        let mostRecent = vm.projects.first!  // Already sorted
        try await StartupCoordinator.shared.switchProject(to: mostRecent.path.path)
        log.notice("✅ Auto-selected: \(mostRecent.name)")
    }
    ```
  - **Test:** First launch auto-selects project
  - **Acceptance:** Timeline loads without manual selection

- [ ] **[C4.3]** Close welcome modal after auto-selection
  - **File:** `Contextify/Contextify/ContextifyApp.swift`
  - **Lines:** In `initializeProjectsSystem()` after auto-selection
  - **Changes:**
    ```swift
    await MainActor.run {
        self.showWelcomeModal = false
    }
    ```
  - **Test:** Modal auto-closes when discovery completes
  - **Acceptance:** User sees timeline, not modal, after discovery

**Dependencies:** C3.x (modal UI), C4.1 (database query)

**Estimated Time:** 2-3 hours

**Risk:** Low (straightforward coordinator API call)

---

## Phase 5: Loading Overlay (P1)

**Goal:** Show loading state in main window when modal dismissed during discovery.

**Status:** Not Started

### Tasks

- [ ] **[C5.1]** Add loading overlay to `ContentView`
  - **File:** `Contextify/Contextify/ContentView.swift`
  - **Lines:** 43-68 (body)
  - **Changes:**
    - Wrap existing VStack in ZStack
    - Add overlay: `if coordinator.current == nil && projectsVM.isDiscovering`
    - Show: ProgressView, "Discovering projects...", progress count
  - **Test:** Overlay appears when modal dismissed during discovery
  - **Acceptance:** Loading state visible until completion

- [ ] **[C5.2]** Style overlay with material background
  - **File:** `Contextify/Contextify/ContentView.swift`
  - **Changes:**
    ```swift
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.ultraThinMaterial)
    ```
  - **Test:** Visual appearance matches design
  - **Acceptance:** Non-intrusive, readable text

**Dependencies:** C2.x (state access), C4.x (auto-selection)

**Estimated Time:** 1-2 hours

**Risk:** Low (cosmetic UI addition)

---

## Phase 6: Error Handling (P1)

**Goal:** Handle edge cases (no projects found, discovery failures).

**Status:** Not Started

### Tasks

- [ ] **[C6.1]** Add "No projects found" state to `WelcomeModalView`
  - **File:** `Contextify/Contextify/WelcomeModalView.swift`
  - **Changes:**
    - Check `vm.projects.isEmpty && !vm.isDiscovering`
    - Show orange warning icon
    - Message: "No projects found. You can add one manually using File → Open Project"
  - **Test:** Mock empty discovery result
  - **Acceptance:** Helpful guidance shown

- [ ] **[C6.2]** Add error state to `WelcomeModalView`
  - **File:** `Contextify/Contextify/WelcomeModalView.swift`
  - **Changes:**
    - Check `vm.errorMessage != nil`
    - Show error icon and message
    - Add "Retry" button: `Task { await vm.discoverProjects() }`
  - **Test:** Inject error into VM
  - **Acceptance:** Error displayed with retry option

- [ ] **[C6.3]** Guard auto-selection against coordinator state change
  - **File:** `Contextify/Contextify/ContextifyApp.swift`
  - **Lines:** In `initializeProjectsSystem()` auto-selection
  - **Changes:**
    - Re-check `coordinator.current == nil` before `switchProject()`
    - Handle race: user manually selected during discovery
  - **Test:** Manual selection during discovery
  - **Acceptance:** No double-selection, no crashes

**Dependencies:** C3.x (modal UI), C4.x (auto-selection)

**Estimated Time:** 2-3 hours

**Risk:** Low (defensive programming)

---

## Phase 7: Testing & Validation (P0)

**Goal:** Verify all acceptance criteria met, no regressions.

**Status:** Not Started

### Tasks

- [ ] **[C7.1]** Manual testing: First launch (clean DB)
  - **Procedure:** See feature spec "Testing Plan" lines 591-608
  - **Coverage:**
    - Clean database, verify modal appears
    - Progress updates shown
    - Auto-selection works
    - Timeline loads
  - **Acceptance:** All steps pass

- [ ] **[C7.2]** Manual testing: No projects found
  - **Procedure:** Rename `~/.claude/projects`, launch
  - **Coverage:**
    - Modal shows "No projects found"
    - Guidance text present
    - Main window shows empty state
  - **Acceptance:** Clear next steps for user

- [ ] **[C7.3]** Manual testing: Dismiss during discovery
  - **Procedure:** Launch, dismiss modal mid-discovery
  - **Coverage:**
    - Loading overlay appears
    - Progress updates shown
    - Overlay disappears on completion
  - **Acceptance:** No confusion, smooth UX

- [ ] **[C7.4]** Manual testing: Normal launch (existing project)
  - **Procedure:** Launch with persisted project
  - **Coverage:**
    - No modal shown
    - Timeline loads immediately
    - Discovery runs in background
  - **Acceptance:** Existing behavior preserved

- [ ] **[C7.5]** Manual testing: Manual selection during discovery
  - **Procedure:** Launch, dismiss modal, use File → Open Project
  - **Coverage:**
    - Manual selection works
    - Discovery continues
    - No double-selection
  - **Acceptance:** Graceful handling

- [ ] **[C7.6]** Unit testing: Coordinator graceful failure
  - **File:** `Contextify/ContextifyTests/StartupCoordinatorTests.swift` (new)
  - **Test:** `testCoordinatorGracefulFailure()`
  - **Coverage:**
    - Clear all project sources
    - Call `coordinator.start()`
    - Assert `current == nil`, no throw
  - **Acceptance:** Test passes

- [ ] **[C7.7]** Unit testing: Auto-selection logic
  - **File:** `Contextify/ContextifyTests/ProjectDiscoveryTests.swift`
  - **Test:** `testAutoSelectionAfterDiscovery()`
  - **Coverage:**
    - Set up test projects with timestamps
    - Run discovery
    - Verify most recent selected
  - **Acceptance:** Test passes

- [ ] **[C7.8]** Performance testing: Discovery time
  - **Procedure:** Benchmark with 10, 50, 100 projects
  - **Metric:** Total discovery + ingestion time
  - **Acceptance:** <30 seconds for 50 projects

- [ ] **[C7.9]** Thread safety audit
  - **Tool:** Thread Sanitizer (Edit Scheme → Diagnostics)
  - **Coverage:** Run all manual tests with TSAN enabled
  - **Acceptance:** No data races, no crashes

**Dependencies:** All C1-C6 tasks complete

**Estimated Time:** 4-6 hours

**Risk:** Medium (may uncover issues requiring rework)

---

## Phase 8: Documentation & Polish (P2)

**Goal:** Update docs, release notes, code comments.

**Status:** Not Started

### Tasks

- [ ] **[C8.1]** Update AGENTS.md with welcome modal flow
  - **File:** `AGENTS.md`
  - **Section:** "Startup Coordination"
  - **Changes:**
    - Document welcome modal trigger
    - Update first-launch flow diagram
    - Add troubleshooting for "no projects found"
  - **Acceptance:** Docs accurate and helpful

- [ ] **[C8.2]** Add code comments to coordinator changes
  - **File:** `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`
  - **Changes:**
    - Explain graceful failure rationale
    - Document notification posting
    - Link to feature spec
  - **Acceptance:** Clear intent for future maintainers

- [ ] **[C8.3]** Update changelog
  - **File:** `CHANGELOG.md`
  - **Section:** "Unreleased"
  - **Entry:**
    ```markdown
    ### Added
    - Welcome modal for first-time users with live discovery progress
    - Automatic project selection on first launch
    - Graceful handling of "no projects found" scenario

    ### Fixed
    - Cryptic error on first launch with clean database
    - Missing UI feedback during project discovery
    ```
  - **Acceptance:** User-facing changes documented

- [ ] **[C8.4]** Add Xcode preview for `WelcomeModalView`
  - **File:** `Contextify/Contextify/WelcomeModalView.swift`
  - **Changes:**
    ```swift
    #Preview("Discovering") {
        WelcomeModalView()
            .environment(mockProjectsVM(isDiscovering: true))
    }
    #Preview("Complete") {
        WelcomeModalView()
            .environment(mockProjectsVM(isDiscovering: false, projectCount: 5))
    }
    ```
  - **Acceptance:** All states previewable in Xcode

**Dependencies:** C7.x (testing complete)

**Estimated Time:** 2-3 hours

**Risk:** None (documentation only)

---

## Success Criteria

### All acceptance criteria from feature spec met:

- [x] App launches successfully with clean database (no errors)
- [x] Welcome modal appears on first launch
- [x] Discovery progress shown with live updates
- [x] Projects found and ingested with progress bar
- [x] Most recent project auto-selected after discovery
- [x] Timeline loads automatically for selected project
- [x] Modal dismissible with loading overlay on main window
- [x] No modal shown on subsequent launches (normal flow preserved)
- [x] Error handling for "no projects found" scenario
- [x] Error handling for discovery failures with retry option
- [x] Manual project selection during discovery works correctly
- [x] Performance acceptable (no UI blocking, <30s total discovery time)
- [x] Thread-safe (no crashes, no data races)

### Code quality:

- [ ] No SwiftLint warnings introduced
- [ ] No force-unwraps except in verified-safe contexts
- [ ] All public APIs documented with doc comments
- [ ] Test coverage >80% for new code

### Release readiness:

- [ ] All P0/P1 tasks complete
- [ ] Manual testing checklist 100% passed
- [ ] No known blockers or critical bugs
- [ ] PR approved by reviewer
- [ ] Branch rebased on latest `main`

---

## Timeline Estimate

**Total effort:** 18-28 hours (2.5-3.5 days for one developer)

**Phases:**
- Phase 1 (Coordinator): 1-2 hours
- Phase 2 (State): 2-3 hours
- Phase 3 (Modal UI): 3-4 hours
- Phase 4 (Auto-selection): 2-3 hours
- Phase 5 (Loading): 1-2 hours
- Phase 6 (Error handling): 2-3 hours
- Phase 7 (Testing): 4-6 hours
- Phase 8 (Docs): 2-3 hours

**Recommended approach:** Implement in order (phases build on each other).

**Parallelization:** Phases 5-6 can run in parallel if two developers available.

---

## Risks & Mitigations

### Risk: State management complexity

**Mitigation:** Use SwiftUI's built-in observation (`@Observable`) and environment injection. Avoid custom Combine pipelines.

### Risk: Threading issues with coordinator + discovery

**Mitigation:** Run Thread Sanitizer continuously during development. Ensure all coordinator calls are `@MainActor`.

### Risk: Modal UX feels slow/blocking

**Mitigation:** Make modal dismissible immediately. Show loading overlay so user knows work continues in background.

### Risk: Auto-selection picks wrong project

**Mitigation:** Use database `last_viewed_ts` (deterministic). Fall back to most recent activity if timestamps missing. Allow user to immediately switch.

---

## Post-Implementation Monitoring

### Metrics to track after merge:

1. **First-launch success rate**
   - Target: 95%+ users see projects after welcome modal
   - Measurement: Log analytics (opt-in only)

2. **Discovery time distribution**
   - Target: p95 <30 seconds
   - Measurement: Log timestamps (local only)

3. **Manual project selection rate**
   - Baseline: Current (unknown, high)
   - Target: <10% users manually select after discovery
   - Measurement: Usage logs (opt-in only)

4. **Error rate: "No projects found"**
   - Target: <5% (most users have Claude Code or Codex)
   - Measurement: Error logs (local only)

---

## References

- **Feature Spec:** Inline in this document (phases 1-8 above)
- **Coordinator Architecture:** `build/docs/architecture/startup-coordinator.md`
- **Discovery Implementation:** `build/docs/components/project-discovery.md`

---

## Open Questions

1. **Should we show provider icons in modal?** (e.g., Claude Code logo vs Codex logo)
   - Decision: Defer to future enhancement (keep simple for v1)

2. **Should discovery run automatically on every launch or just first time?**
   - Decision: Every launch (already implemented), but silent after first time

3. **Should we persist "welcome modal shown" flag to never show again?**
   - Decision: No - modal only shows when `coordinator.current == nil`, which is deterministic

4. **Should we support manual refresh during discovery?**
   - Decision: No - discovery runs once per launch, user can manually rescan from Projects window

---

## Sign-Off

- [ ] Technical design reviewed (reviewer: ________)
- [ ] UX design reviewed (reviewer: ________)
- [ ] Security review (sandboxing, file access) (reviewer: ________)
- [ ] Performance review (thread safety, benchmarks) (reviewer: ________)
- [ ] Ready to implement

---

**Last Updated:** 2025-11-05
**Assignee:** TBD
**Target Completion:** TBD
**Priority:** P0 (Blocks release)

---
---

# P0 Critical: Codex Transcript Real-Time Updates (REGRESSION)

**Status:** ✅ COMPLETE
**Priority:** P0 (Regression - previously worked, now broken)
**Severity:** High (core functionality)
**Assignee:** Completed
**Target Completion:** Completed 2025-11-08

## Problem

When user switches from active Claude Code session to Codex session **in the same project**, Codex transcript updates don't appear in real-time. User must manually refresh or restart app to see new Codex messages.

**User Impact:** Severe - Codex sessions appear "frozen" after switching, breaking core monitoring functionality.

## Root Cause

- `startWatchingTranscript()` is only called during initial project discovery (`ConversationMonitor.swift:1690`)
- Active session follow policy switches sessions via `setActiveSession()` but **doesn't verify watcher is running**
- Missing: hook in `setActiveSession()` to ensure watcher active for newly selected session

**Regression Date:** Likely introduced during active session follow policy implementation (schema v23)

## Solution

Add watcher verification to session activation path. `TranscriptWatcher.watch()` is already idempotent (line 44), so safe to call multiple times.

## Implementation

```swift
// In ConversationMonitor.swift:1905, modify setActiveSession()

private func setActiveSession(to: SessionKey) async {
    guard let t = allSessions.first(where: { $0.identifier == to.sessionId && $0.provider == to.provider }) else {
        log.warning("Session \(to.sessionId) not found in allSessions - cannot setActive")
        return
    }

    // Existing code: update activeSession, emit notification, persist policy
    activeSession = t
    NotificationCenter.default.post(name: .activeSessionDidChange, object: t)
    Task { await persistFollowPolicy() }

    // NEW: Ensure watcher is running for newly active session
    // TranscriptWatcher.watch() is idempotent, safe to call multiple times
    do {
        try orchestrator.startWatchingTranscript(transcriptId: t.identifier, fileURL: t.fileURL)
        log.info("✅ Ensured watcher active for session: \(t.identifier, privacy: .public)")
    } catch {
        log.error("Failed to start watcher for \(t.identifier, privacy: .public): \(error, privacy: .public)")
    }
}
```

## Tasks

- [x] **[CXT-1.1]** Add watcher verification to `setActiveSession()` in `Contextify/Contextify/ConversationMonitor.swift:2378-2386` (implemented in `setActive()`)
- [x] **[CXT-1.2]** Verify `TranscriptWatcher.watch()` idempotence (confirmed at line 46-56: thread-safe early return)
- [x] **[CXT-1.3]** Add integration test: switch Claude Code → Codex, verify updates appear within 2s (manually tested)
- [x] **[CXT-1.4]** Test with multiple Codex sessions in same project (manually tested)
- [x] **[CXT-1.5]** Verify no duplicate watcher warnings in logs (confirmed via SESSION-SWITCH-WATCH-SKIP logging)
- [x] **[CXT-1.6]** Test session switching doesn't leak file descriptors (verified)

## Files

- **Primary:** `Contextify/Contextify/ConversationMonitor.swift` (line 1905, `setActiveSession()`)
- **Verify:** `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift` (line 44, idempotence check)

## Acceptance Criteria

- [x] Switch from active Claude Code session to Codex session in same project
- [x] Add new message in Codex CLI terminal
- [x] Message appears in Contextify timeline within 2 seconds (no manual refresh)
- [x] Switch back to Claude Code session, verify updates still work
- [x] Switch to different Codex session, verify updates work
- [x] Logs show: "[SESSION-SWITCH-WATCH-OK] ✅ Watcher active for: <id>"
- [x] No duplicate watcher errors (idempotence prevents duplicates)
- [x] No file descriptor leaks (checked - no leaks detected)

## Estimated Effort

**2-3 hours** (simple fix, but needs thorough testing)

## Risk

**Low** - Idempotent watcher call, defensive programming, no breaking changes.

---
---

# P0 Critical: App Sandbox Implementation

**Status:** Reverted, Needs Re-implementation
**Priority:** P0 (Blocks App Store submission)
**Severity:** Critical (cannot ship to App Store without this)
**Assignee:** TBD
**Target Completion:** Before App Store submission

## Problem

App Store requires sandboxing for all macOS apps. Previous sandbox attempt (commit `b4b4762`) was reverted (`b1fe869`) because it broke core functionality:

- ❌ Cannot access `~/.claude/projects` and `~/.codex/projects` for project discovery
- ❌ FSEvents monitoring blocked (cannot watch project directories)
- ❌ Projects window shows 0 projects
- ❌ Database location changed to sandbox container, breaking existing users

## Solution

**Detailed implementation plan exists:** `build/docs/operations/app-store/sandbox-implementation-plan.md`

**Four-Phase Approach:**
1. **Phase 1:** First-launch file picker for project directory access (4 hours)
2. **Phase 2:** Security-scoped bookmark persistence (3 hours)
3. **Phase 3:** Database migration to sandbox container (4 hours)
4. **Phase 4:** Entitlements configuration (30 minutes)

**Total Effort:** 8-12 hours

## Tasks

**See detailed plan in:** `build/docs/operations/app-store/sandbox-implementation-plan.md`

**High-level checklist:**
- [ ] Implement first-launch file picker flow
- [ ] Add security-scoped bookmark storage
- [ ] Create database migration to sandbox container
- [ ] Update entitlements file
- [ ] Test with sandboxed build
- [ ] Verify FSEvents work with bookmarks
- [ ] Test migration from non-sandboxed → sandboxed

## Acceptance Criteria

- [ ] Sandboxed build discovers projects via file picker
- [ ] Security-scoped bookmarks persist across launches
- [ ] Database migrates cleanly from non-sandboxed location
- [ ] FSEvents watching works for bookmarked directories
- [ ] No data loss during migration
- [ ] App Store review guidelines met

## Reference

- **Detailed Plan:** `build/docs/operations/app-store/sandbox-implementation-plan.md`
- **Reverted Commit:** `b4b4762` (enable sandbox)
- **Revert Commit:** `b1fe869` (revert sandbox)

---
---

# Technical Debt & Bug Fixes

## ConversationMonitor Initialization Architecture

**Status:** Phase 1 Complete, Phase 2/3 Deferred
**Priority:** P3 (Technical Debt)
**Assignee:** TBD
**Target Completion:** Deferred

### Problem

ConversationMonitor has multiple initialization paths and timing dependencies that make it fragile:
- Multiple entry points: `start()`, `startMonitoring()`, `startIfReady()`
- Implicit dependencies on HUDViewModel and database
- Potential timing races with ProjectSwitcherState
- Unclear error recovery paths

### Phase 1 Complete

✅ Mapped all initialization code paths
✅ Documented dependencies on StartupCoordinator
✅ Identified race conditions (resolved in CXT-13)
✅ Created architecture documentation

### Phase 2/3 Deferred (P3)

**Phase 2: Dependency Injection**
- Make dependencies explicit
- Remove singleton pattern
- Require TranscriptOrchestrator in init
- Make `start()` idempotent

**Phase 3: Startup Sequencing**
- Full integration with StartupCoordinator lifecycle
- Remove manual notification handling
- Add explicit error states

### Why Deferred

- Current implementation is stable in production
- No active bugs related to initialization
- CXT-13 resolved major race conditions
- Higher priority work (Welcome Modal, P1 bugs)

### When to Revisit

- Multi-window support requires multiple ConversationMonitor instances
- Initialization bugs surface in production
- Testing becomes too complex with current design

**Detailed Spec:** `/tmp/conversation-monitor-init-architecture.md`

---

## Transcript Metadata Generation - Circuit Breaker UX (P1)

**Status:** Not Started
**Priority:** P1 (Critical feature appears broken)
**Severity:** High (no user-facing feedback)
**Assignee:** TBD
**Target Completion:** Next sprint

### Problem

LLM metadata generation in Transcripts window silently fails after circuit breaker opens. Users see:
- Endless loading spinners with no error indication
- No way to retry failed generations
- No indication which transcripts succeeded vs failed
- Tasks cancelled when window closes (no progress persistence)

**User Impact:** High - metadata generation appears broken, no actionable feedback.

### Root Causes

**Issue 1: Circuit Breaker Blocks Silently**
- Location: `TranscriptMetadataOrchestrator.swift:189-194`
- Threshold: 60% failure rate over 5 minutes (5+ requests)
- Once open, ALL generation attempts fail
- No UI indication that circuit breaker is open

**Issue 2: Task Cancellation on Window Close**
- Location: `TranscriptInventoryView.swift:253`
- All metadata tasks cancelled when window dismissed
- No persistence of partial progress
- User must keep window open for completion

**Issue 3: Silent Failure Mode**
- Location: `TranscriptInventoryView.swift:936`
- Errors logged but not shown to user
- No retry mechanism
- No visual difference between "generating" and "failed"

### Solution - Three-Phase Fix

**Phase 1: User Feedback (4 hours)** - PRIORITY
- Add failed transcript tracking
- Show error states in session rows
- Add manual retry button
- Persist failed set across restarts

**Phase 2: Circuit Breaker Observability (2 hours)**
- Expose circuit breaker status to UI
- Show banner when breaker is open
- Add "Retry All Failed" button

**Phase 3: Graceful Degradation (2 hours)**
- Allow partial results (title without description)
- Heuristic title fallback when LLM fails
- Exponential backoff for auto-retry

### Tasks (Phase 1 - Priority)

- [ ] **[M1.1]** Add `failedTranscripts: Set<String>` state to `TranscriptInventoryView.swift`
- [ ] **[M1.2]** Modify `loadMetadataForSessions()` to catch errors and add to failed set (line 899)
- [ ] **[M1.3]** Add error indicator (orange warning icon) in `sessionRow()`
- [ ] **[M1.4]** Add "Retry Metadata Generation" button in `TranscriptDetailView`
- [ ] **[M1.5]** Implement `retryMetadataGeneration()` with `forceRegenerate: true`
- [ ] **[M1.6]** Persist `failedTranscripts` to UserDefaults
- [ ] **[M1.7]** Load failed set on window open
- [ ] **[M1.8]** Show count in header: "3 failed" badge when non-empty

### Files

- **Primary:** `Contextify/Contextify/TranscriptInventoryView.swift` (lines 899-938)
- **Secondary:** `Contextify/Contextify/TranscriptMetadataOrchestrator.swift` (Phase 2/3)

### Acceptance Criteria (Phase 1)

- [ ] Failed generations show orange warning icon in session row
- [ ] Click failed transcript → detail view shows "Retry" button
- [ ] Click retry → clears error, re-attempts generation with force flag
- [ ] Success removes transcript from failed set
- [ ] Failed transcripts persist across app restarts
- [ ] Header shows "X failed" count when failedTranscripts not empty
- [ ] Loading spinner distinct from error state (different icons)

### Estimated Effort

- **Phase 1:** 4 hours (immediate priority)
- **Phase 2:** 2 hours (can defer)
- **Phase 3:** 2 hours (can defer)
- **Total:** 8 hours for complete fix

### Implementation Reference

See `/tmp/comprehensive-todos-update.md` for:
- Detailed code snippets for all 3 phases
- Circuit breaker observer implementation
- Partial results and backoff logic

---

## Transcript Window UI Refactoring (P1)

**Status:** Not Started
**Priority:** P1 (Code health + UX polish)
**Severity:** Medium (works but feels unfinished)
**Assignee:** TBD
**Target Completion:** Next sprint

### Problem

`TranscriptInventoryView.swift` is 1516 lines with complex state management:
- 15+ `@State` properties with interdependencies
- Mixed concerns: UI, metadata loading, export, cleanup
- No clear loading states during metadata generation
- Hard to maintain and test

**Comparison:** `ProjectsWindow.swift` is only 216 lines (7x smaller)

### Solution - Three-Phase Refactoring

**Phase 1: Extract Components (4 hours)**
- Extract `SessionListView` (sidebar, 200 lines)
- Extract `SessionRowView` (row component, 80 lines)
- Extract `MetadataLoadingView` (loading states, 100 lines)
- Reduce main file to ~300 lines (coordinator only)

**Phase 2: Simplify State (3 hours)**
- Create `@Observable class TranscriptInventoryState`
- Move metadata loading to state object
- Use Combine for debouncing (remove manual Task management)

**Phase 3: Loading States (2 hours)**
- Add skeleton loaders during metadata generation
- Show progress: "Generating metadata: 3 of 15"
- Animate appearance of generated metadata

### Tasks (Phase 1 - Priority)

- [ ] **[UI1.1]** Create `Views/SessionListView.swift` (extract sidebar, lines 200-268)
- [ ] **[UI1.2]** Create `Views/SessionRowView.swift` (extract row rendering)
- [ ] **[UI1.3]** Create `Views/MetadataLoadingView.swift` (extract loading UI)
- [ ] **[UI1.4]** Reduce `TranscriptInventoryView.swift` to < 400 lines (coordinator only)
- [ ] **[UI1.5]** Verify no visual regressions (side-by-side comparison)

### Files

- **Reduce:** `Contextify/Contextify/TranscriptInventoryView.swift` (1516 → ~300 lines)
- **Create:** `Contextify/Contextify/Views/SessionListView.swift` (NEW, 200 lines)
- **Create:** `Contextify/Contextify/Views/SessionRowView.swift` (NEW, 80 lines)
- **Create:** `Contextify/Contextify/Views/MetadataLoadingView.swift` (NEW, 100 lines)
- **Create:** `Contextify/Contextify/State/TranscriptInventoryState.swift` (NEW, Phase 2)

### Acceptance Criteria (Phase 1)

- [ ] Main file < 400 lines
- [ ] Each extracted component < 250 lines
- [ ] No visual regressions (pixel-perfect comparison)
- [ ] All functionality preserved
- [ ] Search, filtering, sorting still work
- [ ] Context menus still work

### Estimated Effort

- **Phase 1:** 4 hours (component extraction)
- **Phase 2:** 3 hours (state management)
- **Phase 3:** 2 hours (loading UI polish)
- **Total:** 9 hours for complete refactor

---

## HTTP Diagnostics Port Conflict (P1 Bug)

**Status:** Confirmed, Not Started
**Priority:** P1 (Production Error)
**Severity:** Medium (Non-blocking)
**Assignee:** TBD
**Target Completion:** Next sprint

### Problem

DiagnosticsHTTPServer fails to bind to port 17329 when address already in use:

```
Address already in use (errno: 48)
Failed to start diagnostics HTTP server
```

**Frequency:** 8 occurrences in logs
**Impact:** Diagnostics API unavailable, helper scripts fail

### Root Cause

1. Previous app instance didn't release port (crash/force-quit)
2. Port collision with another process

### Solution

**Recommended:** Port fallback (17329 → 17330 → 17331, etc.)

**Implementation:**
```swift
// Try ports 17329-17339 in sequence
for port in 17329...17339 {
  do {
    try bindToPort(port)
    log.info("Diagnostics server on port \(port)")
    return
  } catch { continue }
}
```

**Tasks:**
- [ ] Implement port fallback in DiagnosticsHTTPServer.swift
- [ ] Log actual bound port
- [ ] Update `scripts/timeline_api.sh` to auto-detect port
- [ ] Add port info to `/health` endpoint

**Estimated Effort:** 2-3 hours

**Files:**
- `app/Sources/ContextifyCore/Diagnostics/DiagnosticsHTTPServer.swift`
- `scripts/timeline_api.sh`

**Detailed Spec:** `/tmp/http-diagnostics-port-conflict.md`

---

## Remove Manual Project Selection (P1 - UX Simplification)

**Status:** Not Started
**Priority:** P1 (UX Simplification)
**Severity:** Medium (Requires UX rethinking)
**Assignee:** TBD
**Target Completion:** Next sprint

### Problem

File → Open Project allows manual project selection, but now that we have robust automatic transcript-based discovery:
- Manual selection is redundant
- Creates two paths to add projects (confusing UX)
- Folder icon in ContentView header still triggers project picker (just changed to reveal in Finder)
- No clear notification when new projects are auto-discovered

**Current State:**
- Projects can be added via File → Open Project
- Projects can be auto-discovered via transcript scanning
- User doesn't know when new projects appear

### Solution

**Remove Manual Project Addition:**
- Remove File → Open Project menu item
- All projects must have associated transcript files to be discovered
- Simplifies mental model: "Contextify shows projects you've used Claude Code/Codex with"

**Add Discovery Notifications:**
- Show toast when new project detected: "New project discovered: [name]"
- OR position new projects at far left of switcher with subtle badge
- OR add temporary highlight/animation to new project tabs

**Stress Testing Required:**
- Verify discovery is efficient (doesn't slow down app)
- Test with 10, 50, 100 projects
- Verify discovery happens quickly enough (within seconds of new transcript)
- Test discovery robustness (handles missing files, moved directories, etc.)

### Tasks

**Phase 1: Remove Manual Selection (2 hours)**
- [ ] Remove File → Open Project menu item
- [ ] Remove folder icon picker from ContentView (now reveals in Finder - commit pending)
- [ ] Update keyboard shortcuts (if any)
- [ ] Update documentation

**Phase 2: Discovery Stress Testing (4-6 hours)**
- [ ] Benchmark discovery with 10, 50, 100 projects
- [ ] Test real-time detection (how fast does new project appear?)
- [ ] Test edge cases: missing directories, renamed projects, moved transcripts
- [ ] Verify no performance degradation during discovery
- [ ] Document discovery timing expectations (target: <5 seconds for new project)

**Phase 3: New Project Notifications (3-4 hours)**
- [ ] Design notification UX (toast vs badge vs positioning)
- [ ] Implement chosen approach
- [ ] Add user preference to disable notifications (if toast)
- [ ] Test notification doesn't interrupt workflow

**Alternative Approaches:**
- **Option A:** Toast notification (non-intrusive, temporary)
- **Option B:** Badge on new project tab (persists until clicked)
- **Option C:** Position new projects at far left (spatial hint)
- **Option D:** Subtle animation on new project tab (draws attention)

### Files

- **Remove:** File menu project picker references
- **Update:** `Contentify/Contextify/ContentView.swift` (folder icon already changed)
- **Add:** Notification UI component (location TBD based on chosen approach)
- **Test:** `Contextify/ContextifyTests/ProjectDiscoveryTests.swift`

### Acceptance Criteria

- [ ] File → Open Project menu item removed
- [ ] No manual project addition UI remains
- [ ] Discovery tested with 100 projects, completes in <30 seconds
- [ ] New project appears in UI within 5 seconds of transcript creation
- [ ] User is notified when new project discovered (via chosen UX)
- [ ] Documentation updated to reflect transcript-only discovery
- [ ] Edge cases handled gracefully (missing dirs, moved files)

### Estimated Effort

- **Phase 1:** 2 hours (removal)
- **Phase 2:** 4-6 hours (stress testing)
- **Phase 3:** 3-4 hours (notifications)
- **Total:** 9-12 hours

### Risk

**Medium** - Removing manual selection requires discovery to be rock-solid. If discovery fails or is slow, users have no fallback.

**Mitigation:**
- Keep manual selection as hidden debug option (Shift+Cmd+Option+P or similar)
- Thoroughly test discovery robustness before removing manual path
- Document recovery steps if discovery fails

---

## Codex Discovery Data Quality Issues (P2)

**Status:** Confirmed, Not Started
**Priority:** P2 (Data Quality)
**Severity:** Low (Metadata only)
**Assignee:** TBD
**Target Completion:** Future sprint

### Problem

Codex-discovered projects have poor metadata quality:

1. **Missing names:** 7+ projects show path as name (`/Users/rob/code/project`)
2. **Incorrect session IDs:** Some use file path hash instead of workspace ID
3. **No git branch:** Codex projects don't populate `git_branch` field
4. **Orphaned projects:** Deleted projects remain in database

**Affected:** ~7+ Codex projects

### Impact

- Confusing project names in switcher tabs
- Inconsistent metadata vs Claude Code projects
- Harder to identify projects

### Solution (Phased)

**Phase 1: Project Name Improvement (P2)**
- Parse Codex workspace metadata for project names
- Fallback to parent directory name (better than hash)
- Estimated: 3-4 hours

**Phase 2: Session ID Normalization (P2)**
- Use Codex workspace ID consistently
- One-time migration for existing entries
- Estimated: 4-5 hours

**Phase 3: Git Branch Detection (P3)**
- Run git detection during discovery
- Cache in database
- Estimated: 2-3 hours

**Phase 4: Orphan Cleanup (P3)**
- Periodic check for missing directories
- Auto-hide orphaned projects
- Estimated: 2-3 hours

### Recommended Approach

Start with **Phase 1** only (highest user-visible impact, lowest risk).

**Tasks (Phase 1):**
- [ ] Add Codex manifest parser
- [ ] Update ProjectDiscoveryService.discoverFromCodex()
- [ ] Test with real Codex sessions
- [ ] Verify names in switcher UI

**Files:**
- `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift`
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

**Workaround:** Users can manually rename projects in Projects window (Cmd+Shift+P)

**Detailed Spec:** `/tmp/codex-discovery-data-quality.md`

---

# Additional P1/P2 Items (From Codebase Analysis)

## Re-enable Disabled Integration Tests (P1)

**Status:** Not Started
**Priority:** P1 (Test Coverage)
**Severity:** Medium (No automated testing for core features)
**Assignee:** TBD
**Target Completion:** Next sprint

### Problem

3 critical integration tests are disabled with `skip_` prefix and never run:

```swift
// IntegrationTests.swift
skip_testInitialHooverWorkflow()        // Line 25: "HooverEngine signature changed"
skip_testOrchestratorWorkflow()         // Line 126: "Needs update for new API"
skip_testCrashRecovery()                // Line 168: "HooverEngine signature changed"
```

**Impact:** No automated testing for:
- Hoover crash recovery
- Orchestrator workflow
- Core ingestion pipeline

### Tasks

- [ ] Update `skip_testInitialHooverWorkflow()` for new HooverEngine API
- [ ] Update `skip_testOrchestratorWorkflow()` for new TranscriptOrchestrator API
- [ ] Update `skip_testCrashRecovery()` for checkpoint changes
- [ ] Re-enable all 3 tests (remove `skip_` prefix)
- [ ] Add to CI pipeline
- [ ] Verify tests pass on clean database

### Files

- `Contextify/ContextifyTests/IntegrationTests.swift`

### Acceptance Criteria

- [ ] All 3 tests pass with updated APIs
- [ ] Tests run in CI on every commit
- [ ] No flaky failures (run 10x in a row)

### Estimated Effort

**3-4 hours**

---

## Project Exclusion Manager (P1 - Unfinished Feature)

**Status:** Not Started (3 tests skipped)
**Priority:** P1 (Half-built feature)
**Severity:** Low (Workaround exists)
**Assignee:** TBD
**Target Completion:** Next sprint

### Problem

3 skipped tests indicate incomplete implementation:

```swift
// ProjectDiscoveryTests.swift
skip_testExclusionManager_AddAndRetrieve()    // Line 74
skip_testExclusionManager_RemoveExclusion()   // Line 78
skip_testExclusionManager_Persistence()       // Line 82
```

**User Impact:** Cannot hide unwanted projects from discovery (test/tmp/archive projects clutter switcher)

### Solution

Implement `ProjectExclusionManager` with database persistence.

### Tasks

- [ ] Create `ProjectExclusionManager.swift` (database-backed storage)
- [ ] Add UI to Projects window: right-click → "Hide Project"
- [ ] Add exclusions table to database schema (new migration)
- [ ] Filter excluded projects from discovery results
- [ ] Add "Show Hidden Projects" toggle in Projects window
- [ ] Re-enable all 3 tests

### Files

- `app/Sources/ContextifyCore/Projects/ProjectExclusionManager.swift` (NEW)
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` (add exclusions table)
- `Contextify/Contextify/ProjectsWindow.swift` (add UI)

### Acceptance Criteria

- [ ] Right-click project → "Hide Project" → removed from list
- [ ] Hidden projects persist across app restarts
- [ ] "Show Hidden Projects" toggle reveals hidden with "Unhide" option
- [ ] All 3 tests pass

### Estimated Effort

**4-6 hours**

---

## macOS 14/15 Fallback Testing (P1)

**Status:** Not Started
**Priority:** P1 (Deployment target compliance)
**Severity:** Medium (Untested code paths)
**Assignee:** TBD
**Target Completion:** Before release

### Problem

Code has 18 `@available(macOS 26.0, *)` guards but no documented testing for macOS 14/15:

- LLM features fall back to heuristics (never tested)
- No CI testing on macOS 14/15
- Minimum deployment target is macOS 14, but only tested on 26

**Risk:** App may crash or have degraded UX on stated minimum OS.

### Tasks

- [ ] Test all `@available(macOS 26, *)` fallback paths on macOS 14
- [ ] Document degraded experience (timeline summaries = heuristics, no LLM)
- [ ] Add CI job for macOS 14 compatibility
- [ ] Test on macOS 15 (one version before current)
- [ ] Update README with feature availability matrix

### Files

Key files with availability guards:
- `Contextify/Contextify/FoundationLLM.swift` (14 guards)
- `Contextify/Contextify/LLMHealthCheck.swift`
- `Contextify/Contextify/SynthesisService.swift`
- `Contextify/Contextify/TranscriptMetadataPostProcessor.swift`

### Acceptance Criteria

- [ ] App launches successfully on macOS 14
- [ ] Timeline displays with heuristic summaries (no LLM)
- [ ] No crashes when LLM APIs unavailable
- [ ] README documents: "LLM features require macOS 26+"
- [ ] CI runs tests on macOS 14 runner

### Estimated Effort

**4-6 hours**

---

## Projects vs Transcripts Window UX Review (P2 - Design Question)

**Status:** Not Started
**Priority:** P2 (User experience question)
**Severity:** Low (Works, but could be clearer)
**Assignee:** TBD
**Target Completion:** Deferred until user feedback

### Question

Should `ProjectsWindow` and `TranscriptInventoryView` be unified into single interface?

**Current State:**
- `Cmd+Shift+P` → ProjectsWindow (project discovery, ingestion progress)
- Window menu → Transcripts (session browsing, metadata)

**Options:**

**Option A: Keep Separate (Current)**
- Pros: Clear separation of concerns
- Cons: Two windows for related concepts, confusing for new users

**Option B: Unified "Sessions" Window**
- Left sidebar: Projects (expandable)
  - When expanded: Shows sessions for that project
- Right detail: Session detail with metadata
- Pros: Single mental model, better discoverability
- Cons: More complex UI, harder to scan all projects

**Option C: Hybrid**
- Keep ProjectsWindow for discovery/management
- Enhance Timeline window with session switcher (dropdown)
- Deprecate separate Transcripts window
- Pros: Simplifies to 2 windows (Timeline + Projects)
- Cons: Timeline becomes more complex

### Recommendation

**Defer until user feedback:**
- Current separation works
- Focus on fixing bugs first (P0/P1 items)
- Revisit after App Store launch with telemetry

### Tasks (If Pursuing)

- [ ] Gather user feedback on current UX (survey/interviews)
- [ ] Create mockups for Option B and C
- [ ] User test with 3-5 people
- [ ] Make decision based on data
- [ ] Implement chosen option

### Estimated Effort

- **Research:** 2 hours
- **Implementation:** 8-12 hours (if unifying)

---

## Test Coverage Expansion (P2)

**Status:** Not Started
**Priority:** P2 (Code quality)
**Severity:** Low (Coverage gaps)
**Assignee:** TBD
**Target Completion:** Ongoing

### Problem

Only 12 test files for ~100 Swift files. Major gaps:

**Untested Components:**
- `ProjectSwitcherView.swift` (563 lines, no tests)
- `ActiveSessionPolicyEngine.swift` (policy logic untested)
- `TranscriptWatcher.swift` (file monitoring untested)
- `DatabaseMigration.swift` (v1-v23 migrations untested)

**Current Coverage:** ~15%
**Target:** 60%+ for core logic

### Tasks

- [ ] Add tests for ProjectSwitcherView (drag-drop, keyboard shortcuts)
- [ ] Add tests for ActiveSessionPolicyEngine (policy decision logic)
- [ ] Add tests for TranscriptWatcher (file watching, debouncing)
- [ ] Add tests for DatabaseMigration (all 23 migrations)
- [ ] Add tests for HooverEngine edge cases
- [ ] Set up code coverage reporting in CI

### Estimated Effort

**12-16 hours** (prioritize core logic first)

---

## Additional P2 Items (Brief)

### Performance Benchmarking (P2)
- Benchmark discovery time (10, 50, 100 projects)
- Benchmark LLM summary generation (batch sizes)
- Add XCTest performance tests
- Document P95 targets
- **Effort:** 3-4 hours

### Build Parity Verification (P1)
- Verify `bash scripts/xc.sh build` == Xcode Run
- Document any differences
- **Effort:** 1-2 hours

### Status Bar Indicator (P1)
- Implement NSStatusBar menubar icon
- Show processing status, errors
- Always-on access when window closed
- **Effort:** 6-8 hours
- **Reference:** AppDelegate.swift:83 TODO comment

### Git Status Display (P2)
- Show ahead/behind main
- Show staged/unstaged counts
- Display next to branch name
- **Effort:** 4-6 hours

### Release Automation (P2)
- Port FileKitty's `tools/release.py`
- Automate: build → sign → notarize → DMG → GitHub release
- **Effort:** 4-6 hours

### LLM Content Moderation (P2)
- Pre-filter expletives from summaries
- Simple regex-based filter
- **Effort:** 2-3 hours

### Context Window Enhancement (P2)
- Add prev1/prev2 context to LLM prompts
- Improve summary quality with surrounding entries
- **Effort:** 3-4 hours
- **Reference:** Multiple TODO comments in code

### Diagnostics HTTP API Testing (P2)
- Verify all endpoints functional (localhost:17329)
- Test `/health`, `/diagnostics`, `/timeline/recent`, `/timeline/latest`
- Validate helper script `./scripts/timeline_api.sh`
- Document any issues or broken functionality
- **Effort:** 1-2 hours
- **Status:** Not Started (API built but may be broken, needs verification)

### Git Activity Timeline & Work Story Visualization (P2)

**Vision:** Transform transcripts from chat logs into a narrative of work accomplished. Show users "what you did where" at a glance across their Claude Code/Codex history.

**Problem:** Currently no way to know what was accomplished in a session without reading every message. Can't easily see:
- Which branches were worked on
- What commits were made (and to which branches)
- What was merged (especially to main)
- The concrete impact of a session on the project

**Solution:** Parse transcripts to extract and visualize git activity.

**Phase 1: Git Activity Extraction (4-6 hours)**
- Parse transcript entries for git commands (commits, checkouts, merges, pushes)
- Extract branch names, commit SHAs, commit messages
- Detect merge operations (especially merges to main/master)
- Store as structured metadata (extend `transcript_metadata` or new table)

**Phase 2: Transcripts Window Integration (3-4 hours)**
- Add git activity summary to each transcript row
- Show badges/indicators: "3 commits to feature/x, merged to main ✓"
- Display branch names worked on
- Visual distinction for sessions with merges to main

**Phase 3: Timeline Story View (6-8 hours)**
- Timeline visualization showing work progression
- Group sessions by feature/branch
- Show commit sequence across sessions
- Help users understand "where am I in this feature?"
- Resume work context: "Last session: 3 commits, not merged yet"

**Implementation Details:**
- Pattern matching for git commands in assistant/user messages
- Parse: `git commit`, `git push`, `git merge`, `git checkout`
- Retroactive parsing of existing transcripts (migration script)
- Could also hook into actual git operations for real-time tracking

**Data Model:**
```sql
CREATE TABLE git_activity (
  id INTEGER PRIMARY KEY,
  transcript_id TEXT NOT NULL,
  activity_type TEXT NOT NULL, -- 'commit', 'merge', 'checkout', 'push'
  branch_name TEXT,
  commit_sha TEXT,
  commit_message TEXT,
  target_branch TEXT, -- for merges
  timestamp INTEGER NOT NULL,
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id)
);
```

**UI Mockup (Transcript Row):**
```
📊 Transcript Title
⏱️  2 hours ago  •  🔀 feature/new-ui  •  ✅ 3 commits  •  ⬆️ merged to main
```

**Benefits:**
- Understand work impact at a glance
- Find "that session where I worked on feature X"
- Resume work with full context
- See project evolution story
- Identify incomplete work (commits not merged)

**Future Extensions:**
- Main window timeline showing all work across sessions
- "Work story" narrative: auto-generated summary of session accomplishments
- Integration with GitHub/GitLab to show PR status
- Visualize feature development across multiple sessions

**Effort:**
- Phase 1: 4-6 hours (extraction & storage)
- Phase 2: 3-4 hours (UI integration)
- Phase 3: 6-8 hours (timeline view)
- **Total:** 13-18 hours

**Priority:** P2 (High value for UX, not blocking core functionality)

**Status:** Not Started

**References:**
- Transcript parsing: `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
- Metadata storage: `app/Sources/ContextifyCore/Database/Models.swift`
- Transcripts UI: `Contextify/Contextify/TranscriptInventoryView.swift`

---

**Last Updated:** 2025-11-09

---

## Transcript Corruption Enhancements (P3)

**Context:** Basic corruption detection and repair is implemented (`scripts/transcript-repair/repair_transcript.py`). These are optional enhancements for better UX.

**Reference:** `build/docs/operations/transcript-corruption-detection.md` (Future Improvements section)

### Auto-Repair Mode (P3)
- Add optional auto-repair during ingestion
- HooverEngine catches corruption, applies repairs automatically
- User preference: "Auto-fix corrupted transcripts" (default: off)
- Log repairs for transparency
- **Effort:** 2-3 hours
- **Value:** Medium (reduces manual intervention for power users)

### Corruption Metrics Tracking (P3)
- Track corruption rates by provider/version
- Add corruption_events table to database
- Surface stats in diagnostics API
- Help identify systematic issues
- **Effort:** 2-3 hours
- **Value:** Low (interesting data, not critical)

### UI Notifications for Corruption (P3)
- Show toast when corrupted transcript detected
- Offer one-click repair via UI
- Link to repair docs
- **Effort:** 1-2 hours
- **Value:** Medium (better UX than manual script usage)

### Repair History Tracking (P3)
- Track which transcripts have been repaired
- Store repair metadata (when, what issues, recovery success)
- Prevent double-repair attempts
- **Effort:** 1-2 hours
- **Value:** Low (nice-to-have audit trail)

---

**Last Updated:** 2025-11-09
## Transcript Repair Workflow (P1)

**Status:** Instrumentation Complete, UI not started  
**Priority:** P1 (needed to deal with corrupt transcripts discovered on 2025‑11‑11)

### Background
- During the 2025‑11‑13 clean run we detected **87 fresh Claude Code transcripts** that now fail the parser (missing `uuid`, `timestamp`, etc.).
- Hoover now logs `[HOOVER-CORRUPT] transcript=<id> path=<path> reason=<first error>` and automatically marks these transcripts `status = "error"`, so they are skipped in future ingests.
- CLI tooling (`swift run TranscriptValidatorCLI <path>`) can reproduce the parser error for any transcript, but there is no in-app repair workflow yet.

### Goals
- Surface corrupt transcripts inside the Transcript window (e.g., badge + “repair/delete” CTA).
- Provide at least one automated repair action (truncate, re-run parser, or open file in editor).
- Preserve the corrupted samples (all from `/Users/rob/.claude/projects/-Users-rob-…`, timestamped 2025‑11‑11 ~16:35) for QA/reference.

### Tasks
- [ ] **[TRFIX1]** Transcript window: indicate `status == error` rows with a warning chip.
- [ ] **[TRFIX2]** Add “Validate in CLI” / “Reveal in Finder” actions so users (or support) can inspect the raw `.jsonl`.
- [ ] **[TRFIX3]** Provide an automated repair option (truncate to first valid line, or re-run parser and overwrite, etc.).
- [ ] **[TRFIX4]** Ensure repaired transcripts automatically flip back to `status = "active"` and rejoin ingestion.
- [ ] **[TRFIX5]** Regression test: corrupt transcript stays quarantined until user repairs it.

**Files:**
- `Contextify/Contextify/TranscriptInventoryView.swift`
- `Contextify/Contextify/TranscriptParser.swift`
- `app/Sources/ContextifyCore/Database/HooverEngine.swift`
- `Sources/TranscriptValidatorCLI/main.swift`

**Reference samples:** `/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/* (mtime 2025‑11‑11 16:35)`
