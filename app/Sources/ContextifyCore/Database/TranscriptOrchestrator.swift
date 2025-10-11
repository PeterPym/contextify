import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "TranscriptOrchestrator")

/// High-level orchestrator for transcript ingestion and monitoring
@MainActor
public final class TranscriptOrchestrator {
  private let dbManager: DatabaseManager
  private let projectRepo: ProjectRepository
  private let transcriptRepo: TranscriptRepository
  private let entryRepo: EntryRepository
  private let errorRepo: ParseErrorRepository
  private let metadataRepo: MetadataRepository
  nonisolated(unsafe) private let cacheRepo: CacheRepository  // Thread-safe via GRDB pool

  private let hooverEngine: HooverEngine
  private let watcher: TranscriptWatcher

  public init(dbManager: DatabaseManager = .shared) throws {
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
      return existing.id
    }

    // Create new project
    return try projectRepo.create(name: name, rootPath: rootPath, bookmark: bookmark)
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
    // Get file metadata
    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let lastModified = attrs[.modificationDate] as? Date ?? Date()
    let fileSize = attrs[.size] as? Int

    // Upsert transcript record
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: fileURL,
      provider: provider,
      providerSessionId: providerSessionId,
      lastModified: lastModified,
      fileSize: fileSize
    )

    // Get transcript
    guard let transcript = try transcriptRepo.get(transcriptId) else {
      throw RepositoryError.notFound
    }

    // Hoover the transcript
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

  public func searchEntries(content: String, projectId: String?) throws -> [TranscriptEntry] {
    try entryRepo.search(content: content, projectId: projectId)
  }

  // v2: Single-query feed with cache join
  public func getRecentFeed(forProject projectId: String, limit: Int = 50, generatorSignature: String) throws -> [(TranscriptEntry, TimelineCache?)] {
    try entryRepo.recentFeed(projectId: projectId, limit: limit, generatorSignature: generatorSignature)
  }

  // MARK: - Cache Management

  nonisolated public func getCachedTimeline(contentSha256: String, windowSha256: String) throws -> TimelineCache? {
    try cacheRepo.get(contentSha256: contentSha256, windowSha256: windowSha256)
  }

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
