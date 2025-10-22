import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "EmbeddingRepository")

/// Repository for managing embedding storage in the database
public protocol EmbeddingRepository: Sendable {
  /// Saves an embedding vector for a transcript entry
  func saveEmbedding(entryId: String, vector: [Float], version: Int) async throws

  /// Retrieves an embedding vector for a transcript entry
  func getEmbedding(entryId: String) async throws -> [Float]?

  /// Gets all entries that don't have embeddings for the specified version
  func getEntriesWithoutEmbeddings(version: Int, projectId: String?, minLength: Int) async throws -> [String]

  /// Gets all entries with embeddings (for similarity search)
  func getAllEntriesWithEmbeddings(version: Int, projectId: String?, minLength: Int) async throws -> [(entryId: String, embedding: [Float])]

  /// Counts entries by embedding status
  func countEmbeddings(version: Int, projectId: String?, minLength: Int) async throws -> (total: Int, embedded: Int, pending: Int)
}

/// GRDB implementation of EmbeddingRepository
public final class EmbeddingRepositoryImpl: EmbeddingRepository, @unchecked Sendable {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  public func saveEmbedding(entryId: String, vector: [Float], version: Int) async throws {
    let data = serializeEmbedding(vector)
    let now = Int(Date().timeIntervalSince1970)

    try await db.write { db in
      try db.execute(
        sql: """
          UPDATE transcript_entries
          SET embedding = ?, embedding_version = ?, embedding_generated_at = ?
          WHERE id = ?
        """,
        arguments: [data, version, now, entryId]
      )
    }

    logger.debug("Saved embedding for entry \(entryId, privacy: .public) (version \(version))")
  }

  public func getEmbedding(entryId: String) async throws -> [Float]? {
    try await db.read { db in
      guard let data = try Data.fetchOne(
        db,
        sql: "SELECT embedding FROM transcript_entries WHERE id = ? AND embedding IS NOT NULL",
        arguments: [entryId]
      ) else {
        return nil
      }

      return deserializeEmbedding(data)
    }
  }

  public func getEntriesWithoutEmbeddings(version: Int, projectId: String? = nil, minLength: Int = 100) async throws -> [String] {
    try await db.read { db in
      var sql = """
        SELECT id FROM transcript_entries
        WHERE (embedding IS NULL OR embedding_version != ?)
        AND length(content) >= ?
        """

      var arguments: [DatabaseValueConvertible] = [version, minLength]

      if let projectId = projectId {
        sql += " AND project_id = ?"
        arguments.append(projectId)
      }

      sql += " ORDER BY timestamp ASC"

      return try String.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    }
  }

  public func getAllEntriesWithEmbeddings(version: Int, projectId: String? = nil, minLength: Int = 100) async throws -> [(entryId: String, embedding: [Float])] {
    try await db.read { db in
      var sql = """
        SELECT id, embedding FROM transcript_entries
        WHERE embedding IS NOT NULL
        AND embedding_version = ?
        AND length(content) >= ?
        """

      var arguments: [DatabaseValueConvertible] = [version, minLength]

      if let projectId = projectId {
        sql += " AND project_id = ?"
        arguments.append(projectId)
      }

      sql += " ORDER BY timestamp ASC LIMIT 5000"

      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

      return rows.compactMap { row in
        guard let id: String = row["id"],
              let data: Data = row["embedding"] else {
          return nil
        }

        let vector = deserializeEmbedding(data)
        return (entryId: id, embedding: vector)
      }
    }
  }

  public func countEmbeddings(version: Int, projectId: String? = nil, minLength: Int = 100) async throws -> (total: Int, embedded: Int, pending: Int) {
    try await db.read { db in
      var baseSql = "SELECT COUNT(*) FROM transcript_entries WHERE length(content) >= ?"
      var arguments: [DatabaseValueConvertible] = [minLength]

      if let projectId = projectId {
        baseSql += " AND project_id = ?"
        arguments.append(projectId)
      }

      let total = try Int.fetchOne(db, sql: baseSql, arguments: StatementArguments(arguments)) ?? 0

      let embeddedSql = baseSql + " AND embedding IS NOT NULL AND embedding_version = ?"
      let embedded = try Int.fetchOne(db, sql: embeddedSql, arguments: StatementArguments(arguments + [version])) ?? 0

      let pending = total - embedded

      return (total: total, embedded: embedded, pending: pending)
    }
  }
}
