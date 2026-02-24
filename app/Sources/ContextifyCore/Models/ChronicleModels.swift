import Foundation
import GRDB

// MARK: - Chronicle Enums

/// Status of a narrative arc
public enum ArcStatus: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
  case active
  case completing
  case completed
  case blocked
  case abandoned
}

/// Kind of narrative signpost
public enum SignpostKind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
  case decision
  case discovery
  case pivot
  case milestone
  case blocker
  case resolution
}

/// Signal that links two transcripts as part of the same work thread
public enum ContinuitySignal: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
  case clearCommand
  case compaction
  case timeProximity
  case explicitReference
}

// MARK: - ExchangeSummary

/// Lightweight summary of a single exchange, stored in NarrativeState.rollingWindowJson
public struct ExchangeSummary: Codable, Sendable, Equatable {
  public let entryId: String
  public let summary: String

  public init(entryId: String, summary: String) {
    self.entryId = entryId
    self.summary = summary
  }
}

// MARK: - ChronicleArc

/// A coherent thread of work toward a goal
public struct ChronicleArc: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
  public let id: String
  public let projectId: String
  public var intent: String
  public var strategicContext: String?
  public var status: ArcStatus
  public var parentArcId: String?
  public var discoveredFromEntryId: String?
  public var startedAt: Int  // Unix seconds
  public var completedAt: Int?  // Unix seconds
  public var lastActivityAt: Int  // Unix seconds
  public var transcriptIdsJson: String  // JSON array of transcript IDs

  public static let databaseTableName = "chronicle_arcs"

  enum CodingKeys: String, CodingKey {
    case id
    case projectId = "project_id"
    case intent
    case strategicContext = "strategic_context"
    case status
    case parentArcId = "parent_arc_id"
    case discoveredFromEntryId = "discovered_from_entry_id"
    case startedAt = "started_at"
    case completedAt = "completed_at"
    case lastActivityAt = "last_activity_at"
    case transcriptIdsJson = "transcript_ids_json"
  }

  /// Decoded transcript IDs from JSON storage
  public var transcriptIds: [String] {
    get {
      guard let data = transcriptIdsJson.data(using: .utf8),
            let ids = try? JSONDecoder().decode([String].self, from: data) else {
        return []
      }
      return ids
    }
  }

  /// Create a new transcript IDs JSON string from an array
  public static func encodeTranscriptIds(_ ids: [String]) -> String {
    guard let data = try? JSONEncoder().encode(ids),
          let json = String(data: data, encoding: .utf8) else {
      return "[]"
    }
    return json
  }

  public init(
    id: String = UUID().uuidString,
    projectId: String,
    intent: String,
    strategicContext: String? = nil,
    status: ArcStatus = .active,
    parentArcId: String? = nil,
    discoveredFromEntryId: String? = nil,
    startedAt: Int,
    completedAt: Int? = nil,
    lastActivityAt: Int,
    transcriptIdsJson: String = "[]"
  ) {
    self.id = id
    self.projectId = projectId
    self.intent = intent
    self.strategicContext = strategicContext
    self.status = status
    self.parentArcId = parentArcId
    self.discoveredFromEntryId = discoveredFromEntryId
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.lastActivityAt = lastActivityAt
    self.transcriptIdsJson = transcriptIdsJson
  }
}

// MARK: - ChronicleSignpost

/// A significant moment in the narrative (decision, discovery, pivot, etc.)
public struct ChronicleSignpost: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
  public let id: String
  public let arcId: String
  public var entryId: String?
  public var kind: SignpostKind
  public var summary: String
  public var detail: String?
  public var reasoning: String?
  public var revisitConditions: String?
  public var consequenceArcId: String?
  public var timestamp: Int  // Unix seconds

  public static let databaseTableName = "chronicle_signposts"

  enum CodingKeys: String, CodingKey {
    case id
    case arcId = "arc_id"
    case entryId = "entry_id"
    case kind
    case summary
    case detail
    case reasoning
    case revisitConditions = "revisit_conditions"
    case consequenceArcId = "consequence_arc_id"
    case timestamp
  }

  public init(
    id: String = UUID().uuidString,
    arcId: String,
    entryId: String? = nil,
    kind: SignpostKind,
    summary: String,
    detail: String? = nil,
    reasoning: String? = nil,
    revisitConditions: String? = nil,
    consequenceArcId: String? = nil,
    timestamp: Int
  ) {
    self.id = id
    self.arcId = arcId
    self.entryId = entryId
    self.kind = kind
    self.summary = summary
    self.detail = detail
    self.reasoning = reasoning
    self.revisitConditions = revisitConditions
    self.consequenceArcId = consequenceArcId
    self.timestamp = timestamp
  }
}

// MARK: - NarrativeState

/// Per-project rolling analysis state. Primary key is project_id.
public struct NarrativeState: Codable, FetchableRecord, PersistableRecord, Sendable {
  public let projectId: String
  public var currentArcId: String?
  public var arcStackJson: String  // JSON array of arc IDs (discovery chain stack)
  public var rollingWindowJson: String  // JSON array of ExchangeSummary
  public var lastProcessedEntryId: String?
  public var updatedAt: Int  // Unix seconds

  public static let databaseTableName = "chronicle_narrative_state"

  enum CodingKeys: String, CodingKey {
    case projectId = "project_id"
    case currentArcId = "current_arc_id"
    case arcStackJson = "arc_stack_json"
    case rollingWindowJson = "rolling_window_json"
    case lastProcessedEntryId = "last_processed_entry_id"
    case updatedAt = "updated_at"
  }

  /// Decoded arc stack from JSON storage
  public var arcStack: [String] {
    get {
      guard let data = arcStackJson.data(using: .utf8),
            let ids = try? JSONDecoder().decode([String].self, from: data) else {
        return []
      }
      return ids
    }
  }

  /// Decoded rolling window from JSON storage
  public var rollingWindow: [ExchangeSummary] {
    get {
      guard let data = rollingWindowJson.data(using: .utf8),
            let summaries = try? JSONDecoder().decode([ExchangeSummary].self, from: data) else {
        return []
      }
      return summaries
    }
  }

  /// Encode arc stack to JSON
  public static func encodeArcStack(_ ids: [String]) -> String {
    guard let data = try? JSONEncoder().encode(ids),
          let json = String(data: data, encoding: .utf8) else {
      return "[]"
    }
    return json
  }

  /// Encode rolling window to JSON
  public static func encodeRollingWindow(_ summaries: [ExchangeSummary]) -> String {
    guard let data = try? JSONEncoder().encode(summaries),
          let json = String(data: data, encoding: .utf8) else {
      return "[]"
    }
    return json
  }

  public init(
    projectId: String,
    currentArcId: String? = nil,
    arcStackJson: String = "[]",
    rollingWindowJson: String = "[]",
    lastProcessedEntryId: String? = nil,
    updatedAt: Int = Int(Date().timeIntervalSince1970)
  ) {
    self.projectId = projectId
    self.currentArcId = currentArcId
    self.arcStackJson = arcStackJson
    self.rollingWindowJson = rollingWindowJson
    self.lastProcessedEntryId = lastProcessedEntryId
    self.updatedAt = updatedAt
  }
}

// MARK: - TranscriptContinuity

/// Link between two transcripts that are part of the same narrative thread.
/// Composite primary key: (from_transcript_id, to_transcript_id)
public struct TranscriptContinuity: Codable, FetchableRecord, PersistableRecord, Sendable {
  public let fromTranscriptId: String
  public let toTranscriptId: String
  public var continuitySignal: ContinuitySignal
  public var confidence: Double
  public var detectedAt: Int  // Unix seconds

  public static let databaseTableName = "transcript_continuity"

  enum CodingKeys: String, CodingKey {
    case fromTranscriptId = "from_transcript_id"
    case toTranscriptId = "to_transcript_id"
    case continuitySignal = "continuity_signal"
    case confidence
    case detectedAt = "detected_at"
  }

  public init(
    fromTranscriptId: String,
    toTranscriptId: String,
    continuitySignal: ContinuitySignal,
    confidence: Double,
    detectedAt: Int = Int(Date().timeIntervalSince1970)
  ) {
    self.fromTranscriptId = fromTranscriptId
    self.toTranscriptId = toTranscriptId
    self.continuitySignal = continuitySignal
    self.confidence = confidence
    self.detectedAt = detectedAt
  }
}
