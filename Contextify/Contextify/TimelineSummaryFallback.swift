//
//  TimelineSummaryFallback.swift
//  Contextify
//
//  Shared rule-based fallback generators for timeline summaries.
//  Used by both FoundationLLM (validation recovery) and TimelineCacheMissGenerator (decoding recovery).
//

import Foundation

/// Shared fallback generators for timeline summaries
/// All methods are nonisolated and safe to call from any actor context
enum TimelineSummaryFallback {
    // Note: maxFallbackLength is 120 (hard cap to prevent unbounded output)
    // Using inline constant due to Swift 6 actor isolation inference

    // Precompiled regex for issue/PR references (e.g., #1234)
    nonisolated private static let issueRefPattern = try! NSRegularExpression(pattern: #"#\d{1,6}"#)

    // MARK: - Public API

    /// Generate fallback summary for user messages
    /// - Parameters:
    ///   - message: The original user message
    ///   - assistantName: Display name of the assistant (e.g., "Claude Code")
    /// - Returns: A bounded, single-line summary
    nonisolated static func makeUserFallback(message: String, assistantName: String) -> String {
        let trimmed = collapseWhitespace(message)
        let msgLower = trimmed.lowercased()

        // Imperative commands: "run it", "do it", "fix it", "commit", "push"
        // Also handle "show" for display requests
        let commandVerbs = ["run", "do", "fix", "commit", "push", "build", "test", "deploy", "merge", "check", "show"]
        for verb in commandVerbs {
            if msgLower.hasPrefix(verb) || msgLower == verb {
                let topic = clipForSummary(msgLower, maxLength: 40)
                return "You asked \(assistantName) to \(topic)."
            }
        }

        // Questions: "how", "what", "why", "where", "when", "can you", "are you", "do you"
        if msgLower.hasPrefix("how") || msgLower.hasPrefix("what") || msgLower.hasPrefix("why") ||
           msgLower.hasPrefix("where") || msgLower.hasPrefix("when") || msgLower.hasPrefix("can you") ||
           msgLower.hasPrefix("are you") || msgLower.hasPrefix("do you") || msgLower.hasPrefix("will you") {
            // For questions addressing the assistant, rephrase to third person
            if msgLower.hasPrefix("are you ") {
                let rest = String(trimmed.dropFirst(8))  // "are you " is 8 chars
                let topic = clipForSummary(rest, maxLength: 40)
                return "You asked whether \(assistantName) was \(topic)."
            }
            return "You asked \(assistantName) a question."
        }

        // Affirmations: "yes", "ok", "sure", "go ahead", "sounds good"
        let affirmations = ["yes", "ok", "okay", "sure", "go ahead", "sounds good", "do it", "proceed", "yep", "yeah", "lgtm", "ship it", "looks good"]
        if affirmations.contains(where: { msgLower == $0 || msgLower.hasPrefix($0 + " ") }) {
            return "You confirmed to proceed."
        }

        // Negations: "no", "stop", "cancel", "wait"
        let negations = ["no", "stop", "cancel", "wait", "hold on", "nope"]
        if negations.contains(where: { msgLower == $0 || msgLower.hasPrefix($0 + " ") }) {
            return "You asked to stop or reconsider."
        }

        // Short meta-actions: "retry", "again", "one more time"
        let retryPatterns = ["retry", "re-run", "again", "one more time", "try again"]
        if retryPatterns.contains(where: { msgLower == $0 || msgLower.hasPrefix($0 + " ") }) {
            return "You asked to retry."
        }

        // Politeness prefix: "please ..."
        if msgLower.hasPrefix("please ") {
            let rest = String(trimmed.dropFirst(7))  // "please " is 7 chars
            let topic = clipForSummary(rest, maxLength: 50)
            return "You asked \(assistantName) to \(topic)."
        }

        // File paths (absolute, ~/, ./, ../)
        if looksLikeFilePath(msgLower) {
            return "You referenced a file path."
        }

        // Issue/PR references: #1234, PR #5678 (using precompiled regex)
        if msgLower.contains("#") {
            let range = NSRange(msgLower.startIndex..., in: msgLower)
            if issueRefPattern.firstMatch(in: msgLower, range: range) != nil {
                return "You referenced an issue or PR."
            }
        }

        // JSON/code snippets (only if message STARTS with JSON, not just contains it)
        if (message.hasPrefix("{") && message.contains(":")) || (message.hasPrefix("[") && message.contains(",")) {
            return "You shared a code snippet."
        }

        // Suggestions: "we should", "we could", "it would be nice"
        if msgLower.hasPrefix("we should ") || msgLower.hasPrefix("we could ") {
            let dropCount = msgLower.hasPrefix("we should ") ? 10 : 9
            let rest = String(trimmed.dropFirst(dropCount))
            let topic = clipForSummary(rest, maxLength: 40)
            return "You suggested: \(topic)."
        }
        let suggestionPatterns = ["it would be", "might want to", "maybe we"]
        if suggestionPatterns.contains(where: { msgLower.hasPrefix($0) || msgLower.contains($0) }) {
            return "You suggested an improvement."
        }

        // Default: treat as instruction with bounded snippet
        let snippet = clipForSummary(trimmed, maxLength: 60)
        return "You instructed: \"\(snippet)\""
    }

    /// Generate fallback summary for assistant messages
    /// - Parameters:
    ///   - message: The original assistant message
    ///   - assistantName: Display name of the assistant (e.g., "Claude Code")
    /// - Returns: A bounded, single-line summary
    nonisolated static func makeAssistantFallback(message: String, assistantName: String) -> String {
        let trimmed = collapseWhitespace(message)
        let msgLower = trimmed.lowercased()

        // Table detection
        if message.contains("|") && (message.contains("---") || message.contains("| ")) {
            return "\(assistantName) displayed a data table."
        }

        // Code block detection
        if message.contains("```") {
            return "\(assistantName) provided code."
        }

        // Queue system specific (tightened: require "queue system" or queue+message context)
        if msgLower.contains("queue system") ||
           (msgLower.contains("queue") && (msgLower.contains("message") || msgLower.contains("pipeline") || msgLower.contains("processing"))) {
            return "\(assistantName) explained how the queue system works."
        }

        // Explanation patterns
        if msgLower.contains("let you") || msgLower.contains("allows you") || msgLower.contains("enables") {
            return "\(assistantName) explained a feature."
        }

        // Technical explanations
        if msgLower.contains("works by") || msgLower.contains("this means") || msgLower.contains("essentially") {
            return "\(assistantName) provided a technical explanation."
        }

        // Instructions/how-to
        if msgLower.contains("you can") || msgLower.contains("to do this") || msgLower.contains("first,") {
            return "\(assistantName) provided instructions."
        }

        // Analysis/investigation
        if msgLower.contains("looking at") || msgLower.contains("found that") || msgLower.contains("the issue") {
            return "\(assistantName) shared analysis findings."
        }

        // First sentence extraction (if reasonable length)
        let firstSentenceEnd = message.firstIndex(of: ".") ?? message.firstIndex(of: "\n") ?? message.endIndex
        let firstPart = String(message[..<firstSentenceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        if firstPart.count <= 60 && firstPart.count >= 10 {
            return boundSummary("\(assistantName): \(firstPart).")
        }

        // Ultimate fallback
        return "\(assistantName) provided a response."
    }

    // MARK: - Helpers

    /// Clip text to a maximum length, breaking at word boundary if possible, with ellipsis
    nonisolated static func clipForSummary(_ text: String, maxLength: Int = 60) -> String {
        guard text.count > maxLength else { return text }

        let truncated = String(text.prefix(maxLength))
        // Try to break at word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }

    /// Collapse whitespace (spaces, tabs, newlines) into single spaces and trim
    nonisolated static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if text looks like a file path (excludes URLs)
    nonisolated static func looksLikeFilePath(_ text: String) -> Bool {
        // Exclude URLs (contain ://)
        if text.contains("://") {
            return false
        }
        // Absolute paths
        if text.hasPrefix("/") && (text.contains(".") || text.contains("/tmp/") || text.contains("/users/")) {
            return true
        }
        // Home-relative paths
        if text.hasPrefix("~/") {
            return true
        }
        // Relative paths
        if text.hasPrefix("./") || text.hasPrefix("../") {
            return true
        }
        return false
    }

    /// Ensure summary is within max length (hard cap of 120 chars)
    nonisolated static func boundSummary(_ summary: String) -> String {
        guard summary.count > 120 else { return summary }
        return clipForSummary(summary, maxLength: 117) // 120 - 3 for "..."
    }
}
