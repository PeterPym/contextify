import Foundation
import GRDB
#if canImport(OSLog)
import OSLog
#endif

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

#if canImport(OSLog)
private let log = Logger(subsystem: "dev.contextify", category: "TranscriptOrchestrator")
#else
private let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "TranscriptOrchestrator")
#endif

// MARK: - Public API Types

/// Lightweight input for batch transcript discovery
public struct DiscoveredTranscript: Sendable {
  public let fileURL: URL
  public let provider: String
  public let sessionId: String?

  /// Compile-time enforced provider initialization (prevents "codex" drift)
  public init(fileURL: URL, provider: DiscoveredProject.Provider, sessionId: String?) {
    self.fileURL = fileURL
    self.provider = provider.rawValue
    self.sessionId = sessionId
  }

  /// Legacy string-based init (deprecated - use Provider enum)
  @available(*, deprecated, message: "Use init(fileURL:provider:sessionId:) with Provider enum")
  public init(fileURL: URL, providerString: String, sessionId: String?) {
    self.fileURL = fileURL
    self.provider = providerString
    self.sessionId = sessionId
  }
}

/// Output from transcript upsert with canonical ID
public struct ResolvedTranscript: Sendable {
  public let transcriptId: String
  public let fileURL: URL
  public let provider: String
  public let wasCreated: Bool  // true if new, false if existing

  public init(transcriptId: String, fileURL: URL, provider: String, wasCreated: Bool) {
    self.transcriptId = transcriptId
    self.fileURL = fileURL
    self.provider = provider
    self.wasCreated = wasCreated
  }
}

/// Result from getOrCreateProject indicating whether project was newly created
public struct ProjectLookupResult: Sendable {
  public let projectId: String
  public let wasCreated: Bool

  public init(projectId: String, wasCreated: Bool) {
    self.projectId = projectId
    self.wasCreated = wasCreated
  }
}

/// Pipeline readiness state for gating UI
public struct PipelineReadiness: Sendable {
  public var discoveryComplete: Bool
  public var dbUpdated: Bool
  public var watchersReady: Bool

  public var isReady: Bool {
    discoveryComplete && dbUpdated && watchersReady
  }

  public init(discoveryComplete: Bool = false, dbUpdated: Bool = false, watchersReady: Bool = false) {
    self.discoveryComplete = discoveryComplete
    self.dbUpdated = dbUpdated
    self.watchersReady = watchersReady
  }
}

public struct WatcherRecoverySummary: Sendable {
  public let projectId: String
  public let startedCount: Int
  public let alreadyActiveCount: Int
  public let missingFileCount: Int
  public let targetTranscriptId: String?
}

public struct WatcherPlanFailure: Sendable {
  public let transcriptId: String
  public let isFdExhaustion: Bool
  public let errorDescription: String
}

public struct WatcherPlanResult: Sendable {
  public let projectId: String
  public let startedCount: Int
  public let stoppedCount: Int
  public let failedStarts: [WatcherPlanFailure]
}

public enum IngestionMode {
  case preview(entries: Int)
  case complete

  var ingestLimit: IngestLimit {
    switch self {
    case let .preview(entries):
      return .entries(entries)
    case .complete:
      return .none
    }
  }
}

/// High-level orchestrator for transcript ingestion and monitoring
/// NOT @MainActor - allows safe concurrent access from background tasks
/// Sendable: GRDB pool handles thread-safety, repositories are stateless
///
/// ## Thread-Safety Contract
/// - **Reads**: Safe to call concurrently from any thread
/// - **Writes**: While technically safe via GRDB pool + WAL mode, concurrent writes from
///   multiple sources (e.g., ConversationMonitor debounce + ProjectSwitcher auto-reload)
///   may trigger "database is locked" errors under high load
/// - **Busy Timeout**: DatabaseManager configures 5-second busy timeout to reduce lock errors
/// - **Best Practice**: Callers should implement retry logic for transient database lock errors,
///   or serialize writes through a single actor/queue when possible
public final class TranscriptOrchestrator: @unchecked Sendable {
  private let dbManager: DatabaseManager
  private let projectRepo: ProjectRepository
  private let transcriptRepo: TranscriptRepository
  private let entryRepo: EntryRepository
  private let errorRepo: ParseErrorRepository
  private let metadataRepo: MetadataRepository
  nonisolated(unsafe) private let cacheRepo: CacheRepository  // Thread-safe via GRDB pool
  private let projectVisitsRepo: ProjectVisitsRepository
  private let tabGroupRepo: TabGroupRepository  // v33: Tab grouping
  private let worktreePreferenceRepo: WorktreePreferenceRepository  // v33: Worktree preferences

  private let hooverEngine: HooverEngine
  private let watcher: TranscriptWatcher
  private let validator: TranscriptValidator
  private let ingestionLockTTL: TimeInterval = 600

  private struct PrimerStatus: Sendable {
    let target: Int
    let startedAt: Date
    var ready: Bool
  }

  private struct PrimerTrackerState: Sendable {
    var statuses: [String: PrimerStatus] = [:]
    var readyCount: Int = 0
  }

  private let primerStatusLock = CrossPlatformLock(initialState: PrimerTrackerState())

  // Hoover scheduler for concurrency control
  private lazy var _hooverScheduler: HooverScheduler = HooverScheduler(
    orchestrator: self,
    maxConcurrency: ContextifyConfig.shared.maxConcurrentHoovers
  )

  public var hooverScheduler: HooverScheduler { _hooverScheduler }

  /// Number of active file watchers (for diagnostics and testing)
  public var watcherCount: Int { watcher.watcherCount }

  // v23: Write queue for serialized write operations (prevents SQLITE_BUSY)
  private let writeQueue: DatabaseWriteQueue

  // Performance: Bulk ingest manager bypasses GRDB observation overhead
  private let bulkIngestManager: BulkIngestManager?

  private let accessProvider: TranscriptAccessProvider?

  public init(
    dbManager: DatabaseManager,
    accessProvider: TranscriptAccessProvider? = nil
  ) throws {
    self.dbManager = dbManager
    self.accessProvider = accessProvider

    // Validate CLI transcript path if provided
    do {
      try PassthroughAccessProvider.validateTranscriptPath()
    } catch let error as TranscriptPathError {
      let msg = error.errorDescription ?? error.localizedDescription
      log.error("[BENCH] Transcript path validation failed: \(msg)")
      fputs("Error: \(msg)\n", stderr)
      exit(66)  // EX_NOINPUT
    }

    let pool = try dbManager.pool

    // v23: Initialize write queue early (P0-3: non-optional let)
    self.writeQueue = DatabaseWriteQueue(pool: pool)

    // Initialize repositories
    self.projectRepo = ProjectRepositoryImpl(db: pool)
    self.transcriptRepo = TranscriptRepositoryImpl(db: pool)
    self.entryRepo = EntryRepositoryImpl(db: pool)
    self.errorRepo = ParseErrorRepositoryImpl(db: pool)
    self.metadataRepo = MetadataRepositoryImpl(db: pool)
    self.cacheRepo = CacheRepositoryImpl(db: pool)
    self.projectVisitsRepo = ProjectVisitsRepositoryImpl(db: pool)
    self.tabGroupRepo = TabGroupRepositoryImpl(db: pool)  // v33
    self.worktreePreferenceRepo = WorktreePreferenceRepositoryImpl(db: pool)  // v33

    // v7: Initialize metadata repositories
    let fileSnapshotRepo = FileSnapshotRepositoryImpl(db: pool)
    let trackedFileRepo = TrackedFileRepositoryImpl(db: pool)
    let transcriptSummaryRepo = TranscriptSummaryRepositoryImpl(db: pool)
    let systemEventRepo = SystemEventRepositoryImpl(db: pool)
    let assistantUsageRepo = AssistantUsageRepositoryImpl(db: pool)

    // Initialize bulk ingest manager for high-performance writes
    // Uses separate DatabaseQueue to bypass GRDB observation overhead
    let dbPath = try dbManager.databasePath().path
    let bulkManager = BulkIngestManager(dbPath: dbPath)
    do {
      try bulkManager.open()
      self.bulkIngestManager = bulkManager
      log.info("[PERF] BulkIngestManager initialized for observation-free bulk ingest")
    } catch {
      log.warning("[ORCHESTRATOR] BulkIngestManager init failed, using standard path: \(error.localizedDescription)")
      self.bulkIngestManager = nil
    }

    // Initialize hoover engine with multi-provider parser
    let parser = MultiProviderParser()
    let metadataParser = MultiProviderMetadataParser()
    self.hooverEngine = HooverEngine(
      db: pool,
      transcriptRepo: transcriptRepo,
      entryRepo: entryRepo,
      errorRepo: errorRepo,
      projectRepo: projectRepo,
      parser: parser,
      fileSnapshotRepo: fileSnapshotRepo,
      trackedFileRepo: trackedFileRepo,
      transcriptSummaryRepo: transcriptSummaryRepo,
      systemEventRepo: systemEventRepo,
      assistantUsageRepo: assistantUsageRepo,
      metadataParser: metadataParser,
      bulkIngestManager: bulkIngestManager
    )

    // Initialize watcher (invalidation callback set after initialization)
    self.watcher = TranscriptWatcher(
      hooverEngine: hooverEngine,
      transcriptRepo: transcriptRepo,
      accessProvider: accessProvider
    )

    // Initialize validator
    self.validator = TranscriptValidator()

    // Set metadata invalidation callback with weak self reference
    watcher.setMetadataInvalidator { [weak self] transcriptId in
      try? self?.deleteMetadata(forTranscript: transcriptId)
    }

    // Set re-hoover callback to route through discoverTranscriptInternal (synchronous)
    watcher.setRehoover { [weak self] projectId, fileURL, provider, sessionId in
      try self?.discoverTranscriptInternal(
        projectId: projectId,
        fileURL: fileURL,
        provider: provider,
        providerSessionId: sessionId,
        startWatching: false,  // Already watching
        bypassScheduler: true
      )
    }
  }

  deinit {
    bulkIngestManager?.close()
  }

  // MARK: - Primer Tracking

  public func resetPrimerTracking() {
    primerStatusLock.withLock { state in
      state.statuses.removeAll()
      state.readyCount = 0
    }
  }

  public func registerPrimer(projectId: String, target: Int, startedAt: Date = Date()) {
    primerStatusLock.withLock { state in
      state.statuses[projectId] = PrimerStatus(target: target, startedAt: startedAt, ready: false)
    }
  }

  private func evaluatePrimerReadinessIfNeeded(projectId: String) {
    let shouldEvaluate = primerStatusLock.withLock { state in
      if let status = state.statuses[projectId] {
        return !status.ready
      }
      return false
    }

    guard shouldEvaluate else { return }

    let entryCount: Int
    do {
      entryCount = try getEntryCount(forProject: projectId)
    } catch {
      log.error("[PRIMER-ERROR] Failed to read entry count for \(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return
    }

    let snapshot = primerStatusLock.withLock { state -> (entries: Int, elapsedMs: Int, ready: Int, total: Int)? in
      guard var status = state.statuses[projectId], !status.ready else {
        return nil
      }

      guard entryCount >= status.target else { return nil }

      status.ready = true
      state.statuses[projectId] = status
      state.readyCount += 1
      let elapsedMs = Int(Date().timeIntervalSince(status.startedAt) * 1000)
      return (entryCount, elapsedMs, state.readyCount, state.statuses.count)
    }

    guard let snapshot else { return }

    log.info(
      "[PRIMER-READY] project=\(projectId, privacy: .public) entries=\(snapshot.entries, privacy: .public) elapsed_ms=\(snapshot.elapsedMs, privacy: .public)"
    )

    NotificationCenter.default.post(
      name: .timelinePrimerReady,
      object: projectId,
      userInfo: ["entries": snapshot.entries]
    )

    if snapshot.ready == snapshot.total {
      log.info("[PRIMER-ALL-READY] ready=\(snapshot.ready, privacy: .public)/\(snapshot.total, privacy: .public)")
    }
  }

  // MARK: - Project Management

  public func createProject(name: String?, rootPath: String, bookmark: Data?) throws -> String {
    try projectRepo.create(name: name, rootPath: rootPath, bookmark: bookmark)
  }

  public func getOrCreateProject(name: String?, rootPath: String, bookmark: Data? = nil) throws -> ProjectLookupResult {
    // Try to find existing project by canonicalized path
    let canon = PathUtils.canonicalizePath(rootPath)
    if let existing = try projectRepo.list().first(where: { $0.rootPath == canon }) {
      if LoggingConfig.enableVerboseProjectDiscovery {
        log.debug("Found existing project: \(existing.id) for path: \(canon)")
      }
      return ProjectLookupResult(projectId: existing.id, wasCreated: false)
    }

    // Create new project
    let projectId = try projectRepo.create(name: name, rootPath: rootPath, bookmark: bookmark)
    log.info("Created new project: \(projectId) for path: \(canon)")

    // Verify the project was created
    if let verified = try projectRepo.get(id: projectId) {
      log.info("✅ Project creation verified: \(verified.id)")
    } else {
      log.error("❌ Project creation failed - cannot retrieve project \(projectId)")
    }

    return ProjectLookupResult(projectId: projectId, wasCreated: true)
  }

  /// Convenience method for callers that only need the project ID
  public func getOrCreateProjectId(name: String?, rootPath: String, bookmark: Data? = nil) throws -> String {
    try getOrCreateProject(name: name, rootPath: rootPath, bookmark: bookmark).projectId
  }

  public func listProjects() throws -> [Project] {
    try projectRepo.list()
  }

  /// List projects for the tab switcher: display_order first, then activity.
  /// Excludes hidden projects.
  public func listProjectsForSwitcher() throws -> [Project] {
    try dbManager.pool.read { db in
      let sql = """
        SELECT p.*
        FROM projects p
        LEFT JOIN (
          SELECT project_id, MAX(created_ts) as max_entry_ts
          FROM transcript_entries
          GROUP BY project_id
        ) e ON p.id = e.project_id
        WHERE p.hidden = 0
        ORDER BY
          (p.display_order IS NULL) ASC,
          p.display_order ASC,
          COALESCE(e.max_entry_ts, 0) DESC,
          p.created_at DESC
        """
      return try Project.fetchAll(db, sql: sql)
    }
  }

  /// Seed display_order for projects that do not yet have a persisted order.
  public func seedDisplayOrderFromDiscoveryIfUnset(_ lightweightProjects: [LightweightProject]) throws {
    guard !lightweightProjects.isEmpty else { return }
    let pool = try dbManager.pool
    try pool.write { db in
      var seeded = 0
      var skipped = 0
      for (index, project) in lightweightProjects.enumerated() {
        let rootPath = project.canonicalRootPath
        try db.execute(sql: """
          UPDATE projects
          SET display_order = ?
          WHERE root_path = ?
            AND display_order IS NULL
        """, arguments: [index, rootPath])

        if db.changesCount > 0 {
          seeded += 1
        } else {
          skipped += 1
        }
      }

      if seeded > 0 {
        log.info("[DISPLAY-ORDER-SEED] seeded=\(seeded, privacy: .public) alreadySet=\(skipped, privacy: .public)")
      } else {
        log.info("[DISPLAY-ORDER-SEED] No projects required seeding (alreadySet=\(skipped, privacy: .public))")
      }
    }
  }

  /// Update projects table with lightweight metadata (NO transcript ingestion)
  /// Used by Phase 3 lazy loading architecture for fast startup
  /// This ONLY updates the projects table, not transcripts or entries
  public func updateProjectsMetadataOnly(_ lightweightProjects: [LightweightProject]) async throws {
    try await dbManager.pool.write { db in
      let nowSec = Int(Date().timeIntervalSince1970)

      for project in lightweightProjects {
        // Prefer decoded filesystem path when available.
        let canonicalRootPath = project.canonicalRootPath
        let hashedRootPath = PathUtils.canonicalizePath(project.path.path)

        // Case 1: Canonical row already exists (UUID or previously upgraded hash ID)
        if let canonicalRow = try Row.fetchOne(
          db,
          sql: "SELECT id FROM projects WHERE root_path = ?",
          arguments: [canonicalRootPath]
        ), let canonicalId: String = canonicalRow["id"] {
          try db.execute(sql: """
            UPDATE projects
            SET name = ?, updated_at = ?
            WHERE id = ?
          """, arguments: [project.displayName, nowSec, canonicalId])

          // Hide hash-based duplicate rows pointing at .claude folder paths.
          if hashedRootPath != canonicalRootPath,
             let hashRow = try Row.fetchOne(
               db,
               sql: "SELECT id FROM projects WHERE id = ? AND root_path = ?",
               arguments: [project.id, hashedRootPath]
             ),
             let hashId: String = hashRow["id"],
             hashId != canonicalId {
            try db.execute(sql: """
              UPDATE projects
              SET hidden = 1, updated_at = ?
              WHERE id = ?
            """, arguments: [nowSec, hashId])
            log.warning("[METADATA-ONLY] Hid duplicate hash project \(hashId, privacy: .public) (canonical: \(canonicalId, privacy: .public))")
          }
          continue
        }

        // Case 2: Only hash-path row exists – upgrade it to canonical root path.
        if hashedRootPath != canonicalRootPath,
           let hashRow = try Row.fetchOne(
             db,
             sql: "SELECT id FROM projects WHERE root_path = ?",
             arguments: [hashedRootPath]
           ),
           let hashId: String = hashRow["id"] {
          try db.execute(sql: """
            UPDATE projects
            SET root_path = ?, name = ?, updated_at = ?
            WHERE id = ?
          """, arguments: [canonicalRootPath, project.displayName, nowSec, hashId])
          log.info("[METADATA-ONLY] Canonicalized project \(hashId, privacy: .public) to \(canonicalRootPath, privacy: .public)")
          continue
        }

        // Case 3: Brand-new project – insert deterministic record
        let projectId = project.id
        try db.execute(sql: """
          INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
          VALUES (?, ?, ?, ?, ?, ?)
        """, arguments: [projectId, project.displayName, canonicalRootPath, nowSec, nowSec, nowSec])

        log.debug("[METADATA-ONLY] Created project: \(projectId, privacy: .public) with name: \(project.displayName, privacy: .public)")
      }

      log.info("[METADATA-ONLY] Updated \(lightweightProjects.count, privacy: .public) projects (metadata only, no transcripts)")
    }
  }

  /// Reset newest transcripts to partial to bootstrap FastPath when timeline is empty.
  public func forceResetIngestState(projectId: String, limit: Int) throws -> [String] {
    guard limit > 0 else { return [] }
    let pool = try dbManager.pool
    return try pool.write { db in
      let rows = try Row.fetchAll(db, sql: """
        SELECT id FROM transcripts
        WHERE project_id = ?
          AND status = 'active'
        ORDER BY updated_at DESC
        LIMIT ?
      """, arguments: [projectId, limit])

      let ids = rows.compactMap { $0["id"] as? String }
      guard !ids.isEmpty else { return [] }

      let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
      try db.execute(sql: """
        UPDATE transcripts
        SET ingest_state = 'partial',
            last_error = NULL
        WHERE id IN (\(placeholders))
      """, arguments: StatementArguments(ids))

      log.info("[INGEST-STATE-RESET] project=\(projectId, privacy: .public) count=\(ids.count, privacy: .public)")
      return ids
    }
  }

  /// Returns a map of project_id -> transcript entry count.
  public func getProjectEntryCounts() throws -> [String: Int] {
    try dbManager.pool.read { db in
      let sql = """
        SELECT project_id, COUNT(*) AS entry_count
        FROM transcript_entries
        GROUP BY project_id
        """
      var counts: [String: Int] = [:]
      for row in try Row.fetchAll(db, sql: sql) {
        if let projectId: String = row["project_id"],
           let entryCount: Int = row["entry_count"] {
          counts[projectId] = entryCount
        }
      }
      return counts
    }
  }

  /// Get the most recently viewed project (for auto-selection on first launch)
  ///
  /// Returns the project with the highest last_viewed_ts (most recently viewed).
  /// Falls back to most recently created project if all timestamps are zero.
  ///
  /// **Migration Safety:** Handles existing databases where last_viewed_ts may be
  /// zero for all projects (pre-v12 migrations or never-viewed projects).
  ///
  /// - Returns: Most recent project, or nil if no projects exist
  /// Get project with most recent transcript entry (for auto-selection on first launch)
  public func getProjectWithNewestEntry() throws -> Project? {
    try dbManager.pool.read { db in
      // Try to query for project ID with most recent entry timestamp
      // This may fail if entries table doesn't exist yet (fresh database)
      let projectId: String?
      do {
        let sql = """
          SELECT project_id
          FROM transcript_entries
          ORDER BY created_ts DESC
          LIMIT 1
        """
        projectId = try String.fetchOne(db, sql: sql)
        if let id = projectId {
          print("🔍 DEBUG: Found project from transcript_entries table: \(id)")
        } else {
          print("🔍 DEBUG: No transcript_entries found in table, falling back")
        }
      } catch {
        // Table doesn't exist or query failed - no entries yet
        print("🔍 DEBUG: Entries table query failed: \(error.localizedDescription)")
        projectId = nil
      }

      guard let projectId = projectId else {
        // No entries found - fall back to Contextify project itself, or most recently created
        print("🔍 DEBUG: No entries found, falling back to project selection")

        // First try: find project with "contextify" in the path (case-insensitive)
        if let contextifyProject = try Project
          .filter(sql: "LOWER(root_path) LIKE '%contextify%'")
          .limit(1)
          .fetchOne(db) {
          print("🔍 DEBUG: Fallback selected Contextify project: \(contextifyProject.rootPath)")
          return contextifyProject
        }

        // Second try: most recently created project
        let fallback = try Project
          .order(Column("created_at").desc)
          .limit(1)
          .fetchOne(db)
        if let fb = fallback {
          print("🔍 DEBUG: Fallback selected most recent project: \(fb.rootPath)")
        } else {
          print("🔍 DEBUG: No projects found at all!")
        }
        return fallback
      }

      // Fetch the project
      let project = try Project.fetchOne(db, key: projectId)
      if let p = project {
        print("🔍 DEBUG: Fetched project by ID: \(p.rootPath)")
      }
      return project
    }
  }

  /// Get project by last viewed timestamp (deprecated - use getProjectWithNewestEntry for auto-selection)
  @available(*, deprecated, renamed: "getProjectWithNewestEntry")
  public func getMostRecentProject() throws -> Project? {
    try dbManager.pool.read { db in
      // Try viewed projects first (preferred)
      if let recent = try Project
          .filter(Column("last_viewed_ts") > 0)
          .order(Column("last_viewed_ts").desc)
          .limit(1)
          .fetchOne(db) {
        return recent
      }

      // Fallback: most recently created (handles zero timestamps)
      return try Project
        .order(Column("created_at").desc)
        .limit(1)
        .fetchOne(db)
    }
  }

  public func getProject(id: String) throws -> Project? {
    try projectRepo.get(id: id)
  }

  /// Gets the set of providers (Claude Code, Codex, etc.) that have transcripts for a project
  /// - Parameter projectPath: Absolute path to project root
  /// - Returns: Set of provider types found in project's transcripts
  public func getProviders(forProjectPath projectPath: String) async throws -> Set<DiscoveredProject.Provider> {
    try await Self.getProviders(forProjectPath: projectPath, pool: dbManager.pool)
  }

  /// Static helper for querying providers without instantiating a full orchestrator.
  /// Use this for lightweight queries from Views where creating a full orchestrator is wasteful.
  public static func getProviders(forProjectPath projectPath: String, pool: DatabasePool) async throws -> Set<DiscoveredProject.Provider> {
    try await pool.read { db in
      let sql = """
        SELECT GROUP_CONCAT(DISTINCT t.provider) AS providers
        FROM projects p
        LEFT JOIN transcripts t ON t.project_id = p.id
        WHERE p.root_path = ?
        GROUP BY p.id
        LIMIT 1
        """

      guard let row = try Row.fetchOne(db, sql: sql, arguments: [projectPath]) else {
        return []
      }

      // Parse provider set from CSV of raw values
      let providersCSV: String? = row["providers"]
      var result: Set<DiscoveredProject.Provider> = []
      if let csv = providersCSV, !csv.isEmpty {
        for token in csv.split(separator: ",") {
          let raw = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
          // Tolerant mapping for legacy/variant provider strings
          if let p = DiscoveredProject.Provider(dbRaw: raw) ?? DiscoveredProject.Provider(rawValue: raw) {
            result.insert(p)
          } else {
            result.insert(.other)
          }
        }
      }
      return result
    }
  }

  /// Reset all display_order values to NULL for activity-based sorting
  /// (Used on first launch to ensure projects sort by newest entry)
  public func resetDisplayOrder() throws {
    log.info("[BACKEND-RESET-START] Resetting display_order to NULL")

    var rowsAffected = 0
    try dbManager.pool.write { db in
      try db.execute(sql: "UPDATE projects SET display_order = NULL")
      rowsAffected = db.changesCount
    }

    log.info("[BACKEND-RESET-DONE] Reset display_order → NULL for \(rowsAffected, privacy: .public) projects")

    // Verify: count projects with non-NULL display_order
    let nonNullCount = try dbManager.pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects WHERE display_order IS NOT NULL") ?? 0
    }

    if nonNullCount > 0 {
      log.warning("[BACKEND-RESET-VERIFY] ⚠️ Still have \(nonNullCount, privacy: .public) projects with non-NULL display_order!")
    } else {
      log.info("[BACKEND-RESET-VERIFY] ✓ All projects have NULL display_order")
    }
  }

  // MARK: - Git Branch Extraction (Transcript-Based)

  /// Get the current git branch from the most recent transcript entry for a project.
  /// This enables branch display in App Store builds without filesystem access.
  ///
  /// - Parameter projectId: SQL project ID
  /// - Returns: Branch name if found, nil otherwise
  public func getCurrentBranch(forProject projectId: String) throws -> String? {
    try dbManager.pool.read { db in
      // Get the most recent entry with a non-null git_branch
      // Both Claude Code and Codex parsers store branch data in this column
      let sql = """
        SELECT git_branch
        FROM transcript_entries
        WHERE project_id = ?
          AND git_branch IS NOT NULL
          AND git_branch != ''
        ORDER BY timestamp DESC, created_ts DESC
        LIMIT 1
        """
      return try String.fetchOne(db, sql: sql, arguments: [projectId])
    }
  }

  /// Get git branch with metadata about its source (for DMG validation logging)
  /// - Parameter projectId: SQL project ID
  /// - Returns: Tuple of (branch, provider, entryTimestamp) or nil
  public func getCurrentBranchWithMetadata(forProject projectId: String) throws -> (branch: String, provider: String?, timestamp: Int)? {
    try dbManager.pool.read { db in
      let sql = """
        SELECT git_branch, provider, timestamp
        FROM transcript_entries
        WHERE project_id = ?
          AND git_branch IS NOT NULL
          AND git_branch != ''
        ORDER BY timestamp DESC, created_ts DESC
        LIMIT 1
        """
      guard let row = try Row.fetchOne(db, sql: sql, arguments: [projectId]) else { return nil }
      let branch: String = row["git_branch"]
      let provider: String? = row["provider"]
      let timestamp: Int = row["timestamp"] ?? 0
      return (branch, provider, timestamp)
    }
  }

  public func setProjectHidden(projectId: String, hidden: Bool) throws {
    try projectRepo.setHidden(id: projectId, hidden: hidden)
  }

  /// Restore all hidden projects (set hidden=false for all projects)
  public func restoreAllHiddenProjects() throws {
    let now = Int(Date().timeIntervalSince1970)
    try dbManager.pool.write { db in
      try db.execute(sql: "UPDATE projects SET hidden = 0, updated_at = ? WHERE hidden = 1", arguments: [now])
    }
  }

  /// Count hidden projects
  public func countHiddenProjects() throws -> Int {
    try dbManager.pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects WHERE hidden = 1") ?? 0
    }
  }

  public func setProjectDisplayOrder(projectId: String, displayOrder: Int) throws {
    try projectRepo.setDisplayOrder(id: projectId, displayOrder: displayOrder)
  }

  /// Atomically update display order for all projects in a single transaction
  /// Uses two-phase update to avoid transient unique constraint violations if added later
  public func setProjectDisplayOrderBulk(_ orderedIds: [String]) throws {
    let now = Int(Date().timeIntervalSince1970)
    let writeBlock: () throws -> Void = {
      try self.dbManager.pool.write { db in
        // Phase 1: assign negative ranks preserving order (avoids odd ordering if observed mid-transaction)
        // Using -n ... -1 ensures proper ordering even in temporary state
        for (i, id) in orderedIds.enumerated() {
          let tempOrder = -(orderedIds.count - i)  // -count, -count+1, ..., -1
          try db.execute(sql: "UPDATE projects SET display_order = ? WHERE id = ?", arguments: [tempOrder, id])
        }
        // Phase 2: final non-negative ordering + updated_at
        for (i, id) in orderedIds.enumerated() {
          try db.execute(sql: "UPDATE projects SET display_order = ?, updated_at = ? WHERE id = ?", arguments: [i, now, id])
        }
      }
    }

    // One-shot retry on SQLITE_BUSY
    do {
      try writeBlock()
    } catch let e as DatabaseError where e.resultCode == .SQLITE_BUSY {
      usleep(50_000) // 50ms backoff
      try writeBlock()
    }
  }

  /// Seed display_order values using transcript modification times when no manual order exists.
  public func seedDisplayOrderFromTranscriptActivityIfUnset() throws {
    let hasExistingOrder = try dbManager.pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects WHERE display_order IS NOT NULL") ?? 0
    } > 0

    guard !hasExistingOrder else {
      log.info("[DISPLAY-ORDER-SEED] Skipping seed - display_order already populated")
      return
    }

    struct ActivityRow {
      let id: String
      let activity: Int
    }

    let rows: [ActivityRow] = try dbManager.pool.read { db in
      try Row.fetchAll(db, sql: """
        SELECT p.id AS id,
               COALESCE(MAX(t.mtime_ms), MAX(t.last_modified), p.updated_at) AS activity
        FROM projects p
        LEFT JOIN transcripts t ON t.project_id = p.id
        GROUP BY p.id
      """).compactMap { row in
        guard let id: String = row["id"] else { return nil }
        let activityValue = (row["activity"] as? Int64).map(Int.init) ?? 0
        return ActivityRow(id: id, activity: activityValue)
      }
    }

    let orderedIds = rows
      .sorted { $0.activity > $1.activity }
      .map(\.id)

    guard !orderedIds.isEmpty else {
      log.info("[DISPLAY-ORDER-SEED] No projects to seed")
      return
    }

    try setProjectDisplayOrderBulk(orderedIds)
    log.info("[DISPLAY-ORDER-SEED] Seeded display_order for \(orderedIds.count, privacy: .public) projects")
  }

  public func markProjectOrphaned(projectId: String, orphanedSince: Int) throws {
    try projectRepo.markOrphaned(id: projectId, orphanedSince: orphanedSince)
  }

  public func markProjectRestored(projectId: String) throws {
    try projectRepo.markRestored(id: projectId)
  }

  // MARK: - Transcript Discovery & Ingestion

  /// Discover and ingest a transcript file
  /// Internal method bypasses scheduler (prevents recursion)
  internal func discoverTranscriptInternal(
    projectId: String,
    fileURL: URL,
    provider: String,
    providerSessionId: String?,
    startWatching: Bool,
    bypassScheduler: Bool = false
  ) throws {
    log.info("[TRANS-DISC-START] Discovering transcript: \(fileURL.lastPathComponent, privacy: .public) provider: \(provider, privacy: .public) project: \(projectId, privacy: .public)")

    // Determine if this provider needs security-scoped access.
    let needsScope = needsSecurityScope(provider: provider)

    if needsScope, let accessProvider {
      try accessProvider.withAccess(for: provider) { root in
        // In debug builds, enforce that fileURL is under the root.
        assert(fileURL.path.hasPrefix(root.path), "fileURL not under provider root: \(fileURL.path) vs \(root.path)")
        try self.doDiscoverTranscript(
          projectId: projectId,
          fileURL: fileURL,
          provider: provider,
          providerSessionId: providerSessionId,
          startWatching: startWatching,
          progress: nil,
          ingestLimit: .none
        )
      }
    } else {
      // DMG build or provider without special scope.
      try self.doDiscoverTranscript(
        projectId: projectId,
        fileURL: fileURL,
        provider: provider,
        providerSessionId: providerSessionId,
        startWatching: startWatching,
        progress: nil,
        ingestLimit: .none
      )
    }
  }

  /// Public method routes through scheduler
  public func discoverTranscript(
    projectId: String,
    fileURL: URL,
    provider: String,
    providerSessionId: String?,
    startWatching: Bool = true,
    progress: IngestProgressSink? = nil,
    ingestLimit: IngestLimit = .none,
    isPrimer: Bool = false
  ) async throws {
    if ContextifyConfig.shared.hooverSchedulerEnabled {
      try await hooverScheduler.enqueue(
        projectId: projectId,
        fileURL: fileURL,
        provider: provider,
        sessionId: providerSessionId,
        isPrimer: isPrimer
      )
    } else {
      try discoverTranscriptInternal(
        projectId: projectId,
        fileURL: fileURL,
        provider: provider,
        providerSessionId: providerSessionId,
        startWatching: startWatching,
        bypassScheduler: true
      )
    }

    evaluatePrimerReadinessIfNeeded(projectId: projectId)
  }

  /// Evict stale preflight cache entries older than the specified age
  /// Call periodically (e.g., on app startup) to prevent unbounded cache growth
  public func evictStalePreflightCache(olderThanDays days: Int = 7) throws {
    let cutoffTime = Date().timeIntervalSince1970 - Double(days * 24 * 60 * 60)

    let deletedCount = try dbManager.pool.write { db in
      try db.execute(sql: """
        DELETE FROM transcript_preflight_cache
        WHERE checked_at < ?
      """, arguments: [cutoffTime])
      return db.changesCount
    }

    if deletedCount > 0 {
      log.info("[PREFLIGHT-EVICT] Evicted \(deletedCount, privacy: .public) stale cache entries (older than \(days, privacy: .public) days)")
    }
  }

  /// Delete preflight cache entry for a specific file
  /// TODO: Hook this into transcript deletion events (TranscriptWatcher, transcriptRepo.delete)
  /// For now, 7-day TTL in evictStalePreflightCache handles orphaned entries
  public func deletePreflightCacheEntry(fileURL: URL, provider: String) throws {
    try dbManager.pool.write { db in
      try db.execute(sql: """
        DELETE FROM transcript_preflight_cache
        WHERE file_path = ? AND provider = ?
      """, arguments: [fileURL.path, provider])
    }
    log.debug("[PREFLIGHT-DELETE] Removed cache entry for \(fileURL.lastPathComponent, privacy: .public)")
  }

  /// Check preflight cache and validate if needed
  /// Returns: (isValid, errorMessage)
  /// Query standalone cache table by (file_path, provider)
  private func checkPreflight(
    fileURL: URL,
    projectRootPath: String,
    provider: String
  ) throws -> (isValid: Bool, errorMessage: String?) {
    let currentMtime: Double

    if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
       let modDate = attrs[.modificationDate] as? Date {
      currentMtime = modDate.timeIntervalSince1970
    } else if let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let modDate = resourceValues.contentModificationDate {
      currentMtime = modDate.timeIntervalSince1970
      log.warning("[PREFLIGHT-MTIME-FALLBACK] Using resourceValues for \(fileURL.lastPathComponent, privacy: .public)")
    } else {
      currentMtime = 0
      log.error("[PREFLIGHT-MTIME-ERROR] Could not read mtime for \(fileURL.lastPathComponent, privacy: .public); cache will miss")
    }

    // Check standalone cache table (keyed by file_path + provider)
    let cached = try dbManager.pool.read { db in
      try Row.fetchOne(db, sql: """
        SELECT status, mtime, error
        FROM transcript_preflight_cache
        WHERE file_path = ? AND provider = ?
      """, arguments: [fileURL.path, provider])
    }

    if let row = cached,
       let status = row["status"] as? String,
       let cachedMtime = row["mtime"] as? Double,
       abs(cachedMtime - currentMtime) < 1.0 {

      log.info("[PREFLIGHT-CACHE-HIT] \(fileURL.lastPathComponent, privacy: .public): \(status, privacy: .public) (cached mtime: \(cachedMtime, privacy: .public), current: \(currentMtime, privacy: .public))")

      if status == "passed" {
        return (isValid: true, errorMessage: nil)
      } else {
        let error = row["error"] as? String ?? "Unknown preflight failure"
        return (isValid: false, errorMessage: error)
      }
    }

    // Cache miss - extract mtime for logging (if row exists but mtime stale)
    let cachedMtime = (cached?["mtime"] as? Double) ?? 0
    log.info("[PREFLIGHT-CACHE-MISS] \(fileURL.lastPathComponent, privacy: .public) (cached mtime: \(cachedMtime, privacy: .public), current: \(currentMtime, privacy: .public))")

    // Perform fresh validation
    let result = validator.validate(
      fileURL: fileURL,
      projectRootPath: projectRootPath,
      provider: provider
    )

    // Persist validation result to cache immediately (before transcript row exists)
    try dbManager.pool.write { db in
      try db.execute(sql: """
        INSERT OR REPLACE INTO transcript_preflight_cache (file_path, provider, mtime, status, error, checked_at)
        VALUES (?, ?, ?, ?, ?, ?)
      """, arguments: [
        fileURL.path,
        provider,
        currentMtime,
        result.isValid ? "passed" : "failed",
        result.errors.first?.description,
        Date().timeIntervalSince1970
      ])
    }

    log.debug("[PREFLIGHT-CACHE-WRITE] file=\(fileURL.lastPathComponent, privacy: .public) status=\(result.isValid ? "passed" : "failed", privacy: .public) mtime=\(currentMtime, privacy: .public)")
    log.info("[PREFLIGHT-CACHE-UPDATE] \(fileURL.lastPathComponent, privacy: .public): \(result.isValid ? "passed" : "failed", privacy: .public)")

    return (
      isValid: result.isValid,
      errorMessage: result.errors.first?.description
    )
  }

  /// Internal implementation - all file I/O must happen synchronously here.
  ///
  /// IMPORTANT: All file I/O on `fileURL` must complete synchronously in this call.
  /// TranscriptAccessProvider.withAccess() wraps this call with a security scope.
  /// Do not offload file reads to background tasks that outlive this call.
  private func doDiscoverTranscript(
    projectId: String,
    fileURL: URL,
    provider: String,
    providerSessionId: String?,
    startWatching: Bool,
    progress: IngestProgressSink?,
    ingestLimit: IngestLimit
  ) throws {
    // Diagnostic: Verify project exists before proceeding
    guard let project = try projectRepo.get(id: projectId) else {
      log.error("[TRANS-DISC-ERROR] ❌ FK validation failed: project \(projectId, privacy: .public) does not exist")
      throw RepositoryError.notFound
    }
    log.debug("[TRANS-DISC-VALID] ✅ FK validation: project \(projectId, privacy: .public) exists")

    // Check preflight validation (with caching)
    let preflightResult = try checkPreflight(
      fileURL: fileURL,
      projectRootPath: project.rootPath,
      provider: provider
    )

    if !preflightResult.isValid {
      log.warning("[TRANS-DISC-PREFLIGHT-FAIL] \(fileURL.lastPathComponent, privacy: .public)")

      // Get file metadata
      let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      let lastModified = attrs[.modificationDate] as? Date ?? Date()
      let fileSize = attrs[.size] as? Int

      // Upsert transcript record for tracking
      let transcriptId = try transcriptRepo.upsert(
        projectId: projectId,
        fileURL: fileURL,
        provider: provider,
        providerSessionId: providerSessionId,
        lastModified: lastModified,
        fileSize: fileSize
      )

      // Mark as error (preflight cache already updated in checkPreflight)
      try dbManager.pool.write { db in
        try db.execute(sql: """
          UPDATE transcripts
          SET status = 'error',
              ingest_state = 'complete',
              last_processed_line = 0,
              last_error = ?
          WHERE id = ?
        """, arguments: [
          preflightResult.errorMessage ?? "Preflight validation failed",
          transcriptId
        ])
      }

      log.info("[TRANS-DISC-SKIP-HOOVER] \(transcriptId, privacy: .public)")
      return  // Skip hoover, continue batch
    }

    // Preflight passed - cache already updated in checkPreflight()
    log.info("[TRANS-DISC-PREFLIGHT-PASS] ✅ \(fileURL.lastPathComponent, privacy: .public)")

    // Get file metadata
    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let lastModified = attrs[.modificationDate] as? Date ?? Date()
    let fileSize = attrs[.size] as? Int

    // Upsert transcript record
    log.info("[TRANS-DISC-UPSERT] Upserting transcript record for: \(fileURL.lastPathComponent, privacy: .public)")
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: fileURL,
      provider: provider,
      providerSessionId: providerSessionId,
      lastModified: lastModified,
      fileSize: fileSize
    )
    log.info("[TRANS-DISC-UPSERT] ✅ Transcript upserted with ID: \(transcriptId, privacy: .public)")

    // Get transcript
    guard let transcript = try transcriptRepo.get(transcriptId) else {
      log.error("[TRANS-DISC-ERROR] ❌ Transcript \(transcriptId, privacy: .public) not found after upsert")
      throw RepositoryError.notFound
    }

    // Verify transcript has correct project ID
    guard transcript.projectId == projectId else {
      log.error("[TRANS-DISC-ERROR] ❌ Transcript projectId mismatch: expected \(projectId, privacy: .public), got \(transcript.projectId, privacy: .public)")
      throw RepositoryError.invalidData
    }

    // Hoover the transcript
    log.info("[TRANS-DISC-HOOVER-START] Starting hoover for transcript: \(transcriptId, privacy: .public)")
    let progressSink = progress ?? NoOpProgressSink()
    let outcome = try hooverEngine.hooverTranscript(transcript, fileURL: fileURL, progress: progressSink, limit: ingestLimit)
    if let sha = outcome.contentSha256 {
      log.info("[TRANS-DISC-HOOVER-DONE] ✅ Hoovered transcript: \(transcriptId, privacy: .public) SHA256: \(String(sha.prefix(8)), privacy: .public)")
    } else {
      log.info("[TRANS-DISC-HOOVER-DONE] ✅ Hoovered transcript: \(transcriptId, privacy: .public) (partial \(outcome.newEntries) entries)")
    }

    // Checkpoint WAL after significant bulk writes to prevent WAL growth
    dbManager.checkpointAfterBulkWrites(entriesWritten: outcome.newEntries)

    // TODO: pass transcriptSHA256 to metadata generation/persistence when implemented

    // Reconcile pending assistant_usage records after hoover completes
    try? reconcileAssistantUsage()

    if outcome.reachedEOF,
       let fileSize,
       let lastEntryTs = try fetchLatestEntryTimestamp(transcriptId: transcriptId) {
      try updateTranscriptBaseline(
        transcriptId: transcriptId,
        knownLastEntryTs: lastEntryTs,
        knownFileSize: Int64(fileSize)
      )
      try clearPendingRehoover(transcriptId: transcriptId)
      try clearUnreadApproximation(transcriptId: transcriptId)
    }

    // Start watching if requested
    if startWatching {
      log.info("[TRANS-DISC-WATCH-START] Starting watcher for transcript: \(transcriptId, privacy: .public)")
      try watcher.watch(transcriptId: transcriptId, fileURL: fileURL, provider: provider)
      log.info("[TRANS-DISC-WATCH-DONE] ✅ Watcher started for transcript: \(transcriptId, privacy: .public)")
    }

    log.info("[TRANS-DISC-COMPLETE] ✅ Discovery complete for transcript: \(transcriptId, privacy: .public)")
  }

  private func needsSecurityScope(provider: String) -> Bool {
    guard Sandbox.isSandboxed else { return false }
    return provider == TranscriptProviderID.claude || provider == TranscriptProviderID.codex
  }

  /// Check if project has high preflight failure rate (>90%)
  private func shouldSkipCorruptProject(projectRootPath: String) throws -> Bool {
    let stats = try dbManager.pool.read { db in
      try Row.fetchOne(db, sql: """
        SELECT
          COUNT(*) as total,
          SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failures
        FROM transcript_preflight_cache
        WHERE file_path LIKE ? || '%'
      """, arguments: [projectRootPath])
    }

    guard let row = stats,
          let total = row["total"] as? Int64,
          let failures = row["failures"] as? Int64,
          total > 0 else {
      return false  // No cache data, don't skip
    }

    let failureRatio = Double(failures) / Double(total)
    return failureRatio > 0.9 && total >= 10  // Require at least 10 samples
  }

  /// Batch discover transcripts for a project
  public func discoverTranscripts(
    projectId: String,
    transcriptFiles: [(url: URL, provider: String, sessionId: String?)],
    progress: IngestProgressSink? = nil,
    concurrency: Int = 8,
    startWatching: Bool = true
  ) async throws {
    log.info("[BATCH-DISC-START] Starting parallel discovery for \(transcriptFiles.count, privacy: .public) transcripts in project: \(projectId, privacy: .public) (concurrency: \(concurrency, privacy: .public))")

    // Evict stale preflight cache entries (7-day TTL) on each batch discovery
    try? evictStalePreflightCache(olderThanDays: 7)

    guard let project = try projectRepo.get(id: projectId) else {
      log.error("[BATCH-DISC-ERROR] Project not found: \(projectId, privacy: .public)")
      throw RepositoryError.notFound
    }

    // Auto-skip projects with >90% preflight failures (corrupt workspaces)
    if try shouldSkipCorruptProject(projectRootPath: project.rootPath) {
      log.warning("[CORRUPT-SKIP] Skipping project with high failure rate: \(project.name ?? projectId, privacy: .public) at \(project.rootPath, privacy: .public)")
      return
    }

    let progressSink = progress ?? NoOpProgressSink()
    progressSink.didStartProject(name: project.name ?? projectId, transcriptCount: transcriptFiles.count)

    let total = transcriptFiles.count
    let completed = CrossPlatformLock(initialState: 0)
    let hasNotified = CrossPlatformLock(initialState: false)  // Track if we've sent progress notification

    try await withThrowingTaskGroup(of: Void.self) { group in
      var activeTaskCount = 0

      for file in transcriptFiles {
        // Wait for a slot to open up if we're at max concurrency
        if activeTaskCount >= concurrency {
          try await group.next()
          activeTaskCount -= 1
        }

        // Add task for this transcript
        group.addTask {
          // Note: Don't pass progressSink to avoid data races in parallel execution
          try await self.discoverTranscript(
            projectId: projectId,
            fileURL: file.url,
            provider: file.provider,
            providerSessionId: file.sessionId,
            startWatching: startWatching,
            progress: nil
          )

          // Update progress counter
          let current = completed.withLock { count in
            count += 1
            return count
          }

          log.debug("[BATCH-DISC-COMPLETE-FILE] Completed \(current, privacy: .public)/\(total, privacy: .public): \(file.url.lastPathComponent, privacy: .public)")

          // Smart notification: only notify once we have enough entries to fill the timeline
          // Query database to check if we have 25+ entries (timeline limit), then notify exactly once
          let shouldCheck = hasNotified.withLock { notified in
            !notified && current >= 3  // Start checking after first batch completes
          }

          if shouldCheck {
            let entryCount = (try? self.getRecentFeed(forProject: projectId, limit: 26, generatorSignature: "").count) ?? 0

            if entryCount >= 25 {
              let shouldNotify = hasNotified.withLock { notified in
                if !notified {
                  notified = true
                  return true
                }
                return false
              }

              if shouldNotify {
                await MainActor.run {
                  NotificationCenter.default.post(
                    name: .transcriptHooveringProgress,
                    object: projectId,
                    userInfo: [
                      "transcriptCount": current,
                      "totalTranscripts": total,
                      "entryCount": entryCount
                    ]
                  )
                }
                log.info("[BATCH-DISC-PROGRESS] Timeline ready: \(entryCount, privacy: .public) entries available (transcript \(current, privacy: .public)/\(total, privacy: .public))")
              }
            }
          }
        }
        activeTaskCount += 1
      }

      // Wait for all remaining tasks to complete
      try await group.waitForAll()
    }

    progressSink.didCompleteProject(name: project.name ?? projectId)

    // Log preflight summary - detailed hit/miss/failure counts available in individual [PREFLIGHT-CACHE-*] logs
    log.info("[PREFLIGHT-SUMMARY] Discovery complete for \(transcriptFiles.count, privacy: .public) transcripts (check PREFLIGHT-CACHE-* logs for details)")

    log.info("[BATCH-DISC-DONE] Parallel discovery complete for project: \(projectId, privacy: .public) (\(transcriptFiles.count, privacy: .public) transcripts)")
  }

  // MARK: - Targeted Ingestion

  private func acquireIngestionLock(transcriptId: String) throws -> Bool {
    let pool = try dbManager.pool
    let now = Int(Date().timeIntervalSince1970)
    var acquired = false

    try pool.write { db in
      let expiry = now - Int(ingestionLockTTL)
      try db.execute(sql: "DELETE FROM ingestion_locks WHERE locked_at < ?", arguments: [expiry])
      try db.execute(sql: """
        INSERT OR IGNORE INTO ingestion_locks(transcript_id, locked_at)
        VALUES (?, ?)
      """, arguments: [transcriptId, now])
      acquired = db.changesCount > 0
    }

    return acquired
  }

  private func releaseIngestionLock(transcriptId: String) {
    do {
      let pool = try dbManager.pool
      try pool.write { db in
        try db.execute(sql: "DELETE FROM ingestion_locks WHERE transcript_id = ?", arguments: [transcriptId])
      }
    } catch {
      log.error("[INGEST-LOCK] Failed to release lock for \(transcriptId, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  @discardableResult
  public func ingestTranscript(
    transcriptId: String,
    mode: IngestionMode,
    notifyUI: Bool = true,
    startWatching: Bool = true
  ) async throws -> Bool {
    guard let initialTranscript = try transcriptRepo.get(transcriptId) else {
      throw RepositoryError.notFound
    }
    let transcript = initialTranscript

    if case .preview = mode, initialTranscript.ingestState == "complete" {
      log.debug("[FAST-PATH] Transcript already complete, skipping preview: \(transcriptId, privacy: .public)")
      return false
    }

    guard try acquireIngestionLock(transcriptId: transcriptId) else {
      log.debug("[INGEST-LOCK] Another worker is processing transcript: \(transcriptId, privacy: .public)")
      // Reload transcript to get current state (may have changed since initial read)
      let refreshedTranscript = try transcriptRepo.get(transcriptId)
      if notifyUI {
        log.info("[ORCHESTRATOR-NOTIFY] Posting TranscriptUpdated notification for project: \(transcript.projectId, privacy: .public) transcript: \(transcriptId.prefix(8), privacy: .public)")
        DispatchQueue.main.async {
          NotificationCenter.default.post(
            name: Notification.Name("TranscriptUpdated"),
            object: nil,
            userInfo: ["projectId": transcript.projectId]
          )
        }
      }
      return refreshedTranscript?.ingestState == "partial"
    }

    defer { releaseIngestionLock(transcriptId: transcriptId) }

    let fileURL = URL(fileURLWithPath: transcript.filePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      log.error("[FAST-PATH] File missing for transcript \(transcriptId, privacy: .public) at \(fileURL.path, privacy: .public)")
      try transcriptRepo.setIngestionState(
        id: transcript.id,
        lastProcessedLine: transcript.lastProcessedLine,
        lineCount: transcript.lineCount,
        parserVersion: transcript.parserVersion,
        status: "unavailable",
        ingestState: "complete",
        lastError: "File no longer exists"
      )
      if notifyUI {
        log.info("[ORCHESTRATOR-NOTIFY] Posting TranscriptUpdated notification for project: \(transcript.projectId, privacy: .public) transcript: \(transcriptId.prefix(8), privacy: .public)")
        DispatchQueue.main.async {
          NotificationCenter.default.post(
            name: Notification.Name("TranscriptUpdated"),
            object: nil,
            userInfo: ["projectId": transcript.projectId]
          )
        }
      }
      return false
    }

    try await discoverTranscript(
      projectId: transcript.projectId,
      fileURL: fileURL,
      provider: transcript.provider,
      providerSessionId: transcript.providerSessionId,
      startWatching: startWatching,
      progress: nil,
      ingestLimit: mode.ingestLimit
    )

    let refreshed = try transcriptRepo.get(transcriptId)
    let isPartial = refreshed?.ingestState == "partial"

    if notifyUI {
      log.info("[ORCHESTRATOR-NOTIFY] Posting TranscriptUpdated notification for project: \(transcript.projectId, privacy: .public) transcript: \(transcriptId.prefix(8), privacy: .public)")
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: Notification.Name("TranscriptUpdated"),
          object: nil,
          userInfo: ["projectId": transcript.projectId]
        )
      }
    }

    return isPartial
  }

  public func getPartialTranscripts(limit: Int? = nil) throws -> [Transcript] {
    let pool = try dbManager.pool
    return try pool.read { db in
      var sql = """
        SELECT * FROM transcripts
        WHERE ingest_state = 'partial' AND status = 'active'
        ORDER BY updated_at DESC
      """
      if let limit {
        sql += " LIMIT \(limit)"
      }
      return try Transcript.fetchAll(db, sql: sql)
    }
  }

  // MARK: - Timeline Decoration Queries

  /// Layer 1: Get entries that spawned agents (Task tool invocations).
  /// Returns a dictionary mapping entry IDs to their agent decoration info (type + model).
  /// Shows badges immediately when Task is invoked, not waiting for sidechain linkage.
  public func getSpawnedAgentEntries(transcriptId: String) throws -> [String: AgentDecorationInfo] {
    let pool = try dbManager.pool
    return try pool.read { db in
      let sql = """
        SELECT entry_id, tool_key, json_extract(metadata_json, '$.model') as model
        FROM tool_invocations
        WHERE transcript_id = ? AND tool_name = 'Task'
      """
      var result: [String: AgentDecorationInfo] = [:]
      let rows = try Row.fetchAll(db, sql: sql, arguments: [transcriptId])
      for row in rows {
        if let entryId: String = row["entry_id"],
           let toolKey: String = row["tool_key"] {
          let model: String? = row["model"]
          result[entryId] = AgentDecorationInfo(agentType: toolKey, model: model)
        }
      }
      return result
    }
  }

  /// Agent decoration info returned by getSpawnedAgentEntries
  public struct AgentDecorationInfo: Sendable {
    public let agentType: String   // e.g., "Explore", "Plan"
    public let model: String?      // e.g., "haiku", "sonnet", "opus"
  }

  /// Layer 1: Get entries that spawned agents for all transcripts in a project.
  /// Shows badges immediately when Task is invoked, not waiting for sidechain linkage.
  public func getSpawnedAgentEntries(projectId: String) throws -> [String: AgentDecorationInfo] {
    let pool = try dbManager.pool
    return try pool.read { db in
      let sql = """
        SELECT ti.entry_id, ti.tool_key, json_extract(ti.metadata_json, '$.model') as model
        FROM tool_invocations ti
        JOIN transcripts t ON ti.transcript_id = t.id
        WHERE t.project_id = ? AND ti.tool_name = 'Task'
      """
      var result: [String: AgentDecorationInfo] = [:]
      var modelsFound = 0
      let rows = try Row.fetchAll(db, sql: sql, arguments: [projectId])
      for row in rows {
        if let entryId: String = row["entry_id"],
           let toolKey: String = row["tool_key"] {
          let model: String? = row["model"]
          if model != nil { modelsFound += 1 }
          result[entryId] = AgentDecorationInfo(agentType: toolKey, model: model)
        }
      }
      if !result.isEmpty {
        log.info("[DECORATION-QUERY] Found \(result.count, privacy: .public) Task invocations (\(modelsFound, privacy: .public) with model info)")
      }
      return result
    }
  }

  /// Layer 2: Get entry IDs that are Contextify skill/agent invocations for a transcript.
  /// Returns both tool_use entry IDs and tool_result entry IDs where is_contextify = 1.
  public func getContextifyEntryIds(transcriptId: String) throws -> Set<String> {
    let pool = try dbManager.pool
    return try pool.read { db in
      let sql = """
        SELECT entry_id, tool_result_entry_id
        FROM tool_invocations
        WHERE transcript_id = ? AND is_contextify = 1
      """
      var entryIds = Set<String>()
      let rows = try Row.fetchAll(db, sql: sql, arguments: [transcriptId])
      for row in rows {
        if let entryId: String = row["entry_id"] {
          entryIds.insert(entryId)
        }
        if let resultEntryId: String = row["tool_result_entry_id"] {
          entryIds.insert(resultEntryId)
        }
      }
      return entryIds
    }
  }

  /// Layer 2: Get entry IDs that are Contextify skill/agent invocations for all transcripts in a project.
  public func getContextifyEntryIds(projectId: String) throws -> Set<String> {
    let pool = try dbManager.pool
    return try pool.read { db in
      let sql = """
        SELECT ti.entry_id, ti.tool_result_entry_id
        FROM tool_invocations ti
        JOIN transcripts t ON ti.transcript_id = t.id
        WHERE t.project_id = ? AND ti.is_contextify = 1
      """
      var entryIds = Set<String>()
      let rows = try Row.fetchAll(db, sql: sql, arguments: [projectId])
      for row in rows {
        if let entryId: String = row["entry_id"] {
          entryIds.insert(entryId)
        }
        if let resultEntryId: String = row["tool_result_entry_id"] {
          entryIds.insert(resultEntryId)
        }
      }
      return entryIds
    }
  }

  /// Info about a Contextify tool invocation for template-based summaries
  public struct ContextifyEntryInfo: Sendable {
    public let toolKey: String?      // e.g., "total-recall", "query:contextify-researcher"
    public let isResult: Bool        // true if this is the tool_result, false if tool_use
  }

  /// Layer 2: Get Contextify entry info (tool_key, isResult) for all Contextify entries in a project.
  /// Used to generate template summaries instead of LLM for Contextify calls.
  public func getContextifyEntryInfo(projectId: String) throws -> [String: ContextifyEntryInfo] {
    let pool = try dbManager.pool
    return try pool.read { db in
      let sql = """
        SELECT ti.entry_id, ti.tool_result_entry_id, ti.tool_key
        FROM tool_invocations ti
        JOIN transcripts t ON ti.transcript_id = t.id
        WHERE t.project_id = ? AND ti.is_contextify = 1
      """
      var result: [String: ContextifyEntryInfo] = [:]
      let rows = try Row.fetchAll(db, sql: sql, arguments: [projectId])
      for row in rows {
        let toolKey: String? = row["tool_key"]
        if let entryId: String = row["entry_id"] {
          result[entryId] = ContextifyEntryInfo(toolKey: toolKey, isResult: false)
        }
        if let resultEntryId: String = row["tool_result_entry_id"] {
          result[resultEntryId] = ContextifyEntryInfo(toolKey: toolKey, isResult: true)
        }
      }
      return result
    }
  }

  /// Mark a transcript as terminally unavailable to prevent repeated retries across runs.
  /// Uses `ingest_state = 'complete'` so it won't be picked up by startup partial resumption.
  public func markTranscriptUnavailable(transcriptId: String, lastError: String) throws {
    guard let transcript = try transcriptRepo.get(transcriptId) else { return }
    try transcriptRepo.setIngestionState(
      id: transcript.id,
      lastProcessedLine: transcript.lastProcessedLine,
      lineCount: transcript.lineCount,
      parserVersion: transcript.parserVersion,
      status: "unavailable",
      ingestState: "complete",
      lastError: lastError
    )
  }

  // MARK: - Private Helpers

  /// Determines if file needs rehashing based on cached metadata
  private func shouldRehash(existing: Row?, path: String) throws -> Bool {
    guard let ex = existing,
          let cachedLen: Int64 = ex["content_length"],
          let cachedMtime: Int64 = ex["mtime_ms"] else {
      return true
    }

    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    let len = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    let mtime = Int64(((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000)

    return (cachedLen != len) || (cachedMtime != mtime)
  }

  // MARK: - Batch Upsert

  /// Batch upsert transcripts using path normalization for identity
  /// - Parameters:
  ///   - projectId: Project ID to associate transcripts with
  ///   - discovered: Array of discovered transcripts
  /// - Returns: Array of resolved transcripts with canonical IDs
  /// - Note: Uses single transaction for atomicity, UPSERT for idempotency
  ///         Prefers provider_session_id when available, falls back to path_hash
  ///         Only recomputes SHA256 if file size or mtime changed (streaming)
  public func upsertTranscripts(
    projectId: String,
    discovered: [DiscoveredTranscript]
  ) throws -> [ResolvedTranscript] {
    guard try projectRepo.get(id: projectId) != nil else {
      log.error("❌ FK validation failed: project \(projectId) does not exist")
      throw RepositoryError.notFound
    }

    let pool = try dbManager.pool
    var resolved: [ResolvedTranscript] = []

    // Single transaction for atomicity
    try pool.write { db in
      for disc in discovered {
        let path = disc.fileURL.path

        // Normalize path and compute hash
        let (normalizedPath, pathHash) = PathNormalizer.normalizeAndHash(path)

        // Clean up session ID (trim whitespace)
        let sid = disc.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if transcript exists - try multiple lookup strategies in order:
        // 1. (project_id, file_path) - most reliable, handles path normalization
        // 2. (provider, path_hash) - handles symlinks and moved files
        // 3. (provider, provider_session_id) - only if session ID is set (prevents UNIQUE constraint violation)
        let existing: Row? = try Row.fetchOne(db, sql: """
          SELECT id, content_length, mtime_ms, content_sha256
          FROM transcripts
          WHERE project_id = ? AND file_path = ?
        """, arguments: [projectId, path])

        // If not found by (project_id, file_path), try path_hash
        ?? (try Row.fetchOne(db, sql: """
          SELECT id, content_length, mtime_ms, content_sha256
          FROM transcripts
          WHERE provider = ? AND path_hash = ?
        """, arguments: [disc.provider, pathHash]))

        // If not found by path, try (provider, provider_session_id) if session ID exists
        ?? (sid != nil ? try Row.fetchOne(db, sql: """
          SELECT id, content_length, mtime_ms, content_sha256
          FROM transcripts
          WHERE provider = ? AND provider_session_id = ?
        """, arguments: [disc.provider, sid!]) : nil)

        // Get file facts (streaming SHA256)
        let (len, mtimeMs, sha): (Int64, Int64, String)
        if FileManager.default.fileExists(atPath: path) {
          // Only rehash if size or mtime changed
          if try shouldRehash(existing: existing, path: path) {
            (len, mtimeMs, sha) = try FileFacts.forPath(path)
          } else {
            // File metadata unchanged - reuse cached SHA
            len = (existing?["content_length"] as? Int64) ?? 0
            mtimeMs = (existing?["mtime_ms"] as? Int64) ?? 0
            sha = (existing?["content_sha256"] as? String) ?? "pending"
          }
        } else {
          // File no longer exists - use placeholder
          (len, mtimeMs, sha) = (0, 0, "missing")
        }

        let wasCreated: Bool
        let transcriptId: String
        let nowMs = TimeUnits.nowMs()
        let nowSec = TimeUnits.secondsFromMs(nowMs)

        if let ex = existing, let id = ex["id"] as? String {
          // Existing transcript - update
          transcriptId = id
          wasCreated = false

          // Don't update provider_session_id on UPDATE - preserve existing value
          // Reason: Session IDs can be duplicated across projects (same file copied),
          // and we use (project_id, file_path) as primary lookup anyway.
          // Backfilling NULL values could cause UNIQUE constraint violations.
          try db.execute(sql: """
            UPDATE transcripts
            SET file_path = ?,
                normalized_path = ?,
                path_hash = ?,
                last_modified = ?,
                file_size = ?,
                content_length = ?,
                mtime_ms = ?,
                content_sha256 = ?,
                updated_at = ?
            WHERE id = ?
          """, arguments: [
            path,
            normalizedPath,
            pathHash,
            TimeUnits.secondsFromMs(mtimeMs),  // last_modified in seconds for compatibility
            len > 0 ? Int(len) : nil,
            len,
            mtimeMs,
            sha,
            nowSec,
            transcriptId
          ])

          log.debug("✅ Updated existing transcript: \(transcriptId) [\(pathHash.prefix(8))...]")
        } else {
          // New transcript - insert
          transcriptId = UUID().uuidString
          wasCreated = true

          // Use nil instead of empty string for provider_session_id (avoids UNIQUE constraint issues)
          let sessionIdArg: String? = (sid == nil || sid!.isEmpty) ? nil : sid

          try db.execute(sql: """
            INSERT INTO transcripts (
              id, project_id, file_path, normalized_path, path_hash,
              provider, provider_session_id,
              last_modified, file_size, content_length, mtime_ms, content_sha256,
              line_count, last_processed_line, parser_version, status, ingest_state,
              created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """, arguments: [
            transcriptId, projectId, path, normalizedPath, pathHash,
            disc.provider, sessionIdArg,  // Pass nil as NULL, not empty string
            TimeUnits.secondsFromMs(mtimeMs), len > 0 ? Int(len) : nil, len, mtimeMs, sha,
            0, 0, 1, "active", "partial",  // New transcripts start as partial so fast-path can preview
            nowSec, nowSec
          ])

          log.debug("✅ Created new transcript: \(transcriptId) [\(pathHash.prefix(8))...]")
        }

        resolved.append(ResolvedTranscript(
          transcriptId: transcriptId,
          fileURL: disc.fileURL,
          provider: disc.provider,
          wasCreated: wasCreated
        ))
      }
    }

    log.info("Upserted \(resolved.count) transcripts for project \(projectId) (\(resolved.filter(\.wasCreated).count) new)")
    return resolved
  }

  /// Resolve transcript ID for a file URL and provider
  /// - Parameters:
  ///   - fileURL: File URL to look up
  ///   - provider: Provider identifier
  /// - Returns: Canonical transcript ID if found
  public func resolveTranscriptId(fileURL: URL, provider: String) throws -> String? {
    let path = fileURL.path
    let (_, pathHash) = PathNormalizer.normalizeAndHash(path)

    let pool = try dbManager.pool
    return try pool.read { db in
      try String.fetchOne(db, sql: """
        SELECT id FROM transcripts
        WHERE provider = ? AND path_hash = ?
      """, arguments: [provider, pathHash])
    }
  }

  // MARK: - Transcript Queries

  public func getTranscripts(forProject projectId: String) throws -> [Transcript] {
    try transcriptRepo.byProject(projectId)
  }

  /// Delete a transcript and all its associated data
  /// - Parameter transcriptId: Transcript ID to delete
  /// - Note: Cascading deletes will remove: transcript_entries, timeline_cache, parse_errors, file_snapshots, tracked_files, transcript_summaries, system_events, assistant_usage
  public func deleteTranscript(transcriptId: String) throws {
    stopWatchingTranscript(transcriptId: transcriptId)
    try transcriptRepo.delete(id: transcriptId)
    log.info("Deleted transcript: \(transcriptId)")
  }

  /// Find and delete all transcripts whose files no longer exist on disk
  /// - Returns: Array of deleted transcript IDs
  public func cleanupMissingTranscripts() throws -> [String] {
    // Phase 1: Read all transcripts (read transaction, no lock held)
    let allTranscripts: [Transcript] = try dbManager.pool.read { db in
      try Transcript.fetchAll(db)
    }

    // Phase 2: Check filesystem outside any transaction (no DB lock)
    let missingTranscripts = allTranscripts.filter { transcript in
      !FileManager.default.fileExists(atPath: transcript.filePath)
    }

    let deletedIds = missingTranscripts.map(\.id)
    guard !deletedIds.isEmpty else { return [] }

    // Phase 3: Delete missing transcripts atomically in single write transaction
    // Chunk deletions to avoid SQLite parameter limits (max 999)
    try dbManager.pool.write { db in
      for chunk in deletedIds.chunked(into: 900) {
        let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
        let sql = "DELETE FROM transcripts WHERE id IN (\(placeholders))"
        try db.execute(sql: sql, arguments: StatementArguments(chunk))
      }
    }

    for transcript in missingTranscripts {
      stopWatchingTranscript(transcriptId: transcript.id)
      log.info("Cleaned up transcript with missing file: \(transcript.id) at \(transcript.filePath)")
    }

    if deletedIds.isEmpty {
      log.info("No missing transcript files found during cleanup")
    } else {
      log.info("Cleaned up \(deletedIds.count) transcripts with missing files")
    }

    return deletedIds
  }

  /// Get count of displayable entries for a transcript (excludes metadata-only records)
  public func getEntryCount(transcriptId: String) throws -> Int {
    try dbManager.pool.read { db in
      try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcript_entries
        WHERE transcript_id = ? AND display_in_timeline = 1
          AND is_sidechain = 0
      """, arguments: [transcriptId]) ?? 0
    }
  }

  public func getEntries(forTranscript transcriptId: String, afterTimestamp: Int? = nil) throws -> [TranscriptEntry] {
    try entryRepo.byTranscript(transcriptId, afterTimestamp: afterTimestamp)
  }

  public func getEntryCount(forProject projectId: String) throws -> Int {
    try dbManager.pool.read { db in
      try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM transcript_entries
        WHERE project_id = ? AND display_in_timeline = 1
          AND is_sidechain = 0
      """, arguments: [projectId]) ?? 0
    }
  }

  public func getRecentEntries(forProject projectId: String, limit: Int = 50) throws -> [TranscriptEntry] {
    try entryRepo.recentByProject(projectId, limit: limit)
  }

  public func getNewEntries(forProject projectId: String, afterTimestamp: Int) throws -> [TranscriptEntry] {
    try entryRepo.newByProject(projectId, afterTimestamp: afterTimestamp)
  }

  @available(*, deprecated, message: "Use getEntriesAfterCursor(projectId:after: EntryCursor?)")
  public func getEntriesAfterCursor(forProject projectId: String, after: EntryCursor) throws -> [TranscriptEntry] {
    // Convert EntryCursor to tuple for compatibility with entriesAfterCursor
    let tuple = (timestamp: Int(after.timestamp), createdAt: Int(after.createdAt), id: after.id)
    return try entryRepo.entriesAfterCursor(projectId: projectId, after: tuple)
  }

  public func searchEntries(content: String, projectId: String?) throws -> [TranscriptEntry] {
    try entryRepo.search(content: content, projectId: projectId)
  }

  public func latestTimestampsByTranscript(projectId: String) throws -> [String: Int] {
    try entryRepo.latestTimestampsByTranscript(projectId: projectId)
  }

  /// Check which entry IDs exist in transcript_entries table (FK preflight for cache misses)
  /// Returns set of entry IDs that exist in the database
  public func existingEntryIds(_ ids: [String]) throws -> Set<String> {
    guard !ids.isEmpty else { return [] }

    return try dbManager.pool.read { db in
      let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
      let sql = "SELECT id FROM transcript_entries WHERE id IN (\(placeholders))"
      let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(ids))
      return Set(rows.compactMap { $0["id"] as String? })
    }
  }

  // v2: Single-query feed with cache join
  public func getRecentFeed(forProject projectId: String, limit: Int = 50, generatorSignature: String) throws -> [(TranscriptEntry, TimelineCache?)] {
    try entryRepo.recentFeed(projectId: projectId, limit: limit, generatorSignature: generatorSignature)
  }

  // MARK: - Cache Management

  // New CacheKey-based API
  nonisolated public func getCachedTimeline(key: CacheKey) throws -> TimelineCache? {
    try cacheRepo.get(contentSha256: key.content, windowSha256: key.window)
  }

  nonisolated public func getCachedTimelineMany(keys: [CacheKey]) throws -> [CacheKey: TimelineCache] {
    let tuples = keys.map { ($0.content, $0.window) }
    let stringMap = try cacheRepo.getMany(keys: tuples)

    // Convert string-keyed result to CacheKey-keyed result
    var result: [CacheKey: TimelineCache] = [:]
    for key in keys {
      if let cache = stringMap[key.composite] {
        result[key] = cache
      }
    }
    return result
  }

  // Legacy API - deprecated
  @available(*, deprecated, message: "Use getCachedTimeline(key:) instead")
  nonisolated public func getCachedTimeline(contentSha256: String, windowSha256: String) throws -> TimelineCache? {
    try cacheRepo.get(contentSha256: contentSha256, windowSha256: windowSha256)
  }

  @available(*, deprecated, message: "Use getCachedTimelineMany(keys:) with [CacheKey] instead")
  nonisolated public func getCachedTimelineMany(keys: [(String, String)]) throws -> [String: TimelineCache] {
    try cacheRepo.getMany(keys: keys)
  }

  nonisolated public func getCachedTimelineManyWithSignature(keys: [CacheKey], generatorSignature: String) throws -> [CacheKey: TimelineCache] {
    try cacheRepo.getManyWithSignature(keys: keys, generatorSignature: generatorSignature)
  }

  /// Save timeline cache entry (LLM-generated summary)
  ///
  /// **Concurrency Note**: While thread-safe via GRDB pool, concurrent writes from multiple
  /// sources may cause transient "database is locked" errors. DatabaseManager enforces 5-second
  /// busy timeout to mitigate this. Callers should retry on SQLITE_BUSY (GRDB.DatabaseError code 5).
  nonisolated public func saveCachedTimeline(_ cache: TimelineCache) throws {
    try cacheRepo.upsert(cache)
  }

  /// Save multiple timeline cache entries in a single transaction
  ///
  /// **Concurrency Note**: While thread-safe via GRDB pool, concurrent writes from multiple
  /// sources may cause transient "database is locked" errors. DatabaseManager enforces 5-second
  /// busy timeout to mitigate this. Callers should retry on SQLITE_BUSY (GRDB.DatabaseError code 5).
  nonisolated public func saveCachedTimelineMany(_ caches: [TimelineCache]) throws {
    try cacheRepo.upsertMany(caches)
  }

  /// Delete a timeline cache entry by its composite key
  ///
  /// Allows manual regeneration of summaries by invalidating cached entries.
  /// The TimelineCacheMissGenerator will automatically regenerate on next access.
  ///
  /// - Parameters:
  ///   - contentSha256: SHA256 hash of the entry content
  ///   - windowSha256: SHA256 hash of the context window
  nonisolated public func deleteCachedTimeline(contentSha256: String, windowSha256: String) throws {
    try cacheRepo.delete(contentSha256: contentSha256, windowSha256: windowSha256)
  }

  // MARK: - Metadata Management

  public func getMetadata(forTranscript transcriptId: String) throws -> TranscriptMetadataRecord? {
    try metadataRepo.get(transcriptId)
  }

  /// Get metadata for multiple transcripts (handles SQLite IN clause limits)
  /// - Parameter transcriptIds: Array of transcript IDs
  /// - Returns: Dictionary mapping transcript ID to metadata
  /// - Note: Delegates to repository which chunks queries to stay under SQLite's 999 parameter limit
  public func getMetadataBatch(transcriptIds: [String]) throws -> [String: TranscriptMetadataRecord] {
    try metadataRepo.getBatch(transcriptIds)
  }

  public func saveMetadata(_ metadata: TranscriptMetadataRecord) throws {
    try metadataRepo.upsert(metadata)
  }

  public func deleteMetadata(forTranscript transcriptId: String) throws {
    let pool = try dbManager.pool
    try pool.write { db in
      try db.execute(sql: "DELETE FROM transcript_metadata WHERE transcript_id = ?", arguments: [transcriptId])
    }
  }

  // MARK: - Maintenance

  public func performMaintenance() throws {
    log.info("Running database maintenance...")

    // Check WAL size
    try dbManager.checkWALSize()

    // Run ANALYZE
    try dbManager.analyze()

    // Vacuum if needed
    try dbManager.vacuumIfNeeded()

    log.info("Database maintenance completed")
  }

  /// Reconcile transcripts against filesystem - mark missing files as deleted
  public func reconcileDeletedTranscripts(projectId: String) throws {
    let transcripts = try transcriptRepo.byProject(projectId)
    var markedDeleted = 0

    for transcript in transcripts {
      let fileURL = URL(fileURLWithPath: transcript.filePath)
      if !FileManager.default.fileExists(atPath: fileURL.path) {
        // Mark as deleted
        try transcriptRepo.setIngestionState(
          id: transcript.id,
          lastProcessedLine: transcript.lastProcessedLine,
          lineCount: transcript.lineCount,
          parserVersion: transcript.parserVersion,
          status: "deleted",
          ingestState: "complete",
          lastError: "File no longer exists"
        )
        markedDeleted += 1
      }
    }

    if markedDeleted > 0 {
      log.info("Reconciled project \(projectId): marked \(markedDeleted) transcripts as deleted")
    }
  }

  // MARK: - Metadata Queries (v7)

  /// Get file snapshots for a transcript
  public func getFileSnapshots(transcriptId: String) throws -> [FileSnapshot] {
    let repo = FileSnapshotRepositoryImpl(db: try dbManager.pool)
    return try repo.byTranscript(transcriptId)
  }

  /// Get tracked files for a snapshot
  public func getTrackedFiles(snapshotId: String) throws -> [TrackedFile] {
    let repo = TrackedFileRepositoryImpl(db: try dbManager.pool)
    return try repo.bySnapshot(snapshotId)
  }

  /// Get file modification history across transcripts
  public func getFileHistory(projectId: String, filePath: String, limit: Int = 50) throws -> [TrackedFile] {
    let repo = TrackedFileRepositoryImpl(db: try dbManager.pool)
    return try repo.byFilePath(projectId, path: filePath, limit: limit)
  }

  /// Get transcript summary (Claude Code's internal title)
  public func getTranscriptSummary(transcriptId: String) throws -> TranscriptSummary? {
    let repo = TranscriptSummaryRepositoryImpl(db: try dbManager.pool)
    return try repo.get(transcriptId)
  }

  /// Get system events for a transcript
  public func getSystemEvents(transcriptId: String, limit: Int = 100) throws -> [SystemEvent] {
    let repo = SystemEventRepositoryImpl(db: try dbManager.pool)
    return try repo.byTranscript(transcriptId, limit: limit)
  }

  /// Get system events by subtype (e.g., "slash_command", "api_error")
  public func getSystemEventsByType(transcriptId: String, subtype: String, limit: Int = 100) throws -> [SystemEvent] {
    let repo = SystemEventRepositoryImpl(db: try dbManager.pool)
    return try repo.bySubtype(transcriptId, subtype: subtype, limit: limit)
  }

  /// Get error events for a transcript
  public func getErrorEvents(transcriptId: String, limit: Int = 100) throws -> [SystemEvent] {
    let repo = SystemEventRepositoryImpl(db: try dbManager.pool)
    return try repo.errorEvents(transcriptId, limit: limit)
  }

  /// Get usage data for a specific entry
  public func getAssistantUsage(entryId: String) throws -> AssistantUsage? {
    let repo = AssistantUsageRepositoryImpl(db: try dbManager.pool)
    return try repo.get(entryId)
  }

  /// Get aggregated usage statistics for a transcript
  public func getTranscriptUsageStats(transcriptId: String) throws -> UsageAggregate {
    let repo = AssistantUsageRepositoryImpl(db: try dbManager.pool)
    return try repo.aggregateByTranscript(transcriptId)
  }

  /// Get aggregated usage statistics for a project (with optional date range)
  public func getProjectUsageStats(
    projectId: String,
    startDate: Date? = nil,
    endDate: Date? = nil
  ) throws -> UsageAggregate {
    let repo = AssistantUsageRepositoryImpl(db: try dbManager.pool)
    return try repo.aggregateByProject(projectId, startDate: startDate, endDate: endDate)
  }

  // MARK: - Project Visits (Unread Tracking)

  /// Mark a project as viewed at a specific timestamp
  @discardableResult
  public func markProjectViewed(projectId: String, timestamp: String) throws -> ProjectVisit {
    try projectVisitsRepo.markViewed(projectId: projectId, timestamp: timestamp)
    // Return fresh state immediately after update
    guard let visit = try projectVisitsRepo.getVisit(projectId: projectId) else {
      // If visit doesn't exist yet, return a default one
      return ProjectVisit(projectId: projectId, lastViewedAt: timestamp, lastSelectedAt: nil, pinned: false)
    }
    return visit
  }

  /// Mark a project as selected (updates last_selected_at to now)
  public func markProjectSelected(projectId: String) throws {
    try projectVisitsRepo.markSelected(projectId: projectId)
  }

  /// Result of activating a project (consolidated from 3 separate operations)
  public struct ProjectActivationResult {
    public let visit: ProjectVisit
    public let unreadCount: Int
  }

  public enum ProjectActivationError: Error {
    case projectNotFound(String)
  }

#if DEBUG
  // Test-only hook to force failures during activation for rollback verification
  private nonisolated(unsafe) static var activationFailureHook: (() throws -> Void)?

  public static func setActivationFailureHookForTesting(_ hook: (() throws -> Void)?) {
    activationFailureHook = hook
  }
#endif

  /// Unified method to mark a project as activated (selected + viewed) and get fresh unread count.
  ///
  /// This consolidates three separate orchestrator calls into one atomic operation:
  /// 1. markProjectSelected() - updates last_selected_at
  /// 2. markProjectViewed() - updates last_viewed_at
  /// 3. getUnreadCount() - returns fresh count after updates
  ///
  /// Using this single method prevents foot-guns where callers forget one of the operations.
  ///
  /// - Parameters:
  ///   - projectId: The project ID to activate
  ///   - timestamp: ISO8601 timestamp for when the project was viewed
  /// - Returns: Combined result with visit state and unread count
  public func markProjectActivated(projectId: String, timestamp: String) throws -> ProjectActivationResult {
    let selectedAt = ISO8601Z.string(from: SystemClock().now())

    return try dbManager.pool.write { db in
      // Ensure project exists to avoid silent no-op updates
      guard try Project.fetchOne(db, key: projectId) != nil else {
        throw ProjectActivationError.projectNotFound(projectId)
      }

      // Update projects.last_viewed_ts using same precision as markProjectViewed()
      if let date = ISO8601Z.date(from: timestamp) {
        let epochSeconds = TimeUnits.truncateToMillis(date.timeIntervalSince1970)
        try db.execute(
          sql: "UPDATE projects SET last_viewed_ts = MAX(last_viewed_ts, ?) WHERE id = ?",
          arguments: [epochSeconds, projectId]
        )
      }

      // Upsert visit with both selected and viewed timestamps
      var visit = try ProjectVisit.fetchOne(db, key: projectId) ?? ProjectVisit(projectId: projectId)
      visit.lastSelectedAt = selectedAt
      visit.lastViewedAt = timestamp
      try visit.save(db)

#if DEBUG
      if let hook = Self.activationFailureHook {
        try hook()
      }
#endif

      let unreadCount = try projectVisitsRepo.unreadCount(projectId: projectId, in: db)

      return ProjectActivationResult(visit: visit, unreadCount: unreadCount)
    }
  }

  /// Get unread count for a specific project
  public func getUnreadCount(projectId: String) throws -> Int {
    try projectVisitsRepo.getUnreadCount(projectId: projectId)
  }

  /// Get unread counts for all projects
  public func getUnreadCounts() throws -> [String: Int] {
    try projectVisitsRepo.getUnreadCounts()
  }

  /// Get unread counts for specific projects (batch query)
  public func getUnreadCounts(projectIds: [String]) throws -> [String: Int] {
    try projectVisitsRepo.getUnreadCounts(projectIds: projectIds)
  }

  public func getUnreadIndicator(projectId: String) throws -> UnreadIndicatorResult {
    try projectVisitsRepo.getUnreadIndicator(projectId: projectId)
  }

  public func getUnreadIndicators(projectIds: [String]) throws -> [String: UnreadIndicatorResult] {
    var result: [String: UnreadIndicatorResult] = [:]
    for projectId in projectIds {
      result[projectId] = try projectVisitsRepo.getUnreadIndicator(projectId: projectId)
    }
    return result
  }

  /// Ensure visit record exists for a project
  public func ensureProjectVisit(projectId: String) throws {
    try projectVisitsRepo.ensureVisit(projectId: projectId)
  }

  // MARK: - File Watching

  /// Start watching a transcript file for changes (idempotent)
  /// - Parameters:
  ///   - transcriptId: The transcript ID to watch
  ///   - fileURL: The file URL to watch
  /// - Note: Idempotent - skips if already watching
  public func startWatchingTranscript(
    transcriptId: String,
    fileURL: URL,
    provider: String? = nil
  ) throws {
    guard !watcher.isWatching(transcriptId: transcriptId) else {
      return
    }
    let providerToUse: String
    if let provider {
      providerToUse = provider
    } else if let transcript = try transcriptRepo.get(transcriptId) {
      providerToUse = transcript.provider
    } else {
      log.error("[WATCHER-START-ERROR] Transcript not found while starting watcher: \(transcriptId, privacy: .public)")
      return
    }
    try watcher.watch(transcriptId: transcriptId, fileURL: fileURL, provider: providerToUse)
  }

  /// Check if a transcript is being watched
  public func isWatchingTranscript(transcriptId: String) -> Bool {
    return watcher.isWatching(transcriptId: transcriptId)
  }

  /// Stop watching a transcript file (idempotent)
  public func stopWatchingTranscript(transcriptId: String) {
    watcher.stopWatching(transcriptId: transcriptId)
  }

  public func stopAllWatchingTranscripts(reason: String = "manual") {
    let count = watcher.stopAll()
    log.info("[WATCHER-STOP-ALL] count=\(count, privacy: .public) reason=\(reason, privacy: .public)")
  }

  public func getTranscript(transcriptId: String) throws -> Transcript? {
    return try transcriptRepo.get(transcriptId)
  }

  public func withAccess<T>(for provider: String, _ body: @Sendable () throws -> T) throws -> T {
    if needsSecurityScope(provider: provider), let accessProvider {
      return try accessProvider.withAccess(for: provider) { _ in
        try body()
      }
    }
    return try body()
  }

  /// Apply a watcher plan for a project, starting/stopping transcripts to match target set
  public func applyWatcherPlan(
    projectId: String,
    targetTranscriptIds: Set<String>
  ) throws -> WatcherPlanResult {
    let transcripts = try getTranscripts(forProject: projectId)
    let transcriptsById = Dictionary(uniqueKeysWithValues: transcripts.map { ($0.id, $0) })

    let currentlyWatched = Set(transcripts.filter { watcher.isWatching(transcriptId: $0.id) }.map { $0.id })
    let toStop = currentlyWatched.subtracting(targetTranscriptIds).sorted()
    let toStart = targetTranscriptIds.subtracting(currentlyWatched).sorted()

    var stoppedCount = 0
    for transcriptId in toStop {
      watcher.stopWatching(transcriptId: transcriptId)
      stoppedCount += 1
    }

    var startedCount = 0
    var failedStarts: [WatcherPlanFailure] = []

    for transcriptId in toStart {
      guard let transcript = transcriptsById[transcriptId] else { continue }
      let fileURL = URL(fileURLWithPath: transcript.filePath)
      do {
        try startWatchingTranscript(transcriptId: transcriptId, fileURL: fileURL, provider: transcript.provider)
        startedCount += 1
      } catch {
        let fdExhaustion = isFdExhaustionError(error)
        failedStarts.append(
          WatcherPlanFailure(
            transcriptId: transcriptId,
            isFdExhaustion: fdExhaustion,
            errorDescription: error.localizedDescription
          )
        )
      }
    }

    return WatcherPlanResult(
      projectId: projectId,
      startedCount: startedCount,
      stoppedCount: stoppedCount,
      failedStarts: failedStarts
    )
  }

  /// Ensure watchers are running for a project's transcripts
  /// - Parameters:
  ///   - projectId: Database project identifier
  ///   - targetTranscriptId: Optional transcript focus (defaults to all transcripts)
  /// - Returns: Summary of watcher state changes for diagnostics/telemetry
  public func ensureProjectWatcher(
    projectId: String,
    targetTranscriptId: String? = nil
  ) throws -> WatcherRecoverySummary {
    if LoggingConfig.enableVerboseWatcherHealthChecks {
      log.info("[ENSURE-WATCHER-START] Entered ensureProjectWatcher for project=\(projectId, privacy: .public) target=\(targetTranscriptId ?? "all", privacy: .public)")
    }

    let transcripts = try getTranscripts(forProject: projectId)

    if LoggingConfig.enableVerboseWatcherHealthChecks {
      log.debug("[ENSURE-WATCHER-QUERY] Found \(transcripts.count) transcripts for project=\(projectId, privacy: .public)")
    }

    guard !transcripts.isEmpty else {
      log.warning("[WATCHER-RECOVERY] No transcripts found for project \(projectId, privacy: .public)")
      return WatcherRecoverySummary(
        projectId: projectId,
        startedCount: 0,
        alreadyActiveCount: 0,
        missingFileCount: 0,
        targetTranscriptId: targetTranscriptId
      )
    }

    var started = 0
    var already = 0
    var missing = 0

    for transcript in transcripts {
      let isWatching = self.watcher.isWatching(transcriptId: transcript.id)

      if LoggingConfig.enableVerboseWatcherHealthChecks {
        log.debug("[ENSURE-WATCHER-CHECK] Checking transcript=\(transcript.id, privacy: .public) isWatching=\(isWatching)")
      }

      if let targetTranscriptId, targetTranscriptId != transcript.id {
        if LoggingConfig.enableVerboseWatcherHealthChecks {
          log.debug("[ENSURE-WATCHER-CHECK] Skipping transcript=\(transcript.id, privacy: .public) (not target)")
        }
        continue
      }

      let fileURL = URL(fileURLWithPath: transcript.filePath)
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        log.warning("[WATCHER-RECOVERY-SKIP] Transcript file missing for \(transcript.id, privacy: .public) at \(fileURL.path, privacy: .public)")
        missing += 1
        continue
      }

      if watcher.isWatching(transcriptId: transcript.id) {
        if LoggingConfig.enableVerboseWatcherRecovery {
          log.debug("[WATCHER-RECOVERY-SKIP] Already watching transcript \(transcript.id, privacy: .public)")
        }
        already += 1
        continue
      }

      if LoggingConfig.enableVerboseWatcherRecovery {
        log.debug("[WATCHER-RECOVERY-START] Restarting watcher for transcript \(transcript.id, privacy: .public)")
      }
      try startWatchingTranscript(transcriptId: transcript.id, fileURL: fileURL, provider: transcript.provider)
      started += 1
      if LoggingConfig.enableVerboseWatcherRecovery {
        log.debug("[WATCHER-RECOVERY-SUCCESS] Watcher active for transcript \(transcript.id, privacy: .public)")
      }
    }

    if LoggingConfig.enableVerboseWatcherHealthChecks {
      log.info("[ENSURE-WATCHER-DONE] Completed for project=\(projectId, privacy: .public) started=\(started) already=\(already) missing=\(missing)")
    }

    return WatcherRecoverySummary(
      projectId: projectId,
      startedCount: started,
      alreadyActiveCount: already,
      missingFileCount: missing,
      targetTranscriptId: targetTranscriptId
    )
  }

  /// Stop all watchers for a specific project (lazy watcher support)
  public func stopAllWatchers(forProjectId projectId: String) throws {
    let transcripts = try getTranscripts(forProject: projectId)
    var stopped = 0

    for transcript in transcripts where watcher.isWatching(transcriptId: transcript.id) {
      watcher.stopWatching(transcriptId: transcript.id)
      stopped += 1
    }

    if stopped > 0 {
      log.info("[WATCHER-STOP-PROJECT] Stopped \(stopped, privacy: .public) watchers for project \(projectId, privacy: .public)")
    }
  }

  /// Manually trigger hoover for a transcript (for recovery/debugging)
  /// Bypasses watcher and directly ingests new content from file
  @discardableResult
  public func manualHoover(transcriptId: String, fileURL: URL) throws -> HooverOutcome {
    guard let transcript = try transcriptRepo.get(transcriptId) else {
      throw RepositoryError.notFound
    }
    return try hooverEngine.hooverTranscript(transcript, fileURL: fileURL, progress: NoOpProgressSink())
  }

  // MARK: - Lazy Watcher Support

  /// Mark a transcript for rehoover after a deferred ingestion or failure
  public func markPendingRehoover(transcriptId: String) async throws {
    let pool = try dbManager.pool
    try await pool.write { db in
      try db.execute(sql: """
        UPDATE transcripts
        SET pending_rehoover = 1,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])
    }
  }

  public func getTranscriptBaseline(
    transcriptId: String
  ) throws -> (knownLastEntryTs: Double?, knownFileSize: Int64?) {
    let pool = try dbManager.pool
    return try pool.read { db in
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT known_last_entry_ts, known_file_size
          FROM transcripts
          WHERE id = ?
        """,
        arguments: [transcriptId]
      )
      let lastEntryTs = row?["known_last_entry_ts"] as Double?
      let fileSize = row?["known_file_size"] as Int64?
      return (lastEntryTs, fileSize)
    }
  }

  public func updateTranscriptBaseline(
    transcriptId: String,
    knownLastEntryTs: Double,
    knownFileSize: Int64
  ) throws {
    let pool = try dbManager.pool
    try pool.write { db in
      try db.execute(sql: """
        UPDATE transcripts
        SET known_last_entry_ts = ?,
            known_file_size = ?,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        knownLastEntryTs,
        knownFileSize,
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])
    }
  }

  public func setTranscriptActivityDetectedAt(transcriptId: String, at: Date) throws {
    let pool = try dbManager.pool
    try pool.write { db in
      try db.execute(sql: """
        UPDATE transcripts
        SET last_activity_detected_at = ?,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        Int(at.timeIntervalSince1970),
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])
    }
  }

  public func setProjectActivityDetectedAt(projectId: String, at: Date) throws {
    let pool = try dbManager.pool
    try pool.write { db in
      try db.execute(sql: """
        UPDATE projects
        SET last_activity_detected_at = ?,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        Int(at.timeIntervalSince1970),
        Int(Date().timeIntervalSince1970),
        projectId
      ])
    }
  }

  public func setUnreadApproximation(
    transcriptId: String,
    count: Int,
    confidence: String,
    updatedAt: Date
  ) throws {
    let pool = try dbManager.pool
    try pool.write { db in
      try db.execute(sql: """
        UPDATE transcripts
        SET unread_approx_count = ?,
            unread_approx_confidence = ?,
            unread_approx_updated_at = ?,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        count,
        confidence,
        Int(updatedAt.timeIntervalSince1970),
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])
    }
  }

  public func clearUnreadApproximation(transcriptId: String) throws {
    let pool = try dbManager.pool
    try pool.write { db in
      try db.execute(sql: """
        UPDATE transcripts
        SET unread_approx_count = NULL,
            unread_approx_confidence = NULL,
            unread_approx_updated_at = 0,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])
    }
  }

  /// Rehoover transcripts whose filesystem mtime or pending flag indicate missed changes
  /// - Returns: Count of transcripts rehoovered
  public func rehooverDirtyTranscripts(
    projectId: String,
    restrictToTranscriptIds: Set<String>? = nil
  ) async throws -> Int {
    let transcripts = try getTranscripts(forProject: projectId)
    var rehoovered = 0

    for transcript in transcripts {
      if let restrictToTranscriptIds,
         !restrictToTranscriptIds.contains(transcript.id) {
        continue
      }
      let fileURL = URL(fileURLWithPath: transcript.filePath)
      let currentMtimeMs: Int64
      do {
        currentMtimeMs = try fetchMtimeMs(fileURL: fileURL, provider: transcript.provider)
      } catch let error as NSError {
        // P1.3 FIX: If file doesn't exist, clear pending_rehoover to prevent infinite retry
        if error.domain == NSCocoaErrorDomain && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) {
          log.info("[LAZY-WATCHER] File not found for transcript \(transcript.id, privacy: .public), clearing pending_rehoover flag")
          try? clearPendingRehoover(transcriptId: transcript.id)
        } else {
          log.warning("[LAZY-WATCHER] Skipping transcript \(transcript.id, privacy: .public) due to mtime fetch error: \(error.localizedDescription, privacy: .public)")
        }
        continue
      }
      let cachedMtimeMs = Int64(transcript.mtimeMs ?? 0)
      let shouldRehoover = transcript.pendingRehoover == 1 || currentMtimeMs > cachedMtimeMs

      guard shouldRehoover else { continue }

      if needsSecurityScope(provider: transcript.provider), let accessProvider {
        try accessProvider.withAccess(for: transcript.provider) { _ in
          _ = try hooverEngine.hooverTranscript(transcript, fileURL: fileURL, progress: NoOpProgressSink())
        }
      } else {
        _ = try hooverEngine.hooverTranscript(transcript, fileURL: fileURL, progress: NoOpProgressSink())
      }

      if let baselineLastEntryTs = try fetchLatestEntryTimestamp(transcriptId: transcript.id) {
        let baselineFileSize = try fetchFileSize(fileURL: fileURL, provider: transcript.provider)
        try updateTranscriptBaseline(
          transcriptId: transcript.id,
          knownLastEntryTs: baselineLastEntryTs,
          knownFileSize: baselineFileSize
        )
      }

      try updateTranscriptMtimeMs(transcriptId: transcript.id, mtimeMs: currentMtimeMs)
      try clearPendingRehoover(transcriptId: transcript.id)
      try clearUnreadApproximation(transcriptId: transcript.id)
      rehoovered += 1
    }

    return rehoovered
  }

  private func clearPendingRehoover(transcriptId: String) throws {
    let pool = try dbManager.pool
    try pool.write { db in
      try db.execute(sql: """
        UPDATE transcripts
        SET pending_rehoover = 0,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])
    }
  }

  private func updateTranscriptMtimeMs(transcriptId: String, mtimeMs: Int64) throws {
    let pool = try dbManager.pool
    let lastModifiedSeconds = Int(TimeInterval(mtimeMs) / 1000.0)
    try pool.write { db in
      try db.execute(sql: """
        UPDATE transcripts
        SET mtime_ms = ?,
            last_modified = ?,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        mtimeMs,
        lastModifiedSeconds,
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])
    }
  }

  private func fetchMtimeMs(fileURL: URL, provider: String) throws -> Int64 {
    if needsSecurityScope(provider: provider), let accessProvider {
      return try accessProvider.withAccess(for: provider) { _ in
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = (attrs[.modificationDate] as? Date) ?? .distantPast
        return Int64(modDate.timeIntervalSince1970 * 1000)
      }
    }

    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let modDate = (attrs[.modificationDate] as? Date) ?? .distantPast
    return Int64(modDate.timeIntervalSince1970 * 1000)
  }

  private func fetchFileSize(fileURL: URL, provider: String) throws -> Int64 {
    if needsSecurityScope(provider: provider), let accessProvider {
      return try accessProvider.withAccess(for: provider) { _ in
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
      }
    }

    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    return (attrs[.size] as? NSNumber)?.int64Value ?? 0
  }

  private func fetchLatestEntryTimestamp(transcriptId: String) throws -> Double? {
    let pool = try dbManager.pool
    return try pool.read { db in
      try Double.fetchOne(
        db,
        sql: "SELECT MAX(created_ts) FROM transcript_entries WHERE transcript_id = ?",
        arguments: [transcriptId]
      )
    }
  }

  private func isFdExhaustionError(_ error: Error) -> Bool {
    if case let TranscriptWatcherError.fileDescriptorOpenFailed(errno) = error {
      return errno == EMFILE || errno == ENFILE
    }
    return false
  }

  // MARK: - Assistant Usage Reconciliation

  /// Reconcile pending assistant_usage records with transcript_entries
  /// Moves staged usage records from assistant_usage_pending → assistant_usage when their entries appear
  /// Also prunes stale pending records (7+ days old)
  /// Call after hoover passes and at startup to ensure usage metrics are eventually attached
  public func reconcileAssistantUsage(prune: Bool = true) throws {
    let pool = try dbManager.pool
    try pool.write { db in
      // Count pending before reconciliation
      let beforeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM assistant_usage_pending") ?? 0

      // Move pending usage records that now have matching entries
      try db.execute(sql: """
        INSERT OR IGNORE INTO assistant_usage (
          entry_id, request_id, model, input_tokens, output_tokens,
          cache_creation_tokens, cache_read_tokens, service_tier,
          ephemeral_5m_tokens, ephemeral_1h_tokens
        )
        SELECT p.entry_id, p.request_id, p.model, p.input_tokens, p.output_tokens,
               p.cache_creation_tokens, p.cache_read_tokens, p.service_tier,
               p.ephemeral_5m_tokens, p.ephemeral_1h_tokens
        FROM assistant_usage_pending p
        WHERE EXISTS (SELECT 1 FROM transcript_entries e WHERE e.id = p.entry_id)
      """)

      // Clean up pending records that have been reconciled
      let stmt = try db.makeStatement(sql: """
        DELETE FROM assistant_usage_pending
        WHERE entry_id IN (SELECT id FROM transcript_entries)
      """)
      try stmt.execute()
      let reconciledCount = db.changesCount

      // Prune stale pending records (7+ days old) if requested
      var prunedCount = 0
      if prune {
        let pruneStmt = try db.makeStatement(sql: """
          DELETE FROM assistant_usage_pending
          WHERE created_at IS NOT NULL
            AND strftime('%s','now') - strftime('%s', created_at) > 7*24*3600
        """)
        try pruneStmt.execute()
        prunedCount = db.changesCount
      }

      // Count remaining pending
      let afterCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM assistant_usage_pending") ?? 0

      // Log telemetry for visibility
      if reconciledCount > 0 || prunedCount > 0 || afterCount > 0 {
        log.info("assistant_usage reconciled: \(reconciledCount) moved, \(prunedCount) pruned, \(afterCount) remaining (was \(beforeCount))")
      }
    }
  }

  // MARK: - Active Session Follow (v23)

  /// Input for inserting system switch events
  public struct SystemEventInsert: Sendable {
    public let id: String
    public let transcriptId: String
    public let projectId: String  // F: TEXT to match projects(id)
    public let timestampMs: Int64
    public let content: String
    public let metadataJSON: String

    public init(id: String, transcriptId: String, projectId: String, timestampMs: Int64, content: String, metadataJSON: String) {
      self.id = id
      self.transcriptId = transcriptId
      self.projectId = projectId
      self.timestampMs = timestampMs
      self.content = content
      self.metadataJSON = metadataJSON
    }
  }

  /// Set project to automatic follow mode
  public func setAutomatic(projectId: String) async throws {
    try await writeQueue.write { db in
      try db.execute(sql: """
        INSERT INTO project_follow_policy(project_id, mode, pinned_session_id, pinned_provider, updated_at)
        VALUES (?, 0, NULL, NULL, strftime('%Y-%m-%dT%H:%M:%SZ','now'))
        ON CONFLICT(project_id) DO UPDATE SET
          mode=excluded.mode,
          pinned_session_id=NULL,
          pinned_provider=NULL,
          updated_at=excluded.updated_at
      """, arguments: [projectId])
    }
  }

  /// Set project to manual follow mode with pinned session
  public func setManual(projectId: String, sessionId: String, provider: String) async throws {
    try await writeQueue.write { db in
      try db.execute(sql: """
        INSERT INTO project_follow_policy(project_id, mode, pinned_session_id, pinned_provider, updated_at)
        VALUES (?, 1, ?, ?, strftime('%Y-%m-%dT%H:%M:%SZ','now'))
        ON CONFLICT(project_id) DO UPDATE SET
          mode=excluded.mode,
          pinned_session_id=excluded.pinned_session_id,
          pinned_provider=excluded.pinned_provider,
          updated_at=excluded.updated_at
      """, arguments: [projectId, sessionId, provider])
    }
  }

  /// Insert a system switch event (persisted to DB)
  /// R2: Project-scoped events use empty transcript_id ("") as sentinel value.
  ///     These rows must be filtered by project_id only - do not JOIN to transcripts table.
  public func insertSystemEvent(_ e: SystemEventInsert) async throws {
    try await writeQueue.write { db in
      try db.execute(sql: """
        INSERT INTO system_events(id, transcript_id, project_id, timestamp, subtype, content, level, metadata_json)
        VALUES (?, ?, ?, ?, 'session_switch', ?, 'info', ?)
      """, arguments: [e.id, e.transcriptId, e.projectId, e.timestampMs, e.content, e.metadataJSON])
    }
  }

  /// Retrieve recent system switch events for a project (for restart-safe timeline display)
  public func getRecentSystemSwitchEvents(projectId: String, since: Int64?) async throws -> [SystemEvent] {
    let pool = try dbManager.pool
    return try await pool.read { db in
      if let since {
        return try SystemEvent.fetchAll(db, sql: """
          SELECT *
            FROM system_events
           WHERE project_id = ?
             AND subtype = 'session_switch'
             AND timestamp > ?
           ORDER BY timestamp ASC
        """, arguments: [projectId, since])
      } else {
        return try SystemEvent.fetchAll(db, sql: """
          SELECT *
            FROM system_events
           WHERE project_id = ?
             AND subtype = 'session_switch'
           ORDER BY timestamp ASC
        """, arguments: [projectId])
      }
    }
  }

  /// Get follow policy for a project
  /// P1: Made async to avoid blocking main thread during startup
  public func getFollowPolicy(projectId: String) async throws -> FollowPolicyRow? {
    let pool = try dbManager.pool
    return try await pool.read { db in
      try FollowPolicyRow.fetchOne(db, sql: """
        SELECT * FROM project_follow_policy WHERE project_id = ?
      """, arguments: [projectId])
    }
  }

  /// Get entries after a cursor for deterministic incremental ingestion
  /// Uses composite cursor (timestamp, created_at, id) with covering index
  /// Handles out-of-order entry arrival without skips or duplicates
  public func getEntriesAfterCursor(projectId: String, after cursor: EntryCursor?) throws -> [TranscriptEntry] {
    let pool = try dbManager.pool
    return try pool.read { db in
      if let c = cursor {
        // Scalar comparison workaround (SQLite has no tuple >)
        return try TranscriptEntry.fetchAll(db, sql: """
          SELECT * FROM transcript_entries
           WHERE project_id = :pid
             AND display_in_timeline = 1
             AND is_sidechain = 0
             AND (
                  timestamp > :ts
               OR (timestamp = :ts AND created_at > :ca)
               OR (timestamp = :ts AND created_at = :ca AND id > :id)
             )
           ORDER BY timestamp ASC, created_at ASC, id ASC
        """, arguments: ["pid": projectId, "ts": c.timestamp, "ca": c.createdAt, "id": c.id])
      } else {
        // Initial load: no cursor
        return try TranscriptEntry.fetchAll(db, sql: """
          SELECT * FROM transcript_entries
           WHERE project_id = :pid
             AND display_in_timeline = 1
             AND is_sidechain = 0
           ORDER BY timestamp ASC, created_at ASC, id ASC
        """, arguments: ["pid": projectId])
      }
    }
  }

  // MARK: - Repair Functions (Issue #2 fix)

  /// Get transcripts with 0 entries (parser failures that need re-ingestion)
  public func getZeroEntryTranscripts(limit: Int) throws -> [String] {
    try dbManager.pool.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT t.id
          FROM transcripts t
          LEFT JOIN transcript_entries e ON e.transcript_id = t.id
          WHERE e.transcript_id IS NULL
            AND NOT EXISTS (SELECT 1 FROM parse_errors pe WHERE pe.transcript_id = t.id)
          ORDER BY t.updated_at DESC
          LIMIT ?
        """,
        arguments: [limit]
      )
    }
  }

  /// Reset transcript checkpoints for re-ingestion
  public func resetTranscriptCheckpoints(transcriptIds: [String]) throws {
    try dbManager.pool.write { db in
      for transcriptId in transcriptIds {
        try db.execute(
          sql: """
            UPDATE transcripts
            SET ingest_state = 'partial',
                last_processed_line = 0,
                last_processed_entry_id = NULL,
                last_error = NULL,
                status = 'active'
            WHERE id = ?
          """,
          arguments: [transcriptId]
        )
      }
    }
  }

  // MARK: - Cleanup

  public func stopAllWatchers() {
    watcher.stopAll()
  }

  // MARK: - Tab Group Operations (v33)

  /// List all tab groups
  public func listTabGroups() throws -> [TabGroup] {
    try tabGroupRepo.list()
  }

  /// Get a tab group by ID
  public func getTabGroup(id: String) throws -> TabGroup? {
    try tabGroupRepo.get(id: id)
  }

  /// Get the tab group for a git root (for worktree grouping)
  public func getTabGroupByGitRoot(_ gitRoot: String) throws -> TabGroup? {
    try tabGroupRepo.getByGitRoot(gitRoot)
  }

  /// Create a new tab group
  public func createTabGroup(
    name: String? = nil,
    colorHex: String? = nil,
    gitRoot: String? = nil,
    isWorktreeGroup: Bool = false
  ) throws -> TabGroup {
    try tabGroupRepo.create(name: name, colorHex: colorHex, gitRoot: gitRoot, isWorktreeGroup: isWorktreeGroup)
  }

  /// Update a tab group's name
  public func setTabGroupName(id: String, name: String?) throws {
    try tabGroupRepo.setName(id: id, name: name)
  }

  /// Update a tab group's color (or clear to auto)
  public func setTabGroupColor(id: String, colorHex: String?) throws {
    try tabGroupRepo.setColorOverride(id: id, colorHex: colorHex)
  }

  /// Delete a tab group (projects will have group_id set to NULL)
  public func deleteTabGroup(id: String) throws {
    try tabGroupRepo.delete(id: id)
  }

  /// Delete a tab group if it has no members
  public func deleteTabGroupIfEmpty(id: String) throws -> Bool {
    try tabGroupRepo.deleteIfEmpty(id: id)
  }

  /// Add a project to a tab group
  public func addProjectToGroup(projectId: String, groupId: String, displayOrder: Int? = nil) throws {
    let order = try displayOrder ?? (projectRepo.get(id: projectId)?.displayOrder ?? 0)
    try projectRepo.setGroupMembership(id: projectId, groupId: groupId, groupDisplayOrder: order)
  }

  /// Remove a project from its tab group (becomes solo tab)
  public func removeProjectFromGroup(projectId: String) throws {
    try projectRepo.setGroupMembership(id: projectId, groupId: nil, groupDisplayOrder: nil)
  }

  /// Get worktree preference for a git root
  public func getWorktreePreference(_ gitRoot: String) throws -> WorktreePreference? {
    try worktreePreferenceRepo.get(gitRoot)
  }

  /// Set worktree as ungrouped (prevents auto-grouping)
  public func setWorktreeUngrouped(_ gitRoot: String, ungrouped: Bool) throws {
    try worktreePreferenceRepo.setUngrouped(gitRoot, ungrouped: ungrouped)
  }

  // MARK: - Worktree Auto-Grouping (Phase 4)

  /// Auto-group projects that share the same git root into worktree groups.
  /// Called on startup and when new projects are discovered.
  /// Returns number of groups created or updated.
  @discardableResult
  public func autoGroupWorktrees() throws -> Int {
    // 1. Get all visible, non-orphaned projects
    let projects = try projectRepo.list().filter { !$0.hidden && !$0.isOrphaned }

    // 2. Compute git roots for each project (Swift-side computation)
    // Use findMainGitRoot to properly resolve worktrees to their main repository
    var projectsByGitRoot: [String: [Project]] = [:]
    for project in projects {
      let projectURL = URL(fileURLWithPath: project.rootPath)
      if let gitRoot = GitRepositoryResolver.findMainGitRoot(startingAt: projectURL) {
        let key = gitRoot.path
        projectsByGitRoot[key, default: []].append(project)
      }
    }

    // 3. Process each git root with 2+ projects
    var groupsCreatedOrUpdated = 0
    for (gitRootPath, siblingProjects) in projectsByGitRoot where siblingProjects.count >= 2 {
      // Check if user has explicitly ungrouped this worktree
      if let pref = try worktreePreferenceRepo.get(gitRootPath), pref.ungrouped {
        log.debug("[WORKTREE-AUTOGROUP] Skipping ungrouped worktree: \(gitRootPath, privacy: .public)")
        continue
      }

      // Check if worktree group already exists
      var group: TabGroup
      if let existingGroup = try tabGroupRepo.getByGitRoot(gitRootPath) {
        group = existingGroup
        log.debug("[WORKTREE-AUTOGROUP] Using existing group: \(group.id, privacy: .public) for \(gitRootPath, privacy: .public)")
      } else {
        // Create new worktree group
        let repoName = URL(fileURLWithPath: gitRootPath).lastPathComponent
        group = try tabGroupRepo.create(
          name: repoName,
          colorHex: nil,  // Auto-compute from git root hash
          gitRoot: gitRootPath,
          isWorktreeGroup: true
        )
        groupsCreatedOrUpdated += 1
        log.info("[WORKTREE-AUTOGROUP] Created new worktree group: \(group.id, privacy: .public) for \(gitRootPath, privacy: .public)")
      }

      // Add all sibling projects to the group (if not already members)
      // P0.1 fix: For existing groups, compute nextOrder from max existing group_display_order
      // to avoid collisions with existing members
      let existingMembers = try projectRepo.list().filter { $0.groupId == group.id }
      let maxExistingOrder = existingMembers.compactMap(\.groupDisplayOrder).max() ?? -1
      var nextOrder = maxExistingOrder + 1

      for project in siblingProjects {
        if project.groupId != group.id {
          try projectRepo.setGroupMembership(id: project.id, groupId: group.id, groupDisplayOrder: nextOrder)
          nextOrder += 1
          log.debug("[WORKTREE-AUTOGROUP] Added project \(project.id, privacy: .public) to group \(group.id, privacy: .public) at order \(nextOrder - 1, privacy: .public)")
        }
      }
    }

    if groupsCreatedOrUpdated > 0 {
      log.info("[WORKTREE-AUTOGROUP] Auto-grouping complete: \(groupsCreatedOrUpdated, privacy: .public) groups created")
    }

    return groupsCreatedOrUpdated
  }

  /// Ungroup all projects from a worktree group and delete the group.
  /// Sets worktree_preferences.ungrouped = true to prevent re-grouping.
  public func ungroupWorktree(gitRoot: String) throws {
    // 1. Find the worktree group
    guard let group = try tabGroupRepo.getByGitRoot(gitRoot) else {
      log.warning("[WORKTREE-UNGROUP] No worktree group found for: \(gitRoot, privacy: .public)")
      return
    }

    // 2. Get all projects in this group
    let projects = try projectRepo.list().filter { $0.groupId == group.id }

    // 3. Remove all projects from the group
    for project in projects {
      try projectRepo.setGroupMembership(id: project.id, groupId: nil, groupDisplayOrder: nil)
    }

    // 4. Delete the empty group
    try tabGroupRepo.delete(id: group.id)

    // 5. Set preference to prevent re-grouping
    try worktreePreferenceRepo.setUngrouped(gitRoot, ungrouped: true)

    log.info("[WORKTREE-UNGROUP] Ungrouped \(projects.count, privacy: .public) projects from worktree: \(gitRoot, privacy: .public)")
  }

  /// Regroup projects that share a git root into a worktree group.
  /// Clears worktree_preferences.ungrouped to allow grouping.
  public func regroupWorktree(gitRoot: String) throws {
    // 1. Clear the ungrouped preference
    try worktreePreferenceRepo.setUngrouped(gitRoot, ungrouped: false)

    // 2. Find all projects with this git root
    // Use findMainGitRoot to properly resolve worktrees to their main repository
    let allProjects = try projectRepo.list().filter { !$0.hidden && !$0.isOrphaned }
    let siblingProjects = allProjects.filter { project in
      let projectURL = URL(fileURLWithPath: project.rootPath)
      if let projectGitRoot = GitRepositoryResolver.findMainGitRoot(startingAt: projectURL) {
        return projectGitRoot.path == gitRoot
      }
      return false
    }

    guard siblingProjects.count >= 2 else {
      log.info("[WORKTREE-REGROUP] Not enough siblings to regroup: \(siblingProjects.count, privacy: .public)")
      return
    }

    // 3. Create new worktree group
    let repoName = URL(fileURLWithPath: gitRoot).lastPathComponent
    let group = try tabGroupRepo.create(
      name: repoName,
      colorHex: nil,
      gitRoot: gitRoot,
      isWorktreeGroup: true
    )

    // 4. Add all siblings to the group
    for (order, project) in siblingProjects.enumerated() {
      try projectRepo.setGroupMembership(id: project.id, groupId: group.id, groupDisplayOrder: order)
    }

    log.info("[WORKTREE-REGROUP] Regrouped \(siblingProjects.count, privacy: .public) projects into worktree: \(gitRoot, privacy: .public)")
  }

  // MARK: - Phase 5: Group/Tab Ordering Persistence

  /// Reorder projects within a group by updating their group_display_order values.
  /// The order is determined by position in the orderedProjectIds array.
  public func reorderProjectsInGroup(groupId: String, orderedProjectIds: [String]) throws {
    for (order, projectId) in orderedProjectIds.enumerated() {
      try projectRepo.setGroupMembership(id: projectId, groupId: groupId, groupDisplayOrder: order)
    }
    log.info("[GROUP-REORDER] Reordered \(orderedProjectIds.count, privacy: .public) projects in group \(groupId, privacy: .public)")
  }

  /// Reorder tab groups by updating their display_order values.
  /// The order is determined by position in the orderedGroupIds array.
  public func reorderTabGroups(orderedGroupIds: [String]) throws {
    try tabGroupRepo.reorderGroups(orderedGroupIds)
    log.info("[GROUP-REORDER] Reordered \(orderedGroupIds.count, privacy: .public) tab groups")
  }
}

// MARK: - Follow Policy Models

/// Row representation of project_follow_policy table
public struct FollowPolicyRow: Codable, FetchableRecord, Sendable {
  public let projectId: String  // P0-1: TEXT to match projects(id)
  public let mode: Int  // 0=auto, 1=manual
  public let pinnedSessionId: String?
  public let pinnedProvider: String?
  public let updatedAt: String

  enum CodingKeys: String, CodingKey {
    case projectId = "project_id"
    case mode
    case pinnedSessionId = "pinned_session_id"
    case pinnedProvider = "pinned_provider"
    case updatedAt = "updated_at"
  }
}
