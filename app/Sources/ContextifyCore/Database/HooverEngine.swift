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
  public func hooverTranscript(
    _ transcript: Transcript,
    fileURL: URL,
    progress: IngestProgressSink
  ) throws {
    let startTime = Date()
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    progress.didStartTranscript(name: fileURL.lastPathComponent, totalLines: transcript.lineCount)

    var buffer = Data()
    var lineNo = transcript.lastProcessedLine
    var batch: [EntryInsert] = []
    var errors: [(lineNumber: Int, rawLine: String, error: String)] = []
    var transcriptHasher = SHA256Utils.IncrementalHasher()

    let nl: UInt8 = 0x0A // '\n'

    // Skip to resume point if needed
    if lineNo > 0 {
      var skippedLines = 0
      while skippedLines < lineNo {
        let chunk = try handle.read(upToCount: 64 * 1024)
        if chunk.isEmpty { break }
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
      let chunk = try handle.read(upToCount: 64 * 1024)
      if chunk.isEmpty { break }
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
            lineCount: lineNo
          )
          batch.removeAll()
          errors.removeAll()
          progress.didAdvance(linesProcessed: lineNo, totalLines: nil)
        }
      }
    }

    // Handle final partial line (no trailing newline)
    if !buffer.isEmpty {
      guard let lineString = String(data: buffer, encoding: .utf8) else {
        errors.append((lineNo + 1, "<invalid UTF-8>", "Final line is not valid UTF-8"))
        buffer.removeAll()
      }

      if !buffer.isEmpty {
        lineNo += 1
        transcriptHasher.update(lineData: buffer)

        do {
          let entry = try parser.parse(
            line: lineString!,
            lineNumber: lineNo,
            transcriptId: transcript.id,
            projectId: transcript.projectId,
            provider: transcript.provider,
            sessionId: transcript.providerSessionId
          )
          batch.append(entry)
        } catch {
          let truncated = String(lineString!.prefix(MonitorConfig.parseErrorMaxChars))
          errors.append((lineNo, truncated, error.localizedDescription))
        }
        buffer.removeAll()
      }
    }

    // Final batch
    if !batch.isEmpty || !errors.isEmpty {
      try commitBatch(
        transcriptId: transcript.id,
        entries: batch,
        errors: errors,
        lastProcessedLine: lineNo,
        lineCount: lineNo
      )
    }

    let duration = Date().timeIntervalSince(startTime)
    progress.didCompleteTranscript(durationMs: Int(duration * 1000))

    log.info("Hoovered transcript \(transcript.id): \(lineNo) lines in \(Int(duration * 1000))ms")
  }

  /// Commit a batch of entries and errors to the database
  private func commitBatch(
    transcriptId: String,
    entries: [EntryInsert],
    errors: [(lineNumber: Int, rawLine: String, error: String)],
    lastProcessedLine: Int,
    lineCount: Int
  ) throws {
    // Insert entries
    let models = entries.map { $0.toModel() }
    try entryRepo.insertBatch(models)

    // Insert errors
    for error in errors {
      try errorRepo.insert(
        transcriptId: transcriptId,
        lineNumber: error.lineNumber,
        rawLine: error.rawLine,
        errorMessage: error.error
      )
    }

    // Prune old errors
    try errorRepo.pruneOldest(
      transcriptId: transcriptId,
      keepLast: MonitorConfig.parseErrorRetentionPerTranscript
    )

    // Update transcript checkpoint
    try transcriptRepo.setIngestionState(
      id: transcriptId,
      lastProcessedLine: lastProcessedLine,
      lineCount: lineCount,
      parserVersion: 1,
      status: "active",
      lastError: nil
    )
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
