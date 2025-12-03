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

**Last Updated:** 2025-12-03
**Status:** Active

**Priority Levels:**
- **P0 (Launch Critical):** 3 items - Must complete for v1.0 public launch
- **P1 (High Priority):** 20 items - Important for quality/UX, ship soon after launch
- **P2 (Medium Priority):** 43 items - Nice to have, can defer to future releases
- **P3 (Low Priority / Deferred):** 17 items - Future enhancements

**Total Active Items:** 83

---

# P0 (Launch Critical) - 3 Items

---

## v1.0 Public Launch (1 item)

**Status:** App Store resubmitted (WAITING_FOR_REVIEW), website/DMG release pending
**Priority:** P0 (blocking public launch)
**Effort:** 4-6 hours remaining

- [ ] #P0-LAUNCH: Complete v1.0 public launch sequence

**Current State:**
- Help menu: DONE (simplified, links to contextify.sh/help/ and GitHub issues)
- Public repo: DONE (github.com/PeterPym/contextify with issue templates)
- App Store: WAITING_FOR_REVIEW (Build 10, resubmitted Dec 2)
- DMG: Built but not publicly released on website
- Review materials: Sample data + demo video deployed to contextify.sh
- Website: Design system done, needs screenshots + deploy (see #P1-WEBSITE-REDESIGN)

**Immediate Next Steps:**
1. [x] Fix website styling - design system migration complete (see #P1-WEBSITE-REDESIGN)
2. [ ] Add app screenshots to website
3. [ ] Publish DMG release on website with download link
4. [ ] Deploy website: `./scripts/deploy-website.sh`
5. [ ] Wait for App Store approval, then add App Store badge

**Reference:** `releases/v1.0.0/release.json`, `releases/WORKFLOW.md`

### Remaining Sub-tasks

**Website (contextify.sh)**
- [x] Help landing page created
- [x] Support page updated with GitHub issues links
- [x] Design system migration (INSPINIA -> design tokens)
- [x] Brand divider, card hover, navbar styling
- [x] Hero section with headline and swoopity background
- [ ] App screenshots (light + dark mode)
- [ ] OG image for social sharing
- [ ] Deploy current changes
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

## #P0-PROJECT-ROOT-MODAL: Spurious "Stored project root is invalid" modal

**Status:** Bug - recurring, blocks clean first-run experience
**Priority:** P0 (affects App Store review, demo recording)
**Effort:** 2-4 hours

**Issue:**
Modal appears on startup with message: "Stored project root is invalid or unreadable (saved path): /path/to/dir". Blocks user interaction until dismissed.

**Root Cause (partial):**
- App uses TWO UserDefaults domains: `sh.contextify.Contextify` (bundle ID) and `dev.contextify` (shared suite)
- Clean scripts only cleared bundle ID defaults, leaving stale `dev.contextify.projectRoot` key
- Fixed in scripts but modal logic may need hardening

**Remaining Work:**
1. [ ] Audit why two UserDefaults domains exist - consolidate to bundle ID if possible
2. [ ] Change modal to non-blocking log message (fall back gracefully)
3. [ ] Ensure `HUDPreferences.clearPersistedRoot()` is called when path invalid
4. [ ] Add test for clean first-run experience

**Files:**
- `app/Sources/ContextifyCore/HUDCore.swift:264` - error message source
- `app/Sources/ContextifyCore/HUDCore.swift:22-27` - dual UserDefaults domains
- `scripts/xc.sh:331-332` - reset logic (now fixed)
- `scripts/release/demo-recording.sh:153-160` - reset logic (now fixed)

**History:** Previously tracked, thought resolved, recurred during demo recording session.

---

## #P0-SETTINGS-OVERHAUL: Fix Settings window and permissions UX

**Status:** Broken - Settings window missing permissions tab, poor UX
**Priority:** P0 (blocks App Store users from granting permissions)
**Effort:** 4-6 hours

**Problems Identified:**

1. **Settings window is broken:**
   - Only shows Database tab, no way to access Transcript Sources (permissions)
   - `TranscriptSourcesSettingsView` is in a separate window, not a tab
   - Huge empty space at top (fixed 400px height too tall for content)
   - Users cannot find where to grant permissions

2. **Empty state UX is confusing:**
   - "Loading conversation..." spinner shows indefinitely when no permissions granted
   - No indication that permissions are needed
   - "Open project..." link is misleading (implies file picker, not permissions)

3. **Permission grant may not trigger discovery:**
   - Need to verify granting permissions kicks off discovery workflow
   - Projects should appear in tab bar after granting access

**Solution:**

1. **Combine Settings into tabbed view:**
   ```swift
   Settings {
     TabView {
       SettingsView()
         .tabItem { Label("Database", systemImage: "cylinder") }
       TranscriptSourcesSettingsView(...)
         .tabItem { Label("Permissions", systemImage: "folder.badge.plus") }
     }
   }
   ```

2. **Fix Database tab layout:**
   - Remove fixed height or reduce to fit content
   - Clean up empty space at top

3. **Improve empty state messaging:**
   - Replace spinner with explanatory text when no permissions
   - "Contextify needs access to transcript folders to get started"
   - Button to open Settings > Permissions tab directly
   - "Learn more" link to contextify.sh

4. **Verify permission → discovery flow:**
   - Test: Grant permission → projects appear → timeline populates
   - Fix if broken

**Files:**
- `Contextify/Contextify/ContextifyApp.swift:240-248` - Settings window definition
- `Contextify/Contextify/SettingsView.swift:178` - Fixed height
- `Contextify/Contextify/Settings/TranscriptSourcesSettingsView.swift`
- `Contextify/Contextify/ConversationTimelineView.swift` - Empty state

**Acceptance Criteria:**
- [ ] Settings window has Database and Permissions tabs
- [ ] Database tab fits content without huge empty space
- [ ] Empty timeline shows "permissions needed" message, not spinner
- [ ] Clear path from empty state to granting permissions
- [ ] Granting permissions triggers discovery and populates UI

**Supersedes:** #P1-PERMISSIONS-MODAL, #P1-APPSTORE-NO-PERMISSIONS-UX

---

# P1 (High Priority) - 20 Items

Note: #P1-PERMISSIONS-MODAL and #P1-APPSTORE-NO-PERMISSIONS-UX were merged into #P0-SETTINGS-OVERHAUL

---

## Release Status Bar (1 item)

**Status:** Not Started
**Priority:** P1 (developer experience, release workflow visibility)
**Effort:** 2-4 hours

- [ ] #P1-RELEASE-STATUS-BAR: Add Claude Code status line showing current release version

**Problem:**
When working on releases, it's not immediately obvious which release version is active. You have to run `./scripts/release/status.sh` or check `releases/manifest.json` manually.

**Solution:**
Configure Claude Code's status line to display the current release version being worked on.

**Implementation:**
1. Check if Claude Code supports custom status line configuration
2. Create a script that reads `releases/manifest.json` and outputs current version + phase
3. Configure status line to run this script
4. Display format: `v1.0.0 (review_materials)` or similar

**Example output:**
```
v1.0.0 build:4 phase:review_materials
```

**Acceptance Criteria:**
- [ ] Status line shows current release version
- [ ] Status line shows current phase (pre_release, build, review_materials, etc.)
- [ ] Updates automatically when release.json changes
- [ ] Works in Claude Code sessions for this project

**Reference:** Claude Code status line documentation

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
**Priority:** P1 (enables branch display in App Store without filesystem access)
**Effort:** 6-8 hours

- [ ] #P1-GIT-BRANCH: Implement transcript-based git branch tracking and display for App Store builds

**Goal:** Display git branch in App Store builds using transcript data instead of filesystem access. Old approach (commit `b0abdb4`) disabled git entirely; new approach re-enables display.

**Key Finding:** Both transcript formats already contain branch data:
- Claude Code: `gitBranch` on every message (immediate updates)
- Codex: `session_meta.payload.git.branch` (updates on session start)
- Parser and schema already support extraction

**Investigation & Spec:** `build/notes/todo-support/P1-GIT-BRANCH-investigation.md`

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

**Status:** Phase 1 shipped, Phase 2 ready to implement
**Priority:** P1 (High - Quality/UX)
**Effort:** 5-7 hours

- [ ] #P1-USER-PROMPT-REWORK: Implement comprehensive user message summarization improvements with permission response handling

**Goal:** Mirror assistant-side summarization improvements (disposition taxonomy, verb-tense rules, structured prompts) for user messages. Includes permission response handling and bug fixes.

**Phase 1 (SHIPPED ✅):** Expanded negative word list - commit `a8577a9`

**Phase 2 scope:**
- Rewrite user prompt with explicit disposition taxonomy
- Add `permission_response` disposition for Claude Code permission dialogs
- Trust `classifyUserIntent` as source of truth in postProcess
- Fix double-prefix bugs ("You requested Claude Code You...")

**Spec:** `build/notes/todo-support/P1-USER-PROMPT-REWORK-spec.md`
**Planning:** `build/docs/planning/user-timeline-summarization-improvement.md`
**Related:** #P2-SUMMARIZATION-FIX (attribution issues - separate)

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

## Context Re-injection (1 item)

**Status:** Research/Design needed
**Priority:** P1 (enables AI workflow continuity)
**Effort:** 4-8 hours (Phase 1 MVP)

- [ ] #P1-CONTEXT-REINJECTION: Enable re-injection of found context into new AI conversations

**Problem:** User finds relevant message via search, wants to inject it (with surrounding context) into new Claude Code session. Current "Copy as JSON" lacks db entry ID, AI cannot look up surrounding context.

**Research Areas:**
1. "Copy with Context" action - fetch N surrounding messages, format as Markdown
2. Local web server / quasi-MCP - AI queries `localhost:PORT/context?entry_id=X`
3. File-based handoff - export to `~/.contextify/context-export/latest.md`
4. Enhanced Copy as JSON - include surrounding_context array
5. Local LLM summary - generate optimized context summary for re-injection

**Brief:** `/tmp/search-context-injection-brief.md` (move to `build/notes/todo-support/` when finalized)
**Related:** P1-CONVO-SEARCH spec section 5.4 (surrounding context query)

---

## Website Redesign (1 item)

**Status:** In Progress - design system and styling done, assets needed
**Priority:** P1 (public launch quality)
**Effort:** 4-6 hours remaining
**Branch:** `feature/design-system-and-website`

- [ ] #P1-WEBSITE-REDESIGN: Complete website with screenshots and deploy

**Completed (Dec 2025):**
- [x] Design system established (`build/design/brand/colors.md`)
- [x] Color migration from INSPINIA to design system tokens
- [x] Brand gradient divider below hero
- [x] Card hover effects (lift + shadow)
- [x] Solid navbar background for sticky behavior
- [x] Logomark copied to website assets
- [x] Bootstrap 5 landing page structure
- [x] Content pages (privacy, terms, support) with shared styling
- [x] Hero section with swoopity background SVG

**Remaining Work:**
1. **Screenshots (HIGH PRIORITY)**
   - Take app screenshot in light mode
   - Take app screenshot in dark mode
   - Export at 2x for retina
   - Place in `website/assets/img/`

2. **OG Image / Social Card**
   - Create 1200x630 banner for social sharing
   - `website/assets/img/og-banner.png`

3. **Favicon & Touch Icon**
   - Verify `website/favicon.ico` exists and is current
   - Verify `website/apple-touch-icon.png`

4. **Content Verification**
   - Test privacy.html, terms.html, support.html with new color tokens

5. **Responsive Testing**
   - Desktop (wide), tablet, mobile

6. **Deploy**
   - `./scripts/deploy-website.sh` (after screenshots added)

**Design Tools:**
- Comparator: `build/design/website/specimens/website-comparator.html`
- Color tokens: `build/design/brand/colors.md`

**Reference:** `build/docs/operations/marketing/launch-plan-v1.md`

---

# P2 (Medium Priority) - 41 Items

---

## #P2-PROJECT-COUNT-MISMATCH: Welcome modal project count includes non-displayed projects

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

## #P2-SEARCH-INDEXING-WARNING: Warn when searching incompletely indexed project

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
- Search results view (TBD - depends on #P1-CONVO-SEARCH implementation)

**Related:**
- #P1-CONVO-SEARCH (search implementation - this todo applies once search exists)
- `.backgroundIngestProgress` notification (already broadcasts remaining count)

---

## #P2-ACTIVATION-ORCH-UNIFICATION: Single orchestrator + activation façade

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

## #P2-ACTIVATION-OBS: Activation observability and sandbox retries

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

## #P2-CONSOLIDATE-USERDEFAULTS: Consolidate UserDefaults to single domain

**Status:** Not Started
**Priority:** P2 (code cleanup, reduces complexity)
**Effort:** 1-2 hours

**Issue:**
App uses two UserDefaults domains:
- `sh.contextify.Contextify` (bundle ID) - standard
- `dev.contextify` (shared suite) - for HUDPreferences

This causes confusion when resetting app state (both must be cleared) and was root cause of #P0-PROJECT-ROOT-MODAL recurring.

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

- [ ] #P2-DYNAMIC-FORWARDER: Implement dynamic download links that always point to latest release

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

## TODO System Refactoring (1 item)

**Status:** Research Complete
**Priority:** P2 (workflow improvement - current file is 2k+ lines)
**Effort:** 4-6 hours
**Research:** `build/notes/todo-support/P2-TODOS-REFACTOR-research.md`

- [ ] #P2-TODOS-REFACTOR: Refactor TODO system to reduce file size and improve AI efficiency

**Problem:**
- TODOS.md is 2k+ lines, AI must read full file to update one status
- Priority embedded in task IDs (e.g., `#P1-WEBSITE`) makes reprioritization awkward
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
**Priority:** P2 (UX improvement)
**Effort:** 4-6 hours

- [ ] #P2-BACKGROUND-SUMM: Re-implement background LLM summarization for "would-be-visible" entries

**Goal:** When app is backgrounded, continue summarizing entries the user is likely to scroll to. Pre-populates summaries for smoother UX when returning to foreground.

**Current behavior:** LLM summarization completely disabled when backgrounded (log: "App resigned active - background processing DISABLED"). This is policy, not a bug, but a missed opportunity.

**Design:** `build/notes/todo-support/P2-BACKGROUND-SUMM-design.md`

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
**Priority:** P2 (UX enhancement)
**Effort:** 4-6 hours

- [ ] #P2-WORKTREE: Add visual grouping for git worktrees and verify transcript isolation

**Goal:** Add subtle background color to project tabs to indicate related worktrees from the same git repository. Core worktree support already works (separate projects, transcript isolation by CWD).

**Main deliverable:** Hash git root path to consistent color, apply as tab background tint.

**Investigation:** `build/notes/todo-support/P2-WORKTREE-investigation.md`

---

## Project Tab Reordering UX (1 item)

**Status:** Investigation Complete - Ready for Implementation
**Priority:** P2 (UX improvement)
**Effort:** 3-4 hours

- [ ] #P2-TAB-REORDER-UX: Fix drag-drop precision and add keyboard shortcuts for tab reordering

**Issues:**
1. **Vertical drag sensitivity** - Small vertical drift cancels drag unexpectedly (fix: expand hit zone)
2. **Missing keyboard shortcuts** - Add `Shift-Cmd-Opt-[/]` to move active tab (no wrap-around)

**Investigation:** `build/notes/todo-support/P2-TAB-REORDER-UX-investigation.md`

---

## Release Workflow Python CLI Refactor (1 item)

**Status:** Ready for implementation
**Priority:** P2 (architectural improvement + App Store status integration)
**Effort:** 12-16 hours (incremental migration)

- [ ] #P2-PYTHON-CLI-REFACTOR: Refactor release workflow to Python CLI with App Store Connect API integration

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

# P3 (Low Priority / Deferred) - 17 Items

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

## Sidechain Transcript Enhancements (1 item)

**Status:** Backlog - v1 fix shipped, future enhancements identified
**Priority:** P3 (robustness improvements, no immediate user impact)
**Effort:** 8-12 hours total
**Reference:** `build/notes/todo-support/sidechain-transcript-enhancements.md`

- [ ] #P3-SIDECHAIN-ENHANCEMENTS: Implement schema-level and UX improvements for sidechain transcript handling

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
