import Foundation
import SwiftUI
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "AppOrchestrator")

/// Application-wide state
public enum AppState: Sendable {
  case startup
  case discovering
  case idle(projects: [LightweightProject])
  case loading(projectId: String)
  case active(projectId: String)
  case error(String)
}

/// The central coordinator for all app state transitions
/// Replaces the fragmented responsibilities of StartupCoordinator, ProjectActivityMonitor, and ProjectsViewModel ingestion logic
@MainActor
public final class AppStateOrchestrator: ObservableObject {
  public static let shared = AppStateOrchestrator()

  // Dependencies
  private let discovery: LightweightDiscoveryService
  // Optional: nil until onboarding completes in sandboxed builds
  private var orchestrator: TranscriptOrchestrator?
  private var fastPath: FastPathIngestionCoordinator?
  private var accessProvider: TranscriptAccessProvider?

  // Background discovery (App Store builds)
  private var sandboxedWatcher: SandboxedDirectoryWatcher?
  private var codexPollTimer: Timer?
  private let codexPollInterval: TimeInterval = 10.0  // 10 seconds

  // Refresh guard (prevents overlapping refreshProjects() calls)
  private var isRefreshing: Bool = false

  // State
  @Published public private(set) var state: AppState = .startup

  /// Returns the active project ID if the orchestrator is in `.active` state.
  /// Allows components that initialize late to rehydrate from current state
  /// rather than depending on having seen the `.projectDidActivate` notification.
  public var activeProjectId: String? {
    if case .active(let id) = state { return id }
    return nil
  }

  /// Whether the orchestrator has been fully initialized with database access.
  /// In sandboxed builds, this is false until onboarding completes.
  public var isInitialized: Bool {
    orchestrator != nil
  }

  private var knownProjects: [LightweightProject] = []
  private var projectLookup: [String: LightweightProject] = [:]
  private var backgroundTask: Task<Void, Never>?

  private init() {
    self.discovery = LightweightDiscoveryService()

    // In sandboxed builds without onboarding, defer database initialization
    if Sandbox.isSandboxed && !HUDPreferences.hasCompletedAppStoreOnboarding() {
      log.info("[ORCH-INIT] Sandboxed build, onboarding not complete - deferring DB init")
      self.orchestrator = nil
      self.fastPath = nil
      return
    }

    // Normal initialization path (DMG builds, or App Store after onboarding)
    initializeDatabaseComponents()
  }

  /// Initialize database-dependent components. Called during init for DMG builds,
  /// or after onboarding completes for App Store builds.
  private func initializeDatabaseComponents() {
    guard orchestrator == nil else {
      log.warning("[ORCH-INIT] Database components already initialized")
      return
    }

    do {
      let db = DatabaseManager.shared
      let orch = try TranscriptOrchestrator(dbManager: db)
      self.orchestrator = orch
      let fp = FastPathIngestionCoordinator(orchestrator: orch)
      self.fastPath = fp

      Task(priority: .background) {
        log.info("[ORCH-FASTPATH-RESUME] Starting resumePendingCompletions()")
        await fp.resumePendingCompletions()
        log.info("[ORCH-FASTPATH-RESUME] Finished resumePendingCompletions()")
      }

      log.info("[ORCH-INIT] Database components initialized successfully")
    } catch {
      log.error("[ORCH-INIT] Failed to initialize database components: \(error.localizedDescription)")
      // Leave orchestrator/fastPath nil - startup() will fail gracefully
    }
  }

  /// Complete initialization after onboarding. Called by the onboarding flow.
  public func completeOnboardingInitialization() {
    guard !isInitialized else {
      log.info("[ORCH-ONBOARDING] Already initialized, skipping")
      return
    }

    log.info("[ORCH-ONBOARDING] Completing post-onboarding initialization")
    initializeDatabaseComponents()
  }

  /// Configure the access provider for sandbox builds.
  ///
  /// **MUST be called before startup() in App Store builds.**
  ///
  /// Components that depend on this being set before use:
  /// - `LightweightDiscoveryService`: Uses provider to resolve security-scoped bookmark paths
  /// - `startup()`: Runs discovery which needs the provider for correct filesystem access
  /// - JIT ingest and sandbox file watchers (via TranscriptOrchestrator)
  ///
  /// The ordering is enforced by:
  /// - DEBUG precondition in `startup()` that checks `accessProvider != nil` for sandbox builds
  /// - Release error logging if startup runs without provider configured
  public func configureAccessProvider(_ provider: TranscriptAccessProvider) async {
    self.accessProvider = provider
    await discovery.configure(accessProvider: provider)
    log.info("[ORCH-CONFIG] Access provider configured")
  }

  /// Update state and notify observers
  private func setState(_ newState: AppState) {
    self.state = newState
    // Post notification for compatibility with NotificationCenter observers
    NotificationCenter.default.post(name: .appStateDidChange, object: newState)
    log.debug("[ORCH-STATE] State changed to: \(String(describing: newState))")
  }

  // MARK: - Startup Flow

  /// Performs lightweight startup: filesystem scan only, NO DB writes.
  /// Expected duration: <200ms
  ///
  /// **App Store builds call sequence:**
  /// 1. `configureAccessProvider(_:)` - Must be called first to enable sandbox access
  /// 2. `startup()` - Runs initial discovery, then starts background discovery
  ///
  /// **Background discovery lifecycle:**
  /// Background discovery (Claude watcher + Codex polling) starts once per process and runs
  /// until termination. This is intentional for the singleton `AppStateOrchestrator.shared`.
  /// The `stopBackgroundDiscovery()` method exists for cleanup but is not called in normal
  /// operation since the orchestrator lives for the process lifetime.
  ///
  /// **Precondition (App Store builds):**
  /// Onboarding must be complete before startup() is called. This is enforced via
  /// precondition to catch any code path that bypasses the pipeline gate.
  public func startup() async {
    // Defense-in-depth: Catch any code path that bypasses the onboarding gate
    #if APPSTORE_BUILD
    precondition(
      !Sandbox.isSandboxed || HUDPreferences.hasCompletedAppStoreOnboarding(),
      "AppStateOrchestrator.startup() called before App Store onboarding complete"
    )
    #endif

    // Defense-in-depth: Ensure access provider is configured in sandbox builds
    #if DEBUG
    if Sandbox.isSandboxed {
      precondition(
        accessProvider != nil,
        "AppStateOrchestrator.startup() called in sandbox without configured TranscriptAccessProvider. " +
        "Call configureAccessProvider() first."
      )
    }
    #else
    // Release builds: log error instead of crashing
    if Sandbox.isSandboxed && accessProvider == nil {
      log.error("[ORCH-STARTUP] BUG: startup() called without a configured access provider in sandbox build. Discovery will fail.")
    }
    #endif

    log.info("[ORCH-STARTUP] Beginning lightweight startup...")
    let startTime = Date()

    setState(.discovering)

    // 1. Lightweight Scan (stat-only, no file reads, no DB writes)
    let projects = await discovery.discoverProjectsLightweight()
    self.knownProjects = projects
    rebuildProjectLookup(with: projects)
    log.info("[ORCH-STARTUP] Discovered \(projects.count, privacy: .public) projects")

    // 2. Update projects table metadata ONLY (single transaction, no transcripts)
    if let orchestrator {
      do {
        try await orchestrator.updateProjectsMetadataOnly(projects)
        log.debug("[ORCH-STARTUP] Updated projects table metadata")
        try orchestrator.seedDisplayOrderFromDiscoveryIfUnset(projects)
      } catch {
        log.error("[ORCH-STARTUP] Failed to update project metadata: \(error.localizedDescription, privacy: .public)")
      }
    } else {
      log.warning("[ORCH-STARTUP] Orchestrator not initialized, skipping metadata update")
    }

    // 3. Show UI immediately
    setState(.idle(projects: projects))

    let duration = Date().timeIntervalSince(startTime)
    log.info("[ORCH-STARTUP] Startup complete in \(String(format: "%.3f", duration), privacy: .public)s. UI ready.")

    // Post notification that discovery is complete (enables ProjectActivityMonitor FSEvents)
    NotificationCenter.default.post(name: .projectsDiscoveryComplete, object: nil)
    log.info("[ORCH-NOTIFY] Posted .projectsDiscoveryComplete (isActive=\(NSApp.isActive, privacy: .public), keyWindow=\(NSApp.keyWindow != nil, privacy: .public))")

    // 4. PATCH C: Auto-select most recent project (projects are already sorted by activity)
    if let mostRecent = projects.first {
      log.info("[ORCH-STARTUP] Auto-selecting most recent project: \(mostRecent.id, privacy: .public)")
      await selectProject(id: mostRecent.id)
    } else {
      log.info("[ORCH-STARTUP] No projects found - showing empty state")

      // Sandbox builds: Show welcome modal after discovery confirms no projects
      // DMG builds handle this in initializeProjectsSystem() based on DB state
      if Sandbox.isSandboxed {
        log.info("[ORCH-STARTUP] No projects found after discovery (sandbox) - triggering welcome modal")
        NotificationCenter.default.post(name: .startupRequiresWelcomeModal, object: nil)
      }

      // 5. Optional: Start background indexing (low priority)
      startBackgroundIndexing()
    }

    // 6. Start background discovery for App Store builds
    // Claude: directory watcher (flat structure)
    // Codex: polling timer (nested date-based structure)
    #if APPSTORE_BUILD
    log.info("[ORCH-STARTUP] App Store build detected, starting background discovery")
    startBackgroundDiscovery()
    #else
    log.debug("[ORCH-STARTUP] DMG build - background discovery disabled (uses FSEvents instead)")
    #endif
  }

  // MARK: - Background Discovery (App Store)

  #if APPSTORE_BUILD
  /// Start background discovery mechanisms for sandboxed builds.
  /// Claude uses directory watching; Codex uses polling due to nested structure.
  private func startBackgroundDiscovery() {
    guard let provider = accessProvider else {
      log.warning("[ORCH-BACKGROUND-DISCOVERY] Access provider not configured, skipping background discovery")
      return
    }

    // Claude: Directory watcher (flat ~/.claude/projects/ structure)
    sandboxedWatcher = SandboxedDirectoryWatcher(accessProvider: provider)
    sandboxedWatcher?.startWatching()

    // Codex: Polling timer (nested ~/.codex/sessions/YYYY/MM/DD/ structure)
    // Directory watching doesn't work for nested structures - new files in existing
    // date folders won't trigger events on the root directory.
    startCodexPolling()

    log.info("[ORCH-BACKGROUND-DISCOVERY] Started: Claude=watcher, Codex=\(codexPollInterval)s poll")
  }

  /// Start polling timer for Codex project discovery.
  private func startCodexPolling() {
    codexPollTimer?.invalidate()
    codexPollTimer = Timer.scheduledTimer(withTimeInterval: codexPollInterval, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        await self.refreshProjects()
      }
    }
    // Fire once immediately to catch any projects created during startup
    codexPollTimer?.fire()
  }

  /// Stop background discovery mechanisms.
  private func stopBackgroundDiscovery() {
    sandboxedWatcher?.stopWatching()
    sandboxedWatcher = nil
    codexPollTimer?.invalidate()
    codexPollTimer = nil
    log.info("[ORCH-BACKGROUND-DISCOVERY] Stopped")
  }
  #endif

  // MARK: - Project Refresh

  /// Re-run lightweight discovery to find new projects (App Store sandbox builds)
  /// Called when app becomes active or via manual refresh
  /// Does NOT change current selection - only updates available projects list
  public func refreshProjects() async {
    // Reentrancy guard - skip if refresh already in progress
    guard !isRefreshing else {
      log.info("[ORCH-REFRESH] Skip - refresh already in progress")
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }

    log.info("[ORCH-REFRESH] Beginning project refresh...")
    let startTime = Date()

    // Re-run lightweight scan
    let projects = await discovery.discoverProjectsLightweight()

    // Check for new projects
    let existingIds = Set(knownProjects.map { $0.id })
    let newProjects = projects.filter { !existingIds.contains($0.id) }

    if !newProjects.isEmpty {
      log.info("[ORCH-REFRESH] Found \(newProjects.count, privacy: .public) new project(s)")
      for project in newProjects {
        log.info("[ORCH-REFRESH-NEW] \(project.displayName, privacy: .public) at \(project.canonicalRootPath, privacy: .public)")
      }
    }

    // Check if active project has new transcript files (e.g., Codex merged into Claude)
    // If so, re-ingest to pick up the new entries
    var activeProjectNeedsReIngest = false
    if case .active(let currentId) = state {
      if let oldProject = knownProjects.first(where: { $0.id == currentId }),
         let newProject = projects.first(where: { $0.id == currentId }) {
        let oldFileCount = oldProject.transcriptFiles.count
        let newFileCount = newProject.transcriptFiles.count
        if newFileCount > oldFileCount {
          log.info("[ORCH-REFRESH] Active project \(currentId, privacy: .public) has new transcript files: \(oldFileCount) -> \(newFileCount)")
          activeProjectNeedsReIngest = true
        }
      }
    }

    // Update state
    self.knownProjects = projects
    rebuildProjectLookup(with: projects)

    // Update DB metadata for new projects
    if let orchestrator {
      do {
        try await orchestrator.updateProjectsMetadataOnly(projects)
        try orchestrator.seedDisplayOrderFromDiscoveryIfUnset(projects)
      } catch {
        log.error("[ORCH-REFRESH] Failed to update project metadata: \(error.localizedDescription, privacy: .public)")
      }
    }

    // Update state (preserve current active project)
    if case .active(let currentId) = state {
      setState(.active(projectId: currentId))

      // Re-ingest active project if new transcript files were discovered
      // This handles cases like Codex transcripts merging into a Claude project
      if activeProjectNeedsReIngest, let project = projectLookup[currentId], let fastPath {
        log.info("[ORCH-REFRESH] Re-ingesting active project to pick up new transcripts")
        do {
          let dbProjectId = try await fastPath.ingestProjectJIT(project)
          // Notify timeline to refresh
          NotificationCenter.default.post(name: .projectDidActivate, object: dbProjectId)
          log.info("[ORCH-REFRESH] Re-ingestion complete, posted .projectDidActivate")
        } catch {
          log.error("[ORCH-REFRESH] Re-ingestion failed: \(error.localizedDescription, privacy: .public)")
        }
      }
    } else {
      setState(.idle(projects: projects))
    }

    // Notify observers of updated project list
    NotificationCenter.default.post(name: .projectsDiscoveryComplete, object: nil)
    log.info("[ORCH-NOTIFY] Posted .projectsDiscoveryComplete from refresh (isActive=\(NSApp.isActive, privacy: .public), keyWindow=\(NSApp.keyWindow != nil, privacy: .public))")

    let duration = Date().timeIntervalSince(startTime)
    log.info("[ORCH-REFRESH] Refresh complete in \(String(format: "%.3f", duration), privacy: .public)s. Projects: \(projects.count, privacy: .public)")
  }

  // MARK: - User Selection Flow

  /// User clicked a project - perform JIT (Just-In-Time) ingestion
  /// Expected duration: <1s for typical project
  public func selectProject(id: String) async {
    log.info("[ORCH-SELECT] User selected project: \(id, privacy: .public)")

    // 1. Cancel background work
    backgroundTask?.cancel()
    await fastPath?.cancel()

    // Look up project - first try direct ID match
    var project = projectLookup[id]

    // Derive canonical path for multi-provider merge check
    let canonicalPath: String
    if let existing = project {
      // Normal case: ID is a known project; use its canonicalRootPath
      canonicalPath = existing.canonicalRootPath
    } else {
      // Defensive: if id is actually a path (e.g. canonicalRootPath), canonicalize it
      canonicalPath = PathUtils.canonicalizePath(id)
    }

    // Invariant: canonicalRootPath must be stable and identical across providers
    // (Claude hash directory vs Codex CWD) for the same real project. If this
    // changes, multi-provider merging here will silently misbehave.
    let matchingProjects = projectLookup.values.filter { $0.canonicalRootPath == canonicalPath }

    // Merge if: multiple providers found, OR direct lookup failed but canonical match exists
    if matchingProjects.count > 1 || (project == nil && !matchingProjects.isEmpty) {
      precondition(!matchingProjects.isEmpty, "Entered merge branch with empty matchingProjects; check canonicalPath logic.")

      log.info("[ORCH-SELECT-CANONICAL] Found \(matchingProjects.count, privacy: .public) project(s) by canonical path: \(canonicalPath, privacy: .public)")

      let mergedFiles = matchingProjects.flatMap { $0.transcriptFiles }
      let primaryProject = matchingProjects.max { $0.lastActivity < $1.lastActivity }!

      project = LightweightProject(
        id: id,  // Preserve the UI/DB ID for downstream consistency
        path: primaryProject.path,
        displayName: primaryProject.displayName,
        transcriptCount: mergedFiles.count,
        lastActivity: primaryProject.lastActivity,
        provider: matchingProjects.count > 1 ? "multi" : primaryProject.provider,
        cwd: primaryProject.cwd,
        transcriptFiles: mergedFiles
      )

      let providers = Set(matchingProjects.map { $0.provider }).sorted()
      log.info("[ORCH-SELECT-MERGE] Merged \(mergedFiles.count, privacy: .public) transcript files from \(matchingProjects.count, privacy: .public) provider(s): \(providers, privacy: .public)")
    }

    // DB fallback if still not found
    if project == nil, let orchestrator {
      log.warning("[ORCH-SELECT-MISS] Project ID \(id, privacy: .public) not in cache; attempting DB fallback")
      do {
        if let dbProject = try orchestrator.getProject(id: id) {
          let cwd = dbProject.rootPath
          let name = dbProject.name ?? URL(fileURLWithPath: cwd).lastPathComponent
          project = LightweightProject(
            id: dbProject.id,
            path: URL(fileURLWithPath: cwd),
            displayName: name,
            transcriptCount: 0,
            lastActivity: Date(),
            provider: "db_fallback",
            cwd: cwd,
            transcriptFiles: []
          )
          cacheProject(project!)
          log.info("[ORCH-SELECT-DB-PATCH] Hydrated project \(id, privacy: .public) from DB")
        }
      } catch {
        log.error("[ORCH-SELECT-DB-PATCH] DB lookup failed: \(error.localizedDescription, privacy: .public)")
      }
    }

    guard let project else {
      log.error("[ORCH-SELECT] Project not found after DB fallback: \(id, privacy: .public)")
      setState(.error("Project not found"))
      return
    }

    // 2. UI Loading State
    setState(.loading(projectId: id))

    let startTime = Date()
    log.info("[ORCH-SELECT] Loading project: \(project.path.lastPathComponent, privacy: .public)")

    guard let fastPath else {
      log.error("[ORCH-SELECT] FastPath not initialized - onboarding may not be complete")
      setState(.error("Database not ready. Please complete onboarding."))
      return
    }

    do {
      // 3. JIT Ingestion (FastPath with batching)
      // This will: Ensure DB Project Row -> Populate Transcripts Table -> Process Entries
      let dbProjectId = try await fastPath.ingestProjectJIT(project)
      log.debug("[ORCH-SELECT] JIT ingestion complete, DB project ID: \(dbProjectId, privacy: .public)")

      // 4. Legacy Compatibility Wiring
      // Tell StartupCoordinator about the switch so it can notify ConversationMonitor and other legacy components
      // CRITICAL: Use real project path (cwd) if available, NOT hash folder path
      do {
        let realPath = project.cwd ?? project.path.path
        try await StartupCoordinator.shared.handleExternalProjectSwitch(id: dbProjectId, path: realPath)
        log.debug("[ORCH-SELECT] StartupCoordinator notified with path: \(realPath, privacy: .public)")
      } catch {
        log.warning("[ORCH-SELECT] Failed to notify StartupCoordinator: \(error.localizedDescription, privacy: .public)")
        // Non-fatal - continue with activation
      }

      // 5. Activate
      setState(.active(projectId: id))

      let duration = Date().timeIntervalSince(startTime)
      log.info("[ORCH-SELECT] Project ready in \(String(format: "%.3f", duration), privacy: .public)s")

      // 6. Notify other components (Timeline, etc.)
      NotificationCenter.default.post(name: .projectDidActivate, object: id)

    } catch {
      log.error("[ORCH-SELECT] Failed to load project: \(error.localizedDescription, privacy: .public)")
      setState(.error("Failed to load project: \(error.localizedDescription)"))
    }

    // 6. Resume background work
    startBackgroundIndexing()
  }

  // MARK: - Background Indexing

  /// Low-priority background task to pre-ingest inactive projects
  private func startBackgroundIndexing() {
    backgroundTask?.cancel()

    backgroundTask = Task(priority: .utility) { @MainActor in
      // Wait 5 seconds after user activity before starting
      try? await Task.sleep(nanoseconds: 5_000_000_000)

      log.info("[ORCH-BACKGROUND] Starting background indexing...")

      let activeId: String? = {
        if case .active(let id) = self.state {
          return id
        }
        return nil
      }()

      let candidates = self.knownProjects.filter { project in
        guard let activeId else { return true }
        return project.id != activeId
      }

      let total = candidates.count
      await self.postBackgroundProgress(total: total, remaining: total)

      // Ingest projects one at a time, checking for cancellation
      for (index, project) in candidates.enumerated() {
        if Task.isCancelled {
          log.info("[ORCH-BACKGROUND] Indexing cancelled")
          await self.postBackgroundProgress(total: total, remaining: total - index)
          break
        }

        // Ingest this project
        guard let fastPath = self.fastPath else {
          log.warning("[ORCH-BACKGROUND] FastPath not initialized, stopping background indexing")
          break
        }
        do {
          try await fastPath.ingestProjectJIT(project)
          log.debug("[ORCH-BACKGROUND] Ingested project: \(project.id, privacy: .public)")
        } catch {
          log.warning("[ORCH-BACKGROUND] Failed to ingest \(project.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        await self.postBackgroundProgress(total: total, remaining: total - (index + 1))

        // Yield between projects
        await Task.yield()
      }

      log.info("[ORCH-BACKGROUND] Background indexing complete")
      await self.postBackgroundProgress(total: total, remaining: 0)
    }
  }

  @MainActor
  private func postBackgroundProgress(total: Int, remaining: Int) {
    NotificationCenter.default.post(
      name: .backgroundIngestProgress,
      object: nil,
      userInfo: [
        "total": total,
        "remaining": remaining
      ]
    )
  }

  private func rebuildProjectLookup(with projects: [LightweightProject]) {
    var map: [String: LightweightProject] = [:]
    for project in projects {
      map[project.id] = project
    }
    projectLookup = map
  }

  private func cacheProject(_ project: LightweightProject) {
    projectLookup[project.id] = project
  }
}

// MARK: - Supporting Types

/// Lightweight project metadata (no DB required)
public struct LightweightProject: Sendable, Identifiable, Hashable {
  public let id: String
  public let path: URL
  public let displayName: String  // Friendly name derived during discovery
  public let transcriptCount: Int
  public let lastActivity: Date
  public let provider: String
  public let cwd: String?  // Real project path (for Codex) or decoded path (for Claude)
  public let transcriptFiles: [URL]  // File paths discovered during scan (for JIT ingestion)

  public init(id: String, path: URL, displayName: String, transcriptCount: Int, lastActivity: Date, provider: String, cwd: String? = nil, transcriptFiles: [URL] = []) {
    self.id = id
    self.path = path
    self.displayName = displayName
    self.transcriptCount = transcriptCount
    self.lastActivity = lastActivity
    self.provider = provider
    self.cwd = cwd
    self.transcriptFiles = transcriptFiles
  }

  /// Canonical root path used for database identity (defaults to filesystem path if decoding fails).
  public var canonicalRootPath: String {
    PathUtils.canonicalizePath(cwd ?? path.path)
  }
}

// MARK: - Notifications

extension Notification.Name {
  public static let projectDidActivate = Notification.Name("projectDidActivate")
  public static let appStateDidChange = Notification.Name("appStateDidChange")
  public static let backgroundIngestProgress = Notification.Name("backgroundIngestProgress")
  public static let projectsDiscoveryComplete = Notification.Name("contextify.projectsDiscoveryComplete")
}
