---
todo_id: ENTRY-FILTER-ARCHITECTURE
title: Unified Entry Filter Architecture
type: spec
date: 2025-12-21
status: active
description: Decouple is_sidechain from includeHidden and implement unified EntryFilter type for scalable query filtering.
---

# Unified Entry Filter Architecture

## Problem Statement

The CLI query service (`ContextifyQueryService.swift`) has accumulated ad-hoc filtering parameters that are:

1. **Coupled incorrectly** - `is_sidechain` filtering is tied to `includeHidden` parameter
2. **Inconsistent** - Some functions allow filter overrides, others hard-code filters
3. **Not scalable** - Adding new filters means changing every function signature

This coupling breaks CLI functionality: it's impossible to express "show hidden entries but not sidechains" or "show sidechains for debugging but not hidden entries."

### Evidence

| Function | Location | Issue |
|----------|----------|-------|
| `context()` | L714-718 | Couples `is_sidechain = 0` to `!includeHidden` |
| `activity()` | L903 | Same coupling |
| `recentActivity()` | L976 | Always filters sidechains, no override |
| `projectStats()` | L1042 | Always filters sidechains, no override |
| `search()` | L457 | Correctly does NOT filter sidechains |

### UI Search Consistency Issue

The UI search path has a parallel problem:

- `ConversationSearchService.search()` - Does NOT filter `is_sidechain` (can return sidechain hits)
- `ConversationSearchService.getContext()` - Hard-codes `AND is_sidechain = 0` (L242, L252, L260)
- `ConversationSearchService.getContextCounts()` - Same hard-coded filter (L306, L318)

**Result:** UI search can return sidechain hits, but context retrieval returns empty windows for those hits. This must be fixed as part of the same change set.

### Root Cause

When sidechain ingestion was added, the `is_sidechain = 0` filter was expedient piggybacked onto `includeHidden`:

```swift
// Current (problematic)
if !includeHidden {
  filters.append("\(prefix).display_in_timeline = 1")
  filters.append("\(prefix).is_sidechain = 0")  // Incorrectly coupled
}
```

## Solution: Unified `EntryFilter` Type

### Design Principles

1. **Orthogonal concerns** - Each filter dimension is independent
2. **Sensible defaults** - Timeline-oriented views exclude hidden + sidechains by default
3. **Presets for common use cases** - `.timeline`, `.search`, `.debug`
4. **Central SQL generation** - One helper generates predicates consistently
5. **Shared between UI and CLI** - Same type used across codebase
6. **Hard to misuse** - Provide explicit helpers for WHERE vs AND fragment patterns

### Design Decisions

**Scope filters stay separate:** `projectId`, `transcriptId`, and `timeRange` are NOT part of `EntryFilter`. They're often implemented differently (JOIN vs WHERE vs EXISTS), and forcing them in would bloat `EntryFilter` into a "query builder."

Naming convention: `EntryFilter` is only "entry-dimension predicates" (visibility/source/type/provider). If scope composition is needed later, use a separate struct: `EntryQueryScope` or `EntryQueryOptions`.

**Defer `providers` filter:** Until there's a concrete use case, `providers` is not included in the type. Add it when a real use case emerges.

### Type Definition

```swift
/// Unified filter specification for transcript entry queries.
/// Covers entry-dimension predicates only (visibility, source, type).
/// Scope filters (project, transcript, time) remain separate parameters.
public struct EntryFilter: Sendable, Equatable {

  // MARK: - Visibility Filters

  /// Include entries with `display_in_timeline = 0`.
  /// Default: false (show only timeline-visible entries)
  public var includeHidden: Bool = false

  /// Include entries from sidechain (subagent) transcripts.
  /// Default: false (show only main-chain entries)
  public var includeSidechains: Bool = false

  // MARK: - Type Filters

  /// Filter by entry kind. Nil or empty means all kinds (no filter applied).
  /// Use EntryFilter.Kind constants to avoid typos.
  /// Note: Uses array for ergonomic call sites; sorted internally for deterministic SQL.
  public var kinds: [String]? = nil

  // MARK: - Presets

  /// Default filter for timeline views (excludes hidden and sidechains)
  public static let timeline = EntryFilter()

  /// Filter for search results: includes sidechains (searchable), excludes hidden
  public static let search = EntryFilter(includeSidechains: true)

  /// Filter for debugging/forensics (includes everything - hidden + sidechains)
  /// Also useful for "search all" scenarios where you want complete results
  public static let debug = EntryFilter(includeHidden: true, includeSidechains: true)

  // MARK: - Initializers

  public init(
    includeHidden: Bool = false,
    includeSidechains: Bool = false,
    kinds: [String]? = nil
  ) {
    self.includeHidden = includeHidden
    self.includeSidechains = includeSidechains
    self.kinds = kinds
  }
}

// MARK: - Kind Constants (avoid stringly-typed drift)

extension EntryFilter {
  public enum Kind {
    public static let user = "user"
    public static let assistant = "assistant"
    public static let toolUse = "tool_use"
    public static let toolResult = "tool_result"
  }
}
```

### SQL Generation Helpers

Two helpers with explicit contracts to avoid WHERE/AND glue bugs.

**Security note:** The `prefix` parameter is interpolated into SQL and must be a trusted internal constant (e.g., `"e"`, `"te"`). Never forward user input to `prefix`.

```swift
extension EntryFilter {

  // MARK: - Table Aliases (constrain prefix to known-safe values)

  /// Known-safe table aliases for entry queries.
  /// Hardening against SQL injection by constraining to enum values.
  ///
  /// Trade-off: New aliases require modifying this enum (coupling point).
  /// For a solo project, this is acceptable - add cases as needed.
  /// If this becomes friction, consider a validated custom case:
  ///   case custom(String)  // validated against ^[A-Za-z_][A-Za-z0-9_]*$
  public enum TableAlias: String {
    case e      // Standard: "transcript_entries e"
    case te     // Alternative: "transcript_entries te"
  }

  // MARK: - Internal

  /// Build filter clauses and args (shared implementation)
  private func buildClauses(alias: TableAlias) -> (clauses: [String], args: [DatabaseValueConvertible]) {
    let prefix = alias.rawValue
    var clauses: [String] = []
    var args: [DatabaseValueConvertible] = []

    if !includeHidden {
      clauses.append("\(prefix).display_in_timeline = 1")
    }
    if !includeSidechains {
      clauses.append("\(prefix).is_sidechain = 0")
    }
    if let kinds, !kinds.isEmpty {
      // Dedupe and sort for deterministic SQL (order not preserved)
      let sortedKinds = Array(Set(kinds)).sorted()
      let placeholders = Array(repeating: "?", count: sortedKinds.count).joined(separator: ", ")
      clauses.append("\(prefix).kind IN (\(placeholders))")
      for k in sortedKinds {
        args.append(k)
      }
    }

    return (clauses, args)
  }

  /// Generate a SQL predicate for entry filtering.
  /// Returns a complete predicate (never empty - returns "1 = 1" if no filters).
  /// Use in: `WHERE (\(predicate))` or `ON ... AND (\(predicate))`
  func sqlPredicate(alias: TableAlias = .e) -> (sql: String, args: [DatabaseValueConvertible]) {
    let (clauses, args) = buildClauses(alias: alias)
    let sql = clauses.isEmpty ? "1 = 1" : clauses.joined(separator: " AND ")
    return (sql, args)
  }

  /// Generate a SQL fragment with leading " AND " for appending to existing WHERE.
  /// Returns empty string if no filters apply.
  /// Use in: `WHERE existing_condition\(andFragment)`
  func sqlAndFragment(alias: TableAlias = .e) -> (sql: String, args: [DatabaseValueConvertible]) {
    let (clauses, args) = buildClauses(alias: alias)
    if clauses.isEmpty {
      return ("", [])
    }
    return (" AND " + clauses.joined(separator: " AND "), args)
  }
}
```

### Usage Patterns

**WHERE clause (activity-style):**
```swift
let (filterPredicate, filterArgs) = filter.sqlPredicate()  // defaults to .e
var sql = """
  SELECT ... FROM transcript_entries e
  WHERE 1 = 1
"""
sql += " AND (\(filterPredicate))"
args.append(contentsOf: filterArgs)
```

**Existing WHERE with append (context-style):**
```swift
let (andFragment, filterArgs) = filter.sqlAndFragment()  // defaults to .e
var sql = """
  SELECT ... FROM transcript_entries e
  WHERE e.transcript_id = ?
"""
sql += andFragment
args.append(contentsOf: filterArgs)
```

**LEFT JOIN ON clause (projectStats-style):**
```swift
let (filterPredicate, filterArgs) = filter.sqlPredicate()
var args: [DatabaseValueConvertible] = []
// Keep in ON clause to preserve LEFT JOIN semantics (projects with 0 entries still appear)
var sql = """
  SELECT ...
  FROM projects p
  LEFT JOIN transcript_entries e
    ON e.project_id = p.id AND (\(filterPredicate))
"""
// Args still needed if filter has kinds
args.append(contentsOf: filterArgs)
```

**Using alternate alias:**
```swift
let (filterPredicate, filterArgs) = filter.sqlPredicate(alias: .te)
// Generates: "te.display_in_timeline = 1 AND te.is_sidechain = 0"
```

## Context Anchor Semantics

The `context()` function has special behavior that needs explicit documentation:

**Current behavior:**
1. Fetches anchor entry by ID with NO visibility/source filters
2. Applies filters to before/after windows and `transcriptEntryCount`

**Decision (Option 3 - explicit filtering):**
- Always return anchor if it exists (even if filters would exclude it)
- Apply filters to neighbor retrieval
- If neighbors are empty due to filtering, this is expected behavior
- Add debug logging when filter causes empty window for existing anchor

**Rationale:** This matches CLI use case of "find this entry, show context that would appear in timeline." Callers who want full transcript context can use `.debug` preset.

**Test requirement:** Add test for sidechain anchor with `includeSidechains: false` - should return anchor with empty neighbors.

## Implementation Plan

### Phase 0: Characterization Tests (BEFORE Any Code Changes)

**Purpose:** Lock down current behavior so refactor regressions are caught.

**Tasks:**
- [ ] Add sidechain entry fixtures to `QueryActivityTests.swift`
- [ ] Add sidechain entry fixtures to `QueryContextTests.swift`
- [ ] Add characterization tests with `XCTExpectFailure` for known bugs
- [ ] Run `swift test` - all tests must pass
- [ ] Commit: "test(query): add sidechain characterization tests before refactor"

**Use `XCTExpectFailure` for known-bug assertions:**

```swift
func testContext_includeHiddenTrue_shouldIncludeSidechains() async throws {
  // Setup: anchor with sidechain neighbors
  // ...

  // This documents the CURRENT BUG: includeHidden=true still excludes sidechains
  // NOTE: XCTExpectFailure is STRICT by default - test FAILS if assertion passes.
  // MUST remove this wrapper when bug is fixed.
  XCTExpectFailure("Bug: sidechains coupled to includeHidden - REMOVE WRAPPER when fixed") {
    let context = try service.context(entryId: "anchor", includeHidden: true)
    // After fix, this should include sidechain neighbors
    XCTAssertTrue(context.entries.contains { $0.isSidechain == 1 })
  }
}
```

**Important:** `XCTExpectFailure` is **strict by default** - if the expected failure doesn't happen (i.e., the bug is fixed), XCTest treats it as an "unexpected pass" and **fails the test**. This is actually desirable: it forces cleanup of the wrapper once the bug is fixed.

**Benefits:**
- Permanent "this was broken" breadcrumb in test history
- Strict mode nags you to clean up when bug is fixed
- Documents expected behavior clearly

**Workflow:**
1. Add test with `XCTExpectFailure` wrapper - test passes (expected failure)
2. Fix the bug
3. Test now fails ("unexpected pass") - reminder to remove wrapper
4. Remove `XCTExpectFailure` wrapper - test passes normally

### Phase 1: Add EntryFilter Type (Non-Breaking)

**Files:**
- Create `app/Sources/ContextifyCore/Database/EntryFilter.swift`

**Tasks:**
- [ ] Define `EntryFilter` struct with visibility + kinds fields
- [ ] Add `Kind` constants enum
- [ ] Implement `buildClauses(prefix:)` private helper
- [ ] Implement `sqlPredicate(prefix:)` helper
- [ ] Implement `sqlAndFragment(prefix:)` helper
- [ ] Add presets (`.timeline`, `.search`, `.debug`)
- [ ] Add unit tests for SQL generation (all 4 visibility combinations)
- [ ] Add unit tests for kinds filtering
- [ ] Run `swift test` - all tests must pass (Phase 0 characterization tests still pass)

### Phase 2a: Minimal Fix (Alternative - Fastest Path) ✅ COMPLETE

If full `EntryFilter` is deferred, this standalone fix resolves the immediate bug:

**Tasks:**
- [x] Add `includeSidechains: Bool = false` to `context()` and `activity()`
- [x] Split coupled filter into two independent checks:
  ```swift
  if !includeHidden {
    filters.append("\(prefix).display_in_timeline = 1")
  }
  if !includeSidechains {
    filters.append("\(prefix).is_sidechain = 0")
  }
  ```
- [x] Add tests for all 4 combinations
- [x] Fix `ConversationSearchService.getContext()` - removed hard-coded `is_sidechain = 0`
- [x] Fix `ConversationSearchService.getContextCounts()` - same fix

**Commits:**
- `fc703491 test(query): add sidechain filter decoupling test`
- `4edf184f fix(query): decouple is_sidechain from includeHidden filter`

This ~20 line change fixed the CLI correctness bug immediately.

### Phase 2b: Refactor CLI Functions (Full Solution)

**Files:**
- `app/Sources/ContextifyCore/Database/ContextifyQueryService.swift`

**API Strategy: Internal Implementation Function (Avoids Overload Ambiguity)**

Swift overloads with defaulted parameters can cause "ambiguous use of 'activity'" errors. For example, `activity(projectId: "p1")` could match both a boolean-based and filter-based signature if both have defaults.

**Solution:** Use an internal implementation function and keep the public surface boolean-based:

```swift
// Public API: boolean parameters (backward compatible)
public func activity(
  projectId: String? = nil,
  includeHidden: Bool = false,
  includeSidechains: Bool = false,
  // ... other params
) throws -> [ActivityItem] {
  let filter = EntryFilter(includeHidden: includeHidden, includeSidechains: includeSidechains)
  return try activityImpl(filter: filter, projectId: projectId, ...)
}

// Internal: EntryFilter-based implementation
internal func activityImpl(
  filter: EntryFilter,
  projectId: String? = nil,
  // ... other params
) throws -> [ActivityItem] {
  // Primary implementation using filter.sqlPredicate()
}
```

If we later want to expose `EntryFilter` publicly, make the filter parameter **required** (no default) to avoid ambiguity:

```swift
// Future: explicit filter overload (no default = no ambiguity)
public func activity(
  filter: EntryFilter,  // REQUIRED - no default
  projectId: String? = nil,
  // ... other params
) throws -> [ActivityItem]
```

**Alternative:** Keep `EntryFilter` internal until Phase 3 proves reuse across CLI + UI. Solo project - don't lock into public API shape prematurely.

**Tasks:**
- [ ] Add `includeSidechains: Bool = false` parameter to `activity()`
- [ ] Add `includeSidechains: Bool = false` parameter to `context()`
- [ ] Add transitional `filter: EntryFilter` overloads (internal or public)
- [ ] Refactor internal SQL generation to use `EntryFilter.sqlPredicate()`
- [ ] Update `recentActivity()` to accept optional `filter: EntryFilter?`
- [ ] Update `projectStats()` - keep filter in ON clause, not WHERE
- [ ] Add debug logging: log computed predicate at `.debug` level
- [ ] Remove `XCTExpectFailure` from Phase 0 tests (bug is now fixed)
- [ ] Add tests for all 4 combinations in `activity()` and `context()`
- [ ] Add test for sidechain anchor context window
- [ ] Run `swift test` - all tests must pass with new correct behavior

### Phase 3: Update UI Search Service

**Files:**
- `app/Sources/ContextifyCore/Search/ConversationSearchService.swift`

**Decision: Use `EntryFilter.search` for context retrieval**

The UI search policy requires explicit decisions:

| Function | Current Behavior | Decision | Rationale |
|----------|-----------------|----------|-----------|
| `search()` | No filtering (returns all FTS hits) | **Keep as-is** | Search should find everything; filtering happens at display |
| `getContext()` | Hard-codes `is_sidechain = 0` | **Use `.search`** | Include sidechains so context works for sidechain hits |
| `getContextCounts()` | Hard-codes `is_sidechain = 0` | **Use `.search`** | Match `getContext()` behavior |

**Note:** `ConversationSearchService.search()` currently does NOT filter `display_in_timeline`. This is intentional - it's a "deep search" that finds all matching entries. The UI can filter results at display time if needed. Changing this would be a user-visible behavior change requiring separate consideration.

**UI Hidden-Hit Policy (MUST DECIDE)**

Since `search()` is "deep search" and can return hidden entries (`display_in_timeline = 0`), but `getContext()` uses `.search` (which excludes hidden), we have a potential inconsistency:

- User clicks a hidden hit → `getContext()` filters it out → empty context or missing anchor

**Policy options:**

1. **Filter at display time (recommended for now):** Deep search may find hidden entries, but UI filters them from clickable results. Then `.search` for `getContext()` is correct because hidden hits are never clickable.

2. **Anchor-unfiltered context:** Make `getContext()` match CLI `context()` anchor semantics - always include the anchor entry by ID regardless of filter, apply filter only to before/after windows. Eliminates "empty window for existing hit" entirely.

**Decision:** Option 1 for Phase 3. Add test that hidden hits are filtered from displayed/clickable results in UI. If this causes user confusion later, revisit with Option 2.

**Tasks:**
- [ ] Use `EntryFilter.search.sqlAndFragment()` for `getContext()` queries (L237-265)
- [ ] Use `EntryFilter.search.sqlAndFragment()` for `getContextCounts()` queries (L299-340)
- [ ] Remove duplicated hard-coded filter SQL strings
- [ ] Add sidechain fixtures to `ConversationSearchServiceTests.swift`
- [ ] Add regression test: search finds sidechain entry, context retrieval includes neighbors
- [ ] Add hidden-hit policy test: hidden entries from search are filtered from clickable results
- [ ] Run `swift test` - all tests must pass

### Phase 4: CLI Interface Updates (Optional)

**Tasks:**
- [ ] Add `--include-sidechains` flag to CLI commands
- [ ] Add `--include-hidden` flag (if not already present)
- [ ] Update CLI help text to document filter options

## Regression Testing Strategy

### Pre-Refactor Validation

Before any code changes, capture current behavior as golden tests:

**Step 1: Audit existing tests**
```bash
# Find all tests for affected functions
grep -r "activity\|context\|recentActivity\|projectStats\|getContext" Tests/ContextifyCoreTests/*.swift -l
```

Current test coverage gaps:
- `QueryActivityTests` - Tests `activity()` but no sidechain entries in fixtures
- `QueryContextTests` - Tests `includeHidden` but not sidechain filtering
- `ConversationSearchServiceTests` - Tests `getContext` but no sidechain behavior
- No tests for `recentActivity()` or `projectStats()` filter behavior

**Step 2: Add characterization tests BEFORE refactoring**

Capture current output for known inputs:

```swift
func testActivity_characterization_defaultBehavior() async throws {
  // Setup: main-chain entries + sidechain entries + hidden entries
  // Call: activity(includeHidden: false)
  // Assert: Returns ONLY main-chain, visible entries
  // This test should PASS before and after refactor
}

func testContext_characterization_defaultBehavior() async throws {
  // Setup: anchor with mixed neighbors (main/sidechain, visible/hidden)
  // Call: context(entryId: anchor, includeHidden: false)
  // Assert: Returns anchor + ONLY main-chain, visible neighbors
  // This test should PASS before and after refactor
}
```

**Step 3: Add test fixtures with sidechain entries**

Current fixtures all use `isSidechain: 0`. Add entries with `isSidechain: 1`:

```swift
let sidechainEntry = TranscriptEntry(
  id: "sidechain-e1",
  transcriptId: "agent-abc123",  // Sidechain transcript
  projectId: "p1",
  // ...
  displayInTimeline: 1,  // Can be visible
  isSidechain: 1         // But is sidechain
)
```

### Test Matrix for Filter Combinations

Each affected function needs tests for all 4 visibility combinations:

| Test | includeHidden | includeSidechains | Expected Behavior |
|------|---------------|-------------------|-------------------|
| Default | false | false | Main-chain, visible only |
| Hidden only | true | false | Main-chain, all visibility |
| Sidechain only | false | true | All chains, visible only |
| All | true | true | Everything |

**Functions requiring this matrix:**
- [ ] `activity()` - 4 tests
- [ ] `context()` - 4 tests + anchor edge cases
- [ ] `recentActivity()` - 4 tests (when filter param added)
- [ ] `projectStats()` - 4 tests (verify LEFT JOIN semantics)
- [ ] `ConversationSearchService.getContext()` - 4 tests

### Existing Test Updates Required

| Test File | Current State | Required Update |
|-----------|--------------|-----------------|
| `QueryActivityTests.swift` | No sidechain fixtures | Add sidechain entries, verify filtered |
| `QueryContextTests.swift` | Tests `includeHidden` only | Add sidechain tests, verify decoupled |
| `ConversationSearchServiceTests.swift` | No sidechain tests | Add sidechain hit + context test |
| `ContextifyQueryServiceTests.swift` | Unknown coverage | Audit and add filter tests |

### Regression Detection Strategy

**Before each phase:**
1. Run full test suite: `swift test`
2. Capture any test output/behavior that relies on current filter coupling

**After each phase:**
1. Run full test suite - all existing tests must pass
2. Run new filter combination tests
3. Manually verify CLI behavior: `contextify-query activity --limit 5`

### QA Suite Updates

Check `scripts/qa/` for integration tests that may assume current filter behavior:

```bash
grep -r "activity\|context\|search" scripts/qa/*.sh
```

If QA tests create fixtures, ensure they include sidechain entries after this change.

## Test Requirements

### Unit Tests

```swift
func testEntryFilterDefaults() {
  let filter = EntryFilter()
  XCTAssertFalse(filter.includeHidden)
  XCTAssertFalse(filter.includeSidechains)
  XCTAssertNil(filter.kinds)
}

func testEntryFilterPresets() {
  // .timeline excludes both
  XCTAssertFalse(EntryFilter.timeline.includeHidden)
  XCTAssertFalse(EntryFilter.timeline.includeSidechains)

  // .search includes sidechains, excludes hidden
  XCTAssertFalse(EntryFilter.search.includeHidden)
  XCTAssertTrue(EntryFilter.search.includeSidechains)

  // .debug includes everything
  XCTAssertTrue(EntryFilter.debug.includeHidden)
  XCTAssertTrue(EntryFilter.debug.includeSidechains)
}

func testSqlPredicateGeneration() {
  // Default filter (timeline)
  let (sql1, args1) = EntryFilter.timeline.sqlPredicate()  // defaults to .e
  XCTAssertEqual(sql1, "e.display_in_timeline = 1 AND e.is_sidechain = 0")
  XCTAssertTrue(args1.isEmpty)

  // Search filter (includes sidechains, excludes hidden)
  let (sql2, args2) = EntryFilter.search.sqlPredicate()
  XCTAssertEqual(sql2, "e.display_in_timeline = 1")
  XCTAssertTrue(args2.isEmpty)

  // Debug filter (includes everything)
  let (sql3, args3) = EntryFilter.debug.sqlPredicate()
  XCTAssertEqual(sql3, "1 = 1")
  XCTAssertTrue(args3.isEmpty)

  // With kinds (array literal works directly)
  let filter4 = EntryFilter(kinds: [EntryFilter.Kind.user, EntryFilter.Kind.assistant])
  let (sql4, args4) = filter4.sqlPredicate()
  XCTAssertTrue(sql4.contains("e.kind IN (?, ?)"))
  XCTAssertEqual(args4.count, 2)

  // Empty kinds = no filter (same as nil)
  let filter5 = EntryFilter(kinds: [])
  let (sql5, _) = filter5.sqlPredicate()
  XCTAssertFalse(sql5.contains("kind"))  // No kind filter applied
}

func testSqlAndFragmentGeneration() {
  // Non-empty filter returns " AND ..."
  let (frag1, _) = EntryFilter.timeline.sqlAndFragment()
  XCTAssertTrue(frag1.hasPrefix(" AND "))

  // Empty filter returns ""
  let (frag2, _) = EntryFilter.debug.sqlAndFragment()
  XCTAssertEqual(frag2, "")
}
```

### Integration Tests

- [ ] `activity()` with all 4 visibility combinations
- [ ] `context()` with sidechain anchor, `includeSidechains: false` - verify empty neighbors
- [ ] `context()` with sidechain anchor, `includeSidechains: true` - verify neighbors returned
- [ ] `projectStats()` with filter in ON clause - verify projects with 0 entries still appear
- [ ] UI search finds sidechain hit, context retrieval includes neighbors

## Migration Notes

### Backward Compatibility

All existing CLI consumers continue to work:
- Default behavior unchanged (sidechains excluded from timeline views)
- Existing parameters preserved
- New parameters have sensible defaults
- Adding parameters with defaults is source-compatible for Swift call sites

### Breaking Changes

None in Phase 1-3. Phase 4 CLI changes are additive (new flags).

### No External Binary Consumers

`ContextifyCore` is not shipped as a dynamic framework with third-party clients. All consumers are compiled together, so adding parameters with defaults doesn't require binary compatibility concerns.

## Observability

Add debug-level logging when building queries:

```swift
import OSLog
private let log = Logger(subsystem: "dev.contextify", category: "EntryFilter")

// In query functions:
log.debug("activity filter: includeHidden=\(filter.includeHidden), includeSidechains=\(filter.includeSidechains)")
log.debug("activity predicate: \(filterSQL)")
```

This helps debug "why is my query empty?" issues without adding production overhead.

## Related Work

- **TRANSCRIPT-DATA-AUDIT (P1):** May identify additional filter dimensions needed
- **DECORATE-CONTEXTIFY-CALLS:** Uses `tool_invocations` table, may need filtering
- **Sidechain Ingestion:** Completed, this fixes the filter coupling introduced

## Future Extensions

The `EntryFilter` design accommodates future needs:

| Future Need | How to Add |
|-------------|------------|
| Filter by provider | Add `providers: Set<String>?` when use case emerges |
| Filter by content length | Add `maxContentLength: Int?` |
| Filter by model | Add `models: Set<String>?` |
| Filter by tool name | Add `toolNames: Set<String>?` (uses tool_invocations) |

## Open Questions (Resolved)

1. **Should scope filters move into EntryFilter?**
   - **Decision:** No. Keep separate. `EntryFilter` is entry-dimension predicates only.

2. **Should context() default to including hidden entries?**
   - **Decision:** No. Context is "timeline-like" by default. Use `.debug` for forensic views.

3. **What about UI search sidechain hits?**
   - **Decision:** `search()` stays unfiltered (deep search). `getContext()`/`getContextCounts()` use `.search` preset to include sidechains. Fixes empty-window bug.

4. **What does `kinds: []` (empty array) mean?**
   - **Decision:** Same as `nil` - no kind filter applied. Simpler than returning zero results.

5. **Should `kinds` be `Set<String>` or `[String]`?**
   - **Decision:** `[String]?` for ergonomic call sites. Sorted internally for deterministic SQL.

6. **How to prevent SQL injection via `prefix` parameter?**
   - **Decision:** Use `TableAlias` enum instead of raw string. Constrains to known-safe values.

7. **Should UI search filter `display_in_timeline`?**
   - **Decision:** No change to current behavior. `search()` is "deep search" - returns all FTS matches. Filtering happens at display time if needed. Changing this would be user-visible behavior change.

8. **Public API direction - booleans vs EntryFilter?**
   - **Decision:** Internal implementation function. Keep boolean params for public API (backward compatible), use internal `activityImpl(filter:)` for implementation. If exposing `EntryFilter` publicly later, make `filter:` parameter **required** (no default) to avoid Swift overload ambiguity.

9. **What is the intended UI behavior for hidden hits from deep search?**
   - **Decision:** Filter at display time. Hidden entries may be found by search, but UI filters them from clickable results. `getContext()` uses `.search` preset (excludes hidden), which is correct since hidden hits are never clickable. Add test to enforce this policy.

10. **Should `EntryFilter` be public or internal initially?**
    - **Decision:** Keep internal until Phase 3 proves reuse across CLI + UI. Solo project - don't lock into public API shape prematurely. SQL helpers can be internal.

## Acceptance Criteria

### Functional
- [x] `is_sidechain` filter decoupled from `includeHidden` (Phase 2a - DONE)
- [ ] `EntryFilter` type with `sqlPredicate()` and `sqlAndFragment()` helpers (Phase 1)
- [ ] `TableAlias` enum constrains prefix to known-safe values (SQL injection prevention)
- [ ] `kinds` uses `[String]?` for ergonomic call sites, deduped internally
- [ ] Kind constants (`EntryFilter.Kind.*`) defined to prevent stringly-typed drift
- [x] New `includeSidechains` parameter available on `activity()` and `context()` (Phase 2a - DONE)
- [ ] Internal `activityImpl(filter:)` / `contextImpl(filter:)` for implementation (Phase 2b)
- [ ] `recentActivity()` and `projectStats()` have optional filter override
- [ ] `projectStats()` keeps filter in ON clause (LEFT JOIN semantics preserved)
- [ ] UI `ConversationSearchService.getContext()` uses `EntryFilter.search`
- [ ] UI `ConversationSearchService.search()` unchanged (deep search)
- [ ] UI hidden-hit policy: hidden entries filtered from clickable results
- [ ] Debug logging for computed predicates

### Testing
- [ ] Phase 0 characterization tests with `XCTExpectFailure` for known bugs (skipped - went direct to Phase 2a)
- [x] All 4 visibility combinations tested for `context()` (Phase 2a - DONE)
- [ ] All 4 visibility combinations tested for `activity()` (Phase 2b)
- [ ] Sidechain anchor context window test (anchor returned, neighbors filtered)
- [ ] `projectStats()` LEFT JOIN regression test (projects with 0 entries still appear)
- [ ] UI search sidechain hit + context retrieval test
- [ ] UI hidden-hit policy test (hidden entries filtered from clickable results)
- [ ] Kinds determinism test (verify args order is sorted/deduped)
- [ ] Existing tests in `QueryActivityTests`, `QueryContextTests` updated with sidechain fixtures
- [ ] Full test suite passes: `swift test` with 0 failures

### Compatibility
- [x] No breaking changes to existing CLI consumers (Phase 2a - DONE)
- [x] Default behavior unchanged (sidechains excluded from timeline views) (Phase 2a - DONE)
- [ ] Internal implementation allows gradual migration to `EntryFilter` API (Phase 2b)
