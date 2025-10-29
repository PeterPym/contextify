# TODO: Project Switcher & Multi-Project Mode

## P0 Bug Fixes (feature/project-switcher-fixes)

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

### 1. Timeline Not Updating with New Messages
**Issue:** Conversation logs aren't showing new messages from any session (active or inactive projects).

**Symptoms:**
- Active project timeline doesn't update when new entries arrive
- Inactive project timelines remain frozen
- ConversationMonitor may not be receiving events from ProjectActivityMonitor

**Investigation needed:**
- Check if TranscriptWatcher is emitting file change events
- Verify ProjectActivityMonitor event stream is connected to ConversationMonitor
- Confirm hoover engine is processing new JSONL lines
- Check timeline state refresh triggers

**Files to review:**
- `Contextify/Contextify/ConversationMonitor.swift`
- `app/Sources/ContextifyCore/ProjectActivityMonitor.swift`
- `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`

---

### 2. First Startup Experience - No Feedback During Discovery
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

### 3. LLM Status Bar Not Showing In-Progress Work
**Issue:** Status bar shows "Up to date" while LLM processing is happening (e.g., summarizing entries after project switch).

**Symptoms:**
- Switch to project with unsummarized entries
- LLM starts processing (confirmed by logs)
- Status bar remains "Up to date" instead of showing progress
- Status stuck on previous state

**Investigation needed:**
- Check if `TimelineCacheMissGenerator` and `TranscriptMetadataOrchestrator` are reporting to StatusBar
- Verify StatusBarViewModel is aggregating both LLM queues correctly
- Confirm status bar is observing the right state properties
- Check if status updates are being throttled/debounced incorrectly

**Files to review:**
- `Contextify/Contextify/StatusBarViewModel.swift` (aggregation logic)
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` (queue reporting)
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift` (metadata queue reporting)
- `Contextify/Contextify/StatusBarView.swift` (UI updates)

---

### 4. Project Tab Organization (Drag & Drop Reordering)
**Issue:** No way to organize projects in the multi-project tabs.

**Requirements:**
- Allow drag-and-drop reordering of project tabs
- Persist order in UserDefaults or database
- Maintain order across app restarts

**Implementation approach:**
- Add `display_order` column to `projects` table (or use UserDefaults array)
- Implement SwiftUI drag-and-drop in project tabs UI
- Save order on change, restore on app launch

**Files to create/modify:**
- `Contextify/Contextify/ProjectsWindow.swift` (drag-drop UI)
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` (migration for display_order)
- `Contextify/Contextify/ProjectSwitcherState.swift` (persist/restore order)

---

### 5. Hide/Show Projects in Multi-Project List
**Issue:** No way to hide projects from the multi-project tabs.

**Requirements:**
- Mark projects as "hidden" (don't show in tabs)
- Show hidden projects in settings/management UI
- "Unhide all" bulk action

**Implementation approach:**
- Add `hidden` boolean column to `projects` table
- Filter hidden projects in `ProjectSwitcherState.allProjects`
- Add management UI in ProjectsWindow
- Add "Show Hidden" toggle or "Unhide All" button

**Files to modify:**
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` (migration for hidden column)
- `Contextify/Contextify/ProjectSwitcherState.swift` (filter hidden projects)
- `Contextify/Contextify/ProjectsWindow.swift` (hide/unhide UI)

---

## Recently Completed Work

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

#### Orphaned Projects (Projects with Missing Directories)
**Current State:** Projects are created from transcript discovery, extracting CWD from JSONL files. If a project directory is later deleted or renamed, the transcripts remain but the project becomes "orphaned" - it has valid transcripts but no corresponding filesystem directory.

**Problem:** Currently these orphaned projects generate error logs during discovery:
```
error: Failed to process project directory -Users-rob-code-personal-job-search:
       The operation couldn't be completed. (ContextifyCore.ProjectIdentityError error 3.)
```

**Root Cause:**
- `ProjectIdentity.reverseManglePath()` extracts CWD from transcript (e.g., `/Users/rob/code/personal/job-search`)
- `canonicalizePath()` verifies directory exists and throws `invalidPath` (error 3) if missing
- This is expected behavior for deleted/moved projects, not an error condition

**Proposed Solution:**

**Phase 1: Better Discovery Error Handling**
1. Distinguish between actual errors and expected orphaned projects:
   ```swift
   catch let error as ProjectIdentityError {
     switch error {
     case .invalidPath:
       // Expected: project directory was deleted/moved
       log.debug("Skipping orphaned project \(directory.lastPathComponent): directory no longer exists")
     case .cannotReadSessionMetadata:
       // Expected: empty or malformed session directory
       log.debug("Skipping invalid session directory \(directory.lastPathComponent): no readable metadata")
     case .unknownProvider:
       // Unexpected: should never happen
       log.error("Unknown provider for \(directory.lastPathComponent)")
     }
   }
   ```

2. Track orphaned projects in database:
   - Add `is_orphaned` boolean column to `projects` table
   - Set `is_orphaned = true` when `invalidPath` error occurs during discovery
   - Clear `is_orphaned = false` if directory reappears
   - Add `orphaned_since` timestamp for tracking

**Phase 2: Orphaned Projects UI (Projects Window)**
1. **Visual Decoration:**
   - Show orphaned badge/icon next to project name (e.g., ⚠️ or grayed out)
   - Use different text color or strikethrough style
   - Show tooltip: "Project directory not found: /expected/path"

2. **Filter/Section:**
   - Add "Show Orphaned Projects" toggle or filter
   - Or create separate "Orphaned Projects" section at bottom
   - Show count: "3 orphaned projects"

3. **Restore Action:**
   - "Restore Project Folder" button for each orphaned project
   - Shows modal: "Create directory at `/expected/path`? This will create the folder structure but will not restore any files that may have existed."
   - On confirm: `FileManager.default.createDirectory(atPath:withIntermediateDirectories:)`
   - After creation, mark `is_orphaned = false` and refresh UI
   - **Note:** This is a simple convenience feature - useful for projects that just need the folder structure (like note-taking projects)

4. **Remove Action:**
   - "Remove Project" button (disabled initially - see Transcript Removal Workflow below)
   - When transcript removal is implemented, this removes project + all transcripts
   - Shows count: "This will delete X transcripts and Y entries"
   - Confirmation required

**Phase 3: Advanced Features (Future)**
1. **Auto-detect moved projects:**
   - If project directory doesn't exist at original path, search for directories with same name
   - Offer to "reconnect" if found
   - Update CWD in database after user confirmation

2. **Export orphaned transcripts:**
   - Before deletion, offer to export transcripts to JSON/Markdown
   - Useful for archival purposes

**Database Schema Changes:**
```sql
-- Migration vXX: Add orphaned project tracking
ALTER TABLE projects ADD COLUMN is_orphaned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE projects ADD COLUMN orphaned_since TEXT; -- ISO8601 timestamp
CREATE INDEX idx_projects_orphaned ON projects(is_orphaned) WHERE is_orphaned = 1;
```

**Files to Modify:**
- `app/Sources/ContextifyCore/ProjectActivityMonitor.swift:244-246` - Improve error handling
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Add orphaned columns (vXX migration)
- `app/Sources/ContextifyCore/Database/Models.swift` - Add `isOrphaned`/`orphanedSince` to Project model
- `app/Sources/ContextifyCore/Database/Repositories.swift` - Add orphaned project queries
- `Contextify/Contextify/ProjectsWindow.swift` - Add orphaned UI section
- `Contextify/Contextify/ProjectsViewModel.swift` - Add restore/remove actions

**Testing Checklist:**
- [ ] Orphaned projects don't spam error logs (only debug level)
- [ ] Discovery marks projects as orphaned when directory missing
- [ ] Restore action creates directory and clears orphaned flag
- [ ] UI shows orphaned badge and correct count
- [ ] Re-creating directory manually (outside app) clears orphaned status on next discovery
- [ ] Remove action requires transcript removal workflow (disabled until implemented)

**Dependencies:**
- Phase 2 "Remove Action" depends on "Transcript Removal Workflow" (below)

**Related Issues:**
- Error logs: `ProjectIdentityError error 3` for `-Users-rob-code-personal-job-search`
- Error logs: `ProjectIdentityError error 2` for `2025` (likely empty session dir)

---

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

