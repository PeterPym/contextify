import Foundation

enum TimelineEntryKind: String, Codable, Sendable {
    case user
    case assistant
    case system

    var label: String {
        switch self {
        case .user: return "You"
        case .assistant: return "Claude"
        case .system: return "System"
        }
    }
}

enum TimelineEntryAction: Hashable, Sendable {
    case none
    case revealInInventory(transcriptPath: String)
}

struct TimelineEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: TimelineEntryKind
    let timestamp: Date
    let summary: String
    let detail: String
    let sourceContent: String?
    let sourceContext: TimelineSourceContext?
    let sourceIdentifier: String
    let isError: Bool
    let isCompletion: Bool
    let isDirective: Bool
    let requestId: UUID?
    let action: TimelineEntryAction
    let sessionId: String?  // Identifies which session this entry belongs to

    // Hidden cache keys for lightweight refresh (not displayed in UI)
    let contentSha256: String?
    let windowSha256: String?

    init(
        id: UUID = UUID(),
        kind: TimelineEntryKind,
        timestamp: Date = Date(),
        summary: String,
        detail: String,
        sourceContent: String? = nil,
        sourceContext: TimelineSourceContext? = nil,
        sourceIdentifier: String,
        isError: Bool = false,
        isCompletion: Bool = false,
        isDirective: Bool = false,
        requestId: UUID? = nil,
        action: TimelineEntryAction = .none,
        sessionId: String? = nil,
        contentSha256: String? = nil,
        windowSha256: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.summary = summary
        self.detail = detail
        self.sourceContent = sourceContent
        self.sourceContext = sourceContext
        self.sourceIdentifier = sourceIdentifier
        self.isError = isError
        self.isCompletion = isCompletion
        self.isDirective = isDirective
        self.requestId = requestId
        self.action = action
        self.sessionId = sessionId
        self.contentSha256 = contentSha256
        self.windowSha256 = windowSha256
    }
}

struct TimelineSourceContext: Hashable, Sendable {
    enum Provider: String, Sendable {
        case claudeCode = "claude.code"
        case codexCLI = "codex.cli"
        case other

        var icon: String {
            switch self {
            case .claudeCode:
                return "🟠"  // Placeholder - replace with "claude-code-icon" when asset is added
            case .codexCLI:
                return "🌀"  // Placeholder - replace with "codex-icon" when asset is added
            case .other:
                return "🔄"  // Placeholder - could use "ai.sparkles" SF Symbol
            }
        }

        /// Returns the asset name or SF Symbol name for the provider icon
        var iconImage: String {
            switch self {
            case .claudeCode:
                return "claude-code-icon"  // Custom asset (orange asterisk)
            case .codexCLI:
                return "codex-icon"  // Custom asset (blue swirly brackets)
            case .other:
                return "sparkles"  // SF Symbol fallback
            }
        }

        nonisolated var displayName: String {
            switch self {
            case .claudeCode:
                return "Claude Code"
            case .codexCLI:
                return "Codex CLI"
            case .other:
                return "AI Source"
            }
        }
    }

    let provider: Provider
    let identifier: String
    let filePath: String?
    let line: Int?
    let column: Int?

    init(provider: Provider, identifier: String, filePath: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.provider = provider
        self.identifier = identifier
        self.filePath = filePath
        self.line = line
        self.column = column
    }

    var formattedReference: String {
        if let filePath, let line {
            if let column {
                return "[\(filePath)]\(line):\(column)"
            }
            return "[\(filePath)]\(line)"
        }

        if let filePath {
            return "[\(filePath)]"
        }

        return "[\(provider.rawValue)]\(identifier)"
    }
}

extension TimelineEntry {
    func markdownPayload() -> String {
        let logText = detail
        let sourceText = sourceContent ?? detail
        let reference = sourceContext?.formattedReference ?? sourceIdentifier

        return "\(logText)\n---\n\(sourceText)\n---\n\(reference)"
    }

    /// Create a copy with modified fields
    func copyWith(
        summary: String? = nil,
        sessionId: String? = nil,
        action: TimelineEntryAction? = nil
    ) -> TimelineEntry {
        TimelineEntry(
            id: id,
            kind: kind,
            timestamp: timestamp,
            summary: summary ?? self.summary,
            detail: detail,
            sourceContent: sourceContent,
            sourceContext: sourceContext,
            sourceIdentifier: sourceIdentifier,
            isError: isError,
            isCompletion: isCompletion,
            isDirective: isDirective,
            requestId: requestId,
            action: action ?? self.action,
            sessionId: sessionId ?? self.sessionId,
            contentSha256: contentSha256,
            windowSha256: windowSha256
        )
    }
}

struct ConversationExchange: Sendable {
    let index: Int
    let identifier: String
    let user: String?
    let assistant: String?
    let system: String?
    let capturedAt: Date
    let isError: Bool

    init(index: Int, user: String?, assistant: String?, system: String?, capturedAt: Date, isError: Bool = false) {
        self.index = index
        self.user = user
        self.assistant = assistant
        self.system = system
        self.capturedAt = capturedAt
        self.isError = isError

        // Create content-based identifier using hash of user text (more stable than sequence)
        if let userText = user?.trimmingCharacters(in: .whitespacesAndNewlines), !userText.isEmpty {
            self.identifier = "exchange-\(abs(userText.hashValue))"
        } else if let systemText = system?.trimmingCharacters(in: .whitespacesAndNewlines), !systemText.isEmpty {
            self.identifier = "exchange-system-\(abs(systemText.hashValue))"
        } else {
            self.identifier = "exchange-\(index)"
        }
    }
}

struct MonitorConfig: Sendable {
    var pollInterval: TimeInterval = 10
    var maxEntries: Int = 50
    var timelineMaxEntriesPerSession: Int = 800  // Per-session retention limit
    var previewCharacterLimit: Int = 1400
    var userSummaryPrefix = "You"
    var assistantSummaryPrefix = "Claude"
}

enum TimelineRefreshTrigger: Sendable {
    case automatic
    case manualHotkey
    case hudSend
}
