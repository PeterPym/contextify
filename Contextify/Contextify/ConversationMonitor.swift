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
    private(set) var isCollapsed = false
    private(set) var isMonitoring = false
    private(set) var isProcessing = false
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?
    var autoScroll = true

    @ObservationIgnored private var fileWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var conversationFileDescriptor: CInt = -1
    @ObservationIgnored private var lastProcessedLine: Int = 0
    @ObservationIgnored private var currentLineNumber: Int = 0
    @ObservationIgnored private var seenMessageUUIDs: Set<String> = []
    @ObservationIgnored private var didEmitSessionStart = false
    @ObservationIgnored private var currentConversationFile: URL?
    @ObservationIgnored private(set) var activeSession: TranscriptSession?
    @ObservationIgnored private var conversationResolverTask: Task<Void, Never>?
    @ObservationIgnored private(set) var allSessions: [TranscriptSession] = []
    @ObservationIgnored private var lastUserDirectiveId: UUID?
    @ObservationIgnored private var lastUserDirectiveTimestamp: Date?
    @ObservationIgnored private var sessionEpoch = UUID()  // Track session to cancel cross-session tasks

    private init() {}

    func startMonitoring() {
        guard fileWatcher == nil else { return }
        log.info("Starting conversation timeline monitoring via project conversation files")
        log.info("HUDViewModel projectRootURL: \(String(describing: HUDViewModel.shared.projectRootURL?.path), privacy: .public)")
        isMonitoring = true

        // Find and watch the current project's conversation file
        Task { [weak self] in
            await self?.refreshActiveConversation(force: true)
        }
        startConversationResolverLoop()

        // Cache flush on app terminate is now handled by AppDelegate.applicationShouldTerminate
    }

    func stopMonitoring() {
        tearDownFileWatcher()
        isMonitoring = false
        currentConversationFile = nil
        activeSession = nil
        conversationResolverTask?.cancel()
        conversationResolverTask = nil
    }

    func toggleCollapsed() {
        isCollapsed.toggle()
    }

    func clearEntries() {
        entries.removeAll()
        lastProcessedLine = 0
        seenMessageUUIDs.removeAll()
        didEmitSessionStart = false
        // Don't add system entry immediately - it will be added at the end
        // after backfill when processConversationFile() completes
    }

    func requestImmediateRefresh(trigger: TimelineRefreshTrigger) {
        Task {
            await processConversationFile()
        }
    }

    /// Public method for user-initiated session switch from transcript inventory
    func switchToSessionFromUser(_ session: TranscriptSession) async {
        await switchToSession(session, reason: .userSelection)
    }

    /// Public refresh method for manual refresh requests
    nonisolated func refresh() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshActiveConversation(force: true)
            }
        }
    }

    // MARK: - File Discovery & Watching

    private func refreshActiveConversation(force: Bool = false) async {
        guard let projectURL = HUDViewModel.shared.projectRootURL else {
            if activeSession != nil {
                log.info("No project root set; tearing down watcher")
                tearDownFileWatcher()
            }
            activeSession = nil
            currentConversationFile = nil
            allSessions = []
            lastError = "No project root set"
            log.error("Timeline: No project root URL available from HUDViewModel")
            return
        }

        log.info("Timeline: Resolving conversations for project: \(projectURL.path, privacy: .public)")

        // Use ProjectContext for worktree-aware session discovery
        guard let context = ProjectContext.current() else {
            log.error("Timeline: Failed to create ProjectContext")
            lastError = "Failed to create project context"
            return
        }

        let sessions = conversationResolver.resolveAllSessions(for: context)
        allSessions = sessions

        log.info("Timeline: Found \(sessions.count) total sessions for project (including worktrees)")

        guard let session = sessions.first else {
            if activeSession != nil {
                log.info("No active conversation sessions found; tearing down watcher")
                tearDownFileWatcher()
            }
            activeSession = nil
            currentConversationFile = nil
            lastError = "No conversation file found for this project"
            log.error("Timeline: No sessions found for project")
            return
        }

        log.info("Timeline: Active session at \(session.fileURL.path, privacy: .public)")

        if !force, let current = activeSession, current.fileURL == session.fileURL {
            // Same session, just update the reference
            activeSession = session
            log.info("Timeline: Session unchanged, skipping switch")
            return
        }

        // Only emit provider switch if we're actually changing sessions
        let switchReason: SessionSwitchReason
        if force {
            switchReason = .initial
        } else if activeSession != nil {
            // We had a previous session and it's different - this is a real provider change
            switchReason = .providerChange
        } else {
            // First time setting up - treat as initial
            switchReason = .initial
        }

        await switchToSession(session, reason: switchReason)
    }

    private enum SessionSwitchReason {
        case initial
        case providerChange
        case userSelection
    }

    private func switchToSession(_ session: TranscriptSession, reason: SessionSwitchReason) async {
        tearDownFileWatcher()

        activeSession = session
        currentConversationFile = session.fileURL

        // Clear state for new session - generate new epoch to invalidate in-flight tasks
        sessionEpoch = UUID()
        entries.removeAll()
        lastProcessedLine = 0
        seenMessageUUIDs.removeAll()
        didEmitSessionStart = false
        lastError = nil

        // Load cache for this conversation BEFORE processing
        do {
            try await TimelineCacheOrchestrator.shared.loadCache(for: session.fileURL)
            log.info("Timeline cache loaded for \(session.fileURL.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Failed to load timeline cache: \(error.localizedDescription, privacy: .public)")
        }

        configureFileWatcher(for: session.fileURL)

        // Add initializing placeholder entry to improve startup UX
        let placeholderEntry = TimelineEntry(
            kind: .system,
            timestamp: Date(),
            summary: "Initializing timeline…",
            detail: "Loading conversation history",
            sourceContext: makeSourceContext(identifier: "system-initializing"),
            sourceIdentifier: "system-initializing"
        )
        entries.append(placeholderEntry)

        // Process conversation file FIRST to backfill historical entries
        await processConversationFile()

        // Remove placeholder after processing completes
        entries.removeAll { $0.sourceIdentifier == "system-initializing" }

        // Add system message at the END (most recent position)
        if reason == .initial {
            ensureSessionStartEntry()
        } else if reason == .providerChange {
            emitProviderSwitchEntry(for: session)
        }
    }

    private func configureFileWatcher(for fileURL: URL) {
        let path = fileURL.path
        conversationFileDescriptor = open(path, O_EVTONLY)
        guard conversationFileDescriptor >= 0 else {
            log.error("Failed to open conversation file for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: conversationFileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                await self?.processConversationFile()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.conversationFileDescriptor >= 0 {
                close(self.conversationFileDescriptor)
                self.conversationFileDescriptor = -1
            }
        }

        source.resume()
        fileWatcher = source
        log.info("Watching transcript: \(fileURL.lastPathComponent, privacy: .public)")
    }

    private func tearDownFileWatcher() {
        if let watcher = fileWatcher {
            watcher.cancel()
            fileWatcher = nil
        } else if conversationFileDescriptor >= 0 {
            close(conversationFileDescriptor)
        }

        conversationFileDescriptor = -1
    }

    private func emitProviderSwitchEntry(for session: TranscriptSession) {
        let sourceId = "provider-switch-\(session.identifier)"

        // Deduplicate: don't add if we already have this exact system message
        if entries.contains(where: { $0.sourceIdentifier == sourceId && $0.kind == .system }) {
            log.info("🟡 emitProviderSwitchEntry: Already have provider switch entry for \(session.identifier), skipping")
            return
        }

        let providerName: String
        switch session.provider {
        case .claudeCode: providerName = "Claude Code"
        case .codexCLI: providerName = "Codex CLI"
        case .other: providerName = "AI Source"
        }

        let summary = "Switched to \(providerName) conversation"
        let detail = """
        Timeline switched to \(providerName) conversation

        Monitoring: \(session.fileURL.lastPathComponent)
        Path: \(session.fileURL.path)
        """
        let context = TimelineSourceContext(
            provider: session.provider,
            identifier: session.identifier,
            filePath: session.fileURL.path
        )

        let entry = TimelineEntry(
            kind: .system,
            timestamp: Date(),
            summary: summary,
            detail: detail,
            sourceContent: detail,
            sourceContext: context,
            sourceIdentifier: sourceId
        )

        entries.append(entry)
        if entries.count > config.maxEntries {
            entries = Array(entries.suffix(config.maxEntries))
        }
    }

    private func startConversationResolverLoop() {
        conversationResolverTask?.cancel()
        conversationResolverTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let interval = self.config.pollInterval
            let delay = UInt64(max(interval, 1) * 1_000_000_000)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay)
                await self.refreshActiveConversation()
            }
        }
    }

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

        #if DEBUG
        // Validate that sourceIdentifier is a valid UUID for user/assistant entries
        if entry.kind == .user || entry.kind == .assistant {
            if UUID(uuidString: entry.sourceIdentifier) == nil {
                assertionFailure("sourceIdentifier must be a valid UUID for user/assistant entries, got: \(entry.sourceIdentifier)")
            }
        }
        #endif

        entries.append(entry)
        if entries.count > config.maxEntries {
            entries = Array(entries.suffix(config.maxEntries))
        }
    }

    // MARK: - Processing

    private func processConversationFile() async {
        guard isMonitoring else {
            log.error("🔴 processConversationFile: not monitoring")
            return
        }
        guard !isProcessing else {
            log.error("🔴 processConversationFile: already processing")
            return
        }
        guard let fileURL = currentConversationFile else {
            log.error("🔴 processConversationFile: no conversation file")
            return
        }

        log.info("🟢 processConversationFile: starting, file=\(fileURL.lastPathComponent, privacy: .public)")

        isProcessing = true
        defer {
            isProcessing = false
            lastUpdate = Date()
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

            log.info("🟢 processConversationFile: read \(lines.count) lines, lastProcessedLine=\(self.lastProcessedLine)")

            // Only process new lines since last check
            guard lines.count > lastProcessedLine else {
                log.info("🟡 processConversationFile: no new lines to process")
                return
            }

            let newLines: ArraySlice<String>
            let shouldBackfillLimitedEntries: Bool
            if lastProcessedLine == 0 {
                // Initial load: Check if timeline is effectively empty (only system messages)
                let hasNonSystemMessages = entries.contains { $0.kind != .system }

                if !hasNonSystemMessages {
                    // Timeline is empty, backfill last 5 displayable entries
                    newLines = lines[...]
                    shouldBackfillLimitedEntries = true
                    log.info("🟢 processConversationFile: Initial load (empty timeline), will backfill last 5 displayable entries from \(lines.count) total lines")
                } else {
                    // Timeline already has content, don't backfill old messages
                    newLines = []
                    shouldBackfillLimitedEntries = false
                    log.info("🟢 processConversationFile: Initial load (existing timeline), skipping backfill")
                }
                lastProcessedLine = lines.count
            } else {
                // Incremental update: process all new lines
                newLines = lines[lastProcessedLine...]
                shouldBackfillLimitedEntries = false
                lastProcessedLine = lines.count
                log.info("🟢 processConversationFile: Incremental update, processing \(newLines.count) new lines")
            }

            var processedCount = 0
            var skippedCount = 0
            let entriesBeforeProcessing = entries.count

            // Process lines in forward order (chronological)
            for (index, line) in newLines.enumerated() {
                // Calculate actual line number in file - always use true file line number
                let startLine = lastProcessedLine - newLines.count
                let lineNumber = startLine + index + 1

                // If backfilling with limit, check if we have enough displayable entries
                if shouldBackfillLimitedEntries {
                    let newDisplayableEntries = entries.count - entriesBeforeProcessing
                    if newDisplayableEntries >= 20 {
                        log.info("🟢 processConversationFile: Reached displayable entries limit (\(newDisplayableEntries)), stopping backfill")
                        break
                    }
                }

                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    skippedCount += 1
                    continue
                }

                currentLineNumber = lineNumber
                await processConversationEntry(json)
                processedCount += 1
            }

            log.info("🟢 processConversationFile: processed \(processedCount) entries, skipped \(skippedCount), total timeline entries now: \(self.entries.count)")

            lastError = nil
        } catch {
            lastError = "Failed to read conversation: \(error.localizedDescription)"
            log.error("🔴 processConversationFile: Failed to process conversation file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func processConversationEntry(_ json: [String: Any]) async {
        guard let uuid = json["uuid"] as? String else {
            log.error("🔴 processConversationEntry: no uuid")
            return
        }
        guard !seenMessageUUIDs.contains(uuid) else {
            log.info("🟡 processConversationEntry: already seen uuid=\(uuid, privacy: .public)")
            return
        }
        seenMessageUUIDs.insert(uuid)

        if (json["isSidechain"] as? Bool) == true {
            log.info("🟡 processConversationEntry: skipping sidechain message")
            return
        }

        guard let type = json["type"] as? String else {
            log.error("🔴 processConversationEntry: no type for uuid=\(uuid, privacy: .public)")
            return
        }
        guard let timestampStr = json["timestamp"] as? String else {
            log.error("🔴 processConversationEntry: no timestamp for uuid=\(uuid, privacy: .public)")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let timestamp = formatter.date(from: timestampStr) else {
            log.error("🔴 processConversationEntry: invalid timestamp '\(timestampStr, privacy: .public)' for uuid=\(uuid, privacy: .public)")
            return
        }

        log.info("🟢 processConversationEntry: type=\(type, privacy: .public), uuid=\(uuid, privacy: .public)")

        switch type {
        case "user":
            await processUserMessage(json, timestamp: timestamp, uuid: uuid)
        case "assistant":
            await processAssistantMessage(json, timestamp: timestamp, uuid: uuid)
        default:
            log.info("🟡 processConversationEntry: skipping unknown type=\(type, privacy: .public)")
            break
        }
    }

    private func processUserMessage(_ json: [String: Any], timestamp: Date, uuid: String) async {
        log.info("🟢 processUserMessage: uuid=\(uuid, privacy: .public)")

        // Capture current epoch at the start of async processing
        let epoch = sessionEpoch

        guard let message = json["message"] as? [String: Any] else {
            log.error("🔴 processUserMessage: no message dict for uuid=\(uuid, privacy: .public)")
            return
        }

        let toolUseStdout = (json["toolUseResult"] as? [String: Any])?["stdout"] as? String
        let fallbackToolText = (toolUseStdout?.isEmpty == false) ? toolUseStdout : nil

        if let contentBlocks = message["content"] as? [[String: Any]] {
            let blockTypes = contentBlocks.compactMap { $0["type"] as? String }
            if !blockTypes.isEmpty, blockTypes.allSatisfy({ $0 == "tool_result" }) {
                log.info("🟡 processUserMessage: skipping assistant tool_result relay for uuid=\(uuid, privacy: .public)")
                return
            }
        }

        let text: String
        if let directContent = message["content"] as? String {
            text = directContent
        } else if let contentBlocks = message["content"] as? [[String: Any]] {
            let blockText = contentBlocks.compactMap { block -> String? in
                guard let blockType = block["type"] as? String else { return nil }

                switch blockType {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty { return text }
                    if let text = block["content"] as? String, !text.isEmpty { return text }
                    return nil
                case "tool_result":
                    if let text = block["content"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                default:
                    return nil
                }
            }.first

            if let blockText {
                text = blockText
            } else if let stdout = fallbackToolText {
                // Prefer inline block content when available; fall back to tool output if the array omits it.
                text = stdout
            } else {
                let contentType = type(of: message["content"] as Any)
                log.error("🔴 processUserMessage: no usable content in array for uuid=\(uuid, privacy: .public), content type=\(String(describing: contentType))")
                return
            }
        } else if let stringArray = message["content"] as? [String],
                  let first = stringArray.first(where: { !$0.isEmpty }) {
            text = first
        } else if let stdout = fallbackToolText {
            // Prefer inline block content when available; fall back to tool output if the array omits it.
            text = stdout
        } else {
            let contentType = type(of: message["content"] as Any)
            log.error("🔴 processUserMessage: content not a string for uuid=\(uuid, privacy: .public), content type=\(String(describing: contentType))")
            return
        }

        let isMeta = json["isMeta"] as? Bool ?? false
        log.info("🟢 processUserMessage: text length=\(text.count), isMeta=\(isMeta)")

        // Skip meta messages and command wrappers
        guard !text.isEmpty,
              !(json["isMeta"] as? Bool ?? false),
              !text.contains("<command-name>"),
              !text.contains("<local-command-stdout>") else {
            log.info("🟡 processUserMessage: skipping (empty/meta/command) for uuid=\(uuid, privacy: .public)")
            return
        }

        log.info("🟢 processUserMessage: creating timeline entry for uuid=\(uuid, privacy: .public)")

        let actionHint = shouldUseActionHint(for: text) ? latestAssistantActionHint() : nil
        let summaryResult: FoundationLLM.TimelineSummaryResult
        do {
            summaryResult = try await FoundationLLM.shared.summarizeTimeline(kind: .user, text: text, actionHint: actionHint)
        } catch {
            log.error("🔴 processUserMessage: summarization failed after retries, skipping entry: \(error.localizedDescription, privacy: .public)")
            return
        }
        let detail = text.count > config.previewCharacterLimit
            ? String(text.prefix(config.previewCharacterLimit - 1)) + "…"
            : text

        let entry = TimelineEntry(
            kind: .user,
            timestamp: timestamp,
            summary: summaryResult.summary,
            detail: detail,
            sourceContent: text,
            sourceContext: makeSourceContext(identifier: uuid, line: currentLineNumber),
            sourceIdentifier: uuid,  // Use raw UUID for consistency
            isCompletion: false,
            isDirective: summaryResult.isDirective,
            requestId: nil
        )

        appendEntryIfCurrentEpoch(epoch, entry: entry)

        // Track this directive for correlation with future completions
        if summaryResult.isDirective {
            lastUserDirectiveId = entry.id
            lastUserDirectiveTimestamp = timestamp
            log.info("🟢 processUserMessage: Tracking directive id=\(entry.id) for completion correlation")
        }

        log.info("✅ processUserMessage: Added user entry, summary=\(summaryResult.summary, privacy: .private), total entries=\(self.entries.count)")
    }

    private func processAssistantMessage(_ json: [String: Any], timestamp: Date, uuid: String) async {
        log.info("🟢 processAssistantMessage: uuid=\(uuid, privacy: .public)")

        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            log.error("🔴 processAssistantMessage: no message or content array for uuid=\(uuid, privacy: .public)")
            return
        }

        log.info("🟢 processAssistantMessage: content blocks count=\(content.count)")

        // Process each content block (skip tool invokes, only surface text)
        for (index, block) in content.enumerated() {
            guard let blockType = block["type"] as? String else {
                log.error("🔴 processAssistantMessage: no type in block \(index) for uuid=\(uuid, privacy: .public)")
                continue
            }

            log.info("🟢 processAssistantMessage: block \(index) type=\(blockType, privacy: .public)")

            switch blockType {
            case "text":
                if let text = block["text"] as? String {
                    await addAssistantTextEntry(text: text, timestamp: timestamp, uuid: uuid)
                } else {
                    log.error("🔴 processAssistantMessage: text block has no text field")
                }
            case "tool_use":
                log.info("🟡 processAssistantMessage: skipping tool_use block for uuid=\(uuid, privacy: .public)")
            default:
                log.info("🟡 processAssistantMessage: skipping unknown block type=\(blockType, privacy: .public)")
                break
            }
        }
    }

    private func addAssistantTextEntry(text: String, timestamp: Date, uuid: String) async {
        log.info("🟢 addAssistantTextEntry: text length=\(text.count), uuid=\(uuid, privacy: .public)")

        // Capture current epoch at the start of async processing
        let epoch = sessionEpoch

        // Try to use cache, fall back to direct LLM call on failure
        let rendered: RenderedTimelineEntry
        do {
            // Build message JSON for content hashing (exclude timestamp for stability)
            let messageJSON: [String: Any] = [
                "uuid": uuid,
                "role": "assistant",
                "text": text
            ]

            // Context window: last 2 message UUIDs for better disposition detection
            // Now uses raw transcript UUIDs from sourceIdentifier
            let contextUUIDs = Array(entries.suffix(2).map { $0.sourceIdentifier })

            rendered = try await TimelineCacheOrchestrator.shared.getCachedEntry(
                messageUUID: uuid,
                messageJSON: messageJSON,
                contextWindow: contextUUIDs,
                text: text,
                kind: .assistant
            )
        } catch {
            log.error("🔴 addAssistantTextEntry: Cache lookup failed, falling back to direct LLM: \(error.localizedDescription, privacy: .public)")

            // Fallback to direct LLM call
            let summaryResult: FoundationLLM.TimelineSummaryResult
            do {
                summaryResult = try await FoundationLLM.shared.summarizeTimeline(kind: .assistant, text: text)
            } catch {
                log.error("🔴 addAssistantTextEntry: summarization failed after retries, skipping entry: \(error.localizedDescription, privacy: .public)")
                return
            }

            // Convert to RenderedTimelineEntry format
            let disp = Disposition(rawValue: summaryResult.disposition) ?? .unknown
            rendered = RenderedTimelineEntry(
                summary: summaryResult.summary,
                disposition: disp,
                isCompletion: summaryResult.isCompletion,
                isDirective: summaryResult.isDirective,
                requestId: nil,
                duration: nil
            )
        }

        // Disposition-based filtering to reduce noise
        // TODO: Make this configurable via user settings (see TODOS.md - Timeline Verbosity Settings)
        // Current level: Option 1 (Recommended) - Suppress ack, wip, analysis
        let suppressibleDispositions: Set<Disposition> = [.note, .progress, .analysis]

        if suppressibleDispositions.contains(rendered.disposition) {
            log.info("🟡 addAssistantTextEntry: Suppressing low-value entry (disposition=\(rendered.disposition.rawValue, privacy: .public))")
            return
        }

        // Deduplicate sequential completion entries
        if rendered.isCompletion {
            // Find the last assistant entry
            if let lastAssistantEntry = entries.last(where: { $0.kind == .assistant }), lastAssistantEntry.isCompletion {
                log.info("🟡 addAssistantTextEntry: Suppressing sequential completion entry (previous entry was also completion)")
                return
            }
        }

        let detail = text.count > config.previewCharacterLimit
            ? String(text.prefix(config.previewCharacterLimit - 1)) + "…"
            : text

        // Link completion to the last user directive for duration tracking
        let requestId = rendered.isCompletion ? lastUserDirectiveId : nil

        let entry = TimelineEntry(
            kind: .assistant,
            timestamp: timestamp,
            summary: rendered.summary,
            detail: detail,
            sourceContent: text,
            sourceContext: makeSourceContext(identifier: uuid, line: currentLineNumber),
            sourceIdentifier: uuid,  // Use raw UUID for cache key matching
            isCompletion: rendered.isCompletion,
            isDirective: rendered.isDirective,
            requestId: requestId
        )

        appendEntryIfCurrentEpoch(epoch, entry: entry)
        log.info("✅ addAssistantTextEntry: Added assistant text entry, summary=\(rendered.summary, privacy: .private), completion=\(rendered.isCompletion), uuid=\(uuid, privacy: .public), total entries=\(self.entries.count)")
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
        let entry = TimelineEntry(
            kind: .system,
            summary: summary,
            detail: detail,
            sourceContent: detail,
            sourceContext: makeSourceContext(identifier: "system-start"),
            sourceIdentifier: "system-start"
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
