import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "DatabaseMigration")

/// Handles database location migrations
public enum DatabaseMigration {

  public enum MigrationError: Error, LocalizedError {
    case sourceNotFound
    case targetExists
    case insufficientSpace(required: Int64, available: Int64)
    case copyFailed(underlying: Error)
    case validationFailed

    public var errorDescription: String? {
      switch self {
      case .sourceNotFound:
        return "Source database not found"
      case .targetExists:
        return "A database already exists at the target location"
      case .insufficientSpace(let required, let available):
        return "Insufficient disk space (need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), have \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)))"
      case .copyFailed(let error):
        return "Failed to copy database: \(error.localizedDescription)"
      case .validationFailed:
        return "Database validation failed after migration"
      }
    }
  }

  /// Migrates database from current location to a new location
  /// - Parameters:
  ///   - targetDirectory: The directory where the database should be moved
  ///   - deleteSource: Whether to delete the source database after successful migration (default: false)
  /// - Throws: MigrationError if migration fails
  public static func migrateDatabase(to targetDirectory: URL, deleteSource: Bool = false) async throws {
    log.info("🔄 Starting database migration to: \(targetDirectory.path)")

    // 1. Get current database location BEFORE closing connection
    let sourcePath = try DatabaseManager.shared.databasePath()
    let sourceDir = sourcePath.deletingLastPathComponent()

    // 2. Close existing database connection to release file locks
    DatabaseManager.shared.closeDatabase()

    // Wait a moment for connection to fully close
    try await Task.sleep(for: .milliseconds(100))

    // 3. Verify source exists
    guard FileManager.default.fileExists(atPath: sourcePath.path) else {
      throw MigrationError.sourceNotFound
    }

    // 4. Prepare target location
    let targetPath = targetDirectory.appendingPathComponent("contextify.db")

    // Check if target already exists
    if FileManager.default.fileExists(atPath: targetPath.path) {
      throw MigrationError.targetExists
    }

    // Create target directory
    try FileManager.default.createDirectory(
      at: targetDirectory,
      withIntermediateDirectories: true
    )

    // 5. Check available disk space
    let dbSize = try databaseSize(at: sourcePath)
    let availableSpace = try availableDiskSpace(at: targetDirectory)

    guard availableSpace > dbSize * 2 else { // 2x for safety
      throw MigrationError.insufficientSpace(required: dbSize * 2, available: availableSpace)
    }

    // 6. Copy database files
    log.info("📦 Copying database files (\(ByteCountFormatter.string(fromByteCount: dbSize, countStyle: .file)))...")

    do {
      // Copy main database
      try FileManager.default.copyItem(at: sourcePath, to: targetPath)

      // Copy WAL file if exists
      let sourceWal = sourcePath.appendingPathExtension("wal")
      if FileManager.default.fileExists(atPath: sourceWal.path) {
        let targetWal = targetPath.appendingPathExtension("wal")
        try FileManager.default.copyItem(at: sourceWal, to: targetWal)
      }

      // Copy SHM file if exists
      let sourceShm = sourcePath.appendingPathExtension("shm")
      if FileManager.default.fileExists(atPath: sourceShm.path) {
        let targetShm = targetPath.appendingPathExtension("shm")
        try FileManager.default.copyItem(at: sourceShm, to: targetShm)
      }
    } catch {
      // Clean up partial copy on failure
      try? FileManager.default.removeItem(at: targetPath)
      try? FileManager.default.removeItem(at: targetPath.appendingPathExtension("wal"))
      try? FileManager.default.removeItem(at: targetPath.appendingPathExtension("shm"))
      throw MigrationError.copyFailed(underlying: error)
    }

    // 7. Update preference to use new location
    HUDPreferences.setCustomDatabaseLocation(targetDirectory)

    // 8. Reopen database at new location and validate
    log.info("✅ Verifying migrated database...")

    do {
      let pool = try DatabaseManager.shared.pool
      try await pool.read { db in
        try db.execute(sql: "PRAGMA quick_check")
      }
    } catch {
      // Rollback: clear custom location to go back to source
      HUDPreferences.clearCustomDatabaseLocation()
      throw MigrationError.validationFailed
    }

    // 9. Delete source if requested
    if deleteSource {
      log.info("🗑 Deleting source database...")
      try? FileManager.default.removeItem(at: sourcePath)
      try? FileManager.default.removeItem(at: sourcePath.appendingPathExtension("wal"))
      try? FileManager.default.removeItem(at: sourcePath.appendingPathExtension("shm"))
    }

    log.info("✅ Database migration complete")
  }

  /// Calculates total size of database files
  private static func databaseSize(at path: URL) throws -> Int64 {
    var totalSize: Int64 = 0

    // Main database
    if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path) {
      totalSize += (attrs[.size] as? Int64) ?? 0
    }

    // WAL file
    let walPath = path.appendingPathExtension("wal")
    if let attrs = try? FileManager.default.attributesOfItem(atPath: walPath.path) {
      totalSize += (attrs[.size] as? Int64) ?? 0
    }

    // SHM file
    let shmPath = path.appendingPathExtension("shm")
    if let attrs = try? FileManager.default.attributesOfItem(atPath: shmPath.path) {
      totalSize += (attrs[.size] as? Int64) ?? 0
    }

    return totalSize
  }

  /// Gets available disk space at a path
  private static func availableDiskSpace(at url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values.volumeAvailableCapacityForImportantUsage ?? 0
  }
}
