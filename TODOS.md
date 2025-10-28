# TODO: Project Switcher & Multi-Project Mode

## P0 Bug Fixes (feature/project-switcher-fixes)

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

### 2. Unread Badges Not Showing for Inactive Projects
**Issue:** Project tabs don't show unread counts even after new messages arrive in non-active projects.

**Symptoms:**
- Badge counts remain at 0 despite new entries
- `ProjectSwitcherState.unreadCounts` dictionary may not be updating
- Events emitted but unread refresh not triggered

**Investigation needed:**
- Verify `ProjectEvent.transcriptUpdated` events are emitted after hoover
- Check if `scheduleUnreadRefresh()` is being called for inactive projects
- Confirm `getUnreadCounts(projectIds:)` query is correct
- Check if `activeProjectId` check is too aggressive

**Files to review:**
- `Contextify/Contextify/ProjectSwitcherState.swift:312-315` (transcriptUpdated handler)
- `app/Sources/ContextifyCore/Database/ProjectVisitsRepository.swift:163-187` (batch unread query)
- `app/Sources/ContextifyCore/ProjectActivityMonitor.swift:327-328` (event emission after hoover)

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

## Recently Completed Work (feature/project-switcher)

### Project Activity Monitor & Unread Badges
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

