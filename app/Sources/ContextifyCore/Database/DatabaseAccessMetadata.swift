import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "DatabaseMetadata")

/// Tracks database access metadata for conflict detection
public struct DatabaseAccessMetadata: Codable, Sendable {
  public let machineId: String
  public let machineName: String
  public let lastAccess: Date
  public let appVersion: String

  enum CodingKeys: String, CodingKey {
    case machineId = "machine_id"
    case machineName = "machine_name"
    case lastAccess = "last_access"
    case appVersion = "app_version"
  }
}

extension DatabaseAccessMetadata: FetchableRecord, PersistableRecord {
  public static let databaseTableName = "database_access_metadata"
}

/// Manages database access tracking and conflict detection
public enum DatabaseAccessTracker {

  /// Potential conflict types
  public enum ConflictType {
    case multiMachine(machines: [String])
    case recentConflict(otherMachine: String, timeSince: TimeInterval)
  }

  // MARK: - Thread-safe static caching to avoid expensive operations on every write

  /// Thread-safe cache for expensive lookups
  /// static let initializers are lazy and guaranteed once-only with no races
  private enum Cache {
    static let machineId: String = MachineID.current()
    static let machineName: String = Host.current().localizedName ?? "Unknown"
    static let appVersion: String =
      (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown"
  }

  /// Updates access metadata for current machine
  public static func recordAccess(db: Database) throws {
    let metadata = DatabaseAccessMetadata(
      machineId: Cache.machineId,
      machineName: Cache.machineName,
      lastAccess: Date(),
      appVersion: Cache.appVersion
    )

    try metadata.insert(db, onConflict: .replace)
  }

  /// Checks for potential access conflicts
  public static func checkForConflicts(db: Database) throws -> ConflictType? {
    let currentMachineId = Cache.machineId
    let allAccess = try DatabaseAccessMetadata.fetchAll(db)

    // Filter out current machine
    let otherMachines = allAccess.filter { $0.machineId != currentMachineId }

    guard !otherMachines.isEmpty else {
      return nil  // No other machines have accessed this database
    }

    // Check for recent conflicts (within last 5 minutes)
    let recentThreshold = Date().addingTimeInterval(-300)  // 5 minutes ago
    let recentAccess = otherMachines.filter { $0.lastAccess > recentThreshold }

    if let recent = recentAccess.first {
      let timeSince = Date().timeIntervalSince(recent.lastAccess)
      return .recentConflict(otherMachine: recent.machineName, timeSince: timeSince)
    }

    // Multiple machines but no recent conflicts
    if otherMachines.count > 0 {
      let machineNames = otherMachines.map { $0.machineName }
      return .multiMachine(machines: machineNames)
    }

    return nil
  }

  /// Gets unique machine identifier (App Store-safe, Keychain-backed)
  private static func getMachineId() -> String {
    return MachineID.current()
  }

  /// Schema migration to add metadata table
  public static func addAccessMetadataTable(db: Database) throws {
    try db.create(table: "database_access_metadata", ifNotExists: true) { t in
      t.column("machine_id", .text).primaryKey()
      t.column("machine_name", .text).notNull()
      t.column("last_access", .datetime).notNull()
      t.column("app_version", .text).notNull()
    }

    log.info("Created database_access_metadata table")
  }
}
