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

### 1. First Startup Experience - Implemented, Needs Testing
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

### 2. Complete Convert-to-Codex/Claude Code Transcript Behaviors
**Status:** High Priority - Transcript conversion feature incomplete

**Current State:**
TranscriptConverter.swift exists (33KB, last modified Oct 25) but conversion behaviors need completion and testing.

**What Exists:**
- ✅ `app/Sources/ContextifyCore/TranscriptConverter.swift` - Core conversion logic
- ✅ Documentation in `build/notes/archive/implementation-docs/transcript-tool-conversion/`
- ✅ Format specifications in `build/notes/technical-reference/claude-code-transcript-format.md`

**What Needs Completion:**
- [ ] Audit current conversion implementation for correctness
- [ ] Test convert-to-codex behavior (Claude Code → Codex format)
- [ ] Test convert-to-claude-code behavior (Codex → Claude Code format)
- [ ] Verify field mappings (content blocks, message types, UUIDs)
- [ ] Handle edge cases (empty transcripts, metadata-only files, malformed records)
- [ ] Add validation to detect format mismatches
- [ ] UI integration for triggering conversions (if not already present)
- [ ] Documentation of when/why users would convert formats

**Key Considerations:**
- Claude Code uses `text` content blocks, Codex uses `input_text`/`output_text`
- Message structure differences: Claude Code has top-level `uuid`/`type`, Codex wraps in `payload.type:"message"`
- Metadata record handling (file-history, summary, system messages)
- Timestamp format preservation

**Testing Scenarios:**
1. Convert real Claude Code transcript → Codex → verify in Codex CLI
2. Convert real Codex transcript → Claude Code → verify in Contextify
3. Round-trip conversion (both directions) and compare checksums
4. Convert empty/metadata-only transcripts
5. Convert large transcripts (10k+ entries)

**Files to Review:**
- `app/Sources/ContextifyCore/TranscriptConverter.swift`
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` (for format reference)
- `build/notes/technical-reference/claude-code-transcript-format.md` (spec)

**Success Criteria:**
- Converted transcripts load correctly in target tool (Claude Code or Codex)
- No data loss in conversion (all messages, metadata preserved)
- Conversion errors handled gracefully with clear error messages

---

### 3. QA Mixed-Mode Transcript Following & System Messages
**Status:** High Priority - Need to test/restore system message behavior

**Issue:**
When Contextify detects it's now following a different transcript for a project (e.g., user switched from Claude Code to Codex CLI, or started a new session), the app should show a system message in the timeline indicating the switch. This behavior may not be working correctly or may have regressed.

**Expected Behavior:**
- User is viewing project A in Contextify, following transcript session X
- User switches to a different transcript session Y (same project, different session ID)
- Contextify timeline should show a system message like:
  - "Now following session: [session-Y-name]"
  - "Switched from Claude Code to Codex CLI"
  - Or similar indicator that the active transcript changed

**Testing Scenarios:**
1. **Same Provider, Different Session:**
   - Start Claude Code session A in project
   - View in Contextify (should show session A timeline)
   - Start new Claude Code session B in same project
   - Verify system message appears: "Now following session B"

2. **Different Provider (Mixed Mode):**
   - Start Codex CLI session in project
   - View in Contextify (should show Codex timeline)
   - Start Claude Code session in same project
   - Verify system message: "Switched to Claude Code session"

3. **Transcript Deleted/Missing:**
   - Follow transcript X
   - Delete/move transcript X source file
   - Start new transcript Y
   - Verify system message: "Previous transcript no longer available, showing: [Y]"

4. **Manual Transcript Switch:**
   - Use Transcript Inventory to switch active transcript
   - Verify system message appears in timeline

**Files to Investigate:**
- `Contextify/Contextify/ConversationMonitor.swift` - Timeline state management, transcript switching logic
- `Contextify/Contextify/TimelineModels.swift` - System message models (`TimelineEntry` with `disposition: .system`?)
- `Contextify/Contextify/ConversationTimelineView.swift` - System message rendering
- `Contextify/Contextify/ConversationSources.swift` - Provider detection (Claude Code vs Codex)
- `app/Sources/ContextifyCore/Database/Repositories.swift` - Active transcript tracking

**Investigation Steps:**
1. Search codebase for "system message" or similar patterns
2. Check if system message insertion code was removed or disabled
3. Review timeline entry creation logic for transcript switches
4. Add logging to track when transcript switches occur
5. Test all scenarios above and document actual vs expected behavior

**Success Criteria:**
- Clear system messages appear when switching transcripts
- Messages are visually distinct (different styling, icon, color)
- User never confused about which transcript they're viewing
- System messages persist across app restarts

---

### 4. Terminal Label Update Requires App Focus Cycle
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

## Conversation Log Improvements

### Question Preservation in Assistant Summaries (Future Enhancement)
**Status:** Deferred - needs investigation

**Goal:** Preserve questions at end of assistant messages in timeline summaries.

**Example:**
```
Original: "Database cleaned successfully... Would you like me to launch the app?"
Current:  "Claude cleaned the database."
Desired:  "Claude cleaned the database and asked if you'd like to launch the app."
```

**Attempted Implementation:**
- Hybrid approach: regex detection + LLM integration
- Fast-path patterns: "would you like", "should i", "shall i", etc.
- LLM receives TRAILING_QUESTION field for summary formatting

**Issue:**
- Question extraction logic implemented but not detecting questions in practice
- Debug logging not appearing (print statements not showing in console)
- May be related to message preprocessing or truncation before extraction
- Needs deeper investigation into message flow and LLM prompt handling

**Next Steps:**
1. Investigate why debug logging doesn't appear
2. Check if message is truncated/preprocessed before reaching extractTrailingQuestion()
3. Verify LLM is receiving TRAILING_QUESTION field correctly
4. Consider alternative approach (post-processing LLM output vs pre-processing input)

**Files to review:**
- `Contextify/Contextify/FoundationLLM.swift` (extraction logic, LLM prompt)
- Message preprocessing pipeline (where is text truncated/cleaned?)

---

### Timeline Summary Intent Classification (2025-11-03)
- ✅ Eliminated "infer from message" placeholders in timeline summaries
- ✅ Improved intent classification with 40+ new patterns
- ✅ Added problem report detection ("did not work", "not working", etc.)
- ✅ Added missing imperative verbs ("read", "investigate", "verify", "analyze")
- ✅ Added informal statement patterns ("it's", "we're", "there are")
- ✅ Enhanced question pattern matching ("is there", "do you", "can we")
- ✅ Fixed UNKNOWN prompt template to eliminate placeholder leakage
- ✅ Added Unicode-aware word boundary matching
- ✅ Implemented regex caching for performance
- ✅ Added productive prefix support (re-, pre-, auto-, de-)

**Impact:** Reduced .unknown classification from ~15-30% to <5%

**Implementation:**
- Database analysis identified 268 placeholder instances across 56 unique messages
- Created analysis tools: `scripts/analyze_intent_classification.sh`, `scripts/generate_intent_improvements.py`
- Updated `FoundationLLM.swift` with comprehensive pattern improvements
- Added comprehensive test coverage for edge cases
- Cleared 56 timeline cache entries to force regeneration

**Commits:**
- `7493bec` - Eliminate 'infer from message' placeholders (main fix)
- `d69ff38` - Make patterns more specific with word boundaries
- `320fb10` - Improve accuracy with Unicode-aware matching
- `a5eee8a` - Address correctness issues (regex cache, productive prefixes)
- `1755813` - Whitespace merge fixes and polish

**Files modified:**
- `Contextify/Contextify/FoundationLLM.swift` - Intent classification and prompt templates
- `Contextify/ContextifyTests/FoundationLLMTests.swift` - Test coverage
- Analysis tools and documentation in `build/notes/technical-reference/`

### UI Consistency: Hourglass Icons (2025-11-03)
- ✅ Replaced animated spinner with static hourglass icon in Transcript Inventory
- ✅ Matches design pattern from Conversation Log timeline entries
- ✅ Consistent styling across all pending/generating states

**Implementation:**
- Changed `ProgressView()` to `Image(systemName: "hourglass")`
- Applied consistent styling: `.caption2` font, monochrome, tertiary foreground
- Reduces visual noise (static vs animated indicator)

**Commit:** `3b440d0`

**Files modified:**
- `Contextify/Contextify/TranscriptInventoryView.swift` (lines 316-325)

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

#### System Tray Support with Unread Indicator
**Proposed Feature:** Allow app to be closed to system tray instead of quitting, with visual indicator for activity.

**Requirements:**
- Close window (Cmd+W or red button) minimizes to system tray instead of quitting
- System tray icon shows unread count for currently selected project
- Click tray icon to restore window
- Optionally show unread counts for all projects (if space allows)
- Consider badge/dot indicator when any project has unread messages
- Preference setting: "Keep in system tray when closed" (default: enabled)

**Implementation Notes:**
- Use `NSStatusBar` for menu bar/system tray icon
- Monitor unread count changes via ProjectActivityMonitor events
- Update icon/badge when unread counts change
- Handle window close event to hide instead of terminate
- Right-click tray icon: "Show Contextify", "Quit"

**Files to Create/Modify:**
- `Contextify/Contextify/SystemTrayManager.swift` (NEW)
- `Contextify/Contextify/ContextifyApp.swift` - Handle window close behavior
- `Contextify/Contextify/SettingsView.swift` - Add system tray preference

**Design Considerations:**
- Should app launch directly to tray on startup if preference enabled?
- What icon to use? (Contextify logo, custom design, SF Symbol?)
- How to render unread count on small icon? (badge, text overlay)
- Notification integration? (e.g., show notification when unread count increases)

#### Transcript Inventory: Use Hourglass Icon for Pending Summarization
**Issue:** Transcript Inventory currently shows an "analyzing" spinner for transcripts with pending LLM summarization. This should use the hourglass icon (⏳ or SF Symbol "hourglass") to match the Conversation Log design pattern.

**Current Behavior:**
- Transcript rows show animated spinner when metadata generation is in progress
- Inconsistent with Conversation Log, which uses hourglass for pending summaries

**Expected Behavior:**
- Use same hourglass icon as Conversation Log (TimelineEntryRow.swift:192-206)
- No animation (static icon)
- Match styling/color with timeline entries

**Files to Modify:**
- `Contextify/Contextify/TranscriptInventoryView.swift` - Replace spinner with hourglass

**Reference Implementation:**
- `Contextify/Contextify/TimelineEntryRow.swift:192-206` - Hourglass icon usage

#### Transcript Inventory: Investigate Missing Metadata (UUID-only Display)
**Issue:** Many transcripts in Transcript Inventory show only the UUID with no title, description, or other metadata.

**Expected Behavior:**
- Transcripts should show:
  - Session title (generated or inferred from content)
  - Description (LLM summary)
  - Topics/tags (if available)
  - Timestamp range (first/last message dates)
  - Entry count

**Current Behavior:**
- Some transcripts display as UUID only (e.g., "A31F3D0A-4820-41AB-8121-0C81AC8533C4")
- Unclear why metadata is missing

**Investigation Steps:**
1. **Check database state:**
   - Query `transcripts` table for rows with NULL/empty metadata fields
   - Check if TranscriptMetadataOrchestrator processed these transcripts
   - Review `timeline_cache` for metadata entries

2. **Review metadata generation:**
   - Check if metadata generation failed (errors in logs)
   - Verify TranscriptMetadataOrchestrator is running
   - Check for empty/metadata-only transcripts (see transcript classification docs)
   - Review circuit breaker state (did generation get rate-limited?)

3. **Test metadata generation:**
   - Pick a UUID-only transcript
   - Manually trigger metadata generation
   - Verify it appears in UI after generation

4. **Check UI fallback logic:**
   - `TranscriptInventoryView.swift` - How does it handle missing metadata?
   - Should show placeholder text like "Untitled Transcript" instead of UUID?
   - Should trigger metadata generation on first view?

**Possible Root Causes:**
- Metadata generation never ran for these transcripts
- Empty/metadata-only transcripts (no conversational content to summarize)
- TranscriptMetadataOrchestrator circuit breaker tripped
- Database migration issue (metadata columns not populated)
- UI not falling back gracefully when metadata is NULL

**Files to Investigate:**
- `Contextify/Contextify/TranscriptInventoryView.swift` - UI rendering
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift` - Generation logic
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Transcript table schema
- `app/Sources/ContextifyCore/Database/Models.swift` - Transcript model

**Success Criteria:**
- All transcripts show meaningful metadata (title, description, or placeholder)
- UUID never shown as primary display (use as fallback only)
- Empty transcripts show clear indicator (e.g., "No conversational content")
- Metadata generation triggered automatically for new transcripts

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

### Custom Slash Command Metadata Reading
**Priority:** Low - Future Enhancement

**Goal:** Read custom slash command definitions from user's agent directories to generate context-aware summaries.

**Current State:**
- Built-in slash commands (Claude Code and Codex) have hardcoded summaries
- Custom slash commands use generic fallback: "You performed the following command: [command]"

**Proposed Implementation:**
1. **Discover command directories:**
   - Claude Code: `~/.claude/commands/`
   - Codex: `~/.codex/commands/`
   - Parse `.md` files to extract command descriptions

2. **Parse command metadata:**
   - Extract command name from filename (e.g., `review-prep.md` → `/review-prep`)
   - Parse frontmatter or first paragraph for description
   - Cache in memory for fast lookup during summarization

3. **Use in LLM summarization:**
   - Match detected slash command to custom command definition
   - Generate summary like: "You {description from .md file}"
   - Example: `/review-prep` → "You generated a comprehensive review package"

4. **Edge cases:**
   - Handle commands with same name across providers (prefer current provider)
   - Reload on file system changes (use FSEvents)
   - Graceful degradation if .md file is malformed

**Files to Create:**
- `app/Sources/ContextifyCore/SlashCommandRegistry.swift` - Command discovery and parsing
- `Contextify/Contextify/SlashCommandMetadata.swift` - Models for command metadata

**Files to Modify:**
- `Contextify/Contextify/FoundationLLM.swift` - Use registry in slash command detection

**Benefits:**
- Better timeline summaries for custom commands
- No hardcoding needed for user-specific workflows
- Automatically adapts to new commands

---

### Help/Tooltip System - Advanced Features (Lower Priority)

**Current State:** Core help/tooltip system complete (Phases 1-4). Advanced features deferred for future PRs.

**What's Implemented:**
- ✅ InfoButton + InfoPopoverContent reusable components
- ✅ Info popovers for complex features (AI status, error badge, follow modes, database location, empty states)
- ✅ First-use onboarding hints (project tab reordering)
- ✅ Timestamp tooltips with absolute time
- ✅ SF Symbols animations (error bounce, hourglass pulse)
- ✅ Full accessibility support (labels, hints, reduced motion)
- ✅ Help menu structure with submenus
- ✅ Comprehensive help documentation (6500+ words)

**What's Deferred:**
- ❌ HelpLink integration in Settings (link to online docs)
- ❌ First-launch onboarding tour (welcome screen, feature highlights)
- ❌ Context-sensitive help menu (dynamic items based on app state)
- ❌ In-app help search (⌘K command palette)

**Proposed Future Work:**

1. **HelpLink Integration** (1-2 hours)
   - Add HelpLink buttons in Settings for complex features
   - Link to GitHub wiki or hosted documentation
   - Supplement inline popovers with comprehensive guides
   - **Files:** SettingsView.swift, help documentation hosting
   - **Benefits:** Users can access detailed docs without leaving the app

2. **First-Launch Onboarding** (3-4 hours)
   - Welcome modal on first launch (TipKit or custom)
   - Show 2-3 key features ("Projects auto-discover", "Timeline shows AI activity", etc.)
   - Dismissible, shows once per install
   - **Files:** WelcomeView.swift (new), ContextifyApp.swift (launch detection)
   - **Benefits:** Reduces initial confusion for new users

3. **Context-Sensitive Help Menu** (2-3 hours)
   - Help menu items context-aware based on current view
   - Example: When viewing timeline → "Help > About Timeline" enabled
   - Dynamic menu item visibility/enabled state
   - **Files:** ContextifyApp.swift (HelpCommands), ConversationMonitor (state)
   - **Benefits:** Relevant help always available

4. **In-App Help Search** (4-6 hours)
   - ⌘K command palette for quick help access
   - Aggregates all help content (menu items, tooltips, documentation)
   - Fuzzy search across help topics
   - Recent help topics
   - **Files:** HelpSearchView.swift (new), HelpSearchIndex.swift (new)
   - **Benefits:** Fastest way to find answers

**Branch:** `claude/improve-mouseover-help-ux-011CUoSTV2ErvioRGaMEVySj`
**Reference:** `build/notes/design-reference/help-tooltip-ux-system.md`

---

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

---

### Multi-Machine Database Sync Protection (Lower Priority)

**Current State:** Contextify detects multi-machine access conflicts but does not prevent concurrent writes. Users receive warnings in Settings → Database tab when another machine has recently accessed the database (< 5 minutes). See `DatabaseAccessMetadata.swift` for implementation.

**Detection System:**
- ✅ Records machine ID, name, timestamp, and app version on every database open
- ✅ Warns when another machine accessed within last 5 minutes
- ✅ Shows informational message for historical multi-machine access
- ✅ Displays in Settings UI with time-since-access details

**Limitation:** Detection-only, not prevention. SQLite WAL mode + cloud sync (Dropbox, iCloud) don't guarantee atomic syncing of db/wal/shm files, leading to potential corruption if instances run simultaneously.

**Proposed Enhancement Options:**

1. **Block Launch on Recent Conflict** (Easiest - 2-4 hours)
   - **What:** Show modal alert and refuse to open database if another machine accessed < 5 min ago
   - **Implementation:**
     - Check `DatabaseAccessTracker.checkForConflicts()` on launch
     - If `.recentConflict`, show blocking alert with "Force Open" escape hatch
     - Update `DatabaseManager.swift` and `ContextifyApp.swift`
   - **Pros:** Prevents most concurrent access scenarios
   - **Cons:** False positives if user force-quit on other machine (timestamp not updated)
   - **Files:** `app/Sources/ContextifyCore/Database/DatabaseManager.swift`, `Contextify/Contextify/ContextifyApp.swift`

2. **Periodic Heartbeat Updates** (Medium - 4-6 hours)
   - **What:** Update `last_access` timestamp every 30 seconds while app is running
   - **Implementation:**
     - Add background Task to `ContextifyApp` that updates timestamp periodically
     - Makes "is other instance still running?" detection more accurate
     - Reduces false positive window from "time since launch" to "< 30 seconds"
   - **Pros:** More accurate conflict detection, better UX with Option 1
   - **Cons:** Extra writes (one every 30s), more cloud sync traffic
   - **Trade-off:** Could increase interval to 60-120s to reduce writes
   - **Files:** `app/Sources/ContextifyCore/Database/DatabaseAccessMetadata.swift`, `Contextify/Contextify/ContextifyApp.swift`

3. **Separate Sync-Friendly Architecture** (Hard - 40+ hours, major rewrite)
   - **What:** Replace SQLite with append-only event log + CRDTs for conflict-free replication
   - **Implementation:**
     - Design event-sourced architecture
     - Implement CRDT for project/transcript state
     - Build sync reconciliation logic
     - Migration path from current SQLite schema
   - **Pros:** True multi-machine support, no corruption risk
   - **Cons:** Major architectural change, significant testing burden, migration complexity
   - **Status:** Not recommended unless multi-machine sync becomes core feature
   - **Files:** Entire database layer rewrite

**Recommendation:**
- **Option 1** (Block Launch) is low-hanging fruit for users who enable custom database locations
- Combine with **Option 2** (Heartbeat) for best UX (reduced false positives)
- **Option 3** is overkill unless multi-machine sync becomes a primary use case

**Related Files:**
- `app/Sources/ContextifyCore/Database/DatabaseAccessMetadata.swift` - Current detection system
- `app/Sources/ContextifyCore/Database/DatabaseManager.swift` - Database opening, access recording
- `Contextify/Contextify/SettingsView.swift` - Conflict warning display
- `build/notes/design-reference/help-documentation.md` - User-facing multi-machine documentation

