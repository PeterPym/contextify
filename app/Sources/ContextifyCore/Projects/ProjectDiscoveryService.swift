import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "ProjectDiscovery")

/// Service for discovering and managing Claude Code and Codex projects
public actor ProjectDiscoveryService {
  private let db: DatabasePool
  private let orchestrator: TranscriptOrchestrator
  private let exclusionManager: ProjectExclusionManager
  private var ingestionErrors: [String: String] = [:]  // projectPath -> error message

  public init(
    db: DatabasePool,
    orchestrator: TranscriptOrchestrator,
    exclusionManager: ProjectExclusionManager = ProjectExclusionManager()
  ) {
    self.db = db
    self.orchestrator = orchestrator
    self.exclusionManager = exclusionManager
  }

  // MARK: - Public API

  /// Discovers all Claude Code and Codex projects
  /// - Parameter currentProjectPath: Path to the current project (for isCurrent flag)
  /// - Returns: Array of discovered projects with metadata
  public func discoverAllProjects(currentProjectPath: String?) async throws -> [DiscoveredProject] {
    logger.info("Starting project discovery")

    // 1. Scan ~/.claude/projects/* for Claude Code projects
    let claudeProjects = try await discoverClaudeCodeProjects()
    logger.debug("Found \(claudeProjects.count) Claude Code project paths")

    // 2. Filter out excluded projects
    let excluded = await exclusionManager.getExcludedProjects()
    let filteredProjects = claudeProjects.filter { !excluded.contains($0.path) }

    if claudeProjects.count > filteredProjects.count {
      logger.debug("Filtered out \(claudeProjects.count - filteredProjects.count) excluded projects")
    }

    var discovered: [DiscoveredProject] = []

    // 3. For each Claude project, check if it also has Codex transcripts
    for projectPath in filteredProjects {
      var providers: Set<DiscoveredProject.Provider> = [.claudeCode]

      if hasCodexTranscripts(at: projectPath) {
        providers.insert(.codex)
      }

      // 4. Get metadata from database (if already ingested)
      let metadata = try await getProjectMetadata(projectId: projectPath.path)

      // 5. Determine display name
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
        ingestionError: ingestionErrors[projectPath.path]
      ))
    }

    // 6. Sort by last activity (most recent first)
    let sorted = discovered.sorted {
      ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
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
        projectsCompleted: index,
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
        logger.error("Failed to ingest project \(projectName): \(error.localizedDescription)")
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

    // Fallback: heuristic based on directory name
    // Only use if it produces a valid existing path
    let dirName = dirURL.lastPathComponent
    let guessedPath = dirName.replacingOccurrences(of: "-", with: "/")
    guard guessedPath.hasPrefix("/") else {
      logger.debug("Fallback failed: not absolute path (\(dirName))")
      return nil
    }

    let url = URL(fileURLWithPath: guessedPath)
    guard fm.fileExists(atPath: url.path) else {
      logger.debug("Fallback failed: path doesn't exist (\(guessedPath))")
      return nil
    }

    logger.debug("Using fallback heuristic for: \(dirName) → \(guessedPath)")
    return url
  }

  /// Checks if a project has Codex transcripts
  private func hasCodexTranscripts(at projectPath: URL) -> Bool {
    let codexDir = projectPath.appendingPathComponent(".codex/sessions")

    guard FileManager.default.fileExists(atPath: codexDir.path) else {
      return false
    }

    // Check if there are any .jsonl files
    let files = try? FileManager.default.contentsOfDirectory(
      at: codexDir,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "jsonl" }

    return !(files?.isEmpty ?? true)
  }

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
    else { return nil }

    // Find the directory whose reverse mapping matches our project path
    return dirs.first { reversePathMapping(dirURL: $0)?.path == projectPath.path }
  }

  // MARK: - Database Queries

  /// Gets metadata for a single project from database
  private func getProjectMetadata(projectId: String) async throws -> ProjectMetadata {
    try db.read { db in
      let sql = """
        SELECT
          COUNT(DISTINCT t.id) as transcript_count,
          COUNT(e.id) as entry_count,
          MAX(e.timestamp) as last_activity
        FROM transcripts t
        LEFT JOIN transcript_entries e ON t.id = e.transcript_id
        WHERE t.project_id = ?
        """

      guard let row = try Row.fetchOne(db, sql: sql, arguments: [projectId]) else {
        return ProjectMetadata(
          projectId: projectId,
          transcriptCount: 0,
          entryCount: 0,
          lastActivity: nil
        )
      }

      let transcriptCount: Int = row["transcript_count"] ?? 0
      let entryCount: Int = row["entry_count"] ?? 0
      let timestamp: Int? = row["last_activity"]
      let lastActivity = timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }

      return ProjectMetadata(
        projectId: projectId,
        transcriptCount: transcriptCount,
        entryCount: entryCount,
        lastActivity: lastActivity
      )
    }
  }

  // MARK: - Exclusion Management

  /// Excludes a project from future discovery
  public func excludeProject(_ projectPath: String) async {
    await exclusionManager.excludeProject(projectPath)
    logger.info("Excluded project: \(projectPath)")
  }

  /// Includes a previously excluded project
  public func includeProject(_ projectPath: String) async {
    await exclusionManager.includeProject(projectPath)
    logger.info("Included project: \(projectPath)")
  }

  /// Gets all excluded project paths
  public func getExcludedProjects() async -> Set<String> {
    await exclusionManager.getExcludedProjects()
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

    // Prepare discovered transcripts
    let discovered = transcriptFiles.map { file in
      DiscoveredTranscript(
        fileURL: file,
        provider: "claude.code",
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
        provider: "codex",
        sessionId: file.deletingPathExtension().lastPathComponent
      )
    }

    // Batch upsert
    _ = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)
  }
}
