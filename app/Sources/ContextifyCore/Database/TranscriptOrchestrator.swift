import Foundation
import GRDB
import OSLog
import CryptoKit

private let log = Logger(subsystem: "dev.contextify", category: "TranscriptOrchestrator")

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

  private let hooverEngine: HooverEngine
  private let watcher: TranscriptWatcher
  private let validator: TranscriptValidator
  private let ingestionLockTTL: TimeInterval = 600

  // v23: Write queue for serialized write operations (prevents SQLITE_BUSY)
  private let writeQueue: DatabaseWriteQueue

  private let accessProvider: TranscriptAccessProvider?

  public init(
    dbManager: DatabaseManager,
    accessProvider: TranscriptAccessProvider? = nil
  ) throws {
    self.dbManager = dbManager
    self.accessProvider = accessProvider
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

    // v7: Initialize metadata repositories
    let fileSnapshotRepo = FileSnapshotRepositoryImpl(db: pool)
    let trackedFileRepo = TrackedFileRepositoryImpl(db: pool)
    let transcriptSummaryRepo = TranscriptSummaryRepositoryImpl(db: pool)
    let systemEventRepo = SystemEventRepositoryImpl(db: pool)
    let assistantUsageRepo = AssistantUsageRepositoryImpl(db: pool)

    // Initialize hoover engine with multi-provider parser
    let parser = MultiProviderParser()
    let metadataParser = MultiProviderMetadataParser()
    self.hooverEngine = HooverEngine(
      db: pool,
      transcriptRepo: transcriptRepo,
      entryRepo: entryRepo,
      errorRepo: errorRepo,
      parser: parser,
      fileSnapshotRepo: fileSnapshotRepo,
      trackedFileRepo: trackedFileRepo,
      transcriptSummaryRepo: transcriptSummaryRepo,
      systemEventRepo: systemEventRepo,
      assistantUsageRepo: assistantUsageRepo,
      metadataParser: metadataParser
    )

    // Initialize watcher (invalidation callback set after initialization)
    self.watcher = TranscriptWatcher(
      hooverEngine: hooverEngine,
      transcriptRepo: transcriptRepo
    )

    // Initialize validator
    self.validator = TranscriptValidator()

    // Set metadata invalidation callback with weak self reference
    watcher.setMetadataInvalidator { [weak self] transcriptId in
      try? self?.deleteMetadata(forTranscript: transcriptId)
    }

    // Set re-hoover callback to route through discoverTranscript (applies security-scoped access)
    watcher.setRehoover { [weak self] projectId, fileURL, provider, sessionId in
      try self?.discoverTranscript(
        projectId: projectId,
        fileURL: fileURL,
        provider: provider,
        providerSessionId: sessionId,
        startWatching: false,  // Already watching
        progress: nil
      )
    }
  }

  // MARK: - Project Management

  public func createProject(name: String?, rootPath: String, bookmark: Data?) throws -> String {
    try projectRepo.create(name: name, rootPath: rootPath, bookmark: bookmark)
  }

  public func getOrCreateProject(name: String?, rootPath: String, bookmark: Data? = nil) throws -> String {
    // Try to find existing project by canonicalized path
    let canon = PathUtils.canonicalizePath(rootPath)
    if let existing = try projectRepo.list().first(where: { $0.rootPath == canon }) {
      log.info("Found existing project: \(existing.id) for path: \(canon)")
      return existing.id
    }

    // Create new project
    let projectId = try projectRepo.create(name: name, rootPath: rootPath, bookmark: bookmark)
    log.info("Created new project: \(projectId, privacy: .public) for path: \(canon)")

    // Verify the project was created
    if let verified = try projectRepo.get(id: projectId) {
      log.info("✅ Project creation verified: \(verified.id)")
    } else {
      log.error("❌ Project creation failed - cannot retrieve project \(projectId, privacy: .public)")
    }

    return projectId
  }

  public func listProjects() throws -> [Project] {
    try projectRepo.list()
  }

  /// List projects sorted by activity (most recent entry first)
  /// When display_order is NULL, sorts by newest entry timestamp
  public func listProjectsSortedByActivity() throws -> [Project] {
    try dbManager.pool.read { db in
      let sql = """
        SELECT p.*
        FROM projects p
        LEFT JOIN (
          SELECT project_id, MAX(created_ts) as max_entry_ts
          FROM transcript_entries
          GROUP BY project_id
        ) e ON p.id = e.project_id
        ORDER BY
          CASE WHEN p.display_order IS NOT NULL THEN 0 ELSE 1 END,
          p.display_order ASC,
          COALESCE(e.max_entry_ts, 0) DESC,
          p.created_at DESC
        """
      return try Project.fetchAll(db, sql: sql)
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

  public func markProjectOrphaned(projectId: String, orphanedSince: Int) throws {
    try projectRepo.markOrphaned(id: projectId, orphanedSince: orphanedSince)
  }

  public func markProjectRestored(projectId: String) throws {
    try projectRepo.markRestored(id: projectId)
  }

  // MARK: - Transcript Discovery & Ingestion

  /// Discover and ingest a transcript file
  public func discoverTranscript(
    projectId: String,
    fileURL: URL,
    provider: String,
    providerSessionId: String?,
    startWatching: Bool = true,
    progress: IngestProgressSink? = nil,
    ingestLimit: IngestLimit = .none
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
          progress: progress,
          ingestLimit: ingestLimit
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
        progress: progress,
        ingestLimit: ingestLimit
      )
    }
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

    // Validate transcript integrity before hoovering
    let validationResult = validator.validate(
      fileURL: fileURL,
      projectRootPath: project.rootPath ?? "",
      provider: provider
    )

    guard validationResult.isValid else {
      log.error("[TRANS-DISC-ERROR] ❌ Transcript validation failed for \(fileURL.lastPathComponent, privacy: .public)")
      for error in validationResult.errors {
        log.error("[TRANS-DISC-ERROR]    \(error.description, privacy: .public)")
      }
      throw validationResult.errors.first ?? RepositoryError.invalidData
    }

    log.info("[TRANS-DISC-VALID] ✅ Transcript validation passed: \(fileURL.lastPathComponent, privacy: .public)")

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

    // TODO: pass transcriptSHA256 to metadata generation/persistence when implemented

    // Reconcile pending assistant_usage records after hoover completes
    try? reconcileAssistantUsage()

    // Start watching if requested
    if startWatching {
      log.info("[TRANS-DISC-WATCH-START] Starting watcher for transcript: \(transcriptId, privacy: .public)")
      try watcher.watch(transcriptId: transcriptId, fileURL: fileURL)
      log.info("[TRANS-DISC-WATCH-DONE] ✅ Watcher started for transcript: \(transcriptId, privacy: .public)")
    }

    log.info("[TRANS-DISC-COMPLETE] ✅ Discovery complete for transcript: \(transcriptId, privacy: .public)")
  }

  private func needsSecurityScope(provider: String) -> Bool {
    return provider == TranscriptProviderID.claude || provider == TranscriptProviderID.codex
  }

  /// Batch discover transcripts for a project
  public func discoverTranscripts(
    projectId: String,
    transcriptFiles: [(url: URL, provider: String, sessionId: String?)],
    progress: IngestProgressSink? = nil,
    concurrency: Int = 8
  ) async throws {
    log.info("[BATCH-DISC-START] Starting parallel discovery for \(transcriptFiles.count, privacy: .public) transcripts in project: \(projectId, privacy: .public) (concurrency: \(concurrency, privacy: .public))")

    guard let project = try projectRepo.get(id: projectId) else {
      log.error("[BATCH-DISC-ERROR] Project not found: \(projectId, privacy: .public)")
      throw RepositoryError.notFound
    }

    let progressSink = progress ?? NoOpProgressSink()
    progressSink.didStartProject(name: project.name ?? projectId, transcriptCount: transcriptFiles.count)

    let total = transcriptFiles.count
    let completed = OSAllocatedUnfairLock(initialState: 0)
    let hasNotified = OSAllocatedUnfairLock(initialState: false)  // Track if we've sent progress notification

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
          try self.discoverTranscript(
            projectId: projectId,
            fileURL: file.url,
            provider: file.provider,
            providerSessionId: file.sessionId,
            startWatching: true,
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
    notifyUI: Bool = true
  ) throws -> Bool {
    guard let initialTranscript = try transcriptRepo.get(transcriptId) else {
      throw RepositoryError.notFound
    }

    if case .preview = mode, initialTranscript.ingestState == "complete" {
      log.debug("[FAST-PATH] Transcript already complete, skipping preview: \(transcriptId, privacy: .public)")
      return false
    }

    guard try acquireIngestionLock(transcriptId: transcriptId) else {
      log.debug("[INGEST-LOCK] Another worker is processing transcript: \(transcriptId, privacy: .public)")
      // Reload transcript to get current state (may have changed since initial read)
      let refreshedTranscript = try transcriptRepo.get(transcriptId)
      return refreshedTranscript?.ingestState == "partial"
    }

    defer { releaseIngestionLock(transcriptId: transcriptId) }

    let transcript = initialTranscript

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
      return false
    }

    try discoverTranscript(
      projectId: transcript.projectId,
      fileURL: fileURL,
      provider: transcript.provider,
      providerSessionId: transcript.providerSessionId,
      startWatching: true,
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
        WHERE ingest_state = 'partial'
        ORDER BY updated_at DESC
      """
      if let limit {
        sql += " LIMIT \(limit)"
      }
      return try Transcript.fetchAll(db, sql: sql)
    }
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
    guard let project = try projectRepo.get(id: projectId) else {
      log.error("❌ FK validation failed: project \(projectId, privacy: .public) does not exist")
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

    log.info("Upserted \(resolved.count) transcripts for project \(projectId, privacy: .public) (\(resolved.filter(\.wasCreated).count) new)")
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
    try transcriptRepo.byProject(projectId, privacy: .public)
  }

  /// Delete a transcript and all its associated data
  /// - Parameter transcriptId: Transcript ID to delete
  /// - Note: Cascading deletes will remove: transcript_entries, timeline_cache, parse_errors, file_snapshots, tracked_files, transcript_summaries, system_events, assistant_usage
  public func deleteTranscript(transcriptId: String) throws {
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
      """, arguments: [transcriptId]) ?? 0
    }
  }

  public func getEntries(forTranscript transcriptId: String, afterTimestamp: Int? = nil) throws -> [TranscriptEntry] {
    try entryRepo.byTranscript(transcriptId, afterTimestamp: afterTimestamp)
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
    let transcripts = try transcriptRepo.byProject(projectId, privacy: .public)
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
      log.info("Reconciled project \(projectId, privacy: .public): marked \(markedDeleted) transcripts as deleted")
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
  public func markProjectViewed(projectId: String, timestamp: String) throws {
    try projectVisitsRepo.markViewed(projectId: projectId, timestamp: timestamp)
  }

  /// Mark a project as selected (updates last_selected_at to now)
  public func markProjectSelected(projectId: String) throws {
    try projectVisitsRepo.markSelected(projectId: projectId)
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
  public func startWatchingTranscript(transcriptId: String, fileURL: URL) throws {
    guard !watcher.isWatching(transcriptId: transcriptId) else {
      return
    }
    try watcher.watch(transcriptId: transcriptId, fileURL: fileURL)
  }

  /// Check if a transcript is being watched
  public func isWatchingTranscript(transcriptId: String) -> Bool {
    return watcher.isWatching(transcriptId: transcriptId)
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
           WHERE project_id = :pid AND (
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
           ORDER BY timestamp ASC, created_at ASC, id ASC
        """, arguments: ["pid": projectId])
      }
    }
  }

  // MARK: - Cleanup

  public func stopAllWatchers() {
    watcher.stopAll()
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
