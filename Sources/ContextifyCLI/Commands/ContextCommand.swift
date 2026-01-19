// SPDX-License-Identifier: MIT
// ContextCommand.swift - Get context around a specific entry

import ArgumentParser
import Foundation
import GRDB
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct ContextCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "context",
    abstract: "Get context around an entry",
    discussion: """
      Retrieve entries before and after a specific entry ID, useful for
      understanding the full conversation context of a search result.

      EXAMPLES:
        contextify context abc123              # Get context around entry abc123
        contextify context abc123 --before 5  # 5 entries before, default after
        contextify context abc123 --after 10  # Default before, 10 entries after
        contextify context abc123 --json      # JSON output for scripting
      """
  )

  @Argument(help: "Entry ID to get context for")
  public var entryId: String

  @Option(name: .long, help: "Path to the SQLite database file")
  public var db: String?

  @Option(name: .long, help: "Number of entries before (default: 5)")
  public var before: Int = 5

  @Option(name: .long, help: "Number of entries after (default: 5)")
  public var after: Int = 5

  @Flag(name: .long, help: "Include hidden entries")
  public var includeHidden: Bool = false

  @Flag(name: .long, help: "Exclude content from output")
  public var noContent: Bool = false

  @Flag(name: .long, help: "Include full content (no truncation)")
  public var fullContent: Bool = false

  @Flag(name: .long, help: "Output as JSON for scripting")
  public var json: Bool = false

  public init() {}

  public mutating func run() throws {
    // Validate before/after
    guard before >= 0 else {
      throw ValidationError("--before must be >= 0")
    }
    guard after >= 0 else {
      throw ValidationError("--after must be >= 0")
    }

    // Resolve database path
    let dbPath = resolveDatabasePath()

    // Check if database exists
    guard FileManager.default.fileExists(atPath: dbPath) else {
      if json {
        emitJSON([
          "type": "error",
          "code": "db_not_found",
          "message": "Database not found",
          "database_path": dbPath
        ])
      } else {
        XDGPaths.writeStderr("Database not found at: \(dbPath)\n")
        XDGPaths.writeStderr("Run 'contextify ingest' to create the database and index transcripts.\n")
      }
      throw ExitCode(2)
    }

    // Open database and get context
    let dbURL = URL(fileURLWithPath: dbPath)
    let service = try ContextifyQueryService(databaseURL: dbURL)

    do {
      let result = try service.context(
        entryId: entryId,
        beforeCount: before,
        afterCount: after,
        includeHidden: includeHidden,
        includeContent: !noContent,
        fullContent: fullContent,
        maxContentBytes: 2048
      )

      // Output results
      if json {
        outputJSON(result: result)
      } else {
        outputHuman(result: result)
      }
    } catch let error as ContextifyQueryService.EntryLookupError {
      switch error {
      case .notFound(let id):
        if json {
          emitJSON([
            "type": "error",
            "code": "entry_not_found",
            "message": "No entry with id '\(id)'"
          ])
        } else {
          XDGPaths.writeStderr("Error: No entry with id '\(id)'\n")
        }
        throw ExitCode(1)
      }
    }
  }

  // MARK: - Helpers

  private func resolveDatabasePath() -> String {
    if let dbFlag = db {
      return XDGPaths.expandTilde(dbFlag)
    }
    return XDGPaths.databasePath.path
  }

  private func outputHuman(result: ContextifyQueryService.ContextResult) {
    let totalEntries = result.before.count + 1 + result.after.count

    print("Context for entry \(entryId) (\(totalEntries) entries):\n")

    if result.meta.hasMoreBefore {
      print("... (more entries before)")
      print("")
    }

    // Print entries before
    for entry in result.before {
      printEntry(entry, isAnchor: false)
    }

    // Print anchor entry (highlighted)
    printEntry(result.anchor, isAnchor: true)

    // Print entries after
    for entry in result.after {
      printEntry(entry, isAnchor: false)
    }

    if result.meta.hasMoreAfter {
      print("")
      print("... (more entries after)")
    }
  }

  private func printEntry(_ entry: ContextifyQueryService.EntryPayload, isAnchor: Bool) {
    let timestamp = formatTimestamp(entry.timestamp)
    let kindDisplay = entry.kind.replacingOccurrences(of: "_", with: " ")
    let marker = isAnchor ? ">>>" : "   "

    print("\(marker) [\(timestamp)] \(kindDisplay) (\(entry.id))")

    if let content = entry.content, !noContent {
      let lines = content.components(separatedBy: "\n")
      let prefix = isAnchor ? ">>> " : "    "
      for line in lines.prefix(5) {
        let truncatedLine = line.count > 100 ? String(line.prefix(100)) + "..." : line
        print("\(prefix)\(truncatedLine)")
      }
      if lines.count > 5 || (entry.contentTruncated ?? false) {
        print("\(prefix)...")
      }
    }
    print("")
  }

  private func outputJSON(result: ContextifyQueryService.ContextResult) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    struct ContextResponse: Encodable {
      let type: String
      let schemaVersion: Int
      let data: ContextifyQueryService.ContextResult
    }

    let response = ContextResponse(
      type: "context",
      schemaVersion: 1,
      data: result
    )

    do {
      let data = try encoder.encode(response)
      if let jsonString = String(data: data, encoding: .utf8) {
        print(jsonString)
      }
    } catch {
      XDGPaths.writeStderr("JSON encoding error: \(error)\n")
    }
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

  private func formatTimestamp(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: Double(timestamp))
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter.string(from: date)
  }
}
