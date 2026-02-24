//
//  ChronicleSchemas.swift
//  Contextify
//
//  @Generable schemas for structured LLM output in Project Chronicle.
//  These must live in the app target because @Generable requires FoundationModels.
//

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

#if canImport(FoundationModels)

// MARK: - Exchange Analysis Schema

/// Nested types used in ExchangeAnalysis

@available(macOS 26.0, *)
@Generable(description: "The current state of the narrative arc")
struct ArcStatusResult: Sendable {
  @Guide(description: "How this exchange relates to the current arc")
  var status: ArcStatusValue

  @Guide(description: "Updated intent if the arc is changing or a new arc is starting")
  var updatedIntent: String?

  @Guide(description: "Updated strategic context if the arc context has changed")
  var updatedStrategicContext: String?
}

@available(macOS 26.0, *)
@Generable(description: "Arc status classification")
enum ArcStatusValue: String, Sendable {
  case continuing   // work continues on the same arc
  case discovering  // a nested arc is being discovered
  case pivoting     // direction is changing within the arc
  case completing   // the arc is wrapping up
  case resuming     // returning from a nested arc
}

@available(macOS 26.0, *)
@Generable(description: "Signpost kind classification")
enum SignpostKindValue: String, Sendable {
  case decision
  case discovery
  case pivot
  case milestone
  case blocker
  case resolution
}

@available(macOS 26.0, *)
@Generable(description: "A significant moment detected in the narrative")
struct SignpostResult: Sendable {
  @Guide(description: "Type of signpost")
  var kind: SignpostKindValue

  @Guide(description: "One sentence (120 chars max) describing what happened")
  var summary: String

  @Guide(description: "Optional extended explanation of reasoning or context")
  var detail: String?
}

/// Main output schema for exchange analysis
@available(macOS 26.0, *)
@Generable(description: "Analysis of a single transcript exchange for narrative tracking")
struct ExchangeAnalysis: Sendable {
  @Guide(description: "Arc status assessment for this exchange")
  var arcStatus: ArcStatusResult

  @Guide(description: "Array of signposts (decisions, discoveries, pivots, milestones, blockers) detected in this exchange. Empty array if none.")
  var signposts: [SignpostResult]

  @Guide(description: "One sentence summary of this exchange (80 chars max) for the rolling window")
  var exchangeSummary: String

  @Guide(description: "Any git branch names, commit messages, or PR references mentioned in this exchange")
  var gitContext: String?
}

// MARK: - Continuity Analysis Schema

/// Output schema for transcript continuity detection
@available(macOS 26.0, *)
@Generable(description: "Assessment of whether a new transcript continues the previous work thread")
struct ContinuityAnalysis: Sendable {
  @Guide(description: "True if this transcript continues work from the previous transcript")
  var isContinuation: Bool

  @Guide(description: "Confidence level between 0.0 (uncertain) and 1.0 (certain)", .range(0...1))
  var confidence: Double

  @Guide(description: "One sentence explaining the reasoning for this assessment")
  var reasoning: String
}

#endif // canImport(FoundationModels)
