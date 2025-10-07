import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

struct TimelineSummaryResult: Sendable {
    let summary: String
    let isCompletion: Bool
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 18.0, tvOS 18.0, visionOS 2.0, *)
@Generable(description: "Timeline summary metadata for HUD entries")
struct GuidedTimelineSummary {
    @Guide(description: "One sentence (≤110 chars) starting with the appropriate prefix.")
    var summary: String

    @Guide(description: "true when the assistant states the task is finished (done/fixed/completed). false otherwise." )
    var isCompletion: Bool
}
#endif

actor FoundationLLM {
    static let shared = FoundationLLM()

    private let log = Logger(subsystem: "dev.contextify", category: "FoundationLLM")
    private init() {}

    func isAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    func summarizeTimeline(
        kind: TimelineEntryKind,
        text: String,
        actionHint: String? = nil
    ) async -> TimelineSummaryResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TimelineSummaryResult(
                summary: sanitize(fallback(for: kind, text: text), kind: kind),
                isCompletion: false
            )
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 18.0, tvOS 18.0, visionOS 2.0, *) {
            guard isAvailable() else {
                return TimelineSummaryResult(
                    summary: sanitize(fallback(for: kind, text: trimmed), kind: kind),
                    isCompletion: false
                )
            }

            do {
                let instructions = instructionsForTimeline(kind: kind)
                let session = LanguageModelSession(instructions: instructions)
                let options = GenerationOptions(
                    sampling: .greedy,
                    temperature: 0.0,
                    maximumResponseTokens: 48
                )
                let clamped = String(trimmed.prefix(1200))
                let payloadInput: String
                if kind == .user, let hint = actionHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
                    payloadInput = "MESSAGE:\n\(clamped)\n\nACTION_HINT:\n\(hint)"
                } else {
                    payloadInput = clamped
                }

                let response = try await session.respond(
                    to: payloadInput,
                    generating: GuidedTimelineSummary.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                let payload = response.content

                let cleanedSummary = stripPreamble(from: payload.summary)
                let normalizedSummary = sanitize(cleanedSummary, kind: kind)
                if normalizedSummary.isEmpty {
                    return TimelineSummaryResult(
                        summary: sanitize(fallback(for: kind, text: trimmed), kind: kind),
                        isCompletion: false
                    )
                }

                let finalCompletion = kind == .assistant
                    ? (payload.isCompletion && hasCompletionSignal(in: normalizedSummary))
                    : false

                return TimelineSummaryResult(summary: normalizedSummary, isCompletion: finalCompletion)
            } catch let guardedError as LanguageModelSession.GenerationError {
                log.error("timeline summarize guardrail triggered: \(String(describing: guardedError), privacy: .public)")
                return TimelineSummaryResult(
                    summary: sanitize(fallback(for: kind, text: trimmed), kind: kind),
                    isCompletion: false
                )
            } catch {
                log.error("timeline summarize failed: \(error.localizedDescription, privacy: .public)")
                return TimelineSummaryResult(
                    summary: sanitize(fallback(for: kind, text: trimmed), kind: kind),
                    isCompletion: false
                )
            }
        }
        #endif

        return TimelineSummaryResult(
            summary: sanitize(fallback(for: kind, text: trimmed), kind: kind),
            isCompletion: false
        )
    }
}

private extension FoundationLLM {
    struct PrefixPolicy {
        let allowed: [String]
        let fallback: String
    }

    func fallback(for kind: TimelineEntryKind, text: String) -> String {
        let normalized = collapseWhitespace(text)
        let policy = prefixPolicy(for: kind)
        guard !normalized.isEmpty else { return policy.fallback }
        if policy.allowed.contains(where: { normalized.hasPrefix($0) }) {
            return normalized
        }
        return "\(policy.fallback) \(normalized)"
    }

    func sanitize(_ summary: String, kind: TimelineEntryKind) -> String {
        var normalized = collapseWhitespace(summary)

        let policy = prefixPolicy(for: kind)
        if normalized.isEmpty {
            normalized = policy.fallback
        } else if !policy.allowed.contains(where: { normalized.hasPrefix($0) }) {
            normalized = "\(policy.fallback) \(normalized)"
        }

        if normalized.count > 110 {
            normalized = String(normalized.prefix(110))
        }
        return normalized
    }

    func prefixPolicy(for kind: TimelineEntryKind) -> PrefixPolicy {
        switch kind {
        case .user:
            return PrefixPolicy(
                allowed: [
                    "You made",
                    "You asked",
                    "You requested Claude"
                ],
                fallback: "You requested Claude"
            )
        case .assistant:
            return PrefixPolicy(
                allowed: ["Claude"],
                fallback: "Claude"
            )
        case .system:
            return PrefixPolicy(
                allowed: ["System"],
                fallback: "System"
            )
        }
    }

    func hasCompletionSignal(in summary: String) -> Bool {
        let completionTokens = [
            "done", "completed", "complete", "fixed", "resolved", "finished", "ready", "shipped",
            "build succeeded", "wrote", "saved", "applied", "merged", "implemented", "processed",
            "updated", "ensured", "finalized", "✅"
        ]
        let lower = summary.lowercased()
        return completionTokens.contains { lower.contains($0) }
    }

    func collapseWhitespace(_ text: String) -> String {
        let parts = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    func instructionsForTimeline(kind: TimelineEntryKind) -> String {
        switch kind {
        case .user:
            return """
            You fill the fields of a TimelineSummary for a developer's message.

            summary rules:
            - Output ONE sentence, ≤110 chars, past tense.
            - Choose the appropriate prefix based on message type:
              • "You made" - user reports completing their own action (e.g., "I've made the change", "I updated the file", "I fixed the bug")
              • "You asked" - user asks a question (e.g., "What does this do?", "Can you explain?")
              • "You requested Claude" - user requests Claude to take action (e.g., "Fix this", "Update the parser", "Run tests")
            - Special cases:
              • Bare affirmative (yes/ok/sure/y/👍/go ahead/proceed/do it/please do/sgtm/roger):
                → "You requested Claude to proceed as proposed."
              • Bare negative (no/not now/hold off/stop/don't):
                → "You requested Claude not to proceed."
            - If ACTION_HINT text is provided, treat it as context for affirm/deny messages.

            Examples:
            Input: "I've made the change to the prompt."
            → "You made the change to the prompt."

            Input: "Can you explain how this works?"
            → "You asked how this works."

            Input: "Fix the build warnings"
            → "You requested Claude to fix the build warnings."

            Input format:
            MESSAGE:<newline>user text
            Optional ACTION_HINT:<newline>assistant proposal to reference for affirm/deny messages.

            isCompletion: Always false for user messages.
            """
        case .assistant:
            return """
            You fill the fields of a TimelineSummary for an AI assistant response.

            summary rules:
            - Output ONE sentence starting with “Claude”, ≤110 chars.
            - Use past tense whenever the assistant reports completion (tokens like done/fixed/completed/resolved/built ✅/"finished", etc.).
            - Use present continuous ONLY for clear in-progress execution (e.g., “is running the test suite”).
            - Otherwise use simple present ("explains", "confirms", "proposes", "asks").
            - Do not invent tool names. Mention tools (Write/Edit/Read/Bash/etc.) only if the MESSAGE explicitly says they were executed.
            - When the input mentions specific subjects (files, features, bugs), use those concrete nouns instead of vague verbs.

            isCompletion rules:
            - true when the assistant explicitly indicates work is done/completed/fixed/resolved/ready.
            - false for analysis, planning, questions, or work-in-progress updates.

            Examples:
            Input: “✅ Done. Build succeeded. Wrote /tmp/out.md (12 lines).”
            → summary: “Claude wrote /tmp/out.md after a successful build.”
            → isCompletion: true

            Input: “Running unit tests… 38%… collecting results…”
            → summary: “Claude is running the unit tests.”
            → isCompletion: false

            Input: “We should review the backfill logic for edge cases.”
            → summary: “Claude proposes reviewing the backfill logic for edge cases.”
            → isCompletion: false
            """
        case .system:
            return """
            You fill a TimelineSummary for a neutral system event.
            - summary: One concise sentence under 110 characters.
            - isCompletion: false.
            """
        }
    }

    func stripPreamble(from response: String) -> String {
        var output = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Common preamble patterns
        let preambles = [
            #"^Sure,?\s+here'?s?\s+(a\s+)?(possible\s+)?response:?\s*"??"#,
            #"^Here'?s?\s+(the\s+)?summary:?\s*"??"#,
            #"^Here'?s?\s+what\s+.+?:\s*"??"#,
            #"^The\s+summary\s+is:?\s*"??"#,
            #"^Let me\s+.+?:\s*"??"#
        ]

        for pattern in preambles {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                if let match = regex.firstMatch(in: output, range: range) {
                    if let matchRange = Range(match.range, in: output) {
                        output = String(output[matchRange.upperBound...])
                        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Remove leading quote if present
                        if output.hasPrefix("\"") {
                            output.removeFirst()
                        }
                        // Remove trailing quote if present
                        if output.hasSuffix("\"") {
                            output.removeLast()
                        }
                        break
                    }
                }
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
