// SPDX-License-Identifier: MIT
// IngestCommand.swift - Main ingestion command

import ArgumentParser
import Foundation
import GRDB
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

struct IngestCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ingest",
    abstract: "Ingest transcripts into the database"
  )

  @Option(name: .long, help: "Path to the SQLite database file")
  var db: String

  @Option(name: .long, parsing: .upToNextOption, help: "Input directories to scan for transcripts")
  var input: [String] = []

  @Option(name: .long, help: "Transcript provider: auto, claude, or codex")
  var provider: ProviderOption = .auto

  @Flag(name: .long, help: "Delete existing data and rebuild from scratch")
  var fullRebuild: Bool = false

  @Option(name: .long, help: "Output format: jsonl or human")
  var format: OutputFormat = .human

  enum ProviderOption: String, ExpressibleByArgument {
    case auto, claude, codex
  }

  enum OutputFormat: String, ExpressibleByArgument {
    case jsonl, human
  }

  mutating func run() async throws {
    let runId = UUID().uuidString.prefix(8).lowercased()
    let startTime = Date()

    // Set up event sink
    let sinkFormat: CLIEventSink.OutputFormat = format == .jsonl ? .jsonl : .human
    let sink = CLIEventSink(format: sinkFormat)

    // Fail fast if --input is provided (not yet implemented)
    if !input.isEmpty {
      sink.fileError(path: input.joined(separator: ", "), error: "--input option is not yet implemented. Discovery uses default Claude/Codex locations.")
      throw ExitCode.failure
    }

    // Open database with FTS5 preflight
    let pool: DatabasePool
    do {
      pool = try DatabaseOpener.openDatabase(at: db)
    } catch let error as DatabaseOpener.CLIError {
      sink.fileError(path: db, error: error.localizedDescription)
      throw ExitCode.failure
    }

    // Handle full rebuild
    if fullRebuild {
      if format == .human {
        print("Performing full rebuild - clearing existing data...")
      }
      try await pool.write { db in
        try db.execute(sql: "DELETE FROM transcript_entries")
        try db.execute(sql: "DELETE FROM transcripts")
        try db.execute(sql: "DELETE FROM projects")
      }
    }

    // Discover transcripts
    let discovery = LightweightDiscoveryService()
    var projects = await discovery.discoverProjectsLightweight()

    // Filter by provider if specified
    if provider != .auto {
      let providerFilter = provider == .claude ? "claude.code" : "codex.cli"
      projects = projects.filter { $0.provider == providerFilter }
    }

    // Count total transcripts
    let totalTranscripts = projects.reduce(0) { $0 + $1.transcriptFiles.count }

    if format == .human {
      print("Found \(projects.count) projects with \(totalTranscripts) transcripts")
    }

    // Emit start event
    sink.ingestionStarted(runId: String(runId), transcriptCount: totalTranscripts)

    // Track statistics
    var totalErrors = 0
    var transcriptsProcessed = 0
    var projectsProcessed = 0

    // Run-level timestamp for created_at/updated_at bookkeeping
    let runNow = Int(Date().timeIntervalSince1970)

    // Process each project
    for project in projects {
      let projectId: String
      do {
        // Get or create project using direct SQL
        projectId = try await pool.write { db -> String in
          // Check if project exists
          if let existingId = try String.fetchOne(db, sql: """
            SELECT id FROM projects WHERE root_path = ?
          """, arguments: [project.canonicalRootPath]) {
            return existingId
          }

          // Create new project
          let newId = ProjectIdentity.computeProjectID(provider: project.provider, path: project.canonicalRootPath)
          try db.execute(sql: """
            INSERT INTO projects (id, root_path, name, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
          """, arguments: [newId, project.canonicalRootPath, project.displayName, runNow, runNow])
          return newId
        }

        if format == .human {
          print("\nProcessing: \(project.displayName) (\(project.transcriptFiles.count) transcripts)")
        }
        projectsProcessed += 1
      } catch {
        sink.fileError(path: project.path.path, error: "Failed to create project: \(error.localizedDescription)")
        totalErrors += 1
        continue
      }

      // Process each transcript in the project
      for fileURL in project.transcriptFiles {
        do {
          // Get file attributes
          let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
          let lastModified = (attrs[.modificationDate] as? Date) ?? Date()
          let fileSize = (attrs[.size] as? Int) ?? 0

          // Compute canonical path first (used for storage and provider derivation)
          let filePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
          let lastModifiedInt = Int(lastModified.timeIntervalSince1970)

          // Derive provider from canonical path using anchored patterns
          // (project.provider might be "multi" for merged projects)
          let transcriptProvider: String
          if filePath.contains("/.claude/projects/") {
            transcriptProvider = "claude.code"
          } else if filePath.contains("/.codex/sessions/") {
            transcriptProvider = "codex.cli"
          } else {
            transcriptProvider = "other"
          }

          // Upsert transcript record using direct SQL (cross-platform compatible)

          try await pool.write { db in
            // Check if transcript exists by (project_id, file_path)
            if let existingId = try String.fetchOne(db, sql: """
              SELECT id FROM transcripts WHERE project_id = ? AND file_path = ?
            """, arguments: [projectId, filePath]) {
              // Update existing
              try db.execute(sql: """
                UPDATE transcripts SET last_modified = ?, file_size = ?, updated_at = ?
                WHERE id = ?
              """, arguments: [lastModifiedInt, fileSize, runNow, existingId])
            } else {
              // Insert new
              let id = UUID().uuidString
              try db.execute(sql: """
                INSERT INTO transcripts (
                  id, project_id, file_path, provider, last_modified, file_size,
                  line_count, last_processed_line, parser_version, status, ingest_state,
                  created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, 0, 0, 1, 'active', 'partial', ?, ?)
              """, arguments: [id, projectId, filePath, transcriptProvider, lastModifiedInt, fileSize, runNow, runNow])
            }
          }

          transcriptsProcessed += 1

        } catch {
          sink.fileError(path: fileURL.path, error: error.localizedDescription)
          totalErrors += 1
        }
      }
    }

    let duration = Date().timeIntervalSince(startTime)

    // Note: Entry parsing not yet implemented - this creates the project/transcript skeleton
    // Full entry ingestion will be added when HooverEngine wiring is complete
    let summary = IngestionSummary(
      transcriptsProcessed: transcriptsProcessed,
      entriesInserted: 0,  // TODO: Wire HooverEngine for entry parsing
      entriesSkipped: 0,
      errorsEncountered: totalErrors,
      durationSeconds: duration
    )
    sink.ingestionCompleted(runId: String(runId), success: totalErrors == 0, summary: summary)

    if format == .human {
      print("")
      print("Ingestion complete (skeleton only - entry parsing pending):")
      print("  Projects processed: \(projectsProcessed)")
      print("  Transcripts registered: \(transcriptsProcessed)")
      print("  Errors: \(totalErrors)")
      print("  Duration: \(String(format: "%.2f", duration))s")
      print("")
      print("Database: \(db)")
      print("Use 'contextify-ingest verify --db \(db)' to verify the database.")
      print("")
      print("NOTE: Entry parsing (HooverEngine) not yet wired. Only project/transcript")
      print("      records are created. Full ingestion will be added in a future update.")
    }
  }
}
