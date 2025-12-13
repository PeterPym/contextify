import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "StateWriter")

/// Writes a discovery sidecar next to the active database.
/// Sidecar location: `<db-dir>/.state/state.json` and README.
enum StateWriter {
  static let schemaURL = "https://contextify.sh/schemas/state/v1.json"
  static let stateVersion = 1

  struct StateV1: Codable, Sendable {
    let schema: String
    let stateVersion: Int
    let databasePath: String
    let databaseDir: String
    let schemaVersion: Int
    let buildFlavor: String
    let appVersion: String
    let lastMigratedAt: String
    let lastWrittenAt: String
    let capabilities: [String]

    enum CodingKeys: String, CodingKey {
      case schema = "$schema"
      case stateVersion = "state_version"
      case databasePath = "database_path"
      case databaseDir = "database_dir"
      case schemaVersion = "schema_version"
      case buildFlavor = "build_flavor"
      case appVersion = "app_version"
      case lastMigratedAt = "last_migrated_at"
      case lastWrittenAt = "last_written_at"
      case capabilities
    }
  }

  static func writeState(
    databaseURL: URL,
    schemaVersion: Int,
    appVersion: String,
    buildFlavor: String,
    capabilities: [String]
  ) {
    do {
      let dbDir = databaseURL.deletingLastPathComponent()
      let stateDir = dbDir.appendingPathComponent(".state", isDirectory: true)
      try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

      let readmeURL = stateDir.appendingPathComponent("README.md")
      if !FileManager.default.fileExists(atPath: readmeURL.path) {
        try readmeContents().write(to: readmeURL, atomically: true, encoding: .utf8)
      }

      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      let now = Date()
      let lastWrittenAt = formatter.string(from: now)
      // Best-effort: actual migration time isn't currently tracked, so keep legacy field aligned.
      let lastMigratedAt = lastWrittenAt

      let state = StateV1(
        schema: schemaURL,
        stateVersion: stateVersion,
        databasePath: databaseURL.path,
        databaseDir: dbDir.path,
        schemaVersion: schemaVersion,
        buildFlavor: buildFlavor,
        appVersion: appVersion,
        lastMigratedAt: lastMigratedAt,
        lastWrittenAt: lastWrittenAt,
        capabilities: capabilities
      )

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(state)

      let stateURL = stateDir.appendingPathComponent("state.json")
      try data.write(to: stateURL, options: .atomic)
    } catch {
      log.warning("Failed writing state sidecar for db at \(databaseURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  private static func readmeContents() -> String {
    """
    # Contextify Database State Sidecar

    This folder is a machine-readable discovery sidecar for Contextify tools.

    - `state.json` describes the active database location and capabilities.
    - The schema is versioned and additive. Older readers should ignore unknown fields.
    - `last_written_at` is the timestamp when this sidecar was written.
    - `last_migrated_at` is a legacy timestamp field and may currently match `last_written_at`.

    If this folder is missing, open Contextify once to initialize discovery.
    """
  }
}
