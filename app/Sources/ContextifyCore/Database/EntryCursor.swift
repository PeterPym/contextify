import Foundation

/// Composite cursor for deterministic incremental ingestion
/// Ensures no entries are skipped or duplicated under out-of-order arrival
/// Orders by (timestamp, created_at, id) with covering index support
public struct EntryCursor: Equatable, Codable, Sendable {
  public let timestamp: Int64
  public let createdAt: Int64
  public let id: String

  public init(timestamp: Int64, createdAt: Int64, id: String) {
    self.timestamp = timestamp
    self.createdAt = createdAt
    self.id = id
  }

  /// Initialize from a transcript entry
  public init(from entry: TranscriptEntry) {
    self.timestamp = Int64(entry.timestamp)
    self.createdAt = Int64(entry.createdAt)
    self.id = entry.id
  }
}

extension EntryCursor {
  enum CodingKeys: String, CodingKey {
    case timestamp = "ts"
    case createdAt = "ca"
    case id
  }
}
