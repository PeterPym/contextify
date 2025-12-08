import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "DatabaseManager")

// MARK: - Onboarding Error

/// Guard error for App Store builds attempting DB access before onboarding.
///
/// This should not be reachable if UI gating is correct - the wizard blocks
/// all code paths that would access the database. Exists as defense-in-depth.
public struct OnboardingRequiredError: Error, LocalizedError {
  public var errorDescription: String? {
    "Database cannot be accessed until onboarding is complete. Please select a database location."
  }
}

/// Manages the SQLite database connection and lifecycle
/// Thread-safe singleton - GRDB pool handles concurrency internally
public final class DatabaseManager: @unchecked Sendable {
  public static let shared = DatabaseManager()

  private let poolLock = NSLock()
  private var _pool: DatabasePool?
  private var securityScopedDirURL: URL?
  private var isMigrationInProgress = false
  private let overrideDatabaseURL: URL?

  public var pool: DatabasePool {
    get throws {
      poolLock.lock()
      defer { poolLock.unlock() }

      // Block pool access during migration to prevent race conditions
      if isMigrationInProgress {
        throw NSError(
          domain: "dev.contextify.DatabaseManager",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Database is being migrated"]
        )
      }

      if let pool = _pool {
        return pool
      }
      let pool = try openDatabase()
      _pool = pool
      return pool
    }
  }

  private init(overrideDatabaseURL: URL? = nil) {
    self.overrideDatabaseURL = overrideDatabaseURL
  }

  /// Creates an isolated manager for tests with a fixed database location.
  /// - Parameter databaseURL: Full path to the SQLite file (directory is created if needed).
  /// - Returns: Dedicated DatabaseManager instance.
  public static func makeTestingInstance(databaseURL: URL) -> DatabaseManager {
    // Ensure parent exists eagerly so migrations can run
    let directory = databaseURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return DatabaseManager(overrideDatabaseURL: databaseURL)
  }

  /// Opens or creates the database at the default location
  private func openDatabase() throws -> DatabasePool {
    // Guard: In sandboxed builds, require onboarding completion before DB access
    // This prevents accidental creation of database in container location
    // NOTE: Must use runtime Sandbox.isSandboxed check instead of #if APPSTORE_BUILD
    // because compile-time flags don't propagate to Swift package code.
    if Sandbox.isSandboxed && !HUDPreferences.hasCompletedAppStoreOnboarding() {
      log.warning("[DB-GUARD] Sandboxed build attempted DB access before onboarding")
      throw OnboardingRequiredError()
    }

    // Start security-scoped access if using bookmark (sandboxed builds only)
    if let bookmarkURL = HUDPreferences.resolveDatabaseBookmark() {
      if Sandbox.isSandboxed {
        // Only start if not already accessing this URL
        if securityScopedDirURL != bookmarkURL {
          // Stop previous scope if different URL
          if let previousURL = securityScopedDirURL {
            previousURL.stopAccessingSecurityScopedResource()
          }

          guard bookmarkURL.startAccessingSecurityScopedResource() else {
            throw NSError(
              domain: "dev.contextify.DatabaseManager",
              code: 1,
              userInfo: [NSLocalizedDescriptionKey: "Failed to access security-scoped directory"]
            )
          }
          securityScopedDirURL = bookmarkURL
          log.debug("Started security-scoped access: \(bookmarkURL.path)")
        }
      } else {
        // Non-sandbox build: no security scope needed
        securityScopedDirURL = nil
        log.debug("Using custom database location (non-sandbox): \(bookmarkURL.path)")
      }
    }

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

    // Record access for conflict detection (post-migration safe)
    try pool.write { db in
      // Ensure table exists before recording access (guards against pre-v21 DBs)
      if try !db.tableExists("database_access_metadata") {
        try DatabaseAccessTracker.addAccessMetadataTable(db: db)
      }
      try DatabaseAccessTracker.recordAccess(db: db)
    }

    log.info("Database opened and validated successfully")

    return pool
  }

  /// Returns the path to the database file
  public func databasePath() throws -> URL {
    if let overrideDatabaseURL {
      return overrideDatabaseURL
    }

    // Check for custom database location first
    if let customLocation = try customDatabasePath() {
      return customLocation
    }

    // Fall back to default location
    return try defaultDatabasePath()
  }

  /// Returns custom database path if configured
  private func customDatabasePath() throws -> URL? {
    // Try to resolve bookmark first (sandboxed builds)
    if let bookmarkURL = HUDPreferences.resolveDatabaseBookmark() {
      let dbPath = bookmarkURL.appendingPathComponent("contextify.db")
      log.debug("Using custom database location (bookmark): \(dbPath.path)")
      return dbPath
    }

    // Try direct path (non-sandboxed builds)
    if let customPath = HUDPreferences.getCustomDatabaseLocation() {
      let baseURL = URL(fileURLWithPath: customPath)

      // Ensure directory exists
      try FileManager.default.createDirectory(
        at: baseURL,
        withIntermediateDirectories: true
      )

      let dbPath = baseURL.appendingPathComponent("contextify.db")
      log.debug("Using custom database location: \(dbPath.path)")
      return dbPath
    }

    return nil
  }

  /// Returns default database path
  /// DMG builds: ~/Library/Application Support/Contextify/ (no TCC prompt needed)
  /// App Store builds: Should never reach here without onboarding (guarded in openDatabase)
  private func defaultDatabasePath() throws -> URL {
    let fm = FileManager.default

    // Application Support location (no TCC prompt required)
    let appSupport = try fm.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let appSupportDir = appSupport.appendingPathComponent("Contextify", isDirectory: true)
    let appSupportDB = appSupportDir.appendingPathComponent("contextify.db")

    // DMG builds: Use Application Support (no permission prompt)
    if !Sandbox.isSandboxed {
      // Check for legacy transcripts.db and use it if present
      let legacyOldDB = appSupportDir.appendingPathComponent("transcripts.db")
      if fm.fileExists(atPath: legacyOldDB.path) && !fm.fileExists(atPath: appSupportDB.path) {
        // Rename legacy file to new name
        try fm.moveItem(at: legacyOldDB, to: appSupportDB)
        log.info("[DB-PATH] Renamed legacy transcripts.db to contextify.db")
      }

      try fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
      log.info("[DB-PATH] Using Application Support (DMG build)")
      return appSupportDB
    }

    // Sandboxed builds should not reach here - onboarding wizard handles location selection
    // But if they do (edge case), fall back to Application Support within container
    log.warning("[DB-PATH] Sandboxed build reached defaultDatabasePath - using container Application Support")
    try fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    return appSupportDB
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

  /// Checks for multi-machine access conflicts
  public func checkForAccessConflicts() throws -> DatabaseAccessTracker.ConflictType? {
    let pool = try self.pool
    return try pool.read { db in
      try DatabaseAccessTracker.checkForConflicts(db: db)
    }
  }

  /// Checks WAL size and triggers checkpoint if needed
  public func checkWALSize() throws {
    guard let pool = _pool else { return }

    let pageSize = try pool.read { db in
      try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 4096
    }

    // PRAGMA wal_checkpoint(PASSIVE) needs write access to update WAL header
    // Use pool.write and silently ignore lock errors (checkpoint is opportunistic)
    let row: Row?
    do {
      row = try pool.write { db in
        try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(PASSIVE)")
      }
    } catch let error as DatabaseError where error.resultCode == .SQLITE_BUSY || error.resultCode == .SQLITE_LOCKED {
      log.debug("WAL checkpoint skipped (database busy)")
      return
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
  /// Note: VACUUM cannot run while other transactions are active
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
      do {
        try pool.write { db in
          try db.execute(sql: "VACUUM")
        }
        log.info("VACUUM completed successfully")
      } catch {
        // VACUUM fails if there are active transactions - this is normal during discovery
        // Skip silently and try again later
        log.debug("VACUUM skipped: \(error.localizedDescription) (will retry later)")
      }
    }
  }

  /// Sets migration in progress flag to block pool access during migration
  public func setMigrationInProgress(_ inProgress: Bool) {
    poolLock.lock()
    defer { poolLock.unlock() }
    isMigrationInProgress = inProgress
  }

  /// Closes the current database connection (used for migrations)
  public func closeDatabase() {
    poolLock.lock()
    defer { poolLock.unlock() }

    if let pool = _pool {
      // Run a checkpoint to flush WAL to main database
      try? pool.writeWithoutTransaction { db in
        try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
      }
      log.info("Database connection closed for migration")
    }

    _pool = nil  // Release the pool, connection will be closed

    // Stop security-scoped access (sandbox only)
    if Sandbox.isSandboxed, let url = securityScopedDirURL {
      url.stopAccessingSecurityScopedResource()
      securityScopedDirURL = nil
      log.debug("Stopped security-scoped access: \(url.path)")
    }
  }

}
