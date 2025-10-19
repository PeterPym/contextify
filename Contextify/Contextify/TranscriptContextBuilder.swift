import Foundation

// MARK: - Built Context

/// Result of building context from exchanges
struct BuiltContext: Sendable {
  let text: String
  let sampledCount: Int
}

// MARK: - Signal Extraction

/// Extracted signals from transcript for signal-first summarization
struct ExtractedSignals: Sendable {
  let entities: [String]        // Filenames, modules, APIs
  let topicShifts: [String]     // Lines indicating topic changes
  let salientSnippets: [String] // 3-6 most important user messages
}

/// Extracts key signals from exchanges for efficient two-pass summarization
nonisolated enum SignalExtractor {
  /// Extract entities, topic shifts, and salient snippets
  static func extract(from exchanges: [Exchange]) -> ExtractedSignals {
    var entities = Set<String>()
    var topicShifts: [String] = []
    var scoredSnippets: [(snippet: String, score: Double)] = []

    for (index, exchange) in exchanges.enumerated() {
      let text = exchange.text

      // Extract filenames using regex
      let pattern = #"([A-Za-z0-9_.\-/]+\.(swift|md|ts|js|kt|py|rb|java|go|rs|c|cpp|h|hpp|json|yaml|yml|toml|txt|sh))"#
      if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        for match in matches {
          if let range = Range(match.range, in: text) {
            let filename = String(text[range])
            // Extract just the filename, not the full path
            let basename = filename.split(separator: "/").last.map(String.init) ?? filename
            entities.insert(basename)
          }
        }
      }

      // Detect topic shifts
      let lowerText = text.lowercased()
      let shiftCues = ["now let's", "next", "switching to", "new bug", "new feature", "let me"]
      if shiftCues.contains(where: { lowerText.contains($0) }) {
        let snippet = String(text.prefix(100))
        topicShifts.append(snippet)
      }

      // Score user messages for salience
      if exchange.role == .user {
        let score = calculateSalience(text: text, position: index, total: exchanges.count)
        let snippet = Sanitizers.collapse(text, hardLimit: 150)
        scoredSnippets.append((snippet, score))
      }
    }

    // Select top 6 salient snippets
    let topSnippets = scoredSnippets
      .sorted { $0.score > $1.score }
      .prefix(6)
      .map { $0.snippet }

    return ExtractedSignals(
      entities: Array(entities).sorted().prefix(10).map { $0 },
      topicShifts: topicShifts.prefix(5).map { $0 },
      salientSnippets: Array(topSnippets)
    )
  }

  private static func calculateSalience(text: String, position: Int, total: Int) -> Double {
    var score = 0.0

    // Question marks (likely important requests)
    score += Double(text.filter { $0 == "?" }.count) * 2.0

    // Length (substantive messages)
    let wordCount = text.split(whereSeparator: \.isWhitespace).count
    score += min(Double(wordCount) / 50.0, 3.0)

    // Position bias (beginning and end more important)
    let relativePos = Double(position) / Double(max(1, total - 1))
    if relativePos < 0.2 || relativePos > 0.8 {
      score += 2.0
    }

    // Keywords
    let lowerText = text.lowercased()
    let importantKeywords = ["error", "bug", "fix", "add", "implement", "create", "test", "issue"]
    for keyword in importantKeywords {
      if lowerText.contains(keyword) {
        score += 1.5
      }
    }

    return score
  }
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

    case .signalFirst:
      // Two-pass: extract signals locally, format compactly for LLM
      let signals = SignalExtractor.extract(from: exchanges)
      let formatted = Self.formatSignals(signals, totalCount: exchanges.count)
      return BuiltContext(
        text: formatted,
        sampledCount: signals.salientSnippets.count
      )
    }
  }

  private static func formatSignals(_ signals: ExtractedSignals, totalCount: Int) -> String {
    var sections: [String] = []

    // Files mentioned
    if !signals.entities.isEmpty {
      sections.append("Files: \(signals.entities.joined(separator: ", "))")
    }

    // Topic shifts
    if !signals.topicShifts.isEmpty {
      sections.append("Topic shifts:\n" + signals.topicShifts.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n"))
    }

    // Key user requests
    sections.append("Key requests (\(signals.salientSnippets.count) of \(totalCount) messages):\n" +
      signals.salientSnippets.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n"))

    return sections.joined(separator: "\n\n")
  }

  // Move closing brace here
  private static func formatWithDeltas(_ exchanges: [Exchange]) -> String {
    // Original implementation moved down
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

// Remove duplicate implementations below
// MARK: - Adaptive Sampler

/// Samples exchanges using importance scoring to fit within token budget
nonisolated enum AdaptiveSampler {
  // Keep existing implementation
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

    return exchanges.reduce(0) { acc, exchange in
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
