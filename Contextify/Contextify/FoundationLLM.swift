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

    var isRetryable: Bool {
        switch self {
        case .llmTimeout, .databaseError, .unexpected: return true
        case .contextOverflow, .guardrailViolation, .decodingFailure, .cancelled: return false
        }
    }

    var userMessage: String {
        switch self {
        case .llmTimeout:
            return "Summary generation timed out. Please try again."
        case .contextOverflow(let tokens, let limit):
            return "Message too long (\(tokens) tokens, limit \(limit))."
        case .guardrailViolation:
            return "Content could not be summarized due to safety filters."
        case .decodingFailure:
            return "Summary format was invalid."
        case .databaseError(let msg):
            return "A database error occurred: \(msg)"
        case .unexpected(let msg):
            return "An unexpected error occurred: \(msg)"
        case .cancelled:
            return "Operation was cancelled."
        }
    }
}

// SHA256 hex helper
extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
    func hexPrefix(_ length: Int) -> String {
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

    @available(macOS 26.0, *)
    private var controllers: [String: ControllerEntry] = [:]
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
    func setForceStateless(_ enabled: Bool) {
        #if canImport(FoundationModels)
        forceStatelessMode = enabled
        controllers.removeAll()  // Clear cache to force recreation with new setting
        log.info("ForceStateless mode \(enabled ? "enabled" : "disabled") - cleared controller cache")
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
        if !result.contains("```") && !result.contains("\"\"\"") && !result.contains(">") && !result.contains("`") {
            return collapseWhitespace(result)
        }

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
        let normalized = clean.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

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

            let negatives = ["no", "nope", "nah", "not", "now", "hold", "off", "stop", "don't", "cancel", "abort"]
            let allNegative = tokens.allSatisfy { negatives.contains($0) }
            if allNegative { return .negative }
        }

        // Check for directive patterns (request phrases)
        let directivePatterns = ["can you", "could you", "would you", "please", "see if you can", "help me", "let's", "we should", "i need"]
        for pattern in directivePatterns {
            if normalized.contains(pattern) { return .directive }
        }

        // Separate "i want to know" (question) from general "i want" (directive)
        if normalized.contains("i want to know") { return .question }
        if normalized.contains("i want") { return .directive }

        // Check for imperative verbs at start
        let firstWord = tokens.first ?? ""
        let imperatives: Set<String> = [
            "commit", "fix", "run", "update", "add", "create", "test", "build", "deploy",
            "write", "explain", "show", "make", "delete", "remove", "check", "refactor",
            "optimize", "implement", "modify", "debug", "install", "configure"
        ]
        if imperatives.contains(firstWord) { return .directive }

        // Check for question patterns
        let questionWords = ["what", "why", "how", "when", "where", "which", "who"]
        if questionWords.contains(where: { normalized.hasPrefix($0) }) { return .question }
        if normalized.hasSuffix("?") { return .question }

        // Check for past-tense self-reports
        let reportPatterns = ["i updated", "i fixed", "i created", "i modified", "i changed", "i added"]
        for pattern in reportPatterns {
            if normalized.contains(pattern) { return .report }
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
                if #available(macOS 26.0, *) {
                    await resetSession(kind: kind, provider: provider)
                    log.info("Reset session before retry \(attempt)")
                }

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
            } else if kind == .user {
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

                    // Detect directive
                    if kind == .user, isDirective(message) {
                        result = TimelineSummaryResult(summary: result.summary, isCompletion: false, isDirective: true, disposition: result.disposition)
                        log.debug("[\(reqNum)] timeline: user directive detected")
                    }

                    log.debug("[\(reqNum)] timeline: FINAL summary after postProcess: '\(result.summary, privacy: .public)'")
                    // Record success
                    metrics.total += 1
                    return result
                } catch Error.retryExhausted {
                    // postProcess rejected - don't retry, just propagate up
                    metrics.total += 1
                    metrics.failed += 1
                    log.error("[\(reqNum)] postProcess rejection - propagating failure without retry")
                    throw Error.retryExhausted
                } catch {
                    // Other postProcess errors
                    metrics.total += 1
                    metrics.failed += 1
                    log.error("[\(reqNum)] postProcess unexpected error: \(error)")
                    throw Error.retryExhausted
                }
            } catch Error.retryExhausted {
                // Already exhausted from postProcess - just propagate
                throw Error.retryExhausted
            } catch let guarded as LanguageModelSession.GenerationError {
                metrics.total += 1
                metrics.failed += 1
                log.error("[\(reqNum)] timeline summarize guardrail triggered: \(String(describing: guarded), privacy: .public)")

                // Map FoundationModels errors to TimelineError
                switch guarded {
                case .exceededContextWindowSize(let context):
                    let info = Self.parseOverflow(from: context.debugDescription) ?? (tokens: 4097, limit: 4096)
                    await controller.reset()
                    throw TimelineError.contextOverflow(tokens: info.tokens, limit: info.limit)

                case .guardrailViolation(let context):
                    await controller.reset()
                    throw TimelineError.guardrailViolation(reason: context.debugDescription)

                case .decodingFailure(let context):
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
            verbLemma: nil  // TODO: LLM should provide this in Phase 2
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
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

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
        epoch &+= 1
        log.info("Reset LanguageModelSession for instructions key (\(self.instructions.prefix(24), privacy: .public))… (epoch \(self.epoch))")
    }

    private func acquire() async {
        if !inFlight {
            inFlight = true                                     // fast path gets the token
            return
        }

        // Enqueue waiter in FIFO order
        let id = UUID()
        try? await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waitOrder.append(id)
                waiters[id] = cont
            }
        } onCancel: {
            // Do NOT call release() here - just remove from queue
            Task {
                await self.cancelWaiter(id)
            }
        }
        // NOTE: do NOT set inFlight here - still held by current owner
    }

    private func cancelWaiter(_ id: UUID) {
        if let idx = waitOrder.firstIndex(of: id) {
            waitOrder.remove(at: idx)
        }
        waiters.removeValue(forKey: id)
        // Cancelled waiter is dropped; current holder keeps the token
    }

    private func release() {
        // Give token to the next non-cancelled waiter or mark idle
        while let id = waitOrder.first {
            waitOrder.removeFirst()
            if let cont = waiters.removeValue(forKey: id) {
                cont.resume()
                return                                      // token stays inFlight for resumed waiter
            }
        }
        inFlight = false                                     // no waiters → idle
    }

    func generate<T: Generable>(
        _ prompt: String,
        generating: T.Type,
        includeSchema: Bool,
        options: GenerationOptions
    ) async throws -> T {
        await acquire()
        defer { release() }

        if forceStateless { reset() }

        do {
            let s = try getOrCreateSession()
            let resp = try await s.respond(
                to: prompt,
                generating: T.self,
                includeSchemaInPrompt: includeSchema,
                options: options
            )
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

    func raw(_ prompt: String, options: GenerationOptions) async throws -> String {
        await acquire()
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
                allowed: ["You made", "You asked", "You requested \(assistantName)"],
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
            You fill a TimelineSummary for an AI assistant response.

            Rules:
            - Output ONE sentence starting with "\(assistantName)", ≤140 chars.
            - Use only MESSAGE content; do not introduce topics absent from MESSAGE.
            - Tense:
              * Past when completion is explicitly reported (done/✅/completed/fixed/resolved/merged/wrote/saved).
              * Present continuous ONLY for clear in-progress execution (e.g., “is running the test suite”).
              * Otherwise simple present (“explains/clarifies/confirms/proposes/asks/acknowledges”).
            - Mention tools (Write/Edit/Read/Bash/etc.) ONLY if MESSAGE explicitly says they were executed.

            Fields:
            - summary: one sentence following the rules.
            - isCompletion: true only if MESSAGE explicitly indicates completion.
            - disposition: one of ack, completion, wip, analysis, proposal, question, refusal.
            - grounding: grounded | ungrounded | insufficient.
            - confidence: 0.0–1.0 (lower for short or ungrounded inputs).

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
            - QUESTION    → "You asked [question]"
            - REPORT      → "You made [description]"
            - AFFIRMATIVE → "You requested \(assistantName) to proceed as proposed."
            - NEGATIVE    → "You requested \(assistantName) not to proceed."
            - UNKNOWN     → "You requested \(assistantName) to [infer from message]"

            Rules:
            - MESSAGE has already been preprocessed to remove code blocks, quotes, and blockquotes
            - If ACTION_HINT is present, it provides context but should NOT appear in the summary text
            - Use past-tense verb in the prefix ("requested", "asked", "made")
            - Focus on user's intent, not implementation details

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
            return Set(filtered.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 3 })
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

            // Instruction-derived words
            "infer", "proceed", "proposed",

            // Common prepositions and conjunctions
            "about", "from", "during", "with", "for", "and", "the", "that", "this", "these", "those",
            "regarding", "concerning", "without", "into", "onto", "upon",

            // Generic action/context words that legitimately appear in summaries
            "options", "types", "handling", "transitions", "moving", "changes", "updates",
            "message", "messages", "logs", "issues", "errors", "them", "perhaps"
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

    func isDirective(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Detect command/directive patterns
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
            "i need", "help me", "figure out"
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
private extension FoundationLLM {
    // Controllers now moved to actor state (see top of FoundationLLM actor)

    func getController(for instructions: String) async -> SessionController {
        if let entry = controllers[instructions] {
            // Update last-used timestamp
            controllers[instructions]?.lastUsed = .now
            return entry.controller
        }
        let controller = SessionController(instructions: instructions, forceStateless: forceStatelessMode)
        controllers[instructions] = ControllerEntry(controller: controller, lastUsed: .now)
        await evictIdleControllers()
        return controller
    }

    /// Evict idle controllers to prevent unbounded growth
    /// Default: 5 min idle timeout, max 16 total controllers
    func evictIdleControllers(maxIdle: TimeInterval = 300, maxTotal: Int = 16) async {
        let cutoff = Date().addingTimeInterval(-maxIdle)

        // Remove idle controllers
        controllers = controllers.filter { $0.value.lastUsed > cutoff }

        // Evict oldest if still over capacity
        if controllers.count > maxTotal {
            let victims = controllers.sorted { $0.value.lastUsed < $1.value.lastUsed }
                                     .prefix(controllers.count - maxTotal)
                                     .map(\.key)
            for key in victims {
                controllers.removeValue(forKey: key)
            }
        }
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
            let grounding = payload.grounding.lowercased()
            let isGrounded = grounding == "grounded"

            // Multi-factor acceptance decision:
            // Accept if ANY of:
            // 1. Confidence ≥0.6 - trust the model when it's reasonably confident
            // 2. Low leakage (<8 tokens) with OK confidence (≥0.5)
            // 3. Grounded with any confidence ≥0.4
            // This is VERY permissive because the LLM is generally good
            let goodConfidence = payload.confidence >= 0.6
            let okConfidence = payload.confidence >= 0.5
            let minimalConfidence = payload.confidence >= 0.4
            let excessiveLeakage = leaked.count >= 8

            let shouldAccept = goodConfidence ||
                               (okConfidence && !excessiveLeakage) ||
                               (isGrounded && minimalConfidence)
            let shouldReject = !shouldAccept

            if shouldReject {
                log.warning("timeline summary REJECTED (grounding=\(grounding), leaked=\(leaked.count), confidence=\(payload.confidence, privacy: .public)): \(leaked.joined(separator: ", "), privacy: .public)")
                // Special case: if it's just an ack, accept the generic ack message
                let assistantName = provider?.displayName ?? "Claude Code"
                if isAck(message) {
                    return TimelineSummaryResult(summary: "\(assistantName) acknowledges the request.", isCompletion: false, isDirective: false, disposition: "ack")
                }
                // Reject but DON'T retry - it won't help since input doesn't change
                log.error("NOT retrying - postProcess rejection won't change with same input")
                throw Error.retryExhausted  // Skip straight to exhausted
            }

            if !isGrounded && leaked.count > 0 {
                log.debug("timeline summary ACCEPTED despite leakage (grounding=\(grounding), leaked=\(leaked.count), confidence=\(payload.confidence, privacy: .public))")
            }
        } else if kind == .user {
            // NEW: User message validation (parity with assistant)
            let autoIntent = classifyUserIntent(message)
            let s = summary.lowercased()

            // Validate prefix matches detected intent
            let prefixMatchesIntent: Bool
            switch autoIntent {
            case .directive:
                prefixMatchesIntent = s.hasPrefix("you requested")
            case .question:
                prefixMatchesIntent = s.hasPrefix("you asked")
            case .report:
                prefixMatchesIntent = s.hasPrefix("you made")
            case .affirmative:
                prefixMatchesIntent = s.contains("proceed as proposed")
            case .negative:
                prefixMatchesIntent = s.contains("not to proceed")
            case .unknown:
                prefixMatchesIntent = true // Allow LLM to decide
            }

            if !prefixMatchesIntent {
                log.warning("User summary prefix mismatch: intent=\(autoIntent.rawValue), summary=\(summary, privacy: .public)")
                throw Error.retryExhausted
            }

            // Validate length
            if summary.count > 140 {
                log.warning("User summary too long: \(summary.count) chars")
                throw Error.retryExhausted
            }

            // Validate leakage
            let leaked = introducedTopics(message: message, summary: summary)
            if leaked.count > 6 {
                log.warning("User summary has excessive leakage: \(leaked.count) tokens: \(leaked.joined(separator: ", "), privacy: .public)")
                throw Error.retryExhausted
            }

            // Validate confidence/grounding
            if payload.confidence < 0.45 && payload.grounding.lowercased() != "grounded" {
                log.warning("User summary has low confidence (\(payload.confidence, privacy: .public)) and is not grounded")
                throw Error.retryExhausted
            }
        }

        let completion = kind == .assistant
            ? (payload.isCompletion && hasCompletionToken(summary))
            : false

        return TimelineSummaryResult(summary: summary, isCompletion: completion, isDirective: false, disposition: payload.disposition)
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
    #endif
}
#endif
