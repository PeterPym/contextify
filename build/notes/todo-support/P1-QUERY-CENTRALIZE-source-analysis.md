---
todo_id: P1-QUERY-CENTRALIZE
title: Timeline Query Source Code Analysis
type: source_analysis
date: 2025-11-22
status: active
description: Complete audit of all timeline entry loading functions showing duplicate implementations
---

# Timeline Query Source Code Analysis

## All Entry-Loading Functions

| Function | File | Line | Filters? | Used By |
|----------|------|------|----------|------------|
| `recentFeed()` | Repositories.swift | 383 | ✅ Yes | Initial timeline load |
| `recentByProject()` | Repositories.swift | 344 | ✅ Yes | - |
| `newByProject()` | Repositories.swift | 354 | ✅ Yes | - |
| `entriesAfterCursor()` | Repositories.swift | 431 | ✅ Yes | **NOT USED** |
| `getEntriesAfterCursor()` | TranscriptOrchestrator | 2085 | ❌ NO (fixed) | Incremental updates |
| `byTranscript()` | Repositories.swift | 363 | ❌ NO (fixed) | Single transcript view |
| `search()` | Repositories.swift | 373 | ❌ NO (fixed) | Search results |

## Duplicate Implementations

### Problem: Two Cursor-Based Entry Loaders

**Implementation 1 - Repositories.swift:431-438** (GRDB, correct but unused)
```swift
public func entriesAfterCursor(projectId: String, after: (timestamp: Int, createdAt: Int, id: String)) throws -> [TranscriptEntry] {
  try db.read { db in
    try TranscriptEntry
      .filter(Column("project_id") == projectId && Column("display_in_timeline") == 1)
      .filter(sql: "(timestamp, created_at, id) > (?, ?, ?)", arguments: [after.timestamp, after.createdAt, after.id])
      .order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)
      .fetchAll(db)
  }
}
```

**Implementation 2 - TranscriptOrchestrator.swift:2085-2108** (Raw SQL, actively used)
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
    } else {
      return try TranscriptEntry.fetchAll(db, sql: """
        SELECT * FROM transcript_entries
         WHERE project_id = :pid
         ORDER BY timestamp ASC, created_at ASC, id ASC
      """, arguments: ["pid": projectId])
    }
  }
}
```

**Why duplicate?**
- TranscriptOrchestrator reimplements instead of delegating to Repositories
- Raw SQL instead of using GRDB query builder
- Different signatures (`EntryCursor` vs tuple)

**Result:**
- GRDB version correct but never called
- Raw SQL version missing filter, actively used
- Bug hides in parallel implementation

## Architectural Smell

### Layer Violation

**Expected architecture:**
```
UI Layer (ConversationMonitor)
    ↓
Orchestrator Layer (TranscriptOrchestrator)
    ↓
Repository Layer (Repositories)
    ↓
Database Layer (GRDB)
```

**Actual implementation:**
```
ConversationMonitor
    ↓
TranscriptOrchestrator ──→ Raw SQL (bypasses Repositories)
    ↓
Repositories (unused for incremental updates)
```

**Problem:** Orchestrator bypasses abstraction layer

### Why It Happened

**Hypothesis:**
1. Initial implementation used Repositories correctly
2. Performance optimization needed (cursor pagination)
3. Developer added `getEntriesAfterCursor()` directly to Orchestrator
4. Skipped Repositories layer to avoid overhead
5. Forgot to add `display_in_timeline` filter (not in original query)

**Evidence:**
- Repositories has correct implementation (unused)
- Orchestrator has faster implementation (missing filter)
- No delegation pattern used

## Callsite Analysis

### getEntriesAfterCursor() Usage

**Primary caller:** ConversationMonitor.swift:2578
```swift
private func processIncrementalUpdate() async {
    guard let cursor = lastCursor else { return }

    do {
        let newEntries = try orchestrator.getEntriesAfterCursor(
            projectId: currentProjectId,
            after: cursor
        )

        await MainActor.run {
            self.timeline.append(contentsOf: newEntries)
        }
    } catch {
        logger.error("Incremental update failed: \(error)")
    }
}
```

**Frequency:** Every new transcript entry arrival
**Impact:** High (user-visible, high frequency)

### byTranscript() Usage

**Caller:** Unknown (needs grep)
**Frequency:** Low (single transcript detail view)
**Impact:** Medium (user-visible, low frequency)

### search() Usage

**Caller:** Search feature (if implemented)
**Frequency:** Low (on-demand search)
**Impact:** Low (user-initiated, infrequent)

## Implementation Strategy

### Step 1: Fix P0 Bugs

Add `display_in_timeline = 1` filter to all three functions:
1. `getEntriesAfterCursor()` (both branches)
2. `byTranscript()`
3. `search()`

**Effort:** 15 minutes
**Risk:** Very low (just adding missing filter)

### Step 2: Architectural Cleanup (P1)

**Goal:** Eliminate duplicate implementations, enforce single source of truth

**Approach:**
1. Create `TimelineEntryQuery` builder class
2. Refactor all 7 functions to use builder
3. Update callsites
4. Remove duplicates

**Effort:** 8-12 hours
**Risk:** Medium (refactoring active code paths)

### Why P1 Not P0

**P0 fixes make timeline correct:**
- Hidden entries no longer appear
- User-visible bugs eliminated
- Minimal code changes

**P1 cleanup prevents future bugs:**
- Can't forget filter (enforced by builder)
- No duplicate implementations
- Easier to maintain

**Prioritization:** Correctness first (P0), architecture second (P1)

## Related Files

**Current implementations:**
- `app/Sources/ContextifyCore/Database/Repositories.swift` (lines 344-438)
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` (lines 2085-2108)

**Callsites:**
- `Contextify/Contextify/ConversationMonitor.swift` (line 2578)
- Search feature (needs investigation)

**Documentation:**
- Design: `build/notes/todo-support/P1-QUERY-CENTRALIZE-design.md`
- Investigation: `build/notes/todo-support/P0-TIMELINE-FILTERS-investigation.md`
