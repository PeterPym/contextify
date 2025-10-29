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
  public let hasTextContent: Bool  // true if contains "text" blocks, false if only "thinking"

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
    cwd: String?,
    hasTextContent: Bool = true
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
    self.hasTextContent = hasTextContent
  }

  /// Convert to TranscriptEntry model
  public func toModel() -> TranscriptEntry {
    let now = Int(Date().timeIntervalSince1970)
    let epochSeconds = timestamp.timeIntervalSince1970
    return TranscriptEntry(
      id: id,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: sessionId,
      provider: provider,
      kind: kind,
      timestamp: Int(epochSeconds),
      content: content,
      contentSha256: contentSha256,
      displayInTimeline: hasTextContent ? 1 : 0,  // Hide thinking-only entries from timeline
      parentId: parentId,
      gitBranch: gitBranch,
      gitCommit: gitCommit,
      cwd: cwd,
      prev1Id: nil,
      prev2Id: nil,
      windowSha256: nil,
      createdTs: epochSeconds,  // Epoch timestamp for unread tracking
      createdAt: now,
      updatedAt: now
    )
  }
}

// MARK: - Metadata Batch (v7)

/// Container for accumulated metadata during ingestion
private struct MetadataBatch {
  var fileSnapshots: [FileSnapshot] = []
  var trackedFiles: [TrackedFile] = []
  var transcriptSummaries: [TranscriptSummary] = []
  var systemEvents: [SystemEvent] = []
  var assistantUsages: [AssistantUsage] = []

  mutating func add(_ result: MetadataParseResult) {
    if let snapshot = result.fileSnapshot {
      fileSnapshots.append(snapshot)
    }
    trackedFiles.append(contentsOf: result.trackedFiles)
    if let summary = result.transcriptSummary {
      transcriptSummaries.append(summary)
    }
    if let event = result.systemEvent {
      systemEvents.append(event)
    }
    if let usage = result.assistantUsage {
      assistantUsages.append(usage)
    }
  }

  mutating func clear() {
    fileSnapshots.removeAll()
    trackedFiles.removeAll()
    transcriptSummaries.removeAll()
    systemEvents.removeAll()
    assistantUsages.removeAll()
  }

  var isEmpty: Bool {
    fileSnapshots.isEmpty && trackedFiles.isEmpty && transcriptSummaries.isEmpty && systemEvents.isEmpty && assistantUsages.isEmpty
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
  // v7 metadata repositories
  private let fileSnapshotRepo: FileSnapshotRepository
  private let trackedFileRepo: TrackedFileRepository
  private let transcriptSummaryRepo: TranscriptSummaryRepository
  private let systemEventRepo: SystemEventRepository
  private let assistantUsageRepo: AssistantUsageRepository
  private let metadataParser: TranscriptMetadataParser

  public init(
    db: DatabasePool,
    transcriptRepo: TranscriptRepository,
    entryRepo: EntryRepository,
    errorRepo: ParseErrorRepository,
    parser: TranscriptLineParser,
    fileSnapshotRepo: FileSnapshotRepository,
    trackedFileRepo: TrackedFileRepository,
    transcriptSummaryRepo: TranscriptSummaryRepository,
    systemEventRepo: SystemEventRepository,
    assistantUsageRepo: AssistantUsageRepository,
    metadataParser: TranscriptMetadataParser
  ) {
    self.db = db
    self.transcriptRepo = transcriptRepo
    self.entryRepo = entryRepo
    self.errorRepo = errorRepo
    self.parser = parser
    self.fileSnapshotRepo = fileSnapshotRepo
    self.trackedFileRepo = trackedFileRepo
    self.transcriptSummaryRepo = transcriptSummaryRepo
    self.systemEventRepo = systemEventRepo
    self.assistantUsageRepo = assistantUsageRepo
    self.metadataParser = metadataParser
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
    var metadataBatch = MetadataBatch()  // v7: accumulate metadata
    var errors: [(lineNumber: Int, rawLine: String, error: String)] = []
    var transcriptHasher = SHA256Utils.IncrementalHasher()

    // Seed previousEntries from last processed entry for correct window state on resume
    var previousEntries: [String] = []
    if let lastId = transcript.lastProcessedEntryId {
      // Seed from the last processed entry (and its prev1)
      if let last = try? db.read({ db in try TranscriptEntry.fetchOne(db, key: lastId) }) {
        var seed: [String] = []
        if let p1 = last.prev1Id { seed.append(p1) } // oldest first
        seed.append(last.id)
        previousEntries = seed
      } else {
        // Graceful fallback: lastId is stale/deleted, fall back to 2-row seed
        let seed = try db.read { db in
          try Row.fetchAll(db, sql: """
            SELECT id FROM transcript_entries
            WHERE transcript_id = ?
            ORDER BY timestamp DESC, id DESC
            LIMIT 2
          """, arguments: [transcript.id])
          .compactMap { $0["id"] as String? }
          .reversed()
        }
        previousEntries = Array(seed.suffix(2))
      }
    } else {
      // Fresh transcript or old DB: seed with last two existing (if any)
      let seed = try db.read { db in
        try Row.fetchAll(db, sql: """
          SELECT id FROM transcript_entries
          WHERE transcript_id = ?
          ORDER BY timestamp DESC, id DESC
          LIMIT 2
        """, arguments: [transcript.id])
        .compactMap { $0["id"] as String? }
        .reversed()
      }
      previousEntries = Array(seed.suffix(2))
    }

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

        var entryId: String? = nil
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
          entryId = entry.id
        } catch ParserError.skipEntry {
          // Silently skip - this is expected for meta messages, empty content, etc.
          // Don't add to batch, don't record as error
        } catch {
          let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxChars))
          errors.append((lineNo, truncated, error.localizedDescription))
        }

        // v7: Extract metadata regardless of whether entry was added to batch
        if let metadataResult = try? metadataParser.parseMetadata(
          line: lineString,
          lineNumber: lineNo,
          transcriptId: transcript.id,
          projectId: transcript.projectId,
          provider: transcript.provider,
          entryId: entryId
        ) {
          metadataBatch.add(metadataResult)
        }

        // Checkpoint every N lines
        if batch.count >= MonitorConfig.batchLines {
          try commitBatch(
            transcriptId: transcript.id,
            entries: batch,
            metadata: metadataBatch,
            errors: errors,
            lastProcessedLine: lineNo,
            lineCount: lineNo,
            previousEntries: &previousEntries
          )
          batch.removeAll()
          metadataBatch.clear()
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

        var entryId: String? = nil
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
          entryId = entry.id
        } catch ParserError.skipEntry {
          // Silently skip - this is expected for meta messages, empty content, etc.
          // Don't add to batch, don't record as error
        } catch {
          let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxChars))
          errors.append((lineNo, truncated, error.localizedDescription))
        }

        // v7: Extract metadata from final line
        if let metadataResult = try? metadataParser.parseMetadata(
          line: lineString,
          lineNumber: lineNo,
          transcriptId: transcript.id,
          projectId: transcript.projectId,
          provider: transcript.provider,
          entryId: entryId
        ) {
          metadataBatch.add(metadataResult)
        }
      } else {
        errors.append((lineNo + 1, "<invalid UTF-8>", "Final line is not valid UTF-8"))
      }
      buffer.removeAll()
    }

    // Final batch
    if !batch.isEmpty || !errors.isEmpty || !metadataBatch.isEmpty {
      try commitBatch(
        transcriptId: transcript.id,
        entries: batch,
        metadata: metadataBatch,
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
    metadata: MetadataBatch,
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

        // Check if parent exists before inserting (avoid FK constraint violation)
        // This handles out-of-order entries where a child references a parent that hasn't been inserted yet
        if let parentId = model.parentId {
          let parentExists = try Bool.fetchOne(db, sql: """
            SELECT EXISTS(SELECT 1 FROM transcript_entries WHERE id = ?)
          """, arguments: [parentId]) ?? false

          if !parentExists {
            log.debug("Parent \(parentId) doesn't exist yet, setting parent_id to NULL for entry \(model.id)")
            model.parentId = nil  // Will be backfilled later if needed
          }
        }

        do {
          try model.insert(db, onConflict: .ignore)
        } catch {
          // Log detailed FK error info
          log.error("❌ Entry insert failed: \(error.localizedDescription)")
          log.error("   Entry ID: \(model.id)")
          log.error("   Transcript ID: \(model.transcriptId)")
          log.error("   Project ID: \(model.projectId)")
          log.error("   Parent ID: \(model.parentId ?? "nil")")
          log.error("   Prev1 ID: \(model.prev1Id ?? "nil")")
          log.error("   Prev2 ID: \(model.prev2Id ?? "nil")")
          throw error
        }

        // Update tracking (keep last 2)
        previousEntries.append(entry.id)
        if previousEntries.count > 2 {
          previousEntries.removeFirst()
        }
      }

      // v7: Insert metadata
      for snapshot in metadata.fileSnapshots {
        try snapshot.insert(db, onConflict: .ignore)
      }
      for file in metadata.trackedFiles {
        try file.insert(db, onConflict: .ignore)
      }
      for summary in metadata.transcriptSummaries {
        try summary.insert(db, onConflict: .ignore)
      }
      for event in metadata.systemEvents {
        try event.insert(db, onConflict: .ignore)
      }
      // FK-safe usage insert: single-statement to avoid round-trips and races
      for usage in metadata.assistantUsages {
        // Try direct insert with EXISTS guard (hot path for in-order ingestion)
        let stmt = try db.makeStatement(sql: """
          INSERT OR IGNORE INTO assistant_usage (
            entry_id, request_id, model, input_tokens, output_tokens,
            cache_creation_tokens, cache_read_tokens, service_tier,
            ephemeral_5m_tokens, ephemeral_1h_tokens
          )
          SELECT ?,?,?,?,?,?,?,?,?,?
          WHERE EXISTS (SELECT 1 FROM transcript_entries WHERE id = ?)
          """)
        try stmt.execute(arguments: [
          usage.entryId, usage.requestId, usage.model,
          usage.inputTokens, usage.outputTokens,
          usage.cacheCreationTokens, usage.cacheReadTokens,
          usage.serviceTier, usage.ephemeral5mTokens, usage.ephemeral1hTokens,
          usage.entryId  // for EXISTS check
        ])

        // If nothing was inserted (entry doesn't exist yet), stage for reconciliation
        let inserted = db.changesCount > 0
        if !inserted {
          try db.execute(sql: """
            INSERT OR REPLACE INTO assistant_usage_pending (
              entry_id, request_id, model, input_tokens, output_tokens,
              cache_creation_tokens, cache_read_tokens, service_tier,
              ephemeral_5m_tokens, ephemeral_1h_tokens
            ) VALUES (?,?,?,?,?,?,?,?,?,?)
            """,
            arguments: [
              usage.entryId, usage.requestId, usage.model,
              usage.inputTokens, usage.outputTokens,
              usage.cacheCreationTokens, usage.cacheReadTokens,
              usage.serviceTier, usage.ephemeral5mTokens, usage.ephemeral1hTokens
            ]
          )
          log.debug("Staged usage for entry \(usage.entryId) (entry not yet present)")
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

      // Update transcript checkpoint with last processed entry ID
      // Use COALESCE to preserve existing ID if this batch had only errors
      let lastEntryId = entries.last?.id
      try db.execute(sql: """
        UPDATE transcripts
        SET last_processed_line = ?,
            last_processed_entry_id = COALESCE(?, last_processed_entry_id),
            line_count = ?,
            parser_version = ?,
            status = 'active',
            last_error = NULL,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        lastProcessedLine,
        lastEntryId,
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
  case skipEntry  // Indicates entry should be skipped (meta messages, empty content, etc.)
}
