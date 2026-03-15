// SPDX-License-Identifier: MIT
// CLIStyle.swift - Terminal styling helper with ANSI color and OSC 8 hyperlink support

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Terminal styling helper with automatic color/capability detection.
///
/// Respects NO_COLOR (https://no-color.org), TERM=dumb, and non-TTY output.
/// All output falls back gracefully to unstyled text when colors are disabled.
enum CLIStyle {
  /// Whether the terminal supports ANSI escape sequences.
  /// Disabled when: stdout is not a TTY, NO_COLOR is set, or TERM=dumb.
  static let isStyled: Bool = {
    guard isatty(STDOUT_FILENO) != 0 else { return false }
    if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
    if ProcessInfo.processInfo.environment["TERM"] == "dumb" { return false }
    return true
  }()

  // MARK: - ANSI Escape Codes

  static let reset  = isStyled ? "\u{001B}[0m" : ""
  static let bold   = isStyled ? "\u{001B}[1m" : ""
  static let dim    = isStyled ? "\u{001B}[2m" : ""
  static let green  = isStyled ? "\u{001B}[32m" : ""
  static let red    = isStyled ? "\u{001B}[31m" : ""
  static let yellow = isStyled ? "\u{001B}[33m" : ""
  static let cyan   = isStyled ? "\u{001B}[36m" : ""

  // MARK: - Semantic Formatters

  /// Format a success message with a green checkmark prefix.
  static func success(_ text: String) -> String {
    "\(green)\(isStyled ? "\u{2713}" : "OK:")\(reset) \(text)"
  }

  /// Format an error message with a red X prefix.
  static func error(_ text: String) -> String {
    "\(red)\(isStyled ? "\u{2717}" : "ERROR:")\(reset) \(text)"
  }

  /// Format a warning message with a yellow exclamation prefix.
  static func warning(_ text: String) -> String {
    "\(yellow)\(isStyled ? "!" : "WARNING:")\(reset) \(text)"
  }

  /// Format text as a bold header.
  static func header(_ text: String) -> String {
    "\(bold)\(text)\(reset)"
  }

  /// Format text as dim (secondary information).
  static func dimText(_ text: String) -> String {
    "\(dim)\(text)\(reset)"
  }

  /// Format text in cyan (for commands, URLs, highlights).
  static func cyanText(_ text: String) -> String {
    "\(cyan)\(text)\(reset)"
  }

  /// Format text in green (for positive values).
  static func greenText(_ text: String) -> String {
    "\(green)\(text)\(reset)"
  }

  /// Format text in red (for negative values).
  static func redText(_ text: String) -> String {
    "\(red)\(text)\(reset)"
  }

  /// Format text in yellow (for cautionary values).
  static func yellowText(_ text: String) -> String {
    "\(yellow)\(text)\(reset)"
  }

  /// Format text as bold.
  static func boldText(_ text: String) -> String {
    "\(bold)\(text)\(reset)"
  }

  // MARK: - OSC 8 Hyperlinks

  /// Create a clickable terminal hyperlink using the OSC 8 protocol.
  /// Falls back to "text (url)" in non-interactive terminals.
  /// Falls back to plain cyan URL in tmux (which does not support OSC 8).
  static func link(_ text: String, url: String) -> String {
    guard isStyled else { return "\(text) (\(url))" }
    // tmux does not support OSC 8 hyperlinks
    if ProcessInfo.processInfo.environment["TMUX"] != nil {
      return "\(cyan)\(url)\(reset)"
    }
    return "\u{001B}]8;;\(url)\u{001B}\\\(cyan)\(text)\(reset)\u{001B}]8;;\u{001B}\\"
  }

  // MARK: - Label/Value Formatting

  /// Format a label-value pair with dim label and styled value.
  /// Used for status output like "Server:     https://example.com"
  static func labelValue(_ label: String, _ value: String, padTo width: Int = 0) -> String {
    let paddedLabel = width > 0 ? label.padding(toLength: width, withPad: " ", startingAt: 0) : label
    return "\(dim)\(paddedLabel)\(reset)\(value)"
  }

  // MARK: - Snippet Styling

  /// Convert HTML bold tags (<b>...</b>) in search snippets to ANSI bold.
  /// When styling is disabled, strips the tags entirely.
  ///
  /// SECURITY: Snippets contain remote content that may include malicious
  /// terminal escape sequences. We use a sentinel-based approach:
  /// 1. Replace <b>/<\/b> with private sentinels
  /// 2. Strip ALL escape/control sequences from the raw text
  /// 3. Replace sentinels with our own ANSI codes
  static func styledSnippet(_ text: String) -> String {
    let openSentinel = "\u{FFFE}"  // BOM-reversed, not valid in normal text
    let closeSentinel = "\u{FFFF}" // Noncharacter, safe sentinel

    // Step 1: Replace HTML bold tags with sentinels
    var result = text
      .replacingOccurrences(of: "<b>", with: openSentinel)
      .replacingOccurrences(of: "</b>", with: closeSentinel)

    // Step 2: Strip ALL escape sequences and control characters from remote content
    result = stripEscapeSequences(result)

    // Step 3: Replace sentinels with our own ANSI codes (or nothing if unstyled)
    if isStyled {
      result = result
        .replacingOccurrences(of: openSentinel, with: bold)
        .replacingOccurrences(of: closeSentinel, with: reset)
    } else {
      result = result
        .replacingOccurrences(of: openSentinel, with: "")
        .replacingOccurrences(of: closeSentinel, with: "")
    }

    return result
  }

  /// Strip all ANSI escape sequences and control characters from text,
  /// preserving only printable content, newlines, and tabs.
  /// Used to sanitize remote/untrusted content before display.
  static func stripEscapeSequences(_ text: String) -> String {
    var result = ""
    var i = text.startIndex
    while i < text.endIndex {
      let c = text[i]
      if c == "\u{001B}" {
        // Skip entire escape sequence
        let next = text.index(after: i)
        if next < text.endIndex {
          if text[next] == "[" {
            // CSI sequence: skip until letter terminator
            var j = text.index(after: next)
            while j < text.endIndex && !text[j].isLetter { j = text.index(after: j) }
            i = (j < text.endIndex) ? text.index(after: j) : j
            continue
          } else if text[next] == "]" {
            // OSC sequence: skip until ST (ESC\) or BEL
            var j = text.index(after: next)
            while j < text.endIndex {
              if text[j] == "\u{0007}" { j = text.index(after: j); break }
              if text[j] == "\\" {
                let prev = text.index(before: j)
                if prev >= next && text[prev] == "\u{001B}" { j = text.index(after: j); break }
              }
              j = text.index(after: j)
            }
            i = j
            continue
          }
        }
        i = text.index(after: i)
      } else if c == "\n" || c == "\t" {
        result.append(c)
        i = text.index(after: i)
      } else if c == "\r" {
        // Strip carriage returns from remote content to prevent
        // terminal line-overwrite attacks (e.g. "safe\rMALICIOUS")
        i = text.index(after: i)
      } else if c.unicodeScalars.allSatisfy({ $0.properties.isControl }) {
        // Skip control characters
        i = text.index(after: i)
      } else {
        result.append(c)
        i = text.index(after: i)
      }
    }
    return result
  }
}
