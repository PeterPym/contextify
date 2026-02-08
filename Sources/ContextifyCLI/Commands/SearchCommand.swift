// SPDX-License-Identifier: MIT
// SearchCommand.swift - Full-text search across indexed transcripts

import ArgumentParser
import Foundation
import GRDB
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct SearchCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "search",
    abstract: "Search indexed transcripts",
    discussion: """
      Full-text search across all indexed Claude Code and Codex CLI transcripts.
      Returns matching entries with snippets showing the match context.

      EXAMPLES:
        contextify search "error handling"           # Search all transcripts
        contextify search "refactor" --days 7        # Last 7 days only
        contextify search "database" --limit 20     # Limit results
        contextify search "config" --json            # JSON output for scripting
      """
  )

  @Argument(help: "Search query (use quotes for exact phrases)")
  public var query: String

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

  @Option(name: .long, help: "Maximum number of results (default: 50, max: 500)")
  public var limit: Int = 50

  @Flag(name: .long, help: "Include hidden entries")
  public var includeHidden: Bool = false

  @Option(name: .long, help: "Filter by entry kinds (comma-separated: user,assistant,tool_use,tool_result)")
  public var kinds: String?

  @Flag(name: .long, help: "Output as JSON for scripting")
  public var json: Bool = false

  public init() {}

  public mutating func run() throws {
    // Validate limit
    guard limit > 0 && limit <= 500 else {
      throw ValidationError("--limit must be between 1 and 500")
    }

    // Validate query
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      throw ValidationError("Search query cannot be empty")
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

    // Parse kinds filter
    let kindsFilter: [String]? = kinds?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

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

    // Open database and run search
    let dbURL = URL(fileURLWithPath: dbPath)
    let service = try ContextifyQueryService(databaseURL: dbURL)

    let results = try service.search(
      query: trimmedQuery,
      projectId: projectId,
      transcriptId: transcriptId,
      limit: limit,
      includeHidden: includeHidden,
      timeRange: timeRange,
      kinds: kindsFilter,
      treatAsFTS: false
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

  private func outputHuman(results: [ContextifyQueryService.SearchHit]) {
    if results.isEmpty {
      print("No results found.")
      return
    }

    print("Found \(results.count) result\(results.count == 1 ? "" : "s"):\n")

    for (index, hit) in results.enumerated() {
      let projectDisplay = hit.projectName ?? hit.projectId
      let timestamp = formatTimestamp(hit.timestamp)

      print("[\(index + 1)] \(projectDisplay) - \(hit.kind)")
      print("    Time: \(timestamp)")
      print("    Entry: \(hit.id)")
      if let title = hit.transcriptTitle {
        print("    Transcript: \(title)")
      }
      print("    ---")
      // Indent the snippet
      let snippetLines = hit.contentSnippet.components(separatedBy: "\n")
      for line in snippetLines.prefix(5) {
        print("    \(line)")
      }
      if snippetLines.count > 5 || hit.contentTruncated {
        print("    ...")
      }
      print("")
    }
  }

  private func outputJSON(results: [ContextifyQueryService.SearchHit]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    struct SearchResponse: Encodable {
      let type: String
      let schemaVersion: Int
      let data: ResultData

      struct ResultData: Encodable {
        let results: [ContextifyQueryService.SearchHit]
        let count: Int
      }
    }

    let response = SearchResponse(
      type: "search",
      schemaVersion: 1,
      data: SearchResponse.ResultData(
        results: results,
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
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
