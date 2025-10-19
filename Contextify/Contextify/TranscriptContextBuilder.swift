import Foundation

// MARK: - Built Context

/// Result of building context from exchanges
struct BuiltContext: Sendable {
  let text: String
  let sampledCount: Int
}

// MARK: - Context Builder

/// Builds LLM-ready context from exchanges using various strategies
nonisolated struct ContextBuilder: Sendable {
  func build(
    exchanges: [Exchange],
    strategy: GenerationStrategy,
    budgetTokens: Int? = nil
  ) throws -> BuiltContext {
    switch strategy {
    case .full:
      let formatted = Self.formatWithDeltas(exchanges)
      return BuiltContext(
        text: formatted,
        sampledCount: exchanges.count
      )

    case .bookends:
      let head = Array(exchanges.prefix(MetadataBudgets.bookendCount))
      let tail = Array(exchanges.suffix(MetadataBudgets.bookendCount))
      let seq = (head + tail).sorted { $0.timestamp < $1.timestamp }
      let formatted = Self.formatWithDeltas(seq)
      return BuiltContext(
        text: formatted,
        sampledCount: seq.count
      )

    case .adaptive:
      let budget = budgetTokens ?? MetadataBudgets.samplerBudget
      let seq = AdaptiveSampler.sample(exchanges: exchanges, budgetTokens: budget)
      let formatted = Self.formatWithDeltas(seq)
      return BuiltContext(
        text: formatted,
        sampledCount: seq.count
      )
    }
  }

  private static func formatWithDeltas(_ exchanges: [Exchange]) -> String {
    guard !exchanges.isEmpty else { return "" }

    let startTime = exchanges.first!.timestamp
    var lines: [String] = []

    for exchange in exchanges {
      let role = (exchange.role == .user) ? "U" : "A"
      let delta = formatTimeDelta(exchange.timestamp.timeIntervalSince(startTime))
      let oneLine = Sanitizers.collapse(exchange.text, hardLimit: MetadataBudgets.perExchangeCharLimit)
      lines.append("\(role) +\(delta): \(oneLine)")
    }

    return lines.joined(separator: "\n")
  }

  private static func formatTimeDelta(_ seconds: TimeInterval) -> String {
    let absSeconds = abs(seconds)

    if absSeconds < 1 {
      return "0s"
    } else if absSeconds < 60 {
      return "\(Int(absSeconds))s"
    } else if absSeconds < 3600 {
      let minutes = Int(absSeconds / 60)
      let secs = Int(absSeconds.truncatingRemainder(dividingBy: 60))
      return secs > 0 ? "\(minutes)m\(secs)s" : "\(minutes)m"
    } else {
      let hours = Int(absSeconds / 3600)
      let mins = Int((absSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
      return mins > 0 ? "\(hours)h\(mins)m" : "\(hours)h"
    }
  }
}

// MARK: - Adaptive Sampler

/// Samples exchanges using importance scoring to fit within token budget
nonisolated enum AdaptiveSampler {
  static func sample(exchanges: [Exchange], budgetTokens: Int) -> [Exchange] {
    // If small enough, return all
    guard exchanges.count > (MetadataBudgets.bookendCount * 2) else { return exchanges }

    let head = Array(exchanges.prefix(MetadataBudgets.bookendCount))
    let tail = Array(exchanges.suffix(MetadataBudgets.bookendCount))
    let middle = Array(exchanges.dropFirst(MetadataBudgets.bookendCount).dropLast(MetadataBudgets.bookendCount))

    // Score each middle exchange
    struct Scored {
      let ex: Exchange
      let score: Double
    }

    let ranked: [Scored] = middle.map {
      Scored(ex: $0, score: importance(of: $0))
    }.sorted { $0.score > $1.score }

    // Greedily select highest-scored exchanges within budget
    var chosen: [Exchange] = []
    var usedTokens = estimateTokens(for: head + tail)

    for item in ranked {
      let tokens = estimateTokens(for: [item.ex])
      if usedTokens + tokens > budgetTokens {
        continue
      }
      chosen.append(item.ex)
      usedTokens += tokens
      if usedTokens >= budgetTokens {
        break
      }
    }

    // Reconstruct chronological order
    let seq = (head + chosen.sorted { $0.timestamp < $1.timestamp } + tail)
    return seq
  }

  // MARK: - Importance Scoring

  private static func importance(of exchange: Exchange) -> Double {
    var score = 0.0
    let text = exchange.text.lowercased()

    // Topic shift cues (+2.0)
    let shiftCues = [
      "now let's", "next", "switching to", "new bug",
      "docs", "tests", "refactor"
    ]
    if shiftCues.contains(where: { text.contains($0) }) {
      score += 2.0
    }

    // Completion tokens (+1.5)
    let completionTokens = [
      "✅", "done", "fixed", "merged", "completed"
    ]
    if completionTokens.contains(where: { text.contains($0) }) {
      score += 1.5
    }

    // Questions for user messages (+0.5 per '?', capped at +1.0)
    if exchange.role == .user {
      let questionCount = text.filter { $0 == "?" }.count
      score += min(Double(questionCount) * 0.5, 1.0)
    }

    // Length (favor substantive messages, +0.5 max)
    let wordCount = text.split(whereSeparator: \.isWhitespace).count
    score += min(Double(wordCount) / 200.0, 1.0)

    return score
  }

  // MARK: - Token Estimation

  /// Estimates token count for AdaptiveSampler budget calculations
  /// NOTE: This is ONLY used for TranscriptMetadata generation (session titles/descriptions),
  /// NOT for timeline summaries (which process one message at a time).
  private static func estimateTokens(for exchanges: [Exchange]) -> Int {
    let charsPerToken = MetadataBudgets.charsPerToken  // Auto-tuned by LLM observations

    exchanges.reduce(0) { acc, exchange in
      let limitedText = Sanitizers.collapse(exchange.text, hardLimit: MetadataBudgets.perExchangeCharLimit)
      let charCount = limitedText.count
      // Use auto-tuned ratio (default 2.5) + timestamp/role overhead (~25 tokens)
      // This accounts for: code symbols, file paths, technical terms, punctuation
      // which tokenize less efficiently than prose (~4 chars/token)
      // Timeline summaries use different logic (single-message processing in FoundationLLM.summarizeTimeline)
      return acc + Int(Double(charCount) / charsPerToken) + 25
    }
  }
}

// MARK: - Sanitizers

/// Text sanitization utilities
nonisolated enum Sanitizers {
  /// Collapses whitespace and truncates to hard limit
  static func collapse(_ text: String, hardLimit: Int) -> String {
    var sanitized = text

    // Replace code blocks with compact placeholders
    sanitized = elideCodeBlocks(sanitized)

    // Elide middle of long file paths
    sanitized = elideFilePaths(sanitized)

    // Collapse whitespace
    let range = NSRange(location: 0, length: (sanitized as NSString).length)
    sanitized = Formatters.collapseWhitespace.stringByReplacingMatches(
      in: sanitized,
      options: [],
      range: range,
      withTemplate: " "
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    if sanitized.count > hardLimit {
      sanitized = String(sanitized.prefix(hardLimit))
    }

    return sanitized
  }

  /// Replaces code blocks with compact placeholders like [code block, 34 lines]
  private static func elideCodeBlocks(_ text: String) -> String {
    var result = text

    // Replace markdown code blocks (```...```)
    let codeBlockPattern = #"```[\s\S]*?```"#
    if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
      let matches = regex.matches(
        in: result,
        options: [],
        range: NSRange(result.startIndex..., in: result)
      )

      // Process matches in reverse to maintain valid ranges
      for match in matches.reversed() {
        if let range = Range(match.range, in: result) {
          let block = result[range]
          let lineCount = block.split(separator: "\n").count
          result.replaceSubrange(range, with: "[code block, \(lineCount) lines]")
        }
      }
    }

    return result
  }

  /// Elides middle of long file paths: /Users/rob/very/long/path/file.swift → /Users/.../file.swift
  private static func elideFilePaths(_ text: String) -> String {
    var result = text

    // Match file paths (simplified pattern)
    let pathPattern = #"/[\w\-./]{40,}"#
    if let regex = try? NSRegularExpression(pattern: pathPattern, options: []) {
      let matches = regex.matches(
        in: result,
        options: [],
        range: NSRange(result.startIndex..., in: result)
      )

      // Process matches in reverse to maintain valid ranges
      for match in matches.reversed() {
        if let range = Range(match.range, in: result) {
          let path = String(result[range])
          let components = path.split(separator: "/")

          if components.count > 4 {
            let first = components.prefix(2).joined(separator: "/")
            let last = components.suffix(1).joined(separator: "/")
            let elided = "/\(first)/…/\(last)"
            result.replaceSubrange(range, with: elided)
          }
        }
      }
    }

    return result
  }

  /// Sanitizes text to prevent prompt injection
  static func sanitizeForPrompt(_ text: String) -> String {
    var sanitized = text

    // Replace known injection phrases
    let injectionPhrases = [
      "ignore previous instructions",
      "ignore all previous instructions",
      "disregard previous",
      "new instructions:",
      "system:"
    ]

    for phrase in injectionPhrases {
      sanitized = sanitized.replacingOccurrences(
        of: phrase,
        with: phrase.replacingOccurrences(of: " ", with: "_"),
        options: .caseInsensitive
      )
    }

    // Strip trailing output directives
    sanitized = sanitized.replacingOccurrences(
      of: #"Output:\s*$"#,
      with: "",
      options: .regularExpression
    )

    return sanitized
  }
}
