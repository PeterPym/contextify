---
todo_id: P0-TIMELINE-FILTERS
title: Timeline Filter Bypasses - Implementation Plan
type: plan
date: 2025-11-22
status: active
description: Complete implementation plan for fixing display_in_timeline filter bypasses in incremental updates, transcript view, and search
---

# Timeline Filter Bypasses - Implementation Plan

## Overview

**Problem:** Hidden entries (`display_in_timeline = 0`) appearing in timeline UI

**Root causes:** Three SQL queries missing `AND display_in_timeline = 1` filter

**Impact:** User sees thinking blocks with hallucinated summaries during normal app use

**Effort:** 2-4 hours (including tests)

## Implementation Details

### Fix 1: Incremental Updates (CRITICAL - User-Visible)

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`
**Function:** `getEntriesAfterCursor(projectId:after:)`
**Lines:** ~2085-2108

**Change:**
```swift
public func getEntriesAfterCursor(projectId: String, after cursor: EntryCursor?) throws -> [TranscriptEntry] {
  let pool = try dbManager.pool
  return try pool.read { db in
    if let c = cursor {
      return try TranscriptEntry.fetchAll(db, sql: """
        SELECT * FROM transcript_entries
         WHERE project_id = :pid
           AND display_in_timeline = 1  -- ADD THIS LINE
           AND (
                timestamp > :ts
             OR (timestamp = :ts AND created_at > :ca)
             OR (timestamp = :ts AND created_at = :ca AND id > :id)
           )
         ORDER BY timestamp ASC, created_at ASC, id ASC
      """, arguments: ["pid": projectId, "ts": c.timestamp, "ca": c.createdAt, "id": c.id])
    } else {
      // Initial load without cursor
      return try TranscriptEntry.fetchAll(db, sql: """
        SELECT * FROM transcript_entries
         WHERE project_id = :pid
           AND display_in_timeline = 1  -- ADD THIS LINE
         ORDER BY timestamp ASC, created_at ASC, id ASC
      """, arguments: ["pid": projectId])
    }
  }
}
```

**Impact:** Stops hidden entries from appearing during incremental timeline updates (when new entries arrive)

---

### Fix 2: Single Transcript View

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift`
**Function:** `byTranscript(_:afterTimestamp:)`
**Lines:** ~363-371

**Change:**
```swift
public func byTranscript(_ transcriptId: String, afterTimestamp: Int? = nil) throws -> [TranscriptEntry] {
  try db.read { db in
    var query = TranscriptEntry
      .filter(Column("transcript_id") == transcriptId)
      .filter(Column("display_in_timeline") == 1)  // ADD THIS LINE
    if let after = afterTimestamp {
      query = query.filter(Column("timestamp") > after)
    }
    return try query.order(Column("timestamp").asc).fetchAll(db)
  }
}
```

**Impact:** Stops hidden entries from appearing when viewing a specific transcript

---

### Fix 3: Search Results

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift`
**Function:** `search(content:projectId:)`
**Lines:** ~373-381

**Change:**
```swift
public func search(content: String, projectId: String? = nil) throws -> [TranscriptEntry] {
  try db.read { db in
    var query = TranscriptEntry
      .filter(Column("content").like("%\(content)%"))
      .filter(Column("display_in_timeline") == 1)  // ADD THIS LINE
    if let projectId = projectId {
      query = query.filter(Column("project_id") == projectId)
    }
    return try query.order(Column("timestamp").desc).fetchAll(db)
  }
}
```

**Impact:** Stops hidden entries from appearing in search results

---

## Testing Strategy

### Unit Tests

Add to `ContextifyTests/`:

```swift
func testIncrementalUpdateFiltersHiddenEntries() async throws {
    // Insert thinking-only entry with display_in_timeline = 0
    let hiddenEntry = TranscriptEntry(
        id: UUID().uuidString,
        transcriptId: testTranscriptId,
        projectId: testProjectId,
        kind: "assistant",
        displayInTimeline: 0,  // Hidden
        content: "The user wants... Let me do...",
        timestamp: Int(Date().timeIntervalSince1970)
    )
    try await orchestrator.insertEntry(hiddenEntry)

    // Fetch entries after cursor
    let cursor = EntryCursor(timestamp: 0, createdAt: 0, id: "")
    let entries = try orchestrator.getEntriesAfterCursor(projectId: testProjectId, after: cursor)

    // Verify hidden entry NOT included
    XCTAssertFalse(entries.contains { $0.id == hiddenEntry.id },
                   "Hidden entry should not appear in incremental updates")
}

func testByTranscriptFiltersHiddenEntries() throws {
    // Similar test for byTranscript()
}

func testSearchFiltersHiddenEntries() throws {
    // Similar test for search()
}
```

### Manual Testing

**Test scenario 1: Project switching**
1. Open app with existing project
2. Switch to different project in tab bar
3. Let new transcript entries arrive
4. Verify NO thinking blocks appear in timeline
5. Check logs for "Incremental update appended X entries"

**Test scenario 2: No regressions**
1. Create normal conversation with visible entries
2. Verify they all appear in timeline
3. Verify timeline loads normally
4. Check that all expected entries are present

---

## Success Metrics

**Immediate (after deployment):**
- [ ] Zero hidden entries appear in main timeline UI
- [ ] Zero hidden entries appear in transcript detail view
- [ ] Zero hidden entries appear in search results
- [ ] Timeline still loads normally (no performance regression)

**Within 1 day:**
- [ ] No user-visible bugs from filter changes
- [ ] Log monitoring shows expected behavior

---

## Rollback Plan

**All changes are single-commit reverts, no schema changes:**

```bash
# If incremental filter breaks timeline
git revert <incremental-filter-commit-hash>

# If all fixes break something
git revert <all-commits> --no-commit
git commit -m "Rollback timeline filter fixes"
```

**No data migration needed** - database regenerates frequently in preproduction.
