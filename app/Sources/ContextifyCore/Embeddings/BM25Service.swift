import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "BM25")

/// BM25 (Best Matching 25) keyword search implementation
/// Probabilistic ranking function that combines term frequency, inverse document frequency,
/// and document length normalization for effective keyword-based retrieval.
public actor BM25Service {
  private let db: DatabasePool

  // BM25 tuning parameters
  private let k1: Double = 1.2  // Term frequency saturation parameter
  private let b: Double = 0.75   // Length normalization parameter

  public init(db: DatabasePool) {
    self.db = db
  }

  /// Performs BM25 keyword search across transcript entries
  /// - Parameters:
  ///   - query: Search query text
  ///   - topK: Number of top results to return
  ///   - projectId: Optional project filter
  ///   - minLength: Minimum content length filter
  /// - Returns: Array of (entryId, bm25Score) sorted by score descending
  public func search(
    query: String,
    topK: Int = 20,
    projectId: String? = nil,
    minLength: Int = 100
  ) async throws -> [(entryId: String, score: Double)] {
    let startTime = Date()

    // Tokenize query (simple whitespace + lowercase)
    let queryTerms = tokenize(query)
    guard !queryTerms.isEmpty else {
      logger.warning("Empty query after tokenization")
      return []
    }

    logger.debug("BM25 search for: \(queryTerms.joined(separator: " "))")

    // Compute BM25 scores
    let results = try await computeBM25Scores(
      queryTerms: queryTerms,
      projectId: projectId,
      minLength: minLength
    )

    // Sort by score descending and take top-K
    let topResults = results
      .sorted { $0.score > $1.score }
      .prefix(topK)
      .map { (entryId: $0.entryId, score: $0.score) }

    let duration = Date().timeIntervalSince(startTime)
    logger.info("BM25 search complete: \(topResults.count) results in \(String(format: "%.0f", duration * 1000))ms")

    return topResults
  }

  // MARK: - Private Helpers

  private struct DocumentStats {
    let entryId: String
    let content: String
    let length: Int
  }

  private struct ScoredResult {
    let entryId: String
    let score: Double
  }

  /// Compute BM25 scores for all documents matching the filter
  private func computeBM25Scores(
    queryTerms: [String],
    projectId: String?,
    minLength: Int
  ) async throws -> [ScoredResult] {
    try await db.read { db in
      // Fetch all eligible documents
      var sql = """
        SELECT id, content
        FROM transcript_entries
        WHERE length(content) >= ?
        """
      var arguments: [DatabaseValueConvertible] = [minLength]

      if let projectId = projectId {
        sql += " AND project_id = ?"
        arguments.append(projectId)
      }

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

      let documents: [DocumentStats] = rows.compactMap { row in
        guard let id: String = row["id"],
              let content: String = row["content"] else {
          return nil
        }
        return DocumentStats(
          entryId: id,
          content: content,
          length: content.count
        )
      }

      guard !documents.isEmpty else {
        return []
      }

      // Compute statistics
      let totalDocs = documents.count
      let avgDocLength = Double(documents.map { $0.length }.reduce(0, +)) / Double(totalDocs)

      // Build inverted index for query terms
      let docFrequency = self.computeDocumentFrequencies(documents: documents, terms: queryTerms)

      // Compute BM25 for each document
      var results: [ScoredResult] = []

      for doc in documents {
        let score = self.computeBM25(
          document: doc,
          queryTerms: queryTerms,
          avgDocLength: avgDocLength,
          totalDocs: totalDocs,
          docFrequency: docFrequency
        )

        if score > 0 {
          results.append(ScoredResult(entryId: doc.entryId, score: score))
        }
      }

      return results
    }
  }

  /// Compute BM25 score for a single document
  nonisolated private func computeBM25(
    document: DocumentStats,
    queryTerms: [String],
    avgDocLength: Double,
    totalDocs: Int,
    docFrequency: [String: Int]
  ) -> Double {
    let docTokens = tokenize(document.content)
    let termFreq = computeTermFrequencies(tokens: docTokens)

    var score: Double = 0.0

    for term in queryTerms {
      guard let tf = termFreq[term], tf > 0 else {
        continue
      }

      // IDF component: log((N - df + 0.5) / (df + 0.5))
      let df = Double(docFrequency[term] ?? 0)
      let N = Double(totalDocs)
      let idf = log((N - df + 0.5) / (df + 0.5) + 1.0)  // +1 to avoid log(0)

      // Term frequency component with saturation
      let tfComponent = (Double(tf) * (k1 + 1.0)) / (Double(tf) + k1 * (1.0 - b + b * Double(document.length) / avgDocLength))

      score += idf * tfComponent
    }

    return score
  }

  /// Count how many documents contain each term
  nonisolated private func computeDocumentFrequencies(documents: [DocumentStats], terms: [String]) -> [String: Int] {
    var docFreq: [String: Int] = [:]

    for term in terms {
      var count = 0
      for doc in documents {
        let tokens = tokenize(doc.content)
        if tokens.contains(term) {
          count += 1
        }
      }
      docFreq[term] = count
    }

    return docFreq
  }

  /// Count term frequencies in a document
  nonisolated private func computeTermFrequencies(tokens: [String]) -> [String: Int] {
    var freq: [String: Int] = [:]
    for token in tokens {
      freq[token, default: 0] += 1
    }
    return freq
  }

  /// Simple tokenization: lowercase, split on whitespace and punctuation
  nonisolated private func tokenize(_ text: String) -> [String] {
    let lowercased = text.lowercased()

    // Split on whitespace and common punctuation
    let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let tokens = lowercased.components(separatedBy: separators)

    // Filter out empty strings and very short tokens
    return tokens.filter { $0.count >= 2 }
  }
}
