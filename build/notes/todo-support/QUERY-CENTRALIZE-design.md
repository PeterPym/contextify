---
todo_id: P1-QUERY-CENTRALIZE
title: Timeline Query Centralization - Design
type: spec
date: 2025-11-22
status: active
description: Architectural design for centralized timeline query builder to prevent filter drift
---

# Timeline Query Centralization - Design

## Problem

Multiple SQL implementations doing similar things:
- Repositories layer: GRDB query builder (correct)
- Orchestrator layer: Raw SQL (missing filters)

Result: Filter drift, bugs hiding in parallel implementations

## Current State

**7 functions loading timeline entries:**

| Function | Location | Implementation | Filters? |
|----------|----------|----------------|----------|
| `recentFeed()` | Repositories.swift:383 | GRDB | ✅ Yes |
| `recentByProject()` | Repositories.swift:344 | GRDB | ✅ Yes |
| `newByProject()` | Repositories.swift:354 | GRDB | ✅ Yes |
| `entriesAfterCursor()` | Repositories.swift:431 | GRDB | ✅ Yes |
| `getEntriesAfterCursor()` | TranscriptOrchestrator.swift:2085 | Raw SQL | ❌ NO |
| `byTranscript()` | Repositories.swift:363 | GRDB | ❌ NO |
| `search()` | Repositories.swift:373 | GRDB | ❌ NO |

**Issues:**
- Duplicate implementations (GRDB vs raw SQL)
- Inconsistent filtering
- Orchestrator bypasses Repositories layer

## Solution: Query Builder Pattern

### Design

```swift
final class TimelineEntryQuery {
    private var projectId: String?
    private var visibleOnly: Bool = false
    private var cursor: EntryCursor?
    private var transcriptId: String?
    private var searchText: String?
    private var limitCount: Int?

    // Chainable filters
    func forProject(_ id: String) -> Self {
        self.projectId = id
        return self
    }

    func visibleOnly() -> Self {
        self.visibleOnly = true
        return self
    }

    func afterCursor(_ cursor: EntryCursor) -> Self {
        self.cursor = cursor
        return self
    }

    func byTranscript(_ id: String) -> Self {
        self.transcriptId = id
        return self
    }

    func search(_ text: String) -> Self {
        self.searchText = text
        return self
    }

    func limit(_ n: Int) -> Self {
        self.limitCount = n
        return self
    }

    // Execute query
    func fetch() throws -> [TranscriptEntry] {
        // Build GRDB query from accumulated filters
        var query = TranscriptEntry.all()

        if let projectId = projectId {
            query = query.filter(Column("project_id") == projectId)
        }

        if visibleOnly {
            query = query.filter(Column("display_in_timeline") == 1)
        }

        if let transcriptId = transcriptId {
            query = query.filter(Column("transcript_id") == transcriptId)
        }

        if let searchText = searchText {
            query = query.filter(Column("content").like("%\(searchText)%"))
        }

        if let cursor = cursor {
            query = query.filter(sql: "(timestamp, created_at, id) > (?, ?, ?)",
                                arguments: [cursor.timestamp, cursor.createdAt, cursor.id])
        }

        query = query.order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)

        if let limitCount = limitCount {
            query = query.limit(limitCount)
        }

        return try db.read { db in
            try query.fetchAll(db)
        }
    }
}
```

### Usage Examples

**Incremental timeline update:**
```swift
let entries = TimelineEntryQuery()
    .forProject(projectId)
    .visibleOnly()
    .afterCursor(cursor)
    .fetch()
```

**Single transcript view:**
```swift
let entries = TimelineEntryQuery()
    .byTranscript(transcriptId)
    .visibleOnly()
    .fetch()
```

**Search:**
```swift
let entries = TimelineEntryQuery()
    .forProject(projectId)
    .visibleOnly()
    .search(searchText)
    .fetch()
```

**Recent feed:**
```swift
let entries = TimelineEntryQuery()
    .forProject(projectId)
    .visibleOnly()
    .limit(100)
    .fetch()
```

## Benefits

### Impossible to Forget Filter

**Current problem:**
```swift
// Easy to forget display_in_timeline
SELECT * FROM transcript_entries WHERE project_id = ?
```

**With query builder:**
```swift
// Filter always explicit in callsite
TimelineEntryQuery()
    .forProject(projectId)
    .visibleOnly()  // ← Must call to filter
    .fetch()
```

**Callsite clearly shows intent:** "I want visible entries only"

### Single Source of Truth

**Before:** 7 functions with different implementations

**After:** 1 query builder, 7 callsites using it

**Maintenance:** Change filter logic in one place

### Type Safety

**Current:** Raw SQL strings, easy to make mistakes

**Builder:** Chainable methods with compile-time checks

### Testability

**Can test query builder in isolation:**
```swift
func testQueryBuilderFiltersHiddenEntries() throws {
    let query = TimelineEntryQuery()
        .forProject(testProjectId)
        .visibleOnly()

    let sql = query.buildSQL()  // Expose for testing
    XCTAssertTrue(sql.contains("display_in_timeline = 1"))
}
```

## Migration Strategy

### Phase 1: Create Builder

1. Add `TimelineEntryQuery` class to Repositories.swift
2. Implement chainable methods
3. Add unit tests for builder

### Phase 2: Refactor One Function at a Time

**Order (least risky first):**
1. `byTranscript()` (low usage)
2. `search()` (low usage)
3. `getEntriesAfterCursor()` (high usage - thorough testing)
4. Consider consolidating other functions

**Process per function:**
1. Replace implementation with query builder
2. Run existing unit tests
3. Add integration test
4. Deploy and monitor
5. Move to next function

### Phase 3: Remove Duplicates

1. Delete unused `entriesAfterCursor()` in Repositories
2. Consolidate similar functions (e.g., `recentFeed()` and `recentByProject()`)
3. Update documentation

## Testing

### Unit Tests

**Query builder tests:**
```swift
func testVisibleOnlyFilter() throws {
    let entries = TimelineEntryQuery()
        .forProject(testProjectId)
        .visibleOnly()
        .fetch()

    XCTAssertTrue(entries.allSatisfy { $0.displayInTimeline == 1 })
}

func testCursorPagination() throws {
    let cursor = EntryCursor(timestamp: 100, createdAt: 50, id: "abc")
    let entries = TimelineEntryQuery()
        .forProject(testProjectId)
        .afterCursor(cursor)
        .fetch()

    XCTAssertTrue(entries.allSatisfy {
        $0.timestamp > 100 ||
        ($0.timestamp == 100 && $0.createdAt > 50) ||
        ($0.timestamp == 100 && $0.createdAt == 50 && $0.id > "abc")
    })
}
```

### Integration Tests

**Timeline loading:**
```swift
func testTimelineLoadingWithBuilder() async throws {
    // Simulate project switch
    await conversationMonitor.switchProject(testProjectId)

    // Let timeline load
    try await Task.sleep(nanoseconds: 1_000_000_000)

    // Verify only visible entries loaded
    let timeline = await conversationMonitor.timeline
    XCTAssertTrue(timeline.allSatisfy { $0.displayInTimeline == 1 })
}
```

### Performance

**Benchmark:** Ensure no regression
```swift
func testQueryBuilderPerformance() throws {
    measure {
        for _ in 0..<100 {
            _ = try TimelineEntryQuery()
                .forProject(testProjectId)
                .visibleOnly()
                .fetch()
        }
    }
}
```

## Rollback

**Can revert to old implementation if issues:**
```bash
git revert <query-builder-commit-hash>
```

**Migration is incremental:**
- Refactor one function at a time
- Each function is separate commit
- Can revert individual functions if needed

## Future Enhancements

### Async Queries

```swift
func fetch() async throws -> [TranscriptEntry] {
    // Use async database access
}
```

### Query Caching

```swift
func fetch(cache: Bool = false) throws -> [TranscriptEntry] {
    if cache, let cached = queryCache[buildKey()] {
        return cached
    }
    let results = try executeQuery()
    if cache {
        queryCache[buildKey()] = results
    }
    return results
}
```

### Query Debugging

```swift
func explain() -> String {
    // Return EXPLAIN QUERY PLAN for debugging
}

func toSQL() -> String {
    // Return SQL string for inspection
}
```

## Related

- Source analysis: `build/notes/todo-support/P1-QUERY-CENTRALIZE-source-analysis.md`
- Filter investigation: `build/notes/todo-support/P0-TIMELINE-FILTERS-investigation.md`
- Comprehensive review: `/tmp/timeline-summarization-comprehensive-review-package.md`
