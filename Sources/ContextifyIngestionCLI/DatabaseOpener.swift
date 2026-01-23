// SPDX-License-Identifier: MIT
// DatabaseOpener.swift - CLI-specific database opener with FTS5 preflight

#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif
import GRDB
import Foundation

/// CLI-specific database opener that bypasses HUDPreferences and sandbox logic.
/// Unlike DatabaseManager, this takes an explicit path and has no macOS-specific dependencies.
public struct DatabaseOpener {

  /// Errors specific to CLI database operations
  public enum CLIError: Error, LocalizedError {
    case missingFTS5(message: String)
    case databaseNotFound(path: String)
    case migrationFailed(underlying: Error)

    public var errorDescription: String? {
      switch self {
      case .missingFTS5(let message):
        return message
      case .databaseNotFound(let path):
        return "Database not found at: \(path)"
      case .migrationFailed(let underlying):
        return "Migration failed: \(underlying.localizedDescription)"
      }
    }
  }

  /// Opens a database at the given path with full initialization.
  /// Runs FTS5 preflight check and applies all migrations.
  ///
  /// - Parameter path: Absolute path to the SQLite database file
  /// - Returns: Configured DatabasePool ready for use
  /// - Throws: CLIError if FTS5 is unavailable or migrations fail
  public static func openDatabase(at path: String) throws -> DatabasePool {
    let url = URL(fileURLWithPath: path)

    // Create parent directory if needed
    let parentDir = url.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: parentDir.path) {
      try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
    }

    // Configure database
    var config = Configuration()
    config.foreignKeysEnabled = true
    config.busyMode = .timeout(2.0)
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode=WAL")
      try db.execute(sql: "PRAGMA synchronous=NORMAL")
      try db.execute(sql: "PRAGMA wal_autocheckpoint=1000")
      try db.execute(sql: "PRAGMA temp_store=MEMORY")
    }

    let pool = try DatabasePool(path: path, configuration: config)

    // FTS5 preflight check - fail fast before any other work
    try checkFTS5Availability(pool: pool)

    // Run migrations
    do {
      let migrator = DatabaseSchema.createMigrator()
      try migrator.migrate(pool)
    } catch {
      throw CLIError.migrationFailed(underlying: error)
    }

    return pool
  }

  /// Checks if FTS5 is available in the linked SQLite library.
  /// Fails fast with a helpful error message if not available.
  ///
  /// Uses `pool.write` rather than `pool.read` because:
  /// 1. We're executing DDL (CREATE/DROP TABLE) which requires write access
  /// 2. Avoids any "read-only" or "query-only" mode surprises from GRDB configuration
  /// 3. Makes the intent unambiguous: this is a capability probe that modifies the database
  private static func checkFTS5Availability(pool: DatabasePool) throws {
    try pool.write { db in
      // Try to create an in-memory FTS5 table as capability probe
      // This is more reliable than checking compile options
      do {
        try db.execute(sql: """
          CREATE VIRTUAL TABLE IF NOT EXISTS _fts5_capability_check
          USING fts5(content)
        """)
        // Clean up the test table
        try db.execute(sql: "DROP TABLE IF EXISTS _fts5_capability_check")
      } catch {
        throw CLIError.missingFTS5(message: """

          ERROR: FTS5 is required but not available in your SQLite installation.

          The SQLite library linked by GRDB does not have FTS5 enabled.
          This is required for Contextify's full-text search functionality.

          Solutions by platform:

          Linux (Ubuntu/Debian):
            sudo apt-get install libsqlite3-dev
            # Ensure the package includes FTS5 (most modern versions do)

          Linux (Fedora/RHEL):
            sudo dnf install sqlite-devel

          macOS:
            System SQLite includes FTS5 by default.
            If using Homebrew SQLite, ensure it's properly linked.

          Docker:
            Use official Swift images (swift:6.0) which include FTS5.

          Original error: \(error.localizedDescription)
          """)
      }
    }
  }

  /// Validates an existing database without running migrations.
  /// Useful for the `verify` command.
  public static func validateDatabase(at path: String) throws -> ValidationResult {
    guard FileManager.default.fileExists(atPath: path) else {
      throw CLIError.databaseNotFound(path: path)
    }

    var config = Configuration()
    config.readonly = true

    let pool = try DatabasePool(path: path, configuration: config)

    return try pool.read { db in
      var result = ValidationResult()

      // Check journal mode
      let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode")
      result.journalMode = journalMode ?? "unknown"
      result.isWALMode = journalMode?.lowercased() == "wal"

      // Check FTS5 availability by checking if an FTS5 table exists
      // (we can't create tables in readonly mode)
      do {
        // Check if transcript_entries_fts exists (the app's FTS table)
        let ftsTableExists = try String.fetchOne(db, sql: """
          SELECT name FROM sqlite_master WHERE type='table' AND name='transcript_entries_fts'
        """)
        if ftsTableExists != nil {
          result.hasFTS5 = true
        } else {
          // Try checking if FTS5 module is available via compile options
          let compileOptions = try String.fetchAll(db, sql: "PRAGMA compile_options")
          result.hasFTS5 = compileOptions.contains("ENABLE_FTS5")
          if !result.hasFTS5 {
            result.fts5Error = "FTS5 module not available (no FTS tables and ENABLE_FTS5 not in compile options)"
          }
        }
      } catch {
        result.hasFTS5 = false
        result.fts5Error = error.localizedDescription
      }

      // Quick integrity check
      let integrityResult = try String.fetchOne(db, sql: "PRAGMA quick_check")
      result.integrityOK = integrityResult == "ok"
      result.integrityResult = integrityResult ?? "unknown"

      // Schema version
      result.schemaVersion = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0

      // Table counts
      result.projectCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects") ?? 0
      result.transcriptCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts") ?? 0
      result.entryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries") ?? 0

      // SQLite version
      result.sqliteVersion = try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? "unknown"

      return result
    }
  }

  /// Result of database validation
  public struct ValidationResult {
    public var journalMode: String = "unknown"
    public var isWALMode: Bool = false
    public var hasFTS5: Bool = false
    public var fts5Error: String?
    public var integrityOK: Bool = false
    public var integrityResult: String = "unknown"
    public var schemaVersion: Int = 0
    public var projectCount: Int = 0
    public var transcriptCount: Int = 0
    public var entryCount: Int = 0
    public var sqliteVersion: String = "unknown"

    public var isValid: Bool {
      isWALMode && hasFTS5 && integrityOK
    }
  }
}
