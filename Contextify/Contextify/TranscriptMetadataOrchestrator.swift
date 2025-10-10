import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Simple async semaphore for controlling concurrent access
actor AsyncSemaphore {
  private let limit: Int
  private var permits: Int

  init(_ limit: Int) {
    self.limit = limit
    self.permits = limit
  }

  func acquire() async {
    while permits == 0 {
      try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }
    permits -= 1
  }

  func release() {
    permits = min(permits + 1, limit)
  }
}

/// Orchestrates transcript metadata generation with caching, retries, and circuit breaking
actor TranscriptMetadataOrchestrator {
  static let shared = TranscriptMetadataOrchestrator()

  private let log = Logger(subsystem: "dev.contextify.metadata", category: "Orchestrator")
  private let store = SidecarMetadataStore()
  private let parser = TranscriptParser()
  private let builder = ContextBuilder()
  private let llm: TranscriptMetadataLLM
  private let postProcessor = MetadataPostProcessor()

  private init() {
    self.llm = TranscriptMetadataLLM.shared
  }

  private let currentPromptVersion = 2
  private let currentGeneratorVersion = 1

  // Circuit breaker state with sliding window
  private var requestWindow: [Date] = []
  private var failureCount = 0
  private let windowSpan: TimeInterval = 300 // 5 minutes
  private let circuitBreakerThreshold = 5

  // Concurrency control
  private var activeTasks: [URL: Task<TranscriptMetadata, Error>] = [:]
  private let llmGate = AsyncSemaphore(2)

  // MARK: - Public API

  /// Ensures metadata exists for a session, generating if needed
  func ensureMetadata(
    for session: TranscriptSession,
    forceRegenerate: Bool = false
  ) async throws -> TranscriptMetadata {
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
        Task { await self.removeTask(for: session.fileURL) }
      }
      return try await self.generateMetadata(for: session, forceRegenerate: forceRegenerate)
    }

    activeTasks[session.fileURL] = task
    return try await task.value
  }

  // MARK: - Private Implementation

  private func removeTask(for url: URL) {
    activeTasks.removeValue(forKey: url)
  }

  private func generateMetadata(
    for session: TranscriptSession,
    forceRegenerate: Bool
  ) async throws -> TranscriptMetadata {
    let startTime = Date()

    // Check cache unless forcing regeneration
    if !forceRegenerate,
       let cached = try? store.load(for: session.fileURL),
       store.isFresh(
        cached,
        for: session.fileURL,
        promptVersion: currentPromptVersion,
        generatorVersion: currentGeneratorVersion
       ) {
      log.info("Using cached metadata for \(session.identifier, privacy: .public)")
      return cached
    }

    log.info("Generating metadata for \(session.identifier, privacy: .public)")

    // Parse exchanges (background-safe, no MainActor needed)
    let parseStart = Date()
    let exchanges = try parser.parseExchanges(url: session.fileURL)
    let parseTime = Date().timeIntervalSince(parseStart)

    // Handle very short transcripts with heuristic
    if exchanges.count < 3 {
      log.info("Very short transcript (\(exchanges.count) exchanges), using heuristic")
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      try await store.save(metadata, for: session.fileURL)
      return metadata
    }

    // Check circuit breaker
    if shouldUseCircuitBreaker() {
      log.warning("Circuit breaker active, using heuristic fallback")
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      try await store.save(metadata, for: session.fileURL)
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
        let guided = try await llm.singlePass(
          context: context.text,
          sampledCount: context.sampledCount,
          totalCount: exchanges.count
        )

        // Post-process (background-safe)
        metadata = postProcessor.apply(to: guided, context: context.text)
        metadata.messageCount = exchanges.count
        metadata.strategy = "singlePass:\(strategy.rawValue)"

        recordSuccess()
      } else {
        throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
      }
      #else
      throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
      #endif
    } catch {
      log.error("LLM call failed: \(error.localizedDescription, privacy: .public)")
      recordFailure()

      // Try bookends fallback if we weren't already using it
      if strategy != .bookends {
        log.info("Retrying with bookends strategy...")
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
            let guided = try await llm.singlePass(
              context: bookendContext.text,
              sampledCount: bookendContext.sampledCount,
              totalCount: exchanges.count
            )

            metadata = postProcessor.apply(to: guided, context: bookendContext.text)
            metadata.messageCount = exchanges.count
            metadata.strategy = "singlePass:bookends-fallback"

            recordSuccess()
          } else {
            throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
          }
          #else
          throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
          #endif
        } catch {
          log.error("Bookends fallback also failed, using heuristic")
          recordFailure()
          metadata = HeuristicMetadata.generate(exchanges: exchanges)
          metadata.strategy = "heuristic-after-failure"
        }
      } else {
        // Already tried bookends, use heuristic
        metadata = HeuristicMetadata.generate(exchanges: exchanges)
        metadata.strategy = "heuristic-after-failure"
      }
    }

    let llmTime = Date().timeIntervalSince(llmStart)

    // Finalize metadata
    let storageStart = Date()
    metadata.transcriptSHA256 = try store.sha256(url: session.fileURL)
    metadata.promptVersion = currentPromptVersion
    metadata.generatorVersion = currentGeneratorVersion
    let totalTime = Date().timeIntervalSince(startTime)
    metadata.latencyMs = Int(totalTime * 1000)

    // Save to sidecar
    try await store.save(metadata, for: session.fileURL)
    let storageTime = Date().timeIntervalSince(storageStart)

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

    logMetrics(metrics, for: session.identifier)

    return metadata
  }

  // MARK: - Circuit Breaker

  private func shouldUseCircuitBreaker() -> Bool {
    let now = Date()
    // Clean up old entries outside the window
    requestWindow = requestWindow.filter { now.timeIntervalSince($0) <= windowSpan }

    let total = max(1, requestWindow.count)
    let ratio = Double(failureCount) / Double(total)

    // Open circuit if failure ratio >= 60% and we have at least 5 requests
    return ratio >= 0.6 && total >= 5
  }

  private func recordSuccess() {
    let now = Date()
    requestWindow.append(now)
    requestWindow = requestWindow.filter { now.timeIntervalSince($0) <= windowSpan }
    // Decay failure count on success, but don't reset completely
    failureCount = max(0, failureCount - 1)
  }

  private func recordFailure() {
    let now = Date()
    requestWindow.append(now)
    requestWindow = requestWindow.filter { now.timeIntervalSince($0) <= windowSpan }
    failureCount += 1

    let total = max(1, requestWindow.count)
    let ratio = Double(failureCount) / Double(total)
    if ratio >= 0.6 && total >= 5 {
      log.warning("Circuit breaker triggered: \(self.failureCount) failures out of \(total) requests (\(String(format: "%.1f%%", ratio * 100)))")
    }
  }

  // MARK: - Metrics Logging

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
