---
title: Sidechain Transcript Enhancements
created: 2025-11-29
related_todo: P3-SIDECHAIN-ENHANCEMENTS
status: backlog
---

# Sidechain Transcript Enhancements

Future improvements identified during the sidechain transcript bug fix (2025-11-29).

## Context

The v1 fix uses a filename heuristic (`agent-*.jsonl`) to deprioritize sidechain transcripts during FastPath ingestion. These enhancements would improve robustness and UX but are not required for the immediate bug fix.

## Enhancement 1: DB-level Transcript Kind Column

**Problem:** Current fix relies on filename pattern matching in the ingestion coordinator.

**Solution:** Add a `kind` column to the `transcripts` table:

```sql
ALTER TABLE transcripts ADD COLUMN kind TEXT DEFAULT 'unknown';
-- Values: 'main', 'sidechain', 'unknown'
```

**Population strategy:**
- On first ingest when Hoover sees `isSidechain: true` in first record, set `kind = 'sidechain'`
- If first record has `agentId: null`, set `kind = 'main'`
- Migration could infer from filename + first line for existing transcripts

**Benefits:**
- FastPath can sort by `kind` instead of filename heuristics
- More robust against naming convention changes
- Enables richer queries (e.g., "show only main conversations")

**Effort:** Medium (schema migration + parser changes + FastPath update)

## Enhancement 2: Content-Value-Based Prioritization

**Problem:** Current prioritization is binary (agent vs non-agent) + file size.

**Solution:** Order by "likely to contribute timeline entries":

```swift
transcripts.sorted { lhs, rhs in
  // 1. Transcripts already known to have entries
  if lhs.hasEntries != rhs.hasEntries {
    return lhs.hasEntries
  }
  // 2. Non-sidechain transcripts
  if lhs.kind != rhs.kind {
    return lhs.kind == "main"
  }
  // 3. Most recently modified
  return lhs.lastModified > rhs.lastModified
}
```

**Benefits:**
- Better handles large projects with many stale sessions
- Prioritizes transcripts we know have content
- More intelligent than pure file size

**Effort:** Low once Enhancement 1 is done

## Enhancement 3: Timeline Primer UX for Sidechain-Only Projects

**Problem:** If a project has only sidechain transcripts, timeline shows "waiting for primer entries" then times out.

**Solution:** Detect the condition and show appropriate message:

```swift
// After primer timeout, check if all transcripts are sidechains
if entryCount == 0 && allTranscriptsAreSidechains {
  showMessage("No visible timeline entries (only internal agent messages present)")
} else {
  showMessage("No entries found")
}
```

**Benefits:**
- Clearer UX for edge case
- Avoids confusing "waiting" state when nothing will ever arrive

**Effort:** Low (detection + UI message)

## Related Files

- `/Users/rob/code/projects/contextify/app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`
- `/Users/rob/code/projects/contextify/app/Sources/ContextifyCore/Database/DatabaseSchema.swift`
- `/Users/rob/code/projects/contextify/Contextify/Contextify/ConversationMonitor.swift`

## References

- `/tmp/sidechain-transcript-bug-analysis.md` - Original bug analysis
- `/tmp/here-s-my-review-as-principal-engineer.md` - Principal engineer review
