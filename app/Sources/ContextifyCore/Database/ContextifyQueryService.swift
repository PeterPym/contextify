import Foundation
import GRDB

#if canImport(OSLog)
import OSLog
private let log = Logger(subsystem: "dev.contextify", category: "ContextifyQueryService")
#else
private let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "ContextifyQueryService")
#endif

/// Read-only query core for external tools.
public struct ContextifyQueryService: Sendable {
  public enum QueryError: Error, Sendable, Equatable {
    case featureUnavailable(feature: String, message: String)
  }

  /// Structured errors for cloud pull import failures.
  /// Each case has a stable error code for support reporting.
  public enum CloudPullImportError: Error, LocalizedError, Sendable {
    /// Project root_path invariant failed: row expected but not found after insert-or-skip.
    case projectRootPathInvariant(serverId: String, rootPath: String)

    /// A stable error code string suitable for support reporting.
    public var errorCode: String {
      switch self {
      case .projectRootPathInvariant: return "SYNC_PROJECT_ROOTPATH_INVARIANT"
      }
    }

    /// Human-readable description via LocalizedError protocol.
    public var errorDescription: String? {
      switch self {
      case .projectRootPathInvariant(let serverId, let rootPath):
        return "[\(errorCode)] Project root_path invariant failed: no local row for root_path=\"\(rootPath)\" after insert (server id=\(serverId))"
      }
    }

    /// Generates a mailto: URL for reporting this error to support.
    public func supportMailtoURL(deviceName: String? = nil) -> URL? {
      let subject = "Contextify Sync Error: \(errorCode)"
      var body = "Error: \(errorDescription ?? errorCode)\n"
      body += "Timestamp: \(ISO8601DateFormatter().string(from: Date()))\n"
      if let deviceName { body += "Device: \(deviceName)\n" }
      body += "\n--- Please describe what you were doing when this occurred ---\n"

      var components = URLComponents()
      components.scheme = "mailto"
      components.path = "support@contextify.sh"
      components.queryItems = [
        URLQueryItem(name: "subject", value: subject),
        URLQueryItem(name: "body", value: body),
      ]
      return components.url
    }
  }
  private let pool: DatabasePool
  private let entriesPKIndex: String?

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
    public let gitCommit: String?
    public let cwd: String?
  }

  public struct EntryPayload: Codable, Sendable {
    public let id: String
    public let projectId: String
    public let transcriptId: String
    public let provider: String
    public let kind: String
    public let timestamp: Int
    public let createdAt: Int
    public let displayInTimeline: Int
    public let content: String?
    public let contentTruncated: Bool?
    public let contentFullSize: Int?
  }

  public struct EntryResult: Codable, Sendable {
    public let entry: EntryPayload
    public let projectName: String?
    public let transcriptTitle: String?
  }

  public struct ContextMeta: Codable, Sendable {
    public let firstEntryId: String
    public let lastEntryId: String
    public let hasMoreBefore: Bool
    public let hasMoreAfter: Bool
    public let transcriptEntryCount: Int?
  }

  public struct ContextResult: Codable, Sendable {
    public let anchor: EntryPayload
    public let before: [EntryPayload]
    public let after: [EntryPayload]
    public let meta: ContextMeta
  }

  public enum EntryLookupError: Error, Sendable {
    case notFound(entryId: String)
  }

  public struct ActivityItem: Codable, Sendable {
    public let entry: EntryPayload
    public let projectName: String?
    public let transcriptTitle: String?
  }

  public struct DatabaseCounts: Codable, Sendable {
    public let projectCount: Int
    public let transcriptCount: Int
    public let entryCount: Int
  }

  public struct ProjectStats: Codable, Sendable {
    public let projectId: String
    public let projectName: String?
    public let transcriptCount: Int
    public let entryCount: Int
    public let lastEntryTimestamp: Int?
    public let lastViewedTs: Double?

    enum CodingKeys: String, CodingKey {
      case projectId
      case projectName
      case transcriptCount
      case entryCount
      case lastEntryTimestamp
      case lastViewedTs = "lastViewedTimestamp"
    }
  }

  public struct VersionInfo: Codable, Sendable {
    public let sqliteUserVersion: Int
    public let expectedSchemaVersion: Int
    public let ftsEnabled: Bool
    public let summariesEnabled: Bool

    public var appSchemaVersion: Int { expectedSchemaVersion }

    public init(
      sqliteUserVersion: Int,
      expectedSchemaVersion: Int,
      ftsEnabled: Bool,
      summariesEnabled: Bool
    ) {
      self.sqliteUserVersion = sqliteUserVersion
      self.expectedSchemaVersion = expectedSchemaVersion
      self.ftsEnabled = ftsEnabled
      self.summariesEnabled = summariesEnabled
    }

    enum CodingKeys: String, CodingKey {
      case sqliteUserVersion
      case expectedSchemaVersion
      case appSchemaVersion
      case ftsEnabled
      case summariesEnabled
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      sqliteUserVersion = try container.decode(Int.self, forKey: .sqliteUserVersion)
      if let expected = try container.decodeIfPresent(Int.self, forKey: .expectedSchemaVersion) {
        expectedSchemaVersion = expected
      } else if let legacy = try container.decodeIfPresent(Int.self, forKey: .appSchemaVersion) {
        expectedSchemaVersion = legacy
      } else {
        expectedSchemaVersion = 0
      }
      ftsEnabled = try container.decode(Bool.self, forKey: .ftsEnabled)
      summariesEnabled = try container.decode(Bool.self, forKey: .summariesEnabled)
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(sqliteUserVersion, forKey: .sqliteUserVersion)
      try container.encode(expectedSchemaVersion, forKey: .expectedSchemaVersion)
      try container.encode(expectedSchemaVersion, forKey: .appSchemaVersion)
      try container.encode(ftsEnabled, forKey: .ftsEnabled)
      try container.encode(summariesEnabled, forKey: .summariesEnabled)
    }
  }

  /// Create a query service connected to the given database.
  ///
  /// - Parameters:
  ///   - databaseURL: Path to the SQLite database file.
  ///   - readOnly: When true (default), the connection refuses writes via
  ///     `config.readonly` and `PRAGMA query_only = ON`. Set to false for
  ///     operations that need to write (e.g., cloud sync pull/import).
  public init(databaseURL: URL, readOnly: Bool = true) throws {
    var config = Configuration()
    config.readonly = readOnly
    config.busyMode = .timeout(5.0)
    config.prepareDatabase { db in
      if readOnly {
        // Defense-in-depth: ensure this connection never writes, even if misused.
        do { try db.execute(sql: "PRAGMA query_only = ON") }
        catch { log.warning("Failed to set PRAGMA query_only=ON: \(error.localizedDescription)") }
      }
      // Defense-in-depth: avoid loading/using schema from untrusted sources.
      do { try db.execute(sql: "PRAGMA trusted_schema = OFF") }
      catch { log.warning("Failed to set PRAGMA trusted_schema=OFF: \(error.localizedDescription)") }
    }
    self.pool = try DatabasePool(path: databaseURL.path, configuration: config)
    self.entriesPKIndex = try Self.detectPKIndex(pool: self.pool)
  }

  /// Detect the PK autoindex name for transcript_entries at runtime.
  /// Returns nil if no PK index exists (rowid table) or name is unexpected.
  private static func detectPKIndex(pool: DatabasePool) throws -> String? {
    try pool.read { db in
      let sql = "SELECT name FROM pragma_index_list('transcript_entries') WHERE origin = 'pk' LIMIT 1"
      guard let name = try String.fetchOne(db, sql: sql) else { return nil }
      guard name.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil else { return nil }
      return name
    }
  }

  /// Build JOIN clause for FTS queries, using INDEXED BY when PK index is known.
  /// Falls back to plain JOIN if PK index wasn't detected (slower but correct).
  func ftsJoinEntries(alias: String = "e", ftsAlias: String = "transcript_entries_fts", left: Bool = false) -> String {
    let joinType = left ? "LEFT JOIN" : "JOIN"
    if let idx = entriesPKIndex {
      return "\(joinType) transcript_entries \(alias) INDEXED BY \(idx) ON \(alias).id = \(ftsAlias).entry_id"
    }
    return "\(joinType) transcript_entries \(alias) ON \(alias).id = \(ftsAlias).entry_id"
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

  // MARK: - Shared FTS Filter Builder

  /// Shared WHERE clause components for FTS search and count queries.
  /// Prevents filter divergence between search() and searchCount().
  private struct FTSFilterClause {
    /// SQL fragment to append after "WHERE ... MATCH ?", e.g. " AND e.display_in_timeline = 1 AND ..."
    let whereSQL: String
    /// All arguments: first is the MATCH query, followed by filter arguments
    let arguments: [DatabaseValueConvertible]
    /// If true, the caller should short-circuit with an empty/zero result (empty projectIds array)
    let emptyResult: Bool
  }

  private func buildFTSFilterClause(
    query: String,
    projectIds: [String]?,
    transcriptId: String?,
    includeHidden: Bool,
    timeRange: QueryTimeRange,
    kinds: [String]?,
    device: String? = nil
  ) -> FTSFilterClause {
    var whereParts: [String] = []
    var args: [DatabaseValueConvertible] = [query]

    if !includeHidden {
      whereParts.append("e.display_in_timeline = 1")
    }
    if let projectIds = projectIds {
      if projectIds.isEmpty {
        return FTSFilterClause(whereSQL: "", arguments: args, emptyResult: true)
      }
      let uniqueIds = Array(Set(projectIds)).sorted()
      let placeholders = uniqueIds.map { _ in "?" }.joined(separator: ", ")
      whereParts.append("e.project_id IN (\(placeholders))")
      for id in uniqueIds { args.append(id) }
    }
    if let transcriptId {
      whereParts.append("e.transcript_id = ?")
      args.append(transcriptId)
    }
    if let kinds, !kinds.isEmpty {
      let sortedKinds = Array(Set(kinds)).sorted()
      let placeholders = sortedKinds.map { _ in "?" }.joined(separator: ", ")
      whereParts.append("e.kind IN (\(placeholders))")
      args.append(contentsOf: sortedKinds)
    }
    if let since = timeRange.sinceTimestamp {
      whereParts.append("e.timestamp >= ?")
      args.append(since)
    }
    if let until = timeRange.untilTimestamp {
      whereParts.append("e.timestamp <= ?")
      args.append(until)
    }
    if let device {
      // Match device name when present; fall back to device ID only when name is absent.
      // This prevents a UUID substring coincidentally matching a different device's entries.
      whereParts.append("""
        (
          (e.source_device_name IS NOT NULL AND e.source_device_name != ''
            AND e.source_device_name LIKE '%' || ? || '%' COLLATE NOCASE)
          OR
          ((e.source_device_name IS NULL OR e.source_device_name = '')
            AND e.source_device_id LIKE '%' || ? || '%' COLLATE NOCASE)
        )
        """)
      args.append(device)
      args.append(device)
    }

    let whereSQL = whereParts.isEmpty ? "" : " AND " + whereParts.joined(separator: " AND ")
    return FTSFilterClause(whereSQL: whereSQL, arguments: args, emptyResult: false)
  }

  public func search(
    query: String,
    projectIds: [String]? = nil,
    transcriptId: String? = nil,
    limit: Int = 50,
    offset: Int = 0,
    includeHidden: Bool = false,
    timeRange: QueryTimeRange = QueryTimeRange(),
    kinds: [String]? = nil,
    snippetTokens: Int = 10,
    treatAsFTS: Bool = false,
    device: String? = nil
  ) throws -> [SearchHit] {
    let safeQuery = treatAsFTS ? query : FTSQueryBuilder.buildSafeFTSQuery(query)
    guard !safeQuery.isEmpty else { return [] }

    let filter = buildFTSFilterClause(
      query: safeQuery,
      projectIds: projectIds,
      transcriptId: transcriptId,
      includeHidden: includeHidden,
      timeRange: timeRange,
      kinds: kinds,
      device: device
    )
    guard !filter.emptyResult else { return [] }

    return try pool.read { db in
      guard try db.tableExists("transcript_entries_fts") else {
        throw QueryError.featureUnavailable(feature: "fts_search", message: "FTS search is not available in this database.")
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
          e.git_commit AS git_commit,
          e.cwd AS cwd,
          bm25(transcript_entries_fts) AS score,
          COALESCE(snippet(transcript_entries_fts, 0, '', '', '…', \(snippetTokens)), '') AS snippet,
          CASE
            WHEN instr(snippet(transcript_entries_fts, 0, '', '', '…', \(snippetTokens)), '…') > 0 THEN 1
            ELSE 0
          END AS content_truncated
        FROM transcript_entries_fts
        \(ftsJoinEntries())
        LEFT JOIN projects p ON p.id = e.project_id
        LEFT JOIN transcript_metadata tm ON tm.transcript_id = e.transcript_id
        WHERE transcript_entries_fts MATCH ?
      """
      sql += filter.whereSQL

      // Order by BM25 relevance (more negative = better match), then recency, then id for stability
      sql += " ORDER BY score ASC, e.timestamp DESC, e.id ASC"
      sql += " LIMIT ?"
      var args = filter.arguments
      args.append(limit)
      if offset > 0 {
        sql += " OFFSET ?"
        args.append(offset)
      }

      struct Row: FetchableRecord, Decodable {
        let id: String
        let projectId: String
        let projectName: String?
        let transcriptId: String
        let transcriptTitle: String?
        let provider: String
        let kind: String
        let timestamp: Int
        let gitCommit: String?
        let cwd: String?
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
          case gitCommit = "git_commit"
          case cwd
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
          contentTruncated: $0.contentTruncated,
          gitCommit: $0.gitCommit,
          cwd: $0.cwd
        )
      }
    }
  }

  /// Returns per-term match counts for an OR query.
  /// For "term1 OR term2 OR term3", returns ["term1": 42, "term2": 18, "term3": 5].
  /// Returns nil if the query is not an OR query.
  public func searchTermCounts(
    query: String,
    projectIds: [String]? = nil,
    transcriptId: String? = nil,
    includeHidden: Bool = false,
    timeRange: QueryTimeRange = QueryTimeRange(),
    kinds: [String]? = nil,
    device: String? = nil
  ) throws -> [String: Int]? {
    let terms = Self.parseORTerms(query)
    guard terms.count >= 2 else { return nil }

    // Deduplicate preserving first-seen order, cap at 10 terms to bound query cost
    var seen = Set<String>()
    let uniqueTerms = terms.filter { seen.insert($0).inserted }
    guard uniqueTerms.count <= 10 else { return nil }

    var result: [String: Int] = [:]
    for term in uniqueTerms {
      let count = try searchCount(
        query: term,
        projectIds: projectIds,
        transcriptId: transcriptId,
        includeHidden: includeHidden,
        timeRange: timeRange,
        kinds: kinds,
        treatAsFTS: true,
        device: device
      )
      result[term] = count
    }
    return result
  }

  /// Parses a simple OR query into individual terms.
  /// "fuck OR fucking OR fucked" -> ["fuck", "fucking", "fucked"]
  /// "\"memory leak\" OR \"out of memory\"" -> ["\"memory leak\"", "\"out of memory\""]
  /// Returns empty array if the query doesn't use OR or has complex structure (AND, NOT, parentheses).
  static func parseORTerms(_ query: String) -> [String] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

    // Bail on complex queries with AND, NOT, or parentheses
    if trimmed.range(of: "\\bAND\\b", options: .regularExpression) != nil { return [] }
    if trimmed.range(of: "\\bNOT\\b", options: .regularExpression) != nil { return [] }
    if trimmed.contains("(") || trimmed.contains(")") { return [] }

    // Must contain OR (case-sensitive, FTS5 convention)
    guard trimmed.range(of: "\\s+OR\\s+", options: .regularExpression) != nil else { return [] }

    // Bail if OR appears inside a quoted phrase (e.g., "fear OR loathing" OR vegas)
    // Check: after splitting, if any term has unbalanced quotes, the split was wrong
    // Split on OR with flexible whitespace using regex replacement
    let normalized = trimmed.replacingOccurrences(
      of: "\\s+OR\\s+",
      with: "\n",
      options: .regularExpression
    )
    let terms = normalized.components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard terms.count >= 2 else { return [] }

    // Bail if any term has unbalanced quotes (split broke a quoted phrase)
    for term in terms {
      let quoteCount = term.filter { $0 == "\"" }.count
      if quoteCount % 2 != 0 { return [] }
    }

    return terms
  }

  /// Returns total match count for a search query without fetching results.
  /// Uses the same filters as `search()` via shared `buildFTSFilterClause()`.
  public func searchCount(
    query: String,
    projectIds: [String]? = nil,
    transcriptId: String? = nil,
    includeHidden: Bool = false,
    timeRange: QueryTimeRange = QueryTimeRange(),
    kinds: [String]? = nil,
    treatAsFTS: Bool = false,
    device: String? = nil
  ) throws -> Int {
    let safeQuery = treatAsFTS ? query : FTSQueryBuilder.buildSafeFTSQuery(query)
    guard !safeQuery.isEmpty else { return 0 }

    let filter = buildFTSFilterClause(
      query: safeQuery,
      projectIds: projectIds,
      transcriptId: transcriptId,
      includeHidden: includeHidden,
      timeRange: timeRange,
      kinds: kinds,
      device: device
    )
    guard !filter.emptyResult else { return 0 }

    return try pool.read { db in
      guard try db.tableExists("transcript_entries_fts") else {
        throw QueryError.featureUnavailable(feature: "fts_search", message: "FTS search is not available in this database.")
      }

      // When no additional filters reference the entries table, use faster FTS-only count
      let trimmedWhere = filter.whereSQL.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedWhere.isEmpty {
        let sql = "SELECT COUNT(*) FROM transcript_entries_fts WHERE transcript_entries_fts MATCH ?"
        guard let matchArg = filter.arguments.first else { return 0 }
        return try Int.fetchOne(db, sql: sql, arguments: [matchArg]) ?? 0
      }

      let sql = """
        SELECT COUNT(*)
        FROM transcript_entries_fts
        \(ftsJoinEntries())
        WHERE transcript_entries_fts MATCH ?
      """ + filter.whereSQL

      return try Int.fetchOne(db, sql: sql, arguments: StatementArguments(filter.arguments)) ?? 0
    }
  }

  // Backward compatibility overload for old single projectId parameter
  @available(*, deprecated, message: "Use search(query:projectIds:...) instead")
  @_disfavoredOverload
  public func search(
    query: String,
    projectId: String?,
    transcriptId: String? = nil,
    limit: Int = 50,
    includeHidden: Bool = false,
    timeRange: QueryTimeRange = QueryTimeRange(),
    kinds: [String]? = nil,
    treatAsFTS: Bool = false
  ) throws -> [SearchHit] {
    let projectIds = projectId.map { [$0] }
    return try search(
      query: query,
      projectIds: projectIds,
      transcriptId: transcriptId,
      limit: limit,
      includeHidden: includeHidden,
      timeRange: timeRange,
      kinds: kinds,
      treatAsFTS: treatAsFTS
    )
  }

  public func entry(
    entryId: String,
    includeContent: Bool = true,
    fullContent: Bool = false,
    maxContentBytes: Int = 2048
  ) throws -> EntryResult {
    try pool.read { db in
      struct Row: FetchableRecord, Decodable {
        let id: String
        let projectId: String
        let projectName: String?
        let transcriptId: String
        let transcriptTitle: String?
        let provider: String
        let kind: String
        let timestamp: Int
        let createdAt: Int
        let displayInTimeline: Int
        let content: String

        enum CodingKeys: String, CodingKey {
          case id
          case projectId = "project_id"
          case projectName = "project_name"
          case transcriptId = "transcript_id"
          case transcriptTitle = "transcript_title"
          case provider
          case kind
          case timestamp
          case createdAt = "created_at"
          case displayInTimeline = "display_in_timeline"
          case content
        }
      }

      let sql = """
        SELECT
          e.id AS id,
          e.project_id AS project_id,
          p.name AS project_name,
          e.transcript_id AS transcript_id,
          tm.title AS transcript_title,
          e.provider AS provider,
          e.kind AS kind,
          e.timestamp AS timestamp,
          e.created_at AS created_at,
          e.display_in_timeline AS display_in_timeline,
          e.content AS content
        FROM transcript_entries e
        LEFT JOIN projects p ON p.id = e.project_id
        LEFT JOIN transcript_metadata tm ON tm.transcript_id = e.transcript_id
        WHERE e.id = ?
      """

      guard let row = try Row.fetchOne(db, sql: sql, arguments: [entryId]) else {
        throw EntryLookupError.notFound(entryId: entryId)
      }

      let content: String?
      let contentTruncated: Bool?
      let contentFullSize: Int?
      if !includeContent {
        content = nil
        contentTruncated = nil
        contentFullSize = nil
      } else if fullContent {
        content = row.content
        contentTruncated = nil
        contentFullSize = nil
      } else {
        let result = QueryContentTruncator.truncateUTF8PreservingScalars(row.content, maxBytes: maxContentBytes)
        content = result.truncated
        contentTruncated = result.didTruncate ? true : nil
        contentFullSize = result.didTruncate ? result.fullSizeBytes : nil
      }

      return EntryResult(
        entry: EntryPayload(
          id: row.id,
          projectId: row.projectId,
          transcriptId: row.transcriptId,
          provider: row.provider,
          kind: row.kind,
          timestamp: row.timestamp,
          createdAt: row.createdAt,
          displayInTimeline: row.displayInTimeline,
          content: content,
          contentTruncated: contentTruncated,
          contentFullSize: contentFullSize
        ),
        projectName: row.projectName,
        transcriptTitle: row.transcriptTitle
      )
    }
  }

  public func context(
    entryId: String,
    beforeCount: Int = 10,
    afterCount: Int = 20,
    includeHidden: Bool = false,
    includeSidechains: Bool = false,
    kinds: [String]? = nil,
    includeContent: Bool = true,
    fullContent: Bool = false,
    maxContentBytes: Int = 2048
  ) throws -> ContextResult {
    let filter = EntryFilter(
      includeHidden: includeHidden,
      includeSidechains: includeSidechains,
      kinds: kinds
    )
    return try contextImpl(
      entryId: entryId,
      beforeCount: beforeCount,
      afterCount: afterCount,
      filter: filter,
      includeContent: includeContent,
      fullContent: fullContent,
      maxContentBytes: maxContentBytes
    )
  }

  /// Internal implementation using EntryFilter for unified filter handling.
  internal func contextImpl(
    entryId: String,
    beforeCount: Int,
    afterCount: Int,
    filter: EntryFilter,
    includeContent: Bool,
    fullContent: Bool,
    maxContentBytes: Int
  ) throws -> ContextResult {
    try pool.read { db in
      struct AnchorRow: FetchableRecord, Decodable {
        let id: String
        let projectId: String
        let transcriptId: String
        let provider: String
        let kind: String
        let timestamp: Int
        let createdAt: Int
        let displayInTimeline: Int
        let content: String

        enum CodingKeys: String, CodingKey {
          case id
          case projectId = "project_id"
          case transcriptId = "transcript_id"
          case provider
          case kind
          case timestamp
          case createdAt = "created_at"
          case displayInTimeline = "display_in_timeline"
          case content
        }
      }

      let anchorSQL = """
        SELECT id, project_id, transcript_id, provider, kind, timestamp, created_at, display_in_timeline, content
        FROM transcript_entries
        WHERE id = ?
      """
      guard let anchor = try AnchorRow.fetchOne(db, sql: anchorSQL, arguments: [entryId]) else {
        throw EntryLookupError.notFound(entryId: entryId)
      }

      func mapEntry(_ row: AnchorRow) -> EntryPayload {
        let content: String?
        let contentTruncated: Bool?
        let contentFullSize: Int?
        if !includeContent {
          content = nil
          contentTruncated = nil
          contentFullSize = nil
        } else if fullContent {
          content = row.content
          contentTruncated = nil
          contentFullSize = nil
        } else {
          let result = QueryContentTruncator.truncateUTF8PreservingScalars(row.content, maxBytes: maxContentBytes)
          content = result.truncated
          contentTruncated = result.didTruncate ? true : nil
          contentFullSize = result.didTruncate ? result.fullSizeBytes : nil
        }

        return EntryPayload(
          id: row.id,
          projectId: row.projectId,
          transcriptId: row.transcriptId,
          provider: row.provider,
          kind: row.kind,
          timestamp: row.timestamp,
          createdAt: row.createdAt,
          displayInTimeline: row.displayInTimeline,
          content: content,
          contentTruncated: contentTruncated,
          contentFullSize: contentFullSize
        )
      }

      let beforeLimit = max(0, beforeCount)
      let afterLimit = max(0, afterCount)

      // Get filter SQL fragment (uses EntryFilter for unified handling)
      let (filterFragment, filterArgs) = filter.sqlAndFragment(alias: .e)

      var beforeArgs: [any DatabaseValueConvertible] = [
        anchor.transcriptId,
        anchor.timestamp,
        anchor.timestamp,
        anchor.createdAt,
        anchor.timestamp,
        anchor.createdAt,
        anchor.id,
      ]
      beforeArgs.append(contentsOf: filterArgs)
      let beforeSQL = """
        SELECT id, project_id, transcript_id, provider, kind, timestamp, created_at, display_in_timeline, content
        FROM transcript_entries e
        WHERE e.transcript_id = ?
          AND (
            e.timestamp < ?
            OR (e.timestamp = ? AND e.created_at < ?)
            OR (e.timestamp = ? AND e.created_at = ? AND e.id < ?)
          )\(filterFragment)
        ORDER BY e.timestamp DESC, e.created_at DESC, e.id DESC
        LIMIT ?
      """
      beforeArgs.append(beforeLimit + 1)
      let beforeRows = try AnchorRow.fetchAll(db, sql: beforeSQL, arguments: StatementArguments(beforeArgs))
      let hasMoreBefore = beforeRows.count > beforeLimit
      let beforeWindow = beforeRows.prefix(beforeLimit).reversed().map(mapEntry)

      var afterArgs: [any DatabaseValueConvertible] = [
        anchor.transcriptId,
        anchor.timestamp,
        anchor.timestamp,
        anchor.createdAt,
        anchor.timestamp,
        anchor.createdAt,
        anchor.id,
      ]
      afterArgs.append(contentsOf: filterArgs)
      let afterSQL = """
        SELECT id, project_id, transcript_id, provider, kind, timestamp, created_at, display_in_timeline, content
        FROM transcript_entries e
        WHERE e.transcript_id = ?
          AND (
            e.timestamp > ?
            OR (e.timestamp = ? AND e.created_at > ?)
            OR (e.timestamp = ? AND e.created_at = ? AND e.id > ?)
          )\(filterFragment)
        ORDER BY e.timestamp ASC, e.created_at ASC, e.id ASC
        LIMIT ?
      """
      afterArgs.append(afterLimit + 1)
      let afterRows = try AnchorRow.fetchAll(db, sql: afterSQL, arguments: StatementArguments(afterArgs))
      let hasMoreAfter = afterRows.count > afterLimit
      let afterWindow = afterRows.prefix(afterLimit).map(mapEntry)

      var countArgs: [any DatabaseValueConvertible] = [anchor.transcriptId]
      countArgs.append(contentsOf: filterArgs)
      let countSQL = "SELECT COUNT(*) FROM transcript_entries e WHERE e.transcript_id = ?\(filterFragment)"
      let transcriptEntryCount = try Int.fetchOne(db, sql: countSQL, arguments: StatementArguments(countArgs))

      let anchorEntry = mapEntry(anchor)
      let firstEntryId = beforeWindow.first?.id ?? anchorEntry.id
      let lastEntryId = afterWindow.last?.id ?? anchorEntry.id

      return ContextResult(
        anchor: anchorEntry,
        before: beforeWindow,
        after: afterWindow,
        meta: ContextMeta(
          firstEntryId: firstEntryId,
          lastEntryId: lastEntryId,
          hasMoreBefore: hasMoreBefore,
          hasMoreAfter: hasMoreAfter,
          transcriptEntryCount: transcriptEntryCount
        )
      )
    }
  }

  public func activity(
    projectIds: [String]? = nil,
    transcriptId: String? = nil,
    limit: Int = 50,
    includeHidden: Bool = false,
    includeSidechains: Bool = false,
    timeRange: QueryTimeRange = QueryTimeRange(),
    includeContent: Bool = true,
    fullContent: Bool = false,
    maxContentBytes: Int = 2048,
    device: String? = nil
  ) throws -> [ActivityItem] {
    let filter = EntryFilter(includeHidden: includeHidden, includeSidechains: includeSidechains)
    return try activityImpl(
      filter: filter,
      projectIds: projectIds,
      transcriptId: transcriptId,
      limit: limit,
      timeRange: timeRange,
      includeContent: includeContent,
      fullContent: fullContent,
      maxContentBytes: maxContentBytes,
      device: device
    )
  }

  // Backward compatibility overload for old single projectId parameter
  @available(*, deprecated, message: "Use activity(projectIds:...) instead")
  @_disfavoredOverload
  public func activity(
    projectId: String?,
    transcriptId: String? = nil,
    limit: Int = 50,
    includeHidden: Bool = false,
    includeSidechains: Bool = false,
    timeRange: QueryTimeRange = QueryTimeRange(),
    includeContent: Bool = true,
    fullContent: Bool = false,
    maxContentBytes: Int = 2048
  ) throws -> [ActivityItem] {
    let projectIds = projectId.map { [$0] }
    return try activity(
      projectIds: projectIds,
      transcriptId: transcriptId,
      limit: limit,
      includeHidden: includeHidden,
      includeSidechains: includeSidechains,
      timeRange: timeRange,
      includeContent: includeContent,
      fullContent: fullContent,
      maxContentBytes: maxContentBytes
    )
  }

  /// Internal implementation using EntryFilter for unified filter handling.
  internal func activityImpl(
    filter: EntryFilter,
    projectIds: [String]? = nil,
    transcriptId: String? = nil,
    limit: Int = 50,
    timeRange: QueryTimeRange = QueryTimeRange(),
    includeContent: Bool = true,
    fullContent: Bool = false,
    maxContentBytes: Int = 2048,
    device: String? = nil
  ) throws -> [ActivityItem] {
    try pool.read { db in
      struct Row: FetchableRecord, Decodable {
        let id: String
        let projectId: String
        let projectName: String?
        let transcriptId: String
        let transcriptTitle: String?
        let provider: String
        let kind: String
        let timestamp: Int
        let createdAt: Int
        let displayInTimeline: Int
        let content: String

        enum CodingKeys: String, CodingKey {
          case id
          case projectId = "project_id"
          case projectName = "project_name"
          case transcriptId = "transcript_id"
          case transcriptTitle = "transcript_title"
          case provider
          case kind
          case timestamp
          case createdAt = "created_at"
          case displayInTimeline = "display_in_timeline"
          case content
        }
      }

      // Get filter SQL fragment (uses EntryFilter for unified handling)
      let (filterFragment, filterArgs) = filter.sqlAndFragment(alias: .e)

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
          e.created_at AS created_at,
          e.display_in_timeline AS display_in_timeline,
          e.content AS content
        FROM transcript_entries e
        LEFT JOIN projects p ON p.id = e.project_id
        LEFT JOIN transcript_metadata tm ON tm.transcript_id = e.transcript_id
        WHERE 1 = 1\(filterFragment)
      """
      var args: [any DatabaseValueConvertible] = []
      args.append(contentsOf: filterArgs)

      if let projectIds = projectIds {
        if projectIds.isEmpty {
          return []  // Empty array = no results
        }
        // Dedupe and sort for deterministic SQL and reduced query work
        let uniqueIds = Array(Set(projectIds)).sorted()
        let placeholders = uniqueIds.map { _ in "?" }.joined(separator: ", ")
        sql += " AND e.project_id IN (\(placeholders))"
        for id in uniqueIds {
          args.append(id)
        }
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
      if let device {
        // Match device name when present; fall back to device ID only when name is absent.
        sql += """
           AND (
            (e.source_device_name IS NOT NULL AND e.source_device_name != ''
              AND e.source_device_name LIKE '%' || ? || '%' COLLATE NOCASE)
            OR
            ((e.source_device_name IS NULL OR e.source_device_name = '')
              AND e.source_device_id LIKE '%' || ? || '%' COLLATE NOCASE)
          )
          """
        args.append(device)
        args.append(device)
      }

      sql += " ORDER BY e.timestamp DESC, e.created_at DESC, e.id DESC LIMIT ?"
      args.append(limit)

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
      return rows.map { row in
        let content: String?
        let contentTruncated: Bool?
        let contentFullSize: Int?
        if !includeContent {
          content = nil
          contentTruncated = nil
          contentFullSize = nil
        } else if fullContent {
          content = row.content
          contentTruncated = nil
          contentFullSize = nil
        } else {
          let result = QueryContentTruncator.truncateUTF8PreservingScalars(row.content, maxBytes: maxContentBytes)
          content = result.truncated
          contentTruncated = result.didTruncate ? true : nil
          contentFullSize = result.didTruncate ? result.fullSizeBytes : nil
        }

        return ActivityItem(
          entry: EntryPayload(
            id: row.id,
            projectId: row.projectId,
            transcriptId: row.transcriptId,
            provider: row.provider,
            kind: row.kind,
            timestamp: row.timestamp,
            createdAt: row.createdAt,
            displayInTimeline: row.displayInTimeline,
            content: content,
            contentTruncated: contentTruncated,
            contentFullSize: contentFullSize
          ),
          projectName: row.projectName,
          transcriptTitle: row.transcriptTitle
        )
      }
    }
  }

  public func counts() throws -> DatabaseCounts {
    try pool.read { db in
      let projectCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects") ?? 0
      let transcriptCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts") ?? 0
      let entryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries") ?? 0
      return DatabaseCounts(projectCount: projectCount, transcriptCount: transcriptCount, entryCount: entryCount)
    }
  }

  /// Most recent timeline-visible entries, optionally project scoped.
  /// - Parameters:
  ///   - projectId: Optional project ID to scope results
  ///   - limit: Maximum number of entries to return
  ///   - filter: Entry filter. Defaults to `.timeline` (excludes hidden + sidechains).
  public func recentActivity(
    projectId: String? = nil,
    limit: Int = 50,
    filter: EntryFilter = .timeline
  ) throws -> [TranscriptEntry] {
    let (filterPredicate, filterArgs) = filter.sqlPredicate()
    return try pool.read { db in
      var sql = """
        SELECT *
        FROM transcript_entries e
        WHERE (\(filterPredicate))
      """
      var args: [any DatabaseValueConvertible] = []
      args.append(contentsOf: filterArgs)
      if let projectId {
        sql += " AND e.project_id = ?"
        args.append(projectId)
      }
      sql += " ORDER BY e.timestamp DESC, e.created_at DESC, e.id DESC LIMIT ?"
      args.append(limit)
      return try TranscriptEntry.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    }
  }

  /// Full-text search across entries (FTS5), optionally project scoped.
  public func ftsSearch(query: String, projectId: String? = nil, limit: Int = 50) throws -> [TranscriptEntry] {
    let safeQuery = FTSQueryBuilder.buildSafeFTSQuery(query)
    guard !safeQuery.isEmpty else { return [] }
    return try pool.read { db in
      guard try db.tableExists("transcript_entries_fts") else {
        throw QueryError.featureUnavailable(feature: "fts_search", message: "FTS search is not available in this database.")
      }
      var sql = """
        SELECT e.*
        FROM transcript_entries_fts f
        \(ftsJoinEntries(ftsAlias: "f"))
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
        throw QueryError.featureUnavailable(feature: "summaries", message: "Summaries are not available in this database.")
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
  /// - Parameters:
  ///   - projectId: Optional project ID to scope results
  ///   - filter: Entry filter for counting entries. Defaults to `.timeline`.
  ///             Uses aggregate subqueries to avoid cross-product performance issues.
  ///             Projects with 0 matching entries still appear (LEFT JOIN semantics).
  public func projectStats(projectId: String? = nil, filter: EntryFilter = .timeline) throws -> [ProjectStats] {
    // Use aggregate subqueries to avoid cross-product (N×M) performance issues.
    // Filter is applied inside entries subquery; projects with 0 entries still appear.
    let (filterPredicate, filterArgs) = filter.sqlPredicate(alias: .e)
    return try pool.read { db in
      var sql = """
        SELECT
          p.id AS project_id,
          p.name AS project_name,
          COALESCE(ta.transcript_count, 0) AS transcript_count,
          COALESCE(ea.entry_count, 0) AS entry_count,
          ea.last_entry_timestamp AS last_entry_timestamp,
          p.last_viewed_ts AS last_viewed_ts
        FROM projects p
        LEFT JOIN (
          SELECT project_id, COUNT(*) AS transcript_count
          FROM transcripts
          GROUP BY project_id
        ) ta ON ta.project_id = p.id
        LEFT JOIN (
          SELECT e.project_id, COUNT(*) AS entry_count, MAX(e.timestamp) AS last_entry_timestamp
          FROM transcript_entries e
          WHERE (\(filterPredicate))
          GROUP BY e.project_id
        ) ea ON ea.project_id = p.id
      """
      var args: [any DatabaseValueConvertible] = []
      args.append(contentsOf: filterArgs)
      if let projectId {
        sql += " WHERE p.id = ?"
        args.append(projectId)
      }
      sql += " ORDER BY last_entry_timestamp DESC NULLS LAST"

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

  // MARK: - Cloud Push Export

  /// Count entries remaining for cloud push from the given cursor position.
  ///
  /// Uses the same keyset pagination WHERE clause as `exportForCloudPush()`
  /// so the count accurately reflects entries that will be pushed. Runs a
  /// single COUNT(*) query, which is fast even on large tables.
  ///
  /// - Parameters:
  ///   - afterTimestamp: Resume after this timestamp (keyset cursor).
  ///   - afterEntryId: Resume after this entry ID (keyset tiebreaker).
  /// - Returns: Number of entries remaining to push.
  public func countEntriesForCloudPush(
    afterTimestamp: Int? = nil,
    afterEntryId: String? = nil
  ) throws -> Int {
    try pool.read { db in
      // v37: JOIN projects to exclude cloud_sync_enabled = 0
      var sql = """
        SELECT COUNT(*) FROM transcript_entries e
        JOIN projects p ON p.id = e.project_id
        WHERE e.display_in_timeline = 1
          AND p.cloud_sync_enabled = 1
        """
      var args: [DatabaseValueConvertible] = []
      if let afterTimestamp, let afterEntryId {
        sql += " AND (e.timestamp > ? OR (e.timestamp = ? AND e.id > ?))"
        args.append(afterTimestamp)
        args.append(afterTimestamp)
        args.append(afterEntryId)
      }
      return try Int.fetchOne(db, sql: sql, arguments: StatementArguments(args)) ?? 0
    }
  }

  /// Export entries for cloud push. Returns projects, transcripts, and entries
  /// ready for serialization into the cloud API push payload.
  ///
  /// Supports keyset pagination: pass `afterTimestamp` and `afterEntryId` from
  /// the last entry of the previous batch to fetch the next page. Both must be
  /// provided together for pagination to take effect.
  ///
  /// - Parameters:
  ///   - afterTimestamp: Resume after this timestamp (keyset cursor).
  ///   - afterEntryId: Resume after this entry ID (keyset tiebreaker).
  ///   - limit: Maximum entries per batch (default 500).
  public func exportForCloudPush(
    afterTimestamp: Int? = nil,
    afterEntryId: String? = nil,
    limit: Int = 500
  ) throws -> CloudPushExport {
    try pool.read { db in
      // Get entries (ordered by timestamp, id for stable keyset paging)
      // v37: JOIN projects to exclude cloud_sync_enabled = 0
      var sql = """
        SELECT e.id, e.transcript_id, e.project_id, e.session_id,
               e.provider, e.kind, e.timestamp, e.content, e.content_sha256,
               e.display_in_timeline, e.git_branch, e.git_commit,
               e.cwd, e.created_at, e.updated_at
        FROM transcript_entries e
        JOIN projects p ON p.id = e.project_id
        WHERE e.display_in_timeline = 1
          AND p.cloud_sync_enabled = 1
        """
      var args: [DatabaseValueConvertible] = []
      if (afterTimestamp == nil) != (afterEntryId == nil) {
        log.warning("exportForCloudPush called with partial cursor; ignoring cursor")
      }
      if let afterTimestamp, let afterEntryId {
        sql += " AND (e.timestamp > ? OR (e.timestamp = ? AND e.id > ?))"
        args.append(afterTimestamp)
        args.append(afterTimestamp)
        args.append(afterEntryId)
      }
      sql += " ORDER BY e.timestamp ASC, e.id ASC LIMIT ?"
      args.append(limit)

      let entryRows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))

      let entries: [CloudPushExport.Entry] = entryRows.map { row in
        CloudPushExport.Entry(
          id: row["id"], transcriptId: row["transcript_id"],
          projectId: row["project_id"], sessionId: row["session_id"],
          provider: row["provider"], kind: row["kind"],
          timestamp: row["timestamp"], content: row["content"],
          contentSha256: row["content_sha256"],
          displayInTimeline: row["display_in_timeline"],
          gitBranch: row["git_branch"], gitCommit: row["git_commit"],
          cwd: row["cwd"],
          sourceDeviceId: row["source_device_id"],
          sourceDeviceName: row["source_device_name"],
          createdAt: row["created_at"], updatedAt: row["updated_at"]
        )
      }

      // Collect referenced project and transcript IDs
      let projectIds = Array(Set(entries.map { $0.projectId }))
      let transcriptIds = Array(Set(entries.map { $0.transcriptId }))

      // Fetch projects
      var projects: [CloudPushExport.Project] = []
      if !projectIds.isEmpty {
        let placeholders = projectIds.map { _ in "?" }.joined(separator: ",")
        let projRows = try Row.fetchAll(db,
          sql: "SELECT id, name, root_path FROM projects WHERE id IN (\(placeholders))",
          arguments: StatementArguments(projectIds))
        projects = projRows.map { row in
          CloudPushExport.Project(
            id: row["id"], name: row["name"], rootPath: row["root_path"])
        }
      }

      // Fetch transcripts
      var transcripts: [CloudPushExport.Transcript] = []
      if !transcriptIds.isEmpty {
        let placeholders = transcriptIds.map { _ in "?" }.joined(separator: ",")
        let txRows = try Row.fetchAll(db,
          sql: """
            SELECT id, project_id, file_path, provider, provider_session_id,
                   line_count, created_at, updated_at
            FROM transcripts WHERE id IN (\(placeholders))
            """,
          arguments: StatementArguments(transcriptIds))
        transcripts = txRows.map { row in
          CloudPushExport.Transcript(
            id: row["id"], projectId: row["project_id"],
            filePath: row["file_path"], provider: row["provider"],
            providerSessionId: row["provider_session_id"],
            lineCount: row["line_count"] ?? 0,
            createdAt: row["created_at"], updatedAt: row["updated_at"])
        }
      }

      let enrichedProjects: [CloudPushExport.Project] = projects.map { project in
        #if INGESTION_CORE
        // Linux build: GitProjectIdentity is not available (depends on
        // GitRepositoryResolver which is macOS-only). Push projects without
        // git identity enrichment; the server treats all git fields as optional.
        return CloudPushExport.Project(
          id: project.id,
          name: project.name,
          rootPath: project.rootPath,
          repoName: URL(fileURLWithPath: project.rootPath).lastPathComponent
        )
        #else
        let identity = GitProjectIdentity.resolve(forProjectRootPath: project.rootPath)
        return CloudPushExport.Project(
          id: project.id,
          name: project.name,
          rootPath: project.rootPath,
          repoGroupKey: identity?.repoGroupKey,
          repoIdentity: identity?.repoIdentity,
          repoOriginNormalized: identity?.repoOriginNormalized,
          gitCommonDir: identity?.gitCommonDir,
          isWorktree: identity?.isWorktree ?? false,
          defaultBranch: identity?.defaultBranch,
          vcsProvider: identity?.vcsProvider,
          worktreeName: identity?.worktreeName,
          repoName: identity?.repoName ?? URL(fileURLWithPath: project.rootPath).lastPathComponent
        )
        #endif
      }

      return CloudPushExport(
        projects: enrichedProjects,
        transcripts: transcripts,
        entries: entries)
    }
  }

  // MARK: - Project Cloud Sync Settings

  /// List all projects with their cloud sync enabled status.
  public func listProjectsCloudSyncStatus() throws -> [(id: String, name: String?, rootPath: String, cloudSyncEnabled: Bool)] {
    try pool.read { db in
      let rows = try Row.fetchAll(db, sql: """
        SELECT id, name, root_path, cloud_sync_enabled
        FROM projects
        WHERE hidden = 0
        ORDER BY display_order ASC, name ASC
      """)
      return rows.map { row in
        (
          id: row["id"] as String,
          name: row["name"] as String?,
          rootPath: row["root_path"] as String,
          cloudSyncEnabled: (row["cloud_sync_enabled"] as Int) != 0
        )
      }
    }
  }

  /// Set cloud_sync_enabled for a project by name (fuzzy match on name or root_path).
  public func setProjectCloudSyncEnabled(projectMatch: String, enabled: Bool) throws -> String? {
    try pool.write { db in
      let now = Int(Date().timeIntervalSince1970)
      // Try exact name match first, then path contains, then path ends with
      let row = try Row.fetchOne(db, sql: """
        SELECT id, name, root_path FROM projects
        WHERE name = ? OR root_path = ? OR root_path LIKE ?
        LIMIT 1
      """, arguments: [projectMatch, projectMatch, "%/\(projectMatch)"])

      guard let row else { return nil }
      let projectId: String = row["id"]
      let projectName: String? = row["name"]
      try db.execute(
        sql: "UPDATE projects SET cloud_sync_enabled = ?, updated_at = ? WHERE id = ?",
        arguments: [enabled, now, projectId]
      )
      return projectName ?? row["root_path"]
    }
  }

  // MARK: - Cloud Pull Import

  /// Import data received from a cloud pull response into the local database.
  /// Upserts projects, transcripts, and entries. Skips entries that already
  /// exist (by id) to avoid duplicates. Returns counts of imported items.
  public func importFromCloudPull(
    projects: [[String: Any]],
    transcripts: [[String: Any]],
    entries: [[String: Any]],
    summaries: [[String: Any]]
  ) throws -> CloudPullImportResult {
    try pool.write { db in
      var projectsImported = 0
      var transcriptsImported = 0
      var entriesImported = 0
      var skipped = 0
      var projectIdRemap = [String: String]()

      let now = Int(Date().timeIntervalSince1970)

      // Upsert projects
      for proj in projects {
        guard let id = proj["id"] as? String,
              let rootPath = proj["root_path"] as? String else { continue }
        let name = proj["name"] as? String
        if let existingId = try String.fetchOne(
          db,
          sql: "SELECT id FROM projects WHERE id = ?",
          arguments: [id]
        ) {
          projectIdRemap[id] = existingId
          continue
        }

        if let existingId = try String.fetchOne(
          db,
          sql: "SELECT id FROM projects WHERE root_path = ?",
          arguments: [rootPath]
        ) {
          projectIdRemap[id] = existingId
          if let name {
            try db.execute(
              sql: """
                UPDATE projects
                SET name = COALESCE(name, ?), updated_at = ?
                WHERE id = ?
              """,
              arguments: [name, now, existingId]
            )
          }
          continue
        }

        try db.execute(sql: """
          INSERT INTO projects (id, name, root_path, last_viewed_ts, hidden,
            is_orphaned, created_at, updated_at)
          VALUES (?, ?, ?, 0.0, 0, 0, ?, ?)
          ON CONFLICT(root_path) DO NOTHING
          """, arguments: [id, name, rootPath, now, now])
        // After insert-or-skip, look up the local owner of this root_path.
        // This handles both the fresh-insert case and the conflict case where
        // the local project has a different ID than the server's.
        guard let localId = try String.fetchOne(db,
          sql: "SELECT id FROM projects WHERE root_path = ?",
          arguments: [rootPath]) else {
          throw CloudPullImportError.projectRootPathInvariant(serverId: id, rootPath: rootPath)
        }
        if localId != id {
          #if canImport(OSLog)
          Logger(subsystem: "dev.contextify", category: "CloudPullImport")
            .info("Project ID remap: server=\(id, privacy: .public) -> local=\(localId, privacy: .public) (root_path=\(rootPath, privacy: .public))")
          #endif
        }
        projectIdRemap[id] = localId
        projectsImported += 1
      }

      // Resolve a server project ID to its local equivalent.
      // Checks the remap dictionary first (covers cross-machine ID divergence),
      // then falls back to a direct DB lookup (covers projects already present
      // from a prior sync page or local ingest). Returns nil if no local
      // project exists for this ID.
      func resolveLocalProjectId(_ serverId: String) throws -> String? {
        if let remapped = projectIdRemap[serverId] {
          return remapped
        }
        return try String.fetchOne(db,
          sql: "SELECT id FROM projects WHERE id = ?",
          arguments: [serverId])
      }

      // v37: Pull-side sync exclusion check.
      // A project is excluded from pull if ALL local projects sharing its
      // repo_group_key have cloud_sync_enabled = 0. Mixed groups import normally.
      // Projects without a repo_group_key fall back to per-project check.
      func isExcludedFromPull(_ localProjectId: String) throws -> Bool {
        // Get this project's repo_group_key and cloud_sync_enabled
        guard let row = try Row.fetchOne(db,
          sql: "SELECT repo_group_key, cloud_sync_enabled FROM projects WHERE id = ?",
          arguments: [localProjectId]) else { return false }

        let enabled: Int = row["cloud_sync_enabled"]
        let repoGroupKey: String? = row["repo_group_key"]

        // If no repo_group_key, use per-project check
        guard let key = repoGroupKey else {
          return enabled == 0
        }

        // Check if ALL members of the repo group are excluded
        let enabledCount = try Int.fetchOne(db,
          sql: "SELECT COUNT(*) FROM projects WHERE repo_group_key = ? AND cloud_sync_enabled = 1",
          arguments: [key]) ?? 0
        return enabledCount == 0
      }

      // Upsert transcripts
      for tx in transcripts {
        guard let id = tx["id"] as? String,
              let rawProjectId = tx["project_id"] as? String,
              let filePath = tx["file_path"] as? String,
              let provider = tx["provider"] as? String else { continue }
        guard let projectId = try resolveLocalProjectId(rawProjectId) else {
          #if canImport(OSLog)
          Logger(subsystem: "dev.contextify", category: "CloudPullImport")
            .warning("Skipping transcript \(id, privacy: .public): no local project for server project_id=\(rawProjectId, privacy: .public)")
          #endif
          continue
        }
        let exists = try Int.fetchOne(db, sql:
          "SELECT 1 FROM transcripts WHERE id = ?", arguments: [id])
        if exists == nil {
          let lineCount = tx["line_count"] as? Int ?? 0
          let createdAt = tx["created_at"] as? Int ?? now
          let updatedAt = tx["updated_at"] as? Int ?? now
          try db.execute(sql: """
            INSERT INTO transcripts (id, project_id, file_path, provider,
              provider_session_id, last_modified, line_count,
              last_processed_line, parser_version, status, ingest_state,
              created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, 'active', 'complete', ?, ?)
            """, arguments: [
              id, projectId, filePath, provider,
              tx["provider_session_id"] as? String,
              updatedAt, lineCount, createdAt, updatedAt,
            ])
          transcriptsImported += 1
        }
      }

      // Insert entries (skip existing by id)
      var summaryKindSkipped = 0
      for entry in entries {
        guard let id = entry["id"] as? String,
              let transcriptId = entry["transcript_id"] as? String,
              let rawProjectId = entry["project_id"] as? String,
              let provider = entry["provider"] as? String,
              let kind = entry["kind"] as? String,
              let timestamp = entry["timestamp"] as? Int,
              let content = entry["content"] as? String,
              let contentSha256 = entry["content_sha256"] as? String else { continue }
        guard let projectId = try resolveLocalProjectId(rawProjectId) else {
          #if canImport(OSLog)
          Logger(subsystem: "dev.contextify", category: "CloudPullImport")
            .warning("Skipping entry \(id, privacy: .public): no local project for server project_id=\(rawProjectId, privacy: .public)")
          #endif
          skipped += 1
          continue
        }

        // Validate transcript exists locally before inserting entry
        let transcriptExists = try Int.fetchOne(db,
          sql: "SELECT 1 FROM transcripts WHERE id = ?",
          arguments: [transcriptId])
        guard transcriptExists != nil else {
          #if canImport(OSLog)
          Logger(subsystem: "dev.contextify", category: "CloudPullImport")
            .warning("Skipping entry \(id, privacy: .public): no local transcript for transcript_id=\(transcriptId, privacy: .public)")
          #endif
          skipped += 1
          continue
        }

        // v37: Skip entries for projects excluded from pull on this device
        if try isExcludedFromPull(projectId) {
          skipped += 1
          continue
        }

        // Skip 'summary' kind entries entirely - local schema only supports
        // user/assistant/system. Summaries are handled via the summaries table.
        if kind == "summary" {
          summaryKindSkipped += 1
          continue
        }

        let exists = try Int.fetchOne(db, sql:
          "SELECT 1 FROM transcript_entries WHERE id = ?", arguments: [id])
        if exists != nil {
          skipped += 1
          continue
        }

        let createdAt = entry["created_at"] as? Int ?? now
        let updatedAt = entry["updated_at"] as? Int ?? now
        let displayInTimeline = entry["display_in_timeline"] as? Bool ?? true
        try db.execute(sql: """
          INSERT INTO transcript_entries (id, transcript_id, project_id,
            session_id, provider, kind, timestamp, content, content_sha256,
            display_in_timeline, git_branch, git_commit, cwd,
            created_at, updated_at, created_ts, source_device_id, source_device_name)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """, arguments: [
            id, transcriptId, projectId,
            entry["session_id"] as? String,
            provider, kind, timestamp, content, contentSha256,
            displayInTimeline ? 1 : 0,
            entry["git_branch"] as? String,
            entry["git_commit"] as? String,
            entry["cwd"] as? String,
            createdAt, updatedAt,
            Double(timestamp),
            entry["source_device_id"] as? String,
            entry["source_device_name"] as? String,
          ])
        entriesImported += 1
      }

      // Log ignored summaries (summary storage not yet implemented)
      if !summaries.isEmpty || summaryKindSkipped > 0 {
        #if canImport(OSLog)
        let logger = Logger(subsystem: "dev.contextify", category: "CloudPullImport")
        logger.info("Cloud pull: ignored \(summaries.count, privacy: .public) summaries and \(summaryKindSkipped, privacy: .public) summary-kind entries (storage not implemented)")
        #endif
      }

      return CloudPullImportResult(
        projectsImported: projectsImported,
        transcriptsImported: transcriptsImported,
        entriesImported: entriesImported,
        entriesSkipped: skipped
      )
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
        expectedSchemaVersion: DatabaseSchema.version,
        ftsEnabled: ftsEnabled,
        summariesEnabled: summariesEnabled
      )
    }
  }
}

// MARK: - Cloud Pull Import Result

/// Result of importing cloud pull data into the local database.
public struct CloudPullImportResult: Sendable {
  public let projectsImported: Int
  public let transcriptsImported: Int
  public let entriesImported: Int
  public let entriesSkipped: Int
}

// MARK: - Cloud Push Export Types

/// Data exported from local SQLite for pushing to a cloud server.
public struct CloudPushExport: Sendable {
  public let projects: [Project]
  public let transcripts: [Transcript]
  public let entries: [Entry]

  public struct Project: Sendable {
    public let id: String
    public let name: String?
    public let rootPath: String
    public let repoGroupKey: String?
    public let repoIdentity: String?
    public let repoOriginNormalized: String?
    public let gitCommonDir: String?
    public let isWorktree: Bool
    public let defaultBranch: String?
    public let vcsProvider: String?
    public let worktreeName: String?
    public let repoName: String

    public init(
      id: String,
      name: String?,
      rootPath: String,
      repoGroupKey: String? = nil,
      repoIdentity: String? = nil,
      repoOriginNormalized: String? = nil,
      gitCommonDir: String? = nil,
      isWorktree: Bool = false,
      defaultBranch: String? = nil,
      vcsProvider: String? = nil,
      worktreeName: String? = nil,
      repoName: String = ""
    ) {
      self.id = id
      self.name = name
      self.rootPath = rootPath
      self.repoGroupKey = repoGroupKey
      self.repoIdentity = repoIdentity
      self.repoOriginNormalized = repoOriginNormalized
      self.gitCommonDir = gitCommonDir
      self.isWorktree = isWorktree
      self.defaultBranch = defaultBranch
      self.vcsProvider = vcsProvider
      self.worktreeName = worktreeName
      self.repoName = repoName
    }

    public var asDictionary: [String: Any] {
      var d: [String: Any] = ["id": id, "root_path": rootPath]
      if let n = name { d["name"] = n }
      if let repoGroupKey { d["repo_group_key"] = repoGroupKey }
      if let repoIdentity { d["repo_identity"] = repoIdentity }
      if let repoOriginNormalized { d["repo_origin_normalized"] = repoOriginNormalized }
      if let gitCommonDir { d["git_common_dir"] = gitCommonDir }
      if isWorktree { d["is_worktree"] = true }
      if let defaultBranch { d["default_branch"] = defaultBranch }
      if let vcsProvider { d["vcs_provider"] = vcsProvider }
      if let worktreeName { d["worktree_name"] = worktreeName }
      d["repo_name"] = repoName
      return d
    }
  }

  public struct Transcript: Sendable {
    public let id: String
    public let projectId: String
    public let filePath: String
    public let provider: String
    public let providerSessionId: String?
    public let lineCount: Int
    public let createdAt: Int
    public let updatedAt: Int

    public var asDictionary: [String: Any] {
      var d: [String: Any] = [
        "id": id, "project_id": projectId, "file_path": filePath,
        "provider": provider, "line_count": lineCount,
        "created_at": createdAt, "updated_at": updatedAt,
      ]
      if let sid = providerSessionId { d["provider_session_id"] = sid }
      return d
    }
  }

  public struct Entry: Sendable {
    public let id: String
    public let transcriptId: String
    public let projectId: String
    public let sessionId: String?
    public let provider: String
    public let kind: String
    public let timestamp: Int
    public let content: String
    public let contentSha256: String
    public let displayInTimeline: Bool
    public let gitBranch: String?
    public let gitCommit: String?
    public let cwd: String?
    public let sourceDeviceId: String?
    public let sourceDeviceName: String?
    public let createdAt: Int
    public let updatedAt: Int

    public var asDictionary: [String: Any] {
      var d: [String: Any] = [
        "id": id, "transcript_id": transcriptId,
        "project_id": projectId, "provider": provider,
        "kind": kind, "timestamp": timestamp,
        "content": content, "content_sha256": contentSha256,
        "display_in_timeline": displayInTimeline,
        "created_at": createdAt, "updated_at": updatedAt,
      ]
      if let s = sessionId { d["session_id"] = s }
      if let b = gitBranch { d["git_branch"] = b }
      if let c = gitCommit { d["git_commit"] = c }
      if let c = cwd { d["cwd"] = c }
      return d
    }
  }
}
