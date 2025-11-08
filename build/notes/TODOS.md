# High-Priority TODOs

**Status:** Active
**Last Updated:** 2025-11-05
**Priority Level:** P0 (Blocking release)

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

**Last Updated:** 2025-11-08
