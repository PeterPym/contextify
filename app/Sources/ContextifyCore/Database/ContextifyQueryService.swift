import Foundation
import GRDB

/// Read-only query core for external tools.
public struct ContextifyQueryService: Sendable {
  private let pool: DatabasePool

  public struct ProjectListItem: Codable, Sendable {
    public let id: String
    public let name: String?
    public let rootPath: String
    public let hidden: Bool
    public let lastViewedTs: Double
    public let lastActivityTimestamp: Int?
    public let transcriptCount: Int?
    public let entryCount: Int?
  }

  public struct ProjectSuggestion: Codable, Sendable {
    public let id: String
    public let name: String?
    public let rootPath: String
  }

  public enum ProjectResolutionError: Error, Sendable {
    case notFound(path: String, suggestions: [ProjectSuggestion], totalProjectCount: Int)
    case ambiguous(path: String, candidates: [ProjectSuggestion])
  }

  public struct TranscriptListItem: Codable, Sendable {
    public let id: String
    public let projectId: String
    public let provider: String
    public let entryCount: Int?
    public let firstEntryTimestamp: Int?
    public let lastEntryTimestamp: Int?
    public let title: String?
  }

  public struct SearchHit: Codable, Sendable {
    public let id: String
    public let projectId: String
    public let projectName: String?
    public let transcriptId: String
    public let transcriptTitle: String?
    public let provider: String
    public let kind: String
    public let timestamp: Int
    public let score: Double
    public let contentSnippet: String
    public let contentTruncated: Bool
  }

  public struct ProjectStats: Codable, Sendable {
    public let projectId: String
    public let projectName: String?
    public let transcriptCount: Int
    public let entryCount: Int
    public let lastEntryTimestamp: Int?
    public let lastViewedTs: Double?
  }

  public struct VersionInfo: Codable, Sendable {
    public let sqliteUserVersion: Int
    public let appSchemaVersion: Int
    public let ftsEnabled: Bool
    public let summariesEnabled: Bool
  }

  public init(databaseURL: URL) throws {
    var config = Configuration()
    config.readonly = true
    config.busyMode = .timeout(5.0)
    config.prepareDatabase { db in
      // Defense-in-depth: ensure this connection never writes, even if misused.
      try? db.execute(sql: "PRAGMA query_only = ON")
      // Defense-in-depth: avoid loading/using schema from untrusted sources.
      try? db.execute(sql: "PRAGMA trusted_schema = OFF")
    }
    self.pool = try DatabasePool(path: databaseURL.path, configuration: config)
  }

  public func listProjects(includeHidden: Bool = false, limit: Int? = nil) throws -> [ProjectListItem] {
    try pool.read { db in
      var sql = """
        SELECT
          p.id AS id,
          p.name AS name,
          p.root_path AS root_path,
          p.hidden AS hidden,
          p.last_viewed_ts AS last_viewed_ts,
          (
            SELECT MAX(e.timestamp)
            FROM transcript_entries e
            WHERE e.project_id = p.id
          ) AS last_activity_ts,
          (
            SELECT COUNT(*)
            FROM transcripts t
            WHERE t.project_id = p.id
          ) AS transcript_count,
          (
            SELECT COUNT(*)
            FROM transcript_entries e
            WHERE e.project_id = p.id
          ) AS entry_count
        FROM projects p
      """
      var args: [DatabaseValueConvertible] = []
      if !includeHidden {
        sql += " WHERE p.hidden = 0"
      }
      sql += " ORDER BY last_activity_ts DESC NULLS LAST, p.last_viewed_ts DESC"
      if let limit {
        sql += " LIMIT ?"
        args.append(limit)
      }

      struct Row: FetchableRecord, Decodable {
        let id: String
        let name: String?
        let rootPath: String
        let hidden: Bool
        let lastViewedTs: Double
        let lastActivityTimestamp: Int?
        let transcriptCount: Int?
        let entryCount: Int?

        enum CodingKeys: String, CodingKey {
          case id
          case name
          case rootPath = "root_path"
          case hidden
          case lastViewedTs = "last_viewed_ts"
          case lastActivityTimestamp = "last_activity_ts"
          case transcriptCount = "transcript_count"
          case entryCount = "entry_count"
        }
      }

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
      return rows.map {
        ProjectListItem(
          id: $0.id,
          name: $0.name,
          rootPath: $0.rootPath,
          hidden: $0.hidden,
          lastViewedTs: $0.lastViewedTs,
          lastActivityTimestamp: $0.lastActivityTimestamp,
          transcriptCount: $0.transcriptCount,
          entryCount: $0.entryCount
        )
      }
    }
  }

  public func resolveProjectId(forPath path: String) throws -> String {
    let canonical = PathUtils.canonicalizePath(path)
    let canonicalFolded = foldPath(canonical)

    return try pool.read { db in
      struct Candidate: FetchableRecord, Decodable {
        let id: String
        let name: String?
        let rootPath: String

        enum CodingKeys: String, CodingKey {
          case id
          case name
          case rootPath = "root_path"
        }
      }

      let totalCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects WHERE hidden = 0") ?? 0
      let candidates = try Candidate.fetchAll(db, sql: "SELECT id, name, root_path FROM projects WHERE hidden = 0")

      let matches: [(candidate: Candidate, matchLength: Int)] = candidates.compactMap { candidate in
        let candidateCanonical = PathUtils.canonicalizePath(candidate.rootPath)
        let candidateFolded = foldPath(candidateCanonical)
        if canonicalFolded == candidateFolded {
          return (candidate, candidateFolded.count)
        }
        if canonicalFolded.hasPrefix(candidateFolded.hasSuffix("/") ? candidateFolded : candidateFolded + "/") {
          return (candidate, candidateFolded.count)
        }
        return nil
      }

      guard let best = matches.max(by: { $0.matchLength < $1.matchLength }) else {
        let suggestions = try recentProjectSuggestions(db, limit: 10)
        throw ProjectResolutionError.notFound(
          path: canonical,
          suggestions: suggestions,
          totalProjectCount: totalCount
        )
      }

      let bestLength = best.matchLength
      let tied = matches.filter { $0.matchLength == bestLength }
      if tied.count > 1 {
        let tiedSuggestions = tied.map {
          ProjectSuggestion(id: $0.candidate.id, name: $0.candidate.name, rootPath: $0.candidate.rootPath)
        }
        throw ProjectResolutionError.ambiguous(path: canonical, candidates: tiedSuggestions)
      }

      return best.candidate.id
    }
  }

  private func recentProjectSuggestions(_ db: Database, limit: Int) throws -> [ProjectSuggestion] {
    struct Row: FetchableRecord, Decodable {
      let id: String
      let name: String?
      let rootPath: String

      enum CodingKeys: String, CodingKey {
        case id
        case name
        case rootPath = "root_path"
      }
    }

    let sql = """
      SELECT id, name, root_path
      FROM projects
      WHERE hidden = 0
      ORDER BY last_viewed_ts DESC
      LIMIT ?
    """
    let rows = try Row.fetchAll(db, sql: sql, arguments: [limit])
    return rows.map { ProjectSuggestion(id: $0.id, name: $0.name, rootPath: $0.rootPath) }
  }

  private func foldPath(_ path: String) -> String {
    path.lowercased(with: Locale(identifier: "en_US_POSIX"))
  }

  public func listTranscripts(
    projectId: String,
    limit: Int = 50,
    timeRange: QueryTimeRange = QueryTimeRange()
  ) throws -> [TranscriptListItem] {
    try pool.read { db in
      var sql = """
        SELECT
          t.id AS id,
          t.project_id AS project_id,
          t.provider AS provider,
          (
            SELECT COUNT(*)
            FROM transcript_entries e
            WHERE e.transcript_id = t.id
          ) AS entry_count,
          (
            SELECT MIN(e.timestamp)
            FROM transcript_entries e
            WHERE e.transcript_id = t.id
          ) AS first_ts,
          (
            SELECT MAX(e.timestamp)
            FROM transcript_entries e
            WHERE e.transcript_id = t.id
          ) AS last_ts,
          tm.title AS title
        FROM transcripts t
        LEFT JOIN transcript_metadata tm ON tm.transcript_id = t.id
        WHERE t.project_id = ?
      """
      var args: [DatabaseValueConvertible] = [projectId]

      if let since = timeRange.sinceTimestamp, let until = timeRange.untilTimestamp {
        sql += """
           AND EXISTS (
             SELECT 1
             FROM transcript_entries e
             WHERE e.transcript_id = t.id
               AND e.timestamp >= ?
               AND e.timestamp <= ?
           )
        """
        args.append(since)
        args.append(until)
      } else if let since = timeRange.sinceTimestamp {
        sql += """
           AND EXISTS (
             SELECT 1
             FROM transcript_entries e
             WHERE e.transcript_id = t.id
               AND e.timestamp >= ?
           )
        """
        args.append(since)
      } else if let until = timeRange.untilTimestamp {
        sql += """
           AND EXISTS (
             SELECT 1
             FROM transcript_entries e
             WHERE e.transcript_id = t.id
               AND e.timestamp <= ?
           )
        """
        args.append(until)
      }

      sql += " ORDER BY last_ts DESC NULLS LAST LIMIT ?"
      args.append(limit)

      struct Row: FetchableRecord, Decodable {
        let id: String
        let projectId: String
        let provider: String
        let entryCount: Int?
        let firstEntryTimestamp: Int?
        let lastEntryTimestamp: Int?
        let title: String?

        enum CodingKeys: String, CodingKey {
          case id
          case projectId = "project_id"
          case provider
          case entryCount = "entry_count"
          case firstEntryTimestamp = "first_ts"
          case lastEntryTimestamp = "last_ts"
          case title
        }
      }

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
      return rows.map {
        TranscriptListItem(
          id: $0.id,
          projectId: $0.projectId,
          provider: $0.provider,
          entryCount: $0.entryCount,
          firstEntryTimestamp: $0.firstEntryTimestamp,
          lastEntryTimestamp: $0.lastEntryTimestamp,
          title: $0.title
        )
      }
    }
  }

  public func search(
    query: String,
    projectId: String? = nil,
    transcriptId: String? = nil,
    limit: Int = 50,
    includeHidden: Bool = false,
    timeRange: QueryTimeRange = QueryTimeRange()
  ) throws -> [SearchHit] {
    let safeQuery = ConversationSearchService.buildSafeFTSQuery(query)
    guard !safeQuery.isEmpty else { return [] }

    return try pool.read { db in
      guard try db.tableExists("transcript_entries_fts") else {
        throw NSError(
          domain: "dev.contextify.ContextifyQueryService",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey: "FTS search is not available in this database."]
        )
      }

      var sql = """
        SELECT
          e.id AS id,
          e.project_id AS project_id,
          p.name AS project_name,
          e.transcript_id AS transcript_id,
          tm.title AS transcript_title,
          e.provider AS provider,
          e.kind AS kind,
          e.timestamp AS timestamp,
          bm25(transcript_entries_fts) AS score,
          COALESCE(snippet(transcript_entries_fts, 0, '', '', '…', 10), '') AS snippet,
          CASE
            WHEN length(e.content) > length(COALESCE(snippet(transcript_entries_fts, 0, '', '', '…', 10), '')) THEN 1
            ELSE 0
          END AS content_truncated
        FROM transcript_entries_fts
        JOIN transcript_entries e ON e.id = transcript_entries_fts.entry_id
        LEFT JOIN projects p ON p.id = e.project_id
        LEFT JOIN transcript_metadata tm ON tm.transcript_id = e.transcript_id
        WHERE transcript_entries_fts MATCH ?
      """
      var args: [DatabaseValueConvertible] = [safeQuery]

      if !includeHidden {
        sql += " AND e.display_in_timeline = 1"
      }
      if let projectId {
        sql += " AND e.project_id = ?"
        args.append(projectId)
      }
      if let transcriptId {
        sql += " AND e.transcript_id = ?"
        args.append(transcriptId)
      }
      if let since = timeRange.sinceTimestamp {
        sql += " AND e.timestamp >= ?"
        args.append(since)
      }
      if let until = timeRange.untilTimestamp {
        sql += " AND e.timestamp <= ?"
        args.append(until)
      }

      sql += " ORDER BY score, e.timestamp DESC LIMIT ?"
      args.append(limit)

      struct Row: FetchableRecord, Decodable {
        let id: String
        let projectId: String
        let projectName: String?
        let transcriptId: String
        let transcriptTitle: String?
        let provider: String
        let kind: String
        let timestamp: Int
        let score: Double
        let contentSnippet: String
        let contentTruncated: Bool

        enum CodingKeys: String, CodingKey {
          case id
          case projectId = "project_id"
          case projectName = "project_name"
          case transcriptId = "transcript_id"
          case transcriptTitle = "transcript_title"
          case provider
          case kind
          case timestamp
          case score
          case contentSnippet = "snippet"
          case contentTruncated = "content_truncated"
        }
      }

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
      return rows.map {
        SearchHit(
          id: $0.id,
          projectId: $0.projectId,
          projectName: $0.projectName,
          transcriptId: $0.transcriptId,
          transcriptTitle: $0.transcriptTitle,
          provider: $0.provider,
          kind: $0.kind,
          timestamp: $0.timestamp,
          score: $0.score,
          contentSnippet: $0.contentSnippet,
          contentTruncated: $0.contentTruncated
        )
      }
    }
  }

  /// Most recent timeline-visible entries, optionally project scoped.
  public func recentActivity(projectId: String? = nil, limit: Int = 50) throws -> [TranscriptEntry] {
    try pool.read { db in
      var sql = """
        SELECT *
        FROM transcript_entries
        WHERE display_in_timeline = 1
      """
      var args: [DatabaseValueConvertible] = []
      if let projectId {
        sql += " AND project_id = ?"
        args.append(projectId)
      }
      sql += " ORDER BY timestamp DESC, created_at DESC, id DESC LIMIT ?"
      args.append(limit)
      return try TranscriptEntry.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    }
  }

  /// Full-text search across entries (FTS5), optionally project scoped.
  public func ftsSearch(query: String, projectId: String? = nil, limit: Int = 50) throws -> [TranscriptEntry] {
    let safeQuery = ConversationSearchService.buildSafeFTSQuery(query)
    guard !safeQuery.isEmpty else { return [] }
    return try pool.read { db in
      guard try db.tableExists("transcript_entries_fts") else {
        throw NSError(
          domain: "dev.contextify.ContextifyQueryService",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "FTS search is not available in this database."]
        )
      }
      var sql = """
        SELECT e.*
        FROM transcript_entries_fts f
        JOIN transcript_entries e ON e.id = f.entry_id
        WHERE f.transcript_entries_fts MATCH ?
      """
      var args: [DatabaseValueConvertible] = [safeQuery]
      if let projectId {
        sql += " AND f.project_id = ?"
        args.append(projectId)
      }
      sql += " ORDER BY bm25(transcript_entries_fts), e.timestamp DESC LIMIT ?"
      args.append(limit)
      return try TranscriptEntry.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    }
  }

  /// Transcript-level summaries, optionally project scoped.
  public func summaries(projectId: String? = nil, limit: Int = 50) throws -> [TranscriptMetadataRecord] {
    try pool.read { db in
      guard try db.tableExists("transcript_metadata") else {
        throw NSError(
          domain: "dev.contextify.ContextifyQueryService",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Summaries are not available in this database."]
        )
      }
      var sql = """
        SELECT *
        FROM transcript_metadata
      """
      var args: [DatabaseValueConvertible] = []
      if let projectId {
        sql += " WHERE project_id = ?"
        args.append(projectId)
      }
      sql += " ORDER BY generated_at DESC LIMIT ?"
      args.append(limit)
      return try TranscriptMetadataRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    }
  }

  /// Aggregate stats per project, or for a specific project if provided.
  public func projectStats(projectId: String? = nil) throws -> [ProjectStats] {
    try pool.read { db in
      var sql = """
        SELECT
          p.id AS project_id,
          p.name AS project_name,
          COUNT(DISTINCT t.id) AS transcript_count,
          COUNT(e.id) AS entry_count,
          MAX(e.timestamp) AS last_entry_timestamp,
          p.last_viewed_ts AS last_viewed_ts
        FROM projects p
        LEFT JOIN transcripts t ON t.project_id = p.id
        LEFT JOIN transcript_entries e
          ON e.project_id = p.id AND e.display_in_timeline = 1
      """
      var args: [DatabaseValueConvertible] = []
      if let projectId {
        sql += " WHERE p.id = ?"
        args.append(projectId)
      }
      sql += " GROUP BY p.id ORDER BY last_entry_timestamp DESC NULLS LAST"

      struct RowStats: FetchableRecord, Decodable {
        let projectId: String
        let projectName: String?
        let transcriptCount: Int
        let entryCount: Int
        let lastEntryTimestamp: Int?
        let lastViewedTs: Double?

        enum CodingKeys: String, CodingKey {
          case projectId = "project_id"
          case projectName = "project_name"
          case transcriptCount = "transcript_count"
          case entryCount = "entry_count"
          case lastEntryTimestamp = "last_entry_timestamp"
          case lastViewedTs = "last_viewed_ts"
        }
      }

      let rows = try RowStats.fetchAll(db, sql: sql, arguments: StatementArguments(args))
      return rows.map {
        ProjectStats(
          projectId: $0.projectId,
          projectName: $0.projectName,
          transcriptCount: $0.transcriptCount,
          entryCount: $0.entryCount,
          lastEntryTimestamp: $0.lastEntryTimestamp,
          lastViewedTs: $0.lastViewedTs
        )
      }
    }
  }

  /// Database version and feature availability.
  public func versionInfo() throws -> VersionInfo {
    try pool.read { db in
      let sqliteUserVersion = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
      let ftsEnabled = (try? db.tableExists("transcript_entries_fts")) ?? false
      let summariesEnabled = (try? db.tableExists("transcript_metadata")) ?? false
      return VersionInfo(
        sqliteUserVersion: sqliteUserVersion,
        appSchemaVersion: DatabaseSchema.version,
        ftsEnabled: ftsEnabled,
        summariesEnabled: summariesEnabled
      )
    }
  }
}
