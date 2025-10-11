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
  func recentFeed(projectId: String, limit: Int, generatorSignature: String) throws -> [(TranscriptEntry, TimelineCache?)]
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
        .order(Column("timestamp").desc, Column("created_at").desc, Column("id").desc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func newByProject(_ projectId: String, afterTimestamp: Int) throws -> [TranscriptEntry] {
    try db.read { db in
      try TranscriptEntry
        .filter(Column("project_id") == projectId && Column("timestamp") > afterTimestamp && Column("display_in_timeline") == 1)
        .order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)
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

  public func recentFeed(projectId: String, limit: Int, generatorSignature: String) throws -> [(TranscriptEntry, TimelineCache?)] {
    let t0 = Date()
    defer {
      let ms = Int(Date().timeIntervalSince(t0) * 1000)
      if ms > 10 { log.warning("recentFeed took \(ms)ms for \(limit) entries") }
    }

    return try db.read { db in
      let sql = """
        SELECT e.*, c.*
        FROM transcript_entries e
        LEFT JOIN timeline_cache c
          ON c.content_sha256 = e.content_sha256
         AND c.window_sha256 = e.window_sha256
         AND c.generator_signature = ?
        WHERE e.project_id = ?
          AND e.display_in_timeline = 1
        ORDER BY e.timestamp DESC, e.created_at DESC, e.id DESC
        LIMIT ?
      """

      let adapter = ScopeAdapter([
        "e": RangeRowAdapter(0..<TranscriptEntry.databaseColumnCount),
        "c": RangeRowAdapter(TranscriptEntry.databaseColumnCount..<(TranscriptEntry.databaseColumnCount + TimelineCache.databaseColumnCount))
      ])

      return try Row
        .fetchAll(db, sql: sql, arguments: [generatorSignature, projectId, limit], adapter: adapter)
        .map { row in
          let entry = try TranscriptEntry(row: row.scopes["e"]!)

          // If cache row has content (LEFT JOIN matched), construct it; otherwise nil
          let cacheScope = row.scopes["c"]!
          let cache: TimelineCache? = if cacheScope["content_sha256"] != nil {
            try TimelineCache(row: cacheScope)
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
  func getManyWithSignature(keys: [CacheKey], generatorSignature: String) throws -> [CacheKey: TimelineCache]
  func upsert(_ cache: TimelineCache) throws
  func upsertMany(_ caches: [TimelineCache]) throws
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
      // Conditional upsert: only update if user hasn't edited
      // This preserves user customizations while allowing LLM regeneration
      try db.execute(sql: """
        INSERT INTO timeline_cache (
          content_sha256, window_sha256, entry_id, generator_signature,
          disposition, present_form, past_form, selected_form, verb_lemma,
          generated_at, user_edited, user_text, edited_at, request_id, duration
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(content_sha256, window_sha256) DO UPDATE SET
          entry_id = excluded.entry_id,
          generator_signature = excluded.generator_signature,
          disposition = excluded.disposition,
          present_form = excluded.present_form,
          past_form = excluded.past_form,
          selected_form = excluded.selected_form,
          verb_lemma = excluded.verb_lemma,
          generated_at = excluded.generated_at,
          request_id = excluded.request_id,
          duration = excluded.duration
        WHERE timeline_cache.user_edited = 0
      """, arguments: [
        cache.contentSha256,
        cache.windowSha256,
        cache.entryId,
        cache.generatorSignature,
        cache.disposition,
        cache.presentForm,
        cache.pastForm,
        cache.selectedForm,
        cache.verbLemma,
        cache.generatedAt,
        cache.userEdited,
        cache.userText,
        cache.editedAt,
        cache.requestId,
        cache.duration
      ])
    }
  }

  public func getManyWithSignature(keys: [CacheKey], generatorSignature: String) throws -> [CacheKey: TimelineCache] {
    guard !keys.isEmpty else { return [:] }

    return try db.read { db in
      var result: [CacheKey: TimelineCache] = [:]

      // Chunk by 300 pairs (~900 params + 1 signature per clause = ~901 total params per chunk)
      let chunkSize = 300
      for chunk in stride(from: 0, to: keys.count, by: chunkSize).map({ Array(keys[$0..<min($0 + chunkSize, keys.count)]) }) {
        let clauses = chunk.map { _ in
          "(content_sha256 = ? AND window_sha256 = ? AND generator_signature = ?)"
        }.joined(separator: " OR ")

        let sql = "SELECT * FROM timeline_cache WHERE \(clauses)"

        var args: [DatabaseValueConvertible] = []
        for key in chunk {
          args += [key.content, key.window, generatorSignature]
        }

        let caches = try TimelineCache.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        for cache in caches {
          let key = CacheKey(content: cache.contentSha256, window: cache.windowSha256)
          result[key] = cache
        }
      }

      return result
    }
  }

  public func upsertMany(_ caches: [TimelineCache]) throws {
    guard !caches.isEmpty else { return }

    try db.write { db in
      for cache in caches {
        // Use same conditional upsert logic as single upsert
        // CASE expressions ensure user_edited=1 rows are never clobbered
        try db.execute(sql: """
          INSERT INTO timeline_cache (
            content_sha256, window_sha256, entry_id, generator_signature,
            disposition, present_form, past_form, selected_form, verb_lemma,
            generated_at, user_edited, user_text, edited_at, request_id, duration
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(content_sha256, window_sha256) DO UPDATE SET
            entry_id = CASE WHEN timeline_cache.user_edited = 1 THEN timeline_cache.entry_id ELSE excluded.entry_id END,
            generator_signature = CASE WHEN timeline_cache.user_edited = 1 THEN timeline_cache.generator_signature ELSE excluded.generator_signature END,
            disposition = CASE WHEN timeline_cache.user_edited = 1 THEN timeline_cache.disposition ELSE excluded.disposition END,
            present_form = CASE WHEN timeline_cache.user_edited = 1 THEN timeline_cache.present_form ELSE excluded.present_form END,
            past_form = CASE WHEN timeline_cache.user_edited = 1 THEN timeline_cache.past_form ELSE excluded.past_form END,
            selected_form = CASE WHEN timeline_cache.user_edited = 1 THEN timeline_cache.selected_form ELSE excluded.selected_form END,
            verb_lemma = CASE WHEN timeline_cache.user_edited = 1 THEN timeline_cache.verb_lemma ELSE excluded.verb_lemma END,
            generated_at = CASE WHEN timeline_cache.user_edited = 1 THEN timeline_cache.generated_at ELSE excluded.generated_at END
        """, arguments: [
          cache.contentSha256,
          cache.windowSha256,
          cache.entryId,
          cache.generatorSignature,
          cache.disposition,
          cache.presentForm,
          cache.pastForm,
          cache.selectedForm,
          cache.verbLemma,
          cache.generatedAt,
          cache.userEdited,
          cache.userText,
          cache.editedAt,
          cache.requestId,
          cache.duration
        ])
      }
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
