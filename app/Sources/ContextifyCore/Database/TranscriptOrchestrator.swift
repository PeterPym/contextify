import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "TranscriptOrchestrator")

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

    // Initialize hoover engine with multi-provider parser
    let parser = MultiProviderParser()
    self.hooverEngine = HooverEngine(
      db: pool,
      transcriptRepo: transcriptRepo,
      entryRepo: entryRepo,
      errorRepo: errorRepo,
      parser: parser
    )

    // Initialize watcher
    self.watcher = TranscriptWatcher(
      hooverEngine: hooverEngine,
      transcriptRepo: transcriptRepo
    )
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

  // MARK: - Transcript Queries

  public func getTranscripts(forProject projectId: String) throws -> [Transcript] {
    try transcriptRepo.byProject(projectId)
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

  public func saveMetadata(_ metadata: TranscriptMetadataRecord) throws {
    try metadataRepo.upsert(metadata)
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

  // MARK: - Cleanup

  public func stopAllWatchers() {
    watcher.stopAll()
  }
}
