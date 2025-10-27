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

  // Concurrency control (using shared utility)
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
    notifyQueueChanged()
    return try await task.value
  }

  // MARK: - Private Implementation

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

    log.info("Generating metadata for \(transcriptId, privacy: .public)")

    // Read entries from database (not JSONL file)
    let parseStart = Date()
    log.info("🔍 Calling getEntries(forTranscript: '\(transcriptId, privacy: .public)', afterTimestamp: nil)")
    let entries = try orchestrator.getEntries(forTranscript: transcriptId, afterTimestamp: nil)
    log.info("🔍 getEntries returned \(entries.count) entries for transcript '\(transcriptId, privacy: .public)'")
    let exchanges = convertEntriesToExchanges(entries)
    log.info("🔍 convertEntriesToExchanges produced \(exchanges.count) exchanges from \(entries.count) entries")
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

        await circuitBreaker.recordSuccess()
      } else {
        throw LLMError.unavailable
      }
      #else
      throw LLMError.unavailable
      #endif
    } catch {
      stats.failures += 1
      log.error("LLM call failed: \(error.localizedDescription, privacy: .public)")
      await circuitBreaker.recordFailure()

      // Try bookends fallback if we weren't already using it
      if strategy != .bookends {
        log.info("Retrying with bookends strategy (first 10 + last 10 exchanges)...")

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

            await circuitBreaker.recordSuccess()
          } else {
            throw LLMError.unavailable
          }
          #else
          throw LLMError.unavailable
          #endif
        } catch {
          stats.failures += 1
          log.error("Bookends fallback also failed, using heuristic")
          await circuitBreaker.recordFailure()
          metadata = HeuristicMetadata.generate(exchanges: exchanges)
          metadata.strategy = "heuristic"
        }
      } else {
        // Already tried bookends, use heuristic
        metadata = HeuristicMetadata.generate(exchanges: exchanges)
        metadata.strategy = "heuristic"
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
    let activeCount = activeTasks.count
    let isProcessing = activeCount > 0

    // No ETA calculation for metadata (tasks complete independently)
    // No error tracking exposed (handled by circuit breaker internally)

    return QueueStats(
      pending: activeCount,
      isProcessing: isProcessing,
      currentBatchSize: activeCount,  // All tasks run concurrently
      estimatedSecondsRemaining: 0,   // No predictable ETA
      recentErrorCount: 0,             // Circuit breaker handles this
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
