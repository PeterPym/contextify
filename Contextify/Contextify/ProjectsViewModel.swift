import Foundation
import SwiftUI
import Observation
import ContextifyCore
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "ProjectsViewModel")

/// Simplified view model for Phase 3 lazy loading
/// This is a "dumb" view model that observes AppStateOrchestrator and reflects its state
@MainActor
@Observable
final class ProjectsViewModel {
  // UI State (derived from AppStateOrchestrator)
  private(set) var projects: [DiscoveredProject] = []
  private(set) var selectedProjectId: String?
  private(set) var isLoading = false
  private(set) var loadingMessage = ""
  private(set) var errorMessage: String?

  // Welcome modal state (for compatibility with existing UI)
  private(set) var isDiscovering = false
  private(set) var isWelcomeReady = false
  private(set) var watcherTargetCount = 0
  private(set) var watchersReadyCount = 0
  private(set) var lastScanTime: Date?

  // Legacy discovery service (kept for compatibility with old UI that might reference it)
  let discoveryService: ProjectDiscoveryService

  @ObservationIgnored private var stateObservationTask: Task<Void, Never>?

  init(
    discoveryService: ProjectDiscoveryService,
    orchestrator: TranscriptOrchestrator,
    hudModel: HUDViewModel
  ) {
    self.discoveryService = discoveryService

    logger.info("[VM-INIT] Phase 3 ProjectsViewModel initialized")

    // Start observing AppStateOrchestrator
    startObservingOrchestrator()
  }

  nonisolated deinit {
    stateObservationTask?.cancel()
  }

  // MARK: - State Observation

  private func startObservingOrchestrator() {
    stateObservationTask = Task { @MainActor [weak self] in
      guard let self else { return }

      // Observe state changes from orchestrator
      for await _ in NotificationCenter.default.notifications(named: .appStateDidChange) {
        await self.updateFromOrchestrator()
      }
    }

    // Initial update
    Task {
      await updateFromOrchestrator()
    }
  }

  private func updateFromOrchestrator() async {
    let state = AppStateOrchestrator.shared.state

    logger.debug("[VM-UPDATE] Received state: \(String(describing: state))")

    switch state {
    case .startup:
      isLoading = true
      loadingMessage = "Initializing..."

    case .discovering:
      isDiscovering = true
      isLoading = true
      loadingMessage = "Discovering projects..."

    case .idle(let lightweightProjects):
      isDiscovering = false
      isLoading = false
      isWelcomeReady = true
      lastScanTime = Date()
      // Convert LightweightProject to DiscoveredProject for UI compatibility
      self.projects = convertToDiscoveredProjects(lightweightProjects)
      logger.info("[VM-UPDATE] Showing \(self.projects.count) projects (idle)")

      // Phase 3: Update pipeline readiness for welcome modal button
      // Discovery is complete, DB has been updated, watchers will be ready
      StartupCoordinator.shared.updatePipelineReadiness(
        discoveryComplete: true,
        dbUpdated: true,
        watchersReady: true
      )
      logger.info("[VM-UPDATE] Pipeline readiness updated (all ready)")

    case .loading(let projectId):
      isLoading = true
      selectedProjectId = projectId
      loadingMessage = "Loading timeline..."
      logger.info("[VM-UPDATE] Loading project: \(projectId)")

    case .active(let projectId):
      isLoading = false
      selectedProjectId = projectId
      logger.info("[VM-UPDATE] Active project: \(projectId)")

      // Update projects array to mark the active one as current
      for i in projects.indices {
        if projects[i].id == projectId {
          let current = projects[i]
          // DiscoveredProject is a struct, need to create a new instance
          projects[i] = DiscoveredProject(
            id: current.id,
            name: current.name,
            path: current.path,
            providers: current.providers,
            transcriptCount: current.transcriptCount,
            entryCount: current.entryCount,
            lastActivity: current.lastActivity,
            isCurrent: true,  // Mark as current
            ingestionError: current.ingestionError,
            displayOrder: current.displayOrder
          )
        } else if projects[i].isCurrent {
          // Unmark previously current project
          let prev = projects[i]
          projects[i] = DiscoveredProject(
            id: prev.id,
            name: prev.name,
            path: prev.path,
            providers: prev.providers,
            transcriptCount: prev.transcriptCount,
            entryCount: prev.entryCount,
            lastActivity: prev.lastActivity,
            isCurrent: false,  // Unmark
            ingestionError: prev.ingestionError,
            displayOrder: prev.displayOrder
          )
        }
      }

    case .error(let message):
      isLoading = false
      errorMessage = message
      logger.error("[VM-UPDATE] Error: \(message)")
    }
  }

  // MARK: - Actions

  /// User selected a project - delegate to orchestrator
  func setAsCurrent(_ project: DiscoveredProject) {
    logger.info("[VM-ACTION] User selected project: \(project.name)")

    Task {
      await AppStateOrchestrator.shared.selectProject(id: project.id)
    }
  }

  /// Refresh projects (for manual refresh button)
  func refresh() {
    logger.info("[VM-ACTION] Manual refresh requested")

    Task {
      // Re-run lightweight discovery
      await AppStateOrchestrator.shared.startup()
    }
  }

  /// Reveal project in Finder
  func revealInFinder(_ project: DiscoveredProject) {
    logger.debug("[VM-ACTION] Revealing project in Finder: \(project.name)")
    NSWorkspace.shared.activateFileViewerSelecting([project.path])
  }

  // MARK: - Legacy Compatibility

  /// Legacy method kept for compatibility with ContextifyApp initialization
  /// Phase 3: This is now a no-op - orchestrator handles discovery
  func discoverProjects() async {
    logger.info("[VM-LEGACY] discoverProjects() called - delegating to orchestrator")
    await AppStateOrchestrator.shared.startup()
  }

  /// Legacy property for welcome modal compatibility
  var discoveryProgress: DiscoveryProgress? {
    // Phase 3: If we have projects and welcome is ready, show complete
    if isWelcomeReady && !projects.isEmpty {
      return DiscoveryProgress(
        phase: .complete,
        projectsCompleted: projects.count,
        projectsTotal: projects.count,
        message: "✅ Found \(projects.count) projects"
      )
    } else if isDiscovering {
      return DiscoveryProgress(
        phase: .scanning,
        projectsCompleted: 0,
        projectsTotal: 0,
        message: "Scanning filesystem..."
      )
    } else if !projects.isEmpty {
      // Interim state: have projects but not fully ready
      return DiscoveryProgress(
        phase: .ingesting,
        projectsCompleted: projects.count,
        projectsTotal: projects.count,
        message: "Found \(projects.count) projects"
      )
    }
    return nil
  }

  /// Legacy property for compatibility
  var isIngesting: Bool {
    return isLoading
  }

  /// Legacy method for compatibility (no-op in Phase 3)
  func setDiscoveryProgress(_ progress: DiscoveryProgress?) {
    logger.debug("[VM-LEGACY] setDiscoveryProgress() called (no-op in Phase 3)")
    // Phase 3: Progress is managed by orchestrator state, not manually set
  }

  // MARK: - Helpers

  private func convertToDiscoveredProjects(_ lightweight: [LightweightProject]) -> [DiscoveredProject] {
    return lightweight.map { light in
      // Map provider string to enum
      let provider: DiscoveredProject.Provider = light.provider == "claude.code" ? .claudeCode : .codexCLI

      // Phase 3: Use displayName populated during discovery (no need to derive it here)
      return DiscoveredProject(
        id: light.id,
        name: light.displayName,  // Already derived by LightweightDiscoveryService
        path: light.path,
        providers: [provider],
        transcriptCount: light.transcriptCount,
        entryCount: 0, // Not available in lightweight scan
        lastActivity: light.lastActivity,
        isCurrent: false // Will be updated by coordinator
      )
    }
  }
}

// MARK: - Legacy Types (for compatibility)

extension ProjectsViewModel {
  enum WelcomePhase: String, Sendable {
    case discovery
    case ingesting
    case watchers
    case ready
  }

  var welcomePhase: WelcomePhase {
    if isDiscovering {
      return .discovery
    } else if isLoading {
      return .ingesting
    } else {
      return .ready
    }
  }
}
