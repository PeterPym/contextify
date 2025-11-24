# SQL & Repository Guidelines for CLAUDE.md

**Add this section to Contextify CLAUDE.md under a new heading "SQL & Database Access Patterns"**

---

## SQL & Database Access Patterns

### Repository Layer Discipline

**CRITICAL RULE: Never bypass the Repository layer**

Repositories are the single source of truth for data access. Orchestrators should delegate to Repositories, never reimplement queries.

#### ❌ WRONG: Orchestrator reimplements with raw SQL

```swift
// In TranscriptOrchestrator
func getEntries(projectId: String) throws -> [Entry] {
  try pool.read { db in
    // ❌ BAD: Raw SQL duplicating Repository logic
    try Entry.fetchAll(db, sql: """
      SELECT * FROM transcript_entries
      WHERE project_id = ?
    """, arguments: [projectId])
  }
}
```

**Problems:**
- Duplicate implementation → multiple places to maintain
- Easy to forget filters (as seen in Bug #4 of timeline hallucination)
- Layer architecture decay

#### ✅ CORRECT: Orchestrator delegates to Repository

```swift
// In TranscriptOrchestrator
func getEntries(projectId: String) throws -> [Entry] {
  // ✅ GOOD: Delegate to Repository's canonical implementation
  try entryRepo.recentByProject(projectId, limit: Int.max)
}
```

**Benefits:**
- Single source of truth
- Filters applied consistently
- Changes only need one edit

#### Exceptions

Orchestrator can use raw SQL ONLY if:

1. **Coordinating multiple repositories** (transaction spanning tables)
2. **Complex multi-table join** Repository doesn't support
3. **Must document why** in code comment

Example of justified raw SQL in Orchestrator:

```swift
// ✅ OK: Complex transaction across project + transcript tables
func archiveProject(id: String) throws {
  try pool.write { db in
    // Multi-table transaction that doesn't fit single repository
    try db.execute(sql: "UPDATE projects SET archived = 1 WHERE id = ?", arguments: [id])
    try db.execute(sql: "UPDATE transcripts SET archived = 1 WHERE project_id = ?", arguments: [id])
    // Note: Could refactor to use repositories with explicit transaction, but raw SQL clearer here
  }
}
```

---

### Required Filters for UI Queries

**CRITICAL: Timeline entry queries MUST filter on `display_in_timeline = 1`**

The `display_in_timeline` column hides thinking blocks (internal AI planning) from users. Forgetting this filter causes:
- ❌ Hidden internal AI state visible to users
- ❌ Thinking blocks with hallucinated summaries shown
- ❌ Wasted LLM API calls generating summaries for hidden entries

#### ❌ WRONG: Missing filter

```swift
func getEntries(projectId: String) throws -> [Entry] {
  try Entry
    .filter(Column("project_id") == projectId)
    .fetchAll(db)
  // ❌ MISSING: .filter(Column("display_in_timeline") == 1)
}
```

**Result:** User sees thinking blocks with wrong summaries

#### ✅ CORRECT: Filter applied

```swift
func getEntries(projectId: String) throws -> [Entry] {
  try Entry
    .filter(Column("project_id") == projectId)
    .filter(Column("display_in_timeline") == 1)  // ✅ ALWAYS for UI queries
    .fetchAll(db)
}
```

**Result:** User sees only entries meant for display

#### When to filter

**ALWAYS filter on `display_in_timeline = 1` for:**
- Timeline views (main feed, incremental updates)
- Search results
- Entry counts shown to user
- Any query populating UI

**DON'T filter for:**
- Admin/debug views (if explicitly showing all entries)
- Backend metrics (total entries including hidden)
- Must document why filter is intentionally omitted

---

### Filter Checklist

When writing new entry queries:

- [ ] Filters on `project_id` (if project-scoped)
- [ ] Filters on `display_in_timeline = 1` (if populating UI)
- [ ] Uses Repository method if one exists (don't duplicate)
- [ ] Documented if using raw SQL (explain why)
- [ ] Tested with hidden entries (verify filter works)

---

### Query Builder vs Raw SQL

**Prefer query builder for simple queries:**

#### ✅ GOOD: Simple filter, use query builder

```swift
func getEntry(id: String) throws -> Entry? {
  try Entry
    .filter(Column("id") == id)
    .filter(Column("display_in_timeline") == 1)
    .fetchOne(db)
}
```

**Benefits:**
- Type-safe (compiler catches typos)
- Readable
- Composable (easy to add filters)

#### ✅ OK: Complex join justifies raw SQL

```swift
func entriesWithCache(projectId: String, signature: String, limit: Int) throws -> [(Entry, Cache?)] {
  try db.read { db in
    // Complex LEFT JOIN with cache table - cleaner in raw SQL
    try Row.fetchAll(db, sql: """
      SELECT e.*, c.*
      FROM transcript_entries e
      LEFT JOIN timeline_cache c
        ON e.content_sha256 = c.content_sha256
       AND e.window_sha256 = c.window_sha256
       AND c.generator_signature = ?
      WHERE e.project_id = ?
        AND e.display_in_timeline = 1  -- ✅ Don't forget filters in raw SQL!
      ORDER BY e.timestamp DESC
      LIMIT ?
    """, arguments: [signature, projectId, limit])
  }
}
```

**Note:** Even in raw SQL, apply all required filters!

---

### Decision Guide: Query Builder vs Raw SQL

| Query Complexity | Query Builder Can Express? | Use Raw SQL? |
|------------------|---------------------------|--------------|
| Single table, simple filters | Yes | ❌ Use query builder |
| 1-2 table join | Possible (may be awkward) | ⚠️ Either (prefer builder) |
| 3+ table join | Difficult | ✅ Raw SQL OK |
| Tuple comparison | No (SQLite limitation) | ✅ Mixed (builder + raw fragment) |
| Simple aggregation (COUNT) | Yes (verbose) | ✅ Raw SQL (cleaner) |
| Complex aggregation (GROUP BY, HAVING) | Difficult | ✅ Raw SQL |
| Window functions | No | ✅ Raw SQL (required) |

#### Mixed Approach Example

When query builder can't express specific logic (e.g., tuple comparison):

```swift
func entriesAfterCursor(projectId: String, after: (timestamp: Int, createdAt: Int, id: String)) throws -> [Entry] {
  try Entry
    .filter(Column("project_id") == projectId)
    .filter(Column("display_in_timeline") == 1)
    // ✅ Mixed: Use raw SQL fragment for tuple comparison (builder limitation)
    .filter(sql: "(timestamp, created_at, id) > (?, ?, ?)", arguments: [after.timestamp, after.createdAt, after.id])
    .order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)
    .fetchAll(db)
}
```

---

### When using raw SQL

**Follow these rules:**

1. **Add comment explaining why**
   ```swift
   // Using raw SQL because: Complex 3-table LEFT JOIN cleaner than builder
   ```

2. **Use parameter placeholders** (never string interpolation)
   ```swift
   // ✅ GOOD: Parameterized
   sql: "SELECT * FROM entries WHERE id = ?", arguments: [id]

   // ❌ BAD: SQL injection risk
   sql: "SELECT * FROM entries WHERE id = '\(id)'"
   ```

3. **Apply all required filters**
   ```swift
   // ✅ Don't forget filters just because using raw SQL!
   WHERE project_id = ? AND display_in_timeline = 1
   ```

4. **Consider if Repository method could be enhanced instead**
   - Maybe Repository should support this use case
   - Better to add capability to Repository than bypass it

---

## Architecture Layers

**Expected call flow:**

```
UI (SwiftUI View)
    ↓
State (@Observable ViewModel/Monitor)
    ↓
Orchestrator (Business Logic)
    ↓
Repository (Data Access)
    ↓
GRDB (Database Driver)
```

### Layer Responsibilities

#### UI Layer
- Display data from State
- Trigger user actions
- **NO** database access
- **NO** business logic

#### State Layer (@Observable)
- Properties for UI binding
- Coordinate Orchestrator calls
- Transform data for UI (formatting, grouping)
- **NO** raw SQL
- **NO** direct Repository access (use Orchestrator)

#### Orchestrator Layer
- Business logic (validation, workflow)
- Coordinate multi-repository operations
- **Delegate to Repository** for data access
- CAN use raw SQL ONLY for cross-repository transactions
- MUST document why if bypassing Repository

#### Repository Layer
- **Single source of SQL queries**
- Type-safe GRDB wrappers
- **NO** business logic (just data access)
- Canonical implementations (no duplicates)

---

### When Adding New Data Access

**Workflow:**

1. **Check if Repository method exists** → Use it
2. **If not, add to Repository** (not Orchestrator)
3. **Orchestrator delegates** to Repository
4. **Apply all required filters**
5. **Prefer query builder** unless complex join/aggregation

**Example:**

```swift
// Step 1: Add to Repository (canonical implementation)
// File: Repositories.swift
public func visibleEntriesForProject(_ projectId: String) throws -> [Entry] {
  try Entry
    .filter(Column("project_id") == projectId)
    .filter(Column("display_in_timeline") == 1)  // Always!
    .order(Column("timestamp").desc)
    .fetchAll(db)
}

// Step 2: Orchestrator delegates
// File: TranscriptOrchestrator.swift
public func getVisibleEntries(projectId: String) throws -> [Entry] {
  try entryRepo.visibleEntriesForProject(projectId)
}

// Step 3: State layer calls Orchestrator
// File: ConversationMonitor.swift
func loadEntries() async {
  let entries = try? orchestrator.getVisibleEntries(projectId: currentProject.id)
  self.entries = entries ?? []
}
```

---

## Anti-Patterns to Avoid

### 1. Orchestrator Reimplements Repository

#### ❌ Don't:

```swift
// Repository has this
func recentEntries() -> [Entry] { ... }

// Orchestrator reimplements same thing
func getRecentEntries() -> [Entry] {
  // ❌ Raw SQL doing same thing as Repository
  try pool.read { db in
    try Entry.fetchAll(db, sql: "SELECT * FROM ...")
  }
}
```

#### ✅ Do:

```swift
// Orchestrator delegates
func getRecentEntries() -> [Entry] {
  try entryRepo.recentEntries()
}
```

---

### 2. Missing Filters in Some Code Paths

#### ❌ Don't:

```swift
// Method A has filter
func recentEntries() {
  Entry.filter(display_in_timeline == 1)
}

// Method B forgets filter
func searchEntries() {
  Entry.filter(content.like("%...%"))
  // ❌ Missing display_in_timeline filter!
}
```

#### ✅ Do:

Every UI query has same filters:

```swift
func recentEntries() {
  Entry.filter(display_in_timeline == 1)  // ✅
}

func searchEntries() {
  Entry.filter(display_in_timeline == 1)  // ✅
        .filter(content.like("%...%"))
}
```

---

### 3. Duplicate Implementations

#### ❌ Don't:

```swift
// 3 different methods doing same thing
func loadRecentEntries() { ... }
func getRecentEntries() { ... }
func recentEntries() { ... }
```

#### ✅ Do:

One canonical method, others delegate or deprecated:

```swift
// Canonical implementation
func recentEntries() { ... }

// If wrapper needed, delegate
func getRecentEntries() {
  recentEntries()
}
```

---

## Code Review Checklist

When reviewing database access code:

- [ ] Uses existing Repository method if available
- [ ] Doesn't reimplement existing query with raw SQL
- [ ] Applies `display_in_timeline = 1` filter for UI queries
- [ ] Applies `project_id` filter for project-scoped queries
- [ ] Uses query builder for simple queries (prefer over raw SQL)
- [ ] Documents why if using raw SQL (complex join, performance, etc.)
- [ ] No SQL injection risk (uses parameters, not string concat)
- [ ] Respects layer boundaries (no UI → DB, no Orchestrator raw SQL duplicating Repository)

---

## Testing Requirements

All new data access methods need tests for:

- [ ] Correct filtering (display_in_timeline, project_id, etc.)
- [ ] Cursor pagination (if applicable)
- [ ] Empty result handling
- [ ] Error handling (database errors)

### Example Test

```swift
func testEntriesFilterHiddenContent() throws {
  // Insert visible entry
  let visible = Entry(id: "v1", displayInTimeline: 1)
  try repo.insert(visible)

  // Insert hidden entry
  let hidden = Entry(id: "h1", displayInTimeline: 0)
  try repo.insert(hidden)

  // Query should return only visible
  let results = try repo.entriesForProject(projectId)

  XCTAssertEqual(results.count, 1)
  XCTAssertEqual(results[0].id, "v1")
  XCTAssertFalse(results.contains { $0.id == "h1" }, "Hidden entries should be filtered")
}
```

---

## Following These Guidelines Prevents

- ✅ Missing filter bugs (wrong data shown to users)
- ✅ Duplicate implementations (maintenance burden)
- ✅ Layer violations (architectural decay)
- ✅ Inconsistent behavior (different views showing different data)
- ✅ Wasted resources (LLM calls on hidden entries)

---

## Quick Reference

### When in doubt:

1. **Check if Repository method exists** → Use it
2. **Prefer query builder** over raw SQL
3. **Apply all required filters** (display_in_timeline, project_id)
4. **Document exceptions** (why raw SQL, why no filter)
5. **Test with hidden entries** (verify filter works)

### Common Filters

```swift
// UI queries - ALWAYS
.filter(Column("display_in_timeline") == 1)

// Project-scoped - ALWAYS
.filter(Column("project_id") == projectId)

// Chronological order (most common)
.order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)

// Recent first
.order(Column("timestamp").desc, Column("created_at").desc, Column("id").desc)
```

---

## Real-World Examples

### Example 1: Load Timeline Entries

```swift
// ✅ CORRECT: Repository method with all filters
public func recentByProject(_ projectId: String, limit: Int) throws -> [TranscriptEntry] {
  try db.read { db in
    try TranscriptEntry
      .filter(Column("project_id") == projectId)           // ✅ Project isolation
      .filter(Column("display_in_timeline") == 1)          // ✅ Hide thinking blocks
      .order(Column("timestamp").desc)                     // Most recent first
      .limit(limit)
      .fetchAll(db)
  }
}

// ✅ CORRECT: Orchestrator delegates
public func getRecentEntries(forProject projectId: String, limit: Int = 50) throws -> [TranscriptEntry] {
  try entryRepo.recentByProject(projectId, limit: limit)
}
```

### Example 2: Complex Join (Justified Raw SQL)

```swift
// ✅ CORRECT: Raw SQL for LEFT JOIN with cache, includes all filters
public func recentFeed(projectId: String, limit: Int, generatorSignature: String) throws -> [(Entry, Cache?)] {
  try db.read { db in
    let sql = """
      SELECT e.*, c.*
      FROM transcript_entries e
      LEFT JOIN timeline_cache c
        ON c.content_sha256 = e.content_sha256
       AND c.window_sha256 = e.window_sha256
       AND c.generator_signature = ?
      WHERE e.project_id = ?              -- ✅ Project filter
        AND e.display_in_timeline = 1     -- ✅ Hide thinking blocks
      ORDER BY e.timestamp DESC
      LIMIT ?
    """
    // Note: Using raw SQL because LEFT JOIN with cache table clearer than query builder
    try Row.fetchAll(db, sql: sql, arguments: [generatorSignature, projectId, limit])
  }
}
```

### Example 3: Cursor Pagination (Mixed Approach)

```swift
// ✅ CORRECT: Query builder + raw fragment for tuple comparison
public func entriesAfterCursor(projectId: String, after: (timestamp: Int, createdAt: Int, id: String)) throws -> [Entry] {
  try db.read { db in
    try TranscriptEntry
      .filter(Column("project_id") == projectId)           // ✅ Project filter
      .filter(Column("display_in_timeline") == 1)          // ✅ Hide thinking blocks
      // Mixed: Raw SQL fragment for tuple comparison (builder limitation)
      .filter(sql: "(timestamp, created_at, id) > (?, ?, ?)", arguments: [after.timestamp, after.createdAt, after.id])
      .order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)
      .fetchAll(db)
  }
}
```

---

## Summary

**Golden Rules:**

1. **Never bypass Repository** - Orchestrator delegates, never reimplements
2. **Always filter UI queries** - `display_in_timeline = 1` for timeline entries
3. **Prefer query builder** - Use raw SQL only when necessary
4. **Document exceptions** - Comment why raw SQL or missing filter
5. **Test filters** - Verify hidden entries are actually hidden

**Remember:** The bugs found in the audit (timeline hallucination, search pollution) were all caused by forgetting `display_in_timeline = 1` filter. Make it impossible to forget!
