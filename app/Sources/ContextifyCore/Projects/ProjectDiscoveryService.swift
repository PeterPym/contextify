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
  private var codexIndexCache: CachedCodexIndex?
  private var codexProjectEntries: [String: CodexIndex.ProjectEntry] = [:]

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
  /// **CRITICAL - Security Scope Rules:**
  /// - URLs obtained inside this closure may be stored for later use
  /// - Storing these URLs is only safe as *identifiers*; they do NOT carry an active security scope
  /// - However, any FileManager operations (reading, writing, listing) on those URLs
  ///   MUST occur inside a future `withClaudeRoot` or `withAccess` call
  /// - The security scope is released when the closure returns
  /// - Do NOT call FileManager APIs on these URLs outside a security scope
  private func withClaudeRoot<T>(
    _ operation: @Sendable (URL) throws -> T
  ) async throws -> T where T: Sendable {
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

  /// Execute an operation with security-scoped access to ~/.codex/sessions.
  private func withCodexRoot<T>(
    _ operation: @Sendable (URL) throws -> T
  ) async throws -> T where T: Sendable {
    let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/sessions")

    guard let controller = folderAccessController else {
      return try operation(defaultRoot)
    }

    guard let auth = await controller.authorization(for: .codex),
          auth.status == .authorized else {
      logger.debug("No Codex authorization (sandboxed build requires user permission)")
      throw FolderAccessError.securityScopeAccessDenied(defaultRoot)
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

    // Merge Claude + Codex projects keyed by normalized path
    var mergedProjects: [String: DiscoveredProject] = [:]
    var overrideMtimes: [String: Date] = [:]

    for project in discovered {
      mergedProjects[normalizedKey(for: project.path.path)] = project
    }

    if let codexIndex = await loadCodexIndex() {
      for (normalizedPath, entry) in codexIndex.projects {
        let projectURL = URL(fileURLWithPath: normalizedPath)
        let metadata = try await getProjectMetadata(projectId: normalizedPath)
        var providers = metadata.providers
        providers.insert(.codexCLI)
        let isCurrent = projectURL.path == currentProjectPath

        if let existing = mergedProjects[normalizedPath] {
          let combinedProviders = existing.providers.union(providers)
          let transcriptCount = max(existing.transcriptCount, metadata.transcriptCount)
          let entryCount = max(existing.entryCount, metadata.entryCount)
          let lastActivity = maxDate(existing.lastActivity, maxDate(metadata.lastActivity, entry.latestMtime))
          let displayOrder = existing.displayOrder ?? metadata.displayOrder

          mergedProjects[normalizedPath] = DiscoveredProject(
            id: existing.id,
            name: existing.name,
            path: existing.path,
            providers: combinedProviders,
            transcriptCount: transcriptCount,
            entryCount: entryCount,
            lastActivity: lastActivity,
            isCurrent: existing.isCurrent || isCurrent,
            ingestionError: existing.ingestionError,
            displayOrder: displayOrder
          )
        } else {
          let project = DiscoveredProject(
            id: projectURL.path,
            name: deriveProjectName(from: projectURL),
            path: projectURL,
            providers: providers,
            transcriptCount: metadata.transcriptCount,
            entryCount: metadata.entryCount,
            lastActivity: entry.latestMtime ?? metadata.lastActivity,
            isCurrent: isCurrent,
            ingestionError: ingestionErrors[projectURL.path],
            displayOrder: metadata.displayOrder
          )
          mergedProjects[normalizedPath] = project
        }

        if let latest = entry.latestMtime {
          overrideMtimes[normalizedPath] = latest
        }
      }
    } else {
      codexProjectEntries = [:]
    }

    let mergedList = Array(mergedProjects.values)

    // Pre-compute mtimes for sorting (async calls required for sandbox access)
    var mtimeCache: [String: Date] = [:]
    for project in mergedList {
      let key = normalizedKey(for: project.path.path)
      if let override = overrideMtimes[key] {
        mtimeCache[key] = override
      } else {
        mtimeCache[key] = await getNewestTranscriptMtime(for: project.path)
      }
    }

    // Sort by display_order, then newest activity, then name
    let sorted = mergedList.sorted { lhs, rhs in
      if let lOrder = lhs.displayOrder, let rOrder = rhs.displayOrder, lOrder != rOrder {
        return lOrder < rOrder
      }

      let lhsKey = normalizedKey(for: lhs.path.path)
      let rhsKey = normalizedKey(for: rhs.path.path)
      let lhsMtime = mtimeCache[lhsKey] ?? Date.distantPast
      let rhsMtime = mtimeCache[rhsKey] ?? Date.distantPast
      if lhsMtime != rhsMtime {
        return lhsMtime > rhsMtime
      }

      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    logger.info("Discovery complete: \(sorted.count) projects found")

    // Log first 3 projects for debugging
    if !sorted.isEmpty {
      let top3 = sorted.prefix(3).map { project -> String in
        let key = normalizedKey(for: project.path.path)
        let mtime = mtimeCache[key] ?? Date.distantPast
        return "\(project.name) (mtime: \(mtime))"
      }.joined(separator: ", ")
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
        let normalizedProject = normalizedKey(for: projectPath.path)
        if let codexEntry = codexProjectEntries[normalizedProject], !codexEntry.files.isEmpty {
          try await ingestCodexTranscripts(for: projectPath, codexFiles: codexEntry.files)
        } else {
          let codexDir = projectPath.appendingPathComponent(".codex/sessions")
          if FileManager.default.fileExists(atPath: codexDir.path) {
            try await ingestCodexTranscriptsInDirectory(for: projectPath, codexDir: codexDir)
          }
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

  /// Build or return cached Codex discovery index
  private func loadCodexIndex(forceRefresh: Bool = false) async -> CodexIndex? {
    if !forceRefresh,
       let cached = codexIndexCache,
       Date().timeIntervalSince(cached.timestamp) < 300 {
      logger.debug("[CODEX-INDEX-CACHE] Using cached Codex index (projects=\(cached.index.projects.count, privacy: .public))")
      codexProjectEntries = cached.index.projects
      return cached.index
    }

    do {
      let index = try await withCodexRoot { root in
        try CodexIndexBuilder.build(at: root)
      }

      codexIndexCache = CachedCodexIndex(index: index, timestamp: Date())
      codexProjectEntries = index.projects

      if index.projects.isEmpty {
        logger.debug("[CODEX-INDEX] No Codex sessions discovered")
        return nil
      } else {
        logger.info("[CODEX-INDEX-DONE] projects=\(index.projects.count, privacy: .public) files=\(index.totalFiles, privacy: .public) errors=\(index.errorCount, privacy: .public) duration_ms=\(Int(index.duration * 1000), privacy: .public)")
        return index
      }
    } catch {
      logger.info("[CODEX-INDEX-SKIP] \(error.localizedDescription, privacy: .public)")
      codexProjectEntries = [:]
      return nil
    }
  }

  private func normalizedKey(for path: String) -> String {
    PathNormalizer.normalize(path)
  }

  private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case let (l?, r?):
      return l > r ? l : r
    case (let l?, nil):
      return l
    case (nil, let r?):
      return r
    default:
      return nil
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
    do {
      return try await withClaudeRoot { root in
        // Same logic as claudeDir(for:), but computing mtimes instead
        let dirs = try FileManager.default.contentsOfDirectory(
          at: root,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        // Find the matching project dir
        guard let dir = dirs.first(where: { reversePathMapping(dirURL: $0) == projectPath }) else {
          return Date.distantPast
        }

        // Find all .jsonl files and get newest mtime
        let files = try FileManager.default.contentsOfDirectory(
          at: dir,
          includingPropertiesForKeys: [.contentModificationDateKey],
          options: [.skipsHiddenFiles]
        )

        let mtimes = files.compactMap {
          (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return mtimes.max() ?? Date.distantPast
      }
    } catch {
      logger.debug("Failed to compute mtime for \(projectPath.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return Date.distantPast
    }
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
    // CRITICAL: Each phase needs its own withAccess() call because the scope is released
    // when the closure returns. We cannot use URLs obtained in earlier phases (like
    // claudeDir from discovery) - we must re-enter the scope for ingestion.
    let transcriptFiles = try await withClaudeRoot { _ in
      try FileManager.default.contentsOfDirectory(
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
    // Note: We store the file URLs in the database, but don't read them here
    // HooverEngine will re-enter security scope when actually reading file contents
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

  /// Ingest Codex transcripts discovered via the global ~/.codex/sessions index
  private func ingestCodexTranscripts(for projectPath: URL, codexFiles: [CodexIndex.FileRecord]) async throws {
    guard !codexFiles.isEmpty else { return }

    let discovered: [DiscoveredTranscript]
    do {
      discovered = try await resolveCodexTranscripts(from: codexFiles)
    } catch {
      logger.error("Failed to resolve Codex transcripts for \(projectPath.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return
    }

    guard !discovered.isEmpty else { return }

    let projectId = try orchestrator.getOrCreateProject(
      name: deriveProjectName(from: projectPath),
      rootPath: projectPath.path
    )
    logger.info("Ingesting Codex transcripts for project_id: \(projectId, privacy: .public) (path: \(projectPath.path, privacy: .public)) via global index")

    _ = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)
  }

  private func resolveCodexTranscripts(from records: [CodexIndex.FileRecord]) async throws -> [DiscoveredTranscript] {
    try await withCodexRoot { root in
      records.compactMap { record in
        let fileURL = root.appendingPathComponent(record.relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          self.logger.debug("[CODEX-INGEST-SKIP] Missing file \(record.relativePath, privacy: .public)")
          return nil
        }

        return DiscoveredTranscript(
          fileURL: fileURL,
          provider: .codexCLI,
          sessionId: record.sessionId
        )
      }
    }
  }

  /// Legacy ingestion path for Codex transcripts stored inside the project directory
  private func ingestCodexTranscriptsInDirectory(for projectPath: URL, codexDir: URL) async throws {
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

private struct CachedCodexIndex {
  let index: CodexIndex
  let timestamp: Date
}

private enum CodexIndexBuilder {
  private static let log = Logger(subsystem: "dev.contextify", category: "ProjectDiscovery.CodexIndex")

  static func build(at root: URL) throws -> CodexIndex {
    guard FileManager.default.fileExists(atPath: root.path) else {
      log.debug("[CODEX-INDEX] Root not found at \(root.path)")
      return CodexIndex(projects: [:], totalFiles: 0, errorCount: 0, duration: 0)
    }

    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      log.warning("[CODEX-INDEX] Failed to create enumerator for \(root.path)")
      return CodexIndex(projects: [:], totalFiles: 0, errorCount: 0, duration: 0)
    }

    var projects: [String: CodexIndex.ProjectEntry] = [:]
    var fileCount = 0
    var parseErrors = 0
    let start = Date()

    for case let fileURL as URL in enumerator {
      guard fileURL.pathExtension == "jsonl" else { continue }

      let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
      guard resourceValues?.isRegularFile == true else { continue }

      fileCount += 1

      guard let firstLine = readFirstLine(of: fileURL),
            let meta = parseCodexSessionMeta(from: firstLine) else {
        parseErrors += 1
        continue
      }

      let normalizedPath = meta.cwd
      let relativePath = relativeCodexPath(for: fileURL, root: root)
      let mtime = resourceValues?.contentModificationDate ?? Date.distantPast

      var entry = projects[normalizedPath] ?? CodexIndex.ProjectEntry()
      entry.files.append(CodexIndex.FileRecord(relativePath: relativePath, sessionId: meta.sessionId, mtime: mtime))
      entry.files.sort { $0.mtime > $1.mtime }
      if entry.files.count > 1000 {
        entry.files = Array(entry.files.prefix(1000))
      }
      if let existingMtime = entry.latestMtime {
        entry.latestMtime = max(existingMtime, mtime)
      } else {
        entry.latestMtime = mtime
      }
      projects[normalizedPath] = entry
    }

    return CodexIndex(
      projects: projects,
      totalFiles: fileCount,
      errorCount: parseErrors,
      duration: Date().timeIntervalSince(start)
    )
  }

  private static func parseCodexSessionMeta(from line: String) -> (cwd: String, sessionId: String)? {
    guard let data = line.data(using: .utf8) else { return nil }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    guard let type = json["type"] as? String,
          type.lowercased() == "session_meta",
          let payload = json["payload"] as? [String: Any],
          let rawCwd = payload["cwd"] as? String else {
      return nil
    }

    let sessionId = (payload["id"] as? String) ??
      (payload["sessionId"] as? String) ??
      UUID().uuidString

    return (cwd: PathNormalizer.normalize(rawCwd), sessionId: sessionId)
  }

  private static func relativeCodexPath(for file: URL, root: URL) -> String {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    var fullPath = file.path
    if fullPath.hasPrefix(rootPath) {
      fullPath.removeFirst(rootPath.count)
    } else if fullPath.hasPrefix(root.path) {
      fullPath.removeFirst(root.path.count)
      if fullPath.hasPrefix("/") {
        fullPath.removeFirst()
      }
    }
    return fullPath
  }

  private static func readFirstLine(of fileURL: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
    defer { try? handle.close() }

    var buffer = Data()
    while true {
      guard let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty else {
        break
      }

      if let newlineIndex = chunk.firstIndex(of: UInt8(ascii: "\n")) {
        buffer.append(chunk.prefix(upTo: newlineIndex))
        break
      } else {
        buffer.append(chunk)
        if buffer.count > 262_144 {
          break
        }
      }
    }

    guard !buffer.isEmpty else { return nil }
    return String(data: buffer, encoding: .utf8)
  }
}
