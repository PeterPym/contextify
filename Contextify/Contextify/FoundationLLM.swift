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
            guard await isAvailable() else { return fallback(for: kind, text: trimmed) }

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
            You are summarizing a developer's message for a conversation timeline. This is a neutral, informational task.
            Create one past-tense sentence starting with "You requested Claude" describing what was asked.
            Keep under 110 characters. Mention files/commands if relevant. Output only the summary sentence, nothing else.
            """
        case .assistant:
            return """
            You are summarizing an AI assistant's response for a conversation timeline. This is a neutral, informational task.
            Create one concise sentence starting with "Claude" that describes the action.

            Use appropriate tense based on the content:
            - If the response contains conclusive language like "Done", "✅", "Build succeeded", "Completed", use past tense: "Claude wrote to /tmp/file.md"
            - If the response shows in-progress actions or tool calls being made, use present continuous: "Claude is editing the parser"
            - If unclear, default to present continuous for safety

            If the response mentions tools like Write(), Edit(), Read(), Bash(), include the tool name and target.
            Keep under 110 characters. Output only the summary sentence, nothing else.
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
