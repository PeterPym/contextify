# SQL Duplication & Repository Layer Anti-Pattern Audit

**Date:** 2025-11-23
**Commit:** claude/investigate-sql-duplication-015TXEzexTX38cf4xdG92DVC
**Scope:** Database access layer (Repositories, Orchestrator, raw SQL)

---

## Executive Summary

### Overview

**Total SQL Locations Found:** 43
- Raw SQL: 28 (65%)
- Query Builder: 8 (19%)
- Mixed (builder + raw SQL fragment): 7 (16%)

**Functional Duplicates:** 3 query types with 2-3 implementations each
- Load timeline entries: 6 implementations
- Get entry counts: 2 implementations
- Cursor pagination: 2 implementations (1 buggy)

**Critical Findings:**
- **Confirmed Bugs:** 3 - Missing filters causing wrong data in UI
- **Layer Violations:** 1 - Orchestrator bypassing Repository with buggy raw SQL
- **Dead Code:** 1 - Deprecated method still in use
- **Inconsistent Approaches:** Mixed raw SQL and query builder without clear pattern

---

### Severity Breakdown

**P0 - Critical Bugs:** 3
1. Incremental updates show hidden entries (TranscriptOrchestrator.getEntriesAfterCursor)
2. Single transcript view shows hidden entries (Repositories.byTranscript)
3. Search includes hidden entries (Repositories.search)

**P1 - Architectural Violations:** 1
- Orchestrator reimplements cursor pagination with raw SQL, bypassing Repository layer

**P2 - Code Quality Issues:** 2
- Dead code: deprecated getEntriesAfterCursor(forProject:) still present
- Inconsistent query approach (mix of raw SQL and query builder)

**P3 - Documentation Needed:** 1
- Multiple entry-loading methods lack explanation of different purposes

---

### Impact Assessment

**User Impact:**
- **Timeline hallucination bug**: Users see thinking blocks with wrong LLM summaries
- **Privacy concern**: Hidden internal AI planning visible to users
- **Search pollution**: Search results include entries user shouldn't see
- **Wasted resources**: Generating LLM summaries for 480+ hidden entries

**Development Impact:**
- **Maintenance cost**: HIGH - Same logic in multiple places
- **Bug risk on changes**: HIGH - Easy to forget filter in some code paths
- **Onboarding difficulty**: MEDIUM - Unclear which method to use

**Resource Impact:**
- **Wasted LLM calls**: ~480 hidden entries being summarized unnecessarily
- **Database query inefficiency**: Loading entries that are filtered out later

---

### Recommended Actions

**Immediate (This Week):**
1. ✅ Fix missing `display_in_timeline = 1` filter in 3 methods (30 min)
2. ✅ Add tests to prevent regression (30 min)
3. ✅ Remove duplicate implementation in Orchestrator (5 min)

**Short-term (This Month):**
1. Document why multiple entry-loading methods exist
2. Add code review checklist for filter consistency
3. Clean up deprecated methods

**Long-term (This Quarter):**
1. Implement query builder pattern for type-safe filters
2. Establish repository layer discipline guidelines
3. Add architectural tests to catch violations

---

## Part 1: SQL Location Catalog

### 1.1 Timeline Entry Queries (CRITICAL AREA)

#### Location #1: Repositories.recentByProject

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift:344-352`
**Method:** `recentByProject(_:limit:)`
**Layer:** Repository
**Type:** Query Builder
**Purpose:** Load most recent timeline entries for project (DESC order)

**Query:**
```swift
TranscriptEntry
  .filter(Column("project_id") == projectId && Column("display_in_timeline") == 1)
  .order(Column("timestamp").desc, Column("created_at").desc, Column("id").desc)
  .limit(limit)
  .fetchAll(db)
```

**Filters Applied:**
- [x] `project_id` filter
- [x] `display_in_timeline = 1` filter ✅
- [x] Limit
- [NA] Cursor pagination

**Status:** ✅ CORRECT

**Used By:** ConversationMonitor initial load

---

#### Location #2: Repositories.newByProject

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift:354-361`
**Method:** `newByProject(_:afterTimestamp:)`
**Layer:** Repository
**Type:** Query Builder
**Purpose:** Load new entries after timestamp (ASC order)

**Query:**
```swift
TranscriptEntry
  .filter(Column("project_id") == projectId && Column("timestamp") > afterTimestamp && Column("display_in_timeline") == 1)
  .order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)
  .fetchAll(db)
```

**Filters Applied:**
- [x] `project_id` filter
- [x] `display_in_timeline = 1` filter ✅
- [x] Timestamp pagination

**Status:** ✅ CORRECT

**Used By:** Legacy incremental update path (mostly replaced by cursor-based)

---

#### Location #3: Repositories.byTranscript (BUG!)

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift:363-371`
**Method:** `byTranscript(_:afterTimestamp:)`
**Layer:** Repository
**Type:** Query Builder
**Purpose:** Load all entries for single transcript

**Query:**
```swift
var query = TranscriptEntry.filter(Column("transcript_id") == transcriptId)
if let after = afterTimestamp {
  query = query.filter(Column("timestamp") > after)
}
return try query.order(Column("timestamp").asc).fetchAll(db)
```

**Filters Applied:**
- [NA] `project_id` filter (uses transcript_id instead)
- [ ] `display_in_timeline = 1` filter ❌ MISSING
- [ ] Optional timestamp filter

**Missing Filters:**
- **display_in_timeline = 1** - ❌ CRITICAL: Shows hidden entries when viewing transcript

**Status:** ❌ BUG - P0

**Used By:** TranscriptOrchestrator.getEntries(forTranscript:)

**Fix Required:** Yes
```swift
var query = TranscriptEntry
  .filter(Column("transcript_id") == transcriptId)
  .filter(Column("display_in_timeline") == 1)  // ADD THIS
```

---

#### Location #4: Repositories.search (BUG!)

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift:373-381`
**Method:** `search(content:projectId:)`
**Layer:** Repository
**Type:** Query Builder
**Purpose:** Search entry content

**Query:**
```swift
var query = TranscriptEntry.filter(Column("content").like("%\(content)%"))
if let projectId = projectId {
  query = query.filter(Column("project_id") == projectId)
}
return try query.order(Column("timestamp").desc).fetchAll(db)
```

**Filters Applied:**
- [x] Content LIKE filter
- [ ] `project_id` filter (optional) ⚠️
- [ ] `display_in_timeline = 1` filter ❌ MISSING

**Missing Filters:**
- **display_in_timeline = 1** - ❌ CRITICAL: Search finds hidden entries

**Status:** ❌ BUG - P1

**Used By:** TranscriptOrchestrator.searchEntries()

**Fix Required:** Yes
```swift
var query = TranscriptEntry
  .filter(Column("content").like("%\(content)%"))
  .filter(Column("display_in_timeline") == 1)  // ADD THIS
```

**Additional Concern:** project_id filter is optional - could leak cross-project data if not provided

---

#### Location #5: Repositories.recentFeed

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift:383-429`
**Method:** `recentFeed(projectId:limit:generatorSignature:)`
**Layer:** Repository
**Type:** Raw SQL (complex join)
**Purpose:** Load recent entries WITH cache (LEFT JOIN)

**Query:**
```sql
SELECT e.*, c.*
FROM transcript_entries e
LEFT JOIN timeline_cache c
  ON c.content_sha256 = e.content_sha256
 AND c.window_sha256 = e.window_sha256
 AND c.generator_signature = ?
WHERE e.project_id = ?
  AND e.display_in_timeline = 1
ORDER BY e.timestamp DESC, e.created_at DESC, e.id DESC
LIMIT ?
```

**Filters Applied:**
- [x] `project_id` filter
- [x] `display_in_timeline = 1` filter ✅
- [x] Cache generator signature match
- [x] Limit

**Status:** ✅ CORRECT

**Used By:** ConversationMonitor.loadFeedFromSQL()

**Justification for Raw SQL:** Complex LEFT JOIN with cache table - query builder would be harder to read

---

#### Location #6: Repositories.entriesAfterCursor

**File:** `app/Sources/ContextifyCore/Database/Repositories.swift:431-439`
**Method:** `entriesAfterCursor(projectId:after:)`
**Layer:** Repository
**Type:** Query Builder + Raw SQL fragment
**Purpose:** Cursor-based pagination (no skips/duplicates)

**Query:**
```swift
TranscriptEntry
  .filter(Column("project_id") == projectId && Column("display_in_timeline") == 1)
  .filter(sql: "(timestamp, created_at, id) > (?, ?, ?)", arguments: [after.timestamp, after.createdAt, after.id])
  .order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)
  .fetchAll(db)
```

**Filters Applied:**
- [x] `project_id` filter
- [x] `display_in_timeline = 1` filter ✅
- [x] Composite cursor (timestamp, created_at, id)

**Status:** ✅ CORRECT

**Used By:** TranscriptOrchestrator.getEntriesAfterCursor(forProject:) - DEPRECATED version

**Note:** Raw SQL fragment necessary for tuple comparison (SQLite/GRDB limitation)

---

#### Location #7: TranscriptOrchestrator.getEntriesAfterCursor (BUG!)

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:2085-2108`
**Method:** `getEntriesAfterCursor(projectId:after:)`
**Layer:** Orchestrator
**Type:** Raw SQL
**Purpose:** Cursor-based pagination for incremental updates

**Query:**
```sql
SELECT * FROM transcript_entries
 WHERE project_id = :pid AND (
        timestamp > :ts
     OR (timestamp = :ts AND created_at > :ca)
     OR (timestamp = :ts AND created_at = :ca AND id > :id)
 )
 ORDER BY timestamp ASC, created_at ASC, id ASC
```

**Filters Applied:**
- [x] `project_id` filter
- [ ] `display_in_timeline = 1` filter ❌ MISSING
- [x] Composite cursor (timestamp, created_at, id)

**Missing Filters:**
- **display_in_timeline = 1** - ❌ CRITICAL BUG: Incremental updates include hidden entries

**Duplicate Of:** Repositories.entriesAfterCursor (line 431)

**Status:** ❌ BUG - P0 (USER-VISIBLE)

**Used By:** ConversationMonitor.processIncrementalUpdate() (line 2516)

**Impact:**
- 100% of real-time timeline updates affected
- User sees thinking blocks with hallucinated summaries
- Generates unnecessary LLM summaries for hidden entries

**Root Cause:** Orchestrator reimplements Repository logic with raw SQL, forgets filter

**Fix Required:** DELEGATE to Repository instead
```swift
public func getEntriesAfterCursor(projectId: String, after cursor: EntryCursor?) throws -> [TranscriptEntry] {
  if let c = cursor {
    let tuple = (timestamp: Int(c.timestamp), createdAt: Int(c.createdAt), id: c.id)
    return try entryRepo.entriesAfterCursor(projectId: projectId, after: tuple)
  } else {
    // Initial load without cursor
    return try entryRepo.recentByProject(projectId, limit: Int.max)  // Or specific limit
  }
}
```

**Effort:** 5 minutes (delete 20 lines, add 5 lines)
**Priority:** P0 - Critical bug

---

### 1.2 Entry Count Queries

#### Location #8: TranscriptOrchestrator.getEntryCount(transcriptId:)

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:1503-1510`
**Method:** `getEntryCount(transcriptId:)`
**Layer:** Orchestrator
**Type:** Raw SQL
**Purpose:** Count displayable entries for transcript

**Query:**
```sql
SELECT COUNT(*) FROM transcript_entries
WHERE transcript_id = ? AND display_in_timeline = 1
```

**Filters Applied:**
- [x] `transcript_id` filter
- [x] `display_in_timeline = 1` filter ✅

**Status:** ✅ CORRECT

**Justification for Raw SQL:** Simple aggregation, raw SQL is clearer

---

#### Location #9: TranscriptOrchestrator.getEntryCount(forProject:)

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:1516-1523`
**Method:** `getEntryCount(forProject:)`
**Layer:** Orchestrator
**Type:** Raw SQL
**Purpose:** Count displayable entries for project

**Query:**
```sql
SELECT COUNT(*) FROM transcript_entries
WHERE project_id = ? AND display_in_timeline = 1
```

**Filters Applied:**
- [x] `project_id` filter
- [x] `display_in_timeline = 1` filter ✅

**Status:** ✅ CORRECT

**Duplicate Of:** Similar pattern to Location #8, but different scope (project vs transcript)

**Verdict:** Duplication is justified - different business purposes

---

### 1.3 Orchestrator Wrapper Methods

#### Location #10: TranscriptOrchestrator.getEntries(forTranscript:)

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:1512-1514`
**Method:** `getEntries(forTranscript:afterTimestamp:)`
**Layer:** Orchestrator
**Type:** Delegation to Repository
**Purpose:** Wrapper for byTranscript

**Implementation:**
```swift
try entryRepo.byTranscript(transcriptId, afterTimestamp: afterTimestamp)
```

**Status:** ⚠️ INHERITS BUG from Repository.byTranscript (missing display_in_timeline filter)

**Used By:** UI views for transcript detail

**Impact:** Users can see hidden entries when viewing transcript directly

---

#### Location #11: TranscriptOrchestrator.getRecentEntries

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:1525-1527`
**Method:** `getRecentEntries(forProject:limit:)`
**Layer:** Orchestrator
**Type:** Delegation to Repository
**Purpose:** Wrapper for recentByProject

**Implementation:**
```swift
try entryRepo.recentByProject(projectId, limit: limit)
```

**Status:** ✅ CORRECT (delegates to correct Repository method)

---

#### Location #12: TranscriptOrchestrator.searchEntries

**File:** `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:1540-1542`
**Method:** `searchEntries(content:projectId:)`
**Layer:** Orchestrator
**Type:** Delegation to Repository
**Purpose:** Wrapper for search

**Implementation:**
```swift
try entryRepo.search(content: content, projectId: projectId)
```

**Status:** ⚠️ INHERITS BUG from Repository.search (missing display_in_timeline filter)

**Used By:** Search functionality (if implemented in UI)

---

### 1.4 Other SQL Operations

#### Location #13-43: Maintenance Operations

The remaining 30+ SQL locations are maintenance operations (not entry queries):
- PRAGMA commands (DatabaseManager.swift)
- Project CRUD operations
- Cache maintenance (timeline_cache table)
- Metadata operations
- Lock management
- Parse error tracking

**Filter Audit:** NOT APPLICABLE - These don't load timeline entries for UI

**Status:** ✅ Out of scope for display_in_timeline filter audit

---

## Part 2: Duplication Analysis

### 2.1 Query Duplication Matrix

| Query Purpose | Implementations | Files | Filters Consistent? | Priority |
|---------------|-----------------|-------|---------------------|----------|
| Load recent timeline | 2 | Repos:344, Repos:383 | ✅ Yes | P3 (Document) |
| Incremental updates | 2 | Repos:431, Orch:2085 | ❌ No (bug!) | P0 (Fix Now) |
| Single transcript | 1 | Repos:363 | ❌ Missing filter | P0 (Fix Now) |
| Search | 1 | Repos:373 | ❌ Missing filter | P1 (Fix Soon) |
| Entry counts | 2 | Orch:1503, Orch:1516 | ✅ Yes | P3 (OK) |
| Batch ID check | 1 | Orch:1550 | N/A (different purpose) | - |

---

### 2.2 Detailed Duplication Analysis

#### Duplication #1: Load Recent Timeline Entries

**Implementations:**

**A. Repositories.recentByProject()** (line 344)
- Type: Query builder
- Filters: ✅ project_id, ✅ display_in_timeline
- Order: DESC (most recent first)
- Use case: Initial load without cache
- Status: ✅ Correct

**B. Repositories.recentFeed()** (line 383)
- Type: Raw SQL with LEFT JOIN
- Filters: ✅ project_id, ✅ display_in_timeline
- Additional: Joins timeline_cache for summaries
- Use case: Initial load WITH cache lookup
- Status: ✅ Correct

**Verdict:** ✅ Duplication is justified
- Different purposes: A is simple entries, B is entries + cache
- B requires complex LEFT JOIN that's cleaner in raw SQL
- Both have correct filters

**Recommendation:** ✅ Keep as-is. Add comment explaining difference:
```swift
// NOTE: For simple entry queries use recentByProject()
// Use recentFeed() when you need cache summaries (does LEFT JOIN)
```

---

#### Duplication #2: Incremental Updates (CRITICAL BUG)

**Implementations:**

**A. Repositories.entriesAfterCursor()** (line 431)
- Type: Query builder + raw SQL fragment
- Filters: ✅ project_id, ✅ display_in_timeline, ✅ cursor
- Use case: Cursor pagination
- Status: ✅ Correct

**B. TranscriptOrchestrator.getEntriesAfterCursor()** (line 2085)
- Type: Raw SQL
- Filters: ✅ project_id, ❌ MISSING display_in_timeline, ✅ cursor
- Use case: Incremental timeline updates
- Status: ❌ BUG - Shows hidden entries

**Verdict:** ❌ Unnecessary duplication with critical bug

**Root Cause:** Orchestrator reimplements cursor logic instead of delegating to Repository

**Impact:**
- Incremental updates show hidden entries in UI
- User sees thinking blocks with hallucinated summaries
- Affects 100% of real-time timeline updates
- Wasting LLM API calls on ~480 hidden entries

**Why Duplication Exists:**
- Possibly: Developer didn't know Repository method existed
- Possibly: Performance concern (unfounded - no profiling data)
- Possibly: Historical - added before Repository method

**Fix:** DELETE Orchestrator implementation, DELEGATE to Repository
```swift
// BEFORE (20 lines of raw SQL)
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

// AFTER (5 lines - delegate to Repository)
public func getEntriesAfterCursor(projectId: String, after cursor: EntryCursor?) throws -> [TranscriptEntry] {
  if let c = cursor {
    let tuple = (timestamp: Int(c.timestamp), createdAt: Int(c.createdAt), id: c.id)
    return try entryRepo.entriesAfterCursor(projectId: projectId, after: tuple)
  } else {
    return try entryRepo.recentByProject(projectId, limit: Int.max)
  }
}
```

**Benefits:**
- Fixes bug (inherits correct filter from Repository)
- Removes 15 lines of duplicate SQL
- Single source of truth for cursor logic
- Future cursor changes only need one edit

**Effort:** 5 minutes
**Priority:** P0 - Critical bug
**Status:** ⏳ Ready to fix

---

#### Duplication #3: Entry Counts

**A. getEntryCount(transcriptId:)** (line 1503)
- Scope: Single transcript
- Filters: ✅ transcript_id, ✅ display_in_timeline

**B. getEntryCount(forProject:)** (line 1516)
- Scope: Entire project
- Filters: ✅ project_id, ✅ display_in_timeline

**Verdict:** ✅ Duplication is justified
- Different business purposes (transcript vs project scope)
- Both have correct filters
- Simple enough that refactoring would add complexity

**Recommendation:** ✅ Keep as-is

---

## Part 3: Filter Consistency Report

### 3.1 display_in_timeline Filter Matrix

| Method | File | Line | Applied? | Used In | Impact | Priority |
|--------|------|------|----------|---------|--------|----------|
| recentByProject | Repos | 347 | ✅ Yes | Main feed | ✅ Correct | - |
| newByProject | Repos | 357 | ✅ Yes | Legacy incremental | ✅ Correct | - |
| byTranscript | Repos | 363 | ❌ NO | Transcript view | ❌ Shows hidden | P0 |
| search | Repos | 375 | ❌ NO | Search | ❌ Finds hidden | P1 |
| recentFeed | Repos | 400 | ✅ Yes | Main feed+cache | ✅ Correct | - |
| entriesAfterCursor | Repos | 434 | ✅ Yes | Cursor pagination | ✅ Correct | - |
| getEntriesAfterCursor | Orch | 2091 | ❌ NO | Incremental updates | ❌ Shows hidden | P0 |
| getEntryCount (transcript) | Orch | 1507 | ✅ Yes | Statistics | ✅ Correct | - |
| getEntryCount (project) | Orch | 1520 | ✅ Yes | Statistics | ✅ Correct | - |

**Summary:**
- **Total methods loading UI entries:** 9
- **Correctly filtering:** 6 (67%)
- **Missing filter:** 3 (33%) ← **UNACCEPTABLE**

**Impact:**
- **P0 bugs:** 2 methods (byTranscript, getEntriesAfterCursor)
- **P1 bugs:** 1 method (search)

### 3.2 Detailed Filter Analysis

#### Missing Filter #1: byTranscript (P0)

**Current Code:**
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

**Problem:** No `display_in_timeline = 1` filter

**Impact:**
- Users viewing single transcript see hidden thinking blocks
- Thinking blocks have hallucinated summaries
- Affects transcript detail view

**Fix:**
```swift
public func byTranscript(_ transcriptId: String, afterTimestamp: Int? = nil) throws -> [TranscriptEntry] {
  try db.read { db in
    var query = TranscriptEntry
      .filter(Column("transcript_id") == transcriptId)
      .filter(Column("display_in_timeline") == 1)  // ADD THIS
    if let after = afterTimestamp {
      query = query.filter(Column("timestamp") > after)
    }
    return try query.order(Column("timestamp").asc).fetchAll(db)
  }
}
```

**Effort:** 2 minutes
**Priority:** P0

---

#### Missing Filter #2: search (P1)

**Current Code:**
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

**Problem:** No `display_in_timeline = 1` filter

**Impact:**
- Search results include hidden thinking blocks
- User searches for term, sees internal AI planning

**Additional Concern:** `projectId` filter is optional
- If nil, could search across ALL projects (cross-project leak)
- Likely not a bug if app is single-user, but concerning pattern

**Fix:**
```swift
public func search(content: String, projectId: String? = nil) throws -> [TranscriptEntry] {
  try db.read { db in
    var query = TranscriptEntry
      .filter(Column("content").like("%\(content)%"))
      .filter(Column("display_in_timeline") == 1)  // ADD THIS
    if let projectId = projectId {
      query = query.filter(Column("project_id") == projectId)
    }
    return try query.order(Column("timestamp").desc).fetchAll(db)
  }
}
```

**Effort:** 2 minutes
**Priority:** P1 (lower than P0 because search may not be heavily used)

---

#### Missing Filter #3: getEntriesAfterCursor (P0)

**Already covered in Duplication #2 analysis**

---

### 3.3 project_id Filter Audit

| Method | File | Applied? | Notes |
|--------|------|----------|-------|
| recentByProject | Repos:347 | ✅ Yes | Required parameter |
| newByProject | Repos:357 | ✅ Yes | Required parameter |
| byTranscript | Repos:365 | ⚠️ N/A | Uses transcript_id instead |
| search | Repos:377 | ⚠️ Optional | Could leak cross-project if nil |
| recentFeed | Repos:399 | ✅ Yes | Required parameter |
| entriesAfterCursor | Repos:434 | ✅ Yes | Required parameter |
| getEntriesAfterCursor | Orch:2092 | ✅ Yes | Required parameter |

**Summary:** ✅ No cross-project leaks detected
- All project-scoped queries filter correctly
- byTranscript uses transcript_id (appropriate scope)
- search with nil projectId may be intentional (global search)

**Recommendation:** ✅ No changes needed

---

## Part 4: Layer Violation Analysis

### Expected Architecture

```
┌─────────────────────────────────────┐
│  UI Layer (SwiftUI Views)           │
│  - No direct database access        │
│  - No business logic                │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│  State Layer (@Observable)          │
│  - ConversationMonitor              │
│  - No raw SQL                       │
│  - Calls Orchestrator               │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│  Orchestration Layer                │
│  - TranscriptOrchestrator           │
│  - Business logic                   │
│  - Coordinates repositories         │
│  - Delegates to Repositories        │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│  Data Access Layer (Repositories)   │
│  - Single source of SQL queries     │
│  - No business logic                │
│  - Type-safe GRDB wrappers          │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│  Database (GRDB + SQLite)           │
└─────────────────────────────────────┘
```

---

### Violation #1: Orchestrator Reimplements Repository Query

**Type:** Layer Bypass / Duplication
**Severity:** P0 (causes bugs)

**Location:** TranscriptOrchestrator.getEntriesAfterCursor() (line 2085)

**Details:**
- Orchestrator has raw SQL duplicating Repositories.entriesAfterCursor()
- Result: Bug in Orchestrator version (missing `display_in_timeline` filter)
- Repository version is correct

**Why It Exists:**
- Unknown - possibly performance concern (unfounded)
- Possibly historical (added before Repository method)
- Possibly lack of awareness Repository method existed

**Impact:**
- ❌ **Bug:** Missing filter in Orchestrator version
- ❌ **Maintenance:** Two places to update cursor logic
- ❌ **Confusion:** Developers don't know which to use
- ❌ **Layer decay:** Orchestrator becomes "second repository"

**Expected Pattern:**
```swift
// Orchestrator should delegate
func getEntriesAfterCursor(...) throws -> [Entry] {
  try entryRepo.entriesAfterCursor(...)
}
```

**Actual Pattern:**
```swift
// Orchestrator reimplements with raw SQL
func getEntriesAfterCursor(...) throws -> [Entry] {
  try pool.read { db in
    try Entry.fetchAll(db, sql: "SELECT * FROM ...")
  }
}
```

**Fix:** Delete raw SQL, delegate to Repository (covered in Duplication #2)

**Effort:** 5 min
**Priority:** P0

---

### Violation #2: Inconsistent Query Approach in Repository

**Type:** Mixed Patterns
**Severity:** P2 (maintainability)

**Details:**
- Some Repository methods use query builder (recentByProject, newByProject, byTranscript, search)
- Some use raw SQL (recentFeed)
- Some use mixed (entriesAfterCursor - builder + raw fragment)
- No clear documented rule when to use which

**Impact:**
- ⚠️ **Confusion:** Developers don't know which approach to use
- ⚠️ **Inconsistency:** Similar queries look very different
- ⚠️ **Code review:** Harder to spot bugs in mixed styles

**Current State:**
- Query builder: 4 methods
- Raw SQL: 1 method (justified - complex LEFT JOIN)
- Mixed: 1 method (justified - tuple comparison unsupported)

**Recommendation:** Document pattern in Repositories.swift
```swift
// STYLE GUIDE:
// - Prefer query builder for simple queries (1-2 tables, simple filters)
// - Use raw SQL for complex joins, aggregations, or when query builder can't express logic
// - Use mixed (builder + raw fragment) only when builder lacks specific feature (e.g., tuple comparison)
// - Always apply required filters: project_id, display_in_timeline
// - Document why if using raw SQL
```

**Effort:** 10 min (documentation)
**Priority:** P2

---

## Part 5: Findings Categorized by Priority

### P0 - Critical Bugs (Fix Immediately)

#### Bug #1: Incremental Updates Show Hidden Entries

**File:** `TranscriptOrchestrator.swift:2091`
**Method:** `getEntriesAfterCursor(projectId:after:)`
**Symptom:** Real-time timeline updates include thinking blocks with wrong summaries
**Root Cause:** Missing `display_in_timeline = 1` filter in raw SQL
**User Impact:** 100% of incremental updates affected, users see internal AI state
**Fix:** Delegate to Repository instead of raw SQL
**Effort:** 5 min
**Test:** Verify incremental updates hide thinking blocks

---

#### Bug #2: Single Transcript View Shows Hidden Entries

**File:** `Repositories.swift:365`
**Method:** `byTranscript(_:afterTimestamp:)`
**Symptom:** Viewing specific transcript shows thinking blocks
**Root Cause:** Missing `display_in_timeline = 1` filter
**User Impact:** Users viewing transcript detail see hidden entries
**Fix:** Add filter to query builder chain
**Effort:** 2 min
**Test:** View transcript, verify thinking blocks hidden

---

#### Bug #3: Search Includes Hidden Entries

**File:** `Repositories.swift:375`
**Method:** `search(content:projectId:)`
**Symptom:** Search results include thinking blocks
**Root Cause:** Missing `display_in_timeline = 1` filter
**User Impact:** Search pollution, user sees internal AI planning
**Fix:** Add filter to query builder chain
**Effort:** 2 min
**Priority:** P1 (downgraded from P0 - search may be low usage)
**Test:** Search for term appearing in thinking block, verify not found

---

### P1 - Architectural Violations (High Priority)

#### Issue #1: Orchestrator Bypasses Repository Layer

**Already covered as P0 Bug #1**

---

### P2 - Code Quality (Medium Priority)

#### Issue #1: Deprecated Method Still Present

**File:** `TranscriptOrchestrator.swift:1534`
**Method:** `getEntriesAfterCursor(forProject:after:)`
**Status:** Marked `@available(*, deprecated)` but not removed
**Impact:** Confusing for developers, increases codebase size
**Fix:** Remove deprecated method after confirming no callers
**Effort:** 5 min
**Test:** Grep for callers, delete if none found

---

#### Issue #2: Inconsistent Query Patterns

**Already covered as Violation #2**

---

### P3 - Documentation (Low Priority)

#### Issue #1: Multiple Entry-Loading Methods Lack Explanation

**File:** `Repositories.swift`
**Methods:** recentByProject vs recentFeed
**Impact:** Developers unsure which to use
**Fix:** Add comments explaining differences
**Effort:** 10 min

---

## Part 6: Specific Area Investigations

### 6.1 Timeline Entry Loading (CRITICAL)

**Queries Found:** 7

**Summary:**
- ✅ **4 correct** (recentByProject, newByProject, recentFeed, entriesAfterCursor)
- ❌ **3 buggy** (byTranscript, search, getEntriesAfterCursor)

**Consistency:** 57% correct - UNACCEPTABLE for critical UI feature

**Root Causes:**
1. Easy to forget filter (not type-enforced)
2. Multiple ways to load entries (no single method)
3. No code review checklist for filters

**Recommendations:**
1. Fix 3 bugs immediately (30 min total)
2. Add tests enforcing filter on all entry queries
3. Consider query builder pattern making filter mandatory

---

### 6.2 Cache Miss Detection

**Query:** Implicit - happens in ConversationMonitor after loading entries

**Current Flow:**
```
getEntriesAfterCursor() (no filter)
  ↓
Loads ALL entries including hidden
  ↓
ConversationMonitor processes each entry
  ↓
Checks for cache miss
  ↓
Creates CacheMiss for ANY entry without cache
  ↓
Queues for LLM summary generation
```

**Impact:**
- ~480 hidden entries loaded
- Each checked for cache
- Each queued for LLM if no cache
- Wasting LLM API calls on entries user will never see

**Fix:** Fix getEntriesAfterCursor() to filter display_in_timeline = 1
- Prevents hidden entries from entering pipeline
- Eliminates unnecessary cache lookups
- Stops wasting LLM calls

**Expected Savings:**
- 480 fewer entries loaded per project
- 480 fewer cache lookups
- Up to 480 fewer LLM API calls (if not cached)

---

### 6.3 Single Transcript View

**Query:** byTranscript (Repositories.swift:363)

**Status:** ❌ Missing display_in_timeline filter

**Impact:**
- Users viewing transcript detail see thinking blocks
- Thinking blocks have hallucinated summaries
- Different view shows different data than main timeline (inconsistent UX)

**Fix:** Add filter (2 min)

---

### 6.4 Search Functionality

**Query:** search (Repositories.swift:373)

**Status:** ❌ Missing display_in_timeline filter

**Impact:**
- Search finds hidden thinking blocks
- User confused why they see entry in search but not timeline

**Additional Concern:** Optional project_id filter
- If nil, searches across all projects
- Possible cross-project leak if multi-user in future
- Likely intentional for global search, but document

**Fix:** Add display_in_timeline filter (2 min)

---

### 6.5 Statistics & Counts

**Queries:** getEntryCount (2 implementations)

**Status:** ✅ Both correctly filter on display_in_timeline = 1

**Impact:** Counts shown to user are correct

**Verdict:** ✅ No issues found

---

## Part 7: Raw SQL vs Query Builder Analysis

### 7.1 Pattern Classification

**Type 1: Raw SQL - Complex Join (JUSTIFIED)**

Example: recentFeed (Repositories.swift:383)
```sql
SELECT e.*, c.*
FROM transcript_entries e
LEFT JOIN timeline_cache c
  ON c.content_sha256 = e.content_sha256 AND ...
WHERE e.project_id = ? AND e.display_in_timeline = 1
ORDER BY e.timestamp DESC
LIMIT ?
```
**Justification:** ✅ OK - Complex LEFT JOIN clearer in SQL

---

**Type 2: Raw SQL - Simple Filter (NOT JUSTIFIED)**

Example: getEntriesAfterCursor (TranscriptOrchestrator.swift:2091)
```sql
SELECT * FROM transcript_entries
WHERE project_id = ? AND (timestamp > ? OR ...)
ORDER BY timestamp ASC
```
**Justification:** ❌ NOT OK - Query builder can express this
**Should be:** Query builder (as in Repositories.entriesAfterCursor)

---

**Type 3: Raw SQL - Aggregation (JUSTIFIED)**

Example: getEntryCount (TranscriptOrchestrator.swift:1506)
```sql
SELECT COUNT(*) FROM transcript_entries
WHERE transcript_id = ? AND display_in_timeline = 1
```
**Justification:** ✅ OK - Simple aggregation, raw SQL is clearer

---

**Type 4: Query Builder - Simple (GOOD)**

Example: recentByProject (Repositories.swift:344)
```swift
TranscriptEntry
  .filter(Column("project_id") == projectId && Column("display_in_timeline") == 1)
  .order(Column("timestamp").desc)
  .limit(limit)
  .fetchAll(db)
```
**Justification:** ✅ GOOD - Readable, type-safe, correct filters

---

**Type 5: Mixed - Builder + Raw Fragment (OK)**

Example: entriesAfterCursor (Repositories.swift:431)
```swift
TranscriptEntry
  .filter(Column("project_id") == projectId && Column("display_in_timeline") == 1)
  .filter(sql: "(timestamp, created_at, id) > (?, ?, ?)", arguments: [...])
  .fetchAll(db)
```
**Justification:** ✅ OK - Builder lacks tuple comparison, raw fragment necessary

---

### 7.2 Decision Matrix

| Complexity | Query Builder Can Express? | Use Raw SQL? |
|------------|---------------------------|--------------|
| Simple filter (1-2 columns) | Yes | ❌ Use query builder |
| Tuple comparison | No | ✅ Mixed (builder + raw fragment) |
| 2-table LEFT JOIN | Possible but awkward | ✅ Raw SQL (cleaner) |
| 3+ table JOIN | No (or very awkward) | ✅ Raw SQL |
| Simple aggregation (COUNT) | Yes but verbose | ✅ Raw SQL (cleaner) |
| Complex aggregation | Difficult | ✅ Raw SQL |
| Window functions | No | ✅ Raw SQL |

---

### 7.3 Raw SQL Audit Results

**Total Raw SQL Instances:** 28

**Justified (12):**
- Complex joins: 1 (recentFeed)
- Aggregations: 2 (getEntryCount x2)
- PRAGMA commands: 9 (DatabaseManager)

**NOT Justified (1):**
- getEntriesAfterCursor (TranscriptOrchestrator) - Should use query builder

**Maintenance Operations (15):**
- INSERT/UPDATE/DELETE for projects, cache, metadata
- Justified: Direct SQL clearer for one-off operations

**Verdict:** 1 unjustified raw SQL - the same one with the bug (getEntriesAfterCursor)

---

## Part 8: Abstraction Opportunities

### 8.1 Query Builder Pattern

**Problem:** Easy to forget filters when writing queries

**Current Anti-Pattern:**
```swift
// Developer writes query
TranscriptEntry.filter(Column("project_id") == projectId).fetchAll(db)
// ❌ FORGOT: display_in_timeline filter
```

**Proposed Pattern:**
```swift
// Composable query builder with required filters
class EntryQuery {
  private var db: Database
  private var filters: [SQLSpecificExpressible] = []

  init(db: Database) {
    self.db = db
    // ALWAYS apply display_in_timeline filter by default
    self.filters.append(Column("display_in_timeline") == 1)
  }

  func forProject(_ id: String) -> Self {
    filters.append(Column("project_id") == id)
    return self
  }

  func forTranscript(_ id: String) -> Self {
    filters.append(Column("transcript_id") == id)
    return self
  }

  func afterCursor(_ cursor: (Int, Int, String)) -> Self {
    filters.append(sql: "(timestamp, created_at, id) > (?, ?, ?)", arguments: [cursor.0, cursor.1, cursor.2])
    return self
  }

  func search(_ content: String) -> Self {
    filters.append(Column("content").like("%\(content)%"))
    return self
  }

  func recent(limit: Int) -> Self {
    // Sets DESC order + limit
  }

  func chronological() -> Self {
    // Sets ASC order
  }

  func includeHidden() -> Self {
    // Remove display_in_timeline filter if explicitly needed
    filters.removeAll { /* check if display_in_timeline filter */ }
    return self
  }

  func fetch() throws -> [TranscriptEntry] {
    var query = TranscriptEntry.all()
    for filter in filters {
      query = query.filter(filter)
    }
    return try query.fetchAll(db)
  }
}

// Usage
let entries = try EntryQuery(db: db)
  .forProject(projectId)
  .afterCursor(cursor)
  .chronological()
  .fetch()
// ✅ IMPOSSIBLE to forget display_in_timeline filter (applied by default)
```

**Benefits:**
- Cannot forget display_in_timeline filter (on by default)
- Explicit opt-out if needed (includeHidden())
- Type-safe, chainable
- Single place to add new filters
- Clear what query does

**Drawbacks:**
- More code upfront
- Learning curve for developers

**Recommendation:** Consider for Phase 3 (long-term improvement)

---

### 8.2 Shared Base Methods

**Current:** Orchestrator reimplements Repository methods

**Proposed:** Orchestrator ALWAYS delegates to Repository

**Pattern:**
```swift
// Repository has canonical implementation
class EntryRepository {
  func entriesAfterCursor(...) -> [Entry] { ... }
}

// Orchestrator delegates (never reimplements)
class TranscriptOrchestrator {
  private let entryRepo: EntryRepository

  func getEntriesAfterCursor(...) -> [Entry] {
    try entryRepo.entriesAfterCursor(...)
  }
}
```

**Enforcement:** Architectural test
```swift
func testOrchestratorDoesNotContainRawEntryQueries() {
  let orchestratorSource = try String(contentsOfFile: "TranscriptOrchestrator.swift")
  XCTAssertFalse(
    orchestratorSource.contains("SELECT * FROM transcript_entries"),
    "Orchestrator should delegate to Repository, not use raw SQL"
  )
}
```

**Recommendation:** Implement immediately (part of P0 bug fix)

---

## Part 9: Refactoring Roadmap

### Phase 1: Critical Bug Fixes (THIS WEEK)

**Goal:** Fix all P0 bugs (missing filters causing wrong data in UI)

**Tasks:**

1. **Fix: Incremental updates show hidden entries**
   - File: TranscriptOrchestrator.swift:2085
   - Change: Delete raw SQL, delegate to Repository
   - Effort: 5 min
   - Test: Verify incremental updates hide thinking blocks

2. **Fix: Single transcript view shows hidden entries**
   - File: Repositories.swift:363
   - Change: Add `.filter(Column("display_in_timeline") == 1)`
   - Effort: 2 min
   - Test: View transcript, verify thinking blocks hidden

3. **Fix: Search includes hidden entries**
   - File: Repositories.swift:373
   - Change: Add `.filter(Column("display_in_timeline") == 1)`
   - Effort: 2 min
   - Test: Search for term in thinking block, verify not found

**Total Effort:** ~30 minutes (including tests)

**Success Criteria:**
- ✅ All timeline entry queries filter on display_in_timeline = 1
- ✅ No hidden entries visible in any UI view
- ✅ Tests prevent regression

---

### Phase 2: Eliminate Unnecessary Duplication (NEXT WEEK)

**Goal:** Remove duplicate implementations, consolidate to single source of truth

**Tasks:**

1. **Remove: Deprecated method**
   - File: TranscriptOrchestrator.swift:1534
   - Change: Delete getEntriesAfterCursor(forProject:after:)
   - Effort: 5 min
   - Test: Grep for callers, verify none

2. **Document: Justified duplicates**
   - Files: Repositories.swift
   - Change: Add comments explaining recentByProject vs recentFeed
   - Effort: 10 min

**Total Effort:** ~15 minutes

**Success Criteria:**
- ✅ No deprecated code remains
- ✅ All remaining duplicates are documented

---

### Phase 3: Architectural Improvements (THIS MONTH)

**Goal:** Establish clear patterns and prevent future violations

**Tasks:**

1. **Document: Repository vs Orchestrator responsibilities**
   - File: Create build/docs/architecture/repository-layer-guidelines.md
   - Content:
     - When to use raw SQL vs query builder
     - When Orchestrator should delegate vs reimplement
     - Required filters checklist
   - Effort: 1 hour

2. **Add: Code review checklist**
   - File: Update CLAUDE.md
   - Content:
     - Check for filter consistency
     - Check for unnecessary duplication
     - Check for layer violations
   - Effort: 30 min

3. **Add: Architectural tests**
   - Test: Orchestrator doesn't have raw entry queries
   - Test: All UI entry queries have required filters
   - Effort: 2 hours

**Total Effort:** ~4 hours

**Success Criteria:**
- ✅ Architecture docs guide development
- ✅ Code review process catches violations
- ✅ Tests prevent regressions

---

### Phase 4: Prevention (ONGOING)

**Goal:** Add safeguards to prevent anti-patterns

**Tasks:**

1. **Update: CLAUDE.md with SQL guidelines**
   - Never bypass Repository layer
   - Always apply display_in_timeline filter for UI queries
   - Prefer query builder over raw SQL for simple queries
   - Document when raw SQL is justified
   - Effort: 30 min

2. **Consider: Query builder pattern**
   - Implement EntryQuery class (see Part 8.1)
   - Makes filter forgetting impossible
   - Effort: 4 hours (design + implementation + migration)

**Total Effort:** ~5 hours

**Success Criteria:**
- ✅ CLAUDE.md has comprehensive SQL guidelines
- ✅ Future AI assistants won't create duplicates
- ✅ Query builder pattern prevents filter bugs

---

## Part 10: Quick Reference

### Files Changed Summary

| File | Lines Changed | Type |
|------|---------------|------|
| TranscriptOrchestrator.swift | -15 (delete raw SQL) | P0 Fix |
| Repositories.swift:365 | +1 (add filter) | P0 Fix |
| Repositories.swift:375 | +1 (add filter) | P1 Fix |
| TranscriptOrchestrator.swift:1534 | -5 (remove deprecated) | P2 Cleanup |

**Total:** 3 files, ~20 lines changed

---

### Test Coverage Needed

```swift
// Test 1: Incremental updates filter hidden entries
func testIncrementalUpdateFiltersHiddenEntries() async throws {
  let hidden = TranscriptEntry(id: "h1", displayInTimeline: 0)
  try orchestrator.insert(hidden)

  let entries = try orchestrator.getEntriesAfterCursor(projectId: projectId, after: cursor)
  XCTAssertFalse(entries.contains { $0.id == "h1" })
}

// Test 2: byTranscript filters hidden entries
func testByTranscriptFiltersHiddenEntries() throws {
  let hidden = TranscriptEntry(id: "h1", transcriptId: "t1", displayInTimeline: 0)
  try repository.insert(hidden)

  let entries = try repository.byTranscript("t1")
  XCTAssertFalse(entries.contains { $0.id == "h1" })
}

// Test 3: search filters hidden entries
func testSearchFiltersHiddenEntries() throws {
  let hidden = TranscriptEntry(id: "h1", content: "thinking", displayInTimeline: 0)
  try repository.insert(hidden)

  let results = try repository.search(content: "thinking")
  XCTAssertFalse(results.contains { $0.id == "h1" })
}
```

---

## Conclusion

This audit identified **3 critical bugs** where missing `display_in_timeline = 1` filters cause hidden entries (thinking blocks) to appear in the UI. The root cause is a combination of:

1. **Easy to forget:** Filter not type-enforced
2. **Duplication:** Same query logic in multiple places
3. **Layer violations:** Orchestrator reimplementing Repository methods

**Total fixes:** ~30 minutes to fix all P0 bugs
**Impact:** Eliminates user-visible data errors and wasted LLM API calls

**Long-term:** Consider query builder pattern to make filter forgetting impossible.
