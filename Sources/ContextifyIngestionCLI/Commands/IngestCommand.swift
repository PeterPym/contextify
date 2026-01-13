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

public struct IngestCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "ingest",
    abstract: "Index new transcripts into the database",
    discussion: """
      Scans for Claude Code and Codex CLI transcripts and indexes them into
      the Contextify database for full-text search.

      EXAMPLES:
        contextify ingest                    # Index using defaults
        contextify ingest --quiet            # Silent mode for cron/systemd
        contextify ingest --db ~/custom.db   # Custom database location

      DATABASE LOCATION (in order of precedence):
        1. --db flag
        2. CONTEXTIFY_DB_PATH environment variable
        3. XDG_DATA_HOME/contextify/contextify.db
        4. ~/.local/share/contextify/contextify.db
      """
  )

  @Option(name: .long, help: "Path to the SQLite database file (default: XDG location)")
  public var db: String?

  @Flag(name: .shortAndLong, help: "Suppress non-error output")
  public var quiet: Bool = false

  @Flag(name: .long, help: "Output format for systemd journal (summary line only)")
  public var systemd: Bool = false

  @Option(name: .long, parsing: .upToNextOption, help: "Input directories to scan for transcripts")
  public var input: [String] = []

  @Option(name: .long, help: "Transcript provider: auto, claude, or codex")
  public var provider: ProviderOption = .auto

  @Flag(name: .long, help: "Delete existing data and rebuild from scratch")
  public var fullRebuild: Bool = false

  @Option(name: .long, help: "Output format: jsonl or human")
  public var format: OutputFormat = .human

  @Option(name: .long, help: "Only process transcripts modified after this time (ISO8601 or Unix timestamp)")
  public var since: String?

  @Option(name: .long, help: "Number of parallel workers for transcript processing (default: 4)")
  public var workers: Int = 4

  public enum ProviderOption: String, ExpressibleByArgument {
    case auto, claude, codex
  }

  public enum OutputFormat: String, ExpressibleByArgument {
    case jsonl, human
  }

  public init() {}

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

  public mutating func run() async throws {
    let runId = UUID().uuidString.prefix(8).lowercased()
    let startTime = Date()

    // Resolve database path (--db > env var > XDG default)
    let dbPath = resolveDatabasePath()

    // Ensure parent directory exists with secure permissions
    let dbDir = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
    if !XDGPaths.ensureSecureDirectory(dbDir) {
      throw ExitCode.failure
    }

    // Determine output verbosity
    let isQuiet = quiet || systemd
    let showHumanOutput = format == .human && !isQuiet

    // Set up event sink (only for non-quiet jsonl output)
    let sinkFormat: CLIEventSink.OutputFormat = format == .jsonl ? .jsonl : .human
    let sink = isQuiet ? CLIEventSink(format: .human) : CLIEventSink(format: sinkFormat)

    // Parse --since date if provided
    let sinceDate = try parseSinceDate()
    if let since = sinceDate, showHumanOutput {
      let formatter = ISO8601DateFormatter()
      print("Filtering: only transcripts modified after \(formatter.string(from: since))")
    }

    // Warn about --workers not being implemented yet
    if workers != 4 && showHumanOutput {
      print("Note: --workers is not yet implemented (parallel processing coming in a future release)")
    }

    // Open database with FTS5 preflight
    let pool: DatabasePool
    do {
      pool = try DatabaseOpener.openDatabase(at: dbPath)
    } catch let error as DatabaseOpener.CLIError {
      sink.fileError(path: dbPath, error: error.localizedDescription)
      throw ExitCode.failure
    }

    // Tighten DB file permissions immediately after creation (reduces exposure window)
    XDGPaths.setSecureDatabasePermissions(URL(fileURLWithPath: dbPath))

    // Handle full rebuild
    if fullRebuild {
      if showHumanOutput {
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
      if showHumanOutput {
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

    if showHumanOutput {
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

        if showHumanOutput {
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

          if showHumanOutput && outcome.entriesInserted > 0 {
            print("  \(fileURL.lastPathComponent): \(outcome.entriesInserted) entries")
          }

        } catch {
          sink.fileError(path: fileURL.path, error: error.localizedDescription)
          totalErrors += 1
        }
      }
    }

    let duration = Date().timeIntervalSince(startTime)

    // Secure database file and sidecars (WAL/SHM) permissions
    XDGPaths.setSecureDatabasePermissions(URL(fileURLWithPath: dbPath))

    let summary = IngestionSummary(
      transcriptsProcessed: transcriptsProcessed,
      entriesInserted: totalEntriesInserted,
      entriesSkipped: totalEntriesSkipped,
      errorsEncountered: totalErrors,
      durationSeconds: duration
    )

    // Emit completion event (for jsonl format when not quiet)
    if !isQuiet {
      sink.ingestionCompleted(runId: String(runId), success: totalErrors == 0, summary: summary)
    }

    // Output based on mode
    if systemd {
      // Single summary line for systemd journal
      print("Ingested \(totalEntriesInserted) entries from \(transcriptsProcessed) transcripts (\(totalErrors) errors)")
    } else if showHumanOutput {
      print("")
      print("Ingestion complete:")
      print("  Projects processed: \(projectsProcessed)")
      print("  Transcripts processed: \(transcriptsProcessed)")
      print("  Entries inserted: \(totalEntriesInserted)")
      print("  Entries skipped: \(totalEntriesSkipped)")
      print("  Errors: \(totalErrors)")
      print("  Duration: \(String(format: "%.2f", duration))s")
      print("")
      print("Database: \(dbPath)")
      print("Use 'contextify verify --db \(dbPath)' to verify the database.")
    }

    // Exit codes: 0=success, 1=error, 2=noop
    if totalErrors > 0 {
      throw ExitCode.failure
    }
    if totalEntriesInserted == 0 && transcriptsProcessed == 0 {
      // Nothing to do - exit code 2 for scripts
      throw ExitCode(CLIExitCode.noop.rawValue)
    }
  }

  /// Resolve database path using precedence: --db > env var > XDG default
  private func resolveDatabasePath() -> String {
    if let dbFlag = db {
      // Expand tilde in user-provided path
      return XDGPaths.expandTilde(dbFlag)
    }
    return XDGPaths.databasePath.path
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
