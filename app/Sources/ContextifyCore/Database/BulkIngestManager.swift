import Foundation
import GRDB

// MARK: - BulkIngestManager

/// Dedicated bulk ingest writer that bypasses GRDB observation overhead.
/// Uses a separate DatabaseQueue with prepared statements for maximum throughput.
///
/// ## Performance Characteristics
/// - Prepared statement reuse eliminates query compilation overhead
/// - `setUncheckedArguments` avoids per-argument validation
/// - Manual transactions reduce commit overhead
/// - No StatementAuthorizer/DatabaseRegion tracking (separate connection)
///
/// ## Thread Safety
/// - Must only be used from HooverEngine (serialized by design)
/// - Main pool can read concurrently (WAL mode)
///
/// ## Architecture
/// ```
///                                 ┌─────────────────────────────┐
///                                 │     Main DatabasePool       │
///                                 │  (reads, UI observations)   │
///                                 └──────────────┬──────────────┘
///                                                │
///                                                ▼
/// ┌──────────────────────┐       ┌─────────────────────────────┐
/// │   HooverEngine       │──────▶│   BulkIngestManager         │
/// │   (orchestration)    │       │   - Dedicated writer conn   │
/// └──────────────────────┘       │   - Prepared statements     │
///                                │   - Manual transactions     │
///                                │   - No observation overhead │
///                                └─────────────────────────────┘
/// ```
public final class BulkIngestManager: @unchecked Sendable {
  private let dbPath: String
  private var queue: DatabaseQueue?
  private var entryInsertStmt: Statement?
  private var toolInvocationStmt: Statement?

  private static let log = CrossPlatformLogger(
    subsystem: "dev.contextify",
    category: "BulkIngestManager"
  )

  public init(dbPath: String) {
    self.dbPath = dbPath
  }

  /// Opens dedicated connection with minimal overhead.
  /// Call once during orchestrator initialization.
  public func open() throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    config.busyMode = .timeout(5.0)

    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode=WAL")
      try db.execute(sql: "PRAGMA synchronous=NORMAL")
      // Disable auto-checkpoint during bulk ingest - we checkpoint manually
      try db.execute(sql: "PRAGMA wal_autocheckpoint=0")
      try db.execute(sql: "PRAGMA temp_store=MEMORY")
      try db.execute(sql: "PRAGMA cache_size=-102400")  // 100MB (negative = KiB)
      try db.execute(sql: "PRAGMA mmap_size=1073741824")  // 1GB
    }

    queue = try DatabaseQueue(path: dbPath, configuration: config)

    // Pre-compile prepared statements for the hottest tables
    try queue?.write { db in
      // TranscriptEntry: 25 columns (embedding columns set to NULL during ingest)
      self.entryInsertStmt = try db.makeStatement(sql: """
        INSERT OR IGNORE INTO transcript_entries (
          id, transcript_id, project_id, session_id, provider,
          kind, timestamp, content, content_sha256, display_in_timeline,
          parent_id, git_branch, git_commit, cwd,
          prev1_id, prev2_id, window_sha256,
          embedding, embedding_version, embedding_generated_at,
          created_ts, created_at, updated_at, is_queued, is_sidechain
        ) VALUES (?,?,?,?,?, ?,?,?,?,?, ?,?,?,?, ?,?,?, ?,?,?, ?,?,?,?,?)
      """)

      // ToolInvocation: 17 columns
      self.toolInvocationStmt = try db.makeStatement(sql: """
        INSERT OR IGNORE INTO tool_invocations (
          id, entry_id, transcript_id, parent_invocation_id,
          tool_name, tool_key, tool_use_id, tool_result_entry_id,
          sidechain_transcript_id, sidechain_agent_id,
          started_at, completed_at, status, is_contextify,
          metadata_json, created_at, updated_at
        ) VALUES (?,?,?,?, ?,?,?,?, ?,?, ?,?,?,?, ?,?,?)
      """)
    }

    Self.log.info("[PERF] BulkIngestManager opened with prepared statements")
  }

  /// Commits a batch of entries and tool invocations using prepared statements.
  /// Returns the number of entries actually inserted (excludes conflicts).
  ///
  /// - Parameters:
  ///   - entries: TranscriptEntry models to insert
  ///   - toolInvocations: ToolInvocation models with their parent entry IDs
  /// - Returns: Count of entries successfully inserted
  public func commitBatch(
    entries: [TranscriptEntry],
    toolInvocations: [ToolInvocation]
  ) throws -> Int {
    guard let queue = queue,
          let entryStmt = entryInsertStmt,
          let toolStmt = toolInvocationStmt
    else {
      throw BulkIngestError.notOpen
    }

    var insertedCount = 0

    try queue.writeWithoutTransaction { db in
      try db.execute(sql: "BEGIN IMMEDIATE")

      // Insert entries with prepared statement
      for entry in entries {
        // Build StatementArguments for type-safe binding
        let entryArgs = StatementArguments([
          entry.id,
          entry.transcriptId,
          entry.projectId,
          entry.sessionId,
          entry.provider,
          entry.kind,
          entry.timestamp,
          entry.content,
          entry.contentSha256,
          entry.displayInTimeline,
          entry.parentId,
          entry.gitBranch,
          entry.gitCommit,
          entry.cwd,
          entry.prev1Id,
          entry.prev2Id,
          entry.windowSha256,
          entry.embedding,
          entry.embeddingVersion,
          entry.embeddingGeneratedAt,
          entry.createdTs,
          entry.createdAt,
          entry.updatedAt,
          entry.isQueued,
          entry.isSidechain
        ] as [(any DatabaseValueConvertible)?])
        // Use setUncheckedArguments for maximum performance (no validation)
        entryStmt.setUncheckedArguments(entryArgs)
        try entryStmt.execute()

        if db.changesCount > 0 {
          insertedCount += 1
        }
      }

      // Insert tool invocations with prepared statement
      for tool in toolInvocations {
        let toolArgs = StatementArguments([
          tool.id,
          tool.entryId,
          tool.transcriptId,
          tool.parentInvocationId,
          tool.toolName,
          tool.toolKey,
          tool.toolUseId,
          tool.toolResultEntryId,
          tool.sidechainTranscriptId,
          tool.sidechainAgentId,
          tool.startedAt,
          tool.completedAt,
          tool.status,
          tool.isContextify,
          tool.metadataJson,
          tool.createdAt,
          tool.updatedAt
        ] as [(any DatabaseValueConvertible)?])
        toolStmt.setUncheckedArguments(toolArgs)
        try toolStmt.execute()
      }

      try db.execute(sql: "COMMIT")
    }

    return insertedCount
  }

  /// Performs WAL checkpoint to consolidate WAL file.
  /// Call periodically (e.g., after each transcript) to prevent WAL growth.
  public func checkpoint() throws {
    try queue?.write { db in
      // PASSIVE checkpoint doesn't block readers
      try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
    }
  }

  /// Closes connection and releases prepared statements.
  /// Safe to call multiple times.
  public func close() {
    entryInsertStmt = nil
    toolInvocationStmt = nil
    queue = nil
    Self.log.info("BulkIngestManager closed")
  }

  /// Whether the manager is currently open with active connection.
  public var isOpen: Bool {
    queue != nil
  }
}

// MARK: - Errors

public enum BulkIngestError: Error, LocalizedError {
  case notOpen

  public var errorDescription: String? {
    switch self {
    case .notOpen:
      return "BulkIngestManager is not open. Call open() before committing batches."
    }
  }
}
