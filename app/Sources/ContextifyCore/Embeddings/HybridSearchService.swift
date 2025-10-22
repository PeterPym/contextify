import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "HybridSearch")

/// Hybrid search combining semantic similarity (embeddings) and keyword matching (BM25)
/// Uses Reciprocal Rank Fusion (RRF) to merge rankings from both approaches.
public actor HybridSearchService {
  private let semanticSearch: SearchService
  private let bm25Search: BM25Service
  private let db: DatabasePool

  // RRF constant (typically 60, controls rank position impact)
  private let k: Double = 60.0

  public init(semanticSearch: SearchService, bm25Search: BM25Service, db: DatabasePool) {
    self.semanticSearch = semanticSearch
    self.bm25Search = bm25Search
    self.db = db
  }

  /// Performs hybrid search using semantic similarity + keyword matching
  /// - Parameters:
  ///   - query: Search query text
  ///   - topK: Number of final results to return
  ///   - projectId: Optional project filter
  ///   - minLength: Minimum content length filter
  ///   - semanticWeight: Weight for semantic results (0.0-1.0, default 0.5)
  /// - Returns: Array of search results sorted by hybrid score
  public func search(
    query: String,
    topK: Int = 20,
    projectId: String? = nil,
    minLength: Int = 100,
    semanticWeight: Double = 0.5
  ) async throws -> [SearchResult] {
    let startTime = Date()

    // Run both searches in parallel
    async let semanticResults = semanticSearch.search(
      query: query,
      topK: topK * 2,  // Fetch more candidates for fusion
      projectId: projectId,
      minLength: minLength
    )

    async let bm25Results = bm25Search.search(
      query: query,
      topK: topK * 2,  // Fetch more candidates for fusion
      projectId: projectId,
      minLength: minLength
    )

    let (semantic, bm25) = try await (semanticResults, bm25Results)

    logger.debug("Semantic results: \(semantic.count), BM25 results: \(bm25.count)")

    // Merge using Reciprocal Rank Fusion
    let fusedScores = computeRRF(
      semanticResults: semantic,
      bm25Results: bm25,
      semanticWeight: semanticWeight
    )

    // Sort by fused score and take top-K
    let topEntries = fusedScores
      .sorted { $0.score > $1.score }
      .prefix(topK)

    // Normalize scores to 0-1 range for display
    let maxScore = topEntries.first?.score ?? 1.0
    let minScore = topEntries.last?.score ?? 0.0
    let scoreRange = maxScore - minScore

    // Fetch full entry details for top results
    let results = try await fetchSearchResults(entryIds: topEntries.map { $0.entryId })

    // Create a map for efficient lookup
    let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })

    // Build final results in sorted order (preserving topEntries ranking)
    let finalResults = topEntries.compactMap { entry -> SearchResult? in
      guard let result = resultMap[entry.entryId] else { return nil }

      // Normalize to 0-1 range (like cosine similarity)
      let normalizedScore: Float
      if scoreRange > 0 {
        normalizedScore = Float((entry.score - minScore) / scoreRange)
      } else {
        normalizedScore = 1.0  // All scores are the same
      }

      return SearchResult(
        id: result.id,
        content: result.content,
        similarity: normalizedScore,
        role: result.role,
        timestamp: result.timestamp,
        projectId: result.projectId,
        parentId: result.parentId,
        parentContent: result.parentContent,
        parentRole: result.parentRole
      )
    }

    let duration = Date().timeIntervalSince(startTime)
    logger.info("Hybrid search complete: \(finalResults.count) results in \(String(format: "%.0f", duration * 1000))ms")

    return finalResults
  }

  // MARK: - Reciprocal Rank Fusion

  private struct FusedResult {
    let entryId: String
    let score: Double
  }

  /// Combine semantic and BM25 rankings using Reciprocal Rank Fusion
  /// RRF formula: score(d) = Σ 1/(k + rank_i(d)) for each ranking system i
  private func computeRRF(
    semanticResults: [SearchResult],
    bm25Results: [(entryId: String, score: Double)],
    semanticWeight: Double
  ) -> [FusedResult] {
    // Build rank maps (lower rank = better)
    var semanticRanks: [String: Int] = [:]
    for (index, result) in semanticResults.enumerated() {
      semanticRanks[result.id] = index
    }

    var bm25Ranks: [String: Int] = [:]
    for (index, result) in bm25Results.enumerated() {
      bm25Ranks[result.entryId] = index
    }

    // Collect all unique document IDs
    let allEntryIds = Set(semanticRanks.keys).union(Set(bm25Ranks.keys))

    // Compute RRF score for each document
    var fusedResults: [FusedResult] = []

    for entryId in allEntryIds {
      var rrfScore: Double = 0.0

      // Semantic contribution (weighted)
      if let rank = semanticRanks[entryId] {
        rrfScore += semanticWeight / (k + Double(rank))
      }

      // BM25 contribution (weighted)
      if let rank = bm25Ranks[entryId] {
        rrfScore += (1.0 - semanticWeight) / (k + Double(rank))
      }

      fusedResults.append(FusedResult(entryId: entryId, score: rrfScore))
    }

    return fusedResults
  }

  // MARK: - Fetch Full Results

  private struct EntryWithParent {
    let id: String
    let content: String
    let role: String
    let timestamp: Date
    let projectId: String
    let parentId: String?
    let parentContent: String?
    let parentRole: String?
  }

  /// Fetch full entry details with parent context
  private func fetchSearchResults(entryIds: [String]) async throws -> [EntryWithParent] {
    guard !entryIds.isEmpty else { return [] }

    return try await db.read { db in
      // Fetch entries
      let placeholders = Array(repeating: "?", count: entryIds.count).joined(separator: ",")
      let entrySql = """
        SELECT id, content, kind, timestamp, project_id, parent_id
        FROM transcript_entries
        WHERE id IN (\(placeholders))
        """

      let entryRows = try Row.fetchAll(db, sql: entrySql, arguments: StatementArguments(entryIds))

      // Extract parent IDs
      let parentIds = entryRows.compactMap { row -> String? in
        row["parent_id"]
      }

      // Fetch parent entries
      var parentMap: [String: (content: String, role: String)] = [:]
      if !parentIds.isEmpty {
        let parentPlaceholders = Array(repeating: "?", count: parentIds.count).joined(separator: ",")
        let parentSql = """
          SELECT id, content, kind
          FROM transcript_entries
          WHERE id IN (\(parentPlaceholders))
          """

        let parentRows = try Row.fetchAll(db, sql: parentSql, arguments: StatementArguments(parentIds))

        for row in parentRows {
          guard let id: String = row["id"],
                let content: String = row["content"],
                let kind: String = row["kind"] else {
            continue
          }
          parentMap[id] = (content: content, role: kind)
        }
      }

      // Build results
      return entryRows.compactMap { row -> EntryWithParent? in
        guard let id: String = row["id"],
              let content: String = row["content"],
              let kind: String = row["kind"],
              let timestampInt: Int = row["timestamp"],
              let projectId: String = row["project_id"] else {
          return nil
        }

        let parentId: String? = row["parent_id"]
        let parent = parentId.flatMap { parentMap[$0] }

        return EntryWithParent(
          id: id,
          content: content,
          role: kind,
          timestamp: Date(timeIntervalSince1970: TimeInterval(timestampInt)),
          projectId: projectId,
          parentId: parentId,
          parentContent: parent?.content,
          parentRole: parent?.role
        )
      }
    }
  }
}
