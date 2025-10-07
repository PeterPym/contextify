import Foundation
import Observation
import OSLog
import ContextifyCore

@Observable
@MainActor
final class ConversationMonitor {
    static let shared = ConversationMonitor()

    private let log = Logger(subsystem: "dev.contextify", category: "Timeline")
    private let config = MonitorConfig()
    private let conversationResolver = ActiveConversationResolver(providers: [ClaudeTranscriptProvider()])

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
    @ObservationIgnored private var seenMessageUUIDs: Set<String> = []
    @ObservationIgnored private var didEmitSessionStart = false
    @ObservationIgnored private var currentConversationFile: URL?
    @ObservationIgnored private var activeSession: TranscriptSession?
    @ObservationIgnored private var conversationResolverTask: Task<Void, Never>?

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
        ensureSessionStartEntry()
    }

    func requestImmediateRefresh(trigger: TimelineRefreshTrigger) {
        Task {
            await processConversationFile()
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
            lastError = "No project root set"
            log.error("Timeline: No project root URL available from HUDViewModel")
            return
        }

        let projectPath = projectURL.path
        log.info("Timeline: Resolving conversation for project: \(projectPath, privacy: .public)")

        guard let session = conversationResolver.resolveActiveSession(for: projectPath) else {
            if activeSession != nil {
                log.info("No active conversation sessions found; tearing down watcher")
                tearDownFileWatcher()
            }
            activeSession = nil
            currentConversationFile = nil
            lastError = "No conversation file found for this project"
            log.error("Timeline: No session found for project path: \(projectPath, privacy: .public)")
            return
        }

        log.info("Timeline: Found session at \(session.fileURL.path, privacy: .public)")

        if !force, let current = activeSession, current.fileURL == session.fileURL {
            activeSession = session
            return
        }

        await switchToSession(session, reason: force ? .initial : .providerChange)
    }

    private enum SessionSwitchReason {
        case initial
        case providerChange
    }

    private func switchToSession(_ session: TranscriptSession, reason: SessionSwitchReason) async {
        tearDownFileWatcher()

        activeSession = session
        currentConversationFile = session.fileURL
        lastProcessedLine = 0
        seenMessageUUIDs.removeAll()
        lastError = nil

        configureFileWatcher(for: session.fileURL)

        if reason == .initial {
            ensureSessionStartEntry()
        } else if reason == .providerChange {
            emitProviderSwitchEntry(for: session)
        }

        await processConversationFile()
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
            sourceIdentifier: "provider-switch-\(session.identifier)"
        )

        entries.append(entry)
        if entries.count > config.maxEntries {
            entries = Array(entries.suffix(config.maxEntries))
        }
    }

    private func startConversationResolverLoop() {
        conversationResolverTask?.cancel()
        conversationResolverTask = Task { [weak self] in
            guard let self else { return }
            let interval = await MainActor.run { self.config.pollInterval }
            let delay = UInt64(max(interval, 1) * 1_000_000_000)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay)
                await self.refreshActiveConversation()
            }
        }
    }

    private func makeSourceContext(identifier: String) -> TimelineSourceContext {
        let provider = activeSession?.provider ?? .other
        let filePath = activeSession?.fileURL.path
        return TimelineSourceContext(provider: provider, identifier: identifier, filePath: filePath)
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
            if lastProcessedLine == 0 {
                // Initial load: Check if timeline is effectively empty (only system messages)
                let hasNonSystemMessages = entries.contains { $0.kind != .system }

                if !hasNonSystemMessages {
                    // Timeline is empty, only process last 5 entries to avoid overwhelming the timeline
                    let startIndex = max(0, lines.count - 5)
                    newLines = lines[startIndex...]
                    log.info("🟢 processConversationFile: Initial load (empty timeline), processing last \(newLines.count) entries from \(lines.count) total")
                } else {
                    // Timeline already has content, don't backfill old messages
                    newLines = []
                    log.info("🟢 processConversationFile: Initial load (existing timeline), skipping backfill")
                }
                lastProcessedLine = lines.count
            } else {
                // Incremental update: process all new lines
                newLines = lines[lastProcessedLine...]
                lastProcessedLine = lines.count
                log.info("🟢 processConversationFile: Incremental update, processing \(newLines.count) new lines")
            }

            var processedCount = 0
            var skippedCount = 0

            for line in newLines {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    skippedCount += 1
                    continue
                }

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

        let summary = await FoundationLLM.shared.summarizeTimeline(kind: .user, text: text)
        let detail = text.count > config.previewCharacterLimit
            ? String(text.prefix(config.previewCharacterLimit - 1)) + "…"
            : text

        let entry = TimelineEntry(
            kind: .user,
            timestamp: timestamp,
            summary: summary,
            detail: detail,
            sourceContent: text,
            sourceContext: makeSourceContext(identifier: uuid),
            sourceIdentifier: "msg-\(uuid)"
        )

        entries.append(entry)

        if entries.count > config.maxEntries {
            entries = Array(entries.suffix(config.maxEntries))
        }

        log.info("✅ processUserMessage: Added user entry, summary=\(summary, privacy: .public), total entries=\(self.entries.count)")
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

        let summary = await FoundationLLM.shared.summarizeTimeline(kind: .assistant, text: text)
        let detail = text.count > config.previewCharacterLimit
            ? String(text.prefix(config.previewCharacterLimit - 1)) + "…"
            : text

        let entry = TimelineEntry(
            kind: .assistant,
            timestamp: timestamp,
            summary: summary,
            detail: detail,
            sourceContent: text,
            sourceContext: makeSourceContext(identifier: uuid),
            sourceIdentifier: "msg-\(uuid)-text"
        )

        entries.append(entry)
        log.info("✅ addAssistantTextEntry: Added assistant text entry, summary=\(summary, privacy: .public), total entries=\(self.entries.count)")
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
