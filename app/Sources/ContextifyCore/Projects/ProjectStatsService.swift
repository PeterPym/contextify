import Foundation
import GRDB
import OSLog

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
  private let logger = Logger(subsystem: "dev.contextify", category: "ProjectStats")

  public init(db: DatabasePool) {
    self.db = db
  }

  // MARK: - Private Helpers

  /// Normalizes timestamp from database (handles both seconds and milliseconds)
  /// Timestamps > 10^12 are treated as milliseconds
  private static func normalizeTimestamp(_ raw: Int?) -> TimeInterval? {
    guard let v = raw else { return nil }
    // Treat values > 10^12 as milliseconds (e.g., 2025-epoch in ms ≈ 1.7e12)
    return TimeInterval(v > 1_000_000_000_000 ? v / 1000 : v)
  }

  // MARK: - Public API

  /// Gets comprehensive statistics for a project
  /// - Parameter projectId: Either projects.id (UUID) or projects.root_path (absolute path)
  /// - Returns: Detailed statistics
  public func getStatistics(for projectId: String) async throws -> ProjectStatistics {
    logger.debug("Computing statistics for project: \(projectId)")

    return try await db.read { db in
      // Resolve to canonical project UUID (supports both UUID and path lookups)
      let pid = try String.fetchOne(db, sql: """
        SELECT id FROM projects WHERE id = ? OR root_path = ? LIMIT 1
        """, arguments: [projectId, projectId])

      guard let pid = pid else {
        let projectName = URL(fileURLWithPath: projectId).lastPathComponent
        self.logger.notice("No project found for: \(projectId, privacy: .public)")
        return ProjectStatistics(
          projectId: projectId,
          projectName: projectName,
          transcriptCount: 0,
          entryCount: 0,
          searchableEntryCount: 0,
          lastActivity: nil,
          firstActivity: nil,
          providers: [],
          topicBreakdown: [:]
        )
      }

      // Basic counts
      let transcriptCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcripts WHERE project_id = ?
        """, arguments: [pid]) ?? 0

      let entryCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcript_entries WHERE project_id = ?
        """, arguments: [pid]) ?? 0

      let searchableCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcript_entries
        WHERE project_id = ? AND embedding IS NOT NULL
        """, arguments: [pid]) ?? 0

      // Activity timestamps
      let lastTimestamp = try Int.fetchOne(db, sql: """
        SELECT MAX(timestamp) FROM transcript_entries WHERE project_id = ?
        """, arguments: [pid])
      let lastActivity: Date? = Self.normalizeTimestamp(lastTimestamp).map {
        Date(timeIntervalSince1970: $0)
      }

      let firstTimestamp = try Int.fetchOne(db, sql: """
        SELECT MIN(timestamp) FROM transcript_entries WHERE project_id = ?
        """, arguments: [pid])
      let firstActivity: Date? = Self.normalizeTimestamp(firstTimestamp).map {
        Date(timeIntervalSince1970: $0)
      }

      // Providers
      let providerRows = try Row.fetchAll(db, sql: """
        SELECT DISTINCT provider FROM transcripts WHERE project_id = ?
        """, arguments: [pid])

      let providers = Set(providerRows.compactMap { $0["provider"] as String? })

      // Topic breakdown (simplified: use kind as proxy)
      let topicRows = try Row.fetchAll(db, sql: """
        SELECT kind, COUNT(*) as count
        FROM transcript_entries
        WHERE project_id = ?
        GROUP BY kind
        """, arguments: [pid])

      var topicBreakdown: [String: Int] = [:]
      for row in topicRows {
        if let kind: String = row["kind"], let count: Int = row["count"] {
          topicBreakdown[kind.capitalized] = count
        }
      }

      // Project name (from path)
      let projectName = URL(fileURLWithPath: projectId).lastPathComponent

      self.logger.notice("Stats for \(projectName, privacy: .public): \(transcriptCount) transcripts, \(entryCount) entries")

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
    let projectIds = try await db.read { db in
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
  ///   - projectId: Either projects.id (UUID) or projects.root_path (absolute path)
  ///   - days: Number of days to include (default 30)
  /// - Returns: Dictionary of date -> entry count
  public func getActivityTimeline(for projectId: String, days: Int = 30) async throws -> [Date: Int] {
    logger.debug("Computing activity timeline for project: \(projectId)")

    return try await db.read { db in
      // Resolve to canonical project UUID (supports both UUID and path lookups)
      guard let pid = try String.fetchOne(db, sql: """
        SELECT id FROM projects WHERE id = ? OR root_path = ? LIMIT 1
        """, arguments: [projectId, projectId]) else {
        self.logger.notice("No project found for timeline: \(projectId, privacy: .public)")
        return [:]
      }

      let startTimestamp = Int(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)

      let rows = try Row.fetchAll(db, sql: """
        SELECT
          DATE(timestamp, 'unixepoch') as day,
          COUNT(*) as count
        FROM transcript_entries
        WHERE project_id = ? AND timestamp >= ?
        GROUP BY day
        ORDER BY day
        """, arguments: [pid, startTimestamp])

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
