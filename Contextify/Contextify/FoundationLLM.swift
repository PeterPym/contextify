import Foundation
import OSLog
import CryptoKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Typed error model for timeline generation with user-facing messages
enum TimelineError: Swift.Error {
    case llmTimeout
    case contextOverflow(tokens: Int, limit: Int)
    case guardrailViolation(reason: String)
    case decodingFailure(reason: String)
    case databaseError(String)
    case unexpected(String)
    case cancelled
    case llmUnavailable(reason: String)
    case validationFailure(reason: String)

    var isRetryable: Bool {
        switch self {
        case .llmTimeout, .databaseError, .unexpected: return true
        case .contextOverflow, .guardrailViolation, .decodingFailure, .cancelled, .llmUnavailable, .validationFailure: return false
        }
    }

    var userMessage: String {
        switch self {
        case .llmTimeout:
            return "Summary generation timed out. Please try again."
        case .contextOverflow(let tokens, let limit):
            return "Message too long (\(tokens) tokens, limit \(limit))."
        case .guardrailViolation(let reason):
            return "Content could not be summarized due to safety filters: \(reason)"
        case .decodingFailure(let reason):
            return "Summary format was invalid: \(reason)"
        case .databaseError(let msg):
            return "A database error occurred: \(msg)"
        case .unexpected(let msg):
            return "An unexpected error occurred: \(msg)"
        case .cancelled:
            return "Operation was cancelled."
        case .llmUnavailable(let reason):
            return "\(reason) This typically recovers after a minute or two. If it happens frequently or persists, consider contacting support via Help menu."
        case .validationFailure(let reason):
            return "Summary validation failed: \(reason)"
        }
    }
}

// SHA256 hex helper
extension Digest {
    nonisolated var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
    nonisolated func hexPrefix(_ length: Int) -> String {
        String(hexString.prefix(length))
    }
}

actor FoundationLLM {
    // Actor-isolated controller cache with idle eviction
    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private struct ControllerEntry {
        var controller: SessionController
        var lastUsed: Date
    }

    // Note: Type-erased storage allows actor to exist on all OS versions
    // ControllerEntry is @available(macOS 26.0+) so we must use Any? for the stored property
    private var _controllers: Any?

    @available(macOS 26.0, *)
    private var controllers: [String: ControllerEntry] {
        get {
            if let dict = _controllers as? [String: ControllerEntry] {
                return dict
            }
            let empty: [String: ControllerEntry] = [:]
            _controllers = empty
            return empty
        }
        set {
            _controllers = newValue
        }
    }
    #endif

    /// Helper to parse token overflow info from error context with targeted regex
    private static func parseOverflow(from s: String) -> (tokens: Int, limit: Int)? {
        // Example: "Content contains 4360-4369 tokens, which exceeds the maximum allowed context size of 4096."
        let pattern = #"contains\s+(\d+)(?:-\d+)?\s+tokens.*?maximum.*?(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else {
            return nil
        }
        func extractInt(_ index: Int) -> Int {
            let range = match.range(at: index)
            let substring = (s as NSString).substring(with: range)
            return Int(substring) ?? 0
        }
        return (extractInt(1), extractInt(2))
    }

    /// Timeout wrapper for LLM respond calls is handled internally by LanguageModelSession
    /// Additional timeout handling can be added per request as needed

    /// Reset session for a specific entry kind and provider (replaces resetTimelineSummarizerSession)
    @available(macOS 26.0, *)
    func resetSession(kind: TimelineEntryKind, provider: TimelineSourceContext.Provider? = nil) async {
        #if canImport(FoundationModels)
        let key = instructionsForTimeline(kind: kind, provider: provider)
        if let entry = controllers[key] {
            await entry.controller.reset()
            controllers[key] = nil
        }
        #endif
    }

    /// Set forceStateless mode at runtime (overrides environment variable)
    /// When changed, all existing controllers are cleared to apply new setting
    @available(macOS 26.0, *)
    func setForceStateless(_ enabled: Bool) async {
        #if canImport(FoundationModels)
        forceStatelessMode = enabled
        // Proactively reset existing sessions to apply new policy immediately
        let count = controllers.count
        for (_, entry) in controllers {
            await entry.controller.reset()
        }
        controllers.removeAll()
        log.info("ForceStateless=\(enabled); reset \(count) sessions and cleared cache")
        #endif
    }

    /// Legacy method - use resetSession(kind:provider:) instead
    @available(macOS 26.0, *)
    @available(*, deprecated, renamed: "resetSession(kind:provider:)")
    func resetTimelineSummarizerSession() async {
        await resetSession(kind: .assistant, provider: nil)
    }

    static let shared = FoundationLLM()

    private let log = Logger(subsystem: "dev.contextify", category: "FoundationLLM")
    private var requestCount = 0  // Request numbering for logging
    private var lastRequestTime: Date?

    // Telemetry-only metrics (not used for operational decisions)
    private var metrics = (total: 0, failed: 0)

    // Throttle to prevent overwhelming the LLM
    private let minRequestInterval: TimeInterval = 0.15 // 150ms between requests

    // Runtime-configurable forceStateless mode (set via CONTEXTIFY_FORCE_STATELESS_LLM=1 or setForceStateless)
    private var forceStatelessMode: Bool = {
        ProcessInfo.processInfo.environment["CONTEXTIFY_FORCE_STATELESS_LLM"] == "1"
    }()

    /// Hard timeout guard for LLM respond calls (prevents indefinite hangs)
    private func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimelineError.llmTimeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    enum Error: Swift.Error {
        case unavailable
        case unexpectedEnvironment
        case retryExhausted
    }

    // Final timeline result struct - intentionally lighter than GuidedTimelineSummary
    // Design decision: grounding and confidence are LLM generation metadata,
    // not persisted in the final timeline entry. They're logged but not stored.
    // This keeps the result focused on user-facing timeline data.
    struct TimelineSummaryResult: Sendable {
        let summary: String
        let isCompletion: Bool
        let isDirective: Bool
        let disposition: String
    }

    struct TimelineSummaryWithForms: Sendable {
        let presentForm: String
        let pastForm: String
        let disposition: Disposition
        let verbLemma: String?
        let isDirective: Bool
        let isCompletion: Bool
    }

    enum UserIntent: String {
        case directive
        case question
        case report
        case affirmative
        case negative
        case unknown
    }

    /// Strip quoted content, code blocks, and blockquotes from user message
    /// Uses line-wise scanning to avoid regex catastrophic backtracking
    func stripQuotedAndCode(_ text: String) -> String {
        var result = text

        // Fast path: if no markers present, skip expensive processing
        if !result.contains("```") && !result.contains("\"\"\"") && !result.contains(">") && !result.contains("`") && !result.contains("<bash-") && !result.contains("<command-") && !result.contains("<system-") && !result.contains("Caveat:") {
            return collapseWhitespace(result)
        }

        // Remove "Caveat:" meta-messages (Claude Code wrapper messages)
        // These are informational wrappers that should not be summarized
        if result.hasPrefix("Caveat:") {
            return "[meta message]"
        }

        // Remove bash output tags (Claude Code format) - these contain verbose system output
        // Pattern: <bash-stdout>...</bash-stdout>, <bash-stderr>...</bash-stderr>, <bash-input>...</bash-input>
        // Note: Use capture group and backreference to ensure tags match; (?s) makes . match newlines
        result = result.replacingOccurrences(
            of: #"(?s)<bash-(stdout|stderr|input)>.*?</bash-\1>"#,
            with: "[system output]",
            options: .regularExpression
        )

        // Remove command tags (slash command format)
        // Pattern: <command-name>...</command-name>, <command-message>...</command-message>
        result = result.replacingOccurrences(
            of: #"(?s)<command-(name|message)>.*?</command-\1>"#,
            with: "",
            options: .regularExpression
        )

        // Remove system reminder tags (injected by Claude Code)
        result = result.replacingOccurrences(
            of: #"(?s)<system-reminder>.*?</system-reminder>"#,
            with: "",
            options: .regularExpression
        )

        var lines: [String] = []
        var inCodeBlock = false

        // Line-wise scan for code fences and blockquotes (avoids backtracking)
        for line in result.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)

            // Toggle code block state on fence markers
            if lineStr.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }

            // Skip lines inside code blocks
            if inCodeBlock {
                continue
            }

            // Skip blockquote lines (starting with >)
            if lineStr.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                continue
            }

            lines.append(lineStr)
        }

        result = lines.joined(separator: "\n")

        // Remove inline code (`...`) with non-greedy regex
        result = result.replacingOccurrences(
            of: #"`[^`]*?`"#,
            with: "",
            options: .regularExpression
        )

        // Remove triple-quoted strings ("""...""") handling same-line open/close correctly
        var cleanedLines: [String] = []
        var inTripleQuote = false
        for line in result.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            let tripleQuoteCount = lineStr.components(separatedBy: "\"\"\"").count - 1

            if tripleQuoteCount == 0 {
                // No triple-quotes on this line
                if !inTripleQuote {
                    cleanedLines.append(lineStr)
                }
                continue
            }

            if tripleQuoteCount % 2 == 0 {
                // Even number: contains both open and close on same line (e.g., """inline""")
                // Drop the entire line
                continue
            } else {
                // Odd number: toggle state
                inTripleQuote.toggle()
                // Drop this line (it's part of the triple-quote boundary)
                continue
            }
        }

        result = cleanedLines.joined(separator: "\n")

        return collapseWhitespace(result)
    }

    /// Authoritatively classify user intent using deterministic rules
    func classifyUserIntent(_ text: String) -> UserIntent {
        let clean = stripQuotedAndCode(text)
        let normalized = Self.normalizeForIntent(clean)

        // Gate for short utterances (affirmative/negative) - allow up to 5 token confirmations
        // Strip punctuation from tokens to handle "yes," "ok." etc.
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: separators) }
            .filter { !$0.isEmpty }

        if tokens.count <= 5 {
            let affirmatives = ["yes", "y", "ok", "okay", "sure", "👍", "yep", "yup", "go", "ahead", "proceed", "do", "it", "please", "sgtm", "roger", "affirmative", "yeah", "yah"]
            let allAffirmative = tokens.allSatisfy { affirmatives.contains($0) }
            if allAffirmative { return .affirmative }

            let negatives = [
                // Direct negations
                "no", "nope", "nah", "not", "don't",

                // Cancellations
                "cancel", "abort", "stop", "nevermind", "never", "mind",

                // Deferrals
                "hold", "off", "pause", "wait", "skip", "later",

                // Returns/backs
                "back", "return",

                // Time-based (for patterns like "not now")
                "now"
            ]
            let allNegative = tokens.allSatisfy { negatives.contains($0) }
            if allNegative { return .negative }
        }

        // Check for problem reports / negative feedback (treat as implicit directives to fix)
        // Using prebuilt alternation pattern for performance
        if Self.matchesProblemIndicators(normalized) { return .directive }

        // Observation patterns (only when followed by negative/problem context)
        if (normalized.hasPrefix("seems ") && !normalized.contains(" good") && !normalized.contains(" fine") && !normalized.contains(" correct")) ||
           (normalized.hasPrefix("appears ") && !normalized.contains(" good") && !normalized.contains(" fine") && !normalized.contains(" correct")) {
            return .directive
        }

        // Observation interjections (informal problem reports)
        if normalized.hasPrefix("hm.") || normalized.hasPrefix("hmm") {
            return .directive
        }

        // Check for directive patterns (request phrases)
        // NOTE: Keep in sync with directiveLexicon (used by isDirective() post-LLM).
        // These two could be unified in a future refactor.
        let directivePatterns = [
            "can you", "could you", "would you", "please", "see if you can",
            "help me", "let's", "we should", "we need to", "we could",
            "i need", "go ahead", "proceed", "continue", "figure out"
        ]
        for pattern in directivePatterns {
            if Self.containsPhrase(normalized, phrase: pattern) { return .directive }
        }

        // Separate "i want to know" (question) from general "i want" (directive)
        if Self.containsPhrase(normalized, phrase: "i want to know") { return .question }
        if Self.containsPhrase(normalized, phrase: "i want") { return .directive }

        // Check for imperative verbs at start (allow productive prefixes like "reinvestigate")
        let firstWord = tokens.first ?? ""
        let imperatives: Set<String> = [
            "commit", "fix", "run", "update", "add", "create", "test", "build", "deploy",
            "write", "explain", "show", "make", "delete", "remove", "check", "refactor",
            "optimize", "implement", "modify", "debug", "install", "configure", "look",
            "read", "investigate", "try", "revert", "verify", "analyze", "review",
            "list", "describe", "summarize", "compare", "find", "search", "identify",
            "determine", "examine", "inspect", "explore", "document", "outline"
        ]
        if Self.isImperativeLike(firstWord, baseVerbs: imperatives) { return .directive }

        // Check for question patterns
        let questionWords = ["what", "why", "how", "when", "where", "which", "who"]
        if Self.startsWithAny(normalized, prefixes: questionWords) { return .question }
        if normalized.hasSuffix("?") { return .question }

        // Additional question patterns (questions without traditional question words)
        if normalized.hasPrefix("is there") || normalized.hasPrefix("is that") ||
           normalized.hasPrefix("are those") || normalized.hasPrefix("are there") ||
           normalized.hasPrefix("do you") || normalized.hasPrefix("does it") ||
           normalized.hasPrefix("can we") || normalized.hasPrefix("should we") {
            return .question
        }

        // Check for past-tense self-reports
        let reportPatterns = ["i updated", "i fixed", "i created", "i modified", "i changed", "i added"]
        for pattern in reportPatterns {
            if Self.containsPhrase(normalized, phrase: pattern) { return .report }
        }

        // Informal statements (treat as implicit directives)
        // Be specific to avoid false positives like "we're working on" (report) vs "we don't need" (directive)
        if normalized.hasPrefix("its just ") || normalized.hasPrefix("it's just ") ||
           normalized.hasPrefix("its strange ") || normalized.hasPrefix("it's strange ") ||
           normalized.hasPrefix("we don't ") || normalized.hasPrefix("we need ") || normalized.hasPrefix("we should ") ||
           normalized.hasPrefix("there are no ") || normalized.hasPrefix("there is no ") ||
           normalized.hasPrefix("i'm not seeing") || normalized.hasPrefix("i'm not ") ||
           normalized.hasPrefix("i think we ") {
            return .directive
        }

        // Default to unknown
        return .unknown
    }

    /// Public entry point with structured retry logic
    func summarizeTimeline(
        kind: TimelineEntryKind,
        text: String,
        provider: TimelineSourceContext.Provider? = nil,
        actionHint: String? = nil
    ) async throws -> TimelineSummaryResult {
        guard #available(macOS 26.0, *) else {
            throw TimelineError.llmUnavailable(reason: "FoundationModels requires macOS 26.0+")
        }

        let maxRetries = 3
        var attempt = 0
        var backoffNs: UInt64 = 500_000_000 // 0.5s

        while true {
            do {
                return try await summarizeTimelineOnce(
                    kind: kind,
                    text: text,
                    provider: provider,
                    actionHint: actionHint,
                    attempt: attempt
                )
            } catch let err as TimelineError {
                guard err.isRetryable, attempt < maxRetries else {
                    throw err
                }

                attempt += 1
                log.warning("Retryable error on attempt \(attempt): \(err.userMessage)")

                // IMPORTANT: reset session before retry to prevent context accumulation
                await resetSession(kind: kind, provider: provider)
                log.info("Reset session before retry \(attempt)")

                // Exponential backoff with jitter
                let jitter = UInt64(Int.random(in: 0...(200_000_000)))
                try await Task.sleep(nanoseconds: backoffNs + jitter)
                backoffNs = min(backoffNs * 2, 4_000_000_000) // cap at 4s
            }
        }
    }

    /// Internal implementation (single attempt, no retry)
    private func summarizeTimelineOnce(
        kind: TimelineEntryKind,
        text: String,
        provider: TimelineSourceContext.Provider? = nil,
        actionHint: String? = nil,
        attempt: Int = 0
    ) async throws -> TimelineSummaryResult {
        let message = collapseWhitespace(text)

        // Throttle requests to prevent overwhelming the LLM
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minRequestInterval {
                let delay = minRequestInterval - elapsed
                log.debug("Throttling: sleeping \(Int(delay * 1000))ms before next request")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        lastRequestTime = Date()

        requestCount += 1
        let reqNum = requestCount

        guard !message.isEmpty else {
            log.info("[\(reqNum)] timeline: empty message, using fallback")
            return fallbackSummary(kind: kind, text: text)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                if attempt == 0 {
                    log.debug("[\(reqNum)] timeline: SystemLanguageModel available")
                }
                break
            case .unavailable:
                log.warning("[\(reqNum)] timeline: SystemLanguageModel unavailable")
                throw Error.unavailable
            @unknown default:
                log.warning("[\(reqNum)] timeline: SystemLanguageModel unknown availability")
                throw Error.unavailable
            }

            // Fast paths to skip LLM call (all routed through postProcess for validation)
            let assistantName = provider?.displayName ?? "Claude Code"
            if kind == .assistant, isAck(message) {
                log.debug("[\(reqNum)] timeline: ack detected, using fast path")
                let fp = GuidedTimelineSummary(
                    summary: "\(assistantName) acknowledges the request.",
                    isCompletion: false,
                    disposition: "ack",
                    grounding: "grounded",
                    confidence: 0.95
                )
                var result = try postProcess(kind: kind, payload: fp, message: message, provider: provider)
                result = TimelineSummaryResult(summary: result.summary, isCompletion: result.isCompletion, isDirective: false, disposition: "ack")
                return result
            } else if kind == .assistant, message == "[Request interrupted by user]" {
                log.debug("[\(reqNum)] timeline: interruption detected, using fast path")
                let fp = GuidedTimelineSummary(
                    summary: "You interrupted \(assistantName).",
                    isCompletion: false,
                    disposition: "interrupted",
                    grounding: "grounded",
                    confidence: 0.95
                )
                var result = try postProcess(kind: kind, payload: fp, message: message, provider: provider)
                result = TimelineSummaryResult(summary: result.summary, isCompletion: false, isDirective: false, disposition: "interrupted")
                return result
            } else if kind == .user {
                // Fast path for slash commands (before intent classification)
                if let commandSummary = detectSlashCommand(message, assistantName: assistantName) {
                    log.debug("[\(reqNum)] timeline: slash command detected, using fast path")
                    let fp = GuidedTimelineSummary(
                        summary: commandSummary,
                        isCompletion: false,
                        disposition: "command",
                        grounding: "grounded",
                        confidence: 0.95
                    )
                    var result = try postProcess(kind: kind, payload: fp, message: message, provider: provider)
                    result = TimelineSummaryResult(summary: result.summary, isCompletion: false, isDirective: true, disposition: "command")
                    return result
                }

                let intent = classifyUserIntent(message)

                // Fast path for affirmative/negative
                if intent == .affirmative {
                    log.debug("[\(reqNum)] timeline: affirmative detected, using fast path")
                    let fp = GuidedTimelineSummary(
                        summary: "You requested \(assistantName) to proceed as proposed.",
                        isCompletion: false,
                        disposition: "affirmative",
                        grounding: "grounded",
                        confidence: 0.95
                    )
                    var result = try postProcess(kind: kind, payload: fp, message: message, provider: provider)
                    result = TimelineSummaryResult(summary: result.summary, isCompletion: result.isCompletion, isDirective: true, disposition: "affirmative")
                    return result
                } else if intent == .negative {
                    log.debug("[\(reqNum)] timeline: negative detected, using fast path")
                    let fp = GuidedTimelineSummary(
                        summary: "You requested \(assistantName) not to proceed.",
                        isCompletion: false,
                        disposition: "negative",
                        grounding: "grounded",
                        confidence: 0.95
                    )
                    var result = try postProcess(kind: kind, payload: fp, message: message, provider: provider)
                    result = TimelineSummaryResult(summary: result.summary, isCompletion: result.isCompletion, isDirective: true, disposition: "negative")
                    return result
                }
            }

            let instructions = instructionsForTimeline(kind: kind, provider: provider)

            // Fetch per-instructions controller (single-flight per session)
            let controller = await getController(for: instructions)

            // Use slight temperature on retries to help unstick from bad states
            let temperature = attempt > 0 ? 0.1 : 0.0
            let options = GenerationOptions(
                sampling: .greedy,
                temperature: temperature,
                maximumResponseTokens: 150  // Need space for JSON structure + 140 char summary
            )

            let clamped = String(message.prefix(1200))

            // Preprocess and classify for user messages
            let intent: UserIntent?
            let cleanMessage: String
            if kind == .user {
                intent = classifyUserIntent(clamped)
                cleanMessage = stripQuotedAndCode(clamped)
            } else {
                intent = nil
                cleanMessage = clamped
            }

            let payloadInput: String
            if kind == .user {
                let intentStr = intent?.rawValue.uppercased() ?? "UNKNOWN"
                if let hint = actionHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
                    let safeHint = String(hint.prefix(300))
                    payloadInput = "MESSAGE:\n<<<\(cleanMessage)>>>\nDETECTED_INTENT: \(intentStr)\nACTION_HINT:\n<<<\(safeHint)>>>"
                } else {
                    payloadInput = "MESSAGE:\n<<<\(cleanMessage)>>>\nDETECTED_INTENT: \(intentStr)"
                }
            } else {
                payloadInput = "MESSAGE:\n<<<\(cleanMessage)>>>"
            }

            do {
                if attempt == 0 {
                    log.debug("[\(reqNum)] timeline: requesting LLM summary (attempt \(attempt + 1))")
                } else {
                    log.warning("[\(reqNum)] timeline: requesting LLM summary (retry \(attempt))")
                }
                log.debug("[\(reqNum)] input: \(payloadInput, privacy: .public)")

                let payload: GuidedTimelineSummary = try await withTimeout(30) {
                    try await controller.generate(
                        payloadInput,
                        generating: GuidedTimelineSummary.self,
                        includeSchema: true,
                        options: options
                    )
                }
                log.debug("[\(reqNum)] timeline: LLM SUCCESS - grounding=\(payload.grounding), confidence=\(String(format: "%.2f", payload.confidence)), disposition=\(payload.disposition), isCompletion=\(payload.isCompletion)")
                log.debug("[\(reqNum)] timeline: raw summary from LLM: '\(payload.summary, privacy: .public)'")
                do {
                    var result = try postProcess(kind: kind, payload: payload, message: clamped, provider: provider)

                    // Detect directive and fix disposition if LLM missed it
                    if kind == .user, isDirective(message) {
                        // Override disposition to "directive" if LLM returned "unknown" or other non-directive value
                        let correctedDisposition = (result.disposition == "unknown" || !["directive", "affirmative", "negative"].contains(result.disposition)) ? "directive" : result.disposition
                        result = TimelineSummaryResult(summary: result.summary, isCompletion: false, isDirective: true, disposition: correctedDisposition)
                        log.debug("[\(reqNum)] timeline: user directive detected, disposition=\(correctedDisposition)")
                    }

                    log.debug("[\(reqNum)] timeline: FINAL summary after postProcess: '\(result.summary, privacy: .public)'")
                    // Record success
                    metrics.total += 1
                    return result
                } catch let validationError as TimelineError {
                    // postProcess rejected with TimelineError (e.g., validationFailure) - don't retry
                    metrics.total += 1
                    metrics.failed += 1
                    log.error("[\(reqNum)] postProcess rejection - propagating failure without retry: \(validationError.userMessage)")
                    throw validationError
                } catch {
                    // Other postProcess errors - convert to validation failure
                    metrics.total += 1
                    metrics.failed += 1
                    log.error("[\(reqNum)] postProcess unexpected error: \(error)")
                    throw TimelineError.validationFailure(reason: error.localizedDescription)
                }
            } catch let validationError as TimelineError where validationError.isRetryable == false {
                // Non-retryable TimelineError from postProcess - just propagate
                throw validationError
            } catch let guarded as LanguageModelSession.GenerationError {
                // Map FoundationModels errors to TimelineError
                switch guarded {
                case .exceededContextWindowSize(let context):
                    metrics.total += 1
                    metrics.failed += 1
                    log.error("[\(reqNum)] context overflow: \(String(describing: guarded), privacy: .public)")
                    let info = Self.parseOverflow(from: context.debugDescription) ?? (tokens: 4097, limit: 4096)
                    await controller.reset()
                    throw TimelineError.contextOverflow(tokens: info.tokens, limit: info.limit)

                case .guardrailViolation(let context):
                    // Don't count as failure - handled gracefully by TimelineCacheMissGenerator
                    metrics.total += 1
                    log.info("[\(reqNum)] Apple Intelligence filtered content (guardrail triggered)")
                    await controller.reset()
                    throw TimelineError.guardrailViolation(reason: context.debugDescription)

                case .decodingFailure(let context):
                    metrics.total += 1
                    metrics.failed += 1
                    log.error("[\(reqNum)] DECODING FAILURE: \(context.debugDescription, privacy: .public)")
                    log.error("[\(reqNum)] We sent this input: \(payloadInput, privacy: .public)")
                    log.error("[\(reqNum)] Expected schema: {summary: String, isCompletion: Bool, disposition: String, grounding: String, confidence: Double}")

                    // Try to get raw response for debugging (makes second LLM call but only on failure)
                    do {
                        let raw: String = try await withTimeout(15) {
                            try await controller.raw(payloadInput, options: options)
                        }
                        log.error("[\(reqNum)] LLM actually returned (raw): \(raw, privacy: .public)")
                    } catch {
                        log.error("[\(reqNum)] Could not fetch raw response: \(error.localizedDescription, privacy: .public)")
                    }

                    await controller.reset()
                    throw TimelineError.decodingFailure(reason: context.debugDescription)

                default:
                    metrics.total += 1
                    metrics.failed += 1
                    log.error("[\(reqNum)] Other generation error: \(String(describing: guarded), privacy: .public)")
                    await controller.reset()
                    throw TimelineError.decodingFailure(reason: "\(guarded)")
                }
            } catch is CancellationError {
                throw TimelineError.cancelled
            } catch let tErr as TimelineError {
                throw tErr
            } catch {
                log.error("[\(reqNum)] timeline summarize unexpected error: \(error.localizedDescription, privacy: .public)")
                throw TimelineError.unexpected(error.localizedDescription)
            }
        }
        #endif

        log.error("[\(reqNum)] timeline: FoundationModels not available (macOS < 26)")
        throw Error.unexpectedEnvironment
    }

    func fallbackSummary(kind: TimelineEntryKind, text: String, provider: TimelineSourceContext.Provider? = nil) -> TimelineSummaryResult {
        let summary = sanitize(fallback(for: kind, text: text, provider: provider), kind: kind, provider: provider)
        return TimelineSummaryResult(summary: summary, isCompletion: false, isDirective: false, disposition: "unknown")
    }

    /// Generate dual-form (present + past) timeline summary for cache storage
    func summarizeTimelineWithForms(
        kind: TimelineEntryKind,
        text: String,
        provider: TimelineSourceContext.Provider? = nil,
        contextWindow: [String] = []
    ) async throws -> TimelineSummaryWithForms {
        guard #available(macOS 26.0, *) else {
            throw TimelineError.llmUnavailable(reason: "FoundationModels requires macOS 26.0+")
        }

        // Call existing LLM summarization
        let result = try await summarizeTimeline(kind: kind, text: text, provider: provider)

        // Parse disposition string to enum
        let disp = Disposition(rawValue: result.disposition) ?? .unknown

        // For now, use simple transformation to generate both forms
        // TODO: Phase 2 will have LLM generate both forms natively
        let present = result.summary
        let past = convertToPastTense(result.summary, disposition: disp, provider: provider)

        return TimelineSummaryWithForms(
            presentForm: present,
            pastForm: past,
            disposition: disp,
            verbLemma: nil,  // TODO: LLM should provide this in Phase 2
            isDirective: result.isDirective,
            isCompletion: result.isCompletion
        )
    }

    /// Simple fallback for converting present tense to past tense
    /// This is temporary until Phase 2 when LLM generates both forms
    /// Guards against code blocks and unsafe transformations
    private func convertToPastTense(_ text: String, disposition: Disposition, provider: TimelineSourceContext.Provider? = nil) -> String {
        // If already past tense (completion), return as-is
        if disposition == .completion {
            return text
        }

        // Guard: Don't transform if text contains code blocks or inline code
        if text.contains("```") || text.contains("`") {
            return text
        }

        // Guard: Don't transform if text contains colons (likely code/paths)
        if text.contains(":") {
            return text
        }

        // Use anchored regex patterns to only match sentence starts
        var result = text
        let assistantName = provider?.displayName ?? "Claude Code"

        // Pattern: "<AssistantName> is <verb>ing" → "<AssistantName> <verb>ed"
        let escapedName = NSRegularExpression.escapedPattern(for: assistantName)
        let patternString = "^\(escapedName) is (\\w+?)ing\\b"
        if let regex = try? NSRegularExpression(pattern: patternString, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "\(assistantName) $1ed")
        }

        // Pattern: "<AssistantName> <verb>s" → "<AssistantName> <verb>ed" (only for safe verbs)
        let verbTransforms = [
            "proposes": "proposed",
            "implements": "implemented",
            "fixes": "fixed",
            "adds": "added",
            "creates": "created",
            "updates": "updated",
            "modifies": "modified"
        ]
        for (verb, pastForm) in verbTransforms {
            if result.hasPrefix("\(assistantName) \(verb)") {
                result = result.replacingOccurrences(of: "\(assistantName) \(verb)", with: "\(assistantName) \(pastForm)")
                break
            }
        }

        return result
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@Generable(description: "Timeline summary metadata for HUD entries")
// SCHEMA CONTRACT: Must stay in exact lockstep with LLM prompt JSON output
// The prompt in instructionsForTimeline(kind: .assistant) promises this exact structure:
// {
//   "summary": String (≤140 chars, starts with assistant name)
//   "isCompletion": Bool (true only if explicit completion markers)
//   "disposition": String (one of: ack, completion, wip, analysis, proposal, question, refusal)
//   "grounding": String (grounded | ungrounded | insufficient)
//   "confidence": Double (0.0-1.0)
// }
// ⚠️ Any mismatch in field names, types, or required/optional status will cause guided decoding to fail silently.
// ⚠️ If adding fields here, you MUST update the prompt's JSON example and instructions.
struct GuidedTimelineSummary {
    @Guide(description: "One sentence (≤140 chars) starting with an allowed prefix. Use only MESSAGE content.")
    var summary: String

    @Guide(description: "true only if the MESSAGE explicitly reports completion (done/fixed/completed/merged/wrote/saved/✅).")
    var isCompletion: Bool

    @Guide(description: "Message disposition: directive, question, report, affirmative, negative (user), ack, completion, wip, analysis, proposal, refusal (assistant).")
    var disposition: String

    @Guide(description: "Grounding: grounded, ungrounded, insufficient.")
    var grounding: String

    @Guide(description: "Confidence value between 0.0 and 1.0", .range(0...1))
    var confidence: Double
}

/// One controller per unique instructions string; guarantees single-flight respond().
@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
actor SessionController {
    private let log = Logger(subsystem: "dev.contextify", category: "FoundationLLM.SessionController")
    private let instructions: String
    private var session: LanguageModelSession?

    // FIFO async semaphore with cancellation support (ordered queue + dictionary)
    private var inFlight = false
    private var waitOrder: [UUID] = []                          // preserves FIFO order
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    // Per-session lifetime tracking and circuit breaker
    private var requestCount = 0
    private var consecutiveErrors = 0
    private let maxRequests = 15
    private let maxConsecutiveErrors = 3

    // Session epoch to prevent reset fighting
    private var epoch = 0

    // Force stateless mode: reset session before every request
    // Enable if benchmarks show session creation is very fast (<2ms)
    private let forceStateless: Bool

    // Schema installation tracking (one-time per session)
    private var schemaInstalledTypes: Set<String> = []
    private var historyMessageCount = 0

    init(instructions: String, forceStateless: Bool = false) {
        self.instructions = instructions
        self.forceStateless = forceStateless
    }

    private func getOrCreateSession() throws -> LanguageModelSession {
        // Circuit breaker: reset if limits exceeded
        if requestCount >= maxRequests || consecutiveErrors >= maxConsecutiveErrors {
            log.warning("Circuit breaker triggered (requests: \(self.requestCount)/\(self.maxRequests), errors: \(self.consecutiveErrors)/\(self.maxConsecutiveErrors))")
            reset()
        }

        if let s = session { return s }
        let s = LanguageModelSession(instructions: self.instructions)
        session = s
        log.info("Created LanguageModelSession for instructions key (\(self.instructions.prefix(24), privacy: .public))… (epoch \(self.epoch))")
        return s
    }

    func reset() {
        session = nil
        requestCount = 0
        consecutiveErrors = 0
        schemaInstalledTypes = []
        historyMessageCount = 0
        epoch &+= 1
        log.info("Reset LanguageModelSession for instructions key (\(self.instructions.prefix(24), privacy: .public))… (epoch \(self.epoch))")
    }

    private func acquire() async -> Bool {
        if !inFlight {
            inFlight = true                                     // fast path gets the token
            return true
        }

        // Enqueue waiter in FIFO order
        let id = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                waitOrder.append(id)
                waiters[id] = cont
            }
        } onCancel: {
            // Do NOT call release() here - just remove from queue
            Task {
                await self.cancelWaiter(id)
            }
        }
        // Will be resumed by cancelWaiter(false) or release(true)
        return acquired
    }

    private func cancelWaiter(_ id: UUID) {
        if let idx = waitOrder.firstIndex(of: id) {
            waitOrder.remove(at: idx)
        }
        if let cont = waiters.removeValue(forKey: id) {
            cont.resume(returning: false)  // explicitly NOT acquired - caller must check
        }
        // Cancelled waiter is dropped; current holder keeps the token
    }

    private func release() {
        // Give token to the next non-cancelled waiter or mark idle
        while let id = waitOrder.first {
            waitOrder.removeFirst()
            if let cont = waiters.removeValue(forKey: id) {
                cont.resume(returning: true)  // hand off token to next waiter
                return                        // token stays inFlight for resumed waiter
            }
        }
        inFlight = false                      // no waiters → idle
    }

    func generate<T: Generable>(
        _ prompt: String,
        generating: T.Type,
        includeSchema: Bool,
        options: GenerationOptions,
        recordHistory: Bool = true
    ) async throws -> T {
        let acquired = await acquire()
        guard acquired else { throw CancellationError() }
        defer { release() }

        if forceStateless { reset() }

        let typeName = String(describing: T.self)
        let schemaAlreadyInstalled = schemaInstalledTypes.contains(typeName)

        // Diagnostic logging
        let maxResp = options.maximumResponseTokens ?? 0
        log.info("[LLM] hist=\(self.historyMessageCount) schema=\(schemaAlreadyInstalled ? "✓" : "new") promptChars=\(prompt.count) maxResp=\(maxResp) ephemeral=\(!recordHistory)")

        do {
            let s: LanguageModelSession
            let isEphemeral = !recordHistory

            if isEphemeral {
                // Ephemeral: create throwaway session (won't pollute main session)
                s = LanguageModelSession(instructions: instructions)
                log.debug("Created ephemeral session for pre-flight")
            } else {
                // Normal: use persistent session
                s = try getOrCreateSession()
            }

            // Track schema installation (one-time per type per session)
            // For ephemeral calls, schema is always "new" since it's a fresh session
            if includeSchema && (!schemaAlreadyInstalled || isEphemeral) {
                if !isEphemeral {
                    schemaInstalledTypes.insert(typeName)
                }
                log.debug("Installed schema for \(typeName) (ephemeral=\(isEphemeral))")
            }

            let resp = try await s.respond(
                to: prompt,
                generating: T.self,
                includeSchemaInPrompt: includeSchema,
                options: options
            )

            // Only increment history count if recording
            if recordHistory {
                requestCount += 1
                historyMessageCount += 1
            } else {
                log.debug("Ephemeral call completed - session discarded")
            }

            consecutiveErrors = 0
            return resp.content
        } catch {
            consecutiveErrors += 1
            // Reset on context window overflow
            if case LanguageModelSession.GenerationError.exceededContextWindowSize = error {
                log.error("Context window overflow - resetting session (hist=\(self.historyMessageCount))")
                reset()
            }
            throw error
        }
    }

    func raw(_ prompt: String, options: GenerationOptions) async throws -> String {
        let acquired = await acquire()
        guard acquired else { throw CancellationError() }
        defer { release() }

        if forceStateless { reset() }

        do {
            let s = try getOrCreateSession()
            let resp = try await s.respond(to: prompt, options: options)
            requestCount += 1
            consecutiveErrors = 0
            return resp.content
        } catch {
            consecutiveErrors += 1
            // Reset on context window overflow
            if case LanguageModelSession.GenerationError.exceededContextWindowSize = error {
                reset()
            }
            throw error
        }
    }

    // MARK: - DEBUG hooks for testing

    #if DEBUG
    /// Get current waiter count for testing FIFO queue behavior
    func _debugWaiterCount() async -> Int {
        waiters.count
    }

    /// Get current epoch for testing epoch tracking and reset behavior
    func _debugEpoch() async -> Int {
        epoch
    }

    /// Get current request count for testing circuit breaker
    func _debugRequestCount() async -> Int {
        requestCount
    }

    /// Get consecutive error count for testing circuit breaker
    func _debugConsecutiveErrors() async -> Int {
        consecutiveErrors
    }
    #endif
}
#endif

// MARK: - Slash Command Detection

private extension FoundationLLM {
    /// Detect and summarize slash commands from Claude Code and Codex CLI
    /// Returns a summary string if a command is detected, nil otherwise
    nonisolated func detectSlashCommand(_ message: String, assistantName: String) -> String? {
        // Extract command pattern: /command [optional args]
        // Match messages containing <command-name>/command</command-name> or starting with /command
        let normalizedMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern 1: <command-name>/clear</command-name> ...
        if let commandNameMatch = normalizedMsg.range(of: #"<command-name>/([a-z_\-]+)</command-name>"#, options: .regularExpression) {
            let commandName = normalizedMsg[commandNameMatch]
                .replacingOccurrences(of: "<command-name>/", with: "")
                .replacingOccurrences(of: "</command-name>", with: "")

            if let summary = knownCommandSummary(commandName) {
                return summary
            }
            // Generic fallback for unknown commands
            return "You performed the following command: /\(commandName)."
        }

        // Pattern 2: Message starts with /command
        if normalizedMsg.hasPrefix("/") {
            // Extract command and args
            let parts = normalizedMsg.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let commandPart = parts.first else { return nil }
            let commandName = String(commandPart.dropFirst()) // Remove leading /
            let args = parts.count > 1 ? String(parts[1]) : nil

            if let summary = knownCommandSummary(commandName, args: args) {
                return summary
            }
            // Generic fallback with args
            if let args = args {
                return "You performed the following command: /\(commandName) \(args)."
            } else {
                return "You performed the following command: /\(commandName)."
            }
        }

        return nil
    }

    /// Known command summaries for Claude Code and Codex CLI built-in commands
    nonisolated func knownCommandSummary(_ command: String, args: String? = nil) -> String? {
        switch command {
        // Commands common to both Claude Code and Codex
        case "clear":
            return "You cleared the session context using the /clear command."
        case "compact":
            if let args = args, !args.isEmpty {
                return "You compacted the conversation with focus instructions using /compact."
            }
            return "You compacted the conversation using the /compact command."
        case "model":
            return "You changed the AI model using the /model command."
        case "review":
            return "You requested a code review using the /review command."
        case "init":
            return "You initialized the project with agent instructions using /init."
        case "logout":
            return "You logged out using the /logout command."
        case "mcp":
            return "You managed MCP server connections using the /mcp command."
        case "status":
            return "You checked the session status using the /status command."

        // Claude Code specific
        case "add-dir", "add_dir":
            return "You added working directories using the /add-dir command."
        case "agents":
            return "You managed custom AI subagents using the /agents command."
        case "bug":
            return "You reported a bug using the /bug command."
        case "config":
            return "You opened the Settings interface using /config."
        case "cost":
            return "You checked token usage statistics using /cost."
        case "doctor":
            return "You ran a health check using /doctor."
        case "help":
            return "You requested help using the /help command."
        case "login":
            return "You switched Anthropic accounts using /login."
        case "memory":
            return "You edited CLAUDE.md memory files using /memory."
        case "permissions":
            return "You managed permissions using the /permissions command."
        case "pr_comments", "pr-comments":
            return "You viewed pull request comments using /pr_comments."
        case "rewind":
            return "You rewound the conversation using /rewind."
        case "sandbox":
            return "You enabled sandboxed bash execution using /sandbox."
        case "terminal-setup", "terminal_setup":
            return "You configured terminal key bindings using /terminal-setup."
        case "usage":
            return "You checked plan usage limits using /usage."
        case "vim":
            return "You entered vim mode using the /vim command."

        // Codex specific
        case "approvals":
            return "You configured approval settings using /approvals."
        case "new":
            return "You started a new chat using the /new command."
        case "undo":
            return "You undid the previous turn using /undo."
        case "diff":
            return "You viewed the git diff using /diff."
        case "mention":
            return "You mentioned a file using the /mention command."
        case "quit", "exit":
            return "You exited the session using /\(command)."
        case "feedback":
            return "You sent feedback to maintainers using /feedback."

        default:
            return nil // Unknown command, caller will use generic fallback
        }
    }
}

// MARK: - Word-boundary helpers for intent classification

private extension FoundationLLM {
    /// Simple regex cache to avoid recompilation in hot paths
    /// Thread-safe via NSLock; NSRegularExpression is thread-safe for matching
    final class RegexCache: @unchecked Sendable {
        static let shared = RegexCache()
        private var cache: [String: NSRegularExpression] = [:]
        private let lock = NSLock()

        func regex(for pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
            lock.lock()
            defer { lock.unlock() }
            if let rx = cache[pattern] { return rx }
            guard let rx = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            cache[pattern] = rx
            return rx
        }
    }

    /// Normalize text for intent classification (single normalization pass)
    nonisolated static func normalizeForIntent(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Normalize apostrophes: U+2018 ('), U+2019 ('), U+2032 (′), backtick
        let apostropheVariants = ["\u{2018}", "\u{2019}", "\u{2032}", "`"]
        apostropheVariants.forEach { normalized = normalized.replacingOccurrences(of: $0, with: "'") }

        // Collapse runs of whitespace to a single space (stabilizes phrase matching)
        normalized = normalized.replacingOccurrences(
            of: #"\s+"#, with: " ", options: .regularExpression
        )

        // Handle common contractions missing apostrophes with boundary-aware regexes
        normalized = replaceWordBoundary(normalized, from: "lets", to: "let's")
        normalized = replaceWordBoundary(normalized, from: "dont", to: "don't")
        normalized = replaceWordBoundary(normalized, from: "cant", to: "can't")
        normalized = replaceWordBoundary(normalized, from: "wont", to: "won't")
        normalized = replaceWordBoundary(normalized, from: "shouldnt", to: "shouldn't")
        normalized = replaceWordBoundary(normalized, from: "wouldnt", to: "wouldn't")
        normalized = replaceWordBoundary(normalized, from: "couldnt", to: "couldn't")

        // Fix common typos that might affect intent detection
        let typoFixes = [
            ("develioper", "developer"),
            ("devleoper", "developer"),
            ("teh ", "the "),
            (" taht ", " that "),
            (" wiht ", " with "),
            (" brnach", " branch"),
            (" barnch", " branch")
        ]
        for (typo, correct) in typoFixes {
            normalized = normalized.replacingOccurrences(of: typo, with: correct)
        }

        return normalized
    }

    /// Replace a whole word regardless of trailing punctuation using Unicode boundaries
    nonisolated static func replaceWordBoundary(_ text: String, from: String, to: String) -> String {
        let pattern = "(^|[^\\p{L}\\p{N}])(\(regexEscape(from)))(?=$|[^\\p{L}\\p{N}])"
        let repl = "$1\(to)"
        guard let rx = RegexCache.shared.regex(for: pattern, options: [.caseInsensitive]) else { return text }
        return rx.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: repl)
    }

    /// Escape string for use in regex pattern
    nonisolated static func regexEscape(_ s: String) -> String {
        NSRegularExpression.escapedPattern(for: s)
    }

    /// Unicode-aware word boundary check: start/end or any non-letter/number
    nonisolated static func containsWord(_ text: String, word: String) -> Bool {
        let pattern = "(^|[^\\p{L}\\p{N}])\(regexEscape(word))(?=$|[^\\p{L}\\p{N}])"
        guard let rx = RegexCache.shared.regex(for: pattern, options: [.caseInsensitive]) else { return false }
        return rx.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Phrase match with word-like boundaries at both ends, tolerant to punctuation
    nonisolated static func containsPhrase(_ text: String, phrase: String) -> Bool {
        let core = regexEscape(phrase).replacingOccurrences(of: "\\ ", with: "\\s+")
        let pattern = "(^|[^\\p{L}\\p{N}])\(core)(?=$|[^\\p{L}\\p{N}])"
        guard let rx = RegexCache.shared.regex(for: pattern, options: [.caseInsensitive]) else { return false }
        return rx.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Check if text starts with any of the given prefixes (fast path without regex)
    nonisolated static func startsWithAny(_ text: String, prefixes: [String]) -> Bool {
        for prefix in prefixes {
            if text.hasPrefix(prefix) { return true }
        }
        return false
    }

    /// Treat "reinvestigate" as "investigate", etc. (productive prefixes)
    /// Guards against spurious matches by requiring stem length ≥ 4
    nonisolated static func isImperativeLike(_ word: String, baseVerbs: Set<String>) -> Bool {
        if baseVerbs.contains(word) { return true }
        // Common productive prefixes seen in requests
        let prefixes = ["re", "pre", "auto", "de"]
        for p in prefixes {
            if word.hasPrefix(p), let idx = word.index(word.startIndex, offsetBy: p.count, limitedBy: word.endIndex) {
                let stem = String(word[idx...])
                // Require stem length ≥ 4 to avoid spurious hits (e.g., "remove" if "move" were added)
                if stem.count >= 4 && baseVerbs.contains(stem) { return true }
            }
        }
        return false
    }

    /// Prebuilt alternation pattern for problem indicators (compiled once, cached)
    nonisolated static func matchesProblemIndicators(_ text: String) -> Bool {
        // Lazy-init pattern on first use
        struct Static {
            static let pattern: String = {
                let phrases = [
                    "did not work", "didn't work", "not working", "does not work", "doesn't work",
                    "did not do", "didn't do", "does not do", "doesn't do",
                    "not seeing", "not showing", "not displayed", "not appearing",
                    "that did not", "that didn't", "no that did", "nope that"
                ]
                let escaped = phrases.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
                return "(^|[^\\p{L}\\p{N}])(\(escaped))(?=$|[^\\p{L}\\p{N}])"
            }()
        }
        guard let rx = RegexCache.shared.regex(for: Static.pattern, options: [.caseInsensitive]) else {
            return false
        }
        return rx.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }
}

private extension FoundationLLM {
    struct PrefixPolicy {
        let allowed: [String]
        let fallback: String
    }

    func fallback(for kind: TimelineEntryKind, text: String, provider: TimelineSourceContext.Provider? = nil) -> String {
        let normalized = collapseWhitespace(text)
        let policy = prefixPolicy(for: kind, provider: provider)
        guard !normalized.isEmpty else { return policy.fallback }
        if hasAllowedPrefix(normalized, policy: policy) {
            return normalized
        }
        return "\(policy.fallback) \(normalized)"
    }

    func sanitize(_ summary: String, kind: TimelineEntryKind, provider: TimelineSourceContext.Provider? = nil) -> String {
        var output = collapseWhitespace(summary)
        let policy = prefixPolicy(for: kind, provider: provider)
        if output.isEmpty {
            output = policy.fallback
        } else if !hasAllowedPrefix(output, policy: policy) {
            output = "\(policy.fallback) \(output)"
        }
        if output.count > 140 {
            output = truncateAtWordBoundary(output, limit: 140)
        }
        return output
    }

    /// Truncates text at the last complete word before the character limit
    /// to avoid cutting mid-word. Adds ellipsis if truncated.
    func truncateAtWordBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }

        // Try to find last space before the limit
        let truncated = String(text.prefix(limit))

        // Find the last word boundary (space, punctuation, etc.)
        if let lastSpace = truncated.lastIndex(where: { $0.isWhitespace || $0.isPunctuation }) {
            let result = String(truncated[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Only add ellipsis if we actually truncated meaningful content
            if !result.isEmpty && text.count > result.count + 5 {
                return result + "…"
            }
            return result
        }

        // No word boundary found - fall back to hard truncation but with ellipsis
        return String(text.prefix(limit - 1)) + "…"
    }

    func prefixPolicy(for kind: TimelineEntryKind, provider: TimelineSourceContext.Provider? = nil) -> PrefixPolicy {
        let assistantName = provider?.displayName ?? "Claude Code"
        switch kind {
        case .assistant:
            return PrefixPolicy(allowed: [assistantName], fallback: assistantName)
        case .user:
            return PrefixPolicy(
                allowed: [
                    "You informed",          // REPORT: past-tense self-reports
                    "You asked",
                    "You requested \(assistantName)",
                    "You explained",         // UNKNOWN: explanations/clarifications
                    "You mentioned",         // UNKNOWN: providing info/context (also /mention)
                    "You noted",             // UNKNOWN: acknowledgments/comments
                    "You said:",             // UNKNOWN: truly unclear messages
                    "You cleared",           // /clear
                    "You compacted",         // /compact
                    "You changed",           // /model
                    "You checked",           // /status, /cost, /usage
                    "You initialized",       // /init
                    "You logged",            // /login, /logout
                    "You managed",           // /mcp, /agents, /permissions
                    "You added",             // /add-dir
                    "You reported",          // /bug
                    "You opened",            // /config
                    "You ran",               // /doctor
                    "You switched",          // /login (account switching)
                    "You edited",            // /memory
                    "You viewed",            // /pr_comments
                    "You rewound",           // /rewind
                    "You enabled",           // /sandbox
                    "You configured",        // /terminal-setup, /approvals
                    "You entered",           // /vim
                    "You started",           // /new
                    "You undid",             // /undo
                    "You exited",            // /quit, /exit
                    "You sent",              // /feedback
                    "You performed",         // generic fallback for unknown commands
                    "You executed"           // alternative generic fallback
                ],
                fallback: "You requested \(assistantName)"
            )
        case .system:
            return PrefixPolicy(allowed: ["System"], fallback: "System")
        }
    }

    func hasAllowedPrefix(_ text: String, policy: PrefixPolicy) -> Bool {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:;,."))
        let lower = text.lowercased()
        for prefix in policy.allowed {
            let candidate = prefix.lowercased()
            guard lower.hasPrefix(candidate) else { continue }
            let boundary = lower.index(lower.startIndex, offsetBy: candidate.count)
            if boundary == lower.endIndex { return true }
            let scalar = lower[boundary]
            if String(scalar).rangeOfCharacter(from: separators) != nil {
                return true
            }
        }
        return false
    }


    func instructionsForTimeline(kind: TimelineEntryKind, provider: TimelineSourceContext.Provider? = nil) -> String {
        let assistantName = provider?.displayName ?? "Claude Code"
        switch kind {
        case .assistant:
            return """
            You are classifying a SINGLE assistant message for a developer timeline.

            Your job:
            1. Decide the **disposition** of this message
            2. Write a short summary suitable for a project activity timeline

            ### Dispositions

            Choose the most appropriate disposition. For most assistant messages, use one of these three:

            **"completion"** - Work that has ALREADY been done or is actively being performed
            Examples:
            - "I've added logging to the function."
            - "I refactored the class into two files."
            - "I just pushed a fix to handle that edge case."

            **"proposal"** - Work that COULD be done in the future, or offering to do something, but NOT done yet
            Examples:
            - "I can add logging to that function."
            - "I will refactor this into two files."
            - "Let me write a unit test for this."
            - "Would you like me to add a retry loop?"

            **"analysis"** - Analyzing, explaining, or reasoning WITHOUT committing to future work or reporting completed work
            Examples:
            - "Looking at the stack trace, it seems like the crash is due to a nil optional."
            - "There should be a race condition between these two tasks."
            - "It appears that the query is missing an index."

            (If clearly appropriate, you may also use: ack, wip, question, refusal)

            ### Verb & Tense Rules (CRITICAL)

            Use verb tense and context to decide disposition:

            **COMPLETION** when:
            - Message uses PAST or PRESENT PERFECT tense:
              "I've added…", "I already…", "I just…", "I went ahead and…", "I updated…", "I fixed…"
            - Assistant is reporting work IS DONE or IS BEING DONE

            **PROPOSAL** when:
            - Message uses FUTURE or CONDITIONAL tense:
              "I'll…", "I will…", "I can…", "I could…", "I'm going to…", "I need to…", "Let me…", "Would you like me to…"
            - Assistant is describing something that MIGHT be done, OFFERING work, or SUGGESTING change

            **ANALYSIS** when:
            - Message describes or interprets information:
              "Looking at…", "It looks like…", "It seems that…", "This suggests…", "There should be…", "I think the issue is…"
            - Text is explanation or diagnosis without clear action claim or promise

            ### Mixed/Ambiguous Cases

            - If message describes **completed work AND mentions future steps**:
              → Prefer **"completion"** if at least one significant action is clearly done

            - If message is **mostly explanation** with weak language like "we could…" but no concrete commitment:
              → Prefer **"analysis"** over "proposal"

            - Do NOT label as "proposal" only because of "should" or "could" in analysis context:
              → "There should be a lock around this code" is **analysis**, not a proposal to implement it

            ### Summary Phrasing (CRITICAL)

            Match your verb choice to the disposition:

            **For COMPLETION:**
            - Use past-tense verbs: "added", "implemented", "refactored", "fixed", "updated", "created"
            - Do NOT use proposal language like "proposed" or "suggested"
            - Example: "\(assistantName) implemented retry logic in the network client."

            **For PROPOSAL:**
            - Use proposal verbs: "proposed", "suggested", "offered to", "outlined", "presented"
            - Do NOT use completion verbs like "created", "implemented", "fixed"
            - Example: "\(assistantName) suggested adding telemetry for deployment metrics."

            **For ANALYSIS:**
            - Use analysis verbs: "explained", "analyzed", "noted", "identified", "clarified"
            - Example format: "\(assistantName) [verb] the [subject] and [verb] [outcome]."
            - Concrete example: "\(assistantName) explained the authentication logic and identified retry timing."

            ### Output Format

            Return a JSON object with these exact keys:

            {
              "summary": "One sentence (≤140 chars) starting with '\(assistantName)'",
              "isCompletion": true,
              "disposition": "completion",
              "grounding": "grounded",
              "confidence": 0.75
            }

            Input format:
            MESSAGE:
            <<<assistant text>>>
            """
        case .user:
            return """
            You produce a ONE-sentence timeline summary (≤140 chars) for a developer message.

            DETECTED_INTENT will be provided as: DIRECTIVE | QUESTION | REPORT | AFFIRMATIVE | NEGATIVE | UNKNOWN

            Use these prefixes based on DETECTED_INTENT:
            - DIRECTIVE   → "You requested \(assistantName) to [action]"
            - QUESTION    → "You asked \(assistantName) [question]"
            - REPORT      → "You informed \(assistantName) [description]"
            - AFFIRMATIVE → "You requested \(assistantName) to proceed as proposed."
            - NEGATIVE    → "You requested \(assistantName) not to proceed."
            - UNKNOWN     → Infer intent from MESSAGE content:
              * If explaining/clarifying → "You explained [what]"
              * If providing info/context → "You mentioned [what]"
              * If acknowledging/commenting → "You noted [what]"
              * If truly unclear → "You said [brief paraphrase]"

            Rules:
            - MESSAGE has already been preprocessed to remove code blocks, quotes, blockquotes, and system output
            - If ACTION_HINT is present, it provides context but should NOT appear in the summary text
            - Use past-tense verb in the prefix ("requested", "asked", "made")
            - Focus on user's intent, not implementation details
            - NEVER repeat verbose system output, file paths, or command results in the summary
            - Keep summaries concise and high-level (≤140 chars is STRICT)
            - No emojis

            Fields:
            - summary: one sentence following the rules above
            - isCompletion: false (users don't complete tasks, Claude does)
            - disposition: echo the DETECTED_INTENT value
            - grounding: "grounded" if summary matches MESSAGE, "ungrounded" if not
            - confidence: 0.0–1.0 (higher when intent is clear and MESSAGE is unambiguous)

            Input format:
            MESSAGE:
            <<<user text>>>
            DETECTED_INTENT: <intent>
            Optional ACTION_HINT:
            <<<assistant proposal>>>
            """
        case .system:
            return """
            You fill a TimelineSummary for a neutral system event.
            - summary: one concise sentence under 140 characters.
            - isCompletion: false.
            - No emojis.
            """
        }
    }

    func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizePhrase(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized.trimmingCharacters(in: .punctuationCharacters.union(CharacterSet(charactersIn: "…“”\"'")))
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return normalized.lowercased()
    }

    func introducedTopics(message: String, summary: String) -> [String] {
        func tokens(_ source: String) -> Set<String> {
            let keep = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._- "))
            let filtered = String(source.unicodeScalars.filter { keep.contains($0) })
            let punct = CharacterSet.punctuationCharacters
            return Set(filtered.lowercased().split(separator: " ")
                .map { $0.trimmingCharacters(in: punct) }
                .filter { $0.count >= 3 })
        }
        let summaryTokens = tokens(summary)
        let messageTokens = tokens(message)
        let diff = summaryTokens.subtracting(messageTokens).subtracting(bridgingLexicon)
        return Array(diff)
    }

    var bridgingLexicon: Set<String> {
        [
            // Assistant-specific verbs
            "claude", "explains", "explained", "explaining", "clarifies", "clarified", "clarifying",
            "states", "stated", "says", "said", "notes", "noted", "acknowledges", "acknowledged",
            "confirms", "confirmed", "reports", "reported", "outlines", "outlined", "highlights",
            "highlighted", "advises", "advised", "suggests", "suggested", "proposes", "proposed",
            "asks", "asked", "observes", "observed", "mentions", "mentioned", "reminds", "reminded",
            "recommends", "recommended", "describes", "described", "details", "detailed", "responds",
            "responded", "summarizes", "summarized",

            // User message required words (from LLM instructions)
            "you", "requested", "made",
            // User prefix verbs (slash commands and general)
            "informed", "cleared", "compacted", "changed", "checked", "initialized",
            "logged", "managed", "added", "opened", "ran", "switched", "edited",
            "viewed", "rewound", "enabled", "configured", "entered", "started",
            "undid", "exited", "sent", "performed", "executed",

            // Instruction-derived words
            "infer", "proceed", "proposed",

            // Common prepositions and conjunctions
            "about", "from", "during", "with", "for", "and", "the", "that", "this", "these", "those",
            "regarding", "concerning", "without", "into", "onto", "upon",

            // Generic action/context words that legitimately appear in summaries
            "options", "types", "handling", "transitions", "moving", "changes", "updates",
            "message", "messages", "logs", "issues", "errors", "them", "perhaps",

            // Meta-discussion terms (used when discussing text/wording/UI copy)
            "sound", "sounds", "sounded", "unsatisfactory", "satisfactory", "feedback",
            "phrase", "phrases", "phrasing", "wording", "worded", "word", "words",
            "alternative", "alternatives", "preferred", "prefer", "prefers", "preference",
            "subtle", "subtly", "current", "currently", "existing", "text", "copy",
            "messaging", "label", "labels", "labeled",
            "better", "worse", "improved", "improvement", "clearer", "clarity"
        ]
    }

    func hasCompletionToken(_ text: String) -> Bool {
        let lower = text.lowercased()
        return completionLexicon.contains { lower.contains($0) }
    }

    func isAck(_ text: String) -> Bool {
        let normalized = normalizePhrase(text)
        guard !normalized.isEmpty else { return false }
        let tokens = normalized.split(separator: " ")
        guard tokens.count <= 3 else { return false }
        return tokens.allSatisfy { acknowledgementLexicon.contains(String($0)) }
    }

    // NOTE: isDirective() and classifyUserIntent() both detect directives but use
    // different lexicons. isDirective() is a post-LLM fallback, classifyUserIntent()
    // runs pre-LLM. Keep directiveLexicon in sync with directivePatterns in
    // classifyUserIntent(). Could be unified in a future refactor.
    func isDirective(_ text: String) -> Bool {
        let lower = text.lowercased()
        return directiveLexicon.contains { lower.contains($0) }
    }

    var acknowledgementLexicon: Set<String> {
        ["ack", "ok", "okay", "k", "👍", "roger", "thanks", "thx", "ty", "got", "it", "understood", "noted", "sure"]
    }

    var directiveLexicon: [Substring] {
        [
            "please", "can you", "could you", "would you", "go ahead",
            "proceed", "continue", "commit", "fix", "update", "add",
            "create", "make", "build", "run", "test", "deploy",
            "implement", "refactor", "change", "modify", "remove", "delete",
            "we should", "we need to", "we could", "let's", "i want",
            "i need", "help me", "figure out", "look"
        ]
    }

    var completionLexicon: [Substring] {
        [
            "✅", "done", "completed", "finished", "fixed", "resolved", "ready",
            "build succeeded", "wrote", "saved", "applied", "merged", "shipped", "implemented"
        ]
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension FoundationLLM {
    // Controllers now moved to actor state (see top of FoundationLLM actor)

    func getController(for instructions: String, sessionId: String? = nil) async -> SessionController {
        let key = sessionId ?? instructions
        if let entry = controllers[key] {
            // Update last-used timestamp
            controllers[key]?.lastUsed = .now
            return entry.controller
        }
        let controller = SessionController(instructions: instructions, forceStateless: forceStatelessMode)
        controllers[key] = ControllerEntry(controller: controller, lastUsed: .now)
        await evictIdleControllers()
        return controller
    }

    // Make sessionKey() public and nonisolated (no actor state access)
    nonisolated public func sessionKey(
        model: String,
        instructions: String,
        schemaSig: String,
        transcriptId: String
    ) -> String {
        let instrHash = SHA256.hash(data: Data(instructions.utf8)).hexString.prefix(16)
        return "\(model)|\(instrHash)|\(schemaSig)|\(transcriptId)"
    }

    /// Reset session for specific session ID
    public func resetSessionById(_ sessionId: String) async {
        if let entry = controllers[sessionId] {
            await entry.controller.reset()
            log.info("Reset session: \(sessionId.prefix(32))")
        }
    }

    /// Evict idle controllers to prevent unbounded growth
    /// Default: 5 min idle timeout, max 16 total controllers
    func evictIdleControllers(maxIdle: TimeInterval = 300, maxTotal: Int = 16) async {
        let cutoff = Date().addingTimeInterval(-maxIdle)

        // Keep only active entries (rebuild dictionary)
        controllers = controllers.reduce(into: [:]) { acc, pair in
            if pair.value.lastUsed > cutoff { acc[pair.key] = pair.value }
        }

        // Cap by LRU if still over capacity
        if controllers.count > maxTotal {
            let victims = controllers.sorted { $0.value.lastUsed < $1.value.lastUsed }
                                     .prefix(controllers.count - maxTotal)
                                     .map(\.key)
            for key in victims {
                controllers.removeValue(forKey: key)
            }
        }
    }

    /// Check if summary contains known prompt example phrases that indicate contamination
    private func containsPromptExample(_ summary: String) -> Bool {
        let examples = [
            "analyzed the stack trace and identified the root cause",
            "added logging around the authentication flow",
            "proposed creating a helper script with presets"
        ]
        return examples.contains { summary.localizedCaseInsensitiveContains($0) }
    }

    func postProcess(
        kind: TimelineEntryKind,
        payload: GuidedTimelineSummary,
        message: String,
        provider: TimelineSourceContext.Provider? = nil
    ) throws -> TimelineSummaryResult {
        let summary = sanitize(payload.summary, kind: kind, provider: provider)

        if kind == .assistant {
            let leaked = introducedTopics(message: message, summary: summary)

            // Objective validation (no LLM self-assessment)
            // Reject if:
            // 1. Excessive leakage (≥6 tokens from prompt)
            // 2. Contains known prompt example phrases
            let excessiveLeakage = leaked.count >= 6
            let hasExamplePhrase = containsPromptExample(summary)

            let shouldReject = excessiveLeakage || hasExamplePhrase

            if shouldReject {
                if hasExamplePhrase {
                    log.warning("[VALIDATION-REJECT] Timeline summary contains prompt example phrase: \(summary, privacy: .public)")
                }
                if excessiveLeakage {
                    log.warning("[VALIDATION-REJECT] Timeline summary has excessive leakage (leaked=\(leaked.count), confidence=\(payload.confidence, privacy: .public)): \(leaked.joined(separator: ", "), privacy: .public)")
                }

                // Special case: if it's just an ack, accept the generic ack message
                let assistantName = provider?.displayName ?? "Claude Code"
                if isAck(message) {
                    return TimelineSummaryResult(summary: "\(assistantName) acknowledges the request.", isCompletion: false, isDirective: false, disposition: "ack")
                }
                // Reject but DON'T retry - it won't help since input doesn't change
                log.error("NOT retrying - postProcess rejection won't change with same input")
                throw TimelineError.validationFailure(reason: "excessive leakage or prompt contamination")
            }

            if leaked.count > 0 {
                log.debug("[VALIDATION-ACCEPT] Timeline summary accepted with minimal leakage (leaked=\(leaked.count), confidence=\(payload.confidence, privacy: .public))")
            }

            // Disposition-verb alignment validation
            // Catch obvious mismatches using lexical cues from the original message

            let msgLower = message.lowercased()

            // Lexical cue detection
            // Completion cues: first-person past/present-perfect markers
            // Note: Removed generic "done" and "✅" (too noisy, appear in non-completion contexts)
            let completionCues = [
                "i've ", "i have ", "i already ", "i just ", "i went ahead",
                "i updated", "i fixed", "i changed", "i added", "i implemented",
                "i pushed", "i committed"
            ]
            let hasCompletionCue = completionCues.contains { msgLower.contains($0) }

            let proposalCues = [
                "i'll ", "i will ", "i can ", "i could ", "i'm going to",
                "i need to ", "let me ", "would you like me to", "i should go"
            ]
            let hasProposalCue = proposalCues.contains { msgLower.contains($0) }

            let analysisCues = [
                "looking at ", "it looks like", "it seems that", "there should be",
                "this suggests", "the issue is", "i think the problem is",
                "from the logs", "from the stack trace"
            ]
            let hasAnalysisCue = analysisCues.contains { msgLower.contains($0) }

            // Validation rules (in priority order)

            // Rule 1: Flip proposal → completion if strong completion cues present
            if payload.disposition == "proposal" && hasCompletionCue && !hasProposalCue {
                log.warning("Overriding disposition: proposal → completion (completion cues detected)")
                log.debug("Message preview: \(String(message.prefix(200)), privacy: .public)")

                return TimelineSummaryResult(
                    summary: summary,
                    isCompletion: true,
                    isDirective: false,
                    disposition: "completion"
                )
            }

            // Rule 2: Flip completion → proposal if strong proposal cues present
            if payload.disposition == "completion" && hasProposalCue && !hasCompletionCue && !hasAnalysisCue {
                log.warning("Overriding disposition: completion → proposal (proposal cues detected)")
                log.debug("Message preview: \(String(message.prefix(200)), privacy: .public)")

                return TimelineSummaryResult(
                    summary: summary,
                    isCompletion: false,
                    isDirective: false,
                    disposition: "proposal"
                )
            }

            // Rule 3: Flip proposal → analysis if pure diagnostic language
            if payload.disposition == "proposal" && hasAnalysisCue && !hasCompletionCue && !hasProposalCue {
                log.warning("Overriding disposition: proposal → analysis (analysis cues detected)")
                log.debug("Message preview: \(String(message.prefix(200)), privacy: .public)")

                return TimelineSummaryResult(
                    summary: summary,
                    isCompletion: false,
                    isDirective: false,
                    disposition: "analysis"
                )
            }

            // Rule 4: Mixed case - completion wins if strong past-perfect present
            if hasCompletionCue && hasProposalCue {
                let strongCompletionMarkers = ["i've ", "i have ", "i already ", "i just "]
                let hasStrongCompletion = strongCompletionMarkers.contains { msgLower.contains($0) }

                if hasStrongCompletion && payload.disposition != "completion" {
                    log.info("Mixed case: preferring completion (strong past-perfect marker found)")

                    return TimelineSummaryResult(
                        summary: summary,
                        isCompletion: true,
                        isDirective: false,
                        disposition: "completion"
                    )
                }
            }

            // Note: "let me" with analysis verbs (analyze, calculate, read) is intentionally
            // NOT overridden because investigation/calculation completes when done.
            // Example: "Let me analyze the logs" → "analyzed" is correct.

        } else if kind == .user {
            // NEW: User message validation (parity with assistant)
            let autoIntent = classifyUserIntent(message)
            let s = summary.lowercased()

            // Validate prefix matches detected intent (with reasonable alternatives)
            // Note: Accept semantically correct alternatives rather than enforcing exact phrasing
            let prefixMatchesIntent: Bool
            switch autoIntent {
            case .directive:
                // Accept: "You requested", "You asked", "You performed", "You executed", "You ran"
                prefixMatchesIntent = s.hasPrefix("you requested") ||
                                     s.hasPrefix("you asked") ||
                                     s.hasPrefix("you performed") ||
                                     s.hasPrefix("you executed") ||
                                     s.hasPrefix("you ran") ||
                                     s.hasPrefix("you invoked")
            case .question:
                prefixMatchesIntent = s.hasPrefix("you asked") || s.hasPrefix("you questioned")
            case .report:
                // Accept: "You informed", "You reported", "You mentioned", "You noted"
                prefixMatchesIntent = s.hasPrefix("you informed") ||
                                     s.hasPrefix("you reported") ||
                                     s.hasPrefix("you mentioned") ||
                                     s.hasPrefix("you noted")
            case .affirmative:
                prefixMatchesIntent = s.contains("proceed as proposed") ||
                                     s.contains("confirmed") ||
                                     s.contains("agreed")
            case .negative:
                prefixMatchesIntent = s.contains("not to proceed") ||
                                     s.contains("rejected") ||
                                     s.contains("declined")
            case .unknown:
                prefixMatchesIntent = true // Allow LLM to decide
            }

            if !prefixMatchesIntent {
                // Log for monitoring but don't fail - accept reasonable semantic alternatives
                log.debug("User summary prefix alternative: intent=\(autoIntent.rawValue), summary=\(summary, privacy: .public)")
                // Don't throw - accept the summary
            }

            // Validate length
            if summary.count > 140 {
                log.warning("User summary too long: \(summary.count) chars")
                throw TimelineError.validationFailure(reason: "summary too long (\(summary.count) chars)")
            }

            // Detect placeholder leaks from LLM instructions (e.g., "[what]", "[action]")
            let placeholderPattern = #"\[(?:what|action|question|description|brief paraphrase)\]"#
            if let _ = summary.range(of: placeholderPattern, options: .regularExpression) {
                log.warning("User summary contains placeholder text: \(summary, privacy: .public)")
                throw TimelineError.validationFailure(reason: "placeholder leak in summary")
            }

            // Validate leakage (skip for high-confidence fast-path results)
            // Fast-path summaries (confidence >= 0.9, grounded) are pre-approved and may intentionally
            // reference command names or specific terms from the input
            let isFastPath = payload.confidence >= 0.9 && payload.grounding.lowercased() == "grounded"
            if !isFastPath {
                let leaked = introducedTopics(message: message, summary: summary)
                if leaked.count > 6 {
                    log.warning("User summary has excessive leakage: \(leaked.count) tokens: \(leaked.joined(separator: ", "), privacy: .public)")
                    throw TimelineError.validationFailure(reason: "excessive token leakage (\(leaked.count) tokens)")
                }
            }

            // Validate confidence/grounding
            if payload.confidence < 0.45 && payload.grounding.lowercased() != "grounded" {
                log.warning("User summary has low confidence (\(payload.confidence, privacy: .public)) and is not grounded")
                throw TimelineError.validationFailure(reason: "low confidence and ungrounded")
            }
        }

        let completion = kind == .assistant
            ? (payload.isCompletion && hasCompletionToken(summary))
            : false

        // Set isDirective based on classified intent for user messages
        let directiveFlag: Bool
        if kind == .user {
            let intent = classifyUserIntent(message)
            directiveFlag = intent == .directive || intent == .affirmative || intent == .negative
        } else {
            directiveFlag = false
        }

        return TimelineSummaryResult(summary: summary, isCompletion: completion, isDirective: directiveFlag, disposition: payload.disposition)
    }
}
#endif

#if DEBUG
extension FoundationLLM {
    func _testSanitize(_ summary: String, kind: TimelineEntryKind) async -> String {
        sanitize(summary, kind: kind)
    }

    func _testClassifyUserIntent(_ text: String) async -> UserIntent {
        classifyUserIntent(text)
    }

    func _testStripQuotedAndCode(_ text: String) async -> String {
        stripQuotedAndCode(text)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func _testPostProcess(kind: TimelineEntryKind, payload: GuidedTimelineSummary, message: String) throws -> TimelineSummaryResult {
        try postProcess(kind: kind, payload: payload, message: message)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func _testTimelineSummary(message: String, kind: TimelineEntryKind = .assistant, provider: TimelineSourceContext.Provider? = nil) async throws -> TimelineSummaryResult {
        return try await summarizeTimeline(kind: kind, text: message, provider: provider)
    }
    #endif
}
#endif

// MARK: - Generic LLM Helpers (unified client for all use cases)

#if canImport(FoundationModels)
@available(macOS 26.0, *)
extension FoundationLLM {
    /// Generate guided JSON output using any @Generable schema
    /// All calls are serialized through SessionController (single-flight per instruction key)
    ///
    /// - Parameters:
    ///   - instructions: System instructions for the LLM
    ///   - prompt: User prompt
    ///   - generating: Type conforming to @Generable
    ///   - includeSchema: Whether to include JSON schema (default: true)
    ///   - options: Generation options (temperature, max tokens, etc.)
    ///   - sessionId: Optional session identifier for per-transcript isolation
    ///   - recordHistory: Whether to record this call in session history (default: true, use false for ephemeral pre-flight)
    public func generateGuided<T: Generable & Sendable>(
        instructions: String,
        prompt: String,
        generating: T.Type,
        includeSchema: Bool = true,
        options: GenerationOptions,
        sessionId: String? = nil,
        recordHistory: Bool = true
    ) async throws -> T {
        let controller = await getController(for: instructions, sessionId: sessionId)
        return try await controller.generate(
            prompt,
            generating: T.self,
            includeSchema: includeSchema,
            options: options,
            recordHistory: recordHistory
        )
    }

    /// Raw (non-JSON) generation with custom instructions
    ///
    /// **Use Cases:**
    /// - Plain text generation where structured JSON is not needed (e.g., SynthesisService)
    /// - Debugging decoding failures to inspect raw LLM output
    ///
    /// **IMPORTANT:** Do NOT use this for pre-flight validation when the actual call uses
    /// `generateGuided()` with `includeSchema: true`. The schema adds ~150-200 tokens of overhead
    /// that raw generation doesn't account for, causing the actual call to exceed context limits
    /// even when pre-flight passes.
    ///
    /// **Recommended Pattern:**
    /// - If your actual call uses `generateGuided()` → use `generateGuided()` for pre-flight too
    /// - If you need plain text output → use `rawWithInstructions()`
    ///
    /// See TranscriptContextFitting.swift for correct pre-flight implementation.
    public func rawWithInstructions(
        instructions: String,
        prompt: String,
        options: GenerationOptions
    ) async throws -> String {
        let controller = await getController(for: instructions)
        return try await controller.raw(prompt, options: options)
    }
}
#endif
