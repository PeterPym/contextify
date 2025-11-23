---
todo_id: P0-TIMELINE-FILTERS
title: Timeline Filter Bypasses - Investigation Report
type: investigation
date: 2025-11-22
status: active
description: Investigation showing how hidden entries appear in UI via incremental updates, plus complete filter audit
---

# Timeline Filter Bypasses - Investigation Report

## Discovery

User observation: "I saw the hallucinated entry in the timeline UI during normal app use."

Database query: Entry has `display_in_timeline = 0`

Question: How did it appear in UI if it's marked hidden?

## Investigation Path

### Initial Hypothesis

**Assumed:** `recentFeed()` query (initial timeline load) had a bug

**Investigation:** Checked `recentFeed()` implementation

**Result:** Query filters correctly:
```swift
.filter(Column("display_in_timeline") == 1)  // ✅ Correct
```

### The Real Bug

**Location:** Incremental timeline updates, not initial load

**Function:** `getEntriesAfterCursor()` in TranscriptOrchestrator.swift:2085-2108

**Query:**
```swift
public func getEntriesAfterCursor(projectId: String, after cursor: EntryCursor?) throws -> [TranscriptEntry] {
  let pool = try dbManager.pool
  return try pool.read { db in
    if let c = cursor {
      return try TranscriptEntry.fetchAll(db, sql: """
        SELECT * FROM transcript_entries
         WHERE project_id = :pid AND (
                timestamp > :ts
             OR (timestamp = :ts AND created_at > :ca)
             OR (timestamp = :ts AND created_at = :ca AND id > :id)
         )
         ORDER BY timestamp ASC, created_at ASC, id ASC
      """, arguments: ["pid": projectId, "ts": c.timestamp, "ca": c.createdAt, "id": c.id])
    }
  }
}
```

**MISSING:** `AND display_in_timeline = 1` filter

### How User Saw It

**Timeline loading flow:**

1. **Project switch** → `onProjectOrSessionChange()` (ConversationMonitor.swift:671)
2. **Startup sequence** → `loadFeedFromSQL()` (line 1318)
3. **Initial load** → `orchestrator.getRecentFeed()` → **Filters correctly** ✅
4. **New entry arrives** → `processIncrementalUpdate()` (line 2578)
5. **Incremental fetch** → `orchestrator.getEntriesAfterCursor()` → **NO FILTER** ❌
6. **Hidden entry appears** in timeline UI

**User's experience:**
- Switched between projects in tab bar
- Timeline loaded (used filtered `recentFeed()` - correct)
- New transcript entry arrived (thinking block with hallucinated summary)
- Incremental update appended it (used unfiltered `getEntriesAfterCursor()` - bug!)
- Entry appeared in UI despite `display_in_timeline = 0`

## Complete Filter Audit

**Timeline entry loading functions:**

| Function | Location | Filters? | Used By |
|----------|----------|----------|---------|
| `recentFeed()` | Repositories.swift:383 | ✅ Yes | Initial timeline load |
| `recentByProject()` | Repositories.swift:344 | ✅ Yes | - |
| `newByProject()` | Repositories.swift:354 | ✅ Yes | - |
| `entriesAfterCursor()` | Repositories.swift:431 | ✅ Yes | *(Not used!)* |
| `getEntriesAfterCursor()` | TranscriptOrchestrator.swift:2085 | ❌ **NO** | **Incremental updates** |
| `byTranscript()` | Repositories.swift:363 | ❌ **NO** | Single transcript view |
| `search()` | Repositories.swift:373 | ❌ **NO** | Search results |

**Bug surface area:**
- ❌ Incremental updates (high frequency, user-visible)
- ❌ Single transcript view (low frequency, user-visible)
- ❌ Search results (low frequency, user-visible)

## Evidence of Duplicate Implementations

**Finding:** There are **TWO** implementations of "cursor-based entry loading":

**Implementation 1 - Repositories.swift:431-438** ✅ **Correct**
```swift
public func entriesAfterCursor(projectId: String, after: (timestamp: Int, createdAt: Int, id: String)) throws -> [TranscriptEntry] {
  try db.read { db in
    try TranscriptEntry
      .filter(Column("project_id") == projectId && Column("display_in_timeline") == 1)  // ← FILTERED
      .filter(sql: "(timestamp, created_at, id) > (?, ?, ?)", arguments: [after.timestamp, after.createdAt, after.id])
      .order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)
      .fetchAll(db)
  }
}
```

**Implementation 2 - TranscriptOrchestrator.swift:2085-2108** ❌ **Missing filter**
```swift
public func getEntriesAfterCursor(projectId: String, after cursor: EntryCursor?) throws -> [TranscriptEntry] {
  // ... raw SQL without display_in_timeline filter
}
```

**Why it happened:**
- Repositories layer uses GRDB query builder (correct filter)
- TranscriptOrchestrator layer reimplements with raw SQL (forgot filter)
- Orchestrator doesn't delegate to Repositories, creates parallel implementation

## Impact Analysis

### Original Understanding (Before This Discovery)

**Believed:**
- Hidden entries only affect cache miss detection (background summarization)
- User never sees hidden entries (filter works in UI queries)
- Impact: Wasted LLM resources, hallucination risk in background

**Priority:** Medium (inefficiency, not correctness bug)

### Updated Understanding (After This Discovery)

**Reality:**
- Hidden entries appear in timeline UI via incremental updates
- User DOES see hallucinated summaries for thinking blocks
- Impact: User-visible data corruption, trust erosion, incorrect timeline

**Priority:** **Critical** (user-facing correctness bug)

### Frequency

**How often does bug trigger?**
- Every project switch with subsequent transcript activity
- Every new entry arrival during active session
- High frequency during normal app use

**Severity:** P0 (blocking release, user-visible data corruption)

## Related Analysis

- Comprehensive review: `/tmp/timeline-summarization-comprehensive-review-package.md`
- Addendum: `/tmp/timeline-summarization-addendum-incremental-update-filter-bug.md`
- Colleague feedback: `/tmp/here-s-a-reflowed.md`
- Implementation plan: `/tmp/P0-TIMELINE-FILTER-BUGS-implementation-plan.md`
