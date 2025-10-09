import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Post-processes LLM-generated metadata for quality and grounding
struct MetadataPostProcessor: Sendable {
  private let log = Logger(subsystem: "dev.contextify.metadata", category: "PostProcessor")

  private let allowedTopics: Set<String> = [
    "feature-work", "bug-fix", "refactoring", "testing", "documentation",
    "code-review", "performance", "security", "architecture", "deployment", "general"
  ]

  #if canImport(FoundationModels)
  @available(macOS 26, *)
  func apply(
    to guided: GuidedTranscriptMetadata,
    context: String
  ) -> TranscriptMetadata {
    // Clamp lengths safely
    let title = clampTitle(guided.title)
    let description = clampDescription(guided.description)

    // Normalize topics
    var topics = normalizeTopics(guided.topics)
    if topics.isEmpty {
      topics = ["general"]
    }

    // Filename grounding check
    let (cleanedDescription, hasHallucinations) = stripUnseenFilenames(
      in: description,
      from: context
    )

    // Determine if needs review
    let needsReview = guided.confidence < 0.6 || hasHallucinations || guided.mayContainHallucinations

    if hasHallucinations {
      log.warning("Filename grounding check failed - setting needsReview=true")
    }

    if needsReview {
      log.info("Metadata flagged for review (confidence: \(guided.confidence, privacy: .public), hallucinations: \(hasHallucinations))")
    }

    return TranscriptMetadata(
      version: 1,
      title: title,
      description: cleanedDescription,
      topics: topics,
      confidence: guided.confidence,
      mayContainHallucinations: hasHallucinations || guided.mayContainHallucinations,
      needsReview: needsReview,
      generatedAt: Date(),
      model: "SystemLanguageModel@local",
      promptVersion: 2,
      generatorVersion: 1,
      transcriptSHA256: "", // Will be filled by orchestrator
      messageCount: 0,      // Will be filled by orchestrator
      strategy: "",         // Will be filled by orchestrator
      llmCalls: 1,
      latencyMs: 0          // Will be filled by orchestrator
    )
  }
  #endif

  // MARK: - Length Clamping

  func clampTitle(_ title: String) -> String {
    clamp(title, limit: 60)
  }

  func clampDescription(_ description: String) -> String {
    clamp(description, limit: 200)
  }

  private func clamp(_ text: String, limit: Int) -> String {
    guard text.count > limit else { return text }

    // Try to break at word boundary
    let truncated = String(text.prefix(limit))

    if let lastSpace = truncated.lastIndex(where: { $0.isWhitespace }) {
      let result = String(truncated[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !result.isEmpty {
        return result + "…"
      }
    }

    // Fallback to character boundary
    return String(text.prefix(limit - 1)) + "…"
  }

  // MARK: - Topic Normalization

  func normalizeTopics(_ topics: [String]) -> [String] {
    var normalized = topics
      .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { allowedTopics.contains($0) }

    // Deduplicate while preserving order
    var seen = Set<String>()
    normalized = normalized.filter { seen.insert($0).inserted }

    // Map common out-of-vocabulary terms
    if normalized.isEmpty && topics.contains(where: { $0.lowercased().contains("develop") }) {
      normalized = ["general"]
    }

    return normalized
  }

  // MARK: - Filename Grounding

  func stripUnseenFilenames(in text: String, from context: String) -> (String, Bool) {
    // Extract candidate filenames from text
    let filenamePattern = #"([A-Za-z0-9_.\-/]+\.(swift|md|ts|js|kt|py|rb|java|go|rs|c|cpp|h|hpp|json|yaml|yml|toml|txt|sh))"#
    guard let regex = try? NSRegularExpression(pattern: filenamePattern, options: []) else {
      return (text, false)
    }

    let nsText = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

    var hasUnseenFilenames = false
    var cleanedText = text

    for match in matches.reversed() {
      let range = match.range
      let filename = nsText.substring(with: range)

      // Check if filename appears in context
      if !context.contains(filename) {
        hasUnseenFilenames = true
        log.warning("Found unseen filename in description: \(filename, privacy: .public)")

        // Remove the filename from the description
        let startIndex = text.index(text.startIndex, offsetBy: range.location)
        let endIndex = text.index(startIndex, offsetBy: range.length)
        cleanedText.removeSubrange(startIndex..<endIndex)
      }
    }

    // Clean up any double spaces left from removals
    cleanedText = cleanedText.replacingOccurrences(
      of: #"\s+"#,
      with: " ",
      options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    return (cleanedText, hasUnseenFilenames)
  }
}
