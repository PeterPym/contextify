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
  private let llm: TranscriptMetadataLLM
  private let postProcessor = MetadataPostProcessor()

  private init() {
    self.llm = TranscriptMetadataLLM.shared
  }

  /// Initialize with database orchestrator (call once from app startup)
  func initialize(orchestrator: TranscriptOrchestrator) async {
    self.orchestrator = orchestrator
    log.debug("TranscriptMetadataOrchestrator initialized with SQL backend")

    // Calibrate LLM overhead on startup
    #if canImport(FoundationModels)
    if #available(macOS 26, *) {
      do {
        try await llm.calibrateOverheadIfNeeded()
      } catch {
        log.warning("Overhead calibration failed, using default: \(error.localizedDescription)")
      }
    }
    #endif
  }

  private let currentPromptVersion = 2
  private let currentGeneratorVersion = 1

  // Circuit breaker with sliding window (using shared utility)
  private let circuitBreaker = CircuitBreaker(
    windowSeconds: 300,      // 5 minutes
    failureThreshold: 0.6,   // 60% failure rate
    minimumRequests: 5       // Need at least 5 requests
  )

  // Concurrency control (using shared utility)
  private var activeTasks: [URL: Task<TranscriptMetadata, Error>] = [:]
  private let llmGate = ConcurrencyGate(permits: 2)

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

  // MARK: - Public API

  /// Ensures metadata exists for a session, generating if needed
  func ensureMetadata(
    for session: TranscriptSession,
    forceRegenerate: Bool = false
  ) async throws -> TranscriptMetadata {
    guard let orchestrator = orchestrator else {
      log.error("TranscriptMetadataOrchestrator not initialized with orchestrator")
      throw TranscriptMetadataError.notInitialized
    }

    // Cancel existing task if forcing regeneration
    if forceRegenerate, let existingTask = activeTasks[session.fileURL] {
      existingTask.cancel()
      activeTasks.removeValue(forKey: session.fileURL)
    }

    // Check for existing task
    if let existingTask = activeTasks[session.fileURL] {
      log.info("Reusing existing generation task for \(session.identifier, privacy: .public)")
      return try await existingTask.value
    }

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
    return try await task.value
  }

  // MARK: - Private Implementation

  private func removeTask(for url: URL) {
    activeTasks.removeValue(forKey: url)
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

    log.info("Generating metadata for \(transcriptId, privacy: .public)")

    // Read entries from database (not JSONL file)
    let parseStart = Date()
    let entries = try orchestrator.getEntries(forTranscript: transcriptId, afterTimestamp: nil)
    let exchanges = convertEntriesToExchanges(entries)
    let parseTime = Date().timeIntervalSince(parseStart)

    log.info("📊 Loaded \(exchanges.count, privacy: .public) exchanges from database (from \(entries.count, privacy: .public) entries)")

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
      log.warning("Circuit breaker active (\(cbStats.failures)/\(cbStats.total), \(String(format: "%.1f%%", cbStats.ratio * 100))), using heuristic fallback")
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      try await saveToSQL(metadata, transcriptId: transcriptId, fileURL: session.fileURL, orchestrator: orchestrator)
      return metadata
    }

    // Calculate available token budget using actual LLM tokenizer
    #if canImport(FoundationModels)
    let availableTokens: Int
    if #available(macOS 26, *) {
      // For adaptive strategy, we need to know the budget first
      // Use a preliminary count estimate to decide strategy
      let preliminaryCount = exchanges.count
      availableTokens = await llm.calculateAvailableContextTokens(
        sampledCount: min(preliminaryCount, MetadataBudgets.bookendCount * 2),
        totalCount: preliminaryCount
      )
    } else {
      // Fallback to static budget if LLM not available
      availableTokens = MetadataBudgets.samplerBudget
    }
    #else
    let availableTokens = MetadataBudgets.samplerBudget
    #endif

    // Select strategy based on available budget and exchange count
    let strategy: GenerationStrategy
    if exchanges.count <= MetadataBudgets.fullStrategyLimit {
      strategy = .full
    } else {
      strategy = .adaptive
    }

    // Build context with dynamic budget (background-safe, no MainActor needed)
    let samplingStart = Date()
    let context = try builder.build(
      exchanges: exchanges,
      strategy: strategy,
      budgetTokens: availableTokens
    )
    let samplingTime = Date().timeIntervalSince(samplingStart)

    // Log context size for debugging
    log.info("Built context: \(context.text.count) chars, estimated \(context.text.count / 4) tokens, budget was \(availableTokens) tokens")

    // Call LLM (with fallback to bookends on failure)
    var metadata: TranscriptMetadata
    let llmStart = Date()

    do {
      // Wait for LLM slot
      await llmGate.acquire()
      defer { Task { await llmGate.release() } }

      #if canImport(FoundationModels)
      if #available(macOS 26, *) {
        stats.llmCalls += 1
        let guided = try await llm.singlePass(
          context: context.text,
          sampledCount: context.sampledCount,
          totalCount: exchanges.count,
          strategy: strategy.rawValue
        )

        // Post-process (background-safe)
        metadata = postProcessor.apply(to: guided, context: context.text)
        metadata.messageCount = exchanges.count
        metadata.strategy = "singlePass:\(strategy.rawValue)"

        await circuitBreaker.recordSuccess()
      } else {
        throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
      }
      #else
      throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
      #endif
    } catch {
      stats.failures += 1

      // Log error with specific context
      if let llmError = error as? TranscriptMetadataLLM.LLMError,
         case .contextWindowExceeded(let tokens, let limit) = llmError {
        log.warning("Context window exceeded: \(tokens)/\(limit) tokens with \(strategy.rawValue) strategy")

        // Check if remote fallback is enabled for rare overflow cases
        if MetadataBudgets.enableRemoteLargeWindowFallback {
          log.info("Remote large-window fallback enabled but not yet implemented - falling back to heuristic")
          // TODO: Implement remote service call with 32K+ context window
          // For now, fall through to existing fallback logic
        }
      } else {
        log.error("LLM call failed: \(error.localizedDescription, privacy: .public)")
      }

      await circuitBreaker.recordFailure()

      // Try bookends fallback if we weren't already using it
      if strategy != .bookends {
        log.info("Retrying with bookends strategy (first 10 + last 10 exchanges)...")
        let bookendContext = try builder.build(
          exchanges: exchanges,
          strategy: .bookends,
          budgetTokens: availableTokens
        )

        do {
          await llmGate.acquire()
          defer { Task { await llmGate.release() } }

          #if canImport(FoundationModels)
          if #available(macOS 26, *) {
            stats.llmCalls += 1
            let guided = try await llm.singlePass(
              context: bookendContext.text,
              sampledCount: bookendContext.sampledCount,
              totalCount: exchanges.count,
              strategy: "bookends-fallback"
            )

            metadata = postProcessor.apply(to: guided, context: bookendContext.text)
            metadata.messageCount = exchanges.count
            metadata.strategy = "singlePass:bookends-fallback"

            await circuitBreaker.recordSuccess()
          } else {
            throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
          }
          #else
          throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
          #endif
        } catch {
          stats.failures += 1
          log.error("Bookends fallback also failed, using heuristic")
          await circuitBreaker.recordFailure()
          metadata = HeuristicMetadata.generate(exchanges: exchanges)
          metadata.strategy = "heuristic"  // DB constraint requires: full, bookends, or heuristic
        }
      } else {
        // Already tried bookends, use heuristic
        metadata = HeuristicMetadata.generate(exchanges: exchanges)
        metadata.strategy = "heuristic"  // DB constraint requires: full, bookends, or heuristic
      }
    }

    let llmTime = Date().timeIntervalSince(llmStart)

    // Finalize metadata and save to SQL
    let storageStart = Date()
    try await saveToSQL(metadata, transcriptId: transcriptId, fileURL: session.fileURL, orchestrator: orchestrator)
    let storageTime = Date().timeIntervalSince(storageStart)

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
}

// MARK: - Error Types

enum TranscriptMetadataError: Error {
  case notInitialized
  case orphanedTranscript(String)  // Transcript FK missing when saving metadata
}

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
