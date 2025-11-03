import Foundation
import Observation
import OSLog
import ContextifyCore
import AppKit

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

    private(set) var isCollapsed = false
    private(set) var isMonitoring = false
    private(set) var isProcessing = false
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?
    var autoScroll = true

    @ObservationIgnored private var didEmitSessionStart = false
    @ObservationIgnored private(set) var activeSession: TranscriptSession?
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
    @ObservationIgnored private var lastSeenCursor: (timestamp: Int, createdAt: Int, id: String)?  // Keyset cursor for incremental updates
    @ObservationIgnored var orchestrator: TranscriptOrchestrator!  // Shared instance (nonisolated, accessible to inventory view)
    @ObservationIgnored private var seenEntryIDs = Set<String>()  // Deduplicate entries
    @ObservationIgnored private var backgroundTasks: Task<Void, Never>?  // Parent task for all background work
    private(set) var cacheMissGenerator: TimelineCacheMissGenerator?  // Background cache generation
    // Observable flag for status bar - avoids exposing non-Sendable generator object
    private(set) var isCacheGeneratorActive = false
    @ObservationIgnored nonisolated(unsafe) private var cacheUpdateObserver: AnyObject?  // For cache update notifications
    @ObservationIgnored nonisolated(unsafe) private var projectChangeObserver: AnyObject?  // For project root change notifications
    @ObservationIgnored private var updateInFlight = false  // Single-flight guard for processIncrementalUpdate
    @ObservationIgnored private var updateDirty = false    // Marks that updates arrived during processing
    @ObservationIgnored private let updateDrainMaxItersDefault = 8  // Max drain loop iterations to prevent starvation
    @ObservationIgnored private var updateDrainItersRemaining = 8  // Current iterations remaining
    @ObservationIgnored private var debounceTask: Task<Void, Never>?  // Debounce task for transcript updates

    private init() {
        // Set up project change notifications early, so we can react to project selection
        // even if monitoring hasn't started yet
        setupProjectChangeNotifications()
    }

    deinit {
        // Cancel any pending debounce task
        debounceTask?.cancel()

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
    func startMonitoring() {
        // Cancel residual background work before starting new group
        backgroundTasks?.cancel()
        backgroundTasks = nil
        seenEntryIDs.removeAll(keepingCapacity: false)

        guard !isMonitoring else { return }

        log.info("⭐️ Timeline integration starting")
        log.info("Starting SQL-based timeline monitoring")

        Task { @MainActor [weak self] in
            guard let self else { return }

            // 1. Get project from HUD
            guard let projectRoot = HUDViewModel.shared.projectRootURL else {
                self.lastError = "No project root set"
                self.log.error("No project root URL available from HUDViewModel")
                return
            }

            // 2. Initialize shared orchestrator (nonisolated - safe for concurrent access)
            do {
                self.orchestrator = try TranscriptOrchestrator(dbManager: .shared)

                // CRITICAL: Create project on main actor and wait for DB commit
                // This ensures the project exists before background tasks access it
                self.currentProjectId = try self.orchestrator.getOrCreateProject(
                    name: projectRoot.lastPathComponent,
                    rootPath: projectRoot.path
                )
                self.log.info("📁 Project ID set: \(self.currentProjectId ?? "nil")")

                // Verify project was persisted (forces read from DB, ensures commit)
                let projectId = self.currentProjectId!
                guard let _ = try self.orchestrator.getProject(id: projectId) else {
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

                // 4. Start background work (discovery + debounced updates) in a single parent task
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
                    }
                }

                // 5. Load initial feed (fast - single query)
                await self.loadFeedFromSQL()

                // 6. Subscribe to realtime updates (SQL notifications handled by watchForDebouncedTranscriptUpdates)
                // self.setupSQLNotifications()  // Disabled: debouncing is handled by background watcher
                self.setupCacheUpdateNotifications()
                // Project change notifications already set up in init()

                self.isMonitoring = true
                self.log.info("SQL-based timeline monitoring started for project: \(projectRoot.lastPathComponent)")
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
    func toggleCollapsed() {
        isCollapsed.toggle()
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

        // Restart monitoring with new project
        log.debug("handleProjectRootChange: restarting monitoring")
        startMonitoring()
        log.info("✅ Project root change complete - monitoring restarted")
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

            // Update cursor from latest entry
            if let latest = transcriptEntries.first {
                lastSeenCursor = (timestamp: latest.timestamp, createdAt: latest.createdAt, id: latest.id)
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
            log.warning("Cannot load sessions: no project or orchestrator")
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
            action = .generating  // Mark as pending generation
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

        isProcessing = true
        defer { isProcessing = false }

        do {
            let startTime = Date()

            // Single query gets entries + cache
            let feed = try orchestrator.getRecentFeed(
                forProject: projectId,
                limit: config.maxEntries,
                generatorSignature: generatorSignature()
            )

            log.info("📊 Feed loaded: \(feed.count) entries from DB")

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

            // Track latest cursor for incremental updates
            if let latestEntry = feed.first {
                let e = latestEntry.0
                lastSeenCursor = (timestamp: e.timestamp, createdAt: e.createdAt, id: e.id)
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

            log.info("Updated \(updates.count) entries with fresh cache summaries")
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

                // Update cursor to latest entry added
                if let latestNew = newEntries.max(by: { a, b in
                    if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
                    if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                    return a.id < b.id
                }) {
                    lastSeenCursor = (timestamp: latestNew.timestamp, createdAt: latestNew.createdAt, id: latestNew.id)
                }

                lastUpdate = Date()

                let elapsed = Date().timeIntervalSince(startTime)
                log.info("Added \(addedCount) new entries (\(newEntries.count - addedCount) duplicates) in \(Int(elapsed * 1000))ms")
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
            log.info("🔎 discoverNewTranscripts: starting with projectId=\(projectId)")
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
            log.info("✅ discoverNewTranscripts: verified project \(projectId) exists")
        }

        if Task.isCancelled { return }

        // Find JSONL files on disk for THIS project only
        guard let projectRoot = await HUDViewModel.shared.projectRootURL else { return }

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
            log.info("🔍 Discovery: Found \(filesOnDisk.count) .jsonl files in \(expectedDirName)")
        }

        if Task.isCancelled { return }

        // Use new upsert API - handles idempotency via path normalization
        // Extract session ID from filename (matches ProjectDiscoveryService behavior)
        let discovered = filesOnDisk.map { file in
            DiscoveredTranscript(
                fileURL: file,
                provider: "claude.code",
                sessionId: file.deletingPathExtension().lastPathComponent
            )
        }

        let resolved = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)

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
