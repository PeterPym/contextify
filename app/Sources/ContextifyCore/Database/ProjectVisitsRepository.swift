import Foundation
import GRDB

/// Visit information for a project (for unread tracking)
public struct ProjectVisit: Codable, FetchableRecord, PersistableRecord {
  public let projectId: String
  public var lastViewedAt: String?  // ISO8601Z UTC
  public var lastSelectedAt: String?  // ISO8601Z UTC
  public var pinned: Bool

  enum CodingKeys: String, CodingKey {
    case projectId = "project_id"
    case lastViewedAt = "last_viewed_at"
    case lastSelectedAt = "last_selected_at"
    case pinned
  }

  public static let databaseTableName = "project_visits"

  public init(projectId: String, lastViewedAt: String? = nil, lastSelectedAt: String? = nil, pinned: Bool = false) {
    self.projectId = projectId
    self.lastViewedAt = lastViewedAt
    self.lastSelectedAt = lastSelectedAt
    self.pinned = pinned
  }
}

/// Project with unread count
public struct ProjectWithUnread: Sendable {
  public let projectId: String
  public let unreadCount: Int

  public init(projectId: String, unreadCount: Int) {
    self.projectId = projectId
    self.unreadCount = unreadCount
  }
}

public struct UnreadIndicatorResult: Sendable {
  public let accurateUnread: Int
  public let hasActivitySignal: Bool
  public let approxDelta: Int?
  public let approxConfidence: String?

  public init(
    accurateUnread: Int,
    hasActivitySignal: Bool,
    approxDelta: Int?,
    approxConfidence: String?
  ) {
    self.accurateUnread = accurateUnread
    self.hasActivitySignal = hasActivitySignal
    self.approxDelta = approxDelta
    self.approxConfidence = approxConfidence
  }
}

/// Repository for managing project visit tracking (for unread counts)
public protocol ProjectVisitsRepository {
  /// Mark a project as viewed at a specific timestamp
  /// - Parameters:
  ///   - projectId: Project ID
  ///   - timestamp: ISO8601Z UTC timestamp (e.g., "2025-10-27T12:00:00Z")
  func markViewed(projectId: String, timestamp: String) throws

  /// Mark a project as selected (updates last_selected_at to now)
  /// - Parameter projectId: Project ID
  func markSelected(projectId: String) throws

  /// Toggle pin status for a project
  /// - Parameter projectId: Project ID
  func togglePin(projectId: String) throws

  /// Get visit record for a project
  /// - Parameter projectId: Project ID
  /// - Returns: ProjectVisit if exists, nil otherwise
  func getVisit(projectId: String) throws -> ProjectVisit?

  /// Get unread count for a specific project
  /// - Parameter projectId: Project ID
  /// - Returns: Number of unread entries (created_at > last_viewed_at)
  func getUnreadCount(projectId: String) throws -> Int

  /// Get unread counts for all projects
  /// - Returns: Dictionary mapping project_id to unread count
  func getUnreadCounts() throws -> [String: Int]

  /// Get unread counts for specific projects (batch query)
  /// - Parameter projectIds: Array of project IDs
  /// - Returns: Dictionary mapping project_id to unread count
  func getUnreadCounts(projectIds: [String]) throws -> [String: Int]

  /// Get unread count using an existing database handle (for transactional callers)
  func unreadCount(projectId: String, in db: Database) throws -> Int

  /// Get unread indicator state for a project (accurate, approx, activity signal)
  func getUnreadIndicator(projectId: String) throws -> UnreadIndicatorResult

  /// Ensure visit record exists for a project (creates if missing)
  /// - Parameter projectId: Project ID
  func ensureVisit(projectId: String) throws
}

/// Implementation of ProjectVisitsRepository
public final class ProjectVisitsRepositoryImpl: ProjectVisitsRepository {
  private let db: DatabasePool
  private let clock: Clock

  public init(db: DatabasePool, clock: Clock = SystemClock()) {
    self.db = db
    self.clock = clock
  }

  public func markViewed(projectId: String, timestamp: String) throws {
    try db.write { db in
      // Update projects.last_viewed_ts with epoch timestamp (monotonic guard)
      // Convert ISO8601Z string to epoch seconds, truncate to milliseconds for consistency
      if let date = ISO8601Z.date(from: timestamp) {
        let epochSeconds = TimeUnits.truncateToMillis(date.timeIntervalSince1970)
        try db.execute(
          sql: "UPDATE projects SET last_viewed_ts = MAX(last_viewed_ts, ?) WHERE id = ?",
          arguments: [epochSeconds, projectId]
        )
      }

      // Also update project_visits for backward compatibility
      var visit = try ProjectVisit.fetchOne(db, key: projectId) ?? ProjectVisit(projectId: projectId)
      visit.lastViewedAt = timestamp
      try visit.save(db)
    }
  }

  public func markSelected(projectId: String) throws {
    try db.write { db in
      // Upsert visit record
      var visit = try ProjectVisit.fetchOne(db, key: projectId) ?? ProjectVisit(projectId: projectId)
      visit.lastSelectedAt = ISO8601Z.string(from: clock.now())
      try visit.save(db)
    }
  }

  public func togglePin(projectId: String) throws {
    try db.write { db in
      // Upsert visit record
      var visit = try ProjectVisit.fetchOne(db, key: projectId) ?? ProjectVisit(projectId: projectId)
      visit.pinned.toggle()
      try visit.save(db)
    }
  }

  public func getVisit(projectId: String) throws -> ProjectVisit? {
    try db.read { db in
      try ProjectVisit.fetchOne(db, key: projectId)
    }
  }

  public func getUnreadCount(projectId: String) throws -> Int {
    try db.read { try unreadCount(projectId: projectId, in: $0) }
  }

  public func unreadCount(projectId: String, in db: Database) throws -> Int {
    // Count entries where created_ts > last_viewed_ts (epoch timestamps)
    // Uses project.last_viewed_ts directly (not project_visits table)
    // Falls back to timestamp field if created_ts is NULL (transition entries)
    let count = try Int.fetchOne(db, sql: """
      SELECT COUNT(*)
      FROM transcript_entries e
      JOIN transcripts t ON t.id = e.transcript_id
      JOIN projects p ON p.id = t.project_id
      WHERE p.id = ?
        AND COALESCE(e.created_ts, CAST(e.timestamp AS REAL)) > p.last_viewed_ts
        AND e.display_in_timeline = 1
        AND e.is_sidechain = 0
    """, arguments: [projectId])

    return count ?? 0
  }

  public func getUnreadCounts() throws -> [String: Int] {
    try db.read { db in
      // Batch query for all projects with unread counts (epoch timestamps)
      // Uses project.last_viewed_ts directly (defaults to 0, so all entries are unread initially)
      // Falls back to timestamp field if created_ts is NULL (transition entries)
      let rows = try Row.fetchAll(db, sql: """
        SELECT t.project_id, COUNT(*) AS unread
        FROM transcript_entries e
        JOIN transcripts t ON t.id = e.transcript_id
        JOIN projects p ON p.id = t.project_id
        WHERE COALESCE(e.created_ts, CAST(e.timestamp AS REAL)) > p.last_viewed_ts
          AND e.display_in_timeline = 1
          AND e.is_sidechain = 0
        GROUP BY t.project_id
      """)

      var result: [String: Int] = [:]
      for row in rows {
        let projectId: String = row["project_id"]
        let unread: Int = row["unread"]
        result[projectId] = unread
      }

      return result
    }
  }

  public func getUnreadCounts(projectIds: [String]) throws -> [String: Int] {
    guard !projectIds.isEmpty else { return [:] }

    return try db.read { db in
      // Build parameterized query with IN clause (epoch timestamps)
      // Falls back to timestamp field if created_ts is NULL (transition entries)
      let placeholders = Array(repeating: "?", count: projectIds.count).joined(separator: ",")
      let rows = try Row.fetchAll(db, sql: """
        SELECT t.project_id AS pid, COUNT(*) AS c
        FROM transcript_entries e
        JOIN transcripts t ON t.id = e.transcript_id
        JOIN projects p ON p.id = t.project_id
        WHERE t.project_id IN (\(placeholders))
          AND COALESCE(e.created_ts, CAST(e.timestamp AS REAL)) > p.last_viewed_ts
          AND e.display_in_timeline = 1
          AND e.is_sidechain = 0
        GROUP BY t.project_id
      """, arguments: StatementArguments(projectIds))

      var result: [String: Int] = [:]
      for row in rows {
        let pid: String = row["pid"]
        let c: Int = row["c"]
        result[pid] = c
      }
      return result
    }
  }

  public func getUnreadIndicator(projectId: String) throws -> UnreadIndicatorResult {
    try db.read { db in
      let accurateUnread = try unreadCount(projectId: projectId, in: db)

      let projectRow = try Row.fetchOne(
        db,
        sql: """
          SELECT last_viewed_ts, last_activity_detected_at
          FROM projects
          WHERE id = ?
        """,
        arguments: [projectId]
      )
      let lastViewedTs = projectRow?["last_viewed_ts"] as Double? ?? 0
      let lastActivityDetectedAt = projectRow?["last_activity_detected_at"] as Int?
      let hasActivitySignal = lastActivityDetectedAt.map { Double($0) > lastViewedTs } ?? false

      let approxRow = try Row.fetchOne(
        db,
        sql: """
          SELECT
            SUM(unread_approx_count) AS approx_sum,
            MAX(
              CASE unread_approx_confidence
                WHEN 'high' THEN 2
                WHEN 'medium' THEN 1
                ELSE 0
              END
            ) AS confidence_rank
          FROM transcripts
          WHERE project_id = ?
            AND pending_rehoover = 1
            AND unread_approx_count IS NOT NULL
            AND unread_approx_confidence IN ('medium','high')
        """,
        arguments: [projectId]
      )

      let approxSum = approxRow?["approx_sum"] as Int?
      let confidenceRank = approxRow?["confidence_rank"] as Int? ?? 0
      let approxConfidence: String?
      switch confidenceRank {
      case 2:
        approxConfidence = "high"
      case 1:
        approxConfidence = "medium"
      default:
        approxConfidence = nil
      }

      let approxDelta = (approxSum ?? 0) > 0 ? approxSum : nil

      return UnreadIndicatorResult(
        accurateUnread: accurateUnread,
        hasActivitySignal: hasActivitySignal,
        approxDelta: approxDelta,
        approxConfidence: approxConfidence
      )
    }
  }

  public func ensureVisit(projectId: String) throws {
    try db.write { db in
      // Check if visit exists, if not create one with NULL last_viewed_at
      if try ProjectVisit.fetchOne(db, key: projectId) == nil {
        let visit = ProjectVisit(projectId: projectId)
        try visit.insert(db)
      }
    }
  }
}
