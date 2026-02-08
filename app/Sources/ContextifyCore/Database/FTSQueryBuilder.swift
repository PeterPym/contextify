// SPDX-License-Identifier: MIT
// FTSQueryBuilder.swift - FTS5 query sanitization

import Foundation

/// Utility for building safe FTS5 queries from user input.
public enum FTSQueryBuilder {
  /// Sanitizes user input for FTS5 MATCH queries.
  /// - Handles quoted phrases
  /// - Removes special FTS operators
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

    // Split on whitespace, wrap each token in quotes, join with AND
    let tokens = trimmed.components(separatedBy: .whitespaces)
      .filter { !$0.isEmpty }
      .map { token in
        // Remove any quotes and special chars from individual tokens
        let clean = token
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: "*", with: "")
          .replacingOccurrences(of: "(", with: "")
          .replacingOccurrences(of: ")", with: "")
        return "\"\(clean)\""
      }
      .filter { $0 != "\"\"" }  // Filter out empty tokens

    guard !tokens.isEmpty else { return "" }
    return tokens.joined(separator: " AND ")
  }
}
