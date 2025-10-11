import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Repositories")

// MARK: - Project Repository

public protocol ProjectRepository {
  func create(name: String?, rootPath: String, bookmark: Data?) throws -> String
  func list() throws -> [Project]
  func get(id: String) throws -> Project?
  func update(id: String, name: String?, bookmark: Data?) throws
  func delete(id: String) throws
}

public final class ProjectRepositoryImpl: ProjectRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func create(name: String?, rootPath: String, bookmark: Data?) throws -> String {
    let id = UUID().uuidString
    let now = Int(Date().timeIntervalSince1970)
    let canonPath = PathUtils.canonicalizePath(rootPath)

    try db.write { db in
      let project = Project(
        id: id,
        name: name,
        rootPath: canonPath,
        rootBookmark: bookmark,
        createdAt: now,
        updatedAt: now
      )
      try project.insert(db)
    }

    return id
  }

  public func list() throws -> [Project] {
    try db.read { db in
      try Project.fetchAll(db)
    }
  }

  public func get(id: String) throws -> Project? {
    try db.read { db in
      try Project.fetchOne(db, key: id)
    }
  }

  public func update(id: String, name: String?, bookmark: Data?) throws {
    let now = Int(Date().timeIntervalSince1970)

    try db.write { db in
      guard var project = try Project.fetchOne(db, key: id) else {
        throw RepositoryError.notFound
      }
      project.name = name
      project.rootBookmark = bookmark
      project.updatedAt = now
      try project.update(db)
    }
  }

  public func delete(id: String) throws {
    try db.write { db in
      try Project.deleteOne(db, key: id)
    }
  }
}

// MARK: - Transcript Repository

public protocol TranscriptRepository {
  func upsert(
    projectId: String,
    fileURL: URL,
    provider: String,
    providerSessionId: String?,
    lastModified: Date,
    fileSize: Int?
  ) throws -> String

  func setIngestionState(
    id: String,
    lastProcessedLine: Int,
    lineCount: Int,
    parserVersion: Int,
    status: String,
    lastError: String?
  ) throws

  func byProject(_ projectId: String) throws -> [Transcript]
  func get(_ transcriptId: String) throws -> Transcript?
  func needsReparse(currentVersion: Int) throws -> [Transcript]
}

public final class TranscriptRepositoryImpl: TranscriptRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func upsert(
    projectId: String,
    fileURL: URL,
    provider: String,
    providerSessionId: String?,
    lastModified: Date,
    fileSize: Int?
  ) throws -> String {
    let filePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
    let now = Int(Date().timeIntervalSince1970)
    let lastModifiedInt = Int(lastModified.timeIntervalSince1970)

    return try db.write { db in
      // Try to find existing
      if let existing = try Transcript
        .filter(Column("project_id") == projectId && Column("file_path") == filePath)
        .fetchOne(db) {
        // Update existing
        var transcript = existing
        transcript.lastModified = lastModifiedInt
        transcript.fileSize = fileSize
        transcript.updatedAt = now
        try transcript.update(db)
        return existing.id
      } else {
        // Insert new
        let id = providerSessionId ?? UUID().uuidString
        let transcript = Transcript(
          id: id,
          projectId: projectId,
          filePath: filePath,
          provider: provider,
          providerSessionId: providerSessionId,
          lastModified: lastModifiedInt,
          fileSize: fileSize,
          lineCount: 0,
          bookmark: nil,
          lastProcessedLine: 0,
          lastProcessedEntryId: nil,
          parserVersion: 1,
          status: "active",
          lastError: nil,
          createdAt: now,
          updatedAt: now
        )
        try transcript.insert(db)
        return id
      }
    }
  }

  public func setIngestionState(
    id: String,
    lastProcessedLine: Int,
    lineCount: Int,
    parserVersion: Int,
    status: String,
    lastError: String?
  ) throws {
    let now = Int(Date().timeIntervalSince1970)

    try db.write { db in
      guard var transcript = try Transcript.fetchOne(db, key: id) else {
        throw RepositoryError.notFound
      }
      transcript.lastProcessedLine = lastProcessedLine
      transcript.lineCount = lineCount
      transcript.parserVersion = parserVersion
      transcript.status = status
      transcript.lastError = lastError
      transcript.updatedAt = now
      try transcript.update(db)
    }
  }

  public func byProject(_ projectId: String) throws -> [Transcript] {
    try db.read { db in
      try Transcript
        .filter(Column("project_id") == projectId)
        .order(Column("updated_at").desc)
        .fetchAll(db)
    }
  }

  public func get(_ transcriptId: String) throws -> Transcript? {
    try db.read { db in
      try Transcript.fetchOne(db, key: transcriptId)
    }
  }

  public func needsReparse(currentVersion: Int) throws -> [Transcript] {
    try db.read { db in
      try Transcript
        .filter(Column("parser_version") < currentVersion)
        .fetchAll(db)
    }
  }
}

// MARK: - Entry Repository

public protocol EntryRepository {
  func insert(_ entry: TranscriptEntry) throws
  func insertBatch(_ entries: [TranscriptEntry]) throws
  func recentByProject(_ projectId: String, limit: Int) throws -> [TranscriptEntry]
  func newByProject(_ projectId: String, afterTimestamp: Int) throws -> [TranscriptEntry]
  func byTranscript(_ transcriptId: String, afterTimestamp: Int?) throws -> [TranscriptEntry]
  func search(content: String, projectId: String?) throws -> [TranscriptEntry]

  // v2: Single-query feed with cache join
  func recentFeed(projectId: String, limit: Int) throws -> [(TranscriptEntry, TimelineCache?)]
}

public final class EntryRepositoryImpl: EntryRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func insert(_ entry: TranscriptEntry) throws {
    try db.write { db in
      try entry.insert(db, onConflict: .ignore)
    }
  }

  public func insertBatch(_ entries: [TranscriptEntry]) throws {
    try db.write { db in
      for entry in entries {
        try entry.insert(db, onConflict: .ignore)
      }
    }
  }

  public func recentByProject(_ projectId: String, limit: Int) throws -> [TranscriptEntry] {
    try db.read { db in
      try TranscriptEntry
        .filter(Column("project_id") == projectId && Column("display_in_timeline") == 1)
        .order(Column("timestamp").desc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func newByProject(_ projectId: String, afterTimestamp: Int) throws -> [TranscriptEntry] {
    try db.read { db in
      try TranscriptEntry
        .filter(Column("project_id") == projectId && Column("timestamp") > afterTimestamp && Column("display_in_timeline") == 1)
        .order(Column("timestamp").asc)
        .fetchAll(db)
    }
  }

  public func byTranscript(_ transcriptId: String, afterTimestamp: Int? = nil) throws -> [TranscriptEntry] {
    try db.read { db in
      var query = TranscriptEntry.filter(Column("transcript_id") == transcriptId)
      if let after = afterTimestamp {
        query = query.filter(Column("timestamp") > after)
      }
      return try query.order(Column("timestamp").asc).fetchAll(db)
    }
  }

  public func search(content: String, projectId: String? = nil) throws -> [TranscriptEntry] {
    try db.read { db in
      var query = TranscriptEntry.filter(Column("content").like("%\(content)%"))
      if let projectId = projectId {
        query = query.filter(Column("project_id") == projectId)
      }
      return try query.order(Column("timestamp").desc).fetchAll(db)
    }
  }

  public func recentFeed(projectId: String, limit: Int) throws -> [(TranscriptEntry, TimelineCache?)] {
    let t0 = Date()
    defer {
      let ms = Int(Date().timeIntervalSince(t0) * 1000)
      if ms > 10 { log.warning("recentFeed took \(ms)ms for \(limit) entries") }
    }

    return try db.read { db in
      let sql = """
        SELECT
          e.id AS e_id,
          e.transcript_id AS e_transcript_id,
          e.project_id AS e_project_id,
          e.session_id AS e_session_id,
          e.provider AS e_provider,
          e.kind AS e_kind,
          e.timestamp AS e_timestamp,
          e.content AS e_content,
          e.content_sha256 AS e_content_sha256,
          e.summary AS e_summary,
          e.disposition AS e_disposition,
          e.display_in_timeline AS e_display_in_timeline,
          e.is_completion AS e_is_completion,
          e.is_directive AS e_is_directive,
          e.parent_id AS e_parent_id,
          e.git_branch AS e_git_branch,
          e.git_commit AS e_git_commit,
          e.cwd AS e_cwd,
          e.prev1_id AS e_prev1_id,
          e.prev2_id AS e_prev2_id,
          e.window_sha256 AS e_window_sha256,
          e.created_at AS e_created_at,
          e.updated_at AS e_updated_at,
          c.content_sha256 AS c_content_sha256,
          c.window_sha256 AS c_window_sha256,
          c.entry_id AS c_entry_id,
          c.generator_signature AS c_generator_signature,
          c.disposition AS c_disposition,
          c.present_form AS c_present_form,
          c.past_form AS c_past_form,
          c.selected_form AS c_selected_form,
          c.verb_lemma AS c_verb_lemma,
          c.generated_at AS c_generated_at,
          c.user_edited AS c_user_edited,
          c.user_text AS c_user_text,
          c.edited_at AS c_edited_at,
          c.request_id AS c_request_id,
          c.duration AS c_duration
        FROM transcript_entries e
        LEFT JOIN timeline_cache c
          ON c.content_sha256 = e.content_sha256
         AND c.window_sha256  = e.window_sha256
        WHERE e.project_id = ?
          AND e.display_in_timeline = 1
        ORDER BY e.timestamp DESC, e.created_at DESC, e.id DESC
        LIMIT ?
      """

      return try Row
        .fetchAll(db, sql: sql, arguments: [projectId, limit])
        .map { row in
          // Construct entry from e_ prefixed columns
          let entry = TranscriptEntry(
            id: row["e_id"],
            transcriptId: row["e_transcript_id"],
            projectId: row["e_project_id"],
            sessionId: row["e_session_id"],
            provider: row["e_provider"],
            kind: row["e_kind"],
            timestamp: row["e_timestamp"],
            content: row["e_content"],
            contentSha256: row["e_content_sha256"],
            summary: row["e_summary"],
            disposition: row["e_disposition"],
            displayInTimeline: row["e_display_in_timeline"],
            isCompletion: row["e_is_completion"],
            isDirective: row["e_is_directive"],
            parentId: row["e_parent_id"],
            gitBranch: row["e_git_branch"],
            gitCommit: row["e_git_commit"],
            cwd: row["e_cwd"],
            prev1Id: row["e_prev1_id"],
            prev2Id: row["e_prev2_id"],
            windowSha256: row["e_window_sha256"],
            createdAt: row["e_created_at"],
            updatedAt: row["e_updated_at"]
          )

          // Check if cache fields present (if LEFT JOIN matched)
          let cache: TimelineCache? = if row["c_present_form"] != nil {
            TimelineCache(
              contentSha256: row["c_content_sha256"],
              windowSha256: row["c_window_sha256"],
              entryId: row["c_entry_id"],
              generatorSignature: row["c_generator_signature"],
              disposition: row["c_disposition"],
              presentForm: row["c_present_form"],
              pastForm: row["c_past_form"],
              selectedForm: row["c_selected_form"],
              verbLemma: row["c_verb_lemma"],
              generatedAt: row["c_generated_at"],
              userEdited: row["c_user_edited"],
              userText: row["c_user_text"],
              editedAt: row["c_edited_at"],
              requestId: row["c_request_id"],
              duration: row["c_duration"]
            )
          } else {
            nil
          }

          return (entry, cache)
        }
    }
  }
}

// MARK: - Metadata Repository

public protocol MetadataRepository {
  func upsert(_ metadata: TranscriptMetadataRecord) throws
  func get(_ transcriptId: String) throws -> TranscriptMetadataRecord?
  func stale(promptVersion: Int, generatorVersion: Int) throws -> [String]
}

public final class MetadataRepositoryImpl: MetadataRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func upsert(_ metadata: TranscriptMetadataRecord) throws {
    try db.write { db in
      try metadata.save(db)
    }
  }

  public func get(_ transcriptId: String) throws -> TranscriptMetadataRecord? {
    try db.read { db in
      try TranscriptMetadataRecord.fetchOne(db, key: transcriptId)
    }
  }

  public func stale(promptVersion: Int, generatorVersion: Int) throws -> [String] {
    try db.read { db in
      try TranscriptMetadataRecord
        .filter(sql: "prompt_version < ? OR generator_version < ?", arguments: [promptVersion, generatorVersion])
        .fetchAll(db)
        .map { $0.transcriptId }
    }
  }
}

// MARK: - Cache Repository

public protocol CacheRepository {
  func get(contentSha256: String, windowSha256: String) throws -> TimelineCache?
  func getMany(keys: [(String, String)]) throws -> [String: TimelineCache]
  func upsert(_ cache: TimelineCache) throws
}

public final class CacheRepositoryImpl: CacheRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func get(contentSha256: String, windowSha256: String) throws -> TimelineCache? {
    try db.read { db in
      try TimelineCache
        .filter(Column("content_sha256") == contentSha256 && Column("window_sha256") == windowSha256)
        .fetchOne(db)
    }
  }

  public func getMany(keys: [(String, String)]) throws -> [String: TimelineCache] {
    guard !keys.isEmpty else { return [:] }

    return try db.read { db in
      // Build SQL with IN clause for composite keys
      let placeholders = Array(repeating: "(?, ?)", count: keys.count).joined(separator: ", ")
      let sql = """
        SELECT * FROM timeline_cache
        WHERE (content_sha256, window_sha256) IN (\(placeholders))
      """

      let args = keys.flatMap { [$0.0, $0.1] }
      let caches = try TimelineCache.fetchAll(db, sql: sql, arguments: StatementArguments(args))

      // Build result map keyed by "contentSha|windowSha"
      var result: [String: TimelineCache] = [:]
      for cache in caches {
        let key = "\(cache.contentSha256)|\(cache.windowSha256)"
        result[key] = cache
      }
      return result
    }
  }

  public func upsert(_ cache: TimelineCache) throws {
    try db.write { db in
      try cache.save(db)
    }
  }
}

// MARK: - Parse Error Repository

public protocol ParseErrorRepository {
  func insert(
    transcriptId: String,
    lineNumber: Int,
    rawLine: String,
    errorMessage: String
  ) throws

  func byTranscript(_ transcriptId: String, limit: Int) throws -> [ParseError]
  func pruneOldest(transcriptId: String, keepLast: Int) throws
}

public final class ParseErrorRepositoryImpl: ParseErrorRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func insert(
    transcriptId: String,
    lineNumber: Int,
    rawLine: String,
    errorMessage: String
  ) throws {
    let id = UUID().uuidString
    let now = Int(Date().timeIntervalSince1970)

    // Truncate raw line to ~1K chars
    let truncated = String(rawLine.prefix(1024))

    let error = ParseError(
      id: id,
      transcriptId: transcriptId,
      lineNumber: lineNumber,
      rawLine: truncated,
      errorMessage: errorMessage,
      createdAt: now
    )

    try db.write { db in
      try error.insert(db)
    }
  }

  public func byTranscript(_ transcriptId: String, limit: Int) throws -> [ParseError] {
    try db.read { db in
      try ParseError
        .filter(Column("transcript_id") == transcriptId)
        .order(Column("created_at").desc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func pruneOldest(transcriptId: String, keepLast: Int) throws {
    try db.write { db in
      // Get IDs to delete (all but the newest N)
      let idsToDelete = try ParseError
        .filter(Column("transcript_id") == transcriptId)
        .order(Column("created_at").desc)
        .limit(-1, offset: keepLast)
        .fetchAll(db)
        .map { $0.id }

      // Delete them
      for id in idsToDelete {
        try ParseError.deleteOne(db, key: id)
      }
    }
  }
}

// MARK: - Errors

public enum RepositoryError: Error {
  case notFound
  case invalidData
}
