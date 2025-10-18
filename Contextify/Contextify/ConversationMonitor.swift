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

    // Derived map stays in sync because it's computed
    var indexByCacheKey: [CacheKey: Int] {
        Dictionary(uniqueKeysWithValues: entries.enumerated().compactMap { i, e in
            e.cacheKey.map { ($0, i) }
        })
    }

    func replace(with entries: [TimelineEntry]) {
        self.entries = entries
        revision &+= 1
    }

    func append(_ e: TimelineEntry) {
        entries.append(e)
        revision &+= 1
    }

    func update(at index: Int, to newValue: TimelineEntry) {
        guard entries.indices.contains(index) else { return }
        entries[index] = newValue
        revision &+= 1
    }

    func sortChronologically() {
        entries.sort { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.sourceIdentifier < b.sourceIdentifier
        }
        revision &+= 1
    }

    func trim(to max: Int) {
        if entries.count > max { entries = Array(entries.suffix(max)); revision &+= 1 }
    }
}

@Observable
@MainActor
final class ConversationMonitor {
    static let shared = ConversationMonitor()

    private let log = Logger(subsystem: "dev.contextify", category: "Timeline")
    private let config = MonitorConfig()
    private let conversationResolver = ActiveConversationResolver(providers: [
        ClaudeTranscriptProvider(),
        CodexTranscriptProvider()
    ])
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

    /// Cached filtered entries (invalidated when entries or currentSessionId changes)
    @ObservationIgnored private var cachedVisibleEntries: [TimelineEntry]?
    @ObservationIgnored private var cachedForSessionId: String??
    @ObservationIgnored private var cachedForRevision: UInt64 = .max

    /// Entries filtered to the active session (UI-visible subset)
    /// When no session is selected, shows all entries (project-wide view)
    /// Uses optional caching to avoid recomputing filter on every access
    var visibleEntries: [TimelineEntry] {
        // Check if cache is valid
        if let cached = cachedVisibleEntries,
           cachedForSessionId == currentSessionId,
           cachedForRevision == state.revision {
            return cached
        }

        // Recompute and cache (read directly from state.entries for explicit observation tracking)
        let filtered: [TimelineEntry]
        if let id = currentSessionId {
            filtered = state.entries.filter { $0.sessionId == id }
        } else {
            filtered = state.entries  // Show all when no session filter
        }

        cachedVisibleEntries = filtered
        cachedForSessionId = currentSessionId
        cachedForRevision = state.revision
        return filtered
    }

    private(set) var isCollapsed = false
    private(set) var isMonitoring = false
    private(set) var isProcessing = false
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?
    var autoScroll = true

    @ObservationIgnored private var didEmitSessionStart = false
    @ObservationIgnored private(set) var activeSession: TranscriptSession?
    @ObservationIgnored private var conversationResolverTask: Task<Void, Never>?
    // MUST be observable for UI - inventory and session switching depend on this
    private(set) var allSessions: [TranscriptSession] = []
    @ObservationIgnored private var lastUserDirectiveId: UUID?
    @ObservationIgnored private var lastUserDirectiveTimestamp: Date?
    @ObservationIgnored private var sessionEpoch = UUID()  // Track session to cancel cross-session tasks
    // MUST be observable for UI - visibleEntries filtering depends on this
    private var currentSessionId: String? {  // Current session identifier for timeline entries
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
    @ObservationIgnored private var orchestrator: TranscriptOrchestrator!  // Shared instance (nonisolated)
    @ObservationIgnored private var seenEntryIDs = Set<String>()  // Deduplicate entries
    @ObservationIgnored private var backgroundTasks: Task<Void, Never>?  // Parent task for all background work
    @ObservationIgnored private var cacheMissGenerator: TimelineCacheMissGenerator?  // Background cache generation
    @ObservationIgnored private var cacheUpdateObserver: NSObjectProtocol?  // For cache update notifications
    @ObservationIgnored private var projectChangeObserver: NSObjectProtocol?  // For project root change notifications
    @ObservationIgnored private var updateInFlight = false  // Single-flight guard for processIncrementalUpdate
    @ObservationIgnored private var updateDirty = false    // Marks that updates arrived during processing
    @ObservationIgnored private let updateDrainMaxItersDefault = 8  // Max drain loop iterations to prevent starvation
    @ObservationIgnored private var updateDrainItersRemaining = 8  // Current iterations remaining
    @ObservationIgnored private var debounceTask: Task<Void, Never>?  // Debounce task for transcript updates

    private init() {}

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

                // 3. Initialize cache miss generator
                self.cacheMissGenerator = TimelineCacheMissGenerator(orchestrator: self.orchestrator)

                // 4. Start background work (discovery + debounced updates) in a single parent task
                let orchestrator = self.orchestrator!
                self.log.info("🚀 Spawning background tasks for project: \(projectId)")
                self.backgroundTasks = Task { [weak self] in
                    guard let self else { return }
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
                self.setupProjectChangeNotifications()

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
        conversationResolverTask?.cancel()
        conversationResolverTask = nil
        backgroundTasks?.cancel()   // NEW: cancels the whole background task group
        backgroundTasks = nil
        debounceTask?.cancel()
        debounceTask = nil

        if let observer = cacheUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
            cacheUpdateObserver = nil
        }

        if let observer = projectChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            projectChangeObserver = nil
        }

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

    /// Cancel pending debounce task on project/session changes to avoid late callbacks into torn state
    @MainActor
    private func onProjectOrSessionChange() {
        debounceTask?.cancel()
        debounceTask = nil
        // Also invalidate visible entries cache
        cachedVisibleEntries = nil
        cachedForSessionId = nil
        cachedForRevision = .max
    }

    /// Structured watcher for debounced transcript updates (off main actor, no polling)
    private func watchForDebouncedTranscriptUpdates() async {
        let center = NotificationCenter.default
        let name = NSNotification.Name("TranscriptUpdated")

        for await note in center.notifications(named: name) {
            if Task.isCancelled { break }
            let pid = note.userInfo?["projectId"] as? String

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard pid == nil || pid == self.currentProjectId else { return }

                // Cancel existing debounce task and start new one
                self.debounceTask?.cancel()
                self.debounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
                    guard let self, !Task.isCancelled else { return }
                    await self.processIncrementalUpdate()
                }
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
        stopMonitoring()

        // Clear all entries
        clearEntries()

        // Restart monitoring with new project
        startMonitoring()
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
        // Filter by transcript file path
        guard let projectId = currentProjectId, orchestrator != nil else {
            log.warning("Cannot switch session: no project or orchestrator")
            return
        }

        do {
            // Find transcript ID by file path
            let transcripts = try orchestrator.getTranscripts(forProject: projectId)
            guard let transcript = transcripts.first(where: { $0.filePath == session.fileURL.path }) else {
                log.warning("No transcript found for session: \(session.fileURL.path)")
                // Fall back to loading all entries
                await loadFeedFromSQL()
                return
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
            let sessions = Self.mapTranscriptsToSessions(transcripts: transcripts, latestTimestamps: latestTimestamps)

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
            isCompletion: entry.isCompletion == 1,
            isDirective: entry.isDirective == 1,
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
        projectChangeObserver = NotificationCenter.default.addObserver(
            forName: .projectRootDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.handleProjectRootChange()
            }
        }
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
        if updateInFlight { updateDirty = true; return }
        updateInFlight = true
        defer { updateInFlight = false }

        repeat {
            updateDirty = false

            guard let projectId = currentProjectId, orchestrator != nil else { return }

            // If no cursor, do full reload instead
            guard let cursor = lastSeenCursor else {
                log.info("No cursor available, doing full reload")
                await loadFeedFromSQL()
                return
            }

            do {
                let startTime = Date()

                // Get new entries using keyset pagination (prevents duplicates/skips)
                let newEntries = try orchestrator.getEntriesAfterCursor(
                    forProject: projectId,
                    after: cursor
                )

                guard !newEntries.isEmpty else {
                    log.debug("No new entries in incremental update")
                    continue  // Check if more updates arrived
                }

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
                    Task {
                        await generator.queueMisses(misses)
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

        updateDrainItersRemaining = updateDrainMaxItersDefault  // Reset for next call
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
        let filesOnDisk = try FileManager.default.contentsOfDirectory(
            at: claudeDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }

        await MainActor.run {
            log.info("🔍 Discovery: Found \(filesOnDisk.count) .jsonl files in \(expectedDirName)")
        }

        if Task.isCancelled { return }

        // Get files already in SQL
        let transcripts = try orchestrator.getTranscripts(forProject: projectId)
        let filesInSQL = Set(transcripts.map { $0.filePath })

        if Task.isCancelled { return }

        await MainActor.run {
            log.info("📚 Discovery: \(transcripts.count) transcripts already in DB")
        }

        // Find new files
        let newFiles = filesOnDisk.filter { !filesInSQL.contains($0.path) }

        if !newFiles.isEmpty {
            await MainActor.run {
                log.info("Discovering \(newFiles.count) new transcripts for project \(projectId)")
            }

            // Batch discover with progress
            let files = newFiles.map { (url: $0, provider: "claude.code", sessionId: nil as String?) }

            try orchestrator.discoverTranscripts(
                projectId: projectId,
                transcriptFiles: files,
                progress: nil
            )

            // Run maintenance after bulk ingest
            try orchestrator.performMaintenance()

            log.info("Discovery complete")
        } else {
            log.info("No new transcripts to discover")
        }

        // Refresh sessions list for transcript inventory (re-fetch after discovery)
        let updatedTranscripts = try orchestrator.getTranscripts(forProject: projectId)
        let latestTimestamps = try orchestrator.latestTimestampsByTranscript(projectId: projectId)
        let sessions = Self.mapTranscriptsToSessions(transcripts: updatedTranscripts, latestTimestamps: latestTimestamps)
        await MainActor.run {
            self.log.info("📝 Mapped \(updatedTranscripts.count) transcripts to sessions")
            self.allSessions = sessions
            self.log.info("✅ allSessions updated with \(self.allSessions.count) sessions")
            Task { await self.loadFeedFromSQL() }
        }
    }

    nonisolated private static func mapTranscriptsToSessions(transcripts: [Transcript], latestTimestamps: [String: Int]) -> [TranscriptSession] {
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

            return TranscriptSession(
                provider: provider,
                identifier: transcript.id,
                fileURL: fileURL,
                lastActivity: lastActivity
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
