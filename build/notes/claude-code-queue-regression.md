# Claude Code Bug Report: Missing Queue-Operation Cleanup Records

## Summary

Claude Code 2.0.50+ has a regression where `queue-operation` records with operations `dequeue`, `popAll`, and `remove` are no longer being written to transcript files. This breaks queue state management for tools that depend on these records to track message acknowledgment.

## Versions Affected

- **Last working version:** 2.0.37 (Nov 13, 2025)
- **Broken version:** 2.0.50 (current, as of Nov 21, 2025)
- **Regression window:** Sometime between v2.0.37 and v2.0.50

## Expected Behavior

When a queued user message is acknowledged by Claude (dequeued), Claude Code should write a `queue-operation` record to the transcript with one of:
- `"operation": "dequeue"` - Single message dequeued
- `"operation": "popAll"` - All queued messages cleared
- `"operation": "remove"` - Specific message removed from queue

### Example (from v2.0.37 transcript)

```json
{"type":"queue-operation","operation":"dequeue","timestamp":"2025-11-13T19:57:12.788Z","sessionId":"fb10e487-2d43-4108-be10-3cd9af26002b"}
{"type":"queue-operation","operation":"dequeue","timestamp":"2025-11-13T19:58:16.465Z","sessionId":"fb10e487-2d43-4108-be10-3cd9af26002b"}
{"type":"queue-operation","operation":"popAll","timestamp":"2025-11-13T20:00:06.073Z","content":"/review-prep ","sessionId":"fb10e487-2d43-4108-be10-3cd9af26002b"}
```

## Actual Behavior

In Claude Code 2.0.50, only `enqueue` operations are written:

```json
{"type":"queue-operation","operation":"enqueue","timestamp":"2025-11-21T21:14:25.025Z","content":"Reply ACK123...","sessionId":"9199e69d-c01a-461c-888a-6ba8e7f0631a"}
```

No corresponding `dequeue`/`popAll`/`remove` records are written when the message is acknowledged.

## Impact

Applications that track message queue state (e.g., showing "QUEUED" badges in UI) cannot detect when messages have been acknowledged. This leaves stale "queued" indicators visible even after Claude has processed the message.

## Reproduction Steps

1. Start a Claude Code session in a project directory
2. Send a message while Claude is responding to a previous message (triggers queue)
3. Verify `enqueue` operation is written to transcript:
   ```bash
   tail ~/.claude/projects/<project-path>/<session-id>.jsonl | grep queue-operation
   ```
4. Wait for Claude to finish and acknowledge the queued message
5. Check transcript again - **BUG:** No `dequeue`/`popAll`/`remove` operation is written

## Verification

### Working transcript (v2.0.37)
```bash
$ head -5 ~/.claude/projects/-Users-rob-code-projects-contextify/fb10e487-2d43-4108-be10-3cd9af26002b.jsonl | grep version
"version":"2.0.37"

$ grep '"operation":"dequeue\|"operation":"popAll"' fb10e487-2d43-4108-be10-3cd9af26002b.jsonl | head -3
{"type":"queue-operation","operation":"dequeue","timestamp":"2025-11-13T19:57:12.788Z",...}
{"type":"queue-operation","operation":"dequeue","timestamp":"2025-11-13T19:58:16.465Z",...}
{"type":"queue-operation","operation":"popAll","timestamp":"2025-11-13T20:00:06.073Z",...}
```

### Broken transcript (v2.0.50)
```bash
$ head -5 ~/.claude/projects/-Users-rob-code-projects-contextify/9199e69d-c01a-461c-888a-6ba8e7f0631a.jsonl | grep version
"version":"2.0.50"

$ grep '"operation":"dequeue\|"operation":"popAll\|"operation":"remove"' 9199e69d-c01a-461c-888a-6ba8e7f0631a.jsonl
# (no results)

$ grep '"operation":"enqueue"' 9199e69d-c01a-461c-888a-6ba8e7f0631a.jsonl | wc -l
47  # enqueue operations present, but no cleanup operations
```

## Understanding Queue Operations

Based on v2.0.37 transcript analysis, the queue mechanism works as follows:

**Timeline:**
```
19:57:11.080 - ENQUEUE "then do your commits"  (metadata record)
                ↓ Message held in memory, NOT in conversation yet
19:57:12.788 - DEQUEUE                           (metadata record)
                ↓ Message ready to be released
19:57:12.812 - User message appears              (actual conversation entry)
                ↓ NOW in transcript with proper UUID
19:57:21.072 - Assistant responds
```

**Key insight:** Queue-operation records are METADATA, not conversation entries. The real user message appears AFTER dequeue, and that's the actual conversation entry.

## Workaround

For applications parsing transcripts and displaying timeline:

1. Create synthetic placeholder entries from `enqueue` operations (shows user what's queued)
2. When real user message appears, match by `content_sha256` and delete the synthetic entry
3. Display the real message normally (no longer queued)

Example:
```swift
// When inserting user entries (not synthetic queue-XX entries)
for entry in entries where entry.kind == "user" && !entry.id.hasPrefix("queue-") {
  // Delete matching synthetic queue entry
  db.execute("""
    DELETE FROM transcript_entries
    WHERE transcript_id = ? AND content_sha256 = ?
      AND id LIKE 'queue-%' AND is_queued = 1
  """, [transcriptId, entry.contentSha256])
}
```

This gives users visibility into queued messages while maintaining accurate timeline state.

## Requested Fix

Restore the queue cleanup operation logging that was present in v2.0.37. Ensure that `dequeue`, `popAll`, and `remove` queue-operations are written to transcripts when messages are acknowledged.

## Additional Context

- Project: Contextify (macOS app for tracking Claude Code sessions)
- Reporter: rob@banagale.com
- Date: November 21, 2025
- Related files:
  - Working transcript: `~/.claude/projects/-Users-rob-code-projects-contextify/fb10e487-2d43-4108-be10-3cd9af26002b.jsonl`
  - Broken transcript: `~/.claude/projects/-Users-rob-code-projects-contextify/9199e69d-c01a-461c-888a-6ba8e7f0631a.jsonl`
