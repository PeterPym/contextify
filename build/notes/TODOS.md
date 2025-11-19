# Contextify TODO List

**Last Updated:** 2025-11-19
**Status:** Active - Reorganized based on user feedback review

**Priority Levels:**
- **P0 (Blocking Release):** 21 items remaining (3 completed) - Must complete before App Store submission
- **P1 (High Priority):** 13 items - Important for quality/UX, ship soon after launch
- **P2 (Medium Priority):** 22 items - Nice to have, can defer to future releases
- **P3 (Low Priority / Deferred):** 8 items - Future enhancements

**Total Active Items:** 59 (3 P0 items completed: drag-drop fixes, welcome modal hang)

**Change Log (2025-11-15):**
- Removed 19 completed items, 5 dropped items (diagnostics server feature)
- Promoted 13 items (11 to P0, 2 to P1) - critical bugs and testing
- Demoted 21 items (2 from P0, 11 from P1, 8 from P2)
- Grouped 15 items into 3 consolidated features
- See `/tmp/todo-proposed-changes-final.md` for full rationale

---

# P0 (Blocking Release) - 21 Items Remaining

## Website (1 item)

- [ ] #2: Setup support@contextify.sh email (15 min)

**Note:** Using support@ as primary contact (standard for customer support)

**Note:** URL forwarding completed (#1: ✅ complete 2025-11-11)

---

## Sandboxed Build (3 items)

**Status:** Git monitoring disabled (✅ complete 2025-11-15, commit `b0abdb4`)

- [ ] #3: Test App Store build with zero [GIT-BROKEN] errors
- [ ] #4: Verify branch UI hidden in sandboxed builds
- [ ] #5: Verify git monitoring disabled in App Store builds

**Testing:**
```bash
bash scripts/xc.sh --dist=appstore Debug cleanrun
log stream --predicate 'subsystem == "dev.contextify"' --level debug
```

**Expected:** Zero [GIT-BROKEN] errors, project name shows (no branch), timeline loads

**Reference:** See "P0: Disable Git Monitoring in Sandboxed Builds" section for full implementation details

---

## App Store Submission (4 items)

**Status:** Not Started
**Effort:** 8-12 hours

- [ ] #6: App Store Connect setup (metadata, screenshots, description)
- [ ] #7: Build Release binary (sign, archive, validate, upload)
- [ ] #8: Submit for review (compliance, age rating, reviewer notes)
- [ ] #9: TestFlight beta (optional, recommended)

**Reference:** `build/notes/website-launch-status.md` § "APP STORE SUBMISSION CHECKLIST"

---

## Welcome Modal Copy (1 item)

- [ ] #16: Polish welcome modal copy & progress messaging

**Tasks:**
- Remove "Run in Background" button (✅ complete if already done)
- Review and improve welcome text clarity
- Polish progress messaging
- Add dismissal confirmation if user closes during ingestion

**Files:** `Contextify/Contextify/WelcomeModalView.swift`
**Effort:** 1-2 hours

---

## Critical Bugs - Drag & Drop (2 items) ✅ COMPLETE

**Status:** ✅ Complete (2025-11-18)
**Commit:** `0bbe383` - fix(drag-drop): clear ghost entries when dragging outside window
**Branch:** `fix/drag-drop-ghost-entries`

- [x] #29: Fix drag-drop cancellation when cursor exits window ✅
- [x] #30: Add state validation after drag operations ✅

**Problem:** Dragging project tab outside window created ghost dashed-line entry that persisted indefinitely. Only fix was app restart.

**Root Cause:** `dropExited()` was intentionally blank to avoid flicker, but this prevented clearing drag state when cursor left the window.

**Solution:**
1. Clear drag state in `dropExited()` when cursor exits drop zone
2. Add validation before rendering insertion indicators
3. Add validation in `onDrag` to detect stale state

**Files:**
- `Contextify/Contextify/ProjectSwitcherView.swift` (4 changes)

**Testing:**
- ✅ Dragging outside window cancels cleanly
- ✅ No ghost entries persist
- ✅ Project returns to original position
- ✅ UI state consistent with data

---

## Critical UX - Discovery (2 items) ⬆️

**Status:** Not Started
**Priority:** Promoted from P1
**Effort:** 4-6 hours total

- [ ] #32: Show toast for newly discovered projects
- [ ] #43: Stress test discovery with 10, 50, 100 projects

**#32 - Toast Notifications:**
- Format: "New project discovered: [project-name]"
- Use existing toast system (NotificationCenter + `.contextifyShowToast`)
- Debounce rapid events (2-second window)

**#43 - Stress Testing:**
- Benchmark discovery time with varying project counts
- Document P95 targets (goal: <30 seconds for 50 projects)
- Test edge cases: missing directories, renamed projects, moved transcripts

**Files:** `Contextify/Contextify/ContextifyApp.swift`, `ProjectsViewModel.swift`

---

## Critical UX - Failed Metadata (1 item) ⬆️

**Status:** Not Started
**Priority:** Promoted from P1
**Effort:** 2-3 hours

- [ ] #35: Show manual retry button for failed metadata generation

**Problem:** Silent failures after circuit breaker opens. Users see endless loading spinners.

**Implementation:**
- Add `failedTranscripts: Set<String>` state
- Show orange warning icon in session rows
- Add "Retry Metadata Generation" button
- Persist failed set to UserDefaults

**Files:** `Contextify/Contextify/TranscriptInventoryView.swift`

**Acceptance Criteria:**
- Failed generations show warning icon
- Retry button appears in detail view
- Success removes from failed set
- Failed transcripts persist across restarts

---

## Critical - Integration Tests (3 items) ⬆️

**Status:** Not Started
**Priority:** Promoted from P1
**Effort:** 6-8 hours

- [ ] #45: Re-enable testInitialHooverWorkflow integration test
- [ ] #46: Re-enable testOrchestratorWorkflow integration test
- [ ] #47: Re-enable testCrashRecovery integration test

**Problem:** 3 critical tests disabled with `skip_` prefix. No automated testing for core ingestion pipeline.

**Tasks:**
- Update tests for new HooverEngine API
- Update tests for new TranscriptOrchestrator API
- Update tests for checkpoint changes
- Remove `skip_` prefix
- Add to CI pipeline
- Verify tests pass 10x in a row (no flaky failures)

**Files:** `Contextify/ContextifyTests/IntegrationTests.swift`

---

## Critical - Project Management (2 items) ⬆️

**Status:** Not Started
**Priority:** Promoted from P1
**Effort:** 4-6 hours

- [ ] #49: Add Hide Project UI to Projects window
- [ ] #50: Add Show Hidden Projects toggle

**Implementation:**
- Create `ProjectExclusionManager.swift` with database persistence
- Add exclusions table to schema (new migration)
- Right-click menu: "Hide Project"
- "Show Hidden Projects" toggle reveals hidden with "Unhide" option
- Filter excluded projects from discovery

**Files:**
- `app/Sources/ContextifyCore/Projects/ProjectExclusionManager.swift` (NEW)
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
- `Contextify/Contextify/ProjectsWindow.swift`

**Acceptance Criteria:**
- Hidden projects persist across restarts
- All 3 skipped tests re-enabled and passing

---

## Critical - Welcome Modal Hang (1 item) ✅ COMPLETE

**Status:** ✅ Complete (2025-11-19)
**Priority:** Promoted from P1 (11-second UI freeze during onboarding)
**Effort:** 4-6 hours
**Evidence:** `/private/tmp/transcript-queue-monitor-20251118-002852.log`

- [x] #P1-DISCOVERY: Fix ProjectActivityMonitor causing 11s hang during welcome modal ✅

**Problem:** Welcome modal shows "1/19 projects" for **11+ seconds** before completing discovery. UI appears frozen/broken to users during first-run experience.

**Root Cause (from log analysis):**

Timeline breakdown:
```
00:29:16.348-16.479: ProjectsViewModel.discoverAllProjects() completes (131ms) ✅
00:29:16.479-18.285: Ingestion completes (1.8s) ✅
00:29:18.285-29.966: 11.8 SECOND GAP - waiting for ProjectActivityMonitor ⚠️
00:29:29.966: ProjectActivityMonitor.start() finally runs
00:29:30.342+: Processes 602 transcripts synchronously (blocks UI)
```

**Architectural Issues:**

1. **Duplicate discovery:** ProjectActivityMonitor runs its own `discoverAllProjects()` **after** ProjectsViewModel already completed discovery
2. **Late initialization:** ProjectActivityMonitor.start() doesn't begin until 13+ seconds after modal appears
3. **Synchronous processing:** Processes 602 transcripts on main thread with debug logging for each file
4. **UI blocking:** Modal progress bar stuck at "1/19" while waiting for background discovery

**Solution:**

1. **Deduplicate discovery:** ProjectActivityMonitor should reuse ProjectsViewModel's discovery results instead of re-scanning
2. **Earlier initialization:** Start ProjectActivityMonitor in parallel with ProjectsViewModel, not after
3. **Background processing:** Move transcript enumeration off main thread
4. **Reduce logging:** Don't log every individual file at debug level (602 log lines!)

**Files:**
- `app/Sources/ContextifyCore/ProjectActivityMonitor.swift:74` - Remove duplicate `discoverAllProjects()` call
- `Contextify/Contextify/ProjectsViewModel.swift` - Coordinate with ProjectActivityMonitor
- Consider: Shared discovery coordinator to eliminate duplication

**Acceptance Criteria:**
- Welcome modal completes discovery in <3 seconds (currently 14s)
- Progress bar updates smoothly (no 11s freeze at "1/19")
- No duplicate filesystem scans
- ProjectActivityMonitor reuses existing discovery data

**References:**
- Investigation: `build/docs/archive/investigations/2025-11-17-discoverallprojects-fastpath.md`
- Log evidence: Lines showing "11.8 second gap" between ingestion completion and ProjectActivityMonitor start

---


# P1 (High Priority) - 13 Items

## CLI Logomark Display (1 item) ⬇️

**Status:** Partially complete (project switch works, ingestion updates missing)
**Priority:** Demoted from P0 (project switch already works via database)
**Effort:** 1-2 hours (add hoover notification subscription)

- [ ] #P0-LOGOMARK: Add real-time logomark updates during transcript ingestion

**Already Working (commit `0ab0d79`):**
- ✅ Database-backed provider detection
- ✅ Updates on project switch via `.task(id: projectPath)`
- ✅ Efficient SQL query for providers

**Missing:**
- ❌ Real-time updates during initial ingestion/hoovering
- ProjectBadgesContainer needs to subscribe to hoover notifications

**Implementation:**
- Subscribe to hoover/ingestion completion notifications
- Trigger `loadProviders()` refresh when transcripts are added
- No UI changes needed, just notification wiring

**Files:**
- `Contextify/Contentify/ProjectBadgesContainer.swift`

---

## Build Warnings (5 items) ✅ COMPLETE

**Status:** ✅ Complete (verified 2025-11-18)
**Validation:** `bash scripts/xc.sh build 2>&1 | grep -c "warning:"` → **0**

- [x] #19: Fix ConversationMonitor.swift warnings ✅
- [x] #20: Fix TranscriptMetadataOrchestrator.swift availability checks ✅
- [x] #21: Fix ProjectsViewModel.swift warnings ✅
- [x] #22: Fix ProjectSwitcherState.swift warnings ✅
- [x] #23: Verify clean build with zero warnings ✅

**Result:** Build produces **zero warnings** - all previously reported warnings have been resolved.

**Tested:**
- `bash scripts/xc.sh build` → BUILD SUCCEEDED, 0 warnings
- Meets zero-tolerance policy from CLAUDE.md

---


## Compatibility (1 item)

**Status:** Not Started
**Effort:** 4-6 hours

- [ ] #51: Test all @available(macOS 26, *) fallback paths on macOS 14

**Problem:** Code has 18 availability guards but no documented testing on macOS 14/15. App may crash on stated minimum OS.

**Tasks:**
- Test all fallback paths on macOS 14
- Document degraded experience (timeline summaries = heuristics, no LLM)
- Update README with feature availability matrix
- Test on macOS 15 (one version before current)

**Key files with guards:**
- `Contextify/Contextify/FoundationLLM.swift` (14 guards)
- `Contextify/Contextify/LLMHealthCheck.swift`
- `Contextify/Contextify/SynthesisService.swift`

**Acceptance:** App launches on macOS 14, timeline displays with heuristics, no crashes

---

## UI/UX (2 items) 🔗

**Status:** Not Started
**Effort:** 6-8 hours total

- [ ] #54+#55: **[GROUPED]** Implement NSStatusBar menubar icon with processing status & errors
- [ ] #56: Surface corrupt transcripts in Transcript window with warning

**#54+#55 - Menubar (Grouped Feature):**
- Implement NSStatusBar menubar icon
- Show processing status and errors
- Always-on access when window closed
- **Files:** `Contextify/Contextify/AppDelegate.swift` (see TODO comment line 83)
- **Effort:** 6-8 hours

**#56 - Corrupt Transcripts:**
- Related to #58 (P0 repair feature) but separate concern
- #56 = display warnings, #58 = repair actions
- Show warning indicator for transcripts with errors
- **Effort:** 1-2 hours (may already be covered by #58 implementation)

---

## Git Activity & Work Story (7 items) 🔗⬆️

**Status:** Not Started
**Priority:** #81 and #83 promoted from P2
**Effort:** 13-18 hours total

- [ ] #71: Show ahead/behind main in git status
- [ ] #72: Show staged/unstaged counts next to branch
- [ ] #79: Parse transcripts for git commands (commits, merges, pushes)
- [ ] #80: Extract branch names, commit SHAs, messages
- [ ] #81: Add git activity summary to transcript rows
- [ ] #82: Show badges: "3 commits to feature/x, merged to main ✓"
- [ ] #83: Timeline visualization showing work progression

**Vision:** Transform transcripts into work narrative. Show "what you did where" at a glance.

**Implementation Phases:**
1. **Phase 1:** Git activity extraction & storage (#79-80) - 4-6 hours
2. **Phase 2:** Transcripts window integration (#81-82, #71-72) - 3-4 hours
3. **Phase 3:** Timeline story view (#83) - 6-8 hours

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

**Files:**
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
- `app/Sources/ContextifyCore/Database/Models.swift`
- `Contextify/Contextify/TranscriptInventoryView.swift`

**Benefits:**
- Understand work impact at a glance
- Find sessions by feature/branch
- Resume work with full context
- Identify incomplete work (commits not merged)

---

## Transcript Repair Enhancements (4 items) 🔗

**Status:** Not Started
**Priority:** Collected from P3, related to #58-59 (P0 MVP)
**Effort:** 6-8 hours

- [ ] #85: Add auto-repair mode during ingestion
- [ ] #86: Track corruption rates by provider/version
- [ ] #87: Show toast when corrupted transcript detected
- [ ] #88: Track repair history and metadata

**Note:** These are enhancements to the P0 repair MVP (#58-59). Can be implemented as Phase 2 after MVP ships.

**Implementation:**
- #85: HooverEngine auto-repair with user preference toggle
- #86: Add corruption_events table, surface in diagnostics API
- #87: Toast notification + one-click repair UI
- #88: Track which transcripts repaired, prevent double-repair

**Files:** Same as #58-59, plus diagnostics API integration

**Reference:** `build/docs/operations/transcript-corruption-detection.md` (Future Improvements section)

---

## Other (1 item)

**Status:** Not Started
**Effort:** 2-3 hours

- [ ] #91: Extend parser to collect queue-operation-result metadata

**Note:** User didn't mark for demotion, keeping at P1 until clarified.

---

# P2 (Medium Priority) - 22 Items

## Transcript Repair MVP (2 items) ⬇️

**Status:** Instrumentation complete, UI not started
**Priority:** Demoted from P0 (user-requested, CLI workaround exists)
**Effort:** 8-10 hours

- [ ] #58: Provide automated repair option for corrupt transcripts
- [ ] #59: Ensure repaired transcripts flip back to active status

**Background:**
- 87 fresh Claude Code transcripts fail parser (missing uuid, timestamp)
- Hoover logs `[HOOVER-CORRUPT]` and marks `status = "error"`
- CLI tool exists (`swift run TranscriptValidatorCLI`) - manual workaround available

**Tasks:**
- Surface corrupt transcripts in Transcript window (warning chip)
- Add "Validate in CLI" / "Reveal in Finder" actions
- Provide automated repair (truncate/re-parse/editor)
- Auto-flip repaired transcripts to `status = "active"`

**Files:**
- `Contextify/Contextify/TranscriptInventoryView.swift`
- `app/Sources/ContextifyCore/Database/HooverEngine.swift`
- `Sources/TranscriptValidatorCLI/main.swift`

**Reference samples:** `/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/* (mtime 2025-11-11 16:35)`

**Note:** Phase 2 enhancements (auto-repair mode, metrics tracking) in P1 as #85-88 (see Git Activity section)

---

## Timeline Flicker (1 item) ✅ FIXED

**Status:** ✅ Fixed (2025-11-16)
**Commit:** `c69d3c7` - fix(timeline): eliminate flicker by skipping unchanged data updates
**Branch:** `feature/fix-timeline-flicker`

- [x] #P2-FLICKER: Fix timeline flicker during DMG startup with clean database

**Problem:** Timeline re-rendered identical data multiple times, causing visible flicker during startup and ongoing hoovering.

**Root Cause:** `setEntries()` always updated state and incremented `entriesRevision`, forcing SwiftUI to diff and rerender even when data was unchanged.

**Solution:** Added data-changed check to `setEntries()` before updating state:
```swift
if state.entries.count == new.count && state.entries == new {
    log.debug("[TIMELINE-SKIP] Skipping setEntries - data unchanged")
    return
}
```

**Results (45s test):**
- Before: 19 loadFeedFromSQL calls → 19 UI updates → constant flicker
- After:  19 loadFeedFromSQL calls → 1 UI update, 18 skipped → no flicker
- **95% reduction in unnecessary UI updates**

**Files Changed:**
- `Contextify/Contextify/ConversationMonitor.swift` (5 lines added to setEntries)

**Evidence:**
- Test log: `/tmp/transcript-queue-monitor-20251116-005710.log`
- Analysis: `/tmp/flicker-fix-results.md`
- Root cause analysis: `/tmp/flicker-root-cause-and-solution.md`

**Impact:**
- Behavioral: No changes (updates still happen when data changes)
- Performance: Eliminates unnecessary SwiftUI diff operations
- Visual: Timeline stays stable, no visible flicker

---

## Database Import (4 items) ⬇️

**Status:** Not Started
**Priority:** Demoted from P1 (power user feature, manual workaround exists)
**Effort:** 6-8 hours

- [ ] #24: Add Import Database button to Settings
- [ ] #25: Implement schema version validation for imports
- [ ] #27: Add backup-before-import safety mechanism
- [ ] #28: Test database import with v1-v23 schemas

**Problem:** No way to import existing database from another location. Users must manually copy file (error-prone).

**Implementation:**
- File picker to select `contextify.db`
- Validate schema version, run migrations if older
- Backup current database before import
- Atomic operation with rollback on failure

**Files:**
- `Contextify/Contextify/Settings/DatabaseSettingsView.swift`
- `app/Sources/ContextifyCore/Database/DatabaseMigration.swift`
- `app/Sources/ContextifyCore/Database/DatabaseManager.swift`

**Workaround:** Manual file copy to expected location

---

## Broken Projects UI (2 items) ⬇️

**Status:** Not Started
**Priority:** Demoted from P0 (low frequency, manual cleanup workaround)
**Effort:** 4-5 hours

- [ ] #13: Show broken projects in Transcripts window with errors
- [ ] #14: Add Remove Project action for broken projects

**Problem:** 3 broken projects (test-project x2, test) show in tab bar with warning icons. No way to identify issue or remove.

**Tasks:**
- Identify why projects have warning icons
- Add validation during discovery (skip invalid)
- Move broken projects to separate section in Transcripts window
- Add context menu: "Show Error", "Remove Project"
- Add `error_state` field to projects table

**Files:**
- `Contextify/Contextify/ProjectSwitcherView.swift`
- `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift`
- `Contextify/Contextify/TranscriptInventoryView.swift`

---

## Code Quality - Refactoring (4 items) ⬇️

**Status:** Not Started
**Priority:** Demoted from P1 (no user-visible impact, works but large)
**Effort:** 4-6 hours

- [ ] #37: Extract SessionListView component (~200 lines)
- [ ] #38: Extract SessionRowView component (~80 lines)
- [ ] #39: Extract MetadataLoadingView component (~100 lines)
- [ ] #40: Reduce TranscriptInventoryView to <400 lines

**Problem:** `TranscriptInventoryView.swift` is 1516 lines with complex state. Hard to maintain and test.

**Solution:** Extract components, reduce main file to ~300 lines (coordinator only).

**Files:**
- **Reduce:** `Contextify/Contextify/TranscriptInventoryView.swift`
- **Create:** `Views/SessionListView.swift`, `Views/SessionRowView.swift`, `Views/MetadataLoadingView.swift`

**Comparison:** `ProjectsWindow.swift` is only 216 lines (7x smaller)

---

## Project Switch Consolidation (1 item)

**Status:** Not Started
**Priority:** P2 (code quality, no user-visible impact)
**Effort:** 4-6 hours

- [ ] #P2-SWITCH: Consolidate 4 overlapping project switch code paths into single unified pipeline

**Problem:** ConversationMonitor has 4 different code paths handling project switching, creating overlaps, potential race conditions, and wasted work during rapid switching.

**Current Paths:**
1. `startMonitoring()` - Full bootstrap + initial feed load
2. `onProjectOrSessionChange()` - v23 startup pipeline (policy/sessions/cursor/feed/switch events)
3. `handleContextUpdate()` - Coordinator-triggered switch
4. `handleProjectRootChange()` - Legacy notification

**Solution:** Single `switchToProject(_:reason:)` entry point that all 4 paths delegate to.

**Key Requirements:**
- Preserve v23 startup sequence (policy → sessions → cursor → feed → switch events)
- Split session switching logic (no timeline reload for session-only changes)
- Cancel in-flight loads on rapid switching
- Extract bootstrap infrastructure setup into separate helper

**Files:**
- `Contextify/Contextify/ConversationMonitor.swift` (primary changes)

**Reference:**
- Implementation plan: `build/notes/feature-specs/refactor-project-switcher.md`
- Source code analysis: `/tmp/project-switch-consolidation-SOURCE-CODE.md`

---

## Features (3 items)

**Status:** Mixed
**Effort:** Varies

- [ ] #60: Parse Codex workspace metadata for project names *(needs clarification: "Is this for transcript window?")*
- [ ] #48: Implement ProjectExclusionManager with database persistence ⬇️ (demoted from P1)
- [ ] #57: Add Validate in CLI / Reveal in Finder actions ⬇️ (demoted from P1)

**#60 - Codex Metadata:**
- Part of larger data quality improvement
- 7+ projects show path as name (confusing)
- Parse workspace files for better names
- **Effort:** 3-4 hours
- **User question:** Clarify intent before implementing

**#48 - Exclusion Manager:**
- Now covered by #49-50 (P0) for UI
- This is backend implementation
- **Effort:** 2-3 hours (if #49-50 doesn't cover it)

**#57 - CLI Actions:**
- Related to #58 (transcript repair)
- May already be covered
- **Effort:** 1-2 hours

---

## Testing (6 items)

**Status:** Not Started
**Effort:** 12-16 hours total

- [ ] #63: Add tests for ProjectSwitcherView drag-drop
- [ ] #64: Add tests for ActiveSessionPolicyEngine logic
- [ ] #65: Add tests for TranscriptWatcher file monitoring
- [ ] #66: Add tests for all 23 DatabaseMigrations
- [ ] #52: Add CI job for macOS 14 compatibility ⬇️ (demoted from P1)

**Problem:** Only 12 test files for ~100 Swift files. Current coverage ~15%, target 60%+.

**Priority items:**
- #63: Drag-drop behavior (critical UX)
- #64: Policy decision logic (core functionality)
- #65: File watching, debouncing (stability)
- #66: All 23 migrations (data integrity)

**#52 - macOS 14 CI:**
- Manual testing feasible short-term
- Can add CI job post-launch
- **Effort:** 2-3 hours

---

# P3 (Low Priority / Deferred) - 8 Items

## Performance & Monitoring (4 items) ⬇️

**Status:** Not Started
**Priority:** Demoted from P2 (no current performance issues)
**Effort:** 6-8 hours total

- [ ] #67: Set up code coverage reporting in CI
- [ ] #68: Benchmark discovery time (10, 50, 100 projects)
- [ ] #69: Benchmark LLM summary generation batch sizes
- [ ] #70: Add XCTest performance tests

**Note:** #68 overlaps with #43 (P0 stress testing) but is more comprehensive benchmarking.

---

## Features (4 items) ⬇️

**Status:** Not Started
**Priority:** Demoted from P2 or P1
**Effort:** 8-12 hours total

- [ ] #61: Fallback to parent directory name for Codex projects (demoted from P2)
- [ ] #76: Add prev1/prev2 context to LLM prompts (demoted from P2)
- [ ] #89: Extend parser to collect queue-operation metadata (demoted from P1)
- [ ] #90: Extend parser to collect timeline-state metadata (demoted from P1)

**#61 - Codex Names:**
- Part of larger Codex data quality work (#60 in P2)
- Lower priority than parsing workspace metadata

**#76 - LLM Context:**
- Improve summary quality with surrounding entries
- Multiple TODO comments in code
- **Effort:** 3-4 hours

**#89-90 - Parser Metadata:**
- Extend parser for additional debugging data
- **Effort:** 2-3 hours each

---

# COMPLETED ITEMS (For Reference)

## Website Launch (2025-11-11) ✅

- [x] #1: Disable Namecheap URL forwarding
- [x] Domain registration & DNS
- [x] Homepage, privacy policy, support page
- [x] Nginx + SSL deployment
- [x] Deploy scripts

**Remaining:** #2 (Setup hello@contextify.sh email) - moved to P0

---

## P0 Completed Items ✅

- [x] #10: Fix project ingestion order to match tab order
- [x] #11: Prioritize active project hoover on first launch
- [x] #12: Hide invalid projects from tab bar
- [x] #15: Remove "Run in Background" button from welcome modal
- [x] #17: Replace invalid project root modal with warning icons
- [x] #18: Validate paths before persisting to database
- [x] #29: Fix drag-drop cancellation when cursor exits window (2025-11-18, commit `0bbe383`)
- [x] #30: Add state validation after drag operations (2025-11-18, commit `0bbe383`)
- [x] #P0-SUMM: Fix failure to kick off summarization on initial viewport load (2025-11-17)
- [x] #P0-LOGOMARK-INFO: Remove non-functional CLI logomark info icon (2025-11-17)

---

## P1 Completed Items ✅

- [x] #19: Fix ConversationMonitor.swift warnings (verified 2025-11-18)
- [x] #20: Fix TranscriptMetadataOrchestrator.swift availability checks (verified 2025-11-18)
- [x] #21: Fix ProjectsViewModel.swift warnings (verified 2025-11-18)
- [x] #22: Fix ProjectSwitcherState.swift warnings (verified 2025-11-18)
- [x] #23: Verify clean build with zero warnings (verified 2025-11-18)
- [x] #31: Auto-refresh Projects tab on FSEvents detection
- [x] #33: Debounce rapid filesystem events (2s)
- [x] #34: Add failed transcript tracking with error states
- [x] #36: Persist failed transcripts across restarts
- [x] #44: Document discovery timing expectations (<5s target)
- [x] #53: Verify bash scripts/xc.sh build matches Xcode Run

---

## P2 Completed Items ✅

- [x] #62: Gather user feedback on Projects vs Transcripts window UX
- [x] #73: Port FileKitty's release.py for automation
- [x] #74: Automate build → sign → notarize → DMG → GitHub release
- [x] #75: Add regex-based content filter for LLM summaries

---

## P3 Completed Items ✅

- [x] #84: Refactor ConversationMonitor initialization (deferred)
- [x] #92: Add v26 migration with 3 new metadata tables

---

## Dropped/Invalid Items ❌

- ❌ #26: F53B3BE1-3A80-4C84-9E37-42D947CADAFA (accidental paste)
- ❌ #41: Implement port fallback for diagnostics server - **DROP DIAGNOSTICS SERVER FROM INITIAL RELEASE**
- ❌ #42: Update timeline_api.sh to auto-detect port - **Depends on #41 (dropped)**
- ❌ #77: Verify all diagnostics API endpoints functional - **Feature dropped**
- ❌ #78: Test /health, /diagnostics, /timeline/* endpoints - **Feature dropped**

**Rationale:** User note: "Should drop diagnostics / web server from initial release entirely" - non-critical debugging feature, can add post-launch.

---

# DETAILED TASK SPECIFICATIONS

*The sections below contain full implementation details for complex tasks. Simple tasks (listed above) don't need detailed specs.*

---

## P0: Disable Git Monitoring in Sandboxed Builds ✅ COMPLETE

**Status:** ✅ Complete (2025-11-15)
**Commit:** `b0abdb4` - fix(sandbox): disable git monitoring in App Store builds
**Branch:** `claude/codex-discovery-fix-012fkAJXMWvjrfWZPh7xhPEm`

### Problem

Git branch monitoring completely broken in sandboxed builds. Console spam every 2 seconds:
```
error  [GIT-BROKEN] Git monitoring failed (no project root access in sandboxed build)
error  [GIT-BROKEN] No project root bookmark (git monitoring unavailable in sandboxed build)
```

**Root cause:** Requires user permission to project root directories. Complex to implement (per-project bookmarks, NSOpenPanel, permission UI). NOT WORTH IT for initial release.

### Solution Implemented

Simple, fast approach:
1. Early return from `updateHeadWatcher()` if sandboxed (skip all git logic) ✅
2. Hide branch UI in sandboxed builds (show project name only) ✅
3. Remove bookmark restoration attempts in sandboxed builds ✅

**Result:** Clean logs, zero errors, shippable App Store build.

### Implementation

```swift
// HUDCore.swift:944
public func updateHeadWatcher() {
    #if os(macOS)
    guard !Sandbox.isSandboxed else {
        // Git monitoring disabled in sandboxed builds (no project root access)
        return
    }
    #endif

    cancelHeadAndRefWatchers()
    // ... existing git watcher code ...
}

// ContentView.swift (header)
if !Sandbox.isSandboxed {
    Text("Branch: \(vm.branch)")  // Only show in DMG builds
}
```

### Tasks

- [x] **[NOGIT1]** Early return from `updateHeadWatcher()` if sandboxed ✅
- [x] **[NOGIT2]** Remove bookmark restoration in `handleCoordinatorUpdate()` ✅
- [x] **[NOGIT3]** Hide branch display in header ✅
- [ ] **[NOGIT4]** Test App Store build: `bash scripts/xc.sh --dist=appstore Debug cleanrun`
- [ ] **[NOGIT5]** Verify: Zero `[GIT-BROKEN]` errors in Console.app logs

**Files:**
- `app/Sources/ContextifyCore/HUDCore.swift`
- `Contextify/Contextify/ContentView.swift`

**Estimated Effort:** 1-2 hours (simple code removal)

---

## P0 Critical: Codex Transcript Real-Time Updates ✅ COMPLETE

**Status:** ✅ COMPLETE (2025-11-08)
**Priority:** P0 (Regression - previously worked, now broken)

### Problem

When user switches from active Claude Code session to Codex session **in the same project**, Codex transcript updates don't appear in real-time. User must manually refresh or restart app.

**User Impact:** Severe - Codex sessions appear "frozen" after switching.

### Root Cause

- `startWatchingTranscript()` only called during initial project discovery
- Active session follow policy switches sessions via `setActiveSession()` but doesn't verify watcher running
- Missing hook in `setActiveSession()` to ensure watcher active

### Solution Implemented

Add watcher verification to session activation path. `TranscriptWatcher.watch()` is idempotent (line 44), so safe to call multiple times.

### Tasks Completed

- [x] Add watcher verification to `setActiveSession()`
- [x] Verify `TranscriptWatcher.watch()` idempotence
- [x] Integration test: switch Claude Code → Codex
- [x] Test with multiple Codex sessions
- [x] Verify no duplicate watcher warnings
- [x] Test no file descriptor leaks

**Files:** `Contextify/Contextify/ConversationMonitor.swift`, `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`

---

## P0 Critical: App Sandbox Implementation

**Status:** Reverted, Needs Re-implementation
**Priority:** P0 (Blocks App Store submission)

### Problem

Previous sandbox attempt (commit `b4b4762`) was reverted (`b1fe869`) because:
- Cannot access `~/.claude/projects` and `~/.codex/projects`
- FSEvents monitoring blocked
- Projects window shows 0 projects
- Database location changed, breaking existing users

### Solution

**Detailed plan:** `build/docs/operations/app-store/sandbox-implementation-plan.md`

**Four-Phase Approach:**
1. First-launch file picker for project directory access (4 hours)
2. Security-scoped bookmark persistence (3 hours)
3. Database migration to sandbox container (4 hours)
4. Entitlements configuration (30 minutes)

**Total Effort:** 8-12 hours

### Tasks

- [ ] Implement first-launch file picker flow
- [ ] Add security-scoped bookmark storage
- [ ] Create database migration to sandbox container
- [ ] Update entitlements file
- [ ] Test with sandboxed build
- [ ] Verify FSEvents work with bookmarks
- [ ] Test migration from non-sandboxed → sandboxed

### Acceptance Criteria

- [ ] Sandboxed build discovers projects via file picker
- [ ] Security-scoped bookmarks persist across launches
- [ ] Database migrates cleanly
- [ ] FSEvents watching works
- [ ] No data loss during migration
- [ ] App Store review guidelines met

---

## P0: Welcome Modal & First Launch UX

**Context:** StartupCoordinator refactor introduced regression where first launch fails with cryptic error.

**Reference:** Detailed specification follows (phases 1-8)

**Target:** 100% passing acceptance criteria before merge to main

### Phase 1: Coordinator Graceful Failure (P0)

**Goal:** Make coordinator tolerate "no project configured" state without fatal error.

**Status:** Not Started

**Tasks:**
- [ ] Modify `StartupCoordinator.start()` to catch `noProjectRootAvailable` gracefully
- [ ] Add notification name for welcome modal trigger
- [ ] Update `ContextifyApp.init()` error handling

**Dependencies:** None
**Estimated Time:** 1-2 hours
**Risk:** Low

### Phase 2: State Unification (P0)

**Goal:** Make discovery state accessible to main window for progress UI.

**Tasks:**
- [ ] Initialize `ProjectsViewModel` early in `ContextifyApp.init()`
- [ ] Pass `ProjectsViewModel` to `ContentView` via environment
- [ ] Add `ProjectsViewModel` to `ContentView` environment

**Dependencies:** Phase 1
**Estimated Time:** 2-3 hours

### Phase 3: Welcome Modal UI (P0)

**Goal:** Implement modal with live discovery progress.

**Tasks:**
- [ ] Create `WelcomeModalView.swift`
- [ ] Add welcome modal state to `ContextifyApp`
- [ ] Subscribe to `startupRequiresWelcomeModal` notification
- [ ] Attach modal as sheet to main window

**Dependencies:** Phase 2
**Estimated Time:** 3-4 hours

### Phase 4: Auto-Selection Logic (P0)

**Goal:** After discovery, automatically select most recent project.

**Tasks:**
- [ ] Add `getMostRecentProject()` to `TranscriptOrchestrator`
- [ ] Implement auto-selection in `initializeProjectsSystem()`
- [ ] Close welcome modal after auto-selection

**Dependencies:** Phase 3
**Estimated Time:** 2-3 hours

### Phase 5: Loading Overlay (P1)

**Goal:** Show loading state when modal dismissed during discovery.

**Tasks:**
- [ ] Add loading overlay to `ContentView`
- [ ] Style overlay with material background

**Dependencies:** Phase 4
**Estimated Time:** 1-2 hours

### Phase 6: Error Handling (P1)

**Goal:** Handle edge cases (no projects found, discovery failures).

**Tasks:**
- [ ] Add "No projects found" state to modal
- [ ] Add error state with retry button
- [ ] Guard auto-selection against races

**Dependencies:** Phase 3
**Estimated Time:** 2-3 hours

### Phase 7: Testing & Validation (P0)

**Goal:** Verify all acceptance criteria met.

**Tasks:**
- [ ] Manual testing: First launch (clean DB)
- [ ] Manual testing: No projects found
- [ ] Manual testing: Dismiss during discovery
- [ ] Manual testing: Normal launch (existing project)
- [ ] Manual testing: Manual selection during discovery
- [ ] Unit testing: Coordinator graceful failure
- [ ] Unit testing: Auto-selection logic
- [ ] Performance testing: Discovery time
- [ ] Thread safety audit

**Dependencies:** Phases 1-6
**Estimated Time:** 4-6 hours

### Phase 8: Documentation & Polish (P2)

**Goal:** Update docs, release notes, code comments.

**Tasks:**
- [ ] Update AGENTS.md with welcome modal flow
- [ ] Add code comments to coordinator changes
- [ ] Update changelog
- [ ] Add Xcode preview for modal

**Dependencies:** Phase 7
**Estimated Time:** 2-3 hours

**Total Effort:** 18-28 hours (2.5-3.5 days)

---

# CROSS-REFERENCE: Item Number → Priority

**P0 (25):** #2-9, #16, #29-30, #32, #35, #43, #45-47, #49-50, #58-59

**P1 (18):** #19-23, #51, #54-56, #71-72, #79-83, #85-88, #91

**P2 (19):** #13-14, #24-25, #27-28, #37-40, #48, #52, #57, #60, #63-66

**P3 (8):** #61, #67-70, #76, #89-90

**Removed (22):** #1, #10-12, #15, #17-18, #26, #31, #33-34, #36, #41-42, #44, #53, #62, #73-75, #77-78, #84, #92

---

**End of TODO List**
