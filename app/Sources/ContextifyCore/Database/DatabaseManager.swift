import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "DatabaseManager")

/// Manages the SQLite database connection and lifecycle
@MainActor
public final class DatabaseManager {
  public static let shared = DatabaseManager()

  private var _pool: DatabasePool?

  public var pool: DatabasePool {
    get throws {
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

    // Run migrations
    try pool.write { db in
      try DatabaseSchema.migrate(db)
    }

    // Validate database
    try validateDatabase(pool)

    log.info("Database opened and validated successfully")
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

    guard let row = row, row.count > 1 else { return }
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
}
