import Foundation

public enum GitAnchorCueKind: String, Codable, Sendable {
  case file
  case command
  case symbol
}

public struct GitAnchorCue: Codable, Sendable, Equatable {
  public let rawValue: String
  public let normalized: String
  public let kind: GitAnchorCueKind

  public init(rawValue: String, normalized: String, kind: GitAnchorCueKind) {
    self.rawValue = rawValue
    self.normalized = normalized
    self.kind = kind
  }
}

public struct GitAnchorCommit: Codable, Sendable, Equatable {
  public let hash: String
  public let timestamp: Int

  public init(hash: String, timestamp: Int) {
    self.hash = hash
    self.timestamp = timestamp
  }
}

public struct GitAnchorPlan: Codable, Sendable, Equatable {
  public let cues: [GitAnchorCue]
  public let files: [String]
  public let commits: [GitAnchorCommit]

  public init(cues: [GitAnchorCue], files: [String], commits: [GitAnchorCommit]) {
    self.cues = cues
    self.files = files
    self.commits = commits
  }

  public var triggerKinds: [String] {
    Array(Set(cues.map(\.kind.rawValue))).sorted()
  }

  public var fileLabels: [String] {
    Array(Set(files.map { URL(fileURLWithPath: $0).lastPathComponent })).sorted()
  }
}

public struct GitAnchorRerankResult: Sendable {
  public let hits: [ContextifyQueryService.SearchHit]
  public let topResultsChanged: Bool

  public init(hits: [ContextifyQueryService.SearchHit], topResultsChanged: Bool) {
    self.hits = hits
    self.topResultsChanged = topResultsChanged
  }
}

public enum GitAnchorSearch {
  public static func extractCues(from rawQuery: String) -> [GitAnchorCue] {
    let normalizedQuery = normalizeQuery(rawQuery)
    guard !normalizedQuery.isEmpty else { return [] }

    var cues: [GitAnchorCue] = []
    var seen = Set<String>()

    func addCue(rawValue: String, normalized: String, kind: GitAnchorCueKind) {
      let trimmedRaw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedNormalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedRaw.isEmpty, !trimmedNormalized.isEmpty else { return }
      let key = "\(kind.rawValue)|\(trimmedNormalized.lowercased())"
      guard seen.insert(key).inserted else { return }
      cues.append(GitAnchorCue(rawValue: trimmedRaw, normalized: trimmedNormalized, kind: kind))
    }

    // Explicit paths or filenames with extensions are the strongest signal.
    let filePattern = #"(?:\.{0,2}/)?(?:[A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+\.[A-Za-z0-9]{1,8}"#
    for match in regexMatches(filePattern, in: normalizedQuery) {
      addCue(rawValue: match, normalized: match, kind: .file)
    }

    // Slash commands often map directly to skills or scripts.
    let commandPattern = #"(?<!\w)/[A-Za-z0-9._-]+"#
    for match in regexMatches(commandPattern, in: normalizedQuery) {
      let command = String(match.dropFirst())
      if command.count >= 3 {
        addCue(rawValue: match, normalized: command, kind: .command)
      }
    }

    // Symbol-ish identifiers: snake_case, camelCase, ALL_CAPS, kebab-case.
    let symbolPattern = #"\b(?:[A-Z]{2,}[A-Z0-9_]*|[A-Za-z0-9]+_[A-Za-z0-9_]+|[A-Za-z0-9]+-[A-Za-z0-9-]+|[a-z]+(?:[A-Z][A-Za-z0-9]+)+)\b"#
    for match in regexMatches(symbolPattern, in: normalizedQuery) {
      if match.count >= 4 {
        addCue(rawValue: match, normalized: match, kind: .symbol)
      }
    }

    return cues
  }

  public static func rerank(
    hits: [ContextifyQueryService.SearchHit],
    using plan: GitAnchorPlan,
    requestedLimit: Int
  ) -> GitAnchorRerankResult {
    guard !hits.isEmpty else {
      return GitAnchorRerankResult(hits: [], topResultsChanged: false)
    }

    let candidateCount = hits.count
    let baselineTop = Array(hits.prefix(requestedLimit)).map(\.id)
    let fileLabels = Set(plan.fileLabels.map { $0.lowercased() })
    let cueTerms = Set(plan.cues.map { $0.normalized.lowercased() }).union(fileLabels)
    let commitHashes = Set(plan.commits.map(\.hash))
    let commitTimes = plan.commits.map(\.timestamp)

    let reranked = hits.enumerated()
      .map { index, hit -> (score: Double, index: Int, hit: ContextifyQueryService.SearchHit) in
        let baselineScore = Double(candidateCount - index) / Double(candidateCount)
        let commitBonus = scoreCommitMatch(hit.gitCommit, candidateHashes: commitHashes)
        let timeBonus = scoreTimeProximity(hit.timestamp, commitTimes: commitTimes)
        let mentionBonus = scoreMentions(hit: hit, cueTerms: cueTerms)
        return (baselineScore + commitBonus + timeBonus + mentionBonus, index, hit)
      }
      .sorted { lhs, rhs in
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.index < rhs.index
      }
      .map(\.hit)

    let limited = Array(reranked.prefix(requestedLimit))
    let rerankedTop = limited.map(\.id)
    return GitAnchorRerankResult(hits: limited, topResultsChanged: rerankedTop != baselineTop)
  }

  private static func normalizeQuery(_ rawQuery: String) -> String {
    rawQuery
      .replacingOccurrences(of: #"(?i)\buse\s+/?total-recall\b"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"(?i)\bsearch\s+(our\s+)?conversation\s+history\b"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func regexMatches(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      guard let matchRange = Range(match.range, in: text) else { return nil }
      return String(text[matchRange])
    }
  }

  private static func scoreCommitMatch(_ gitCommit: String?, candidateHashes: Set<String>) -> Double {
    guard let gitCommit, !gitCommit.isEmpty else { return 0 }
    for hash in candidateHashes {
      if hash == gitCommit || hash.hasPrefix(gitCommit) || gitCommit.hasPrefix(hash) {
        return 6
      }
    }
    return 0
  }

  private static func scoreTimeProximity(_ timestamp: Int, commitTimes: [Int]) -> Double {
    guard let nearest = commitTimes.map({ abs($0 - timestamp) }).min() else { return 0 }
    switch nearest {
    case ...21600:
      return 2.5
    case ...86400:
      return 1.5
    case ...259200:
      return 0.75
    case ...604800:
      return 0.35
    default:
      return 0
    }
  }

  private static func scoreMentions(hit: ContextifyQueryService.SearchHit, cueTerms: Set<String>) -> Double {
    guard !cueTerms.isEmpty else { return 0 }
    let haystacks = [
      hit.contentSnippet.lowercased(),
      hit.transcriptTitle?.lowercased() ?? ""
    ]
    var matches = 0
    for term in cueTerms where term.count >= 3 {
      if haystacks.contains(where: { $0.contains(term) }) {
        matches += 1
      }
    }
    return min(Double(matches) * 0.9, 2.7)
  }
}
