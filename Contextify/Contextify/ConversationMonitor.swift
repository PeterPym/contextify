import Foundation
import Observation
import OSLog
import ContextifyCore
import AppKit
import CryptoKit

// MARK: - Diagnostics Configuration

enum DiagnosticsConfig {
    #if DEBUG
    static let enableHTTPServer = true
    #else
    static let enableHTTPServer = false
    #endif
}

// MARK: - R3: String hash extension for stable cursor keys

extension String {
    /// R3: Normalize project paths to stable short keys for cursor persistence
    nonisolated func sha1Hex() -> String {
        let digest = Insecure.SHA1.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - P0-3: Cursor Persistence Actor

/// Off-main-thread cursor persistence to avoid UI jank
/// R3: Uses sha1 hash of project path for stable UserDefaults keys
private actor CursorPersistence {
    func load(projectId: String) -> EntryCursor? {
        let key = "dev.contextify.cursor.\(projectId.sha1Hex())"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EntryCursor.self, from: data)
    }

    func save(projectId: String, cursor: EntryCursor) {
        let key = "dev.contextify.cursor.\(projectId.sha1Hex())"
        guard let data = try? JSONEncoder().encode(cursor) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

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

    var indexByCacheKey: [CacheKey: Int] {
        _indexByCacheKey
    }

    private func rebuildCacheIndex() {
        _indexByCacheKey = Dictionary(
            entries.enumerated().compactMap { i, e in
                e.cacheKey.map { ($0, i) }
            },
            uniquingKeysWith: { _, new in new }  // Keep latest index on collision
        )
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
    }

    func update(at index: Int, to newValue: TimelineEntry) {
        guard entries.indices.contains(index) else { return }

        // Atomic cache index update: remove old key, then add new key
        let oldKey = entries[index].cacheKey
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

    private let log = Logger(subsystem: "dev.contextify", category: "Timeline")
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

    private let state = TimelineState()

    /// Read-only view over state.entries (single source of truth)
    var entries: [TimelineEntry] { state.entries }

    /// Maximum number of entries to display (tuneable for performance)
    private let visibleEntryLimit = 25

    /// All entries are visible - sessions appear as one continuous stream
    /// No filtering by session - timeline shows chronological view across all sessions
    /// Limited for performance (tuneable via visibleEntryLimit)
    var visibleEntries: [TimelineEntry] {
        let n = max(visibleEntryLimit, 1)
        return state.entries.count > n
          ? Array(state.entries.suffix(n))
          : state.entries
    }

    private(set) var isMonitoring = false
    private(set) var isProcessing = false
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?
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
    @ObservationIgnored private var lastSeenCursor: EntryCursor?  // P1-4: Keyset cursor for incremental updates (persisted per project)
    @ObservationIgnored var orchestrator: TranscriptOrchestrator!  // Shared instance (nonisolated, accessible to inventory view)
    @ObservationIgnored private var seenEntryIDs = Set<String>()  // Deduplicate entries
    @ObservationIgnored private var backgroundTasks: Task<Void, Never>?  // Parent task for all background work
    private(set) var cacheMissGenerator: TimelineCacheMissGenerator?  // Background cache generation
    // Observable flag for status bar - avoids exposing non-Sendable generator object
    private(set) var isCacheGeneratorActive = false
    @ObservationIgnored nonisolated(unsafe) private var cacheUpdateObserver: NSObjectProtocol?  // For cache update notifications
    @ObservationIgnored nonisolated(unsafe) private var projectChangeObserver: NSObjectProtocol?  // For project root change notifications
    @ObservationIgnored private var updateInFlight = false  // Single-flight guard for processIncrementalUpdate
    @ObservationIgnored private var updateDirty = false    // Marks that updates arrived during processing
    @ObservationIgnored private let updateDrainMaxItersDefault = 8  // Max drain loop iterations to prevent starvation
    @ObservationIgnored private var updateDrainItersRemaining = 8  // Current iterations remaining
    @ObservationIgnored private var debounceTask: Task<Void, Never>?  // Debounce task for transcript updates

    // v23: Active session follow state
    @ObservationIgnored private var startupTask: Task<Void, Never>?  // P0-2: Cancellable startup sequence
    @ObservationIgnored private var policyEvalTask: Task<Void, Never>?  // P1-2: Debounced policy evaluation
    @ObservationIgnored private var sessionsLoaded = false  // Gate for policy reconciliation
    @ObservationIgnored private var isReadyForUpdates = false  // Gate for incremental updates
    private(set) var followMode: FollowMode = .automatic  // P0-4: Observable for UI
    @ObservationIgnored private var lastActiveKey: SessionKey?
    @ObservationIgnored private var lastSwitchAt: Date?
    @ObservationIgnored private var lastSystemEventTs: Int64?
    @ObservationIgnored private var seenSystemEventIds = Set<String>()
    @ObservationIgnored private let policyEngine = ActiveSessionPolicyEngine()
    @ObservationIgnored private let cursorPersistence = CursorPersistence()  // P0-3: Off-main cursor I/O
    private(set) var activeSession: TranscriptSession?  // Observable for UI (v23: actively followed session)

    // Health monitoring and diagnostics
    @ObservationIgnored private var lastHealthCheck: Date?
    @ObservationIgnored private var diagnosticsService: TimelineDiagnosticsService?
    @ObservationIgnored private var diagnosticsHTTPServer: DiagnosticsHTTPServer?  // External HTTP API

    // P0-4: Computed properties for UI binding
    var isPinnedMode: Bool {
        if case .manual = followMode { return true }
        return false
    }
    var pinnedKey: SessionKey? { followMode.pinnedKey }

    private init() {
        // Set up project change notifications early, so we can react to project selection
        // even if monitoring hasn't started yet
        setupProjectChangeNotifications()
    }

    deinit {
        // Cancel any pending debounce task
        debounceTask?.cancel()

        // Cancel background task group (health monitoring, polling, etc.)
        backgroundTasks?.cancel()

        // Clean up observers (only relevant for tests/previews, not for singleton)
        if let observer = projectChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = cacheUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        log.info("ConversationMonitor deinit: cancelled debounceTask and removed observers")
    }

    @MainActor
    func startMonitoring(projectId: String) {
        // Cancel residual background work before starting new group
        backgroundTasks?.cancel()
        backgroundTasks = nil
        seenEntryIDs.removeAll(keepingCapacity: false)

        guard !isMonitoring else { return }

        log.info("⭐️ Timeline integration starting for project \(projectId)")

        Task { @MainActor [weak self] in
            guard let self else { return }

            // 1. Initialize orchestrator and bind known project id (P1-1: off main actor)
            do {
                let orch = try await Task.detached { try TranscriptOrchestrator(dbManager: .shared) }.value
                self.orchestrator = orch
                self.currentProjectId = projectId
                self.log.info("📁 Project ID set: \(projectId)")

                // Verify project was persisted (forces read from DB, ensures commit)
                let projectId = self.currentProjectId!
                guard let _ = try orch.getProject(id: projectId) else {
                    self.lastError = "Failed to verify project creation"
                    self.log.error("❌ Project \(projectId) not found after creation")
                    return
                }
                self.log.info("✅ Project \(projectId) verified in database")

                // 3. Shutdown old cache miss generator (if exists) before creating new one
                if let oldGenerator = self.cacheMissGenerator {
                    await oldGenerator.shutdown()  // Actor-isolated method requires await
                }
                self.cacheMissGenerator = nil  // Clear before creating new
                self.isCacheGeneratorActive = false

                // Initialize new cache miss generator for this project
                self.cacheMissGenerator = TimelineCacheMissGenerator(orchestrator: self.orchestrator)
                self.isCacheGeneratorActive = true

                // Initialize diagnostics service
                self.diagnosticsService = TimelineDiagnosticsService(db: try DatabaseManager.shared.pool)

                // Initialize diagnostics HTTP server (external API) - opt-in, non-fatal
                if DiagnosticsConfig.enableHTTPServer {
                    self.diagnosticsHTTPServer = DiagnosticsHTTPServer()
                    do {
                        try await self.diagnosticsHTTPServer?.start(
                            diagnosticsHandler: { @Sendable [weak self] in
                                guard let self else { return nil }
                                return await self.captureDiagnostics()
                            },
                            recentEntriesHandler: { @Sendable [weak self] count in
                                guard let self else { return [] }
                                return await self.getRecentEntries(count: count)
                            }
                        )
                    } catch {
                        self.log.warning("Diagnostics HTTP disabled: \(error.localizedDescription, privacy: .public)")
                        self.diagnosticsHTTPServer = nil
                    }
                }

                // 4. Start background work (discovery + debounced updates + health monitoring) in a single parent task
                let orchestrator = self.orchestrator!
                self.log.info("🚀 Spawning background tasks for project: \(projectId)")
                self.backgroundTasks = Task { [weak self] in
                    guard let self else { return }

                    // Initialize metadata orchestrator with SQL backend (await before use)
                    await TranscriptMetadataOrchestrator.shared.initialize(orchestrator: orchestrator)

                    await withTaskGroup(of: Void.self) { group in
                        // Task 1: Discovery loop (structured, cancellable)
                        group.addTask { [weak self] in
                            guard let self else { return }
                            do {
                                try await self.discoverNewTranscripts(projectId: projectId, orchestrator: orchestrator)
                            } catch is CancellationError {
                                return
                            } catch {
                                await MainActor.run {
                                    self.log.error("Background discovery failed: \(error.localizedDescription, privacy: .public)")
                                }
                            }
                        }

                        // Task 2: Debounced transcript updates
                        group.addTask { [weak self] in
                            await self?.watchForDebouncedTranscriptUpdates()
                        }

                        // Task 3: Health monitoring with auto-recovery
                        group.addTask { [weak self] in
                            await self?.runHealthMonitoring(projectId: projectId, orchestrator: orchestrator)
                        }

                        // Task 4: Fallback polling (in case FSEvents fails)
                        group.addTask { [weak self] in
                            await self?.runFallbackPolling(projectId: projectId, orchestrator: orchestrator)
                        }
                    }
                }

                // 5. Load initial feed (fast - single query)
                await self.loadFeedFromSQL()

                // 6. Subscribe to realtime updates (SQL notifications handled by watchForDebouncedTranscriptUpdates)
                // self.setupSQLNotifications()  // Disabled: debouncing is handled by background watcher
                self.setupCacheUpdateNotifications()
                // Project change notifications already set up in init()

                self.isMonitoring = true
                self.log.info("SQL-based timeline monitoring started (projectId: \(projectId))")
                NotificationCenter.default.post(name: .conversationMonitoringDidStart, object: nil)
            } catch {
                self.lastError = "Failed to start monitoring: \(error.localizedDescription)"
                self.log.error("Monitoring startup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    func stopMonitoring() {
        isMonitoring = false
        activeSession = nil
        backgroundTasks?.cancel()   // NEW: cancels the whole background task group
        backgroundTasks = nil
        debounceTask?.cancel()
        debounceTask = nil

        // Stop diagnostics exporter
        if let server = diagnosticsHTTPServer {
            Task {
                await server.stop()
            }
        }
        diagnosticsHTTPServer = nil

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
    }

    /// Cancel pending debounce task on project changes to avoid late callbacks into torn state
    @MainActor
    private func onProjectOrSessionChange() {
        log.debug("onProjectOrSessionChange: projectId=\(self.currentProjectId ?? "nil")")

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

        // Clear pending LLM requests for non-active projects to prevent resource waste
        if let generator = cacheMissGenerator {
            Task {
                await generator.clearPendingMisses(exceptProjectId: currentProjectId)
            }
        }

        // P0-2: Cancellable startup sequence with checkpoints
        startupTask = Task { @MainActor in
            do {
                // 1. Load policy from DB (C: restore followMode)
                try Task.checkCancellation()
                await self.loadPolicyForCurrentProject()

                // 2. Load all sessions before reconciliation
                try Task.checkCancellation()
                await self.loadAllSessionsFromDatabase()
                self.sessionsLoaded = true

                // 3. Reconcile policy with available sessions
                try Task.checkCancellation()
                await self.reconcilePolicyWithAvailableSessions()

                // 4. Load persisted cursor (P1-4: restart safety)
                try Task.checkCancellation()
                await self.loadCursor()

                // 5. Load feed and initialize cursor
                try Task.checkCancellation()
                await self.loadFeedFromSQL()

                // 6. Replay switch events
                try Task.checkCancellation()
                await self.loadSwitchEventsFromSQL()

                // 7. Enable incremental updates
                self.isReadyForUpdates = true
            } catch is CancellationError {
                log.debug("Startup cancelled for project switch")
            } catch {
                log.error("Startup failed: \(error.localizedDescription)")
            }
        }
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

                log.debug("📬 TranscriptUpdated notification received: projectId=\(pid ?? "nil"), currentProjectId=\(self.currentProjectId ?? "nil")")

                // Branch 1: Current project - refresh timeline
                if pid == self.currentProjectId || pid == nil {
                    log.debug("📬 ✅ Matches current project - scheduling debounced refresh")
                    // Cancel existing debounce task and start new one
                    self.debounceTask?.cancel()
                    self.debounceTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
                        guard let self, !Task.isCancelled else {
                            self?.log.debug("📬 Debounce task cancelled or self deallocated")
                            return
                        }
                        self.log.debug("📬 Debounce complete - calling processIncrementalUpdate")
                        await self.processIncrementalUpdate()
                    }
                } else {
                    log.debug("📬 ❌ Notification for different project (pid=\(pid ?? "nil") != current=\(self.currentProjectId ?? "nil")) - ignoring")
                }

                // Branch 2: Other project - unread count is DB-derived (no action needed here)
                // ProjectSwitcherState will query unread counts on refresh
            }
        }
    }

    @available(*, unavailable, message: "Use watchForDebouncedTranscriptUpdates()")
    private func handleTranscriptUpdate(projectId: String?) async {}

    @MainActor
    private func pruneSeenIDsIfNeeded() {
        let cap = config.maxEntries * 2
        if seenEntryIDs.count > cap {
            seenEntryIDs = Set(state.entries.map { $0.sourceIdentifier })
        }
    }

    @MainActor
    private func setEntries(_ new: [TimelineEntry]) {
        state.replace(with: new)
    }

    @MainActor
    private func appendEntry(_ e: TimelineEntry) {
        state.append(e)
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

    @MainActor
    func handleProjectRootChange() {
        log.info("🔄 Project root changed - reloading conversation timeline")

        // Stop current monitoring
        log.debug("handleProjectRootChange: stopping monitoring")
        stopMonitoring()

        // Clear all entries
        log.debug("handleProjectRootChange: clearing entries")
        clearEntries()

        // Restart monitoring with explicit project id to avoid identity races
        log.debug("handleProjectRootChange: restarting monitoring")
        guard let url = HUDViewModel.shared.projectRootURL else {
            log.error("handleProjectRootChange: no HUD project URL; aborting restart")
            return
        }
        Task { @MainActor in
            do {
                let pid = try await Task.detached(priority: .userInitiated) { () throws -> String in
                    let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
                    return try orchestrator.getOrCreateProject(
                        name: url.lastPathComponent,
                        rootPath: url.path
                    )
                }.value
                startMonitoring(projectId: pid)
                log.info("✅ Project root change complete - monitoring restarted")
            } catch {
                lastError = "Failed to resolve project id for restart: \(error.localizedDescription)"
                log.error("handleProjectRootChange: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    func requestImmediateRefresh(trigger: TimelineRefreshTrigger) {
        Task { @MainActor in
            await loadFeedFromSQL()
        }
    }

    /// Public method for user-initiated session switch from transcript inventory
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
                await loadFeedFromSQL()
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

            // Map to timeline entries
            seenEntryIDs.removeAll(keepingCapacity: false)
            let transcriptTimelineEntries = transcriptEntries.map { entry in
                seenEntryIDs.insert(entry.id)
                let cacheKey = entry.windowSha256.map { CacheKey(content: entry.contentSha256, window: $0) }
                let cache = cacheKey.flatMap { cacheMap[$0] }
                return toTimelineEntry(entry, cached: cache)
            }

            setEntries(transcriptTimelineEntries)
            sortEntriesChronologically()  // Ensure consistent sort (timestamp, sourceIdentifier)
            pruneSeenIDsIfNeeded()

            // Update cursor from latest entry (P1-4: persist)
            if let latest = transcriptEntries.first {
                lastSeenCursor = EntryCursor(from: latest)
                saveCursor()
            }

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
                await self.loadFeedFromSQL()
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
        } catch {
            log.error("Failed to regenerate summary: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load all sessions from database for transcript inventory
    /// This is called when the transcript inventory window opens to ensure sessions are populated
    @MainActor
    func loadAllSessionsFromDatabase() async {
        guard let projectId = currentProjectId, orchestrator != nil else {
            log.debug("Cannot load sessions: no project or orchestrator (likely shutting down)")
            return
        }

        do {
            let transcripts = try orchestrator.getTranscripts(forProject: projectId)
            let latestTimestamps = try orchestrator.latestTimestampsByTranscript(projectId: projectId)

            // Fetch entry counts for all transcripts
            var entryCounts: [String: Int] = [:]
            for transcript in transcripts {
                if let count = try? orchestrator.getEntryCount(transcriptId: transcript.id) {
                    entryCounts[transcript.id] = count
                }
            }

            let sessions = Self.mapTranscriptsToSessions(
                transcripts: transcripts,
                latestTimestamps: latestTimestamps,
                entryCounts: entryCounts
            )

            allSessions = sessions
            log.info("Loaded \(sessions.count) sessions from database for transcript inventory")
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

    private func toTimelineEntry(_ entry: TranscriptEntry, cached: TimelineCache?) -> TimelineEntry {
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
            action = entry.windowSha256 == nil ? .nonSummarizable : .generating
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
                filePath: nil,
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
            contentSha256: entry.contentSha256,
            windowSha256: entry.windowSha256
        )
    }

    @MainActor
    private func loadFeedFromSQL() async {
        guard let projectId = currentProjectId, orchestrator != nil else { return }

        // P1-1: Hold isReadyForUpdates=false during initial load to prevent append races
        let priorReady = isReadyForUpdates
        isReadyForUpdates = false
        defer { isReadyForUpdates = priorReady }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let startTime = Date()

            // Single query gets entries + cache
            // Note: P1-1 deferred - TranscriptEntry not Sendable, would need Models.swift update
            let feed = try orchestrator.getRecentFeed(
                forProject: projectId,
                limit: config.maxEntries,
                generatorSignature: generatorSignature()
            )

            log.debug("📊 Feed loaded: \(feed.count) entries from DB")

            // Map to UI entries and track seen IDs + collect cache misses
            seenEntryIDs.removeAll(keepingCapacity: true)
            var misses: [CacheMiss] = []

            let newEntries = feed.map { entry, cache in
                seenEntryIDs.insert(entry.id)

                // Collect cache miss for background generation
                if cache == nil, let windowSha = entry.windowSha256 {
                    let miss = CacheMiss(
                        entryId: entry.id,
                        projectId: projectId,  // Track project for cancellation when switching
                        contentSha256: entry.contentSha256,
                        windowSha256: windowSha,
                        content: entry.content,
                        context: entry.content,  // TODO: Add surrounding context
                        kind: entry.kind,
                        provider: entry.provider
                    )
                    misses.append(miss)
                }

                return toTimelineEntry(entry, cached: cache)
            }

            setEntries(newEntries)
            sortEntriesChronologically()  // Ensure consistent sort (timestamp, sourceIdentifier)
            pruneSeenIDsIfNeeded()

            // Queue cache misses for background generation
            if !misses.isEmpty, let generator = cacheMissGenerator {
                Task {
                    await generator.queueMisses(misses)
                }
            }

            // P1-1: Initialize cursor from tail only if not already set (prevent regression)
            if let tailEntry = feed.last, lastSeenCursor == nil {
                let e = tailEntry.0
                lastSeenCursor = EntryCursor(from: e)
                saveCursor()  // P1-4: Persist cursor for project
                log.debug("Initialized cursor from tail: \(e.id)")
            }

            lastUpdate = Date()
            lastError = nil

            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 0.02 {
                log.warning("Feed load took \(Int(elapsed * 1000))ms (threshold: 20ms)")
            }

            // Diagnostic: Check entry content
            let nonEmptyCount = self.entries.filter { !$0.summary.isEmpty && !$0.detail.isEmpty }.count
            let emptyCount = self.entries.count - nonEmptyCount
            log.info("Loaded \(self.entries.count) entries (\(nonEmptyCount) with content, \(emptyCount) empty) in \(Int(elapsed * 1000))ms")
        } catch {
            lastError = "Failed to load timeline: \(error.localizedDescription)"
            log.error("SQL feed load failed: \(error.localizedDescription, privacy: .public)")
        }
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
                    await appendSystemEntry(summary: content)
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

    /// Load persisted cursor for current project from UserDefaults
    /// P0-3: Async I/O via cursor persistence actor to avoid main thread jank
    @MainActor
    private func loadCursor() async {
        guard let projectId = currentProjectId else { return }

        if let cursor = await cursorPersistence.load(projectId: projectId) {
            lastSeenCursor = cursor
            log.debug("Loaded persisted cursor for project \(projectId): \(cursor.id)")
        }
    }

    /// Save current cursor to UserDefaults for restart safety
    /// P0-3: Fire-and-forget detached task to avoid blocking main thread
    private func saveCursor() {
        guard let projectId = currentProjectId, let cursor = lastSeenCursor else { return }

        Task.detached { [cursor, projectId, cursorPersistence] in
            await cursorPersistence.save(projectId: projectId, cursor: cursor)
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
            Task { @MainActor [weak self] in
                await self?.refreshCachedEntries(keys: keys)
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
                    action: old.action == .generating ? .none : old.action
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
        log.debug("🔄 processIncrementalUpdate called - updateInFlight=\(self.updateInFlight)")
        if updateInFlight { updateDirty = true; return }
        updateInFlight = true
        defer {
            updateInFlight = false
            updateDrainItersRemaining = updateDrainMaxItersDefault  // Always reset
        }

        repeat {
            updateDirty = false

            guard let projectId = currentProjectId, orchestrator != nil else {
                log.warning("⚠️ processIncrementalUpdate: No projectId or orchestrator - aborting")
                return
            }

            // If no cursor, do full reload instead
            guard let cursor = lastSeenCursor else {
                log.debug("🔄 No cursor available, doing full reload")
                await loadFeedFromSQL()
                return
            }

            do {
                let startTime = Date()

                log.debug("🔄 Fetching new entries after cursor for projectId=\(projectId)")
                // Get new entries using keyset pagination (prevents duplicates/skips)
                let newEntries = try orchestrator.getEntriesAfterCursor(
                    forProject: projectId,
                    after: cursor
                )

                guard !newEntries.isEmpty else {
                    log.debug("🔄 No new entries in incremental update")
                    break  // No more entries, exit the drain loop
                }

                log.debug("🔄 Found \(newEntries.count) new entries to process")

                // Convert to timeline entries with cache lookup + collect misses
                // TODO: Batch cache lookup for better performance
                var addedCount = 0
                var misses: [CacheMiss] = []

                for entry in newEntries {
                    // Deduplicate using seenEntryIDs
                    guard !seenEntryIDs.contains(entry.id) else {
                        log.debug("Skipping duplicate entry: \(entry.id)")
                        continue
                    }

                    seenEntryIDs.insert(entry.id)

                    // Try to get cache for this entry
                    let key = CacheKey(content: entry.contentSha256, window: entry.windowSha256 ?? "")
                    let cache = try? orchestrator.getCachedTimeline(key: key)

                    // Collect cache miss for background generation
                    if cache == nil, let windowSha = entry.windowSha256 {
                        let miss = CacheMiss(
                            entryId: entry.id,
                            projectId: projectId,  // Track project for cancellation when switching
                            contentSha256: entry.contentSha256,
                            windowSha256: windowSha,
                            content: entry.content,
                            context: entry.content,  // TODO: Add surrounding context
                            kind: entry.kind,
                            provider: entry.provider
                        )
                        misses.append(miss)
                    }

                    let timelineEntry = toTimelineEntry(entry, cached: cache)
                    appendEntry(timelineEntry)
                    addedCount += 1
                }

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
                pruneSeenIDsIfNeeded()

                // Update cursor to latest entry added (P1-4: persist)
                if let latestNew = newEntries.max(by: { a, b in
                    if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
                    if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                    return a.id < b.id
                }) {
                    lastSeenCursor = EntryCursor(from: latestNew)
                    saveCursor()
                }

                lastUpdate = Date()

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
                log.debug("Added \(addedCount) new entries (\(newEntries.count - addedCount) duplicates) in \(Int(elapsed * 1000))ms")
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

    nonisolated private func discoverNewTranscripts(projectId: String, orchestrator: TranscriptOrchestrator) async throws {
        await MainActor.run {
            log.debug("🔎 discoverNewTranscripts: starting with projectId=\(projectId)")
        }

        if Task.isCancelled { return }

        // Verify project exists before discovering
        guard try orchestrator.getProject(id: projectId) != nil else {
            await MainActor.run {
                log.error("❌ discoverNewTranscripts: project \(projectId) not found in database")
            }
            throw RepositoryError.notFound
        }
        await MainActor.run {
            log.debug("✅ discoverNewTranscripts: verified project \(projectId) exists")
        }

        if Task.isCancelled { return }

        // Find JSONL files on disk for THIS project only
        // HUDViewModel is @MainActor; hop correctly to read the property
        guard let projectRoot = await MainActor.run(body: {
            HUDViewModel.shared.projectRootURL
        }) else { return }

        // Build expected directory name: Claude Code mangles paths like:
        // /Users/rob/code/projects/contextify -> -Users-rob-code-projects-contextify
        let expectedDirName = projectRoot.path.replacingOccurrences(of: "/", with: "-")

        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(expectedDirName)

        // Check if this project's directory exists
        guard FileManager.default.fileExists(atPath: claudeDir.path) else {
            await MainActor.run {
                log.info("No Claude Code directory found for project: \(expectedDirName)")
            }
            return
        }

        // Get all .jsonl files from this project's directory
        // Run file I/O on background thread to avoid blocking main thread
        let filesOnDisk = try await Task.detached {
            try FileManager.default.contentsOfDirectory(
                at: claudeDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "jsonl" }
        }.value

        await MainActor.run {
            log.info("🔍 Discovery: Found \(filesOnDisk.count) Claude Code sessions in \(expectedDirName)")
        }

        if Task.isCancelled { return }

        // Use new upsert API - handles idempotency via path normalization
        // Extract session ID from filename (matches ProjectDiscoveryService behavior)
        let discovered = filesOnDisk.map { file in
            DiscoveredTranscript(
                fileURL: file,
                provider: .claudeCode,
                sessionId: file.deletingPathExtension().lastPathComponent
            )
        }

        // Also discover Codex CLI sessions for this project
        // Codex stores sessions globally in ~/.codex/sessions/YYYY/MM/DD/*.jsonl
        // We need to scan recursively and match by 'cwd' field in session_meta
        let projectPath = projectRoot.path
        let codexResult = try await Task.detached(priority: .utility) { () -> (transcripts: [DiscoveredTranscript], parseFailures: Int, missingCwd: Int) in
            let codexRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions")

            guard FileManager.default.fileExists(atPath: codexRoot.path) else {
                return ([], 0, 0)
            }

            // Find all .jsonl files recursively
            guard let enumerator = FileManager.default.enumerator(
                at: codexRoot,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return ([], 0, 0)
            }

            var matchingFiles: [DiscoveredTranscript] = []
            var parseFailures = 0
            var missingCwd = 0
            let cutoff = Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? .distantPast

            while !Task.isCancelled, let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled { break }

                // Skip overly deep paths (defensive: ~/.codex/sessions/YYYY/MM/DD/<file>.jsonl → depth ~ 5–6)
                let depth = fileURL.pathComponents.count - codexRoot.pathComponents.count
                if depth > 8 { continue }

                guard fileURL.pathExtension == "jsonl" else { continue }

                guard
                    let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                    resourceValues.isRegularFile == true
                else {
                    continue
                }

                if let modified = resourceValues.contentModificationDate, modified < cutoff {
                    continue
                }

                guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
                    parseFailures += 1
                    continue
                }
                defer { try? handle.close() }

                let chunk: Data
                do {
                    guard let data = try handle.read(upToCount: 8192), !data.isEmpty else {
                        parseFailures += 1
                        continue
                    }
                    chunk = data
                } catch {
                    parseFailures += 1
                    continue
                }

                if Task.isCancelled { break }

                let newline = chunk.firstIndex(of: 0x0A)
                let lineData = newline.map { chunk.prefix(upTo: $0) } ?? chunk

                guard
                    let lineString = String(data: lineData, encoding: .utf8),
                    !lineString.isEmpty,
                    let jsonData = lineString.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                else {
                    parseFailures += 1
                    continue
                }

                guard
                    let payload = json["payload"] as? [String: Any],
                    let cwd = payload["cwd"] as? String,
                    !cwd.isEmpty
                else {
                    missingCwd += 1
                    continue
                }

                // Match by project path
                if cwd == projectPath {
                    let sessionId = fileURL.deletingPathExtension().lastPathComponent
                    matchingFiles.append(DiscoveredTranscript(
                        fileURL: fileURL,
                        provider: .codexCLI,
                        sessionId: sessionId
                    ))
                }
            }

            return (matchingFiles, parseFailures, missingCwd)
        }.value

        let codexDiscovered = codexResult.transcripts
        if codexResult.parseFailures > 0 || codexResult.missingCwd > 0 {
            log.warning("Codex discovery skipped \(codexResult.parseFailures) malformed session(s) and \(codexResult.missingCwd) session(s) missing cwd for project \(projectRoot.lastPathComponent, privacy: .public)")
        }

        await MainActor.run {
            log.info("🔍 Discovery: Found \(codexDiscovered.count) Codex CLI sessions for project")
        }

        // Combine Claude Code and Codex CLI discoveries
        let allDiscovered = discovered + codexDiscovered

        let resolved = try orchestrator.upsertTranscripts(projectId: projectId, discovered: allDiscovered)

        await MainActor.run {
            log.info("✅ Upserted \(resolved.count) transcripts (\(resolved.filter(\.wasCreated).count) new)")
        }

        if Task.isCancelled { return }

        // Start watchers for ALL transcripts (not just newly created)
        // This ensures orphaned transcripts (existing in DB but never hoovered) get processed
        // TranscriptWatcher.watch() is idempotent and will skip if already watching
        if !resolved.isEmpty {
            // Identify orphaned transcripts for diagnostic logging
            // Fetch all transcripts for this project and build a lookup dictionary
            let allTranscripts = try orchestrator.getTranscripts(forProject: projectId)
            let transcriptLookup = Dictionary(uniqueKeysWithValues: allTranscripts.map { ($0.id, $0) })

            let orphaned = resolved.filter { tr in
                !tr.wasCreated &&
                (transcriptLookup[tr.transcriptId]?.lastProcessedLine ?? -1) == 0
            }

            if !orphaned.isEmpty {
                await MainActor.run {
                    log.info("📋 Found \(orphaned.count) existing transcript(s) pending initial hoover (will process now)")
                }
            }

            await MainActor.run {
                log.info("🔄 Starting/verifying watchers for \(resolved.count) transcripts (\(resolved.filter(\.wasCreated).count) new, \(orphaned.count) pending)")
            }

            // Start watchers for ALL transcripts
            for tr in resolved {
                if Task.isCancelled { return }
                // watch() is idempotent: checks isWatching() and skips if already active
                // It also performs initial hoovering, ensuring orphaned transcripts get processed
                try orchestrator.startWatchingTranscript(transcriptId: tr.transcriptId, fileURL: tr.fileURL)
            }

            // Run maintenance after bulk ingest
            try orchestrator.performMaintenance()

            await MainActor.run {
                log.info("✅ Discovery complete - all transcripts watching")
            }
        } else {
            await MainActor.run {
                log.info("No transcripts found for this project")
            }
        }

        // Refresh sessions list for transcript inventory (re-fetch after discovery)
        let updatedTranscripts = try orchestrator.getTranscripts(forProject: projectId)
        let latestTimestamps = try orchestrator.latestTimestampsByTranscript(projectId: projectId)

        // Fetch entry counts for all transcripts
        var entryCounts: [String: Int] = [:]
        for transcript in updatedTranscripts {
            if let count = try? orchestrator.getEntryCount(transcriptId: transcript.id) {
                entryCounts[transcript.id] = count
            }
        }

        let sessions = Self.mapTranscriptsToSessions(
            transcripts: updatedTranscripts,
            latestTimestamps: latestTimestamps,
            entryCounts: entryCounts
        )
        await MainActor.run {
            self.log.info("📝 Mapped \(updatedTranscripts.count) transcripts to sessions")
            self.allSessions = sessions
            self.log.info("✅ allSessions updated with \(self.allSessions.count) sessions")
            Task { await self.loadFeedFromSQL() }
        }
    }

    nonisolated private static func mapTranscriptsToSessions(
        transcripts: [Transcript],
        latestTimestamps: [String: Int],
        entryCounts: [String: Int]
    ) -> [TranscriptSession] {
        return transcripts.compactMap { transcript in
            let fileURL = URL(fileURLWithPath: transcript.filePath)
            let provider: TimelineSourceContext.Provider
            switch transcript.provider {
            case "claude.code": provider = .claudeCode
            case "codex.cli": provider = .codexCLI
            default: provider = .other
            }

            // Use latest conversation timestamp if available, otherwise fall back to file modified time
            let lastActivityTimestamp = latestTimestamps[transcript.id] ?? transcript.updatedAt
            let lastActivity = Date(timeIntervalSince1970: TimeInterval(lastActivityTimestamp))

            // Get entry count (defaults to 0 if not found)
            let entryCount = entryCounts[transcript.id] ?? 0

            return TranscriptSession(
                provider: provider,
                identifier: transcript.id,
                fileURL: fileURL,
                lastActivity: lastActivity,
                entryCount: entryCount
            )
        }.sorted { $0.lastActivity > $1.lastActivity }
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
        guard let pid = currentProjectId else { return }
        guard let t = allSessions.first(where: { $0.identifier == to.sessionId && $0.provider == to.provider }) else {
            log.warning("Session \(to.sessionId) not found in allSessions - cannot setActive")
            return
        }

        lastActiveKey = to
        activeSession = t
        log.debug("Set active session: \(to.sessionId) (\(to.provider.displayName))")

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
                log.info("System event persisted for session switch: \(reason.rawValue)")
            } catch {
                log.error("Failed to persist system event: \(error.localizedDescription, privacy: .public)")
                // Degrade gracefully: still publish typed event for in-app subscribers
                publishTypedEvent(to: to, reason: reason)
            }
        }
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
        // P2: Use currentProjectId directly instead of querying HUDViewModel
        let evt = ActiveSessionDidChangeEvent(
            projectPath: currentProjectId ?? "",
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
            cursorExists: lastSeenCursor != nil
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
                isGenerating: entry.action == .generating,
                isNonSummarizable: entry.action == .nonSummarizable,
                isError: entry.isError
            )
        }
    }

    /// Health monitoring loop - runs every 30s
    /// Detects stalls and attempts auto-recovery
    private func runHealthMonitoring(projectId: String, orchestrator: TranscriptOrchestrator) async {
        log.info("🏥 Health monitoring started")

        while !Task.isCancelled {
            do {
                // Wait 30s between checks
                try await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak self] in
                    self?.lastHealthCheck = Date()
                }

                // Capture diagnostic snapshot
                guard let snapshot = await self.captureDiagnostics() else {
                    continue
                }

                // Log heartbeat (debug level - visible during development)
                log.debug("🏥 Health check: \(snapshot.issues.count) issues")

                // Check for critical issues and attempt recovery
                for issue in snapshot.issues where issue.severity == .critical {
                    await MainActor.run { [weak self] in
                        self?.log.warning("🏥 Critical issue detected: \(issue.message, privacy: .public)")
                    }

                    // Auto-recovery for specific issues
                    if issue.category == .watcherMissing {
                        await attemptWatcherRecovery(projectId: projectId, orchestrator: orchestrator)
                    } else if issue.category == .hooverStall {
                        await attemptHooverRecovery(projectId: projectId, orchestrator: orchestrator)
                    }
                }

            } catch is CancellationError {
                break
            } catch {
                await MainActor.run { [weak self] in
                    self?.log.error("Health monitoring error: \(error.localizedDescription)")
                }
            }
        }

        log.info("🏥 Health monitoring stopped")
    }

    /// Fallback polling - runs every 10s when FSEvents may not be working
    /// Manually triggers hoover for transcripts that haven't been updated recently
    private func runFallbackPolling(projectId: String, orchestrator: TranscriptOrchestrator) async {
        log.info("🔄 Fallback polling started")

        while !Task.isCancelled {
            do {
                // Wait 10s between polls
                try await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }

                // Get all transcripts for this project
                let transcripts = try orchestrator.getTranscripts(forProject: projectId)

                for transcript in transcripts where !Task.isCancelled {
                    let fileURL = URL(fileURLWithPath: transcript.filePath)

                    // Check if file has been modified since last DB update
                    guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                          let modDate = attrs[.modificationDate] as? Date else {
                        continue
                    }

                    let lastUpdate = Date(timeIntervalSince1970: TimeInterval(transcript.updatedAt))
                    let age = Date().timeIntervalSince(lastUpdate)

                    // If file modified recently but DB not updated in > 60s, manually trigger hoover
                    if modDate > lastUpdate && age > 60 {
                        log.debug("🔄 Fallback polling: triggering hoover for \(transcript.id)")
                        try orchestrator.manualHoover(transcriptId: transcript.id, fileURL: fileURL)
                    }
                }

            } catch is CancellationError {
                break
            } catch {
                // Log errors but continue polling
                log.debug("Fallback polling error: \(error.localizedDescription)")
            }
        }

        log.info("🔄 Fallback polling stopped")
    }

    /// Attempt to recover stalled watcher
    private func attemptWatcherRecovery(projectId: String, orchestrator: TranscriptOrchestrator) async {
        do {
            let transcripts = try orchestrator.getTranscripts(forProject: projectId)

            for transcript in transcripts where !orchestrator.isWatchingTranscript(transcriptId: transcript.id) {
                log.info("🔧 Attempting to restart watcher for: \(transcript.id)")
                let fileURL = URL(fileURLWithPath: transcript.filePath)
                try orchestrator.startWatchingTranscript(transcriptId: transcript.id, fileURL: fileURL)
            }
        } catch {
            log.error("Watcher recovery failed: \(error.localizedDescription)")
        }
    }

    /// Attempt to recover stalled hoover
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
