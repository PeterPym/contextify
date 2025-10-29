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
  var activityMonitor: ProjectActivityMonitor?  // Internal: shared with StatusBarViewModel for event observation

  // All discovered projects
  private(set) var allProjects: [ProjectInfo] = []

  // Currently active project ID
  private(set) var activeProjectId: String?

  // Unread counts per project
  private(set) var unreadCounts: [String: Int] = [:]

  // Lifecycle state
  @ObservationIgnored private var projectObservationTask: Task<Void, Never>?
  @ObservationIgnored private var isStarted: Bool = false

  // Coalescing state for batch unread updates
  @ObservationIgnored private var pendingUnread: Set<String> = []
  @ObservationIgnored private var coalesceTask: Task<Void, Never>?

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
    guard !isStarted else {
      log.warning("ProjectSwitcher: start() called while started")
      return
    }
    isStarted = true
    log.info("ProjectSwitcher: starting")

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

    // Initialize activity monitor once
    if activityMonitor == nil {
      activityMonitor = ProjectActivityMonitor(orchestrator: orchestrator)
    }

    // Initial discovery & full unread pass based on current DB
    Task {
      // Ensure current project is in database
      await ensureCurrentProjectInDatabase()

      await refreshProjects()
      await refreshUnreadCounts() // current state from DB; events will refine

      // Auto-select first project if none is selected (leftmost tab)
      if activeProjectId == nil && !allProjects.isEmpty {
        log.info("No project selected on startup, auto-selecting first project")
        await switchToProject(allProjects[0].id)
      }

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

    // Single observer loop
    projectObservationTask = Task { @MainActor [weak self] in
      guard let self, let monitor = await self.activityMonitor else { return }
      log.info("ProjectSwitcher: observing events")
      for await event in await monitor.observeProjectEvents() {
        await self.handle(event)
      }
      log.warning("ProjectSwitcher: event stream ended")
    }
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
      }

      log.info("ProjectSwitcher: projects=\(projectInfos.count)")
    } catch {
      log.error("ProjectSwitcher: refreshProjects error=\(String(describing: error))")
    }
  }

  /// Refresh unread counts for all projects
  public func refreshUnreadCounts() async {
    guard let orchestrator = orchestrator else { return }

    do {
      let counts = try orchestrator.getUnreadCounts()
      await MainActor.run {
        self.unreadCounts = counts
      }
      log.debug("ProjectSwitcher: unread(all)=\(counts)")
    } catch {
      log.error("ProjectSwitcher: refreshUnreadCounts error=\(String(describing: error))")
    }
  }

  /// Refresh unread counts for specific projects (for coalescing)
  private func refreshUnreadCounts(for projectIds: [String]) async {
    guard let orchestrator = orchestrator, !projectIds.isEmpty else { return }

    do {
      let pairs = try orchestrator.getUnreadCounts(projectIds: projectIds)
      await MainActor.run {
        for (pid, c) in pairs {
          self.unreadCounts[pid] = c
        }
      }
      log.debug("ProjectSwitcher: unread(batch)=\(pairs)")
    } catch {
      log.error("ProjectSwitcher: refreshUnreadCounts(batch) error=\(String(describing: error))")
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

      // Mark as viewed with current timestamp (using centralized formatter)
      let timestamp = ISO8601Z.string(from: Date())
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

  /// Handle project event (called from observer loop)
  private func handle(_ event: ProjectEvent) async {
    log.debug("ProjectSwitcher: received \(event.kind.rawValue) project=\(event.projectId)")

    switch event.kind {
    case .discovered:
      await refreshProjects()
      // let the next transcriptUpdated drive the unread refresh

    case .removed:
      await MainActor.run {
        self.allProjects.removeAll { $0.id == event.projectId }
        self.unreadCounts.removeValue(forKey: event.projectId)
      }

    case .transcriptUpdated:
      // Coalesce to avoid N DB reads for one write
      guard event.projectId != self.activeProjectId else { return }
      scheduleUnreadRefresh(for: event.projectId)
    }
  }

  /// Schedule coalesced unread refresh for a project
  private func scheduleUnreadRefresh(for projectId: String) {
    pendingUnread.insert(projectId)
    coalesceTask?.cancel()
    coalesceTask = Task { [weak self] in
      // Small window to coalesce multiple FSEvents
      try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
      guard let self else { return }
      await self.refreshUnreadCounts(for: Array(self.pendingUnread))
      await MainActor.run {
        self.pendingUnread.removeAll()
      }
    }
  }
}
