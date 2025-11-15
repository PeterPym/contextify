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
  private var fastPathCoordinator: FastPathIngestionCoordinator?

  // All discovered projects (Projects window + diagnostics)
  private(set) var allProjects: [ProjectInfo] = []

  // Tabs-visible projects (excludes orphaned paths)
  private(set) var tabProjects: [ProjectInfo] = []

  // Currently active project ID
  private(set) var activeProjectId: String?

  // Unread counts per project
  private(set) var unreadCounts: [String: Int] = [:]

  // Tracks whether any hidden projects exist
  private(set) var hasHiddenProjects: Bool = false

  // Lifecycle state
  @ObservationIgnored private var projectObservationTask: Task<Void, Never>?
  @ObservationIgnored private var ingestionCompleteTask: Task<Void, Never>?
  @ObservationIgnored private var projectRootObserver: NSObjectProtocol?
  @ObservationIgnored private var isStarted: Bool = false
  @ObservationIgnored private var monitorStartTask: Task<Void, Never>?
  @ObservationIgnored private var monitorFallbackTask: Task<Void, Never>?
  @ObservationIgnored private var hasStartedMonitoring = false

  // Coalescing state for batch unread updates
  @ObservationIgnored private var pendingUnread: Set<String> = []
  @ObservationIgnored private var coalesceTask: Task<Void, Never>?
  @ObservationIgnored private var coordinatorTask: Task<Void, Never>?

  // Deduplication: track target project ID for in-flight switch
  @ObservationIgnored private var switchInProgress: String?
  @ObservationIgnored private var switchTask: Task<Void, Never>?

  // Tab order stabilization
  @ObservationIgnored private var isTabOrderFrozen: Bool = false
  @ObservationIgnored private var tabOrderFreezeTask: Task<Void, Never>?
  @ObservationIgnored private var pendingTabProjects: [ProjectInfo]?
  private let tabOrderFreezeInterval: TimeInterval = 4

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
    ingestionCompleteTask?.cancel()
    coalesceTask?.cancel()
    coordinatorTask?.cancel()
    monitorStartTask?.cancel()
    monitorFallbackTask?.cancel()
    tabOrderFreezeTask?.cancel()
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

    if fastPathCoordinator == nil {
      let coordinator = FastPathIngestionCoordinator(orchestrator: orchestrator)
      Task(priority: .background) {
        await coordinator.resumePendingCompletions()
      }
      fastPathCoordinator = coordinator
      log.info("✅ ProjectSwitcher: initialized fast-path coordinator")
    }

    scheduleMonitorStart()

    // Subscribe to coordinator updates for project context changes
    coordinatorTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for await context in StartupCoordinator.shared.updates() {
        await self.handleContextUpdate(context)
      }
    }

    // Subscribe to ingestion complete notification to refresh tabs
    // CRITICAL: This handles a race condition where welcome modal ingests projects BEFORE
    // startGlobalMonitoring() runs. When watchers already exist, ensureWatcher() skips
    // emitting .discovered events, so we need this notification to trigger refreshProjects().
    // Without this, tabs won't appear after welcome modal ingestion completes.
    ingestionCompleteTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let notifications = NotificationCenter.default.notifications(named: .projectsIngestionComplete)
      for await _ in notifications {
        log.info("ProjectSwitcher: received .projectsIngestionComplete notification - refreshing projects")
        await self.refreshProjects()
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
      log.info("✅ Startup complete: activeProjectId=\(self.activeProjectId ?? "nil", privacy: .public), projects=\(self.allProjects.count)")

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
    ingestionCompleteTask?.cancel()
    ingestionCompleteTask = nil
    coalesceTask?.cancel()
    coalesceTask = nil
    cancelMonitorStartTasks()
    hasStartedMonitoring = false
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

    log.info("[SWITCHER-REFRESH] Starting refresh of project list")

    do {
      // Query all projects sorted by activity (newest entry first)
      log.info("[SWITCHER-SORT-START] Querying projects sorted by activity")
      let projects = try orchestrator.listProjectsSortedByActivity()
      log.info("[SWITCHER-SORT-QUERY] Got \(projects.count, privacy: .public) projects from DB")

      // Log display_order status for debugging
      let withOrder = projects.filter { $0.displayOrder != nil }.count
      let withoutOrder = projects.count - withOrder
      log.info("[SWITCHER-SORT-DEBUG] Projects with display_order: \(withOrder, privacy: .public), without: \(withoutOrder, privacy: .public)")

      // Filter out hidden projects (v18)
      let visibleProjects = projects.filter { project in
        guard !project.hidden else { return false }
        if Sandbox.isSandboxed, SandboxPathFilter.isSandboxContainerPath(project.rootPath) {
          log.info("[SWITCHER-FILTER] Skipping sandbox container project: \(project.rootPath, privacy: .public)")
          return false
        }
        return true
      }
      let hiddenCount = projects.count - visibleProjects.count

      // SQL already sorts by activity (max entry timestamp) when display_order is NULL
      // so we can trust the database order even on first launch.
      let sortedProjects = visibleProjects

      // Log final order with display_order values
      let sortedDebug = sortedProjects.prefix(10).map { p in
        let orderStr = p.displayOrder.map { "order=\($0)" } ?? "order=NULL"
        return "\(p.rootPath) [\(orderStr)]"
      }.joined(separator: " | ")
      log.info("[SWITCHER-SORTED] Tab order (first 10): \(sortedDebug, privacy: .public)")

      // Map to ProjectInfo (use DB orphaned status as primary, verify with FS check)
      let projectInfos = sortedProjects.map { project in
        let pathExists = FileManager.default.fileExists(atPath: project.rootPath)

        if project.isOrphaned && pathExists {
          let projectId = project.id
          Task.detached(priority: .utility) {
            do {
              try orchestrator.markProjectRestored(projectId: projectId)
              await MainActor.run {
                log.info("[ORPHAN-RESTORE] Cleared orphaned flag for project \(projectId, privacy: .public)")
              }
            } catch {
              await MainActor.run {
                log.error("[ORPHAN-RESTORE-ERROR] Failed to clear orphaned flag for \(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
              }
            }
          }
        }

        let isOrphaned = project.isOrphaned || !pathExists
        return ProjectInfo(
          id: project.id,
          name: project.name ?? URL(fileURLWithPath: project.rootPath).lastPathComponent,
          rootPath: project.rootPath,
          transcriptCount: 0,  // TODO: query actual count
          isOrphaned: isOrphaned
        )
      }

      let visibleTabs = projectInfos.filter { !$0.isOrphaned }

      // Update state on main actor
      await MainActor.run {
        self.allProjects = projectInfos
        self.hasHiddenProjects = hiddenCount > 0

        if self.isTabOrderFrozen {
          self.pendingTabProjects = visibleTabs
          log.info("[SWITCHER-SORT-FROZEN] Deferred tab update while freeze active (tabs=\(visibleTabs.count, privacy: .public))")
        } else {
          self.pendingTabProjects = nil
          self.updateTabProjects(visibleTabs)
        }
      }

      log.info("ProjectSwitcher: projects=\(projectInfos.count) (hidden=\(hiddenCount))")
    } catch {
      log.error("[SWITCHER-ERROR] refreshProjects failed: \(String(describing: error), privacy: .public)")
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

  @MainActor
  private func updateTabProjects(_ projects: [ProjectInfo]) {
    let previousIds = Set(tabProjects.map { $0.id })
    let nextIds = Set(projects.map { $0.id })

    let hiddenIds = previousIds.subtracting(nextIds)
    let restoredIds = nextIds.subtracting(previousIds)

    for id in hiddenIds {
      log.info("[ORPHAN-TAB-HIDE] action=hide project=\(id, privacy: .public)")
    }

    for id in restoredIds {
      log.info("[ORPHAN-TAB-HIDE] action=show project=\(id, privacy: .public)")
    }

    tabProjects = projects
  }

  /// Cycle to previous project (for keyboard shortcut)
  public func cycleToPreviousProject() async {
    let startTime = Date()
    log.info("[UIOPT-INPUT] ⌨️ Keyboard shortcut: Previous Project (Cmd+Shift+[)")
    guard !tabProjects.isEmpty else { return }

    if let currentId = activeProjectId,
       let currentIndex = tabProjects.firstIndex(where: { $0.id == currentId }) {
      // Move to previous, wrapping around to end
      let previousIndex = currentIndex > 0 ? currentIndex - 1 : tabProjects.count - 1
      let previousProject = tabProjects[previousIndex]
      log.info("[UIOPT-INPUT] Previous project selected: \(previousProject.name, privacy: .public) (elapsed: \(String(format: "%.0f", Date().timeIntervalSince(startTime) * 1000), privacy: .public)ms)")
      await switchToProject(previousProject.id)
    } else if let first = tabProjects.first {
      // No active project, select first
      await switchToProject(first.id)
    }
  }

  /// Cycle to next project (for keyboard shortcut)
  public func cycleToNextProject() async {
    let startTime = Date()
    log.info("[UIOPT-INPUT] ⌨️ Keyboard shortcut: Next Project (Cmd+Shift+])")
    guard !tabProjects.isEmpty else { return }

    if let currentId = activeProjectId,
       let currentIndex = tabProjects.firstIndex(where: { $0.id == currentId }) {
      // Move to next, wrapping around to start
      let nextIndex = currentIndex < tabProjects.count - 1 ? currentIndex + 1 : 0
      let nextProject = tabProjects[nextIndex]
      log.info("[UIOPT-INPUT] Next project selected: \(nextProject.name, privacy: .public) (elapsed: \(String(format: "%.0f", Date().timeIntervalSince(startTime) * 1000), privacy: .public)ms)")
      await switchToProject(nextProject.id)
    } else if let first = tabProjects.first {
      // No active project, select first
      await switchToProject(first.id)
    }
  }

  /// Manually trigger a full hoover rescan (Diagnostics menu, welcome modal investigations)
  public func triggerManualHooverRescan(reason: String = "user-command") {
    guard let monitor = activityMonitor else {
      log.error("Manual hoover rescan requested but activity monitor is unavailable")
      return
    }

    log.info("[MANUAL-RESCAN] Trigger requested (reason: \(reason))")
    Task {
      await monitor.forceRescanAllProjects(reason: reason)
    }
  }

  /// Switch to a different project
  public func switchToProject(_ projectId: String) async {
    let switchStart = Date()
    log.info("[UIOPT-SWITCH-START] switchToProject() called for: \(projectId, privacy: .public)")

    guard let orchestrator = orchestrator else {
      log.error("[UIOPT-SWITCH-ERROR] No orchestrator available")
      return
    }

    // Deduplicate: if already switching to this project, skip
    if switchInProgress == projectId {
      log.debug("🔀 ProjectSwitcher: Switch to \(projectId, privacy: .public) already in progress, skipping duplicate")
      log.info("[UIOPT-SWITCH-SKIP] Already switching to \(projectId, privacy: .public), skipped")
      return
    }

    log.info("🔀 ProjectSwitcher: Switching to project: \(projectId, privacy: .public)")
    log.info("[SUMM-SWITCH] ProjectSwitcherState initiating switch to: \(projectId, privacy: .public)")

    freezeTabOrdering(reason: "user-switch")

    // Cancel any previous switch task (only one switch at a time)
    switchTask?.cancel()

    // Mark switch in progress
    switchInProgress = projectId
    log.info("[UIOPT-SWITCH-MARKED] Switch marked in progress (elapsed: \(String(format: "%.0f", Date().timeIntervalSince(switchStart) * 1000), privacy: .public)ms)")

    // IMMEDIATE UI UPDATE: Set activeProjectId now for instant visual feedback
    // (Coordinator will confirm/correct this when it publishes, ensuring consistency)
    activeProjectId = projectId
    log.info("[UIOPT-SWITCH-UI] activeProjectId updated immediately for instant feedback (elapsed: \(String(format: "%.0f", Date().timeIntervalSince(switchStart) * 1000), privacy: .public)ms)")

    // CXT-13: Use StartupCoordinator for atomic project switching
    // This ensures ProjectSwitcherState and ConversationMonitor receive updates simultaneously
    // via their respective update streams, eliminating the race condition where UI shows
    // one project but timeline shows data from another.

    // CXT-14: Move database lookup AND coordinator switch into background task
    // to avoid blocking UI on database waits (especially during active LLM generation)
    let clearInProgress = { @MainActor [weak self] in
      self?.switchInProgress = nil
    }

    log.info("[UIOPT-SWITCH-SPAWN] Spawning detached task for DB lookup and coordinator call (elapsed: \(String(format: "%.0f", Date().timeIntervalSince(switchStart) * 1000), privacy: .public)ms)")
    let spawnTime = Date()

    switchTask = Task.detached(priority: .userInitiated) { [orchestrator] in
      let logger = Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")
      let taskStart = Date()
      let spawnDelay = Date().timeIntervalSince(spawnTime)
      logger.info("[UIOPT-SWITCH-TASK-SPAWN-DELAY] Task.detached started executing after \(String(format: "%.0f", spawnDelay * 1000), privacy: .public)ms delay")
      logger.info("[UIOPT-SWITCH-TASK-START] Detached task started (elapsed: \(String(format: "%.0f", Date().timeIntervalSince(switchStart) * 1000), privacy: .public)ms)")

      defer {
        Task(priority: .userInitiated, operation: clearInProgress)
      }

      do {
        // Get project root path (off main thread to avoid blocking on DB lock)
        let dbStart = Date()
        logger.info("[UIOPT-SWITCH-DB-START] Looking up project in database...")

        guard let project = try orchestrator.getProject(id: projectId) else {
          logger.error("Project not found: \(projectId, privacy: .public)")
          logger.error("[UIOPT-SWITCH-ERROR] Project \(projectId, privacy: .public) not found in database")
          return
        }

        let dbElapsed = Date().timeIntervalSince(dbStart)
        logger.info("[UIOPT-SWITCH-DB-DONE] Database lookup completed in \(String(format: "%.0f", dbElapsed * 1000), privacy: .public)ms")

        // Call coordinator to switch (will publish updates to all subscribers)
        let coordStart = Date()
        logger.info("[SUMM-SWITCH] Calling StartupCoordinator.switchProject(to: \(project.rootPath))")
        logger.info("[UIOPT-SWITCH-COORD-START] Calling StartupCoordinator.switchProject()...")

        try await StartupCoordinator.shared.switchProject(to: project.rootPath)

        let coordElapsed = Date().timeIntervalSince(coordStart)
        logger.info("[UIOPT-SWITCH-COORD-DONE] StartupCoordinator.switchProject() completed in \(String(format: "%.0f", coordElapsed * 1000), privacy: .public)ms")

        let totalElapsed = Date().timeIntervalSince(taskStart)
        logger.info("[UIOPT-SWITCH-TASK-DONE] Detached task completed in \(String(format: "%.0f", totalElapsed * 1000), privacy: .public)ms")
      } catch {
        logger.error("Failed to switch project via coordinator: \(error.localizedDescription)")
        logger.error("[UIOPT-SWITCH-ERROR] Coordinator error: \(error.localizedDescription, privacy: .public)")
      }
    }

    // StartupCoordinator will publish update, which triggers:
    // 1. handleContextUpdate() in ProjectSwitcherState (sets activeProjectId)
    // 2. handleContextUpdate() in ConversationMonitor (loads new timeline)
    // This ensures UI and data stay in sync with no race condition

    if let coordinator = fastPathCoordinator {
      var projectIds = allProjects.map { $0.id }
      if !projectIds.contains(projectId) {
        projectIds.append(projectId)
      }

      log.info("[FASTPATH-SWITCH] Triggering fast-path preview for project switch: \(projectId, privacy: .public)")
      Task.detached(priority: .utility) { [coordinator, projectIds, projectId] in
        await coordinator.runFastPath(projectIds: projectIds, activeProjectId: projectId)
      }
    } else {
      log.info("[FASTPATH-SWITCH] Fast-path coordinator unavailable; skipping preview run")
    }

    // CXT-11: Update metadata in background (non-blocking)
    Task.detached(priority: .userInitiated) { [orchestrator] in
      let logger = Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")
      do {
        // Mark project as selected and viewed
        try orchestrator.markProjectSelected(projectId: projectId)
        let timestamp = ISO8601Z.string(from: Date())
        try orchestrator.markProjectViewed(projectId: projectId, timestamp: timestamp)
        logger.debug("✅ Project metadata updated in database: \(projectId, privacy: .public)")
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

      log.info("Hidden project: \(projectId, privacy: .public)")
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

      log.info("Unhidden project: \(projectId, privacy: .public)")
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
    // Reorder visible tab projects first, then append any remaining (orphans)
    let reorderedTabs = orderedProjectIds.compactMap { id in
      tabProjects.first(where: { $0.id == id })
    }
    let orderedSet = Set(orderedProjectIds)
    let remainingProjects = allProjects.filter { !orderedSet.contains($0.id) }

    await MainActor.run {
      self.updateTabProjects(reorderedTabs)
      self.allProjects = reorderedTabs + remainingProjects
      self.unfreezeTabOrdering(reason: "manual-reorder")
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

  @MainActor
  private func scheduleMonitorStart() {
    guard activityMonitor != nil else {
      log.error("[SWITCHER-MONITOR] Cannot schedule monitoring start without activity monitor")
      return
    }

    cancelMonitorStartTasks()

    monitorStartTask = Task { [weak self] in
      guard let self else { return }
      let notifications = NotificationCenter.default.notifications(named: .projectsDiscoveryComplete)
      for await _ in notifications {
        await self.startGlobalMonitoringIfNeeded(reason: "projectsDiscoveryComplete")
        return
      }
    }

    monitorFallbackTask = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      await self.startGlobalMonitoringIfNeeded(reason: "fallback-timeout")
    }
  }

  @MainActor
  private func startGlobalMonitoringIfNeeded(reason: String) async {
    guard !hasStartedMonitoring else { return }
    guard let monitor = activityMonitor else {
      log.error("[SWITCHER-MONITOR] Cannot start monitoring (reason: \(reason)) - activity monitor unavailable")
      return
    }

    hasStartedMonitoring = true
    cancelMonitorStartTasks()

    do {
      try await monitor.startGlobalMonitoring()
      log.info("[SWITCHER-MONITOR] Started global monitoring (reason: \(reason))")
    } catch {
      log.error("Failed to start global monitoring (reason: \(reason)): \(error.localizedDescription)")
    }
  }

  private func cancelMonitorStartTasks() {
    monitorStartTask?.cancel()
    monitorStartTask = nil
    monitorFallbackTask?.cancel()
    monitorFallbackTask = nil
  }

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

  private func freezeTabOrdering(reason: String, duration: TimeInterval? = nil) {
    let interval = duration ?? tabOrderFreezeInterval
    tabOrderFreezeTask?.cancel()
    isTabOrderFrozen = true
    log.info("[SWITCHER-SORT-FROZEN] Freeze activated (reason: \(reason)) for \(interval)s")

    tabOrderFreezeTask = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
      await MainActor.run {
        self.unfreezeTabOrdering(reason: "timeout")
      }
    }
  }

  private func unfreezeTabOrdering(reason: String) {
    guard isTabOrderFrozen else { return }

    isTabOrderFrozen = false
    tabOrderFreezeTask?.cancel()
    tabOrderFreezeTask = nil
    log.info("[SWITCHER-SORT-UNFROZEN] Tab order thawed (reason: \(reason))")

    if let pending = pendingTabProjects {
      pendingTabProjects = nil
      let visible = pending.filter { !$0.isOrphaned }
      updateTabProjects(visible)
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
        let visibleTabs = self.allProjects.filter { !$0.isOrphaned }
        self.updateTabProjects(visibleTabs)
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
    guard !tabProjects.isEmpty else { return }
    guard let currentId = activeProjectId,
          let currentIndex = tabProjects.firstIndex(where: { $0.id == currentId }) else {
      // No active project - switch to first
      await switchToProject(tabProjects[0].id)
      return
    }

    let previousIndex = currentIndex == 0 ? tabProjects.count - 1 : currentIndex - 1
    await switchToProject(tabProjects[previousIndex].id)
  }

  /// Switch to the next project in the list (cycles to beginning if at end)
  @MainActor
  public func switchToNextProject() async {
    guard !tabProjects.isEmpty else { return }
    guard let currentId = activeProjectId,
          let currentIndex = tabProjects.firstIndex(where: { $0.id == currentId }) else {
      // No active project - switch to first
      await switchToProject(tabProjects[0].id)
      return
    }

    let nextIndex = (currentIndex + 1) % tabProjects.count
    await switchToProject(tabProjects[nextIndex].id)
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
