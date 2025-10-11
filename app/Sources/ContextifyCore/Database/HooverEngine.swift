import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "HooverEngine")

// MARK: - Configuration

public enum MonitorConfig {
  public static let fileWatcherDebounce: TimeInterval = 0.150
  public static let batchLines: Int = 1000
  public static let checkpointEveryLines: Int = 1000
  public static let parseErrorMaxChars: Int = 1024
  public static let parseErrorRetentionPerTranscript: Int = 500
}

// MARK: - Parsed Entry Insert

/// Intermediate struct for entries before DB insert
public struct EntryInsert {
  public let id: String
  public let transcriptId: String
  public let projectId: String
  public let sessionId: String?
  public let provider: String
  public let kind: String
  public let timestamp: Date
  public let content: String
  public let contentSha256: String
  public let parentId: String?
  public let gitBranch: String?
  public let gitCommit: String?
  public let cwd: String?

  public init(
    id: String,
    transcriptId: String,
    projectId: String,
    sessionId: String?,
    provider: String,
    kind: String,
    timestamp: Date,
    content: String,
    contentSha256: String,
    parentId: String?,
    gitBranch: String?,
    gitCommit: String?,
    cwd: String?
  ) {
    self.id = id
    self.transcriptId = transcriptId
    self.projectId = projectId
    self.sessionId = sessionId
    self.provider = provider
    self.kind = kind
    self.timestamp = timestamp
    self.content = content
    self.contentSha256 = contentSha256
    self.parentId = parentId
    self.gitBranch = gitBranch
    self.gitCommit = gitCommit
    self.cwd = cwd
  }

  /// Convert to TranscriptEntry model
  public func toModel() -> TranscriptEntry {
    let now = Int(Date().timeIntervalSince1970)
    return TranscriptEntry(
      id: id,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: sessionId,
      provider: provider,
      kind: kind,
      timestamp: Int(timestamp.timeIntervalSince1970),
      content: content,
      contentSha256: contentSha256,
      summary: nil,
      disposition: nil,
      displayInTimeline: 1,
      isCompletion: 0,
      isDirective: 0,
      parentId: parentId,
      gitBranch: gitBranch,
      gitCommit: gitCommit,
      cwd: cwd,
      createdAt: now,
      updatedAt: now
    )
  }
}

// MARK: - Hoover Engine

/// Streaming transcript parser and ingestion engine
public final class HooverEngine {
  private let db: DatabasePool
  private let transcriptRepo: TranscriptRepository
  private let entryRepo: EntryRepository
  private let errorRepo: ParseErrorRepository
  private let parser: TranscriptLineParser

  public init(
    db: DatabasePool,
    transcriptRepo: TranscriptRepository,
    entryRepo: EntryRepository,
    errorRepo: ParseErrorRepository,
    parser: TranscriptLineParser
  ) {
    self.db = db
    self.transcriptRepo = transcriptRepo
    self.entryRepo = entryRepo
    self.errorRepo = errorRepo
    self.parser = parser
  }

  /// Hoover a transcript with streaming parser
  /// Returns the SHA256 hash of the entire transcript content
  @discardableResult
  public func hooverTranscript(
    _ transcript: Transcript,
    fileURL: URL,
    progress: IngestProgressSink
  ) throws -> String {
    let startTime = Date()
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    progress.didStartTranscript(name: fileURL.lastPathComponent, totalLines: transcript.lineCount)

    var buffer = Data()
    var lineNo = transcript.lastProcessedLine
    var batch: [EntryInsert] = []
    var errors: [(lineNumber: Int, rawLine: String, error: String)] = []
    var transcriptHasher = SHA256Utils.IncrementalHasher()
    var previousEntries: [String] = [] // Track last 2 entry IDs for window computation

    let nl: UInt8 = 0x0A // '\n'

    // Skip to resume point if needed
    if lineNo > 0 {
      var skippedLines = 0
      while skippedLines < lineNo {
        guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
        buffer.append(chunk)

        while let i = buffer.firstIndex(of: nl) {
          let lineData = buffer[..<i]
          buffer.removeSubrange(..<buffer.index(after: i))
          transcriptHasher.update(lineData: lineData)
          skippedLines += 1
          if skippedLines >= lineNo { break }
        }
      }
      buffer.removeAll()
    }

    // Process remaining lines
    while true {
      guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
      buffer.append(chunk)

      while let i = buffer.firstIndex(of: nl) {
        let lineData = buffer[..<i]
        buffer.removeSubrange(..<buffer.index(after: i))
        lineNo += 1
        transcriptHasher.update(lineData: lineData)

        guard let lineString = String(data: lineData, encoding: .utf8) else {
          errors.append((lineNo, "<invalid UTF-8>", "Line is not valid UTF-8"))
          continue
        }

        do {
          let entry = try parser.parse(
            line: lineString,
            lineNumber: lineNo,
            transcriptId: transcript.id,
            projectId: transcript.projectId,
            provider: transcript.provider,
            sessionId: transcript.providerSessionId
          )
          batch.append(entry)
        } catch {
          let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxChars))
          errors.append((lineNo, truncated, error.localizedDescription))
        }

        // Checkpoint every N lines
        if batch.count >= MonitorConfig.batchLines {
          try commitBatch(
            transcriptId: transcript.id,
            entries: batch,
            errors: errors,
            lastProcessedLine: lineNo,
            lineCount: lineNo,
            previousEntries: &previousEntries
          )
          batch.removeAll()
          errors.removeAll()
          progress.didAdvance(linesProcessed: lineNo, totalLines: nil)
        }
      }
    }

    // Handle final partial line (no trailing newline)
    if !buffer.isEmpty {
      if let lineString = String(data: buffer, encoding: .utf8) {
        lineNo += 1
        transcriptHasher.update(lineData: buffer)

        do {
          let entry = try parser.parse(
            line: lineString,
            lineNumber: lineNo,
            transcriptId: transcript.id,
            projectId: transcript.projectId,
            provider: transcript.provider,
            sessionId: transcript.providerSessionId
          )
          batch.append(entry)
        } catch {
          let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxChars))
          errors.append((lineNo, truncated, error.localizedDescription))
        }
      } else {
        errors.append((lineNo + 1, "<invalid UTF-8>", "Final line is not valid UTF-8"))
      }
      buffer.removeAll()
    }

    // Final batch
    if !batch.isEmpty || !errors.isEmpty {
      try commitBatch(
        transcriptId: transcript.id,
        entries: batch,
        errors: errors,
        lastProcessedLine: lineNo,
        lineCount: lineNo,
        previousEntries: &previousEntries
      )
    }

    let duration = Date().timeIntervalSince(startTime)
    progress.didCompleteTranscript(durationMs: Int(duration * 1000))

    let transcriptSHA256 = transcriptHasher.finalize()
    let linesPerSec = duration > 0 ? Int(Double(lineNo) / duration) : 0
    log.info("Hoovered transcript \(transcript.id): \(lineNo) lines in \(Int(duration * 1000))ms (\(linesPerSec)/s)")

    return transcriptSHA256
  }

  /// Commit a batch of entries and errors to the database
  /// All operations are atomic within a single transaction
  /// Tracks previous entries for window SHA256 computation
  private func commitBatch(
    transcriptId: String,
    entries: [EntryInsert],
    errors: [(lineNumber: Int, rawLine: String, error: String)],
    lastProcessedLine: Int,
    lineCount: Int,
    previousEntries: inout [String]
  ) throws {
    try db.write { db in
      // Insert entries with window tracking
      for entry in entries {
        // Compute window from previous 2 entries
        let prev1 = previousEntries.last
        let prev2 = previousEntries.count >= 2 ? previousEntries[previousEntries.count - 2] : nil
        let windowSha = SHA256Utils.computeWindowSHA256(prev2: prev2, prev1: prev1)

        var model = entry.toModel()
        model.prev1Id = prev1
        model.prev2Id = prev2
        model.windowSha256 = windowSha

        try model.insert(db, onConflict: .ignore)

        // Update tracking (keep last 2)
        previousEntries.append(entry.id)
        if previousEntries.count > 2 {
          previousEntries.removeFirst()
        }
      }

      // Insert errors (bulk insert)
      if !errors.isEmpty {
        let now = Int(Date().timeIntervalSince1970)
        let stmt = try db.makeStatement(sql: """
          INSERT INTO parse_errors (id, transcript_id, line_number, raw_line, error_message, created_at)
          VALUES (?, ?, ?, ?, ?, ?)
        """)
        for error in errors {
          let truncated = String(error.rawLine.prefix(MonitorConfig.parseErrorMaxChars))
          try stmt.execute(arguments: [
            UUID().uuidString,
            transcriptId,
            error.lineNumber,
            truncated,
            error.error,
            now
          ])
        }
      }

      // Prune old errors (single SQL)
      try db.execute(sql: """
        DELETE FROM parse_errors
        WHERE id IN (
          SELECT id FROM parse_errors
          WHERE transcript_id = ?
          ORDER BY created_at DESC
          LIMIT -1 OFFSET ?
        )
      """, arguments: [transcriptId, MonitorConfig.parseErrorRetentionPerTranscript])

      // Update transcript checkpoint
      try db.execute(sql: """
        UPDATE transcripts
        SET last_processed_line = ?,
            line_count = ?,
            parser_version = ?,
            status = 'active',
            last_error = NULL,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        lastProcessedLine,
        lineCount,
        1,
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])
    }
  }
}

// MARK: - Parser Protocol

/// Protocol for parsing transcript lines
public protocol TranscriptLineParser {
  func parse(
    line: String,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    sessionId: String?
  ) throws -> EntryInsert
}

public enum ParserError: Error {
  case invalidJSON
  case missingRequiredField(String)
  case unsupportedProvider(String)
  case invalidFormat(String)
}
