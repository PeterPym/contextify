import Foundation
import OSLog
import ContextifyCore
import CryptoKit
import GRDB

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Orchestrates transcript metadata generation with SQL caching, retries, and circuit breaking
actor TranscriptMetadataOrchestrator {
  static let shared = TranscriptMetadataOrchestrator()

  private let log = Logger(subsystem: "dev.contextify.metadata", category: "Orchestrator")
  private var orchestrator: TranscriptOrchestrator!  // Injected after init
  private let builder = ContextBuilder()
  private let postProcessor = MetadataPostProcessor()

  private init() {}

  /// Initialize with database orchestrator (call once from app startup)
  func initialize(orchestrator: TranscriptOrchestrator) async {
    self.orchestrator = orchestrator
    log.debug("TranscriptMetadataOrchestrator initialized with SQL backend (using FoundationLLM)")
  }

  private let currentPromptVersion = 2
  private let currentGeneratorVersion = 1

  // Circuit breaker with sliding window (using shared utility)
  private let circuitBreaker = CircuitBreaker(
    windowSeconds: 300,      // 5 minutes
    failureThreshold: 0.6,   // 60% failure rate
    minimumRequests: 5       // Need at least 5 requests
  )

  // MARK: - Queue Infrastructure (Viewport-Aware Processing)

  /// Queue item for LIFO processing of transcript metadata generation
  private struct QueueItem: Identifiable {
    let id: String  // transcript identifier (SQL primary key)
    let session: TranscriptSession
    let enqueuedAt: Date

    var age: TimeInterval {
      Date().timeIntervalSince(enqueuedAt)
    }
  }

  // LIFO queue (newest first) - viewport prioritization
  private var pendingQueue: [QueueItem] = []
  private var pendingKeys: Set<String> = []  // Fast deduplication by transcript ID
  private var processingTask: Task<Void, Never>?
  private var isProcessing = false

  // Stabilization delay to prevent flooding (matches TimelineCacheMissGenerator)
  private let stabilizationDelayMs: Int = 500

  // Queue metrics (viewport-aware pruning metrics)
  private struct QueueMetrics {
    var totalEnqueued = 0
    var totalProcessed = 0
    var totalPruned = 0
    var totalErrors = 0

    var pruningRate: Double {
      guard totalEnqueued > 0 else { return 0.0 }
      return Double(totalPruned) / Double(totalEnqueued)
    }
  }
  private var queueMetrics = QueueMetrics()

  // Error tracking for queue processing (separate from circuit breaker)
  // Local queue-level breaker: pauses the worker after N consecutive generation failures.
  // Distinct from the LLM sliding-window CircuitBreaker (which decides per-call fallback to heuristics).
  private var consecutiveErrors = 0
  private var isPaused = false
  private let maxConsecutiveErrors = 3
  private var circuitBreakerResetTask: Task<Void, Never>?  // Track reset Task to avoid duplicates

  // Concurrency control (legacy - will be replaced by queue)
  private var activeTasks: [URL: Task<TranscriptMetadata, Error>] = [:]

  // Observability stats
  private struct Stats {
    var hits = 0
    var misses = 0
    var llmCalls = 0
    var failures = 0
    var breakerOpens = 0
  }
  private var stats = Stats()
  private var requestCount = 0

  // MARK: - Observer Infrastructure (Status Bar Support)

  // UUID-keyed dictionary for status bar observers
  private var queueObservers: [UUID: AsyncStream<QueueStats>.Continuation] = [:]

  // MARK: - Public API

  /// Enqueue sessions for background metadata generation (viewport-aware)
  /// - Parameter sessions: Array of transcript sessions to generate metadata for
  func enqueueMetadata(for sessions: [TranscriptSession]) async {
    guard !sessions.isEmpty else {
      log.debug("[QUEUE-ADD] Empty sessions array, returning")
      return
    }

    log.info("[QUEUE-ADD] Enqueueing \(sessions.count) sessions for metadata generation")

    let beforeCount = pendingQueue.count
    var skippedDuplicates = 0

    // Add to LIFO queue, removing duplicates first to maintain proper ordering
    // Enqueue in reverse order so newest sessions (at start of array) end up at front of queue
    for session in sessions.reversed() {
      let transcriptId = session.identifier

      // If already queued, remove it first so we can re-insert at correct position
      if pendingKeys.contains(transcriptId) {
        pendingQueue.removeAll { $0.id == transcriptId }
        pendingKeys.remove(transcriptId)
        skippedDuplicates += 1
      }

      let item = QueueItem(
        id: transcriptId,
        session: session,
        enqueuedAt: Date()
      )

      // Insert at front (LIFO - newest first)
      pendingQueue.insert(item, at: 0)
      pendingKeys.insert(transcriptId)
    }

    let added = pendingQueue.count - beforeCount
    if skippedDuplicates > 0 {
      log.debug("[QUEUE-ADD] Skipped \(skippedDuplicates) duplicate sessions")
    }

    // Update metrics
    queueMetrics.totalEnqueued += added
    log.info("[QUEUE-ADD] Added \(added) sessions (total pending: \(self.pendingQueue.count), total enqueued: \(self.queueMetrics.totalEnqueued))")

    // Notify observers
    notifyQueueChanged()

    // Ensure processing task is running
    await ensureProcessing()
  }

  /// Shutdown generator and cancel any in-flight processing
  func shutdown() {
    log.info("[QUEUE-SHUTDOWN] Shutting down metadata generator (pending: \(self.pendingQueue.count))")

    // Cancel processing
    processingTask?.cancel()
    processingTask = nil
    isProcessing = false

    // Cancel circuit breaker reset
    circuitBreakerResetTask?.cancel()
    circuitBreakerResetTask = nil

    // Clear queue
    pendingQueue.removeAll()
    pendingKeys.removeAll()

    // Reset state
    consecutiveErrors = 0
    isPaused = false

    // Notify observers
    notifyQueueChanged()

    // Close observer streams
    for (_, continuation) in queueObservers {
      continuation.finish()
    }
    queueObservers.removeAll()
  }

  /// Prune pending queue to keep only sessions visible in viewport
  /// - Parameter visibleIDs: Set of transcript IDs currently visible to user
  func pruneQueue(keepOnly visibleIDs: Set<String>) {
    let beforeCount = pendingQueue.count
    log.debug("[QUEUE-PRUNE] Checking queue: \(beforeCount) pending, \(visibleIDs.count) visible IDs")

    guard beforeCount > 0 else {
      log.debug("[QUEUE-PRUNE] Queue empty, nothing to prune")
      return
    }

    // Keep items that are visible OR recently enqueued (< stabilization delay)
    pendingQueue.removeAll { item in
      let isVisible = visibleIDs.contains(item.id)
      let isRecent = item.age < Double(stabilizationDelayMs) / 1000.0
      let shouldKeep = isVisible || isRecent

      if !shouldKeep {
        log.debug("[QUEUE-PRUNE] Removing session \(item.id.prefix(8)): visible=\(isVisible), recent=\(isRecent)")
      }
      return !shouldKeep
    }

    // Rebuild deduplication set
    pendingKeys = Set(pendingQueue.map { $0.id })

    let prunedCount = beforeCount - pendingQueue.count
    if prunedCount > 0 {
      // Update metrics
      queueMetrics.totalPruned += prunedCount
      let pruningRate = queueMetrics.pruningRate
      log.info("[QUEUE-PRUNE] Removed \(prunedCount) invisible sessions (kept \(self.pendingQueue.count), pruning rate: \(String(format: "%.1f%%", pruningRate * 100)))")
      notifyQueueChanged()
    } else {
      log.debug("[QUEUE-PRUNE] No sessions removed (all \(beforeCount) still visible or recent)")
    }
  }

  /// Ensures metadata exists for a session, generating if needed
  func ensureMetadata(
    for session: TranscriptSession,
    forceRegenerate: Bool = false
  ) async throws -> TranscriptMetadata {
    guard let orchestrator = orchestrator else {
      log.error("[META-ERROR] TranscriptMetadataOrchestrator not initialized with orchestrator")
      throw TranscriptMetadataError.notInitialized
    }

    // Cancel existing task if forcing regeneration
    if forceRegenerate, let existingTask = activeTasks[session.fileURL] {
      log.info("[META-CANCEL] Canceling existing task for \(session.identifier, privacy: .public) (force regenerate)")
      existingTask.cancel()
      activeTasks.removeValue(forKey: session.fileURL)
    }

    // Check for existing task
    if let existingTask = activeTasks[session.fileURL] {
      log.debug("[META-REUSE] Reusing existing generation task for \(session.identifier, privacy: .public)")
      return try await existingTask.value
    }

    log.info("[META-START] Starting metadata generation for \(session.identifier, privacy: .public)")

    // Create new task
    let task = Task<TranscriptMetadata, Error> {
      defer {
        Task { self.removeTask(for: session.fileURL) }
      }
      return try await self.generateMetadata(
        for: session,
        orchestrator: orchestrator,
        forceRegenerate: forceRegenerate
      )
    }

    activeTasks[session.fileURL] = task
    notifyQueueChanged()
    return try await task.value
  }

  // MARK: - Private Implementation

  /// Ensure processing task is running (idempotent)
  private func ensureProcessing() async {
    // Spawn if missing
    if processingTask == nil {
      let count = pendingQueue.count
      log.debug("[QUEUE-START] Spawning processing task (pending: \(count))")
      processingTask = Task { await self.processQueue() }
      return
    }

    // Defensive: if we have work queued but not processing, restart
    if !isProcessing && !pendingQueue.isEmpty {
      log.warning("[QUEUE-RESTART] Processing handle exists but not active; restarting worker (pending: \(self.pendingQueue.count))")
      processingTask?.cancel()
      processingTask = Task { await self.processQueue() }
    }
  }

  /// LIFO processing loop - processes queue until empty or cancelled
  private func processQueue() async {
    defer {
      log.debug("[QUEUE-STOP] Processing loop stopped")
    }

    log.info("[QUEUE-LOOP] Processing loop started")

    while !Task.isCancelled {
      // Check if paused by circuit breaker
      if isPaused {
        log.debug("[QUEUE-PAUSED] Processing paused, waiting...")
        try? await Task.sleep(for: .milliseconds(1000))
        continue
      }

      // Get next item (LIFO - most recent first): newest is at index 0
      guard !pendingQueue.isEmpty else {
        // Queue empty, wait a bit before checking again
        try? await Task.sleep(for: .milliseconds(100))
        continue
      }

      // Mark as processing only when actually working on an item
      isProcessing = true
      let item = pendingQueue.removeFirst()  // Pop from front where newest items are
      pendingKeys.remove(item.id)

      // Notify UI that generation started (for loading indicator)
      Task { @MainActor in
        NotificationCenter.default.post(
          name: .transcriptMetadataGenerationStarted,
          object: item.id,
          userInfo: ["transcriptId": item.id]
        )
      }

      // Log queue state
      let remaining = pendingQueue.count
      log.info("[QUEUE-PROCESS] Processing \(item.id.prefix(8)) (\(remaining) remaining)")

      do {
        // Generate metadata (reuse existing generateMetadata logic)
        guard let orchestrator = orchestrator else {
          log.error("[QUEUE-ERROR] Orchestrator not initialized; pausing worker 1s")
          isProcessing = false
          try? await Task.sleep(for: .seconds(1))
          continue
        }

        _ = try await generateMetadata(
          for: item.session,
          orchestrator: orchestrator,
          forceRegenerate: false
        )

        log.info("[QUEUE-DONE] ✅ Metadata generated for \(item.id.prefix(8))")

        // Success - reset error counter and update metrics
        consecutiveErrors = 0
        queueMetrics.totalProcessed += 1

      } catch {
        log.error("[QUEUE-ERROR] ❌ Failed to generate metadata for \(item.id.prefix(8)): \(error.localizedDescription)")

        // Track errors and trigger circuit breaker if needed
        consecutiveErrors += 1
        queueMetrics.totalErrors += 1

        if consecutiveErrors >= maxConsecutiveErrors {
          isPaused = true
          log.warning("[CIRCUIT-BREAKER] ⚠️  Paused after \(self.consecutiveErrors) consecutive errors")

          // Cancel any existing reset task to avoid duplicates
          circuitBreakerResetTask?.cancel()

          // Reset after 10 seconds
          circuitBreakerResetTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }

            await self.resetCircuitBreaker()
          }
        }
      }

      // Clear processing flag after item completion (success or failure)
      isProcessing = false
      notifyQueueChanged()
    }

    log.info("[QUEUE-LOOP] Processing loop cancelled")
  }

  /// Reset circuit breaker state (called after cooldown or manually)
  private func resetCircuitBreaker() {
    consecutiveErrors = 0
    isPaused = false
    circuitBreakerResetTask = nil
    log.info("[CIRCUIT-BREAKER] Resumed after cooldown")
  }

  private func removeTask(for url: URL) {
    activeTasks.removeValue(forKey: url)
    notifyQueueChanged()
  }

  /// Convert TranscriptEntry[] to Exchange[] (same logic as SQLBackedMetadataOrchestrator)
  private func convertEntriesToExchanges(_ entries: [TranscriptEntry]) -> [Exchange] {
    var exchanges: [Exchange] = []

    for entry in entries {
      let role: Exchange.Role
      switch entry.kind {
      case "user":
        role = .user
      case "assistant":
        role = .assistant
      default:
        continue
      }

      guard !entry.content.isEmpty else { continue }

      let timestamp = Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
      exchanges.append(Exchange(
        role: role,
        text: entry.content,
        timestamp: timestamp
      ))
    }

    return exchanges
  }

  private func generateMetadata(
    for session: TranscriptSession,
    orchestrator: TranscriptOrchestrator,
    forceRegenerate: Bool
  ) async throws -> TranscriptMetadata {
    let startTime = Date()

    // Get transcript ID from SQL (using identifier which is the transcript_id from SQL)
    let transcriptId = session.identifier

    // Check SQL cache unless forcing regeneration
    if !forceRegenerate {
      if let cached = try orchestrator.getMetadata(forTranscript: transcriptId) {
        // Check if metadata is fresh (versions match and file hasn't changed)
        let isFresh = try await isFresh(
          metadata: cached,
          fileURL: session.fileURL,
          orchestrator: orchestrator
        )

        if isFresh {
          stats.hits += 1
          logStatsIfNeeded()
          log.info("Using cached metadata for \(transcriptId, privacy: .public)")
          return cached.toUIModel()
        } else {
          stats.misses += 1
          log.debug("Cached metadata is stale, regenerating")
        }
      } else {
        stats.misses += 1
      }
    }

    log.info("[META-GEN] Generating metadata for \(transcriptId, privacy: .public)")

    // Read entries from database (not JSONL file)
    let parseStart = Date()
    log.debug("[META-GEN] Calling getEntries for transcript: \(transcriptId, privacy: .public)")
    let entries = try orchestrator.getEntries(forTranscript: transcriptId, afterTimestamp: nil)
    log.debug("[META-GEN] Loaded \(entries.count, privacy: .public) entries from database")
    let exchanges = convertEntriesToExchanges(entries)
    log.debug("[META-GEN] Converted to \(exchanges.count, privacy: .public) exchanges")
    let parseTime = Date().timeIntervalSince(parseStart)

    log.info("[META-GEN] Loaded \(exchanges.count, privacy: .public) exchanges in \(String(format: "%.2f", parseTime), privacy: .public)s")

    // Handle very short transcripts with heuristic
    if exchanges.count < 3 {
      log.warning("⚠️ Very short transcript (\(exchanges.count, privacy: .public) exchanges < 3), using heuristic fallback")
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      try await saveToSQL(metadata, transcriptId: transcriptId, fileURL: session.fileURL, orchestrator: orchestrator)
      return metadata
    }

    // Check circuit breaker
    guard await circuitBreaker.allow() else {
      stats.breakerOpens += 1
      let cbStats = await circuitBreaker.stats()
      log.warning("[CIRCUIT-OPEN] ⚠️  Circuit breaker active (\(cbStats.failures, privacy: .public)/\(cbStats.total, privacy: .public), \(String(format: "%.1f%%", cbStats.ratio * 100), privacy: .public)), using heuristic fallback")
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      try await saveToSQL(metadata, transcriptId: transcriptId, fileURL: session.fileURL, orchestrator: orchestrator)
      return metadata
    }

    // Select strategy based on exchange count
    let strategy: GenerationStrategy
    if exchanges.count <= MetadataBudgets.fullStrategyLimit {
      strategy = .full
    } else {
      strategy = .adaptive
    }

    // Build context (background-safe, no MainActor needed)
    let samplingStart = Date()
    let context = try builder.build(
      exchanges: exchanges,
      strategy: strategy,
      budgetTokens: MetadataBudgets.samplerBudget
    )
    let samplingTime = Date().timeIntervalSince(samplingStart)

    log.info("Built context: \(context.text.count) chars, strategy=\(strategy.rawValue)")

    // Get versioned instructions for session isolation
    let instructions = TranscriptPrompts.metadataInstructions()

    // Generate per-transcript session key for isolation
    #if canImport(FoundationModels)
    var sessionId: String = ""
    if #available(macOS 26, *) {
      sessionId = FoundationLLM.shared.sessionKey(
        model: "FoundationLLM",
        instructions: instructions,
        schemaSig: "GuidedTranscriptMetadata-v\(TranscriptPrompts.metadataPromptVersion)",
        transcriptId: transcriptId
      )
    }
    #endif

    // Call LLM (with fallback to bookends on failure)
    var metadata: TranscriptMetadata
    let llmStart = Date()

    do {
      #if canImport(FoundationModels)
      if #available(macOS 26, *) {
        stats.llmCalls += 1

        // 1. Pre-flight validation (ephemeral, same session)
        let fitted = try await TranscriptContextFitting.ensureFitsViaRawPreflight(
          context: context.text,
          sampledCount: context.sampledCount,
          totalCount: exchanges.count,
          instructions: instructions,
          sessionId: sessionId
        )

        // 2. Reset session to ensure clean slate (belt-and-suspenders)
        if #available(macOS 26, *) {
          await FoundationLLM.shared.resetSessionById(sessionId)
        }

        // 2. Guided generation with fitted context (routed through FoundationLLM)
        let prompt = """
        CONTEXT: This excerpt shows \(context.sampledCount) of \(exchanges.count) messages. First 10 and last 10 are always included; the middle is selected for importance.

        \(fitted)
        """

        let options = GenerationOptions(
          sampling: .greedy,
          temperature: 0,
          maximumResponseTokens: 150
        )

        let guided: GuidedTranscriptMetadata = try await FoundationLLM.shared.generateGuided(
          instructions: instructions,
          prompt: prompt,
          generating: GuidedTranscriptMetadata.self,
          includeSchema: true,
          options: options,
          sessionId: sessionId
        )

        // Post-process (background-safe)
        metadata = postProcessor.apply(to: guided, context: fitted)
        metadata.messageCount = exchanges.count
        metadata.strategy = strategy.rawValue

        log.info("[META-LLM-SUCCESS] ✅ LLM generation succeeded for \(transcriptId, privacy: .public)")
        await circuitBreaker.recordSuccess()
      } else {
        throw LLMError.unavailable
      }
      #else
      throw LLMError.unavailable
      #endif
    } catch {
      stats.failures += 1
      log.error("[META-LLM-ERROR] ❌ LLM call failed for \(transcriptId, privacy: .public): \(error.localizedDescription, privacy: .public)")
      await circuitBreaker.recordFailure()

      // Try bookends fallback if we weren't already using it
      if strategy != .bookends {
        log.info("[META-RETRY] Retrying with bookends strategy (first 10 + last 10 exchanges)...")

        // Reset session before retry to prevent history accumulation
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
          await FoundationLLM.shared.resetSessionById(sessionId)
        }
        #endif

        let bookendContext = try builder.build(
          exchanges: exchanges,
          strategy: .bookends,
          budgetTokens: MetadataBudgets.samplerBudget
        )

        do {
          #if canImport(FoundationModels)
          if #available(macOS 26, *) {
            stats.llmCalls += 1

            let fittedBookend = try await TranscriptContextFitting.ensureFitsViaRawPreflight(
              context: bookendContext.text,
              sampledCount: bookendContext.sampledCount,
              totalCount: exchanges.count,
              instructions: instructions,
              sessionId: sessionId
            )

            // Reset again after pre-flight
            if #available(macOS 26, *) {
              await FoundationLLM.shared.resetSessionById(sessionId)
            }

            let bookendPrompt = """
            CONTEXT: This excerpt shows \(bookendContext.sampledCount) of \(exchanges.count) messages. First 10 and last 10 are always included; the middle is selected for importance.

            \(fittedBookend)
            """

            let options = GenerationOptions(
              sampling: .greedy,
              temperature: 0,
              maximumResponseTokens: 150
            )

            let guided: GuidedTranscriptMetadata = try await FoundationLLM.shared.generateGuided(
              instructions: instructions,
              prompt: bookendPrompt,
              generating: GuidedTranscriptMetadata.self,
              includeSchema: true,
              options: options,
              sessionId: sessionId
            )

            metadata = postProcessor.apply(to: guided, context: fittedBookend)
            metadata.messageCount = exchanges.count
            metadata.strategy = "bookends"

            log.info("[META-RETRY-SUCCESS] ✅ Bookends retry succeeded for \(transcriptId, privacy: .public)")
            await circuitBreaker.recordSuccess()
          } else {
            throw LLMError.unavailable
          }
          #else
          throw LLMError.unavailable
          #endif
        } catch {
          stats.failures += 1
          log.error("[META-FALLBACK] ❌ Bookends fallback failed for \(transcriptId, privacy: .public), using heuristic")
          await circuitBreaker.recordFailure()
          metadata = HeuristicMetadata.generate(exchanges: exchanges)
          metadata.strategy = "heuristic"
        }
      } else {
        // Already tried bookends, use heuristic
        log.info("[META-FALLBACK] Using heuristic for \(transcriptId, privacy: .public) (already tried bookends)")
        metadata = HeuristicMetadata.generate(exchanges: exchanges)
        metadata.strategy = "heuristic"
      }
    }

    let llmTime = Date().timeIntervalSince(llmStart)

    // Finalize metadata and save to SQL
    let storageStart = Date()
    log.debug("[META-SAVE] Saving metadata to SQL for \(transcriptId, privacy: .public)")
    try await saveToSQL(metadata, transcriptId: transcriptId, fileURL: session.fileURL, orchestrator: orchestrator)
    let storageTime = Date().timeIntervalSince(storageStart)
    log.debug("[META-SAVE] Saved in \(String(format: "%.2f", storageTime), privacy: .public)s")

    let totalTime = Date().timeIntervalSince(startTime)

    // Log metrics
    let metrics = GenerationMetrics(
      parseTimeMs: Int(parseTime * 1000),
      samplingTimeMs: Int(samplingTime * 1000),
      llmTimeMs: Int(llmTime * 1000),
      storageTimeMs: Int(storageTime * 1000),
      totalTimeMs: Int(totalTime * 1000),
      exchangeCount: exchanges.count,
      strategy: strategy,
      success: !metadata.needsReview,
      needsReview: metadata.needsReview
    )

    logMetrics(metrics, for: transcriptId)

    return metadata
  }

  // MARK: - SQL Persistence

  private func saveToSQL(
    _ metadata: TranscriptMetadata,
    transcriptId: String,
    fileURL: URL,
    orchestrator: TranscriptOrchestrator
  ) async throws {
    // Compute transcript SHA256 for freshness tracking (using streaming to avoid memory blowup)
    let transcriptSHA256 = try FileFacts.stableSha256(url: fileURL)

    // Convert topics array to JSON string
    let topicsJSON = (try? String(data: JSONEncoder().encode(metadata.topics), encoding: .utf8)) ?? "[]"

    // Create SQL record
    let now = Int(Date().timeIntervalSince1970)
    let record = TranscriptMetadataRecord(
      transcriptId: transcriptId,
      projectId: "", // Will be filled by repository from transcript FK
      title: metadata.title,
      description: metadata.description,
      topics: topicsJSON,
      confidence: metadata.confidence,
      mayContainHallucinations: metadata.mayContainHallucinations ? 1 : 0,
      needsReview: metadata.needsReview ? 1 : 0,
      generatedAt: Int(metadata.generatedAt.timeIntervalSince1970),
      model: metadata.model,
      promptVersion: currentPromptVersion,
      generatorVersion: currentGeneratorVersion,
      transcriptSha256: transcriptSHA256,  // Note: lowercase 'sha' in record
      messageCount: metadata.messageCount,
      strategy: metadata.strategy,
      llmCalls: metadata.llmCalls,
      latencyMs: metadata.latencyMs,
      createdAt: now,
      updatedAt: now
    )

    // Save with FK constraint error handling
    do {
      try orchestrator.saveMetadata(record)
    } catch let err as DatabaseError where err.resultCode == .SQLITE_CONSTRAINT_FOREIGNKEY {
      log.error("Orphaned metadata for \(transcriptId, privacy: .public) - transcript FK missing")
      throw TranscriptMetadataError.orphanedTranscript(transcriptId)
    }

    // Post notification for cache updates (outside actor to avoid reentrancy)
    Task { @MainActor in
      NotificationCenter.default.post(
        name: .transcriptMetadataUpdated,
        object: transcriptId,
        userInfo: ["transcriptId": transcriptId]
      )
    }
  }

  private func isFresh(
    metadata: TranscriptMetadataRecord,
    fileURL: URL,
    orchestrator: TranscriptOrchestrator
  ) async throws -> Bool {
    // Check if versions match
    guard metadata.promptVersion == currentPromptVersion,
          metadata.generatorVersion == currentGeneratorVersion else {
      return false
    }

    // Compute current file SHA256 (using streaming to avoid memory blowup)
    let currentSHA = try FileFacts.stableSha256(url: fileURL)

    // Compare with cached SHA256 (note: lowercase 'sha' in record)
    return metadata.transcriptSha256 == currentSHA
  }

  // MARK: - Metrics Logging

  private func logStatsIfNeeded() {
    self.requestCount += 1
    if self.requestCount % 100 == 0 {
      let total = max(1, self.stats.hits + self.stats.misses)
      let hitRate = Int(Double(self.stats.hits) * 100 / Double(total))
      log.info("Metadata stats: hit rate \(hitRate)%, calls=\(self.stats.llmCalls), failures=\(self.stats.failures), breaker opens=\(self.stats.breakerOpens)")
    }
  }

  private func logMetrics(_ metrics: GenerationMetrics, for identifier: String) {
    log.info("""
      Metadata generated for \(identifier, privacy: .public): \
      parse=\(metrics.parseTimeMs)ms, \
      sampling=\(metrics.samplingTimeMs)ms, \
      llm=\(metrics.llmTimeMs)ms, \
      storage=\(metrics.storageTimeMs)ms, \
      total=\(metrics.totalTimeMs)ms, \
      exchanges=\(metrics.exchangeCount), \
      strategy=\(metrics.strategy.rawValue, privacy: .public), \
      needsReview=\(metrics.needsReview)
      """)
  }

  // MARK: - Queue Observation API

  /// Subscribe to metadata generation queue state changes
  nonisolated func observeQueue() -> AsyncStream<QueueStats> {
    let observerId = UUID()

    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      Task {
        await self.registerObserver(id: observerId, continuation: continuation)
      }
      continuation.onTermination = { @Sendable _ in
        Task { await self.removeObserver(id: observerId) }
      }
    }
  }

  private func registerObserver(id: UUID, continuation: AsyncStream<QueueStats>.Continuation) {
    queueObservers[id] = continuation
    let stats = makeQueueStats()
    continuation.yield(stats)
  }

  private func removeObserver(id: UUID) {
    queueObservers.removeValue(forKey: id)
  }

  private func notifyQueueChanged() {
    let stats = makeQueueStats()
    for (_, continuation) in queueObservers {
      continuation.yield(stats)
    }
  }

  private func makeQueueStats() -> QueueStats {
    let pendingCount = pendingQueue.count
    let processingCount = isProcessing ? 1 : 0  // Sequential processing (1 at a time)

    // No ETA calculation for metadata (generation time varies widely)
    // Error tracking from queue metrics (not circuit breaker)

    return QueueStats(
      pending: pendingCount,
      isProcessing: isProcessing,
      currentBatchSize: processingCount,  // Sequential: 0 or 1
      estimatedSecondsRemaining: 0,       // No predictable ETA
      recentErrorCount: queueMetrics.totalErrors,
      topErrorReason: nil
    )
  }
}

// MARK: - Error Types

enum TranscriptMetadataError: Error {
  case notInitialized
  case orphanedTranscript(String)  // Transcript FK missing when saving metadata
}

enum LLMError: Error {
  case unavailable
}

// MARK: - Heuristic Fallback

enum HeuristicMetadata: Sendable {
  nonisolated static func generate(exchanges: [Exchange]) -> TranscriptMetadata {
    let title = exchanges.count < 3 ? "Brief Session" : "Developer Chat"
    let description = generateDescription(exchanges: exchanges)
    let topics = ["general"]

    return TranscriptMetadata(
      version: 1,
      title: title,
      description: description,
      topics: topics,
      confidence: 0.3,
      mayContainHallucinations: false,
      needsReview: true,
      generatedAt: Date(),
      model: "heuristic",
      promptVersion: 0,
      generatorVersion: 1,
      transcriptSHA256: "",
      messageCount: exchanges.count,
      strategy: "heuristic",
      llmCalls: 0,
      latencyMs: 0
    )
  }

  nonisolated private static func generateDescription(exchanges: [Exchange]) -> String {
    guard !exchanges.isEmpty else {
      return "Empty transcript."
    }

    if exchanges.count < 3 {
      return "Very short conversation."
    }

    // Extract first and last user messages
    let userMessages = exchanges.filter { $0.role == .user }
    let firstUser = userMessages.first?.text.prefix(50) ?? ""
    let lastUser = userMessages.last?.text.prefix(50) ?? ""

    if firstUser.isEmpty && lastUser.isEmpty {
      return "Conversation with \(exchanges.count) messages."
    }

    if !firstUser.isEmpty && !lastUser.isEmpty {
      return "Started with: \(firstUser)... Ended with: \(lastUser)..."
    }

    return "Conversation with \(exchanges.count) messages."
  }
}

// MARK: - QueueStatsProvider Conformance

extension TranscriptMetadataOrchestrator: QueueStatsProvider {}

// MARK: - Record to UI Model Conversion

extension TranscriptMetadataRecord {
  nonisolated func toUIModel() -> TranscriptMetadata {
    // Parse topics from JSON
    let topicsArray = (try? JSONDecoder().decode([String].self, from: Data(topics.utf8))) ?? []

    return TranscriptMetadata(
      title: title,
      description: description,
      topics: topicsArray,
      confidence: confidence,
      mayContainHallucinations: mayContainHallucinations != 0,
      needsReview: needsReview != 0,
      generatedAt: Date(timeIntervalSince1970: TimeInterval(generatedAt)),
      model: model,
      promptVersion: promptVersion,
      generatorVersion: generatorVersion,
      transcriptSHA256: transcriptSha256,  // Note: lowercase 'sha' in record
      messageCount: messageCount,
      strategy: strategy,
      llmCalls: llmCalls,
      latencyMs: latencyMs
    )
  }
}
