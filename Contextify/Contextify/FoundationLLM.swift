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
        let icon: String?  // Optional emoji prefix (✅, 👉, ❓, etc.)
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
                log.info("Throttling: sleeping \(Int(delay * 1000))ms before next request")
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

        // Check for simple acks - these can skip LLM
        if kind == .assistant, isAck(message) {
            log.info("[\(reqNum)] timeline: ack detected, skipping LLM")
            return TimelineSummaryResult(summary: "Claude acknowledges the request.", isCompletion: false, icon: nil)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                if retryCount == 0 {
                    log.info("[\(reqNum)] timeline: SystemLanguageModel available")
                }
                break
            case .unavailable:
                log.warning("[\(reqNum)] timeline: SystemLanguageModel unavailable")
                throw Error.unavailable
            @unknown default:
                log.warning("[\(reqNum)] timeline: SystemLanguageModel unknown availability")
                throw Error.unavailable
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
            let payloadInput: String
            if kind == .user,
               let hint = actionHint?.trimmingCharacters(in: .whitespacesAndNewlines),
               !hint.isEmpty {
                let safeHint = String(hint.prefix(300))
                payloadInput = "MESSAGE:\n<<<\(clamped)>>>\nACTION_HINT:\n<<<\(safeHint)>>>"
            } else {
                payloadInput = "MESSAGE:\n<<<\(clamped)>>>"
            }

            do {
                log.info("[\(reqNum)] timeline: requesting LLM summary (retry \(retryCount)/\(maxRetries))")
                log.info("[\(reqNum)] input: \(payloadInput, privacy: .public)")

                let response = try await session.respond(
                    to: payloadInput,
                    generating: GuidedTimelineSummary.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                let payload = response.content
                log.info("[\(reqNum)] timeline: LLM SUCCESS - grounding=\(payload.grounding), confidence=\(String(format: "%.2f", payload.confidence)), disposition=\(payload.disposition), isCompletion=\(payload.isCompletion)")
                log.info("[\(reqNum)] timeline: raw summary from LLM: '\(payload.summary, privacy: .public)'")
                do {
                    var result = try postProcess(kind: kind, payload: payload, message: clamped)

                    // Detect completion and add icon
                    if result.isCompletion {
                        result = TimelineSummaryResult(summary: result.summary, isCompletion: true, icon: "✅")
                        log.info("[\(reqNum)] timeline: completion detected, adding ✅ icon")
                    } else if kind == .user, isDirective(message) {
                        result = TimelineSummaryResult(summary: result.summary, isCompletion: false, icon: "👉")
                        log.info("[\(reqNum)] timeline: user directive detected, adding 👉 icon")
                    }

                    log.info("[\(reqNum)] timeline: FINAL summary after postProcess: '\(result.summary, privacy: .public)'")
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
        return TimelineSummaryResult(summary: summary, isCompletion: false, icon: nil)
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

    @Guide(description: "Assistant disposition: ack, completion, wip, analysis, proposal, question, refusal.")
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
            output = String(output.prefix(140))
        }
        return output
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
            You fill a TimelineSummary for a developer’s message.

            summary rules:
            - ONE sentence, ≤140 chars, past tense.
            - Allowed prefixes:
              • “You made …” — user reports a completed action (e.g., “I updated the file”).
              • “You asked …” — user asks a question (e.g., “Can you explain?”).
              • “You requested Claude …” — user asks Claude to act (e.g., “Fix this”, “Run tests”).
            - Special cases:
              • Bare affirmative (yes/ok/sure/y/👍/go ahead/proceed/do it/please do/sgtm/roger):
                → “You requested Claude to proceed as proposed.”
              • Bare negative (no/not now/hold off/stop/don’t):
                → “You requested Claude not to proceed.”
            - If ACTION_HINT is present, treat it as the action being approved or rejected.

            Fields:
            - summary: one sentence following the rules.
            - isCompletion: false.

            Input format:
            MESSAGE:
            <<<user text>>>
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
            "claude", "explains", "explained", "explaining", "clarifies", "clarified", "clarifying",
            "states", "stated", "says", "said", "notes", "noted", "acknowledges", "acknowledged",
            "confirms", "confirmed", "reports", "reported", "outlines", "outlined", "highlights",
            "highlighted", "advises", "advised", "suggests", "suggested", "proposes", "proposed",
            "asks", "asked", "observes", "observed", "mentions", "mentioned", "reminds", "reminded",
            "recommends", "recommended", "describes", "described", "details", "detailed", "responds",
            "responded", "summarizes", "summarized", "states", "reports", "notes", "acknowledges"
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
            "i need", "help me"
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
                    return TimelineSummaryResult(summary: "Claude acknowledges the request.", isCompletion: false, icon: nil)
                }
                // Reject but DON'T retry - it won't help since input doesn't change
                log.error("NOT retrying - postProcess rejection won't change with same input")
                throw Error.retryExhausted  // Skip straight to exhausted
            }

            if !isGrounded && leaked.count > 0 {
                log.info("timeline summary ACCEPTED despite leakage (grounding=\(grounding), leaked=\(leaked.count), confidence=\(payload.confidence, privacy: .public))")
            }
        }

        let completion = kind == .assistant
            ? (payload.isCompletion && hasCompletionToken(summary))
            : false

        return TimelineSummaryResult(summary: summary, isCompletion: completion, icon: nil)
    }
}
#endif

#if DEBUG
extension FoundationLLM {
    func _testSanitize(_ summary: String, kind: TimelineEntryKind) async -> String {
        sanitize(summary, kind: kind)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func _testPostProcess(kind: TimelineEntryKind, payload: GuidedTimelineSummary, message: String) throws -> TimelineSummaryResult {
        try postProcess(kind: kind, payload: payload, message: message)
    }
    #endif
}
#endif
