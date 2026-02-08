// SPDX-License-Identifier: MIT
// ProjectsCommand.swift - List indexed projects

import ArgumentParser
import Foundation
import GRDB
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct ProjectsCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "projects",
    abstract: "List indexed projects",
    discussion: """
      Display all projects that have been indexed, with statistics about
      transcript and entry counts.

      EXAMPLES:
        contextify projects                    # List all projects
        contextify projects --include-hidden   # Include hidden projects
        contextify projects --json             # JSON output for scripting
      """
  )

  @Option(name: .long, help: "Path to the SQLite database file")
  public var db: String?

  @Option(name: .long, help: "Maximum number of projects to show")
  public var limit: Int?

  @Flag(name: .long, help: "Include hidden projects")
  public var includeHidden: Bool = false

  @Flag(name: .long, help: "Output as JSON for scripting")
  public var json: Bool = false

  public init() {}

  public mutating func run() throws {
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

    // Open database and list projects
    let dbURL = URL(fileURLWithPath: dbPath)
    let service = try ContextifyQueryService(databaseURL: dbURL)

    let projects = try service.listProjects(includeHidden: includeHidden, limit: limit)

    // Output results
    if json {
      outputJSON(projects: projects)
    } else {
      outputHuman(projects: projects)
    }
  }

  // MARK: - Helpers

  private func resolveDatabasePath() -> String {
    if let dbFlag = db {
      return XDGPaths.expandTilde(dbFlag)
    }
    return XDGPaths.databasePath.path
  }

  private func outputHuman(projects: [ContextifyQueryService.ProjectListItem]) {
    if projects.isEmpty {
      print("No projects found.")
      print("")
      print("Run 'contextify ingest' to index transcripts from Claude Code or Codex CLI.")
      return
    }

    print("Indexed projects (\(projects.count)):\n")

    for project in projects {
      let name = project.name ?? "(unnamed)"
      let transcripts = project.transcriptCount ?? 0
      let entries = project.entryCount ?? 0

      print("\(name)")
      print("  ID: \(project.id)")
      print("  Path: \(project.rootPath)")
      print("  Transcripts: \(transcripts), Entries: \(formatNumber(entries))")

      if let lastActivity = project.lastActivityTimestamp {
        print("  Last activity: \(formatTimestamp(lastActivity))")
      }

      if project.hidden {
        print("  (hidden)")
      }
      print("")
    }
  }

  private func outputJSON(projects: [ContextifyQueryService.ProjectListItem]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    struct ProjectsResponse: Encodable {
      let type: String
      let schemaVersion: Int
      let data: ResultData

      struct ResultData: Encodable {
        let projects: [ContextifyQueryService.ProjectListItem]
        let count: Int
      }
    }

    let response = ProjectsResponse(
      type: "projects",
      schemaVersion: 1,
      data: ProjectsResponse.ResultData(
        projects: projects,
        count: projects.count
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

  private func formatNumber(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
  }

  private func formatTimestamp(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: Double(timestamp))
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
