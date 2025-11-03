# Active Transcript Follow - Quick Reference

## Overview

Active session following automatically switches the timeline to show the most recent transcript activity, with support for manual pinning when you want to focus on a specific session.

## Modes

### Automatic Mode (Default)
- Timeline follows newest transcript after global cooldown (5 seconds)
- Switches occur when newer activity detected across sessions
- System messages emitted on switches (respects cooldown to avoid spam)

### Manual Mode (Pinned)
- User explicitly pins a session for monitoring
- Blocks automatic switches until unpinned
- Persists across app restarts via `project_follow_policy` table

## UI Components

### Projects Window
- **Follow chip**: Shows current mode ("Follow: Auto" or "Follow: Pinned (Session)")
- **Context menu**:
  - "Follow Newest (Auto)" - switch to automatic mode
  - "Pin Current Session" - pin the active session

### Transcript Inventory
- **List rows**: Green dot for active session, blue PINNED badge for manually pinned
- **Detail view actions**:
  - Not active → "Select for Monitoring"
  - Active → "Unpin (Auto)" button

## Key Architecture

### Components

1. **ActiveSessionPolicyEngine** (`ActiveSessionPolicyEngine.swift`)
   - Pure functional decision logic
   - Input: followMode, lastActiveKey, newestCandidate, cooldown
   - Output: Decision (nextActive, shouldEmitMessage, reason)

2. **ConversationMonitor** (`ConversationMonitor.swift`)
   - Lifecycle coordination and state management
   - Public API: `unpinToAuto()`, `pinAndSwitch(session)`
   - Private: `reconcilePolicyWithAvailableSessions()`, `handlePinnedMissing()`, `setActive()`

3. **TranscriptOrchestrator** (`TranscriptOrchestrator.swift`)
   - Database write methods: `setAutomatic()`, `setManual()`, `insertSystemEvent()`
   - Read methods: `getFollowPolicy()`, `getEntriesAfterCursor()`, `getRecentSystemSwitchEvents()`

4. **DatabaseWriteQueue** (`DatabaseWriteQueue.swift`)
   - Actor-based write serialization
   - Prevents SQLITE_BUSY errors under concurrent load

### Data Flow

```
User action (Pin/Unpin)
  ↓
ConversationMonitor public API
  ↓
TranscriptOrchestrator async writes
  ↓
DatabaseWriteQueue serialization
  ↓
SQLite project_follow_policy table
  ↓
Typed event → NotificationCenter
```

### Database Schema

**project_follow_policy:**
```sql
CREATE TABLE project_follow_policy (
  project_id        INTEGER NOT NULL UNIQUE,
  mode              INTEGER NOT NULL,  -- 0=auto, 1=manual
  pinned_session_id TEXT,
  pinned_provider   TEXT,
  updated_at        TEXT NOT NULL
)
```

**system_events** (enhanced):
```sql
-- Added columns:
project_id     INTEGER,  -- FK to projects
metadata_json  TEXT      -- Structured event data (from/to/reason/mode)
```

### Incremental Ingestion

**Composite cursor**: `(timestamp, created_at, id)`
- Deterministic ordering with covering index
- Handles out-of-order arrival without skips/duplicates
- Restart-safe: cursor initialized from tail entry

**Index:**
```sql
CREATE INDEX idx_entries_cursor ON transcript_entries(
  project_id, timestamp, created_at, id
)
```

## Special Behaviors

### Pinned Session Missing
When pinned session deleted:
1. Mode switches to automatic
2. If other sessions exist → switch to newest
3. If zero sessions → persist project-scoped event: "Pinned session unavailable — awaiting new activity"

### Provider Normalization
Migration v23 normalized all `"codex"` → `"codex.cli"` with compile-time enforcement via enum:
```swift
enum Provider: String {
  case claudeCode = "claude.code"
  case codexCLI = "codex.cli"
}
```

### Non-Summarizable Entries
Entries without `windowSha256` (no window context):
- Skip cache generation queue
- Display action: `.nonSummarizable`
- UI shows neutral dash (−) instead of spinner

## Events

**ActiveSessionDidChangeEvent** (Codable):
```swift
struct ActiveSessionDidChangeEvent {
  let projectPath: String
  let sessionId: String
  let provider: String
  let mode: String       // "automatic" | "manual"
  let reason: String     // newerWrite, pinnedMissing, etc.
  let timestamp: Date
}
```

Published to: `NotificationCenter.default` (`Notification.Name.activeSessionDidChange`)

## SwitchReason Cases

- `newerWrite` - Newer activity detected in another session
- `pinnedMissing` - Pinned session no longer available
- `manualSelection` - User explicitly selected a session
- `unpinToAuto` - User unpinned to automatic mode
- `projectChange` - Project root changed

## Configuration

**Global cooldown**: 5 seconds (configurable in policy engine)
- Suppresses duplicate system messages during rapid switches
- Session still switches, but message emission is suppressed

## Files Modified/Created

### Core Infrastructure
- `DatabaseSchema.swift` - v23 migration
- `DatabaseWriteQueue.swift` - Write serialization actor
- `TranscriptOrchestrator.swift` - Async write methods
- `EntryCursor.swift` - Composite cursor
- `ActiveSessionPolicyEngine.swift` - Policy engine
- `ActiveSessionEvents.swift` - Typed events
- `ConversationMonitor.swift` - Lifecycle integration
- `ProjectModels.swift` - Provider enum update

### UI
- `TranscriptInventoryView.swift` - Active indicators, PINNED badges, action buttons
- `ProjectRowView.swift` - Follow chip with context menu

## Next Steps (Future Enhancement)

1. **Dynamic Follow Chip Labels**: Expose followMode as observable, show "Follow: Pinned (Session Title)"
2. **Multi-Project Active Badges**: Show active indicators across all projects in ProjectsWindow
3. **Telemetry**: Track switch counts, cooldown hits, pin duration
4. **Tests**: Unit tests for policy engine, integration tests for restart persistence

## Troubleshooting

**SQLITE_BUSY errors**: Should not occur - DatabaseWriteQueue serializes all writes

**Pinned session not restoring on restart**: Check `project_follow_policy` table, verify `getFollowPolicy()` called in `loadFeedFromSQL()`

**System messages not appearing**: Check cooldown timing, verify `shouldEmitMessage` in Decision output

**Provider icons showing wrong color**: Verify enum normalization in migration v23

## References

- Implementation plan: `/private/tmp/yes-those-five-items.md`
- Progress tracking: `build/notes/feature-specs/active-transcript-follow/IMPLEMENTATION_PROGRESS.md`
- SQL architecture: `build/notes/technical-reference/sql-backend-architecture.md`
