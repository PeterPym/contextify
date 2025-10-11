import Foundation
import GRDB

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

    try db.write { db in
      let project = Project(
        id: id,
        name: name,
        rootPath: rootPath,
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
  func insertBatch(_ entries: [TranscriptEntry]) throws
  func recentByProject(_ projectId: String, limit: Int) throws -> [TranscriptEntry]
  func byTranscript(_ transcriptId: String, afterTimestamp: Date?) throws -> [TranscriptEntry]
  func search(content: String, projectId: String?) throws -> [TranscriptEntry]
}

public final class EntryRepositoryImpl: EntryRepository {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
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
        .filter(Column("project_id") == projectId)
        .order(Column("timestamp").desc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  public func byTranscript(_ transcriptId: String, afterTimestamp: Date? = nil) throws -> [TranscriptEntry] {
    try db.read { db in
      var query = TranscriptEntry.filter(Column("transcript_id") == transcriptId)
      if let after = afterTimestamp {
        query = query.filter(Column("timestamp") > Int(after.timeIntervalSince1970))
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
        .filter(Column("prompt_version") < promptVersion || Column("generator_version") < generatorVersion)
        .fetchAll(db)
        .map { $0.transcriptId }
    }
  }
}

// MARK: - Cache Repository

public protocol CacheRepository {
  func get(contentSha256: String, windowSha256: String) throws -> TimelineCache?
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
