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

    NSLog("🔥 Parser: Scanning \(lines.count) lines for active input section")

    // Look for the active input section pattern:
    // ─────────────────────────
    // > your input here
    // ─────────────────────────
    // ⏵⏵ bypass permissions on

    // Scan from bottom to find the status line (⏵⏵), then look above it
    for (index, line) in lines.reversed().enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Found the status line (⏵⏵ bypass permissions on)
      if trimmed.hasPrefix("⏵") {
        NSLog("🔥 Parser: Found status line at position \(lines.count - index)")

        // Now look backwards from here for the input section
        let actualIndex = lines.count - index - 1

        // Check if there's a separator above the status line
        if actualIndex > 0 {
          let aboveLine = lines[actualIndex - 1].trimmingCharacters(in: .whitespaces)

          if aboveLine.hasPrefix("─") {
            NSLog("🔥 Parser: Found bottom separator")

            // Now collect all lines with "> " above this separator
            var inputLines: [String] = []
            var foundTopSeparator = false

            for i in stride(from: actualIndex - 2, through: 0, by: -1) {
              let currentLine = lines[i].trimmingCharacters(in: .whitespaces)

              // Hit top separator - we're done
              if currentLine.hasPrefix("─") {
                NSLog("🔥 Parser: Found top separator at line \(i)")
                foundTopSeparator = true
                break
              }

              // Collect input lines
              if currentLine.hasPrefix("> ") {
                let input = String(currentLine.dropFirst(2))
                inputLines.insert(input, at: 0)
              }
            }

            if foundTopSeparator && !inputLines.isEmpty {
              let result = inputLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
              NSLog("🔥 Parser: ✅ Extracted active input: [\(result)]")
              return result
            }
          }
        }
      }
    }

    NSLog("🔥 Parser: ❌ No active input section found")
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
