import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

/// LLM client for generating transcript metadata
actor TranscriptMetadataLLM {
  static let shared = TranscriptMetadataLLM()

  private let log = Logger(subsystem: "dev.contextify.metadata", category: "TranscriptMetadataLLM")
  let modelSignature = "SystemLanguageModel@local"

  private init() {}

  enum LLMError: Error {
    case unavailable
    case unexpectedEnvironment
    case decodingFailure(String)
  }

  // MARK: - Token Budget Calculation

#if canImport(FoundationModels)
  @available(macOS 26, *)
  func calculateAvailableContextTokens(sampledCount: Int, totalCount: Int) async -> Int {
    let instructions = Prompts.singlePass(sampledCount: sampledCount, totalCount: totalCount)

    // Estimate instruction tokens
    // FoundationModels may not expose token counting, so use character-based estimation
    // Typical ratio is ~4 chars per token for English text
    let instructionTokens = instructions.count / 4

    // Estimate schema tokens added by includeSchemaInPrompt: true
    // The @Generable schema gets converted to JSON schema and added to the prompt
    // Conservative estimate based on the GuidedTranscriptMetadata schema size
    let schemaTokens = 250

    // Budget calculation
    let totalTokens = 4096
    let maxOutputTokens = 300
    // Safety margin for token estimation variance
    // - Time deltas (+5m, +2h) are much more efficient than ISO8601 timestamps
    // - Code symbols and punctuation still tokenize less efficiently
    // - Conservative margin to avoid hitting context limit
    let safetyMargin = 100

    let availableForContext = totalTokens - maxOutputTokens - instructionTokens - schemaTokens - safetyMargin

    log.info("Token budget: instructions=\(instructionTokens), schema=\(schemaTokens), output=\(maxOutputTokens), safety=\(safetyMargin), available=\(availableForContext)")

    return max(0, availableForContext)
  }
#endif

  // MARK: - Single Pass Generation

#if canImport(FoundationModels)
  @available(macOS 26, *)
  func singlePass(
    context: String,
    sampledCount: Int,
    totalCount: Int
  ) async throws -> GuidedTranscriptMetadata {
    let availability = SystemLanguageModel.default.availability
    switch availability {
    case .available:
      break
    case .unavailable:
      log.warning("SystemLanguageModel unavailable")
      throw LLMError.unavailable
    @unknown default:
      log.warning("SystemLanguageModel unknown availability")
      throw LLMError.unavailable
    }

    let instructions = Prompts.singlePass(sampledCount: sampledCount, totalCount: totalCount)
    let session = LanguageModelSession(instructions: instructions)

    let options = GenerationOptions(
      sampling: .greedy,
      temperature: 0,
      maximumResponseTokens: 300
    )

    log.info("Requesting transcript metadata from LLM (sampled: \(sampledCount)/\(totalCount))")

    do {
      let response = try await session.respond(
        to: context,
        generating: GuidedTranscriptMetadata.self,
        includeSchemaInPrompt: true,
        options: options
      )

      log.info("LLM returned metadata - title: '\(response.content.title, privacy: .public)'")
      return response.content
    } catch let error as LanguageModelSession.GenerationError {
      log.error("LLM generation error: \(String(describing: error), privacy: .public)")

      // Try to get more details on decoding failures
      if case .decodingFailure(let errorContext) = error {
        log.error("Decoding failure details: \(errorContext.debugDescription, privacy: .public)")

        // Retry once with higher temperature
        log.info("Retrying with temperature 0.1...")
        let retryOptions = GenerationOptions(
          sampling: .greedy,
          temperature: 0.1,
          maximumResponseTokens: 300
        )

        let retryResponse = try await session.respond(
          to: context,
          generating: GuidedTranscriptMetadata.self,
          includeSchemaInPrompt: true,
          options: retryOptions
        )

        log.info("Retry succeeded")
        return retryResponse.content
      }
      throw LLMError.decodingFailure(String(describing: error))
    }
  }
#else
  @available(macOS 26, *)
  func singlePass(
    context: String,
    sampledCount: Int,
    totalCount: Int
  ) async throws -> Never {
    log.error("FoundationModels not available (macOS < 26)")
    throw LLMError.unexpectedEnvironment
  }
#endif
}

// MARK: - Guided Schema

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable(description: "Transcript metadata")
struct GuidedTranscriptMetadata: Sendable {
  @Guide(description: "Title ≤60 chars; imperative or concise noun phrase.")
  var title: String

  @Guide(description: "Description ≤200 chars; 2–3 activities in chronological order; past tense.")
  var description: String

  @Guide(description: "2–5 topics from the fixed list; lowercase hyphenated.")
  var topics: [String]

  @Guide(description: "Confidence 0.0–1.0", .range(0...1))
  var confidence: Double

  @Guide(description: "True if any referenced filename/module/API not in messages.")
  var mayContainHallucinations: Bool
}
#endif

// MARK: - Prompts

enum Prompts: Sendable {
  nonisolated static func singlePass(sampledCount: Int, totalCount: Int) -> String {
    """
    You are analyzing a developer's AI-assisted coding session.

    OUTPUT RULES
    - Only include details explicitly present in the messages.
    - Do NOT invent filenames, APIs, bugs, or tools.
    - Title: ≤60 chars; imperative or concise noun phrase; focus on the most discussed activity.
    - Description: ≤200 chars; 2–3 key activities in chronological order; past tense; prefer concrete nouns from the text.
    - Topics: 2–5 from {feature-work, bug-fix, refactoring, testing, documentation, code-review, performance, security, architecture, deployment, general}.
    - Confidence: 0.0–1.0 based on clarity/specificity.
    - mayContainHallucinations: true if any referenced filename/module/API is not present verbatim in the messages.

    CONTEXT
    This excerpt shows \(sampledCount) of \(totalCount) messages. First 10 and last 10 are always included; the middle is selected for importance.

    Return ONLY the JSON object for the schema.
    """
  }
}

// MARK: - Heuristics Fallback

enum HeuristicMetadata: Sendable {
  nonisolated static func generate(exchanges: [Exchange]) -> TranscriptMetadata {
    let title = exchanges.count < 3 ? "Brief Session" : "Developer Chat"
    let description = generateDescription(exchanges: exchanges)
    let topics = ["general"]

    return TranscriptMetadata(
      version: 1,
      title: title,
      description: description,
      topics: topics,
      confidence: 0.3,
      mayContainHallucinations: false,
      needsReview: true,
      generatedAt: Date(),
      model: "heuristic",
      promptVersion: 0,
      generatorVersion: 1,
      transcriptSHA256: "",
      messageCount: exchanges.count,
      strategy: "heuristic",
      llmCalls: 0,
      latencyMs: 0
    )
  }

  nonisolated private static func generateDescription(exchanges: [Exchange]) -> String {
    guard !exchanges.isEmpty else {
      return "Empty transcript."
    }

    if exchanges.count < 3 {
      return "Very short conversation."
    }

    // Extract first and last user messages
    let userMessages = exchanges.filter { $0.role == .user }
    let firstUser = userMessages.first?.text.prefix(50) ?? ""
    let lastUser = userMessages.last?.text.prefix(50) ?? ""

    if firstUser.isEmpty && lastUser.isEmpty {
      return "Conversation with \(exchanges.count) messages."
    }

    if !firstUser.isEmpty && !lastUser.isEmpty {
      return "Started with: \(firstUser)... Ended with: \(lastUser)..."
    }

    return "Conversation with \(exchanges.count) messages."
  }
}
