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

  private func withCodexRoot<T>(
    _ operation: @Sendable (URL) throws -> T
  ) async throws -> T where T: Sendable {
    guard let controller = folderAccessController else {
      // Non-sandboxed build: just call operation on the raw path
      let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")
      return try operation(root)
    }

    // Sandboxed build: must use security-scoped access
    guard let auth = await controller.authorization(for: .codex),
          auth.status == .authorized else {
      logger.debug("No Codex authorization (sandboxed build requires user permission)")
      throw FolderAccessError.securityScopeAccessDenied(
        FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".codex/sessions")
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
    let sanitizedCurrentPath = SandboxPathFilter.sanitizedPath(currentProjectPath)

    // Do not clear ingestionErrors here. We keep prior errors visible until a
    // subsequent successful ingest explicitly replaces them.

    // 1. Scan ~/.claude/projects/* for Claude Code projects
    let claudeProjects = try await discoverClaudeCodeProjects()
    logger.debug("Found \(claudeProjects.count) Claude Code project paths")

    var discovered: [DiscoveredProject] = []

    // 2. For each Claude project, get metadata and providers from database
    for projectPath in claudeProjects {
      if SandboxPathFilter.isSandboxContainerPath(projectPath.path) {
        logger.info("[DISCOVERY-FILTER] Skipping sandbox container project: \(projectPath.path, privacy: .public)")
        continue
      }
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
        isCurrent: projectPath.path == sanitizedCurrentPath,
        ingestionError: ingestionErrors[projectPath.path],
        displayOrder: metadata.displayOrder
      ))
    }

    // 6. Pre-compute mtimes for sorting (async calls required for sandbox access)
    // Use task group for parallel retrieval (16x speedup on 16 projects)
    var mtimeCache: [URL: Date] = [:]
    await withTaskGroup(of: (URL, Date).self) { group in
      for project in discovered {
        group.addTask {
          let mtime = await self.getNewestTranscriptMtime(for: project.path)
          return (project.path, mtime)
        }
      }

      for await (path, mtime) in group {
        mtimeCache[path] = mtime
      }
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

  // MARK: - Quick Discovery (Phase 2)

  /// Quickly identifies the project with the newest transcript file without full ingestion.
  ///
  /// This performs a lightweight filesystem scan to find the most recently modified transcript
  /// across all Claude Code and Codex CLI projects. Used during startup to switch to the correct
  /// project before timeline primer runs.
  ///
  /// **Performance:**
  /// - Target: <500ms for typical setups (10-20 projects)
  /// - Scans both ~/.claude/projects and ~/.codex/sessions
  /// - No JSONL parsing, no DB writes
  /// - All FileManager ops happen synchronously inside security scope
  ///
  /// **Security:**
  /// - Requires security-scoped access in sandboxed builds
  /// - Uses same `withClaudeRoot` pattern as full discovery
  ///
  /// - Returns: Tuple of (project path, transcript file, newest mtime) or nil if no transcripts found
  public func quickDiscoverNewest() async -> (projectPath: URL, transcriptFile: URL, mtime: Date)? {
    let startTime = Date()
    logger.info("[QUICK-DISCOVERY-START] Scanning for newest transcript")

    do {
      var allCandidates: [(projectPath: URL, transcriptFile: URL, mtime: Date)] = []

      // PART 1: Scan Claude Code projects (~/.claude/projects)
      // IMPORTANT: All FileManager operations must happen synchronously inside this closure
      // Handle authorization errors gracefully (sandboxed builds need user permission first)
      let claudeCandidates: [(projectPath: URL, transcriptFile: URL, mtime: Date)]
      do {
        claudeCandidates = try await withClaudeRoot { root in
        guard FileManager.default.fileExists(atPath: root.path) else {
          logger.debug("[QUICK-DISCOVERY] Claude projects directory not found")
          return [(projectPath: URL, transcriptFile: URL, mtime: Date)]()
        }

        let projectDirs = try FileManager.default.contentsOfDirectory(
          at: root,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        logger.info("[QUICK-DISCOVERY] Found \(projectDirs.count) Claude project directories")

        // For each directory, find newest .jsonl file (synchronously)
        var results: [(projectPath: URL, transcriptFile: URL, mtime: Date)] = []

        for claudeDir in projectDirs {
          // Reverse map to project path
          guard let projectPath = reversePathMapping(dirURL: claudeDir) else {
            logger.debug("[QUICK-DISCOVERY-SCAN] Could not reverse map: \(claudeDir.lastPathComponent)")
            continue
          }

          // Find all .jsonl files with mtimes
          guard let files = try? FileManager.default.contentsOfDirectory(
            at: claudeDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
          ).filter({ $0.pathExtension == "jsonl" }), !files.isEmpty else {
            continue
          }

          // Find the file with newest mtime
          let filesWithMtimes = files.compactMap { file -> (URL, Date)? in
            guard let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
              return nil
            }
            return (file, mtime)
          }

          if let newestFile = filesWithMtimes.max(by: { $0.1 < $1.1 }) {
            results.append((projectPath, newestFile.0, newestFile.1))
          }
        }

          return results
        }
      } catch {
        // Authorization not granted yet (sandboxed build during first launch)
        // This is expected - user will grant permission via welcome modal
        logger.debug("[QUICK-DISCOVERY] Claude scan skipped (no authorization): \(error.localizedDescription, privacy: .public)")
        claudeCandidates = []
      }

      allCandidates.append(contentsOf: claudeCandidates)

      // PART 2: Scan Codex CLI transcripts (~/.codex/sessions/YYYY/MM/DD/*.jsonl)
      // Codex transcripts contain `cwd` field - need to parse JSONL for project path
      // Handle authorization errors gracefully (sandboxed builds need user permission first)
      let codexCandidates: [(projectPath: URL, transcriptFile: URL, mtime: Date)]
      do {
        codexCandidates = try await withCodexRoot { codexRoot in
          guard FileManager.default.fileExists(atPath: codexRoot.path) else {
            logger.debug("[QUICK-DISCOVERY] Codex sessions directory not found")
            return []
          }

          logger.info("[QUICK-DISCOVERY] Scanning Codex sessions")

          // Recursively find all .jsonl files (up to 3 levels: YYYY/MM/DD)
          let codexFiles: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: codexRoot,
          includingPropertiesForKeys: [.contentModificationDateKey],
          options: []
        ).flatMap { yearDir -> [URL] in
          guard (try? yearDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [] }

          return (try? FileManager.default.contentsOfDirectory(at: yearDir, includingPropertiesForKeys: [.contentModificationDateKey], options: []))?.flatMap { monthDir -> [URL] in
            guard (try? monthDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [] }

            return (try? FileManager.default.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: [.contentModificationDateKey], options: []))?.flatMap { dayDir -> [URL] in
              guard (try? dayDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [] }

              return (try? FileManager.default.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]))?.filter { $0.pathExtension == "jsonl" } ?? []
            } ?? []
          } ?? []
        }) ?? []

        logger.info("[QUICK-DISCOVERY] Found \(codexFiles.count) Codex transcript files")

        // Group by project path (extracted from cwd field) and find newest file per project
        var codexProjectNewest: [String: (file: URL, mtime: Date)] = [:]

        for file in codexFiles {
          // Get file mtime
          guard let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            continue
          }

          // Extract project path using same logic as full discovery
          // This handles both Claude Code (cwd) and Codex (payload.cwd) formats
          // and reads up to 64KB instead of just 1KB
          guard let cwd = try? ProjectIdentity.extractCwdFromTranscriptForOrphaned(file) else {
            logger.debug("[QUICK-DISCOVERY-CODEX] No CWD found in: \(file.lastPathComponent, privacy: .public)")
            continue
          }

          // Track newest file and mtime for this project
          if let existing = codexProjectNewest[cwd] {
            if mtime > existing.mtime {
              codexProjectNewest[cwd] = (file, mtime)
            }
          } else {
            codexProjectNewest[cwd] = (file, mtime)
          }
        }

          // Convert to candidates and return
          var candidates: [(projectPath: URL, transcriptFile: URL, mtime: Date)] = []
          for (projectPath, newest) in codexProjectNewest {
            candidates.append((URL(fileURLWithPath: projectPath), newest.file, newest.mtime))
          }

          logger.info("[QUICK-DISCOVERY] Found \(codexProjectNewest.count) unique Codex projects")

          // Log first 3 projects for validation
          for (projectPath, newest) in codexProjectNewest.prefix(3) {
            logger.debug("[QUICK-DISCOVERY-CODEX] Project: \(projectPath, privacy: .public) newest: \(newest.file.lastPathComponent, privacy: .public) mtime: \(newest.mtime, privacy: .public)")
          }

          return candidates
        }
      } catch {
        // Authorization not granted yet (sandboxed build during first launch)
        // This is expected - user will grant permission via welcome modal
        logger.debug("[QUICK-DISCOVERY] Codex scan skipped (no authorization): \(error.localizedDescription, privacy: .public)")
        codexCandidates = []
      }

      allCandidates.append(contentsOf: codexCandidates)

      // Find global newest across both Claude and Codex
      guard let newest = allCandidates.max(by: { $0.mtime < $1.mtime }) else {
        let duration = Date().timeIntervalSince(startTime)
        logger.info("[QUICK-DISCOVERY-DONE] No transcripts found in any project (duration: \(Int(duration * 1000), privacy: .public)ms)")
        return nil
      }

      let duration = Date().timeIntervalSince(startTime)
      logger.info("[QUICK-DISCOVERY-DONE] Newest: \(newest.projectPath.lastPathComponent, privacy: .public) transcript=\(newest.transcriptFile.lastPathComponent, privacy: .public) mtime=\(newest.mtime, privacy: .public) (duration: \(Int(duration * 1000), privacy: .public)ms)")

      return newest

    } catch {
      let duration = Date().timeIntervalSince(startTime)
      logger.error("[QUICK-DISCOVERY-ERROR] Failed: \(error.localizedDescription) (duration: \(Int(duration * 1000), privacy: .public)ms)")
      return nil
    }
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
    // Use task group for parallel retrieval
    var mtimeCache: [String: Date] = [:]
    await withTaskGroup(of: (String, Date).self) { group in
      for path in projectPaths {
        group.addTask {
          let url = URL(fileURLWithPath: path)
          let mtime = await self.getNewestTranscriptMtime(for: url)
          return (path, mtime)
        }
      }

      for await (path, mtime) in group {
        mtimeCache[path] = mtime
      }
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
    let startTime = Date()
    let projectName = projectPath.lastPathComponent

    do {
      let mtime = try await withClaudeRoot { root in
        // Same logic as claudeDir(for:), but computing mtimes instead
        let dirs = try FileManager.default.contentsOfDirectory(
          at: root,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        // Find the matching project dir
        guard let dir = dirs.first(where: { reversePathMapping(dirURL: $0) == projectPath }) else {
          logger.warning("[MTIME-RETRIEVAL] No transcript directory found for: \(projectName, privacy: .public)")
          return Date.distantPast
        }

        // Find all .jsonl files and get newest mtime
        let files = try FileManager.default.contentsOfDirectory(
          at: dir,
          includingPropertiesForKeys: [.contentModificationDateKey],
          options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }

        guard !files.isEmpty else {
          logger.debug("[MTIME-RETRIEVAL] No transcript files found in directory for: \(projectName, privacy: .public)")
          return Date.distantPast
        }

        let mtimes = files.compactMap {
          (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return mtimes.max() ?? Date.distantPast
      }

      let duration = Date().timeIntervalSince(startTime) * 1000
      logger.debug("[MTIME-RETRIEVAL] ✅ project=\(projectName, privacy: .public) mtime=\(mtime, privacy: .public) duration=\(Int(duration), privacy: .public)ms")
      return mtime

    } catch {
      let duration = Date().timeIntervalSince(startTime) * 1000
      logger.warning("[MTIME-RETRIEVAL] ⚠️ Security-scoped access failed for \(projectName, privacy: .public): \(error.localizedDescription, privacy: .public) duration=\(Int(duration), privacy: .public)ms")

      // Fallback 1: Use project directory mtime as proxy
      do {
        let attrs = try FileManager.default.attributesOfItem(atPath: projectPath.path)
        if let dirMtime = attrs[.modificationDate] as? Date {
          logger.info("[MTIME-RETRIEVAL] Using fallback: project directory mtime for \(projectName, privacy: .public)")
          return dirMtime
        }
      } catch {
        logger.debug("[MTIME-RETRIEVAL] Fallback 1 failed (directory mtime): \(error.localizedDescription, privacy: .public)")
      }

      // Fallback 2: Use current time (fail-safe: sort to top, not bottom)
      logger.warning("[MTIME-RETRIEVAL] All fallbacks failed for \(projectName, privacy: .public) - using current time")
      return Date()  // Treat as recent rather than ancient
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
