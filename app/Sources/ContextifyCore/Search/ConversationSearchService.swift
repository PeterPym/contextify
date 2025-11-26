import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "ConversationSearch")

// MARK: - Conversation Search Models

/// Search scope for filtering results
public enum ConversationSearchScope: Sendable, Equatable {
  /// Quick Search - project-scoped
  case project(String)
  /// Deep Search default - all projects
  case allProjects
  /// Deep Search filtered - specific projects
  case projects([String])
}

/// Search request parameters
public struct ConversationSearchRequest: Sendable {
  public let query: String
  public let scope: ConversationSearchScope
  public let limit: Int
  public let offset: Int

  public init(query: String, scope: ConversationSearchScope, limit: Int = 50, offset: Int = 0) {
    self.query = query
    self.scope = scope
    self.limit = min(limit, 50)  // Cap at 50 per page
    self.offset = min(offset, 5000)  // Cap pagination depth
  }
}

/// Individual search hit with metadata
public struct ConversationSearchHit: Sendable, Identifiable, Equatable {
  public let id: String          // entry_id
  public let projectId: String
  public let projectName: String
  public let role: String
  public let content: String
  public let createdAt: Date
  public let rank: Double        // BM25 score
  public let snippet: String     // Highlighted snippet

  public init(
    id: String,
    projectId: String,
    projectName: String,
    role: String,
    content: String,
    createdAt: Date,
    rank: Double,
    snippet: String
  ) {
    self.id = id
    self.projectId = projectId
    self.projectName = projectName
    self.role = role
    self.content = content
    self.createdAt = createdAt
    self.rank = rank
    self.snippet = snippet
  }
}

/// Search result with pagination info
public struct ConversationSearchResult: Sendable {
  public let hits: [ConversationSearchHit]
  public let totalCount: Int
  public let cappedResults: Bool  // True if total > 5000
  public let query: String
  public let scope: ConversationSearchScope

  public init(
    hits: [ConversationSearchHit],
    totalCount: Int,
    cappedResults: Bool,
    query: String,
    scope: ConversationSearchScope
  ) {
    self.hits = hits
    self.totalCount = totalCount
    self.cappedResults = cappedResults
    self.query = query
    self.scope = scope
  }
}

// MARK: - Conversation Search Service

/// ConversationSearchService provides FTS5-based full-text search for user/assistant messages.
/// - Quick Search (HUD): project-scoped search via Enter
/// - Deep Search (Search Center): cross-project search via Cmd+Enter
///
/// This is read-only and actor-isolated for thread safety.
/// It wraps GRDB's read pool; it does not manage its own connection.
public actor ConversationSearchService {
  private let dbManager: DatabaseManager

  public init(dbManager: DatabaseManager = .shared) {
    self.dbManager = dbManager
  }

  /// Execute a search request
  public func search(_ request: ConversationSearchRequest) async throws -> ConversationSearchResult {
    let pool = try dbManager.pool

    return try await pool.read { db in
      // Build safe FTS query
      let ftsQuery = Self.buildSafeFTSQuery(request.query)

      guard !ftsQuery.isEmpty else {
        return ConversationSearchResult(hits: [], totalCount: 0, cappedResults: false,
                            query: request.query, scope: request.scope)
      }

      var sql = """
        SELECT
          f.entry_id,
          f.project_id,
          p.name as project_name,
          f.role,
          f.content,
          f.created_at,
          bm25(transcript_entries_fts) as rank,
          snippet(transcript_entries_fts, 0, '<mark>', '</mark>', '...', 64) as snippet
        FROM transcript_entries_fts f
        LEFT JOIN projects p ON p.id = f.project_id
        WHERE transcript_entries_fts MATCH ?
      """

      var arguments: [DatabaseValueConvertible] = [ftsQuery]

      // Add scope filter
      switch request.scope {
      case .project(let projectId):
        sql += " AND f.project_id = ?"
        arguments.append(projectId)
      case .allProjects:
        break
      case .projects(let projectIds):
        guard !projectIds.isEmpty else { break }
        let placeholders = projectIds.map { _ in "?" }.joined(separator: ", ")
        sql += " AND f.project_id IN (\(placeholders))"
        arguments.append(contentsOf: projectIds)
      }

      // Order by relevance, then recency as tie-breaker
      sql += """
        ORDER BY rank, f.created_at DESC
        LIMIT ? OFFSET ?
      """
      arguments.append(request.limit)
      arguments.append(request.offset)

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

      let hits = rows.map { row in
        ConversationSearchHit(
          id: row["entry_id"],
          projectId: row["project_id"],
          projectName: row["project_name"] ?? "Unknown",
          role: row["role"],
          content: row["content"],
          createdAt: Date(timeIntervalSince1970: TimeInterval(row["created_at"] as Int64)),
          rank: row["rank"],
          snippet: row["snippet"]
        )
      }

      // Get total count (capped query)
      var countSql = """
        SELECT COUNT(*) FROM transcript_entries_fts
        WHERE transcript_entries_fts MATCH ?
      """
      var countArgs: [DatabaseValueConvertible] = [ftsQuery]

      switch request.scope {
      case .project(let projectId):
        countSql += " AND project_id = ?"
        countArgs.append(projectId)
      case .allProjects:
        break
      case .projects(let projectIds):
        guard !projectIds.isEmpty else { break }
        let placeholders = projectIds.map { _ in "?" }.joined(separator: ", ")
        countSql += " AND project_id IN (\(placeholders))"
        countArgs.append(contentsOf: projectIds)
      }

      let rawCount = try Int.fetchOne(db, sql: countSql, arguments: StatementArguments(countArgs)) ?? 0
      let cappedResults = rawCount > 5000
      let totalCount = min(rawCount, 5000)

      log.debug("Search '\(request.query)' returned \(hits.count) hits (total: \(rawCount))")

      return ConversationSearchResult(
        hits: hits,
        totalCount: totalCount,
        cappedResults: cappedResults,
        query: request.query,
        scope: request.scope
      )
    }
  }

  /// Get surrounding context for a hit, matching timeline display semantics
  public func getContext(entryId: String, before: Int = 10, after: Int = 19) async throws -> [TranscriptEntry] {
    let pool = try dbManager.pool

    return try await pool.read { db in
      // Get the hit's project and created_at for ordering
      guard let hit = try Row.fetchOne(db, sql: """
        SELECT project_id, created_at FROM transcript_entries WHERE id = ?
      """, arguments: [entryId]) else {
        return []
      }

      let projectId: String = hit["project_id"]
      let createdAt: Int64 = hit["created_at"]

      // Get context entries using same predicates as timeline view
      // Uses created_at ordering to match timeline display
      return try TranscriptEntry.fetchAll(db, sql: """
        SELECT * FROM (
          SELECT * FROM transcript_entries
          WHERE project_id = ?
            AND display_in_timeline = 1
            AND created_at <= ?
          ORDER BY created_at DESC
          LIMIT ?
        )
        UNION ALL
        SELECT * FROM (
          SELECT * FROM transcript_entries
          WHERE project_id = ?
            AND display_in_timeline = 1
            AND created_at > ?
          ORDER BY created_at ASC
          LIMIT ?
        )
        ORDER BY created_at ASC
      """, arguments: [projectId, createdAt, before + 1, projectId, createdAt, after])
    }
  }

  /// Check if FTS index is populated (for "indexing in progress" UI)
  public func isIndexReady() async throws -> Bool {
    let pool = try dbManager.pool

    return try await pool.read { db in
      // Check if FTS table exists first
      let tableExists = try db.tableExists("transcript_entries_fts")
      guard tableExists else { return false }

      let ftsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries_fts") ?? 0
      let entryCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcript_entries
        WHERE kind IN ('user', 'assistant') AND display_in_timeline = 1
      """) ?? 0

      // Consider ready if FTS has at least 90% of entries, or both are 0
      return entryCount == 0 || ftsCount >= Int(Double(entryCount) * 0.9)
    }
  }

  // MARK: - Query Building

  /// Build a safe FTS5 query from user input.
  /// Treats input as space-separated AND of quoted tokens.
  /// E.g., "unread counts bug" -> "unread" AND "counts" AND "bug"
  public static func buildSafeFTSQuery(_ query: String) -> String {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    // Check if user provided an explicit phrase with quotes
    if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 2 {
      // User wants exact phrase - validate and pass through
      let phrase = String(trimmed.dropFirst().dropLast())
      let sanitized = phrase.replacingOccurrences(of: "\"", with: "")
      return "\"\(sanitized)\""
    }

    // Split on whitespace, wrap each token in quotes, join with AND
    let tokens = trimmed.components(separatedBy: .whitespaces)
      .filter { !$0.isEmpty }
      .map { token in
        // Remove any quotes and special chars from individual tokens
        let clean = token
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: "*", with: "")
          .replacingOccurrences(of: "(", with: "")
          .replacingOccurrences(of: ")", with: "")
        return "\"\(clean)\""
      }
      .filter { $0 != "\"\"" }  // Filter out empty tokens

    guard !tokens.isEmpty else { return "" }
    return tokens.joined(separator: " AND ")
  }
}
