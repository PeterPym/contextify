# TODO: Project Switcher & Multi-Project Mode

## P0 Bug Fixes

### 0. App Sandbox for App Store Submission
**Status:** Reverted due to file access issues. Requires proper implementation before App Store submission.

**Why it was reverted:**
Enabling `com.apple.security.app-sandbox = true` broke core functionality:
- ❌ Cannot access `~/.claude/projects` and `~/.codex/projects` for project discovery
- ❌ FSEvents monitoring blocked (cannot watch project directories)
- ❌ Projects window shows 0 projects
- ❌ Database location changes from `~/Library/Application Support/Contextify/` to sandboxed container

**What's needed:**
See detailed implementation plan: `build/notes/app-store/sandbox-implementation-plan.md`

**Commits:**
- `35ce380` - Removed iTerm2/terminal integration (entitlements cleanup)
- `b4b4762` - Enabled sandbox (reverted in `b1fe869`)

---

### 1. Timeline Summaries Show "infer from message" Placeholder
**Status:** High Priority - User-facing quality issue in timeline summaries

**Issue:**
User request summaries frequently show the placeholder text:
```
"You requested Claude Code to infer from message"
```

This happens when `classifyUserIntent()` returns `.unknown` because none of its heuristic patterns match the user's message.

**Root Cause:**
`FoundationLLM.swift:282-375` - `classifyUserIntent()` function uses pattern matching:
- **Directive patterns:** "can you", "could you", "please", imperative verbs
- **Question patterns:** "what", "why", "how", question mark at end
- **Report patterns:** "i updated", "i fixed", "i created"
- **Affirmative/Negative:** "yes", "ok", "no", "nope"
- **Default:** Returns `.unknown` if no patterns match (line 374)

When intent is `.unknown`, the LLM prompt template (line 1109) uses:
```
"You requested \(assistantName) to [infer from message]"
```

The LLM is supposed to replace `[infer from message]` with actual content, but sometimes it doesn't, leaving the placeholder visible.

**Example Messages That Trigger `.unknown`:**
- Single-word or terse commands not in imperative list ("revert", "investigate")
- Statements without clear directive words ("this broke the build")
- Context-dependent requests ("the project tab bar issue")
- Informal/casual phrasing that doesn't match patterns

**Investigation Needed:**
1. **Log intent classification results** to see which messages are classified as `.unknown`
2. **Sample real user messages** from database to identify common unmatched patterns
3. **Test if LLM is actually replacing the placeholder** or if it's passing through

**Possible Solutions:**

**Option A: Improve Heuristics (Quick Win)**
Add missing patterns to `classifyUserIntent()`:
- More imperative verbs: "investigate", "revert", "verify", "confirm", "try"
- Statement patterns: "this [verb]", "the [noun] [verb]"
- Shortened directives: "need to", "gotta", "lemme"

**Option B: Better LLM Prompt (More Reliable)**
Change line 1109 from:
```swift
- UNKNOWN     → "You requested \(assistantName) to [infer from message]"
```
To:
```swift
- UNKNOWN     → "You [infer concise action verb from MESSAGE]"
```

This removes the placeholder entirely and forces the LLM to synthesize the intent.

**Option C: Two-Pass Classification (More Expensive)**
If intent is `.unknown`, make a second LLM call to classify intent before summarizing. Cache the result.

**Option D: Remove UNKNOWN Template (Fallback)**
Don't provide a template for `.unknown` - let the LLM use generic "You [action]" format without guidance.

**Recommended Approach:**
1. Start with **Option A** - Add 10-15 more common patterns (1 hour)
2. Monitor logs to see if it reduces `.unknown` frequency
3. If still frequent, try **Option B** - Better prompt without placeholder
4. If persistent, investigate if LLM is ignoring instructions (**Option D**)

**Files to Modify:**
- `Contextify/Contextify/FoundationLLM.swift:282-375` - `classifyUserIntent()`
- `Contextify/Contextify/FoundationLLM.swift:1109` - Template for UNKNOWN intent

**Testing:**
1. Add logging to see intent classification distribution
2. Query database for messages with "infer from message" in summary
3. Test new patterns against real user messages
4. Verify summaries no longer show placeholder

**Success Criteria:**
- Less than 5% of user messages classified as `.unknown`
- Zero summaries containing "infer from message" placeholder
- Summaries accurately reflect user intent

---

### 2. First Startup Experience - Implemented, Needs Testing
**Status:** Implementation complete, requires testing with clean database.

**What was implemented:**
- ✅ Conversation log placeholders with context-aware empty states
- ✅ Loading states in ConversationMonitor
- ⚠️ Welcome modal and footer progress badge not yet implemented

**Testing required:**
- [ ] Test with clean database (delete `~/Library/Application Support/Contextify/contextify.db`)
- [ ] Verify placeholder states appear correctly during first startup
- [ ] Confirm smooth transition from loading to populated state
- [ ] Check that empty states show appropriate messages

**Still TODO:**
- Welcome modal for first launch with progress tracking
- Footer status indicator for discovery/indexing progress
- Progress callbacks from HooverEngine

**Files modified:**
- ✅ `Contextify/Contextify/ConversationTimelineView.swift` - Placeholder states

**Files still needed:**
- `Contextify/Contextify/FirstStartupOrchestrator.swift` (NEW - coordination)
- `Contextify/Contextify/WelcomeModalView.swift` (NEW - modal UI)
- `Contextify/Contextify/ContentView.swift` (footer badge)

---

### 1. Terminal Label Update Requires App Focus Cycle
**Issue:** The textarea label "Send to: [terminal title]" updates, but requires tabbing back to the app, then to terminal, then back to app to see the update.

**Current Behavior:**
- Terminal label does update when terminal window changes
- But requires: Terminal → Contextify → Terminal → Contextify to see the update
- Label is stale on direct Terminal → Contextify switch

**Root Cause Investigation Needed:**
- iTerm2Bridge may only fetch active terminal title on app focus
- Window focus event handlers may not be triggering proactively
- Terminal title fetch might need to happen on a timer or via notifications

**Possible Solutions:**
1. Poll terminal title on a timer when app is active (every 1-2 seconds)
2. Use NSWorkspace notifications to detect terminal window changes
3. Register for iTerm2 window change notifications if available
4. Fetch title immediately on any app activation, not just first activation

**Files to review:**
- `Contextify/Contextify/ITerm2Bridge.swift` (terminal integration)
- `Contextify/Contextify/ContentView.swift` (textarea label display)
- `app/Sources/ContextifyCore/HUDCore.swift` (terminal tracking logic)

---

## Recently Completed Work

### Consolidated Project Switching Code Paths (2025-10-30)
- ✅ Eliminated duplicate project switching logic
- ✅ Single canonical method for all project switches (`switchToProject`)
- ✅ Support for non-Git projects (Git branch shows "—" when not available)
- ✅ Both "Set as Current" button and project tab clicks use same code path
- ✅ Timeline updates correctly for both Git and non-Git projects

**Implementation:**
- Consolidated all project switching through `HUDViewModel.switchToProject()`
- Made Git repository detection optional (project works without `.git`)
- Both UI entry points now use consistent validation and state updates

**Files modified:**
- `app/Sources/ContextifyCore/HUDCore.swift` (switchToProject)
- `Contextify/Contextify/ProjectsViewModel.swift` (setAsCurrent)
- `Contextify/Contextify/ProjectSwitcherView.swift` (tab click handler)

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
- Add preference setting for timeline entry limit (currently hardcoded to 25 in ConversationMonitor.swift)
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

### Embedding & Semantic Search

**Current State:** Basic embedding generation and semantic search features are implemented but incomplete. Currently hidden behind developer mode flag.

**What's Implemented:**
- ✅ Embedding service integration (Apple's EmbeddingService on macOS 26+)
- ✅ Embedding database storage (SQLite with BLOB storage)
- ✅ Batch embedding generation UI (basic)
- ✅ Semantic search UI (basic cosine similarity search)
- ✅ Test buttons for embedding service and database

**What's Missing:**
- ❌ Production-ready UX (current UI is developer-focused)
- ❌ Automatic embedding generation (currently manual batch process)
- ❌ Search results ranking and display improvements
- ❌ Embedding cache invalidation strategy
- ❌ Progress feedback during batch operations
- ❌ Error handling and retry logic
- ❌ Integration with timeline (search within current project/transcript)
- ❌ Performance optimization for large datasets

**Proposed Work:**
1. **Batch Embedding Improvements:**
   - Add progress bar with ETA
   - Implement chunked processing for large transcript sets
   - Add "Resume" functionality for interrupted operations
   - Show which transcripts/entries are already embedded
   - Add "Update embeddings" for modified entries

2. **Semantic Search Enhancements:**
   - Improve search results display (show context, relevance score)
   - Add filters (by project, by date range, by transcript)
   - Integrate with timeline view (click result → jump to entry)
   - Add "Find similar" action on timeline entries
   - Implement search history

3. **Automatic Embedding Generation:**
   - Generate embeddings during transcript ingestion (HooverEngine)
   - Background queue for embedding generation
   - Configurable: "Generate embeddings automatically" setting
   - Batch backfill for existing transcripts on first enable

4. **UX Polish:**
   - Move from modal sheets to sidebar integration
   - Add keyboard shortcuts (Cmd+F for semantic search?)
   - Loading states and empty states
   - Error messages that explain what to do
   - Settings panel for embedding preferences

**Files Involved:**
- `Contextify/Contextify/BatchEmbeddingView.swift` - Batch UI
- `Contextify/Contextify/SemanticSearchView.swift` - Search UI
- `Contextify/Contextify/ContentView.swift` - Button visibility (currently dev-mode gated)
- `app/Sources/ContextifyCore/Embeddings/` - Core embedding logic

**When to Re-enable:**
Complete at least items 1-2 above before showing these features to general users.

