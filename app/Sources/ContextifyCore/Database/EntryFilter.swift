import Foundation
import GRDB

/// Unified filter specification for transcript entry queries.
/// Covers entry-dimension predicates only (visibility, source, type).
/// Scope filters (project, transcript, time) remain separate parameters.
public struct EntryFilter: Sendable, Equatable {

  // MARK: - Visibility Filters

  /// Include entries with `display_in_timeline = 0`.
  /// Default: false (show only timeline-visible entries)
  public var includeHidden: Bool

  /// Include entries from sidechain (subagent) transcripts.
  /// Default: false (show only main-chain entries)
  public var includeSidechains: Bool

  // MARK: - Type Filters

  /// Filter by entry kind. Nil or empty means all kinds (no filter applied).
  /// Use EntryFilter.Kind constants to avoid typos.
  /// Note: Uses array for ergonomic call sites; sorted internally for deterministic SQL.
  public var kinds: [String]?

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

// MARK: - SQL Generation

extension EntryFilter {

  /// Known-safe table aliases for entry queries.
  /// Hardening against SQL injection by constraining to enum values.
  ///
  /// Trade-off: New aliases require modifying this enum (coupling point).
  /// For a solo project, this is acceptable - add cases as needed.
  public enum TableAlias: String, Sendable {
    case e      // Standard: "transcript_entries e"
    case te     // Alternative: "transcript_entries te"
  }

  /// Build filter clauses and args (shared implementation)
  private func buildClauses(alias: TableAlias) -> (clauses: [String], args: [any DatabaseValueConvertible]) {
    let prefix = alias.rawValue
    var clauses: [String] = []
    var args: [any DatabaseValueConvertible] = []

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
  func sqlPredicate(alias: TableAlias = .e) -> (sql: String, args: [any DatabaseValueConvertible]) {
    let (clauses, args) = buildClauses(alias: alias)
    let sql = clauses.isEmpty ? "1 = 1" : clauses.joined(separator: " AND ")
    return (sql, args)
  }

  /// Generate a SQL fragment with leading " AND " for appending to existing WHERE.
  /// Returns empty string if no filters apply.
  /// Use in: `WHERE existing_condition\(andFragment)`
  func sqlAndFragment(alias: TableAlias = .e) -> (sql: String, args: [any DatabaseValueConvertible]) {
    let (clauses, args) = buildClauses(alias: alias)
    if clauses.isEmpty {
      return ("", [])
    }
    return (" AND " + clauses.joined(separator: " AND "), args)
  }
}
