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
  public let parentId: String?
  public let parentContent: String?
  public let parentRole: String?

  public init(
    id: String,
    content: String,
    similarity: Float,
    role: String,
    timestamp: Date,
    projectId: String,
    parentId: String? = nil,
    parentContent: String? = nil,
    parentRole: String? = nil
  ) {
    self.id = id
    self.content = content
    self.similarity = similarity
    self.role = role
    self.timestamp = timestamp
    self.projectId = projectId
    self.parentId = parentId
    self.parentContent = parentContent
    self.parentRole = parentRole
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
  ///   - minLength: Minimum content length filter (default 100)
  /// - Returns: Array of search results sorted by similarity (highest first)
  public func search(query: String, topK: Int = 10, projectId: String? = nil, minLength: Int = 100) async throws -> [SearchResult] {
    let startTime = Date()

    // 1. Generate query embedding
    logger.debug("Generating query embedding for: '\(query, privacy: .public)'")
    let queryEmbedding = try await embeddingService.generateEmbedding(for: query)

    // 2. Fetch all entries with embeddings
    logger.debug("Fetching entries with embeddings (project: \(projectId ?? "all", privacy: .public), minLength: \(minLength))")
    let entries = try await fetchEntriesWithEmbeddings(projectId: projectId, minLength: minLength)

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

    // 5. Fetch parent content for results with parent_id
    let parentIds = Set(topResults.compactMap { $0.entry.parentId })
    let parentEntries = try await fetchParentEntries(parentIds: Array(parentIds))

    // 6. Convert to SearchResult with parent context
    let results = topResults.map { scored in
      let parent = scored.entry.parentId.flatMap { parentEntries[$0] }
      return SearchResult(
        id: scored.entry.id,
        content: scored.entry.content,
        similarity: scored.similarity,
        role: scored.entry.role,
        timestamp: scored.entry.timestamp,
        projectId: scored.entry.projectId,
        parentId: scored.entry.parentId,
        parentContent: parent?.content,
        parentRole: parent?.role
      )
    }

    let duration = Date().timeIntervalSince(startTime)
    logger.info("Search complete: \(results.count) results in \(String(format: "%.0f", duration * 1000))ms (searched \(entries.count) entries, fetched \(parentEntries.count) parent entries)")

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
    let parentId: String?
  }

  private func fetchEntriesWithEmbeddings(projectId: String?, minLength: Int = 100) async throws -> [EntryWithEmbedding] {
    try await db.read { db in
      var sql = """
        SELECT id, content, embedding, kind, timestamp, project_id, parent_id
        FROM transcript_entries
        WHERE embedding IS NOT NULL
        AND length(content) >= ?
        """

      var arguments: [DatabaseValueConvertible] = [minLength]

      if let projectId = projectId {
        sql += " AND project_id = ?"
        arguments.append(projectId)
      }

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

      return rows.compactMap { row in
        guard let id: String = row["id"],
              let content: String = row["content"],
              let embeddingData: Data = row["embedding"],
              let kind: String = row["kind"],
              let timestampInt: Int = row["timestamp"],
              let projectId: String = row["project_id"] else {
          return nil
        }

        let parentId: String? = row["parent_id"]
        let embedding = deserializeEmbedding(embeddingData)
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampInt))

        return EntryWithEmbedding(
          id: id,
          content: content,
          embedding: embedding,
          role: kind,
          timestamp: timestamp,
          projectId: projectId,
          parentId: parentId
        )
      }
    }
  }

  private struct ParentEntry {
    let content: String
    let role: String
  }

  private func fetchParentEntries(parentIds: [String]) async throws -> [String: ParentEntry] {
    guard !parentIds.isEmpty else { return [:] }

    return try await db.read { db in
      let placeholders = Array(repeating: "?", count: parentIds.count).joined(separator: ",")
      let sql = """
        SELECT id, content, kind
        FROM transcript_entries
        WHERE id IN (\(placeholders))
        """

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(parentIds))

      var result: [String: ParentEntry] = [:]
      for row in rows {
        guard let id: String = row["id"],
              let content: String = row["content"],
              let kind: String = row["kind"] else {
          continue
        }

        result[id] = ParentEntry(content: content, role: kind)
      }

      return result
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
