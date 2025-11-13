import Foundation
import GRDB
import OSLog

/// Service for discovering and managing Claude Code and Codex projects
public actor ProjectDiscoveryService {
  private let db: DatabasePool
  private let orchestrator: TranscriptOrchestrator
  private let folderAccessController: FolderAccessController?  // Optional for backward compat
  private var ingestionErrors: [String: String] = [:]  // projectPath -> error message
  private let logger = Logger(subsystem: "dev.contextify", category: "ProjectDiscovery")

  public init(
    db: DatabasePool,
    orchestrator: TranscriptOrchestrator,
    folderAccessController: FolderAccessController? = nil
  ) {
    self.db = db
    self.orchestrator = orchestrator
    self.folderAccessController = folderAccessController
  }

  // MARK: - Security-Scoped Access Helpers

  /// Execute an operation with security-scoped access to ~/.claude/projects.
  ///
  /// **Sandboxed builds (App Store):**
  /// - Requires user to have granted folder authorization for Claude Code
  /// - Wraps operation in `FolderAccessController.withAccess()` to maintain security scope
  /// - Throws if authorization is missing or access is denied
  ///
  /// **Unsandboxed builds (DMG):**
  /// - Directly executes operation with raw filesystem path
  /// - No authorization required
  ///
  /// **CRITICAL:**
  /// All filesystem operations on ~/.claude/projects MUST happen inside this closure.
  /// URLs obtained inside this closure CANNOT be stored and used outside it -
  /// the security scope is released when the closure returns.
  private func withClaudeRoot<T>(
    _ operation: @Sendable (URL) throws -> T
  ) async throws -> T {
    guard let controller = folderAccessController else {
      // Non-sandboxed build: just call operation on the raw path
      let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
      return try operation(root)
    }

    // Sandboxed build: must use security-scoped access
    guard let auth = await controller.authorization(for: .claude),
          auth.status == .authorized else {
      logger.debug("No Claude authorization (sandboxed build requires user permission)")
      throw FolderAccessError.securityScopeAccessDenied(
        FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".claude/projects")
      )
    }

    return try await controller.withAccess(auth, operation)
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

    // 6. Pre-compute mtimes for sorting (async calls required for sandbox access)
    var mtimeCache: [URL: Date] = [:]
    for project in discovered {
      mtimeCache[project.path] = await getNewestTranscriptMtime(for: project.path)
    }

    // 7. Sort by newest transcript file modification time (filesystem-based)
    // This ensures projects with recent work appear first, even before ingestion
    let sorted = discovered.sorted { lhs, rhs in
      // Primary: display_order ascending (if set)
      if let lOrder = lhs.displayOrder, let rOrder = rhs.displayOrder {
        return lOrder < rOrder
      } else if lhs.displayOrder != nil {
        return true  // Projects with display_order come first
      } else if rhs.displayOrder != nil {
        return false
      } else {
        // Secondary: newest transcript file mtime (most recent first)
        let lhsMtime = mtimeCache[lhs.path] ?? Date.distantPast
        let rhsMtime = mtimeCache[rhs.path] ?? Date.distantPast
        return lhsMtime > rhsMtime  // Newest first
      }
    }

    logger.info("Discovery complete: \(sorted.count) projects found")

    // Log first 3 projects for debugging
    if !sorted.isEmpty {
      let top3 = sorted.prefix(3).map { "\($0.name) (mtime: \(mtimeCache[$0.path] ?? Date.distantPast))" }.joined(separator: ", ")
      logger.info("[DISCOVERY-ORDER] Top 3 by activity: \(top3, privacy: .public)")
    }

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
        if let claudeDir = await claudeDir(for: projectPath) {
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

    // Post notification that metadata discovery is complete
    // NOTE: This only upserts transcript records, actual hoovering happens via ProjectActivityMonitor
    await MainActor.run {
      NotificationCenter.default.post(name: .projectsIngestionComplete, object: nil)
    }
    logger.info("Posted .projectsIngestionComplete notification after metadata discovery (hoovering handled separately by ProjectActivityMonitor)")

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
    return try await withClaudeRoot { root in
      guard FileManager.default.fileExists(atPath: root.path) else {
        logger.debug("Claude projects directory not found at \(root.path)")
        return []
      }

      let subdirs = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

      // Convert directory URLs to project paths via JSONL inspection
      // This runs INSIDE the security scope, so reversePathMapping can read files
      return subdirs.compactMap { dir in
        reversePathMapping(dirURL: dir)
      }
    }
  }

  /// Discovers projects using authorized folder access (App Store sandbox)
  private func discoverWithAuthorization(
    source: SourceID,
    controller: FolderAccessController
  ) async throws -> [URL] {
    // Get authorization for this source
    guard let auth = await controller.authorization(for: source),
          auth.status == .authorized else {
      logger.info("No authorization for \(source.rawValue), skipping")
      return []
    }

    // Use security-scoped access
    return try await controller.withAccess(auth) { url in
      guard FileManager.default.fileExists(atPath: url.path) else {
        logger.debug("\(source.rawValue) directory not found at \(url.path)")
        return []
      }

      let subdirs = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

      return subdirs.compactMap { dir in
        reversePathMapping(dirURL: dir)
      }
    }
  }

  /// Reverses Claude Code directory name back to original project path
  /// Uses JSONL content inspection for robust path detection, with heuristic fallback
  private nonisolated func reversePathMapping(dirURL: URL) -> URL? {
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

  /// Sort projects by filesystem transcript modification time
  /// Public API for use by ProjectSwitcherState when display_order is NULL
  ///
  /// **Note:** This function is async because sandbox access requires security-scoped
  /// authorization to read transcript files for mtime comparison
  public func sortProjectsByFilesystemActivity(_ projectPaths: [String]) async -> [String] {
    // Pre-compute mtimes (required for sandbox access with withAccess)
    var mtimeCache: [String: Date] = [:]
    for path in projectPaths {
      let url = URL(fileURLWithPath: path)
      mtimeCache[path] = await getNewestTranscriptMtime(for: url)
    }

    return projectPaths.sorted { lhsPath, rhsPath in
      let lhsMtime = mtimeCache[lhsPath] ?? Date.distantPast
      let rhsMtime = mtimeCache[rhsPath] ?? Date.distantPast
      return lhsMtime > rhsMtime  // Newest first
    }
  }

  /// Gets the modification time of the newest transcript file for a project
  /// Used for sorting projects by most recent activity BEFORE ingestion
  private func getNewestTranscriptMtime(for projectPath: URL) async -> Date {
    let fm = FileManager.default

    // Get Claude Code transcript directory for this project
    guard let dir = await claudeDir(for: projectPath) else {
      return Date.distantPast
    }

    var newestTime = Date.distantPast

    // Find all .jsonl files in directory
    if let files = try? fm.contentsOfDirectory(
      at: dir,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) {
      for file in files where file.pathExtension == "jsonl" {
        if let resourceValues = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
           let mtime = resourceValues.contentModificationDate,
           mtime > newestTime {
          newestTime = mtime
        }
      }
    }

    return newestTime
  }

  /// Finds the Claude Code directory for a known project path
  /// Avoids lossy encoding by scanning and reverse-mapping all Claude dirs
  ///
  /// **App Sandbox Requirement:**
  /// In sandboxed builds (App Store), reading files requires security-scoped access.
  /// This function uses `FolderAccessController.withAccess()` to temporarily access
  /// `~/.claude/projects` with the user's granted permissions. Without this, the app
  /// would get EPERM errors when trying to list directories.
  ///
  /// **Control Flow:**
  /// 1. If folderAccessController exists (sandboxed build):
  ///    - Check if user has authorized Claude folder access
  ///    - Use `withAccess()` to read directory with security-scoped bookmark
  ///    - Scope is active only during the closure execution
  /// 2. If no controller (DMG build):
  ///    - Direct filesystem access (app is not sandboxed)
  ///
  /// - Returns: The Claude directory URL that maps to the project path, or nil if not found
  private func claudeDir(for projectPath: URL) async -> URL? {
    do {
      return try await withClaudeRoot { root in
        let dirs = try FileManager.default.contentsOfDirectory(
          at: root,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        logger.info("Searching for Claude dir matching: \(projectPath.path, privacy: .public)")

        // Find the directory whose reverse mapping matches our project path
        // All of this runs INSIDE the security scope
        for dir in dirs {
          if let decoded = reversePathMapping(dirURL: dir),
             decoded == projectPath {
            return dir
          }
        }
        return nil
      }
    } catch {
      logger.debug("Could not resolve Claude dir for \(projectPath.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return nil
    }
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
          MAX(e.created_ts) AS last_activity_ts,
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
        let dbValue: DatabaseValue = row["last_activity_ts"]
        // Parse epoch timestamp (created_ts is stored as INTEGER)
        if let epochSeconds = Double.fromDatabaseValue(dbValue) {
          return Date(timeIntervalSince1970: epochSeconds)
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
  ///
  /// **App Sandbox Requirement:**
  /// Transcript ingestion requires reading `.jsonl` files from `~/.claude/projects/<hash>/`.
  /// In sandboxed builds, this requires security-scoped access even though we already
  /// used it in `claudeDir()`. The security scope is ONLY active during the `withAccess`
  /// closure execution, so we must use it again here when actually reading files.
  ///
  /// **Why we need withAccess twice (discovery + ingestion):**
  /// 1. Discovery phase: Read directory names to find project mappings
  /// 2. Ingestion phase: Read .jsonl file contents for database import
  ///
  /// Each phase needs its own `withAccess` call because the scope is released
  /// when the closure returns. You cannot "save" a URL from one withAccess call
  /// and use it in another - the scope will have been released.
  private func ingestClaudeCodeTranscripts(for projectPath: URL, claudeDir: URL) async throws {
    // SANDBOXED PATH: Use security-scoped access to read transcript files
    let transcriptFiles: [URL]
    if let controller = folderAccessController {
      guard let auth = await controller.authorization(for: .claude),
            auth.status == .authorized else {
        logger.debug("No Claude authorization for transcript ingestion (sandboxed build)")
        return
      }

      // CRITICAL: Read file list INSIDE withAccess closure
      // We already used withAccess in claudeDir(), but that scope is now released
      // We need a new scope to actually read the transcript files
      transcriptFiles = try await controller.withAccess(auth) { _ in
        try FileManager.default.contentsOfDirectory(
          at: claudeDir,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }
      }
    } else {
      // NON-SANDBOXED PATH: DMG builds have direct filesystem access
      transcriptFiles = try FileManager.default.contentsOfDirectory(
        at: claudeDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ).filter { $0.pathExtension == "jsonl" }
    }

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
