import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "EmbeddingOrchestrator")

/// Orchestrates batch embedding generation for transcript entries
public actor EmbeddingOrchestrator {
  private let embeddingService: EmbeddingService
  private nonisolated let repository: EmbeddingRepository
  private nonisolated let db: DatabasePool

  public init(embeddingService: EmbeddingService, repository: EmbeddingRepository, db: DatabasePool) {
    self.embeddingService = embeddingService
    self.repository = repository
    self.db = db
  }

  /// Progress update callback
  public struct Progress: Sendable {
    public let current: Int
    public let total: Int
    public let currentEntryId: String?
    public let estimatedSecondsRemaining: Int?

    public var percentage: Double {
      guard total > 0 else { return 0 }
      return Double(current) / Double(total) * 100
    }
  }

  /// Generates embeddings for all entries without embeddings
  /// - Parameters:
  ///   - version: Embedding version (default 1)
  ///   - projectId: Optional project filter
  ///   - batchSize: Number of entries to process in each batch (default 10)
  ///   - progress: Callback for progress updates
  /// - Returns: Statistics about the embedding run
  public func generateEmbeddingsForAllEntries(
    version: Int = 1,
    projectId: String? = nil,
    batchSize: Int = 10,
    progress: (@Sendable (Progress) -> Void)? = nil
  ) async throws -> GenerationStats {
    let startTime = Date()

    // Get all entries that need embeddings
    let pendingIds = try await repository.getEntriesWithoutEmbeddings(version: version, projectId: projectId)
    let total = pendingIds.count

    guard total > 0 else {
      logger.info("No entries need embeddings (version \(version))")
      return GenerationStats(
        totalProcessed: 0,
        succeeded: 0,
        failed: 0,
        skipped: 0,
        durationSeconds: 0,
        entriesPerSecond: 0
      )
    }

    logger.info("Starting batch embedding generation: \(total) entries (batch size: \(batchSize))")

    var succeeded = 0
    var failed = 0
    var processedEntries: [String] = []

    // Process in batches
    for (batchIndex, batch) in pendingIds.chunked(into: batchSize).enumerated() {
      let batchStartIndex = batchIndex * batchSize

      for (indexInBatch, entryId) in batch.enumerated() {
        let currentIndex = batchStartIndex + indexInBatch

        do {
          // Get entry content
          guard let content = try await fetchEntryContent(entryId: entryId) else {
            logger.warning("Entry \(entryId, privacy: .public) not found, skipping")
            failed += 1
            continue
          }

          // Skip empty content
          guard !content.isEmpty else {
            logger.debug("Entry \(entryId, privacy: .public) has empty content, skipping")
            failed += 1
            continue
          }

          // Generate embedding
          let vector = try await embeddingService.generateEmbedding(for: content)

          // Save to database
          try await repository.saveEmbedding(entryId: entryId, vector: vector, version: version)

          succeeded += 1
          processedEntries.append(entryId)

          // Report progress
          let elapsed = Date().timeIntervalSince(startTime)
          let rate = Double(succeeded) / elapsed
          let remaining = total - currentIndex - 1
          let estimatedSeconds = remaining > 0 ? Int(Double(remaining) / rate) : 0

          progress?(Progress(
            current: currentIndex + 1,
            total: total,
            currentEntryId: entryId,
            estimatedSecondsRemaining: estimatedSeconds
          ))

        } catch {
          logger.error("Failed to generate embedding for entry \(entryId, privacy: .public): \(error.localizedDescription)")
          failed += 1
        }
      }

      // Log batch completion
      logger.debug("Batch \(batchIndex + 1) complete: \(succeeded) succeeded, \(failed) failed")
    }

    let duration = Date().timeIntervalSince(startTime)
    let rate = duration > 0 ? Double(succeeded) / duration : 0

    let stats = GenerationStats(
      totalProcessed: succeeded + failed,
      succeeded: succeeded,
      failed: failed,
      skipped: 0,
      durationSeconds: duration,
      entriesPerSecond: rate
    )

    logger.info("Batch generation complete: \(succeeded)/\(total) succeeded in \(String(format: "%.1f", duration))s (\(String(format: "%.1f", rate)) entries/sec)")

    return stats
  }

  /// Fetches content for a specific entry
  private func fetchEntryContent(entryId: String) async throws -> String? {
    try await db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT content FROM transcript_entries WHERE id = ?",
        arguments: [entryId]
      )
    }
  }
}

// MARK: - Supporting Types

public struct GenerationStats: Sendable {
  public let totalProcessed: Int
  public let succeeded: Int
  public let failed: Int
  public let skipped: Int
  public let durationSeconds: TimeInterval
  public let entriesPerSecond: Double

  public var successRate: Double {
    guard totalProcessed > 0 else { return 0 }
    return Double(succeeded) / Double(totalProcessed) * 100
  }
}

// MARK: - Collection Extension

extension Array {
  /// Splits array into chunks of specified size
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}
