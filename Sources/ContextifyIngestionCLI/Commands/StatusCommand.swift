// SPDX-License-Identifier: MIT
// StatusCommand.swift - Show database and service status

import ArgumentParser
import Foundation
import GRDB
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct StatusCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Show database and service status",
    discussion: """
      Displays information about the Contextify database including:
      - Database location and size
      - Schema version
      - Indexed content statistics
      - Provider breakdown (Claude Code, Codex CLI)
      - Background service status (if installed)

      EXAMPLES:
        contextify status              # Show status using default database
        contextify status --json       # Output as JSON for scripting
        contextify status --db ~/custom.db
      """
  )

  @Option(name: .long, help: "Path to the SQLite database file (default: XDG location)")
  public var db: String?

  @Flag(name: .long, help: "Output as JSON for scripting")
  public var json: Bool = false

  public init() {}

  public mutating func run() throws {
    let dbPath = resolveDatabasePath()

    // Check if database exists
    guard FileManager.default.fileExists(atPath: dbPath) else {
      if json {
        emitJSON([
          "format_version": 1,
          "error": "Database not found",
          "database_path": dbPath
        ])
      } else {
        print("Database not found at: \(dbPath)")
        print("")
        print("Run 'contextify ingest' to create the database and index transcripts.")
      }
      throw ExitCode(CLIExitCode.noop.rawValue)
    }

    // Get database file size
    let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
    let fileSize = attrs[.size] as? Int64 ?? 0

    // Open database read-only
    var config = Configuration()
    config.readonly = true
    let pool = try DatabasePool(path: dbPath, configuration: config)

    // Query database stats
    let stats = try pool.read { db -> DatabaseStats in
      var stats = DatabaseStats()

      // Schema version
      stats.schemaVersion = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0

      // Counts
      stats.projectCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects") ?? 0
      stats.transcriptCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts") ?? 0
      stats.entryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries") ?? 0

      // Provider breakdown
      let providerRows = try Row.fetchAll(db, sql: """
        SELECT provider, COUNT(*) as count,
               MAX(last_modified) as last_activity
        FROM transcripts
        GROUP BY provider
      """)

      for row in providerRows {
        let provider: String = row["provider"]
        let count: Int = row["count"]
        let lastActivity: Int? = row["last_activity"]
        stats.providers[provider] = ProviderStats(
          transcripts: count,
          lastActivity: lastActivity.map { Date(timeIntervalSince1970: Double($0)) }
        )
      }

      return stats
    }

    // Check systemd timer status (Linux only)
    let serviceStatus = checkServiceStatus()

    // Output
    if json {
      outputJSON(dbPath: dbPath, fileSize: fileSize, stats: stats, service: serviceStatus)
    } else {
      outputHuman(dbPath: dbPath, fileSize: fileSize, stats: stats, service: serviceStatus)
    }
  }

  // MARK: - Helpers

  private func resolveDatabasePath() -> String {
    if let dbFlag = db {
      return dbFlag
    }
    return XDGPaths.databasePath.path
  }

  private func checkServiceStatus() -> ServiceStatus {
    #if os(Linux)
    // Check if timer is active
    let timerCheck = runCommand("systemctl", ["--user", "is-active", "contextify.timer"])
    let isActive = timerCheck.exitCode == 0

    var nextRun: Date?
    if isActive {
      // Get next run time
      let nextRunCheck = runCommand("systemctl", ["--user", "show", "contextify.timer", "--property=NextElapseUSecRealtime", "--value"])
      if nextRunCheck.exitCode == 0, let usec = Int64(nextRunCheck.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
        nextRun = Date(timeIntervalSince1970: Double(usec) / 1_000_000)
      }
    }

    return ServiceStatus(active: isActive, nextRun: nextRun)
    #else
    return ServiceStatus(active: false, nextRun: nil)
    #endif
  }

  private func runCommand(_ command: String, _ args: [String]) -> (exitCode: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/\(command)")
    process.arguments = args
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      return (process.terminationStatus, output)
    } catch {
      return (1, "")
    }
  }

  private func outputHuman(dbPath: String, fileSize: Int64, stats: DatabaseStats, service: ServiceStatus) {
    print("Contextify Database Status")
    print("==========================")
    print("Database: \(dbPath)")
    print("Size: \(formatBytes(fileSize))")
    print("Schema: v\(stats.schemaVersion)")
    print("")

    print("Indexed Content:")
    print("  Projects: \(stats.projectCount)")
    print("  Transcripts: \(stats.transcriptCount)")
    print("  Entries: \(formatNumber(stats.entryCount))")
    print("")

    if !stats.providers.isEmpty {
      print("Providers:")
      for (provider, providerStats) in stats.providers.sorted(by: { $0.value.transcripts > $1.value.transcripts }) {
        let displayName = providerDisplayName(provider)
        var line = "  \(displayName): \(providerStats.transcripts) transcripts"
        if let lastActivity = providerStats.lastActivity {
          line += " (last: \(formatRelativeTime(lastActivity)))"
        }
        print(line)
      }
      print("")
    }

    #if os(Linux)
    if service.active {
      print("Background Service: active")
      if let nextRun = service.nextRun {
        print("  Next run: \(formatRelativeTime(nextRun))")
      }
    } else {
      print("Background Service: not installed")
      print("  Run 'contextify install-service' to enable automatic ingestion")
    }
    print("")
    #endif
  }

  private func outputJSON(dbPath: String, fileSize: Int64, stats: DatabaseStats, service: ServiceStatus) {
    var providers: [String: Any] = [:]
    for (provider, providerStats) in stats.providers {
      var entry: [String: Any] = ["transcripts": providerStats.transcripts]
      if let lastActivity = providerStats.lastActivity {
        entry["last_activity"] = ISO8601DateFormatter().string(from: lastActivity)
      }
      providers[provider] = entry
    }

    var output: [String: Any] = [
      "format_version": 1,
      "cli_version": cliVersion,
      "database": [
        "path": dbPath,
        "size_bytes": fileSize,
        "schema_version": stats.schemaVersion
      ],
      "stats": [
        "projects": stats.projectCount,
        "transcripts": stats.transcriptCount,
        "entries": stats.entryCount
      ],
      "providers": providers
    ]

    #if os(Linux)
    var serviceDict: [String: Any] = ["active": service.active]
    if let nextRun = service.nextRun {
      serviceDict["next_run"] = ISO8601DateFormatter().string(from: nextRun)
    }
    output["service"] = serviceDict
    #endif

    emitJSON(output)
  }

  private func emitJSON(_ dict: [String: Any]) {
    do {
      let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted])
      if let json = String(data: data, encoding: .utf8) {
        print(json)
      }
    } catch {
      XDGPaths.writeStderr("JSON encoding error: \(error)\n")
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  private func formatNumber(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
  }

  private func formatRelativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func providerDisplayName(_ provider: String) -> String {
    switch provider {
    case "claude.code": return "Claude Code"
    case "codex.cli": return "Codex CLI"
    default: return provider
    }
  }
}

// MARK: - Supporting Types

private struct DatabaseStats {
  var schemaVersion: Int = 0
  var projectCount: Int = 0
  var transcriptCount: Int = 0
  var entryCount: Int = 0
  var providers: [String: ProviderStats] = [:]
}

private struct ProviderStats {
  var transcripts: Int
  var lastActivity: Date?
}

private struct ServiceStatus {
  var active: Bool
  var nextRun: Date?
}
