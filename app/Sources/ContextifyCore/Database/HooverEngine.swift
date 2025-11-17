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
  public static let parseErrorLogLimit: Int = 25
  public static let parseErrorAbortThreshold: Int = 50
  public static let enableHooverLoopTracing: Bool = {
    ProcessInfo.processInfo.environment["CONTEXTIFY_TRACE_HOOVER_LOOPS"] == "1"
  }()
  public static let enableHooverStorageTracing: Bool = {
    ProcessInfo.processInfo.environment["CONTEXTIFY_TRACE_HOOVER_STORAGE"] == "1"
  }()
}

// MARK: - Hoover Limits

public enum IngestLimit: Sendable {
  case none
  case entries(Int)

  var maxEntries: Int? {
    switch self {
    case .none:
      return nil
    case let .entries(value):
      return value
    }
  }
}

public struct HooverOutcome {
  public let processedLines: Int
  public let newEntries: Int
  public let reachedEOF: Bool
  public let lastEntryId: String?
  public let contentSha256: String?
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
      createdTs: TimeUnits.truncateToMillis(epochSeconds),  // Truncate to milliseconds for consistent precision
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

  /// Update transcript checkpoint in database
  /// Always call this after processing a transcript to persist the checkpoint
  private func updateCheckpoint(
    transcriptId: String,
    lastProcessedLine: Int,
    lastProcessedEntryId: String?,
    lineCount: Int,
    ingestState: String,
    status: String = "active",
    lastError: String? = nil
  ) throws {
    try db.write { db in
      try db.execute(sql: """
        UPDATE transcripts
        SET last_processed_line = ?,
            last_processed_entry_id = COALESCE(?, last_processed_entry_id),
            line_count = ?,
            parser_version = ?,
            status = ?,
            ingest_state = ?,
            last_error = ?,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        lastProcessedLine,
        lastProcessedEntryId,
        lineCount,
        1,
        status,
        ingestState,
        lastError,
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])

      // Validate UPDATE succeeded
      let rowsAffected = db.changesCount
      log.info("[HOOVER-UPDATE-ROWS] UPDATE affected \(rowsAffected, privacy: .public) rows for transcript: \(transcriptId, privacy: .public), checkpoint: \(lastProcessedLine, privacy: .public)")

      if rowsAffected == 0 {
        log.error("[HOOVER-UPDATE-FAILED] UPDATE affected 0 rows! Transcript ID: \(transcriptId, privacy: .public)")
        if let existing = try? Transcript.fetchOne(db, key: transcriptId) {
          log.error("[HOOVER-UPDATE-FAILED] Transcript EXISTS in database with checkpoint: \(existing.lastProcessedLine, privacy: .public)")
        } else {
          log.error("[HOOVER-UPDATE-FAILED] Transcript NOT FOUND in database (ID mismatch?)")
        }
      }
    }
  }

  /// Hoover a transcript with streaming parser
  /// Returns outcome information for the ingestion run
  public func hooverTranscript(
    _ transcript: Transcript,
    fileURL: URL,
    progress: IngestProgressSink,
    limit: IngestLimit = .none
  ) throws -> HooverOutcome {
    log.info("[HOOVER-START] Starting hoover for transcript: \(transcript.id, privacy: .public) from checkpoint: \(transcript.lastProcessedLine, privacy: .public)")
    let startTime = Date()

    // Verify file size before opening handle
    let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64 ?? 0
    log.debug("[HOOVER-FILE-SIZE] File size: \(fileSize) bytes for transcript: \(transcript.id, privacy: .public)")

    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    // Verify FileHandle can see the file content
    let endOffset = handle.seekToEndOfFile()
    handle.seek(toFileOffset: 0) // Reset to beginning
    log.debug("[HOOVER-FILE-VERIFY] File handle opened, size: \(endOffset) bytes for transcript: \(transcript.id, privacy: .public)")

    progress.didStartTranscript(name: fileURL.lastPathComponent, totalLines: transcript.lineCount)

    var buffer = Data()
    var lineNo = transcript.lastProcessedLine
    var batch: [EntryInsert] = []
    var metadataBatch = MetadataBatch()  // v7: accumulate metadata
    var errors: [(lineNumber: Int, rawLine: String, error: String)] = []
    var transcriptHasher = SHA256Utils.IncrementalHasher()
    var lastEntryId: String? = nil  // Track last entry ID for checkpoint
    var parsedEntryCount = 0
    var parseErrorCount = 0
    var firstParseErrorLine: Int?
    var firstParseErrorReason: String?
    var hasLoggedParseErrorOverflow = false
    var limitReached = false
    var hitEOF = false

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
      // DO NOT clear buffer here - it contains the start of the next unprocessed line
      // buffer.removeAll()
    }

    // Process remaining lines
    var outerLoopCount = 0
    outerLoop: while true {
      outerLoopCount += 1
      if MonitorConfig.enableHooverLoopTracing {
        log.debug("[HOOVER-OUTER-LOOP] Iteration \(outerLoopCount): lineNo=\(lineNo), bufferSize=\(buffer.count) bytes")
      }

      // DRAIN BUFFER FIRST - process all complete lines already in buffer
      var innerLoopCount = 0
      while let i = buffer.firstIndex(of: nl) {
        innerLoopCount += 1

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
          lastEntryId = entry.id  // Track for checkpoint
        } catch ParserError.skipEntry {
          // Silently skip - this is expected for meta messages, empty content, etc.
          // Don't add to batch, don't record as error

          // NEW: Log if this was a large line (diagnostic for hang investigation)
          if lineData.count > 50_000 {
            log.info("[HOOVER-SKIP-LARGE] Line \(lineNo) skipped, size: \(lineData.count) bytes")
          }
        } catch {
          parseErrorCount += 1
          if firstParseErrorReason == nil {
            firstParseErrorLine = lineNo
            firstParseErrorReason = error.localizedDescription
            log.warning("[HOOVER-PARSE-ERROR] transcript=\(transcript.id, privacy: .public) path=\(transcript.filePath, privacy: .public) line=\(lineNo, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
          } else if !hasLoggedParseErrorOverflow && parseErrorCount == MonitorConfig.parseErrorLogLimit {
            log.warning("[HOOVER-PARSE-ERROR] transcript=\(transcript.id, privacy: .public) path=\(transcript.filePath, privacy: .public) exceeding \(MonitorConfig.parseErrorLogLimit, privacy: .public) parse errors, suppressing additional logs")
            hasLoggedParseErrorOverflow = true
          }

          if errors.count < MonitorConfig.parseErrorRetentionPerTranscript {
            let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxChars))
            errors.append((lineNo, truncated, error.localizedDescription))
          }

          if !limitReached,
             parsedEntryCount == 0,
             parseErrorCount >= MonitorConfig.parseErrorAbortThreshold {
            log.error("[HOOVER-PARSE-ABORT] transcript=\(transcript.id, privacy: .public) path=\(transcript.filePath, privacy: .public) aborting after \(parseErrorCount, privacy: .public) errors with no valid entries")
            break outerLoop
          }
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

        if entryId != nil {
          parsedEntryCount += 1
        }

        if let maxEntries = limit.maxEntries, parsedEntryCount >= maxEntries {
          limitReached = true
          log.info("[HOOVER-LIMIT] Reached ingest limit (\(maxEntries)) for transcript: \(transcript.id, privacy: .public)")
          break
        }

        // Checkpoint every N lines
        if batch.count >= MonitorConfig.batchLines {
          #if DEBUG
          log.debug("[HOOVER-BATCH-COMMIT] Committing batch of \(batch.count) entries")
          #endif

          // Time the batch insertion (diagnostic for hang investigation)
          let batchStart = Date()
          #if DEBUG
          log.debug("[HOOVER-BATCH-INSERT-START] Starting batch insertion for \(batch.count) entries at line \(lineNo)")
          #endif

          try commitBatch(
            transcriptId: transcript.id,
            entries: batch,
            metadata: metadataBatch,
            errors: errors,
            lastProcessedLine: lineNo,
            lineCount: lineNo,
            previousEntries: &previousEntries
          )

          let duration = Date().timeIntervalSince(batchStart)
          #if DEBUG
          log.debug("[HOOVER-BATCH-INSERT-DONE] Batch insertion completed in \(String(format: "%.0f", duration * 1000))ms")
          #endif
          if duration > 5.0 {
            log.warning("[HOOVER-BATCH-SLOW] Batch insertion took \(String(format: "%.1f", duration))s - may indicate DB lock contention")
          }

          batch.removeAll()
          metadataBatch.clear()
          errors.removeAll()
          progress.didAdvance(linesProcessed: lineNo, totalLines: nil)
        }
      }
      if MonitorConfig.enableHooverLoopTracing {
        log.debug("[HOOVER-INNER-DONE] Inner loop exited after \(innerLoopCount) iterations, bufferSize=\(buffer.count)")
      }

      #if DEBUG
      if MonitorConfig.enableHooverLoopTracing {
        // Log inner loop completion with batch state (diagnostic for hang investigation)
        log.debug("[HOOVER-INNER-COMPLETE] Processed \(innerLoopCount) lines in this iteration, batch size: \(batch.count), total lines: \(lineNo)")
      }
      #endif

      if limitReached {
        break outerLoop
      }

      // READ MORE DATA - only after draining existing buffer
      let readStart = Date()
      guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
        log.info("[HOOVER-READ-EOF] Reached EOF at line \(lineNo, privacy: .public), outerLoops=\(outerLoopCount) for transcript: \(transcript.id, privacy: .public)")
        hitEOF = true
        break
      }
      let readDuration = Date().timeIntervalSince(readStart)
      if readDuration > 1.0 {
        log.warning("[HOOVER-READ-SLOW] File read took \(String(format: "%.1f", readDuration))s - file may still be written")
      }

      if MonitorConfig.enableHooverLoopTracing {
        log.debug("[HOOVER-READ-CHUNK] Read \(chunk.count) bytes, buffer now \(buffer.count + chunk.count) bytes")
      }
      buffer.append(chunk)

      // NEW: Check buffer size for runaway growth (diagnostic for hang investigation)
      if buffer.count > 10_000_000 {  // 10MB limit
        log.error("[HOOVER-BUFFER-OVERFLOW] Buffer size: \(buffer.count) bytes at line \(lineNo) - aborting. Line may exceed maximum size.")
        throw ParserError.invalidFormat("Line \(lineNo) exceeds maximum size (buffer >10MB)")
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
          lastEntryId = entry.id  // Track for checkpoint
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
        if entryId != nil {
          parsedEntryCount += 1
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

    // ALWAYS update checkpoint, regardless of whether there were new entries
    // This ensures checkpoint is persisted even for already-processed transcripts
    let finalLineCount = hitEOF ? lineNo : max(lineNo, transcript.lineCount)
    let firstParseErrorDescription: String? = {
      guard let reason = firstParseErrorReason else { return nil }
      if let line = firstParseErrorLine {
        return "Line \(line): \(reason)"
      }
      return reason
    }()

    let hadParseErrors = parseErrorCount > 0
    let shouldMarkCorrupt = hadParseErrors && parsedEntryCount == 0

    let ingestState = shouldMarkCorrupt ? "complete" : (hitEOF ? "complete" : "partial")
    let status = shouldMarkCorrupt ? "error" : "active"
    let lastErrorMessage = shouldMarkCorrupt ? firstParseErrorDescription : nil

    if shouldMarkCorrupt {
      log.error("[HOOVER-CORRUPT] transcript=\(transcript.id, privacy: .public) path=\(transcript.filePath, privacy: .public) parse_errors=\(parseErrorCount, privacy: .public) reason=\(firstParseErrorDescription ?? "unknown", privacy: .public)")
    }

    try updateCheckpoint(
      transcriptId: transcript.id,
      lastProcessedLine: lineNo,
      lastProcessedEntryId: lastEntryId,
      lineCount: finalLineCount,
      ingestState: ingestState,
      status: status,
      lastError: lastErrorMessage
    )

    log.info("[DB-UPDATE] transcript=\(transcript.id, privacy: .public) entries=\(parsedEntryCount, privacy: .public) state=\(ingestState, privacy: .public)")

    // Verify checkpoint was updated correctly
    if let updatedTranscript = try? db.read({ db in try Transcript.fetchOne(db, key: transcript.id) }) {
      log.debug("[HOOVER-CHECKPOINT-VERIFY] Checkpoint updated: \(transcript.lastProcessedLine, privacy: .public) → \(updatedTranscript.lastProcessedLine, privacy: .public)")
      if updatedTranscript.lastProcessedLine != lineNo {
        log.error("[HOOVER-CHECKPOINT-MISMATCH] ⚠️ Expected checkpoint \(lineNo, privacy: .public), but database has \(updatedTranscript.lastProcessedLine, privacy: .public)")
      }
    }

    let duration = Date().timeIntervalSince(startTime)
    progress.didCompleteTranscript(durationMs: Int(duration * 1000))

    let transcriptSHA256: String?
    if hitEOF {
      transcriptSHA256 = transcriptHasher.finalize()
    } else {
      _ = transcriptHasher.finalize()
      transcriptSHA256 = nil
    }

    let linesPerSec = duration > 0 ? Int(Double(lineNo) / duration) : 0
    let newLines = lineNo - transcript.lastProcessedLine
    log.info("[HOOVER-DONE] Hoovered transcript \(transcript.id, privacy: .public): \(newLines, privacy: .public) new lines (total: \(lineNo, privacy: .public)) in \(Int(duration * 1000), privacy: .public)ms (\(linesPerSec, privacy: .public)/s). ingest_state=\(ingestState, privacy: .public)")

    return HooverOutcome(
      processedLines: lineNo,
      newEntries: parsedEntryCount,
      reachedEOF: hitEOF,
      lastEntryId: lastEntryId,
      contentSha256: transcriptSHA256
    )
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
            if MonitorConfig.enableHooverStorageTracing {
              log.debug("Parent \(parentId) doesn't exist yet, setting parent_id to NULL for entry \(model.id)")
            }
            model.parentId = nil  // Will be backfilled later if needed
          }
        }

        do {
          try model.insert(db, onConflict: .ignore)

          // Only update window tracking if insert actually happened (not ignored due to conflict)
          let inserted = db.changesCount > 0
          if inserted {
            previousEntries.append(entry.id)
            if previousEntries.count > 2 {
              previousEntries.removeFirst()
            }
          } else {
            // Entry silently ignored (likely duplicate ID from re-ingestion) - expected during database rebuilds
            log.debug("Entry silently ignored (duplicate constraint?)")
            log.debug("   Entry ID: \(model.id, privacy: .public)")
            log.debug("   Kind: \(model.kind, privacy: .public)")
            log.debug("   Content preview: \(String(model.content.prefix(80)), privacy: .public)")
          }
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
      // FK-safe usage insert: atomic CTE-based check+insert with request_id normalization
      for usage in metadata.assistantUsages {
        // Normalize request_id: empty string → entry_id fallback
        let normalizedRequestId: String = {
          let trimmed = usage.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
          return trimmed.isEmpty ? usage.entryId : trimmed
        }()

        // Atomic check+insert using CTE and RETURNING for single round-trip
        let stmt = try db.makeStatement(sql: """
          WITH entry_check AS (SELECT 1 FROM transcript_entries WHERE id = ? LIMIT 1)
          INSERT OR IGNORE INTO assistant_usage (
            entry_id, request_id, model, input_tokens, output_tokens,
            cache_creation_tokens, cache_read_tokens, service_tier,
            ephemeral_5m_tokens, ephemeral_1h_tokens
          )
          SELECT ?,?,?,?,?,?,?,?,?,? FROM entry_check
          RETURNING entry_id;
          """)
        try stmt.execute(arguments: [
          usage.entryId,  // for entry_check CTE
          usage.entryId, normalizedRequestId, usage.model,
          usage.inputTokens, usage.outputTokens,
          usage.cacheCreationTokens, usage.cacheReadTokens,
          usage.serviceTier, usage.ephemeral5mTokens, usage.ephemeral1hTokens
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
              usage.entryId, normalizedRequestId, usage.model,
              usage.inputTokens, usage.outputTokens,
              usage.cacheCreationTokens, usage.cacheReadTokens,
              usage.serviceTier, usage.ephemeral5mTokens, usage.ephemeral1hTokens
            ]
          )
          if MonitorConfig.enableHooverStorageTracing {
            log.debug("Staged usage for entry \(usage.entryId) (entry not yet present)")
          }
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

      // Reconcile assistant_usage_pending → assistant_usage using JOIN (O(N+M) vs O(N×M))
      // Normalize empty request_id during move to reduce uniqueness churn
      try db.execute(sql: """
        INSERT OR IGNORE INTO assistant_usage (
          entry_id, request_id, model, input_tokens, output_tokens,
          cache_creation_tokens, cache_read_tokens, service_tier,
          ephemeral_5m_tokens, ephemeral_1h_tokens
        )
        SELECT
          p.entry_id,
          COALESCE(NULLIF(p.request_id, ''), p.entry_id) AS request_id,
          p.model, p.input_tokens, p.output_tokens,
          p.cache_creation_tokens, p.cache_read_tokens, p.service_tier,
          p.ephemeral_5m_tokens, p.ephemeral_1h_tokens
        FROM assistant_usage_pending p
        INNER JOIN transcript_entries e ON e.id = p.entry_id
      """)

      // Clean up reconciled records via indexed lookup (uses entry_id+request_id)
      // Note: SQLite doesn't support table aliases in DELETE, must use full table name
      try db.execute(sql: """
        DELETE FROM assistant_usage_pending
        WHERE EXISTS (
          SELECT 1 FROM assistant_usage au
          WHERE au.entry_id = assistant_usage_pending.entry_id
            AND au.request_id = COALESCE(NULLIF(assistant_usage_pending.request_id, ''), assistant_usage_pending.entry_id)
        )
      """)

      // NOTE: Checkpoint UPDATE removed - now handled unconditionally in hooverTranscript()
      // This ensures checkpoint is persisted even when batch is empty (already-processed transcripts)
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
  case corruptedRecord(CorruptionType, details: String)
}

extension ParserError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidJSON:
      return "Invalid JSON format"
    case .missingRequiredField(let field):
      return "Missing required field: \(field)"
    case .unsupportedProvider(let provider):
      return "Unsupported provider: \(provider)"
    case .invalidFormat(let reason):
      return "Invalid format: \(reason)"
    case .skipEntry:
      return "Entry skipped (metadata/empty content)"
    case .corruptedRecord(let type, let details):
      return "Corrupted record (\(type.rawValue)): \(details)"
    }
  }
}

/// Types of transcript corruption we can detect and potentially recover from
public enum CorruptionType: String {
  case orphanedToolResult = "orphaned_tool_result"
  case stopReasonMismatch = "stop_reason_mismatch"
  case missingParent = "missing_parent"
  case invalidContentBlock = "invalid_content_block"
}
