import Foundation
import GRDB
#if canImport(OSLog)
import OSLog
#endif

// MARK: - Protocol

/// Repository for Project Chronicle data (arcs, signposts, narrative state, continuity)
public protocol ChronicleRepositoryProtocol {
  // Arcs
  func saveArc(_ arc: ChronicleArc) throws
  func fetchActiveArcs(for projectId: String) throws -> [ChronicleArc]
  func fetchArc(id: String) throws -> ChronicleArc?
  func fetchArcs(for projectId: String) throws -> [ChronicleArc]
  func updateArcStatus(id: String, status: ArcStatus, completedAt: Int?) throws
  func updateArcActivity(id: String, lastActivityAt: Int, transcriptIdsJson: String) throws

  // Signposts
  func saveSignpost(_ signpost: ChronicleSignpost) throws
  func fetchSignposts(for arcId: String) throws -> [ChronicleSignpost]

  // Narrative State
  func saveNarrativeState(_ state: NarrativeState) throws
  func fetchNarrativeState(for projectId: String) throws -> NarrativeState?

  // Transcript Continuity
  func saveTranscriptContinuity(_ continuity: TranscriptContinuity) throws
  func fetchContinuity(from transcriptId: String) throws -> [TranscriptContinuity]
  func fetchContinuity(to transcriptId: String) throws -> [TranscriptContinuity]

  // Queries for analysis
  func fetchRecentEntries(
    for projectId: String,
    after entryId: String?,
    limit: Int
  ) throws -> [(id: String, kind: String, content: String, timestamp: Int, transcriptId: String)]
}

// MARK: - Implementation

/// GRDB-backed implementation of ChronicleRepositoryProtocol
public final class ChronicleRepositoryImpl: ChronicleRepositoryProtocol, @unchecked Sendable {
  // @unchecked Sendable: Thread safety delegated to GRDB DatabasePool (WAL mode, concurrent reads).
  // Same pattern as ProjectVisitsRepositoryImpl.

  private let db: DatabasePool

  #if canImport(OSLog)
  private let log = Logger(subsystem: "dev.contextify", category: "ChronicleRepository")
  #endif

  public init(db: DatabasePool) {
    self.db = db
  }

  // MARK: - Arcs

  public func saveArc(_ arc: ChronicleArc) throws {
    try db.write { db in
      try arc.save(db)
    }
  }

  public func fetchActiveArcs(for projectId: String) throws -> [ChronicleArc] {
    try db.read { db in
      try ChronicleArc
        .filter(Column("project_id") == projectId)
        .filter(Column("status") == ArcStatus.active.rawValue)
        .order(Column("last_activity_at").desc)
        .fetchAll(db)
    }
  }

  public func fetchArc(id: String) throws -> ChronicleArc? {
    try db.read { db in
      try ChronicleArc.fetchOne(db, key: id)
    }
  }

  public func fetchArcs(for projectId: String) throws -> [ChronicleArc] {
    try db.read { db in
      try ChronicleArc
        .filter(Column("project_id") == projectId)
        .order(Column("last_activity_at").desc)
        .fetchAll(db)
    }
  }

  public func updateArcStatus(id: String, status: ArcStatus, completedAt: Int?) throws {
    try db.write { db in
      try db.execute(
        sql: """
          UPDATE chronicle_arcs
          SET status = ?, completed_at = ?
          WHERE id = ?
        """,
        arguments: [status.rawValue, completedAt, id]
      )
    }
  }

  public func updateArcActivity(id: String, lastActivityAt: Int, transcriptIdsJson: String) throws {
    try db.write { db in
      try db.execute(
        sql: """
          UPDATE chronicle_arcs
          SET last_activity_at = ?, transcript_ids_json = ?
          WHERE id = ?
        """,
        arguments: [lastActivityAt, transcriptIdsJson, id]
      )
    }
  }

  // MARK: - Signposts

  public func saveSignpost(_ signpost: ChronicleSignpost) throws {
    try db.write { db in
      try signpost.save(db)
    }
  }

  public func fetchSignposts(for arcId: String) throws -> [ChronicleSignpost] {
    try db.read { db in
      try ChronicleSignpost
        .filter(Column("arc_id") == arcId)
        .order(Column("timestamp").asc)
        .fetchAll(db)
    }
  }

  // MARK: - Narrative State

  public func saveNarrativeState(_ state: NarrativeState) throws {
    try db.write { db in
      // Upsert: NarrativeState PK is project_id
      try state.save(db)
    }
  }

  public func fetchNarrativeState(for projectId: String) throws -> NarrativeState? {
    try db.read { db in
      try NarrativeState.fetchOne(db, key: projectId)
    }
  }

  // MARK: - Transcript Continuity

  public func saveTranscriptContinuity(_ continuity: TranscriptContinuity) throws {
    try db.write { db in
      try continuity.save(db)
    }
  }

  public func fetchContinuity(from transcriptId: String) throws -> [TranscriptContinuity] {
    try db.read { db in
      try TranscriptContinuity
        .filter(Column("from_transcript_id") == transcriptId)
        .fetchAll(db)
    }
  }

  public func fetchContinuity(to transcriptId: String) throws -> [TranscriptContinuity] {
    try db.read { db in
      try TranscriptContinuity
        .filter(Column("to_transcript_id") == transcriptId)
        .fetchAll(db)
    }
  }

  // MARK: - Entry Queries

  public func fetchRecentEntries(
    for projectId: String,
    after entryId: String?,
    limit: Int
  ) throws -> [(id: String, kind: String, content: String, timestamp: Int, transcriptId: String)] {
    try db.read { db in
      var sql: String
      var arguments: StatementArguments

      if let entryId {
        // Fetch entries after the checkpoint entry's timestamp, scoped to project.
        // CTE handles NULL (missing/deleted checkpoint): falls back to "latest N ASC".
        sql = """
          WITH checkpoint AS (
            SELECT timestamp AS ts
            FROM transcript_entries
            WHERE id = ? AND project_id = ?
          )
          SELECT e.id, e.kind, e.content, e.timestamp, e.transcript_id
          FROM transcript_entries e
          WHERE e.project_id = ?
            AND e.display_in_timeline = 1
            AND e.is_sidechain = 0
            AND (
              (SELECT ts FROM checkpoint) IS NULL
              OR e.timestamp > (SELECT ts FROM checkpoint)
            )
          ORDER BY e.timestamp ASC
          LIMIT ?
        """
        arguments = [entryId, projectId, projectId, limit]
      } else {
        // No checkpoint: take latest N entries but return them ASC for exchange pairing.
        sql = """
          SELECT id, kind, content, timestamp, transcript_id
          FROM (
            SELECT e.id, e.kind, e.content, e.timestamp, e.transcript_id
            FROM transcript_entries e
            WHERE e.project_id = ?
              AND e.display_in_timeline = 1
              AND e.is_sidechain = 0
            ORDER BY e.timestamp DESC
            LIMIT ?
          )
          ORDER BY timestamp ASC
        """
        arguments = [projectId, limit]
      }

      let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
      return rows.map { row in
        (
          id: row["id"] as String,
          kind: row["kind"] as String,
          content: row["content"] as String,
          timestamp: row["timestamp"] as Int,
          transcriptId: row["transcript_id"] as String
        )
      }
    }
  }
}
