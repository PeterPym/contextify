import Foundation

// MARK: - Exchange Model

/// Represents a single conversation exchange (user or assistant message)
struct Exchange: Sendable, Equatable {
  enum Role: String, Sendable, Codable {
    case user
    case assistant
  }

  let role: Role
  let text: String
  let timestamp: Date
}

// MARK: - Transcript Metadata

/// Metadata generated for a transcript session, stored in sidecar JSON
nonisolated struct TranscriptMetadata: Codable, Sendable, Equatable {
  var version: Int = 1
  var title: String
  var description: String
  var topics: [String]
  var confidence: Double
  var mayContainHallucinations: Bool
  var needsReview: Bool
  var generatedAt: Date
  var model: String
  var promptVersion: Int
  var generatorVersion: Int
  var transcriptSHA256: String
  var messageCount: Int
  var strategy: String
  var llmCalls: Int
  var latencyMs: Int

  enum CodingKeys: String, CodingKey {
    case version
    case title
    case description
    case topics
    case confidence
    case mayContainHallucinations
    case needsReview
    case generatedAt
    case model
    case promptVersion
    case generatorVersion
    case transcriptSHA256
    case messageCount
    case strategy
    case llmCalls
    case latencyMs
  }
}

// MARK: - Generation Strategy

enum GenerationStrategy: String, Sendable {
  case full
  case adaptive
  case bookends
  case signalFirst  // Two-pass: extract signals locally, then LLM on snippets only
}

// MARK: - Generation Metrics

struct GenerationMetrics: Sendable {
  let parseTimeMs: Int
  let samplingTimeMs: Int
  let llmTimeMs: Int
  let storageTimeMs: Int
  let totalTimeMs: Int
  let exchangeCount: Int
  let strategy: GenerationStrategy
  let success: Bool
  let needsReview: Bool
}
