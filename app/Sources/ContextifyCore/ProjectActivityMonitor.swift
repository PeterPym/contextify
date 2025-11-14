import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "ProjectActivity")

private struct ProjectDiscoveryResult {
  let batches: [ProjectTranscriptBatch]
  let transcriptCount: Int
}

/// Project event emitted by ProjectActivityMonitor
public struct ProjectEvent: Sendable {
  public enum Kind: String, Sendable {
    case discovered
    case transcriptUpdated
    case removed
    case reordered
  }

  public let projectId: String
  public let kind: Kind
  public let timestamp: Date

  public init(projectId: String, kind: Kind, timestamp: Date = Date()) {
    self.projectId = projectId
    self.kind = kind
    self.timestamp = timestamp
  }
}

/// Handle for a project watcher (opaque, used for deduplication)
public struct WatchHandle: Sendable, Hashable {
  public let id: String

  public init(id: String) {
    self.id = id
  }
}

/// Actor that owns all watcher lifecycle
/// Single source of truth for which projects are being watched
public actor ProjectActivityMonitor {
  private let orchestrator: TranscriptOrchestrator
  private var activeWatchers: [String: WatchHandle] = [:]  // projectId -> WatchHandle
  private var eventObservers: [UUID: AsyncStream<ProjectEvent>.Continuation] = [:]
  private var isMonitoring = false

  private var fsEventsMonitor: FSEventsMonitor?
  private var fsEventsTask: Task<Void, Never>?

  public init(orchestrator: TranscriptOrchestrator) {
    self.orchestrator = orchestrator
    let monitorId = "\(ObjectIdentifier(self))"
    log.info("ProjectActivity: monitor initialized (id: \(monitorId))")
  }

  deinit {
    let monitorId = "\(ObjectIdentifier(self))"
    log.debug("ProjectActivity: monitor deallocated (id: \(monitorId))")
  }

  /// Start global monitoring (FSEvents + fallback polling)
  public func startGlobalMonitoring() async throws {
    guard !isMonitoring else {
      log.warning("ProjectActivityMonitor already monitoring")
      return
    }

    isMonitoring = true
    log.info("[INIT] ProjectActivityMonitor: starting global monitoring")

    // Discover all projects from transcript roots
    try await discoverAllProjects()

    #if !APPSTORE_BUILD
    // Start FSEvents monitoring for live transcript updates (DMG builds only)
    #if os(macOS)
    let claudeRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/projects")
    let codexRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/sessions")

    let roots = [claudeRoot.path, codexRoot.path].filter { path in
      FileManager.default.fileExists(atPath: path)
    }

    if !roots.isEmpty {
      let monitor = await FSEventsMonitor(paths: roots, latency: 0.5)
      self.fsEventsMonitor = monitor
      let stream = await monitor.start()

      self.fsEventsTask = Task { [weak self] in
        for await change in stream {
          guard let self else { return }
          await self.handleFileSystemChange(change)
        }
      }

      log.info("[INIT] ProjectActivityMonitor: global discovery + FSEvents enabled (DMG)")
    } else {
      log.warning("No transcript roots found for FSEvents monitoring")
    }
    #else
    log.debug("FSEvents monitoring not available on this platform")
    #endif
    #else
    log.info("[INIT] ProjectActivityMonitor: sandbox mode (no global discovery FSEvents; app layer handles discovery)")
    #endif
  }

  /// Stop all monitoring and watchers
  public func stopGlobalMonitoring() async {
    isMonitoring = false
    activeWatchers.removeAll()

    // Stop FSEvents monitoring
    if let monitor = fsEventsMonitor {
      await monitor.stop()
      fsEventsMonitor = nil
    }

    fsEventsTask?.cancel()
    fsEventsTask = nil

    log.info("Stopped all project monitoring")
  }

  /// Manually trigger a full discovery/hoover pass (used for diagnostics)
  public func forceRescanAllProjects(reason: String = "manual") async {
    log.info("[MANUAL-RESCAN] Requested full rescan (reason: \(reason, privacy: .public))")

    do {
      try await discoverAllProjects()
      log.info("[MANUAL-RESCAN] Completed full rescan (reason: \(reason, privacy: .public))")
    } catch {
      log.error("[MANUAL-RESCAN] Failed to complete rescan: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Legacy compatibility - calls stopGlobalMonitoring()
  public func stopAll() async {
    await stopGlobalMonitoring()
  }

  /// Idempotent watcher start (returns existing handle if already started)
  /// IMPORTANT: Only emits .discovered event on FIRST call per projectId. If watcher already
  /// exists, returns early WITHOUT emitting. Callers expecting .discovered events must handle
  /// this case separately (e.g., ProjectSwitcherState subscribes to .projectsIngestionComplete).
  public func ensureWatcher(projectId: String) async throws -> WatchHandle {
    if let existing = activeWatchers[projectId] {
      log.info("[WATCHER-NOTIFY] Watcher already active for project: \(projectId, privacy: .public)")
      return existing
    }

    // Create new watcher
    let handle = WatchHandle(id: projectId)
    activeWatchers[projectId] = handle

    log.info("[WATCHER-NOTIFY] Started watcher for project: \(projectId, privacy: .public)")

    // Emit discovered event (only on first call - see IMPORTANT note above)
    emitEvent(ProjectEvent(projectId: projectId, kind: .discovered))

    return handle
  }

  /// Stop watcher for specific project
  public func stopWatcher(projectId: String) async {
    guard activeWatchers.removeValue(forKey: projectId) != nil else {
      log.debug("No active watcher for project: \(projectId)")
      return
    }

    log.info("Stopped watcher for project: \(projectId)")

    // Emit removed event
    emitEvent(ProjectEvent(projectId: projectId, kind: .removed))
  }

  /// Event stream for UI (multicast - each subscriber receives all events)
  public nonisolated func observeProjectEvents() -> AsyncStream<ProjectEvent> {
    let observerId = UUID()

    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      // Register observer (need to access actor-isolated state)
      Task { [weak self] in
        guard let self else { return }
        await self.registerObserver(id: observerId, continuation: continuation)
      }

      // Cleanup on termination
      continuation.onTermination = { @Sendable [weak self] _ in
        Task { await self?.removeObserver(id: observerId) }
      }
    }
  }

  /// Active watcher count (for testing)
  public var activeWatcherCount: Int {
    activeWatchers.count
  }

  /// Emit a project event (public for reorder events from UI)
  public func emitProjectEvent(_ event: ProjectEvent) {
    emitEvent(event)
  }

  // MARK: - Private

  /// Register observer (actor-isolated helper)
  private func registerObserver(id: UUID, continuation: AsyncStream<ProjectEvent>.Continuation) {
    eventObservers[id] = continuation
    log.debug("ProjectActivity: registered observer \(id) (total: \(self.eventObservers.count))")
  }

  /// Remove observer by UUID (called on stream termination)
  private func removeObserver(id: UUID) {
    eventObservers.removeValue(forKey: id)
    log.debug("ProjectActivity: removed observer \(id) (total: \(self.eventObservers.count))")
  }

  private func emitEvent(_ event: ProjectEvent) {
    log.debug("ProjectActivity: emitting \(event.kind.rawValue) project=\(event.projectId) to \(self.eventObservers.count) observers")

    // Fan out to all observers
    for (_, continuation) in eventObservers {
      continuation.yield(event)
    }
  }

  private func discoverAllProjects() async throws {
    #if APPSTORE_BUILD
    log.info("[DISC-SCAN-SKIP] Skipping core discovery in sandbox (app layer handles this)")
    return
    #endif

    let startTime = Date()
    log.info("[DISC-SCAN-START] Starting discovery scan for all projects")

    var aggregatedBatches: [ProjectTranscriptBatch] = []

    // Discover projects from Claude Code and Codex CLI transcript roots
    let claudeRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/projects")
    let codexRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/sessions")

    var claudeCount = 0
    var codexCount = 0

    // Discover Claude Code projects
    if FileManager.default.fileExists(atPath: claudeRoot.path) {
      log.info("[DISC-SCAN-ROOT] Scanning Claude Code root: \(claudeRoot.path, privacy: .public)")
      let providerStartTime = Date()
      let result = try await discoverProjectsInRoot(claudeRoot, provider: "claude.code")
      claudeCount = result.transcriptCount
      aggregatedBatches.append(contentsOf: result.batches)
      let duration = Date().timeIntervalSince(providerStartTime)
      log.info("[DISC-SCAN-ROOT-DONE] Claude Code discovery complete: \(claudeCount, privacy: .public) transcripts in \(Int(duration * 1000), privacy: .public)ms")
    } else {
      log.debug("[DISC-SCAN-ROOT] Claude Code root not found: \(claudeRoot.path, privacy: .public)")
    }

    // Discover Codex CLI projects
    if FileManager.default.fileExists(atPath: codexRoot.path) {
      log.info("[DISC-SCAN-ROOT] Scanning Codex CLI root: \(codexRoot.path, privacy: .public)")
      let providerStartTime = Date()
      let result = try await discoverProjectsInRoot(codexRoot, provider: "codex.cli")
      codexCount = result.transcriptCount
      aggregatedBatches.append(contentsOf: result.batches)
      let duration = Date().timeIntervalSince(providerStartTime)
      log.info("[DISC-SCAN-ROOT-DONE] Codex CLI discovery complete: \(codexCount, privacy: .public) transcripts in \(Int(duration * 1000), privacy: .public)ms")
    } else {
      log.debug("[DISC-SCAN-ROOT] Codex CLI root not found: \(codexRoot.path, privacy: .public)")
    }

    let totalDuration = Date().timeIntervalSince(startTime)
    log.info("[DISC-SCAN-DONE] Discovery complete in \(Int(totalDuration * 1000), privacy: .public)ms: Claude=\(claudeCount, privacy: .public) Codex=\(codexCount, privacy: .public)")

    if totalDuration > 60.0 {
      log.warning("[DISC-SCAN-SLOW] Discovery took \(Int(totalDuration), privacy: .public)s - expected < 60s")
    }

    if !aggregatedBatches.isEmpty {
      let coordinator = MultiProjectIngestionCoordinator(orchestrator: orchestrator)
      try await coordinator.runPrimerAndBackfill(batches: aggregatedBatches)
    }
  }

  private func discoverProjectsInRoot(_ root: URL, provider: String) async throws -> ProjectDiscoveryResult {
    // Codex uses nested YYYY/MM/DD structure - requires recursive discovery
    if provider == "codex.cli" {
      return try await discoverCodexSessionsRecursively(root: root)
    }

    // Claude Code uses flat structure - scan immediate children
    let contents = try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    // Prioritize active project for faster time-to-first-data
    // Get current project path from StartupCoordinator
    let activeProjectPath = await StartupCoordinator.shared.current?.path

    // Sort directories: active project first, then others
    let sortedContents = contents.sorted { dir1, dir2 in
      // Try to reverse-mangle both paths to compare with active project
      let path1 = try? ProjectIdentity.reverseManglePath(provider: provider, directory: dir1)
      let path2 = try? ProjectIdentity.reverseManglePath(provider: provider, directory: dir2)

      // Active project always comes first
      if let activePath = activeProjectPath {
        if path1 == activePath { return true }
        if path2 == activePath { return false }
      }

      // Otherwise maintain original order
      return false
    }

    var totalTranscripts = 0
    var batches: [ProjectTranscriptBatch] = []

    for directory in sortedContents {
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir),
            isDir.boolValue else {
        continue
      }

      // Reverse-mangle to get project path
      var projectPathForLogging = directory.lastPathComponent
      do {
        let projectPath = try ProjectIdentity.reverseManglePath(provider: provider, directory: directory)
        projectPathForLogging = projectPath  // Update with unmangled path for error logging
        let projectId = ProjectIdentity.computeProjectID(provider: provider, path: projectPath)

        // Create/upsert project in database
        let dbProjectId = try orchestrator.getOrCreateProject(
          name: URL(fileURLWithPath: projectPath).lastPathComponent,
          rootPath: projectPath
        )

        // Discover and hoover all transcript files for this project
        let transcriptFiles = try FileManager.default.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
          options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "jsonl" }
        .sorted { url1, url2 in
          // Sort by modification time, newest first (for faster time-to-first-data)
          let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
          let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
          return date1 > date2
        }

        if !transcriptFiles.isEmpty {
          log.info("[DISC-PROJECT-START] Found \(transcriptFiles.count, privacy: .public) transcript files for project: \(projectPath, privacy: .public) (sorted newest first)")

          let transcripts = transcriptFiles.compactMap { url -> TranscriptDescriptor? in
            let sessionId = url.deletingPathExtension().lastPathComponent
            let lastModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            log.debug("[DISC-PROJECT-FILE] Transcript: \(url.lastPathComponent, privacy: .public) session: \(sessionId, privacy: .public)")
            return TranscriptDescriptor(
              fileURL: url,
              provider: provider,
              sessionId: sessionId,
              lastModified: lastModified
            )
          }

          if !transcripts.isEmpty {
            log.info("[DISC-PROJECT-QUEUE] Prepared \(transcripts.count, privacy: .public) transcripts for deferred ingestion (project: \(projectPath, privacy: .public))")
            batches.append(ProjectTranscriptBatch(projectId: dbProjectId, transcripts: transcripts))
            totalTranscripts += transcripts.count
          }
        }

        // Ensure watcher for this project (for project-level events)
        let _ = try await ensureWatcher(projectId: projectId)

        log.debug("Discovered project: \(projectPath) (provider: \(provider))")
      } catch let error as ProjectIdentityError {
        // Distinguish between expected orphaned projects and actual errors
        switch error {
        case .invalidPath:
          // Expected: project directory was deleted/moved after transcript was created
          // Try to extract project path from transcripts to mark as orphaned
          do {
            // Try to extract CWD from transcript files even if directory is invalid
            let transcriptFiles = try FileManager.default.contentsOfDirectory(
              at: directory,
              includingPropertiesForKeys: [.fileSizeKey],
              options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "jsonl" }

            if let firstTranscript = transcriptFiles.first,
               let projectPath = try? ProjectIdentity.extractCwdFromTranscriptForOrphaned(firstTranscript) {
              let projectId = ProjectIdentity.computeProjectID(provider: provider, path: projectPath)

              // Check if this project exists in database
              if let existingProject = try? orchestrator.getProject(id: projectId),
                 !existingProject.isOrphaned {
                // Mark as orphaned
                let now = Int(Date().timeIntervalSince1970)
                try orchestrator.markProjectOrphaned(projectId: projectId, orphanedSince: now)
                log.info("Marked project as orphaned: \(projectPath) (transcripts exist but directory missing)")
              } else {
                log.debug("Skipping orphaned project \(projectPath) [mangled: \(directory.lastPathComponent)]: directory no longer exists")
              }
            } else {
              log.debug("Skipping orphaned project \(projectPathForLogging) [mangled: \(directory.lastPathComponent)]: directory no longer exists, cannot determine project path")
            }
          } catch {
            log.debug("Skipping orphaned project [mangled: \(directory.lastPathComponent)]: \(error.localizedDescription)")
          }
        case .cannotReadSessionMetadata:
          // Expected: empty or malformed session directory (e.g., just a "2025" folder with no session.json)
          log.debug("Skipping invalid session directory \(directory.lastPathComponent): no readable metadata")
        case .unknownProvider, .invalidDirectory:
          // Unexpected: should rarely happen
          log.error("Failed to process project directory \(projectPathForLogging, privacy: .public) [mangled: \(directory.lastPathComponent, privacy: .public)]: \(error, privacy: .public)")
        }
      } catch {
        log.error("Failed to process project directory \(projectPathForLogging, privacy: .public) [mangled: \(directory.lastPathComponent, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
      }
    }

    return ProjectDiscoveryResult(batches: batches, transcriptCount: totalTranscripts)
  }

  /// Recursively discover Codex sessions (nested YYYY/MM/DD structure)
  private func discoverCodexSessionsRecursively(root: URL) async throws -> ProjectDiscoveryResult {
    let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )

    guard let enumerator = enumerator else {
      log.warning("[DISC-CODEX] Failed to create enumerator for: \(root.path, privacy: .public)")
      return ProjectDiscoveryResult(batches: [], transcriptCount: 0)
    }

    var transcriptCount = 0
    // Group transcripts by project path for batch processing
    var transcriptsByProject: [String: [(url: URL, sessionId: String)]] = [:]
    var batches: [ProjectTranscriptBatch] = []

    // Collect all files first (enumerator isn't async-compatible)
    var allFiles: [URL] = []
    while let item = enumerator.nextObject() as? URL {
      allFiles.append(item)
    }

    // Now process files (can be async)
    for fileURL in allFiles {
      guard fileURL.pathExtension == "jsonl" else { continue }

      do {
        // Extract project path from transcript CWD field
        guard let projectPath = try ProjectIdentity.extractCwdFromTranscriptForOrphaned(fileURL) else {
          log.debug("[DISC-CODEX] No CWD found in transcript: \(fileURL.lastPathComponent, privacy: .public)")
          continue
        }

        // Extract session ID from filename
        let sessionId = fileURL.deletingPathExtension().lastPathComponent

        // Group by project path
        transcriptsByProject[projectPath, default: []].append((url: fileURL, sessionId: sessionId))
        transcriptCount += 1

        log.debug("[DISC-CODEX-FILE] Found transcript: \(fileURL.lastPathComponent, privacy: .public) project: \(projectPath, privacy: .public)")
      } catch {
        log.warning("[DISC-CODEX] Failed to extract project path from: \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    }

    // Process each project's transcripts in batch
    for (projectPath, transcripts) in transcriptsByProject {
      do {
        log.info("[DISC-CODEX-PROJECT] Discovering \(transcripts.count, privacy: .public) transcripts for project: \(projectPath, privacy: .public)")

        // Create/upsert project in database
        let dbProjectId = try orchestrator.getOrCreateProject(
          name: URL(fileURLWithPath: projectPath).lastPathComponent,
          rootPath: projectPath
        )

        let descriptors = transcripts.map { item in
          TranscriptDescriptor(
            fileURL: item.url,
            provider: "codex.cli",
            sessionId: item.sessionId,
            lastModified: (try? item.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
          )
        }

        if !descriptors.isEmpty {
          let sortedDescriptors = descriptors.sorted { $0.lastModified > $1.lastModified }
          log.info("[DISC-CODEX-PROJECT-DONE] Prepared \(sortedDescriptors.count, privacy: .public) transcripts for deferred ingestion (project: \(projectPath, privacy: .public))")
          batches.append(ProjectTranscriptBatch(projectId: dbProjectId, transcripts: sortedDescriptors))
        }

        // Ensure watcher for this project
        let projectId = ProjectIdentity.computeProjectID(provider: "codex.cli", path: projectPath)
        let _ = try await ensureWatcher(projectId: projectId)
      } catch {
        log.error("[DISC-CODEX] Failed to discover project \(projectPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    }

    log.info("[DISC-CODEX-COMPLETE] Discovered \(transcriptCount, privacy: .public) Codex transcripts across \(transcriptsByProject.count, privacy: .public) projects")
    return ProjectDiscoveryResult(batches: batches, transcriptCount: transcriptCount)
  }

  /// Handle file system change from FSEvents
  /// Maps changed path → project ID → hoover → emit event
  private func handleFileSystemChange(_ change: FSEventChange) {
    #if os(macOS)
    let path = change.path
    log.info("[FSEVENTS-CHANGE] File system change detected: \(path, privacy: .public)")

    // Only process .jsonl files
    guard path.hasSuffix(".jsonl") else {
      log.debug("[FSEVENTS-SKIP] Non-JSONL file ignored: \(path, privacy: .public)")
      return
    }

    log.info("[FSEVENTS-TRANSCRIPT] Transcript file changed: \(path, privacy: .public)")

    let url = URL(fileURLWithPath: path)
    let comps = url.pathComponents

    // Detect provider and marker
    enum Provider { case claude, codex }
    let provider: Provider
    let marker: String
    if comps.contains(".claude") && comps.contains("projects") {
      provider = .claude
      marker = "projects"
    } else if comps.contains(".codex") && comps.contains("sessions") {
      provider = .codex
      marker = "sessions"
    } else {
      log.debug("FSEvents: non-transcript path ignored")
      return
    }

    // Extract mangled directory
    guard let rootIdx = comps.firstIndex(of: marker), rootIdx + 1 < comps.count else {
      log.warning("FSEvents: malformed path (missing \(marker)) path=\(path)")
      return
    }

    let mangledDir = comps[rootIdx + 1]
    let home = FileManager.default.homeDirectoryForCurrentUser
    let transcriptRoot = (provider == .claude)
      ? home.appendingPathComponent(".claude/projects/\(mangledDir)")
      : home.appendingPathComponent(".codex/sessions/\(mangledDir)")

    // Verify transcript root exists
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: transcriptRoot.path, isDirectory: &isDir), isDir.boolValue else {
      log.warning("FSEvents: missing transcript dir=\(transcriptRoot.path)")
      return
    }

    // Use canonical path resolution instead of custom mangle/demangle
    let sessionId = url.deletingPathExtension().lastPathComponent
    let providerString = (provider == .claude ? "claude.code" : "codex.cli")

    // Use ProjectIdentity.reverseManglePath() to properly demangle project paths
    // This handles both Claude Code and Codex, and correctly handles hyphens in directory names
    let projPath: String
    do {
      projPath = try ProjectIdentity.reverseManglePath(
        provider: providerString,
        directory: transcriptRoot
      )

      log.debug("FSEvents: sessionId=\(sessionId) projPath=\(projPath)")

      // Hoover first, emit event only after completion
      Task {
        do {
          let dbProjectId = try await orchestrator.getOrCreateProject(
            name: URL(fileURLWithPath: projPath).lastPathComponent,
            rootPath: projPath
          )
          try await orchestrator.discoverTranscript(
            projectId: dbProjectId,
            fileURL: url,
            provider: providerString,
            providerSessionId: sessionId,
            startWatching: true,
            progress: nil
          )
          // Emit only after hoover finishes (use dbProjectId for database lookups)
          await self.emitEvent(ProjectEvent(projectId: dbProjectId, kind: .transcriptUpdated))

          // Also post NotificationCenter event for ConversationMonitor compatibility
          await MainActor.run {
            NotificationCenter.default.post(
              name: Notification.Name("TranscriptUpdated"),
              object: nil,
              userInfo: ["projectId": dbProjectId]
            )
          }

          log.info("✅ Emitted events for transcript update: dbProjectId=\(dbProjectId)")
        } catch {
          log.error("FSEvents: hoover failed for \(sessionId, privacy: .public): \(String(describing: error), privacy: .public)")
        }
      }
    } catch {
      log.error("FSEvents: path decode failed for \(mangledDir, privacy: .public): \(String(describing: error), privacy: .public)")
    }
    #endif
  }
}
