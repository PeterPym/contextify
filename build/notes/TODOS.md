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

**Last Updated:** 2025-11-27
**Status:** Active

**Priority Levels:**
- **P0 (Launch Critical):** 1 item - Must complete for v1.0 public launch
- **P1 (High Priority):** 17 items - Important for quality/UX, ship soon after launch
- **P2 (Medium Priority):** 36 items - Nice to have, can defer to future releases
- **P3 (Low Priority / Deferred):** 16 items - Future enhancements

**Total Active Items:** 70

---

# P0 (Launch Critical) - 1 Item

---

## v1.0 Public Launch (1 item)

**Status:** App Store rejected, resubmission pending
**Priority:** P0 (blocking public launch)
**Effort:** 4-8 hours remaining

- [ ] #P0-LAUNCH: Complete v1.0 public launch sequence

**Current State:**
- Help menu: DONE (simplified, links to contextify.sh/help/ and GitHub issues)
- Public repo: DONE (github.com/PeterPym/contextify with issue templates)
- App Store: REJECTED (Guideline 2.1 - needs demo video + sample data)
- DMG: Released on GitHub (v1.0.0)
- Review materials: Sample data ready, demo video script ready

**Immediate Next Steps (App Store Resubmission):**
1. [ ] Deploy website with help page and review materials: `./scripts/deploy-website.sh`
2. [ ] Record demo video following `appstore-metadata/review-materials/DEMO-VIDEO-SCRIPT.md`
3. [ ] Build App Store archive (v1.0.0 build 4): `bash scripts/xc.sh --dist=appstore Release archive`
4. [ ] Upload and resubmit in App Store Connect

**Reference:** `releases/v1.0.0/release.json`, `releases/WORKFLOW.md`

### Remaining Sub-tasks

**Website (contextify.sh)**
- [x] Help landing page created
- [x] Support page updated with GitHub issues links
- [ ] Deploy current changes
- [ ] Hero section with headline, subhead, video embed
- [ ] Features section with screenshots
- [ ] Download section (DMG link, SHA256, requirements)
- [ ] App Store badge (when approved)

**Content Creation**
- [x] Demo video script written
- [ ] Record demo video (60-90 seconds)
- [ ] Finalize Show HN post
- [ ] Prepare Twitter announcement thread

**Distribution**
- [ ] App Store resubmission (rejected, needs demo video)
- [x] DMG available on GitHub
- [x] Public repo created (PeterPym/contextify)

**Launch Sequence**
- [ ] Soft launch: Tweet + Reddit on App Store approval
- [ ] Show HN post (1-2 days after soft launch)
- [ ] Monitor and respond to feedback

**Post-Launch**
- [ ] Homebrew Cask formula
- [ ] Product Hunt (when ready)

---

# P1 (High Priority) - 17 Items

---

## Sparkle Release Automation (1 item)

**Status:** Design complete, awaiting user answers before implementation
**Priority:** P1 (release workflow improvement)
**Effort:** 4-6 hours
**Design:** `/tmp/sparkle-release-workflow-design.md`

- [ ] #P1-SPARKLE-RELEASE: Extend release.py with guided Sparkle signing, appcast updates, and website deployment

**Summary:**
Extend `scripts/release.py` to include Sparkle signing, appcast.xml updates, and website deployment with interactive verification prompts at key checkpoints.

**Blockers:** 6 design questions need answers before implementation (see `/tmp/sparkle-release-workflow-status.md`)

**Key Features:**
- Phase 2: Sparkle EdDSA signing + appcast update
- Phase 3: Website deployment (DMG, appcast, release notes)
- Interactive checkpoints with `--yes` for automation
- Server directory creation (releases/, release-notes/)

---

## Help Documentation Content (1 item)

**Status:** Not Started - research complete, structure defined
**Priority:** P1 (user education, support reduction, growth)
**Effort:** 4-8 hours
**Research:** `build/notes/todo-support/P1-HELP-DOCUMENTATION-research.md`

- [ ] #P1-HELP-DOCUMENTATION: Create help pages on contextify.sh with engagement hooks

**Goal:** Populate contextify.sh/help/ with useful content that educates users, reduces support burden, and drives engagement/growth.

**Pages to Create:**
1. `/help` - Hub page linking to all sections
2. `/help/getting-started` - 5-minute setup guide
3. `/help/keyboard-shortcuts` - Reference table
4. `/help/troubleshooting` - Common issues and solutions
5. `/help/features` - Feature discovery (post-launch)
6. `/help/privacy` - Data handling, local-first architecture

**Engagement Hooks to Embed:**
- Newsletter signup (footer of help pages)
- "Was this helpful?" feedback widget
- "Still stuck? Contact us" funnel
- "Try it now" deep links to app features
- Feature discovery prompts

**Growth Flywheels:**
- Help → Feature Discovery → Usage → Referral
- Troubleshooting → Resolution → Trust → Review
- Keyboard Shortcuts → Power Users → Advocates
- Newsletter → Tips → Engagement → Retention

**Analytics to Implement:**
- Page views per article
- Time on page
- Help → Support contact rate
- Newsletter conversion rate
- Search queries (content gaps)

**Technical:**
- UTM params from app: `?ref=app-help-menu`
- Plausible or Fathom for privacy-respecting analytics
- Anchor IDs for deep linking

**Reference:** Research on 1Password, Raycast, Bear patterns in `build/notes/todo-support/P1-HELP-DOCUMENTATION-research.md`

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


## State Management & Orchestrator Consolidation (2 items)

**Status:** External review feedback (2025-11-23)
**Priority:** P1 (architectural improvement, reduces foot-guns)
**Effort:** 4-6 hours total

- [ ] #P1-PROJECT-ACTIVATED: Consolidate markProjectSelected + markProjectViewed + getUnreadCount into single markProjectActivated() method (2h)

**Background:**
External review of test-quality-merge branch identified split responsibility pattern in ProjectSwitcherState.swift:618: 3 separate orchestrator calls (markProjectSelected, markProjectViewed, getUnreadCount) plus separate UI state mutation. This pattern led to P1-UNREAD bugs elsewhere (easy to forget one piece at other call sites).

**Current Pattern (multiple calls):**
```swift
try orchestrator.markProjectSelected(projectId: projectId)
try orchestrator.markProjectViewed(projectId: projectId, timestamp: timestamp)
let freshCount = try orchestrator.getUnreadCount(projectId: projectId)
await MainActor.run { self?.unreadCounts[projectId] = freshCount }
```

**Proposed Pattern (single unified call):**
```swift
public func markProjectActivated(projectId: String, timestamp: String) throws -> (visit: ProjectVisit, unreadCount: Int) {
  try markProjectSelected(projectId: projectId)
  let visit = try markProjectViewed(projectId: projectId, timestamp: timestamp)
  let unread = try getUnreadCount(projectId: projectId)
  return (visit, unread)
}
```

**Benefits:**
- Single call site pattern - removes foot-gun of forgetting getUnreadCount
- Aligns with "unified update method" guideline in code quality spec
- Reduces split responsibility pattern that caused bugs

**Files:**
- `app/Sources/ContextifyCore/TranscriptOrchestrator.swift`
- `Contextify/Contextify/ProjectSwitcherState.swift:618`

**Reference:** `/private/tmp/1-executive-summary-1.md` § P1.1

- [ ] #P1-TASK-DETACHED-SENDABILITY: Review and fix Task.detached Sendability issues with strict concurrency (2h)

**Background:**
Multiple Task.detached call sites may produce strict-concurrency warnings due to capturing non-Sendable references:
- ProjectSwitcherState (fast-path ingestion + metadata updates)
- HUDCore.HUDViewModel ("project switched" notification)
- StartupWarmup.run()
- FastPathIngestionCoordinator ("silent completion" task)

**Strategy:**
1. Run build with strict concurrency fully enabled
2. Use `Task {}` instead of `Task.detached` where actor-bound behavior is desired
3. Ensure detached tasks only capture Sendable data where possible

**Files:**
- Contextify/Contextify/ProjectSwitcherState.swift
- Contextify/Contextify/HUDCore/HUDViewModel.swift
- app/Sources/ContextifyCore/Startup/StartupWarmup.swift
- app/Sources/ContextifyCore/Database/FastPathIngestionCoordinator.swift

**Reference:** `/private/tmp/1-executive-summary-1.md` § P1.2

---

## View Layer Refactoring (1 item)

**Status:** External review feedback (2025-11-23)
**Priority:** P1 (not on hot path, but violates layering intent)
**Effort:** 2-3 hours

- [ ] #P1-PROJECT-BADGES-ORCHESTRATOR: Refactor ProjectBadgesContainer to use injected/shared orchestrator instead of creating new instance per load (2h)

**Background:**
External review identified that ProjectBadgesContainer.swift creates a fresh TranscriptOrchestrator instance every time badges view loads. If TranscriptOrchestrator is heavy (hoover engine, watchers, schedulers), this could be wasteful and potentially lead to duplicated watcher registrations. View is "reaching down" to construct core service instead of receiving data from higher-level coordinator.

**Current Pattern:**
```swift
let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
let set = try await orchestrator.getProviders(forProjectPath: projectPath)
```

**Proposed Pattern:**
- Inject shared orchestrator via @EnvironmentObject or initializer, OR
- Create static, cheap helper in DatabaseManager/ProjectRepository for this specific query without spinning up full orchestrator

**Files:**
- Contextify/Contextify/ProjectBadgesContainer.swift

**Reference:** `/private/tmp/1-executive-summary-1.md` § P1.3

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

## Timeline Query Centralization

**Status:** Deferred to P1 (after P0 filter fixes ship)
**Priority:** P1 (Prevent future filter drift bugs)
**Effort:** 8-12 hours (requires refactoring all query callsites)

- [ ] #P1-QUERY-CENTRALIZE: Eliminate duplicate SQL implementations, create single source of truth for timeline queries

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

**Plan:** `build/notes/todo-support/P1-QUERY-CENTRALIZE-design.md`
**Source Analysis:** `build/notes/todo-support/P1-QUERY-CENTRALIZE-source-analysis.md`

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

## Timeline UX - Expansion State Persistence (1 item)

**Status:** Not Started
**Priority:** P2 (Medium priority - nice to have quality/UX improvement)
**Effort:** 2-3 hours

- [ ] #P2-EXPANSION-STATE: Preserve timeline entry expansion state across view redraws

**Problem:**
When a timeline entry is expanded (disclosure triangle opened to show full content) and a new message arrives, the conversation timeline redraws and collapses the previously expanded entry. This forces users to re-expand entries if they're reading them while new messages arrive.

**Impact:**
- Frustrating UX when actively monitoring conversations
- Interrupts reading flow if user has expanded an entry to read full content
- Not a blocker but degrades experience during active use

**Solution:**

1. **State Management** (1-2 hours)
   - Add `@State private var expandedEntries: Set<UUID> = []` to track expansion by entry ID
   - Pass expansion state to `TimelineEntryRow` via binding
   - Update state when user toggles disclosure triangle

2. **Persist Across Redraws** (0.5-1 hour)
   - Ensure entry IDs remain stable across `monitor.entriesRevision` changes
   - Test that expansion state survives new message arrivals
   - Verify state clears appropriately on project switch

3. **Testing** (0.5 hour)
   - Expand entry, wait for new message, verify stays expanded
   - Switch projects, verify state resets
   - Test with multiple expanded entries

**Files:**
- View: `Contextify/Contextify/ConversationTimelineView.swift`
- Row: `Contextify/Contextify/TimelineEntryRow.swift`

**Note:** Entry IDs should already be stable (UUIDs from database), so this is primarily about wiring up state preservation in the view layer.

---

## Unread Count Investigation (1 item)

**Status:** Not Started
**Priority:** P1 (UX - unread count behavior unclear and doesn't follow standard patterns)
**Effort:** 4-6 hours

- [ ] #P1-UNREAD-COUNT: Investigate and fix unread count calculation and clearing behavior

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
- May interact with #P1-AUTOSCROLL (auto-scroll and unread tracking)
- May inform empty project detection (#P2-EMPTY-PROJECTS)

---

## OS Version Compatibility & User Communication (1 item)

**Status:** Not Started
**Priority:** P1 (Pre-launch - graceful handling of unsupported OS versions)
**Effort:** 2-3 hours

- [ ] #P1-OS-COMPATIBILITY: Investigate App Store OS restrictions and implement compatibility modal

**Problem:**
App is designed for macOS 26+ (Tahoe) but minimum deployment target may be set lower. Need to understand App Store behavior and communicate gracefully to users on unsupported OS versions.

**Investigation (30 min):**
1. **Research App Store behavior:**
   - Does App Store prevent downloads on unsupported OS versions automatically?
   - Or can users download but app won't launch?
   - Check Apple developer documentation on minimum OS version enforcement
   - Test: Can macOS 14 user see/download an app with macOS 26 minimum?

**Implementation (1.5-2 hours):**

2. **Add OS Version Check on Launch:**
   ```swift
   // In App init or SceneDelegate
   if #unavailable(macOS 26) {
       showOSCompatibilityModal()
       return
   }
   ```

3. **Create Compatibility Modal:**
   - **Title:** "macOS Version Not Supported"
   - **Message:** "Contextify is designed for macOS 26 (Tahoe) or later. Your current version: macOS [X.Y]"
   - **Body:** "This version of macOS doesn't include features Contextify requires. We'd love to support your version - let us know!"
   - **Buttons:**
     - Primary: "Request Compatibility" → Opens mailto link
     - Secondary: "Close App" → Quits gracefully

4. **Mailto Link:**
   ```
   mailto:support@contextify.sh?subject=macOS%20Compatibility%20Request&body=I'm%20on%20macOS%20[VERSION]%20and%20would%20like%20Contextify%20support.
   ```
   - Pre-fill subject: "macOS Compatibility Request"
   - Pre-fill body with detected OS version

**Files:**
- `Contextify/Contextify/ContextifyApp.swift` (OS version check on launch)
- `Contextify/Contextify/Views/OSCompatibilityModal.swift` (new modal view)
- `Info.plist` (verify MinimumOSVersion setting)

**Acceptance Criteria:**
- ✅ Documented: Does App Store block downloads on unsupported OS?
- ✅ If app launches on unsupported OS, modal appears immediately
- ✅ Modal clearly communicates OS requirement (macOS 26+)
- ✅ "Request Compatibility" button opens mail client with pre-filled template
- ✅ "Close App" quits gracefully (no crashes)
- ✅ Modal includes detected user OS version
- ✅ User gets clear path to provide feedback/request support

**Benefits:**
- Professional user experience instead of crashes or confusing errors
- Collect compatibility requests to inform future support decisions
- Clear communication about OS requirements
- Graceful degradation path

**Alternative Approach:**
If App Store DOES block downloads, this modal becomes unnecessary but check is still useful for TestFlight/sideload scenarios.

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

## User Message Summarization Quality Improvement (1 item)

**Status:** Planning Complete - Ready to Implement (Phase 1 shipped)
**Priority:** P1 (High - Quality/UX - mirrors assistant-side improvements)
**Effort:** 5-7 hours (comprehensive implementation + validation)
**Coordination:** Combines user prompt rework + permission response handling

- [ ] #P1-USER-PROMPT-REWORK: Implement comprehensive user message summarization improvements with permission response handling

**Background:**

Assistant-side summarization was significantly improved with explicit disposition taxonomy, verb-tense rules, and structured prompts. User-side deserves same quality treatment.

**Scope Expansion Note:**

Original scope (3-6 hours): User prompt quality improvement only
**v2 coordinated scope (5-7 hours):** User prompt quality + permission response handling + bug fixes

**Scope has grown ~50% but legitimately:**
- ✅ Tracks with original intent (improve user summarization quality)
- ✅ More comprehensive (handles permission response edge cases + prevents bugs)
- ✅ Mirrors assistant-side SOTA patterns (disposition taxonomy, structured prompts)
- ✅ Fixes active bugs (broken "Nevermind" summaries, prefixPolicy conflicts)

**Phase 1 (SHIPPED ✅ - commit a8577a9):**
- Expanded negative word list in classifyUserIntent
- Fixes: "Nevermind", "wait", "pause" → correct negative classification
- Zero risk, deterministic, no LLM changes
- Closes immediate issue

**Phase 2 (Coordinated Implementation - 5-7 hours):**

**Core Improvements (from original P1):**
1. Rewrite user prompt with explicit disposition taxonomy + examples
2. Add summary phrasing guidance tied to each disposition (CRITICAL section)
3. Trust classifyUserIntent as source of truth in postProcess
4. Maintain simplicity (no complex rule engine)

**Added: Permission Response Handling (NEW):**
5. Add permission_response disposition to prompt
6. Add "You responded" to prefixPolicy allowed list (prevents double-prefix bug)
7. Add Disposition.permissionResponse enum case
8. Optional: Add permission fast path with cue-word heuristic
9. Update isDirective calculation to include permission_response

**Bug Fixes (from colleague review):**
- Fix UserIntent enum references (.other → .unknown)
- Align with prefixPolicy to prevent "You requested Claude Code You..." bug
- Add Disposition enum case for proper type safety
- Include permission_response in directive flag calculation

**Implementation Tasks:**

1. **User Prompt Rewrite** (2-3 hours)
   - Add disposition taxonomy with examples (directive, question, report, affirmative, negative, permission_response)
   - Add summary phrasing templates for each disposition
   - Add special case handling (slash commands, mixed messages)
   - Mirror assistant-side prompt structure and quality

2. **prefixPolicy Update** (15 min)
   - Add "You responded" to allowed prefixes
   - Prevents double-prefix bug for permission responses

3. **postProcess Integration** (1 hour)
   - Add classifyUserIntent override logic
   - Log disagreements between LLM and classifier
   - Exception: preserve permission_response (LLM has special context)
   - Update isDirective calculation

4. **Disposition Enum** (15 min)
   - Add Disposition.permissionResponse case
   - Audit all switch statements for exhaustiveness

5. **Optional: Permission Fast Path** (1 hour)
   - Add detectPermissionResponse() helper with cue-word heuristic
   - Prevents false positives ("Thanks" → NOT permission_response)
   - Can be deferred to Phase 3 if complexity concerns

6. **Validation** (1-2 hours)
   - Run 15 test cases (directives, questions, reports, permissions, edge cases)
   - Verify disposition accuracy ≥90%
   - Verify no double-prefix bugs
   - Verify no false positive permission responses ("Thanks", "Cool" → NOT permission_response)
   - Monitor first 100 user messages in production

**Files Modified:**
- `Contextify/Contextify/FoundationLLM.swift`
  - User prompt (instructionsForTimeline case .user)
  - prefixPolicy (add "You responded")
  - Optional: detectPermissionResponse() helper
  - Optional: Permission fast path
  - postProcess user block (classifyUserIntent override)
- `app/Sources/ContextifyCore/Database/Models.swift`
  - Add Disposition.permissionResponse enum case
- Optional: `Contextify/Contextify/TimelineEntryRow.swift`
  - UI styling for permission_response disposition

**Test Cases:**

**Directives (3):**
1. "Add logging around retry loop." → "You requested Claude Code to add logging..."
2. "Can you refactor this?" → "You requested Claude Code to refactor..."
3. "/review-prep" → "You requested Claude Code to execute the /review-prep command."

**Questions (2):**
1. "Why is this slow?" → "You asked why this is slow."
2. "What does this error mean?" → "You asked what the error means."

**Reports (2):**
1. "App crashes when clicking timeline." → "You reported crashes..."
2. "CI is failing." → "You reported CI failures."

**Affirmative/Negative (2):**
1. "Yes, that works." → "You confirmed the approach works."
2. "No, that's not right." → "You disagreed with..." OR "You requested Claude Code not to proceed."

**Permission Responses (5):**
1. "Nevermind" → "You requested Claude Code not to proceed." (Phase 1 fast path)
2. "pause a moment" → "You responded to permission request: pause a moment"
3. "do X instead" → "You responded to permission request: do X instead"
4. "THIS IS A TEST" → "You responded to permission request: THIS IS A TEST"
5. "maybe later" → "You responded to permission request: maybe later"

**Edge Cases (3):**
1. "Thanks" → affirmative OR unknown → NOT permission_response ✅
2. "Cool" → affirmative OR unknown → NOT permission_response ✅
3. "Got it" → affirmative → NOT permission_response ✅

**Success Criteria:**
- ✅ User prompt quality matches assistant (symmetry)
- ✅ Disposition accuracy ≥90%
- ✅ classifyUserIntent vs LLM agreement ≥85%
- ✅ Zero double-prefix bugs ("You requested Claude Code You...")
- ✅ Zero false positive permission responses
- ✅ All test cases pass (≥13/15)

**Risks & Mitigation:**
- **Risk:** Breaking existing summaries → Test on recent transcripts first
- **Risk:** classifyUserIntent disagrees with LLM → Log disagreements, monitor patterns
- **Risk:** Permission heuristic false positives → Tightened with cue words, can defer
- **Risk:** prefixPolicy conflicts → Explicitly addressed by adding "You responded"

**References:**
- **Original planning doc:** `build/docs/planning/user-timeline-summarization-improvement.md`
- **v2 coordinated guide:** `/tmp/permission-response-fix-v2-coordinated.md` (Phase 2)
- **Scope analysis:** `/tmp/scope-analysis.md`
- **Phase 1 commit:** `a8577a9` (negative word list expansion - shipped ✅)
- **Colleague review:** `/private/tmp/here-s-my-review.md` (bug fixes integrated)
- **Related:** Permission dialog option 3 parsing (commits 204f12e, a8577a9 - completed ✅)
- **Related:** #P2-SUMMARIZATION-FIX (attribution issues - separate PR)

**Decision Points:**
1. **Include permission fast path?** Recommended: YES with cue words (safe, handles edge cases)
2. **Parser metadata (future)?** Defer to Phase 3 if false positives emerge
3. **Defer lexical seatbelts?** YES - Phase 1 + improved prompt should be sufficient

## Database Discovery (1 item)

**Status:** Identified while troubleshooting missing defaults key
**Priority:** P1 (high impact on automated tooling/QA workflows)
**Effort:** ~1h to sync prefs + fallback detection

- [ ] #P1-DATABASE-DISCOVERY: Ensure `dev.contextify.database_location` mirrors `HUDPreferences.customDatabaseLocationKey` and add fallback detection (read `HUDPreferences.getCustomDatabaseLocation()` and default path when the key is missing) so automation/debugging tools always discover the current database directory without manual defaults tweaks.

**Background:** The settings/migration code currently only writes `HUDPreferences.customDatabaseLocationKey` (`app/Sources/ContextifyCore/HUDCore.swift:19-107`), so scripts reading `dev.contextify.database_location` hit “domain/default pair … does not exist” even though `/Users/rob/Library/CloudStorage/Dropbox/contextify-db/contextify.db` is the live database.

**Reference:** `build/docs/operations/database-migration-runbook.md`, `app/Sources/ContextifyCore/HUDCore.swift:19-107`

**Notes:**
- Phase 1 already shipped (negative word list) - closes immediate issue
- Phase 2 is comprehensive quality improvement coordinated with permission handling
- Mirrors assistant-side improvements (disposition taxonomy, structured prompts, validation)
- Scope grew 50% but legitimately (fixes bugs + handles edge cases)
- Can ship without optional components if time-constrained

---

# Conversation Search (1 item)

**Status:** Spec ready for implementation
**Priority:** P1 (core UX quality)
**Effort:** 8-12 hours (Phase 1)

- [ ] #P1-CONVO-SEARCH: Implement Quick Search (HUD project scope) and Deep Search (Search Center) following the unified spec so users can quickly search messages/context per project and still dig into cross-project history without extra spinner noise.

**Spec:** `build/notes/todo-support/P1-CONVO-SEARCH-spec.md`
**Implementation:** `build/notes/todo-support/P1-CONVO-SEARCH-implementation.md`

---

# P2 (Medium Priority) - 36 Items

---

## Pre-macOS 26 Compatibility (1 item)

**Status:** Not Started
**Priority:** P2 (growth enabler - lets users start collecting history before upgrading)
**Effort:** 6-10 hours

- [ ] #P2-LEGACY-MACOS: Add support for macOS 14/15 with graceful degradation

**Problem:**
Current app requires macOS 26 (Tahoe) because Apple Intelligence powers the LLM summaries. This excludes users on older macOS who could still benefit from:
- Timeline monitoring
- Transcript indexing
- Project organization
- Search (when implemented)

**Growth strategy:**
Let users on older macOS "bank" their conversation history now. When they upgrade to Tahoe, summaries auto-generate for their existing transcripts. This creates upgrade incentive and builds loyalty.

**Implementation options:**

1. **Lite mode (recommended for v1):**
   - Lower deployment target to macOS 14 or 15
   - Detect Apple Intelligence availability at runtime
   - Show timeline without summaries on older macOS
   - Display "Upgrade to macOS 26 for AI summaries" prompt
   - Summaries auto-generate when user upgrades

2. **Alternative LLM support (future):**
   - Ollama integration for local models
   - OpenAI/Anthropic API option (opt-in, user provides key)
   - Requires significant additional work

**Scope for P2:**
- Focus on option 1 (lite mode)
- Runtime detection of FoundationModels availability
- Graceful UI fallback (hide summary column, show "upgrade" badge)
- Ensure database schema works on older macOS
- Test on macOS 14 and 15

**Files:**
- `Contextify/Contextify.xcodeproj` (deployment target)
- `FoundationLLM.swift` (availability checks)
- `TimelineEntryRow.swift` (conditional summary display)
- Various views (upgrade prompts)

**Acceptance criteria:**
- [ ] App installs and runs on macOS 14+
- [ ] Timeline, project switching, indexing work without summaries
- [ ] Clear messaging about what requires macOS 26
- [ ] Summaries appear automatically after macOS upgrade

---

## Scripts Directory Consolidation & Cleanup (1 item)

**Status:** Not Started
**Priority:** P2 (organizational debt - cleanup from Nov 17 audit)
**Effort:** 6-8 hours (audit + consolidation + cleanup)
**Context:** Nov 17 documentation audit identified 15+ standalone docs in scripts/ that should move to build/docs/

- [ ] #P2-SCRIPTS-CONSOLIDATION: Complete scripts directory consolidation and cleanup

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

## Code Quality - Compiler Warnings (1 item)

**Status:** Partial Progress - 11/21 warnings fixed
**Priority:** P2 (Zero-warning policy enforcement)
**Effort:** 3-4 hours remaining
**Branch:** `claude/p1-code-quality-017eyf46izwZZFvGYbX6jsSN` (rebased off main, pushed)

- [ ] #P2-CODE-QUALITY: Fix remaining 10 compiler warnings to achieve zero-warning policy

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

## LLM Summarization Quality (1 item)

**Status:** Not Started
**Priority:** P2 (Quality improvement - summaries misrepresenting user intent)
**Effort:** 4-6 hours
**Spec:** `build/notes/todo-support/P2-SUMMARIZATION-FIX-spec.md`

- [ ] #P2-SUMMARIZATION-FIX: Improve LLM summarization to correctly identify action requests vs. explanations

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

- [ ] #P2-SUMM-PARSING-BACKLOG: Fix messages that fail summarization parsing

**Problem:**
Some transcript entries produce summaries that fail post-processing or contain unexpected formats. Rather than fixing these one-off as they appear, collect examples and fix in batches.

**Workflow:**
1. When encountering an unparseable summary, add to the backlog reference doc
2. Periodically review backlog and identify patterns
3. Fix root causes in parser/prompts/post-processing
4. Validate fixes against collected examples

**Reference:** `build/notes/todo-support/P2-SUMM-PARSING-BACKLOG-examples.md`

**Current Count:** 1 example (seed script markdown table output)

---

## Git Worktree Support (1 item)

**Status:** Investigation Complete - Ready for Implementation
**Priority:** P2 (UX enhancement - worktrees as separate projects with visual grouping)
**Effort:** 4-6 hours
**Discovered during:** P3-LOGOMARK debugging

- [ ] #P2-WORKTREE: Add visual grouping for git worktrees and verify transcript isolation

**Investigation:** `build/notes/todo-support/P2-WORKTREE-investigation.md`

**Background:**
Contextify has partial worktree support. Core infrastructure works (separate project entries, transcript isolation by CWD), but gaps exist in visual UX and code clarity.

**What Works:**
- Worktrees in different directories create separate projects
- Transcripts correctly associated by CWD (not git root)
- Database uniqueness on `root_path` prevents collisions

**Gaps to Address:**

1. **Visual Worktree Grouping (P2 - main deliverable)**
   - Add subtle background color to indicate related worktrees
   - Hash git root path to consistent color
   - Helps users identify which tabs are from same repo
   - File: `Contextify/Contextify/ProjectSwitcherView.swift`

2. **projectIdentifier Collision (P3 - cleanup)**
   - `ProjectContext.projectIdentifier` uses git root, causing collision for worktrees
   - Not a functional bug (database uses full path), but confusing
   - File: `Contextify/Contextify/ProjectContext.swift:14`

3. **allProjectPaths() Documentation (P3 - cleanup)**
   - Clarify when to use aggregation vs isolation
   - File: `Contextify/Contextify/ProjectContext.swift:74`

**Implementation Tasks:**

1. **Add git root to Project model** (30 min)
   - Store resolved git root path alongside root_path
   - Computed during project discovery

2. **Implement color hashing** (1 hour)
   - Hash git root path to HSB color
   - Use subtle opacity (0.1-0.15) for background

3. **Update ProjectSwitcherView** (1-2 hours)
   - Apply group color to tab backgrounds
   - Ensure colors are distinguishable

4. **Add SPM tests** (1-2 hours)
   - Path encoding/decoding with hyphens
   - Git root detection for worktrees
   - Transcript-project association verification

**Testing Strategy:**

**SPM-Compatible (implement now):**
- Unit test: Path encoding/decoding with hyphens in project names
- Unit test: `GitRepositoryResolver.findGitRoot()` with worktree `.git` file
- Integration test: Transcript-project association by CWD

**Deferred SwiftUI Tests:**
- Visual worktree grouping (requires UI automation)
- Tab bar rendering with multiple worktrees

**Files:**
- `Contextify/Contextify/ProjectSwitcherView.swift` (UI changes)
- `Contextify/Contextify/ProjectContext.swift` (cleanup)
- `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift` (git root extraction)
- `Tests/ContextifyCoreTests/GitRepositoryResolverTests.swift` (new tests)

**Acceptance Criteria:**
- [ ] Related worktrees have matching background tint in tab bar
- [ ] Unrelated projects with same name have different colors
- [ ] Transcripts appear in correct project (verified by SPM test)
- [ ] No functional regressions in project switching

**Related:**
- P3-LOGOMARK (discovered during this work)
- P1-PROJECT-BADGES-ORCHESTRATOR (similar layering concerns)

---

## Project Tab Reordering UX (1 item)

**Status:** Investigation Complete - Ready for Implementation
**Priority:** P2 (UX improvement - tab reordering precision and keyboard shortcuts)
**Effort:** 3-4 hours

- [ ] #P2-TAB-REORDER-UX: Fix drag-drop precision and add keyboard shortcuts for tab reordering

**Investigation:** `build/notes/todo-support/P2-TAB-REORDER-UX-investigation.md`

**Issue 1: Vertical Drag Sensitivity**

**Problem:** Dragging a tab too far vertically causes it to "drop" unexpectedly. Users must exercise excessive precision to keep the drag within a narrow horizontal band.

**Root Cause:** `dropExited()` in `ProjectSwitcherView.swift:151-156` clears drag state when cursor exits the drop zone. The drop zone is vertically constrained to tab bar height, so small vertical drift triggers exit.

**Historical Context:** This was likely a fix for "ghost entries when dragging outside the window" - tabs disappearing when dragged outside and released. The fix may be overly aggressive.

**Proposed Fix (Option A - Recommended):**
- Expand vertical hit zone significantly (+/- 100px)
- Keep horizontal precision for slot detection
- Only cancel drag on true horizontal exit (left/right of tab bar)

**Alternative:** Reimplment drag-drop from scratch using:
- SwiftUI's native `.draggable()` / `.dropDestination()` (macOS 13+)
- Custom `DragGesture` with full bounds control
- Research Safari/Chrome tab bar behavior for reference

**Issue 2: Missing Keyboard Shortcuts**

**Problem:** No keyboard shortcuts exist to move the currently selected tab.

**Requested:** `Shift-Command-Option-[` (move left) and `Shift-Command-Option-]` (move right)

**Behavior:**
- Move active tab one position in direction
- **No wrap-around:** At boundaries, do nothing (don't loop to opposite end)
- Should work regardless of focus state

**Implementation:**
```swift
func moveActiveTab(direction: TabMoveDirection) {
  guard let activeId = activeProjectId,
        let currentIndex = projects.firstIndex(where: { $0.id == activeId }) else { return }

  switch direction {
  case .left:
    guard currentIndex > 0 else { return }  // No wrap
    // Move to currentIndex - 1
  case .right:
    guard currentIndex < projects.count - 1 else { return }  // No wrap
    // Move to currentIndex + 1
  }
  // Persist new order...
}
```

**Testing Strategy:**

**SPM-Compatible:**
- Unit test: `moveActiveTab(direction:)` logic
- Unit test: No-wrap-around at boundaries
- Unit test: Tab order persistence

**Deferred SwiftUI Tests:**
- UI test: Drag with vertical drift maintains state
- UI test: Keyboard shortcuts trigger reorder

**Files:**
- `Contextify/Contextify/ProjectSwitcherView.swift` (drag-drop fix, keyboard shortcuts)
- `Contextify/Contextify/ProjectSwitcherState.swift` (add `moveActiveTab()`)
- `Tests/ContextifyCoreTests/TabReorderTests.swift` (new)

**Acceptance Criteria:**
- [ ] Vertical drag drift (reasonable amount) does not cancel drag
- [ ] Horizontal exit still cancels drag (prevents ghost tabs)
- [ ] Shift-Cmd-Opt-[ moves active tab left (no wrap)
- [ ] Shift-Cmd-Opt-] moves active tab right (no wrap)
- [ ] Keyboard reorder persists like drag-drop reorder

**Related:**
- #63: Add tests for ProjectSwitcherView drag-drop (P2 Testing)

---

# P3 (Low Priority / Deferred) - 16 Items

## CLI Logomark Display (1 item) ⬇️

**Status:** Partially complete (project switch works, ingestion updates missing)
**Priority:** Demoted from P1 (project switch already works via database)
**Effort:** 1-2 hours (add hoover notification subscription)

- [ ] #P3-LOGOMARK: Add real-time logomark updates during transcript ingestion

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

- [ ] #P2-TESTS: Validate reinstated test infrastructure and re-enable skipped integration tests

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

**Status:** Ready to implement (removal complete)
**Priority:** P3 (Post-launch feature)
**Effort:** 1-2 hours

- [ ] #P3-RESTORE-HTTP-API: Re-enable diagnostics HTTP server for external tooling

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

## Timeline Summary Height Regression (1 item) ⬇️

**Status:** Idea
**Priority:** P3 (guard against UI regressions)
**Effort:** 2-3 hours (test harness + assertions)

- [ ] #P3-TIMELINE-SUMMARY-HEIGHT: Add regression coverage for the row-height-capping behavior so any future change to `summaryFrameMinHeight` or the logged deltas is caught automatically.

**Plan:** `build/notes/todo-support/P3-TIMELINE-SUMMARY-HEIGHT.md`

---

## Lazy Watcher Optimization (1 item) ⬇️

**Status:** Spec Complete
**Priority:** Demoted from P2 (large effort, no immediate impact)
**Effort:** 3-4 weeks (aligned with ConversationMonitor refactor)
**Spec:** `build/notes/todo-support/P2-LAZY-WATCHERS-design.md`

- [ ] #P3-LAZY-WATCHERS: Implement lazy watchers for inactive projects to reduce file descriptor usage

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

- [ ] #P3-EMPTY-TIMELINE-TESTS: Define and add UI/regression coverage for the empty-project timeline-to-empty-state transition so the spinner removal can be validated automatically (see `build/notes/todo-support/P3-EMPTY-TIMELINE-TESTS.md`)

**Problem:**
- No automated verification currently guards the UI transition around `.loaded` vs `.loading`, so the spinner can reappear unnoticed.
**Approach:**
1. Draft acceptance criteria and scenario matrix in the supporting note (`build/notes/todo-support/P3-EMPTY-TIMELINE-TESTS.md`).
2. Implement a lightweight guard (unit test or UI test) that drives `ConversationMonitor` through the zero-entry case and asserts `phase`, `isAwaitingPrimer`, and the rendered view branch.
3. Hook the guard into CI/integration workflow so regressions are caught during automation.

**Notes:**
- Supporting details and future iterations go into `build/notes/todo-support/P3-EMPTY-TIMELINE-TESTS.md`.

---

## Project Switch Consolidation (1 item) ⬇️

**Status:** Not Started
**Priority:** Demoted from P2 (code quality, no user-visible impact)
**Effort:** 4-6 hours

- [ ] #P3-SWITCH: Consolidate 4 overlapping project switch code paths into single unified pipeline

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

**End of TODO List**
