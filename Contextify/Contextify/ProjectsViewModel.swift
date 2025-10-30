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
  let discoveryService: ProjectDiscoveryService  // Public for ExcludedProjectsView
  private let hudModel: HUDViewModel
  private let activityMonitor: ProjectActivityMonitor

  // State
  private(set) var projects: [DiscoveredProject] = []
  private(set) var isDiscovering = false
  private(set) var isIngesting = false
  private(set) var discoveryProgress: DiscoveryProgress?
  private(set) var errorMessage: String?
  private(set) var lastScanTime: Date?

  // Event observation
  @ObservationIgnored private var eventObservationTask: Task<Void, Never>?
  @ObservationIgnored private var refreshTask: Task<Void, Never>?

  init(discoveryService: ProjectDiscoveryService, hudModel: HUDViewModel) {
    self.discoveryService = discoveryService
    self.hudModel = hudModel

    // Get activity monitor from shared orchestrator
    do {
      let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
      self.activityMonitor = ProjectActivityMonitor(orchestrator: orchestrator)
    } catch {
      logger.error("Failed to initialize ProjectActivityMonitor: \(error.localizedDescription)")
      fatalError("Cannot initialize ProjectsViewModel without activity monitor")
    }

    // Start observing project events for auto-refresh
    startObservingEvents()
  }

  deinit {
    eventObservationTask?.cancel()
    refreshTask?.cancel()
  }

  // MARK: - Actions

  /// Discovers and ingests all projects
  func discoverProjects() async {
    guard !isDiscovering else {
      print("⚠️ ALREADY DISCOVERING - SKIPPING")
      return
    }

    print("✅ DISCOVER PROJECTS CALLED")
    isDiscovering = true
    errorMessage = nil

    do {
      // Phase 1: Discovery
      print("📍 Phase 1: Starting discovery")
      logger.info("Starting project discovery")

      // Get current project path - check multiple sources to handle initialization timing
      let currentPath: String?

      // First, try ProjectSwitcherState if it's been initialized
      if let activeId = ProjectSwitcherState.shared.activeProjectId {
        do {
          let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
          let projects = try orchestrator.listProjects()
          currentPath = projects.first(where: { $0.id == activeId })?.rootPath
          logger.debug("Using active project from ProjectSwitcherState: \(currentPath ?? "nil")")
        } catch {
          logger.warning("Failed to get active project path from database: \(error.localizedDescription)")
          currentPath = hudModel.projectRootURL?.path
        }
      } else if let hudPath = hudModel.projectRootURL?.path {
        // Fall back to HUD model
        currentPath = hudPath
        logger.debug("Using project from HUDViewModel: \(hudPath)")
      } else {
        // Last resort: check database for most recently viewed project
        do {
          let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
          let projects = try orchestrator.listProjects()
          // Sort by last_viewed_ts to find the current project
          let mostRecent = projects
            .filter { $0.lastViewedTs != nil }
            .sorted { ($0.lastViewedTs ?? 0) > ($1.lastViewedTs ?? 0) }
            .first
          currentPath = mostRecent?.rootPath
          logger.debug("Using most recently viewed project from database: \(currentPath ?? "nil")")
        } catch {
          logger.warning("Failed to get most recent project from database: \(error.localizedDescription)")
          currentPath = nil
        }
      }

      let discovered = try await discoveryService.discoverAllProjects(currentProjectPath: currentPath)

      logger.info("Found \(discovered.count) projects")
      projects = discovered
      lastScanTime = Date()

      // Phase 2: Ingestion
      if !discovered.isEmpty {
        isIngesting = true
        let projectURLs = discovered.map { $0.path }

        try await discoveryService.ingestAllProjects(projects: projectURLs) { [weak self] progress in
          Task { @MainActor in
            self?.discoveryProgress = progress
          }
        }

        // Refresh metadata after ingestion
        let refreshed = try await discoveryService.discoverAllProjects(currentProjectPath: currentPath)
        projects = refreshed
      }

      logger.info("Discovery and ingestion complete")

    } catch {
      logger.error("Discovery failed: \(error.localizedDescription)")
      errorMessage = "Discovery failed: \(error.localizedDescription)"
    }

    isDiscovering = false
    isIngesting = false
    discoveryProgress = nil
  }

  /// Sets a project as the current project
  func setAsCurrent(_ project: DiscoveredProject) {
    logger.info("Setting current project: \(project.name)")

    // Update HUD model
    _ = hudModel.setProjectRoot(url: project.path)

    // Refresh projects to update isCurrent flag
    Task {
      let currentPath = hudModel.projectRootURL?.path
      if let refreshed = try? await discoveryService.discoverAllProjects(currentProjectPath: currentPath) {
        projects = refreshed
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

  /// Excludes a project from the list
  func excludeProject(_ project: DiscoveredProject) {
    logger.info("Excluding project: \(project.name)")

    Task {
      await discoveryService.excludeProject(project.path.path)

      // Refresh list to remove excluded project
      let currentPath = hudModel.projectRootURL?.path
      if let refreshed = try? await discoveryService.discoverAllProjects(currentProjectPath: currentPath) {
        projects = refreshed
      }
    }
  }

  /// Gets all excluded projects
  func getExcludedProjects() async -> Set<String> {
    await discoveryService.getExcludedProjects()
  }

  // MARK: - Event Observation

  private func startObservingEvents() {
    eventObservationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      logger.info("ProjectsViewModel: starting event observation")

      for await event in await self.activityMonitor.observeProjectEvents() {
        await self.handleProjectEvent(event)
      }

      logger.warning("ProjectsViewModel: event stream ended")
    }
  }

  private func handleProjectEvent(_ event: ProjectEvent) async {
    logger.debug("ProjectsViewModel: received \(event.kind.rawValue) for project \(event.projectId)")

    guard event.kind == .transcriptUpdated else { return }

    // Debounce refreshes - only refresh once per second max
    refreshTask?.cancel()
    refreshTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
      guard let self else { return }

      // Refresh metadata for all projects (lightweight query)
      let currentPath = self.hudModel.projectRootURL?.path
      if let refreshed = try? await self.discoveryService.discoverAllProjects(currentProjectPath: currentPath) {
        self.projects = refreshed
        logger.debug("ProjectsViewModel: refreshed project metadata after transcript update")
      }
    }
  }
}
