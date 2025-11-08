# Contextify TODOs

**Last Updated:** 2025-11-08
**Current Database Schema:** v21

---

## P0: Critical Path to App Store

### 1. App Sandbox Implementation
**Status:** Reverted - Requires proper implementation before App Store submission
**Blocker:** Cannot ship to App Store without sandbox enabled
**Spec:** `build/notes/app-store/sandbox-implementation-plan.md`

**Why it was reverted:**
- ❌ Cannot access `~/.claude/projects` and `~/.codex/projects` for project discovery
- ❌ FSEvents monitoring blocked (cannot watch project directories)
- ❌ Projects window shows 0 projects
- ❌ Database location changes to sandboxed container

**Implementation Required:**
1. Security-scoped bookmarks for project directories
2. User-facing project selection UI (first launch)
3. Entitlements for read-only access to common locations
4. Migration path for existing users' databases
5. Testing with sandboxed builds before submission

**Files:**
- `Contextify/Contextify.entitlements` - Enable sandbox + required entitlements
- `Contextify/Contextify/FirstLaunchProjectSetup.swift` (NEW) - Project access UI
- `app/Sources/ContextifyCore/Database/DatabaseManager.swift` - Sandbox-aware DB location
- `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift` - Security-scoped access

**Related Commits:**
- `35ce380` - Removed iTerm2/terminal integration (entitlements cleanup)
- `b4b4762` - Enabled sandbox (reverted in `b1fe869`)

---

## P1: High Priority Bug Fixes & Polish

### 1. File Watching Cleanup - Stale Transcript Records
**Status:** Active issue - Production logs show 9+ occurrences
**Impact:** Failed watch attempts on every project switch, clutters logs

**Error Pattern:**
```
Initial ingestion failed for <id>: Code=2 "No such file or directory"
Failed to open file for watching
```

**Root Cause:** TranscriptWatcher trying to watch files that were deleted. Database has stale transcript records pointing to missing files.

**Proposed Fix:**
- Add file existence validation before starting watcher
- Skip/log missing files gracefully
- Add periodic cleanup job to prune orphaned transcripts
- UI indicator in Transcript Inventory for missing source files

**Files:**
- `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift` - Add existence check
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` - Cleanup logic
- `Contextify/Contextify/TranscriptInventoryView.swift` - Show missing file indicator

---

### 2. System Messages for Transcript Switches (QA Ready)
**Status:** Implementation complete - Ready for cherry-pick and testing
**Commit:** `ee33ca7` (was implemented then reverted in `b554563`)
**Effort:** 1-2 hours to cherry-pick, test, and merge

**What's Implemented:**
- ✅ `setEntries()` preserves system entries during SQL refresh
- ✅ `setActive()` calls `appendSystemEntry()` to show messages immediately
- ✅ Enhanced logging for debugging
- ✅ Graceful degradation if database persistence fails
- ✅ System messages visible in timeline UI and HTTP API
- ⚠️ System messages not yet restart-safe (lost on app relaunch)

**Testing Required:**
1. **Same Provider, Different Session:**
   - Start Claude Code session A in project
   - Start new Claude Code session B in same project
   - Verify system message: "Now following session B"

2. **Different Provider (Mixed Mode):**
   - Start Codex CLI session in project
   - Start Claude Code session in same project
   - Verify system message: "Switched to Claude Code session"

3. **Manual Transcript Switch:**
   - Use Transcript Inventory to switch active transcript
   - Verify system message appears in timeline

**Next Steps:**
1. Cherry-pick commit `ee33ca7` onto main or create new branch
2. Run all test scenarios above
3. Merge to main after verification
4. Phase 2 (optional): Make system messages restart-safe

**Files Modified:**
- `Contextify/Contextify/ConversationMonitor.swift` - System message logic (see line ~1992: `appendSystemEntry()`)
- `Contextify/Contextify/TimelineModels.swift` - `.system` kind defined (line 7)

---

### 3. Transcript Converter - Completion & Testing
**Status:** Incomplete - Core exists, needs audit and testing
**Priority:** Medium-High (useful for users switching between Claude Code/Codex)

**Current State:**
- ✅ `app/Sources/ContextifyCore/TranscriptConverter.swift` (33KB)
- ✅ Documentation in `build/docs/archive/completed-work/` (transcript-tool-conversion docs)
- ✅ Format specs in `build/docs/specifications/claude-code-format.md`

**What Needs Completion:**
- [ ] Audit current conversion implementation for correctness
- [ ] Test Claude Code → Codex conversion (verify in Codex CLI)
- [ ] Test Codex → Claude Code conversion (verify in Contextify)
- [ ] Round-trip conversion tests (both directions)
- [ ] Handle edge cases (empty transcripts, metadata-only files)
- [ ] UI integration for triggering conversions (if not already present)
- [ ] User documentation for when/why to convert formats

**Key Differences to Verify:**
- Claude Code uses `text` content blocks, Codex uses `input_text`/`output_text`
- Message structure: Claude Code has top-level `uuid`/`type`, Codex wraps in `payload.type:"message"`
- Metadata record handling (file-history, summary, system messages)
- Timestamp format preservation

**Success Criteria:**
- Converted transcripts load correctly in target tool
- No data loss (all messages, metadata preserved)
- Graceful error messages for conversion failures

---

## P2: LLM Robustness & Quality Improvements

### 1. LLM Content Moderation - Expletive Pre-filtering
**Status:** Planned - Production issue identified
**Impact:** Timeline entries with expletives fail to get summaries indefinitely

**Root Cause:** Raw conversation content sent directly to LLM. Apple's FoundationLLM rejects text containing profanity.

**Impact:**
- Timeline entries with expletives show hourglass forever
- Errors in logs: "content policy violation"
- Affects both timeline summaries and transcript metadata

**Proposed Fix:**
Add pre-filtering step before LLM submission. **Note:** The existing `sanitize()` function in `FoundationLLM.swift` (line ~1284) is for whitespace normalization, NOT expletive filtering.

```swift
/// Sanitize text by replacing expletives with placeholders before LLM submission.
/// Original content remains unchanged in database.
private func sanitizeForLLM(_ text: String) -> String {
    // Common profanity patterns with word boundaries to avoid false positives
    let expletivePatterns = [
        "\\bf[u*]+ck(ing|ed|er|s)?\\b",  // f-word variants
        "\\bsh[i*]+t(ty|s)?\\b",         // s-word variants
        "\\bd[a*]+mn(ed)?\\b",            // d-word variants
        "\\ba[s*]+hole(s)?\\b",           // a-word variants
        "\\bb[i*]+tch(y|es)?\\b",         // b-word variants
    ]

    var sanitized = text
    for pattern in expletivePatterns {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { continue }

        sanitized = regex.stringByReplacingMatches(
            in: sanitized,
            range: NSRange(sanitized.startIndex..., in: sanitized),
            withTemplate: "[expletive]"
        )
    }
    return sanitized
}
```

**Implementation Notes:**
- Filter only LLM input, keep original content in database
- Use word boundaries (`\b`) to avoid false positives (e.g., "class" contains "ass")
- Case-insensitive matching with `[.caseInsensitive]`
- Use `try?` for regex compilation (fail gracefully if pattern invalid)
- Document that LLM receives sanitized input for Apple's content policy compliance

**Files:**
- `Contextify/Contextify/FoundationLLM.swift` - Add sanitization helper
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` - Apply filter
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift` - Apply filter

**Success Criteria:**
- All conversation entries get summaries regardless of language
- No content policy violations in logs
- Previously failed entries succeed after cache regeneration

---

### 2. LLM Language Detection Guardrail
**Status:** Active issue - 3+ production occurrences
**Impact:** Non-English content fails to get LLM summaries

**Error Pattern:**
```
Unsupported language <lang> detected
timeline summarize guardrail triggered: unsupportedLanguageOrLocale
```

**Note:** "Unsupported language" log comes from Apple's FoundationLLM framework, not our code.

**Options:**
1. **Fallback Heuristics** - Generate rule-based summaries for non-English content
2. **Document Limitation** - Show UI message: "English-only summaries"
3. **Pre-filter Language** - Detect language before sending to LLM, skip if non-English

**Recommended:** Option 1 (fallback heuristics) provides best UX.

**Files:**
- `Contextify/Contextify/FoundationLLM.swift` - Language detection
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` - Fallback logic

---

### 3. Question Preservation in Assistant Summaries
**Status:** Deferred - Needs investigation
**Priority:** Low (enhancement, not bug)

**Goal:** Preserve questions at end of assistant messages in timeline summaries.

**Example:**
```
Original: "Database cleaned successfully... Would you like me to launch the app?"
Current:  "Claude cleaned the database."
Desired:  "Claude cleaned the database and asked if you'd like to launch the app."
```

**Issue:**
- Question extraction logic implemented but not detecting questions
- Debug logging not appearing (may be preprocessing issue)
- Needs investigation into message flow and LLM prompt handling

**Next Steps:**
1. Investigate why debug logging doesn't appear
2. Check if message is truncated before reaching `extractTrailingQuestion()`
3. Verify LLM receives TRAILING_QUESTION field correctly
4. Consider post-processing approach instead of pre-processing

---

## P3: First-Time User Experience

### 1. Welcome Modal & Progress Tracking
**Status:** Partial - Empty states done, welcome modal not yet implemented
**Priority:** Nice-to-have for public release

**What's Already Done:**
- ✅ Conversation log empty states (context-aware)
- ✅ Loading states in ConversationMonitor
- ✅ Empty state info popovers

**Still TODO:**
- [ ] Welcome modal on first launch
- [ ] Footer status indicator for discovery/indexing progress
- [ ] Progress callbacks from HooverEngine
- [ ] First-launch onboarding hints (beyond current help system)

**Files Needed:**
- `Contextify/Contextify/FirstStartupOrchestrator.swift` (NEW) - Coordination
- `Contextify/Contextify/WelcomeModalView.swift` (NEW) - Modal UI
- `Contextify/Contextify/ContentView.swift` - Footer badge

**Effort:** 4-6 hours

---

## Documentation & Maintenance

### Technical Documentation Updates
- [x] ~~Update `CLAUDE.md` with database schema v21~~ (already updated - line 49 shows v21)
- [ ] Document `StartupCoordinator` architecture in technical reference (already implemented but not documented)
- [ ] Update `sql-backend-architecture.md` with v12-v21 migrations
- [ ] Document reconciliation process for `assistant_usage`
- [ ] Add troubleshooting guide for timeline/badge issues

### Code Cleanup
- [ ] Remove outdated "Recently Completed Work" from TODOS.md (archive separately)
- [ ] Update roadmap documents with completed features
- [ ] Audit and remove debug-mode-only features (embeddings, semantic search)

---

## Future Enhancements (Post-1.0)

### Performance Optimization
- Timeline virtualization for projects with 10k+ entries
- Incremental timeline loading (fetch on scroll)
- Cache LLM summaries more aggressively

### User Experience
- Keyboard shortcuts for project switching (Cmd+Shift+[/])
- "Last active" timestamp on project tabs
- Pin feature to keep important projects at top
- Configurable timeline entry limit (currently hardcoded to 25)
- Project search/filter in tabs

### System Tray Support
- Minimize to system tray instead of quitting
- Show unread count in menu bar icon
- Quick restore from menu bar click
- Preference: "Keep in system tray when closed"

### Transcript Management
- Delete transcripts from UI (right-click context menu)
- Bulk cleanup for missing source files
- Test/debug transcript detection and removal
- Export transcript metadata before deletion

### Transcript Inventory Polish
- ✅ Hourglass icons (already implemented, commit `3b440d0`)
- Missing metadata investigation (UUID-only display)
- Fallback to placeholder text instead of raw UUID
- Auto-trigger metadata generation on first view

### Custom Slash Command Metadata
- Read custom command definitions from `~/.claude/commands/` and `~/.codex/commands/`
- Parse `.md` files for command descriptions
- Generate context-aware summaries instead of generic "You performed the following command"
- Cache in memory for fast lookup

### Help System Advanced Features
Core system complete (Phases 1-4). Advanced features deferred:
- HelpLink integration in Settings (link to online docs)
- First-launch onboarding tour (welcome screen)
- Context-sensitive help menu (dynamic based on app state)
- In-app help search (⌘K command palette)

**Reference:** `build/docs/design/help-tooltip-ux-system.md`

### Embedding & Semantic Search
**Status:** Implemented but hidden behind dev mode flag

**What's Missing:**
- Production-ready UX (current UI is developer-focused)
- Automatic embedding generation during ingestion
- Search results ranking and display improvements
- Timeline integration (click result → jump to entry)
- Progress feedback for batch operations

**When to Re-enable:** Complete batch improvements and search enhancements first.

### Multi-Machine Database Sync Protection
**Current State:** Detection-only warnings in Settings tab

**Enhancement Options:**
1. **Block Launch on Conflict** (2-4 hours) - Show alert if another machine accessed < 5 min ago
2. **Periodic Heartbeat** (4-6 hours) - Update timestamp every 30s for accurate detection
3. **CRDT Architecture** (40+ hours) - Full conflict-free replication (overkill unless core feature)

**Recommendation:** Option 1 + 2 for users with custom database locations on cloud storage.

---

## Recently Completed (Last 2 Weeks)

### Performance & Stability (2025-11-01 to 2025-11-08)
- ✅ **Startup Coordinator** - Full implementation with deterministic sequencing (commit `531ac70`)
- ✅ **Status Bar Flicker** - Eliminated AI status flicker during project switches (merged `b98f01d`)
- ✅ **Timeline Performance** - Row rendering optimization, ISO8601 formatter caching, main thread blocking eliminated
- ✅ **HTTP Diagnostics Port Conflict** - Server persists across project switches (commit `c14960b`)
- ✅ **Codex Discovery Warnings** - Demoted to debug level (commit `1ba1d90`)

### UI/UX Polish (2025-10-30 to 2025-11-03)
- ✅ **Timeline Summary Intent Classification** - Reduced .unknown from 15-30% to <5%
- ✅ **Hourglass Icons** - Consistent UI across Conversation Log and Transcript Inventory
- ✅ **Empty States** - Context-aware placeholders in timeline (already in production)
- ✅ **Help System** - Phases 1-4 complete with comprehensive tooltips and documentation

### Database & Architecture (2025-10-20 to 2025-10-30)
- ✅ **Project Switching Consolidation** - Single code path for all switches
- ✅ **Path Demangling Fix** - Fixed hyphenated directory handling
- ✅ **Unread Tracking** - Epoch timestamps (v12-v16 migrations)
- ✅ **Assistant Usage FK Hardening** - Staging table + reconciliation (v10-v11)
- ✅ **Project Tab Organization** - Drag-drop reordering, hide/show, orphaned detection

### Testing & Observability
- ✅ **Diagnostics HTTP API** - `/health`, `/diagnostics`, `/timeline/*` endpoints
- ✅ **Log Gap Analyzer** - Thread IDs, timestamps, file output for debugging
- ✅ **UI Performance Instrumentation** - Comprehensive UIOPT logging

**Total commits in last 2 weeks:** 98

---

## Archival Notes

### Removed Features (App Store Compliance)
- **iTerm2/Terminal Integration** - Removed in App Store preparation (commit `35ce380`)
  - Files removed: `ITerm2Bridge.swift`, `ComposeWindowManager.swift`, `GlobalHotkeyManager.swift`
  - See `build/notes/future-features.md` for re-implementation guidance if needed
  - Accessibility API entitlements incompatible with App Store sandboxing

### Database Schema History
- **Current:** v21 (database access metadata)
- **Recent migrations:** v12-v13 (epoch timestamps), v14-v15 (request ID normalization), v16 (unread indices), v17-v20 (schema fixes), v21 (multi-machine tracking)
- **Full history:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
