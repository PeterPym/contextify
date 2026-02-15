// SPDX-License-Identifier: MIT
// ActivityCommand.swift - Show recent activity across transcripts

import ArgumentParser
import Foundation
import GRDB
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct ActivityCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "activity",
    abstract: "Show recent activity",
    discussion: """
      Display recent entries across all indexed transcripts, sorted by time.
      Useful for seeing what you've been working on recently.

      EXAMPLES:
        contextify activity                    # Recent activity (default 50 entries)
        contextify activity --days 1           # Last 24 hours only
        contextify activity --limit 20         # Fewer results
        contextify activity --json             # JSON output for scripting
      """
  )

  @Option(name: .long, help: "Path to the SQLite database file")
  public var db: String?

  @Option(name: .long, help: "Filter to specific project ID")
  public var projectId: String?

  @Option(name: .long, help: "Filter to specific transcript ID")
  public var transcriptId: String?

  @Option(name: .long, help: "Only include entries from the last N days")
  public var days: Int?

  @Option(name: .long, help: "Start time (ISO8601 or Unix timestamp)")
  public var since: String?

  @Option(name: .long, help: "End time (ISO8601 or Unix timestamp)")
  public var until: String?

  @Option(name: .long, help: "Maximum number of results (default: 50)")
  public var limit: Int = 50

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
    // Validate limit
    guard limit > 0 else {
      throw ValidationError("--limit must be > 0")
    }

    // Parse time range
    let timeRange: QueryTimeRange
    do {
      timeRange = try QueryTimeParser.parseSinceUntil(since: since, until: until, days: days)
    } catch let error as QueryTimeParseError {
      switch error {
      case .invalidValue(let msg):
        throw ValidationError(msg)
      }
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

    // Open database and get activity
    let dbURL = URL(fileURLWithPath: dbPath)
    let service = try ContextifyQueryService(databaseURL: dbURL)

    let results = try service.activity(
      projectId: projectId,
      transcriptId: transcriptId,
      limit: limit,
      includeHidden: includeHidden,
      timeRange: timeRange,
      includeContent: !noContent,
      fullContent: fullContent,
      maxContentBytes: 2048
    )

    // Output results
    if json {
      outputJSON(results: results)
    } else {
      outputHuman(results: results)
    }
  }

  // MARK: - Helpers

  private func resolveDatabasePath() -> String {
    if let dbFlag = db {
      return XDGPaths.expandTilde(dbFlag)
    }
    return XDGPaths.databasePath.path
  }

  private func outputHuman(results: [ContextifyQueryService.ActivityItem]) {
    if results.isEmpty {
      print("No recent activity found.")
      return
    }

    print("Recent activity (\(results.count) entries):\n")

    for item in results {
      let entry = item.entry
      let timestamp = formatTimestamp(entry.timestamp)
      let kindDisplay = entry.kind.replacingOccurrences(of: "_", with: " ")
      let projectDisplay = item.projectName ?? entry.projectId

      print("[\(timestamp)] \(kindDisplay)")
      print("  Project: \(projectDisplay)")
      print("  Entry: \(entry.id)")

      if let content = entry.content, !noContent {
        print("  ---")
        let lines = content.components(separatedBy: "\n")
        for line in lines.prefix(3) {
          let truncatedLine = line.count > 100 ? String(line.prefix(100)) + "..." : line
          print("  \(truncatedLine)")
        }
        if lines.count > 3 || (entry.contentTruncated ?? false) {
          print("  ...")
        }
      }
      print("")
    }
  }

  private func outputJSON(results: [ContextifyQueryService.ActivityItem]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    struct ActivityResponse: Encodable {
      let type: String
      let schemaVersion: Int
      let data: ResultData

      struct ResultData: Encodable {
        let entries: [ContextifyQueryService.ActivityItem]
        let count: Int
      }
    }

    let response = ActivityResponse(
      type: "activity",
      schemaVersion: 1,
      data: ActivityResponse.ResultData(
        entries: results,
        count: results.count
      )
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
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
