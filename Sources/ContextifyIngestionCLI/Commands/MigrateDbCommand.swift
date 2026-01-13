// SPDX-License-Identifier: MIT
// MigrateDbCommand.swift - Migrate database to XDG location

import ArgumentParser
import Foundation
import GRDB
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct MigrateDbCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "migrate-db",
    abstract: "Move database to XDG-compliant location",
    discussion: """
      Safely copies the database from a legacy location to the XDG-compliant
      default location (~/.local/share/contextify/contextify.db).

      The migration uses SQLite's backup API to ensure a consistent copy,
      even if the database is being written to.

      EXAMPLES:
        contextify migrate-db                     # Auto-detect and migrate
        contextify migrate-db --from ~/old.db    # Migrate specific database
        contextify migrate-db --dry-run          # Preview without changes
        contextify migrate-db --delete-old       # Remove old after migration

      OPTIONS:
        --yes is required when running non-interactively (in scripts/cron)
      """
  )

  @Option(name: .long, help: "Source database path (default: auto-detect legacy location)")
  public var from: String?

  @Option(name: .long, help: "Destination path (default: XDG location)")
  public var to: String?

  @Flag(name: .long, help: "Remove old database after successful migration")
  public var deleteOld: Bool = false

  @Flag(name: .long, help: "Show what would happen without making changes")
  public var dryRun: Bool = false

  @Flag(name: .long, help: "Skip confirmation prompt (required for non-interactive use)")
  public var yes: Bool = false

  public init() {}

  public mutating func run() throws {
    // Determine source path (with tilde expansion for user-provided paths)
    let sourcePath: String
    if let fromPath = from {
      sourcePath = XDGPaths.expandTilde(fromPath)
    } else if let legacyPath = XDGPaths.findLegacyDatabase() {
      sourcePath = legacyPath.path
    } else {
      print("No legacy database found to migrate.")
      print("")
      print("Checked locations:")
      for path in XDGPaths.legacyDatabasePaths {
        print("  - \(path.path)")
      }
      print("")
      print("If your database is in a custom location, use --from to specify it:")
      print("  contextify migrate-db --from /path/to/old/database.db")
      throw ExitCode(CLIExitCode.noop.rawValue)
    }

    // Verify source exists
    guard FileManager.default.fileExists(atPath: sourcePath) else {
      XDGPaths.writeStderr("Error: Source database not found: \(sourcePath)\n")
      throw ExitCode.failure
    }

    // Determine destination path (with tilde expansion for user-provided paths)
    let destPath: String
    if let toPath = to {
      destPath = XDGPaths.expandTilde(toPath)
    } else {
      destPath = XDGPaths.databasePath.path
    }

    // Check if destination already exists
    if FileManager.default.fileExists(atPath: destPath) {
      print("Destination already exists: \(destPath)")
      print("")
      print("If you want to overwrite, remove the destination first:")
      print("  rm \(destPath)")
      print("  contextify migrate-db")
      throw ExitCode.failure
    }

    // Check if source and destination are the same
    let resolvedSource = URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath().path
    let resolvedDest = URL(fileURLWithPath: destPath).resolvingSymlinksInPath().path
    if resolvedSource == resolvedDest {
      print("Source and destination are the same location.")
      throw ExitCode(CLIExitCode.noop.rawValue)
    }

    // Dry run: just show what would happen
    if dryRun {
      print("Dry run - no changes will be made")
      print("")
      print("Would migrate:")
      print("  From: \(sourcePath)")
      print("  To:   \(destPath)")
      if deleteOld {
        print("  Then delete: \(sourcePath)")
      }
      return
    }

    // Interactive confirmation (if not --yes and both stdin/stderr are TTYs)
    if !yes {
      if XDGPaths.isInteractive() {
        print("Migrate database?")
        print("  From: \(sourcePath)")
        print("  To:   \(destPath)")
        print("")
        print("Type 'yes' to continue, or use --yes to skip this prompt:")
        if let response = readLine()?.lowercased(), response == "yes" {
          // Continue with migration
        } else {
          print("Migration cancelled.")
          throw ExitCode(CLIExitCode.noop.rawValue)
        }
      } else {
        XDGPaths.writeStderr("Error: Running non-interactively. Use --yes to confirm migration.\n")
        throw ExitCode.failure
      }
    }

    // Stop systemd timer if running (Linux only)
    #if os(Linux)
    let timerWasActive = stopSystemdTimer()
    #endif

    // Ensure destination directory exists with secure permissions
    let destDir = URL(fileURLWithPath: destPath).deletingLastPathComponent()
    if !XDGPaths.ensureSecureDirectory(destDir) {
      #if os(Linux)
      if timerWasActive { startSystemdTimer() }
      #endif
      throw ExitCode.failure
    }

    // Perform migration using SQLite backup API
    print("Migrating database...")
    print("  From: \(sourcePath)")
    print("  To:   \(destPath)")

    do {
      try performMigration(from: sourcePath, to: destPath)
    } catch {
      XDGPaths.writeStderr("Error: Migration failed: \(error.localizedDescription)\n")
      // Clean up partial destination
      try? FileManager.default.removeItem(atPath: destPath)
      #if os(Linux)
      if timerWasActive { startSystemdTimer() }
      #endif
      throw ExitCode.failure
    }

    // Set secure permissions on new file and any sidecars
    XDGPaths.setSecureDatabasePermissions(URL(fileURLWithPath: destPath))

    // Verify the migrated database
    print("Verifying migration...")
    do {
      let result = try DatabaseOpener.validateDatabase(at: destPath)
      if !result.isValid {
        XDGPaths.writeStderr("Error: Migrated database validation failed\n")
        try? FileManager.default.removeItem(atPath: destPath)
        #if os(Linux)
        if timerWasActive { startSystemdTimer() }
        #endif
        throw ExitCode.failure
      }
      print("  Schema v\(result.schemaVersion)")
      print("  \(result.projectCount) projects, \(result.transcriptCount) transcripts")
    } catch {
      XDGPaths.writeStderr("Error: Could not verify migrated database: \(error.localizedDescription)\n")
      try? FileManager.default.removeItem(atPath: destPath)
      #if os(Linux)
      if timerWasActive { startSystemdTimer() }
      #endif
      throw ExitCode.failure
    }

    // Restart systemd timer (Linux only)
    #if os(Linux)
    if timerWasActive { startSystemdTimer() }
    #endif

    // Get file size for display
    let attrs = try? FileManager.default.attributesOfItem(atPath: destPath)
    let fileSize = attrs?[.size] as? Int64 ?? 0
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    let sizeStr = formatter.string(fromByteCount: fileSize)

    print("")
    print("Migration complete!")
    print("  New database: \(destPath) (\(sizeStr))")
    print("  Old database: \(sourcePath) (retained)")

    // Delete old if requested
    if deleteOld {
      do {
        try FileManager.default.removeItem(atPath: sourcePath)
        print("  Old database deleted.")
      } catch {
        XDGPaths.writeStderr("Warning: Could not delete old database: \(error.localizedDescription)\n")
      }
    } else {
      print("")
      print("To remove old database: contextify migrate-db --delete-old")
    }
  }

  // MARK: - Migration

  private func performMigration(from sourcePath: String, to destPath: String) throws {
    // Use GRDB's backup functionality for safe migration
    var sourceConfig = Configuration()
    // Set busyMode to handle concurrent writers (transient locks)
    sourceConfig.busyMode = .timeout(5.0)  // Wait up to 5 seconds for locks
    let sourceQueue = try DatabaseQueue(path: sourcePath, configuration: sourceConfig)

    var destConfig = Configuration()
    destConfig.busyMode = .timeout(5.0)
    destConfig.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode=WAL")
    }

    let destQueue = try DatabaseQueue(path: destPath, configuration: destConfig)

    do {
      try sourceQueue.backup(to: destQueue)
    } catch {
      // Provide actionable error if it looks like a lock issue
      let errorDesc = error.localizedDescription.lowercased()
      if errorDesc.contains("busy") || errorDesc.contains("locked") {
        XDGPaths.writeStderr("Error: Database is locked by another process.\n")
        XDGPaths.writeStderr("Hint: Stop any processes using the database (e.g., systemctl --user stop contextify.timer)\n")
      }
      throw error
    }
  }

  // MARK: - Systemd Helpers

  #if os(Linux)
  private func stopSystemdTimer() -> Bool {
    let result = runSystemctl(["--user", "is-active", "contextify.timer"])
    if result.exitCode == 0 {
      _ = runSystemctl(["--user", "stop", "contextify.timer"])
      return true
    }
    return false
  }

  private func startSystemdTimer() {
    _ = runSystemctl(["--user", "start", "contextify.timer"])
  }

  private func runSystemctl(_ args: [String]) -> (exitCode: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()

    // Use env to find systemctl in PATH (checks /usr/bin/env, /bin/env for portability)
    process.executableURL = URL(fileURLWithPath: XDGPaths.envPath)
    process.arguments = ["systemctl"] + args
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
  #endif
}
