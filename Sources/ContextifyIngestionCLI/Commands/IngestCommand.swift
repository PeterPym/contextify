// SPDX-License-Identifier: MIT
// IngestCommand.swift - Main ingestion command with HooverEngine

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

  @Option(name: .long, help: "Only process transcripts modified after this time (ISO8601 or Unix timestamp)")
  var since: String?

  @Option(name: .long, help: "Number of parallel workers for transcript processing (default: 4)")
  var workers: Int = 4

  enum ProviderOption: String, ExpressibleByArgument {
    case auto, claude, codex
  }

  enum OutputFormat: String, ExpressibleByArgument {
    case jsonl, human
  }

  /// Parse --since value as Date (supports ISO8601 or Unix timestamp)
  private func parseSinceDate() throws -> Date? {
    guard let sinceStr = since else { return nil }

    // Try Unix timestamp (seconds) - must be in valid range (year 2000-2100)
    // This prevents date-like strings (e.g., "20251230") from being misinterpreted
    if let ts = Double(sinceStr) {
      let minValidTimestamp = 946684800.0  // 2000-01-01 00:00:00 UTC
      let maxValidTimestamp = 4102444800.0 // 2100-01-01 00:00:00 UTC
      if ts >= minValidTimestamp && ts <= maxValidTimestamp {
        return Date(timeIntervalSince1970: ts)
      }
      // Check if it's milliseconds (13+ digits)
      if ts >= minValidTimestamp * 1000 && ts <= maxValidTimestamp * 1000 {
        return Date(timeIntervalSince1970: ts / 1000)
      }
      // Numeric but not in valid range - fall through to date parsing
    }

    // Try ISO8601 formats
    let iso8601 = ISO8601DateFormatter()
    if let date = iso8601.date(from: sinceStr) { return date }

    // Try date-only format with timezone assumption (UTC)
    let dateOnly = DateFormatter()
    dateOnly.dateFormat = "yyyy-MM-dd"
    dateOnly.timeZone = TimeZone(identifier: "UTC")
    dateOnly.locale = Locale(identifier: "en_US_POSIX")
    if let date = dateOnly.date(from: sinceStr) { return date }

    throw ValidationError("""
      Invalid --since format: '\(sinceStr)'
      Accepted formats:
        - ISO8601: 2024-01-15T10:30:00Z
        - Date only: 2024-01-15 (interpreted as UTC midnight)
        - Unix timestamp (seconds): 1705312200
      """)
  }

  mutating func run() async throws {
    let runId = UUID().uuidString.prefix(8).lowercased()
    let startTime = Date()

    // Set up event sink
    let sinkFormat: CLIEventSink.OutputFormat = format == .jsonl ? .jsonl : .human
    let sink = CLIEventSink(format: sinkFormat)

    // Parse --since date if provided
    let sinceDate = try parseSinceDate()
    if let since = sinceDate, format == .human {
      let formatter = ISO8601DateFormatter()
      print("Filtering: only transcripts modified after \(formatter.string(from: since))")
    }

    // Warn about --workers not being implemented yet
    if workers != 4 && format == .human {
      print("Note: --workers is not yet implemented (parallel processing coming in a future release)")
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
        // Delete in dependency order (child tables first, then parents)
        // This ensures clean rebuild even if FK constraints are disabled
        try db.execute(sql: "DELETE FROM tool_invocations")
        try db.execute(sql: "DELETE FROM timeline_cache")
        try db.execute(sql: "DELETE FROM assistant_usage")
        try db.execute(sql: "DELETE FROM assistant_usage_pending")
        try db.execute(sql: "DELETE FROM transcript_metadata")
        try db.execute(sql: "DELETE FROM project_follow_policy")
        try db.execute(sql: "DELETE FROM transcript_entries")
        try db.execute(sql: "DELETE FROM transcripts")
        try db.execute(sql: "DELETE FROM projects")
        try db.execute(sql: "DELETE FROM ingestion_runs")
      }
    }

    // Create repositories for HooverEngine
    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let entryRepo = EntryRepositoryImpl(db: pool)
    let errorRepo = ParseErrorRepositoryImpl(db: pool)
    let fileSnapshotRepo = FileSnapshotRepositoryImpl(db: pool)
    let trackedFileRepo = TrackedFileRepositoryImpl(db: pool)
    let transcriptSummaryRepo = TranscriptSummaryRepositoryImpl(db: pool)
    let systemEventRepo = SystemEventRepositoryImpl(db: pool)
    let assistantUsageRepo = AssistantUsageRepositoryImpl(db: pool)

    // Create parser and metadata parser
    let parser = MultiProviderParser()
    let metadataParser = MultiProviderMetadataParser()

    // Create HooverEngine
    let hooverEngine = HooverEngine(
      db: pool,
      transcriptRepo: transcriptRepo,
      entryRepo: entryRepo,
      errorRepo: errorRepo,
      projectRepo: projectRepo,
      parser: parser,
      fileSnapshotRepo: fileSnapshotRepo,
      trackedFileRepo: trackedFileRepo,
      transcriptSummaryRepo: transcriptSummaryRepo,
      systemEventRepo: systemEventRepo,
      assistantUsageRepo: assistantUsageRepo,
      metadataParser: metadataParser
    )

    // Progress sink (no-op for CLI batch processing)
    let progressSink = NoOpProgressSink()

    // Discover transcripts
    var projects: [LightweightProject]
    if !input.isEmpty {
      // Use provided input paths
      projects = discoverFromInputPaths(input)
      if format == .human {
        print("Scanning \(input.count) custom input path(s)...")
      }
    } else {
      // Use default discovery
      let discovery = LightweightDiscoveryService()
      projects = await discovery.discoverProjectsLightweight()
    }

    // Filter by provider if specified
    if provider != .auto {
      let providerFilter = provider == .claude ? "claude.code" : "codex.cli"
      projects = projects.filter { $0.provider == providerFilter }
    }

    // Filter transcripts by --since if provided
    if let sinceDate = sinceDate {
      let sinceTimestamp = sinceDate.timeIntervalSince1970
      var filteredProjects: [LightweightProject] = []
      for project in projects {
        let filteredFiles = project.transcriptFiles.filter { url -> Bool in
          guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                let mtime = attrs[.modificationDate] as? Date else {
            return true  // Include if we can't determine mtime
          }
          return mtime.timeIntervalSince1970 >= sinceTimestamp
        }
        if !filteredFiles.isEmpty {
          // Create new project with filtered files (struct is immutable)
          let filtered = LightweightProject(
            id: project.id,
            path: project.path,
            displayName: project.displayName,
            transcriptCount: filteredFiles.count,
            lastActivity: project.lastActivity,
            provider: project.provider,
            cwd: project.cwd,
            transcriptFiles: filteredFiles
          )
          filteredProjects.append(filtered)
        }
      }
      projects = filteredProjects
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
    var totalEntriesInserted = 0
    var totalEntriesSkipped = 0

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

          // Upsert transcript record and get the transcript ID
          let transcriptId: String = try await pool.write { db -> String in
            // Check if transcript exists by (project_id, file_path)
            if let existingId = try String.fetchOne(db, sql: """
              SELECT id FROM transcripts WHERE project_id = ? AND file_path = ?
            """, arguments: [projectId, filePath]) {
              // Update existing
              try db.execute(sql: """
                UPDATE transcripts SET last_modified = ?, file_size = ?, updated_at = ?
                WHERE id = ?
              """, arguments: [lastModifiedInt, fileSize, runNow, existingId])
              return existingId
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
              return id
            }
          }

          // Fetch the full Transcript model for HooverEngine
          let transcript: Transcript? = try await pool.read { db in
            try Transcript.fetchOne(db, sql: "SELECT * FROM transcripts WHERE id = ?", arguments: [transcriptId])
          }

          guard let transcript = transcript else {
            sink.fileError(path: filePath, error: "Failed to fetch transcript after insert")
            totalErrors += 1
            continue
          }

          // Run HooverEngine to parse entries
          let outcome = try hooverEngine.hooverTranscript(
            transcript,
            fileURL: fileURL,
            progress: progressSink
          )

          totalEntriesInserted += outcome.entriesInserted
          totalEntriesSkipped += outcome.entriesSkipped
          transcriptsProcessed += 1

          if format == .human && outcome.entriesInserted > 0 {
            print("  \(fileURL.lastPathComponent): \(outcome.entriesInserted) entries")
          }

        } catch {
          sink.fileError(path: fileURL.path, error: error.localizedDescription)
          totalErrors += 1
        }
      }
    }

    let duration = Date().timeIntervalSince(startTime)

    let summary = IngestionSummary(
      transcriptsProcessed: transcriptsProcessed,
      entriesInserted: totalEntriesInserted,
      entriesSkipped: totalEntriesSkipped,
      errorsEncountered: totalErrors,
      durationSeconds: duration
    )
    sink.ingestionCompleted(runId: String(runId), success: totalErrors == 0, summary: summary)

    if format == .human {
      print("")
      print("Ingestion complete:")
      print("  Projects processed: \(projectsProcessed)")
      print("  Transcripts processed: \(transcriptsProcessed)")
      print("  Entries inserted: \(totalEntriesInserted)")
      print("  Entries skipped: \(totalEntriesSkipped)")
      print("  Errors: \(totalErrors)")
      print("  Duration: \(String(format: "%.2f", duration))s")
      print("")
      print("Database: \(db)")
      print("Use 'contextify-ingest verify --db \(db)' to verify the database.")
    }

    // Exit with non-zero code if errors occurred (for CI/script usage)
    if totalErrors > 0 {
      throw ExitCode.failure
    }
  }

  /// Discover transcripts from custom input paths
  private func discoverFromInputPaths(_ paths: [String]) -> [LightweightProject] {
    var projectMap: [String: LightweightProject] = [:]

    for pathStr in paths {
      let url = URL(fileURLWithPath: pathStr).standardizedFileURL
      let fm = FileManager.default

      // Check if path exists
      var isDir: ObjCBool = false
      guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
        continue
      }

      if isDir.boolValue {
        // Directory: scan for .jsonl files
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
          for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
              addTranscriptToProjects(fileURL, into: &projectMap)
            }
          }
        }
      } else if url.pathExtension == "jsonl" {
        // Single file
        addTranscriptToProjects(url, into: &projectMap)
      }
    }

    return Array(projectMap.values)
  }

  /// Add a transcript file to the appropriate project in the map
  private func addTranscriptToProjects(_ fileURL: URL, into projectMap: inout [String: LightweightProject]) {
    let filePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path

    // Derive project root and provider from path
    let (projectRoot, provider): (String, String)
    if let claudeRange = filePath.range(of: "/.claude/projects/") {
      // Claude: ~/.claude/projects/<project-name>/
      let afterProjects = String(filePath[claudeRange.upperBound...])
      let projectName = afterProjects.components(separatedBy: "/").first ?? "unknown"
      projectRoot = filePath.components(separatedBy: "/.claude/projects/").first! + "/.claude/projects/" + projectName
      provider = "claude.code"
    } else if filePath.contains("/.codex/sessions/") {
      // Codex: ~/.codex/sessions/ (flat structure, all in one "project")
      projectRoot = filePath.components(separatedBy: "/.codex/sessions/").first! + "/.codex/sessions"
      provider = "codex.cli"
    } else {
      // Unknown location: use parent directory as project root
      projectRoot = fileURL.deletingLastPathComponent().path
      provider = "other"
    }

    // Get or create project
    if let existingProject = projectMap[projectRoot] {
      // Create new project with added file (struct is immutable)
      var updatedFiles = existingProject.transcriptFiles
      updatedFiles.append(fileURL)
      let updated = LightweightProject(
        id: existingProject.id,
        path: existingProject.path,
        displayName: existingProject.displayName,
        transcriptCount: updatedFiles.count,
        lastActivity: existingProject.lastActivity,
        provider: existingProject.provider,
        cwd: existingProject.cwd,
        transcriptFiles: updatedFiles
      )
      projectMap[projectRoot] = updated
    } else {
      let displayName = URL(fileURLWithPath: projectRoot).lastPathComponent
      let projectURL = URL(fileURLWithPath: projectRoot)
      // Get file modification time for lastActivity
      let lastActivity: Date
      if let attrs = try? FileManager.default.attributesOfItem(atPath: projectRoot),
         let mtime = attrs[.modificationDate] as? Date {
        lastActivity = mtime
      } else {
        lastActivity = Date()
      }
      let project = LightweightProject(
        id: ProjectIdentity.computeProjectID(provider: provider, path: projectRoot),
        path: projectURL,
        displayName: displayName,
        transcriptCount: 1,
        lastActivity: lastActivity,
        provider: provider,
        cwd: nil,  // Will be derived from path
        transcriptFiles: [fileURL]
      )
      projectMap[projectRoot] = project
    }
  }
}
