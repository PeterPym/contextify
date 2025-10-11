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

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }

        log.info("Starting SQL-based timeline monitoring")

        Task { @MainActor [weak self] in
            guard let self else { return }

            // 1. Get project from HUD
            guard let projectRoot = HUDViewModel.shared.projectRootURL else {
                self.lastError = "No project root set"
                log.error("No project root URL available from HUDViewModel")
                return
            }

            // 2. Get or create project in SQL
            do {
                let orchestrator = try TranscriptOrchestrator(dbManager: .shared)

                self.currentProjectId = try orchestrator.getOrCreateProject(
                    name: projectRoot.lastPathComponent,
                    rootPath: projectRoot.path
                )

                // 3. Background discover + hoover of new transcripts
                Task.detached(priority: .userInitiated) {
                    do {
                        try await self.discoverNewTranscripts(projectId: self.currentProjectId!, orchestrator: orchestrator)
                    } catch {
                        await MainActor.run {
                            self.log.error("Background discovery failed: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }

                // 4. Load initial feed (fast - single query)
                await self.loadFeedFromSQL()

                // 5. Subscribe to realtime updates
                self.setupSQLNotifications()

                self.isMonitoring = true
                self.log.info("SQL-based timeline monitoring started for project: \(projectRoot.lastPathComponent)")
            } catch {
                self.lastError = "Failed to start monitoring: \(error.localizedDescription)"
                self.log.error("Monitoring startup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        activeSession = nil
        conversationResolverTask?.cancel()
        conversationResolverTask = nil
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
        // Stop all watchers
        if let projectId = currentProjectId {
            do {
                let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
                orchestrator.stopAllWatchers()
            } catch {
                log.error("Failed to stop watchers: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func toggleCollapsed() {
        isCollapsed.toggle()
    }

    func clearEntries() {
        entries.removeAll()
        didEmitSessionStart = false
        lastSeenTimestamp = nil
    }

    func requestImmediateRefresh(trigger: TimelineRefreshTrigger) {
        Task {
            await loadFeedFromSQL()
        }
    }

    /// Public method for user-initiated session switch from transcript inventory
    func switchToSessionFromUser(_ session: TranscriptSession) async {
        // With SQL backend, just reload the feed
        // TODO: Implement session-specific filtering if needed
        await loadFeedFromSQL()
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
            summary = cache.selectedForm == "present" ? cache.presentForm : cache.pastForm
        } else {
            // Fallback for cache miss (will trigger LLM generation)
            summary = String(entry.content.prefix(100)) + (entry.content.count > 100 ? "…" : "")
        }

        let disposition = cached.flatMap { Disposition(rawValue: $0.disposition) } ?? .active

        return TimelineEntry(
            id: UUID(uuidString: entry.id) ?? UUID(),
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

    private func loadFeedFromSQL() async {
        guard let projectId = currentProjectId else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Single query gets entries + cache
            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
            let feed = try orchestrator.getRecentFeed(
                forProject: projectId,
                limit: config.maxEntries,
                generatorSignature: generatorSignature()
            )

            // Map to UI entries
            self.entries = feed.map { toTimelineEntry($0.0, cached: $0.1) }

            // Track latest timestamp for incremental updates
            if let latest = entries.first {
                lastSeenTimestamp = Int(latest.timestamp.timeIntervalSince1970)
            }

            lastUpdate = Date()
            lastError = nil

            log.info("Loaded \(entries.count) entries from SQL feed")
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
            Task { @MainActor [weak self] in
                await self?.handleTranscriptUpdate(notification)
            }
        }
    }

    private func handleTranscriptUpdate(_ notification: Notification) async {
        guard let projectId = currentProjectId,
              let lastTimestamp = lastSeenTimestamp else { return }

        do {
            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
            let newEntries = try orchestrator.getNewEntries(
                forProject: projectId,
                afterTimestamp: lastTimestamp
            )

            guard !newEntries.isEmpty else { return }

            // Convert to timeline entries (no cache initially)
            let timelineEntries = newEntries.map { toTimelineEntry($0, cached: nil) }

            // Append to feed
            entries.append(contentsOf: timelineEntries)

            // Trim to max size
            if entries.count > config.maxEntries {
                entries = Array(entries.suffix(config.maxEntries))
            }

            // Update timestamp
            if let latest = newEntries.last {
                lastSeenTimestamp = latest.timestamp
            }

            lastUpdate = Date()

            log.debug("Added \(newEntries.count) new entries from SQL")
        } catch {
            log.error("Failed to fetch new entries: \(error.localizedDescription, privacy: .public)")
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
        let files = newFiles.map { (url: $0, provider: "claude.code", sessionId: nil) }

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
        // Centralize and bump when prompt/model changes
        struct GeneratorSignature {
            let model: String
            let modelVersion: String
            let prompt: String
            let promptVersion: String

            var string: String {
                "\(model)@\(modelVersion)::\(prompt)@\(promptVersion)"
            }
        }

        return GeneratorSignature(
            model: "gpt-4o",
            modelVersion: "2025-09",
            prompt: "timeline",
            promptVersion: "3"
        ).string
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

        let summary = "Timeline monitoring started"
        let detail: String
        if let fileURL = currentConversationFile {
            detail = """
            Timeline monitoring started

            Monitoring: \(fileURL.lastPathComponent)
            Path: \(fileURL.path)
            """
        } else {
            detail = "Timeline monitoring started (no conversation file found yet)"
        }
        let action: TimelineEntryAction
        if let fileURL = currentConversationFile {
            action = .revealInInventory(transcriptPath: fileURL.path)
        } else {
            action = .none
        }

        let entry = TimelineEntry(
            kind: .system,
            summary: summary,
            detail: detail,
            sourceContent: detail,
            sourceContext: makeSourceContext(identifier: "system-start"),
            sourceIdentifier: "system-start",
            action: action,
            sessionId: currentSessionId
        )
        entries.append(entry)
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
