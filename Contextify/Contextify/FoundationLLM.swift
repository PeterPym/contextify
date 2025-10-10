import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

actor FoundationLLM {
    static let shared = FoundationLLM()

    private let log = Logger(subsystem: "dev.contextify", category: "FoundationLLM")
    private var requestCount = 0
    private var failureCount = 0
    private var lastRequestTime: Date?

    // Throttle to prevent overwhelming the LLM
    private let minRequestInterval: TimeInterval = 0.15 // 150ms between requests

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
    func stripQuotedAndCode(_ text: String) -> String {
        var result = text

        // Remove fenced code blocks (```...```)
        result = result.replacingOccurrences(
            of: #"```[\s\S]*?```"#,
            with: "",
            options: .regularExpression
        )

        // Remove inline code (`...`)
        result = result.replacingOccurrences(
            of: #"`[^`]+`"#,
            with: "",
            options: .regularExpression
        )

        // Remove triple-quoted strings ("""...""")
        result = result.replacingOccurrences(
            of: #""{3}[\s\S]*?"{3}"#,
            with: "",
            options: .regularExpression
        )

        // Remove blockquotes (> ...)
        // Use NSRegularExpression for multiline matching
        if let regex = try? NSRegularExpression(pattern: #"^>\s*.*$"#, options: [.anchorsMatchLines]) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "")
        }

        return collapseWhitespace(result)
    }

    /// Authoritatively classify user intent using deterministic rules
    func classifyUserIntent(_ text: String) -> UserIntent {
        let clean = stripQuotedAndCode(text)
        let normalized = clean.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Gate for short utterances (affirmative/negative)
        let tokens = normalized.split(separator: " ")
        if tokens.count <= 3 {
            let allAffirmative = tokens.allSatisfy {
                ["yes", "y", "ok", "okay", "sure", "👍", "yep", "go", "ahead", "proceed", "do", "it", "please", "sgtm", "roger"].contains(String($0))
            }
            if allAffirmative { return .affirmative }

            let allNegative = tokens.allSatisfy {
                ["no", "nope", "not", "now", "hold", "off", "stop", "don't", "cancel"].contains(String($0))
            }
            if allNegative { return .negative }
        }

        // Check for directive patterns (request phrases)
        let directivePatterns = ["can you", "could you", "would you", "please", "see if you can", "help me", "let's", "we should", "i want", "i need"]
        for pattern in directivePatterns {
            if normalized.contains(pattern) { return .directive }
        }

        // Check for imperative verbs at start
        let firstWord = tokens.first.map(String.init) ?? ""
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

    func summarizeTimeline(
        kind: TimelineEntryKind,
        text: String,
        actionHint: String? = nil,
        retryCount: Int = 0
    ) async throws -> TimelineSummaryResult {
        let maxRetries = 3
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
                if retryCount == 0 {
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
            if kind == .assistant, isAck(message) {
                log.debug("[\(reqNum)] timeline: ack detected, using fast path")
                let fp = GuidedTimelineSummary(
                    summary: "Claude acknowledges the request.",
                    isCompletion: false,
                    disposition: "ack",
                    grounding: "grounded",
                    confidence: 0.95
                )
                var result = try postProcess(kind: kind, payload: fp, message: message)
                result = TimelineSummaryResult(summary: result.summary, isCompletion: result.isCompletion, isDirective: false, disposition: "ack")
                return result
            } else if kind == .user {
                let intent = classifyUserIntent(message)

                // Fast path for affirmative/negative
                if intent == .affirmative {
                    log.debug("[\(reqNum)] timeline: affirmative detected, using fast path")
                    let fp = GuidedTimelineSummary(
                        summary: "You requested Claude to proceed as proposed.",
                        isCompletion: false,
                        disposition: "affirmative",
                        grounding: "grounded",
                        confidence: 0.95
                    )
                    var result = try postProcess(kind: kind, payload: fp, message: message)
                    result = TimelineSummaryResult(summary: result.summary, isCompletion: result.isCompletion, isDirective: true, disposition: "affirmative")
                    return result
                } else if intent == .negative {
                    log.debug("[\(reqNum)] timeline: negative detected, using fast path")
                    let fp = GuidedTimelineSummary(
                        summary: "You requested Claude not to proceed.",
                        isCompletion: false,
                        disposition: "negative",
                        grounding: "grounded",
                        confidence: 0.95
                    )
                    var result = try postProcess(kind: kind, payload: fp, message: message)
                    result = TimelineSummaryResult(summary: result.summary, isCompletion: result.isCompletion, isDirective: true, disposition: "negative")
                    return result
                }
            }

            let instructions = instructionsForTimeline(kind: kind)
            let session = LanguageModelSession(instructions: instructions)

            // Use slight temperature on retries to help unstick from bad states
            let temperature = retryCount > 0 ? 0.1 : 0.0
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
                if retryCount == 0 {
                    log.debug("[\(reqNum)] timeline: requesting LLM summary (retry \(retryCount)/\(maxRetries))")
                } else {
                    log.warning("[\(reqNum)] timeline: requesting LLM summary (retry \(retryCount)/\(maxRetries))")
                }
                log.debug("[\(reqNum)] input: \(payloadInput, privacy: .public)")

                let response = try await session.respond(
                    to: payloadInput,
                    generating: GuidedTimelineSummary.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                let payload = response.content
                log.debug("[\(reqNum)] timeline: LLM SUCCESS - grounding=\(payload.grounding), confidence=\(String(format: "%.2f", payload.confidence)), disposition=\(payload.disposition), isCompletion=\(payload.isCompletion)")
                log.debug("[\(reqNum)] timeline: raw summary from LLM: '\(payload.summary, privacy: .public)'")
                do {
                    var result = try postProcess(kind: kind, payload: payload, message: clamped)

                    // Detect directive
                    if kind == .user, isDirective(message) {
                        result = TimelineSummaryResult(summary: result.summary, isCompletion: false, isDirective: true, disposition: result.disposition)
                        log.debug("[\(reqNum)] timeline: user directive detected")
                    }

                    log.debug("[\(reqNum)] timeline: FINAL summary after postProcess: '\(result.summary, privacy: .public)'")
                    // Reset failure count on success
                    failureCount = 0
                    return result
                } catch Error.retryExhausted {
                    // postProcess rejected - don't retry, just propagate up
                    failureCount += 1
                    log.error("[\(reqNum)] postProcess rejection - propagating failure without retry")
                    throw Error.retryExhausted
                } catch {
                    // Other postProcess errors
                    failureCount += 1
                    log.error("[\(reqNum)] postProcess unexpected error: \(error)")
                    throw Error.retryExhausted
                }
            } catch Error.retryExhausted {
                // Already exhausted from postProcess - just propagate
                throw Error.retryExhausted
            } catch let guarded as LanguageModelSession.GenerationError {
                failureCount += 1
                log.error("[\(reqNum)] timeline summarize guardrail triggered: \(String(describing: guarded), privacy: .public)")

                // Log the actual error context for debugging
                switch guarded {
                case .decodingFailure(let context):
                    log.error("[\(reqNum)] DECODING FAILURE: \(context.debugDescription, privacy: .public)")
                    log.error("[\(reqNum)] We sent this input: \(payloadInput, privacy: .public)")
                    log.error("[\(reqNum)] Expected schema: {summary: String, isCompletion: Bool, disposition: String, grounding: String, confidence: Double}")

                    // Try to get raw response for debugging (makes second LLM call but only on failure)
                    do {
                        let rawResponse = try await session.respond(to: payloadInput, options: options)
                        log.error("[\(reqNum)] LLM actually returned (raw): \(rawResponse.content, privacy: .public)")
                    } catch {
                        log.error("[\(reqNum)] Could not fetch raw response: \(error.localizedDescription, privacy: .public)")
                    }
                default:
                    log.error("[\(reqNum)] Other generation error: \(String(describing: guarded), privacy: .public)")
                }

                // Check if we're hitting too many failures in a row
                if failureCount >= 10 {
                    log.error("[\(reqNum)] Too many consecutive failures (\(self.failureCount)), LLM may be overloaded. Backing off longer...")
                    // Longer backoff when system is struggling
                    if retryCount < maxRetries {
                        let backoff = UInt64(pow(2.0, Double(retryCount + 2)) * 500_000_000) // 2s, 4s, 8s
                        log.warning("[\(reqNum)] Extended retry after \(backoff / 1_000_000)ms backoff...")
                        try await Task.sleep(nanoseconds: backoff)
                        return try await summarizeTimeline(kind: kind, text: text, actionHint: actionHint, retryCount: retryCount + 1)
                    }
                } else if retryCount < maxRetries {
                    let backoff = UInt64(pow(2.0, Double(retryCount)) * 500_000_000) // 0.5s, 1s, 2s
                    log.warning("[\(reqNum)] Retrying after \(backoff / 1_000_000)ms backoff...")
                    try await Task.sleep(nanoseconds: backoff)
                    return try await summarizeTimeline(kind: kind, text: text, actionHint: actionHint, retryCount: retryCount + 1)
                }

                log.error("[\(reqNum)] Retry exhausted after \(maxRetries) attempts, failing (total failures: \(self.failureCount))")
                throw Error.retryExhausted
            } catch {
                log.error("[\(reqNum)] timeline summarize unexpected error: \(error.localizedDescription, privacy: .public)")
                throw Error.retryExhausted
            }
        }
        #endif

        log.error("[\(reqNum)] timeline: FoundationModels not available (macOS < 26)")
        throw Error.unexpectedEnvironment
    }

    func fallbackSummary(kind: TimelineEntryKind, text: String) -> TimelineSummaryResult {
        let summary = sanitize(fallback(for: kind, text: text), kind: kind)
        return TimelineSummaryResult(summary: summary, isCompletion: false, isDirective: false, disposition: "unknown")
    }

    /// Generate dual-form (present + past) timeline summary for cache storage
    func summarizeTimelineWithForms(
        kind: TimelineEntryKind,
        text: String,
        contextWindow: [String] = []
    ) async throws -> TimelineSummaryWithForms {
        // Call existing LLM summarization
        let result = try await summarizeTimeline(kind: kind, text: text)

        // Parse disposition string to enum
        let disp = Disposition(rawValue: result.disposition) ?? .unknown

        // For now, use simple transformation to generate both forms
        // TODO: Phase 2 will have LLM generate both forms natively
        let present = result.summary
        let past = convertToPastTense(result.summary, disposition: disp)

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
    private func convertToPastTense(_ text: String, disposition: Disposition) -> String {
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

        // Pattern: "Claude is <verb>ing" → "Claude <verb>ed"
        if let regex = try? NSRegularExpression(pattern: #"^Claude is (\w+?)ing\b"#, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "Claude $1ed")
        }

        // Pattern: "Claude <verb>s" → "Claude <verb>ed" (only for safe verbs)
        let safeVerbs = ["proposes", "implements", "fixes", "adds", "creates", "updates", "modifies"]
        for verb in safeVerbs {
            if result.hasPrefix("Claude \(verb)") {
                let replacement = String(verb.dropLast()) + "ed"
                result = result.replacingOccurrences(of: "Claude \(verb)", with: "Claude \(replacement)")
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
#endif

private extension FoundationLLM {
    struct PrefixPolicy {
        let allowed: [String]
        let fallback: String
    }

    func fallback(for kind: TimelineEntryKind, text: String) -> String {
        let normalized = collapseWhitespace(text)
        let policy = prefixPolicy(for: kind)
        guard !normalized.isEmpty else { return policy.fallback }
        if hasAllowedPrefix(normalized, policy: policy) {
            return normalized
        }
        return "\(policy.fallback) \(normalized)"
    }

    func sanitize(_ summary: String, kind: TimelineEntryKind) -> String {
        var output = collapseWhitespace(summary)
        let policy = prefixPolicy(for: kind)
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

    func prefixPolicy(for kind: TimelineEntryKind) -> PrefixPolicy {
        switch kind {
        case .assistant:
            return PrefixPolicy(allowed: ["Claude"], fallback: "Claude")
        case .user:
            return PrefixPolicy(
                allowed: ["You made", "You asked", "You requested Claude"],
                fallback: "You requested Claude"
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


    func instructionsForTimeline(kind: TimelineEntryKind) -> String {
        switch kind {
        case .assistant:
            return """
            You fill a TimelineSummary for an AI assistant response.

            Rules:
            - Output ONE sentence starting with "Claude", ≤140 chars.
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
            - DIRECTIVE   → "You requested Claude to [action]"
            - QUESTION    → "You asked [question]"
            - REPORT      → "You made [description]"
            - AFFIRMATIVE → "You requested Claude to proceed as proposed."
            - NEGATIVE    → "You requested Claude not to proceed."
            - UNKNOWN     → "You requested Claude to [infer from message]"

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
    func postProcess(
        kind: TimelineEntryKind,
        payload: GuidedTimelineSummary,
        message: String
    ) throws -> TimelineSummaryResult {
        let summary = sanitize(payload.summary, kind: kind)

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
                if isAck(message) {
                    return TimelineSummaryResult(summary: "Claude acknowledges the request.", isCompletion: false, isDirective: false, disposition: "ack")
                }
                // Reject but DON'T retry - it won't help since input doesn't change
                log.error("NOT retrying - postProcess rejection won't change with same input")
                throw Error.retryExhausted  // Skip straight to exhausted
            }

            if !isGrounded && leaked.count > 0 {
                log.info("timeline summary ACCEPTED despite leakage (grounding=\(grounding), leaked=\(leaked.count), confidence=\(payload.confidence, privacy: .public))")
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
