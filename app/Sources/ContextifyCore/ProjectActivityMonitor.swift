import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "ProjectActivity")

/// Project event emitted by ProjectActivityMonitor
public struct ProjectEvent: Sendable {
  public enum Kind: String, Sendable {
    case discovered
    case transcriptUpdated
    case removed
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
  private let eventStream: (stream: AsyncStream<ProjectEvent>, continuation: AsyncStream<ProjectEvent>.Continuation)
  private var isMonitoring = false

  private var fsEventsMonitor: FSEventsMonitor?
  private var fsEventsTask: Task<Void, Never>?

  public init(orchestrator: TranscriptOrchestrator) {
    self.orchestrator = orchestrator
    self.eventStream = AsyncStream<ProjectEvent>.makeStream()
    let monitorId = "\(ObjectIdentifier(self))"
    self.eventStream.continuation.onTermination = { @Sendable [monitorId] _ in
      Task {
        // Termination hook for cleanup if needed
        log.warning("⚠️ ProjectActivity: stream terminated for monitor \(monitorId)")
      }
    }
    log.info("✅ ProjectActivity: monitor initialized (id: \(monitorId))")
  }

  deinit {
    let monitorId = "\(ObjectIdentifier(self))"
    log.warning("🗑️ ProjectActivity: monitor deallocated (id: \(monitorId))")
  }

  /// Start global monitoring (FSEvents + fallback polling)
  public func startGlobalMonitoring() async throws {
    guard !isMonitoring else {
      log.warning("ProjectActivityMonitor already monitoring")
      return
    }

    isMonitoring = true
    log.info("Starting global project monitoring")

    // Discover all projects from transcript roots
    try await discoverAllProjects()

    // Start FSEvents monitoring for live transcript updates
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

      log.info("Started FSEvents monitoring for \(roots.count) transcript roots")
    } else {
      log.warning("No transcript roots found for FSEvents monitoring")
    }
    #else
    log.debug("FSEvents monitoring not available on this platform")
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

  /// Legacy compatibility - calls stopGlobalMonitoring()
  public func stopAll() async {
    await stopGlobalMonitoring()
  }

  /// Idempotent watcher start (returns existing handle if already started)
  public func ensureWatcher(projectId: String) async throws -> WatchHandle {
    if let existing = activeWatchers[projectId] {
      log.debug("Watcher already active for project: \(projectId)")
      return existing
    }

    // Create new watcher
    let handle = WatchHandle(id: projectId)
    activeWatchers[projectId] = handle

    log.info("Started watcher for project: \(projectId)")

    // Emit discovered event
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

  /// Event stream for UI (debounced per-project)
  public nonisolated func observeProjectEvents() -> AsyncStream<ProjectEvent> {
    eventStream.stream
  }

  /// Active watcher count (for testing)
  public var activeWatcherCount: Int {
    activeWatchers.count
  }

  // MARK: - Private

  private func emitEvent(_ event: ProjectEvent) {
    eventStream.continuation.yield(event)
    log.debug("ProjectActivity: emitted \(event.kind.rawValue) project=\(event.projectId)")
  }

  private func discoverAllProjects() async throws {
    // Discover projects from Claude Code and Codex CLI transcript roots
    let claudeRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/projects")
    let codexRoot = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/sessions")

    // Discover Claude Code projects
    if FileManager.default.fileExists(atPath: claudeRoot.path) {
      try await discoverProjectsInRoot(claudeRoot, provider: "claude.code")
    }

    // Discover Codex CLI projects
    if FileManager.default.fileExists(atPath: codexRoot.path) {
      try await discoverProjectsInRoot(codexRoot, provider: "codex.cli")
    }
  }

  private func discoverProjectsInRoot(_ root: URL, provider: String) async throws {
    let contents = try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    for directory in contents {
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
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }

        if !transcriptFiles.isEmpty {
          let transcripts = transcriptFiles.compactMap { url -> (url: URL, provider: String, sessionId: String?)? in
            // Extract session ID from filename (e.g., "767f2c90-6979-406b-9644-38cbbfcf8187.jsonl")
            let sessionId = url.deletingPathExtension().lastPathComponent
            return (url: url, provider: provider, sessionId: sessionId)
          }

          // Batch discover and hoover transcripts
          try orchestrator.discoverTranscripts(
            projectId: dbProjectId,
            transcriptFiles: transcripts,
            progress: nil
          )

          log.info("Discovered \(transcripts.count) transcripts for project: \(projectPath)")
        }

        // Ensure watcher for this project (for project-level events)
        let _ = try await ensureWatcher(projectId: projectId)

        log.debug("Discovered project: \(projectPath) (provider: \(provider))")
      } catch let error as ProjectIdentityError {
        // Distinguish between expected orphaned projects and actual errors
        switch error {
        case .invalidPath:
          // Expected: project directory was deleted/moved after transcript was created
          log.debug("Skipping orphaned project \(projectPathForLogging) [mangled: \(directory.lastPathComponent)]: directory no longer exists")
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
  }

  /// Handle file system change from FSEvents
  /// Maps changed path → project ID → hoover → emit event
  private func handleFileSystemChange(_ change: FSEventChange) {
    #if os(macOS)
    let path = change.path
    log.debug("FSEvents: path=\(path)")

    // Only process .jsonl files
    guard path.hasSuffix(".jsonl") else { return }

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

    // For Claude Code: read project path from directory name (reverse the mangle)
    // For Codex: read from session.json metadata
    let projPath: String
    do {
      if provider == .claude {
        // Claude mangles: /Users/rob/my-app → -Users-rob-my-app
        // Reverse: replace - with / and ensure leading /
        let dirName = transcriptRoot.lastPathComponent
        let unmangled = dirName.replacingOccurrences(of: "-", with: "/")
        projPath = unmangled.hasPrefix("/") ? unmangled : "/" + unmangled
      } else {
        // Codex stores project_root in session.json
        let metaPath = transcriptRoot.appendingPathComponent("session.json")
        let data = try Data(contentsOf: metaPath)
        struct CodexMeta: Codable { let project_root: String }
        projPath = try JSONDecoder().decode(CodexMeta.self, from: data).project_root
      }

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
