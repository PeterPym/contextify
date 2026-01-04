import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "DatabaseManager")

// MARK: - CLI Database Path Error

/// Errors for CLI database path validation
enum DatabasePathError: LocalizedError {
  case pathExists(String)
  case parentNotWritable(String)
  case invalidPath(String)

  var errorDescription: String? {
    switch self {
    case .pathExists(let path):
      return """
        Database already exists at --database-path location: \(path)
        Benchmark mode requires a fresh database. Either:
          1. Delete the existing file at that path
          2. Use a different path: --database-path /tmp/bench-\(UUID().uuidString.prefix(8)).db
        """
    case .parentNotWritable(let path):
      return "Parent directory not writable for --database-path: \(path)"
    case .invalidPath(let path):
      return "Invalid --database-path: \(path)"
    }
  }
}

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

  /// Cached CLI database URL after validation (set once at first resolution)
  /// This prevents re-validation failing after the DB file is created
  /// Access protected by poolLock (set in databasePath() which is called under lock)
  private var validatedCLIDatabaseURL: URL?

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
    #if os(macOS)
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
    #endif

    let dbPath = try databasePath()
    let isNewDatabase = !FileManager.default.fileExists(atPath: dbPath.path)

    if isNewDatabase {
      log.info("[DB-INIT] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
      log.info("[DB-INIT] CREATING NEW DATABASE FROM SCRATCH")
      log.info("[DB-INIT] Path: \(dbPath.path, privacy: .public)")
      log.info("[DB-INIT] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    } else {
      log.info("[DB-INIT] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
      log.info("[DB-INIT] OPENING EXISTING DATABASE")
      log.info("[DB-INIT] Path: \(dbPath.path, privacy: .public)")
      // Get file size for context
      if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath.path),
         let size = attrs[.size] as? Int64 {
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        log.info("[DB-INIT] Size: \(sizeStr, privacy: .public)")
      }
      log.info("[DB-INIT] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

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

    // Keep SQLite user_version aligned with current schema for tooling discovery.
    try pool.write { db in
      try db.execute(sql: "PRAGMA user_version = \(DatabaseSchema.version)")
    }

    // Validate database and log summary
    try validateDatabase(pool, isNewDatabase: isNewDatabase)

    // Record access for conflict detection (post-migration safe)
    try pool.write { db in
      // Ensure table exists before recording access (guards against pre-v21 DBs)
      if try !db.tableExists("database_access_metadata") {
        try DatabaseAccessTracker.addAccessMetadataTable(db: db)
      }
      try DatabaseAccessTracker.recordAccess(db: db)
    }

    // Write discovery sidecar (best-effort).
    #if os(macOS)
    let schemaVersion = try pool.read { db in
      try Int.fetchOne(db, sql: "PRAGMA user_version") ?? DatabaseSchema.version
    }
    let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown"
    let buildFlavor = Sandbox.isSandboxed ? "appstore" : "dmg"
    let capabilities = ["fts_search", "summaries", "usage_stats", "project_metadata"]
    StateWriter.writeState(
      databaseURL: dbPath,
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      buildFlavor: buildFlavor,
      capabilities: capabilities
    )
    #endif

    log.info("Database opened and validated successfully")

    return pool
  }

  /// Returns the path to the database file
  public func databasePath() throws -> URL {
    if let overrideDatabaseURL {
      return overrideDatabaseURL
    }

    // CLI override takes precedence (runtime-only)
    // Use cached URL after first validation to avoid failing after DB creation
    if let cachedURL = validatedCLIDatabaseURL {
      return cachedURL
    }
    if let cliPath = LaunchArguments.shared.databasePath {
      do {
        try validateCLIDatabasePath(cliPath)
      } catch let error as DatabasePathError {
        // Fail-fast for CLI database path validation errors
        let msg = error.errorDescription ?? error.localizedDescription
        log.error("[BENCH] Database path validation failed: \(msg)")
        fputs("Error: \(msg)\n", stderr)
        exit(73)  // EX_CANTCREAT
      }
      let url = URL(fileURLWithPath: cliPath)
      validatedCLIDatabaseURL = url
      log.info("[BENCH] Using CLI database path: \(cliPath, privacy: .public)")
      return url
    }

    // Check for custom database location first
    if let customLocation = try customDatabasePath() {
      return customLocation
    }

    // Fall back to default location
    return try defaultDatabasePath()
  }

  /// Validates CLI database path before use
  private func validateCLIDatabasePath(_ cliPath: String) throws {
    // App Store builds: reject path flags (security-scoped access required)
    #if APPSTORE_BUILD
    fputs("Error: --database-path is not supported in App Store builds\n", stderr)
    exit(64)  // EX_USAGE
    #endif

    let url = URL(fileURLWithPath: cliPath)

    // Validate: path must not exist (fresh benchmark DB)
    if FileManager.default.fileExists(atPath: cliPath) {
      throw DatabasePathError.pathExists(cliPath)
    }

    // Validate: parent directory must exist and be writable
    let parentDir = url.deletingLastPathComponent()
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: parentDir.path, isDirectory: &isDir),
          isDir.boolValue else {
      throw DatabasePathError.invalidPath(cliPath)
    }
    guard FileManager.default.isWritableFile(atPath: parentDir.path) else {
      throw DatabasePathError.parentNotWritable(cliPath)
    }
  }

  /// Returns custom database path if configured
  private func customDatabasePath() throws -> URL? {
    #if os(macOS)
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
    #endif

    return nil
  }

  /// Returns default database path
  /// DMG builds: ~/Library/Application Support/Contextify/ (no TCC prompt needed)
  /// App Store builds: Should never reach here without onboarding (guarded in openDatabase)
  /// Linux: Uses ~/.local/share/Contextify/
  private func defaultDatabasePath() throws -> URL {
    let fm = FileManager.default

    #if os(macOS)
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
      if HUDPreferences.getCustomDatabaseLocation() == nil {
        HUDPreferences.setLegacyDatabaseLocationIfMissing(appSupportDir)
      }
      log.info("[DB-PATH] Using Application Support (DMG build)")
      return appSupportDB
    }

    // Sandboxed builds should not reach here - onboarding wizard handles location selection
    // But if they do (edge case), fall back to Application Support within container
    log.warning("[DB-PATH] Sandboxed build reached defaultDatabasePath - using container Application Support")
    try fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    if HUDPreferences.getCustomDatabaseLocation() == nil {
      HUDPreferences.setLegacyDatabaseLocationIfMissing(appSupportDir)
    }
    return appSupportDB

    #else
    // Linux: Use ~/.local/share/Contextify/
    let homeDir = fm.homeDirectoryForCurrentUser
    let dataDir = homeDir.appendingPathComponent(".local/share/Contextify", isDirectory: true)
    let dbPath = dataDir.appendingPathComponent("contextify.db")

    try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
    log.info("[DB-PATH] Using \(dataDir.path) (Linux)")
    return dbPath
    #endif
  }

  /// Validates database integrity and logs summary
  private func validateDatabase(_ pool: DatabasePool, isNewDatabase: Bool) throws {
    try pool.read { db in
      try db.execute(sql: "PRAGMA quick_check")
    }

    // Get record counts (schema version comes from DatabaseSchema.version)
    let (projectCount, transcriptCount, entryCount, providerCounts) = try pool.read {
      db -> (Int, Int, Int, [String: Int]) in
      let projects = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects") ?? 0
      let transcripts = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts") ?? 0
      let entries = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries") ?? 0

      // Get per-provider transcript counts
      var providers: [String: Int] = [:]
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT provider, COUNT(*) as count FROM transcripts GROUP BY provider"
      )
      for row in rows {
        if let provider: String = row["provider"], let count: Int = row["count"] {
          providers[provider] = count
        }
      }
      return (projects, transcripts, entries, providers)
    }
    let schemaVersion = DatabaseSchema.version

    // Log summary with clear distinction between new and existing
    log.info("[DB-INIT] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    if isNewDatabase {
      log.info("[DB-INIT] NEW DATABASE READY (schema v\(schemaVersion))")
    } else {
      log.info("[DB-INIT] EXISTING DATABASE LOADED (schema v\(schemaVersion))")
      log.info("[DB-INIT] Records: \(projectCount) projects, \(transcriptCount) transcripts, \(entryCount) entries")
      if !providerCounts.isEmpty {
        let providerStr = providerCounts.sorted(by: { $0.key < $1.key })
          .map { "\($0.key): \($0.value)" }
          .joined(separator: ", ")
        log.info("[DB-INIT] Transcripts by provider: \(providerStr, privacy: .public)")
      }
    }
    log.info("[DB-INIT] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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

  /// Threshold for WAL checkpoint (5 batches worth of entries)
  private static let walCheckpointThreshold = 5000

  /// Cumulative entries written since last checkpoint (protected by poolLock)
  private var entriesSinceLastCheckpoint = 0

  /// Flag to prevent concurrent checkpoints (protected by poolLock)
  private var checkpointInProgress = false

  /// Checkpoint WAL after bulk ingest operations
  /// Tracks cumulative entries across transcripts and triggers checkpoint when threshold reached.
  /// Uses PASSIVE mode which doesn't block readers.
  /// Thread-safe: uses poolLock to protect counter and pool access.
  /// - Important: Must be called outside any active DatabasePool write closure.
  public func checkpointAfterBulkWrites(entriesWritten: Int) {
    guard entriesWritten > 0 else { return }
    assert(!Thread.isMainThread, "checkpointAfterBulkWrites must not be called on main thread")

    let pool: DatabasePool
    var claimedCount = 0

    // Acquire lock to safely update counter and check threshold
    poolLock.lock()
    entriesSinceLastCheckpoint += entriesWritten

    // Skip if checkpoint already in progress or below threshold
    guard !checkpointInProgress,
          entriesSinceLastCheckpoint >= Self.walCheckpointThreshold,
          let p = _pool
    else {
      poolLock.unlock()
      return
    }

    // Claim checkpoint and reset counter before running
    // New writes during checkpoint will accumulate from 0
    checkpointInProgress = true
    pool = p
    claimedCount = entriesSinceLastCheckpoint
    entriesSinceLastCheckpoint = 0
    poolLock.unlock()

    // Clear in-progress flag when done (success or failure)
    defer {
      poolLock.lock()
      checkpointInProgress = false
      poolLock.unlock()
    }

    // Perform checkpoint outside lock (blocking operation)
    do {
      // Use writeWithoutTransaction to avoid implicit transaction overhead
      try pool.writeWithoutTransaction { db in
        // PASSIVE checkpoint - returns (busy, log, checkpointed) counts
        if let result = try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(PASSIVE)") {
          let busy = result[0] as? Int ?? 0
          let logPages = result[1] as? Int ?? 0
          let checkpointed = result[2] as? Int ?? 0
          if busy > 0 || checkpointed < logPages {
            log.debug("[WAL-CHECKPOINT] Partial after \(claimedCount) entries: \(checkpointed)/\(logPages) pages, \(busy) busy")
          } else {
            log.debug("[WAL-CHECKPOINT] Complete after \(claimedCount) entries: \(checkpointed) pages")
          }
        }
      }
    } catch {
      // Re-add claimed count on failure to preserve pressure for retry
      poolLock.lock()
      entriesSinceLastCheckpoint += claimedCount
      poolLock.unlock()
      log.debug("[WAL-CHECKPOINT] Skipped: \(error.localizedDescription)")
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

    #if os(macOS)
    // Stop security-scoped access (sandbox only)
    if Sandbox.isSandboxed, let url = securityScopedDirURL {
      url.stopAccessingSecurityScopedResource()
      securityScopedDirURL = nil
      log.debug("Stopped security-scoped access: \(url.path)")
    }
    #endif
  }

}
