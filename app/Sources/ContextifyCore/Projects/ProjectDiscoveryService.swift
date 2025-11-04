import Foundation
import GRDB
import OSLog

/// Service for discovering and managing Claude Code and Codex projects
public actor ProjectDiscoveryService {
  private let db: DatabasePool
  private let orchestrator: TranscriptOrchestrator
  private var ingestionErrors: [String: String] = [:]  // projectPath -> error message
  private let logger = Logger(subsystem: "dev.contextify", category: "ProjectDiscovery")

  public init(
    db: DatabasePool,
    orchestrator: TranscriptOrchestrator
  ) {
    self.db = db
    self.orchestrator = orchestrator
  }

  // MARK: - Public API

  /// Discovers all Claude Code and Codex projects
  /// - Parameter currentProjectPath: Path to the current project (for isCurrent flag)
  /// - Returns: Array of discovered projects with metadata
  public func discoverAllProjects(currentProjectPath: String?) async throws -> [DiscoveredProject] {
    logger.info("Starting project discovery")

    // Do not clear ingestionErrors here. We keep prior errors visible until a
    // subsequent successful ingest explicitly replaces them.

    // 1. Scan ~/.claude/projects/* for Claude Code projects
    let claudeProjects = try await discoverClaudeCodeProjects()
    logger.debug("Found \(claudeProjects.count) Claude Code project paths")

    var discovered: [DiscoveredProject] = []

    // 2. For each Claude project, get metadata and providers from database
    for projectPath in claudeProjects {
      // Get metadata from database (includes providers from ingested transcripts)
      let metadata = try await getProjectMetadata(projectId: projectPath.path)

      // Use database-backed providers
      var providers = metadata.providers

      // Because this project was found under ~/.claude/projects, ensure Claude is shown
      // even before first ingestion.
      if providers.isEmpty {
        providers.insert(.claudeCode)
      }

      // Determine display name
      let name = deriveProjectName(from: projectPath)

      discovered.append(DiscoveredProject(
        id: projectPath.path,
        name: name,
        path: projectPath,
        providers: providers,
        transcriptCount: metadata.transcriptCount,
        entryCount: metadata.entryCount,
        lastActivity: metadata.lastActivity,
        isCurrent: projectPath.path == currentProjectPath,
        ingestionError: ingestionErrors[projectPath.path],
        displayOrder: metadata.displayOrder
      ))
    }

    // 6. Sort by display_order (matching main window tab bar order)
    let sorted = discovered.sorted { lhs, rhs in
      // Primary: display_order ascending (matches ProjectSwitcherState sorting)
      if let lOrder = lhs.displayOrder, let rOrder = rhs.displayOrder {
        return lOrder < rOrder
      } else if lhs.displayOrder != nil {
        return true  // Projects with display_order come first
      } else if rhs.displayOrder != nil {
        return false
      } else {
        // Fallback: sort by last activity (most recent first) for unordered projects
        return (lhs.lastActivity ?? .distantPast) > (rhs.lastActivity ?? .distantPast)
      }
    }

    logger.info("Discovery complete: \(sorted.count) projects found")
    return sorted
  }

  /// Ingests all transcripts for all discovered projects
  /// - Parameters:
  ///   - projects: Array of project URLs to ingest
  ///   - progressHandler: Optional callback for progress updates
  public func ingestAllProjects(
    projects: [URL],
    progressHandler: (@Sendable (DiscoveryProgress) -> Void)? = nil
  ) async throws {
    logger.info("Starting ingestion for \(projects.count) projects")

    // Clear previous errors
    ingestionErrors.removeAll()

    let total = projects.count

    for (index, projectPath) in projects.enumerated() {
      let projectName = deriveProjectName(from: projectPath)

      // Send progress update
      progressHandler?(DiscoveryProgress(
        phase: .ingesting,
        currentProject: projectName,
        projectsCompleted: index + 1,
        projectsTotal: total,
        message: "Ingesting \(projectName)..."
      ))

      do {
        // Check if project has Claude Code transcripts
        if let claudeDir = claudeDir(for: projectPath) {
          try await ingestClaudeCodeTranscripts(for: projectPath, claudeDir: claudeDir)
        }

        // Check if project has Codex transcripts
        let codexDir = projectPath.appendingPathComponent(".codex/sessions")
        if FileManager.default.fileExists(atPath: codexDir.path) {
          try await ingestCodexTranscripts(for: projectPath, codexDir: codexDir)
        }

        logger.debug("Ingested project: \(projectName)")

        // Clear any previous error for this project
        ingestionErrors.removeValue(forKey: projectPath.path)

      } catch {
        logger.error("Failed to ingest project \(projectName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        // Store error for this project
        ingestionErrors[projectPath.path] = error.localizedDescription
        // Continue with other projects instead of failing
      }
    }

    // Send completion update
    progressHandler?(DiscoveryProgress(
      phase: .complete,
      projectsCompleted: total,
      projectsTotal: total,
      message: "Ingestion complete"
    ))

    let errorCount = ingestionErrors.count
    if errorCount > 0 {
      logger.warning("Ingestion complete with \(errorCount) errors")
    } else {
      logger.info("Ingestion complete for all projects")
    }
  }

  // MARK: - Private Discovery Methods

  /// Discovers Claude Code projects from ~/.claude/projects/
  private func discoverClaudeCodeProjects() async throws -> [URL] {
    let claudeProjectsDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/projects")

    guard FileManager.default.fileExists(atPath: claudeProjectsDir.path) else {
      logger.debug("Claude projects directory not found")
      return []
    }

    let subdirs = try FileManager.default.contentsOfDirectory(
      at: claudeProjectsDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

    // Convert directory URLs to project paths via JSONL inspection
    return subdirs.compactMap { dir in
      reversePathMapping(dirURL: dir)
    }
  }

  /// Reverses Claude Code directory name back to original project path
  /// Uses JSONL content inspection for robust path detection, with heuristic fallback
  private func reversePathMapping(dirURL: URL) -> URL? {
    let fm = FileManager.default

    // Try to find a JSONL file in this directory
    guard let jsonlFiles = try? fm.contentsOfDirectory(
      at: dirURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter({ $0.pathExtension == "jsonl" }),
          let jsonl = jsonlFiles.first else {
      logger.debug("No JSONL files in \(dirURL.lastPathComponent)")
      return nil
    }

    // Read first ~128KB of JSONL to find project path clues
    if let data = try? Data(contentsOf: jsonl, options: .mappedIfSafe),
       let text = String(data: data.prefix(131_072), encoding: .utf8) {

      // Look for common fields containing absolute paths
      let patterns = [
        #""(?:cwd|workspaceRoot|root|projectRoot)"\s*:\s*"(/[^"]+)""#,
        #""path"\s*:\s*"(/[^"]+)""#,
        #""file"\s*:\s*"(/[^"]+)""#
      ]

      for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
        let range = NSRange(text.startIndex..., in: text)

        if let match = regex.firstMatch(in: text, options: [], range: range),
           match.numberOfRanges >= 2 {
          let pathRange = match.range(at: 1)
          if let swiftRange = Range(pathRange, in: text) {
            let extractedPath = String(text[swiftRange])

            // Validate it's a directory that exists
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: extractedPath, isDirectory: &isDir), isDir.boolValue {
              logger.debug("Found project path via JSONL inspection: \(extractedPath)")
              return URL(fileURLWithPath: extractedPath)
            }

            // Try parent directories (in case we found a file path)
            var parent = URL(fileURLWithPath: extractedPath).deletingLastPathComponent()
            for _ in 0..<3 {
              if fm.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue {
                logger.debug("Found project path via parent traversal: \(parent.path)")
                return parent
              }
              parent = parent.deletingLastPathComponent()
            }
          }
        }
      }
    }

    // Fallback: use ProjectIdentity.reverseManglePath() if possible
    // This properly handles hyphens in directory names
    do {
      let path = try ProjectIdentity.reverseManglePath(provider: "claude.code", directory: dirURL)
      let url = URL(fileURLWithPath: path)
      logger.debug("Using fallback with proper demangling for: \(dirURL.lastPathComponent) → \(path)")
      return url
    } catch {
      logger.debug("Fallback failed: cannot reverse mangle (\(dirURL.lastPathComponent)): \(error)")
      return nil
    }
  }

  // NOTE: Provider presence is determined from the database (transcripts.provider).
  //       We no longer scan the filesystem for Codex. The hasCodexTranscripts() method
  //       has been removed in favor of database-backed detection.

  /// Derives a display name for a project
  private func deriveProjectName(from path: URL) -> String {
    // For MVP: use last path component
    // Future: could parse .git/config for repo name
    return path.lastPathComponent
  }

  /// Finds the Claude Code directory for a known project path
  /// Avoids lossy encoding by scanning and reverse-mapping all Claude dirs
  private func claudeDir(for projectPath: URL) -> URL? {
    let root = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/projects")

    guard let dirs = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
    else {
      logger.debug("Could not list Claude projects directory")
      return nil
    }

    logger.info("Searching for Claude dir matching: \(projectPath.path, privacy: .public)")
    logger.info("Scanning \(dirs.count) Claude directories")

    // Find the directory whose reverse mapping matches our project path
    for dir in dirs {
      if let mapped = reversePathMapping(dirURL: dir) {
        logger.info("  \(dir.lastPathComponent, privacy: .public) → \(mapped.path, privacy: .public)")
        if mapped.path == projectPath.path {
          logger.info("✅ Found match: \(dir.lastPathComponent, privacy: .public)")
          return dir
        }
      } else {
        logger.info("  \(dir.lastPathComponent, privacy: .public) → (failed to map)")
      }
    }

    logger.warning("❌ No Claude directory found for: \(projectPath.path, privacy: .public)")
    return nil
  }

  // MARK: - Database Queries

  /// Normalizes timestamp from database (handles both seconds and milliseconds)
  /// Timestamps > 10^12 are treated as milliseconds
  private static func normalizeTimestamp(_ raw: Int?) -> TimeInterval? {
    guard let v = raw else { return nil }
    // Treat values > 10^12 as milliseconds (e.g., 2025-epoch in ms ≈ 1.7e12)
    return TimeInterval(v > 1_000_000_000_000 ? v / 1000 : v)
  }

  private static func parseISO8601(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
  }

  /// Gets metadata for a single project from database
  /// - Parameter projectId: Either projects.id (UUID) or projects.root_path (absolute path)
  private func getProjectMetadata(projectId: String) async throws -> ProjectMetadata {
    try await db.read { db in
      // Join through projects table to support both UUID and path lookups
      let sql = """
        SELECT
          p.display_order,
          COUNT(DISTINCT t.id) AS transcript_count,
          COUNT(e.id) AS entry_count,
          MAX(e.timestamp) AS last_activity,
          GROUP_CONCAT(DISTINCT t.provider ORDER BY t.provider) AS providers
        FROM projects p
        LEFT JOIN transcripts t ON t.project_id = p.id
        LEFT JOIN transcript_entries e ON e.transcript_id = t.id
        WHERE p.id = ? OR p.root_path = ?
        GROUP BY p.id
        """

      guard let row = try Row.fetchOne(db, sql: sql, arguments: [projectId, projectId]) else {
        self.logger.notice("No metadata row found for project: \(projectId, privacy: .public)")
        return ProjectMetadata(
          projectId: projectId,
          transcriptCount: 0,
          entryCount: 0,
          lastActivity: nil,
          displayOrder: nil,
          providers: []
        )
      }

      let transcriptCount: Int = row["transcript_count"] ?? 0
      let entryCount: Int = row["entry_count"] ?? 0
      let displayOrder: Int? = row["display_order"]

      let lastActivity: Date? = {
        let dbValue: DatabaseValue = row["last_activity"]
        if let iso = String.fromDatabaseValue(dbValue), !iso.isEmpty,
           let parsed = Self.parseISO8601(iso) {
          return parsed
        }
        if let seconds = Int.fromDatabaseValue(dbValue) {
          return Self.normalizeTimestamp(seconds).map { Date(timeIntervalSince1970: $0) }
        }
        return nil
      }()

      // Parse provider set from CSV of raw values
      let providersCSV: String? = row["providers"]
      var providers: Set<DiscoveredProject.Provider> = []
      if let csv = providersCSV, !csv.isEmpty {
        for token in csv.split(separator: ",") {
          let raw = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
          if let p = DiscoveredProject.Provider(dbRaw: raw) ?? DiscoveredProject.Provider(rawValue: raw) {
            providers.insert(p)
          } else {
            providers.insert(.other)
          }
        }
      }

      self.logger.notice("Metadata for \(projectId, privacy: .public): \(transcriptCount) transcripts, \(entryCount) entries, providers: \(providers.map { $0.rawValue }.joined(separator: ", "))")

      return ProjectMetadata(
        projectId: projectId,
        transcriptCount: transcriptCount,
        entryCount: entryCount,
        lastActivity: lastActivity,
        displayOrder: displayOrder,
        providers: providers
      )
    }
  }

  // MARK: - Ingestion Methods

  /// Ingests Claude Code transcripts for a project
  private func ingestClaudeCodeTranscripts(for projectPath: URL, claudeDir: URL) async throws {
    let transcriptFiles = try FileManager.default.contentsOfDirectory(
      at: claudeDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "jsonl" }

    // Create project if it doesn't exist
    let projectId = try orchestrator.getOrCreateProject(
      name: deriveProjectName(from: projectPath),
      rootPath: projectPath.path
    )
    logger.info("Ingesting Claude transcripts for project_id: \(projectId, privacy: .public) (path: \(projectPath.path, privacy: .public))")

    // Prepare discovered transcripts
    let discovered = transcriptFiles.map { file in
      DiscoveredTranscript(
        fileURL: file,
        provider: .claudeCode,
        sessionId: file.deletingPathExtension().lastPathComponent
      )
    }

    // Batch upsert
    _ = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)
  }

  /// Ingests Codex transcripts for a project
  private func ingestCodexTranscripts(for projectPath: URL, codexDir: URL) async throws {
    let transcriptFiles = try FileManager.default.contentsOfDirectory(
      at: codexDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "jsonl" }

    // Create project if it doesn't exist
    let projectId = try orchestrator.getOrCreateProject(
      name: deriveProjectName(from: projectPath),
      rootPath: projectPath.path
    )

    // Prepare discovered transcripts
    let discovered = transcriptFiles.map { file in
      DiscoveredTranscript(
        fileURL: file,
        provider: .codexCLI,
        sessionId: file.deletingPathExtension().lastPathComponent
      )
    }

    // Batch upsert
    _ = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)
  }
}
