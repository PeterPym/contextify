import Foundation
import SwiftUI
import Observation
import ContextifyCore
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "ProjectsViewModel")

/// View model for the Projects window
@MainActor
@Observable
final class ProjectsViewModel {
  enum WelcomePhase: String, Sendable {
    case discovery
    case ingesting
    case watchers
    case ready
  }
  let discoveryService: ProjectDiscoveryService
  private let orchestrator: TranscriptOrchestrator
  private let hudModel: HUDViewModel
  private let activityMonitor: ProjectActivityMonitor
  private let fastPathCoordinator: FastPathIngestionCoordinator?

  // State
  private(set) var projects: [DiscoveredProject] = []
  private(set) var isDiscovering = false
  private(set) var isIngesting = false
  private(set) var discoveryProgress: DiscoveryProgress?
  private(set) var errorMessage: String?
  private(set) var lastScanTime: Date?
  private(set) var welcomePhase: WelcomePhase = .discovery
  private(set) var isWelcomeReady = false
  private(set) var watcherTargetCount = 0
  private(set) var watchersReadyCount = 0

  // Event observation
  @ObservationIgnored private var eventObservationTask: Task<Void, Never>?
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var coordinatorObservationTask: Task<Void, Never>?

  // Canonical active project (from StartupCoordinator)
  private(set) var currentProjectId: String?
  private(set) var currentProjectPath: String?

  init(
    discoveryService: ProjectDiscoveryService,
    orchestrator: TranscriptOrchestrator,
    hudModel: HUDViewModel
  ) {
    self.discoveryService = discoveryService
    self.orchestrator = orchestrator
    self.hudModel = hudModel

    self.activityMonitor = ProjectActivityMonitor(orchestrator: orchestrator)

    // Initialize fast-path coordinator for instant timeline population
    let coordinator = FastPathIngestionCoordinator(orchestrator: orchestrator)
    Task(priority: .background) {
      await coordinator.resumePendingCompletions()
    }
    self.fastPathCoordinator = coordinator

    // Start observing project events for auto-refresh
    startObservingEvents()

    // Subscribe to StartupCoordinator as single source of truth
    startObservingCoordinator()
  }

  nonisolated deinit {
    eventObservationTask?.cancel()
    refreshTask?.cancel()
    coordinatorObservationTask?.cancel()
  }

  // MARK: - Actions

  /// Discovers and ingests all projects
  func discoverProjects() async {
    guard !isDiscovering else {
      logger.debug("Already discovering; skipping duplicate call")
      return
    }

    let overallStartTime = Date()
    logger.info("[DISCOVERY-START] Beginning full project discovery and ingestion")
    logger.debug("discoverProjects() invoked")
    isDiscovering = true
    errorMessage = nil
    resetWelcomeState()

    do {
      // Phase 1: Discovery
      logger.info("Starting project discovery")

      // Canonical: coordinator context; last resort DB MRU
      let currentPath = try await resolveCurrentProjectPath()

      logger.info("[DISCOVERY-PHASE] Starting filesystem scan (pre-ingestion)")
      let discovered = try await discoveryService.discoverAllProjects(currentProjectPath: currentPath)
      logger.info("[DISCOVERY-PHASE] Filesystem scan complete (pre-ingestion)")

      logger.info("Found \(discovered.count) projects")
      projects = discovered
      lastScanTime = Date()

      // Phase 2: Ingestion
      if !discovered.isEmpty {
        welcomePhase = .ingesting
        logger.info("[PSTATE-INGEST-START] Setting isIngesting = true")
        isIngesting = true
        let projectURLs = discovered.map { $0.path }

        try await discoveryService.ingestAllProjects(projects: projectURLs) { [weak self] progress in
          Task { @MainActor in
            logger.info("[PSTATE-PROGRESS] discoveryProgress: \(progress.projectsCompleted, privacy: .public)/\(progress.projectsTotal, privacy: .public) projects, \(progress.transcriptsCompleted, privacy: .public)/\(progress.transcriptsTotal, privacy: .public) transcripts")
            self?.discoveryProgress = progress
          }
        }

        // Run fast-path ingestion for instant timeline population
        if let coordinator = fastPathCoordinator {
          let projectIds = discovered.map { $0.id }
          logger.info("[VIEWMODEL-FASTPATH] Calling runFastPath with activeProjectId: \(self.currentProjectId ?? "none", privacy: .public) projectIds: \(projectIds.count, privacy: .public)")
          await coordinator.runFastPath(projectIds: projectIds, activeProjectId: self.currentProjectId)
        }

        // Refresh metadata after ingestion using canonical currentPath
        logger.info("[DISCOVERY-PHASE] Refreshing project list after ingestion")
        let refreshed = try await discoveryService.discoverAllProjects(currentProjectPath: currentPath)
        logger.info("[DISCOVERY-PHASE] Refresh complete")
        projects = refreshed
        logger.info("[PSTATE-INGEST-DONE] Setting isIngesting = false")
        isIngesting = false
        postDiscoverySnapshot(refreshed)

        // Update pipeline readiness (DB has been updated during ingestion)
        StartupCoordinator.shared.updatePipelineReadiness(dbUpdated: true)

        // POST .projectsDiscoveryComplete notification BEFORE warming up watchers
        // This unblocks ProjectActivityMonitor to start immediately while watchers warm up in parallel
        // Previously, warmUpWatchers() blocked for 60+ seconds before notification was posted
        let ingestionDuration = Date().timeIntervalSince(overallStartTime)
        logger.info("[DISCOVERY-INGEST-DONE] Ingestion complete in \(Int(ingestionDuration * 1000), privacy: .public)ms")
        await MainActor.run {
          NotificationCenter.default.post(name: .projectsDiscoveryComplete, object: nil)
        }
        logger.info("[DISCOVERY-NOTIFICATION] Posted .projectsDiscoveryComplete notification (before watcher warmup)")

        // Update pipeline readiness (discovery complete)
        StartupCoordinator.shared.updatePipelineReadiness(discoveryComplete: true)

        // Now warm up watchers in parallel with ProjectActivityMonitor startup
        await warmUpWatchers(for: refreshed)
      } else {
        logger.info("[DISCOVERY-PHASE] No projects discovered on initial scan")
        welcomePhase = .ready
        isWelcomeReady = true
        // No ingestion needed, but mark as ready
        StartupCoordinator.shared.updatePipelineReadiness(dbUpdated: true, watchersReady: true)

        // Post notification even with no projects
        await MainActor.run {
          NotificationCenter.default.post(name: .projectsDiscoveryComplete, object: nil)
        }
        logger.info("[DISCOVERY-NOTIFICATION] Posted .projectsDiscoveryComplete notification (no projects)")
        StartupCoordinator.shared.updatePipelineReadiness(discoveryComplete: true)
      }

      let totalDuration = Date().timeIntervalSince(overallStartTime)
      logger.info("[DISCOVERY-COMPLETE] Full discovery and watcher warmup complete in \(Int(totalDuration * 1000), privacy: .public)ms")

    } catch {
      logger.error("Discovery failed: \(error.localizedDescription)")
      errorMessage = "Discovery failed: \(error.localizedDescription)"
      welcomePhase = .ready
      isWelcomeReady = true
      // Even on failure, mark discovery as complete
      StartupCoordinator.shared.updatePipelineReadiness(discoveryComplete: true)

      // POST .projectsDiscoveryComplete even on failure to unblock monitor
      await MainActor.run {
        NotificationCenter.default.post(name: .projectsDiscoveryComplete, object: nil)
      }
      logger.info("[DISCOVERY-NOTIFICATION] Posted .projectsDiscoveryComplete notification (after error)")
    }

    isDiscovering = false
    isIngesting = false
    discoveryProgress = nil
  }

  /// Sets a project as the current project
  func setAsCurrent(_ project: DiscoveredProject) {
    logger.info("[VIEWMODEL-SWITCH] Switching to project: \(project.name, privacy: .public) path: \(project.path.path, privacy: .public)")
    let pathString = project.path.path
    Task {
      do {
        try await StartupCoordinator.shared.switchProject(to: pathString)
        // isCurrent will update via coordinator subscription; do a lightweight refresh for responsiveness
        if let refreshed = try? await discoveryService.discoverAllProjects(currentProjectPath: pathString) {
          projects = refreshed
        }
      } catch {
        logger.error("Coordinator switch failed: \(error.localizedDescription)")
        errorMessage = "Failed to switch project: \(error.localizedDescription)"
      }
    }
  }

  /// Reveals a project in Finder
  func revealInFinder(_ project: DiscoveredProject) {
    logger.debug("Revealing project in Finder: \(project.name)")
    NSWorkspace.shared.activateFileViewerSelecting([project.path])
  }

  /// Refreshes the projects list
  func refresh() {
    Task {
      await discoverProjects()
    }
  }

  /// Set discovery progress (for completion messages from external callers)
  func setDiscoveryProgress(_ progress: DiscoveryProgress?) {
    self.discoveryProgress = progress
  }

  // MARK: - Event Observation

  private func startObservingEvents() {
    eventObservationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      logger.info("ProjectsViewModel: starting event observation")

      for await event in self.activityMonitor.observeProjectEvents() {
        await self.handleProjectEvent(event)
      }

      logger.warning("ProjectsViewModel: event stream ended")
    }
  }

  private func startObservingCoordinator() {
    coordinatorObservationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      logger.info("ProjectsViewModel: subscribing to StartupCoordinator updates")
      for await context in StartupCoordinator.shared.updates() {
        self.currentProjectId = context.id
        self.currentProjectPath = context.path
        await self.refreshCurrentProjectFlag()
      }
      logger.warning("ProjectsViewModel: coordinator update stream ended")
    }
  }

  private func refreshCurrentProjectFlag() async {
    let currentPath = try? await resolveCurrentProjectPath()
    if let refreshed = try? await discoveryService.discoverAllProjects(currentProjectPath: currentPath) {
      projects = refreshed
      logger.debug("ProjectsViewModel: refreshed isCurrent flags after project change")
    }
  }

  private func handleProjectEvent(_ event: ProjectEvent) async {
    logger.debug("ProjectsViewModel: received \(event.kind.rawValue) for project \(event.projectId)")

    // Handle both transcript updates and reordering
    guard event.kind == .transcriptUpdated || event.kind == .reordered else { return }

    // Debounce refreshes - only refresh once per second max
    refreshTask?.cancel()
    refreshTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
      guard let self else { return }

      // Refresh metadata for all projects using coordinator-derived path
      let currentPath = try? await self.resolveCurrentProjectPath()
      if let refreshed = try? await self.discoveryService.discoverAllProjects(currentProjectPath: currentPath) {
        self.projects = refreshed
        let reason = event.kind == .reordered ? "reorder" : "transcript update"
        logger.debug("ProjectsViewModel: refreshed project list after \(reason)")
      }
    }
  }

  // MARK: - Helpers
  private func resetWelcomeState() {
    welcomePhase = .discovery
    isWelcomeReady = false
    watcherTargetCount = 0
    watchersReadyCount = 0
  }

  private func warmUpWatchers(for discovered: [DiscoveredProject]) async {
    let eligible = discovered.filter { $0.transcriptCount > 0 }

    guard !eligible.isEmpty else {
      logger.info("[WELCOME-WATCHERS] No transcripts found - marking ready")
      self.welcomePhase = .ready
      self.isWelcomeReady = true
      // Update pipeline readiness (no watchers needed, so mark as ready)
      StartupCoordinator.shared.updatePipelineReadiness(watchersReady: true)
      return
    }

    self.welcomePhase = .watchers
    self.watcherTargetCount = eligible.count
    self.watchersReadyCount = 0
    logger.info("[WELCOME-WATCHERS] Ensuring watchers for \(eligible.count, privacy: .public) projects")

    for project in eligible {
      do {
        _ = try await activityMonitor.ensureWatcher(projectId: project.id)
        self.watchersReadyCount += 1
        logger.info("[WELCOME-WATCHERS] ready=\(self.watchersReadyCount)/\(self.watcherTargetCount) project=\(project.id, privacy: .public)")
      } catch {
        self.watchersReadyCount += 1
        logger.error("[WELCOME-WATCHERS] Failed to start watcher for \(project.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    }

    self.welcomePhase = .ready
    self.isWelcomeReady = true
    logger.info("[WELCOME-PHASE] Ready - timeline warm up complete")

    // Update pipeline readiness (watchers are ready)
    StartupCoordinator.shared.updatePipelineReadiness(watchersReady: true)
  }

  private func resolveCurrentProjectPath() async throws -> String? {
    if let path = SandboxPathFilter.sanitizedPath(currentProjectPath) {
      return path
    }
    if let ctxPath = SandboxPathFilter.sanitizedPath(StartupCoordinator.shared.current?.path) {
      return ctxPath
    }
    // Last resort: DB MRU (stable and deterministic)
    let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
    let all = try orchestrator.listProjects()
    return all
      .filter { project in
        let root = project.rootPath
        return !SandboxPathFilter.isSandboxContainerPath(root)
      }
      .sorted { $0.lastViewedTs > $1.lastViewedTs }
      .first?.rootPath
  }

  private func postDiscoverySnapshot(_ projects: [DiscoveredProject]) {
    NotificationCenter.default.post(name: .projectsDiscoverySnapshot, object: projects)
  }
}
