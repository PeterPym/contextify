# P0 Quick-Fix List - Immediate Action Required

**Date:** 2025-11-23
**Total Effort:** ~3 hours
**Impact:** Fixes user-visible bugs, prevents data inconsistency

## Overview

This document contains ONLY the P0 (critical) fixes that should be implemented immediately. Each fix is self-contained and can be done independently.

---

## Fix #1: Add display_in_timeline Filter to byTranscript() ⚠️

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift:363`
**Effort:** 5 minutes
**Bug:** Timeline shows hidden entries when loading by transcript

### Current Code

```swift
public func byTranscript(_ transcriptId: String, afterTimestamp: Int? = nil) throws -> [TranscriptEntry] {
  try db.read { db in
    var query = TranscriptEntry.filter(Column("transcript_id") == transcriptId)
    if let after = afterTimestamp {
      query = query.filter(Column("timestamp") > after)
    }
    return try query.order(Column("timestamp").asc).fetchAll(db)
  }
}
```

### Fixed Code

```swift
public func byTranscript(_ transcriptId: String, afterTimestamp: Int? = nil) throws -> [TranscriptEntry] {
  try db.read { db in
    var query = TranscriptEntry
      .filter(Column("transcript_id") == transcriptId)
      .filter(Column("display_in_timeline") == 1)  // ← ADD THIS LINE
    if let after = afterTimestamp {
      query = query.filter(Column("timestamp") > after)
    }
    return try query.order(Column("timestamp").asc).fetchAll(db)
  }
}
```

### Test

```bash
# After fix, verify no hidden entries are returned
sqlite3 ~/Library/Application\ Support/Contextify/contextify.db \
  "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = 'XXX' AND display_in_timeline = 0"
# Should return a count > 0 if hidden entries exist

# Then test byTranscript doesn't return them
# (requires app testing - hidden entries should NOT appear)
```

---

## Fix #2: Add display_in_timeline Filter to search() ⚠️

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift:373`
**Effort:** 5 minutes
**Bug:** Search results include hidden entries

### Current Code

```swift
public func search(content: String, projectId: String? = nil) throws -> [TranscriptEntry] {
  try db.read { db in
    var query = TranscriptEntry.filter(Column("content").like("%\(content)%"))
    if let projectId = projectId {
      query = query.filter(Column("project_id") == projectId)
    }
    return try query.order(Column("timestamp").desc).fetchAll(db)
  }
}
```

### Fixed Code

```swift
public func search(content: String, projectId: String? = nil) throws -> [TranscriptEntry] {
  try db.read { db in
    var query = TranscriptEntry
      .filter(Column("content").like("%\(content)%"))
      .filter(Column("display_in_timeline") == 1)  // ← ADD THIS LINE
    if let projectId = projectId {
      query = query.filter(Column("project_id") == projectId)
    }
    return try query.order(Column("timestamp").desc).fetchAll(db)
  }
}
```

---

## Fix #3: Add display_in_timeline Filter to getEntriesAfterCursor() ⚠️

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:2091-2105`
**Effort:** 10 minutes
**Bug:** Incremental timeline updates include hidden entries

### Current Code

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

### Fixed Code

```swift
public func getEntriesAfterCursor(projectId: String, after cursor: EntryCursor?) throws -> [TranscriptEntry] {
  let pool = try dbManager.pool
  return try pool.read { db in
    if let c = cursor {
      return try TranscriptEntry.fetchAll(db, sql: """
        SELECT * FROM transcript_entries
         WHERE project_id = :pid
           AND display_in_timeline = 1
           AND (
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
           AND display_in_timeline = 1
         ORDER BY timestamp ASC, created_at ASC, id ASC
      """, arguments: ["pid": projectId])
    }
  }
}
```

### Note

**BETTER FIX:** This method should delegate to Repository.entriesAfterCursor() instead of duplicating the query. However, for a quick P0 fix, adding the filter inline is acceptable. File a P1 task to eliminate the duplication.

---

## Fix #4: Refresh Unread Counts After markProjectViewed() ⚠️

**File:** `Contextify/Contextify/ProjectSwitcherState.swift:608-619`
**Effort:** 10 minutes
**Bug:** Unread counts don't update after viewing a project

### Current Code

```swift
Task.detached(priority: .userInitiated) { [orchestrator] in
  let logger = Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")
  do {
    // Mark project as selected and viewed
    try orchestrator.markProjectSelected(projectId: projectId)
    let timestamp = ISO8601Z.string(from: Date())
    try orchestrator.markProjectViewed(projectId: projectId, timestamp: timestamp)
    logger.debug("✅ Project metadata updated in database: \(projectId, privacy: .public)")
  } catch {
    logger.error("Failed to update project metadata: \(error.localizedDescription)")
  }
}
```

### Fixed Code

```swift
Task.detached(priority: .userInitiated) { [weak self, orchestrator] in
  let logger = Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")
  do {
    // Mark project as selected and viewed
    try orchestrator.markProjectSelected(projectId: projectId)
    let timestamp = ISO8601Z.string(from: Date())
    try orchestrator.markProjectViewed(projectId: projectId, timestamp: timestamp)
    logger.debug("✅ Project metadata updated in database: \(projectId, privacy: .public)")

    // ✅ FIX: Refresh unread counts to reflect the viewed state
    await MainActor.run {
      Task { [weak self] in
        await self?.refreshUnreadCounts(for: [projectId])
      }
    }
  } catch {
    logger.error("Failed to update project metadata: \(error.localizedDescription)")
  }
}
```

### Changes

1. Added `[weak self]` to task capture list
2. After DB update, refresh unread counts for the specific project
3. Use MainActor.run to safely call @MainActor method from detached task

### Test

```swift
// Manual test
1. Open app with project that has unread entries
2. Note the unread count badge (should be > 0)
3. Switch to that project
4. Immediately check the badge - should update to 0
5. WITHOUT this fix, badge stays at old value until manual refresh
```

---

## Fix #5: BETTER FIX - Make markProjectViewed Return Fresh State

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:1770`
**Effort:** 20 minutes
**Bug:** Same as #4, but proper architectural fix

### Current Code

```swift
public func markProjectViewed(projectId: String, timestamp: String) throws {
  let pool = try dbManager.pool
  try pool.write { db in
    try projectVisitsRepository.markViewed(db: db, projectId: projectId, timestamp: timestamp)
  }
}
```

### Fixed Code

```swift
public func markProjectViewed(projectId: String, timestamp: String) throws -> ProjectVisit {
  let pool = try dbManager.pool
  return try pool.write { db in
    try projectVisitsRepository.markViewed(db: db, projectId: projectId, timestamp: timestamp)
    // Return fresh visit state immediately
    return try projectVisitsRepository.getVisit(projectId: projectId) ?? ProjectVisit(projectId: projectId, unreadCount: 0)
  }
}
```

### Update Caller

```swift
// ProjectSwitcherState.swift
Task.detached(priority: .userInitiated) { [weak self, orchestrator] in
  do {
    try orchestrator.markProjectSelected(projectId: projectId)
    let timestamp = ISO8601Z.string(from: Date())

    // ✅ Get fresh state from the write operation
    let updatedVisit = try orchestrator.markProjectViewed(projectId: projectId, timestamp: timestamp)

    // ✅ Update observable state with fresh value (no separate refresh needed)
    await MainActor.run {
      self?.unreadCounts[projectId] = updatedVisit.unreadCount
    }
  } catch {
    logger.error("Failed to update project metadata: \(error.localizedDescription)")
  }
}
```

### Why This Is Better

- No separate refresh query (more efficient)
- State guaranteed to match database (no race conditions)
- Clearer contract (write returns updated state)
- Easier to test

**Recommendation:** Use Fix #5 instead of Fix #4 if time permits.

---

## Fix #6: Verify display_in_timeline Filter in All Entry Queries

**Effort:** 30 minutes
**Action:** Audit all remaining queries

### Queries to Check

Run this command to find all queries that might be missing the filter:

```bash
cd /home/user/contextify
rg "SELECT.*FROM transcript_entries" --type swift -n app/Sources/ContextifyCore Contextify/Contextify | \
  grep -v "display_in_timeline"
```

### For Each Result

1. **Determine if filter is needed:**
   - ✅ Need filter: User-facing queries (timeline, search, feed)
   - ❌ Skip filter: Internal queries (embeddings, stats, maintenance)

2. **Add filter if needed:**
   ```sql
   WHERE ... AND display_in_timeline = 1
   ```

3. **Document exceptions:**
   ```swift
   // NOTE: Intentionally querying ALL entries (including hidden) for embedding generation
   let entries = try TranscriptEntry.fetchAll(db, sql: "SELECT * FROM transcript_entries WHERE ...")
   ```

### High-Priority Queries to Check

| File | Method | User-Facing? | Action |
|------|--------|--------------|--------|
| Repositories.swift:363 | byTranscript | ✅ Yes | ✅ Fix #1 |
| Repositories.swift:373 | search | ✅ Yes | ✅ Fix #2 |
| TranscriptOrchestrator.swift:2091 | getEntriesAfterCursor | ✅ Yes | ✅ Fix #3 |
| BatchEmbeddingView.swift:347-355 | Stats queries | ❌ No | ✅ Skip (stats need all) |
| EmbeddingRepository.swift:75 | getEntriesWithoutEmbeddings | ❌ No | ✅ Skip (embedding needs all) |
| ProjectStatsService.swift:95 | Entry counts | ❌ No | ✅ Skip (stats need all) |

---

## Testing Checklist

After applying fixes, verify:

- [ ] **Fix #1:** Timeline by transcript doesn't show hidden entries
- [ ] **Fix #2:** Search results don't include hidden entries
- [ ] **Fix #3:** Incremental updates don't include hidden entries
- [ ] **Fix #4/5:** Unread counts update immediately after viewing project
- [ ] **Regression:** Existing features still work (nothing broken)
- [ ] **Database:** Schema unchanged (no migrations needed)

---

## Effort Summary

| Fix | File | Lines Changed | Effort |
|-----|------|---------------|--------|
| #1 | Repositories.swift | 1 line | 5 min |
| #2 | Repositories.swift | 1 line | 5 min |
| #3 | TranscriptOrchestrator.swift | 2 lines | 10 min |
| #4 | ProjectSwitcherState.swift | 7 lines | 10 min |
| #5 (alternative to #4) | TranscriptOrchestrator.swift + ProjectSwitcherState.swift | 10 lines | 20 min |
| #6 | Various (audit) | N/A | 30 min |

**Total (using Fix #4):** ~60 minutes
**Total (using Fix #5):** ~70 minutes

---

## After Fixes - Create Tests

Once fixes are applied, add regression tests:

```swift
// RepositoriesTests.swift
func testByTranscriptExcludesHiddenEntries() throws {
  // Given: transcript with mixed entries
  let transcriptId = "test-transcript"
  try createEntry(transcriptId: transcriptId, displayInTimeline: 1)
  try createEntry(transcriptId: transcriptId, displayInTimeline: 0) // hidden

  // When
  let entries = try repository.byTranscript(transcriptId)

  // Then
  XCTAssertEqual(entries.count, 1, "Should only return visible entries")
  XCTAssertTrue(entries.allSatisfy { $0.displayInTimeline == 1 })
}

func testSearchExcludesHiddenEntries() throws {
  // Similar test for search()
}

// ProjectSwitcherStateTests.swift
func testMarkProjectViewedUpdatesUnreadCounts() async throws {
  // Given: project with unread entries
  let state = ProjectSwitcherState()
  state.unreadCounts[projectId] = 5

  // When
  await state.selectProject(projectId)

  // Then
  XCTAssertEqual(state.unreadCounts[projectId], 0, "Unread count should reset to 0")
}
```

---

## Priority

**All fixes are P0** - implement ASAP, ideally within 1-2 days.

**Order of implementation:**
1. Fixes #1-3 (SQL filters) - prevents bad data from reaching UI
2. Fix #5 (state sync) - fixes UX bug
3. Fix #6 (audit) - ensures no other missing filters

---

**End of P0 Quick-Fix List**
