// SPDX-License-Identifier: MIT
// VerifyCommand.swift - Database verification and diagnostics

import ArgumentParser
import Foundation
import GRDB
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct VerifyCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "verify",
    abstract: "Verify database integrity and environment compatibility",
    discussion: """
      Checks the database for:
      - WAL mode enabled
      - FTS5 full-text search available
      - Integrity check passes
      - Schema version

      EXAMPLES:
        contextify verify              # Verify default database
        contextify verify --full-check # Run thorough integrity check
        contextify verify --db ~/custom.db
      """
  )

  @Option(name: .long, help: "Path to the SQLite database file (default: XDG location)")
  public var db: String?

  @Option(name: .long, help: "Output format: jsonl or human")
  public var format: OutputFormat = .human

  @Flag(name: .long, help: "Run full integrity check (slower but more thorough)")
  public var fullCheck: Bool = false

  public enum OutputFormat: String, ExpressibleByArgument {
    case jsonl, human
  }

  public init() {}

  public mutating func run() throws {
    // Resolve database path
    let dbPath = db ?? XDGPaths.databasePath.path

    // Validate database
    let result: DatabaseOpener.ValidationResult
    do {
      result = try DatabaseOpener.validateDatabase(at: dbPath)
    } catch let error as DatabaseOpener.CLIError {
      if format == .jsonl {
        emitJSON([
          "status": "error",
          "error": error.localizedDescription
        ])
      } else {
        print("ERROR: \(error.localizedDescription)")
      }
      throw ExitCode.failure
    }

    // Get additional info if requested
    var fullIntegrityResult: String?
    if fullCheck {
      fullIntegrityResult = try runFullIntegrityCheck(dbPath: dbPath)
    }

    // Output results
    if format == .jsonl {
      var output: [String: Any] = [
        "status": result.isValid ? "valid" : "invalid",
        "journalMode": result.journalMode,
        "isWALMode": result.isWALMode,
        "hasFTS5": result.hasFTS5,
        "integrityOK": result.integrityOK,
        "schemaVersion": result.schemaVersion,
        "projectCount": result.projectCount,
        "transcriptCount": result.transcriptCount,
        "entryCount": result.entryCount,
        "sqliteVersion": result.sqliteVersion
      ]
      if let ftsError = result.fts5Error {
        output["fts5Error"] = ftsError
      }
      if let fullResult = fullIntegrityResult {
        output["fullIntegrityResult"] = fullResult
      }
      emitJSON(output)
    } else {
      printHumanReadable(dbPath: dbPath, result, fullIntegrityResult: fullIntegrityResult)
    }

    // Exit with appropriate code
    if !result.isValid {
      throw ExitCode.failure
    }
  }

  private func runFullIntegrityCheck(dbPath: String) throws -> String {
    var config = Configuration()
    config.readonly = true

    let pool = try DatabasePool(path: dbPath, configuration: config)
    return try pool.read { db in
      try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? "unknown"
    }
  }

  private func printHumanReadable(dbPath: String, _ result: DatabaseOpener.ValidationResult, fullIntegrityResult: String?) {
    print("Database Verification Report")
    print("============================")
    print("")
    print("Database: \(dbPath)")
    print("SQLite Version: \(result.sqliteVersion)")
    print("")

    // Status checks
    print("Status Checks:")
    printCheck("WAL Mode", result.isWALMode, detail: result.journalMode)
    printCheck("FTS5 Available", result.hasFTS5, detail: result.fts5Error)
    printCheck("Integrity Check", result.integrityOK, detail: result.integrityResult)
    print("")

    // Schema info
    print("Schema:")
    print("  Version: \(result.schemaVersion)")
    print("")

    // Data summary
    print("Data Summary:")
    print("  Projects: \(result.projectCount)")
    print("  Transcripts: \(result.transcriptCount)")
    print("  Entries: \(result.entryCount)")
    print("")

    // Full integrity if requested
    if let fullResult = fullIntegrityResult {
      print("Full Integrity Check:")
      print("  \(fullResult)")
      print("")
    }

    // Overall status
    print("============================")
    if result.isValid {
      print("RESULT: Database is valid")
    } else {
      print("RESULT: Database has issues")
      if !result.isWALMode {
        print("  - Not using WAL mode (expected: wal, got: \(result.journalMode))")
      }
      if !result.hasFTS5 {
        print("  - FTS5 not available: \(result.fts5Error ?? "unknown error")")
      }
      if !result.integrityOK {
        print("  - Integrity check failed: \(result.integrityResult)")
      }
    }
  }

  private func printCheck(_ name: String, _ passed: Bool, detail: String?) {
    let status = passed ? "[OK]" : "[FAIL]"
    var line = "  \(status) \(name)"
    if let detail = detail, !detail.isEmpty {
      line += " (\(detail))"
    }
    print(line)
  }

  private func emitJSON(_ dict: [String: Any]) {
    do {
      let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
      if var json = String(data: data, encoding: .utf8) {
        json.append("\n")
        print(json, terminator: "")
      }
    } catch {
      FileHandle.standardError.write(Data("JSON encoding error: \(error)\n".utf8))
    }
  }
}
