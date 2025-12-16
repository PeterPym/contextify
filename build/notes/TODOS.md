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
  naming: "{ID}-{type}.md (e.g., AUTOSCROLL-spec.md, SWITCH-investigation.md)"
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

**Last Updated:** 2025-12-14
**Status:** Active

**Priority Levels:**
- **P0 (Launch Critical):** Release blockers
- **P1 (High Priority):** Important for quality/UX, ship soon after launch
- **P2 (Medium Priority):** Nice to have, can defer to future releases
- **P3 (Low Priority / Deferred):** Future enhancements

---

## Active Work

**Tracking:** `build/notes/active-work.md` (gitignored, local only)

See tracking file for current branches in flight and review status.

---

# P0 (Launch Critical)

---

## Historical Transcript Ingestion Gap

**Status:** Core fix complete (2025-12-14), follow-up items in P1
**Priority:** P0 (data loss - user history not searchable)
**Discovered:** 2025-12-13
**Branch:** `fix/ingest-gap-historical-transcripts`

- [x] #INGEST-GAP: Fix missing historical transcript ingestion

**Fix Applied (2025-12-14):**

1. **Added `startWatching` parameter** to `ingestTranscript()` - completion work uses `false` to avoid watcher explosion
2. **Bounded worker pool** (4 workers max) replaces unbounded `Task.detached`
3. **Enqueue ALL remaining transcripts** immediately after preview subset (not blocked on preview)
4. **Added `watcherCount` getter** to TranscriptWatcher for diagnostics

**Results:**
- Coverage improved from 1.7% to 95.1% for active main session transcripts
- Remaining 5% are legitimately empty files (0 bytes, session-only metadata)
- Build: zero warnings, 196 tests passing

**Follow-up items (see P1):**
- `#INGEST-PARSER-BUG`: Some transcripts with content produce 0 entries
- `#INGEST-PERIODIC-CHECK`: No periodic check for late-arriving partials

**Reference:** `app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`

---

## Permission Fix for Dual-CLI Users (1 item)

**Status:** Complete (verified 2025-12-11, E2E test backlogged)
**Priority:** P0 (blocking v1.0.1 release)
**Branch:** `fix/permission-discovery-logging`

- [x] #PERMISSION-FIX-QA: Validate permission fix with regression tests

**Background:**
Dual-CLI users (both Claude Code and Codex) experience issues when granting a second
transcript provider permission via Settings. Two bugs were fixed:
1. Second permission ignored - discovery didn't see newly-authorized provider
2. Watcher recovery using stale orchestrator - health checks used old access provider

**Fixes Applied:**
- NotificationCenter pattern for permission change notification (87bf979a)
- Permission observer in AppLifecycleState singleton (not tied to window)
- Onboarding guard to prevent racing with wizard flow
- Health monitoring now uses current orchestrator (not captured at task start)

**QA Requirements (both builds required):**

**App Store build:**
1. Clean install (delete app, run `make clean-db`)
2. Launch app - onboarding wizard appears
3. Grant Claude Code permission only, complete onboarding
4. Verify Claude projects discovered
5. Open Settings > Permissions, grant Codex
6. Verify: Both Claude AND Codex projects now appear
7. Check logs: No `WATCHER-RECOVERY-ERROR` with sandbox container paths
8. Wait 60+ seconds, verify no recurring recovery errors

**DMG build:**
1. Build: `bash scripts/xc.sh build`
2. Launch app
3. Verify all projects discovered immediately
4. No permission-related errors in logs
5. Health checks run without errors

**Reference:** `Contextify/Contextify/ContextifyApp.swift:100-143`, `Contextify/Contextify/ConversationMonitor.swift:3269-3367`

---

## QA Review and Recent Feature Cleanup (4 items)

**Status:** Complete
**Priority:** P0 (code review debt from autonomous work)
**Context:** QA Phase 2 left fixtures installed without cleanup docs. GIT-BRANCH and EXPANSION-STATE were merged without review during autonomous work.

**Completed 2025-12-11:** All 4 tasks reviewed - no code issues found, documentation gaps filled.

### Task 1: QA Documentation Audit
**Branch:** `fix/qa-docs-audit`
- [x] #QA-REVIEW-1: Find QA Phase 1/2 merge commits, inventory docs created
  - Found: `bf02cfc9` (Phase 1), `d4cae01e` (Phase 2)
  - Docs created: `scripts/qa/README.md`, fixture READMEs
- [x] Identify gaps: Missing "cleanup after local QA" section
- [x] Add missing docs to scripts/qa/README.md (cleanup section added)
- [x] Update cross-references in AGENTS.md (QA suite now referenced in Quick Commands and Testing sections)

### Task 2: Code Review - QA Phase 2
**Branch:** `fix/qa-phase2-review`
- [x] #QA-REVIEW-2: Generate /review-prep package, review implementation, address issues
  - Reviewed 6 commits: fixture infrastructure, assertions, modified tests, new tests, CI
  - No issues found - implementation is solid

### Task 3: Code Review - GIT-BRANCH
**Branch:** `fix/git-branch-review`
- [x] #QA-REVIEW-3: Review transcript-based git branch (TranscriptOrchestrator, HUDCore, ContentView)
  - Reviewed 2 commits: orchestrator methods, HUD fallback chain, ContentView UI
  - Clean implementation with proper error handling and validation logging

### Task 4: Code Review - EXPANSION-STATE
**Branch:** `fix/expansion-state-review`
- [x] #QA-REVIEW-4: Review timeline expansion persistence (ConversationTimelineView, TimelineEntryRow)
  - Reviewed 1 commit: Set<UUID> tracking, binding pattern, project switch reset
  - Clean implementation with efficient state management

---

## Log Analysis Issues

**Status:** Complete
**Priority:** P0 (blocking quality release)

- [x] #LOG-ISSUES: Fix issues identified in Dec 2025 log analysis ✅ DONE

**Completed 2025-12-11:**

1. **Transcript validation** - Skip summary lines in structural validation (was rejecting 108 transcripts)
2. **Watcher recovery loop** - Added exponential backoff with 5-retry limit (was looping 96+ times)
3. **Timeline refresh rate** - Added refresh coalescing (reduced 10+/5s to max 2 refreshes)
4. **Codex getCWD** - Use JSONSerialization + scan 5 lines (fixed 3000+ failures)
5. **AI cancellation noise** - Log at debug level instead of error (reduced 45+ warnings)

**Investigation:** `build/notes/todo-support/log-analysis-2025-12-09.md`

---

# P1 (High Priority)

---

## Missing 112 Transcripts - Never Ingested

**Status:** Not started
**Priority:** P0 (data completeness - 9.3% of transcripts missing)
**Discovered:** 2025-12-15
**Related:** `#INGEST-GAP`

- [ ] #INGEST-GAP-REMAINING: Investigate why 112 transcripts never made it into database

**Current state (2025-12-15 23:10):**
- On disk: 1,208 transcripts
- In database: 1,096 transcripts
- **Not ingested: 112 transcripts (9.3%)**

**Possible causes:**
1. Transcripts in projects that weren't monitored at startup
2. Transcripts arrived after app startup (late-arriving files)
3. FastPath worker pool completed before discovering these files
4. Permission issues or file access errors
5. Files created after initial project scan

**Investigation queries:**
```bash
# Get all file paths on disk
find ~/.claude/projects ~/.codex/sessions -name "*.jsonl" > /tmp/disk_transcripts.txt

# Get all file paths in DB
sqlite3 "$DB_PATH" "SELECT file_path FROM transcripts;" > /tmp/db_transcripts.txt

# Find missing ones
comm -23 <(sort /tmp/disk_transcripts.txt) <(sort /tmp/db_transcripts.txt)
```

**Next steps:**
1. Run investigation queries to identify specific missing transcripts
2. Check if they're in specific projects (pattern analysis)
3. Check file creation dates vs app startup time
4. Check ingestion logs for errors related to these files
5. Determine if this is related to #INGEST-PERIODIC-CHECK need
6. Fix and test with clean build (5-7 min full ingestion time)

**Reference:** `app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`

---

## Transcript Parser Bug - Content Without Entries

**Status:** Not started
**Priority:** P0 (data completeness - 6.8% of transcripts unusable)
**Discovered:** 2025-12-14, analyzed 2025-12-15
**Related:** `#INGEST-GAP`

- [ ] #INGEST-PARSER-BUG: Fix parser for 82 transcripts with content but 0 entries

**Updated analysis (2025-12-15):**
- Total transcripts: 1,208
- In database: 1,096
- With 0 entries: 719 (but 637 are agent sidechains - correct behavior!)
- **Real parser failures: 82 transcripts (6.8%)**
  - 73 Claude regular conversations (non-agent files)
  - 9 Codex transcripts

**Important:** Agent sidechains (files matching `agent-*.jsonl`) SHOULD have 0 entries. They're background work files with `isSidechain: true`, not conversations.

**Evidence (FCB3B514):**
- File: `/Users/rob/.claude/projects/-Users-rob-code-projects-contextify/FCB3B514-A11B-419D-8157-E1BE18DEC02B.jsonl`
- Size: 85KB (88 lines)
- Content: 26 assistant messages, 31 user messages with `userType: "external"`
- All have `isSidechain: false`
- DB shows: `ingest_state: complete`, `last_processed_line: 88`, but 0 entries

**Parser analysis:**
- `extractContentWithType()` should handle string content (line 274-275)
- `validateMessageIntegrity()` returns `false` for string content (line 355-358)
- No parse errors recorded in `parse_errors` table

**Next steps:**
1. Sample 5-10 failing transcripts (use query from continuation doc)
2. Examine file structure and identify common patterns
3. Add parser logging for these specific cases
4. Fix parser to handle these edge cases
5. Test with clean build (5-7 min full ingestion time)

**Reference:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

---

## Periodic Ingestion Check for Resilience

**Status:** Not started
**Priority:** P1 (robustness - may explain some of the 112 missing transcripts)
**Discovered:** 2025-12-14
**Related:** `#INGEST-GAP`, `#INGEST-GAP-REMAINING`

- [ ] #INGEST-PERIODIC-CHECK: Add periodic check for partial transcripts

**Problem:**
`resumePendingCompletions()` only runs once at app startup. Transcripts marked `partial` after startup (manual DB edits, edge cases, late-arriving files) are never picked up until app restart.

**Possibly related to 112 missing transcripts:** If transcripts arrive after app startup or after FastPath completes, they won't be ingested until next restart. Periodic check would catch these late arrivals.

**Current behavior:**
- `AppStateOrchestrator.swift:89-92` - runs once during init
- `ProjectSwitcherState.swift:182-183` - runs once when coordinator initialized
- No periodic timer or event-driven re-check

**Proposed fix:**
Add a periodic check (every 5-10 minutes) or event-driven trigger:
1. Timer-based: `Timer.scheduledTimer` calling `resumePendingCompletions()`
2. Event-driven: Trigger on project switch, settings change, or file system events
3. Hybrid: Event-driven with minimum interval to avoid thrashing

**Acceptance criteria:**
- Partial transcripts picked up within 10 minutes without app restart
- No performance impact during normal operation
- Proper cancellation on app termination

**Reference:** `app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`

---

## v1.0 Launch Follow-up

**Status:** Core launch complete, follow-up submissions pending
**Priority:** P1

- [ ] #LAUNCH-FOLLOWUP: Complete additional launch submissions

**Done:**
- [x] Twitter announcement
- [x] Reddit post
- [x] Show HN

**Remaining:**
- [ ] TinyLaunch submission (inbound invite)
- [ ] Product Hunt (when ready)
- [ ] Monitor and respond to feedback (ongoing)

---

## macOS 15 Testing VM

**Status:** Not started
**Priority:** P1 (needed for legacy macOS QA)

- [ ] #MACOS15-VM: Set up macOS 15 (Sequoia) VM for testing

**Purpose:** Validate lite mode and backward compatibility on older macOS versions.

**Setup steps:**
1. Install UTM: `brew install --cask utm`
2. Create new VM: Virtualize → macOS
3. Download macOS 15 IPSW (~13GB)
4. Allocate 4GB RAM, 60GB disk
5. Complete macOS setup
6. Build and test Contextify DMG

**Test cases:**
- [ ] App launches without dyld crash (proves `canImport` guards work)
- [ ] Lite mode UI displays correctly
- [ ] Timeline shows fallback content (no summaries)
- [ ] Status bar shows "Lite Mode"
- [ ] Search and indexing work normally

---

## Performance Profiling & Optimization

**Status:** Fixes complete, instrumentation optional
**Priority:** P1 (addresses LOG-ISSUES performance problems)
**Effort:** 1-2 hours remaining (instrumentation only)
**Guide:** `build/notes/todo-support/PERFORMANCE-PROFILING-guide.md`

- [~] #PERFORMANCE-PROFILING: Core fixes complete, optional instrumentation remains

**Completed (via #LOG-ISSUES):**
- ✅ Timeline refresh coalescing (pendingRefreshAfterLoad flag)
- ✅ Exponential backoff for watcher recovery (5 retries, then give up)
- ✅ Security scope handling (backoff handles unavailable scope)

**Optional Remaining Work:**
1. **Add os_signpost instrumentation** - for future debugging
2. **Create profiling script** - `scripts/profile.sh`
3. **Validate with profiling** - before/after comparison

**Acceptance Criteria (verified by log analysis fixes):**
- ✅ Timeline refresh collapses N notifications into 1 refresh
- ✅ Watcher recovery gives up after 5 failed attempts

---

## QA Suite App Store Validation (1 item)

**Status:** Ready for implementation
**Priority:** P1 (required before Phase 2 QA)
**Effort:** 1-2 hours

- [x] #QA-APPSTORE-VALIDATION: Validate QA tests work correctly with App Store build ✅ DONE

**Completed 2025-12-11:**
- Added Enter key support to onboarding wizard (keyboard-driven flow)
- QA-01c passes: clean install with full onboarding automation
- Uses `click_group_button` helper for SwiftUI buttons that don't expose names
- Validates via logs (user selects custom DB location during onboarding)

---

## QA Suite Phase 2 Implementation (1 item)

**Status:** Complete
**Priority:** P1 (enables CI integration)
**Effort:** 4-6 hours
**Plan:** `build/notes/todo-support/QA-PHASE-2-plan.md`

- [x] #QA-PHASE-2: Implement fixture-based testing, search tests, DB migration tests, and CI integration ✅ DONE

**Completed 2025-12-11:**
- Fixture infrastructure (QA_FIXTURE_MODE, seed helpers, TEST_PROJECT config)
- Fixture-based transcript tests (QA-03, QA-04 work in fixture mode)
- Search tests (QA-10 Quick Search, QA-11 Deep Search)
- DB migration test (QA-09 with v16 and v25 schema fixtures)
- CI workflow integration (GitHub Actions runs QA suite in fixture mode)

**Note:** CI has pre-existing `swift test` failure (macOS 15 runner lacks macOS 26 SDK). QA tests pass locally.

---

## Sparkle Release Automation (1 item)

**Status:** Design complete, awaiting user answers before implementation
**Priority:** P1 (release workflow improvement)
**Effort:** 4-6 hours
**Design:** `/tmp/sparkle-release-workflow-design.md`

- [ ] #SPARKLE-RELEASE: Extend release.py with guided Sparkle signing, appcast updates, and website deployment

**Summary:**
Extend `scripts/release.py` to include Sparkle signing, appcast.xml updates, and website deployment with interactive verification prompts at key checkpoints.

**Blockers:** 6 design questions need answers before implementation (see `/tmp/sparkle-release-workflow-status.md`)

**Key Features:**
- Phase 2: Sparkle EdDSA signing + appcast update
- Phase 3: Website deployment (DMG, appcast, release notes)
- Interactive checkpoints with `--yes` for automation
- Server directory creation (releases/, release-notes/)

---

## Timeline Query Centralization

**Status:** Deferred to P1 (after P0 filter fixes ship)
**Priority:** P1 (Prevent future filter drift bugs)
**Effort:** 8-12 hours (requires refactoring all query callsites)

- [ ] #QUERY-CENTRALIZE: Eliminate duplicate SQL implementations, create single source of truth for timeline queries

**Problem:** Multiple functions loading timeline entries with inconsistent filters.

**Evidence:**
- `entriesAfterCursor()` in Repositories (GRDB builder, correct, UNUSED)
- `getEntriesAfterCursor()` in TranscriptOrchestrator (raw SQL, was broken, USED)
- 7 total functions doing similar things with different approaches

**Architectural smell:** TranscriptOrchestrator reimplements queries with raw SQL instead of delegating to Repositories.

**Goal:** Single composable query builder that enforces visibility filter by default.

**Design:**
```swift
final class TimelineEntryQuery {
    func forProject(_ id: String) -> Self
    func visibleOnly() -> Self  // display_in_timeline = 1
    func afterCursor(_ cursor: EntryCursor) -> Self
    func byTranscript(_ id: String) -> Self
    func search(_ text: String) -> Self
    func limit(_ n: Int) -> Self
    func fetch() throws -> [TranscriptEntry]
}

// Usage (filter always explicit)
let entries = TimelineEntryQuery()
    .forProject(projectId)
    .visibleOnly()
    .afterCursor(cursor)
    .fetch()
```

**Plan:** `build/notes/todo-support/QUERY-CENTRALIZE-design.md`
**Source Analysis:** `build/notes/todo-support/QUERY-CENTRALIZE-source-analysis.md`

**Benefits:**
- Impossible to forget filter
- Single source of truth
- Easier to maintain and extend
- Prevents future filter drift bugs

**Scope:**
- Create TimelineEntryQuery builder class
- Refactor all 7 query functions to use builder
- Update all callsites in ConversationMonitor, TranscriptOrchestrator
- Remove duplicate implementations

**Testing:**
- Existing unit tests should pass unchanged
- Add builder-specific tests
- Integration test: timeline loading still works

**Rollback:** Can revert to old implementation if issues found

---

## Project Auto-Discovery & QA Setup (1 item)

**Status:** Not Started
**Priority:** P1 (Critical for launch QA)
**Effort:** 6-8 hours

- [ ] #DISCOVERY-QA: Clean up and QA project auto-discovery with DevOps tooling

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

## Unread Count Investigation (1 item)

**Status:** Not Started
**Priority:** P1 (UX - unread count behavior unclear and doesn't follow standard patterns)
**Effort:** 4-6 hours

- [ ] #UNREAD-COUNT: Investigate and fix unread count calculation and clearing behavior

**Problem:**
The calculation of unread counts in project tabs is not transparent, and the clearing behavior doesn't follow common UX patterns. Users can't easily understand when/why counts appear or how to clear them.

**Investigation Areas:**

1. **Current Calculation Logic** (1-2 hours)
   - How are unread counts currently calculated?
   - What events trigger count increments?
   - Are counts stored in database or calculated on-the-fly?
   - How does the system determine what is "read" vs "unread"?
   - Document current implementation with code references

2. **Clearing Behavior** (1-2 hours)
   - When/how do unread counts get cleared?
   - Does clearing happen on tab click, scroll to bottom, message view, or something else?
   - Are there edge cases where counts don't clear properly?
   - How does auto-scroll interact with unread count clearing?

3. **Standard UX Patterns** (1 hour)
   - Research standard unread count patterns (Messages, Slack, Discord, etc.)
   - Identify best practices: clear on view, clear on scroll, clear on explicit action
   - Document expected behavior for Contextify's use case

4. **Proposed Improvements** (1-2 hours)
   - Design improved unread count logic matching standard patterns
   - Consider: Visual "jump to unread" feature
   - Consider: Manual "mark as read" action
   - Consider: Persistence across app restarts
   - Propose implementation approach with code locations

**Files to Investigate:**
- `Contextify/Contextify/ProjectSwitcherView.swift` (tab display with unread badges)
- `Contextify/Contextify/ConversationMonitor.swift` (likely count calculation)
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` (database queries)
- Timeline view files (scroll/view tracking)

**Acceptance Criteria:**
- ✅ Current implementation fully documented
- ✅ Clearing behavior clearly defined
- ✅ UX pattern research completed
- ✅ Proposed improvements documented with rationale
- ✅ Implementation plan with file/line references

**Related Issues:**
- May interact with #AUTOSCROLL (auto-scroll and unread tracking)
- May inform empty project detection (#EMPTY-PROJECTS)

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

- [ ] #CI-THROTTLE: Fix GitHub Actions budget exhaustion and implement build throttling

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

## User Message Summarization Quality Improvement (1 item)

**Status:** Phase 1 shipped, Phase 2 ready to implement
**Priority:** P1 (High - Quality/UX)
**Effort:** 5-7 hours

- [ ] #USER-PROMPT-REWORK: Implement comprehensive user message summarization improvements with permission response handling

**Goal:** Mirror assistant-side summarization improvements (disposition taxonomy, verb-tense rules, structured prompts) for user messages. Includes permission response handling and bug fixes.

**Phase 1 (SHIPPED ✅):** Expanded negative word list - commit `a8577a9`

**Phase 2 scope:**
- Rewrite user prompt with explicit disposition taxonomy
- Add `permission_response` disposition for Claude Code permission dialogs
- Trust `classifyUserIntent` as source of truth in postProcess
- Fix double-prefix bugs ("You requested Claude Code You...")

**Spec:** `build/notes/todo-support/USER-PROMPT-REWORK-spec.md`
**Planning:** `build/docs/planning/user-timeline-summarization-improvement.md`
**Related:** #SUMMARIZATION-FIX (attribution issues - separate)

## Database Discovery (1 item)

**Status:** Identified while troubleshooting missing defaults key
**Priority:** P1 (high impact on automated tooling/QA workflows)
**Effort:** ~1h to sync prefs + fallback detection

- [ ] #DATABASE-DISCOVERY: Ensure `dev.contextify.database_location` mirrors `HUDPreferences.customDatabaseLocationKey` and add fallback detection (read `HUDPreferences.getCustomDatabaseLocation()` and default path when the key is missing) so automation/debugging tools always discover the current database directory without manual defaults tweaks.

**Background:** The settings/migration code currently only writes `HUDPreferences.customDatabaseLocationKey` (`app/Sources/ContextifyCore/HUDCore.swift:19-107`), so scripts reading `dev.contextify.database_location` hit “domain/default pair … does not exist” even though `/Users/rob/Library/CloudStorage/Dropbox/contextify-db/contextify.db` is the live database.

**Reference:** `build/docs/operations/database-migration-runbook.md`, `app/Sources/ContextifyCore/HUDCore.swift:19-107`

**Notes:**
- Phase 1 already shipped (negative word list) - closes immediate issue
- Phase 2 is comprehensive quality improvement coordinated with permission handling
- Mirrors assistant-side improvements (disposition taxonomy, structured prompts, validation)
- Scope grew 50% but legitimately (fixes bugs + handles edge cases)
- Can ship without optional components if time-constrained

---

## Context Re-injection (1 item)

**Status:** Phase 1 complete; Phase 2 queued
**Priority:** P1 (enables AI workflow continuity)
**Effort:** Phase 2: 4-8 hours (skills + install story)

- [ ] #CONTEXT-REINJECTION: Enable re-injection of found context into new AI conversations

**Problem:** User finds relevant message via search, wants to inject it (with surrounding context) into new Claude Code session. Current "Copy as JSON" lacks db entry ID, AI cannot look up surrounding context.

**Phase 1 (done):**
- `contextify-query` provides a stable, read-only JSON contract for discovery + search + entry-anchored context retrieval.
- Feedback inbox exists to capture query/UX gaps during dogfooding.

**Phase 2 (current plan):**
1. Skills-first adoption (Codex + Claude Code): teach “search → entry id → context window → reinject” with budgeting and error handling.
2. CLI install/distribution story:
   - DMG: install/symlink into a PATH directory with explicit user consent.
   - App Store: bundle CLI and support user-driven install to a user-writable directory, or document absolute-path invocation.

**Research Docs:**
- `build/notes/todo-support/CONTEXT-REINJECTION-synthesized-architecture.md` - Architecture recommendation
- `build/notes/todo-support/CONTEXT-REINJECTION-claude-code-research-report.md` - Claude Code capabilities
- `build/notes/todo-support/CONTEXT-REINJECTION-codex-research-report.md` - Codex capabilities
- `build/notes/todo-support/CONTEXT-REINJECTION-browser-research-prompt.md` - Browser research prompt
- `build/notes/todo-support/CONTEXT-REINJECTION-cli-research-prompt.md` - CLI research prompt

**Spec:** `build/notes/todo-support/CONTEXT-REINJECTION-spec.md`

**Related:** #CONVO-SEARCH spec section 5.4 (surrounding context query), #RESUME-FORK (resume/fork from search)

---

## Permissions UI Card Redesign (1 item)

**Status:** Not Started
**Priority:** P1 (UX improvement, follows Loopback pattern)
**Effort:** 4-6 hours

- [ ] #PERMISSIONS-CARD-UI: Redesign permissions UI with Loopback-style cards

**Goal:** Replace current permissions list UI with card-based layout inspired by Loopback's permissions window.

**Scope:**
- App Store Onboarding wizard step 2
- Settings > Permissions tab

Both should use identical card components for consistency.

**Design:**
- Card per provider (Claude Code, Codex CLI)
- Each card shows: icon, name, path, description, Enable/Granted status
- Visual indication that at least one must be enabled
- Clean, modern appearance matching Loopback's style

**Reference:**
- Loopback permissions UI: `build/design/research/ux/loopback-permissions/`
- Current implementation: `Contextify/Contextify/Settings/TranscriptSourcesSettingsView.swift`

**Acceptance Criteria:**
- [ ] Card-based UI for both wizard and Settings
- [ ] Visual consistency between wizard and Settings
- [ ] Clear affordance for enable/disable actions
- [ ] Matches overall app design language

---

# P2 (Medium Priority)

---

## QA-11 Test Fix (1 item)

**Status:** Not Started
**Priority:** P2 (test infrastructure - assertion approach is fragile)
**Effort:** 1-2 hours

- [ ] #QA-11-FIX: Fix Deep Search test to use log messages instead of window count

**Problem:**
QA-11 (Deep Search E2E test) currently validates that Deep Search opened by counting windows. This is fragile because:
- Other windows may be open
- Window count detection depends on AppleScript timing
- Log messages are more reliable and already available

**Current Behavior:**
Test counts windows before/after triggering Deep Search, expects +1.

**Desired Behavior:**
Test should grep for log message indicating Deep Search window opened (e.g., `[DEEP-SEARCH] Window opened` or similar).

**Files:**
- `scripts/qa/tests/qa-11-deep-search.sh`
- May need to add logging to `DeepSearchView.swift` if not already present

**Acceptance Criteria:**
- [ ] Test uses log messages for validation, not window count
- [ ] Test passes in isolation and as part of full suite
- [ ] Test works in fixture mode (`QA_FIXTURE_MODE=1`)

---

## Project Switch Timeline Preview Prefetch (1 item)

**Status:** Not Started
**Priority:** P2 (UX - avoids “empty” timeline after switching projects)
**Effort:** 4-8 hours
**Spec:** `build/notes/todo-support/PROJECT-SWITCH-TIMELINE-PREVIEW-PREFETCH-spec.md`

- [ ] #PROJECT-SWITCH-TIMELINE-PREVIEW-PREFETCH: Prefetch a lightweight, cancelable preview subset for non-active projects so switching projects shows content quickly without starting watchers.

**Problem:**
Only the active project gets FastPath preview + watchers. Inactive projects may have `ingest_state='partial'` with 0 entries until completion/backfill runs. When a user switches projects, the timeline can appear empty for a long time even though transcripts exist.

**Goal:**
Reduce perceived latency on project switching by ensuring a small amount of displayable content exists for likely-next projects, while keeping resource usage bounded and avoiding watcher/file-descriptor explosion.

**Constraints:**
- Must not start watchers for non-active projects (keep `startWatching: false` for prefetch work).
- Must be bounded, cancelable, and deprioritized relative to the active project’s ingestion.
- Must not introduce meaningful startup tax (prefetch runs after UI is usable / idle).

**Acceptance Criteria:**
- [ ] Switching to a recently-viewed/recently-active project shows non-empty timeline content quickly when transcripts exist (target: within ~200ms once DB has entries; within a short bounded window after prefetch begins on first run).
- [ ] Active project ingestion remains prioritized (project switching does not regress perceived latency for the current project).
- [ ] Watcher count does not scale with total project count (non-active prefetch does not create watchers).
- [ ] Prefetch is cancelable (project switch pauses/deprioritizes background prefetch).
- [ ] Unit tests cover prefetch scheduling rules and watcher safety; E2E coverage updated or added if needed.

---

## Lite Mode Public Announcement (1 item)

**Status:** In Progress
**Priority:** P2 (user outreach)
**Branch:** `feature/lite-mode-announcement`

- [ ] #LITE-MODE-ANNOUNCE: Complete public announcement for macOS 15 support

**Done:**
- [x] Website updated (index.html, download page)
- [x] App Store metadata updated (min OS 15.0, description)
- [x] Draft replies for u/quinncom and Tom (ifun.de)

**Remaining:**
- [ ] Deploy website (`./scripts/deploy-website.sh`)
- [ ] Build and upload release DMG
- [ ] Post Reddit reply to u/quinncom
- [ ] Post ifun.de reply to Tom
- [ ] Optional: New Reddit announcement post

**Context:**
Two users explicitly asked for macOS 15 support. Lite Mode is now shipped on main. Need to update public surfaces and notify waiting users.

**Files:**
- `website/index.html` - Lite Mode callout added
- `website/download/index.html` - Requirements updated
- `appstore-metadata/metadata.json` - Min OS and description
- `build/marketing/feedback/user-feedback.md` - Draft replies

---

## Search Follow-on Improvements (3 items)

**Status:** Spec complete
**Priority:** P2
**Effort:** 5-7 hours total
**Spec:** `build/notes/todo-support/SEARCH-FOLLOWON-spec.md`

- [ ] #SEARCH-FOLLOWON: Implement search performance and UX follow-ons

**Items:**
1. Context load performance (2-3s → <200ms) - 1-2 hours
2. QuickSearch row selection highlighting - 15 minutes
3. ViewModel test infrastructure - 2-4 hours

---

## Deep Search UX Enhancements (3 items)

**Status:** Spec complete
**Priority:** P2
**Effort:** 6-8 hours total
**Spec:** `build/notes/todo-support/SEARCH-UX-spec.md`

- [ ] #SEARCH-UX: Add sort control, multi-select, and sticky date header

**Items:**
1. Sort control (Date/Relevance/Both) - 2-3 hours
2. Context pane multi-select (click, shift+click, cmd+click) - 2-3 hours
3. Sticky date header - 1-2 hours

---

## Query CLI Feedback Inbox (1 item)

**Status:** Obsolete (integrated into #CONTEXT-REINJECTION spec)
**Priority:** P2
**Spec:** `build/notes/todo-support/CONTEXT-REINJECTION-spec.md`

- [x] #QUERY-CLI-FEEDBACK: Obsolete (integrated into #CONTEXT-REINJECTION spec)

---

## Timeline Flicker Fix (1 item)

**Status:** Root cause identified, fix ready
**Priority:** P2
**Effort:** 7 minutes
**Investigation:** `build/notes/todo-support/TIMELINE-FLICKER-investigation.md`

- [ ] #TIMELINE-FLICKER: Remove broken P1 check causing duplicate refreshes

**Problem:** DMG builds show timeline flicker during startup. Root cause: P1 check compares total DB count (267) vs paginated display count (25), always fails, causes duplicate refreshes.

**Fix:** Delete the broken check at `ConversationMonitor.swift:1265-1278`. The existing 500ms debounce handles rapid refreshes.

---

## #EMPTY-STATE-MSG: "No Activity Yet" message is misleading during ingestion

**Status:** UX improvement
**Priority:** P2
**Effort:** 30 minutes
**Found:** 2025-12-09

- [ ] #EMPTY-STATE-MSG: Update empty state message to indicate ingestion in progress

**Problem:**
When a project is selected but transcripts haven't been ingested yet, the timeline shows "No Activity Yet" / "This conversation has not started yet." This implies the user hasn't done anything, when really we just haven't finished ingesting their transcripts.

**Current behavior:**
- Shows during initial discovery/ingestion
- Misleading since projects rarely have zero conversations
- User sees this frequently during fastpath ingestion delays

**Proposed change:**
Change to something like:
- "Loading conversations..." (with spinner if ingestion active)
- "Indexing project..."
- Or conditionally show "No Activity Yet" only after ingestion confirms zero transcripts

**Location:** `ConversationTimelineView.swift:344, 391`

---

## #SLOW-DISCOVERY: Discovery scan interval too long (14-29 seconds)

**Status:** Bug - UX feels sluggish
**Priority:** P2
**Effort:** 1-2 hours
**Found:** 2025-12-08

- [ ] #SLOW-DISCOVERY: Reduce discovery scan interval to ~5 seconds

**Problem:**
LightweightDiscovery scans are happening every 14-29 seconds instead of the expected ~5 seconds. This makes the app feel sluggish when new projects appear or permissions are granted.

**Evidence from logs:**
```
22:21:00 → 22:21:27 = 27 seconds
22:21:27 → 22:21:41 = 14 seconds
22:21:41 → 22:22:10 = 29 seconds
22:22:10 → 22:22:26 = 16 seconds
```

**Expected:** Discovery should trigger within ~5 seconds of:
- App becoming active
- Permission being granted
- User inactivity after project switch

**Files to investigate:**
- `app/Sources/ContextifyCore/Discovery/LightweightDiscovery.swift`
- `app/Sources/ContextifyCore/AppOrchestrator.swift` - discovery trigger points

**Acceptance Criteria:**
- [ ] Discovery scans happen within 5 seconds of triggering events
- [ ] No excessive CPU usage from too-frequent scans
- [ ] Permission grants trigger immediate discovery refresh

---

## #EMPTY-STATE-PERMISSIONS-UX: Show "permissions needed" instead of spinner

**Status:** Not Started
**Priority:** P2 (UX clarity for App Store builds)
**Effort:** 2-3 hours

**Problem:**
When an App Store user launches Contextify without having granted folder permissions, the timeline shows an indefinite "Loading conversation..." spinner. Users think the app is broken when really they just need to grant permissions.

**Current behavior:**
- Spinner shows indefinitely
- No indication permissions are needed
- User has no guidance to fix it

**Desired behavior:**
- Clear message: "Contextify needs access to transcript folders"
- Button/link to open Settings > Permissions tab
- Only show spinner when actively loading (not when blocked on permissions)

**Files:**
- `Contextify/Contextify/ConversationTimelineView.swift` - Empty state view

**Acceptance Criteria:**
- [ ] Empty timeline shows explanatory message when no permissions (not spinner)
- [ ] Clear path from empty state to granting permissions
- [ ] Spinner only appears during actual loading operations

**Split from:** #SETTINGS-OVERHAUL

---

## #IMAGE-RENDERING: Render images inline in timeline and search results

**Status:** Not Started
**Priority:** P2 (visual differentiator)
**Effort:** 4-6 hours

**Problem:**
Claude Code transcripts contain embedded images (base64-encoded). Currently we show `[image]` placeholder text. The CLIs also only show text representations. Rendering actual images would be a meaningful differentiator.

**Feature:**
- Render thumbnail images inline in conversation timeline entries
- Click thumbnail to expand to full size (modal or popover)
- Also render in search results when an entry contains images
- Handle multiple images per entry

**Implementation approach:**
1. Detect image content in transcript entries (base64 data URI patterns)
2. Decode base64 to NSImage/Image
3. Render as thumbnail (constrained size, aspect ratio preserved)
4. Add tap/click handler for full-size view
5. Consider lazy loading for performance

**Files:**
- `Contextify/Contextify/ConversationTimelineView.swift` - timeline entry rendering
- `Contextify/Contextify/SearchResultsView.swift` - search result rendering (if exists)
- May need new `ImageThumbnailView` component

**Acceptance Criteria:**
- [ ] Images render as thumbnails in timeline (not `[image]` placeholder)
- [ ] Click/tap expands to full size
- [ ] Multiple images per entry supported
- [ ] Search results show image thumbnails
- [ ] Performance acceptable (lazy loading if needed)

**Related:** See #P4-BLOB-STORAGE in ROADMAP.md for future optimization of binary content storage.

---

## #PROJECT-COUNT-MISMATCH: Welcome modal project count includes non-displayed projects

**Status:** Not Started
**Priority:** P2 (UX confusion)
**Effort:** 1-2 hours

**Problem:**
Welcome modal shows "Found 6 projects" but only 3 appear in the tab bar. The count includes orphaned Codex projects (transcripts for directories that no longer exist or can't be mapped to a project). These are accessible via the Transcripts window but not shown in the project tab bar, making the count misleading.

**Solution:**
The welcome modal should use the same project count logic as the tab bar - only count projects that will actually be displayed to the user.

**Implementation:**
1. Identify where welcome modal gets its project count
2. Ensure it uses the same filtering as `ProjectSwitcherState` or tab bar display logic
3. Either filter out orphaned projects from the count, or clarify the message: "Found 6 transcripts across 3 projects"

**Files:**
- Welcome modal view (TBD - locate)
- `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift` (discovery count)
- `Contextify/Contextify/ProjectSwitcherState.swift` (display filtering)

**Acceptance Criteria:**
- [ ] Welcome modal count matches projects shown in tab bar
- [ ] OR message clarifies what the count represents
- [ ] Orphaned transcripts still accessible via Transcripts window

---

## #SEARCH-INDEXING-WARNING: Warn when searching incompletely indexed project

**Status:** Not Started
**Priority:** P2 (UX - inform user about partial results)
**Effort:** 1-2 hours

**Problem:**
When a user searches within a project that hasn't finished background indexing, search results may be incomplete. The user has no indication that they might be seeing partial results.

**Context:**
Background indexing (`AppStateOrchestrator.startBackgroundIndexing()`) processes inactive projects at low priority after the active project loads. A project's transcripts may not be fully indexed if:
1. User just launched the app and indexing hasn't completed
2. User switched to a project that was queued for background indexing
3. Large project set is still being processed

**Solution:**
When displaying search results, check if the current project's indexing is complete. If not:
1. Show subtle warning banner: "Some results may not be available yet - indexing in progress"
2. Optionally show progress indicator for remaining projects

**Implementation:**
1. Track per-project indexing completion in AppStateOrchestrator or new state
2. In search results view, check indexing status for queried project
3. Show dismissible warning if indexing incomplete
4. Clear warning automatically when indexing completes

**Files:**
- `app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift` (indexing state tracking)
- `Contextify/Contextify/QuickSearchView.swift` (project-scoped search)
- `Contextify/Contextify/DeepSearchView.swift` (cross-project search)

**Related:**
- `.backgroundIngestProgress` notification (already broadcasts remaining count)

---

## #ACTIVATION-ORCH-UNIFICATION: Single orchestrator + activation façade

**Status:** Not Started
**Priority:** P2 (architecture hardening)
**Effort:** 4-6 hours

**Problem:**
Project activation and ingestion bounce across multiple `TranscriptOrchestrator` instances (AppStateOrchestrator, ProjectSwitcherState fallback, quick-discovery scratch instance). Nil-orchestrator paths in `switchToProject` silently no-op, and sandbox builds risk using orchestrators without access providers. Activation logic is smeared across `ContextifyApp`, quick discovery, ProjectSwitcherState, StartupCoordinator, and AppStateOrchestrator.

**Solution:**
Unify around one shared orchestrator and a small activation façade so quick-discovery, tab switches, and welcome flows publish contexts through the same path and always have access provider coverage. Add observability for ingestion vs context delays.

**Implementation:**
1. Configure `ProjectSwitcherState` with the shared orchestrator created in `initializeProjectsSystem` (access-provider aware); treat lazy creation as diagnostics-only.
2. Extract a lightweight `ProjectActivationService` (AppStateOrchestrator-backed) used by quick discovery, keyboard switching, and welcome modal to publish contexts consistently.
3. Add time-to-first-feed and entry-count logging in `ConversationMonitor`/`ProjectSwitcherState` to distinguish ingestion lag from context publication.

**Files:**
- `Contextify/Contextify/ContextifyApp.swift`
- `Contextify/Contextify/ProjectSwitcherState.swift`
- `Contextify/Contextify/ConversationMonitor.swift`
- `app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift`

---

## #ACTIVATION-OBS: Activation observability and sandbox retries

**Status:** Not Started
**Priority:** P2 (diagnostics / stability)
**Effort:** 3-5 hours

**Problem:**
Startup lag and blank tabs are hard to diagnose without knowing whether context publication, ingestion, or sandbox access is missing. Quick-discovery currently skips preview ingest if a provider lacks authorization but never retries after bookmarks are granted, forcing slow-path hoover to catch up.

**Solution:**
Add per-project activation telemetry and a sandbox-only retry for quick discovery once authorizations flip to authorized so preview ingest runs immediately and logs clearly show access failures versus cancellations.

**Implementation:**
1. Log time-to-first-feed and entry counts per project when ConversationMonitor first loads and when tabs are switched.
2. Add a sandbox hook to rerun quick discovery after bookmarks are saved or authorization becomes available, rather than skipping ingest entirely.
3. Log sandbox access failures without redaction so we can distinguish access denied vs cancellation vs parse errors.

**Files:**
- `Contextify/Contextify/ContextifyApp.swift`
- `Contextify/Contextify/ProjectSwitcherState.swift`
- `Contextify/Contextify/ConversationMonitor.swift`

---

## #CONSOLIDATE-USERDEFAULTS: Consolidate UserDefaults to single domain

**Status:** Not Started
**Priority:** P2 (code cleanup, reduces complexity)
**Effort:** 1-2 hours

**Issue:**
App uses two UserDefaults domains:
- `sh.contextify.Contextify` (bundle ID) - standard
- `dev.contextify` (shared suite) - for HUDPreferences

This causes confusion when resetting app state (both must be cleared) and was root cause of #PROJECT-ROOT-MODAL recurring.

**Solution:**
Migrate all preferences to bundle ID domain and remove `dev.contextify` suite.

**Implementation:**
1. [ ] Identify all keys in `dev.contextify` suite (HUDPreferences)
2. [ ] Add migration code to move values to bundle ID on first launch
3. [ ] Update HUDPreferences to use standard UserDefaults
4. [ ] Remove `dev.contextify` suite initialization
5. [ ] Update reset scripts to only clear bundle ID

**Files:**
- `app/Sources/ContextifyCore/HUDCore.swift:22-27` - sharedDefaults initialization

---

## Website Dynamic Forwarders (1 item)

**Status:** Not Started
**Priority:** P2 (release workflow improvement)
**Effort:** 2-4 hours

- [ ] #DYNAMIC-FORWARDER: Implement dynamic download links that always point to latest release

**Problem:**
Download links throughout documentation, README files, and external references point to specific versions. Each release requires updating multiple locations, and stale links in external articles/posts can't be fixed.

**Solution:**
Implement server-side redirects or static file forwarders:

| Forwarder URL | Target | Purpose |
|---------------|--------|---------|
| `contextify.sh/download/latest` | Current DMG | Always points to latest |
| `contextify.sh/download/latest.dmg` | Current DMG | Explicit DMG download |
| `contextify.sh/releases/latest` | Release notes | Latest release info |

**Implementation options:**

1. **Nginx redirects (recommended):**
   ```nginx
   location /download/latest {
       return 302 /releases/Contextify-1.0.0.dmg;
   }
   ```
   Update single config file each release.

2. **Symbolic links:**
   ```bash
   ln -sf Contextify-1.0.0.dmg website/releases/latest.dmg
   ```
   Update symlink as part of release script.

3. **JavaScript redirect:**
   Static HTML that reads version from JSON and redirects.
   Works without server config changes.

**Integration:**
- Add to `scripts/deploy-website.sh` or release workflow
- Update `build/docs/operations/PUBLIC-SURFACES.md` when implemented
- Replace hardcoded links in public repo README

**Acceptance criteria:**
- [ ] `contextify.sh/download/latest` redirects to current DMG
- [ ] Redirect updated as part of release process
- [ ] Public repo README uses dynamic link
- [ ] Old versioned URLs still work (don't break existing links)

**Reference:** `build/docs/operations/PUBLIC-SURFACES.md`

---

## Website Email Collection (1 item)

**Status:** Not Started
**Priority:** P2 (growth/marketing)
**Effort:** 2-4 hours

- [ ] #EMAIL-COLLECTION: Add email signup for release notifications on website

**Problem:**
Users interested in Contextify may want to be notified about new features and releases. Email list enables direct communication with interested users.

**Context:**
Lite Mode for macOS 15 is now shipped. Email list would still be useful for announcing new features, major releases, and other updates.

**Solution:**
Add email signup form to website for release/update notifications.

**Options:**
1. **Buttondown** (recommended) - Simple, cheap, good for small lists
2. **Mailchimp** - More features, free tier available
3. **Self-hosted** - More work, full control

**Implementation:**
- Add signup form to website (footer or dedicated section)
- "Get notified about new releases and features"
- Privacy-focused messaging (no spam, release announcements only)

**Acceptance criteria:**
- [ ] Email signup form on contextify.sh
- [ ] Confirmation email on signup
- [ ] Unsubscribe link in all emails
- [ ] Privacy policy updated if needed

---

## App Store Screenshot Automation (1 item)

**Status:** Not Started
**Priority:** P3

- [ ] #SCREENSHOT-AUTOMATION: Automate App Store screenshots with light/dark mode toggle

**Scope:**
- Script should flip system appearance (dark ↔ light) and capture screenshots in both modes
- Useful for App Store assets and website screenshots
- Consider using `osascript` or AppleScript to toggle System Preferences appearance

---

## Scripts Directory Consolidation & Cleanup (1 item)

**Status:** Not Started
**Priority:** P2 (organizational debt - cleanup from Nov 17 audit)
**Effort:** 6-8 hours (audit + consolidation + cleanup)
**Context:** Nov 17 documentation audit identified 15+ standalone docs in scripts/ that should move to build/docs/

- [ ] #SCRIPTS-CONSOLIDATION: Complete scripts directory consolidation and cleanup

**Scope:**

1. **Audit scripts/ directory structure** (2-3 hours)
   - Document all files in scripts/ and subdirectories (logging/, transcript-repair/, etc.)
   - Classify each file: keep in scripts/, move to build/docs/, consolidate, or delete
   - Identify cleanup needed in logging/ subdirectory
   - Create consolidation plan document in /tmp/

2. **Consolidate standalone documentation** (2-3 hours)
   - Merge scripts/CI-TRIGGER-README.md + scripts/CLAUDE-CODE-WEB-CI-GUIDE.md → build/docs/guides/linux-ci-builds.md
   - Merge scripts/DATABASE-MANAGEMENT.md → build/docs/operations/DATABASE-LOCATIONS.md
   - Merge scripts/LOG-CAPTURE-README.md + scripts/LOG-SETUP-SUMMARY.md → scripts/logging/README.md
   - Merge scripts/QUICK-REFERENCE.md → build/docs/guides/DEVELOPMENT.md
   - Move scripts/RELEASE.md → build/docs/operations/release/RELEASE-PROCESS.md
   - Move scripts/SIGNING-SETUP.md → build/docs/operations/release/
   - Delete scripts/REVIEW-PREP-README.md (internal workflow, belongs in /tmp/)
   - Archive or consolidate CODEX_*.md files (now covered by codex-cli-transcript-format.md)

3. **Clean up scripts/logging/** (1-2 hours)
   - Audit all scripts in logging/ subdirectory
   - Consolidate or remove redundant scripts
   - Update logging/README.md with current script inventory
   - Ensure all scripts have clear descriptions and usage examples

4. **Update cross-references** (1 hour)
   - Update all markdown files referencing moved/consolidated docs
   - Update scripts/README.md to reflect new structure
   - Update AGENTS.md references if needed

**Files to consolidate/move (from Nov 17 audit):**
- scripts/CI-TRIGGER-README.md
- scripts/CLAUDE-CODE-WEB-CI-GUIDE.md
- scripts/DATABASE-MANAGEMENT.md
- scripts/LOG-CAPTURE-README.md
- scripts/LOG-SETUP-SUMMARY.md
- scripts/QUICK-REFERENCE.md
- scripts/RELEASE.md
- scripts/SIGNING-SETUP.md
- scripts/REVIEW-PREP-README.md (delete)
- scripts/CODEX_*.md (3 files - already consolidated in codex-cli-transcript-format.md)

**Acceptance Criteria:**
- ✅ Complete audit document created with classification of all scripts/ files
- ✅ All standalone docs consolidated or moved per plan
- ✅ scripts/logging/ cleaned up with updated README
- ✅ scripts/README.md updated to concise index format
- ✅ All cross-references updated
- ✅ Zero broken documentation links

**Related:**
- Nov 17 documentation audit recommendations
- codex-cli-transcript-format.md consolidation (completed)
- claude-code-transcript-format.md rename (completed)

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

- [ ] #PROJECTS-REFRESH-REVIEW: Investigate if manual "Refresh Projects" button is needed (1.5 hours)
- [ ] #PROJECTS-EMPTY-STATE: Add first-run guidance to empty state (30 min)

**Context:** Projects window improvements for better UX consistency.

---

### #PROJECTS-REFRESH-REVIEW: Review Auto-Refresh Behavior

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

### #PROJECTS-EMPTY-STATE: Add First-Run Guidance

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

## Code Quality - Compiler Warnings (1 item)

**Status:** Partial Progress - 11/21 warnings fixed
**Priority:** P2 (Zero-warning policy enforcement)
**Effort:** 3-4 hours remaining
**Branch:** `claude/p1-code-quality-017eyf46izwZZFvGYbX6jsSN` (rebased off main, pushed)

- [ ] #CODE-QUALITY: Fix remaining 10 compiler warnings to achieve zero-warning policy

**Branch Status:**
- ✅ Rebased off main (commit 22415ce0)
- ✅ All 46 tests passing
- ✅ 11 warnings fixed (Sendable conformance, unnecessary await/try, unused variables)
- ⚠️ 10 warnings remain (unused variables, false positive async warnings, #file deprecation)

**Fixed Warnings (commit 22415ce0):**
1. Added Sendable conformance to CorruptionType enum
2. Removed unnecessary await expressions (6 locations)
3. Removed unreachable catch block
4. Discarded unused db.write() return values (2 locations)
5. Removed unnecessary nil coalescing operator
6. Replaced unused binding with boolean test
7. Removed unnecessary try expression
8. Changed var to let for immutable variable

**Remaining Warnings:**
1. HooverEngine.swift:304 - `transcriptHasher` never mutated
2. TranscriptWatcher.swift:208 - Conditional cast always succeeds (3 occurrences)
3. DatabaseMigration.swift:50 - `sourceDir` never used
4. TranscriptParsers.swift:393 - `hasOnlyThinking` never used
5. TranscriptConverter.swift:288 - `convertedCalls` never used
6. TranscriptConverter.swift:313 - `timestamp` never used
7. FSEventsMonitor.swift:56,180 - No async operations in await (2 occurrences)
8. TestHelpers.swift - #file vs #filePath deprecation (3 occurrences)

**Next Steps:**
1. Fix remaining 10 warnings
2. Run `swift test` to verify zero warnings
3. Merge to main once clean

**Files:**
- Various (see commit history for complete list)

**Related Work on Branch:**
- Query builder pattern implementation (TimelineEntryQuery)
- Raw SQL elimination from TranscriptOrchestrator
- Concurrency fixes (Task.detached → Task)

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

- [ ] #TODOS-AGENT: Build intelligent TODO management agent (create, update, prioritize, clean up)

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

## TODO System Refactoring (1 item)

**Status:** Research Complete
**Priority:** P2 (workflow improvement - current file is 2k+ lines)
**Effort:** 4-6 hours
**Research:** `build/notes/todo-support/TODOS-REFACTOR-research.md`

- [ ] #TODOS-REFACTOR: Refactor TODO system to reduce file size and improve AI efficiency

**Problem:**
- TODOS.md is 2k+ lines, AI must read full file to update one status
- Priority embedded in task IDs (e.g., `#WEBSITE`) makes reprioritization awkward
- No clear rules on when entry needs backing file
- Ad-hoc detail file structure

**Proposed Solution (from research):**
Split into small index + detail files:
```
todos/
├── TODOS.md          # ~100 lines: ID + title + checkbox only
└── active/
    ├── WEBSITE.md    # Full details
    ├── SETTINGS.md
    └── ...
```

**Key changes:**
- Priority is section header, not part of ID
- Index file stays under 150 lines
- Details only loaded when working on specific task
- Completed items archived to `todos/archive/`

**Migration steps:**
1. Create `todos/` directory structure
2. Extract detail content to individual files
3. Reduce main TODOS.md to index format
4. Update AGENTS.md references
5. Archive completed items

---

## Branch Management (1 item)

**Status:** Not Started
**Priority:** P2 (Technical debt - token burn branches need review)
**Effort:** 8-12 hours

- [ ] #TOKEN-BURN: Review and catalog token burn branches from Nov 18-19, 2025

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

**Reference:** `build/notes/todo-support/TOKEN-BURN-prompt.md`

---

## Background LLM Processing (1 item)

**Status:** Not Started
**Priority:** P2 (UX improvement)
**Effort:** 4-6 hours

- [ ] #BACKGROUND-SUMM: Re-implement background LLM summarization for "would-be-visible" entries

**Goal:** When app is backgrounded, continue summarizing entries the user is likely to scroll to. Pre-populates summaries for smoother UX when returning to foreground.

**Current behavior:** LLM summarization completely disabled when backgrounded (log: "App resigned active - background processing DISABLED"). This is policy, not a bug, but a missed opportunity.

**Design:** `build/notes/todo-support/BACKGROUND-SUMM-design.md`

---

## LLM Summarization Quality (1 item)

**Status:** Not Started
**Priority:** P2 (Quality improvement - summaries misrepresenting user intent)
**Effort:** 4-6 hours
**Spec:** `build/notes/todo-support/SUMMARIZATION-FIX-spec.md`

- [ ] #SUMMARIZATION-FIX: Improve LLM summarization to correctly identify action requests vs. explanations

**Problem:**
Timeline summaries sometimes reverse attribution, showing user action requests as assistant explanations. Example: User says "add a P1 todo" → Summary says "You explained how to add a todo."

**Root Cause:**
- Summarizer doesn't distinguish action requests from explanations
- Tool completion results not visible to summarizer (assistant doesn't relay in text)
- Prompts lack explicit guidance on attribution preservation

**Solution:**
1. Update LLM prompts with explicit attribution rules
2. Ensure tool_result content available to summarizer
3. Add examples of correct vs. incorrect attribution patterns

**Test Cases:**
- Entry `f268414b-31ca-431a-b4e6-383898844de0` - Primary example with detailed transcript analysis
- Additional UUIDs in audit doc for validation

**Files:**
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` (prompts)
- `app/Sources/ContextifyCore/Database/Models.swift` (structure)

**Acceptance Criteria:**
- Action requests correctly identified as "User asked to..." or "User requested..."
- No reversed attribution (user actions attributed to assistant or vice versa)
- Completed tasks reflected in summaries (not just requests)
- Information requests distinguished from action requests

**For full analysis**: See investigation document with transcript analysis, examples, and proposed prompt improvements

---

## Summarization Parsing Backlog (1 item)

**Status:** Collecting examples
**Priority:** P2 (Quality - batch fix unparseable summaries)
**Effort:** 2-4 hours per batch

- [ ] #SUMM-PARSING-BACKLOG: Fix messages that fail summarization parsing

**Problem:**
Some transcript entries produce summaries that fail post-processing or contain unexpected formats. Rather than fixing these one-off as they appear, collect examples and fix in batches.

**Workflow:**
1. When encountering an unparseable summary, add to the backlog reference doc
2. Periodically review backlog and identify patterns
3. Fix root causes in parser/prompts/post-processing
4. Validate fixes against collected examples

**Reference:** `build/notes/todo-support/SUMM-PARSING-BACKLOG-examples.md`

**Current Count:** 1 example (seed script markdown table output)

---

## Git Worktree Support (1 item)

**Status:** Investigation Complete - Ready for Implementation
**Priority:** P2 (UX enhancement)
**Effort:** 4-6 hours

- [ ] #WORKTREE: Add visual grouping for git worktrees and verify transcript isolation

**Goal:** Add subtle background color to project tabs to indicate related worktrees from the same git repository. Core worktree support already works (separate projects, transcript isolation by CWD).

**Main deliverable:** Hash git root path to consistent color, apply as tab background tint.

**Investigation:** `build/notes/todo-support/WORKTREE-investigation.md`

---

## Project Tab Reordering UX (1 item)

**Status:** Investigation Complete - Ready for Implementation
**Priority:** P2 (UX improvement)
**Effort:** 3-4 hours

- [ ] #TAB-REORDER-UX: Fix drag-drop precision and add keyboard shortcuts for tab reordering

**Issues:**
1. **Vertical drag sensitivity** - Small vertical drift cancels drag unexpectedly (fix: expand hit zone)
2. **Missing keyboard shortcuts** - Add `Shift-Cmd-Opt-[/]` to move active tab (no wrap-around)

**Investigation:** `build/notes/todo-support/TAB-REORDER-UX-investigation.md`

---

## Release Workflow Python CLI Refactor (1 item)

**Status:** Ready for implementation
**Priority:** P2 (architectural improvement + App Store status integration)
**Effort:** 12-16 hours (incremental migration)

- [ ] #PYTHON-CLI-REFACTOR: Refactor release workflow to Python CLI with App Store Connect API integration

**Problem:**
The release workflow scripts (`scripts/release/*.sh`) have grown into a small application with embedded Python everywhere. Bash associative arrays are fragile, JSON manipulation via `jq` is awkward, and the state machine logic is hard to maintain. Most critically, the system cannot verify actual App Store submission status - it relies on manual user reporting.

**Solution:**
Create `tools/release_cli.py` as single source of truth with subcommands (init, build, status, mark-submitted, mark-rejected, mark-shipped, check-consistency, poll-appstore). Keep existing Bash scripts as thin 5-10 line wrappers that delegate to the Python CLI.

**Key Features:**
1. **App Store Connect API integration** - Query actual submission status from Apple
2. **Apple state enum** - Proper Python enum with all 20 AppStoreVersionState values
3. **State category mapping** - Map Apple states to workflow categories (not_submitted, in_review, approved, rejected, removed)
4. **Automatic state sync** - Detect drift between local tracking and Apple's actual state
5. **Status validation** - Validate submission states as part of release workflow

**Benefits:**
- One language for all state/logic (no more shell/Python hybrid)
- Real unit tests with pytest around state machine
- Native JSON/dict handling
- Proper data structures for Apple state mapping
- App Store Connect API has Python clients available
- Cleaner error handling and atomic file writes
- Preserves existing muscle memory (./scripts/release/mark-shipped.sh still works)

**Migration phases:**
1. Create Python core with minimal commands + Apple state enum
2. Implement `poll-appstore` command with API integration
3. Port remaining guard logic and embedded Python
4. Integrate status polling into workflow validation
5. Stabilize and optionally deprecate Bash wrappers

**Interim solution:**
`scripts/release/poll-appstore-status.sh` provides basic status checking via `xcrun altool --list-apps`. This will be replaced by the Python implementation.

**Apple States to Support:**
See `releases/schemas/appstore-states.schema.json` for complete enum and category mapping.

**Reference:**
- `releases/STATUS-VALUES.md` - State definitions and Apple mapping
- `releases/schemas/` - JSON schemas for state tracking
- `scripts/release/poll-appstore-status.sh` - Interim bash implementation

---

# P3 (Low Priority / Deferred)

## Help Documentation Content (1 item)

**Status:** Not Started - research complete, structure defined
**Priority:** P3 (deferred - user education, support reduction)
**Effort:** 4-8 hours
**Research:** `build/notes/todo-support/HELP-DOCUMENTATION-research.md`

- [ ] #HELP-DOCUMENTATION: Create help pages on contextify.sh with engagement hooks

**Goal:** Populate contextify.sh/help/ with useful content that educates users, reduces support burden, and drives engagement/growth.

**Pages to Create:**
1. `/help` - Hub page linking to all sections
2. `/help/getting-started` - 5-minute setup guide
3. `/help/keyboard-shortcuts` - Reference table
4. `/help/troubleshooting` - Common issues and solutions
5. `/help/features` - Feature discovery (post-launch)
6. `/help/privacy` - Data handling, local-first architecture

**Reference:** Research on 1Password, Raycast, Bear patterns in `build/notes/todo-support/HELP-DOCUMENTATION-research.md`

---

## Project Directory Bookmarks (1 item) ⬇️

**Status:** Expected behavior documented, future enhancement planned
**Priority:** Demoted from P0 (cosmetic issue, not functional blocker)
**Effort:** N/A (tracking only, see ROADMAP.md#P4-PROJECT-DIRECTORY-ACCESS for enhancement)

- [ ] #PROJECT-BOOKMARKS: Project contexts have nil bookmarks in sandboxed builds (expected)

**Background:**
In App Store (sandboxed) builds, discovered projects have `hasBookmark=false` because:
- App only has access to transcript directories (`~/.claude/projects/`, `~/.codex/sessions/`)
- Project directories (e.g., `~/code/projects/foo/`) are discovered from transcript `cwd` hints
- Sandbox blocks bookmark creation for paths without user-granted access

**Impact (cosmetic only):**
- Git branch display shows "—" instead of actual branch
- Finder reveals may fail silently
- Core transcript display works fine

**Resolution:**
- Log level downgraded from warning to debug (expected behavior)
- Comment added explaining sandbox constraint
- Future enhancement: ROADMAP.md#P4-PROJECT-DIRECTORY-ACCESS

**Files:**
- `app/Sources/ContextifyCore/HUDCore.swift:702-733` - bookmark handling with explanatory comment
- `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift:490-519` - external project switch

---

## CLI Logomark Display (1 item) ⬇️

**Status:** Partially complete (project switch works, ingestion updates missing)
**Priority:** Demoted from P1 (project switch already works via database)
**Effort:** 1-2 hours (add hoover notification subscription)

- [ ] #LOGOMARK: Add real-time logomark updates during transcript ingestion

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

## Test Infrastructure Follow-up (1 item)

**Status:** Ready for verification
**Priority:** P3 (post-launch stability work after infrastructure issues resolved)
**Effort:** 6-8 hours

- [ ] #TESTS: Validate reinstated test infrastructure and re-enable skipped integration tests

---

## Project Bar Hide Activation (1 item)

**Status:** Not started
**Priority:** P3 (UI state correctness)
**Discovered:** 2025-12-14

- [ ] #PROJECT-HIDE-ACTIVATE-NEXT: When hiding active project, activate next project to the right

**Problem:**
When a project is hidden via the project bar context menu while it is the active project, the UI can remain logically “active” on the now-hidden project (stale git branch / project row / conversation timeline).

**Expected:**
Hiding the active project activates the next visible project to the right (or the nearest neighbor if none to the right).

**Notes:**
- Repro: Right-click active project tab in the project bar → Hide → observe active selection state.

**Summary:** FoundationLLM/SDK/actor blockers have been addressed, so this work is now about verification: ensure `swift test` passes cleanly, re-enable `testInitialHooverWorkflow`, `testOrchestratorWorkflow`, and `testCrashRecovery`, and confirm the CI workflow references the reactivated suites.

**Files to check:**
- `Contextify/ContextifyTests/IntegrationTests.swift`
- CI/test configuration files

**Acceptance Criteria:**
- ✅ All integration tests run without `skip_`
- ✅ Test infrastructure remains stable across repeated runs
- ✅ CI reflects the reactivated tests

---

## Liquid Glass Design System (1 item) ⬇️

**Status:** Partially implemented, toolbar translucency deferred
**Priority:** Demoted from P2 (SwiftUI toolbar API limitations, diminishing returns)
**Effort:** Unknown (requires AppKit or future SwiftUI improvements)
**Documentation:** `build/docs/audits/liquid-glass-status.md`

- [ ] #LIQUID-GLASS: Complete Liquid Glass toolbar translucency for macOS 26

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

**Status:** Ready to implement (removal complete)
**Priority:** P3 (Post-launch feature)
**Effort:** 1-2 hours

- [ ] #RESTORE-HTTP-API: Re-enable diagnostics HTTP server for external tooling

**Context:**
The diagnostics HTTP server was removed before initial release. This feature allows external scripts to query timeline state via localhost HTTP API.

**Removal Commit:** `c0ffd9c` - feat(diagnostics): remove HTTP API before release (merged via feat/consistent-contextify-blue-tinting → main)

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

- [ ] #OFFSCREEN-ACTIVITY: Indicate when new messages appear in off-screen projects

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

## Timeline Summary Height Regression (1 item) ⬇️

**Status:** Idea
**Priority:** P3 (guard against UI regressions)
**Effort:** 2-3 hours (test harness + assertions)

- [ ] #TIMELINE-SUMMARY-HEIGHT: Add regression coverage for the row-height-capping behavior so any future change to `summaryFrameMinHeight` or the logged deltas is caught automatically.

**Plan:** `build/notes/todo-support/TIMELINE-SUMMARY-HEIGHT.md`

---

## Lazy Watcher Optimization (1 item) ⬇️

**Status:** Spec Complete
**Priority:** Demoted from P2 (large effort, no immediate impact)
**Effort:** 3-4 weeks (aligned with ConversationMonitor refactor)
**Spec:** `build/notes/todo-support/LAZY-WATCHERS-design.md`

- [ ] #LAZY-WATCHERS: Implement lazy watchers for inactive projects to reduce file descriptor usage

**Related:** `#INGEST-GAP` - Once ingestion is fixed, watcher count will spike from ~300 to 1000+. This optimization becomes critical.

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

## Empty Timeline UI Regression Tests (1 item) ⬇️

**Status:** Idea
**Priority:** P3 (post-launch stability)
**Effort:** 4-6 hours

- [ ] #EMPTY-TIMELINE-TESTS: Define and add UI/regression coverage for the empty-project timeline-to-empty-state transition so the spinner removal can be validated automatically (see `build/notes/todo-support/EMPTY-TIMELINE-TESTS.md`)

**Problem:**
- No automated verification currently guards the UI transition around `.loaded` vs `.loading`, so the spinner can reappear unnoticed.
**Approach:**
1. Draft acceptance criteria and scenario matrix in the supporting note (`build/notes/todo-support/EMPTY-TIMELINE-TESTS.md`).
2. Implement a lightweight guard (unit test or UI test) that drives `ConversationMonitor` through the zero-entry case and asserts `phase`, `isAwaitingPrimer`, and the rendered view branch.
3. Hook the guard into CI/integration workflow so regressions are caught during automation.

**Notes:**
- Supporting details and future iterations go into `build/notes/todo-support/EMPTY-TIMELINE-TESTS.md`.

---

## Project Switch Consolidation (1 item) ⬇️

**Status:** Not Started
**Priority:** Demoted from P2 (code quality, no user-visible impact)
**Effort:** 4-6 hours

- [ ] #SWITCH: Consolidate 4 overlapping project switch code paths into single unified pipeline

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
- Implementation plan: `build/notes/todo-support/SWITCH-refactor-plan.md`
- Source code analysis: `build/notes/todo-support/SWITCH-source-analysis.md`

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

## Sidechain Transcript Enhancements (1 item)

**Status:** Backlog - v1 fix shipped, future enhancements identified
**Priority:** P3 (robustness improvements, no immediate user impact)
**Effort:** 8-12 hours total
**Reference:** `build/notes/todo-support/sidechain-transcript-enhancements.md`

- [ ] #SIDECHAIN-ENHANCEMENTS: Implement schema-level and UX improvements for sidechain transcript handling

**Context:**
The v1 fix for the sidechain transcript bug uses a filename heuristic (`agent-*.jsonl`) to deprioritize sidechain transcripts during FastPath ingestion. These enhancements would improve robustness but are not required for the immediate fix.

**Enhancement 1: DB-level Transcript Kind Column**
- Add `kind` column to transcripts table (`main`, `sidechain`, `unknown`)
- Populate on first ingest based on `isSidechain` field
- FastPath can sort by `kind` instead of filename heuristics

**Enhancement 2: Content-Value-Based Prioritization**
- Order by "likely to contribute timeline entries"
- Prioritize transcripts already known to have entries
- More intelligent than pure file size

**Enhancement 3: Timeline Primer UX for Sidechain-Only Projects**
- Detect when project has only sidechain transcripts
- Show appropriate message instead of confusing "waiting for primer entries"

**Related:**
- Bug fix: Sidechain transcript prioritization (FastPathIngestionCoordinator)
- Docs: `transcript-formats.md` sidechain naming convention

---

**End of TODO List**
