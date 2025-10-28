import Foundation
import Observation
import OSLog
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")

/// Project information for display in switcher
public struct ProjectInfo: Identifiable, Sendable, Hashable {
  public let id: String  // project_id
  public let name: String  // display name
  public let rootPath: String
  public let transcriptCount: Int

  public init(id: String, name: String, rootPath: String, transcriptCount: Int) {
    self.id = id
    self.name = name
    self.rootPath = rootPath
    self.transcriptCount = transcriptCount
  }
}

/// Observable state for project switcher UI
/// Follows StatusBarViewModel pattern with event-driven updates
@MainActor
@Observable
public final class ProjectSwitcherState {
  // Shared instance (injectable for testing)
  public static let shared = ProjectSwitcherState()

  private var orchestrator: TranscriptOrchestrator?
  private var activityMonitor: ProjectActivityMonitor?

  // All discovered projects
  private(set) var allProjects: [ProjectInfo] = []

  // Currently active project ID
  private(set) var activeProjectId: String?

  // Unread counts per project
  private(set) var unreadCounts: [String: Int] = [:]

  // Lifecycle state
  @ObservationIgnored private var projectObservationTask: Task<Void, Never>?
  @ObservationIgnored private var isStarted: Bool = false

  private init() {
    // Lazy initialization - orchestrator set on start()
    self.orchestrator = nil
  }

  /// Initialize with explicit orchestrator (for testing)
  public init(orchestrator: TranscriptOrchestrator) {
    self.orchestrator = orchestrator
  }

  // MARK: - Lifecycle

  /// Start monitoring (idempotent)
  public func start() {
    guard !isStarted else { return }
    isStarted = true

    // Initialize orchestrator if not already set
    if orchestrator == nil {
      do {
        orchestrator = try TranscriptOrchestrator(dbManager: .shared)
      } catch {
        log.error("Failed to initialize TranscriptOrchestrator: \(error.localizedDescription)")
        return
      }
    }

    guard let orchestrator = orchestrator else {
      log.error("TranscriptOrchestrator not available")
      return
    }

    // Initialize activity monitor
    activityMonitor = ProjectActivityMonitor(orchestrator: orchestrator)

    // Initial load
    Task {
      // Ensure current project is in database
      await ensureCurrentProjectInDatabase()

      await refreshProjects()

      // Start global monitoring if consent given
      if ConsentManager.shared.isMultiProjectModeEnabled {
        do {
          if let monitor = activityMonitor {
            try await monitor.startGlobalMonitoring()
          }
        } catch {
          log.error("Failed to start global monitoring: \(error.localizedDescription)")
        }
      }
    }

    // Start event stream observation
    projectObservationTask = Task { @MainActor [weak self] in
      await self?.observeProjectUpdates()
    }

    log.info("ProjectSwitcherState started")
  }

  /// Stop monitoring
  public func stop() {
    projectObservationTask?.cancel()
    projectObservationTask = nil
    isStarted = false

    Task {
      await activityMonitor?.stopAll()
    }

    log.info("ProjectSwitcherState stopped")
  }

  // MARK: - Public API

  /// Refresh projects from database
  public func refreshProjects() async {
    guard let orchestrator = orchestrator else { return }

    do {
      // Query all projects from database
      let projects = try orchestrator.listProjects()

      // Get unread counts
      let counts = try orchestrator.getUnreadCounts()

      // Map to ProjectInfo
      let projectInfos = projects.map { project in
        ProjectInfo(
          id: project.id,
          name: project.name ?? URL(fileURLWithPath: project.rootPath).lastPathComponent,
          rootPath: project.rootPath,
          transcriptCount: 0  // TODO: query actual count
        )
      }

      // Update state on main actor
      await MainActor.run {
        self.allProjects = projectInfos
        self.unreadCounts = counts
      }

      log.info("📊 Refreshed \(projectInfos.count) projects: \(projectInfos.map { $0.name }.joined(separator: ", "))")
      log.info("📊 Unread counts: \(counts)")
      log.info("📊 Active project ID: \(self.activeProjectId ?? "nil")")
    } catch {
      log.error("Failed to refresh projects: \(error.localizedDescription)")
    }
  }

  /// Cycle to previous project (for keyboard shortcut)
  public func cycleToPreviousProject() async {
    guard !allProjects.isEmpty else { return }

    if let currentId = activeProjectId,
       let currentIndex = allProjects.firstIndex(where: { $0.id == currentId }) {
      // Move to previous, wrapping around to end
      let previousIndex = currentIndex > 0 ? currentIndex - 1 : allProjects.count - 1
      let previousProject = allProjects[previousIndex]
      await switchToProject(previousProject.id)
    } else if let first = allProjects.first {
      // No active project, select first
      await switchToProject(first.id)
    }
  }

  /// Cycle to next project (for keyboard shortcut)
  public func cycleToNextProject() async {
    guard !allProjects.isEmpty else { return }

    if let currentId = activeProjectId,
       let currentIndex = allProjects.firstIndex(where: { $0.id == currentId }) {
      // Move to next, wrapping around to start
      let nextIndex = currentIndex < allProjects.count - 1 ? currentIndex + 1 : 0
      let nextProject = allProjects[nextIndex]
      await switchToProject(nextProject.id)
    } else if let first = allProjects.first {
      // No active project, select first
      await switchToProject(first.id)
    }
  }

  /// Switch to a different project
  public func switchToProject(_ projectId: String) async {
    guard let orchestrator = orchestrator else { return }

    log.info("Switching to project: \(projectId)")

    // Update active project ID
    activeProjectId = projectId

    // Mark project as selected
    do {
      try orchestrator.markProjectSelected(projectId: projectId)

      // Mark as viewed with current timestamp
      let timestamp = ISO8601DateFormatter().string(from: Date())
      try orchestrator.markProjectViewed(projectId: projectId, timestamp: timestamp)

      // Reset unread count
      unreadCounts[projectId] = 0

      // Get project root path and update HUDViewModel
      if let project = try orchestrator.getProject(id: projectId) {
        // Call HUDViewModel to switch project (updates git info, watchers, etc.)
        await MainActor.run {
          HUDViewModel.shared.switchToProject(project.rootPath)
        }

        log.info("Switched to project: \(project.rootPath)")
      }
    } catch {
      log.error("Failed to switch project: \(error.localizedDescription)")
    }
  }

  // MARK: - Private

  private func ensureCurrentProjectInDatabase() async {
    guard let orchestrator = orchestrator else { return }

    // Get current project from HUDViewModel
    guard let currentRoot = await MainActor.run(body: { HUDViewModel.shared.projectRootURL }) else {
      log.debug("No current project root set")
      return
    }

    let projectPath = currentRoot.path

    do {
      // Get or create project in database
      let projectId = try orchestrator.getOrCreateProject(
        name: currentRoot.lastPathComponent,
        rootPath: projectPath
      )

      // Set as active project
      await MainActor.run {
        self.activeProjectId = projectId
      }

      log.info("Ensured current project in database: \(projectId) at \(projectPath)")
    } catch {
      log.error("Failed to ensure current project in database: \(error.localizedDescription)")
    }
  }

  private func observeProjectUpdates() async {
    guard let monitor = activityMonitor else { return }

    // Observe project events
    for await event in monitor.observeProjectEvents() {
      await MainActor.run { [weak self] in
        guard let self else { return }

        switch event.kind {
        case .discovered:
          // Refresh projects to include newly discovered project
          Task {
            await self.refreshProjects()
          }

        case .transcriptUpdated:
          // Increment unread count if not active project
          if event.projectId != self.activeProjectId {
            let current = self.unreadCounts[event.projectId] ?? 0
            self.unreadCounts[event.projectId] = current + 1
          }

        case .removed:
          // Remove project from list
          self.allProjects.removeAll { $0.id == event.projectId }
          self.unreadCounts.removeValue(forKey: event.projectId)
        }
      }
    }
  }
}
