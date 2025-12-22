import XCTest
@testable import ContextifyCore

final class EntryFilterTests: XCTestCase {

  // MARK: - Default Initialization

  func testDefaultInitialization() {
    let filter = EntryFilter()
    XCTAssertFalse(filter.includeHidden)
    XCTAssertFalse(filter.includeSidechains)
    XCTAssertNil(filter.kinds)
  }

  // MARK: - Presets

  func testTimelinePreset() {
    let filter = EntryFilter.timeline
    XCTAssertFalse(filter.includeHidden)
    XCTAssertFalse(filter.includeSidechains)
    XCTAssertNil(filter.kinds)
  }

  func testSearchPreset() {
    let filter = EntryFilter.search
    XCTAssertFalse(filter.includeHidden)
    XCTAssertTrue(filter.includeSidechains)
    XCTAssertNil(filter.kinds)
  }

  func testDebugPreset() {
    let filter = EntryFilter.debug
    XCTAssertTrue(filter.includeHidden)
    XCTAssertTrue(filter.includeSidechains)
    XCTAssertNil(filter.kinds)
  }

  // MARK: - SQL Predicate Generation (4 visibility combos)

  func testSqlPredicate_defaultFilter_excludesBothHiddenAndSidechains() {
    let filter = EntryFilter()
    let (sql, args) = filter.sqlPredicate()
    XCTAssertEqual(sql, "e.display_in_timeline = 1 AND e.is_sidechain = 0")
    XCTAssertTrue(args.isEmpty)
  }

  func testSqlPredicate_searchFilter_includesSidechainsOnly() {
    let filter = EntryFilter.search
    let (sql, args) = filter.sqlPredicate()
    XCTAssertEqual(sql, "e.display_in_timeline = 1")
    XCTAssertTrue(args.isEmpty)
  }

  func testSqlPredicate_includeHiddenOnly() {
    let filter = EntryFilter(includeHidden: true, includeSidechains: false)
    let (sql, args) = filter.sqlPredicate()
    XCTAssertEqual(sql, "e.is_sidechain = 0")
    XCTAssertTrue(args.isEmpty)
  }

  func testSqlPredicate_debugFilter_noFilters() {
    let filter = EntryFilter.debug
    let (sql, args) = filter.sqlPredicate()
    XCTAssertEqual(sql, "1 = 1")
    XCTAssertTrue(args.isEmpty)
  }

  // MARK: - SQL AND Fragment Generation

  func testSqlAndFragment_defaultFilter_hasLeadingAnd() {
    let filter = EntryFilter.timeline
    let (sql, args) = filter.sqlAndFragment()
    XCTAssertTrue(sql.hasPrefix(" AND "))
    XCTAssertEqual(sql, " AND e.display_in_timeline = 1 AND e.is_sidechain = 0")
    XCTAssertTrue(args.isEmpty)
  }

  func testSqlAndFragment_debugFilter_returnsEmpty() {
    let filter = EntryFilter.debug
    let (sql, args) = filter.sqlAndFragment()
    XCTAssertEqual(sql, "")
    XCTAssertTrue(args.isEmpty)
  }

  // MARK: - Table Alias

  func testSqlPredicate_withAlternateAlias() {
    let filter = EntryFilter.timeline
    let (sql, args) = filter.sqlPredicate(alias: .te)
    XCTAssertEqual(sql, "te.display_in_timeline = 1 AND te.is_sidechain = 0")
    XCTAssertTrue(args.isEmpty)
  }

  func testSqlAndFragment_withAlternateAlias() {
    let filter = EntryFilter.timeline
    let (sql, args) = filter.sqlAndFragment(alias: .te)
    XCTAssertEqual(sql, " AND te.display_in_timeline = 1 AND te.is_sidechain = 0")
    XCTAssertTrue(args.isEmpty)
  }

  // MARK: - Kinds Filtering

  func testSqlPredicate_withKinds() {
    let filter = EntryFilter(kinds: [EntryFilter.Kind.user, EntryFilter.Kind.assistant])
    let (sql, args) = filter.sqlPredicate()
    // kinds are sorted, so "assistant" comes before "user"
    XCTAssertTrue(sql.contains("e.kind IN (?, ?)"))
    XCTAssertEqual(args.count, 2)
    // Verify sorted order
    XCTAssertEqual(args[0] as? String, "assistant")
    XCTAssertEqual(args[1] as? String, "user")
  }

  func testSqlPredicate_kindsAreDeduplicated() {
    let filter = EntryFilter(kinds: ["user", "user", "assistant", "user"])
    let (sql, args) = filter.sqlPredicate()
    // Should only have 2 placeholders after dedup
    XCTAssertTrue(sql.contains("e.kind IN (?, ?)"))
    XCTAssertEqual(args.count, 2)
  }

  func testSqlPredicate_kindsAreSorted() {
    // Test that order is deterministic regardless of input order
    let filter1 = EntryFilter(kinds: ["user", "assistant", "tool_use"])
    let filter2 = EntryFilter(kinds: ["tool_use", "user", "assistant"])

    let (sql1, args1) = filter1.sqlPredicate()
    let (sql2, args2) = filter2.sqlPredicate()

    XCTAssertEqual(sql1, sql2)
    XCTAssertEqual(args1.count, args2.count)

    // Both should produce sorted args: assistant, tool_use, user
    XCTAssertEqual(args1[0] as? String, "assistant")
    XCTAssertEqual(args1[1] as? String, "tool_use")
    XCTAssertEqual(args1[2] as? String, "user")
  }

  func testSqlPredicate_emptyKinds_noKindFilter() {
    let filter = EntryFilter(kinds: [])
    let (sql, _) = filter.sqlPredicate()
    XCTAssertFalse(sql.contains("kind"))
  }

  func testSqlPredicate_nilKinds_noKindFilter() {
    let filter = EntryFilter(kinds: nil)
    let (sql, _) = filter.sqlPredicate()
    XCTAssertFalse(sql.contains("kind"))
  }

  // MARK: - Combined filters

  func testSqlPredicate_kindsWithVisibilityFilters() {
    let filter = EntryFilter(
      includeHidden: false,
      includeSidechains: false,
      kinds: [EntryFilter.Kind.user]
    )
    let (sql, args) = filter.sqlPredicate()
    XCTAssertTrue(sql.contains("e.display_in_timeline = 1"))
    XCTAssertTrue(sql.contains("e.is_sidechain = 0"))
    XCTAssertTrue(sql.contains("e.kind IN (?)"))
    XCTAssertEqual(args.count, 1)
    XCTAssertEqual(args[0] as? String, "user")
  }

  // MARK: - Equatable

  func testEquatable() {
    let filter1 = EntryFilter(includeHidden: true, includeSidechains: false, kinds: ["user"])
    let filter2 = EntryFilter(includeHidden: true, includeSidechains: false, kinds: ["user"])
    let filter3 = EntryFilter(includeHidden: false, includeSidechains: false, kinds: ["user"])

    XCTAssertEqual(filter1, filter2)
    XCTAssertNotEqual(filter1, filter3)
  }

  func testEquatable_kindsOrderDoesNotMatter() {
    // Different input orders should be equal after canonicalization
    let filter1 = EntryFilter(kinds: ["user", "assistant", "tool_use"])
    let filter2 = EntryFilter(kinds: ["tool_use", "user", "assistant"])
    let filter3 = EntryFilter(kinds: ["assistant", "tool_use", "user"])

    XCTAssertEqual(filter1, filter2, "Filters with same kinds in different order should be equal")
    XCTAssertEqual(filter2, filter3, "Filters with same kinds in different order should be equal")
    XCTAssertEqual(filter1, filter3, "Filters with same kinds in different order should be equal")

    // Verify canonicalization worked (kinds stored in sorted order)
    XCTAssertEqual(filter1.kinds, ["assistant", "tool_use", "user"])
    XCTAssertEqual(filter2.kinds, ["assistant", "tool_use", "user"])
  }

  func testEquatable_kindsDuplicatesRemoved() {
    // Duplicates should be removed during canonicalization
    let filter1 = EntryFilter(kinds: ["user", "user", "assistant"])
    let filter2 = EntryFilter(kinds: ["assistant", "user"])

    XCTAssertEqual(filter1, filter2, "Duplicates should be removed")
    XCTAssertEqual(filter1.kinds, ["assistant", "user"])
  }

  // MARK: - Kind Constants

  func testKindConstants() {
    XCTAssertEqual(EntryFilter.Kind.user, "user")
    XCTAssertEqual(EntryFilter.Kind.assistant, "assistant")
    XCTAssertEqual(EntryFilter.Kind.toolUse, "tool_use")
    XCTAssertEqual(EntryFilter.Kind.toolResult, "tool_result")
  }
}
