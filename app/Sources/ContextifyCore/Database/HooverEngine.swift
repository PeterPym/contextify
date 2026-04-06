import Foundation
import GRDB
#if canImport(OSLog)
import OSLog
#endif

#if canImport(OSLog)
private let log = Logger(subsystem: "dev.contextify", category: "HooverEngine")
#else
private let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "HooverEngine")
#endif

// MARK: - Configuration

public enum MonitorConfig {
  public static let fileWatcherDebounce: TimeInterval = 0.150
  /// Maximum batch size (clamped to prevent memory spikes and SQL parameter limit issues)
  private static let maxBatchLines = 10000
  /// Number of lines per batch commit. Default 1000, override via CONTEXTIFY_BATCH_LINES.
  /// Larger batches reduce transaction overhead but increase memory usage.
  /// P1.1: Clamped to maxBatchLines (10000) to prevent memory spikes and SQL issues.
  public static let batchLines: Int = {
    if let envValue = ProcessInfo.processInfo.environment["CONTEXTIFY_BATCH_LINES"],
       let value = Int(envValue), value > 0 {
      if value > maxBatchLines {
        // Log when clamping - use OSLog directly since we're in static init
        #if canImport(OSLog)
        let clampLog = Logger(subsystem: "dev.contextify", category: "MonitorConfig")
        clampLog.warning("[CONFIG] CONTEXTIFY_BATCH_LINES=\(value) exceeds max (\(maxBatchLines)), clamping")
        #endif
        return maxBatchLines
      }
      return value
    }
    return 1000
  }()
  public static let checkpointEveryLines: Int = 1000
  public static let parseErrorMaxChars: Int = 1024
  public static let parseErrorRetentionPerTranscript: Int = 500
  public static let parseErrorLogLimit: Int = 25
  public static let parseErrorAbortThreshold: Int = 50
  public static let enableHooverLoopTracing: Bool = {
    ProcessInfo.processInfo.environment["CONTEXTIFY_TRACE_HOOVER_LOOPS"] == "1"
  }()
  public static let enableHooverStorageTracing: Bool = {
    ProcessInfo.processInfo.environment["CONTEXTIFY_TRACE_HOOVER_STORAGE"] == "1"
  }()
  /// Enable detailed timing breakdown for performance analysis
  /// Set CONTEXTIFY_TRACE_HOOVER_TIMING=1 to see parse/hash/db.write time splits
  public static let enableHooverTimingTracing: Bool = {
    ProcessInfo.processInfo.environment["CONTEXTIFY_TRACE_HOOVER_TIMING"] == "1"
  }()
  /// Enable/disable queue message indicators in timeline
  /// Set CONTEXTIFY_SHOW_QUEUED=0 to hide queued message badges
  /// Default: enabled (shows QUEUED badges for messages sent while Claude is busy)
  public static let showQueuedMessages: Bool = {
    ProcessInfo.processInfo.environment["CONTEXTIFY_SHOW_QUEUED"] != "0"
  }()
}

// MARK: - Hoover Limits

public enum IngestLimit: Sendable {
  case none
  case entries(Int)

  var maxEntries: Int? {
    switch self {
    case .none:
      return nil
    case let .entries(value):
      return value
    }
  }
}

public struct HooverOutcome {
  public let processedLines: Int
  public let newEntries: Int
  public let reachedEOF: Bool
  public let lastEntryId: String?
  public let contentSha256: String?
  public let entriesSkipped: Int      // ParserError.skipEntry count
  public let entriesInserted: Int     // Actual DB inserts (from db.changesCount)
}

// MARK: - Timing Instrumentation

/// Tracks time spent in each phase of batch processing for performance analysis.
/// Enable with CONTEXTIFY_TRACE_HOOVER_TIMING=1
struct BatchTimingStats {
  var parseTimeMs: Double = 0
  var hashTimeMs: Double = 0
  var projectResolutionTimeMs: Double = 0
  var commitBatchTimeMs: Double = 0  // Total time in commitBatch (includes DB writes + overhead)
  var batchCount: Int = 0
  var entryCount: Int = 0

  func log(transcriptId: String, logger: Logger) {
    guard MonitorConfig.enableHooverTimingTracing else { return }
    let total = parseTimeMs + hashTimeMs + projectResolutionTimeMs + commitBatchTimeMs
    guard total > 0 else { return }
    let parsePercent = (parseTimeMs / total) * 100
    let hashPercent = (hashTimeMs / total) * 100
    let projectPercent = (projectResolutionTimeMs / total) * 100
    let commitPercent = (commitBatchTimeMs / total) * 100
    // Extract values to avoid capturing self in OSLog autoclosure
    let msg = String(format: "[HOOVER-TIMING] transcript=%@ batches=%d entries=%d total=%.0fms parse=%.0fms(%.1f%%) hash=%.0fms(%.1f%%) projectRes=%.0fms(%.1f%%) commit=%.0fms(%.1f%%)",
      transcriptId, batchCount, entryCount, total,
      parseTimeMs, parsePercent,
      hashTimeMs, hashPercent,
      projectResolutionTimeMs, projectPercent,
      commitBatchTimeMs, commitPercent)
    logger.warning("\(msg)")  // warning level so it appears in logs (info is filtered)
  }
}

// MARK: - Parsed Entry Insert

/// Intermediate struct for entries before DB insert
public struct EntryInsert {
  public let id: String
  public let transcriptId: String
  public let projectId: String
  public let sessionId: String?
  public let provider: String
  public let kind: String
  public let timestamp: Date
  public let content: String
  public let contentSha256: String
  public let parentId: String?
  public let gitBranch: String?
  public let gitCommit: String?
  public let cwd: String?
  public let hasTextContent: Bool  // true if contains "text" blocks, false if only "thinking"
  public let isQueued: Bool  // true if message is queued (queue-operation enqueue without remove/popAll/dequeue)
  public let isSidechain: Bool
  public let agentId: String?
  public let toolInvocations: [ToolInvocationInsert]
  public let toolResultData: [ToolResultData]
  // Session-level metadata (CC v2.1.82+): passed through for transcript table update
  public let slug: String?
  public let entrypoint: String?

  public init(
    id: String,
    transcriptId: String,
    projectId: String,
    sessionId: String?,
    provider: String,
    kind: String,
    timestamp: Date,
    content: String,
    contentSha256: String,
    parentId: String?,
    gitBranch: String?,
    gitCommit: String?,
    cwd: String?,
    hasTextContent: Bool = true,
    isQueued: Bool = false,
    isSidechain: Bool = false,
    agentId: String? = nil,
    toolInvocations: [ToolInvocationInsert] = [],
    toolResultData: [ToolResultData] = [],
    slug: String? = nil,
    entrypoint: String? = nil
  ) {
    self.id = id
    self.transcriptId = transcriptId
    self.projectId = projectId
    self.sessionId = sessionId
    self.provider = provider
    self.kind = kind
    self.timestamp = timestamp
    self.content = content
    self.contentSha256 = contentSha256
    self.parentId = parentId
    self.gitBranch = gitBranch
    self.gitCommit = gitCommit
    self.cwd = cwd
    self.hasTextContent = hasTextContent
    self.isQueued = isQueued
    self.isSidechain = isSidechain
    self.agentId = agentId
    self.toolInvocations = toolInvocations
    self.toolResultData = toolResultData
    self.slug = slug
    self.entrypoint = entrypoint
  }

  /// Returns a copy with an updated projectId
  public func withProjectId(_ newProjectId: String) -> EntryInsert {
    EntryInsert(
      id: id,
      transcriptId: transcriptId,
      projectId: newProjectId,
      sessionId: sessionId,
      provider: provider,
      kind: kind,
      timestamp: timestamp,
      content: content,
      contentSha256: contentSha256,
      parentId: parentId,
      gitBranch: gitBranch,
      gitCommit: gitCommit,
      cwd: cwd,
      hasTextContent: hasTextContent,
      isQueued: isQueued,
      isSidechain: isSidechain,
      agentId: agentId,
      toolInvocations: toolInvocations,
      toolResultData: toolResultData,
      slug: slug,
      entrypoint: entrypoint
    )
  }

  /// Convert to TranscriptEntry model
  public func toModel() -> TranscriptEntry {
    let now = Int(Date().timeIntervalSince1970)
    let epochSeconds = timestamp.timeIntervalSince1970
    return TranscriptEntry(
      id: id,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: sessionId,
      provider: provider,
      kind: kind,
      timestamp: Int(epochSeconds),
      content: content,
      contentSha256: contentSha256,
      displayInTimeline: hasTextContent ? 1 : 0,  // Hide thinking-only entries from timeline
      parentId: parentId,
      gitBranch: gitBranch,
      gitCommit: gitCommit,
      cwd: cwd,
      prev1Id: nil,
      prev2Id: nil,
      windowSha256: nil,
      createdTs: TimeUnits.truncateToMillis(epochSeconds),  // Truncate to milliseconds for consistent precision
      createdAt: now,
      updatedAt: now,
      isQueued: isQueued ? 1 : 0,
      isSidechain: isSidechain ? 1 : 0,
      sourceDeviceId: MachineID.current(),
      sourceDeviceName: DeviceName.current()
    )
  }
}

public struct ToolInvocationInsert: Sendable {
  public let toolName: String
  public let toolKey: String?
  public let toolUseId: String?
  public let isContextify: Bool
  public let startedAt: Date?
  public let metadataJson: String?
}

public struct ToolResultData: Sendable {
  public let toolUseId: String?
  public let entryId: String
  public let agentId: String?
  public let status: String?
  public let timestamp: Date
}

// MARK: - Metadata Batch (v7)

/// Container for accumulated metadata during ingestion
private struct MetadataBatch {
  var fileSnapshots: [FileSnapshot] = []
  var trackedFiles: [TrackedFile] = []
  var transcriptSummaries: [TranscriptSummary] = []
  var systemEvents: [SystemEvent] = []
  var assistantUsages: [AssistantUsage] = []
  var queueOperations: [QueueOperation] = []
  var customTitle: String?
  var sawCustomTitle = false

  mutating func add(_ result: MetadataParseResult) {
    if let snapshot = result.fileSnapshot {
      fileSnapshots.append(snapshot)
    }
    trackedFiles.append(contentsOf: result.trackedFiles)
    if let summary = result.transcriptSummary {
      transcriptSummaries.append(summary)
    }
    if let event = result.systemEvent {
      systemEvents.append(event)
    }
    if let usage = result.assistantUsage {
      assistantUsages.append(usage)
    }
    queueOperations.append(contentsOf: result.queueOperations)
    if result.sawCustomTitle {
      sawCustomTitle = true
      customTitle = result.customTitle
    }
  }

  mutating func clear() {
    fileSnapshots.removeAll()
    trackedFiles.removeAll()
    transcriptSummaries.removeAll()
    systemEvents.removeAll()
    assistantUsages.removeAll()
    queueOperations.removeAll()
    customTitle = nil
    sawCustomTitle = false
  }

  var isEmpty: Bool {
    fileSnapshots.isEmpty && trackedFiles.isEmpty && transcriptSummaries.isEmpty && systemEvents.isEmpty && assistantUsages.isEmpty && queueOperations.isEmpty && !sawCustomTitle
  }
}

// MARK: - Hoover Engine

/// Streaming transcript parser and ingestion engine
public final class HooverEngine {
  private let db: DatabasePool
  private let transcriptRepo: TranscriptRepository
  private let entryRepo: EntryRepository
  private let errorRepo: ParseErrorRepository
  private let projectRepo: ProjectRepository
  private let parser: TranscriptLineParser
  // v7 metadata repositories
  private let fileSnapshotRepo: FileSnapshotRepository
  private let trackedFileRepo: TrackedFileRepository
  private let transcriptSummaryRepo: TranscriptSummaryRepository
  private let systemEventRepo: SystemEventRepository
  private let assistantUsageRepo: AssistantUsageRepository
  private let metadataParser: TranscriptMetadataParser
  // Performance: Bulk ingest manager bypasses GRDB observation overhead
  private let bulkIngestManager: BulkIngestManager?

  public init(
    db: DatabasePool,
    transcriptRepo: TranscriptRepository,
    entryRepo: EntryRepository,
    errorRepo: ParseErrorRepository,
    projectRepo: ProjectRepository,
    parser: TranscriptLineParser,
    fileSnapshotRepo: FileSnapshotRepository,
    trackedFileRepo: TrackedFileRepository,
    transcriptSummaryRepo: TranscriptSummaryRepository,
    systemEventRepo: SystemEventRepository,
    assistantUsageRepo: AssistantUsageRepository,
    metadataParser: TranscriptMetadataParser,
    bulkIngestManager: BulkIngestManager? = nil
  ) {
    self.db = db
    self.transcriptRepo = transcriptRepo
    self.entryRepo = entryRepo
    self.errorRepo = errorRepo
    self.projectRepo = projectRepo
    self.parser = parser
    self.fileSnapshotRepo = fileSnapshotRepo
    self.trackedFileRepo = trackedFileRepo
    self.transcriptSummaryRepo = transcriptSummaryRepo
    self.systemEventRepo = systemEventRepo
    self.assistantUsageRepo = assistantUsageRepo
    self.metadataParser = metadataParser
    // Check feature flag for bulk ingest (can be disabled via CONTEXTIFY_USE_BULK_INGEST=0)
    let useBulkIngest = ProcessInfo.processInfo.environment["CONTEXTIFY_USE_BULK_INGEST"] != "0"
    self.bulkIngestManager = useBulkIngest ? bulkIngestManager : nil
    if bulkIngestManager != nil && !useBulkIngest {
      log.info("[HOOVER] Bulk ingest disabled via CONTEXTIFY_USE_BULK_INGEST=0")
    }
  }

  // MARK: - Project Resolution Cache (P0 fix: avoid per-entry DB lookups)

  /// Cache for project resolution within a single hooverTranscript call.
  /// Avoids O(N) DB lookups per entry by caching:
  /// - The transcript project's canonical rootPath (fetched once)
  /// - All projects (fetched once on first mismatch)
  /// - Canonical project roots (computed once per project, not per entry)
  /// - Sorted canonical roots for efficient longest-prefix matching (sorted by length descending)
  ///
  /// Internal visibility allows unit testing via @testable import.
  struct ProjectResolutionCache {
    var transcriptProjectRootPath: String?
    /// All projects fetched from DB (lazy-loaded on first cache miss). Note: newly created projects
    /// during this hoover run are NOT added here; they're only added to projectRootToId/sortedCanonicalRoots.
    /// This is intentional: allProjects is only used for initial population, not ongoing lookups.
    var allProjects: [Project]?
    var sortedCanonicalRoots: [String] = []  // All canonical roots sorted by length descending for prefix matching
    var projectRootToId: [String: String] = [:]  // canonical root -> projectId (single source of truth for root<->id mapping)
    var loggedRoots: Set<String> = []  // Track which resolved roots we've logged (P1: reduce log spam, keyed by root not cwd)
    var warnedEmptyCwds: Set<String> = []  // Track cwds that produced empty canonical paths (gate warning spam)

    // MARK: - Static Helpers

    /// Comparator for root paths: length descending, then lexicographic for tie-breaking.
    /// Static to avoid init-order footgun (instance property can't reference self before init).
    static func rootLess(_ lhs: String, _ rhs: String) -> Bool {
      if lhs.count != rhs.count { return lhs.count > rhs.count }
      return lhs < rhs  // Lexicographic tie-break for stability
    }

    /// Normalize a root path: strip trailing slash (except for "/").
    /// Centralizes normalization to avoid repeated inline checks.
    static func normalizeRoot(_ root: String) -> String {
      if root.isEmpty { return root }
      if root != "/" && root.hasSuffix("/") {
        return String(root.dropLast())
      }
      return root
    }

    /// Deterministic collision winner: prefer nonzero createdAt, then earliest, then lexicographic id.
    /// Returns true if (createdAt, id) is preferred over (overCreatedAt, overId).
    static func isPreferredWinner(createdAt: Int, id: String, overCreatedAt: Int, overId: String) -> Bool {
      // Prefer nonzero createdAt (zero may be sentinel for unset)
      if overCreatedAt == 0 && createdAt != 0 { return true }
      if createdAt == 0 && overCreatedAt != 0 { return false }
      // Then prefer earliest createdAt
      if createdAt != overCreatedAt { return createdAt < overCreatedAt }
      // Finally lexicographic id
      return id < overId
    }

    /// Append a loser prefix to the accumulator, respecting the cap.
    /// Used during single-pass collision resolution to avoid re-walking allProjects.
    static func appendLoserPrefix(
      _ prefix: String,
      forRoot root: String,
      into accumulator: inout [String: [String]],
      cap: Int
    ) {
      var losers = accumulator[root] ?? []
      if losers.count < cap {
        losers.append(prefix)
        accumulator[root] = losers
      }
    }

    /// Test-friendly initializer for unit testing prefix matching, insertion ordering, and collision resolution
    /// without mocking GRDB. Pass tuples of (projectId, canonicalRoot, createdAt).
    /// NOTE: The root param is normalized (trailing slash stripped) like production code,
    /// so test inputs like "/foo/" become "/foo" in the cache.
    init(projects: [(id: String, root: String, createdAt: Int)] = []) {
      guard !projects.isEmpty else { return }

      // Single-pass collision resolution (same as production code)
      var bestByRoot: [String: (id: String, root: String, createdAt: Int)] = [:]

      for project in projects {
        let root = Self.normalizeRoot(project.root)
        if root.isEmpty { continue }

        if let existing = bestByRoot[root] {
          // Use static helper for deterministic winner selection
          let newWins = Self.isPreferredWinner(
            createdAt: project.createdAt, id: project.id,
            overCreatedAt: existing.createdAt, overId: existing.id
          )
          if newWins {
            bestByRoot[root] = (project.id, root, project.createdAt)
          }
        } else {
          bestByRoot[root] = (project.id, root, project.createdAt)
        }
      }

      for (root, winner) in bestByRoot {
        projectRootToId[root] = winner.id
      }
      sortedCanonicalRoots = bestByRoot.keys.sorted(by: Self.rootLess)
    }

    /// Insert a new root into sortedCanonicalRoots maintaining sort order.
    /// Uses rootLess to ensure consistent ordering with initial sort.
    /// Guard against duplicate insertion (idempotent).
    mutating func insertRoot(_ newRoot: String) {
      // Guard: skip if already present (idempotent)
      if sortedCanonicalRoots.contains(newRoot) { return }

      // Find insertion point using the same comparator as sort
      var insertIndex = 0
      while insertIndex < sortedCanonicalRoots.count {
        if Self.rootLess(newRoot, sortedCanonicalRoots[insertIndex]) {
          break
        }
        insertIndex += 1
      }
      sortedCanonicalRoots.insert(newRoot, at: insertIndex)
    }

    /// Find the project ID for a cwd using longest-prefix matching on cached roots.
    /// Pure in-memory lookup - searches sortedCanonicalRoots (length-descending) and projectRootToId.
    /// Returns (projectId, matchingRoot) if found, nil otherwise.
    /// Marked mutating to keep call sites stable if we later add hit counters or per-root memoization.
    mutating func findProjectByPrefix(_ canonCwd: String) -> (projectId: String, matchingRoot: String)? {
      // Try exact match first (O(1) dictionary lookup)
      if let cachedId = projectRootToId[canonCwd] {
        return (cachedId, canonCwd)
      }
      // Try prefix match on cached roots (longest first due to sort order)
      for cachedRoot in sortedCanonicalRoots {
        if canonCwd == cachedRoot || canonCwd.hasPrefix(cachedRoot + "/") {
          if let projectId = projectRootToId[cachedRoot] {
            return (projectId, cachedRoot)
          }
        }
      }
      return nil
    }
  }

  /// Look up or create a project based on the CWD from an entry.
  /// Uses longest-prefix matching with cached canonical roots: finds the project whose rootPath
  /// is the longest prefix of canonCwd. Fast path checks cached roots before scanning allProjects.
  /// This handles subdirectory cwds correctly (e.g., cwd=/repo/app/src matches project /repo).
  /// Returns the project ID to use for the entry.
  ///
  /// TRANSACTION SAFETY: Must be called outside any db.write held by hooverTranscript.
  /// resolveProjectId is invoked before/after commitBatch, never within the write transaction.
  /// This method calls ProjectRepositoryImpl methods (get/list/create) which open their own
  /// db.read/write transactions internally.
  private func resolveProjectId(
    fromCwd cwd: String?,
    transcriptProjectId: String,
    transcriptId: String,
    cache: inout ProjectResolutionCache
  ) throws -> String {
    // If no CWD, use the transcript's project
    guard let entryCwd = cwd, !entryCwd.isEmpty else {
      return transcriptProjectId
    }

    // Canonicalize the CWD path and strip trailing slashes
    var canonCwd = PathUtils.canonicalizePath(entryCwd)

    // Handle empty string from canonicalizePath (weird inputs like broken symlinks)
    // Fall back to transcript project if canonicalization produces empty string
    // Gate warning to once per raw cwd to avoid log spam from repeated entries
    if canonCwd.isEmpty {
      if !cache.warnedEmptyCwds.contains(entryCwd) {
        cache.warnedEmptyCwds.insert(entryCwd)
        log.warning("[PROJECT-RESOLVE] canonicalizePath returned empty string for cwd=\(entryCwd) transcript=\(transcriptId.prefix(8)), falling back to transcript project")
      }
      return transcriptProjectId
    }

    canonCwd = ProjectResolutionCache.normalizeRoot(canonCwd)

    // Fetch transcript project's rootPath once per transcript (P0: single DB lookup)
    if cache.transcriptProjectRootPath == nil {
      if let transcriptProject = try projectRepo.get(id: transcriptProjectId) {
        let rootPath = ProjectResolutionCache.normalizeRoot(
          PathUtils.canonicalizePath(transcriptProject.rootPath)
        )
        cache.transcriptProjectRootPath = rootPath
        cache.projectRootToId[rootPath] = transcriptProjectId
        cache.sortedCanonicalRoots = [rootPath]  // Initial seed with transcript root

        // DEBUG assertion: verify seeding was successful immediately (not just after slow-path)
        #if DEBUG
        assert(cache.sortedCanonicalRoots.contains(rootPath),
               "Transcript root \(rootPath) missing from sortedCanonicalRoots immediately after seeding")
        assert(cache.projectRootToId[rootPath] != nil,
               "Transcript root \(rootPath) missing from projectRootToId immediately after seeding")
        #endif
      }
    }

    // Check if CWD is within transcript's project (common case - no reassignment needed)
    // OPTIMIZATION: This check is partially redundant since transcript root is in sortedCanonicalRoots,
    // but it avoids the loop overhead for the most common case (entries within transcript project).
    if let transcriptRoot = cache.transcriptProjectRootPath {
      if canonCwd == transcriptRoot || canonCwd.hasPrefix(transcriptRoot + "/") {
        return transcriptProjectId
      }
    }

    // FAST PATH - check cached roots before scanning allProjects
    // Uses findProjectByPrefix helper for both fast and slow paths to reduce duplication.
    if let (cachedProjectId, _) = cache.findProjectByPrefix(canonCwd) {
      return cachedProjectId
    }

    // SLOW PATH: Cache miss - need to scan all projects from database
    // Fetch all projects once per transcript (P0: single list fetch, reused for all mismatched entries)
    // NOTE: allProjects is only used as a source list for initial population; newly created projects
    // during this hoover run are added to sortedCanonicalRoots/projectRootToId but NOT allProjects.
    if cache.allProjects == nil {
      cache.allProjects = try projectRepo.list()

      // Build sorted roots list from all projects for fast prefix matching
      // Use Set to merge with any pre-seeded roots (e.g., transcript root) and avoid duplicates.
      // NOTE: Set merge also preserves newly created roots from earlier in this hoover run,
      // ensuring subsequent subdirectory entries find the newly created project without another create.
      var allRootsSet = Set(cache.sortedCanonicalRoots)  // Preserve seeded transcript root + any newly created roots

      // Single-pass collision resolution: track best winner per root and collision counts
      // Memory-efficient: O(unique roots) instead of O(projects) for collision tracking
      // Also accumulate loser prefixes during scan to avoid O(N^2) re-walk for logging
      var bestByRoot: [String: Project] = [:]  // canonical root -> winning project
      var collisionCounts: [String: Int] = [:]  // canonical root -> total project count (explicit: 2 on first collision)
      var loserPrefixesByRoot: [String: [String]] = [:]  // canonical root -> first 5 loser id prefixes
      let loserCap = 5

      for project in cache.allProjects ?? [] {
        let rawRoot = PathUtils.canonicalizePath(project.rootPath)
        let root = ProjectResolutionCache.normalizeRoot(rawRoot)

        // Guard against empty rootPath (broken symlinks, etc.)
        if root.isEmpty {
          log.warning("[PROJECT-RESOLVE] Skipping project \(project.id.prefix(8)) with empty canonical rootPath (raw: \(project.rootPath))")
          continue
        }

        // Track all roots for sortedCanonicalRoots (before collision resolution)
        allRootsSet.insert(root)

        if let existing = bestByRoot[root] {
          // Collision: use static helper for deterministic winner selection
          let newWins = ProjectResolutionCache.isPreferredWinner(
            createdAt: project.createdAt, id: project.id,
            overCreatedAt: existing.createdAt, overId: existing.id
          )

          if newWins {
            // New project wins - old winner becomes a loser
            ProjectResolutionCache.appendLoserPrefix(
              String(existing.id.prefix(8)), forRoot: root, into: &loserPrefixesByRoot, cap: loserCap
            )
            bestByRoot[root] = project
          } else {
            // Existing wins - new project is a loser
            ProjectResolutionCache.appendLoserPrefix(
              String(project.id.prefix(8)), forRoot: root, into: &loserPrefixesByRoot, cap: loserCap
            )
          }
          // Explicit count: first collision sets to 2, subsequent increment
          collisionCounts[root] = (collisionCounts[root] ?? 1) + 1
        } else {
          bestByRoot[root] = project
          collisionCounts[root] = 1  // First-seen root: initialize count
        }
      }

      // Log collisions using pre-accumulated loser prefixes (O(1) per root, not O(N))
      for (root, winner) in bestByRoot {
        if let count = collisionCounts[root], count > 1 {
          let losers = loserPrefixesByRoot[root] ?? []
          let loserIds = losers.joined(separator: ", ")
          let suffix = count > (loserCap + 1) ? " (+\(count - loserCap - 1) more)" : ""  // 1 winner + cap shown losers
          log.warning("[PROJECT-RESOLVE] Collision: root=\(root) has \(count) projects, keeping \(winner.id.prefix(8)) (earliest createdAt), ignoring: \(loserIds)\(suffix)")
        }

        cache.projectRootToId[root] = winner.id
      }

      // Sort by length descending, then lexicographically for deterministic tie-breaking
      cache.sortedCanonicalRoots = allRootsSet.sorted(by: ProjectResolutionCache.rootLess)

      // DEBUG assertion: transcript root should be in cache after seeding
      #if DEBUG
      if let transcriptRoot = cache.transcriptProjectRootPath {
        assert(cache.sortedCanonicalRoots.contains(transcriptRoot),
               "Transcript root \(transcriptRoot) missing from sortedCanonicalRoots after population")
        assert(cache.projectRootToId[transcriptRoot] != nil,
               "Transcript root \(transcriptRoot) missing from projectRootToId after population")
      }
      #endif
    }

    // Use findProjectByPrefix helper for longest-prefix matching (same as fast path)
    if let (projectId, projectRoot) = cache.findProjectByPrefix(canonCwd) {
      // Log once per resolved root (not per cwd) when project differs from transcript project
      // Include transcript context for actionable debugging
      let shouldLog = !cache.loggedRoots.contains(projectRoot) && projectId != transcriptProjectId
      if shouldLog {
        cache.loggedRoots.insert(projectRoot)
        log.debug("[PROJECT-REASSIGN] Entry reassigned: transcript=\(transcriptId.prefix(8)) transcriptProject=\(transcriptProjectId.prefix(8)) -> entryProject=\(projectId.prefix(8)) root=\(projectRoot)")
      }
      return projectId
    }

    // No containing project found - create new project for this CWD
    // Store canonical path, not raw path, to prevent duplicate projects
    let newProjectId = try projectRepo.create(name: nil, rootPath: canonCwd, bookmark: nil)

    // Log new project creation with transcript context (symmetric with reassignment log)
    let shouldLog = !cache.loggedRoots.contains(canonCwd)
    if shouldLog {
      cache.loggedRoots.insert(canonCwd)
      log.info("[PROJECT-REASSIGN] Created project: transcript=\(transcriptId.prefix(8)) transcriptProject=\(transcriptProjectId.prefix(8)) root=\(canonCwd) id=\(newProjectId.prefix(8))")
    }

    // Update cache structures with new project root
    // Guard against duplicate insertion (projectRootToId[canonCwd] should be nil for new projects)
    if cache.projectRootToId[canonCwd] == nil {
      cache.projectRootToId[canonCwd] = newProjectId

      // Add new root to sorted list using same comparator as initial sort
      cache.insertRoot(canonCwd)
    } else {
      // This shouldn't happen - we just created a project but root already exists
      let existingProjectId = cache.projectRootToId[canonCwd] ?? "nil"
      log.warning("[PROJECT-RESOLVE] Unexpected: created project \(newProjectId.prefix(8)) but root \(canonCwd) already mapped to \(existingProjectId)")
    }

    return newProjectId
  }

  /// Update transcript checkpoint in database
  /// Always call this after processing a transcript to persist the checkpoint
  private func updateCheckpoint(
    transcriptId: String,
    lastProcessedLine: Int,
    lastProcessedEntryId: String?,
    lineCount: Int,
    ingestState: String,
    status: String = "active",
    lastError: String? = nil
  ) throws {
    try db.write { db in
      try db.execute(sql: """
        UPDATE transcripts
        SET last_processed_line = ?,
            last_processed_entry_id = COALESCE(?, last_processed_entry_id),
            line_count = ?,
            parser_version = ?,
            status = ?,
            ingest_state = ?,
            last_error = ?,
            updated_at = ?
        WHERE id = ?
      """, arguments: [
        lastProcessedLine,
        lastProcessedEntryId,
        lineCount,
        1,
        status,
        ingestState,
        lastError,
        Int(Date().timeIntervalSince1970),
        transcriptId
      ])

      // Validate UPDATE succeeded
      let rowsAffected = db.changesCount
      log.info("[HOOVER-UPDATE-ROWS] UPDATE affected \(rowsAffected) rows for transcript: \(transcriptId), checkpoint: \(lastProcessedLine)")

      if rowsAffected == 0 {
        log.error("[HOOVER-UPDATE-FAILED] UPDATE affected 0 rows! Transcript ID: \(transcriptId)")
        if let existing = try? Transcript.fetchOne(db, key: transcriptId) {
          log.error("[HOOVER-UPDATE-FAILED] Transcript EXISTS in database with checkpoint: \(existing.lastProcessedLine)")
        } else {
          log.error("[HOOVER-UPDATE-FAILED] Transcript NOT FOUND in database (ID mismatch?)")
        }
      }
    }
  }

  /// Hoover a transcript with streaming parser
  /// Returns outcome information for the ingestion run
  public func hooverTranscript(
    _ transcript: Transcript,
    fileURL: URL,
    progress: IngestProgressSink,
    limit: IngestLimit = .none
  ) throws -> HooverOutcome {
    log.info("[HOOVER-START] Starting hoover for transcript: \(transcript.id) from checkpoint: \(transcript.lastProcessedLine)")
    let startTime = Date()

    // Verify file size before opening handle
    let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64 ?? 0
    log.debug("[HOOVER-FILE-SIZE] File size: \(fileSize) bytes for transcript: \(transcript.id)")

    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    // Verify FileHandle can see the file content
    let endOffset = handle.seekToEndOfFile()
    handle.seek(toFileOffset: 0) // Reset to beginning
    log.debug("[HOOVER-FILE-VERIFY] File handle opened, size: \(endOffset) bytes for transcript: \(transcript.id)")

    progress.didStartTranscript(name: fileURL.lastPathComponent, totalLines: transcript.lineCount)

    var buffer = Data()
    var lineNo = transcript.lastProcessedLine
    var batch: [EntryInsert] = []
    var metadataBatch = MetadataBatch()  // v7: accumulate metadata
    var errors: [(lineNumber: Int, rawLine: String, error: String)] = []
    let transcriptHasher = SHA256Utils.IncrementalHasher()
    var lastEntryId: String? = nil  // Track last entry ID for checkpoint
    var parsedEntryCount = 0
    var parseErrorCount = 0
    var firstParseErrorLine: Int?
    var firstParseErrorReason: String?
    var hasLoggedParseErrorOverflow = false
    var limitReached = false
    var hitEOF = false
    var totalEntriesSkipped = 0  // Track skipEntry count
    var totalEntriesInserted = 0  // Track actual DB inserts
    var projectCache = ProjectResolutionCache()  // P0 fix: cache project lookups per transcript
    var timingStats = BatchTimingStats()  // Performance timing breakdown

    // P6 optimization: Preload all existing entry IDs for this transcript
    // This eliminates per-batch parent validation queries (was ~25% of SQL parsing overhead)
    // Memory cost: ~40 bytes per entry (UUID string + Set overhead), acceptable for most transcripts
    // Uses cursor-based construction to avoid intermediate array allocation (per review feedback)
    var preloadedEntryIds: Set<String> = try db.read { db in
      var result = Set<String>()
      let cursor = try String.fetchCursor(db, sql: """
        SELECT id FROM transcript_entries WHERE transcript_id = ?
      """, arguments: [transcript.id])
      while let id = try cursor.next() {
        result.insert(id)
      }
      return result
    }
    log.debug("[HOOVER-P6] Preloaded \(preloadedEntryIds.count) existing entry IDs for parent validation")

    // Seed previousEntries from last processed entry for correct window state on resume
    var previousEntries: [String] = []
    if let lastId = transcript.lastProcessedEntryId {
      // Seed from the last processed entry (and its prev1)
      if let last = try? db.read({ db in try TranscriptEntry.fetchOne(db, key: lastId) }) {
        var seed: [String] = []
        if let p1 = last.prev1Id { seed.append(p1) } // oldest first
        seed.append(last.id)
        previousEntries = seed
      } else {
        // Graceful fallback: lastId is stale/deleted, fall back to 2-row seed
        let seed = try db.read { db in
          try Row.fetchAll(db, sql: """
            SELECT id FROM transcript_entries
            WHERE transcript_id = ?
            ORDER BY timestamp DESC, id DESC
            LIMIT 2
          """, arguments: [transcript.id])
          .compactMap { $0["id"] as String? }
          .reversed()
        }
        previousEntries = Array(seed.suffix(2))
      }
    } else {
      // Fresh transcript or old DB: seed with last two existing (if any)
      let seed = try db.read { db in
        try Row.fetchAll(db, sql: """
          SELECT id FROM transcript_entries
          WHERE transcript_id = ?
          ORDER BY timestamp DESC, id DESC
          LIMIT 2
        """, arguments: [transcript.id])
        .compactMap { $0["id"] as String? }
        .reversed()
      }
      previousEntries = Array(seed.suffix(2))
    }

    let nl: UInt8 = 0x0A // '\n'

    // Skip to resume point if needed
    if lineNo > 0 {
      var skippedLines = 0
      while skippedLines < lineNo {
        guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
        buffer.append(chunk)

        while let i = buffer.firstIndex(of: nl) {
          let lineData = buffer[..<i]
          buffer.removeSubrange(..<buffer.index(after: i))
          transcriptHasher.update(lineData: lineData)
          skippedLines += 1
          if skippedLines >= lineNo { break }
        }
      }
      // DO NOT clear buffer here - it contains the start of the next unprocessed line
      // buffer.removeAll()
    }

    // Process remaining lines
    var outerLoopCount = 0
    outerLoop: while true {
      outerLoopCount += 1
      if MonitorConfig.enableHooverLoopTracing {
        log.debug("[HOOVER-OUTER-LOOP] Iteration \(outerLoopCount): lineNo=\(lineNo), bufferSize=\(buffer.count) bytes")
      }

      // DRAIN BUFFER FIRST - process all complete lines already in buffer
      var innerLoopCount = 0
      while let i = buffer.firstIndex(of: nl) {
        innerLoopCount += 1

        let lineData = buffer[..<i]
        buffer.removeSubrange(..<buffer.index(after: i))
        lineNo += 1

        // Timing: hash update
        let hashStart = MonitorConfig.enableHooverTimingTracing ? Date() : nil
        transcriptHasher.update(lineData: lineData)
        if let start = hashStart {
          timingStats.hashTimeMs += Date().timeIntervalSince(start) * 1000
        }

        guard let lineString = String(data: lineData, encoding: .utf8) else {
          errors.append((lineNo, "<invalid UTF-8>", "Line is not valid UTF-8"))
          continue
        }

        var entryId: String? = nil
        do {
          // Timing: parse
          let parseStart = MonitorConfig.enableHooverTimingTracing ? Date() : nil
          var entry = try parser.parse(
            line: lineString,
            lineNumber: lineNo,
            transcriptId: transcript.id,
            projectId: transcript.projectId,
            provider: transcript.provider,
            sessionId: transcript.providerSessionId
          )
          if let start = parseStart {
            timingStats.parseTimeMs += Date().timeIntervalSince(start) * 1000
          }

          // Timing: project resolution
          let projectStart = MonitorConfig.enableHooverTimingTracing ? Date() : nil
          let correctProjectId = try resolveProjectId(
            fromCwd: entry.cwd,
            transcriptProjectId: transcript.projectId,
            transcriptId: transcript.id,
            cache: &projectCache
          )
          if let start = projectStart {
            timingStats.projectResolutionTimeMs += Date().timeIntervalSince(start) * 1000
          }

          // If project differs, use helper to create entry with corrected project ID
          if correctProjectId != entry.projectId {
            entry = entry.withProjectId(correctProjectId)
          }

          batch.append(entry)
          entryId = entry.id
          lastEntryId = entry.id  // Track for checkpoint
        } catch ParserError.skipEntry {
          // Silently skip - this is expected for meta messages, empty content, etc.
          // Don't add to batch, don't record as error
          totalEntriesSkipped += 1

          // NEW: Log if this was a large line (diagnostic for hang investigation)
          if lineData.count > 50_000 {
            log.info("[HOOVER-SKIP-LARGE] Line \(lineNo) skipped, size: \(lineData.count) bytes")
          }
        } catch {
          parseErrorCount += 1
          if firstParseErrorReason == nil {
            firstParseErrorLine = lineNo
            firstParseErrorReason = error.localizedDescription
            log.warning("[HOOVER-PARSE-ERROR] transcript=\(transcript.id) path=\(transcript.filePath) line=\(lineNo) reason=\(error.localizedDescription)")
          } else if !hasLoggedParseErrorOverflow && parseErrorCount == MonitorConfig.parseErrorLogLimit {
            log.warning("[HOOVER-PARSE-ERROR] transcript=\(transcript.id) path=\(transcript.filePath) exceeding \(MonitorConfig.parseErrorLogLimit) parse errors, suppressing additional logs")
            hasLoggedParseErrorOverflow = true
          }

          if errors.count < MonitorConfig.parseErrorRetentionPerTranscript {
            let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxChars))
            errors.append((lineNo, truncated, error.localizedDescription))
          }

          if !limitReached,
             parsedEntryCount == 0,
             parseErrorCount >= MonitorConfig.parseErrorAbortThreshold {
            log.error("[HOOVER-PARSE-ABORT] transcript=\(transcript.id) path=\(transcript.filePath) aborting after \(parseErrorCount) errors with no valid entries")
            break outerLoop
          }
        }

        // v7: Extract metadata regardless of whether entry was added to batch
        if let metadataResult = try? metadataParser.parseMetadata(
          line: lineString,
          lineNumber: lineNo,
          transcriptId: transcript.id,
          projectId: transcript.projectId,
          provider: transcript.provider,
          entryId: entryId
        ) {
          metadataBatch.add(metadataResult)
        }

        if entryId != nil {
          parsedEntryCount += 1
        }

        if let maxEntries = limit.maxEntries, parsedEntryCount >= maxEntries {
          limitReached = true
          log.info("[HOOVER-LIMIT] Reached ingest limit (\(maxEntries)) for transcript: \(transcript.id)")
          break
        }

        // Checkpoint every N lines
        if batch.count >= MonitorConfig.batchLines {
          #if DEBUG
          log.debug("[HOOVER-BATCH-COMMIT] Committing batch of \(batch.count) entries")
          #endif

          // Time the batch insertion (diagnostic for hang investigation)
          let batchStart = Date()
          #if DEBUG
          log.debug("[HOOVER-BATCH-INSERT-START] Starting batch insertion for \(batch.count) entries at line \(lineNo)")
          #endif

          let inserted = try commitBatch(
            transcriptId: transcript.id,
            entries: batch,
            metadata: metadataBatch,
            errors: errors,
            lastProcessedLine: lineNo,
            lineCount: lineNo,
            previousEntries: &previousEntries,
            preloadedEntryIds: &preloadedEntryIds
          )
          totalEntriesInserted += inserted

          let duration = Date().timeIntervalSince(batchStart)
          // Timing: commitBatch total (db.write + overhead)
          timingStats.commitBatchTimeMs += duration * 1000
          timingStats.batchCount += 1
          timingStats.entryCount += batch.count

          #if DEBUG
          log.debug("[HOOVER-BATCH-INSERT-DONE] Batch insertion completed in \(String(format: "%.0f", duration * 1000))ms")
          #endif
          if duration > 5.0 {
            log.warning("[HOOVER-BATCH-SLOW] Batch insertion took \(String(format: "%.1f", duration))s - may indicate DB lock contention")
          }

          batch.removeAll()
          metadataBatch.clear()
          errors.removeAll()
          progress.didAdvance(linesProcessed: lineNo, totalLines: nil)
        }
      }
      if MonitorConfig.enableHooverLoopTracing {
        log.debug("[HOOVER-INNER-DONE] Inner loop exited after \(innerLoopCount) iterations, bufferSize=\(buffer.count)")
      }

      #if DEBUG
      if MonitorConfig.enableHooverLoopTracing {
        // Log inner loop completion with batch state (diagnostic for hang investigation)
        log.debug("[HOOVER-INNER-COMPLETE] Processed \(innerLoopCount) lines in this iteration, batch size: \(batch.count), total lines: \(lineNo)")
      }
      #endif

      if limitReached {
        break outerLoop
      }

      // READ MORE DATA - only after draining existing buffer
      let readStart = Date()
      guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
        log.info("[HOOVER-READ-EOF] Reached EOF at line \(lineNo), outerLoops=\(outerLoopCount) for transcript: \(transcript.id)")
        hitEOF = true
        break
      }
      let readDuration = Date().timeIntervalSince(readStart)
      if readDuration > 1.0 {
        log.warning("[HOOVER-READ-SLOW] File read took \(String(format: "%.1f", readDuration))s - file may still be written")
      }

      if MonitorConfig.enableHooverLoopTracing {
        log.debug("[HOOVER-READ-CHUNK] Read \(chunk.count) bytes, buffer now \(buffer.count + chunk.count) bytes")
      }
      buffer.append(chunk)

      // Safety limit for runaway buffer growth. 35MB accommodates Claude's 30MB file upload
      // limit plus headroom. See #P3-BLOB-STORAGE for future extraction of large content.
      if buffer.count > 35_000_000 {  // 35MB limit
        log.error("[HOOVER-BUFFER-OVERFLOW] Buffer size: \(buffer.count) bytes at line \(lineNo) - aborting. Line may exceed maximum size.")
        throw ParserError.invalidFormat("Line \(lineNo) exceeds maximum size (buffer >35MB)")
      }
    }

    // Handle final partial line (no trailing newline)
    // CRITICAL: When limitReached is true, we must NOT parse buffered data.
    // The buffer contains the next line to process on resume. Processing it here
    // would increment lineNo and save an incorrect checkpoint, causing that line
    // to be permanently skipped on the next ingestion pass (data loss).
    if !buffer.isEmpty && !limitReached {
      if let lineString = String(data: buffer, encoding: .utf8) {
        lineNo += 1
        transcriptHasher.update(lineData: buffer)

        var entryId: String? = nil
        do {
          var entry = try parser.parse(
            line: lineString,
            lineNumber: lineNo,
            transcriptId: transcript.id,
            projectId: transcript.projectId,
            provider: transcript.provider,
            sessionId: transcript.providerSessionId
          )

          // Check if entry's CWD differs from transcript's project and reassign if needed
          let correctProjectId = try resolveProjectId(
            fromCwd: entry.cwd,
            transcriptProjectId: transcript.projectId,
            transcriptId: transcript.id,
            cache: &projectCache
          )

          // If project differs, use helper to create entry with corrected project ID
          if correctProjectId != entry.projectId {
            entry = entry.withProjectId(correctProjectId)
          }

          batch.append(entry)
          entryId = entry.id
          lastEntryId = entry.id  // Track for checkpoint
        } catch ParserError.skipEntry {
          // Silently skip - this is expected for meta messages, empty content, etc.
          // Don't add to batch, don't record as error
          totalEntriesSkipped += 1
        } catch {
          let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxChars))
          errors.append((lineNo, truncated, error.localizedDescription))
        }

        // v7: Extract metadata from final line
        if let metadataResult = try? metadataParser.parseMetadata(
          line: lineString,
          lineNumber: lineNo,
          transcriptId: transcript.id,
          projectId: transcript.projectId,
          provider: transcript.provider,
          entryId: entryId
        ) {
          metadataBatch.add(metadataResult)
        }
        if entryId != nil {
          parsedEntryCount += 1
        }
      } else {
        errors.append((lineNo + 1, "<invalid UTF-8>", "Final line is not valid UTF-8"))
      }
      buffer.removeAll()
    }

    // Final batch
    if !batch.isEmpty || !errors.isEmpty || !metadataBatch.isEmpty {
      let finalBatchStart = Date()
      let inserted = try commitBatch(
        transcriptId: transcript.id,
        entries: batch,
        metadata: metadataBatch,
        errors: errors,
        lastProcessedLine: lineNo,
        lineCount: lineNo,
        previousEntries: &previousEntries,
        preloadedEntryIds: &preloadedEntryIds
      )
      totalEntriesInserted += inserted
      // Timing: final commitBatch total (db.write + overhead)
      timingStats.commitBatchTimeMs += Date().timeIntervalSince(finalBatchStart) * 1000
      timingStats.batchCount += 1
      timingStats.entryCount += batch.count
    }

    // Log timing breakdown for this transcript
    timingStats.log(transcriptId: transcript.id, logger: log)

    // ALWAYS update checkpoint, regardless of whether there were new entries
    // This ensures checkpoint is persisted even for already-processed transcripts
    let finalLineCount = hitEOF ? lineNo : max(lineNo, transcript.lineCount)
    let firstParseErrorDescription: String? = {
      guard let reason = firstParseErrorReason else { return nil }
      if let line = firstParseErrorLine {
        return "Line \(line): \(reason)"
      }
      return reason
    }()

    let hadParseErrors = parseErrorCount > 0
    let shouldMarkCorrupt = hadParseErrors && parsedEntryCount == 0

    let ingestState = shouldMarkCorrupt ? "complete" : (hitEOF ? "complete" : "partial")
    let status = shouldMarkCorrupt ? "error" : "active"
    let lastErrorMessage = shouldMarkCorrupt ? firstParseErrorDescription : nil

    if shouldMarkCorrupt {
      log.error("[HOOVER-CORRUPT] transcript=\(transcript.id) path=\(transcript.filePath) parse_errors=\(parseErrorCount) reason=\(firstParseErrorDescription ?? "unknown")")
    }

    try updateCheckpoint(
      transcriptId: transcript.id,
      lastProcessedLine: lineNo,
      lastProcessedEntryId: lastEntryId,
      lineCount: finalLineCount,
      ingestState: ingestState,
      status: status,
      lastError: lastErrorMessage
    )

    log.info("[DB-UPDATE] transcript=\(transcript.id) entries=\(parsedEntryCount) state=\(ingestState)")

    // Verify checkpoint was updated correctly
    if let updatedTranscript = try? db.read({ db in try Transcript.fetchOne(db, key: transcript.id) }) {
      log.debug("[HOOVER-CHECKPOINT-VERIFY] Checkpoint updated: \(transcript.lastProcessedLine) → \(updatedTranscript.lastProcessedLine)")
      if updatedTranscript.lastProcessedLine != lineNo {
        log.error("[HOOVER-CHECKPOINT-MISMATCH] ⚠️ Expected checkpoint \(lineNo), but database has \(updatedTranscript.lastProcessedLine)")
      }
    }

    let duration = Date().timeIntervalSince(startTime)
    progress.didCompleteTranscript(durationMs: Int(duration * 1000))

    let transcriptSHA256: String?
    if hitEOF {
      transcriptSHA256 = transcriptHasher.finalize()
    } else {
      _ = transcriptHasher.finalize()
      transcriptSHA256 = nil
    }

    let linesPerSec = duration > 0 ? Int(Double(lineNo) / duration) : 0
    let newLines = lineNo - transcript.lastProcessedLine
    log.info("[HOOVER-DONE] Hoovered transcript \(transcript.id): \(newLines) new lines (total: \(lineNo)) in \(Int(duration * 1000))ms (\(linesPerSec)/s). ingest_state=\(ingestState)")

    return HooverOutcome(
      processedLines: lineNo,
      newEntries: parsedEntryCount,
      reachedEOF: hitEOF,
      lastEntryId: lastEntryId,
      contentSha256: transcriptSHA256,
      entriesSkipped: totalEntriesSkipped,
      entriesInserted: totalEntriesInserted
    )
  }

  /// Commit a batch of entries and errors to the database
  /// All operations are atomic within a single transaction
  /// Tracks previous entries for window SHA256 computation
  /// Returns the number of entries actually inserted to the database
  ///
  /// - Parameter preloadedEntryIds: P6 optimization - preloaded set of existing entry IDs
  ///   for this transcript, used for parent validation. Updated in-place as new entries are inserted.
  private func commitBatch(
    transcriptId: String,
    entries: [EntryInsert],
    metadata: MetadataBatch,
    errors: [(lineNumber: Int, rawLine: String, error: String)],
    lastProcessedLine: Int,
    lineCount: Int,
    previousEntries: inout [String],
    preloadedEntryIds: inout Set<String>
  ) throws -> Int {
    // Fast path: Use BulkIngestManager for high-volume entry/tool inserts
    // This bypasses GRDB observation overhead (~25-40% improvement expected)
    if let bulkManager = bulkIngestManager, !entries.isEmpty {
      return try commitBatchFast(
        bulkManager: bulkManager,
        transcriptId: transcriptId,
        entries: entries,
        metadata: metadata,
        errors: errors,
        lastProcessedLine: lastProcessedLine,
        lineCount: lineCount,
        previousEntries: &previousEntries,
        preloadedEntryIds: &preloadedEntryIds
      )
    }

    // Standard path: Use GRDB pool with observation
    var insertedCount = 0
    let now = Int(Date().timeIntervalSince1970)
    try db.write { db in
      // P6 optimization: Use preloaded entry IDs for parent validation instead of per-batch queries
      // The preloadedEntryIds set is maintained across batches and updated as entries are inserted
      // This eliminates the chunked SELECT queries that contributed to ~25% SQL parsing overhead

      // PERF: Collect tool result data for batch UPDATE after entry inserts
      // Instead of per-entry UPDATEs, we batch them to reduce query overhead
      var deferredToolResults: [(toolUseId: String, entryId: String, agentId: String?, timestamp: Int, status: String?)] = []
      var deferredSidechainLinks: [(agentId: String, transcriptId: String)] = []
      // PERF: Collect unique agentIds for deduped sidechain transcript linking
      var sidechainAgentIds: Set<String> = []

      // Insert entries with window tracking
      for entry in entries {
        // Compute window from previous 2 entries
        let prev1 = previousEntries.last
        let prev2 = previousEntries.count >= 2 ? previousEntries[previousEntries.count - 2] : nil
        let windowSha = SHA256Utils.computeWindowSHA256(prev2: prev2, prev1: prev1)

        var model = entry.toModel()
        model.prev1Id = prev1
        model.prev2Id = prev2
        model.windowSha256 = windowSha

        // Check if parent exists using preloaded entry IDs (P6 optimization)
        // This handles out-of-order entries where a child references a parent that hasn't been inserted yet
        // The preloadedEntryIds set includes both pre-existing entries AND entries inserted earlier in this batch
        if let parentId = model.parentId {
          if !preloadedEntryIds.contains(parentId) {
            if MonitorConfig.enableHooverStorageTracing {
              log.debug("Parent \(parentId) doesn't exist yet, setting parent_id to NULL for entry \(model.id)")
            }
            model.parentId = nil  // Will be backfilled later if needed
          }
        }

        do {
          try model.insert(db, onConflict: .ignore)

          // Only update window tracking if insert actually happened (not ignored due to conflict)
          let inserted = db.changesCount > 0
          if inserted {
            insertedCount += 1
            // P6: Add inserted entry to preloadedEntryIds so later entries (same batch or future batches)
            // can find it as a valid parent (fixes same-batch parent links)
            preloadedEntryIds.insert(model.id)
            previousEntries.append(entry.id)
            if previousEntries.count > 2 {
              previousEntries.removeFirst()
            }
          } else {
            // Entry silently ignored (likely duplicate ID from re-ingestion) - expected during database rebuilds
            log.debug("Entry silently ignored (duplicate constraint?)")
            log.debug("   Entry ID: \(model.id)")
            log.debug("   Kind: \(model.kind)")
            log.debug("   Content preview: \(String(model.content.prefix(80)))")
          }
        } catch {
          // Log detailed FK error info
          log.error("❌ Entry insert failed: \(error.localizedDescription)")
          log.error("   Entry ID: \(model.id)")
          log.error("   Transcript ID: \(model.transcriptId)")
          log.error("   Project ID: \(model.projectId)")
          log.error("   Parent ID: \(model.parentId ?? "nil")")
          log.error("   Prev1 ID: \(model.prev1Id ?? "nil")")
          log.error("   Prev2 ID: \(model.prev2Id ?? "nil")")
          throw error
        }

        // Insert tool invocations from tool_use blocks
        for invocation in entry.toolInvocations {
          let startedAt = invocation.startedAt.map { Int($0.timeIntervalSince1970) }
          let tool = ToolInvocation(
            id: "\(entry.id)-\(invocation.toolUseId ?? UUID().uuidString)",
            entryId: entry.id,
            transcriptId: transcriptId,
            parentInvocationId: nil,
            toolName: invocation.toolName,
            toolKey: invocation.toolKey,
            toolUseId: invocation.toolUseId,
            toolResultEntryId: nil,
            sidechainTranscriptId: nil,
            sidechainAgentId: nil,
            startedAt: startedAt,
            completedAt: nil,
            status: "unknown",
            isContextify: invocation.isContextify ? 1 : 0,
            metadataJson: invocation.metadataJson,
            createdAt: now,
            updatedAt: now
          )
          try tool.insert(db, onConflict: .ignore)
        }

        // PERF: Collect tool result data for deferred batch UPDATE
        // Skip nil toolUseId - UPDATE WHERE tool_use_id = NULL won't match anything
        for result in entry.toolResultData {
          guard let toolUseId = result.toolUseId else { continue }
          deferredToolResults.append((
            toolUseId: toolUseId,
            entryId: result.entryId,
            agentId: result.agentId,
            timestamp: Int(result.timestamp.timeIntervalSince1970),
            status: result.status
          ))
          // Collect unique agentIds for deduped sidechain transcript linking
          if let agentId = result.agentId {
            sidechainAgentIds.insert(agentId)
          }
        }

        // PERF: Collect sidechain link data for deferred batch UPDATE
        if entry.isSidechain, let agentId = entry.agentId {
          deferredSidechainLinks.append((agentId: agentId, transcriptId: transcriptId))
        }
      }

      // PERF: Batch UPDATE tool invocations with tool_result data
      // Uses chunked individual updates (avoiding CASE complexity) but after all inserts complete
      // This improves SQLite page cache locality vs interleaving updates with inserts
      for result in deferredToolResults {
        try db.execute(sql: """
          UPDATE tool_invocations
          SET tool_result_entry_id = ?,
              sidechain_agent_id = ?,
              completed_at = ?,
              status = COALESCE(?, status),
              updated_at = ?
          WHERE tool_use_id = ? AND transcript_id = ?
        """, arguments: [
          result.entryId,
          result.agentId,
          result.timestamp,
          result.status,
          now,
          result.toolUseId,
          transcriptId
        ])
      }

      // PERF: Deduped sidechain transcript linking by unique agentIds
      // Instead of one UPDATE per tool_result, one UPDATE per unique agentId
      for agentId in sidechainAgentIds {
        let sidechainTranscriptId = "agent-\(agentId)"
        try db.execute(sql: """
          UPDATE tool_invocations
          SET sidechain_transcript_id = ?,
              updated_at = ?
          WHERE sidechain_agent_id = ?
            AND sidechain_transcript_id IS NULL
            AND EXISTS (SELECT 1 FROM transcripts WHERE id = ?)
        """, arguments: [sidechainTranscriptId, now, agentId, sidechainTranscriptId])
      }

      // PERF: Batch UPDATE sidechain transcript links for sidechain entries
      for link in deferredSidechainLinks {
        try db.execute(sql: """
          UPDATE tool_invocations
          SET sidechain_transcript_id = ?,
              updated_at = ?
          WHERE sidechain_agent_id = ?
            AND (sidechain_transcript_id IS NULL OR sidechain_transcript_id != ?)
        """, arguments: [link.transcriptId, now, link.agentId, link.transcriptId])
      }

      // HEURISTIC: Delete synthetic queue-XX entries when real message appears
      // Workaround for Claude Code 2.0.50+ not writing dequeue/popAll/remove operations
      // When a real user message appears, it means the queued message was dequeued
      // Match by content_sha256 and delete the synthetic queue-XX placeholder
      for entry in entries where entry.kind == "user" && !entry.id.hasPrefix("queue-") {
        // Check if there's a synthetic queue entry with matching content
        try db.execute(sql: """
          DELETE FROM transcript_entries
          WHERE transcript_id = ?
            AND content_sha256 = ?
            AND id LIKE 'queue-%'
            AND is_queued = 1
        """, arguments: [transcriptId, entry.contentSha256])

        let deletedCount = db.changesCount
        if deletedCount > 0 {
          log.debug("[QUEUE-HEURISTIC] Deleted \(deletedCount) synthetic queue entry (real message appeared) content_sha256=\(entry.contentSha256.prefix(8))")
        }
      }

      // v7: Insert metadata
      for snapshot in metadata.fileSnapshots {
        try snapshot.insert(db, onConflict: .ignore)
      }
      for file in metadata.trackedFiles {
        try file.insert(db, onConflict: .ignore)
      }
      for summary in metadata.transcriptSummaries {
        try summary.insert(db, onConflict: .ignore)
      }
      for event in metadata.systemEvents {
        try event.insert(db, onConflict: .ignore)
      }

      // v40: Update session-level metadata (slug, entrypoint) from entry fields
      // Collapsed to per-batch: take the last non-nil value and update only if changed
      let latestSlug = entries.lazy.compactMap(\.slug).last
      let latestEntrypoint = entries.lazy.compactMap(\.entrypoint).last

      if let latestSlug {
        try db.execute(
          sql: "UPDATE transcripts SET slug = ?, updated_at = ? WHERE id = ? AND COALESCE(slug, '') != ?",
          arguments: [latestSlug, now, transcriptId, latestSlug]
        )
      }
      if let latestEntrypoint {
        try db.execute(
          sql: "UPDATE transcripts SET entrypoint = ?, updated_at = ? WHERE id = ? AND COALESCE(entrypoint, '') != ?",
          arguments: [latestEntrypoint, now, transcriptId, latestEntrypoint]
        )
      }
      // custom_title from custom-title metadata records
      // sawCustomTitle distinguishes "no record" from "empty clear"
      if metadata.sawCustomTitle {
        try db.execute(
          sql: "UPDATE transcripts SET custom_title = NULLIF(?, ''), updated_at = ? WHERE id = ? AND COALESCE(custom_title, '') != COALESCE(?, '')",
          arguments: [metadata.customTitle ?? "", now, transcriptId, metadata.customTitle ?? ""]
        )
      }

      // FK-safe usage insert: atomic CTE-based check+insert with request_id normalization
      for usage in metadata.assistantUsages {
        // Normalize request_id: empty string -> entry_id fallback
        let normalizedRequestId: String = {
          let trimmed = usage.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
          return trimmed.isEmpty ? usage.entryId : trimmed
        }()

        // Atomic check+insert using CTE and RETURNING for single round-trip
        let stmt = try db.makeStatement(sql: """
          WITH entry_check AS (SELECT 1 FROM transcript_entries WHERE id = ? LIMIT 1)
          INSERT OR IGNORE INTO assistant_usage (
            entry_id, request_id, model, input_tokens, output_tokens,
            cache_creation_tokens, cache_read_tokens, service_tier,
            ephemeral_5m_tokens, ephemeral_1h_tokens
          )
          SELECT ?,?,?,?,?,?,?,?,?,? FROM entry_check
          RETURNING entry_id;
          """)
        try stmt.execute(arguments: [
          usage.entryId,  // for entry_check CTE
          usage.entryId, normalizedRequestId, usage.model,
          usage.inputTokens, usage.outputTokens,
          usage.cacheCreationTokens, usage.cacheReadTokens,
          usage.serviceTier, usage.ephemeral5mTokens, usage.ephemeral1hTokens
        ])

        // If nothing was inserted (entry doesn't exist yet), stage for reconciliation
        let inserted = db.changesCount > 0
        if !inserted {
          try db.execute(sql: """
            INSERT OR REPLACE INTO assistant_usage_pending (
              entry_id, request_id, model, input_tokens, output_tokens,
              cache_creation_tokens, cache_read_tokens, service_tier,
              ephemeral_5m_tokens, ephemeral_1h_tokens
            ) VALUES (?,?,?,?,?,?,?,?,?,?)
            """,
            arguments: [
              usage.entryId, normalizedRequestId, usage.model,
              usage.inputTokens, usage.outputTokens,
              usage.cacheCreationTokens, usage.cacheReadTokens,
              usage.serviceTier, usage.ephemeral5mTokens, usage.ephemeral1hTokens
            ]
          )
          if MonitorConfig.enableHooverStorageTracing {
            log.debug("Staged usage for entry \(usage.entryId) (entry not yet present)")
          }
        }
      }

      // Apply queue operations (queue-operation remove/popAll/dequeue)
      if !metadata.queueOperations.isEmpty {
        for op in metadata.queueOperations {
          guard !op.sessionId.isEmpty else {
            log.warning("[QUEUE-OP] Skipping queue operation with empty sessionId for transcript \(op.transcriptId)")
            continue
          }

          switch op.kind {
          case .dequeue, .popAll:
            // Clear entire queue for the session
            try db.execute(sql: """
              UPDATE transcript_entries
              SET is_queued = 0
              WHERE transcript_id = ? AND session_id = ? AND is_queued = 1
            """, arguments: [op.transcriptId, op.sessionId])

            let changes = db.changesCount
            let elapsed = Date().timeIntervalSince(op.timestamp)
            log.info("[QUEUE-OP-CLEAR] \(op.kind.rawValue) cleared \(changes) entries after \(String(format: "%.1f", elapsed))s transcript=\(op.transcriptId.prefix(8))")

          case .remove:
            // FIFO: clear oldest queued entry for this session
            // Claude Code's remove doesn't include content, so we match by order
            try db.execute(sql: """
              UPDATE transcript_entries
              SET is_queued = 0
              WHERE id = (
                SELECT id FROM transcript_entries
                WHERE transcript_id = ? AND session_id = ? AND is_queued = 1
                ORDER BY timestamp ASC
                LIMIT 1
              )
            """, arguments: [op.transcriptId, op.sessionId])

            let changes = db.changesCount
            let elapsed = Date().timeIntervalSince(op.timestamp)
            log.info("[QUEUE-OP-CLEAR] remove cleared \(changes) entries (FIFO) after \(String(format: "%.1f", elapsed))s transcript=\(op.transcriptId.prefix(8))")
          }
        }

        // Notify UI to refresh entries after queue operations
        // ConversationMonitor will re-read affected entries from DB to update badges
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if !metadata.queueOperations.isEmpty {
          let projectId = try String.fetchOne(db, sql: "SELECT project_id FROM transcripts WHERE id = ?", arguments: [transcriptId])
          if let projectId {
            DispatchQueue.main.async {
              NotificationCenter.default.post(
                name: Notification.Name("QueueOperationsProcessed"),
                object: nil,
                userInfo: ["projectId": projectId, "transcriptId": transcriptId]
              )
            }
          }
        }
        #endif
      }

      // Insert errors (bulk insert)
      if !errors.isEmpty {
        let now = Int(Date().timeIntervalSince1970)
        let stmt = try db.makeStatement(sql: """
          INSERT INTO parse_errors (id, transcript_id, line_number, raw_line, error_message, created_at)
          VALUES (?, ?, ?, ?, ?, ?)
        """)
        for error in errors {
          let truncated = String(error.rawLine.prefix(MonitorConfig.parseErrorMaxChars))
          try stmt.execute(arguments: [
            UUID().uuidString,
            transcriptId,
            error.lineNumber,
            truncated,
            error.error,
            now
          ])
        }
      }

      // Prune old errors (single SQL)
      try db.execute(sql: """
        DELETE FROM parse_errors
        WHERE id IN (
          SELECT id FROM parse_errors
          WHERE transcript_id = ?
          ORDER BY created_at DESC
          LIMIT -1 OFFSET ?
        )
      """, arguments: [transcriptId, MonitorConfig.parseErrorRetentionPerTranscript])

      // Reconcile assistant_usage_pending → assistant_usage using JOIN (O(N+M) vs O(N×M))
      // Normalize empty request_id during move to reduce uniqueness churn
      try db.execute(sql: """
        INSERT OR IGNORE INTO assistant_usage (
          entry_id, request_id, model, input_tokens, output_tokens,
          cache_creation_tokens, cache_read_tokens, service_tier,
          ephemeral_5m_tokens, ephemeral_1h_tokens
        )
        SELECT
          p.entry_id,
          COALESCE(NULLIF(p.request_id, ''), p.entry_id) AS request_id,
          p.model, p.input_tokens, p.output_tokens,
          p.cache_creation_tokens, p.cache_read_tokens, p.service_tier,
          p.ephemeral_5m_tokens, p.ephemeral_1h_tokens
        FROM assistant_usage_pending p
        INNER JOIN transcript_entries e ON e.id = p.entry_id
      """)

      // Clean up reconciled records via indexed lookup (uses entry_id+request_id)
      // Note: SQLite doesn't support table aliases in DELETE, must use full table name
      try db.execute(sql: """
        DELETE FROM assistant_usage_pending
        WHERE EXISTS (
          SELECT 1 FROM assistant_usage au
          WHERE au.entry_id = assistant_usage_pending.entry_id
            AND au.request_id = COALESCE(NULLIF(assistant_usage_pending.request_id, ''), assistant_usage_pending.entry_id)
        )
      """)

      // NOTE: Checkpoint UPDATE removed - now handled unconditionally in hooverTranscript()
      // This ensures checkpoint is persisted even when batch is empty (already-processed transcripts)
    }
    return insertedCount
  }

  // MARK: - Fast Path (BulkIngestManager)

  /// Fast path using BulkIngestManager for high-volume entry/tool inserts.
  /// Bypasses GRDB observation overhead (StatementAuthorizer, DatabaseRegion).
  /// Uses separate DatabaseQueue with prepared statements for maximum throughput.
  ///
  /// Strategy:
  /// 1. Build TranscriptEntry and ToolInvocation models with window tracking
  /// 2. Use BulkIngestManager for INSERTs (separate connection, no observation)
  /// 3. Use standard db.write for UPDATEs, DELETEs, metadata (must be after INSERTs)
  private func commitBatchFast(
    bulkManager: BulkIngestManager,
    transcriptId: String,
    entries: [EntryInsert],
    metadata: MetadataBatch,
    errors: [(lineNumber: Int, rawLine: String, error: String)],
    lastProcessedLine: Int,
    lineCount: Int,
    previousEntries: inout [String],
    preloadedEntryIds: inout Set<String>
  ) throws -> Int {
    let now = Int(Date().timeIntervalSince1970)

    // Phase 1: Build models with window tracking
    var entryModels: [TranscriptEntry] = []
    var toolModels: [ToolInvocation] = []

    // Collect deferred UPDATE data (processed after INSERTs)
    var deferredToolResults: [(toolUseId: String, entryId: String, agentId: String?, timestamp: Int, status: String?)] = []
    var deferredSidechainLinks: [(agentId: String, transcriptId: String)] = []
    var sidechainAgentIds: Set<String> = []

    for entry in entries {
      // Compute window from previous 2 entries (same logic as standard path)
      let prev1 = previousEntries.last
      let prev2 = previousEntries.count >= 2 ? previousEntries[previousEntries.count - 2] : nil
      let windowSha = SHA256Utils.computeWindowSHA256(prev2: prev2, prev1: prev1)

      var model = entry.toModel()
      model.prev1Id = prev1
      model.prev2Id = prev2
      model.windowSha256 = windowSha

      // P6: Parent validation using preloaded entry IDs
      if let parentId = model.parentId {
        if !preloadedEntryIds.contains(parentId) {
          if MonitorConfig.enableHooverStorageTracing {
            log.debug("Parent \(parentId) doesn't exist yet, setting parent_id to NULL for entry \(model.id)")
          }
          model.parentId = nil
        }
      }

      entryModels.append(model)

      // Update tracking for next entry's window computation
      // Note: We optimistically add to previousEntries even for potential duplicates.
      // This is acceptable because: (a) duplicates are rare in normal operation,
      // (b) window tracking only affects timeline cache keys, not data integrity.
      previousEntries.append(entry.id)
      if previousEntries.count > 2 {
        previousEntries.removeFirst()
      }
      preloadedEntryIds.insert(model.id)

      // Build tool invocations
      for invocation in entry.toolInvocations {
        let startedAt = invocation.startedAt.map { Int($0.timeIntervalSince1970) }
        let tool = ToolInvocation(
          id: "\(entry.id)-\(invocation.toolUseId ?? UUID().uuidString)",
          entryId: entry.id,
          transcriptId: transcriptId,
          parentInvocationId: nil,
          toolName: invocation.toolName,
          toolKey: invocation.toolKey,
          toolUseId: invocation.toolUseId,
          toolResultEntryId: nil,
          sidechainTranscriptId: nil,
          sidechainAgentId: nil,
          startedAt: startedAt,
          completedAt: nil,
          status: "unknown",
          isContextify: invocation.isContextify ? 1 : 0,
          metadataJson: invocation.metadataJson,
          createdAt: now,
          updatedAt: now
        )
        toolModels.append(tool)
      }

      // Collect deferred UPDATE data
      for result in entry.toolResultData {
        guard let toolUseId = result.toolUseId else { continue }
        deferredToolResults.append((
          toolUseId: toolUseId,
          entryId: result.entryId,
          agentId: result.agentId,
          timestamp: Int(result.timestamp.timeIntervalSince1970),
          status: result.status
        ))
        if let agentId = result.agentId {
          sidechainAgentIds.insert(agentId)
        }
      }

      if entry.isSidechain, let agentId = entry.agentId {
        deferredSidechainLinks.append((agentId: agentId, transcriptId: transcriptId))
      }
    }

    // Phase 2: Bulk INSERT entries and tools (fast path)
    let insertedCount = try bulkManager.commitBatch(
      entries: entryModels,
      toolInvocations: toolModels
    )

    // Phase 3: Standard db.write for UPDATEs, DELETEs, metadata
    // These must run AFTER INSERTs for FK integrity
    try db.write { db in
      // Batch UPDATE tool invocations with tool_result data
      for result in deferredToolResults {
        try db.execute(sql: """
          UPDATE tool_invocations
          SET tool_result_entry_id = ?,
              sidechain_agent_id = ?,
              completed_at = ?,
              status = COALESCE(?, status),
              updated_at = ?
          WHERE tool_use_id = ? AND transcript_id = ?
        """, arguments: [
          result.entryId,
          result.agentId,
          result.timestamp,
          result.status,
          now,
          result.toolUseId,
          transcriptId
        ])
      }

      // Deduped sidechain transcript linking
      for agentId in sidechainAgentIds {
        let sidechainTranscriptId = "agent-\(agentId)"
        try db.execute(sql: """
          UPDATE tool_invocations
          SET sidechain_transcript_id = ?,
              updated_at = ?
          WHERE sidechain_agent_id = ?
            AND sidechain_transcript_id IS NULL
            AND EXISTS (SELECT 1 FROM transcripts WHERE id = ?)
        """, arguments: [sidechainTranscriptId, now, agentId, sidechainTranscriptId])
      }

      // Sidechain transcript links for sidechain entries
      for link in deferredSidechainLinks {
        try db.execute(sql: """
          UPDATE tool_invocations
          SET sidechain_transcript_id = ?,
              updated_at = ?
          WHERE sidechain_agent_id = ?
            AND (sidechain_transcript_id IS NULL OR sidechain_transcript_id != ?)
        """, arguments: [link.transcriptId, now, link.agentId, link.transcriptId])
      }

      // Queue cleanup: Delete synthetic queue entries when real message appears
      for entry in entries where entry.kind == "user" && !entry.id.hasPrefix("queue-") {
        try db.execute(sql: """
          DELETE FROM transcript_entries
          WHERE transcript_id = ?
            AND content_sha256 = ?
            AND id LIKE 'queue-%'
            AND is_queued = 1
        """, arguments: [transcriptId, entry.contentSha256])

        let deletedCount = db.changesCount
        if deletedCount > 0 {
          log.debug("[QUEUE-HEURISTIC] Deleted \(deletedCount) synthetic queue entry (real message appeared) content_sha256=\(entry.contentSha256.prefix(8))")
        }
      }

      // v7: Insert metadata (less frequent than entries, standard path is fine)
      for snapshot in metadata.fileSnapshots {
        try snapshot.insert(db, onConflict: .ignore)
      }
      for file in metadata.trackedFiles {
        try file.insert(db, onConflict: .ignore)
      }
      for summary in metadata.transcriptSummaries {
        try summary.insert(db, onConflict: .ignore)
      }
      for event in metadata.systemEvents {
        try event.insert(db, onConflict: .ignore)
      }

      // v40: Update session-level metadata (slug, entrypoint) from entry fields
      // Collapsed to per-batch: take the last non-nil value and update only if changed
      let latestSlugFast = entries.lazy.compactMap(\.slug).last
      let latestEntrypointFast = entries.lazy.compactMap(\.entrypoint).last

      if let latestSlugFast {
        try db.execute(
          sql: "UPDATE transcripts SET slug = ?, updated_at = ? WHERE id = ? AND COALESCE(slug, '') != ?",
          arguments: [latestSlugFast, now, transcriptId, latestSlugFast]
        )
      }
      if let latestEntrypointFast {
        try db.execute(
          sql: "UPDATE transcripts SET entrypoint = ?, updated_at = ? WHERE id = ? AND COALESCE(entrypoint, '') != ?",
          arguments: [latestEntrypointFast, now, transcriptId, latestEntrypointFast]
        )
      }
      if metadata.sawCustomTitle {
        try db.execute(
          sql: "UPDATE transcripts SET custom_title = NULLIF(?, ''), updated_at = ? WHERE id = ? AND COALESCE(custom_title, '') != COALESCE(?, '')",
          arguments: [metadata.customTitle ?? "", now, transcriptId, metadata.customTitle ?? ""]
        )
      }

      // FK-safe usage insert
      for usage in metadata.assistantUsages {
        let normalizedRequestId: String = {
          let trimmed = usage.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
          return trimmed.isEmpty ? usage.entryId : trimmed
        }()

        let stmt = try db.makeStatement(sql: """
          WITH entry_check AS (SELECT 1 FROM transcript_entries WHERE id = ? LIMIT 1)
          INSERT OR IGNORE INTO assistant_usage (
            entry_id, request_id, model, input_tokens, output_tokens,
            cache_creation_tokens, cache_read_tokens, service_tier,
            ephemeral_5m_tokens, ephemeral_1h_tokens
          )
          SELECT ?,?,?,?,?,?,?,?,?,? FROM entry_check
          RETURNING entry_id;
          """)
        try stmt.execute(arguments: [
          usage.entryId,
          usage.entryId, normalizedRequestId, usage.model,
          usage.inputTokens, usage.outputTokens,
          usage.cacheCreationTokens, usage.cacheReadTokens,
          usage.serviceTier, usage.ephemeral5mTokens, usage.ephemeral1hTokens
        ])

        let inserted = db.changesCount > 0
        if !inserted {
          try db.execute(sql: """
            INSERT OR REPLACE INTO assistant_usage_pending (
              entry_id, request_id, model, input_tokens, output_tokens,
              cache_creation_tokens, cache_read_tokens, service_tier,
              ephemeral_5m_tokens, ephemeral_1h_tokens
            ) VALUES (?,?,?,?,?,?,?,?,?,?)
            """,
            arguments: [
              usage.entryId, normalizedRequestId, usage.model,
              usage.inputTokens, usage.outputTokens,
              usage.cacheCreationTokens, usage.cacheReadTokens,
              usage.serviceTier, usage.ephemeral5mTokens, usage.ephemeral1hTokens
            ]
          )
          if MonitorConfig.enableHooverStorageTracing {
            log.debug("Staged usage for entry \(usage.entryId) (entry not yet present)")
          }
        }
      }

      // Queue operations
      if !metadata.queueOperations.isEmpty {
        for op in metadata.queueOperations {
          guard !op.sessionId.isEmpty else {
            log.warning("[QUEUE-OP] Skipping queue operation with empty sessionId for transcript \(op.transcriptId)")
            continue
          }

          switch op.kind {
          case .dequeue, .popAll:
            try db.execute(sql: """
              UPDATE transcript_entries
              SET is_queued = 0
              WHERE transcript_id = ? AND session_id = ? AND is_queued = 1
            """, arguments: [op.transcriptId, op.sessionId])

            let changes = db.changesCount
            let elapsed = Date().timeIntervalSince(op.timestamp)
            log.info("[QUEUE-OP-CLEAR] \(op.kind.rawValue) cleared \(changes) entries after \(String(format: "%.1f", elapsed))s transcript=\(op.transcriptId.prefix(8))")

          case .remove:
            try db.execute(sql: """
              UPDATE transcript_entries
              SET is_queued = 0
              WHERE id = (
                SELECT id FROM transcript_entries
                WHERE transcript_id = ? AND session_id = ? AND is_queued = 1
                ORDER BY timestamp ASC
                LIMIT 1
              )
            """, arguments: [op.transcriptId, op.sessionId])

            let changes = db.changesCount
            let elapsed = Date().timeIntervalSince(op.timestamp)
            log.info("[QUEUE-OP-CLEAR] remove cleared \(changes) entries (FIFO) after \(String(format: "%.1f", elapsed))s transcript=\(op.transcriptId.prefix(8))")
          }
        }

        // Notify UI to refresh entries after queue operations
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if !metadata.queueOperations.isEmpty {
          let projectId = try String.fetchOne(db, sql: "SELECT project_id FROM transcripts WHERE id = ?", arguments: [transcriptId])
          if let projectId {
            DispatchQueue.main.async {
              NotificationCenter.default.post(
                name: Notification.Name("QueueOperationsProcessed"),
                object: nil,
                userInfo: ["projectId": projectId, "transcriptId": transcriptId]
              )
            }
          }
        }
        #endif
      }

      // Insert errors
      if !errors.isEmpty {
        let stmt = try db.makeStatement(sql: """
          INSERT INTO parse_errors (id, transcript_id, line_number, raw_line, error_message, created_at)
          VALUES (?, ?, ?, ?, ?, ?)
        """)
        for error in errors {
          let truncated = String(error.rawLine.prefix(MonitorConfig.parseErrorMaxChars))
          try stmt.execute(arguments: [
            UUID().uuidString,
            transcriptId,
            error.lineNumber,
            truncated,
            error.error,
            now
          ])
        }
      }

      // Prune old errors
      try db.execute(sql: """
        DELETE FROM parse_errors
        WHERE id IN (
          SELECT id FROM parse_errors
          WHERE transcript_id = ?
          ORDER BY created_at DESC
          LIMIT -1 OFFSET ?
        )
      """, arguments: [transcriptId, MonitorConfig.parseErrorRetentionPerTranscript])

      // Reconcile assistant_usage_pending
      try db.execute(sql: """
        INSERT OR IGNORE INTO assistant_usage (
          entry_id, request_id, model, input_tokens, output_tokens,
          cache_creation_tokens, cache_read_tokens, service_tier,
          ephemeral_5m_tokens, ephemeral_1h_tokens
        )
        SELECT
          p.entry_id,
          COALESCE(NULLIF(p.request_id, ''), p.entry_id) AS request_id,
          p.model, p.input_tokens, p.output_tokens,
          p.cache_creation_tokens, p.cache_read_tokens, p.service_tier,
          p.ephemeral_5m_tokens, p.ephemeral_1h_tokens
        FROM assistant_usage_pending p
        INNER JOIN transcript_entries e ON e.id = p.entry_id
      """)

      try db.execute(sql: """
        DELETE FROM assistant_usage_pending
        WHERE EXISTS (
          SELECT 1 FROM assistant_usage au
          WHERE au.entry_id = assistant_usage_pending.entry_id
            AND au.request_id = COALESCE(NULLIF(assistant_usage_pending.request_id, ''), assistant_usage_pending.entry_id)
        )
      """)
    }

    return insertedCount
  }
}

// MARK: - Parser Protocol

/// Protocol for parsing transcript lines
public protocol TranscriptLineParser {
  func parse(
    line: String,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    sessionId: String?
  ) throws -> EntryInsert
}

public enum ParserError: Error {
  case invalidJSON
  case missingRequiredField(String)
  case unsupportedProvider(String)
  case invalidFormat(String)
  case skipEntry  // Indicates entry should be skipped (meta messages, empty content, etc.)
  case corruptedRecord(CorruptionType, details: String)
}

extension ParserError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidJSON:
      return "Invalid JSON format"
    case .missingRequiredField(let field):
      return "Missing required field: \(field)"
    case .unsupportedProvider(let provider):
      return "Unsupported provider: \(provider)"
    case .invalidFormat(let reason):
      return "Invalid format: \(reason)"
    case .skipEntry:
      return "Entry skipped (metadata/empty content)"
    case .corruptedRecord(let type, let details):
      return "Corrupted record (\(type.rawValue)): \(details)"
    }
  }
}

/// Types of transcript corruption we can detect and potentially recover from
public enum CorruptionType: String, Sendable {
  case orphanedToolResult = "orphaned_tool_result"
  case stopReasonMismatch = "stop_reason_mismatch"
  case missingParent = "missing_parent"
  case invalidContentBlock = "invalid_content_block"
}
