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

    // For now, report that this is a stub implementation
    // Full implementation will use TranscriptOrchestrator.discoverTranscripts()
    if format == .human {
      print("")
      print("NOTE: This is a stub implementation.")
      print("Full ingestion logic using TranscriptOrchestrator is pending.")
      print("")
      print("Projects discovered:")
      for project in projects {
        print("  - \(project.displayName) (\(project.transcriptFiles.count) transcripts)")
      }
    }

    let duration = Date().timeIntervalSince(startTime)
    let summary = IngestionSummary(
      transcriptsProcessed: 0,
      entriesInserted: 0,
      entriesSkipped: 0,
      errorsEncountered: 0,
      durationSeconds: duration
    )
    sink.ingestionCompleted(runId: String(runId), success: true, summary: summary)

    if format == .human {
      print("")
      print("Database created at: \(db)")
      print("Use 'contextify-ingest verify --db \(db)' to verify the database.")
    }
  }
}
