import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "ProjectStats")

/// Detailed statistics about a project
public struct ProjectStatistics: Sendable {
  public let projectId: String
  public let projectName: String
  public let transcriptCount: Int
  public let entryCount: Int
  public let searchableEntryCount: Int  // Entries with embeddings
  public let lastActivity: Date?
  public let firstActivity: Date?
  public let providers: Set<String>
  public let topicBreakdown: [String: Int]  // Entry counts by approximate topic

  public init(
    projectId: String,
    projectName: String,
    transcriptCount: Int,
    entryCount: Int,
    searchableEntryCount: Int,
    lastActivity: Date?,
    firstActivity: Date?,
    providers: Set<String>,
    topicBreakdown: [String: Int]
  ) {
    self.projectId = projectId
    self.projectName = projectName
    self.transcriptCount = transcriptCount
    self.entryCount = entryCount
    self.searchableEntryCount = searchableEntryCount
    self.lastActivity = lastActivity
    self.firstActivity = firstActivity
    self.providers = providers
    self.topicBreakdown = topicBreakdown
  }
}

/// Service for computing detailed project statistics
public actor ProjectStatsService {
  private let db: DatabasePool

  public init(db: DatabasePool) {
    self.db = db
  }

  // MARK: - Private Helpers

  /// Normalizes timestamp from database (handles both seconds and milliseconds)
  /// Timestamps > 10^12 are treated as milliseconds
  private func normalizeTimestamp(_ raw: Int?) -> TimeInterval? {
    guard let v = raw else { return nil }
    // Treat values > 10^12 as milliseconds (e.g., 2025-epoch in ms ≈ 1.7e12)
    return TimeInterval(v > 1_000_000_000_000 ? v / 1000 : v)
  }

  // MARK: - Public API

  /// Gets comprehensive statistics for a project
  /// - Parameter projectId: The project path
  /// - Returns: Detailed statistics
  public func getStatistics(for projectId: String) async throws -> ProjectStatistics {
    logger.debug("Computing statistics for project: \(projectId)")

    return try db.read { db in
      // Basic counts
      let transcriptCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcripts WHERE project_id = ?
        """, arguments: [projectId]) ?? 0

      let entryCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcript_entries WHERE project_id = ?
        """, arguments: [projectId]) ?? 0

      let searchableCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcript_entries
        WHERE project_id = ? AND embedding IS NOT NULL
        """, arguments: [projectId]) ?? 0

      // Activity timestamps
      let lastActivity: Date? = try {
        guard let timestamp = try Int.fetchOne(db, sql: """
          SELECT MAX(timestamp) FROM transcript_entries WHERE project_id = ?
          """, arguments: [projectId]),
              let normalized = normalizeTimestamp(timestamp) else {
          return nil
        }
        return Date(timeIntervalSince1970: normalized)
      }()

      let firstActivity: Date? = try {
        guard let timestamp = try Int.fetchOne(db, sql: """
          SELECT MIN(timestamp) FROM transcript_entries WHERE project_id = ?
          """, arguments: [projectId]),
              let normalized = normalizeTimestamp(timestamp) else {
          return nil
        }
        return Date(timeIntervalSince1970: normalized)
      }()

      // Providers
      let providerRows = try Row.fetchAll(db, sql: """
        SELECT DISTINCT provider FROM transcripts WHERE project_id = ?
        """, arguments: [projectId])

      let providers = Set(providerRows.compactMap { $0["provider"] as String? })

      // Topic breakdown (simplified: use role as proxy)
      let topicRows = try Row.fetchAll(db, sql: """
        SELECT role, COUNT(*) as count
        FROM transcript_entries
        WHERE project_id = ?
        GROUP BY role
        """, arguments: [projectId])

      var topicBreakdown: [String: Int] = [:]
      for row in topicRows {
        if let role: String = row["role"], let count: Int = row["count"] {
          topicBreakdown[role.capitalized] = count
        }
      }

      // Project name (from path)
      let projectName = URL(fileURLWithPath: projectId).lastPathComponent

      return ProjectStatistics(
        projectId: projectId,
        projectName: projectName,
        transcriptCount: transcriptCount,
        entryCount: entryCount,
        searchableEntryCount: searchableCount,
        lastActivity: lastActivity,
        firstActivity: firstActivity,
        providers: providers,
        topicBreakdown: topicBreakdown
      )
    }
  }

  /// Gets statistics for all projects
  /// - Returns: Array of statistics for each project in the database
  public func getAllStatistics() async throws -> [ProjectStatistics] {
    logger.debug("Computing statistics for all projects")

    // Get all distinct project IDs
    let projectIds = try db.read { db in
      try String.fetchAll(db, sql: """
        SELECT DISTINCT project_id FROM transcripts
        """)
    }

    var stats: [ProjectStatistics] = []

    for projectId in projectIds {
      // Reuse single-project logic
      if let projectStats = try? await getStatistics(for: projectId) {
        stats.append(projectStats)
      }
    }

    return stats.sorted {
      ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
    }
  }

  /// Gets activity timeline for a project (entries per day)
  /// - Parameters:
  ///   - projectId: The project path
  ///   - days: Number of days to include (default 30)
  /// - Returns: Dictionary of date -> entry count
  public func getActivityTimeline(for projectId: String, days: Int = 30) async throws -> [Date: Int] {
    logger.debug("Computing activity timeline for project: \(projectId)")

    return try db.read { db in
      let startTimestamp = Int(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)

      let rows = try Row.fetchAll(db, sql: """
        SELECT
          DATE(timestamp, 'unixepoch') as day,
          COUNT(*) as count
        FROM transcript_entries
        WHERE project_id = ? AND timestamp >= ?
        GROUP BY day
        ORDER BY day
        """, arguments: [projectId, startTimestamp])

      var timeline: [Date: Int] = [:]

      // Use DateFormatter for "yyyy-MM-dd" format from SQL DATE()
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .iso8601)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"

      for row in rows {
        guard let dayString: String = row["day"],
              let count: Int = row["count"],
              let date = formatter.date(from: dayString) else {
          continue
        }

        timeline[date] = count
      }

      return timeline
    }
  }
}
