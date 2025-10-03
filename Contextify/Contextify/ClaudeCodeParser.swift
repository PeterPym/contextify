import Foundation

/// Parses terminal content to extract Claude Code input prompts.
///
/// Claude Code displays user input with a `> ` prefix:
/// ```
/// ──────────────────────────────────────────────
/// > user's input text here
/// ──────────────────────────────────────────────
///   ⏵⏵ bypass permissions on
/// ```
enum ClaudeCodeParser {
  /// Extracts the most recent Claude Code input from terminal content.
  ///
  /// Searches for lines starting with `> ` and returns the text after the marker.
  /// Scans from bottom to top to get the most recent input.
  ///
  /// - Parameter terminalContent: Raw text from terminal (from Accessibility API)
  /// - Returns: Extracted input text, or nil if no valid input found
  static func parseInput(from terminalContent: String) -> String? {
    let lines = terminalContent.components(separatedBy: .newlines)

    // Find the last occurrence of "> " (most recent input)
    for line in lines.reversed() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.hasPrefix("> ") {
        let input = String(trimmed.dropFirst(2)) // Remove "> "
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only return non-empty input
        guard !cleaned.isEmpty else { continue }
        return cleaned
      }
    }

    return nil
  }

  /// Advanced parser supporting multi-line input (future enhancement).
  ///
  /// Collects consecutive lines starting with `> ` until hitting a separator.
  /// Currently not used, but included for Phase 2 expansion.
  static func parseInputMultiLine(from terminalContent: String) -> String? {
    let lines = terminalContent.components(separatedBy: .newlines)
    var inputLines: [String] = []
    var inInputSection = false

    // Scan from bottom to top to get most recent input
    for line in lines.reversed() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Detect Claude Code input prompt
      if trimmed.hasPrefix("> ") {
        inInputSection = true
        let input = String(trimmed.dropFirst(2))
        inputLines.insert(input, at: 0)
      }
      // Stop when we hit a separator or status line
      else if trimmed.hasPrefix("─") || trimmed.hasPrefix("⏵") {
        if inInputSection {
          break
        }
      }
      // Continue collecting multi-line input
      else if inInputSection && !trimmed.isEmpty {
        inputLines.insert(trimmed, at: 0)
      }
    }

    guard !inputLines.isEmpty else { return nil }

    let result = inputLines.joined(separator: "\n")
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
