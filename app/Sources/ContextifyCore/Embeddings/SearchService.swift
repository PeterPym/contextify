import Foundation
import GRDB
import Accelerate
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "SearchService")

/// Result from semantic search
public struct SearchResult: Sendable, Identifiable {
  public let id: String  // entry ID
  public let content: String
  public let similarity: Float
  public let role: String
  public let timestamp: Date
  public let projectId: String

  public init(id: String, content: String, similarity: Float, role: String, timestamp: Date, projectId: String) {
    self.id = id
    self.content = content
    self.similarity = similarity
    self.role = role
    self.timestamp = timestamp
    self.projectId = projectId
  }
}

/// Service for semantic search over embeddings
public actor SearchService {
  private let embeddingService: EmbeddingService
  private let repository: EmbeddingRepository
  private nonisolated let db: DatabasePool

  public init(embeddingService: EmbeddingService, repository: EmbeddingRepository, db: DatabasePool) {
    self.embeddingService = embeddingService
    self.repository = repository
    self.db = db
  }

  /// Performs semantic search using cosine similarity
  /// - Parameters:
  ///   - query: Search query text
  ///   - topK: Number of top results to return (default 10)
  ///   - projectId: Optional project filter
  /// - Returns: Array of search results sorted by similarity (highest first)
  public func search(query: String, topK: Int = 10, projectId: String? = nil) async throws -> [SearchResult] {
    let startTime = Date()

    // 1. Generate query embedding
    logger.debug("Generating query embedding for: '\(query, privacy: .public)'")
    let queryEmbedding = try await embeddingService.generateEmbedding(for: query)

    // 2. Fetch all entries with embeddings
    logger.debug("Fetching entries with embeddings (project: \(projectId ?? "all", privacy: .public))")
    let entries = try await fetchEntriesWithEmbeddings(projectId: projectId)

    guard !entries.isEmpty else {
      logger.warning("No entries with embeddings found")
      return []
    }

    logger.debug("Computing similarity for \(entries.count) entries")

    // 3. Compute similarities (optimized with Accelerate)
    var scoredResults: [(entry: EntryWithEmbedding, similarity: Float)] = []
    scoredResults.reserveCapacity(entries.count)

    for entry in entries {
      let similarity = cosineSimilarity(queryEmbedding, entry.embedding)
      scoredResults.append((entry: entry, similarity: similarity))
    }

    // 4. Sort by similarity (highest first) and take top-k
    scoredResults.sort { $0.similarity > $1.similarity }
    let topResults = scoredResults.prefix(topK)

    // 5. Convert to SearchResult
    let results = topResults.map { scored in
      SearchResult(
        id: scored.entry.id,
        content: scored.entry.content,
        similarity: scored.similarity,
        role: scored.entry.role,
        timestamp: scored.entry.timestamp,
        projectId: scored.entry.projectId
      )
    }

    let duration = Date().timeIntervalSince(startTime)
    logger.info("Search complete: \(results.count) results in \(String(format: "%.0f", duration * 1000))ms (searched \(entries.count) entries)")

    return results
  }

  // MARK: - Private Helpers

  private struct EntryWithEmbedding {
    let id: String
    let content: String
    let embedding: [Float]
    let role: String
    let timestamp: Date
    let projectId: String
  }

  private func fetchEntriesWithEmbeddings(projectId: String?) async throws -> [EntryWithEmbedding] {
    try await db.read { db in
      var sql = """
        SELECT id, content, embedding, role, timestamp, project_id
        FROM transcript_entries
        WHERE embedding IS NOT NULL
        """

      var arguments: [DatabaseValueConvertible] = []

      if let projectId = projectId {
        sql += " AND project_id = ?"
        arguments.append(projectId)
      }

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

      return rows.compactMap { row in
        guard let id: String = row["id"],
              let content: String = row["content"],
              let embeddingData: Data = row["embedding"],
              let role: String = row["role"],
              let timestampInt: Int = row["timestamp"],
              let projectId: String = row["project_id"] else {
          return nil
        }

        let embedding = deserializeEmbedding(embeddingData)
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampInt))

        return EntryWithEmbedding(
          id: id,
          content: content,
          embedding: embedding,
          role: role,
          timestamp: timestamp,
          projectId: projectId
        )
      }
    }
  }
}

// MARK: - Optimized Cosine Similarity

/// Computes cosine similarity using Apple's Accelerate framework for SIMD optimization
/// - Parameters:
///   - a: First vector
///   - b: Second vector
/// - Returns: Similarity score in range [-1, 1] where 1 = identical, 0 = orthogonal, -1 = opposite
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
  precondition(a.count == b.count, "Vectors must have same dimension")

  var dotProduct: Float = 0
  var normA: Float = 0
  var normB: Float = 0

  // Use Accelerate for vectorized operations (10-20x faster than naive loop)
  vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
  vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
  vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))

  let denominator = sqrt(normA) * sqrt(normB)

  guard denominator > 0 else {
    return 0  // Handle zero vectors
  }

  return dotProduct / denominator
}
