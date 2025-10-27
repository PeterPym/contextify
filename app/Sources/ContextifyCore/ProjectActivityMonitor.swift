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
  private var eventContinuation: AsyncStream<ProjectEvent>.Continuation?
  private var isMonitoring = false

  private var fsEventsMonitor: FSEventsMonitor?
  private var fsEventsTask: Task<Void, Never>?

  public init(orchestrator: TranscriptOrchestrator) {
    self.orchestrator = orchestrator
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
  }

  /// Stop all monitoring and watchers
  public func stopAll() async {
    isMonitoring = false
    activeWatchers.removeAll()
    eventContinuation?.finish()
    eventContinuation = nil

    // Stop FSEvents monitoring
    if let monitor = fsEventsMonitor {
      await monitor.stop()
      fsEventsMonitor = nil
    }

    fsEventsTask?.cancel()
    fsEventsTask = nil

    log.info("Stopped all project monitoring")
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
    AsyncStream { continuation in
      Task {
        await self.setEventContinuation(continuation)
      }
    }
  }

  /// Active watcher count (for testing)
  public var activeWatcherCount: Int {
    activeWatchers.count
  }

  // MARK: - Private

  private func setEventContinuation(_ continuation: AsyncStream<ProjectEvent>.Continuation) {
    self.eventContinuation = continuation
  }

  private func emitEvent(_ event: ProjectEvent) {
    eventContinuation?.yield(event)
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
      do {
        let projectPath = try ProjectIdentity.reverseManglePath(provider: provider, directory: directory)
        let projectId = ProjectIdentity.computeProjectID(provider: provider, path: projectPath)

        // Create/upsert project in database
        let _ = try orchestrator.getOrCreateProject(
          name: URL(fileURLWithPath: projectPath).lastPathComponent,
          rootPath: projectPath
        )

        // Ensure watcher for this project
        let _ = try await ensureWatcher(projectId: projectId)

        log.debug("Discovered project: \(projectPath) (provider: \(provider))")
      } catch {
        log.error("Failed to reverse-mangle path \(directory.lastPathComponent): \(error.localizedDescription)")
      }
    }
  }
}
