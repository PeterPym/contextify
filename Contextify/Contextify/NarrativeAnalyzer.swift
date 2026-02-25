//
//  NarrativeAnalyzer.swift
//  Contextify
//
//  Actor that makes LLM calls to analyze transcript exchanges for narrative tracking.
//  Stateless: all context is passed in, results are returned. ChronicleService owns state.
//

import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

// ChronicleModels are in ContextifyCore which is imported by the app target

actor NarrativeAnalyzer {
  static let shared = NarrativeAnalyzer()
  private let log = Logger(subsystem: "dev.contextify", category: "NarrativeAnalyzer")

  private init() {}
}

// MARK: - Exchange Analysis

#if canImport(FoundationModels)
@available(macOS 26.0, *)
extension NarrativeAnalyzer {

  /// Analyze a single transcript exchange for arc status and signposts.
  /// - Parameters:
  ///   - entryId: The transcript entry ID (used for session isolation)
  ///   - userContent: The user's message text
  ///   - assistantContent: The assistant's response text
  ///   - currentArcIntent: The current arc's intent string, if any
  ///   - recentSummaries: Rolling window of recent exchange summaries for context
  /// - Returns: ExchangeAnalysis on success, nil on failure
  func analyzeExchange(
    entryId: String,
    userContent: String,
    assistantContent: String,
    currentArcIntent: String?,
    recentSummaries: [String]
  ) async -> ExchangeAnalysis? {
    // Build the prompt
    let contextSection = recentSummaries.isEmpty ? "" : """

    <recent_context>
    \(recentSummaries.suffix(3).joined(separator: "\n"))
    </recent_context>
    """

    let arcSection = currentArcIntent.map { """

    <current_arc>
    \($0)
    </current_arc>
    """ } ?? ""

    // Truncate content to fit context window (~800 tokens max per field)
    let truncatedUser = String(userContent.prefix(2000))
    let truncatedAssistant = String(assistantContent.prefix(2000))

    let userPrompt = """
    Analyze this AI conversation exchange for narrative tracking:\(contextSection)\(arcSection)

    <exchange>
    USER: \(truncatedUser)

    ASSISTANT: \(truncatedAssistant)
    </exchange>

    Identify: arc status, any signposts (decisions/discoveries/pivots/milestones/blockers), and provide a brief summary.
    """

    let instructions = """
    You analyze AI coding assistant conversations to extract narrative structure.
    Focus on: what the developer is trying to accomplish, key decisions made, discoveries found, direction changes, milestones reached, and blockers encountered.
    Be concise. Summaries must be 80 characters or fewer. Only flag genuine signposts, not routine conversation.
    """

    let options = GenerationOptions(
      sampling: .greedy,
      temperature: 0,
      maximumResponseTokens: 300
    )

    do {
      let result = try await FoundationLLM.shared.generateGuided(
        instructions: instructions,
        prompt: userPrompt,
        generating: ExchangeAnalysis.self,
        options: options,
        sessionId: "chronicle-exchange-\(entryId)"
      )
      log.debug("NarrativeAnalyzer: analyzed entry \(entryId, privacy: .public), status=\(result.arcStatus.status.rawValue, privacy: .public), signposts=\(result.signposts.count, privacy: .public)")
      return result
    } catch {
      log.warning("NarrativeAnalyzer: exchange analysis failed for \(entryId, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  // MARK: - Continuity Detection

  /// Detect whether a new transcript continues work from a previous transcript.
  /// - Parameters:
  ///   - lastTranscriptSummary: Summary text of the previous transcript
  ///   - firstExchangeContent: Content of the first exchange in the new transcript
  ///   - timeDeltaSeconds: Time gap between transcripts in seconds
  /// - Returns: ContinuityAnalysis on success, nil on failure
  func detectContinuity(
    lastTranscriptSummary: String,
    firstExchangeContent: String,
    timeDeltaSeconds: TimeInterval
  ) async -> ContinuityAnalysis? {
    let timeGapDesc: String
    if timeDeltaSeconds < 3600 {
      timeGapDesc = "\(Int(timeDeltaSeconds / 60)) minutes"
    } else {
      timeGapDesc = "\(Int(timeDeltaSeconds / 3600)) hours"
    }

    let userPrompt = """
    Assess whether this new conversation continues the previous work thread.

    <previous_session_summary>
    \(String(lastTranscriptSummary.prefix(800)))
    </previous_session_summary>

    <time_gap>\(timeGapDesc)</time_gap>

    <new_session_start>
    \(String(firstExchangeContent.prefix(800)))
    </new_session_start>

    Is this a continuation of the same work?
    """

    let instructions = """
    You determine if a new AI coding session continues work from a previous session.
    Look for: explicit references to previous work, same files/topics, short time gap, /clear or context compaction signals.
    """

    let options = GenerationOptions(
      sampling: .greedy,
      temperature: 0,
      maximumResponseTokens: 150
    )

    do {
      let result = try await FoundationLLM.shared.generateGuided(
        instructions: instructions,
        prompt: userPrompt,
        generating: ContinuityAnalysis.self,
        options: options,
        sessionId: "chronicle-continuity-\(UUID().uuidString)"
      )
      log.debug("NarrativeAnalyzer: continuity result=\(result.isContinuation, privacy: .public), confidence=\(result.confidence, privacy: .public)")
      return result
    } catch {
      log.warning("NarrativeAnalyzer: continuity detection failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}
#endif // canImport(FoundationModels)
