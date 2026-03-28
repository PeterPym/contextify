// SPDX-License-Identifier: MIT
// FTSQueryBuilder.swift - FTS5 query sanitization

import Foundation

/// Utility for building safe FTS5 queries from user input.
public enum FTSQueryBuilder {

  /// FTS5 boolean keywords that must stay quoted when used as search terms.
  private static let ftsKeywords: Set<String> = ["AND", "OR", "NOT", "NEAR"]

  /// Returns true when a token is a simple word safe to leave unquoted in FTS5.
  ///
  /// A token is "simple" when it contains only word characters (`[a-zA-Z0-9_]`)
  /// and optional trailing `*` (prefix wildcard), and is not an FTS5 keyword,
  /// column filter (contains `:`), initial-token operator (contains `^`), or
  /// dotted version number (contains `.`).
  static func isSimpleWord(_ token: String) -> Bool {
    guard !token.isEmpty else { return false }
    // FTS5 keywords must stay quoted (check base without trailing wildcard)
    let base = token.hasSuffix("*") ? String(token.dropLast()) : token
    if ftsKeywords.contains(base.uppercased()) { return false }
    // Tokens with special FTS5 meaning must stay quoted
    if token.contains(":") || token.contains("^") || token.contains(".") { return false }
    // Allow word chars and trailing wildcard only
    let pattern = #"^\w+\*?$"#
    return token.range(of: pattern, options: .regularExpression) != nil
  }

  /// Sanitizes user input for FTS5 MATCH queries.
  /// - Handles quoted phrases
  /// - Removes special FTS operators
  /// - Leaves simple words unquoted so porter stemming applies
  /// - Joins tokens with AND for multi-word queries
  public static func buildSafeFTSQuery(_ query: String) -> String {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    // Check if user provided an explicit phrase with quotes
    if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 2 {
      // User wants exact phrase - validate and pass through
      let phrase = String(trimmed.dropFirst().dropLast())
      let sanitized = phrase.replacingOccurrences(of: "\"", with: "")
      return "\"\(sanitized)\""
    }

    // Split on whitespace, process each token, join with AND
    let tokens = trimmed.components(separatedBy: .whitespaces)
      .filter { !$0.isEmpty }
      .map { token -> String in
        // Normalize: strip quotes and parentheses before classification
        let normalized = token
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: "(", with: "")
          .replacingOccurrences(of: ")", with: "")
        guard !normalized.isEmpty else { return "" }
        // For simple words, leave unquoted (enables porter stemming + prefix wildcards)
        if isSimpleWord(normalized) {
          return normalized
        }
        // Complex tokens: strip wildcard and quote
        let clean = normalized.replacingOccurrences(of: "*", with: "")
        return "\"\(clean)\""
      }
      .filter { $0 != "\"\"" && !$0.isEmpty }  // Filter out empty tokens

    guard !tokens.isEmpty else { return "" }
    return tokens.joined(separator: " AND ")
  }

  /// Build a safe FTS5 query from input that may already contain quoted phrases
  /// (e.g., from hyphen preprocessing). Leaves simple bare tokens unquoted so
  /// porter stemming applies, preserves existing quoted phrases and FTS5
  /// operators, and joins with AND.
  public static func safeWrapPreservingQuotes(_ query: String) -> String {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    var parts: [String] = []
    var current = ""
    var inQuote = false

    for char in trimmed {
      if char == "\"" {
        if inQuote {
          parts.append("\"\(current)\"")
          current = ""
          inQuote = false
        } else {
          if !current.isEmpty {
            let bareTokens = current.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            for token in bareTokens {
              if ftsKeywords.contains(token.uppercased()) {
                parts.append(token)
              } else if isSimpleWord(token) {
                parts.append(token)
              } else {
                let clean = token
                  .replacingOccurrences(of: "(", with: "")
                  .replacingOccurrences(of: ")", with: "")
                if !clean.isEmpty { parts.append("\"\(clean)\"") }
              }
            }
            current = ""
          }
          inQuote = true
        }
      } else {
        current.append(char)
      }
    }

    if inQuote {
      parts.append("\"\(current)\"")
    } else if !current.isEmpty {
      let bareTokens = current.split(separator: " ").map(String.init).filter { !$0.isEmpty }
      for token in bareTokens {
        if ftsKeywords.contains(token.uppercased()) {
          parts.append(token)
        } else if isSimpleWord(token) {
          parts.append(token)
        } else {
          let clean = token
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
          if !clean.isEmpty { parts.append("\"\(clean)\"") }
        }
      }
    }

    guard !parts.isEmpty else { return "" }

    // Join with AND only between non-operator parts
    var result = parts[0]
    for i in 1..<parts.count {
      let prev = parts[i - 1].uppercased()
      let curr = parts[i].uppercased()
      if ftsKeywords.contains(prev) || ftsKeywords.contains(curr) {
        result += " \(parts[i])"
      } else {
        result += " AND \(parts[i])"
      }
    }
    return result
  }

  // MARK: - FTS5 Hyphen Pre-processing (F-02)

  /// Result of hyphen pre-processing, separating the rewritten query from
  /// any hints that should be shown to the user.
  public struct HyphenResult: Sendable {
    public let query: String
    public let hints: [String]
  }

  /// Pre-process a query to handle FTS5 hyphen tokenization issues.
  ///
  /// FTS5 treats hyphens as token separators, causing errors or unexpected
  /// results for hyphenated identifiers common in software development.
  ///
  /// Rewrite rules (applied only to unquoted segments):
  /// - Task IDs (ct-361, bl-123) -> quoted phrase ("ct 361")
  /// - Bare hyphenated tokens (cli-ai-setup) -> quoted phrase ("cli ai setup")
  /// - Trailing hyphens (cc-) -> hint emitted, token unchanged
  /// - Quoted terms, wildcards, and FTS5 operators preserved as-is
  public static func preprocessHyphens(_ query: String) -> HyphenResult {
    var segments: [(text: String, quoted: Bool)] = []
    var current = ""
    var inQuote = false

    for char in query {
      if char == "\"" {
        if inQuote {
          segments.append((current, true))
          current = ""
          inQuote = false
        } else {
          segments.append((current, false))
          current = ""
          inQuote = true
        }
      } else {
        current.append(char)
      }
    }
    if inQuote {
      segments.append((current, true))
    } else if !current.isEmpty {
      segments.append((current, false))
    }

    var hints: [String] = []
    let processed = segments.map { segment -> String in
      if segment.quoted {
        return "\"\(segment.text)\""
      }
      let result = rewriteHyphenatedTokens(segment.text)
      hints.append(contentsOf: result.hints)
      return result.query
    }.joined()

    return HyphenResult(query: processed, hints: hints)
  }

  /// Rewrite hyphenated tokens in an unquoted query segment.
  private static func rewriteHyphenatedTokens(_ text: String) -> HyphenResult {
    let ftsOperators: Set<String> = ["OR", "AND", "NOT", "NEAR"]
    let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    var hints: [String] = []

    let processed = words.map { word -> String in
      guard !word.isEmpty, word.contains("-") else { return word }
      if ftsOperators.contains(word.uppercased()) { return word }

      // Trailing hyphen: hint, don't rewrite
      if word.hasSuffix("-") && word.count > 1 {
        let prefix = String(word.dropLast())
        hints.append("'\(word)' has a trailing hyphen. FTS5 splits on hyphens. Try: \(prefix)* or \"\(prefix)\"")
        return word
      }

      let hasWildcard = word.hasSuffix("*")
      let base = hasWildcard ? String(word.dropLast()) : word

      // Skip tokens with parentheses (complex expressions)
      if base.contains("(") || base.contains(")") { return word }

      // Task ID pattern: 2-6 letter prefix, hyphen, digits (ct-361, bl-123)
      // Use quoted phrase to avoid introducing AND operators into simple queries
      if base.range(of: #"^[a-zA-Z]{2,6}-\d+$"#, options: .regularExpression) != nil {
        let dehyphenated = base.replacingOccurrences(of: "-", with: " ")
        return "\"\(dehyphenated)\""
      }

      // Bare hyphenated token: word(-word)+ (cli-ai-setup, review-loop)
      if base.range(of: #"^\w+(-\w+)+$"#, options: .regularExpression) != nil {
        let dehyphenated = base.replacingOccurrences(of: "-", with: " ")
        if hasWildcard {
          let parts = base.split(separator: "-")
          if parts.count > 1 {
            let allButLast = parts.dropLast().map { "\"\($0)\"" }.joined(separator: " AND ")
            return "\(allButLast) AND \(parts.last!)*"
          }
        }
        return "\"\(dehyphenated)\""
      }

      return word
    }.joined(separator: " ")

    return HyphenResult(query: processed, hints: hints)
  }
}
