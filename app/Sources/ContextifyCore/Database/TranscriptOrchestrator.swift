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

  public init(fileURL: URL, provider: String, sessionId: String?) {
    self.fileURL = fileURL
    self.provider = provider
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

/// High-level orchestrator for transcript ingestion and monitoring
/// NOT @MainActor - allows safe concurrent access from background tasks
/// Sendable: GRDB pool handles thread-safety, repositories are stateless
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

  public init(dbManager: DatabaseManager) throws {
    self.dbManager = dbManager
    let pool = try dbManager.pool

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

    // Set metadata invalidation callback with weak self reference
    watcher.setMetadataInvalidator { [weak self] transcriptId in
      try? self?.deleteMetadata(forTranscript: transcriptId)
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
    log.info("Created new project: \(projectId) for path: \(canon)")

    // Verify the project was created
    if let verified = try projectRepo.get(id: projectId) {
      log.info("✅ Project creation verified: \(verified.id)")
    } else {
      log.error("❌ Project creation failed - cannot retrieve project \(projectId)")
    }

    return projectId
  }

  public func listProjects() throws -> [Project] {
    try projectRepo.list()
  }

  public func getProject(id: String) throws -> Project? {
    try projectRepo.get(id: id)
  }

  public func setProjectHidden(projectId: String, hidden: Bool) throws {
    try projectRepo.setHidden(id: projectId, hidden: hidden)
  }

  public func setProjectDisplayOrder(projectId: String, displayOrder: Int) throws {
    try projectRepo.setDisplayOrder(id: projectId, displayOrder: displayOrder)
  }

  /// Atomically update display order for all projects in a single transaction
  /// Uses two-phase update to avoid transient unique constraint violations if added later
  public func setProjectDisplayOrderBulk(_ orderedIds: [String]) throws {
    let now = Int(Date().timeIntervalSince1970)
    try dbManager.pool.write { db in
      // Phase 1: move to temporary high range to avoid transient conflicts
      for (i, id) in orderedIds.enumerated() {
        try db.execute(sql: "UPDATE projects SET display_order = ? WHERE id = ?", arguments: [i + 10_000, id])
      }
      // Phase 2: final ordering + updated_at
      for (i, id) in orderedIds.enumerated() {
        try db.execute(sql: "UPDATE projects SET display_order = ?, updated_at = ? WHERE id = ?", arguments: [i, now, id])
      }
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
    progress: IngestProgressSink? = nil
  ) throws {
    // Diagnostic: Verify project exists before proceeding
    guard let project = try projectRepo.get(id: projectId) else {
      log.error("❌ FK validation failed: project \(projectId) does not exist")
      throw RepositoryError.notFound
    }
    log.debug("✅ FK validation: project \(projectId) exists")

    // Get file metadata
    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let lastModified = attrs[.modificationDate] as? Date ?? Date()
    let fileSize = attrs[.size] as? Int

    // Upsert transcript record
    log.debug("Upserting transcript for project \(projectId), file: \(fileURL.lastPathComponent)")
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: fileURL,
      provider: provider,
      providerSessionId: providerSessionId,
      lastModified: lastModified,
      fileSize: fileSize
    )
    log.debug("✅ Transcript upserted: \(transcriptId)")

    // Get transcript
    guard let transcript = try transcriptRepo.get(transcriptId) else {
      log.error("❌ Transcript \(transcriptId) not found after upsert")
      throw RepositoryError.notFound
    }

    // Verify transcript has correct project ID
    guard transcript.projectId == projectId else {
      log.error("❌ Transcript projectId mismatch: expected \(projectId), got \(transcript.projectId)")
      throw RepositoryError.invalidData
    }

    // Hoover the transcript
    log.debug("Hoovering transcript: \(transcriptId)")
    let progressSink = progress ?? NoOpProgressSink()
    let transcriptSHA256 = try hooverEngine.hooverTranscript(transcript, fileURL: fileURL, progress: progressSink)
    // TODO: pass transcriptSHA256 to metadata generation/persistence when implemented

    // Reconcile pending assistant_usage records after hoover completes
    try? reconcileAssistantUsage()

    // Start watching if requested
    if startWatching {
      try watcher.watch(transcriptId: transcriptId, fileURL: fileURL)
    }

    log.info("Discovered and hoovered transcript: \(transcriptId)")
  }

  /// Batch discover transcripts for a project
  public func discoverTranscripts(
    projectId: String,
    transcriptFiles: [(url: URL, provider: String, sessionId: String?)],
    progress: IngestProgressSink? = nil
  ) throws {
    guard let project = try projectRepo.get(id: projectId) else {
      throw RepositoryError.notFound
    }

    let progressSink = progress ?? NoOpProgressSink()
    progressSink.didStartProject(name: project.name ?? projectId, transcriptCount: transcriptFiles.count)

    for file in transcriptFiles {
      try discoverTranscript(
        projectId: projectId,
        fileURL: file.url,
        provider: file.provider,
        providerSessionId: file.sessionId,
        startWatching: true,
        progress: progressSink
      )
    }

    progressSink.didCompleteProject(name: project.name ?? projectId)
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
              line_count, last_processed_line, parser_version, status,
              created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """, arguments: [
            transcriptId, projectId, path, normalizedPath, pathHash,
            disc.provider, sessionIdArg,  // Pass nil as NULL, not empty string
            TimeUnits.secondsFromMs(mtimeMs), len > 0 ? Int(len) : nil, len, mtimeMs, sha,
            0, 0, 1, "active",
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

  public func getEntriesAfterCursor(forProject projectId: String, after: (timestamp: Int, createdAt: Int, id: String)) throws -> [TranscriptEntry] {
    try entryRepo.entriesAfterCursor(projectId: projectId, after: after)
  }

  public func searchEntries(content: String, projectId: String?) throws -> [TranscriptEntry] {
    try entryRepo.search(content: content, projectId: projectId)
  }

  public func latestTimestampsByTranscript(projectId: String) throws -> [String: Int] {
    try entryRepo.latestTimestampsByTranscript(projectId: projectId)
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

  nonisolated public func saveCachedTimeline(_ cache: TimelineCache) throws {
    try cacheRepo.upsert(cache)
  }

  nonisolated public func saveCachedTimelineMany(_ caches: [TimelineCache]) throws {
    try cacheRepo.upsertMany(caches)
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

  // MARK: - Cleanup

  public func stopAllWatchers() {
    watcher.stopAll()
  }
}
