import Foundation

// MARK: - Built Context

/// Result of building context from exchanges
struct BuiltContext: Sendable {
  let text: String
  let sampledCount: Int
}

// MARK: - Context Builder

/// Builds LLM-ready context from exchanges using various strategies
struct ContextBuilder: Sendable {
  func build(exchanges: [Exchange], strategy: GenerationStrategy) throws -> BuiltContext {
    switch strategy {
    case .full:
      let formatted = exchanges.map(Self.format).joined(separator: "\n")
      return BuiltContext(
        text: header(sampled: exchanges.count, total: exchanges.count) + formatted,
        sampledCount: exchanges.count
      )

    case .bookends:
      // Limit bookends to fit within context window
      // Each exchange ~50-100 tokens avg, so 10+10 = ~1000-2000 tokens
      let head = Array(exchanges.prefix(10))
      let tail = Array(exchanges.suffix(10))
      let seq = (head + tail).sorted { $0.timestamp < $1.timestamp }
      let formatted = seq.map(Self.format).joined(separator: "\n")
      return BuiltContext(
        text: header(sampled: seq.count, total: exchanges.count) + formatted,
        sampledCount: seq.count
      )

    case .adaptive:
      // Budget: 4096 total - 300 output - 250 prompt/overhead = ~3500 input max
      // Use 2000 to be conservative and allow for token estimation error
      let seq = AdaptiveSampler.sample(exchanges: exchanges, budgetTokens: 2000)
      let formatted = seq.map(Self.format).joined(separator: "\n")
      return BuiltContext(
        text: header(sampled: seq.count, total: exchanges.count) + formatted,
        sampledCount: seq.count
      )
    }
  }

  private func header(sampled: Int, total: Int) -> String {
    "SAMPLED \(sampled) OF \(total)\n"
  }

  private static func format(_ exchange: Exchange) -> String {
    let role = (exchange.role == .user) ? "U" : "A"
    let stamp = ISO8601DateFormatter().string(from: exchange.timestamp)
    let oneLine = Sanitizers.collapse(exchange.text, hardLimit: 2000)
    return "\(role) [\(stamp)]: \(oneLine)"
  }
}

// MARK: - Adaptive Sampler

/// Samples exchanges using importance scoring to fit within token budget
enum AdaptiveSampler {
  static func sample(exchanges: [Exchange], budgetTokens: Int) -> [Exchange] {
    // If small enough, return all
    guard exchanges.count > 20 else { return exchanges }

    let head = Array(exchanges.prefix(10))
    let tail = Array(exchanges.suffix(10))
    let middle = Array(exchanges.dropFirst(10).dropLast(10))

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

  private static func estimateTokens(for exchanges: [Exchange]) -> Int {
    exchanges.reduce(0) { acc, exchange in
      let wordCount = exchange.text.split(whereSeparator: \.isWhitespace).count
      return acc + Int(Double(wordCount) * 1.3) + 8 // 1.3x multiplier + overhead
    }
  }
}

// MARK: - Sanitizers

/// Text sanitization utilities
enum Sanitizers {
  /// Collapses whitespace and truncates to hard limit
  static func collapse(_ text: String, hardLimit: Int) -> String {
    var sanitized = text.replacingOccurrences(
      of: #"\s+"#,
      with: " ",
      options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    if sanitized.count > hardLimit {
      sanitized = String(sanitized.prefix(hardLimit))
    }

    return sanitized
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
