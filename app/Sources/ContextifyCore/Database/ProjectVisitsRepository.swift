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
      // Upsert visit record
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
    try db.read { db in
      // Count entries where created_at > last_viewed_at (or last_viewed_at is NULL)
      // JOIN through transcripts table since project_id lives there
      let count = try Int.fetchOne(db, sql: """
        SELECT COUNT(*)
        FROM transcript_entries e
        JOIN transcripts t ON t.id = e.transcript_id
        LEFT JOIN project_visits v ON v.project_id = t.project_id
        WHERE t.project_id = ?
          AND (v.last_viewed_at IS NULL OR e.created_at > v.last_viewed_at)
      """, arguments: [projectId])

      return count ?? 0
    }
  }

  public func getUnreadCounts() throws -> [String: Int] {
    try db.read { db in
      // Batch query for all projects with unread counts
      // More efficient: single pass without correlated subquery
      let rows = try Row.fetchAll(db, sql: """
        SELECT t.project_id, COUNT(*) AS unread
        FROM transcript_entries e
        JOIN transcripts t ON t.id = e.transcript_id
        LEFT JOIN project_visits v ON v.project_id = t.project_id
        WHERE (v.last_viewed_at IS NULL OR e.created_at > v.last_viewed_at)
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
