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
  public let lastViewedAt: Date?  // Last time this project was viewed
  public let isOrphaned: Bool  // Whether the project directory is missing

  public init(id: String, name: String, rootPath: String, transcriptCount: Int, lastViewedAt: Date? = nil, isOrphaned: Bool = false) {
    self.id = id
    self.name = name
    self.rootPath = rootPath
    self.transcriptCount = transcriptCount
    self.lastViewedAt = lastViewedAt
    self.isOrphaned = isOrphaned
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

  // All discovered projects (visible only)
  private(set) var allProjects: [ProjectInfo] = []

  // Currently active project ID
  private(set) var activeProjectId: String?

  // Unread counts per project
  private(set) var unreadCounts: [String: Int] = [:]

  // Tracks whether any hidden projects exist
  private(set) var hasHiddenProjects: Bool = false

  // Lifecycle state
  @ObservationIgnored private var projectObservationTask: Task<Void, Never>?
  @ObservationIgnored private var projectRootObserver: NSObjectProtocol?
  @ObservationIgnored private var isStarted: Bool = false

  // Coalescing state for batch unread updates
  @ObservationIgnored private var pendingUnread: Set<String> = []
  @ObservationIgnored private var coalesceTask: Task<Void, Never>?
  @ObservationIgnored private var coordinatorTask: Task<Void, Never>?

  // Deduplication: track target project ID for in-flight switch
  @ObservationIgnored private var switchInProgress: String?
  @ObservationIgnored private var switchTask: Task<Void, Never>?

  // Notification coalescing to prevent duplicate/oscillating notifications
  @ObservationIgnored private var lastHandledPath: String?
  @ObservationIgnored private var lastHandledAt: CFAbsoluteTime = 0
  @ObservationIgnored private var suppressedNonces: Set<String> = []  // Nonce-based self-suppression (replaces time window)
  private let debounceMs: Double = 150  // Coalesce identical notifications within 150ms

  private init() {
    // Lazy initialization - orchestrator set on start()
    self.orchestrator = nil
  }

  deinit {
    // Cancel any pending tasks (safety net for tests/non-singleton usage)
    projectObservationTask?.cancel()
    coalesceTask?.cancel()
    coordinatorTask?.cancel()
    // Note: NotificationCenter automatically removes all observers when self is deallocated
  }

  /// Initialize with explicit orchestrator (for testing)
  public init(orchestrator: TranscriptOrchestrator) {
    self.orchestrator = orchestrator
  }

  // MARK: - Lifecycle

  /// Start monitoring (idempotent)
  @MainActor
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
      let monitor = ProjectActivityMonitor(orchestrator: orchestrator)
      activityMonitor = monitor
      let monitorId = "\(ObjectIdentifier(monitor))"
      log.info("✅ ProjectSwitcher: created new activity monitor (id: \(monitorId))")
    } else {
      let monitorId = "\(ObjectIdentifier(activityMonitor!))"
      log.info("ℹ️  ProjectSwitcher: reusing existing activity monitor (id: \(monitorId))")
    }

    // Subscribe to coordinator updates for project context changes
    coordinatorTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for await context in StartupCoordinator.shared.updates() {
        await self.handleContextUpdate(context)
      }
    }

    // Initial discovery & full unread pass based on current DB
    Task {
      // Get initial context from coordinator (guaranteed to be available)
      if let context = StartupCoordinator.shared.current {
        await handleContextUpdate(context)
      } else {
        // Wait for coordinator to publish first context
        do {
          let context = try await StartupCoordinator.shared.ready()
          await handleContextUpdate(context)
        } catch {
          log.error("Failed to get startup context: \(error.localizedDescription)")
        }
      }

      await refreshProjects()
      await refreshUnreadCounts()

      // activeProjectId is now set by handleContextUpdate, no need to auto-select
      log.info("✅ Startup complete: activeProjectId=\(self.activeProjectId ?? "nil"), projects=\(self.allProjects.count)")

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
  @MainActor
  public func stop() {
    projectObservationTask?.cancel()
    projectObservationTask = nil
    coalesceTask?.cancel()
    coalesceTask = nil
    removeProjectRootObserver()
    isStarted = false

    Task {
      await activityMonitor?.stopAll()
    }

    log.info("ProjectSwitcherState stopped")
  }

  /// Handle project context update from StartupCoordinator
  @MainActor
  private func handleContextUpdate(_ context: ActiveProjectContext) async {
    log.debug("📍 Received context update: \(context.displayName) (id: \(context.id, privacy: .public))")

    // Coordinator guarantees project exists in DB, so just set activeProjectId directly
    activeProjectId = context.id

    // Clear unread count for newly active project (CXT-13)
    unreadCounts[context.id] = 0

    // Refresh project list to update UI
    await refreshProjects()

    log.debug("✅ Active project updated to: \(context.id, privacy: .public)")
  }

  // MARK: - Public API

  /// Refresh projects from database
  public func refreshProjects() async {
    guard let orchestrator = orchestrator else { return }

    do {
      // Query all projects from database
      let projects = try orchestrator.listProjects()

      // Filter out hidden projects (v18)
      let visibleProjects = projects.filter { !$0.hidden }
      let hiddenCount = projects.count - visibleProjects.count

      // Sort by display_order (v19), falling back to created_at for nulls
      let sortedProjects = visibleProjects.sorted { lhs, rhs in
        if let lOrder = lhs.displayOrder, let rOrder = rhs.displayOrder {
          return lOrder < rOrder
        } else if lhs.displayOrder != nil {
          return true  // Projects with display_order come first
        } else if rhs.displayOrder != nil {
          return false
        } else {
          return lhs.createdAt < rhs.createdAt  // Fall back to created_at
        }
      }

      // Map to ProjectInfo (use DB orphaned status as primary, verify with FS check)
      let projectInfos = sortedProjects.map { project in
        // Use DB bit as source of truth, OR with FS check to catch newly missing directories
        let isOrphaned = project.isOrphaned
          || !FileManager.default.fileExists(atPath: project.rootPath)
        return ProjectInfo(
          id: project.id,
          name: project.name ?? URL(fileURLWithPath: project.rootPath).lastPathComponent,
          rootPath: project.rootPath,
          transcriptCount: 0,  // TODO: query actual count
          isOrphaned: isOrphaned
        )
      }

      // Update state on main actor
      await MainActor.run {
        self.allProjects = projectInfos
        self.hasHiddenProjects = hiddenCount > 0
      }

      log.info("ProjectSwitcher: projects=\(projectInfos.count) (hidden=\(hiddenCount))")
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
    let startTime = Date()
    log.info("[UIOPT-INPUT] ⌨️ Keyboard shortcut: Previous Project (Cmd+Shift+[)")
    guard !allProjects.isEmpty else { return }

    if let currentId = activeProjectId,
       let currentIndex = allProjects.firstIndex(where: { $0.id == currentId }) {
      // Move to previous, wrapping around to end
      let previousIndex = currentIndex > 0 ? currentIndex - 1 : allProjects.count - 1
      let previousProject = allProjects[previousIndex]
      log.info("[UIOPT-INPUT] Previous project selected: \(previousProject.name, privacy: .public) (elapsed: \(String(format: "%.0f", Date().timeIntervalSince(startTime) * 1000), privacy: .public)ms)")
      await switchToProject(previousProject.id)
    } else if let first = allProjects.first {
      // No active project, select first
      await switchToProject(first.id)
    }
  }

  /// Cycle to next project (for keyboard shortcut)
  public func cycleToNextProject() async {
    let startTime = Date()
    log.info("[UIOPT-INPUT] ⌨️ Keyboard shortcut: Next Project (Cmd+Shift+])")
    guard !allProjects.isEmpty else { return }

    if let currentId = activeProjectId,
       let currentIndex = allProjects.firstIndex(where: { $0.id == currentId }) {
      // Move to next, wrapping around to start
      let nextIndex = currentIndex < allProjects.count - 1 ? currentIndex + 1 : 0
      let nextProject = allProjects[nextIndex]
      log.info("[UIOPT-INPUT] Next project selected: \(nextProject.name, privacy: .public) (elapsed: \(String(format: "%.0f", Date().timeIntervalSince(startTime) * 1000), privacy: .public)ms)")
      await switchToProject(nextProject.id)
    } else if let first = allProjects.first {
      // No active project, select first
      await switchToProject(first.id)
    }
  }

  /// Switch to a different project
  public func switchToProject(_ projectId: String) async {
    guard let orchestrator = orchestrator else { return }

    // Deduplicate: if already switching to this project, skip
    if switchInProgress == projectId {
      log.debug("🔀 ProjectSwitcher: Switch to \(projectId) already in progress, skipping duplicate")
      return
    }

    log.info("🔀 ProjectSwitcher: Switching to project: \(projectId, privacy: .public)")
    log.info("[SUMM-SWITCH] ProjectSwitcherState initiating switch to: \(projectId)")

    // Cancel any previous switch task (only one switch at a time)
    switchTask?.cancel()

    // Mark switch in progress
    switchInProgress = projectId

    // IMMEDIATE UI UPDATE: Set activeProjectId now for instant visual feedback
    // (Coordinator will confirm/correct this when it publishes, ensuring consistency)
    activeProjectId = projectId

    // CXT-13: Use StartupCoordinator for atomic project switching
    // This ensures ProjectSwitcherState and ConversationMonitor receive updates simultaneously
    // via their respective update streams, eliminating the race condition where UI shows
    // one project but timeline shows data from another.

    // CXT-14: Move database lookup AND coordinator switch into background task
    // to avoid blocking UI on database waits (especially during active LLM generation)
    let clearInProgress = { @MainActor [weak self] in
      self?.switchInProgress = nil
    }

    switchTask = Task.detached(priority: .userInitiated) { [orchestrator] in
      defer {
        Task(priority: .userInitiated, operation: clearInProgress)
      }

      do {
        // Get project root path (off main thread to avoid blocking on DB lock)
        guard let project = try orchestrator.getProject(id: projectId) else {
          Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")
            .error("Project not found: \(projectId)")
          return
        }

        // Call coordinator to switch (will publish updates to all subscribers)
        Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")
          .info("[SUMM-SWITCH] Calling StartupCoordinator.switchProject(to: \(project.rootPath))")
        try await StartupCoordinator.shared.switchProject(to: project.rootPath)
      } catch {
        Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")
          .error("Failed to switch project via coordinator: \(error.localizedDescription)")
      }
    }

    // StartupCoordinator will publish update, which triggers:
    // 1. handleContextUpdate() in ProjectSwitcherState (sets activeProjectId)
    // 2. handleContextUpdate() in ConversationMonitor (loads new timeline)
    // This ensures UI and data stay in sync with no race condition

    // CXT-11: Update metadata in background (non-blocking)
    Task.detached(priority: .userInitiated) { [orchestrator] in
      let logger = Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")
      do {
        // Mark project as selected and viewed
        try orchestrator.markProjectSelected(projectId: projectId)
        let timestamp = ISO8601Z.string(from: Date())
        try orchestrator.markProjectViewed(projectId: projectId, timestamp: timestamp)
        logger.debug("✅ Project metadata updated in database: \(projectId)")
      } catch {
        logger.error("Failed to update project metadata: \(error.localizedDescription)")
      }
    }
  }

  /// Get full project details (for checking orphaned status, etc.)
  public func getProjectDetails(_ projectId: String) async -> Project? {
    guard let orchestrator = orchestrator else { return nil }
    return try? orchestrator.getProject(id: projectId)
  }

  /// Hide a project from the switcher tabs
  public func hideProject(_ projectId: String) async {
    guard let orchestrator = orchestrator else { return }

    do {
      // Update hidden state
      try orchestrator.setProjectHidden(projectId: projectId, hidden: true)

      // Refresh project list to remove hidden project
      await refreshProjects()

      log.info("Hidden project: \(projectId)")
    } catch {
      log.error("Failed to hide project: \(error.localizedDescription)")
    }
  }

  /// Unhide a project (must be called from management UI)
  public func unhideProject(_ projectId: String) async {
    guard let orchestrator = orchestrator else { return }

    do {
      // Update hidden state
      try orchestrator.setProjectHidden(projectId: projectId, hidden: false)

      // Refresh project list
      await refreshProjects()

      log.info("Unhidden project: \(projectId)")
    } catch {
      log.error("Failed to unhide project: \(error.localizedDescription)")
    }
  }

  /// Restore all hidden projects at once
  public func restoreAllHiddenProjects() async {
    guard let orchestrator = orchestrator else { return }

    do {
      // Update all hidden projects in bulk
      try orchestrator.restoreAllHiddenProjects()

      // Refresh project list
      await refreshProjects()

      log.info("Restored all hidden projects")
    } catch {
      log.error("Failed to restore hidden projects: \(error.localizedDescription)")
    }
  }

  /// Reorder projects by updating display_order for all projects atomically
  public func reorderProjects(_ orderedProjectIds: [String]) async {
    guard let orchestrator = orchestrator else { return }

    // OPTIMIZATION: Update UI immediately without waiting for DB/FS operations
    // Create ordered list from existing allProjects array
    let reorderedProjects = orderedProjectIds.compactMap { id in
      allProjects.first(where: { $0.id == id })
    }

    // Update state immediately for instant visual feedback
    await MainActor.run {
      self.allProjects = reorderedProjects
    }

    // Persist to database asynchronously (non-blocking)
    Task { [weak self] in
      guard let self else { return }

      do {
        // Atomically update all display_order values in a single transaction
        try orchestrator.setProjectDisplayOrderBulk(orderedProjectIds)

        // Emit reordered event for first project (Projects window will refresh entire list)
        if let firstProjectId = orderedProjectIds.first, let monitor = await self.activityMonitor {
          await monitor.emitProjectEvent(ProjectEvent(projectId: firstProjectId, kind: .reordered))
          await MainActor.run {
            log.debug("Emitted .reordered event for project: \(firstProjectId)")
          }
        }

        await MainActor.run {
          log.info("Persisted reorder for \(orderedProjectIds.count) projects")
        }
      } catch {
        await MainActor.run {
          log.error("Failed to persist reorder: \(error.localizedDescription)")
        }
        // Revert to DB state on error
        await self.refreshProjects()
      }
    }
  }

  // MARK: - Private

  private func ensureCurrentProjectInDatabase() async {
    guard let orchestrator = orchestrator else { return }

    // Get current project from HUDViewModel
    // Note: On clean startup, this might be nil if HUD hasn't loaded yet.
    // That's OK - the notification observer will sync when HUD posts .projectRootDidChange
    guard let currentRoot = await MainActor.run(body: { HUDViewModel.shared.projectRootURL }) else {
      log.debug("No current project root set yet - will sync when HUD startup notification arrives")
      return
    }

    let projectPath = currentRoot.path
    log.info("🏁 ensureCurrentProjectInDatabase: HUDViewModel has project at \(projectPath, privacy: .public)")

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

      log.info("🏁 Ensured current project in database: \(projectId, privacy: .public) at \(projectPath, privacy: .public)")
      log.info("🏁 Set activeProjectId to: \(self.activeProjectId ?? "nil", privacy: .public)")
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

    case .reordered:
      // Reorder event is handled by ProjectsViewModel for Projects window
      // Main window already refreshes via reorderProjects() -> refreshProjects()
      break
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

  /// Switch to the previous project in the list (cycles to end if at beginning)
  @MainActor
  public func switchToPreviousProject() async {
    guard !allProjects.isEmpty else { return }
    guard let currentId = activeProjectId,
          let currentIndex = allProjects.firstIndex(where: { $0.id == currentId }) else {
      // No active project - switch to first
      await switchToProject(allProjects[0].id)
      return
    }

    let previousIndex = currentIndex == 0 ? allProjects.count - 1 : currentIndex - 1
    await switchToProject(allProjects[previousIndex].id)
  }

  /// Switch to the next project in the list (cycles to beginning if at end)
  @MainActor
  public func switchToNextProject() async {
    guard !allProjects.isEmpty else { return }
    guard let currentId = activeProjectId,
          let currentIndex = allProjects.firstIndex(where: { $0.id == currentId }) else {
      // No active project - switch to first
      await switchToProject(allProjects[0].id)
      return
    }

    let nextIndex = (currentIndex + 1) % allProjects.count
    await switchToProject(allProjects[nextIndex].id)
  }

  // MARK: - Observer lifecycle (MainActor)

  /// Suppress external notifications for a brief window to prevent feedback loops
  /// Generate a nonce for self-originated notifications
  /// Returns the nonce to attach to the notification userInfo
  @MainActor
  private func generateSuppressNonce() -> String {
    let nonce = UUID().uuidString
    suppressedNonces.insert(nonce)
    // Prune old nonces (keep last 10) to prevent unbounded growth
    if suppressedNonces.count > 10 {
      suppressedNonces = Set(suppressedNonces.suffix(10))
    }
    return nonce
  }

  /// Canonicalize URL path (resolve symlinks, standardize)
  /// - Parameter url: URL to canonicalize
  /// - Returns: Canonical absolute path
  private func canonicalPath(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
  }

  @MainActor
  private func removeProjectRootObserver() {
    if let observer = projectRootObserver {
      NotificationCenter.default.removeObserver(observer)
      projectRootObserver = nil
    }
  }
}
