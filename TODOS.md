# TODO: Project Switcher & Multi-Project Mode

## P0 Bug Fixes

### 0. Consolidate Project Switching Code Paths (ARCHITECTURAL)
**Issue:** Two different methods for switching projects with inconsistent behavior and validation.

**Problem:**
- `HUDViewModel.setProjectRoot(url:)` - Requires Git repository, returns error if not found
- `HUDViewModel.switchToProject(projectPath:)` - Works with or without Git, no validation
- This duplication creates confusion and potential bugs
- Projects without Git repositories should be supported but currently fail with `setProjectRoot()`

**Required Changes:**
1. **Support non-Git projects:**
   - Projects should work without `.git` directory
   - Git branch info should be optional (show "—" if no Git)
   - All project switching methods should handle both Git and non-Git projects

2. **Consolidate code paths:**
   - Eliminate duplicate project switching logic
   - Use single canonical method for all project switches
   - If one method must remain for legacy reasons, add clear deprecation comments

3. **Specific updates needed:**
   - `setProjectRoot()`: Remove Git requirement, make it optional
   - OR deprecate `setProjectRoot()` entirely in favor of `switchToProject()`
   - Add warning comments: "DO NOT use setProjectRoot() for project switching - use switchToProject() instead"
   - Ensure `ProjectsViewModel.setAsCurrent()` and `ProjectSwitcherView` tab clicks use same code path

**Files to modify:**
- `app/Sources/ContextifyCore/HUDCore.swift:799-819` (setProjectRoot)
- `app/Sources/ContextifyCore/HUDCore.swift:625-662` (switchToProject)
- `Contextify/Contextify/ProjectsViewModel.swift:82-95` (setAsCurrent)
- `Contextify/Contextify/ProjectSwitcherView.swift:23-28` (tab click handler)

**Testing checklist:**
- [ ] Projects without Git repositories can be switched to
- [ ] Git branch info shows "—" for non-Git projects
- [ ] Both "Set as Current" button and project tabs use same code path
- [ ] Timeline updates correctly for both Git and non-Git projects

---

### 1. First Startup Experience - No Feedback During Discovery
**Issue:** On first app launch or with empty database, no feedback about transcript discovery and ingestion progress.

**Symptoms:**
- Empty project list with no explanation
- Projects appear slowly, one at a time
- Conversation logs show as empty initially, then suddenly populate
- No progress indicator or ETA
- Appears broken or frozen

**Requirements:**
1. **Welcome Modal:** Show on first launch with real-time progress
   - Estimated time to completion
   - Current project/transcript being processed
   - Progress bar (X/Y transcripts)
   - Minimize/dismiss option

2. **Project Tab Loading States:** Show "Loading conversation... 47 transcripts found" placeholder
   - Replace with actual entries as they arrive
   - Smooth transition to normal state

3. **Conversation Log Placeholders:** Context-aware empty states
   - No transcripts: "Use Claude Code or Codex to populate the timeline."
   - Transcripts found but ingesting: "Loading conversation... ⏱️ About 2 minutes remaining"
   - Transcripts ingested but empty: "This conversation has not started yet."

4. **Footer Status Indicator:** Show discovery/indexing progress
   - "🔍 Discovering: 12 projects found"
   - "⚙️ Indexing: 21/47 transcripts (45%)"
   - "✓ Ready: 12 projects, 47 transcripts"

**Implementation approach:**
- Extend HooverEngine with progress callbacks
- Create FirstStartupOrchestrator for coordination
- Add loading states to ConversationMonitor
- Build WelcomeModalView component
- Add footer progress badge next to LLM status bar
- Store `firstLaunchCompleted` preference

**Detailed Spec:** `build/notes/feature-specs/first-startup-ux/spec.md`

**Files to create/modify:**
- `app/Sources/ContextifyCore/Database/HooverEngine.swift` (progress events)
- `Contextify/Contextify/FirstStartupOrchestrator.swift` (NEW - coordination)
- `Contextify/Contextify/WelcomeModalView.swift` (NEW - modal UI)
- `Contextify/Contextify/ConversationMonitor.swift` (loading states)
- `Contextify/Contextify/ConversationTimelineView.swift` (✅ placeholder states updated)
- `Contextify/Contextify/ContentView.swift` (footer badge)

**Estimated time:** 4-6 days

---

### 2. Textarea Label Not Updating with Active Terminal
**Issue:** The textarea label "Send to: [terminal title]" is not updating to reflect the most recently active terminal window.

**Symptoms:**
- Label shows stale or incorrect terminal window title
- Should update automatically when switching terminal windows
- Should track the most recently active/focused terminal

**Investigation needed:**
- Check iTerm2Bridge integration for window focus events
- Verify terminal window title fetching mechanism
- Confirm label update triggers on window focus change

**Files to review:**
- `Contextify/Contextify/ITerm2Bridge.swift` (terminal integration)
- `Contextify/Contextify/ContentView.swift` (textarea label display)
- `app/Sources/ContextifyCore/HUDCore.swift` (terminal tracking logic)

---

## Recently Completed Work

### Path Demangling Fix & UNIQUE Constraint Violations (2025-10-30)
- ✅ Fixed naive path demangling breaking for hyphenated directories
- ✅ Consolidated to single source of truth: `ProjectIdentity.reverseManglePath()`
- ✅ Removed naive string replacement in FSEvents handler, ProjectDiscoveryService
- ✅ Added session ID fallback to TranscriptRepository upsert (prevents UNIQUE violations)
- ✅ Cleaned up phantom projects from database (setup, litigation)
- ✅ Added comprehensive test coverage for hyphenated directories
- ✅ Fixed 1 misassociated transcript (wrong project ID)

**Root Cause:** Naive `replacingOccurrences(of: "-", with: "/")` broke for directory names with hyphens:
- `cli-ai-setup` → `/Users/rob/code/projects/cli/ai/setup` ❌ (should be `cli-ai-setup`)
- Created phantom projects that caused UNIQUE constraint violations on session IDs

**Commits:**
- `d131a1e` - Path demangling fixes + test coverage
- Related files: `ProjectActivityMonitor.swift`, `ProjectDiscoveryService.swift`, `Repositories.swift`, `ProjectIdentityTests.swift`

### Timeline Updates & Real-time Hoovering (2025-10-30)
- ✅ Timeline now updates in real-time when new messages arrive
- ✅ Active project timeline refreshes on new entries
- ✅ Inactive project timelines update via ProjectActivityMonitor events
- ✅ ConversationMonitor properly receives hoover completion events
- ✅ TranscriptWatcher emits file change events correctly

**Resolution:** Event stream architecture working correctly; timeline refresh triggers validated.

### LLM Status Bar Improvements (2025-10-30)
- ✅ Status bar now shows in-progress work during LLM processing
- ✅ Displays processing state when summarizing entries after project switch
- ✅ Aggregates both TimelineCacheMissGenerator and TranscriptMetadataOrchestrator queues
- ✅ Shows pending counts, ETAs, and errors correctly

**Resolution:** StatusBarViewModel aggregation logic validated and working correctly.

### Project Tab Organization (2025-10-30)
- ✅ Drag-and-drop reordering of project tabs implemented
- ✅ Order persisted in database (display_order column)
- ✅ Maintains order across app restarts
- ✅ Smooth drag animations and visual feedback

**Implementation:**
- Added `display_order` column to projects table
- SwiftUI drag-and-drop in ProjectSwitcherView
- Order saved on change, restored on launch

### Hide/Show Projects (2025-10-30)
- ✅ Projects can be hidden from multi-project tabs (right-click context menu)
- ✅ "Hide this Project" action marks project as hidden
- ✅ "Restore Hidden Projects" bulk action unhides all
- ✅ Hidden state persisted in database
- ✅ Projects window shows hidden projects with restore option

**Implementation:**
- Added `hidden` boolean column to projects table
- Filter hidden projects in ProjectSwitcherState
- Context menu UI in ProjectSwitcherView

### Orphaned Projects Detection (2025-10-30)
- ✅ Projects with missing directories marked as orphaned
- ✅ Added `is_orphaned` column to projects table
- ✅ Discovery errors downgraded from .error to .debug for expected cases
- ✅ Orphaned projects shown in UI with badge/indicator
- ✅ Can restore (create directory) or remove orphaned projects

**Implementation:**
- Better error handling in ProjectActivityMonitor
- Track orphaned state in database
- UI shows orphaned badge in Projects window

### Unread Tracking - Epoch Timestamps (feature/unread-badges-refactor)
- ✅ Epoch timestamp columns (v12: projects.last_viewed_ts, entries.created_ts)
- ✅ Millisecond precision truncation (prevents burst-entry misclassification)
- ✅ FK-safe CTE inserts + JOIN reconciliation (O(N+M), was O(N×M))
- ✅ Unread query GROUP BY index (v16: idx_entries_unread_join)
- ✅ Request ID normalization (v14: empty → entry_id fallback)
- ✅ FSEvents improvements (dispatch queue, batching, auto-teardown)
- ✅ Timeline cache index atomicity (remove stale keys on update)

**Migrations:** v12-v16
**Commits:** f8c2306, 84fcdce, 5be2bbc, 2e3d942, 47b93ef, 8884a79

### Project Activity Monitor & Unread Badges (feature/project-switcher)
- ✅ Fixed race conditions in event stream (created at init)
- ✅ Added termination handling for clean shutdown
- ✅ Emit events only after hoover completes (no "0 unread" flashes)
- ✅ Robust FSEvents path detection (explicit provider/path validation)
- ✅ 150ms coalescing for FSEvents bursts (prevents DB hammering)
- ✅ Made `start()` idempotent
- ✅ Removed naive in-memory increments (DB is source of truth)
- ✅ Added batch unread query APIs
- ✅ Added performance indices (v9 migration)
- ✅ Deterministic startup from app init

**Commits:**
- `8298d02` - Project switcher race conditions
- Related files: `ProjectActivityMonitor.swift`, `ProjectSwitcherState.swift`, `DatabaseSchema.swift`

### Assistant Usage FK Hardening
- ✅ Fixed FK constraint violations for `assistant_usage` table
- ✅ Added staging table (`assistant_usage_pending`) for out-of-order records
- ✅ Single-statement `INSERT ... WHERE EXISTS` (atomic, no race)
- ✅ BEFORE INSERT trigger for safety net (catches all direct inserts)
- ✅ Composite PRIMARY KEY `(entry_id, request_id)`
- ✅ Automatic reconciliation after hoover + at startup
- ✅ 7-day prune job for stale staging records
- ✅ Enhanced telemetry for reconciliation visibility

**Migrations:**
- v10: Staging table + indices
- v11: Hardening (trigger, composite PK, pruning, cleanup)

**Commits:**
- `592bb6f` - FK safety with staging & reconciliation
- `e123ba7` - Single-statement insert optimization
- `f957250` - v11 database hardening
- `fcd4cb9` - Removed one-time cleanup script

**Manual cleanup required (one-time):**
- Deleted 77 orphaned `assistant_usage` records
- Deleted 50 orphaned `timeline_cache` records
- Database was stuck on v8, couldn't run v9/v10/v11 due to FK violations

---

## Documentation Updates Needed

### Technical References
- ✅ LLM architecture overview exists: `build/notes/technical-reference/llm-processing-architecture.md`
- ✅ Timeline cache + LLM: `build/notes/technical-reference/timeline-cache-llm-architecture.md`
- ✅ SQL backend architecture: `build/notes/technical-reference/sql-backend-architecture.md`
- TODO: Update these docs with v9/v10/v11 schema changes

### Feature Specs
- ✅ Status bar spec: `build/notes/feature-specs/status-bar/spec-final.md`
- ✅ Project switcher spec: `build/notes/feature-specs/project-switcher/spec.md`
- TODO: Document project organization (drag-drop, hide/show) requirements

### README Updates
- TODO: Update `CLAUDE.md` with new database schema version (v11)
- TODO: Document reconciliation process for assistant_usage
- TODO: Add troubleshooting section for timeline/badge issues

---

## Testing Checklist (Before Merge to Main)

- [ ] Verify v9/v10/v11 migrations run successfully on clean DB
- [ ] Test project switching updates unread badges correctly
- [ ] Confirm timeline updates when new messages arrive (active + inactive projects)
- [ ] Verify LLM status bar shows processing state during summarization
- [ ] Test FSEvents coalescing (rapid file changes don't hammer DB)
- [ ] Confirm no FK violations on startup (check logs for FK errors)
- [ ] Test reconciliation logs show correct counts
- [ ] Verify 7-day prune job works (check pending table after 7 days)

---

## Future Enhancements (Lower Priority)

### Performance Optimization
- Add timeline virtualization for projects with 10k+ entries
- Implement incremental timeline loading (fetch on scroll)
- Cache LLM summaries aggressively (avoid re-generation)

### User Experience
- Add keyboard shortcuts for project switching (Cmd+Shift+[/])
- Show "last active" timestamp on project tabs
- Add "pin" feature to keep important projects at top
- Implement project search/filter in tabs

### Observability
- Add telemetry for unread refresh frequency
- Track LLM queue depth over time
- Monitor staging table growth (alert if > 1000 pending)

### Data Management & Cleanup

#### Transcript Removal Workflow
**Current State:** Once a transcript is ingested, it remains in the database permanently even if the source file is deleted. This is intentional (transcripts can be reproduced from files if needed), but we need a way for users to explicitly remove unwanted transcripts.

**Proposed Solution:**
Add transcript management to the **Transcript Inventory** window with:

1. **Delete Action:**
   - Right-click context menu or delete button on transcript rows
   - Shows confirmation dialog: "Remove [session-name]? This will delete the transcript and all its entries from the database. The source file will not be deleted."
   - Executes cleanup:
     ```sql
     DELETE FROM transcript_entries WHERE transcript_id = ?;
     DELETE FROM transcripts WHERE id = ?;
     ```
   - Refreshes inventory after deletion

2. **Bulk Cleanup:**
   - "Clean Up Missing Files" button
   - Scans for transcripts where source file no longer exists
   - Shows list of orphaned transcripts
   - Allows batch deletion with confirmation

3. **Test/Debug Transcript Detection:**
   - Auto-detect test transcripts (files matching `test-*`, `TEST-*` patterns)
   - Show badge or filter in inventory
   - "Remove Test Transcripts" action

**Files to Modify:**
- `Contextify/Contextify/TranscriptInventoryView.swift` - Add delete actions
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` - Add `deleteTranscript(id:)` method
- Consider adding "deleted_at" soft-delete column instead of hard delete (allows undo)

**Edge Cases:**
- What if transcript is currently being watched/hoovered? Stop watcher first
- What if it's the active transcript in timeline? Clear timeline or switch to another
- Should we archive transcript metadata before deletion? (export to JSON)

**Related Scripts:**
- `scripts/remove_test_transcripts.sh` - Example of manual cleanup (can be used as reference)
- `scripts/db_manager.sh` - Already has backup/restore, add transcript removal command

