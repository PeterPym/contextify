# Active Transcript Follow - Implementation Progress

**Branch:** `feature/active-transcript-follow`
**Date:** 2025-11-03
**Status:** In Progress (Core Infrastructure Complete, ConversationMonitor Updates Pending)

## Completed Components

### 1. Database Migration v23 ✅
**File:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

Implements the complete migration as specified in the implementation plan:

- **Follow Policy Table**: `project_follow_policy` with mode (auto/manual), pinned session/provider, timestamps
- **Provider Normalization**: Updates all `codex` → `codex.cli` in transcripts and entries
- **Cursor Index**: `idx_entries_cursor` on `(project_id, timestamp, created_at, id)` for deterministic scans
- **Project-Scoped Events**: Adds `project_id` column to `system_events` with backfill and index
- **Metadata JSON**: Adds `metadata_json` column to `system_events` for structured event data

### 2. DatabaseWriteQueue Actor ✅
**File:** `app/Sources/ContextifyCore/Database/DatabaseWriteQueue.swift`

Serializes all database write operations to prevent SQLITE_BUSY errors under concurrent load:

- Actor-based isolation for thread-safe write operations
- Generic write methods with `@Sendable` closures
- Integrates with existing GRDB pool infrastructure

### 3. TranscriptOrchestrator Async Methods ✅
**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`

Extended orchestrator with new async API for active session management:

- `setAutomatic(projectId:)` - Switch project to auto-follow mode
- `setManual(projectId:sessionId:provider:)` - Pin project to specific session
- `insertSystemEvent(_:)` - Persist session switch events to DB
- `getRecentSystemSwitchEvents(projectId:since:)` - Retrieve switch history for timeline
- `getFollowPolicy(projectId:)` - Read current follow policy
- `getEntriesAfterCursor(projectId:after:)` - Cursor-based incremental ingestion
- `FollowPolicyRow` model for DB row representation
- `SystemEventInsert` input model

### 4. Composite Cursor ✅
**File:** `Contextify/Contextify/EntryCursor.swift`

Deterministic cursor for incremental entry ingestion:

- Composite key: `(timestamp, createdAt, id)`
- Handles out-of-order entry arrival without skips/duplicates
- Compact JSON encoding (`ts`, `ca`, `id` keys)
- Convenience init from `TranscriptEntry`

### 5. ActiveSessionPolicyEngine ✅
**File:** `Contextify/Contextify/ActiveSessionPolicyEngine.swift`

Pure functional policy engine with complete types:

- `SessionKey` - Session identifier (id + provider)
- `FollowMode` - Enum: automatic | manual(pinned)
- `SwitchReason` - Enum for all switch causes
- `Decision` - Output type with next session, emit flag, reason
- `ActiveSessionPolicyEngine.Inputs` - Complete input state
- `decide(inputs:)` - Pure decision function with global cooldown

### 6. Typed Event System ✅
**File:** `Contextify/Contextify/ActiveSessionEvents.swift`

Structured event publication for session changes:

- `ActiveSessionDidChangeEvent` - Codable event with full context
- `Notification.Name.activeSessionDidChange` - NotificationCenter bridge
- Ready for Combine PassthroughSubject integration

### 7. Provider Enum Enforcement ✅
**Files:**
- `app/Sources/ContextifyCore/Projects/ProjectModels.swift`
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`

Compile-time prevention of provider string drift:

- Updated `ProjectSession.Provider` enum: `.codexCLI = "codex.cli"`
- `DiscoveredTranscript` now requires `Provider` enum in primary init
- Legacy string init deprecated with clear message
- Prevents reintroduction of `"codex"` drift

## Completed Components (cont.)

### 8. ConversationMonitor Lifecycle Updates ✅
**File:** `Contextify/Contextify/ConversationMonitor.swift`

Implemented full reconciliation logic with all helpers:

- **State variables**: `sessionsLoaded`, `isReadyForUpdates`, `followMode`, `lastActiveKey`, `lastSwitchAt`, `lastSystemEventTs`, `seenSystemEventIds`, `policyEngine`, `activeSession`
- **reconcilePolicyWithAvailableSessions()**: Checks if pinned session exists, triggers handlePinnedMissing() if not
- **handlePinnedMissing()**: Zero-session persistence with project-scoped events
- **setActive(from:to:reason:emit:)**: Session switching with DB writes and typed event publication
- **computeNewestKey()**: Finds newest session by last activity timestamp
- **followSummary()**: Human-readable summaries for session switches (matches SwitchReason enum)
- **publishTypedEvent()**: NotificationCenter bridge for session change events
- **appendSystemEntry()**: Direct timeline append for system messages
- **toJSON()**: Dictionary → JSON string helper
- **Public API**: `unpinToAuto()`, `pinAndSwitch()` for manual control
- **Fixed**: Duplicate activeSession property (removed one, kept observable one)
- **Fixed**: SystemEventInsert qualified with TranscriptOrchestrator prefix

### 9. Non-Summarizable Entry Handling ✅
**File:** `Contextify/Contextify/ConversationMonitor.swift`, `TimelineModels.swift`

Implemented check for entries without window context:
- Added `.nonSummarizable` action case to TimelineEntryAction enum
- Updated `toTimelineEntry()` to check `entry.windowSha256 == nil` before setting action
- Entries without window SHA never enqueue cache generation work

### 10. Cursor Initialization on Restart ✅
**File:** `Contextify/Contextify/ConversationMonitor.swift`

Implemented tail-based cursor initialization:
- In `loadFeedFromSQL()`, after loading entries, set `lastCursor` from tail entry
- Changed from `.first` to `.last` for correct restart-safe incremental updates
- Ensures cursor tracks the most recent entry position

## Pending Components

### 11. UI Updates ⏳
**Files:** (Not yet modified)
- `Contextify/Contextify/TranscriptInventoryView.swift`
- `Contextify/Contextify/ProjectsView.swift` (if exists, or equivalent)

Planned changes:
- Projects window: Follow chip (Auto/Pinned), context menu actions
- Inventory: Active indicators, Pinned badges, action buttons (Pin/Unpin)

### 12. Tests ⏳
**Files:** (Not yet created)
- Unit tests for `ActiveSessionPolicyEngine`
- Integration tests for restart persistence, provider normalization, ordering
- Stress tests for concurrent write queue

### 13. Documentation ⏳
**Files:** (Not yet created)
- `docs/active-session-policy.md` - Policy rules, cooldown, tripwires
- `build/notes/MIGRATIONS.md` - v23 migration notes
- `build/notes/INSTRUMENTATION.md` - Telemetry counters
- `build/notes/design-reference/ux-follow-pin.md` - UI/UX patterns

## Build Status

- ✅ Release build (v22 baseline): Success
- ✅ Debug build (v23 with all changes): **BUILD SUCCEEDED**
- ✅ Reconciliation logic (v23 + ConversationMonitor): **BUILD SUCCEEDED**

All core infrastructure compiles cleanly. ConversationMonitor lifecycle integration complete.

## Migration Path

For projects using `DiscoveredTranscript`:

```swift
// OLD (deprecated):
let transcript = DiscoveredTranscript(
  fileURL: url,
  providerString: "codex",  // ⚠️ Deprecated - drift risk
  sessionId: id
)

// NEW (enforced):
let transcript = DiscoveredTranscript(
  fileURL: url,
  provider: .codexCLI,  // ✅ Compile-time safety
  sessionId: id
)
```

## Next Steps

1. ✅ **ConversationMonitor Updates** - Core lifecycle and policy integration (COMPLETED)
2. ✅ **Non-Summarizable Handling** - Skip cache generation for entries without window SHA (COMPLETED)
3. ✅ **Cursor Init** - Restart-safe timeline position (COMPLETED)
4. **UI Polish** - Follow chips, badges, actions (NEXT)
5. **Testing** - Unit, integration, stress
6. **Documentation** - Policy docs, migration guide, instrumentation

## Notes

- All core infrastructure is in place and type-safe
- Database schema is fully migrated and indexed
- Write serialization prevents SQLITE_BUSY under load
- Provider enum prevents "codex" drift at compile time
- Ready for ConversationMonitor integration
