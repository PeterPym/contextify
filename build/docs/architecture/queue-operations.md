# Claude Code Queue Operations - Architecture & Implementation

**Related Documentation:**
- [Claude Code Transcript Format Specification](../specifications/claude-code-transcript-format.md#queue-operations) - Transcript record format details
- [TranscriptParsers.swift](../../../app/Sources/ContextifyCore/Database/TranscriptParsers.swift) - Implementation
- [HooverEngine.swift](../../../app/Sources/ContextifyCore/Database/HooverEngine.swift) - Queue operation processing

## Summary

Claude Code uses `queue-operation` metadata records in transcripts to track messages sent while Claude is processing. The behavior changed significantly between v2.0.37 and v2.0.50, requiring defensive programming with dual mechanisms in Contextify.

## Transcript Queue Operations

Three operation types exist:
- **enqueue**: User sent message while Claude was busy
- **dequeue**: Message released into conversation (becomes permanent user record)
- **remove**: Message discarded without permanent record (ephemeral)
- **popAll**: Clear all queued messages for session

## Version Comparison

### v2.0.37 (Nov 13, 2025) - DEQUEUE Pattern

```
19:57:11.080 - ENQUEUE "then do your commits"
19:57:12.788 - DEQUEUE (1.7s later)
19:57:12.812 - User message appears in transcript (UUID: bb68f018...)
19:57:21.072 - Assistant responds
```

**Behavior**: Queued messages become permanent conversation records.
- ENQUEUE is preview/notification
- DEQUEUE signals message entering conversation
- Real user message record written to transcript
- Timeline shows the real message (not synthetic)

### v2.0.50 (Nov 21, 2025) - REMOVE Pattern

```
06:57:55.809 - ENQUEUE "reply acki"
06:57:59.279 - REMOVE (3.5s later)
(NO user message record written)
06:58:02.971 - Assistant responds anyway
```

**Behavior**: Queued messages are ephemeral.
- ENQUEUE creates synthetic entry for awareness
- REMOVE discards without permanent record
- NO real user message in transcript
- Assistant still sees and responds to message
- Message influenced conversation but left no trace

## Contextify Implementation

### Problem
Queue operations are metadata, not conversation entries. Without synthetic entries, ephemeral messages (v2.0.50 REMOVE pattern) would be invisible in timeline despite Claude responding to them.

### Solution: Dual Mechanism

**1. Synthetic Queue Entries** (TranscriptParsers.swift:103-137)
```swift
if type == "queue-operation" && operation == "enqueue" {
  // Create synthetic entry: queue-{hash}-{hash}
  // Set is_queued=true → shows "QUEUED" badge in UI
}
```

**2. Queue Operation Handler** (HooverEngine.swift:811-857)
```swift
case .remove:
  UPDATE transcript_entries SET is_queued = 0
  WHERE content_sha256 = ? AND is_queued = 1
  // Clears badge on synthetic entry

case .dequeue, .popAll:
  UPDATE transcript_entries SET is_queued = 0
  WHERE session_id = ? AND is_queued = 1
  // Clears all queued entries for session
```

**3. Content-Matching Heuristic** (HooverEngine.swift:728-746)
```swift
// Defensive fallback for v2.0.37-style DEQUEUE
for entry in entries where entry.kind == "user" {
  DELETE FROM transcript_entries
  WHERE content_sha256 = ? AND id LIKE 'queue-%'
  // Remove synthetic when real message supersedes it
}
```

**4. UI Refresh** (HooverEngine.swift:858-871)
```swift
// Post notification after queue operations
NotificationCenter.post("QueueOperationsProcessed")
// ConversationMonitor reloads feed to show updated is_queued values
```

### Mechanism Priority

**Execution order during hoover:**
1. Entry insertion (with heuristic) - runs FIRST
2. Metadata processing (with queue-ops) - runs AFTER

**v2.0.50 (REMOVE):**
- Heuristic: no-op (real message never appears)
- Queue-op: wins (changes=1, clears is_queued=0)

**v2.0.37 (DEQUEUE):**
- Heuristic: wins (changes=1, deletes synthetic entry)
- Queue-op: no-op (changes=0, entry already gone)

**Broken/future:**
- Heuristic: fallback works if real messages appear
- Queue-op: fallback works if queue operations resume

## Timing Data

Typical queue durations (ENQUEUE → REMOVE/DEQUEUE):
- Fast: 1.4s (quick acknowledgment)
- Normal: 3.5s (processing ongoing work)
- Slow: 8.0s (complex task completion)

Provides useful activity awareness - user sees "message waiting" indicator during this window.

## Database Schema

```sql
CREATE TABLE transcript_entries (
  id TEXT PRIMARY KEY,
  -- ... other fields ...
  is_queued INTEGER DEFAULT 0,  -- 1=waiting, 0=processed/normal
  content_sha256 TEXT  -- Used for matching queue-XX to real messages
);
```

Synthetic queue entries:
- ID format: `queue-{timestamp_hash}-{content_hash}`
- `is_queued=1` initially
- Set to `0` when processed, or entry deleted entirely

## Configuration

Feature can be disabled via environment variable:
```bash
export CONTEXTIFY_SHOW_QUEUED=0  # Hide queue badges
unset CONTEXTIFY_SHOW_QUEUED     # Show queue badges (default)
```

## Edge Cases

**Multiple queue mechanisms coexist safely:**
- Queue-op `UPDATE is_queued=0` on deleted entry = no-op (changes=0)
- Heuristic `DELETE WHERE is_queued=1` after already cleared = no-op (changes=0)
- Both can run without conflict

**Race conditions handled:**
- ConversationMonitor only refreshes for current project
- Incremental updates use debouncing (150ms)
- Full reload on queue operations ensures consistency

## Logging

```
[QUEUE-ENQUEUE] Creating synthetic entry id=queue-XXX ts=2025-11-22T06:57:55.809Z content="reply acki"
[QUEUE-OP-CLEAR] remove cleared 1 entries after 3.5s content_sha256=21cc882e
[QUEUE-REFRESH] Queue operations processed, refreshing entries
```

Reveals:
- When messages queued
- How long they waited
- Which mechanism processed them
- Whether queued indicator provides UX value

## Summary

Claude Code's queue behavior is undocumented and changed between versions. Contextify uses defensive programming (synthetic entries + dual clearing mechanisms) to handle both patterns correctly, providing visibility into ephemeral messages that would otherwise be invisible in the timeline.
