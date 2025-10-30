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
        lastViewedTs: 0.0,  // Never viewed yet (all entries unread)
        hidden: false,  // Visible by default (v18)
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

  // v2: Keyset pagination for incremental updates
  func entriesAfterCursor(projectId: String, after: (timestamp: Int, createdAt: Int, id: String)) throws -> [TranscriptEntry]

  // Get latest conversation timestamp for each transcript in a project
  func latestTimestampsByTranscript(projectId: String) throws -> [String: Int]
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
      // Get most recent entries (DESC) then reverse to chronological order
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

      let rows = try Row
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

      // Reverse to get chronological order (oldest to newest)
      return rows.reversed()
    }
  }

  public func entriesAfterCursor(projectId: String, after: (timestamp: Int, createdAt: Int, id: String)) throws -> [TranscriptEntry] {
    try db.read { db in
      try TranscriptEntry
        .filter(Column("project_id") == projectId && Column("display_in_timeline") == 1)
        .filter(sql: "(timestamp, created_at, id) > (?, ?, ?)", arguments: [after.timestamp, after.createdAt, after.id])
        .order(Column("timestamp").asc, Column("created_at").asc, Column("id").asc)
        .fetchAll(db)
    }
  }

  public func latestTimestampsByTranscript(projectId: String) throws -> [String: Int] {
    try db.read { db in
      let sql = """
        SELECT transcript_id, MAX(timestamp) as latest_timestamp
        FROM transcript_entries
        WHERE project_id = ?
        GROUP BY transcript_id
      """

      let rows = try Row.fetchAll(db, sql: sql, arguments: [projectId])
      var result: [String: Int] = [:]
      for row in rows {
        if let transcriptId: String = row["transcript_id"],
           let timestamp: Int = row["latest_timestamp"] {
          result[transcriptId] = timestamp
        }
      }
      return result
    }
  }
}

// MARK: - Metadata Repository

public protocol MetadataRepository {
  func upsert(_ metadata: TranscriptMetadataRecord) throws
  func get(_ transcriptId: String) throws -> TranscriptMetadataRecord?
  func getBatch(_ transcriptIds: [String]) throws -> [String: TranscriptMetadataRecord]
  func delete(_ transcriptId: String) throws
  func stale(promptVersion: Int, generatorVersion: Int) throws -> [String]
}

public final class MetadataRepositoryImpl: MetadataRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func upsert(_ r: TranscriptMetadataRecord) throws {
    try db.write { db in
      try db.execute(sql: """
        INSERT INTO transcript_metadata (
          transcript_id, project_id, title, description, topics, confidence,
          may_contain_hallucinations, needs_review, generated_at, model,
          prompt_version, generator_version, transcript_sha256, message_count,
          strategy, llm_calls, latency_ms, created_at, updated_at
        )
        VALUES (
          ?, (SELECT project_id FROM transcripts WHERE id = ?),
          ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        )
        ON CONFLICT(transcript_id) DO UPDATE SET
          title = excluded.title,
          description = excluded.description,
          topics = excluded.topics,
          confidence = excluded.confidence,
          may_contain_hallucinations = excluded.may_contain_hallucinations,
          needs_review = excluded.needs_review,
          generated_at = excluded.generated_at,
          model = excluded.model,
          prompt_version = excluded.prompt_version,
          generator_version = excluded.generator_version,
          transcript_sha256 = excluded.transcript_sha256,
          message_count = excluded.message_count,
          strategy = excluded.strategy,
          llm_calls = excluded.llm_calls,
          latency_ms = excluded.latency_ms,
          updated_at = excluded.updated_at
      """, arguments: [
        r.transcriptId, r.transcriptId,
        r.title, r.description, r.topics, r.confidence,
        r.mayContainHallucinations, r.needsReview, r.generatedAt, r.model,
        r.promptVersion, r.generatorVersion, r.transcriptSha256, r.messageCount,
        r.strategy, r.llmCalls, r.latencyMs, r.createdAt, r.updatedAt
      ])
    }
  }

  public func get(_ transcriptId: String) throws -> TranscriptMetadataRecord? {
    try db.read { db in
      try TranscriptMetadataRecord.fetchOne(db, key: transcriptId)
    }
  }

  public func getBatch(_ transcriptIds: [String]) throws -> [String: TranscriptMetadataRecord] {
    guard !transcriptIds.isEmpty else { return [:] }
    // SQLite default SQLITE_MAX_VARIABLE_NUMBER is 999. Use 900 for headroom + future SQL additions.
    let PARAM_LIMIT_SAFE = 900
    return try db.read { db in
      var result: [String: TranscriptMetadataRecord] = [:]
      for start in stride(from: 0, to: transcriptIds.count, by: PARAM_LIMIT_SAFE) {
        let end = min(start + PARAM_LIMIT_SAFE, transcriptIds.count)
        let ids = Array(transcriptIds[start..<end])
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        precondition(ids.count == placeholders.split(separator: ",").count)
        let rows = try Row.fetchAll(db, sql: """
          SELECT * FROM transcript_metadata WHERE transcript_id IN (\(placeholders))
        """, arguments: StatementArguments(ids))
        for row in rows {
          if let id: String = row["transcript_id"],
             let rec = try? TranscriptMetadataRecord(row: row) {
            result[id] = rec
          }
        }
      }
      return result
    }
  }

  public func delete(_ transcriptId: String) throws {
    try db.write { db in
      try db.execute(sql: "DELETE FROM transcript_metadata WHERE transcript_id = ?", arguments: [transcriptId])
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

// MARK: - File Snapshot Repository (v7 metadata)

public protocol FileSnapshotRepository {
  func insert(_ snapshot: FileSnapshot) throws
  func byTranscript(_ transcriptId: String) throws -> [FileSnapshot]
  func get(_ id: String) throws -> FileSnapshot?
  func byMessageId(_ messageId: String) throws -> FileSnapshot?
}

public final class FileSnapshotRepositoryImpl: FileSnapshotRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func insert(_ snapshot: FileSnapshot) throws {
    try db.write { db in
      try snapshot.insert(db)
    }
  }

  public func byTranscript(_ transcriptId: String) throws -> [FileSnapshot] {
    try db.read { db in
      try FileSnapshot
        .filter(Column("transcript_id") == transcriptId)
        .order(Column("snapshot_timestamp").asc)
        .fetchAll(db)
    }
  }

  public func get(_ id: String) throws -> FileSnapshot? {
    try db.read { db in
      try FileSnapshot.fetchOne(db, key: id)
    }
  }

  public func byMessageId(_ messageId: String) throws -> FileSnapshot? {
    try db.read { db in
      try FileSnapshot
        .filter(Column("message_id") == messageId)
        .fetchOne(db)
    }
  }
}

// MARK: - Tracked File Repository (v7 metadata)

public protocol TrackedFileRepository {
  func insert(_ file: TrackedFile) throws
  func insertBatch(_ files: [TrackedFile]) throws
  func bySnapshot(_ snapshotId: String) throws -> [TrackedFile]
  func byFilePath(_ projectId: String, path: String, limit: Int) throws -> [TrackedFile]
}

public final class TrackedFileRepositoryImpl: TrackedFileRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func insert(_ file: TrackedFile) throws {
    try db.write { db in
      try file.insert(db)
    }
  }

  public func insertBatch(_ files: [TrackedFile]) throws {
    try db.write { db in
      for file in files {
        try file.insert(db)
      }
    }
  }

  public func bySnapshot(_ snapshotId: String) throws -> [TrackedFile] {
    try db.read { db in
      try TrackedFile
        .filter(Column("snapshot_id") == snapshotId)
        .order(Column("file_path").asc)
        .fetchAll(db)
    }
  }

  public func byFilePath(_ projectId: String, path: String, limit: Int) throws -> [TrackedFile] {
    try db.read { db in
      // Join with file_snapshots to filter by project
      let sql = """
        SELECT tf.*
        FROM tracked_files tf
        JOIN file_snapshots fs ON tf.snapshot_id = fs.id
        JOIN transcripts t ON fs.transcript_id = t.id
        WHERE t.project_id = ? AND tf.file_path = ?
        ORDER BY tf.backup_time DESC
        LIMIT ?
      """
      return try TrackedFile.fetchAll(db, sql: sql, arguments: [projectId, path, limit])
    }
  }
}

// MARK: - Transcript Summary Repository (v7 metadata)

public protocol TranscriptSummaryRepository {
  func insert(_ summary: TranscriptSummary) throws
  func get(_ transcriptId: String) throws -> TranscriptSummary?
  func update(_ summary: TranscriptSummary) throws
}

public final class TranscriptSummaryRepositoryImpl: TranscriptSummaryRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func insert(_ summary: TranscriptSummary) throws {
    try db.write { db in
      try summary.insert(db)
    }
  }

  public func get(_ transcriptId: String) throws -> TranscriptSummary? {
    try db.read { db in
      try TranscriptSummary
        .filter(Column("transcript_id") == transcriptId)
        .fetchOne(db)
    }
  }

  public func update(_ summary: TranscriptSummary) throws {
    try db.write { db in
      try summary.update(db)
    }
  }
}

// MARK: - System Event Repository (v7 metadata)

public protocol SystemEventRepository {
  func insert(_ event: SystemEvent) throws
  func byTranscript(_ transcriptId: String, limit: Int) throws -> [SystemEvent]
  func bySubtype(_ transcriptId: String, subtype: String, limit: Int) throws -> [SystemEvent]
  func errorEvents(_ transcriptId: String, limit: Int) throws -> [SystemEvent]
}

public final class SystemEventRepositoryImpl: SystemEventRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func insert(_ event: SystemEvent) throws {
    try db.write { db in
      try event.insert(db)
    }
  }

  public func byTranscript(_ transcriptId: String, limit: Int) throws -> [SystemEvent] {
    try db.read { db in
      try SystemEvent
        .filter(Column("transcript_id") == transcriptId)
        .order(Column("timestamp").desc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func bySubtype(_ transcriptId: String, subtype: String, limit: Int) throws -> [SystemEvent] {
    try db.read { db in
      try SystemEvent
        .filter(Column("transcript_id") == transcriptId && Column("subtype") == subtype)
        .order(Column("timestamp").desc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func errorEvents(_ transcriptId: String, limit: Int) throws -> [SystemEvent] {
    try db.read { db in
      try SystemEvent
        .filter(Column("transcript_id") == transcriptId && Column("error") != nil)
        .order(Column("timestamp").desc)
        .limit(limit)
        .fetchAll(db)
    }
  }
}

// MARK: - Assistant Usage Repository (v7 metadata)

public protocol AssistantUsageRepository {
  func insert(_ usage: AssistantUsage) throws
  func get(_ entryId: String) throws -> AssistantUsage?
  func aggregateByTranscript(_ transcriptId: String) throws -> UsageAggregate
  func aggregateByProject(_ projectId: String, startDate: Date?, endDate: Date?) throws -> UsageAggregate
}

public struct UsageAggregate {
  public let totalInputTokens: Int
  public let totalOutputTokens: Int
  public let totalCacheCreation: Int
  public let totalCacheRead: Int
  public let messageCount: Int

  public init(totalInputTokens: Int, totalOutputTokens: Int, totalCacheCreation: Int, totalCacheRead: Int, messageCount: Int) {
    self.totalInputTokens = totalInputTokens
    self.totalOutputTokens = totalOutputTokens
    self.totalCacheCreation = totalCacheCreation
    self.totalCacheRead = totalCacheRead
    self.messageCount = messageCount
  }
}

public final class AssistantUsageRepositoryImpl: AssistantUsageRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func insert(_ usage: AssistantUsage) throws {
    try db.write { db in
      try usage.insert(db)
    }
  }

  public func get(_ entryId: String) throws -> AssistantUsage? {
    try db.read { db in
      // With composite PK (entry_id, request_id), just fetch first match
      // Note: request_id is not time-ordered; if multiple exist, order is undefined
      // Callers needing specific request_id should use get(_:requestId:)
      try AssistantUsage
        .filter(Column("entry_id") == entryId)
        .fetchOne(db)
    }
  }

  public func aggregateByTranscript(_ transcriptId: String) throws -> UsageAggregate {
    try db.read { db in
      let sql = """
        SELECT
          COALESCE(SUM(input_tokens), 0) as total_input,
          COALESCE(SUM(output_tokens), 0) as total_output,
          COALESCE(SUM(cache_creation_tokens), 0) as total_cache_creation,
          COALESCE(SUM(cache_read_tokens), 0) as total_cache_read,
          COUNT(*) as message_count
        FROM assistant_usage au
        JOIN transcript_entries te ON au.entry_id = te.id
        WHERE te.transcript_id = ?
      """
      let row = try Row.fetchOne(db, sql: sql, arguments: [transcriptId])!
      return UsageAggregate(
        totalInputTokens: row["total_input"],
        totalOutputTokens: row["total_output"],
        totalCacheCreation: row["total_cache_creation"],
        totalCacheRead: row["total_cache_read"],
        messageCount: row["message_count"]
      )
    }
  }

  public func aggregateByProject(_ projectId: String, startDate: Date?, endDate: Date?) throws -> UsageAggregate {
    try db.read { db in
      var sql = """
        SELECT
          COALESCE(SUM(input_tokens), 0) as total_input,
          COALESCE(SUM(output_tokens), 0) as total_output,
          COALESCE(SUM(cache_creation_tokens), 0) as total_cache_creation,
          COALESCE(SUM(cache_read_tokens), 0) as total_cache_read,
          COUNT(*) as message_count
        FROM assistant_usage au
        JOIN transcript_entries te ON au.entry_id = te.id
        WHERE te.project_id = ?
      """

      var args: [DatabaseValueConvertible] = [projectId]

      if let start = startDate {
        sql += " AND te.timestamp >= ?"
        args.append(Int(start.timeIntervalSince1970))
      }

      if let end = endDate {
        sql += " AND te.timestamp <= ?"
        args.append(Int(end.timeIntervalSince1970))
      }

      let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(args))!
      return UsageAggregate(
        totalInputTokens: row["total_input"],
        totalOutputTokens: row["total_output"],
        totalCacheCreation: row["total_cache_creation"],
        totalCacheRead: row["total_cache_read"],
        messageCount: row["message_count"]
      )
    }
  }
}

// MARK: - Errors

public enum RepositoryError: Error {
  case notFound
  case invalidData
}
