import Foundation
import OSLog
import ContextifyCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Result of LLM synthesis from search results
struct SynthesisResult: Sendable {
  let summary: String
  let sources: [SearchResult]
  let query: String
  let generatedAt: Date

  nonisolated init(summary: String, sources: [SearchResult], query: String, generatedAt: Date) {
    self.summary = summary
    self.sources = sources
    self.query = query
    self.generatedAt = generatedAt
  }
}

/// Service for synthesizing AI summaries from search results
actor SynthesisService {
  private let log = Logger(subsystem: "dev.contextify", category: "SynthesisService")

  /// Maximum number of results to include in synthesis
  private let maxSources = 10

  /// Maximum characters per result to include (prevent context overflow)
  private let maxCharsPerSource = 800

  init() {}

  /// Synthesizes a summary from search results using LLM
  /// - Parameters:
  ///   - query: Original search query
  ///   - results: Search results to synthesize
  ///   - maxResults: Maximum number of results to include (default 10)
  /// - Returns: Synthesis result with summary and sources
  func synthesize(query: String, results: [SearchResult], maxResults: Int? = nil) async throws -> SynthesisResult {
    let startTime = Date()
    let limit = min(maxResults ?? maxSources, results.count)
    let topResults = Array(results.prefix(limit))

    guard !topResults.isEmpty else {
      throw SynthesisError.noResults
    }

    log.info("Starting synthesis for query '\(query, privacy: .public)' with \(topResults.count) sources")

    // Assemble context from search results
    let context = assembleContext(query: query, results: topResults)

    // Generate synthesis using LLM
    guard #available(macOS 26.0, *) else {
      throw SynthesisError.llmUnavailable
    }

    let summary = try await generateSynthesis(context: context, query: query)

    let duration = Date().timeIntervalSince(startTime)
    log.info("Synthesis complete in \(String(format: "%.0f", duration * 1000))ms")

    return SynthesisResult(
      summary: summary,
      sources: topResults,
      query: query,
      generatedAt: Date()
    )
  }

  // MARK: - Private Helpers

  /// Assembles formatted context from search results
  private func assembleContext(query: String, results: [SearchResult]) -> String {
    var context = "Query: \"\(query)\"\n\nRelevant conversations:\n\n"

    for (index, result) in results.enumerated() {
      let sourceNum = index + 1
      context += "[\(sourceNum)] "

      // Include parent (user question) if available
      if let parentContent = result.parentContent {
        let truncatedParent = truncate(parentContent, maxLength: maxCharsPerSource)
        context += "User: \(truncatedParent)\n    "
      }

      // Include result content (assistant response)
      let truncatedContent = truncate(result.content, maxLength: maxCharsPerSource)
      context += "Assistant: \(truncatedContent)\n\n"
    }

    return context
  }

  /// Truncates text to max length at word boundary
  private func truncate(_ text: String, maxLength: Int) -> String {
    guard text.count > maxLength else { return text }

    let truncated = String(text.prefix(maxLength))
    if let lastSpace = truncated.lastIndex(where: { $0.isWhitespace }) {
      return String(truncated[..<lastSpace]) + "…"
    }

    return truncated + "…"
  }

  /// Generates synthesis using FoundationLLM
  @available(macOS 26.0, *)
  private func generateSynthesis(context: String, query: String) async throws -> String {
    let instructions = """
    You are a helpful assistant that synthesizes information from conversation transcripts.

    Your task: Analyze the provided conversation excerpts and generate a clear, concise summary
    that answers the user's query.

    Guidelines:
    - Focus on directly answering the query based on the conversations
    - Synthesize information across multiple conversations when relevant
    - Highlight key insights, solutions, or patterns
    - Use clear, technical language appropriate for developers
    - If conversations contradict each other, note the different approaches
    - Keep the summary focused and actionable
    - Format with markdown for readability (use bullet points, code blocks, etc.)

    Do not:
    - Introduce information not present in the conversations
    - Reference source numbers (they're for context only)
    - Be overly verbose - aim for clarity and conciseness
    """

    let prompt = """
    \(context)

    Based on the conversations above, provide a comprehensive answer to: "\(query)"
    """

    let options = GenerationOptions(
      sampling: .greedy,
      temperature: 0.0,  // Deterministic
      maximumResponseTokens: 1000  // Allow longer synthesis
    )

    log.debug("Sending synthesis request to LLM (context length: \(context.count) chars)")

    do {
      // Use raw generation (no structured JSON needed)
      let llm = FoundationLLM.shared
      let response = try await llm.rawWithInstructions(
        instructions: instructions,
        prompt: prompt,
        options: options
      )

      log.debug("LLM synthesis successful (response length: \(response.count) chars)")
      return response.trimmingCharacters(in: .whitespacesAndNewlines)

    } catch {
      log.error("LLM synthesis failed: \(error.localizedDescription, privacy: .public)")
      throw SynthesisError.generationFailed(error.localizedDescription)
    }
  }
}

// MARK: - Errors

enum SynthesisError: Error, LocalizedError {
  case noResults
  case llmUnavailable
  case generationFailed(String)

  var errorDescription: String? {
    switch self {
    case .noResults:
      return "No search results to synthesize"
    case .llmUnavailable:
      return "LLM synthesis requires macOS 26.0+"
    case .generationFailed(let reason):
      return "Synthesis failed: \(reason)"
    }
  }
}
