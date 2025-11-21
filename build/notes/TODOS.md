---
title: Technical Debt & Future Improvements
type: actionable
related: ROADMAP.md
description: Items ready for implementation with clear scope. P0-P3 priority.
promotion_from: ROADMAP.md (once scoped)
priority_levels:
  P0: Release blockers - must complete before App Store submission
  P1: High priority - important for quality/UX, ship soon after launch
  P2: Medium priority - nice to have, can defer to future releases
  P3: Low priority/deferred - future enhancements
doc_references:
  standard: "All TODO supporting docs should have YAML front matter and live in build/notes/todo-support/, named by TODO ID"
  naming: "P{N}-{ID}-{type}.md (e.g., P1-AUTOSCROLL-spec.md, P2-SWITCH-investigation.md)"
  workflow:
    iterate: "Work on docs in /tmp/ creating multiple versions until finalized"
    finalize: "Copy final version to build/notes/todo-support/ with proper naming"
    reference: "Use **Type:** label followed by relative path from repo root"
  labels:
    - "**Spec:**" # Implementation specification
    - "**Investigation:**" # Research/analysis reports
    - "**Plan:**" # Multi-phase implementation plans
    - "**Reference:**" # General supporting documentation
  yaml_front_matter:
    required: ["todo_id", "title", "type", "date", "status", "description"]
    types: ["spec", "investigation", "plan", "source_analysis", "prompt", "reference"]
    statuses: ["active", "complete", "reference", "obsolete"]
  cleanup: "On TODO completion, delete supporting docs from build/notes/todo-support/ OR move to build/docs/ if permanent reference"
---

# Contextify TODO List

**Purpose:** Track open work items. Do NOT celebrate completions - remove completed items.
**Exploratory ideas:** See [ROADMAP.md](ROADMAP.md) for P4-P5 items.

**Last Updated:** 2025-11-20
**Status:** Active

**Priority Levels:**
- **P0 (Blocking Release):** 5 items - Must complete before App Store submission (1 new: logomark visibility, 2 fixed: watcher-init + tab-corners)
- **P1 (High Priority):** 25 items - Important for quality/UX, ship soon after launch
- **P2 (Medium Priority):** 36 items - Nice to have, can defer to future releases
- **P3 (Low Priority / Deferred):** 10 items - Future enhancements

**Total Active Items:** 75 (77 - 2 completed P0 items)

**Change Log (2025-11-20):**
- Added 1 P0 item (#P0-WATCHER-INIT: Fix watcher initialization failure - critical system reliability issue)
- Added 1 P1 item (#P1-WINDOW-WIDTH: Reduce default window width to match HUD-01 screenshot)
- Added 2 P2 items (#P2-PROJECTS-REFRESH-REVIEW, #P2-PROJECTS-EMPTY-STATE)
- Simplified copy in Transcripts and Projects windows to match Apple conventions
- Added investigation report: `build/docs/audits/console-log-error-investigation-2025-11-20.md`
- Root cause analysis reveals watchers never restart after project switches, not that they crash

**Change Log (2025-11-19):**
- Demoted 1 P2 item to P3 (#P2-LIQUID-GLASS → #P3-LIQUID-GLASS: toolbar translucency deferred post-launch)
- Removed 3 P0 items (#3-5: old git monitoring disable tests) - superseded by transcript-based approach
- Demoted 8 P0 items based on pre-submission priorities:
  - #32, #43 (Discovery UX) → P1
  - #35 (Failed metadata retry) → P1
  - #45-47 (Integration tests) → P1 (blocked by test infrastructure issues)
  - #49-50 (Project management) → P2
- Added 1 P1 item (#P1-GIT-BRANCH: transcript-based git branch display for App Store)
- Added 1 P1 item (#P1-OPTION3: parse permission dialog responses)
- Added 1 P1 item (#P1-TESTS: Get test suite running - wrapper for #45-47)

**Change Log (2025-11-15):**
- Removed 19 completed items, 5 dropped items (diagnostics server feature)
- Promoted 13 items (11 to P0, 2 to P1) - critical bugs and testing
- Demoted 21 items (2 from P0, 11 from P1, 8 from P2)
- Grouped 15 items into 3 consolidated features
- See `/tmp/todo-proposed-changes-final.md` for full rationale

---

# P0 (Blocking Release) - 5 Items Remaining

## UI Polish (COMPLETE) ✅

- [x] #P0-LOGOMARK-LIGHT: Fix Codex logomark visibility in light mode (white on white)

**Status:** Fixed - Added conditional shadow for light mode

**Solution Applied:**
Added `@Environment(\.colorScheme)` and conditional shadow (`.shadow(color: .black.opacity(0.5), radius: 0.5)`) when colorScheme is light and provider is Codex CLI.

**Files Changed:**
- `ProjectBadgesView.swift` - Badge display in project list
- `TimelineEntryRow.swift` - Provider icon in timeline entries
- `TranscriptInventoryView.swift` - Provider icon in session rows

---

## Watcher Initialization Failure (FIXED) ✅

**Status:** Completed on feature/fix-watcher-initialization branch (9 commits)
**Branch:** Ready to merge to main

- [x] #P0-WATCHER-INIT: Fix watcher initialization failure causing missing real-time transcript updates
- [x] #P0-TAB-CORNERS: Fix project tab bar dark/bold corners (already fixed, can be removed)

**Problem:** Watchers were never initialized during project switches, discovery reruns, and recovery attempts, which left Claude Code and Codex transcripts frozen until the user restarted the app.

**Summary:** The fix tracked in `feature/fix-watcher-initialization` adds stronger recovery logging, ensures watchers are re-created whenever a project reloads, and adds the retries described in the supporting doc so real-time updates stay live.

**Details:** `build/notes/todo-support/P0-WATCHER-INIT-investigation.md`

---

## Remove Diagnostics HTTP Server (1 item)

**Status:** Not Started
**Priority:** P0 (Blocking Release - debug HTTP server should not ship)
**Effort:** 30 minutes

- [ ] #P0-REMOVE-HTTP-API: Temporarily remove diagnostics HTTP server code before release

**Problem:**
The diagnostics HTTP server (`DiagnosticsHTTPServer.swift`) exposes a local API for debugging timeline state. This debug infrastructure should not ship in the initial release:
- Security concern: local HTTP endpoint exposes internal state
- Unnecessary complexity for v1
- Can be re-enabled post-launch when needed

**Files to Remove/Disable:**
- `app/Sources/ContextifyCore/Diagnostics/DiagnosticsHTTPServer.swift` - HTTP server actor
- `app/Sources/ContextifyCore/Diagnostics/DiagnosticsExporter.swift` - Export utilities (keep if used elsewhere)
- `app/Sources/ContextifyCore/Diagnostics/TimelineDiagnostics.swift` - Keep (used for internal diagnostics)
- `ConversationMonitor.swift` - Remove HTTP server initialization (lines ~563-588)
- `ConversationMonitor.swift` - Remove `DiagnosticsConfig.enableHTTPServer` usage

**Implementation:**
1. Set `DiagnosticsConfig.enableHTTPServer = false` (quick fix) OR
2. Remove `DiagnosticsHTTPServer.swift` entirely and clean up references
3. Document removal commit SHA for future restoration

**Restoration:** See P3-RESTORE-HTTP-API for bringing this back post-launch

---

## App Store Submission (4 items)

**Status:** Not Started (Ready to begin - welcome modal polish complete)
**Effort:** 8-12 hours

- [ ] #6: App Store Connect setup (metadata, screenshots, description)
- [ ] #7: Build Release binary (sign, archive, validate, upload)
- [ ] #8: Submit for review (compliance, age rating, reviewer notes)
- [ ] #9: TestFlight beta (optional, recommended)

**Reference:** `build/notes/todo-support/P0-APP-STORE-checklist.md` § "APP STORE SUBMISSION CHECKLIST"

---


# P1 (High Priority) - 25 Items

## Window Sizing (1 item)

**Status:** Not Started
**Priority:** P1 (First impression - default window size affects App Store impression)
**Effort:** 30 minutes - 1 hour

- [ ] #P1-WINDOW-WIDTH: Reduce default application window width to match HUD-01 screenshot dimensions

**Problem:**
Default window opens too wide, creating unnecessary horizontal scrolling and poor space utilization. Screenshot HUD-01 demonstrates optimal width that fits content perfectly.

**Implementation:**
1. Measure window width in `appstore-metadata/screenshots/releases/01-main-hud.png`
2. Locate default window size setting (likely in `ContextifyApp.swift` or window configuration)
3. Update default width to match screenshot dimensions
4. Ensure minimum width constraints still allow resize
5. Test that content doesn't clip at new default width
6. Verify window remembers user-adjusted size (don't override saved preferences)

**Current vs Target:**
- Current: Unknown (likely too wide)
- Target: Width from HUD-01 screenshot (appears to be ~800-900pt)

**Files:**
- `Contextify/Contextify/ContextifyApp.swift` (likely `.frame()` or window configuration)
- Possibly SwiftUI `.defaultSize()` modifier
- Check for WindowGroup configuration

**Acceptance Criteria:**
- ✅ Default window width matches HUD-01 screenshot
- ✅ Content fits without horizontal scrolling
- ✅ Window remains resizable
- ✅ User preferences for window size are preserved
- ✅ Minimum width constraint prevents over-shrinking

**Testing:**
1. Delete app preferences/saved state
2. Launch app fresh
3. Verify default window width matches target
4. Resize window, quit, relaunch
5. Verify custom size is preserved

**Note:** This affects first-run user experience and App Store reviewer impression. Getting the default size right is important for perceived polish.

---

## Apple Intelligence Blinking Out (1 item)

**Status:** Not Started
**Priority:** P1 (Critical UX bug - Apple Intelligence appears to randomly disappear)
**Effort:** 4-6 hours

- [ ] #P1-AI-HEALTH-BLINK: Fix Apple Intelligence status blinking out unexpectedly due to health check issues

**Problem:**
Apple Intelligence status in the UI (status bar, timeline summaries) unexpectedly "blinks out" and shows as unavailable or checking, then recovers moments later. This creates a confusing UX where the feature appears unreliable even when functioning normally.

**Likely Root Causes:**

1. **Health Check Cancellations During Normal Operations** (Primary Suspect)
   - Health checks get cancelled during project switches, app lifecycle events
   - When cancelled, `StatusBarViewModel` sets status to `.checking` (line 316)
   - Creates appearance of Apple Intelligence going offline when it's actually fine
   - Cancellation tracking shows bursts >3 in 30s window (line 338-341)

2. **Race Conditions in Status Updates**
   - Multiple components trigger health checks simultaneously
   - Cached status may be cleared during active checks
   - Status bounces between `.available`, `.checking`, `.unavailable`

3. **Exponential Backoff Side Effects**
   - Failed checks increase cache interval: 5s → 10s → 20s → 30s
   - Long cache intervals may cause stale status display
   - Cancellations don't count as failures (line 90-93) but still disrupt flow

**Investigation Steps:**

1. **Add Health Check Lifecycle Logging** (1 hour)
   - Log every health check start/completion/cancellation with timestamps
   - Track cancellation sources (project switch, app lifecycle, timeout)
   - Add correlation IDs to track health check lifetimes
   - Log to category: "LLMHealthDebug" at `.info` level

2. **Analyze Cancellation Patterns** (1 hour)
   - Run app with verbose logging during normal usage
   - Identify what triggers cancellations (project switches, window focus, etc.)
   - Measure cancellation burst frequency
   - Check if cancellations correlate with UI "blink out" events

3. **Review Health Check Call Sites** (1 hour)
   - Audit all `LLMHealthCheck.shared.checkHealth()` calls
   - Verify each call site properly handles cancellation
   - Check for redundant health checks within cache window
   - Identify opportunities to share health check results vs re-checking

**Potential Solutions:**

**Option A: Smarter Cancellation Handling**
- Don't change status to `.checking` on cancellation if last known status was `.available`
- Only show `.checking` if no cached status exists
- Treat cancellations as "keep last good status" rather than "reset to checking"

**Option B: Debounce Health Checks**
- Prevent multiple health checks within 5s window
- Queue health check requests and deduplicate
- Return cached result immediately if check is in-flight

**Option C: Health Check Task Coordination**
- Single global health check task that runs periodically
- All components observe health check results rather than triggering checks
- Prevents concurrent/duplicate checks

**Option D: Separate "Availability" from "Health Check In Progress"**
- UI shows last known availability while background check runs
- Only update UI when health status actually changes
- Never show `.checking` unless truly unknown (first launch)

**Files to Review:**
- `Contextify/Contextify/LLMHealthCheck.swift` (lines 187-248, 301-308) - Health check logic
- `Contextify/Contextify/StatusBarViewModel.swift` (lines 270-330) - Status update logic
- `Contextify/Contextify/AppDelegate.swift` (line 70) - Health check trigger
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` (line 614) - Health check usage

**Acceptance Criteria:**
- ✅ Apple Intelligence status remains stable during project switches
- ✅ No visible "blinking" between available/checking/unavailable states
- ✅ Health check cancellations don't cause UI status changes unless health truly changed
- ✅ Logs clearly show health check lifecycle and cancellation reasons
- ✅ Cancellation burst warnings (<3 per 30s window under normal usage)
- ✅ Status updates only when actual health state changes, not on transient events

**Test Scenarios:**
1. Switch between 5 projects rapidly - AI status should remain stable
2. Background app and bring to foreground - status should not blink
3. Let app run idle - periodic health checks should not cause UI flicker
4. Simulate Apple Intelligence going offline - status should update once and stay unavailable
5. Simulate Apple Intelligence coming online - status should update once and stay available

---

## Git Worktree Conversation Display (1 item)

**Status:** Not Started
**Priority:** P1 (Potential bug affecting developer workflow)
**Effort:** 2-4 hours

- [ ] #P1-WORKTREE: Investigate bug where conversations from git worktrees may not display properly

**Problem:**
When working in a git worktree (e.g., `../contextify-liquid-glass`), Contextify may not properly display or discover conversations. This could affect developer workflow when using worktrees for feature development.

**Potential Root Causes:**
- Project path detection may not handle worktree `.git` file (points to main repo)
- Transcript discovery may use git working directory incorrectly
- Project identity (hash/path encoding) may differ between main repo and worktrees
- Database lookups may fail to match worktree paths to project records

**Investigation Steps:**
1. Create test worktree and verify bug reproduction
2. Check how `ProjectIdentity` resolves paths for worktrees
3. Verify transcript discovery scans worktree correctly
4. Test if conversations appear in timeline when working from worktree
5. Check git status detection (branch, HEAD) in worktree context

**Files to Review:**
- `app/Sources/ContextifyCore/Projects/ProjectIdentity.swift`
- `app/Sources/ContextifyCore/Discovery/ProjectDiscoveryService.swift`
- Git detection logic in HUDCore/HUDViewModel

**Acceptance Criteria:**
- Conversations display correctly when working from worktree
- Project identity resolves consistently between main repo and worktrees
- Timeline shows proper conversations for worktree context
- Git branch/status displays correctly in worktree

---

## Test Infrastructure - Get Test Suite Running (4 items) ⬇️

**Status:** Not Started (Blocked)
**Priority:** Demoted from P0 (blocked by test infrastructure issues, manual QA sufficient for MVP)
**Effort:** 12-16 hours

- [ ] #P1-TESTS: Resolve test infrastructure blockers (FoundationLLM, SDK, async/actor issues)
- [ ] #45: Re-enable testInitialHooverWorkflow integration test
- [ ] #46: Re-enable testOrchestratorWorkflow integration test
- [ ] #47: Re-enable testCrashRecovery integration test

**Problem:** Test suite currently broken with substantial blockers related to FoundationLLM, recent SDK changes, and async/actor isolation issues. 3 critical integration tests disabled with `skip_` prefix pending resolution.

**Blockers:**
- FoundationLLM compatibility issues with test environment
- Recent macOS SDK changes affecting test execution
- Async/actor isolation problems in test harness
- **Action:** Search database for previous conversations documenting these blockers

**Tasks:**
1. **Infrastructure Fix** (6-8 hours)
   - Research FoundationLLM test compatibility issues
   - Resolve SDK/async/actor problems
   - Get test suite building and running cleanly
   - Verify existing passing tests still work

2. **Re-enable Integration Tests** (6-8 hours)
   - Update tests for new HooverEngine API
   - Update tests for new TranscriptOrchestrator API
   - Update tests for checkpoint changes
   - Remove `skip_` prefix
   - Add to CI pipeline
   - Verify tests pass 10x in a row (no flaky failures)

**Files:**
- `Contextify/ContextifyTests/IntegrationTests.swift`
- Test configuration files (to be determined during investigation)

**Acceptance Criteria:**
- Test suite builds and runs without infrastructure errors
- All 3 integration tests re-enabled and passing
- Tests are stable (10 consecutive passes)
- Integrated into CI pipeline

**Decision:** Manual QA sufficient for MVP App Store submission. Test infrastructure can be fixed post-launch.

---

## Discovery UX (2 items) ⬇️

**Status:** Not Started
**Priority:** Demoted from P0 (nice to have, not blocking submission)
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

## Automated QA Suite (1 item)

**Status:** Not Started - methodology defined, needs implementation
**Priority:** P2 (valuable for release confidence, but manual QA sufficient for MVP)
**Effort:** 8-12 hours (MVP bash-based suite)
**Methodology:** `build/notes/todo-support/P2-AUTOMATED-QA-methodology.md`

- [ ] #P2-AUTOMATED-QA: Implement automated QA suite for pre-release validation

**Goal:** Bash-based automated QA suite that validates 6 critical user flows through log analysis, database queries, and filesystem verification.

**Scope (MVP - Local Execution):**
- Sequential execution on local macOS dev machine (no CI/CD yet)
- Real integrations with actual Codex/Claude CLIs (not fixtures)
- Sub-10 minute execution time with clear pass/fail results
- AppleScript for UI automation, direct SQLite queries acceptable

**Test Coverage:**
1. App startup and initialization (5 variants: DMG/AppStore × clean/existing + permission skip)
2. Project switching between multiple repositories
3. File system event → ingestion → timeline display
4. LLM processing and summary generation
5. Timeline scroll and rendering
6. Permission grant flows (App Store builds)

**Deliverables:**
- `scripts/qa/` directory with test harness
- 6 test scripts (QA-01 through QA-06)
- Test helper utilities (log parsing, DB queries, UI automation)
- Test report generation
- README with usage instructions

**Future Work (v2 - Professional QA):**
- CI/CD integration with GitHub Actions
- Fixture-based tests for reliability/cost reduction
- Database migration testing
- Performance benchmarks with timing assertions
- Headless controls without AppleScript

**Files:**
- `scripts/qa/` (new directory)
- Test fixtures/helper scripts

**Reference:** Complete methodology with test scenarios, acceptance criteria, and implementation approach in `build/notes/todo-support/P2-AUTOMATED-QA-methodology.md`

---

## Failed Metadata Retry (1 item) ⬇️

**Status:** Not Started
**Priority:** Demoted from P0 (not blocking submission)
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

## Transcript-Based Git Branch Display (1 item)

**Status:** Not Started
**Priority:** P1 (Replaces old P0 "disable git" approach - enables branch display in App Store)
**Effort:** 6-8 hours

- [ ] #P1-GIT-BRANCH: Implement transcript-based git branch tracking and display for App Store builds

**Background:**
Old approach (✅ complete 2025-11-15, commit `b0abdb4`) disabled git monitoring entirely in sandboxed builds and hid branch UI. New approach uses transcript data to display branch WITHOUT filesystem access.

**Investigation:** `build/notes/todo-support/P1-GIT-BRANCH-investigation.md`
**Documentation:** `build/docs/specifications/transcript-formats.md` (lines 56, 95, 360-365, 582)

**Key Finding:**
- ✅ Claude Code: `gitBranch` field on EVERY message → updates immediately
- ✅ Codex: `session_meta.payload.git.branch` → updates at session start/resume
- ✅ Database already supports: `git_branch` column exists (schema v23)
- ✅ Parser already extracts: Both formats handled

**Architecture Requirements:**

**App Store Build:**
- Extract branch from transcript data (Claude Code: any message's `gitBranch`, Codex: last `session_meta`)
- Display branch in UI (status bar/header)
- Add InfoButton (ⓘ) next to branch with popover explaining:
  - "Branch determined from conversation transcripts"
  - "Codex: may lag until next session start"
  - "For real-time status, grant project directory access" + link/button to trigger permission flow
- No filesystem access required

**DMG Build:**
- Track BOTH transcript-based AND filesystem-based branch
- Log alignment discrepancies internally (especially for Codex)
- Metric: How often does Codex transcript branch differ from actual `.git/HEAD`?
- Purpose: Validate transcript-based approach reliability

**Implementation Tasks:**

1. **Branch Extraction Service** (2-3 hours)
   - Add `getCurrentBranch()` to `TranscriptOrchestrator` or similar
   - Query `timeline_entries.git_branch` for most recent entry
   - Handle Codex special case: Find last `session_meta` record
   - Return `nil` if no branch data available

2. **UI Display** (2 hours)
   - Restore branch display in `ContentView.swift` (was hidden in commit `b0abdb4`)
   - Add InfoButton component next to branch
   - Implement InfoPopoverContent with explanation and permission upgrade link
   - Style: Match existing UI patterns

3. **DMG Validation Logging** (1-2 hours)
   - In DMG builds, compare transcript branch vs filesystem branch
   - Log discrepancies at `.info` level
   - Track metrics: mismatch rate, time-to-convergence
   - Don't block or warn user, just collect data

4. **Testing** (1 hour)
   - App Store build: Verify branch displays from transcripts
   - Test Claude Code sessions (immediate updates)
   - Test Codex sessions (updates on session start)
   - Test InfoButton popover and permission link
   - DMG build: Verify dual tracking logs discrepancies

**Files:**
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` (branch extraction)
- `Contextify/Contextify/ContentView.swift` (UI display - restore removed code)
- `Contextify/Contextify/InfoButton.swift` (existing component, reuse)
- `Contextify/Contextify/InfoPopoverContent.swift` (new content for branch explanation)

**Acceptance Criteria:**
- ✅ App Store build displays git branch from transcripts (no filesystem access)
- ✅ Branch updates on next message (Claude Code) or session start (Codex)
- ✅ InfoButton explains source and lag behavior
- ✅ Permission upgrade link triggers folder access flow (if possible in popover)
- ✅ DMG build logs transcript vs filesystem discrepancies
- ✅ Zero [GIT-BROKEN] errors in App Store build

**Related:**
- Supersedes old P0 items #3, #4, #5 (test/verify git disabled)
- Builds on completed work: commit `b0abdb4` (git monitoring disabled)

---

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

## Project Auto-Discovery & QA Setup (1 item)

**Status:** Not Started
**Priority:** P1 (Critical for launch QA)
**Effort:** 6-8 hours

- [ ] #P1-DISCOVERY-QA: Clean up and QA project auto-discovery with DevOps tooling

**Scope:**

1. **UI Polish** (1 hour)
   - Remove "open project" link from empty/no-project state
   - Clean up messaging for better first-run experience

2. **QA Test Scenarios** (2-3 hours)
   - **Scenario A:** First project ever (user has no transcripts)
     - Start first Claude Code/Codex session
     - Verify app auto-discovers and switches to new project immediately
   - **Scenario B:** Adding second project (user has 1 existing project)
     - Start new session in different project
     - Verify app auto-discovers and switches to newest project automatically

3. **DevOps Tooling** (3-4 hours)
   - Design safe transcript-swapping mechanism for QA testing
   - Previous symlink approach caused confusion (all transcripts disappeared)
   - **Requirements:**
     - Temporarily swap real transcripts with test transcripts
     - Run QA scenarios without destroying real data
     - Merge QA-generated transcripts back to real projects (e.g., Contextify dev transcripts)
     - Clear documentation on what's real vs test
   - **Possible approaches:**
     - Scripted symlink swap with clear state tracking
     - Separate database for QA mode
     - Transcript directory cloning/restore mechanism

**Acceptance Criteria:**
- Empty state UI is clean (no broken/confusing links)
- First project auto-discovery works reliably
- Multi-project auto-discovery switches to newest correctly
- Safe QA workflow documented and tested
- Can swap transcripts, run QA, and restore without data loss

**Files:**
- UI: `Contextify/Contextify/ContentView.swift` or empty state view
- Scripts: New QA tooling (to be created)
- Docs: QA workflow documentation

**Related:**
- Builds on fix for welcome modal discovery (commit `199072e`)
- Needed for pre-launch App Store testing

---

## Timeline UX - Queued Messages (1 item)

**Status:** Not Started
**Priority:** P1 (Critical UX bug - timeline shows incomplete conversation)
**Effort:** 3-4 hours

- [ ] #P1-QUEUE-MESSAGES: Parse and display queue-operation records as user messages in timeline

**Problem:**
User messages sent while Claude is working (tools executing) are stored as `queue-operation` records with `operation: "enqueue"`. These are currently skipped by the parser, creating a broken timeline where Claude appears to be "talking to himself" with no user prompts visible.

**Example from logs:**
```
10:05:13 AM - Claude: checked spec in docs
10:05:19 AM - Claude: searched for queue-operation documentation
(missing) YOU: did you check claude code spec specifically in docs
```

**Impact:**
- 1,724 queue-operation records across all sessions (significant data)
- Timeline shows Claude responses without visible user messages
- Confusing UX - appears like Claude is randomly taking actions
- User thinks their messages aren't being received

**Solution:**

1. **Parser Extension** (1-2 hours)
   - Extend `ClaudeCodeMetadataParser` to handle `queue-operation` records
   - Only parse records where `operation: "enqueue"` (ignore "remove" and "popAll")
   - Create timeline entries with `kind: user` and `provider: claude.code`
   - Extract timestamp, content, sessionId from record

2. **Timeline Display** (1 hour)
   - Display with 🐝 bee emoji indicator (shows "sent while working")
   - Add InfoButton (ⓘ) with popover explanation:
     - Title: "Queued Message"
     - Message: "Sent while Claude was working. Received via system reminder and addressed in response."
   - Use existing InfoButton component (`Contextify/Contextify/InfoButton.swift`)

3. **Testing** (1 hour)
   - Verify 1,724 existing queue-operation records are ingested correctly
   - Check timeline ordering with queued messages interspersed
   - Test InfoButton popover appears and explains context
   - Verify no duplicate entries for same message

**Files:**
- Parser: `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
- Timeline: `Contextify/Contextify/TimelineEntryRow.swift`
- UI: Reuse existing `InfoButton.swift` and `InfoPopoverContent.swift`

**Reference:**
- Existing metadata plan: `build/docs/plans/metadata-ingestion-queue-types.md`
- Queue-operation format: `{"type":"queue-operation","operation":"enqueue","content":"...","timestamp":"..."}`

---

## Timeline UX - Permission Dialog Option 3 Responses (1 item)

**Status:** Not Started
**Priority:** P1 (Critical UX - missing user intent from timeline)
**Effort:** 2-3 hours

- [ ] #P1-OPTION3: Parse and display user's custom responses from permission dialog option 3

**Problem:**
When user chooses option 3 ("type something different") in response to Claude Code permission questions, their custom text is stored in the transcript but NOT displayed in timeline. This creates incomplete conversation history where user's alternative instructions are invisible.

**Example from transcript:**
```json
{
  "type": "user",
  "message": {
    "content": [{
      "type": "tool_result",
      "is_error": true,
      "content": "The user doesn't want to proceed... To tell you how to proceed, the user said:\nTHIS IS A TEST TEST TEST IGNORE THIS AND PROCEED ZZZ"
    }]
  }
}
```

**Impact:**
- User's alternative instructions invisible in timeline
- Appears like Claude is acting without user direction
- Can't review what alternative instructions were given
- Confusing UX - "Why did Claude do that instead of what I asked?"

**Solution:**

1. **Parser Extension** (1 hour)
   - Detect `user` records with `message.content[].type == "tool_result"` AND `is_error == true`
   - Check if `content` contains marker text: "To tell you how to proceed, the user said:"
   - Extract user's custom text (everything after marker)
   - Create timeline entry with `kind: user` and extracted text as content
   - Preserve timestamp and session info

2. **Timeline Display** (1 hour)
   - Add visual indicator: 💬 speech bubble or 🔄 response icon
   - Add InfoButton (ⓘ) with popover:
     - Title: "Alternative Instruction"
     - Message: "Response to permission question - user provided alternative instruction instead of proceeding with suggested action."
   - Subtle visual distinction from regular user messages (border/background tint)
   - Use existing InfoButton component

3. **Testing** (30 min)
   - Verify test message "THIS IS A TEST TEST TEST..." appears in timeline
   - Check icon/decoration renders correctly
   - Test InfoButton popover explanation
   - Verify doesn't duplicate with tool_result entries

**Files:**
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` (parser logic)
- `Contextify/Contextify/TimelineEntryRow.swift` (display logic)
- `Contextify/Contextify/InfoButton.swift` (existing component, reuse)

**Acceptance Criteria:**
- ✅ Option 3 custom responses appear in timeline as user messages
- ✅ Visual decoration distinguishes from regular user input
- ✅ InfoButton explains context (response to permission question)
- ✅ All historical option 3 responses ingested on next hoover

**Test Data:**
- Transcript: `28a20f3c-d598-449b-9a88-8d77f3799ce3.jsonl`
- Message: "THIS IS A TEST TEST TEST IGNORE THIS AND PROCEED ZZZ"
- Should appear in timeline with response decoration

---

## Timeline Auto-Scroll Fix (1 item)

**Status:** Ready for implementation
**Priority:** P1 (UX - auto-scroll unreliable, stops working after 25 items)
**Effort:** 2-4 hours
**Spec:** `build/notes/todo-support/P1-AUTOSCROLL-spec.md` (v2 — sticky bottom, jump-to-latest, optional removal of Auto-scroll toggle)

- [ ] #P1-AUTOSCROLL: Fix timeline auto-scroll flicker and 25-item stall

**Problem:**
Timeline auto-scroll is unreliable:
- Flickers on first load (double scroll triggers)
- Stops working after 25 items (count-based trigger saturates)
- Viewport summary queueing delayed by stuck scroll gating

**Root Causes (Validated):**
1. **Double programmatic scroll on first paint** - `onAppear` and `onChange(of: visibleEntries.count)` both fire
2. **Count-based trigger stalls at 25-item cap** - `visibleEntries.count` saturates, no more triggers
3. **Scroll gating stuck** - nil-animated jump doesn't emit `ScrollPhase`, gating never clears
4. **Pending scroll task not cancelled** - teardown can leave stale scroll pending

**Solution:**
- Replace dual-trigger with single scroll path using `scrollPosition(id:anchor:)`
- Key trigger on `entriesRevision` instead of `count`
- Implement "sticky until user scrolls up" with "Jump to Latest" button
- Add 1-second timeout to clear stuck scroll gating

**Files:**
- `ConversationTimelineView.swift` - scroll behavior refactor
- `ConversationMonitor.swift` - gating timeout

**Implementation:** See full spec at `build/notes/todo-support/P1-AUTOSCROLL-spec.md`

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

## CI/CD Infrastructure (1 item)

**Status:** Broken - budget exhausted
**Priority:** P1 (blocking CI for all contributors)
**Effort:** 4-6 hours

- [ ] #P1-CI-THROTTLE: Fix GitHub Actions budget exhaustion and implement build throttling

**Problem:**
GitHub Actions workflow (https://github.com/banagale/contextify/actions/workflows/macos-build.yml) is broken due to budget exhaustion from excessive build triggers.

**Root Causes:**
- No throttling on build triggers
- Web-based AI agents (e.g., Claude Code web) triggering CI builds unnecessarily
- Desktop AI agents should use local build resources, not CI

**Solution:**
1. **Audit trigger frequency** - Analyze GitHub Actions logs to identify what's causing excessive builds
2. **Implement throttling** - Add workflow conditions to prevent redundant builds (e.g., skip if previous commit already built)
3. **Context-aware triggering** - Only trigger CI for:
   - Pull request validation
   - Main branch commits
   - Explicit manual triggers
   - Web-based AI agent requests (when local build not available)
4. **Local build preference** - Update AGENTS.md to instruct desktop AI agents to use `bash scripts/xc.sh build` instead of triggering CI

**Acceptance Criteria:**
- [ ] GitHub Actions budget no longer exhausted
- [ ] CI builds only when necessary (PRs, main commits, manual)
- [ ] Desktop AI agents build locally by default
- [ ] Web AI agents can still request CI builds when needed
- [ ] Throttling rules documented in `.github/workflows/macos-build.yml`

**Reference:** GitHub Actions workflow currently broken: https://github.com/banagale/contextify/actions/workflows/macos-build.yml

---

# P2 (Medium Priority) - 32 Items

---

## Timeline Flicker on DMG Startup (1 item)

**Status:** Unresolved - may be fixed by P1-AUTOSCROLL work
**Priority:** P2 (UX issue - DMG builds only)
**Effort:** 30 minutes - 1 hour (if not resolved by scroll fixes)
**Investigation:** `build/notes/todo-support/P2-TIMELINE-FLICKER-investigation.md`

- [ ] #P2-TIMELINE-FLICKER: Fix timeline flicker during DMG startup (verify after P1-AUTOSCROLL complete)

**Problem:**
DMG builds show visible timeline flicker during startup with clean database. Timeline re-renders identical entries multiple times (visible UI flicker). App Store builds appear fine due to permission delays spacing events naturally.

**Evidence:**
Multiple rapid `loadFeedFromSQL()` calls during startup (4 calls in 19ms), followed by duplicate refresh 519ms later showing same 25 entries.

**Potential Relationship:**
May be resolved by P1-AUTOSCROLL scroll refactor work. The auto-scroll fix replaces dual-trigger scroll paths with single path using `scrollPosition(id:anchor:)` which could eliminate the duplicate refresh triggers.

**Action Plan:**
1. Complete P1-AUTOSCROLL implementation first
2. Test DMG startup with clean database
3. If flicker persists, implement investigation recommendations:
   - Add call site logging to `loadFeedFromSQL()` to track callers
   - Consider debouncing `loadFeedFromSQL()` itself (not just progress handler)
   - Investigate startup sequence timing

**Files:**
- `ConversationMonitor.swift` - `loadFeedFromSQL()` duplicate calls

**Investigation:** Full analysis with timeline reconstruction, root cause theories, and testing plan in `build/notes/todo-support/P2-TIMELINE-FLICKER-investigation.md`

---

## Lazy Watcher Optimization (1 item)

**Status:** Spec Complete
**Priority:** P2 (resource optimization - reduce FD usage by 90%)
**Effort:** 3-4 weeks (aligned with ConversationMonitor refactor)
**Spec:** `build/notes/todo-support/P2-LAZY-WATCHERS-design.md`

- [ ] #P2-LAZY-WATCHERS: Implement lazy watchers for inactive projects to reduce file descriptor usage

**Problem:**
Current implementation creates DispatchSource watchers for ALL transcripts across ALL projects. With 672+ transcripts, this consumes 1600+ file descriptors.

**Solution:**
Two-tier monitoring: active project gets real-time DispatchSource watchers; inactive projects use FSEvents-only with dirty transcript tracking. On activation, rehoover dirty transcripts (including offline changes via mtime check).

**Key components:**
- `MonitoringCoordinator` actor (extracted from ConversationMonitor)
- FSEvents behavior matrix for active/inactive + new/existing transcripts
- `pending_rehoover` + `last_known_mtime` DB columns (migration v27)
- 5-second hysteresis for project switching
- Feature flag for rollout (`lazyWatchersEnabled`)

**Prerequisites:**
- ConversationMonitor 4-way split (P0 from architecture-refactoring-analysis.md)

---

## Empty Project Detection (1 item)

**Status:** Not Started
**Priority:** P2 (UX polish - avoid showing spinner for empty projects)
**Effort:** 2-3 hours

- [ ] #P2-EMPTY-PROJECTS: Detect and immediately show empty state for projects with no conversation entries

**Problem:**
When switching to a project with no conversations, users see a "searching for conversations" spinner that then transitions to a "no conversations" view. This creates unnecessary loading state when we could determine emptiness immediately.

**Impact:**
- Confusing UX - spinner implies search is happening when result is predetermined
- Wasted time - users wait for spinner when answer is instant
- May indicate filtering bug - we previously tried to hide projects with 0 messages from tab bar

**Investigation Required:**
Add logging to verify SQL query filtering behavior:
- Log count of conversation entries per project during tab rendering
- Verify if projects with 0 entries should appear in tab bar at all
- Check if SQL query to filter projects with 0 entries was implemented incorrectly
- Determine if issue is detection logic vs display logic

**Solution:**

1. **Add SQL Query Logging** (1 hour)
   - Add `.info` level logs showing entry count per project in tab bar
   - Log SQL query used to filter projects: `SELECT project_id, COUNT(*) FROM timeline_entries GROUP BY project_id`
   - Verify if zero-entry projects are intentionally shown or filtering failed
   - Log to category: "ProjectFiltering" for easy grep

2. **Immediate Empty Detection** (1 hour)
   - Query entry count before showing spinner: `SELECT COUNT(*) FROM timeline_entries WHERE project_id = ?`
   - If count = 0, skip loading state and show empty view immediately
   - Add `hasAnyEntries` check to project switch logic
   - Cache result to avoid repeated queries

3. **Decision on Zero-Entry Projects** (30 min)
   - Review logs to determine if zero-entry projects should be hidden from tab bar
   - If filtering intended: Fix SQL query and hide from tabs
   - If intentional display: Keep immediate empty state (faster UX)
   - Document decision in code comments

**Files:**
- `Contextify/Contextify/ConversationMonitor.swift` (project switch logic)
- `Contextify/Contextify/ProjectSwitcherView.swift` (tab bar rendering with logging)
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` (entry count query)

**Acceptance Criteria:**
- ✅ Logs show entry count for each project in tab bar
- ✅ SQL query for filtering projects with 0 entries is logged and verified
- ✅ Projects with no conversations show empty state immediately (no spinner)
- ✅ Decision documented: hide zero-entry projects from tabs OR show with instant empty state
- ✅ No "searching" spinner when switching to empty project

---

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

## Project Management (2 items) ⬇️

**Status:** Not Started
**Priority:** Demoted from P0 (can defer to post-launch)
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
- Show/hide functionality works across app restarts
- Excluded projects don't appear in discovery

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

## Projects Window Improvements (2 items)

**Status:** Not Started
**Priority:** P2 (UX improvements - nice to have)
**Effort:** 2 hours total

- [ ] #P2-PROJECTS-REFRESH-REVIEW: Investigate if manual "Refresh Projects" button is needed (1.5 hours)
- [ ] #P2-PROJECTS-EMPTY-STATE: Add first-run guidance to empty state (30 min)

**Context:** Projects window improvements for better UX consistency.

---

### #P2-PROJECTS-REFRESH-REVIEW: Review Auto-Refresh Behavior

**Question:**
ProjectsViewModel observes `AppStateOrchestrator` via `NotificationCenter.default.notifications(named: .appStateDidChange)`. Does this mean projects auto-refresh when discovery runs, making the manual "Refresh Projects" button redundant?

**Investigation Required:**
1. **Test auto-refresh:** Run discovery from welcome modal → Check if Projects window updates automatically
2. **Test manual addition:** Add new project directory manually → Check if it appears without clicking Refresh
3. **Review code:** Trace `AppStateOrchestrator.shared.state` changes → `ProjectsViewModel.updateFromOrchestrator()` flow
4. **Determine necessity:** Is "Refresh Projects" button actually needed?

**Potential Outcomes:**
- **If auto-refresh works:** Consider removing button OR making it less prominent (borderless button, secondary style, or move to menu)
- **If manual refresh needed:** Keep as-is, document why
- **Hybrid approach:** Keep button but add tooltip explaining when it's needed

**Files:**
- `Contextify/Contextify/ProjectsViewModel.swift` (lines 52-100: state observation)
- `Contextify/Contextify/ProjectsWindow.swift` (line 81: button)
- `app/Sources/ContextifyCore/Projects/AppStateOrchestrator.swift`

**Acceptance Criteria:**
- ✅ Documented: Does auto-refresh work?
- ✅ Decision made: Keep/remove/modify button
- ✅ Code updated based on decision
- ✅ User expectations clear (via tooltip or removal)

---

### #P2-PROJECTS-EMPTY-STATE: Add First-Run Guidance

**Problem:**
Empty state shows discovery paths but doesn't guide user on next steps. First-time users may not understand what triggers project discovery.

**Current Empty State (ProjectsWindow.swift:113-152):**
```
No Projects Found

We couldn't find any Claude Code or Codex CLI projects on your machine.

Projects are discovered from:
• ~/.claude/projects/*
• <project>/.codex/sessions/
```

**Suggested Addition:**
Add guidance text below the discovery paths:

```swift
Text("Start a conversation with Claude Code or Codex in any project, and it will appear here automatically.")
  .font(.caption)
  .foregroundStyle(.secondary)
  .multilineTextAlignment(.center)
  .padding(.top, 12)
```

**Alternative (More Concise):**
```
"Projects appear automatically when you use Claude Code or Codex."
```

**Files:**
- `Contextify/Contextify/ProjectsWindow.swift` (lines 113-152)

**Acceptance Criteria:**
- ✅ Guidance text added to empty state
- ✅ Explains what triggers project discovery
- ✅ Matches overall tone and style
- ✅ Doesn't clutter the UI

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
- Implementation plan: `build/notes/todo-support/P2-SWITCH-refactor-plan.md`
- Source code analysis: `build/notes/todo-support/P2-SWITCH-source-analysis.md`

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

## TODO Management Agent (1 item)

**Status:** Research complete, ready to implement
**Priority:** P2 (workflow improvement - frequently managing TODOs)
**Effort:** 6-8 hours

- [ ] #P2-TODOS-AGENT: Build intelligent TODO management agent (create, update, prioritize, clean up)

**Goal:** Full-featured agent that understands TODO/ROADMAP workflows and manages them intelligently.

**Agent Capabilities:**
1. **Create TODOs**
   - Auto-generate IDs (P{N}-{SLUG} format)
   - Insert in correct priority section
   - Create supporting docs in `build/notes/todos/` with YAML front matter
   - Reference research files appropriately

2. **Manage TODOs**
   - Update priorities based on context
   - Move items between TODOS.md and ROADMAP.md
   - Update status and estimates
   - Link related items

3. **Clean Up TODOs**
   - Remove completed items
   - Archive obsolete supporting docs
   - Consolidate duplicate/similar items
   - Flag stale TODOs for review

4. **Workflow Knowledge**
   - Understands priority levels (P0-P5)
   - Knows doc reference standards (YAML front matter, naming conventions)
   - Follows `/tmp/` → `build/notes/todos/` workflow
   - Links to research files and specs appropriately

**Implementation approach:**
1. Create `.claude/agents/todos-manager/` (Claude Code native agent)
2. Create `~/.codex/prompts/todos.md` (Codex workaround via slash command)
3. Agent prompt includes full context:
   - TODOS.md and ROADMAP.md formats
   - Doc reference standards from TODOS.md front matter
   - Priority definitions and workflows
4. Optional: MCP server for richer integration

**Research:** `~/code/projects/cli-ai-setup/notes/cross-cli-agent-research-2025-11-21.md`

**Related:**
- ROADMAP.md#P4-AUTONOMOUS-DEVELOPMENT (future vision - full autonomy)
- `build/notes/todo-support/` directory (supporting docs)
- TODOS.md front matter (standards and workflows)

---

## Branch Management (1 item)

**Status:** Not Started
**Priority:** P2 (Technical debt - token burn branches need review)
**Effort:** 8-12 hours

- [ ] #P2-TOKEN-BURN: Review and catalog token burn branches from Nov 18-19, 2025

**Background:**
Multiple branches created during late-night token burn session with speculative code, documentation, marketing plans, and experimental features. Need comprehensive review and cataloging before any integration.

**Scope:**

1. **Branch Analysis** (2-3 hours)
   - Fetch all remote branches from last 24-48 hours
   - Examine branches starting with `claude/` or created Nov 18-19
   - Categorize by content type: Code, Documentation, Marketing, Research, Configuration
   - Assess review priority: High, Medium, Low
   - Identify dependencies and conflicts between branches

2. **Reference Document Creation** (2-3 hours)
   - Create `build/docs/audits/TOKEN_BURN_BRANCHES_2025-11-18.md`
   - Document each branch: type, description, files changed, status, action required
   - Organize by priority (high/medium/low) and category
   - List commit messages and key changes for each branch
   - Note special cases: breaking changes, duplicate work, experimental APIs

3. **TODO Integration** (1 hour)
   - Add specific review tasks to TODOS.md for each branch
   - Flag branches requiring code review vs documentation extraction
   - Create action items for high priority integrations
   - Document migration plans for breaking changes

4. **Recommendations** (1 hour)
   - Identify branches ready for immediate merge (small, safe changes)
   - Flag branches needing thorough code review (complexity, risk)
   - Extract non-code content (marketing, docs) to appropriate locations
   - Determine which experiments should be archived vs deleted

**Important Constraints:**
- ❌ DO NOT automatically merge any branches without review
- ❌ DO NOT delete branches without documenting first
- ❌ DO NOT consolidate code without manual review
- ❌ DO NOT integrate breaking changes without migration plan
- ✅ DO create comprehensive reference for manual review
- ✅ DO categorize by type and priority
- ✅ DO identify dependencies between branches
- ✅ DO flag risky/breaking changes prominently

**Deliverables:**
- Reference document: `build/docs/audits/TOKEN_BURN_BRANCHES_2025-11-18.md`
- Updated TODOS.md with specific review tasks per branch
- Summary statistics (X branches, Y code, Z docs, etc.)
- Prioritized recommendations for next steps
- Warnings about breaking changes or conflicts

**Special Considerations:**
- Marketing plans → Consider moving to project docs or separate repo
- Completed features → Test thoroughly before merge
- Breaking changes → Requires migration plan and careful review
- Duplicate work → Check if superseded by other work
- Experimental APIs → Requires architecture review

**Reference:** `build/notes/todo-support/P2-TOKEN-BURN-prompt.md`

---

## Background LLM Processing (1 item)

**Status:** Not Started
**Priority:** P2 (UX improvement - pre-generate summaries when app is backgrounded)
**Effort:** 4-6 hours

- [ ] #P2-BACKGROUND-SUMM: Re-implement background LLM summarization for "would-be-visible" entries

**Problem:**
Currently, when app is backgrounded (user switches away), LLM summary generation is completely disabled. The log message is confusing: "App resigned active - background processing DISABLED". This is a policy decision, not a bug, but it's a missed opportunity.

**Previous Implementation:**
Background summarization used to exist but was removed at some point. Worth investigating git history to see:
- Why it was removed (performance? battery? user feedback?)
- What the implementation looked like
- Any useful code/patterns to reuse

**Proposed Behavior:**
When app goes to background, continue summarizing entries that would be "visible" if the user scrolled back in timeline. This would:
- Pre-populate summaries for entries user is likely to see
- Make timeline feel more responsive when app returns to foreground
- Avoid wasted work (only summarize what user might actually view)

**Implementation Approach:**
1. **Define "Would-Be-Visible" Scope** (1 hour)
   - Current viewport + N entries above/below scroll position
   - Or: All entries within last X hours/days
   - Or: Based on user's typical scroll depth
   - Consider: How far back do users typically scroll?

2. **Background Task Management** (2-3 hours)
   - Implement low-priority background LLM queue
   - Respect system resource constraints (low battery, thermal pressure)
   - Pause during active calls, media playback
   - Cancel if app terminated

3. **Smart Prioritization** (1 hour)
   - Prioritize recent entries over old ones
   - Skip entries already summarized
   - Deprioritize if user never scrolls back

4. **Logging & Observability** (30 min)
   - Update confusing log message to explain policy clearly
   - Log when background processing starts/stops
   - Track: summaries generated while backgrounded, battery impact

**Git History Investigation:**
Search for commits related to:
- "background" + "summarization" or "LLM"
- `handleAppResignActive()` implementation changes
- Removal of background processing code
- Performance issues or user complaints

Commands:
```bash
git log --all --grep="background.*summar" -i
git log --all --grep="resign.*active" -i -- "**/ConversationMonitor.swift"
git log -S "background processing" --all
```

**Files:**
- `Contextify/Contextify/ConversationMonitor.swift:2390-2395` (handleAppResignActive)
- Likely: LLM queue management code
- Likely: Timeline cache/priority logic

**Acceptance Criteria:**
- ✅ Background summarization generates summaries for would-be-visible entries
- ✅ Respects system resource constraints (battery, thermal)
- ✅ Logs clearly explain background processing status
- ✅ No performance degradation when app returns to foreground
- ✅ User doesn't notice lag when scrolling to pre-summarized content

**Related:**
- Confusing log message: "App resigned active - background processing DISABLED"
- Should clarify: This is intentional policy, not a bug

---

## Timeline Display Enhancement (1 item)

**Status:** Not Started
**Priority:** P2 (UX polish - improved code readability in timeline)
**Effort:** 2-3 hours

- [ ] #P2-MONOSPACE: Render backtick-enclosed text in monospace font in timeline entries

**Problem:**
Timeline entries display inline code (backtick-enclosed text) in the same proportional font as regular text, making code snippets, function names, and technical terms harder to read and identify at a glance.

**Example:**
Current display uses proportional font for all text including backticked content:
```
Claude Code suggested creating `todos.md` in `/Users/rob/code/projects/contextify/`.
```

Should render backticked text in monospace for better readability:
- `todos.md` → rendered in monospace
- `/Users/rob/code/projects/contextify/` → rendered in monospace
- Regular text → rendered in system font

**Implementation:**

1. **Text Parsing** (1 hour)
   - Parse timeline entry text (summary, detail fields) for backtick patterns
   - Detect inline code: single backticks `` `code` ``
   - Handle edge cases: escaped backticks, nested backticks, unclosed backticks
   - Split text into segments: regular text vs code spans

2. **SwiftUI Rendering** (1 hour)
   - Use `Text` concatenation with `.font(.system(.body, design: .monospaced))`
   - Build attributed text with mixed fonts:
     - Regular segments: system font
     - Code segments: monospace font
   - Preserve existing styling (color, size, weight)
   - Ensure proper spacing and line breaks

3. **Testing** (30 min)
   - Test with various backtick patterns:
     - Single word: `` `todos.md` ``
     - Path: `` `/Users/rob/path` ``
     - Multiple in one line: `` `file.swift` and `other.swift` ``
     - Edge cases: unclosed backticks, escaped backticks
   - Verify rendering in timeline rows (summary and detail views)
   - Check performance with long text containing many code spans

**Files:**
- `Contextify/Contextify/TimelineEntryRow.swift` (entry display)
- `Contextify/Contextify/ConversationMonitor.swift` (if text preprocessing needed)
- Possibly new helper: `Contextify/Contextify/Views/FormattedText.swift` (reusable component)

**Acceptance Criteria:**
- ✅ Backtick-enclosed text renders in monospace font
- ✅ Regular text remains in system font
- ✅ Proper handling of multiple code spans in one entry
- ✅ Edge cases handled gracefully (unclosed, escaped backticks)
- ✅ No performance degradation with long text
- ✅ Styling preserved (colors, emphasis)

**Benefits:**
- Improved readability of technical content in timeline
- Easier to spot file paths, function names, code snippets
- More professional appearance matching developer tools
- Consistent with markdown rendering conventions

**Example Timeline Entries to Test:**
- "Claude Code suggested creating `todos.md` in `/Users/rob/code/projects/contextify/`."
- "Fixed `ConversationMonitor.swift` warnings in `startWatchingTranscript()`"
- "Updated `README.md` with `npm install` instructions"

---

# P3 (Low Priority / Deferred) - 12 Items

## Liquid Glass Design System (1 item) ⬇️

**Status:** Partially implemented, toolbar translucency deferred
**Priority:** Demoted from P2 (SwiftUI toolbar API limitations, diminishing returns)
**Effort:** Unknown (requires AppKit or future SwiftUI improvements)
**Documentation:** `build/docs/audits/liquid-glass-status.md`

- [ ] #P3-LIQUID-GLASS: Complete Liquid Glass toolbar translucency for macOS 26

**What Shipped (~40%):**
- ✅ Glass button effects (`.glassEffect()` on macOS 26)
- ✅ Lightened menu icons for contrast
- ✅ Reduced opacity backgrounds
- ✅ Horizontal project tabs with glass effect
- ✅ NavigationStack infrastructure

**What's Deferred:**
- ❌ Toolbar translucency (content blurring under toolbar)
- ❌ Tabs fixed in toolbar (vs scrolling)

**Blocker:**
SwiftUI's `.navigationTitle()` conflicts with `.principal` toolbar placement. Tabs either:
1. Render in toolbar but disappear after initial paint (SwiftUI lifecycle bug)
2. Scroll beneath toolbar (defeats visual purpose)

**Options for Future:**
1. Drop to AppKit NSToolbar (full control, significant effort)
2. Build custom window chrome (lose system integration)
3. Wait for SwiftUI improvements in macOS 27+

**Decision:** Ship current partial implementation (~40% visual improvement). Re-evaluate post-launch based on user feedback.

**Reference:** `build/docs/audits/liquid-glass-status.md` (full implementation history)
**Branch:** `feat/liquid-glass-implementation` (commit 60ca32e)

---

## Restore Diagnostics HTTP API (1 item)

**Status:** Blocked (waiting for P0-REMOVE-HTTP-API completion)
**Priority:** P3 (Post-launch feature)
**Effort:** 1-2 hours

- [ ] #P3-RESTORE-HTTP-API: Re-enable diagnostics HTTP server for external tooling

**Context:**
The diagnostics HTTP server was removed before initial release (see P0-REMOVE-HTTP-API). This feature allows external scripts to query timeline state via localhost HTTP API.

**Removal Commit:** _(To be documented when P0-REMOVE-HTTP-API is completed)_

**Files to Restore:**
- `app/Sources/ContextifyCore/Diagnostics/DiagnosticsHTTPServer.swift`
- `app/Sources/ContextifyCore/Diagnostics/DiagnosticsExporter.swift` (if removed)
- `ConversationMonitor.swift` initialization code

**Implementation:**
1. Revert or cherry-pick the removal commit
2. Update `DiagnosticsConfig.enableHTTPServer` to be configurable (settings pane or DEBUG-only)
3. Document the HTTP API endpoints for external tooling
4. Consider auth/security for localhost endpoint

**Use Cases:**
- External scripts querying timeline state (`scripts/timeline_api.sh`)
- Automated testing harnesses
- Integration with other developer tools

---

## Off-Screen Project Activity Indicator (1 item)

**Status:** Not Started
**Priority:** P3 (UX enhancement - nice to have)
**Effort:** 2-4 hours

- [ ] #P3-OFFSCREEN-ACTIVITY: Indicate when new messages appear in off-screen projects

**Problem:**
When the project tab bar has many projects, some are scrolled out of view. If a non-visible project receives new transcript activity, the user has no indication that something is happening. They may miss important updates from background sessions.

**Expected Behavior:**
When a project not currently visible in the tab bar receives new messages:
1. Show an indicator that activity is occurring off-screen (e.g., pulsing dot or arrow on the scroll edge)
2. OR show a toast/notification in the app or macOS notification center
3. OR add a badge count to the tab bar edge indicating N projects with new activity

**Implementation Options:**

**Option A: Edge Indicator (Recommended)**
- Track which project tabs are visible in viewport
- When non-visible project gets activity, show indicator on the edge (left/right arrow with pulse)
- Clicking indicator scrolls to the active project

**Option B: In-App Toast**
- Show brief toast at top/bottom: "New activity in [project-name]"
- Toast auto-dismisses after 3-5 seconds
- Clicking toast switches to that project

**Option C: macOS Notification**
- Use `UserNotifications` framework
- Show notification: "Contextify: New activity in [project-name]"
- Only when app is not frontmost (avoid interruption)

**Files:**
- `Contextify/Contextify/ContentView.swift` (project tab bar)
- `Contextify/Contextify/ConversationMonitor.swift` (activity detection)
- Possibly new `ActivityIndicator.swift` view component

**Acceptance Criteria:**
- User can tell when off-screen project has new activity
- Indicator is subtle but noticeable
- Easy to navigate to the active project
- No false positives (only triggers on actual new content)

---

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

## Code Quality (1 item)

**Status:** Not Started
**Priority:** P3 (low priority refactoring)
**Effort:** 1-2 hours

- [ ] #91: Remove hardcoded magic number 25 for timeline entry limits

**Details:**
- Currently hardcoded in 3 places:
  - `ConversationMonitor.swift:185` - `visibleEntryLimit = 25`
  - `TimelineModels.swift:252` - `maxEntries: Int = 25`
  - `TranscriptMetadataFormatters.swift:21` - `fullStrategyLimit = 25`
- Should be centralized constant or user preference
- Low priority: current value works fine, just poor code hygiene

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

## P0: Disable Git Monitoring in Sandboxed Builds ✅ COMPLETE → SUPERSEDED

**Status:** ✅ Complete (2025-11-15) → **Superseded by P1 #P1-GIT-BRANCH**
**Commit:** `b0abdb4` - fix(sandbox): disable git monitoring in App Store builds
**Branch:** `claude/codex-discovery-fix-012fkAJXMWvjrfWZPh7xhPEm`

**Note:** This temporary solution disabled git monitoring entirely in sandboxed builds. **New approach (P1 #P1-GIT-BRANCH)** uses transcript-based branch tracking to ENABLE branch display in App Store builds without filesystem access.

### Old Problem (Solved by Disabling)

Git branch monitoring completely broken in sandboxed builds. Console spam every 2 seconds:
```
error  [GIT-BROKEN] Git monitoring failed (no project root access in sandboxed build)
error  [GIT-BROKEN] No project root bookmark (git monitoring unavailable in sandboxed build)
```

**Root cause:** Requires user permission to project root directories.

### Old Solution (Temporary - Now Being Replaced)

Simple, fast approach:
1. Early return from `updateHeadWatcher()` if sandboxed (skip all git logic) ✅
2. Hide branch UI in sandboxed builds (show project name only) ✅
3. Remove bookmark restoration attempts in sandboxed builds ✅

**Result:** Clean logs, zero errors, but NO branch display in App Store.

### New Solution (P1 #P1-GIT-BRANCH)

Extract branch from transcript data instead of filesystem:
- Claude Code: Read `gitBranch` from any message
- Codex: Read `session_meta.payload.git.branch` from last session_meta
- Display branch with InfoButton explaining source and lag
- Zero filesystem access required
- Works in App Store builds

**See:** P1 section for full specification of transcript-based approach

### Old Tasks (Completed for Temporary Solution)

- [x] **[NOGIT1]** Early return from `updateHeadWatcher()` if sandboxed ✅
- [x] **[NOGIT2]** Remove bookmark restoration in `handleCoordinatorUpdate()` ✅
- [x] **[NOGIT3]** Hide branch display in header ✅
- [x] **[NOGIT4]** Test App Store build - verified zero errors ✅
- [x] **[NOGIT5]** Verify zero `[GIT-BROKEN]` errors ✅

**Files Modified (Will Be Partially Reverted by P1 Implementation):**
- `app/Sources/ContextifyCore/HUDCore.swift` (git monitoring disabled)
- `Contextify/Contextify/ContentView.swift` (branch UI hidden - will be restored)

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

## Automated Product Development Monitoring (1 item)

**Status:** Concept - needs design specification
**Priority:** P3 (valuable infrastructure, not blocking)
**Effort:** Medium-Large (initial setup), Low (ongoing maintenance)

- [ ] #P3-AGENTIC-DEVOPS: Build GitHub Actions service for upstream monitoring and conformance testing

**Proposed Service:**
1. **External Repo Monitoring** - Watch Gemini CLI, Claude Code, Codex CLI releases for transcript-relevant changes
2. **Transcript Format Conformance Testing** - Recurring job creates fresh conversations, analyzes against expected format
3. **Regression Suite** - Test edge cases, known corruption patterns

**Expected Outcomes:**
- Early warning of breaking changes
- Discovery of new feature possibilities
- Living documentation that stays in sync with reality

---

# CROSS-REFERENCE: Item Number → Priority

**P0 (25):** #2-9, #16, #29-30, #32, #35, #43, #45-47, #49-50, #58-59

**P1 (18):** #19-23, #51, #54-56, #71-72, #79-83, #85-88, #91

**P2 (19):** #13-14, #24-25, #27-28, #37-40, #48, #52, #57, #60, #63-66

**P3 (8):** #61, #67-70, #76, #89-90

**Removed (22):** #1, #10-12, #15, #17-18, #26, #31, #33-34, #36, #41-42, #44, #53, #62, #73-75, #77-78, #84, #92

---

**End of TODO List**
