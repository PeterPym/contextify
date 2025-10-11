import Foundation
import Observation
import OSLog
import ContextifyCore
import AppKit

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

    private(set) var entries: [TimelineEntry] = []

    /// Entries filtered to the active session (UI-visible subset)
    var visibleEntries: [TimelineEntry] {
        guard let id = currentSessionId else { return [] }
        return entries.filter { $0.sessionId == id }
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
    @ObservationIgnored private(set) var allSessions: [TranscriptSession] = []
    @ObservationIgnored private var lastUserDirectiveId: UUID?
    @ObservationIgnored private var lastUserDirectiveTimestamp: Date?
    @ObservationIgnored private var sessionEpoch = UUID()  // Track session to cancel cross-session tasks
    @ObservationIgnored private var currentSessionId: String?  // Current session identifier for timeline entries
    @ObservationIgnored private var currentProjectId: String?  // SQL project ID
    @ObservationIgnored private var lastSeenTimestamp: Int?  // Last timestamp seen for incremental updates
    @ObservationIgnored private var notificationObserver: NSObjectProtocol?  // For SQL notifications
    @ObservationIgnored private var orchestrator: TranscriptOrchestrator!  // Shared instance
    @ObservationIgnored private var seenEntryIDs = Set<String>()  // Deduplicate entries
    @ObservationIgnored private var pendingNotificationTask: Task<Void, Never>?  // For debouncing
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?  // Background discovery
    @ObservationIgnored private var cacheMissGenerator: TimelineCacheMissGenerator?  // Background cache generation
    @ObservationIgnored private var cacheUpdateObserver: NSObjectProtocol?  // For cache update notifications

    private init() {}

    @MainActor
    func startMonitoring() {
        guard !isMonitoring else { return }

        log.info("Starting SQL-based timeline monitoring")

        Task { @MainActor [weak self] in
            guard let self else { return }

            // 1. Get project from HUD
            guard let projectRoot = HUDViewModel.shared.projectRootURL else {
                self.lastError = "No project root set"
                self.log.error("No project root URL available from HUDViewModel")
                return
            }

            // 2. Initialize shared orchestrator
            do {
                self.orchestrator = try TranscriptOrchestrator(dbManager: .shared)

                self.currentProjectId = try self.orchestrator.getOrCreateProject(
                    name: projectRoot.lastPathComponent,
                    rootPath: projectRoot.path
                )

                // 3. Initialize cache miss generator
                self.cacheMissGenerator = TimelineCacheMissGenerator(orchestrator: self.orchestrator)

                // 4. Background discover + hoover of new transcripts
                self.discoveryTask = Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.discoverNewTranscripts(projectId: self.currentProjectId!, orchestrator: self.orchestrator)
                    } catch {
                        await MainActor.run {
                            self.log.error("Background discovery failed: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }

                // 5. Load initial feed (fast - single query)
                await self.loadFeedFromSQL()

                // 6. Subscribe to realtime updates
                self.setupSQLNotifications()
                self.setupCacheUpdateNotifications()

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
        pendingNotificationTask?.cancel()
        pendingNotificationTask = nil
        discoveryTask?.cancel()
        discoveryTask = nil

        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }

        if let observer = cacheUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
            cacheUpdateObserver = nil
        }

        // Stop all watchers using shared orchestrator
        if orchestrator != nil {
            orchestrator.stopAllWatchers()
        }

        // Clear state
        seenEntryIDs.removeAll()
        lastSeenTimestamp = nil
        currentProjectId = nil
        cacheMissGenerator = nil
    }

    @MainActor
    func toggleCollapsed() {
        isCollapsed.toggle()
    }

    @MainActor
    func clearEntries() {
        entries.removeAll()
        didEmitSessionStart = false
        lastSeenTimestamp = nil
        seenEntryIDs.removeAll()
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
            let cacheKeys = transcriptEntries.compactMap { entry -> (String, String)? in
                guard let windowSha = entry.windowSha256 else { return nil }
                return (entry.contentSha256, windowSha)
            }

            let cacheMap = try orchestrator.getCachedTimelineMany(keys: cacheKeys)

            // Map to timeline entries
            seenEntryIDs.removeAll(keepingCapacity: true)
            entries = transcriptEntries.map { entry in
                seenEntryIDs.insert(entry.id)
                let cacheKey = entry.windowSha256.map { "\(entry.contentSha256)|\($0)" }
                let cache = cacheKey.flatMap { cacheMap[$0] }
                return toTimelineEntry(entry, cached: cache)
            }

            // Update timestamp
            if let latest = transcriptEntries.first {
                lastSeenTimestamp = latest.timestamp
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

        entries.append(e)
        if entries.count > config.maxEntries {
            entries = Array(entries.suffix(config.maxEntries))
        }
    }

    // MARK: - SQL-based Processing

    private func toTimelineEntry(_ entry: TranscriptEntry, cached: TimelineCache?) -> TimelineEntry {
        // Use cached summary if available, otherwise fallback
        let summary: String
        if let cache = cached {
            // Honor user edits first
            if cache.userEdited == 1, let userText = cache.userText, !userText.isEmpty {
                summary = userText
            } else {
                // Use generated forms
                summary = cache.selectedForm == "present" ? cache.presentForm : cache.pastForm
            }
        } else {
            // Fallback for cache miss (will trigger LLM generation in background)
            summary = String(entry.content.prefix(100)) + (entry.content.count > 100 ? "…" : "")
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
            action: .none,
            sessionId: entry.sessionId
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

            // Map to UI entries and track seen IDs + collect cache misses
            seenEntryIDs.removeAll(keepingCapacity: true)
            var misses: [CacheMiss] = []

            self.entries = feed.map { entry, cache in
                seenEntryIDs.insert(entry.id)

                // Collect cache miss for background generation
                if cache == nil, let windowSha = entry.windowSha256 {
                    let miss = CacheMiss(
                        contentSha256: entry.contentSha256,
                        windowSha256: windowSha,
                        content: entry.content,
                        context: entry.content  // TODO: Add surrounding context
                    )
                    misses.append(miss)
                }

                return toTimelineEntry(entry, cached: cache)
            }

            // Queue cache misses for background generation
            if !misses.isEmpty, let generator = cacheMissGenerator {
                Task {
                    await generator.queueMisses(misses)
                }
            }

            // Track latest timestamp for incremental updates
            if let latestEntry = feed.first {
                lastSeenTimestamp = latestEntry.0.timestamp
            }

            lastUpdate = Date()
            lastError = nil

            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 0.02 {
                log.warning("Feed load took \(Int(elapsed * 1000))ms (threshold: 20ms)")
            }
            log.info("Loaded \(self.entries.count) entries from SQL feed in \(Int(elapsed * 1000))ms")
        } catch {
            lastError = "Failed to load timeline: \(error.localizedDescription)"
            log.error("SQL feed load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setupSQLNotifications() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TranscriptUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract sendable data before crossing isolation boundary
            let projectId = notification.userInfo?["projectId"] as? String
            Task { @MainActor [weak self] in
                await self?.handleTranscriptUpdate(projectId: projectId)
            }
        }
    }

    private func setupCacheUpdateNotifications() {
        cacheUpdateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TimelineCacheUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleCacheUpdate()
            }
        }
    }

    @MainActor
    private func handleCacheUpdate() async {
        // Lightweight refresh: re-query cache for existing entries without full reload
        guard let projectId = currentProjectId, orchestrator != nil else { return }

        log.debug("Cache updated, refreshing summaries for existing entries")

        do {
            // Batch cache lookup for all current entries
            let cacheKeys = entries.compactMap { entry -> (String, String)? in
                // Extract hashes from sourceIdentifier or entry data
                // For now, skip entries without window SHA
                return nil  // TODO: Store hashes in TimelineEntry for efficient refresh
            }

            if cacheKeys.isEmpty {
                // Fallback: do full reload to re-bind all summaries
                log.info("No cache keys available for lightweight refresh, doing full reload")
                await loadFeedFromSQL()
                return
            }

            // Re-query cache
            let cacheMap = try orchestrator.getCachedTimelineMany(keys: cacheKeys)

            // Update summaries in place (keep stable IDs)
            // TODO: Implement efficient in-place update
            // For now, just reload
            await loadFeedFromSQL()

        } catch {
            log.error("Cache refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func handleTranscriptUpdate(projectId: String?) async {
        // Filter by project
        if let notifProjectId = projectId,
           notifProjectId != currentProjectId {
            log.debug("Ignoring notification for different project: \(notifProjectId)")
            return
        }

        guard let projectId = currentProjectId, orchestrator != nil else {
            log.warning("Ignoring notification: no project or orchestrator")
            return
        }

        // Debounce: cancel pending task and schedule new one
        pendingNotificationTask?.cancel()
        pendingNotificationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Wait for debounce interval
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            guard !Task.isCancelled else { return }

            await self.processIncrementalUpdate()
        }
    }

    @MainActor
    private func processIncrementalUpdate() async {
        guard let projectId = currentProjectId, orchestrator != nil else { return }

        // If no lastSeenTimestamp, do full reload instead
        guard let lastTimestamp = lastSeenTimestamp else {
            log.info("No lastSeenTimestamp, doing full reload")
            await loadFeedFromSQL()
            return
        }

        do {
            let startTime = Date()

            // Get new entries (strict > to avoid replays)
            let newEntries = try orchestrator.getNewEntries(
                forProject: projectId,
                afterTimestamp: lastTimestamp
            )

            guard !newEntries.isEmpty else {
                log.debug("No new entries in incremental update")
                return
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
                let cache = try? orchestrator.getCachedTimeline(
                    contentSha256: entry.contentSha256,
                    windowSha256: entry.windowSha256 ?? ""
                )

                // Collect cache miss for background generation
                if cache == nil, let windowSha = entry.windowSha256 {
                    let miss = CacheMiss(
                        contentSha256: entry.contentSha256,
                        windowSha256: windowSha,
                        content: entry.content,
                        context: entry.content  // TODO: Add surrounding context
                    )
                    misses.append(miss)
                }

                let timelineEntry = toTimelineEntry(entry, cached: cache)
                entries.append(timelineEntry)
                addedCount += 1
            }

            // Queue cache misses for background generation
            if !misses.isEmpty, let generator = cacheMissGenerator {
                Task {
                    await generator.queueMisses(misses)
                }
            }

            // Sort to maintain deterministic ordering: timestamp DESC, then id DESC
            entries.sort { a, b in
                if a.timestamp != b.timestamp {
                    return a.timestamp > b.timestamp
                }
                return a.sourceIdentifier > b.sourceIdentifier
            }

            // Trim to max size
            if entries.count > config.maxEntries {
                entries = Array(entries.suffix(config.maxEntries))
            }

            // Update timestamp with max to handle out-of-order deliveries
            let maxTimestamp = newEntries.map(\.timestamp).max() ?? lastTimestamp
            lastSeenTimestamp = max(lastSeenTimestamp ?? 0, maxTimestamp)

            lastUpdate = Date()

            let elapsed = Date().timeIntervalSince(startTime)
            log.info("Added \(addedCount) new entries (\(newEntries.count - addedCount) duplicates) in \(Int(elapsed * 1000))ms")
        } catch {
            lastError = "Failed to fetch new entries: \(error.localizedDescription)"
            log.error("Incremental update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func discoverNewTranscripts(projectId: String, orchestrator: TranscriptOrchestrator) async throws {
        // Find JSONL files on disk
        guard let projectRoot = HUDViewModel.shared.projectRootURL else { return }

        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        let filesOnDisk = try FileManager.default.contentsOfDirectory(
            at: claudeDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }

        // Get files already in SQL
        let filesInSQL = Set(try orchestrator.getTranscripts(forProject: projectId).map { $0.filePath })

        // Find new files
        let newFiles = filesOnDisk.filter { !filesInSQL.contains($0.path) }

        guard !newFiles.isEmpty else {
            log.info("No new transcripts to discover")
            return
        }

        log.info("Discovering \(newFiles.count) new transcripts")

        // Batch discover with progress
        let files = newFiles.map { (url: $0, provider: "claude.code", sessionId: nil as String?) }

        try orchestrator.discoverTranscripts(
            projectId: projectId,
            transcriptFiles: files,
            progress: nil
        )

        // Run maintenance after bulk ingest
        try orchestrator.performMaintenance()

        log.info("Discovery complete, refreshing feed")

        // Refresh feed on main
        await MainActor.run {
            Task { await self.loadFeedFromSQL() }
        }
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
