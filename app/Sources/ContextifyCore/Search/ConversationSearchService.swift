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
    self.limit = max(0, min(limit, 50))  // Cap at 50 per page, guard against negative
    self.offset = max(0, min(offset, 5000))  // Cap pagination depth, guard against negative
  }
}

/// Individual search hit with metadata
public struct ConversationSearchHit: Sendable, Identifiable, Equatable {
  public let id: String          // entry_id
  public let projectId: String
  public let projectName: String
  public let provider: String    // "claude.code" or "codex.cli"
  public let role: String
  public let content: String
  public let createdAt: Date
  public let rank: Double        // BM25 score
  public let snippet: String     // Highlighted snippet

  public init(
    id: String,
    projectId: String,
    projectName: String,
    provider: String,
    role: String,
    content: String,
    createdAt: Date,
    rank: Double,
    snippet: String
  ) {
    self.id = id
    self.projectId = projectId
    self.projectName = projectName
    self.provider = provider
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
          e.provider,
          f.role,
          f.content,
          COALESCE(e.timestamp, f.created_at) as created_at,
          bm25(transcript_entries_fts) as rank,
          snippet(transcript_entries_fts, 0, '<mark>', '</mark>', '...', 64) as snippet
        FROM transcript_entries_fts f
        LEFT JOIN projects p ON p.id = f.project_id
        LEFT JOIN transcript_entries e ON e.id = f.entry_id
        WHERE transcript_entries_fts MATCH ?
          AND e.id IS NOT NULL
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
        ORDER BY rank, e.timestamp DESC
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
          provider: row["provider"] ?? "claude.code",
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
  ///
  /// Returns entries before and after the hit, always including the hit itself.
  /// Uses `id` as secondary sort to ensure deterministic ordering when multiple
  /// entries share the same timestamp (fixes timestamp collision bug).
  public func getContext(entryId: String, before: Int = 10, after: Int = 10) async throws -> [TranscriptEntry] {
    let pool = try dbManager.pool

    return try await pool.read { db in
      // Get the hit's transcript, timestamp, and id for ordering
      guard let hit = try Row.fetchOne(db, sql: """
        SELECT transcript_id, timestamp, id FROM transcript_entries WHERE id = ?
      """, arguments: [entryId]) else {
        return []
      }

      let transcriptId: String = hit["transcript_id"]
      let timestamp: Int64 = hit["timestamp"]
      let hitId: String = hit["id"]

      // Get context entries from the SAME conversation (transcript)
      // Uses (timestamp, id) ordering for deterministic results when timestamps collide
      // The hit is explicitly included via the id comparison
      return try TranscriptEntry.fetchAll(db, sql: """
        SELECT * FROM (
          SELECT * FROM transcript_entries
          WHERE transcript_id = ?
            AND display_in_timeline = 1
            AND is_sidechain = 0
            AND (timestamp < ? OR (timestamp = ? AND id < ?))
          ORDER BY timestamp DESC, id DESC
          LIMIT ?
        )
        UNION ALL
        SELECT * FROM (
          SELECT * FROM transcript_entries
          WHERE transcript_id = ?
            AND display_in_timeline = 1
            AND is_sidechain = 0
            AND id = ?
        )
        UNION ALL
        SELECT * FROM (
          SELECT * FROM transcript_entries
          WHERE transcript_id = ?
            AND display_in_timeline = 1
            AND is_sidechain = 0
            AND (timestamp > ? OR (timestamp = ? AND id > ?))
          ORDER BY timestamp ASC, id ASC
          LIMIT ?
        )
        ORDER BY timestamp ASC, id ASC
      """, arguments: [
        transcriptId, timestamp, timestamp, hitId, before,  // before entries
        transcriptId, hitId,                                  // the hit itself
        transcriptId, timestamp, timestamp, hitId, after      // after entries
      ])
    }
  }

  /// Context counts for "load more" UI
  public struct ContextCounts: Sendable {
    public let earlierCount: Int
    public let laterCount: Int
  }

  /// Get counts of entries before/after the current context window
  /// Used to show "X earlier / Y later" in the UI
  public func getContextCounts(
    entryId: String,
    currentBefore: Int,
    currentAfter: Int
  ) async throws -> ContextCounts {
    let pool = try dbManager.pool

    return try await pool.read { db in
      // Get the hit's transcript, timestamp, and id for ordering
      guard let hit = try Row.fetchOne(db, sql: """
        SELECT transcript_id, timestamp, id FROM transcript_entries WHERE id = ?
      """, arguments: [entryId]) else {
        return ContextCounts(earlierCount: 0, laterCount: 0)
      }

      let transcriptId: String = hit["transcript_id"]
      let timestamp: Int64 = hit["timestamp"]
      let hitId: String = hit["id"]

      // Count entries strictly before the current window (same conversation)
      let earlierCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcript_entries
        WHERE transcript_id = ?
          AND display_in_timeline = 1
          AND is_sidechain = 0
          AND (timestamp < ? OR (timestamp = ? AND id < ?))
      """, arguments: [transcriptId, timestamp, timestamp, hitId]) ?? 0

      // Subtract entries already shown
      let actualEarlier = max(0, earlierCount - currentBefore)

      // Count entries strictly after the current window (same conversation)
      let laterCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcript_entries
        WHERE transcript_id = ?
          AND display_in_timeline = 1
          AND is_sidechain = 0
          AND (timestamp > ? OR (timestamp = ? AND id > ?))
      """, arguments: [transcriptId, timestamp, timestamp, hitId]) ?? 0

      // Subtract entries already shown
      let actualLater = max(0, laterCount - currentAfter)

      return ContextCounts(earlierCount: actualEarlier, laterCount: actualLater)
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
