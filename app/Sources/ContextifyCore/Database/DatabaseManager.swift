import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "DatabaseManager")

/// Manages the SQLite database connection and lifecycle
/// Thread-safe singleton - GRDB pool handles concurrency internally
public final class DatabaseManager: @unchecked Sendable {
  public static let shared = DatabaseManager()

  private let poolLock = NSLock()
  private var _pool: DatabasePool?

  public var pool: DatabasePool {
    get throws {
      poolLock.lock()
      defer { poolLock.unlock() }

      if let pool = _pool {
        return pool
      }
      let pool = try openDatabase()
      _pool = pool
      return pool
    }
  }

  private init() {}

  /// Opens or creates the database at the default location
  private func openDatabase() throws -> DatabasePool {
    let dbPath = try databasePath()
    log.info("Opening database at: \(dbPath.path)")

    var config = Configuration()
    config.foreignKeysEnabled = true
    config.busyMode = .timeout(5.0)
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode=WAL")
      try db.execute(sql: "PRAGMA synchronous=NORMAL")
      try db.execute(sql: "PRAGMA wal_autocheckpoint=1000")
      try db.execute(sql: "PRAGMA temp_store=MEMORY")
    }

    let pool = try DatabasePool(path: dbPath.path, configuration: config)

    // Run migrations using DatabaseMigrator
    let migrator = DatabaseSchema.createMigrator()
    try migrator.migrate(pool)

    // Validate database
    try validateDatabase(pool)

    log.info("Database opened and validated successfully")

    // Start background backfill for transcript identity fields
    runTranscriptBackfillIfNeeded()

    return pool
  }

  /// Returns the path to the database file
  public func databasePath() throws -> URL {
    let appSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let contextifyDir = appSupport.appendingPathComponent("Contextify", isDirectory: true)
    try FileManager.default.createDirectory(at: contextifyDir, withIntermediateDirectories: true)

    return contextifyDir.appendingPathComponent("transcripts.db")
  }

  /// Validates database integrity
  private func validateDatabase(_ pool: DatabasePool) throws {
    try pool.read { db in
      try db.execute(sql: "PRAGMA quick_check")
    }

    let projectCount = try pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects") ?? 0
    }

    log.info("Database OK: \(projectCount) projects")
  }

  /// Checks WAL size and triggers checkpoint if needed
  public func checkWALSize() throws {
    guard let pool = _pool else { return }

    let pageSize = try pool.read { db in
      try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 4096
    }

    let row = try pool.read { db in
      try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(PASSIVE)")
    }

    guard let row = row, row.count >= 2 else {
      log.warning("WAL checkpoint returned unexpected result")
      return
    }
    let logPages = row[1] as? Int ?? 0
    let walMB = (logPages * pageSize) / 1_048_576

    if walMB >= 50 {
      log.warning("WAL size: ~\(walMB)MB")

      if walMB >= 100 {
        try pool.write { db in
          try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
        log.info("WAL checkpoint triggered: \(walMB)MB → truncated")
      }
    }
  }

  /// Runs ANALYZE for query optimization
  public func analyze() throws {
    guard let pool = _pool else { return }
    try pool.write { db in
      try db.execute(sql: "ANALYZE")
    }
    log.info("Database ANALYZE completed")
  }

  /// Runs VACUUM if bloat exceeds threshold
  public func vacuumIfNeeded() throws {
    guard let pool = _pool else { return }

    let dbPath = try databasePath()
    let dbSize = try FileManager.default.attributesOfItem(atPath: dbPath.path)[.size] as? Int64 ?? 0

    let freePages = try pool.read { db in
      try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0
    }

    let pageSize = try pool.read { db in
      try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 4096
    }

    let bloat = Double(freePages * pageSize) / Double(dbSize)

    if bloat > 0.25 {
      log.info("VACUUM: \(Int(bloat * 100))% bloat")
      try pool.write { db in
        try db.execute(sql: "VACUUM")
      }
    }
  }

  // MARK: - Backfill

  /// Backfill transcript identity fields (runs asynchronously after DB opens)
  /// - Parameter batchSize: Number of rows to process per batch (default 500)
  public func runTranscriptBackfillIfNeeded(batchSize: Int = 500) {
    Task.detached(priority: .utility) { [weak self] in
      guard let self = self else { return }

      do {
        let pool = try self.pool

        // Process batches until no rows remain
        var totalProcessed = 0
        while true {
          let batchCount = try await pool.write { db -> Int in
            // Fetch rows missing identity fields
            let rows = try Row.fetchAll(db, sql: """
              SELECT id, file_path FROM transcripts
              WHERE normalized_path IS NULL OR path_hash IS NULL
                 OR content_length IS NULL OR mtime_ms IS NULL OR content_sha256 IS NULL
              LIMIT ?
            """, arguments: [batchSize])

            if rows.isEmpty { return 0 }

            for row in rows {
              let id: String = row["id"]
              let path: String = row["file_path"]

              // Normalize path
              let (normalized, hash) = PathNormalizer.normalizeAndHash(path)

              // Get file facts (streaming hash)
              let (len, mtimeMs, sha): (Int64, Int64, String)
              if FileManager.default.fileExists(atPath: path) {
                (len, mtimeMs, sha) = try FileFacts.forPath(path)
              } else {
                // File no longer exists - use placeholder values
                (len, mtimeMs, sha) = (0, 0, "missing")
              }

              // Update row
              try db.execute(sql: """
                UPDATE transcripts
                SET normalized_path = ?, path_hash = ?, content_length = ?, mtime_ms = ?, content_sha256 = ?
                WHERE id = ?
              """, arguments: [normalized, hash, len, mtimeMs, sha, id])
            }

            return rows.count
          }

          if batchCount == 0 { break }

          totalProcessed += batchCount
          log.info("Backfill progress: \(totalProcessed) transcripts")

          // Yield to other tasks
          try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        if totalProcessed > 0 {
          log.info("Backfill complete: \(totalProcessed) transcripts")

          // Apply identity indexes now that backfill is complete
          let migrator = DatabaseSchema.createMigrator()
          try migrator.migrate(pool, upTo: "v3_identity_indexes")

          log.info("Identity indexes created")
        }
      } catch {
        log.error("Backfill failed: \(error.localizedDescription)")
      }
    }
  }
}
