import Foundation
import SwiftUI
import ContextifyCore
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "ProjectsViewModel")

/// View model for the Projects window
@MainActor
@Observable
final class ProjectsViewModel {
  private let discoveryService: ProjectDiscoveryService
  private let hudModel: HUDViewModel

  // State
  private(set) var projects: [DiscoveredProject] = []
  private(set) var isDiscovering = false
  private(set) var isIngesting = false
  private(set) var discoveryProgress: DiscoveryProgress?
  private(set) var errorMessage: String?
  private(set) var lastScanTime: Date?

  init(discoveryService: ProjectDiscoveryService, hudModel: HUDViewModel) {
    self.discoveryService = discoveryService
    self.hudModel = hudModel
  }

  // MARK: - Actions

  /// Discovers and ingests all projects
  func discoverProjects() async {
    guard !isDiscovering else { return }

    isDiscovering = true
    errorMessage = nil

    do {
      // Phase 1: Discovery
      logger.info("Starting project discovery")
      let currentPath = hudModel.projectRootURL?.path
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
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path.path)
  }

  /// Refreshes the projects list
  func refresh() {
    Task {
      await discoverProjects()
    }
  }
}
