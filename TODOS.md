# Contextify TODOs

This document tracks feature ideas, enhancements, and known issues for future development.

## Active Development

### P0 - RAG Embedding Generation Improvements
**Status:** Backlog (Post-Production Fixes)
**Priority:** P0 (blocks production RAG usage)
**Effort:** 1-2 weeks
**Dependencies:** Phase 4 RAG implementation complete

**Problem:** Current embedding generation is manual and requires user intervention via test modal window. Users must manually trigger batch generation, choose minimum length, and wait for completion. This creates friction for initial setup and ongoing maintenance as new transcripts arrive.

**Solution:** Automatic rolling embedding generation integrated with transcript ingestion, intelligent defaults, and Settings-based configuration.

**Implementation Tasks:**

#### 1. Automatic Rolling Embedding Generation
**Scope:** Generate embeddings automatically as new transcript entries are ingested

**Design:**
- Hook into `HooverEngine` transcript ingestion pipeline
- After each transcript batch is written to DB, trigger embedding generation for new entries
- Background actor-based processing to avoid blocking UI
- Configurable: Enable/disable automatic generation in Settings
- Rate limiting: Don't overwhelm device (max 50 entries/minute)
- Respect minimum content length filter (skip short entries)

**Technical Approach:**
```swift
// In HooverEngine or TranscriptOrchestrator
func ingestComplete(newEntryIds: [String]) async {
  guard Preferences.shared.autoGenerateEmbeddings else { return }

  // Filter for entries meeting minimum length requirement
  let eligible = await filterEligibleEntries(newEntryIds)

  // Queue for background embedding generation
  await EmbeddingOrchestrator.shared.queueForGeneration(eligible)
}
```

**Benefits:**
- Zero manual intervention for ongoing usage
- Embeddings stay up-to-date with transcript ingestion
- Search always includes recent conversations
- Better user experience (just works™)

#### 2. Intelligent Default Minimum Content Length
**Scope:** Set sensible default for minimum content length, allow user override

**Current State:**
- Batch UI defaults to 100 characters
- Users must manually adjust slider (50-500 range)
- No guidance on optimal values

**Proposed Defaults:**
- **Default: 200 characters** (based on semantic search effectiveness)
- Rationale:
  - <100 chars: Often acknowledgements, "OK", "Sure", etc. (low signal)
  - 100-200 chars: Marginal utility, still often simple responses
  - 200+ chars: Substantive content (code, explanations, questions)
  - 500+ chars: Diminishing returns (already high quality)
- Display recommendation in Settings UI: "Recommended: 200-300 chars"
- Store user preference per-project (some projects are more verbose)

**UI Design:**
```
┌─────────────────────────────────────────┐
│ Embedding Settings                      │
├─────────────────────────────────────────┤
│                                         │
│ Minimum Content Length: 200 chars      │
│ ├─────●─────────────┤  [Reset]          │
│ 50    200    500                        │
│                                         │
│ ℹ️ Recommended: 200-300 chars           │
│   Shorter entries often lack semantic   │
│   value for search.                     │
│                                         │
│ Coverage: 1,234 / 2,567 entries (48%)  │
│                                         │
└─────────────────────────────────────────┘
```

#### 3. Initial Hoovering Integration
**Scope:** Generate embeddings automatically during first-time app setup

**User Journey:**
1. User launches Contextify for first time
2. App discovers existing Claude Code/Codex projects
3. HooverEngine ingests all transcripts → DB
4. **NEW:** Automatically queue all eligible entries for embedding generation
5. Show progress: "Setting up semantic search... (1,234 / 2,567 entries)"
6. User can use app immediately; embeddings generate in background
7. Search becomes progressively more complete as embeddings finish

**Implementation:**
```swift
// In ProjectDiscoveryService or initialization logic
func initialSetup() async {
  // Phase 1: Discover projects
  let projects = await discoverAllProjects()

  // Phase 2: Ingest transcripts
  for project in projects {
    await hoover.ingestProject(project)
  }

  // Phase 3: Generate embeddings (NEW)
  if Preferences.shared.autoGenerateEmbeddings {
    await EmbeddingOrchestrator.shared.generateForAllProjects(
      minLength: Preferences.shared.minEmbeddingLength
    )
  }
}
```

**Progress UI:**
- Non-blocking banner at bottom of window
- "Generating embeddings for search... 1,234 / 2,567 (48%)"
- Estimated time remaining
- Dismissible (continues in background)
- Preference: "Don't ask again" to skip initial generation

#### 4. Move Batch Embedding UI to Settings
**Scope:** Relocate batch embedding test modal to Settings window as permanent feature

**Current State:**
- `BatchEmbeddingView` accessible via test button in ContentView (temporary)
- Feels like debug tool, not production feature
- Awkward discovery (hidden test buttons)

**Proposed Location:**
- Settings window → **"Search" tab** (or "Embeddings" tab)
- Sections:
  1. **Automatic Generation** (Enable/disable, minimum length)
  2. **Manual Generation** (Trigger batch for all projects or current project)
  3. **Status** (Coverage stats, last generated timestamp)
  4. **Advanced** (Clear all embeddings, rebuild from scratch)

**Settings UI Design:**
```
┌─────────────────────────────────────────────────────┐
│ Search Settings                                     │
├─────────────────────────────────────────────────────┤
│                                                     │
│ ┌─ Automatic Embedding Generation ─────────────┐  │
│ │ ☑ Generate embeddings automatically          │  │
│ │   New transcript entries will be embedded    │  │
│ │   in the background as they arrive.          │  │
│ │                                               │  │
│ │ Minimum Content Length: 200 characters       │  │
│ │ ├─────●─────────────┤  [Reset to Default]    │  │
│ │ 50    200    500                              │  │
│ │                                               │  │
│ │ ℹ️ Only entries with ≥200 chars will be       │  │
│ │    embedded for semantic search.             │  │
│ └───────────────────────────────────────────────┘  │
│                                                     │
│ ┌─ Coverage ────────────────────────────────────┐  │
│ │ All Projects: 3,456 / 7,890 entries (44%)    │  │
│ │ Current Project: 1,234 / 2,567 entries (48%) │  │
│ │                                               │  │
│ │ Last generated: 2 hours ago                  │  │
│ └───────────────────────────────────────────────┘  │
│                                                     │
│ ┌─ Manual Generation ───────────────────────────┐  │
│ │ [Generate for All Projects]                   │  │
│ │ [Generate for Current Project Only]           │  │
│ │                                               │  │
│ │ [Clear All Embeddings]  [Rebuild from Scratch]│  │
│ └───────────────────────────────────────────────┘  │
│                                                     │
│ ┌─ Advanced ────────────────────────────────────┐  │
│ │ Embedding Model: NLContextualEmbedding (512)  │  │
│ │ Version: 1                                    │  │
│ │ Storage: ~14.2 MB                             │  │
│ └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

**Migration:**
- Remove test buttons from `ContentView.swift` (lines ~106-127)
- Move `BatchEmbeddingView` to Settings/SearchSettingsView
- Add new `SearchSettingsView` component
- Update `SettingsView` to include Search tab
- Update menu: Settings → Search (or Cmd+,)

**Files to Modify:**
- Remove from: `ContentView.swift` (test buttons)
- Add: `SearchSettingsView.swift` (new file)
- Update: `SettingsView.swift` (add Search tab)
- Update: `ContextifyApp.swift` (Settings scene already exists)

#### 5. Convert Search Modal to Native macOS Window UI
**Scope:** Update search modal to use standard macOS window chrome with native red close button

**Current State:**
- `SemanticSearchView` uses custom `.sheet()` or custom window styling
- Lacks standard macOS window controls (red/yellow/green traffic lights)
- Feels inconsistent with native macOS applications

**Proposed Change:**
- Use proper `WindowGroup` or native `NSPanel` for search modal
- Include standard window chrome:
  - Red close button (top left)
  - Yellow minimize button
  - Green zoom/fullscreen button
- Standard title bar with "Semantic Search" title
- Native shadow and rounded corners
- Consistent with macOS Human Interface Guidelines

**Implementation:**
```swift
// In ContextifyApp.swift
Window("Semantic Search", id: "semantic-search") {
  SemanticSearchView()
    .environment(/* ... */)
}
.defaultSize(width: 800, height: 600)
.windowStyle(.automatic)  // Standard macOS window chrome
```

**Benefits:**
- Native macOS feel and behavior
- User-familiar window controls
- Better integration with macOS window management (Mission Control, Spaces, etc.)
- Improved accessibility (standard window controls)

**Implementation Phases:**

**Phase 1: Settings UI Migration** (~1-2 days)
- Create `SearchSettingsView` with basic UI
- Move batch generation controls from test modal
- Add to Settings window as new tab
- Remove test buttons from main window

**Phase 2: Intelligent Defaults** (~1 day)
- Change default minimum length to 200 chars
- Add recommendation text to UI
- Add coverage calculation and display
- Add "Reset to Default" button

**Phase 3: Rolling Generation** (~2-3 days)
- Hook into HooverEngine completion
- Implement background queueing
- Add rate limiting (50 entries/min)
- Add enable/disable preference
- Add progress indicator

**Phase 4: Initial Setup Integration** (~2-3 days)
- Detect first-time app launch
- Trigger automatic generation after hoovering
- Add progress banner to main window
- Add "Skip" option with preference persistence

**Total Effort:** ~1-2 weeks

**User Benefits:**
- ✅ Zero manual setup for semantic search
- ✅ Embeddings stay current automatically
- ✅ Sensible defaults (200 char minimum)
- ✅ Professional Settings integration
- ✅ Clear visibility into coverage status
- ✅ Power users can still customize

**Related Files:**
- `BatchEmbeddingView.swift` - To be moved/refactored
- `EmbeddingOrchestrator.swift` - Add rolling generation support
- `HooverEngine.swift` / `TranscriptOrchestrator.swift` - Add post-ingest hooks
- `SettingsView.swift` - Add Search tab
- `SearchSettingsView.swift` - New file
- `HUDPreferences.swift` or new `SearchPreferences.swift` - Store settings

**Edge Cases:**
- User disables automatic generation: Manual controls still work
- Device under heavy load: Rate limit/pause embedding generation
- Very large corpus (100K+ entries): Show estimated time, allow cancellation
- Multiple projects ingesting simultaneously: Queue globally, process serially
- First launch with no transcripts: Skip embedding setup entirely

---

### P0 - Global Projects Discovery & Management
**Status:** Complete - Merged to Main
**Priority:** P0 (blocks multi-project RAG usage)
**Effort:** 2-3 weeks
**Feature Spec:** `build/notes/archive/projects-discovery-feature-spec.md`

**Problem:** Currently only discovers transcripts for current project root. Users with multiple projects must manually switch to make transcripts searchable.

**Solution:** Auto-discover all Claude Code + Codex projects at startup, ingest all transcripts, provide Projects Window (Window > Projects) for browsing/switching.

**Implementation Phases:**
1. **Phase 1: Backend** - ProjectDiscoveryService, path mapping, auto-ingestion
2. **Phase 2: UI** - ProjectsWindow, list view, Set as Current, Reveal in Finder
3. **Phase 3: Integration** - Auto-discovery at startup, menu items, background refresh
4. **Phase 4: Polish** - Error handling, performance, accessibility

**Future Enhancements (Post-MVP):**
- Project favorites (pin to top)
- Project groups/tags for organization
- Exclude/hide projects from discovery
- Multi-project search weights/boosting
- Project statistics dashboard
- Cross-project pattern detection
- Manual project addition (Codex-only support)

**READ FULL SPEC:** `build/notes/archive/projects-discovery-feature-spec.md` (comprehensive design doc)

### P0 - In Progress
- Line number tracking for narrative composition

### P1 - Next Up
- Narrative composition from selected timeline entries

## Backlog

### Available Feature Branches

#### Transcript Format Converter
**Branch:** `feature/transcript-converter`
**Status:** Complete, ready to merge if needed

Bidirectional converter script for Claude Code ↔ Codex CLI transcript formats. Includes auto-correction of Codex output filenames, metadata generation (session_meta, event_msg), UUID validation, and comprehensive documentation.

Files added:
- `scripts/convert_transcript.py` - Main converter
- `scripts/CODEX_REQUIREMENTS_FINAL.md` - Requirements checklist
- `scripts/CODEX_SESSION_FORMAT.md` - Format reference
- `scripts/TRANSCRIPT_CONVERTER_README.md` - Usage guide
- Additional documentation files

### Far Future / Low Priority

#### Database Encryption
**Status:** Attempted, failed to complete
**Priority:** Low (consider only if user requests)
**Branch:** `feature/encryption-production-hardening` (pushed to origin)

**Summary:**
Attempted to implement SQLCipher encryption for the transcript database. Infrastructure was built (EncryptionManager, KeychainManager, DatabaseMigration, Settings UI) but the core encryption operation consistently fails with "database disk image is malformed" errors when using `sqlcipher_export()`.

**What was tried (all failed):**
- Multiple export directions (source→encrypted, encrypted→source)
- Different journal modes (WAL, DELETE)
- PRAGMA rekey approach (wrong API for initial encryption)
- DatabaseQueue vs DatabasePool
- Export from backup instead of original
- Read-only verification
- 10+ different implementation approaches

**Current state:**
- SQLCipher 4.6.1 (latest) + GRDB 7.8.0 (recent)
- All dependencies integrated
- UI and infrastructure code complete
- Core encryption operation produces corrupted databases
- Root cause unknown after extensive debugging

**If revisiting:**
1. Create minimal reproduction case outside main app
2. Test with tiny database to isolate the issue
3. Consider filing bug report with SQLCipher/GRDB
4. Or find someone who's successfully used SQLCipher + GRDB on macOS
5. Original goal was likely cloud backup - consider implementing that WITHOUT encryption first

**Note:** This feature consumed significant development time with no working result. Recommend low priority unless there's specific user demand for encryption.

### Product Direction Proposals

#### Proposal: Simplify to Timeline + Cloud Backup Focus
**Status:** Under consideration
**Priority:** TBD
**Type:** Strategic direction

**Proposed Changes:**
Remove terminal integration features and focus exclusively on:
1. **Timeline display** - Visualizing Claude Code/Codex conversation history
2. **Cloud backup** - Backing up transcripts to cloud storage

**Code to potentially remove:**
- Text area for sending commands to terminal
- "Send to Terminal" functionality
- "Retrieve from Terminal" functionality
- Terminal integration/automation code

**Potential benefits:**
- Simpler, more focused product
- Reduced maintenance burden
- Clearer value proposition
- Less code to maintain

**Considerations:**
- Are terminal features being used?
- What use cases would be lost?
- Is there overlap with other tools?
- What's the migration path for existing users?

**Next Steps:**
- Validate assumptions about feature usage
- Gather user feedback if applicable
- Decide on direction before implementing
- Create detailed removal plan if approved

**Files to review (if approved):**
- Any terminal integration code
- Send/retrieve command handlers
- Text area UI components not used for display
- Related preferences/settings

### Technical Debt / Optimizations

#### Database Lock Contention & WAL Checkpoint Improvements
**Status:** Open (2025-10-27)
**Priority:** Medium-High (impacts timeline reliability)
**Category:** Performance / Reliability
**Related:** Timeline updates, LLM queue, HooverEngine

**Problem:**
Timeline stops updating with new conversation entries during high database load. Root cause is SQLite WAL checkpoint failures with `database table is locked` errors. Multiple components compete for write locks:
1. `TimelineCacheMissGenerator` - Batch LLM summary writes
2. `HooverEngine` - Streaming transcript ingestion
3. Background discovery - WAL checkpoint operations (`PRAGMA wal_checkpoint(PASSIVE)`)

**Current Workaround:**
Restart app to clear locks (temporary fix).

**Mitigations Implemented:**
- ✅ LLM request cancellation when switching projects (reduces contention by clearing inactive project queues)
- ✅ Added `projectId` tracking to `CacheMiss` structs
- ✅ Auto-cancel pending LLM work in `onProjectOrSessionChange()`

**Recommended Long-Term Fixes:**

1. **Reduce WAL Checkpoint Frequency** (2-3 hours)
   - Current: Aggressive passive checkpointing during background discovery
   - Solution: Reduce frequency or switch to manual/truncate mode
   - Files: `ConversationMonitor.swift`, background discovery logic
   - Risk: WAL file growth (monitor size)

2. **Transaction Timeout & Retry Logic** (1 day)
   - Add exponential backoff for `SQLITE_BUSY` errors
   - Implement transaction retry wrapper with max attempts
   - Files: `DatabaseManager.swift`, all `db.write {}` calls
   - Benefits: Graceful degradation under load

3. **Connection Pooling Optimization** (2-3 days)
   - Separate read/write connection pools
   - Dedicated long-running read connection for queries
   - Short-lived write connections for commits
   - Files: `DatabaseManager.swift`
   - Trade-off: Complexity vs reliability

4. **Deferred Write Queue for LLM Cache** (2-3 days)
   - Queue LLM cache writes instead of immediate commits
   - Batch multiple cache entries into single transaction
   - Flush queue on idle (2s debounce) or size threshold (50 entries)
   - Files: `TimelineCacheMissGenerator.swift`, `TranscriptOrchestrator.swift`
   - Benefits: Reduces write frequency by 10-20x

5. **WAL Mode Tuning** (1-2 hours)
   - Adjust `PRAGMA wal_autocheckpoint` threshold (default: 1000 pages)
   - Consider `PRAGMA journal_size_limit` to cap WAL growth
   - Monitor WAL file size: `ls -lh ~/Library/Application\ Support/Contextify/*.db-wal`
   - Files: `DatabaseSchema.swift`, initialization

**Monitoring & Metrics:**
Add telemetry to track:
- Database lock errors per hour
- WAL file size trends
- Transaction retry counts
- Write queue depth (if implementing deferred writes)
- Checkpoint success/failure rate

**Testing Strategy:**
1. **Stress test:** Rapid project switching (Cmd+Shift+]) with LLM queue active
2. **Monitor logs:** `grep "database table is locked" /tmp/contextify-recent.log`
3. **Success criteria:**
   - Timeline updates reliably for 8+ hours
   - WAL checkpoint errors <1 per hour
   - No user-visible hangs

**Implementation Priority:**
1. **Phase 1 (Quick Wins - 1-2 days):** WAL tuning + Transaction retry logic
2. **Phase 2 (Medium Effort - 2-3 days):** Deferred write queue for LLM cache
3. **Phase 3 (Long Term - 3-5 days):** Connection pooling optimization

**Related Files:**
- `Contextify/Contextify/ConversationMonitor.swift` - Background discovery, checkpoint calls
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` - LLM cache writes
- `app/Sources/ContextifyCore/Database/HooverEngine.swift` - Transcript ingestion writes
- `app/Sources/ContextifyCore/Database/DatabaseManager.swift` - Connection management
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - WAL configuration

**References:**
- SQLite WAL documentation: https://www.sqlite.org/wal.html
- GRDB transaction handling: https://github.com/groue/GRDB.swift/blob/master/Documentation/Transactions.md
- Logs showing lock errors: `/tmp/contextify-recent.log` (search for "database table is locked")

### Technical Debt / Optimizations

#### Phase 2: LLM Session Management & Safety Optimizations
**Status:** Deferred (Post-P0/P1 cleanup)
**Priority:** High (P1.5) - Should proceed before new features
**Effort:** Medium-Large (~3-5 sessions)
**Risk:** Medium (requires careful actor isolation)
**Documentation:** [`build/notes/archive/phase-2-llm-optimizations.md`](build/notes/archive/phase-2-llm-optimizations.md)

Following comprehensive P0/P1 fixes (commits `b375246`, `fbe78a9`, `4941bdf`), 12 additional optimizations were identified during ultrathink review. These address **session lifecycle management**, **resource bounds**, and **operational safety** for production LLM usage.

**Why prioritize this?**
1. **Resource Efficiency**: Current unbounded controller pool leaks memory in long-running sessions
2. **Privacy Compliance**: Raw prompts logged to console may contain user data
3. **Operational Safety**: No per-session limits; risks context pollution and rate exhaustion
4. **Production Resilience**: Missing circuit breakers, cancellation handling improvements needed

**Core issues addressed:**
- Actor-isolated LRU controller pool (eliminates race conditions, bounds memory)
- Session age/request limits (automatic resource recycling)
- Log sanitization (SHA256 hashing instead of raw prompts)
- Enhanced cancellation safety (prevents continuation leaks)
- Stable instruction templates (no per-message controller keys)

**Recommended phasing:**
- **Phase 2a** (High ROI, ~1 session): Session limits, log sanitization, sync simplification
- **Phase 2b** (Architectural, ~2-3 sessions): Controller pool, cancellation fixes, circuit breaker
- **Phase 2c** (Cleanup, ~1 session): Remove global counters, misc cleanup

**Why defer from Phase 1?**
Critical correctness bugs (index drift, memory leaks, retry paradoxes, error handling) are now resolved. These optimizations improve resource efficiency and resilience but don't fix observable production failures. They're important follow-up work that should happen before major new features.

**Next steps:**
1. Review detailed implementation plan in linked document
2. Schedule Phase 2a as next sprint (quick wins)
3. Plan Phase 2b for following sprint (larger refactor)

---

### Bugs

#### Database Naming Inconsistency
**Status:** Open
**Priority:** Medium (naming clarity)

The database filename is currently `transcripts.db` but should be `contextify.db` for better clarity and consistency with the application name.

**Current State:**
- Actual database file: `~/Library/Application Support/Contextify/transcripts.db`
- Documentation refers to it as both `contextify.db` and `transcripts.db`
- Causes confusion when debugging or accessing database directly

**Tasks:**
1. Find all documentation references to `contextify.db` that should be `transcripts.db`
2. Decide on official name: `contextify.db` (preferred) or keep `transcripts.db`
3. If renaming to `contextify.db`:
   - Update DatabaseManager to use new filename
   - Add migration logic to rename existing database files
   - Update all documentation
   - Test migration path for existing users

**Files to check:**
- `DatabaseManager.swift` - Database file path
- All documentation in `build/notes/`
- README files mentioning database location
- Test scripts that reference the database

#### Bash Command Handling in Timeline
**Status:** Open
**Priority:** Medium (UX polish)

Timeline entries for bash commands are not handled well when displayed in the conversation log. The raw bash input/output creates cluttered, hard-to-read entries that don't provide clear intent.

**Current Behavior:**
When a user runs a bash command (e.g., `git status`, `git push`), the timeline shows raw command text without context or summarization.

**Example from screenshot:**
```
<bash-input>git status</bash-input>
<bash-stdout>On branch main
Your branch is ahead of 'origin/main' by 4 commits...
```

**Desired Behavior:**
Timeline should show a human-friendly summary of bash commands with clear intent:
- "You ran a bash command to check git status"
- "You ran a bash command to push commits to origin"
- "You ran a bash command to list directory contents"

**Implementation Considerations:**
- Add special handling in transcript parsing for `<bash-input>` tags
- Use LLM to generate intent summaries for bash commands
- Consider common command patterns (git, npm, build tools) for faster categorization
- Show expandable detail view with full command + output
- May need to add `bash_command` disposition type to timeline cache

**Files to Check:**
- `TranscriptParsers.swift` - Parsing of bash command blocks
- `TimelineCacheMissGenerator.swift` - LLM summarization logic
- `ConversationMonitor.swift` - Entry filtering and display logic
- `TimelineEntryRow.swift` - UI rendering of bash entries

#### Horizontal Rule Alignment (UI Polish)
**Status:** Open
**Priority:** Low (visual nit)

The horizontal rule/divider in the right conversation log panel does not align vertically with the horizontal rule in the main left panel. The right panel divider sits slightly lower, creating a visual misalignment.

**To Fix:**
- Adjust padding/spacing in the conversation timeline view header
- Ensure both panels have matching vertical spacing from top
- Likely a margin or padding discrepancy in SwiftUI layout

**Files to Check:**
- `ConversationTimelineView.swift` - Timeline panel layout
- Main content view layout - Left panel divider position

#### Codex Icon Color Incorrect
**Status:** Completed (2025-10-10)
**Priority:** Medium (visual accuracy)

~~When Codex log messages are being created/displayed, the Codex icon appears in blue but should be white (or the correct theme color).~~

**Solution Implemented:**
Changed Codex CLI provider color from `.blue` to `.white` in `TimelineEntryRow.swift` `providerColor()` function. Claude Code icon remains orange.

#### Provider Name in Timeline Summaries
**Status:** Completed (2025-10-10)
**Priority:** Medium (accuracy)

~~Timeline entry summaries for Codex messages incorrectly say "Claude [did something]" when they should say "Codex [did something]" to accurately reflect which AI provider performed the action.~~

**Solution Implemented:**
- Added `provider` parameter throughout LLM summarization pipeline
- Updated LLM instructions in `instructionsForTimeline()` to dynamically use provider displayName
- Modified prefix policies, fast-path acknowledgements, and fallback summaries
- Marked `Provider.displayName` as `nonisolated` for cross-actor access
- Now correctly generates summaries like "Codex CLI proposes..." for Codex entries

**Files Modified:**
- `FoundationLLM.swift` - Added provider parameter to all summarization methods
- `ConversationMonitor.swift` - Pass provider from activeSession
- `TimelineCacheMissGenerator.swift` - Pass provider to LLM calls
- `TimelineModels.swift` - Made displayName nonisolated

#### System Message Provider Name
**Status:** Completed (2025-10-10)
**Priority:** Low (polish)

~~System messages like "Switched to a new conversation" should include the provider name: "Switched to a new Claude Code conversation" or "Switched to a new Codex conversation" for clarity.~~

**Solution Implemented:**
Updated `emitProviderSwitchEntry()` in `ConversationMonitor.swift` to include provider displayName in system messages. Now shows "Switched to a new Codex CLI conversation" etc.

#### Timeline Entry Tense Inconsistency
**Status:** Completed (2025-10-10)
**Priority:** Medium

~~Timeline entries are generated immediately when messages arrive, using present tense ("Claude proposes...", "Claude implements..."). This looks odd because they're historical log entries that should use past tense ("Claude proposed...", "Claude implemented...").~~

**Solution Implemented:**
Timeline cache now stores both present and past forms of each summary, generated by the LLM. Entries use `selectedForm` to toggle between tenses:
- Present continuous for active work: "Claude is implementing..."
- Past simple for completed work: "Claude implemented..."

The `flipTenseToPast()` method can convert entries to past tense without re-calling the LLM by simply toggling the `selectedForm` field. This enables natural progression from active → completed state.

**Implementation:**
- Dual-form generation in `summarizeTimelineWithForms()`
- Cache storage in `CachedTimelineEntry` with `presentForm` and `pastForm`
- Tense selection via `selectedForm` enum (`.presentContinuous` or `.pastSimple`)
- Fallback regex transformation for backward compatibility

### Performance

#### Viewport-Aware LLM Priority Queue
**Status:** Backlog
**Priority:** High (UX responsiveness)
**Category:** Performance / Intelligence

Implement intelligent LLM summarization queue that prioritizes entries visible to the user or likely to be viewed next, rather than processing entries in chronological order.

**The Problem:**
Current implementation processes timeline entries in order of arrival, regardless of what the user is actually viewing. This creates poor UX when:
- User is scrolling through older entries while new ones arrive at bottom
- User is viewing transcript inventory with many unprocessed items
- LLM is busy summarizing off-screen entries while visible ones remain blank

**The Solution:**
Viewport-aware priority queue that dynamically reorders LLM work based on:
1. What's currently visible in the UI
2. Where the user is likely to scroll next
3. Which window has user focus (main timeline vs inventory)

**Priority Rules (in order):**

**P0 - Currently Visible Entries**
- Highest priority: Entries currently in viewport
- Check both main timeline and transcript inventory views
- Immediately process any visible entries needing summaries
- Re-prioritize on scroll events

**P1 - New Arrivals (if user at bottom)**
- If user is scrolled to bottom of timeline (within 100px)
- AND new entries are arriving in real-time
- THEN prioritize summarizing those new entries
- Rationale: User is watching conversation happen live

**P2 - Active Window Context**
- If transcript inventory window is focused and visible
- AND inventory has unprocessed/unsummarized transcripts
- THEN prioritize generating metadata for those transcripts
- Show count: "3 transcripts need summaries"
- Process visible inventory items before off-screen timeline entries

**P3 - Predicted Scroll Direction**
- When all visible items are processed
- Predict next scroll direction based on user behavior:
  - **At bottom**: Prioritize entries above viewport (upward scroll likely)
  - **At top**: Prioritize entries below viewport (downward scroll likely)
  - **Middle**: Prioritize entries in both directions, closer first
- Use proximity-based scoring: closer = higher priority

**P4 - Background Fill**
- When no user interaction for 2+ seconds
- Process remaining entries in chronological order
- Low-priority background work to fill cache

**Implementation Architecture:**

```swift
// Priority Queue Entry
struct PrioritizedEntry {
  let entryId: String
  let priority: Priority
  let distance: Int  // px from viewport center, negative = above
  let timestamp: Date

  enum Priority: Int {
    case visible = 0       // Currently in viewport
    case newArrival = 1    // New entry, user at bottom
    case activeWindow = 2  // In focused window (inventory)
    case predicted = 3     // Likely to scroll here
    case background = 4    // Everything else
  }
}

// Viewport Tracker
@MainActor
@Observable
final class ViewportTracker {
  // Timeline viewport
  var timelineViewportRange: Range<Int>?  // Entry indices
  var timelineScrollPosition: ScrollPosition  // top/middle/bottom
  var timelineVisibleEntryIds: Set<String>

  // Inventory viewport
  var inventoryViewportRange: Range<Int>?
  var inventoryVisibleTranscriptIds: Set<String>

  // Focus tracking
  var activeWindow: WindowType  // .timeline or .inventory

  // Scroll prediction
  var lastScrollDirection: ScrollDirection?  // .up or .down
  var scrollVelocity: Double  // px/s

  func updateViewport(visibleRange: Range<Int>, scrollOffset: CGFloat) {
    // Track what's visible
    // Detect scroll direction
    // Update predictions
  }
}

// Priority Queue Manager
actor LLMPriorityQueue {
  private var queue: [PrioritizedEntry] = []
  private var viewportTracker: ViewportTracker

  func enqueue(_ entryId: String) async {
    let priority = await calculatePriority(entryId)
    let entry = PrioritizedEntry(entryId: entryId, priority: priority, ...)
    queue.append(entry)
    queue.sort { $0.priority.rawValue < $1.priority.rawValue }
  }

  func dequeue() async -> String? {
    // Return highest priority entry
    return queue.first?.entryId
  }

  func reprioritize() async {
    // Re-calculate priorities based on new viewport state
    for i in queue.indices {
      queue[i].priority = await calculatePriority(queue[i].entryId)
    }
    queue.sort { $0.priority.rawValue < $1.priority.rawValue }
  }

  private func calculatePriority(_ entryId: String) async -> Priority {
    // Check if visible in current viewport
    if viewportTracker.timelineVisibleEntryIds.contains(entryId) {
      return .visible
    }

    // Check if new arrival and user at bottom
    if viewportTracker.timelineScrollPosition == .bottom && isRecentEntry(entryId) {
      return .newArrival
    }

    // Check if in active window (inventory)
    if viewportTracker.activeWindow == .inventory && isInInventoryViewport(entryId) {
      return .activeWindow
    }

    // Predict scroll direction and prioritize accordingly
    let distance = calculateDistanceFromViewport(entryId)
    if abs(distance) < 500 {  // Within 500px of viewport
      return .predicted
    }

    return .background
  }
}

// Integration with TimelineCacheMissGenerator
actor TimelineCacheMissGenerator {
  private var priorityQueue: LLMPriorityQueue

  func processMisses() async {
    while let entryId = await priorityQueue.dequeue() {
      // Generate summary for highest priority entry
      await generateSummary(for: entryId)
    }
  }

  func onViewportChange() async {
    // Reprioritize queue when viewport changes
    await priorityQueue.reprioritize()
  }
}
```

**UI Integration:**

**ConversationTimelineView.swift:**
```swift
ScrollViewReader { proxy in
  List(entries) { entry in
    TimelineEntryRow(entry)
      .onAppear {
        viewportTracker.markVisible(entry.id)
        Task {
          await generator.onViewportChange()
        }
      }
      .onDisappear {
        viewportTracker.markInvisible(entry.id)
      }
  }
  .onScrollGeometryChange(for: CGRect.self) { geometry in
    // Track viewport bounds
    viewportTracker.updateViewport(
      visibleRange: calculateVisibleRange(geometry),
      scrollOffset: geometry.contentOffset.y
    )

    Task {
      await generator.onViewportChange()
    }
  }
}
```

**TranscriptInventoryView.swift:**
```swift
.onAppear {
  viewportTracker.activeWindow = .inventory
  Task {
    await generator.onViewportChange()
  }
}
.onChange(of: selectedTranscriptId) {
  // User selected transcript, prioritize its metadata
  Task {
    await generator.prioritizeTranscript(selectedTranscriptId)
  }
}
```

**Edge Cases:**

1. **Rapid Scrolling**: Debounce viewport updates (100ms) to avoid thrashing
2. **Multiple Windows**: Track focus separately, active window gets priority
3. **Very Long Timeline**: Limit viewport tracking to ±1000 entries from current position
4. **Slow LLM**: If queue depth > 50, show warning "Many summaries pending..."
5. **User Idle**: After 2s of no interaction, fall back to chronological processing

**Performance Benefits:**

- **Before**: User scrolls to old entry, waits 10s for summary while LLM processes off-screen entries
- **After**: Visible entry summarized within 1-2s, off-screen entries wait
- **Perceived Performance**: 5-10x improvement in responsiveness
- **User Experience**: Timeline feels instant regardless of queue depth

**Monitoring:**

Add metrics to track effectiveness:
- Average time-to-summary for visible entries
- Queue reprioritization frequency
- Hit rate for predicted scroll direction
- User satisfaction proxy: scroll speed (slower = reading, faster = scanning)

**Phase 1: Basic Viewport Tracking** (~2 days)
- Implement ViewportTracker
- Track visible entries in timeline
- Basic priority queue (visible vs background)

**Phase 2: Scroll Prediction** (~2 days)
- Detect scroll direction and velocity
- Prioritize entries near viewport
- Handle rapid scrolling

**Phase 3: Multi-Window Awareness** (~2 days)
- Track inventory window focus
- Prioritize transcript metadata generation
- Cross-window priority coordination

**Phase 4: Polish & Optimization** (~1 day)
- Debouncing and performance tuning
- Metrics and monitoring
- User testing and refinement

**Total Effort:** ~1-1.5 weeks

**User Benefits:**
- ✅ Instant summaries for what you're actually looking at
- ✅ No waiting for off-screen entries to finish processing
- ✅ Smarter LLM resource usage
- ✅ Transcript inventory feels responsive
- ✅ Better UX during active conversation monitoring

**Related Work:**
- See `build/notes/technical-reference/timeline-cache-llm-architecture.md` for current LLM integration
- See `build/notes/technical-reference/conversation-monitor-state-architecture.md` for state management

#### Timeline Summary Caching
**Status:** Completed (2025-10-10)
**Priority:** High
**Branch:** feature/timeline-cache

~~Timeline entries were re-generated from scratch on every app launch by re-parsing the entire JSONL transcript and calling the LLM for each message. This was slow and expensive.~~

**Implementation Completed:**
Persistent cache system with content-based invalidation and dual-form tense storage.

**Architecture:**
- **SQL-based storage**: Timeline cache in SQLite database via GRDB
- **LLM generation**: `TimelineCacheMissGenerator` with FoundationLLM integration
- **Database location**: `~/Library/Application Support/Contextify/transcripts.db`
- **Smart invalidation** - Content hash + context window hash + generator signature
- **Per-entry caching** - Cached summaries linked to timeline entries via foreign key

**Cache Entry Structure:**
```swift
struct CachedTimelineEntry {
  let contentHash: String           // SHA256 of message content
  let windowHash: String             // SHA256 of context UUIDs
  let generatorSignature: String     // Model + version + prompt
  let disposition: Disposition       // Entry classification
  let presentForm: String            // "Claude is implementing..."
  let pastForm: String               // "Claude implemented..."
  var selectedForm: Tense            // Which to display
  let verbLemma: String?             // For future conjugation
  let generatedAt: Date
  var userEdited: Bool               // Manual override flag
  var userText: String?              // User's edited text
}
```

**Key Features:**
- ✅ Cache HIT/MISS logging with hit rate tracking
- ✅ Debounced persistence (2s) to reduce disk writes
- ✅ Synchronous flush on app termination
- ✅ Content-aware invalidation (message + context changes)
- ✅ Dual-form tense storage (no regex mutations)
- ✅ User edit support for manual corrections
- ✅ Session epoch tracking prevents cross-session contamination

**Performance Impact:**
- **Before:** ~150ms per message × N messages = slow startup
- **After:** Cache HIT = instant, only new messages call LLM
- **Typical startup:** 1-2 LLM calls instead of 20-50

### Features

#### Cross-CLI Transcript Converter
**Status:** Prototype
**Priority:** Medium-High
**Category:** Interoperability / Developer Workflow

Convert transcripts between Claude Code and Codex CLI formats to enable conversation continuity across tools. Pick up a conversation where the other CLI left off.

**The Problem:**
- Claude Code and Codex CLI use different JSONL transcript formats
- Cannot resume a Claude Code conversation in Codex CLI, or vice versa
- Switching tools means losing conversation context and history
- Forces developers to commit to one tool for entire project lifecycle

**The Solution:**
Bidirectional transcript converter that translates between formats while preserving:
- Message content and timestamps
- User/assistant roles and threading
- Session context (git branch, cwd, etc.)
- Tool call sequences (best-effort mapping)

**Format Differences:**

| Aspect | Claude Code | Codex CLI |
|--------|-------------|-----------|
| **Message structure** | `{uuid, type, message: {role, content: string}}` | `{timestamp, type: "response_item", payload: {role, content: [{type, text}]}}` |
| **Content format** | String or array of `{type, text}` blocks | Always array of `{type, text}` blocks |
| **Tool calls** | Separate assistant messages with `tool_use` blocks | `function_call` + `function_call_output` pairs with `call_id` |
| **Session metadata** | Per-message `sessionId`, `cwd`, `gitBranch` | Single `session_meta` record at start |
| **Threading** | `uuid` + `parentUuid` chains | Temporal ordering only |
| **IDs** | UUIDs throughout | Generated deterministic IDs for messages |

**Conversion Challenges:**

1. **Tool Call Mapping:**
   - Claude Code: Multiple assistant messages, each with one tool_use block
   - Codex: Paired `function_call` / `function_call_output` records
   - Solution: Aggregate consecutive tool_use messages → function_call pairs

2. **Content Structure:**
   - Claude Code accepts string or array
   - Codex requires array of `{type: "input_text", text}` objects
   - Solution: Normalize to array format for Codex, detect and convert for Claude Code

3. **Session Context:**
   - Claude Code: Per-message git/cwd fields
   - Codex: Session-level metadata in first record
   - Solution: Extract from first Claude Code message → `session_meta` for Codex

4. **Threading/Linking:**
   - Claude Code: Explicit parent/child UUIDs
   - Codex: No threading, just temporal order
   - Solution: Preserve temporal order, drop threading for Codex; regenerate threading for Claude Code

5. **File History Snapshots:**
   - Claude Code: `file-history-snapshot` records with backup metadata
   - Codex: No equivalent
   - Solution: Skip snapshots when converting to Codex (informational only)

**Implementation Plan:**

**Phase 1: Core Converter (Prototype)** (~1-2 days)
- Python CLI tool: `scripts/convert_transcript.py`
- Basic structure conversion without tool call mapping
- User/assistant message conversion with content normalization
- Session metadata extraction/generation
- Usage: `./scripts/convert_transcript.py --from claude-code --to codex input.jsonl output.jsonl`

**Phase 2: Tool Call Handling** (~1 day)
- Map Claude Code tool_use → Codex function_call pairs
- Map Codex function_call → Claude Code tool_use messages
- Preserve tool arguments and results
- Handle tool call aggregation (multiple tools in one turn)

**Phase 3: Validation & Testing** (~1 day)
- Test suite with real transcript samples
- Validate converted transcripts load in target CLI
- Round-trip testing (Claude → Codex → Claude)
- Edge case handling (malformed records, missing fields)

**Phase 4: UI Integration** (Future)
- Add converter to Contextify UI
- "Export for Codex CLI" / "Export for Claude Code" actions
- Preview conversion before export
- Direct import into target CLI's transcript directory

**Prototype CLI Tool:**

```python
#!/usr/bin/env python3
"""
Transcript format converter: Claude Code ↔ Codex CLI

Usage:
  convert_transcript.py --from claude-code --to codex input.jsonl output.jsonl
  convert_transcript.py --from codex --to claude-code input.jsonl output.jsonl
"""

import json
import argparse
import hashlib
from datetime import datetime
from uuid import uuid4

def claude_to_codex(input_path, output_path):
    """Convert Claude Code JSONL to Codex CLI format"""
    session_id = str(uuid4())
    first_message = True

    with open(input_path) as infile, open(output_path, 'w') as outfile:
        for line in infile:
            record = json.loads(line)

            # Skip non-message records
            if record.get('type') not in ['user', 'assistant']:
                continue

            # Skip meta/sidechain
            if record.get('isMeta') or record.get('isSidechain'):
                continue

            # Generate session_meta from first message
            if first_message:
                session_meta = {
                    "timestamp": record['timestamp'],
                    "type": "session_meta",
                    "payload": {
                        "id": session_id,
                        "timestamp": record['timestamp'],
                        "cwd": record.get('cwd', '/'),
                        "originator": "claude_code_converter",
                        "cli_version": "converted-1.0.0",
                        "instructions": "Converted from Claude Code transcript",
                        "source": "conversion",
                        "git": {
                            "commit_hash": record.get('gitCommit', ''),
                            "branch": record.get('gitBranch', 'main'),
                            "repository_url": ""
                        }
                    }
                }
                outfile.write(json.dumps(session_meta) + '\n')
                first_message = False

            # Convert message
            message = record.get('message', {})
            content = message.get('content', '')

            # Normalize content to array format
            if isinstance(content, str):
                content_array = [{"type": "input_text", "text": content}]
            else:
                # Already array, normalize type field
                content_array = [
                    {"type": "input_text", "text": block.get('text', '')}
                    for block in content
                    if block.get('text')
                ]

            codex_message = {
                "timestamp": record['timestamp'],
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": record['type'],
                    "content": content_array
                }
            }

            outfile.write(json.dumps(codex_message) + '\n')

def codex_to_claude(input_path, output_path):
    """Convert Codex CLI JSONL to Claude Code format"""
    session_id = None
    git_context = {}

    with open(input_path) as infile, open(output_path, 'w') as outfile:
        for line_num, line in enumerate(infile):
            record = json.loads(line)

            # Extract session metadata
            if record.get('type') == 'session_meta':
                session_id = record['payload']['id']
                git_context = {
                    'cwd': record['payload'].get('cwd'),
                    'gitBranch': record['payload'].get('git', {}).get('branch'),
                    'gitCommit': record['payload'].get('git', {}).get('commit_hash')
                }
                continue

            # Convert messages only
            if record.get('type') != 'response_item':
                continue

            payload = record.get('payload', {})
            if payload.get('type') != 'message':
                continue

            # Extract content from array format
            content_blocks = payload.get('content', [])
            content = '\n'.join(
                block.get('text', '')
                for block in content_blocks
                if block.get('text')
            )

            # Generate UUID
            message_uuid = str(uuid4())

            claude_message = {
                "uuid": message_uuid,
                "type": payload['role'],
                "timestamp": record['timestamp'],
                "message": {
                    "role": payload['role'],
                    "content": content
                },
                "sessionId": session_id or 'converted',
                "parentUuid": None,  # No threading in Codex
                **git_context
            }

            outfile.write(json.dumps(claude_message) + '\n')

def main():
    parser = argparse.ArgumentParser(description='Convert between Claude Code and Codex CLI transcript formats')
    parser.add_argument('--from', dest='from_format', required=True, choices=['claude-code', 'codex'])
    parser.add_argument('--to', dest='to_format', required=True, choices=['claude-code', 'codex'])
    parser.add_argument('input', help='Input JSONL file')
    parser.add_argument('output', help='Output JSONL file')

    args = parser.parse_args()

    if args.from_format == 'claude-code' and args.to_format == 'codex':
        claude_to_codex(args.input, args.output)
        print(f"✓ Converted Claude Code → Codex CLI: {args.output}")
    elif args.from_format == 'codex' and args.to_format == 'claude-code':
        codex_to_claude(args.input, args.output)
        print(f"✓ Converted Codex CLI → Claude Code: {args.output}")
    else:
        print("Error: Same format for input and output")
        return 1

if __name__ == '__main__':
    main()
```

**Usage Examples:**

```bash
# Claude Code → Codex CLI
# IMPORTANT: Codex expects sessions in ~/.codex/sessions/YYYY/MM/DD/
./scripts/convert_transcript.py \
  --from claude-code \
  --to codex \
  ~/.claude/projects/-Users-rob-code-project/session-uuid.jsonl \
  ~/.codex/sessions/$(date +%Y/%m/%d)/converted-$(date +%Y-%m-%dT%H-%M-%S)-<uuid>.jsonl

# Codex CLI → Claude Code
./scripts/convert_transcript.py \
  --from codex \
  --to claude-code \
  ~/.codex/sessions/2025/10/19/session-<uuid>.jsonl \
  ~/.claude/projects/-Users-rob-code-project/imported-session.jsonl
```

**Validation Strategy:**

1. **Parse Test**: Load converted file in target CLI and verify it doesn't error
2. **Content Check**: Ensure all user/assistant messages are preserved
3. **Timestamp Order**: Verify chronological ordering is maintained
4. **Round Trip**: Convert A→B→A and compare to original (lossy for metadata)

**Known Limitations:**

1. **Tool calls**: Basic conversion only in Phase 1, no aggregation
2. **Threading**: Lost when converting to Codex, regenerated (not original) for Claude Code
3. **File snapshots**: Dropped when converting to Codex
4. **Encrypted reasoning**: Codex's encrypted content is opaque, dropped in conversion
5. **Event logs**: Codex's `event_msg` records (token counts, etc.) dropped

**Future Enhancements:**

- **Bidirectional tool mapping**: Full tool_use ↔ function_call conversion
- **Smart threading**: Infer threading for Codex→Claude based on temporal proximity
- **Metadata preservation**: Store original format metadata in comments
- **UI wizard**: Guided conversion with preview and validation
- **Auto-import**: Detect and offer to convert when opening incompatible transcript

**Related Documentation:**
- Format comparison: `build/notes/archive/technical-briefing-local-history-claude-code-codex.md`
- Current parsers: `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

**Prior Art:**
Multiple tools exist for converting Claude Code transcripts to readable formats (HTML, Markdown, TUI), but **none for cross-CLI conversion**. This is a novel approach to enable true interoperability.

**Success Criteria:**
- Can load a Claude Code session in Codex CLI and continue conversation
- Can load a Codex session in Claude Code and continue conversation
- Round-trip conversion preserves >95% of essential content
- Conversion completes in <1s for typical session (~500 messages)

#### Agent Instructions Management View
**Status:** Backlog
**Priority:** Medium
**Related:** AGENTS.md / CLAUDE.md consolidation

Build an auxiliary view to help users maintain Agent Rules v1.0 compliance and avoid documentation drift between AGENTS.md and CLAUDE.md files.

**Functionality:**
1. **File Discovery**: Scan project directory and detect all `AGENTS.md` and `CLAUDE.md` files
2. **Symlink Detection**: Check if CLAUDE.md is a symlink to AGENTS.md (recommended setup)
3. **Diff Display**: Show side-by-side comparison if files exist as separate documents
4. **Warning System**: Visual indicator (⚠️) when files have diverged or are not symlinked
5. **One-Click Actions**:
   - "Create Symlink" - Convert CLAUDE.md to symlink → AGENTS.md
   - "Merge Files" - Interactive merge with conflict resolution
   - "View Diff" - Detailed line-by-line comparison

**Integration Points:**
- **Transcript Discovery Warning**: When ConversationMonitor discovers the first Codex session focused on the same project directory, if AGENTS.md and CLAUDE.md are not set up as symlinks, show a banner warning:
  ```
  ⚠️ Multiple agent instruction files detected
  AGENTS.md and CLAUDE.md are not linked. View comparison →
  ```
- Menu item: **Tools → Agent Instructions Setup**
- Status bar indicator when drift is detected

**UI Design:**
```
┌─────────────────────────────────────────────┐
│ Agent Instructions Setup                    │
├─────────────────────────────────────────────┤
│                                             │
│ Status: ⚠️ Files are separate              │
│                                             │
│ AGENTS.md          vs          CLAUDE.md   │
│ ┌──────────────┐              ┌──────────┐ │
│ │ 175 lines    │              │ 125 lines│ │
│ │ Modified: 2h │              │ Modified:│ │
│ │              │              │  1 week  │ │
│ └──────────────┘              └──────────┘ │
│                                             │
│ [Create Symlink]  [Merge Files]  [View Diff]│
└─────────────────────────────────────────────┘
```

**Technical Notes:**
- Use `FileManager` to detect symlinks (`FileManager.default.destinationOfSymbolicLink(atPath:)`)
- Leverage SwiftUI `TextEditor` for diff display
- Store user preference for "don't warn again" in UserDefaults
- Follow Agent Rules v1.0 spec (AGENTS.md as single source of truth)

#### Configurable Database Location with Cloud Sync & Encryption
**Status:** Backlog
**Priority:** Medium-High
**Related:** Database architecture, cloud storage, security

Allow users to configure where the SQLite database is stored, with support for cloud sync providers (Dropbox, iCloud Drive) and optional encryption for sensitive transcript data.

**Current Behavior:**
- Database location: `~/Library/Application Support/Contextify/transcripts.db` (fixed)
- No encryption (plain SQLite)
- No cloud sync support

**Proposed Functionality:**

1. **Custom Database Location**
   - Settings UI: "Database Location" preference pane
   - Options:
     - Default: `~/Library/Application Support/Contextify/` (current)
     - Dropbox: `~/Dropbox/Apps/Contextify/`
     - iCloud Drive: `~/Library/Mobile Documents/com~apple~CloudDocs/Contextify/`
     - Custom: User-selected folder (via NSOpenPanel)
   - Validation: Check write permissions, available space (>100MB)
   - Migration: Copy existing database to new location with progress indicator

2. **Cloud Sync Integration**
   - **Dropbox**: Direct folder path integration
     - Detect Dropbox folder: `~/.dropbox/info.json` or standard `~/Dropbox`
     - Sync status indicator (syncing/synced/error)
     - Conflict resolution: Last-write-wins with backup
   - **iCloud Drive**: Native CloudKit integration
     - Use `NSFileCoordinator` for iCloud document handling
     - Automatic conflict resolution via iOS/macOS file coordination
     - Status: "Uploading", "Downloading", "Up to Date"
   - **Custom Location**: Basic file monitoring, no special sync handling

3. **Database Encryption**
   - **SQLCipher integration**: Open-source SQLite encryption extension
   - **Options**:
     - None (default, plain SQLite)
     - Encrypted (AES-256 with user-provided passphrase)
   - **Passphrase Management**:
     - Store in macOS Keychain (secure, survives app reinstall)
     - Prompt on first launch if encrypted database detected
     - "Change Passphrase" option in settings
   - **Migration Path**:
     - Encrypt existing database: `ATTACH DATABASE 'encrypted.db' AS encrypted KEY 'passphrase'; SELECT sqlcipher_export('encrypted');`
     - Decrypt database: Reverse process
   - **Performance**: SQLCipher adds ~5-15% overhead (acceptable for transcript data)

**Technical Architecture:**

```swift
// DatabaseManager.swift enhancement
struct DatabaseConfig {
  enum Location {
    case appSupport  // Default
    case dropbox
    case iCloud
    case custom(URL)
  }

  enum Encryption {
    case none
    case sqlcipher(passphrase: String)
  }

  var location: Location
  var encryption: Encryption
}

class DatabaseManager {
  static let shared = DatabaseManager()

  private var config: DatabaseConfig

  func reconfigureDatabase(newConfig: DatabaseConfig) throws {
    // 1. Close current connection
    // 2. Migrate database to new location (if changed)
    // 3. Apply/remove encryption (if changed)
    // 4. Reopen with new config
    // 5. Notify observers (reload UI)
  }

  private func openWithEncryption(path: String, passphrase: String?) throws -> DatabasePool {
    if let pass = passphrase {
      // SQLCipher: PRAGMA key = 'passphrase';
      let config = Configuration()
      config.prepareDatabase { db in
        try db.execute(sql: "PRAGMA key = '\(pass)'")
      }
      return try DatabasePool(path: path, configuration: config)
    } else {
      return try DatabasePool(path: path)
    }
  }
}
```

**UI Design:**
```
┌───────────────────────────────────────────┐
│ Database Settings                         │
├───────────────────────────────────────────┤
│                                           │
│ Location:                                 │
│   ( ) Application Support (Default)       │
│   ( ) Dropbox                             │
│   (•) iCloud Drive                        │
│   ( ) Custom...                           │
│                                           │
│ Current: ~/Library/Mobile Documents/...  │
│ Status: ☁️ Synced (2 minutes ago)         │
│                                           │
│ [Change Location...]                      │
│                                           │
│ ─────────────────────────────────────────│
│                                           │
│ Encryption:                               │
│   [✓] Encrypt database                    │
│                                           │
│ Passphrase: **************                │
│                                           │
│ [Change Passphrase...]                    │
│                                           │
│ ⚠️ Warning: Encryption adds ~10% overhead│
│ and requires passphrase on every launch. │
│                                           │
└───────────────────────────────────────────┘
```

**Implementation Phases:**

**Phase 1: Custom Location (No Encryption)**
- Add location selector to preferences
- Implement database migration logic
- Handle file permissions and validation
- Update DatabaseManager to support configurable paths
- Effort: ~2-3 days

**Phase 2: Cloud Sync Support**
- Dropbox folder detection and monitoring
- iCloud Drive integration with NSFileCoordinator
- Sync status UI indicators
- Conflict resolution strategies
- Effort: ~3-5 days

**Phase 3: Encryption**
- Integrate SQLCipher library (SPM)
- Implement passphrase management (Keychain)
- Add encrypt/decrypt migration workflows
- Performance testing and optimization
- Effort: ~3-4 days

**Security Considerations:**
- **Passphrase Strength**: Require minimum 12 characters, suggest passphrase generator
- **Keychain Storage**: Use `kSecAttrAccessibleWhenUnlocked` (balance security/UX)
- **Backup Warning**: Encrypted databases cannot be recovered without passphrase
- **Cloud Sync + Encryption**: Warn users about syncing encrypted data (safe, but passphrase must match on all devices)

**Edge Cases:**
- **Dropbox/iCloud not installed**: Detect and disable option, show setup instructions
- **Migration failure**: Keep original database intact, rollback on error
- **Sync conflicts**: Last-write-wins with `.conflict` backup file
- **Encryption password forgotten**: No recovery (data loss), require explicit acknowledgement

**Cloud Sync + WAL Mode:**
- WAL mode creates `*-wal` and `*-shm` files that some cloud providers sync poorly
- **Mitigation:** Periodic WAL checkpointing (TRUNCATE) and reduced writer concurrency
- See `build/notes/technical-reference/sql-backend-architecture.md` for details

**Related Work:**
- See `build/notes/technical-reference/sql-backend-architecture.md` for current database design
- SQLCipher documentation: https://www.zetetic.net/sqlcipher/

#### LLM Processing Status Bar

**Status:** Backlog
**Priority:** Medium
**Related:** Timeline cache, Apple Intelligence integration, user feedback

Add a status bar to the main window that shows real-time LLM processing status and Apple Intelligence availability.

**Full specification:** See `build/notes/feature-specs/status-bar/spec.md`

**Summary:**
- Shows LLM queue depth and processing status in window footer
- Displays Apple Intelligence availability (green/gray/red indicator)
- Three implementation phases: basic queue display, AI indicator, polish
- Estimated 2-3 days total implementation time

#### Project Switcher Navigation Bar

**Status:** Completed (2025-10-27)
**Priority:** High
**Related:** Multi-project support, user experience, transcript monitoring

Add a navigation bar above the main window that displays all discovered projects with active transcripts and allows quick switching between them with unread indicators.

**Full specification:** See `build/notes/feature-specs/project-switcher/spec.md`

**Implemented:**
- Horizontal navigation bar showing all projects with transcripts
- Unread badges show new activity in non-active projects
- Click to switch between projects, timeline updates immediately
- Keyboard shortcuts: Cmd+Shift+[ / ] to cycle through projects
- Auto opt-in for multi-project mode
- DB-derived unread counts (crash-safe, no in-memory state)
- Status bar tracks LLM work per project (old generator cancelled on switch)

**Key Components:**
- `ProjectActivityMonitor`: Global project discovery (Phase 1)
- `project_visits` database table: Track visits and unread counts (v8 migration)
- `ProjectSwitcherState`: Observable state for UI binding
- `ProjectSwitcherView`: SwiftUI navigation bar component with keyboard shortcuts
- `TimelineCacheMissGenerator.shutdown()`: Cancels old project's queue on switch

**Future Enhancement - Background Processing:**
Currently, switching projects cancels the old project's LLM queue and drops unprocessed cache misses. They're rediscovered from DB when you switch back. Consider implementing a global queue manager that continues processing all projects in background (active project gets priority, others process during idle). This would improve resource utilization and make all projects gradually summarized. Trade-off: battery usage vs UX. Implement as user preference with status bar showing "Active: X items, Background: Y items (Z projects)".

#### Conversation Log Enhancements

##### 1. Date Separator Between Messages
**Status:** Backlog
**Priority:** Medium (UX polish)

Add visual date separators when the timeline crosses into a new day, similar to macOS Messages app.

**Example:**
```
Claude proposes to implement caching
You requested Claude to proceed
─────── Tuesday, October 15 ───────
Claude implements the cache layer
You asked about performance
─────── Wednesday, October 16 ──────
Claude optimizes the query
```

**Implementation:**
- Check for date boundary between consecutive timeline entries
- Insert a visual separator with formatted date
- Use system date formatting (respects user's locale)
- Style: subtle divider with centered date text
- Consider: "Today", "Yesterday" for recent dates

**Files to modify:**
- `ConversationTimelineView.swift` - Add date separator logic
- Check timestamp difference between entries
- Insert Text/Divider view when date changes

##### 2. Reduce Assistant Entry Density
**Status:** Partially Complete (disposition filtering implemented)
**Priority:** Low (current filtering works well)

Basic disposition-based filtering is implemented in `ConversationMonitor.swift:630`. Currently suppresses `ack` and `wip` dispositions.

**Future enhancements (low priority):**
- User-configurable verbosity levels (see Timeline Verbosity Settings below)
- Time-based throttling for rapid assistant responses
- Adaptive filtering based on completion confidence scores

##### 2. Avoid Sequential Completed Entries
**Status:** Completed (2025-10-10)
**Priority:** Medium

~~The conversation log currently can show multiple sequential "completed" entries, which creates redundancy and clutters the timeline.~~

**Example of redundancy:**
```
✓ Claude marks the final todo as completed.
---
Perfect! The build succeeded with no errors. Let me mark the final todo as completed.

✓ Claude successfully converted the Transcript Inventory to an independent window...
---
## Implementation Complete!
I've successfully converted the Transcript Inventory from a modal sheet to an independent window...
```

**Proposed Solution:**
When processing timeline entries marked as "completed":
1. Check if the previous entry is also marked as "completed"
2. If so, merge or suppress the second completion entry
3. Consider consolidating the summaries or only showing the more detailed one
4. Possibly use a different indicator (e.g., "Progress: ..." vs "✓ Completed")

**Implementation considerations:**
- May need to distinguish between "task completed" vs "subtask completed"
- Could use confidence scoring on completion detection
- Should preserve important context even when merging

##### 2. Timeline Verbosity Settings
**Status:** Backlog
**Priority:** Medium

Add user-configurable verbosity control for timeline entries to balance detail vs clarity.

**Proposed UI:**
- Settings panel with a slider control
- 4 verbosity levels from minimal to verbose
- Real-time preview showing what gets filtered at each level
- Persisted preference in UserDefaults

**Verbosity Levels:**

| Level | Name | Suppressed Dispositions | Kept Dispositions | Est. Entries/Cycle |
|-------|------|------------------------|-------------------|-------------------|
| 0 | Minimal | ack, wip, analysis, proposal | completion, question, refusal | 1-2 |
| 1 | Balanced (Default) | ack, wip, analysis | completion, proposal, question, refusal | 3-5 |
| 2 | Detailed | ack, wip | completion, analysis, proposal, question, refusal | 6-8 |
| 3 | Verbose | (none) | (all) | 10-14 |

**Implementation:**
- Add `TimelineVerbosity` enum with levels 0-3
- Store preference in `MonitorConfig` or `HUDPreferences`
- Update `addAssistantTextEntry()` to check verbosity level
- Add settings UI in ConversationTimelineView menu or separate preferences window

**Current Implementation:**
Level 1 (Balanced) is hard-coded in `ConversationMonitor.swift:630`

##### 3. Task Duration Tracking
**Status:** Completed (2025-10-10)
**Priority:** Medium
**Depends on:** Enhancement #1 (completed entry detection)

Once we can reliably identify completed entries, show the elapsed time from the user's request to completion.

**Proposed UI:**
- Show duration next to completed entries (e.g., "✓ Completed in 2m 34s")
- Add small arrow icon (↑) next to completed entries
- Clicking arrow scrolls to and highlights the original request in the log
- Hovering shows timestamp of request and completion

**Implementation considerations:**
- Need to track correlation between user requests and completion events
- Store request UUID with each task
- Calculate duration from first relevant assistant message to completion marker
- Handle cases where tasks span multiple timeline entries

##### 4. Activity Log (Git Events Integration)
**Status:** Backlog
**Priority:** Medium
**Category:** New Feature

Expand the conversation log into a unified "activity" log that includes git events alongside AI conversation entries, creating a complete project activity timeline.

**Concept:**
Instead of just showing what Claude/Codex did, show the full context of project activity:
- AI conversation entries (current)
- Git commits (with message, author, files changed)
- Git branch switches
- Git merges/rebases
- Other version control events

**Proposed Features:**
1. **Unified Timeline**: Interleave git events with conversation entries in chronological order
2. **Event Filtering**: Toggle visibility of different event types
   - Show/hide: Commits, Branches, AI messages, Tool calls, etc.
   - Filter by author (user, Claude, Codex, other collaborators)
   - Filter by file/directory affected
3. **Git Event Display**:
   - Commit entry: "📝 Committed: [message]" with hash, author, timestamp
   - Branch switch: "🔀 Switched to branch: [name]"
   - Merge: "🔗 Merged [branch] into [branch]"
4. **Correlation**:
   - Link AI "completed" entries to the commits they generated
   - Show which conversation led to which code changes
   - Highlight when AI suggestions were committed vs modified

**Implementation Considerations:**
- Monitor `.git/` directory for changes (already doing this for branch detection)
- Parse `git log` for commit history
- Use `git reflog` for branch switches
- Add event type system: `.conversation`, `.commit`, `.branch`, `.merge`
- Extend filtering UI to support multiple event types
- Consider performance impact of git log parsing

**UI Mockup:**
```
Timeline (Filters: ✓ AI  ✓ Commits  ✓ Branches)
┌──────────────────────────────────────────┐
│ 2:34 PM  User: Fix the logging levels   │
│ 2:35 PM  ✓ Claude moved logs to debug   │
│ 2:36 PM  📝 feat: move routine logs...   │  ← Git commit
│          (3 files changed)               │
│ 2:40 PM  🔀 Switched to main             │  ← Branch change
│ 2:41 PM  🔗 Merged feature/logging       │  ← Git merge
└──────────────────────────────────────────┘
```

**Benefits:**
- Complete project context in one view
- Better understanding of what AI changes made it to main
- Easier to review and correlate work
- More useful for project retrospectives

#### Transcript Migration UI
**Status:** Backlog
**Priority:** Super Low (manual script works fine, edge case)
**Related:** `scripts/migrate-transcripts.sh`

When users move their project to a new directory (e.g., `~/code/contextify` → `~/code/projects/contextify`), Claude Code creates a new transcript directory. Old transcripts remain at the old location with outdated paths in content.

**Current Solution:**
Manual script at `scripts/migrate-transcripts.sh` that:
- Backs up old transcripts
- Copies to new location
- Rewrites all path references to new location

**Future Enhancement:**
Wrap the script in UI:
- Detect when project path has changed
- Offer to migrate old transcripts
- Show preview of what will be migrated
- One-click migration with progress indicator
- Automatic backup before migration

#### SQL Backend for Comprehensive Transcript Analysis
**Status:** Completed (2025-10-24)
**Priority:** High (Foundation for AI-driven project insights)
**Category:** Infrastructure / Intelligence

~~Store all transcript entries (user messages, assistant responses, tool calls, metadata) in a local SQLite database to enable deep project analysis and intelligent assistance features.~~

**Implementation Complete:**
- Database schema with GRDB (DatabaseManager, DatabaseSchema)
- TranscriptOrchestrator with full CRUD operations
- HooverEngine for streaming ingestion with checkpointing
- Timeline cache integration with content-based invalidation
- Repositories for type-safe queries (ProjectRepository, TranscriptRepository, EntryRepository, TimelineCacheRepository)
- Real-time file watching with TranscriptWatcher
- Documentation: `build/notes/technical-reference/sql-backend-architecture.md`

**Grand Theory:**
By analyzing the full project history stored in a relational database, Contextify can:
- Understand project direction and velocity
- Track progress toward stated goals
- Identify patterns (abandoned features, recurring issues)
- Help users remember where they left off
- Suggest next steps based on project trajectory
- Keep commits clean and atomic
- Detect documentation drift
- Correlate code changes with conversations

**Database Schema (preliminary):**
```sql
-- Core transcript entries
CREATE TABLE transcript_entries (
  id INTEGER PRIMARY KEY,
  uuid TEXT UNIQUE NOT NULL,           -- Original message UUID
  session_id TEXT NOT NULL,             -- Conversation session
  provider TEXT NOT NULL,               -- 'claude-code', 'codex', etc.
  kind TEXT NOT NULL,                   -- 'user', 'assistant', 'system'
  timestamp DATETIME NOT NULL,
  content TEXT NOT NULL,                -- Full message content
  summary TEXT,                         -- Timeline summary
  disposition TEXT,                     -- 'completion', 'question', etc.
  display_in_timeline BOOLEAN DEFAULT 1, -- Show in UI or not
  is_completion BOOLEAN DEFAULT 0,
  is_directive BOOLEAN DEFAULT 0,
  parent_uuid TEXT,                     -- For threading

  -- Analysis fields
  topics TEXT,                          -- JSON array of detected topics
  intent TEXT,                          -- Classified user intent
  entities TEXT,                        -- JSON: files, functions, features mentioned
  sentiment REAL,                       -- -1.0 to 1.0

  -- Correlation
  related_commit_hash TEXT,             -- Git commit this relates to
  request_id TEXT,                      -- Links completion to directive
  duration_seconds REAL,                -- Time from request to completion

  -- Metadata
  project_path TEXT NOT NULL,
  git_branch TEXT,
  git_commit TEXT,
  cwd TEXT,

  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Tool invocations
CREATE TABLE tool_calls (
  id INTEGER PRIMARY KEY,
  entry_id INTEGER REFERENCES transcript_entries(id),
  tool_name TEXT NOT NULL,
  arguments TEXT,                       -- JSON
  result TEXT,                          -- stdout/stderr
  exit_code INTEGER,
  duration_seconds REAL,
  timestamp DATETIME NOT NULL
);

-- Project insights (cached analysis)
CREATE TABLE project_insights (
  id INTEGER PRIMARY KEY,
  project_path TEXT NOT NULL,
  insight_type TEXT NOT NULL,           -- 'goal', 'pattern', 'blocker', 'drift'
  title TEXT NOT NULL,
  description TEXT,
  confidence REAL,                      -- 0.0 to 1.0
  supporting_entries TEXT,              -- JSON array of entry UUIDs
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  acknowledged BOOLEAN DEFAULT 0        -- User saw/dismissed
);

-- Git commits (for correlation)
CREATE TABLE git_commits (
  id INTEGER PRIMARY KEY,
  project_path TEXT NOT NULL,
  commit_hash TEXT NOT NULL,
  author TEXT NOT NULL,
  message TEXT NOT NULL,
  timestamp DATETIME NOT NULL,
  files_changed TEXT,                   -- JSON array
  conversation_uuid TEXT,               -- Linked to transcript entry

  UNIQUE(project_path, commit_hash)
);
```

**Key Features:**
1. **Full History Import**: Parse all existing transcripts and backfill database
2. **Real-time Ingestion**: Write to DB as entries arrive in ConversationMonitor
3. **Display Filtering**: `display_in_timeline` flag controls UI visibility without losing data
4. **Semantic Search**: Full-text search across all conversation history
5. **Pattern Detection**: Identify recurring themes, blockers, abandoned work
6. **Progress Tracking**: Correlate stated goals with actual progress
7. **Commit Attribution**: Link AI suggestions to actual git commits
8. **Context Resurrection**: "What was I working on last Tuesday?" queries

**Use Cases:**
- "Show me all entries about authentication this month"
- "What features did we start but never finish?"
- "Find all commits where Claude suggested changes"
- "What were my goals in the last standup message?"
- "Show timeline entries related to this file"

**Implementation Phases:**
1. **Phase 1**: Basic schema + import existing transcripts
2. **Phase 2**: Real-time ingestion in ConversationMonitor
3. **Phase 3**: Analysis engine (pattern detection, insights)
4. **Phase 4**: Smart suggestions UI ("You might want to...")

**Integration Points:**
- `ConversationMonitor`: Write all entries to DB
- New `AnalysisEngine` actor: Run queries and generate insights
- New `InsightsPanel`: Display suggestions and patterns
- Transcript Inventory: Enhanced search powered by SQL

#### Git Commit Rewriting Assistance
**Status:** Backlog
**Priority:** High (Complements SQL backend)
**Category:** Developer Workflow

Intelligent assistance for rewriting git history with atomic, well-structured commits using interactive squash, soft reset, and commit message generation.

**The Problem:**
During development with AI assistance, commits can become messy:
- Many small "fix typo" or "oops" commits
- Commits with unclear or AI-generated messages
- Multiple unrelated changes bundled together
- Features split across too many commits
- No logical atomic structure

**The Solution:**
Guided UI for rewriting branch history into clean, atomic commits with well-written messages.

**Core Features:**

1. **Branch Analysis**
   - Parse all commits since branch diverged from main
   - Show file changes, message quality, logical groupings
   - Identify related changes that should be combined
   - Detect commits that should be split (multiple concerns)

2. **Smart Grouping**
   - Use SQL transcript backend to correlate commits with conversations
   - Group commits by feature/task based on Claude/Codex directives
   - Suggest logical atomic commits: "These 8 commits are all about auth"
   - Show conversation context for each commit group

3. **Interactive Rewrite UI**
   ```
   ┌─────────────────────────────────────────────────────┐
   │ Rewrite History: feature/timeline-improvements      │
   ├─────────────────────────────────────────────────────┤
   │ 23 commits since main │ Suggested: 5 atomic commits│
   │                                                      │
   │ Suggested Grouping:                                 │
   │                                                      │
   │ ☐ Atomic Commit 1: "Timeline cache infrastructure"  │
   │   • 8e9a0b2 Add cache store                         │
   │   • f2b1c4a Add orchestrator                        │
   │   • 9d5e3f0 Add cache models                        │
   │   • 4a7c2b1 Wire up cache loading                   │
   │   Conversation: "Help me cache timeline entries"    │
   │   [Edit Message] [Split] [Reorder]                  │
   │                                                      │
   │ ☐ Atomic Commit 2: "Implement dual-form tense..."   │
   │   • 3b8f1d9 Add present/past forms                  │
   │   • 6e2a9c4 Update cache schema                     │
   │   Conversation: "Timeline should show past tense"   │
   │   [Edit Message] [Split] [Reorder]                  │
   │                                                      │
   │ [Preview Rewrite] [Execute] [Cancel]                │
   └─────────────────────────────────────────────────────┘
   ```

4. **Commit Message Generation**
   - Analyze combined changes and conversation context
   - Generate conventional commit messages (feat/fix/refactor)
   - Include relevant details from conversation
   - Show diff of what changed in each atomic commit
   - User edits and approves before applying

5. **Safe Execution**
   - Create backup branch automatically
   - Show exact git commands that will run
   - Allow preview before execution
   - Dry-run mode: show result without changing history
   - Rollback option if user doesn't like result

**Workflow Example:**
1. User: "Help me clean up this feature branch"
2. App analyzes 23 commits + SQL transcript entries
3. Identifies 4 logical features worked on
4. Suggests 5 atomic commits with messages
5. User reviews, edits messages, reorders groups
6. App creates backup branch: `feature/timeline-improvements-backup`
7. App executes: `git reset --soft main` + `git commit` × 5
8. Shows before/after comparison
9. User pushes cleaned history

**Technical Implementation:**
- Use SQL backend to correlate commits with transcript entries
- Parse `git log` output and diff stats
- Use LLM to generate commit messages from conversation context
- Execute git commands via `Process` (git reset, git commit)
- Integration with ConversationMonitor to link commits to directives

**Git Commands Used:**
```bash
# Backup
git branch feature-backup

# Get commits to rewrite
git log main..HEAD --oneline

# Reset to base
git reset --soft main

# Stage and commit atomically
git add <files for commit 1>
git commit -m "Generated message 1"
...

# Verify
git log --oneline
```

**Safety Features:**
- Always create backup branch first
- Require user confirmation before rewriting
- Show warning if branch is pushed to remote
- Detect if branch is merged or has downstream branches
- Provide undo command if user regrets rewrite

**Advanced Features (Future):**
- Detect co-authored commits (Claude + User)
- Preserve commit signatures where appropriate
- Handle merge commits intelligently
- Support rebasing onto updated main
- "Squash all tiny commits" quick action

---

## Completed
- ✅ Timeline monitoring with JSONL parsing
- ✅ LLM-based timeline summarization
- ✅ Multi-source transcript providers (Claude Code)
- ✅ Git repository and worktree detection
- ✅ Security-scoped bookmarks for sandboxed access
- ✅ Real-time file watching with DispatchSource
- ✅ Transcript inventory with worktree support (2025-10-10)
- ✅ Session switching from transcript inventory UI (2025-10-10)
- ✅ Provider-specific icons in timeline (2025-10-10)
- ✅ Timeline entry persistence across session switches (2025-10-10)
- ✅ Reveal-in-inventory action for system messages (2025-10-10)

---

## Transcript Metadata Storage & Analytics

**Status:** Proposed (2025-10-23)
**Priority:** P1 (enables session analytics and file tracking)
**Effort:** 2-3 weeks
**Related Docs:**
- `build/notes/technical-reference/claude-code-transcript-format.md`
- `build/notes/implementation-plans/transcript-metadata-storage.md`

### Problem Statement

Currently, Contextify only stores conversational messages from Claude Code transcripts, discarding valuable metadata:

1. **File-history-snapshot records (907 across 43 transcripts):**
   - Which files were modified during session
   - File versions and backup metadata
   - Average ~25 files tracked per snapshot

2. **Summary records (48):** Claude Code's internal session summaries

3. **System events (55):** Slash commands, API errors, compact mode boundaries

4. **Usage metadata (all assistant messages):** Token usage, cache stats, cost tracking

**Result:** "Empty" transcripts showing only metadata are hidden from inventory as useless, when they contain valuable file tracking and usage data.

### Proposed Solution

Store all Claude Code metadata types in normalized database tables:

1. **file_snapshots + tracked_files**: File modification tracking
2. **transcript_summaries**: Claude Code summaries for fallback titles
3. **system_events**: Command usage and error tracking
4. **assistant_usage**: Token/cost analytics

**Data Architecture:** Follow v6 principles - separate canonical (transcript_entries) from derived/metadata (new tables).

### Implementation Phases

#### Phase 1: Schema Migration (v7) - 1-2 days
**Tasks:**
- Create 5 new tables: file_snapshots, tracked_files, transcript_summaries, system_events, assistant_usage
- Add appropriate indexes for common queries
- Migration is backward compatible (no changes to existing tables)

**Deliverables:**
- `DatabaseSchema.swift` v7 migration
- Model structs for each table
- Repository methods for CRUD operations

#### Phase 2: Parser Implementation - 3-4 days
**Tasks:**
- Create `TranscriptMetadataParser` protocol
- Implement parsers for each metadata type
- Update `HooverEngine` to extract and store metadata
- Add batch commit logic for metadata records

**Deliverables:**
- `TranscriptMetadataParsers.swift`
- Updated `HooverEngine.swift` with metadata extraction
- Updated `TranscriptOrchestrator.swift` with metadata queries
- Unit tests for each parser

#### Phase 3: Backfill Tool - 1 day
**Tasks:**
- Create `scripts/backfill_metadata.py`
- Reingest existing transcripts to populate metadata
- Progress tracking and error handling

**Deliverables:**
- Backfill script with progress reporting
- Documentation for running backfill
- Make backfill optional/skippable

#### Phase 4: UI Features (Incremental) - 2-3 weeks

**4a. Session Details View (3-4 days)**
- Show files touched, token usage, cost estimate in inventory detail panel
- Display file count: "Files Modified: 12"
- Token summary: "Input: 125K tokens, Output: 8K tokens"
- Cost estimate: "Estimated Cost: $0.42"

**4b. File Timeline View (2-3 days)**
- Show file modification history across all sessions
- Timeline view: "ContentView.swift modified in 5 sessions"
- Link to sessions where file was changed
- Version history display

**4c. Command Analytics (1-2 days)**
- Show slash command usage statistics
- Top commands bar chart: "/build: 156 times, /run: 89 times"
- Command usage trends

**4d. Cost Dashboard (3-4 days)**
- Daily/weekly token usage graphs
- Cost projections and trends
- Per-project breakdown
- Cache effectiveness metrics (hit rate %)

### Database Schema

**file_snapshots:**
```sql
id, transcript_id, message_id, snapshot_timestamp, is_snapshot_update, created_at
```
Row estimate: ~2,100 (21 per transcript × 100 transcripts)

**tracked_files:**
```sql
id, snapshot_id, file_path, backup_filename, version, backup_time
```
Row estimate: ~52,500 (25 files × 21 snapshots × 100 transcripts)

**transcript_summaries:**
```sql
id, transcript_id, summary, leaf_uuid, cwd, created_at
```
Row estimate: ~100 (1 per transcript)

**system_events:**
```sql
id, transcript_id, timestamp, subtype, level, content, error, 
retry_attempt, max_retries, retry_in_ms, parent_uuid, created_at
```
Row estimate: ~100-200 (1-2 per transcript)

**assistant_usage:**
```sql
entry_id, request_id, model, input_tokens, output_tokens,
cache_creation_tokens, cache_read_tokens, service_tier,
ephemeral_5m_tokens, ephemeral_1h_tokens
```
Row estimate: ~25,500 (all assistant messages)

### Key Queries Enabled

1. **Session Details:**
```sql
SELECT COUNT(DISTINCT tf.file_path) as files_modified,
       SUM(au.input_tokens + au.output_tokens) as total_tokens
FROM transcripts t
LEFT JOIN file_snapshots fs ON fs.transcript_id = t.id
LEFT JOIN tracked_files tf ON tf.snapshot_id = fs.id
LEFT JOIN transcript_entries e ON e.transcript_id = t.id
LEFT JOIN assistant_usage au ON au.entry_id = e.id
WHERE t.id = ?;
```

2. **File Timeline:**
```sql
SELECT t.provider_session_id, tm.title, tf.version, tf.backup_time
FROM tracked_files tf
JOIN file_snapshots fs ON fs.id = tf.snapshot_id
JOIN transcripts t ON t.id = fs.transcript_id
LEFT JOIN transcript_metadata tm ON tm.transcript_id = t.id
WHERE tf.file_path = ?
ORDER BY tf.backup_time DESC;
```

3. **Cost Calculation:**
```sql
SELECT SUM(input_tokens) * 0.000003 + 
       SUM(output_tokens) * 0.000015 as estimated_cost_usd
FROM assistant_usage au
JOIN transcript_entries e ON e.id = au.entry_id
WHERE e.transcript_id = ?;
```

### Testing Strategy

**Unit Tests:**
- Parse each metadata type correctly
- Handle missing/malformed fields gracefully
- Usage metadata extraction from assistant messages

**Integration Tests:**
- Ingest transcript with file snapshots → verify DB
- Ingest transcript with summaries/events → verify DB
- Query performance: session details <10ms, file timeline <50ms

**Manual Tests:**
- Reingest existing transcript with metadata
- Verify session details view accuracy
- Check file timeline correctness

### Risks & Mitigations

**Risk 1: Performance impact**
- Parsing 5 record types may slow ingestion
- **Mitigation:** Benchmark, optimize batch commits, make metadata optional

**Risk 2: Storage growth**
- ~52K tracked_file rows + ~25K usage rows
- **Mitigation:** Indexes, retention policies
- **Estimate:** ~5-10 MB per 100 transcripts (acceptable)

**Risk 3: Backfill time**
- 43 transcripts × 1 min = 43+ minutes
- **Mitigation:** Background task, pauseable, or lazy backfill on view

### Success Metrics

1. **Data Completeness:**
   - 100% of file snapshots/summaries/usage stored
   - Zero foreign key violations

2. **Query Performance:**
   - Session details <10ms (p95)
   - File timeline <50ms (p95)
   - Daily usage aggregate <100ms (p95)

3. **User Value:**
   - Files modified count visible for all sessions
   - Token usage/cost visible in details
   - File timeline helps identify change history

### Future Enhancements (Phase 5+)

1. **File diff viewer:** Show actual diffs between versions
2. **Cost predictions:** "This project costs ~$X/week"
3. **Cache optimization suggestions:** "Cache hit rate dropped 20%"
4. **Command recommendations:** "You use /build often, add a hook?"
5. **Export capabilities:** Session reports (PDF/HTML), CSV export

### References

- **Complete spec:** `build/notes/technical-reference/claude-code-transcript-format.md`
- **Implementation plan:** `build/notes/implementation-plans/transcript-metadata-storage.md`
- **Current parser:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
- **Analysis:** 43 transcripts, 18,589 records, 5 record types documented

