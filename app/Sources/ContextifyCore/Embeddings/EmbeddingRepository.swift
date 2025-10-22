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
  func getEntriesWithoutEmbeddings(version: Int, projectId: String?) async throws -> [String]

  /// Gets all entries with embeddings (for similarity search)
  func getAllEntriesWithEmbeddings(projectId: String?) async throws -> [(entryId: String, embedding: [Float])]

  /// Counts entries by embedding status
  func countEmbeddings(projectId: String?) async throws -> (total: Int, embedded: Int, pending: Int)
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

  public func getEntriesWithoutEmbeddings(version: Int, projectId: String? = nil) async throws -> [String] {
    try await db.read { db in
      var sql = """
        SELECT id FROM transcript_entries
        WHERE (embedding IS NULL OR embedding_version != ?)
        """

      var arguments: [DatabaseValueConvertible] = [version]

      if let projectId = projectId {
        sql += " AND project_id = ?"
        arguments.append(projectId)
      }

      sql += " ORDER BY timestamp ASC"

      return try String.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    }
  }

  public func getAllEntriesWithEmbeddings(projectId: String? = nil) async throws -> [(entryId: String, embedding: [Float])] {
    try await db.read { db in
      var sql = """
        SELECT id, embedding FROM transcript_entries
        WHERE embedding IS NOT NULL
        """

      var arguments: [DatabaseValueConvertible] = []

      if let projectId = projectId {
        sql += " AND project_id = ?"
        arguments.append(projectId)
      }

      sql += " ORDER BY timestamp ASC"

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

  public func countEmbeddings(projectId: String? = nil) async throws -> (total: Int, embedded: Int, pending: Int) {
    try await db.read { db in
      var baseSql = "SELECT COUNT(*) FROM transcript_entries"
      var whereClause = ""

      if let projectId = projectId {
        whereClause = " WHERE project_id = ?"
      }

      let total = try Int.fetchOne(db, sql: baseSql + whereClause, arguments: projectId.map { [$0] } ?? []) ?? 0

      let embeddedSql = baseSql + whereClause + (whereClause.isEmpty ? " WHERE" : " AND") + " embedding IS NOT NULL"
      let embedded = try Int.fetchOne(db, sql: embeddedSql, arguments: projectId.map { [$0] } ?? []) ?? 0

      let pending = total - embedded

      return (total: total, embedded: embedded, pending: pending)
    }
  }
}
