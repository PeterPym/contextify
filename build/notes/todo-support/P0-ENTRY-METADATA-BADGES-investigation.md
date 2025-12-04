---
todo_id: P0-ENTRY-METADATA-BADGES
title: Conversation Entry Metadata Display Bugs
type: investigation
date: 2025-12-04
status: active
description: Two bugs cause timeline entry badges (QUEUED, pulsing hourglass) to persist after their conditions clear
---

# Conversation Entry Metadata Display Bugs

Two separate issues cause metadata badges/indicators to persist incorrectly in timeline entries.

---

## Issue 1: Queued Badge Not Clearing

### Problem

User messages marked with "QUEUED" badge do not clear after Claude processes the queued message. The badge persists indefinitely.

### Root Cause

Claude Code's `remove` queue operation does not include the message content:

```json
// enqueue (has content)
{"type":"queue-operation","operation":"enqueue","sessionId":"...","content":"user message"}

// remove (no content)
{"type":"queue-operation","operation":"remove","sessionId":"..."}
```

The parser requires content to compute a hash for matching, so `remove` operations are silently skipped:

**TranscriptParsers.swift:928-930**
```swift
case .remove:
  guard let content = json["content"] as? String, !content.isEmpty else {
    parserLog.warning("[QUEUE-OP] remove without content; skipping...")
    return MetadataParseResult()  // Operation dropped
  }
```

### Solution

Use FIFO matching: on `remove`, clear the oldest queued entry for that session from our database. We already have entry IDs stored when we process `enqueue`.

**TranscriptParsers.swift (~line 927)** - Remove content requirement:
```swift
case .remove:
  // Claude Code's remove doesn't include content; use FIFO matching
  contentSha256 = nil
```

**HooverEngine.swift (~line 842)** - FIFO query:
```swift
case .remove:
  // FIFO: clear oldest queued entry for this session
  try db.execute(sql: """
    UPDATE transcript_entries
    SET is_queued = 0
    WHERE id = (
      SELECT id FROM transcript_entries
      WHERE transcript_id = ? AND session_id = ? AND is_queued = 1
      ORDER BY timestamp ASC
      LIMIT 1
    )
  """, arguments: [op.transcriptId, op.sessionId])
```

### Files

#### Require Changes

| File | Line(s) | Change |
|------|---------|--------|
| `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` | 928-930 | Remove content guard for `.remove` |
| `app/Sources/ContextifyCore/Database/HooverEngine.swift` | 842-858 | FIFO query instead of content-hash match |

#### Related (No Changes Needed)

| File | Line(s) | Role |
|------|---------|------|
| `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` | 103-144 | Parses `enqueue`, creates entry with `isQueued: true` |
| `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` | 795-820 | `QueueOperation` struct definition |
| `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` | 904-948 | Metadata parser for queue operations |
| `app/Sources/ContextifyCore/Database/HooverEngine.swift` | 821-879 | Applies queue operations to DB, posts notification |
| `app/Sources/ContextifyCore/Database/HooverEngine.swift` | 73-106 | `EntryInsert` struct with `isQueued` field |
| `app/Sources/ContextifyCore/Database/Models.swift` | 132, 161 | `TranscriptEntry.isQueued` DB column mapping |
| `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` | 568-588 | Migration v27: `is_queued` column + index |
| `Contextify/Contextify/ConversationMonitor.swift` | 1365 | Converts DB `isQueued` int to bool for UI |
| `Contextify/Contextify/ConversationMonitor.swift` | 1997-2021 | Handles `QueueOperationsProcessed` notification |
| `Contextify/Contextify/TimelineModels.swift` | 43, 81, 100, 254 | `TimelineEntry.isQueued` field and `copyWith` preservation |
| `Contextify/Contextify/TimelineEntryRow.swift` | 147-155 | Renders "QUEUED" badge in UI |

---

## Issue 2: Pulsing Hourglass Not Clearing

### Problem

The pulsing hourglass icon (indicating active summarization) sometimes persists after summarization completes. The entry shows a summary but the hourglass keeps pulsing.

### Root Cause

Race condition between cache update and action state. When `refreshCachedEntries` updates an entry after summarization, it only clears `.unsummarized` action, not `.generatingActive`:

**ConversationMonitor.swift:2670-2674**
```swift
updateEntry(at: index, with: old.copyWith(
    summary: summary,
    action: old.action == .unsummarized ? .none : old.action,  // ← BUG
    disposition: cache.disposition
))
```

**Timeline:**
1. Entry queued for summarization → `action = .unsummarized`
2. Processing starts → `action = .generatingActive` (via `activeGeneratingID` check)
3. Summary saved to cache → `timelineCacheUpdated` notification fired
4. `refreshCachedEntries` runs → checks `old.action == .unsummarized`
5. But action is `.generatingActive`, so it's preserved unchanged
6. Hourglass keeps pulsing despite summary being present

### Solution

Clear action for both `.unsummarized` AND `.generatingActive`:

**ConversationMonitor.swift:2672**
```swift
action: (old.action == .unsummarized || old.action == .generatingActive) ? .none : old.action,
```

### Files

#### Require Changes

| File | Line(s) | Change |
|------|---------|--------|
| `Contextify/Contextify/ConversationMonitor.swift` | 2672 | Include `.generatingActive` in action clear condition |

#### Related (No Changes Needed)

| File | Line(s) | Role |
|------|---------|------|
| `Contextify/Contextify/TimelineEntryRow.swift` | 129-138 | Renders pulsing hourglass for `.generatingActive` |
| `Contextify/Contextify/TimelineEntryRow.swift` | 139-143 | Renders static hourglass for `.unsummarized` |
| `Contextify/Contextify/TimelineModels.swift` | 19-25 | `TimelineEntryAction` enum definition |
| `Contextify/Contextify/TimelineModels.swift` | 218-258 | `copyWith` function for entry updates |
| `Contextify/Contextify/TimelineCacheMissGenerator.swift` | 41 | `activeEntryID` property for tracking active generation |
| `Contextify/Contextify/TimelineCacheMissGenerator.swift` | 291-298 | Sets `activeEntryID` when processing starts |
| `Contextify/Contextify/TimelineCacheMissGenerator.swift` | 334-342 | Updates `activeEntryID` after batch completes |
| `Contextify/Contextify/TimelineCacheMissGenerator.swift` | 352-355 | Clears `activeEntryID` when queue empty |
| `Contextify/Contextify/TimelineCacheMissGenerator.swift` | 705-718 | Posts `timelineCacheUpdated` notification |
| `Contextify/Contextify/ConversationMonitor.swift` | 1512-1546 | Maps `activeGeneratingID` to entry action during feed load |
| `Contextify/Contextify/ConversationMonitor.swift` | 1712-1744 | Handles `timelineCacheUpdated` notification with debounce |
| `Contextify/Contextify/ConversationMonitor.swift` | 2625-2682 | `refreshCachedEntries` implementation |

---

## Summary

| Issue | Badge/Indicator | Root Cause | Fix Location |
|-------|-----------------|------------|--------------|
| Queued badge | "QUEUED" text | `remove` op has no content; parser skips it | TranscriptParsers + HooverEngine |
| Pulsing hourglass | Animated hourglass | Only `.unsummarized` cleared, not `.generatingActive` | ConversationMonitor:2672 |

Both issues are independent - fixing one does not fix the other.

## Testing

### Queued Badge
1. Send a message while Claude is actively working
2. Wait for Claude to process the queued message
3. Verify "QUEUED" badge clears
4. Test with multiple queued messages to verify FIFO ordering

### Pulsing Hourglass
1. Scroll to trigger summarization of an unsummarized entry
2. Watch entry transition to pulsing hourglass
3. Wait for summary to appear
4. Verify hourglass clears when summary displays
