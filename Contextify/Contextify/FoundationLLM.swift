import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
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

    func summarizeTimeline(kind: TimelineEntryKind, text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback(for: kind, text: text) }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard isAvailable() else { return fallback(for: kind, text: trimmed) }

            do {
                let instructions = instructionsForTimeline(kind: kind)
                let session = LanguageModelSession(instructions: instructions)
                let options = GenerationOptions(
                    sampling: .greedy,
                    temperature: 0.2,
                    maximumResponseTokens: 96
                )
                let clamped = String(trimmed.prefix(1200))
                let response = try await session.respond(to: clamped, options: options)
                let cleaned = stripCodeFence(from: response.content)

                // Check if LLM refused the request
                let refusalPatterns = ["cannot assist", "i apologize", "i'm sorry", "i can't"]
                let lowerResponse = cleaned.lowercased()
                if refusalPatterns.contains(where: { lowerResponse.contains($0) }) {
                    log.warning("LLM refused summarization request. Response: '\(cleaned, privacy: .public)' | Original text: '\(String(clamped.prefix(200)), privacy: .public)'")
                    return fallback(for: kind, text: trimmed)
                }

                // Strip preambles like "Sure, here's a possible response:", "Here's the summary:", etc.
                let final = stripPreamble(from: cleaned)
                return final.isEmpty ? fallback(for: kind, text: trimmed) : final
            } catch {
                log.error("timeline summarize failed: \(error.localizedDescription, privacy: .public)")
                return fallback(for: kind, text: trimmed)
            }
        }
        #endif

        return fallback(for: kind, text: trimmed)
    }
}

private extension FoundationLLM {
    func fallback(for kind: TimelineEntryKind, text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix: String
        switch kind {
        case .user: prefix = "You requested Claude"
        case .assistant: prefix = "Claude"
        case .system: prefix = "System"
        }
        guard !normalized.isEmpty else { return prefix }
        if normalized.count <= 160 { return "\(prefix) \(normalized)" }
        let snippet = normalized.prefix(157)
        return "\(prefix) \(snippet)…"
    }

    func instructionsForTimeline(kind: TimelineEntryKind) -> String {
        switch kind {
        case .user:
            return """
            You summarize a developer’s message for a timeline.

            Output: ONE past-tense sentence starting with “You requested Claude”, ≤110 chars.

            If the message is a bare affirmative (yes/ok/sure/y/👍/go ahead/proceed/do it/please do/sgtm/roger):
              → “You requested Claude to proceed as proposed.”
            If it’s a bare negative (no/not now/hold off/stop/don’t):
              → “You requested Claude not to proceed.”
            Otherwise, summarize the explicit request in past tense. Mention tools only if explicitly requested.
            """
        case .assistant:
            return """
            You summarize an AI assistant’s response for a conversation timeline.

            Rules:
            - Output ONE sentence starting with “Claude”, ≤110 chars, nothing else.
            - Tense priority:
              (1) Past if conclusive tokens: Done, ✅, Completed, Build succeeded, Wrote/Saved/Applied.
              (2) Present continuous ONLY for clear in-progress execution (e.g., “Running Bash(…)”, streaming logs).
              (3) Simple present for analysis/confirmation/proposal/Q&A: “explains/clarifies/confirms/proposes/asks/summarizes”.
              (4) If still unclear, use present continuous.
            - Tool names (Write()/Edit()/Read()/Bash()) ONLY if the response says they were executed. Ignore mere mentions.
            - Prefer concrete subjects (“backfill logic”, “timeline parser”) over vague verbs.

            Examples:
            [Input]
            "✅ Done. Build succeeded. Wrote /tmp/out.md (12 lines)."
            [Output]
            Claude wrote /tmp/out.md after a successful build.

            [Input]
            "Running Bash('pytest -q')… 38%… collecting…"
            [Output]
            Claude is running Bash('pytest -q').

            [Input]
            "Yes, confirmed. The current logic takes the last 5 lines… Would you like me to change it to ensure 5 displayable entries?"
            [Output]
            Claude explains backfill counts raw lines and asks to ensure five displayable entries.

            [Input]
            "Tool calls are skipped; we could use Edit('/foo') later."
            [Output]
            Claude proposes using displayable-entry counting and notes tool calls are skipped.

            [Input]
            "OK."
            [Output]
            Claude acknowledges the request.
            """
        case .system:
            return """
            You are summarizing a system event for a timeline. This is a neutral, informational task.
            Create one concise sentence under 110 characters. Output only the summary sentence, nothing else.
            """
        }
    }

    func stripCodeFence(from response: String) -> String {
        var output = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.hasPrefix("```") else { return output }
        output.removeFirst(3)
        if let newline = output.firstIndex(of: "\n") {
            output = String(output[output.index(after: newline)...])
        }
        if let closing = output.range(of: "```", options: .backwards) {
            output.removeSubrange(closing.lowerBound..<output.endIndex)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
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
