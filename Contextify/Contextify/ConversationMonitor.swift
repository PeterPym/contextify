import Foundation
import Observation
import OSLog
import ContextifyCore
import AppKit
import SwiftUI

// Note: sha1Hex() extension moved to StringExtensions.swift
// Note: CursorPersistence actor merged into TimelineDataLoader

// MARK: - Timeline State

/// Single-source container for timeline entries and derived cache index
@MainActor
@Observable
final class TimelineState {
    var entries: [TimelineEntry] = []
    private(set) var revision: UInt64 = 0

    // Cached index map - rebuilt only when entries change (performance optimization)
    // Uses uniquingKeysWith to handle duplicate cache keys (keeps latest index)
    @ObservationIgnored private var _indexByCacheKey: [CacheKey: Int] = [:]
    @ObservationIgnored private var _byID: [UUID: TimelineEntry] = [:]

    var indexByCacheKey: [CacheKey: Int] {
        _indexByCacheKey
    }

    /// O(1) lookup of entry by ID (internal - use ConversationMonitor.lookup for external access)
    fileprivate func lookup(_ id: UUID) -> TimelineEntry? {
        _byID[id]
    }

    private func rebuildCacheIndex() {
        _indexByCacheKey = Dictionary(
            entries.enumerated().compactMap { i, e in
                e.cacheKey.map { ($0, i) }
            },
            uniquingKeysWith: { _, new in new }  // Keep latest index on collision
        )
        _byID = Dictionary(uniqueKeysWithValues: entries.lazy.map { ($0.id, $0) })
    }

    func replace(with entries: [TimelineEntry]) {
        self.entries = entries
        revision &+= 1
        rebuildCacheIndex()  // Rebuild index once when entries change
    }

    func append(_ e: TimelineEntry) {
        entries.append(e)
        revision &+= 1
        // Update cache index incrementally
        if let key = e.cacheKey {
            _indexByCacheKey[key] = entries.count - 1
        }
        _byID[e.id] = e
    }

    func update(at index: Int, to newValue: TimelineEntry) {
        guard entries.indices.contains(index) else { return }

        // Atomic cache index update: remove old key, then add new key
        let oldKey = entries[index].cacheKey
        let oldID = entries[index].id
        entries[index] = newValue
        revision &+= 1

        // Remove stale mapping if cache key changed
        if let oldKey, oldKey != newValue.cacheKey {
            _indexByCacheKey.removeValue(forKey: oldKey)
        }

        // Add new mapping
        if let newKey = newValue.cacheKey {
            _indexByCacheKey[newKey] = index
        }

        // Update ID index
        if oldID != newValue.id {
            _byID.removeValue(forKey: oldID)
        }
        _byID[newValue.id] = newValue
    }

    func sortChronologically() {
        entries.sort { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.sourceIdentifier < b.sourceIdentifier
        }
        revision &+= 1
        rebuildCacheIndex()  // Full rebuild needed after sort changes indices
    }

    func trim(to max: Int) {
        if entries.count > max {
            entries = Array(entries.suffix(max))
            revision &+= 1
            rebuildCacheIndex()  // Full rebuild needed after trim changes indices
        }
    }
}

@Observable
@MainActor
final class ConversationMonitor {
    static let shared = ConversationMonitor()

    private let log = Logger(subsystem: "dev.contextify.timeline", category: "ConversationMonitor")
    private let config = MonitorConfig()
    // conversationResolver removed - now using database-backed session discovery
    private let affirmativeLexicon: Set<String> = [
        "yes", "y", "ok", "okay", "sure", "👍", "yep", "yup", "sounds", "good", "go", "ahead",
        "proceed", "do", "it", "please", "sgtm", "roger", "affirmative", "yeah", "yah", "make", "so"
    ]
    private let negativeLexicon: Set<String> = [
        "no", "nope", "nah", "not", "now", "yet", "hold", "off", "stop", "don't", "do", "cancel", "abort"
    ]
    private let actionHintCues: [String] = [
        "would you like me to", "shall i", "i can ", "i will ",
        "proceed", "change it to", "ensure ", "run ", "fix ", "update ", "refactor ", "implement "
    ]

    /// Explicit phase tracking for timeline state machine
    enum Phase: String {
        case cold      // Not yet loaded
        case loading   // SQL fetch in progress
        case loaded    // Feed loaded successfully
        case failed    // Load failed
    }

    private let state = TimelineState()

    /// Timeline load phase (tracked, drives UI state)
    private(set) var phase: Phase = .cold

    /// Revision counter to force SwiftUI updates when entries change
    /// This ensures the UI reacts to state.entries changes
    /// Note: We track both entriesRevision (incremented manually) and state.revision (incremented by TimelineState)
    private(set) var entriesRevision: Int = 0

    /// Expose state revision for SwiftUI observation (state itself is private let, so changes don't propagate)
    var stateRevision: UInt64 { state.revision }

    /// Read-only view over state.entries (single source of truth)
    var entries: [TimelineEntry] { state.entries }

    /// Maximum number of entries to display (tuneable for performance)
    private let visibleEntryLimit = 25

    /// All entries are visible - sessions appear as one continuous stream
    /// No filtering by session - timeline shows chronological view across all sessions
    /// Limited for performance (tuneable via visibleEntryLimit)
    var visibleEntries: [TimelineEntry] {
        // Force SwiftUI to track this property by reading both revision counters
        _ = entriesRevision  // Manually incremented
        _ = stateRevision    // Auto-incremented by TimelineState (must use public property for observation)
        let n = max(visibleEntryLimit, 1)
        return state.entries.count > n
          ? Array(state.entries.suffix(n))
          : state.entries
    }

    /// O(1) lookup of any entry in current timeline by ID
    func lookup(_ id: UUID) -> TimelineEntry? {
        state.lookup(id)
    }

    private(set) var isMonitoring = false
    private var isSwitchingProjects = false  // CXT-13: Suppress health monitoring during project switch
    private var isInitializing = false  // Prevent duplicate loadFeedFromSQL during startMonitoring
    private(set) var isProcessing = false
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?
    private(set) var allSessionsLastUpdate: Date?
    var autoScroll = true

    @ObservationIgnored private var didEmitSessionStart = false
    // MUST be observable for UI - inventory and session switching depend on this
    private(set) var allSessions: [TranscriptSession] = []
    @ObservationIgnored private var lastUserDirectiveId: UUID?
    @ObservationIgnored private var lastUserDirectiveTimestamp: Date?
    @ObservationIgnored private var sessionEpoch = UUID()  // Track session to cancel cross-session tasks
    // Tracks the currently selected session for inventory UI (not used for timeline filtering)
    private var currentSessionId: String? {
        didSet {
            onProjectOrSessionChange()
        }
    }
    @ObservationIgnored private var currentProjectId: String? {  // SQL project ID
        didSet {
            onProjectOrSessionChange()
        }
    }
    @ObservationIgnored private var lastMonitorRestartRequest: Date?
    @ObservationIgnored private var lastMonitorReadyAt: Date?
    @ObservationIgnored private var monitorRestartGuardTask: Task<Void, Never>?
    @ObservationIgnored private var monitorRestartFailureCount = 0
    @ObservationIgnored private var pendingIdleRestartAlert = false
    // Health monitoring coordinator (extracted to reduce god object complexity)
    @ObservationIgnored private let healthMonitor = HealthMonitoringCoordinator()
    // Timeline data loader (Phase 2 extraction - handles feed loading, cursor, decoration data)
    @ObservationIgnored private var dataLoader: TimelineDataLoader?
    // Viewport tracking coordinator (Phase 1B extraction - handles viewport state machine, visibility)
    @ObservationIgnored private lazy var viewportCoordinator: ViewportTrackingCoordinator = {
        let coord = ViewportTrackingCoordinator()
        coord.delegate = self
        return coord
    }()
    // Cache coordination (Phase 3 extraction - handles cache miss creation, queue management)
    @ObservationIgnored private lazy var cacheCoordinator: TimelineCacheCoordinator = {
        let coord = TimelineCacheCoordinator()
        coord.delegate = self
        return coord
    }()
    @ObservationIgnored private var lastSeenCursor: EntryCursor?  // P1-4: Keyset cursor for incremental updates (persisted per project)
    @ObservationIgnored var orchestrator: TranscriptOrchestrator!
    /// Legacy: seenEntryIDs for dedup. Main paths (loadFeedFromSQL, processIncrementalUpdate)
    /// now use TimelineDataLoader's seenEntryIDs. This local copy is only used by
    /// switchToSessionFromUser and related legacy paths.
    @ObservationIgnored private var seenEntryIDs = Set<String>()
    @ObservationIgnored private var spawnedAgentsLookup: [String: TranscriptOrchestrator.AgentDecorationInfo] = [:]  // entry.id -> agent decoration info
    @ObservationIgnored private var contextifyEntryIds: Set<String> = Set()  // entry IDs for Contextify calls
    @ObservationIgnored private var contextifyEntryInfo: [String: TranscriptOrchestrator.ContextifyEntryInfo] = [:]  // toolKey + isResult for Contextify entries
    @ObservationIgnored private var backgroundTasks: Task<Void, Never>?  // Parent task for all background work
    private(set) var cacheMissGenerator: TimelineCacheMissGenerator?  // Background cache generation
    // Observable flag for status bar - avoids exposing non-Sendable generator object
    private(set) var isCacheGeneratorActive = false
    // IMPORTANT: nonisolated(unsafe) is REQUIRED for observer tokens.
    // NSObjectProtocol is not Sendable, so removing nonisolated(unsafe) causes:
    // "cannot access property 'X' with a non-Sendable type from nonisolated deinit"
    // These tokens must be accessed in deinit to removeObserver(), which is nonisolated.
    // This pattern has been suggested for removal multiple times but MUST be kept.
    @ObservationIgnored nonisolated(unsafe) private var cacheUpdateObserver: NSObjectProtocol?   // For cache update notifications
    @ObservationIgnored nonisolated(unsafe) private var projectChangeObserver: NSObjectProtocol? // For project root change notifications
    @ObservationIgnored nonisolated(unsafe) private var projectsDiscoveryObserver: NSObjectProtocol? // For projects discovery completion
    @ObservationIgnored nonisolated(unsafe) private var primerReadyObserver: NSObjectProtocol? // For primer ready events
    @ObservationIgnored nonisolated(unsafe) private var hooveringProgressObserver: NSObjectProtocol? // For incremental hoovering progress
    @ObservationIgnored nonisolated(unsafe) private var queueOpsObserver: NSObjectProtocol? // For queue operation updates
    @ObservationIgnored private var updateInFlight = false  // Single-flight guard for processIncrementalUpdate
    @ObservationIgnored private var updateDirty = false    // Marks that updates arrived during processing
    @ObservationIgnored private let updateDrainMaxItersDefault = 8  // Max drain loop iterations to prevent starvation
    @ObservationIgnored private var updateDrainItersRemaining = 8  // Current iterations remaining
    @ObservationIgnored private var debounceTask: Task<Void, Never>?  // Debounce task for transcript updates
    @ObservationIgnored private var progressDebounceTask: Task<Void, Never>?  // Debounce task for progress notifications
    @ObservationIgnored private var refreshDebounceTask: Task<Void, Never>?  // Debounce task for timeline refresh (coalesce rapid loadFeedFromSQL calls)
    @ObservationIgnored private var pendingRefreshAfterLoad = false  // Coalesce rapid refresh calls during load
    @ObservationIgnored private var lastProgressRefreshTime: Date?  // Track last progress refresh to enforce minimum interval
    @ObservationIgnored private var refreshHistory: [(trigger: String, timestamp: Date)] = []  // Track refresh frequency for diagnostics
    @ObservationIgnored private var cacheDebounceTask: Task<Void, Never>?  // CXT-13: Debounce cache updates
    @ObservationIgnored private var pendingCacheKeys: Set<CacheKey> = []  // CXT-13: Accumulated cache keys
    @ObservationIgnored private var primerRetryTask: Task<Void, Never>?
    private(set) var isAwaitingPrimer = false

    // v23: Active session follow state
    @ObservationIgnored private var startupTask: Task<Void, Never>?  // P0-2: Cancellable startup sequence
    @ObservationIgnored private var policyEvalTask: Task<Void, Never>?  // P1-2: Debounced policy evaluation
    @ObservationIgnored private var coordinatorTask: Task<Void, Never>?  // Coordinator subscription task
    @ObservationIgnored private var generatorShutdownTask: Task<Void, Never>?  // Exclusive generator handoff
    @ObservationIgnored private var sessionsLoaded = false  // Gate for policy reconciliation
    @ObservationIgnored private var isReadyForUpdates = false  // Gate for incremental updates
    private(set) var followMode: FollowMode = .automatic  // P0-4: Observable for UI
    @ObservationIgnored private var lastActiveKey: SessionKey?
    @ObservationIgnored private var lastSwitchAt: Date?
    @ObservationIgnored private var lastSystemEventTs: Int64?
    @ObservationIgnored private var seenSystemEventIds = Set<String>()
    @ObservationIgnored private let policyEngine = ActiveSessionPolicyEngine()
    // Note: Cursor persistence now handled by TimelineDataLoader actor
    private(set) var activeSession: TranscriptSession?  // Observable for UI (v23: actively followed session)

    // Health monitoring and diagnostics
    @ObservationIgnored private var diagnosticsService: TimelineDiagnosticsService?

    // Viewport tracking and background summarization
    @ObservationIgnored private var backgroundFillTask: Task<Void, Never>?  // Background summarization task
    @ObservationIgnored private var lastLoadCompletionTime: Date?  // Timestamp of last loadFeedFromSQL completion for timing
    @ObservationIgnored private var feedHydrationTask: Task<Void, Never>?  // Cancelable hydration work item
    @ObservationIgnored private var feedLoadGeneration: UInt64 = 0  // Monotonic token to gate async load application
    var debugVisibleIDs = Set<UUID>()  // Observable for debug visualization in timeline rows
    // IMPORTANT: nonisolated(unsafe) is REQUIRED - see comment above cacheUpdateObserver
    @ObservationIgnored nonisolated(unsafe) private var appLifecycleObserver: NSObjectProtocol?  // App lifecycle notifications
    @ObservationIgnored nonisolated(unsafe) private var appBecomeActiveObserver: NSObjectProtocol? // App become active notifications

    // Viewport coordinator accessors
    private var needsInitialVisibilitySnapshot: Bool {
        viewportCoordinator.needsInitialVisibilitySnapshot
    }

    private var initialViewportAwaitingContext: InitialViewportStateMachine.Context? {
        viewportCoordinator.awaitingContext
    }

    private var activeInitialViewportContext: InitialViewportStateMachine.Context? {
        viewportCoordinator.activeContext
    }

    // P0-4: Computed properties for UI binding
    var isPinnedMode: Bool {
        if case .manual = followMode { return true }
        return false
    }
    var pinnedKey: SessionKey? { followMode.pinnedKey }

    private init() {
        log.info("[TIMELINE-INIT] ConversationMonitor initializing")

        // Set up project change notifications early, so we can react to project selection
        // even if monitoring hasn't started yet
        setupProjectChangeNotifications()

        // Set up projects discovery notifications early, so we can react to ingestion completion
        // even during startup before monitoring is active
        setupProjectsDiscoveryNotifications()
        setupPrimerReadyNotifications()

        // Set up hoovering progress notifications for incremental timeline updates
        setupHooveringProgressNotifications()

        // Subscribe to coordinator updates for project context changes
        subscribeToContextUpdates()

        // Set up app lifecycle notifications for background summarization
        setupAppLifecycleNotifications()

        log.info("[TIMELINE-INIT] ConversationMonitor ready")
    }

    /// Configure shared orchestrator (preferred)
    @MainActor
    func configureSharedOrchestrator(_ orchestrator: TranscriptOrchestrator) {
        self.orchestrator = orchestrator
        self.dataLoader = TimelineDataLoader(orchestrator: orchestrator)
        log.info("[TIMELINE-ORCH] Using shared TranscriptOrchestrator instance")
    }

    /// Subscribe to coordinator updates for project switching
    @MainActor
    private func subscribeToContextUpdates() {
        coordinatorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // P1-REHYDRATE: Check if orchestrator already has an active project
            // This handles the case where startup completed before we started listening
            if let activeId = AppStateOrchestrator.shared.activeProjectId,
               let context = StartupCoordinator.shared.current,
               context.id == activeId {
                log.info("[TIMELINE-REHYDRATE] Found active project on init: \(activeId, privacy: .public)")
                await self.handleContextUpdate(context)
            }

            for await context in StartupCoordinator.shared.updates() {
                await self.handleContextUpdate(context)
            }
        }
    }

    deinit {
        // Cancel any pending debounce task
        debounceTask?.cancel()
        cacheDebounceTask?.cancel()

        // Cancel coordinator subscription task
        coordinatorTask?.cancel()

        // Cancel background task group (health monitoring, polling, etc.)
        backgroundTasks?.cancel()

        // Cancel background fill task
        backgroundFillTask?.cancel()

        // Clean up observers (only relevant for tests/previews, not for singleton)
        if let observer = projectChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = cacheUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = projectsDiscoveryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = primerReadyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appLifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = queueOpsObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        monitorRestartGuardTask?.cancel()
        primerRetryTask?.cancel()

        log.info("ConversationMonitor deinit: cancelled tasks, stopped HTTP server, removed observers")
    }

    @MainActor
    private func scheduleMonitorRestartGuard(for projectId: String) {
        monitorRestartGuardTask?.cancel()
        let requestTimestamp = Date()
        lastMonitorRestartRequest = requestTimestamp

        monitorRestartGuardTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                guard let self else { return }
                guard self.lastMonitorRestartRequest == requestTimestamp else { return }
                if self.isMonitoring && self.currentProjectId == projectId {
                    return
                }
                self.monitorRestartFailureCount &+= 1
                self.pendingIdleRestartAlert = true
                self.log.error("🛑 [MONITOR-IDLE] Timeline still idle 5s after restart request #\(self.monitorRestartFailureCount) for project \(projectId, privacy: .public)")
            }
        }
    }

    @MainActor
    private func acknowledgeMonitorReady(projectId: String) {
        pendingIdleRestartAlert = false
        lastMonitorReadyAt = Date()
        monitorRestartGuardTask?.cancel()
    }

    @MainActor
    func startMonitoring(projectId: String) {
        let taskStart = Date()
        log.info("[TIMELINE-START] Starting timeline monitoring for project: \(projectId, privacy: .public)")
        log.info("📊 [MONITOR-ENTRY] startMonitoring called for \(projectId, privacy: .public)")
        log.info("[UIOPT-MONITOR-START] ConversationMonitor.startMonitoring() called for project: \(projectId, privacy: .public)")
        cancelPrimerRetry(reason: "project-switch")

        // Skip if already monitoring this exact project (prevents duplicate calls during startup)
        // Also skip if projectId is already set (even if not yet monitoring), which means
        // a previous call is in progress
        if (isMonitoring && currentProjectId == projectId) || (currentProjectId == projectId && isInitializing) {
            acknowledgeMonitorReady(projectId: projectId)
            log.info("⚠️ [MONITOR-SKIP] Already monitoring/initializing project \(projectId, privacy: .public), skipping duplicate call")
            return
        }

        // Cancel residual background work before starting new group
        backgroundTasks?.cancel()
        backgroundTasks = nil
        seenEntryIDs.removeAll(keepingCapacity: false)
        // Reset recovery backoff on project switch (user may have fixed permissions)
        Task { await healthMonitor.resetRecoveryBackoff() }

        guard !isMonitoring else {
            log.info("⚠️ [MONITOR-SKIP] Already monitoring different project, need to stop first")
            return
        }

        // Set flag to prevent onProjectOrSessionChange from running during initialization
        isInitializing = true

        // Set currentProjectId immediately (synchronously) to prevent race condition
        // where UI tries to load sessions before this is set
        currentProjectId = projectId
        log.info("📁 Project ID set (sync): \(projectId, privacy: .public)")
        resetInitialViewportState(reason: "start-monitoring")

        log.info("⭐️ [MONITOR-START] Timeline integration starting for project \(projectId, privacy: .public)")

        Task { [weak self] in
            guard let self else { return }
            log.info("🔧 [MONITOR-TASK] Background task started (elapsed: \(String(format: "%.3f", Date().timeIntervalSince(taskStart)))s)")

            // 1. Initialize or reuse orchestrator
            do {
                var orch: TranscriptOrchestrator
                if let shared = await MainActor.run(body: { () -> TranscriptOrchestrator? in
                    self.orchestrator
                }) {
                    orch = shared
                } else {
                    let dbStart = Date()
                    self.log.warning("[UIOPT-DB-INIT] Shared orchestrator not configured; creating local instance (watcher state isolated)")
                    self.log.info("[UIOPT-DB-INIT] Creating TranscriptOrchestrator...")
                    let newlyCreated = try TranscriptOrchestrator(dbManager: .shared)
                    await MainActor.run {
                        self.orchestrator = newlyCreated
                        self.log.info("[UIOPT-DB-INIT] TranscriptOrchestrator created in \(String(format: "%.0f", Date().timeIntervalSince(dbStart) * 1000), privacy: .public)ms")
                    }
                    orch = newlyCreated
                }

                // Verify project was persisted (forces read from DB, ensures commit)
                // Use projectId parameter directly (already have it from function arg)
                // Note: Non-fatal check - if project doesn't exist yet (race condition during
                // startup before ingestion), we proceed anyway and reload after ingestion completes
                if let _ = try orch.getProject(id: projectId) {
                    await MainActor.run {
                        self.log.info("✅ Project \(projectId, privacy: .public) verified in database")
                    }
                } else {
                    await MainActor.run {
                        self.log.warning("⚠️ Project \(projectId, privacy: .public) not in database yet (startup race condition), will refresh after ingestion completes")
                    }
                }

                // 3. Shutdown old cache miss generator with chained shutdown (CXT-1)
                // CRITICAL: Capture previous shutdown task BEFORE creating new one to chain them
                // On rapid A→B→C switches, this ensures A shuts down, THEN B, THEN C (serialized)
                // Without chaining: A and B shutdown concurrently → SQLITE_BUSY
                let (previousShutdownTask, oldGenerator, orchestratorForGenerator) = await MainActor.run {
                    (self.generatorShutdownTask, self.cacheMissGenerator, self.orchestrator!)
                }

                if let oldGenerator = oldGenerator {
                    let shutdownTask = Task(priority: .utility) {
                        // First await previous shutdown (if any)
                        await previousShutdownTask?.value
                        // Then shutdown this generator
                        await oldGenerator.shutdown()
                    }
                    await MainActor.run {
                        self.generatorShutdownTask = shutdownTask
                    }
                }
                await MainActor.run {
                    self.cacheMissGenerator = nil  // Clear before creating new
                    self.isCacheGeneratorActive = false
                }

                // 4. Create new generator in background after shutdown completes (CXT-3, CXT-9)
                // Don't block UI - spawn background task that awaits shutdown then creates generator
                // UI returns immediately, generator initializes when safe
                // CXT-9: Removed @MainActor to prevent blocking UI on second switch
                Task { [weak self] in
                    // Wait for chained shutdown to complete (happens in background, off main actor)
                    await self?.generatorShutdownTask?.value

                    // Now safe to create new generator (old one fully shut down)
                    guard let self else { return }
                    log.info("[GENERATOR-INIT] About to create generator...")
                    await MainActor.run {
                        self.log.info("[GENERATOR-INIT] Creating TimelineCacheMissGenerator...")
                        self.cacheMissGenerator = TimelineCacheMissGenerator(orchestrator: orchestratorForGenerator)
                        self.isCacheGeneratorActive = true
                        self.generatorShutdownTask = nil
                        self.log.info("✅ [GENERATOR-INIT] Cache miss generator initialized for new project")
                        self.replayPendingInitialViewportSnapshot(reason: "generator-ready")
                    }
                }

                // Initialize diagnostics service
                let diagnosticsService = try TimelineDiagnosticsService(db: DatabaseManager.shared.pool)
                await MainActor.run {
                    self.diagnosticsService = diagnosticsService
                }

                // 4. Start background work (discovery + debounced updates + health monitoring) in a single parent task
                let orchestrator = orchestratorForGenerator
                await MainActor.run {
                    self.log.info("🚀 Spawning background tasks for project: \(projectId, privacy: .public)")
                }
                let backgroundTasks = Task { [weak self] in
                    guard let self else { return }

                    // Initialize metadata orchestrator with SQL backend (await before use)
                    await TranscriptMetadataOrchestrator.shared.initialize(orchestrator: orchestrator)

                    await withTaskGroup(of: Void.self) { group in
                        // NOTE: Discovery Task removed - ProjectActivityMonitor handles all transcript
                        // discovery via FSEvents. Redundant filesystem scanning removed.

                        // Task 1: Debounced transcript updates
                        group.addTask { [weak self] in
                            await self?.watchForDebouncedTranscriptUpdates()
                        }

                        // Task 2: Health monitoring with auto-recovery (via coordinator)
                        group.addTask { [weak self] in
                            guard let self else { return }
                            await self.healthMonitor.startMonitoring(
                                contextProvider: { [weak self] in
                                    await MainActor.run {
                                        // P1.1: Don't pass orchestrator across actor boundary
                                        HealthMonitoringCoordinator.HealthCheckContext(
                                            projectId: self?.currentProjectId,
                                            hasOrchestrator: self?.orchestrator != nil,
                                            isSwitchingProjects: self?.isSwitchingProjects ?? false,
                                            hasPendingIdleAlert: self?.pendingIdleRestartAlert ?? false
                                        )
                                    }
                                },
                                diagnosticsProvider: { [weak self] in
                                    await self?.captureDiagnostics()
                                },
                                recoveryHandler: { [weak self] action in
                                    await self?.handleRecoveryAction(action)
                                },
                                idleAlertHandler: { [weak self] in
                                    await MainActor.run {
                                        self?.pendingIdleRestartAlert = false
                                    }
                                }
                            )
                        }
                    }
                }
                await MainActor.run {
                    self.backgroundTasks = backgroundTasks
                }

                // 5. Load initial feed (fast - single query) so the timeline is not blank
                let feedStart = Date()
                log.info("[UIOPT-FEED-START] Loading initial feed from SQL...")
                await self.loadFeedFromSQL()?.value
                log.info("[UIOPT-FEED-DONE] Feed loaded in \(Date().timeIntervalSince(feedStart)*1000, privacy: .public)ms")

                // 6. Subscribe to realtime updates (SQL notifications handled by watchForDebouncedTranscriptUpdates)
                // self.setupSQLNotifications()  // Disabled: debouncing is handled by background watcher
                await MainActor.run {
                    self.setupCacheUpdateNotifications()
                    // Project change and projects discovery notifications already set up in init()

                    self.isMonitoring = true
                    self.isInitializing = false  // Clear flag after successful initialization
                    self.acknowledgeMonitorReady(projectId: projectId)
                    self.log.info("SQL-based timeline monitoring started (projectId: \(projectId, privacy: .public))")
                    self.log.info("[UIOPT-MONITOR-READY] ConversationMonitor is now monitoring and ready")
                }
                NotificationCenter.default.post(name: .conversationMonitoringDidStart, object: nil)
            } catch {
                await MainActor.run {
                    self.lastError = "Failed to start monitoring: \(error.localizedDescription)"
                    self.isInitializing = false  // Clear flag on error
                    self.log.error("Monitoring startup failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @MainActor
    func stopMonitoring() {
        log.info("[TIMELINE-STOP] Stopping timeline monitoring")
        isMonitoring = false
        lastMonitorReadyAt = nil
        activeSession = nil
        let projectIdAtStop = currentProjectId

        // Cancel any in-flight feed hydration to prevent late UI mutation after teardown
        let hydrationTask = feedHydrationTask
        feedHydrationTask = nil
        hydrationTask?.cancel()

        // Cancel background task group
        // P1.2: backgroundTasks?.cancel() does NOT stop health monitoring - must call stopMonitoring()
        backgroundTasks?.cancel()
        backgroundTasks = nil
        // Stop health monitoring coordinator (required - not coupled to TaskGroup cancellation)
        Task { await healthMonitor.stopMonitoring() }

        // CXT-101: Cancel viewport/background-fill work (atomic capture-nil-cancel)
        let bfTask = backgroundFillTask
        backgroundFillTask = nil
        bfTask?.cancel()

        // Reset all viewport tracking state via coordinator
        viewportCoordinator.fullReset(reason: "stop-monitoring")

        // Reset data loader state (cursor, seenIDs, decoration data)
        if let loader = dataLoader {
            Task { await loader.resetIfProjectMatches(projectIdAtStop, clearCursor: true, reason: "stop-monitoring") }
        }

        // Cancel any pending startup/policy evaluation work
        startupTask?.cancel()
        startupTask = nil
        policyEvalTask?.cancel()
        policyEvalTask = nil

        debounceTask?.cancel()
        debounceTask = nil
        cacheDebounceTask?.cancel()  // CXT-13: Cancel cache update debounce
        cacheDebounceTask = nil
        pendingCacheKeys.removeAll()
        pendingRefreshAfterLoad = false  // Clear pending refresh on stop
        // CXT-13: Do NOT cancel coordinatorTask here! It must persist across project switches
        // to continue receiving updates. It's only canceled in deinit.

        if let observer = cacheUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
            cacheUpdateObserver = nil
        }

        // NOTE: Do NOT remove projectChangeObserver here! It needs to persist across
        // project switches so we can receive notifications for subsequent switches.
        // It's set up once in init() and should only be removed in deinit.

        // Stop all watchers using shared orchestrator
        if orchestrator != nil {
            orchestrator.stopAllWatchers()
        }

        // Clear state
        seenEntryIDs.removeAll()
        lastSeenCursor = nil
        currentProjectId = nil
        cacheMissGenerator = nil
        isCacheGeneratorActive = false
        debugVisibleIDs.removeAll()
    }

    /// Cancel pending debounce task on project changes to avoid late callbacks into torn state
    @MainActor
    private func onProjectOrSessionChange() {
        log.debug("onProjectOrSessionChange: projectId=\(self.currentProjectId ?? "nil")")

        // Skip if we're in the middle of startMonitoring() initialization
        // This prevents duplicate loadFeedFromSQL() calls when startMonitoring sets currentProjectId
        // TODO: See TODOS.md - Phase 2/3 refactor to split project vs session change handling
        if isInitializing {
            log.debug("onProjectOrSessionChange: skipping, initialization in progress")
            return
        }

        // Reset all viewport tracking state for new project/session
        viewportCoordinator.fullReset(reason: "project-session-change")

        // Cancel any in-flight feed hydration to prevent late UI mutation during project/session switch
        let hydrationTask = feedHydrationTask
        feedHydrationTask = nil
        hydrationTask?.cancel()

        // P0-2: Cancel prior startup to prevent cross-project races
        startupTask?.cancel()

        // P1: Cancel pending policy evaluation from prior project
        policyEvalTask?.cancel()

        // v23 (P0-2, P1-1): Reset follow state for new project
        isReadyForUpdates = false
        sessionsLoaded = false
        seenSystemEventIds.removeAll()
        lastSystemEventTs = nil

        // Cancel any pending debounced updates (they're for the OLD project)
        if debounceTask != nil {
            log.debug("onProjectOrSessionChange: cancelling pending debounce task")
            debounceTask?.cancel()
            debounceTask = nil
        }

        // Clear ALL pending LLM requests on project/session change
        // Visibility tracking will re-queue only the ~25 visible entries
        if let generator = cacheMissGenerator {
            Task {
                await generator.clearPendingMisses(exceptProjectId: nil)
            }
        }

        // P0-2: Cancellable startup sequence with checkpoints
        // CXT-10: Removed @MainActor to prevent blocking UI during database operations
        startupTask = Task {
            do {
                // Phase 2: Reset loader state before cursor/feed work (avoid reset/load races)
                if let loader = await MainActor.run(body: { self.dataLoader }) {
                    await loader.reset(clearCursor: true, reason: "project-session-change")
                }

                // 1. Load policy from DB (C: restore followMode)
                try Task.checkCancellation()
                await self.loadPolicyForCurrentProject()

                // 2. Load all sessions before reconciliation
                try Task.checkCancellation()
                await self.loadAllSessionsFromDatabase()
                await MainActor.run { self.sessionsLoaded = true }

                // 3. Reconcile policy with available sessions
                try Task.checkCancellation()
                await self.reconcilePolicyWithAvailableSessions()

                // 4. Load persisted cursor (P1-4: restart safety)
                try Task.checkCancellation()
                await self.loadCursor()

                // 5. Load feed and initialize cursor
                try Task.checkCancellation()
                await self.loadFeedFromSQL()?.value

                // 6. Replay switch events
                try Task.checkCancellation()
                await self.loadSwitchEventsFromSQL()

                // 7. Enable incremental updates
                await MainActor.run { self.isReadyForUpdates = true }
            } catch is CancellationError {
                log.debug("Startup cancelled for project switch")
            } catch {
                log.error("Startup failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func resetInitialViewportState(reason: String) {
        viewportCoordinator.reset(reason: reason)
    }

    /// Structured watcher for debounced transcript updates (off main actor, no polling)
    /// Multi-project mode: branch on projectId (not filter)
    private func watchForDebouncedTranscriptUpdates() async {
        let center = NotificationCenter.default
        let name = NSNotification.Name("TranscriptUpdated")

        for await note in center.notifications(named: name) {
            if Task.isCancelled { break }
            let pid = note.userInfo?["projectId"] as? String

            await MainActor.run { [weak self] in
                guard let self else { return }

                // Branch 1: Current project - refresh timeline
                if pid == self.currentProjectId || pid == nil {
                    // Cancel existing debounce task and start new one
                    self.debounceTask?.cancel()
                    self.debounceTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
                        guard let self, !Task.isCancelled else {
                            return
                        }
                        await self.processIncrementalUpdate()
                    }
                }

                // Branch 2: Other project - unread count is DB-derived (no action needed here)
                // ProjectSwitcherState will query unread counts on refresh
            }
        }
    }

    @available(*, unavailable, message: "Use watchForDebouncedTranscriptUpdates()")
    private func handleTranscriptUpdate(projectId: String?) async {}

    /// Legacy: Prune CM's local seenEntryIDs. Only used by switchToSessionFromUser.
    /// Main paths use TimelineDataLoader.pruneSeenIDsIfNeeded() instead.
    @MainActor
    private func pruneSeenIDsIfNeeded() {
        let cap = config.maxEntries * 2
        if seenEntryIDs.count > cap {
            seenEntryIDs = Set(state.entries.map { $0.sourceIdentifier })
        }
    }

    @MainActor
    private func setEntries(_ new: [TimelineEntry]) {
        // ⚠️ IMPORTANT: DO NOT RE-ADD SKIP OPTIMIZATION HERE! ⚠️
        //
        // Skip optimization (if entries == new, return early) causes critical bug:
        // - Query returns top-N entries sorted by MESSAGE TIMESTAMP
        // - New entries with OLDER timestamps don't displace current top-N
        // - Skip logic sees "no change" → prevents UI update
        // - User NEVER sees newly hoovered conversations (data loss from user perspective)
        //
        // Example bug scenario:
        // 1. User hoovered conversation from Nov 14 (old messages)
        // 2. Entries successfully inserted into DB ✅
        // 3. Timeline queries top 25 (ORDER BY message timestamp DESC)
        // 4. Query returns SAME 25 as before (Nov 14 messages older than current top 25)
        // 5. Skip optimization: "entries == new" → return early ❌
        // 6. User never sees Nov 14 conversation in timeline ❌
        //
        // Root cause: Message timestamp ≠ Hoovering timestamp
        // - Timeline sorts by when MESSAGE was sent (e.g., Nov 14)
        // - NOT by when FILE was modified/hoovered (e.g., Nov 16)
        //
        // Fix: ALWAYS update, even if data appears unchanged
        // - If flicker is an issue, address with debouncing/throttling
        // - Never suppress updates based on equality check
        //
        // See commit 7b6207f for detailed explanation and test case

        if state.entries.count == new.count && state.entries == new {
            log.debug("[TIMELINE-SKIP-DISABLED] Data unchanged (\(new.count) entries) but updating anyway (ensures fresh hoovered entries appear)")
            // Fall through to update anyway
        }

        #if DEBUG
        log.info("[TIMELINE-APPEND] setEntries \(new.count) (primer)")
        #endif
        state.replace(with: new)
        entriesRevision += 1  // Force SwiftUI update
        log.info("[VIEWPORT-UPDATE] visibleEntries.count → \(self.visibleEntries.count)")
    }

    @MainActor
    private func appendEntry(_ e: TimelineEntry) {
        let beforeCount = state.entries.count
        state.append(e)
        entriesRevision += 1  // Force SwiftUI update
        let afterCount = state.entries.count

        #if DEBUG
        log.info("[TIMELINE-APPEND] Entry appended: \(e.id, privacy: .public) kind: \(e.kind.rawValue, privacy: .public) timestamp: \(e.timestamp, privacy: .public) timeline_count: \(beforeCount, privacy: .public)→\(afterCount, privacy: .public)")
        #endif
        log.debug("[TIMELINE-APPEND] Summary: \(e.summary.prefix(60), privacy: .public)...")
    }

    @MainActor
    private func updateEntry(at i: Int, with e: TimelineEntry) {
        state.update(at: i, to: e)
    }

    @MainActor
    private func sortEntriesChronologically() {
        state.sortChronologically()
    }

    @MainActor
    private func trimEntries() {
        state.trim(to: config.maxEntries)
    }

    @MainActor
    func clearEntries() {
        setEntries([])
        didEmitSessionStart = false
        lastSeenCursor = nil
        seenEntryIDs.removeAll(keepingCapacity: false)
    }

    /// Handle project context update from StartupCoordinator
    @MainActor
    private func handleContextUpdate(_ context: ActiveProjectContext) async {
        let startTime = Date()
        log.info("🔄 [SWITCH-START] Project switch to \(context.displayName) (id: \(context.id, privacy: .public))")
        log.info("[SUMM-MONITOR] ConversationMonitor received context update for: \(context.displayName) (id: \(context.id))")

        // CXT-13: Set flag to suppress health monitoring during switch
        await MainActor.run { isSwitchingProjects = true }
        defer {
            Task { @MainActor in
                isSwitchingProjects = false
                let elapsed = Date().timeIntervalSince(startTime)
                self.log.info("✅ [SWITCH-END] Project switch completed in \(String(format: "%.2f", elapsed))s")
            }
        }

        // Stop current monitoring
        let stopStart = Date()
        log.info("🛑 [SWITCH-STOP] Stopping monitoring (elapsed: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s)")
        stopMonitoring()
        log.info("🛑 [SWITCH-STOP-DONE] Stop complete in \(String(format: "%.2f", Date().timeIntervalSince(stopStart)))s")

        // Clear all entries
        let clearStart = Date()
        log.info("🧹 [SWITCH-CLEAR] Clearing entries (elapsed: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s)")
        clearEntries()
        log.info("🧹 [SWITCH-CLEAR-DONE] Clear complete in \(String(format: "%.2f", Date().timeIntervalSince(clearStart)))s")

        // Start monitoring with new project ID from coordinator
        let monitorStart = Date()
        log.info("🚀 [SWITCH-MONITOR] Starting monitoring (elapsed: \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s)")
        log.info("[SUMM-MONITOR] Calling startMonitoring(projectId: \(context.id, privacy: .public))")
        scheduleMonitorRestartGuard(for: context.id)
        startMonitoring(projectId: context.id)
        log.info("🚀 [SWITCH-MONITOR-DONE] Monitor start triggered in \(String(format: "%.2f", Date().timeIntervalSince(monitorStart)))s")

        log.info("✅ Project context change complete - monitoring restarted for: \(context.id, privacy: .public)")
    }

    @MainActor
    func handleProjectRootChange() {
        log.info("🔄 Project root changed (legacy notification) - reloading conversation timeline")

        Task { @MainActor [weak self] in
            guard let self else { return }

            if let context = StartupCoordinator.shared.current {
                await self.handleContextUpdate(context)
                return
            }

            do {
                let awaitedContext = try await StartupCoordinator.shared.ready()
                self.log.info("handleProjectRootChange: coordinator context became available after wait (id: \(awaitedContext.id, privacy: .public))")
                await self.handleContextUpdate(awaitedContext)
                return
            } catch {
                self.log.error("handleProjectRootChange: coordinator context unavailable after .ready() wait - \(error.localizedDescription, privacy: .public)")
            }

            guard let fallbackContext = self.fallbackContextFromProjectSwitcher() else {
                self.log.error("handleProjectRootChange: no coordinator context or fallback project; aborting restart")
                return
            }

            self.log.warning("handleProjectRootChange: using fallback context from ProjectSwitcherState for project \(fallbackContext.id, privacy: .public)")
            await self.handleContextUpdate(fallbackContext)
        }
    }

    @MainActor
    private func fallbackContextFromProjectSwitcher() -> ActiveProjectContext? {
        guard let fallbackId = ProjectSwitcherState.shared.activeProjectId else {
            return nil
        }

        guard let info = ProjectSwitcherState.shared.allProjects.first(where: { $0.id == fallbackId }) else {
            return nil
        }

        return ActiveProjectContext(
            id: info.id,
            path: info.rootPath,
            displayName: info.name
        )
    }

    @MainActor
    func requestImmediateRefresh(trigger: TimelineRefreshTrigger) {
        Task { @MainActor in
            await loadFeedFromSQL()?.value
        }
    }

    /// Determine whether timeline still needs a full primer reload (e.g., startup).
    @MainActor
    private func needsPrimerReload() -> Bool {
        if isAwaitingPrimer { return true }
        if state.entries.isEmpty { return true }
        if phase != .loaded { return true }
        if !isReadyForUpdates { return true }
        return false
    }

    /// Public method for user-initiated session switch from transcripts
    @MainActor
    func switchToSessionFromUser(_ session: TranscriptSession) async {
        guard orchestrator != nil else {
            log.warning("Cannot switch session: no orchestrator")
            return
        }

        do {
            // Find transcript by file path across ALL projects (session might be from different project)
            let allProjects = try orchestrator.listProjects()
            var foundTranscript: Transcript? = nil

            for project in allProjects {
                let transcripts = try orchestrator.getTranscripts(forProject: project.id)
                if let transcript = transcripts.first(where: { $0.filePath == session.fileURL.path }) {
                    foundTranscript = transcript
                    break
                }
            }

            guard let transcript = foundTranscript else {
                log.warning("No transcript found for session: \(session.fileURL.path)")
                // Fall back to loading all entries
                await loadFeedFromSQL()?.value
                return
            }

            // Switch to the transcript's project if it's different from current
            if currentProjectId != transcript.projectId {
                log.info("Switching to project \(transcript.projectId) for session \(session.identifier)")
                await ProjectSwitcherState.shared.switchToProject(transcript.projectId)
            }

            // Get entries for this specific transcript
            let transcriptEntries = try orchestrator.getEntries(forTranscript: transcript.id, afterTimestamp: nil)

            // Batch cache lookup for better performance
            let cacheKeys = transcriptEntries.compactMap { entry -> CacheKey? in
                guard let windowSha = entry.windowSha256 else { return nil }
                return CacheKey(content: entry.contentSha256, window: windowSha)
            }

            let cacheMap = try orchestrator.getCachedTimelineMany(keys: cacheKeys)

            // Refresh decoration data for this project
            refreshDecorationData(projectId: transcript.projectId)

            // Map to timeline entries
            seenEntryIDs.removeAll(keepingCapacity: false)
            let transcriptTimelineEntries = transcriptEntries.map { entry in
                seenEntryIDs.insert(entry.id)
                let cacheKey = entry.windowSha256.map { CacheKey(content: entry.contentSha256, window: $0) }
                let cache = cacheKey.flatMap { cacheMap[$0] }
                return toTimelineEntry(entry, cached: cache, transcriptPath: transcript.filePath)
            }

            setEntries(transcriptTimelineEntries)
            sortEntriesChronologically()  // Ensure consistent sort (timestamp, sourceIdentifier)
            pruneSeenIDsIfNeeded()

            // Phase 2B: Sync loader state after session switch.
            // Cursor is project-scoped, so we keep it (but rebuild seen IDs for this view).
            let latestForCursor = transcriptEntries.max(by: { a, b in
                if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return a.id < b.id
            })

            if let loader = dataLoader {
                await loader.reset(clearCursor: false, reason: "session-switch")
                if let latestForCursor {
                    await loader.setCursor(EntryCursor(from: latestForCursor))
                }
            }

            // Update CM cursor (backward compat) to match loader
            if let latestForCursor {
                lastSeenCursor = EntryCursor(from: latestForCursor)
            }

            // Route through policy engine to update follow state and emit system events
            await pinAndSwitch(session)

            currentSessionId = session.identifier
            lastUpdate = Date()

            log.info("Switched to session: \(session.fileURL.lastPathComponent) (\(self.entries.count) entries)")
        } catch {
            lastError = "Failed to switch session: \(error.localizedDescription)"
            log.error("Session switch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Public refresh method for manual refresh requests
    nonisolated func refresh() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.loadFeedFromSQL()?.value
            }
        }
    }

    /// Regenerate summary for a specific entry by deleting its cache and refreshing
    ///
    /// Deletes the timeline cache entry for the given content and window hashes,
    /// then triggers a refresh. TimelineCacheMissGenerator will automatically
    /// regenerate the summary on next access.
    ///
    /// - Parameters:
    ///   - contentSha256: SHA256 hash of the entry content
    ///   - windowSha256: SHA256 hash of the context window
    nonisolated func regenerateSummary(contentSha256: String, windowSha256: String) async {
        guard let orchestrator = await MainActor.run(body: { self.orchestrator }) else {
            return
        }

        do {
            // Delete the cache entry
            try orchestrator.deleteCachedTimeline(contentSha256: contentSha256, windowSha256: windowSha256)
            log.info("Deleted cache for regeneration: content=\(contentSha256.prefix(8), privacy: .public)... window=\(windowSha256.prefix(8), privacy: .public)...")

            // Trigger a refresh to reload from database (which will show "generating" state)
            await refresh()

            // Immediately queue the entry for generation (bypass viewport/debounce)
            // Without this, the user would have to scroll the entry out of view and back in
            // to trigger regeneration due to viewport-based queueing with 1.25s debounce
            await MainActor.run {
                // Phase 3: Delegate to cache coordinator
                cacheCoordinator.queueForRegeneration(contentSha256: contentSha256, windowSha256: windowSha256)
            }
        } catch {
            log.error("Failed to regenerate summary: \(error.localizedDescription, privacy: .public)")
        }
    }

    // queueRegeneratedEntry - MOVED to TimelineCacheCoordinator.queueForRegeneration (Phase 3)

    /// Load all sessions from database for transcripts
    /// This is called when the transcripts window opens to ensure sessions are populated
    @MainActor
    func loadAllSessionsFromDatabase(retryCount: Int = 0) async {
        // Check if both projectId and orchestrator are ready
        // If either is missing, retry with exponential backoff
        guard let projectId = currentProjectId, orchestrator != nil else {
            guard retryCount < 3 else {
                if currentProjectId == nil {
                    log.error("Cannot load sessions: project ID still nil after \(retryCount) retries")
                } else {
                    log.error("Cannot load sessions: orchestrator still nil after \(retryCount) retries")
                }
                return
            }

            let delayMs = UInt64(pow(2.0, Double(retryCount)) * 100_000_000)  // 100ms, 200ms, 400ms

            if currentProjectId == nil {
                log.debug("Project ID not ready, retry \(retryCount + 1)/3 in \(delayMs / 1_000_000)ms")
            } else {
                log.debug("Orchestrator not ready, retry \(retryCount + 1)/3 in \(delayMs / 1_000_000)ms")
            }

            try? await Task.sleep(nanoseconds: delayMs)
            await loadAllSessionsFromDatabase(retryCount: retryCount + 1)
            return
        }

        // Phase 2B: Use loader for session loading (DB work off main actor)
        guard let loader = dataLoader else {
            log.warning("Cannot load sessions: dataLoader not initialized")
            return
        }

        do {
            let sessions = try await loader.loadAllSessions(projectId: projectId)
            allSessions = sessions
            allSessionsLastUpdate = Date()
            log.info("Loaded \(sessions.count) sessions from database for transcripts")
        } catch is CancellationError {
            log.debug("Session loading cancelled")
        } catch {
            log.error("Failed to load sessions from database: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Session Management (Legacy)



    private func makeSourceContext(identifier: String, line: Int? = nil) -> TimelineSourceContext {
        let provider = activeSession?.provider ?? .other
        let filePath = activeSession?.fileURL.path
        return TimelineSourceContext(provider: provider, identifier: identifier, filePath: filePath, line: line)
    }

    /// Append entry only if it belongs to the current session epoch (prevents cross-session leaks)
    private func appendEntryIfCurrentEpoch(_ epoch: UUID, entry: TimelineEntry) {
        guard epoch == sessionEpoch else {
            log.warning("🟡 appendEntryIfCurrentEpoch: Dropping late entry from previous session (epoch mismatch)")
            return
        }

        // Guarantee sessionId is set (safety net for future code changes)
        var e = entry
        if e.sessionId == nil {
            e = e.copyWith(sessionId: currentSessionId)
            log.debug("🟡 appendEntryIfCurrentEpoch: Backfilled missing sessionId for entry")
        }

        appendEntry(e)
        trimEntries()
    }

    // MARK: - SQL-based Processing

    private func toTimelineEntry(_ entry: TranscriptEntry, cached: TimelineCache?, transcriptPath: String?) -> TimelineEntry {
        // Use cached summary if available, otherwise fallback
        let summary: String
        let action: TimelineEntryAction
        if let cache = cached {
            // Honor user edits first
            if cache.userEdited == 1, let userText = cache.userText, !userText.isEmpty {
                summary = userText
            } else {
                // Use generated forms
                summary = cache.selectedForm == "present" ? cache.presentForm : cache.pastForm
            }
            action = .none
        } else {
            // Fallback for cache miss (will trigger LLM generation in background)
            if entry.content.isEmpty {
                summary = "[No content]"
            } else {
                summary = String(entry.content.prefix(100)) + (entry.content.count > 100 ? "…" : "")
            }
            // v23: Non-summarizable entries (nil windowSha256) should not show spinner
            action = entry.windowSha256 == nil ? .nonSummarizable : .unsummarized
        }

        // Use stable UUID from entry.id (prefer parsing as UUID, fallback to UUIDv5)
        let stableId: UUID
        if let parsed = UUID(uuidString: entry.id) {
            stableId = parsed
        } else {
            // Use UUIDv5 for stable identity from string IDs
            stableId = UUID(uuidString: "00000000-0000-5000-8000-\(entry.id.prefix(12).padding(toLength: 12, withPad: "0", startingAt: 0))")
                ?? UUID()
        }

        return TimelineEntry(
            id: stableId,
            kind: TimelineEntryKind(rawValue: entry.kind) ?? .assistant,
            timestamp: Date(timeIntervalSince1970: TimeInterval(entry.timestamp)),
            summary: summary,
            detail: entry.content,
            sourceContent: entry.content,
            sourceContext: TimelineSourceContext(
                provider: TimelineSourceContext.Provider(rawValue: entry.provider) ?? .other,
                identifier: entry.id,
                filePath: transcriptPath,
                line: nil
            ),
            sourceIdentifier: entry.id,
            isCompletion: cached?.disposition == "completion",
            isDirective: {
                guard let disp = cached?.disposition else { return false }
                return ["directive", "affirmative", "negative"].contains(disp)
            }(),
            requestId: nil,
            action: action,
            sessionId: entry.sessionId,
            disposition: cached?.disposition,
            isQueued: entry.isQueued == 1,
            spawnedAgentType: spawnedAgentsLookup[entry.id]?.agentType,
            spawnedAgentModel: spawnedAgentsLookup[entry.id]?.model,
            isContextifyCall: contextifyEntryIds.contains(entry.id),
            contentSha256: entry.contentSha256,
            windowSha256: entry.windowSha256
        )
    }

    /// Refresh decoration lookup tables for the current project
    /// Legacy: Only used by switchToSessionFromUser. Main paths (loadFeedFromSQL,
    /// processIncrementalUpdate) now use decoration snapshots from TimelineDataLoader.
    private func refreshDecorationData(projectId: String) {
        guard let orchestrator = orchestrator else {
            spawnedAgentsLookup.removeAll()
            contextifyEntryIds.removeAll()
            contextifyEntryInfo.removeAll()
            return
        }
        do {
            spawnedAgentsLookup = try orchestrator.getSpawnedAgentEntries(projectId: projectId)
            contextifyEntryIds = try orchestrator.getContextifyEntryIds(projectId: projectId)
            contextifyEntryInfo = try orchestrator.getContextifyEntryInfo(projectId: projectId)
            if !self.spawnedAgentsLookup.isEmpty || !self.contextifyEntryIds.isEmpty {
                log.debug("[DECORATION] Loaded decoration data: \(self.spawnedAgentsLookup.count, privacy: .public) agents, \(self.contextifyEntryIds.count, privacy: .public) contextify entries")
            }
        } catch {
            log.warning("[DECORATION] Failed to load decoration data: \(error.localizedDescription, privacy: .public)")
            spawnedAgentsLookup.removeAll()
            contextifyEntryIds.removeAll()
            contextifyEntryInfo.removeAll()
        }
    }

    @MainActor
    /// Track refresh rate for diagnostics - logs warning if >5 refreshes in 5 seconds
    private func recordRefresh(trigger: String) {
        refreshHistory.append((trigger, Date()))
        // Keep last 100
        if refreshHistory.count > 100 {
            refreshHistory.removeFirst()
        }
        // Log warning if >5 refreshes in 5 seconds
        let recent = refreshHistory.filter { Date().timeIntervalSince($0.timestamp) < 5 }
        if recent.count > 5 {
            log.warning("[TIMELINE-REFRESH-RATE] High refresh rate: \(recent.count, privacy: .public) refreshes in 5s (triggers: \(recent.map { $0.trigger }.joined(separator: ", "), privacy: .public))")
        }
    }

    @discardableResult
    private func loadFeedFromSQL() async -> Task<Void, Never>? {
        guard let projectId = currentProjectId, let orchestrator = orchestrator else { return nil }

        // Re-entrancy guard: prevent duplicate loads, but queue a follow-up refresh
        guard phase != .loading else {
            pendingRefreshAfterLoad = true
            log.debug("[TIMELINE-LOAD] Coalescing refresh request (already loading, will refresh after)")
            return nil
        }

        // Clear any pending refresh flag since we're starting a fresh load
        pendingRefreshAfterLoad = false

        // Track refresh frequency for diagnostics
        #if DEBUG
        if let caller = Thread.callStackSymbols.dropFirst().first {
            if let methodRange = caller.range(of: #"(?<=\s)[^\s]+(?=\s*\+)"#, options: .regularExpression) {
                recordRefresh(trigger: String(caller[methodRange]))
            } else {
                recordRefresh(trigger: "unknown")
            }
        }
        #else
        recordRefresh(trigger: "timeline-load")
        #endif

        log.info("[TIMELINE-LOAD] primer start; projectId=\(projectId, privacy: .public)")

        #if DEBUG
        // Call-site logging for diagnostics
        let callStack = Thread.callStackSymbols
        if callStack.count > 1 {
            let caller = callStack[1]
            // Extract method name from stack frame
            if let methodRange = caller.range(of: #"(?<=\s)[^\s]+(?=\s*\+)"#, options: .regularExpression) {
                let methodName = String(caller[methodRange])
                log.debug("[TIMELINE-LOAD-CALLER] \(methodName, privacy: .public)")
            } else {
                log.debug("[TIMELINE-LOAD-CALLER] \(caller, privacy: .public)")
            }
        }
        #endif

        // P1-1: Hold isReadyForUpdates=false during initial load to prevent append races
        let priorReady = isReadyForUpdates

        feedHydrationTask?.cancel()
        let maxEntries = config.maxEntries
        let signature = generatorSignature()

        let existingEntryCount = (try? orchestrator.getEntryCount(forProject: projectId)) ?? 0
        if existingEntryCount == 0 {
            log.debug("[TIMELINE-HYDRATE-SKIP] project=\(projectId, privacy: .public) reason=no entries yet")
            isProcessing = false
            isReadyForUpdates = priorReady
            phase = .loaded
            schedulePrimerRetry(for: projectId)
            return nil
        }

        // Set loading phase (tracked by UI)
        phase = .loading
        log.info("[UIOPT-BRANCH] phase → loading")

        feedLoadGeneration &+= 1
        let loadGeneration = feedLoadGeneration

        isReadyForUpdates = false
        isProcessing = true

        cancelPrimerRetry(reason: "entries-available")

        feedHydrationTask = Task(priority: .userInitiated) { [weak self, dataLoader, loadGeneration] in
            guard let self, let loader = dataLoader else { return }

            do {
                let startTime = Date()
                log.info("[SUMM-LOAD] Loading feed via dataLoader for project: \(projectId, privacy: .public)")
                log.info("[TIMELINE-HYDRATE-START] project=\(projectId, privacy: .public) count=\(maxEntries, privacy: .public)")

                // Phase 2: Use dataLoader instead of direct orchestrator calls
                log.info("[UIOPT-AWAIT] before dataLoader.loadFeed")
                let result = try await loader.loadFeed(
                    projectId: projectId,
                    limit: maxEntries,
                    generatorSignature: signature
                )
                log.info("[UIOPT-AWAIT] after dataLoader.loadFeed; count=\(result.entries.count)")

                // Check cancellation before UI work
                try Task.checkCancellation()

                let shouldApply = await MainActor.run { [weak self] in
                    guard let self else { return false }
                    return self.currentProjectId == projectId
                        && self.phase == .loading
                        && self.feedLoadGeneration == loadGeneration
                }
                guard shouldApply else {
                    self.log.debug("[TIMELINE-HYDRATE-DROP] Dropping load result for stale projectId=\(projectId, privacy: .public)")
                    return
                }
                await self.finishFeedLoad(
                    projectId: projectId,
                    feed: result.entries,
                    transcriptPaths: result.transcriptPaths,
                    decoration: result.decoration,
                    startTime: startTime,
                    priorReady: priorReady
                )
            } catch {
                if error is CancellationError {
                    let shouldApply = await MainActor.run { [weak self] in
                        guard let self else { return false }
                        return self.currentProjectId == projectId
                            && self.phase == .loading
                            && self.feedLoadGeneration == loadGeneration
                    }
                    guard shouldApply else { return }
                    await MainActor.run { self.restoreLoadStateAfterCancellation(priorReady: priorReady) }
                } else {
                    let shouldApply = await MainActor.run { [weak self] in
                        guard let self else { return false }
                        return self.currentProjectId == projectId
                            && self.phase == .loading
                            && self.feedLoadGeneration == loadGeneration
                    }
                    guard shouldApply else { return }
                    await MainActor.run { self.handleFeedLoadError(error, priorReady: priorReady) }
                }
            }
        }

        return feedHydrationTask
    }

    @MainActor
    private func finishFeedLoad(
        projectId: String,
        feed: [(TranscriptEntry, TimelineCache?)],
        transcriptPaths: [String: String],
        decoration: DecorationSnapshot,
        startTime: Date,
        priorReady: Bool
    ) async {
            log.debug("📊 Feed loaded: \(feed.count) entries from DB")
            log.info("[SUMM-LOAD] Feed loaded: \(feed.count) entries from database")
            log.info("[TIMELINE-LOAD] DAO.fetchPrimerEntries \(feed.count) entries in \(String(format: "%.0f", Date().timeIntervalSince(startTime) * 1000), privacy: .public)ms")

            // Phase 2: Copy decoration snapshot to CM properties for backward compat
            self.spawnedAgentsLookup = decoration.spawnedAgentsLookup
            self.contextifyEntryIds = decoration.contextifyEntryIds
            self.contextifyEntryInfo = decoration.contextifyEntryInfo

            // Map to UI entries + collect cache misses
            // Note: seenEntryIDs now managed by dataLoader
            let mapStart = Date()
            log.info("[UIOPT-MAP-START] Mapping \(feed.count, privacy: .public) entries to timeline UI models...")
            let misses = cacheCoordinator.createMissesForFeed(
                entries: feed,
                projectId: projectId,
                contextifyEntryInfo: decoration.contextifyEntryInfo
            )

            // Get active entry ID from generator (if any)
            let activeGeneratingID = cacheMissGenerator?.activeEntryID

            let newEntries = feed.map { entry, cache in
                // Create timeline entry with active state check
                let transcriptPath = transcriptPaths[entry.transcriptId]
                var timelineEntry = toTimelineEntry(entry, cached: cache, transcriptPath: transcriptPath)

                // Override action if this is the actively processing entry
                // Compare using the timeline's UUID (already converted in toTimelineEntry)
                if timelineEntry.action == .unsummarized,
                   let activeID = activeGeneratingID,
                   timelineEntry.id == activeID {
                    timelineEntry = timelineEntry.copyWith(action: .generatingActive)
                }

                return timelineEntry
            }
            log.info("[UIOPT-MAP-DONE] Mapping complete in \(String(format: "%.0f", Date().timeIntervalSince(mapStart) * 1000), privacy: .public)ms")

            let uiUpdateStart = Date()
            log.info("[UIOPT-UI-UPDATE] Updating timeline UI with \(newEntries.count, privacy: .public) entries...")

            // Update state (ensure SwiftUI reactivity)
            setEntries(newEntries)
            sortEntriesChronologically()  // Ensure consistent sort (timestamp, sourceIdentifier)
            // Note: seenIDs pruning now handled by dataLoader

            log.info("[UIOPT-UI-UPDATE] UI updated in \(String(format: "%.0f", Date().timeIntervalSince(uiUpdateStart) * 1000), privacy: .public)ms")
            log.info("[UIOPT-YIELD] post-setEntries scheduling UI tick")
            await Task.yield()  // Let UI process state change

            log.info("[SUMM-MISSES] Detected \(misses.count) cache misses")

            // Viewport-aware queueing: Trust viewport tracking to queue visible entries
            // If we already have a viewport snapshot that intersects current entries,
            // trigger settle directly instead of re-arming initial snapshot state machine
            if !misses.isEmpty {
                let currentVisible = viewportCoordinator.currentVisibleIDs
                let currentEntryIDs = Set(state.entries.map(\.id))
                let effectiveVisible = currentVisible.intersection(currentEntryIDs)
                log.info("[SUMM-LOAD-STATE] currentVisibleIDs.count=\(currentVisible.count, privacy: .public), effectiveVisible=\(effectiveVisible.count, privacy: .public), needsInitialSnapshot=\(self.needsInitialVisibilitySnapshot, privacy: .public)")
                if !effectiveVisible.isEmpty {
                    // Snapshot intersects current entries - use it directly
                    log.info("[SUMM-LOAD-SETTLE] Using existing viewport snapshot (\(effectiveVisible.count, privacy: .public) IDs)")
                    viewportDidSettle(visibleIDs: effectiveVisible)
                } else {
                    // No valid snapshot - arm initial viewport state machine
                    log.info("[SUMM-LOAD-DEFER] Deferring queueing to viewport tracking (\(misses.count, privacy: .public) candidates)")
                    beginAwaitingInitialViewport(reason: "post-load")
                    replayPendingInitialViewportSnapshot(reason: "post-load")
                }
            } else {
                log.info("[SUMM-LOAD-COMPLETE] No cache misses - all entries have summaries")
                resetInitialViewportState(reason: "post-load-no-miss")
            }

            // Phase 2: Cursor already updated by dataLoader; sync local copy for backward compat
            if let loader = dataLoader {
                lastSeenCursor = await loader.lastSeenCursor
                if let cursor = lastSeenCursor {
                    log.debug("Synced cursor from dataLoader: \(cursor.id)")
                }
            }

            lastUpdate = Date()
            lastError = nil
            lastLoadCompletionTime = Date()  // Track completion time for viewport timing analysis
            phase = .loaded  // Mark as successfully loaded
            log.info("[UIOPT-BRANCH] phase → loaded")

            let elapsed = Date().timeIntervalSince(startTime)
            log.info("[TIMELINE-HYDRATE-DONE] duration_ms=\(Int(elapsed * 1000), privacy: .public) entries=\(feed.count, privacy: .public)")
            log.info("[TIMELINE-LOAD] primer complete in \(Int(elapsed * 1000))ms")
            if elapsed > 0.035 {
                log.warning("Feed load took \(Int(elapsed * 1000))ms (threshold: 35ms)")
            }

            // Diagnostic: Check entry content
            let nonEmptyCount = self.entries.filter { !$0.summary.isEmpty && !$0.detail.isEmpty }.count
            let emptyCount = self.entries.count - nonEmptyCount
        log.info("Loaded \(self.entries.count) entries (\(nonEmptyCount) with content, \(emptyCount) empty) in \(Int(elapsed * 1000))ms")

        isProcessing = false
        isReadyForUpdates = priorReady

        // Check for coalesced refresh requests during load
        if self.pendingRefreshAfterLoad {
            self.pendingRefreshAfterLoad = false
            log.debug("[TIMELINE-LOAD] Processing pending refresh request")
            await self.loadFeedFromSQL()?.value
        }
    }

    @MainActor
    private func handleFeedLoadError(_ error: Error, priorReady: Bool) {
        lastError = "Failed to load timeline: \(error.localizedDescription)"
        log.error("SQL feed load failed: \(error.localizedDescription, privacy: .public)")
        phase = .failed
        isProcessing = false
        isReadyForUpdates = priorReady
    }

    @MainActor
    private func restoreLoadStateAfterCancellation(priorReady: Bool) {
        log.debug("[TIMELINE-HYDRATE-CANCELLED] Previous load cancelled before completion")
        isProcessing = false
        isReadyForUpdates = priorReady
    }

    /// v23: Load and replay system switch events from database (restart-safe)
    /// T3: Reader is project-scoped and intentionally avoids JOINs,
    ///     because project-level events use empty transcript_id ("") as a sentinel.
    ///     See TranscriptOrchestrator.insertSystemEvent for details.
    @MainActor
    private func loadSwitchEventsFromSQL() async {
        guard let pid = currentProjectId else { return }
        do {
            let events = try await orchestrator.getRecentSystemSwitchEvents(projectId: pid, since: lastSystemEventTs)
            for ev in events where !seenSystemEventIds.contains(ev.id) {
                if let content = ev.content {
                    appendSystemEntry(summary: content)
                }
                seenSystemEventIds.insert(ev.id)
                // R5: Normalize timestamp to milliseconds (handle legacy seconds-based timestamps)
                let tsMs: Int64 = (ev.timestamp < 10_000_000_000) ? Int64(ev.timestamp) * 1000 : Int64(ev.timestamp)
                lastSystemEventTs = max(lastSystemEventTs ?? 0, tsMs)
            }
            if !events.isEmpty {
                log.info("Loaded \(events.count) system switch events from database")
            }
        } catch {
            log.error("Failed to load system switch events: \(error.localizedDescription)")
        }
    }

    // MARK: - Cursor Persistence (P1-4)

    /// Load persisted cursor for current project from dataLoader
    /// Phase 2: Cursor persistence now owned by TimelineDataLoader actor
    @MainActor
    private func loadCursor() async {
        guard let projectId = currentProjectId, let loader = dataLoader else { return }
        await loader.loadCursor(projectId: projectId)
        // Sync local cursor from loader for backward compat during wiring
        lastSeenCursor = await loader.lastSeenCursor
        if let cursor = lastSeenCursor {
            log.debug("Loaded persisted cursor for project \(projectId, privacy: .public): \(cursor.id, privacy: .public)")
        }
    }

    /// Save current cursor to UserDefaults via dataLoader
    /// Phase 2: Cursor persistence now owned by TimelineDataLoader actor (best-effort, actor-internal)
    private func saveCursor() {
        guard let cursor = lastSeenCursor, let loader = dataLoader else { return }
        // Fire-and-forget: loader handles persistence internally
        Task {
            await loader.setCursor(cursor)
        }
    }

    // MARK: - Policy Persistence (C: Follow mode restore)

    /// Load follow policy from database for current project
    /// P0-2: Made async for startup sequence
    /// P1: Await async getFollowPolicy
    @MainActor
    private func loadPolicyForCurrentProject() async {
        guard let pid = currentProjectId else {
            followMode = .automatic
            return
        }
        guard let orchestrator = orchestrator else {
            log.debug("loadPolicyForCurrentProject: orchestrator not ready yet, defaulting to automatic")
            followMode = .automatic
            return
        }
        do {
            if let row = try await orchestrator.getFollowPolicy(projectId: pid) {
                if row.mode == 0 {
                    followMode = .automatic
                } else if let sid = row.pinnedSessionId, let prov = row.pinnedProvider {
                    let p = TimelineSourceContext.Provider(rawValue: prov) ?? .other
                    followMode = .manual(sessionId: sid, provider: p)
                } else {
                    followMode = .automatic
                }
            } else {
                followMode = .automatic
            }
            log.debug("Follow policy loaded: \(self.followMode == .automatic ? "automatic" : "manual")")
        } catch {
            log.error("Failed to load follow policy: \(error.localizedDescription)")
            followMode = .automatic
        }
    }

    @available(*, unavailable, message: "Use watchForDebouncedTranscriptUpdates() instead")
    private func setupSQLNotifications() {}

    private func setupCacheUpdateNotifications() {
        cacheUpdateObserver = NotificationCenter.default.addObserver(
            forName: .timelineCacheUpdated,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let keys = (note.userInfo?["keys"] as? [CacheKey]) ?? []

            // CXT-13: Debounce cache updates (batch size = 1 causes flood)
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Accumulate keys
                self.pendingCacheKeys.formUnion(keys)

                // Cancel existing debounce and start new one
                self.cacheDebounceTask?.cancel()
                self.cacheDebounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
                    guard let self = self, !Task.isCancelled else { return }

                    let keysToRefresh = await MainActor.run {
                        let keys = Array(self.pendingCacheKeys)
                        self.pendingCacheKeys.removeAll()
                        return keys
                    }

                    await self.refreshCachedEntries(keys: keysToRefresh)
                }
            }
        }
    }

    private func setupProjectsDiscoveryNotifications() {
        // Listen for projects metadata discovery completion
        // NOTE: This notification fires after ProjectDiscoveryService upserts transcript records,
        // but BEFORE ProjectActivityMonitor completes hoovering. Timeline may be empty initially.
        projectsDiscoveryObserver = NotificationCenter.default.addObserver(
            forName: .projectsIngestionComplete,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.log.info("📨 [TIMELINE-REFRESH-INGESTION] Received projectsIngestionComplete notification")
            Task { @MainActor [weak self] in
                guard let self else {
                    self?.log.warning("⚠️ [TIMELINE-REFRESH-INGESTION] Self was deallocated")
                    return
                }

                self.log.info("🔄 [TIMELINE-REFRESH-INGESTION] Metadata discovery complete, reloading timeline (may be empty until hoovering finishes)...")
                self.log.info("🔍 [TIMELINE-REFRESH-INGESTION] isMonitoring=\(self.isMonitoring) (refreshing regardless)")

                guard self.needsPrimerReload() else {
                    self.log.debug("[TIMELINE-REFRESH-INGESTION] Skipping reload (primer already loaded)")
                    return
                }

                await self.loadFeedFromSQL()?.value
                self.log.info("✅ [TIMELINE-REFRESH-INGESTION] Timeline feed reloaded (\(self.state.entries.count) entries - hoovering continues in background)")
            }
        }
    }

    private func setupPrimerReadyNotifications() {
        primerReadyObserver = NotificationCenter.default.addObserver(
            forName: .timelinePrimerReady,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            guard let projectId = notification.object as? String else {
                self.log.error("⚠️ [TIMELINE-PRIMER-READY] Missing projectId in notification")
                return
            }

            let entries = notification.userInfo?["entries"] as? Int
            self.log.info("📨 [TIMELINE-PRIMER-READY] Received primer-ready for \(projectId, privacy: .public) entries=\(entries ?? -1, privacy: .public)")

            Task { @MainActor [weak self] in
                guard let self else { return }

                guard self.currentProjectId == projectId else {
                    self.log.debug("[TIMELINE-PRIMER-READY] Ignoring primer-ready for different project \(projectId, privacy: .public)")
                    return
                }

                guard self.isMonitoring else {
                    self.log.debug("[TIMELINE-PRIMER-READY] Ignoring primer-ready while monitor inactive")
                    return
                }

                self.cancelPrimerRetry(reason: "primer-ready")
                self.log.info("🔄 [TIMELINE-PRIMER-READY] Refreshing timeline after primer-ready event")
                await self.loadFeedFromSQL()?.value
            }
        }
    }

    @MainActor
    private func schedulePrimerRetry(for projectId: String) {
        guard primerRetryTask == nil else { return }

        log.info("[TIMELINE-RETRY-SCHEDULED] Waiting for primer entries (project=\(projectId, privacy: .public))")
        guard let orchestrator = orchestrator else {
            log.error("[TIMELINE-RETRY] Cannot schedule retry - orchestrator unavailable")
            return
        }

        isAwaitingPrimer = true

        primerRetryTask = Task { [weak self, orchestrator] in
            guard let self else { return }
            let maxAttempts = 10
            for attempt in 1...maxAttempts {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }

                let entryCount = (try? orchestrator.getEntryCount(forProject: projectId)) ?? 0
                if entryCount > 0 {
                    await MainActor.run {
                        self.log.info("[TIMELINE-RETRY] Primer entries detected after \(attempt, privacy: .public) attempts - refreshing timeline")
                    }
                    await self.loadFeedFromSQL()?.value
                    await MainActor.run {
                        self.primerRetryTask = nil
                    }
                    return
                }
            }

            await MainActor.run {
                self.log.warning("[TIMELINE-RETRY] Timed out waiting for primer entries (project=\(projectId, privacy: .public))")
                self.primerRetryTask = nil
                self.isAwaitingPrimer = false
            }
        }
    }

    @MainActor
    private func cancelPrimerRetry(reason: String) {
        guard primerRetryTask != nil else { return }
        log.info("[TIMELINE-RETRY-CANCELLED] reason=\(reason, privacy: .public)")
        primerRetryTask?.cancel()
        primerRetryTask = nil
        isAwaitingPrimer = false
    }

    private func setupHooveringProgressNotifications() {
        // Listen for incremental hoovering progress (first 3, then every 10 transcripts)
        // Enables timeline to populate as soon as newest transcripts are hoovered
        hooveringProgressObserver = NotificationCenter.default.addObserver(
            forName: .transcriptHooveringProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            // Extract notification data outside assumeIsolated to avoid data race warnings
            guard let projectId = notification.object as? String else { return }
            let count = notification.userInfo?["transcriptCount"] as? Int ?? 0
            let total = notification.userInfo?["totalTranscripts"] as? Int ?? 0

            // Since queue: .main guarantees main thread, access main-actor properties via assumeIsolated
            MainActor.assumeIsolated {
                // Only refresh if notification is for our active project
                guard projectId == self.currentProjectId else {
                    self.log.debug("[TIMELINE-REFRESH-PROGRESS] Ignoring progress notification for different project")
                    return
                }

                self.log.info("📨 [TIMELINE-REFRESH-PROGRESS] Received hoovering progress: \(count)/\(total) transcripts")

                // Diagnostic logging for first 3 transcripts (verify timeline shows these)
                if count <= 3, let orchestrator = self.orchestrator {
                    do {
                        let transcripts = try orchestrator.getTranscripts(forProject: projectId)
                        let sortedByRecent = transcripts.sorted { $0.lastModified > $1.lastModified }
                        let firstThree = sortedByRecent.prefix(3)

                        for (index, transcript) in firstThree.enumerated() {
                            let date = Date(timeIntervalSince1970: TimeInterval(transcript.lastModified))
                            let formatter = DateFormatter()
                            formatter.dateStyle = .medium
                            formatter.timeStyle = .short
                            let prettyDate = formatter.string(from: date)

                            self.log.info("[HOOVER-FIRST-3] Transcript #\(index + 1, privacy: .public): \(transcript.filePath, privacy: .public) (modified: \(prettyDate, privacy: .public))")
                        }
                    } catch {
                        self.log.error("[HOOVER-FIRST-3] Failed to get transcripts: \(error.localizedDescription, privacy: .public)")
                    }
                }

                // Debounce refresh to reduce flicker (coalesce rapid notifications)
                // Use a more robust approach: enforce minimum 500ms between actual refreshes
                self.progressDebounceTask?.cancel()
                self.progressDebounceTask = Task { @MainActor [weak self] in
                    guard let self else { return }

                    // Calculate how long to wait based on last refresh
                    let now = Date()
                    let minInterval: TimeInterval = 0.5  // 500ms minimum between refreshes
                    let timeSinceLastRefresh = self.lastProgressRefreshTime.map { now.timeIntervalSince($0) } ?? minInterval

                    if timeSinceLastRefresh < minInterval {
                        // Wait for remaining time
                        let remainingWait = minInterval - timeSinceLastRefresh
                        self.log.debug("[TIMELINE-REFRESH-PROGRESS] Waiting \(Int(remainingWait * 1000))ms before refresh (last refresh \(Int(timeSinceLastRefresh * 1000))ms ago)")
                        try? await Task.sleep(for: .milliseconds(Int(remainingWait * 1000)))
                    }

                    guard !Task.isCancelled else {
                        self.log.debug("[TIMELINE-REFRESH-PROGRESS] Refresh cancelled before execution")
                        return
                    }

                    guard self.needsPrimerReload() else {
                        self.log.debug("[TIMELINE-REFRESH-PROGRESS] Skipping reload (primer complete, incremental updates active)")
                        return
                    }

                    self.lastProgressRefreshTime = Date()
                    await self.loadFeedFromSQL()?.value
                    self.log.info("✅ [TIMELINE-REFRESH-PROGRESS] Timeline refreshed (\(self.state.entries.count) entries)")
                }
            }
        }
    }

    private func setupProjectChangeNotifications() {
        // Idempotent: only register once for lifetime of singleton
        guard projectChangeObserver == nil else {
            log.debug("Project change observer already registered, skipping duplicate setup")
            return
        }

        projectChangeObserver = NotificationCenter.default.addObserver(
            forName: .projectRootDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            log.info("📬 ConversationMonitor: Received .projectRootDidChange notification (object: \(String(describing: notification.object)))")
            Task { @MainActor [weak self] in
                self?.handleProjectRootChange()
            }
        }
        log.debug("Project change observer registered")
    }

    // MARK: - Viewport Tracking & Background Summarization (Phase 2-3)

    /// Set up app lifecycle notifications for background summarization
    private func setupAppLifecycleNotifications() {
        guard appLifecycleObserver == nil else {
            log.debug("App lifecycle observer already registered, skipping duplicate setup")
            return
        }

        appLifecycleObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleAppResignActive()
            }
        }

        // Also set up notification for app becoming active to cancel background tasks
        appBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppBecomeActive()
            }
        }

        log.debug("App lifecycle observers registered for background summarization")

        // Set up observer for queue operation updates
        queueOpsObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("QueueOperationsProcessed"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let projectId = notification.userInfo?["projectId"] as? String  // Extract before Task
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleQueueOperationsProcessed(projectId: projectId)
            }
        }
    }

    /// Handle queue operations being processed (clear badges on affected entries)
    @MainActor
    private func handleQueueOperationsProcessed(projectId: String?) async {
        // Only refresh if this is for the current project
        guard projectId == currentProjectId else { return }

        log.debug("[QUEUE-REFRESH] Queue operations processed, refreshing entries")

        // Simplest approach: just reload from SQL (loadFeedFromSQL already handles everything)
        // This ensures we get fresh is_queued values from the database
        await loadFeedFromSQL()?.value
    }

    /// Mark an entry as visible in the viewport (called by UI)
    /// Queueing for summarization happens via settle-driven aggregate path (viewportDidSettle)
    @MainActor
    func markEntryVisible(_ entryId: UUID) {
        viewportCoordinator.markEntryVisible(entryId)
    }

    // MARK: - Scroll-to-Bottom Unread Clearing (P1-UNREAD-COUNT)

    /// Update scroll position and trigger unread clearing if at bottom
    /// Called from timeline view when scroll position changes
    @MainActor
    func updateScrollPosition(visibleRect: CGRect, contentHeight: CGFloat) {
        viewportCoordinator.updateScrollPosition(visibleRect: visibleRect, contentHeight: contentHeight)
    }

    /// Mark active project as viewed with timestamp of latest entry
    /// Clears unread count by updating last_viewed_ts
    @MainActor
    private func markActiveProjectAsViewedInternal() async {
        guard let projectId = currentProjectId else {
            log.debug("[UNREAD-CLEAR] No active project, skipping mark-as-viewed")
            return
        }

        guard let latestEntry = state.entries.last else {
            log.debug("[UNREAD-CLEAR] No entries in timeline, skipping mark-as-viewed")
            return
        }

        guard let orchestrator = orchestrator else {
            log.debug("[UNREAD-CLEAR] No orchestrator available, skipping mark-as-viewed")
            return
        }

        let timestamp = ISO8601Z.string(from: latestEntry.timestamp)

        Task.detached(priority: .utility) { [orchestrator, projectId, timestamp] in
            let logger = Logger(subsystem: "dev.contextify.timeline", category: "ConversationMonitor")
            do {
                try orchestrator.markProjectViewed(projectId: projectId, timestamp: timestamp)
                logger.info("[UNREAD-CLEAR] ✅ Marked project \(projectId, privacy: .public) as viewed (scroll-to-bottom)")

                // Trigger UI refresh of unread counts
                _ = await MainActor.run {
                    Task {
                        await ProjectSwitcherState.shared.refreshUnreadCounts()
                        logger.debug("[UNREAD-CLEAR] Refreshed unread counts in UI")
                    }
                }
            } catch {
                logger.error("[UNREAD-CLEAR-ERROR] Failed to mark project as viewed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Aggregate Visibility Tracking (macOS 15+)

    /// Called by view before programmatic scrollTo to suppress transient visibility events
    @MainActor
    func beginProgrammaticScroll() {
        viewportCoordinator.beginProgrammaticScroll()
    }

    /// Called by view when scroll phase changes - enables queueing once scroll is idle
    @MainActor
    func handleScrollPhaseChange(_ phase: ScrollPhase) {
        viewportCoordinator.handleScrollPhaseChange(phase)
    }

    /// Aggregate snapshot of visible entry IDs from onScrollTargetVisibilityChange
    @MainActor
    func replaceVisibleSnapshot(_ ids: [UUID]) {
        viewportCoordinator.replaceVisibleSnapshot(ids)
    }

    @MainActor
    private func beginAwaitingInitialViewport(reason: String) {
        guard let projectId = currentProjectId else { return }
        viewportCoordinator.beginAwaiting(projectId: projectId, sessionId: currentSessionId, reason: reason)
    }

    @MainActor
    private func replayPendingInitialViewportSnapshot(reason: String) {
        viewportCoordinator.replayPendingSnapshot(reason: reason)
    }

    // pruneQueueToVisible - MOVED to TimelineCacheCoordinator.pruneQueueToVisible (Phase 3)
    // queueVisibleGeneratingEntries - MOVED to TimelineCacheCoordinator.queueVisibleGeneratingEntries (Phase 3)
    // getEntryStatus - MOVED to TimelineCacheCoordinator.getEntryStatus (Phase 3)

    /// Handle app resigning active - background LLM processing not implemented
    @MainActor
    private func handleAppResignActive() async {
        // Policy: Only generate summaries for visible entries (scroll-based prioritization)
        // Background processing disabled - summaries only generated when app is active
        log.info("App resigned active - LLM summary generation paused (policy: visible-only)")
    }

    /// Handle app becoming active - cancel background tasks to prioritize visible entries
    @MainActor
    private func handleAppBecomeActive() {
        // CXT-102: Guard against torn state
        guard isMonitoring else { return }
        log.info("App became active - cancelling background fill task")
        // CXT-103: Atomic capture-nil-cancel
        let task = backgroundFillTask
        backgroundFillTask = nil
        task?.cancel()
    }

    /// Keyed bulk refresh: Update specific entries when their caches are ready
    @MainActor
    private func refreshCachedEntries(keys: [CacheKey]) async {
        guard let orchestrator else { return }
        guard !keys.isEmpty else { return }

        log.debug("Refreshing \(keys.count) specific entries with fresh cache")

        // Only update entries currently in the feed (prevents orphan updates across filters)
        let sig = generatorSignature()

        do {
            // Fetch caches with signature verification (off-main is safe)
            let cacheMap = try orchestrator.getCachedTimelineManyWithSignature(
                keys: keys,
                generatorSignature: sig
            )

            // Compute index map once (avoid O(n·m) recomputation)
            let indexMap = state.indexByCacheKey

            // Build updates for indices we currently show
            var updates: [(Int, TimelineCache)] = []
            for key in keys {
                if let index = indexMap[key],
                   entries.indices.contains(index),
                   let cache = cacheMap[key] {
                    updates.append((index, cache))
                }
            }

            guard !updates.isEmpty else {
                log.debug("No matching entries in current feed for cache update")
                return
            }

            // Apply updates in place, preserving scroll and order
            for (index, cache) in updates.sorted(by: { $0.0 < $1.0 }) {
                let old = entries[index]

                let summary: String
                if cache.userEdited == 1, let userText = cache.userText, !userText.isEmpty {
                    summary = userText
                } else {
                    summary = (cache.selectedForm == "present") ? cache.presentForm : cache.pastForm
                }

                updateEntry(at: index, with: old.copyWith(
                    summary: summary,
                    action: (old.action == .unsummarized || old.action == .generatingActive) ? .none : old.action,
                    disposition: cache.disposition
                ))
            }

            // R8: Drop to debug to reduce noise under heavy cache processing
            log.debug("Updated \(updates.count) entries with fresh cache summaries")
        } catch {
            log.error("Cache bulk refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Legacy handler - kept for backward compatibility, now delegates to keyed refresh
    @MainActor
    private func handleCacheUpdate() async {
        // Extract all keys and delegate to new method
        let keys = entries.compactMap { entry -> CacheKey? in
            guard let content = entry.contentSha256, let window = entry.windowSha256 else {
                return nil
            }
            return CacheKey(content: content, window: window)
        }

        await refreshCachedEntries(keys: keys)
    }

    @MainActor
    private func processIncrementalUpdate() async {
        log.info("[INCR-UPDATE-START] Processing incremental update for project: \(self.currentProjectId ?? "none", privacy: .public)")
        if updateInFlight { updateDirty = true; return }
        updateInFlight = true
        defer {
            updateInFlight = false
            updateDrainItersRemaining = updateDrainMaxItersDefault  // Always reset
        }

        repeat {
            updateDirty = false

            guard let projectId = currentProjectId, let loader = dataLoader else {
                log.debug("[INCR-UPDATE-SKIP] No projectId or dataLoader yet (normal during startup)")
                return
            }

            // If no cursor in loader, do full reload instead
            let hasCursor = await loader.lastSeenCursor != nil
            guard hasCursor else {
                log.debug("[INCR-UPDATE-RELOAD] No cursor available, doing full reload")
                await loadFeedFromSQL()?.value
                return
            }

            do {
                let startTime = Date()

                log.info("[INCR-UPDATE-FETCH] Fetching new entries after cursor for projectId: \(projectId, privacy: .public)")
                // Use loader for incremental update (handles cursor, dedup, decoration)
                let result = try await loader.processIncremental(projectId: projectId)

                guard !result.newEntries.isEmpty else {
                    log.debug("[INCR-UPDATE-EMPTY] No new entries in incremental update")
                    break  // No more entries, exit the drain loop
                }

                let newEntries = result.newEntries
                log.info("[INCR-UPDATE-ENTRIES] ✅ Found \(newEntries.count, privacy: .public) new entries to process")
                for (index, entry) in newEntries.prefix(5).enumerated() {  // Log first 5
                    log.info("[INCR-UPDATE-ENTRY] Entry \(index + 1, privacy: .public): \(entry.id, privacy: .public) kind: \(entry.kind, privacy: .public) timestamp: \(entry.timestamp, privacy: .public)")
                }
                if newEntries.count > 5 {
                    log.info("[INCR-UPDATE-ENTRY] ... and \(newEntries.count - 5, privacy: .public) more entries")
                }

                // Copy decoration snapshot to CM properties (backward compat during wiring)
                self.spawnedAgentsLookup = result.decoration.spawnedAgentsLookup
                self.contextifyEntryIds = result.decoration.contextifyEntryIds
                self.contextifyEntryInfo = result.decoration.contextifyEntryInfo

                // Convert to timeline entries with cache lookup + collect misses
                // TODO: Batch cache lookup for better performance
                var addedCount = 0
                var cacheByEntryId: [String: TimelineCache] = [:]

                for entry in newEntries {
                    // Loader already filtered to unseen entries, no dedup needed here

                    // Try to get cache for this entry
                    let cache: TimelineCache?
                    if let windowSha = entry.windowSha256 {
                        let key = CacheKey(content: entry.contentSha256, window: windowSha)
                        cache = try? orchestrator.getCachedTimeline(key: key)
                    } else {
                        cache = nil
                    }

                    if let cache {
                        cacheByEntryId[entry.id] = cache
                    }

                    let transcriptPath = result.transcriptPaths[entry.transcriptId]
                    let timelineEntry = toTimelineEntry(entry, cached: cache, transcriptPath: transcriptPath)
                    appendEntry(timelineEntry)
                    addedCount += 1
                }

                let misses = cacheCoordinator.createMissesForUpdate(
                    entries: newEntries,
                    projectId: projectId,
                    contextifyEntryInfo: result.decoration.contextifyEntryInfo,
                    cacheForEntry: { cacheByEntryId[$0.id] }
                )

                // Queue cache misses for background generation
                if !misses.isEmpty, let generator = cacheMissGenerator {
                    let missesToQueue = misses  // Capture before Task to avoid mutation warning
                    Task {
                        await generator.queueMisses(missesToQueue)
                    }
                }

                // Sort to maintain chronological ordering: timestamp ASC, id ASC
                sortEntriesChronologically()

                // Trim to max size and prune dedupe set (ensures bounded memory)
                trimEntries()
                // Prune loader's seenIDs (loader owns the set now)
                let currentIDs = state.entries.map { $0.sourceIdentifier }
                await loader.pruneSeenIDsIfNeeded(currentEntryIDs: currentIDs, maxEntries: config.maxEntries)

                // Sync cursor from loader (loader already updated it)
                lastSeenCursor = await loader.lastSeenCursor

                lastUpdate = Date()
                log.info("[INCR-UPDATE-APPENDED] ✅ Appended \(addedCount, privacy: .public) new entries to timeline")

                // P1-2: Debounce policy evaluation to reduce churn during heavy ingestion
                if isReadyForUpdates {
                    policyEvalTask?.cancel()
                    policyEvalTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }

                        let newestKey = computeNewestKey()
                        let now = Date()
                        let decision = policyEngine.decide(inputs: .init(
                            followMode: followMode,
                            lastActiveKey: lastActiveKey,
                            newestCandidate: newestKey,
                            now: now,
                            lastSwitchAt: lastSwitchAt,
                            cooldown: 5.0
                        ))
                        if let target = decision.nextActive {
                            await setActive(from: lastActiveKey, to: target,
                                            reason: decision.reason ?? .newerWrite,
                                            emit: decision.shouldEmitMessage)
                            lastSwitchAt = now
                        }
                    }
                }

                let elapsed = Date().timeIntervalSince(startTime)
                // R8: Drop to debug to reduce noise under heavy ingestion
                log.debug("Added \(addedCount) new entries in \(Int(elapsed * 1000))ms")
            } catch is CancellationError {
                log.debug("[INCR-UPDATE] Cancelled")
                return
            } catch let error as TimelineDataLoaderError {
                switch error {
                case let .projectMismatch(current, requested):
                    log.warning("[INCR-UPDATE] Project mismatch during incremental (current=\(current, privacy: .public), requested=\(requested, privacy: .public)); forcing full reload")
                    await loadFeedFromSQL()?.value
                    return
                }
            } catch {
                lastError = "Failed to fetch new entries: \(error.localizedDescription)"
                log.error("Incremental update failed: \(error.localizedDescription, privacy: .public)")
            }

            // Check starvation guard
            if updateDirty && updateDrainItersRemaining > 0 {
                updateDrainItersRemaining -= 1
            } else {
                break
            }
        } while true
    }

    private func generatorSignature() -> String {
        // Use centralized generator signature from Core module
        return timelineGeneratorSignature()
    }

    private func latestAssistantActionHint() -> String? {
        guard let lastAssistant = entries.reversed().first(where: { $0.kind == .assistant }) else {
            return nil
        }
        let raw = lastAssistant.sourceContent?.isEmpty == false
            ? lastAssistant.sourceContent
            : lastAssistant.detail
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return distilledActionHint(from: raw)
    }

    private func distilledActionHint(from text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let candidate = lines.first { line in
            let lower = line.lowercased()
            return actionHintCues.contains { lower.contains($0) }
        } ?? lines.first

        guard var hint = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty else {
            return nil
        }

        hint = hint.replacingOccurrences(
            of: "^(yes|no|ok|okay|sure|please)[\\s,:-]*",
            with: "",
            options: .regularExpression
        )
        hint = hint.replacingOccurrences(
            of: "[?.!…]+$",
            with: "",
            options: .regularExpression
        )

        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }

    private func shouldUseActionHint(for text: String) -> Bool {
        let normalized = normalizeForActionHint(text)
        guard !normalized.isEmpty else { return false }
        let tokens = normalized.split(separator: " ")
        guard tokens.count <= 3 else { return false }
        let allAffirmative = tokens.allSatisfy { affirmativeLexicon.contains(String($0)) }
        let allNegative = tokens.allSatisfy { negativeLexicon.contains(String($0)) }
        return allAffirmative || allNegative
    }

    private func normalizeForActionHint(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuation = CharacterSet.punctuationCharacters.union(CharacterSet(charactersIn: "…“”\"'"))
        normalized = normalized.trimmingCharacters(in: punctuation)
        normalized = normalized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return normalized.lowercased()
    }

    private func ensureSessionStartEntry() {
        guard !didEmitSessionStart else { return }
        didEmitSessionStart = true

        // With SQL backend, session start is tracked automatically
        // This legacy method is kept for compatibility but does nothing
    }

    // MARK: - Active Session Follow (v23)

    /// Policy reconciliation - checks if pinned session still exists
    @MainActor
    private func reconcilePolicyWithAvailableSessions() async {
        // P0-4: Ensure sessions are actually available, not just marked loaded
        guard sessionsLoaded, (!allSessions.isEmpty || followMode.isAutomatic) else {
            log.warning("Skipping policy reconciliation - sessions not yet loaded or available")
            return
        }
        guard case .manual(let sid, let prov) = followMode else { return }

        if !allSessions.contains(where: { $0.identifier == sid && $0.provider == prov }) {
            log.info("Pinned session \(sid) no longer available - triggering handlePinnedMissing")
            await handlePinnedMissing()
        }
    }

    /// Pinned-missing handler with zero-session persistence
    @MainActor
    private func handlePinnedMissing() async {
        guard let pid = currentProjectId else { return }
        do {
            try await orchestrator.setAutomatic(projectId: pid)
            followMode = .automatic
            log.info("Switched to automatic mode due to pinned session missing")

            if let nk = computeNewestKey() {
                await setActive(from: lastActiveKey, to: nk, reason: .pinnedMissing, emit: true)
            } else {
                // P1-3: No sessions exist - persist a project-scoped event (empty transcript_id)
                let ev = TranscriptOrchestrator.SystemEventInsert(
                    id: UUID().uuidString,
                    transcriptId: "",  // P1-3: empty = project-scoped, not joined to any transcript
                    projectId: pid,
                    timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                    content: "Pinned session unavailable — awaiting new activity",
                    metadataJSON: toJSON(["reason": "pinnedMissing", "noSessions": true, "mode": "automatic"])
                )
                do {
                    try await orchestrator.insertSystemEvent(ev)
                    appendSystemEntry(summary: ev.content)
                    seenSystemEventIds.insert(ev.id)  // F: de-dupe safety
                } catch {
                    log.error("Failed to persist pinned-missing event: \(error.localizedDescription)")
                    appendSystemEntry(summary: ev.content) // graceful: still show UI event
                }
                lastActiveKey = nil
                log.info("No sessions available - persisted project-scoped event")
            }
        } catch {
            log.error("Pinned-missing reconcile failed: \(error.localizedDescription)")
        }
    }

    /// Active session switching with system event emission
    @MainActor
    private func setActive(from: SessionKey?, to: SessionKey, reason: SwitchReason, emit: Bool) async {
        log.info("[SESSION-SWITCH-START] Switching to session: \(to.sessionId, privacy: .public) provider: \(to.provider.rawValue, privacy: .public) reason: \(reason.rawValue, privacy: .public)")

        guard let pid = currentProjectId else {
            log.warning("[SESSION-SWITCH-ERROR] No current project ID")
            return
        }
        guard let t = allSessions.first(where: { $0.identifier == to.sessionId && $0.provider == to.provider }) else {
            log.warning("[SESSION-SWITCH-ERROR] Session \(to.sessionId, privacy: .public) not found in allSessions - cannot setActive")
            return
        }

        lastActiveKey = to
        activeSession = t
        log.info("[SESSION-SWITCH-ACTIVE] ✅ Active session set to: \(to.sessionId, privacy: .public) (\(to.provider.displayName, privacy: .public))")

        // CRITICAL FIX: Ensure watcher is running for newly active session
        // TranscriptWatcher.watch() is idempotent, safe to call multiple times
        do {
            log.info("[SESSION-SWITCH-WATCH-VERIFY] Verifying watcher for: \(t.identifier, privacy: .public)")
            try orchestrator.startWatchingTranscript(
                transcriptId: t.identifier,
                fileURL: t.fileURL,
                provider: t.provider.rawValue
            )
            log.info("[SESSION-SWITCH-WATCH-OK] ✅ Watcher active for: \(t.identifier, privacy: .public)")
        } catch {
            log.error("[SESSION-SWITCH-WATCH-ERROR] ❌ Failed to start watcher: \(error.localizedDescription, privacy: .public)")
        }

        if emit {
            let payload: [String: Any] = [
                "from": from.map { ["sessionId": $0.sessionId, "provider": $0.provider.rawValue] as [String: Any] } as Any,
                "to": ["sessionId": to.sessionId, "provider": to.provider.rawValue] as [String: Any],
                "reason": reason.rawValue,
                "mode": (followMode == .automatic ? "automatic" : "manual")
            ]
            let ev = TranscriptOrchestrator.SystemEventInsert(
                id: UUID().uuidString,
                transcriptId: t.identifier,
                projectId: pid,
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                content: followSummary(to, reason: reason),
                metadataJSON: toJSON(payload)
            )
            do {
                try await orchestrator.insertSystemEvent(ev)
                seenSystemEventIds.insert(ev.id)  // F: de-dupe safety
                publishTypedEvent(to: to, reason: reason)
                log.info("[SESSION-SWITCH-EVENT] System event persisted for session switch: \(reason.rawValue, privacy: .public)")
            } catch {
                log.error("[SESSION-SWITCH-ERROR] Failed to persist system event: \(error.localizedDescription, privacy: .public)")
                // Degrade gracefully: still publish typed event for in-app subscribers
                publishTypedEvent(to: to, reason: reason)
            }
        }

        log.info("[SESSION-SWITCH-DONE] ✅ Switch complete for: \(to.sessionId, privacy: .public)")
    }

    /// Compute the newest session based on last activity
    private func computeNewestKey() -> SessionKey? {
        guard let s = allSessions.max(by: { $0.lastActivity < $1.lastActivity }) else { return nil }
        return SessionKey(sessionId: s.identifier, provider: s.provider)
    }

    /// Generate a human-readable summary for session switches
    private func followSummary(_ to: SessionKey, reason: SwitchReason) -> String {
        let modeStr = followMode == .automatic ? "Auto-follow" : "Pinned"
        let reasonStr: String
        switch reason {
        case .newerWrite:
            reasonStr = "newer activity"
        case .pinnedMissing:
            reasonStr = "pinned session unavailable"
        case .manualSelection:
            reasonStr = "manual selection"
        case .unpinToAuto:
            reasonStr = "unpinned to automatic"
        case .projectChange:
            reasonStr = "project change"
        }
        return "[\(modeStr)] Following \(to.provider.displayName) session — \(reasonStr)"
    }

    /// Publish typed event to NotificationCenter
    /// P2-3: NotificationCenter only (no Combine PassthroughSubject)
    @MainActor
    private func publishTypedEvent(to: SessionKey, reason: SwitchReason) {
        // Map project ID to filesystem path using coordinator
        guard let context = StartupCoordinator.shared.current else {
            log.warning("Cannot publish event: no coordinator context available")
            return
        }

        let evt = ActiveSessionDidChangeEvent(
            projectId: context.id,
            projectPath: context.path,
            sessionId: to.sessionId,
            provider: to.provider.rawValue,
            mode: (followMode == .automatic ? "automatic" : "manual"),
            reason: reason.rawValue,
            timestamp: Date()
        )
        NotificationCenter.default.post(name: .activeSessionDidChange, object: evt)
        log.debug("Published ActiveSessionDidChangeEvent via NotificationCenter")
    }

    /// Helper to append system messages directly to timeline
    @MainActor
    private func appendSystemEntry(summary: String) {
        let entry = TimelineEntry(
            kind: .system,
            timestamp: Date(),
            summary: summary,
            detail: "",
            sourceIdentifier: "system-\(UUID().uuidString)",
            isError: false,
            action: .none
        )
        state.append(entry)
        log.debug("Appended system entry: \(summary)")
    }

    /// Convert dictionary to JSON string
    private func toJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    /// Public API: Switch to automatic follow mode
    /// P0: Emits system event and updates cooldown anchor for restart-safe audit trail
    @MainActor
    func unpinToAuto() async {
        guard let pid = currentProjectId else { return }
        do {
            try await orchestrator.setAutomatic(projectId: pid)
            followMode = .automatic
            log.info("Switched to automatic follow mode")

            // P0: Switch to newest and emit event (restart-safe), or clear if none
            if let target = computeNewestKey() {
                await setActive(from: lastActiveKey, to: target, reason: .unpinToAuto, emit: true)
                lastSwitchAt = Date()
            } else {
                lastActiveKey = nil
                activeSession = nil
            }
        } catch {
            log.error("Failed to unpin: \(error.localizedDescription)")
        }
    }

    /// Public API: Pin to specific session
    /// P0: Emits system event and updates cooldown anchor for restart-safe audit trail
    @MainActor
    func pinAndSwitch(_ session: TranscriptSession) async {
        guard let pid = currentProjectId else { return }
        do {
            try await orchestrator.setManual(projectId: pid, sessionId: session.identifier, provider: session.provider.rawValue)
            followMode = .manual(sessionId: session.identifier, provider: session.provider)

            // P0: Persist event + typed event and update cooldown anchor
            let key = SessionKey(sessionId: session.identifier, provider: session.provider)
            await setActive(from: lastActiveKey, to: key, reason: .manualSelection, emit: true)
            lastSwitchAt = Date()
            log.info("Pinned to session: \(session.identifier)")
        } catch {
            log.error("Failed to pin: \(error.localizedDescription)")
        }
    }

    // MARK: - Diagnostics & Health Monitoring

    /// Public API: Capture full diagnostic snapshot
    /// Can be called any time for debugging - provides complete state picture without human intervention
    @MainActor
    public func captureDiagnostics() async -> TimelineDiagnosticsSnapshot? {
        guard let diagnostics = diagnosticsService else { return nil }

        let monitorState = MonitorStateSnapshot(
            isMonitoring: isMonitoring,
            entryCount: entries.count,
            visibleEntryCount: visibleEntries.count,
            lastUpdate: lastUpdate,
            isProcessing: isProcessing,
            lastError: lastError,
            cursorExists: lastSeenCursor != nil,
            lastRestartRequest: lastMonitorRestartRequest,
            lastReadyAt: lastMonitorReadyAt,
            idleRestartFailureCount: monitorRestartFailureCount
        )

        return await diagnostics.captureSnapshot(
            projectId: currentProjectId,
            orchestrator: orchestrator,
            monitorState: monitorState
        )
    }

    /// Public API: Get recent timeline entries for external API access
    /// Returns lightweight snapshots with content for debugging
    @MainActor
    public func getRecentEntries(count: Int) -> [TimelineEntrySnapshot] {
        let recentEntries = Array(entries.suffix(count))

        func apiDispositionAndRole(for entry: TimelineEntry) -> (disposition: String, role: String?) {
            // Map entry kind to API disposition and role fields
            // disposition: entry class/type (e.g., "message", "system")
            // role: chat role for message entries ("user", "assistant"), nil for non-messages
            switch entry.kind {
            case .user:       return ("message", "user")
            case .assistant:  return ("message", "assistant")
            case .system:     return ("system",  nil)
            }
        }

        return recentEntries.map { entry in
            let mapped = apiDispositionAndRole(for: entry)
            return TimelineEntrySnapshot(
                entryId: entry.id.uuidString,
                timestamp: entry.timestamp,
                disposition: mapped.disposition,
                role: mapped.role,
                content: entry.detail,
                provider: entry.sourceContext?.provider.rawValue,
                presentSummary: entry.summary,
                pastSummary: nil,
                isGenerating: entry.action == .unsummarized || entry.action == .generatingActive,
                isNonSummarizable: entry.action == .nonSummarizable,
                isError: entry.isError
            )
        }
    }

    /// Handle recovery action from HealthMonitoringCoordinator
    /// Runs on MainActor to ensure orchestrator usage is always on correct executor
    @MainActor
    private func handleRecoveryAction(_ action: HealthMonitoringCoordinator.RecoveryAction) async {
        guard let orchestrator = self.orchestrator else {
            log.warning("[RECOVERY] Skipping recovery - no orchestrator available")
            return
        }

        switch action {
        case .watcher(let projectId, let targetTranscriptId):
            await attemptWatcherRecovery(projectId: projectId, orchestrator: orchestrator, targetTranscriptId: targetTranscriptId)
        case .hoover(let projectId):
            await attemptHooverRecovery(projectId: projectId, orchestrator: orchestrator)
        }
    }

    /// Attempt to recover stalled watcher
    @MainActor
    private func attemptWatcherRecovery(projectId: String, orchestrator: TranscriptOrchestrator, targetTranscriptId: String?) async {
        log.info("[WATCHER-RECOVERY-START] Attempting recovery for project=\(projectId, privacy: .public) target=\(targetTranscriptId ?? "all", privacy: .public)")

        do {
            log.debug("[WATCHER-RECOVERY-CALL] Calling orchestrator.ensureProjectWatcher...")
            let summary = try orchestrator.ensureProjectWatcher(
                projectId: projectId,
                targetTranscriptId: targetTranscriptId
            )
            log.info("[WATCHER-RECOVERY-DONE] project=\(projectId, privacy: .public) started=\(summary.startedCount) already=\(summary.alreadyActiveCount) missing=\(summary.missingFileCount) target=\(summary.targetTranscriptId ?? "all")")

            // Success - notify coordinator to reset backoff
            await healthMonitor.recordRecoverySuccess()
        } catch {
            log.error("[WATCHER-RECOVERY-ERROR] Recovery failed for project=\(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")

            // Failure - notify coordinator to increment backoff
            await healthMonitor.recordRecoveryFailure()
        }
    }

    /// Attempt to recover stalled hoover
    @MainActor
    private func attemptHooverRecovery(projectId: String, orchestrator: TranscriptOrchestrator) async {
        do {
            let transcripts = try orchestrator.getTranscripts(forProject: projectId)

            for transcript in transcripts {
                let fileURL = URL(fileURLWithPath: transcript.filePath)

                // Check if file has unprocessed content
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                      let fileSize = attrs[.size] as? NSNumber else {
                    continue
                }

                if fileSize.intValue > (transcript.fileSize ?? 0) {
                    log.info("🔧 Attempting manual hoover for stalled transcript: \(transcript.id)")
                    try orchestrator.manualHoover(transcriptId: transcript.id, fileURL: fileURL)
                }
            }
        } catch {
            log.error("Hoover recovery failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - ViewportTrackingDelegate

extension ConversationMonitor: ViewportTrackingDelegate {
    func viewportDidSettle(visibleIDs: Set<UUID>) {
        debugVisibleIDs = visibleIDs
        // Phase 3: Delegate to cache coordinator for queue management (coalesced internally)
        cacheCoordinator.handleViewportSettle(visibleIDs: visibleIDs)
    }

    func queueCacheMisses(_ misses: [CacheMiss]) async {
        guard let generator = cacheMissGenerator else { return }
        await generator.queueMisses(misses)
    }

    func lookupEntry(_ id: UUID) -> TimelineEntry? {
        state.lookup(id)
    }

    func getCurrentProjectId() -> String? {
        currentProjectId
    }

    func getContextifyEntryInfo(for entryId: String) -> TranscriptOrchestrator.ContextifyEntryInfo? {
        contextifyEntryInfo[entryId]
    }

    func markActiveProjectAsViewed() async {
        await markActiveProjectAsViewedInternal()
    }

    func getCurrentEntryIDs() -> Set<UUID> {
        Set(state.entries.map { $0.id })
    }

    var maxEntries: Int {
        config.maxEntries
    }
}

// MARK: - CacheCoordinatorDelegate

extension ConversationMonitor: CacheCoordinatorDelegate {
    // currentProjectId - protocol satisfied by private var of same name
    // cacheMissGenerator - protocol satisfied by private(set) var of same name
    // visibleEntries - protocol satisfied by public computed property of same name
    // getContextifyEntryInfo - protocol satisfied by existing method in ViewportTrackingDelegate

    func getRecentVisibleIDs() -> Set<UUID> {
        viewportCoordinator.recentVisibleIDs()
    }
}

#if DEBUG
extension ConversationMonitor {
    func _testShouldUseActionHint(_ text: String) -> Bool {
        shouldUseActionHint(for: text)
    }

    func _testDistilledActionHint(from text: String) -> String? {
        distilledActionHint(from: text)
    }
}
#endif
