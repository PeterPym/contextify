import Foundation
import GRDB

/// Read-only query core for external tools.
public struct ContextifyQueryService: Sendable {
  private let pool: DatabasePool

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
  }

  public init(databaseURL: URL) throws {
    var config = Configuration()
    config.readonly = true
    config.busyMode = .timeout(5.0)
    self.pool = try DatabasePool(path: databaseURL.path, configuration: config)
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
      return VersionInfo(
        sqliteUserVersion: sqliteUserVersion,
        appSchemaVersion: DatabaseSchema.version,
        ftsEnabled: ftsEnabled
      )
    }
  }
}
