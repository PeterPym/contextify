import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

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

  // Circuit breaker state
  private var failureCount = 0
  private var lastFailureTime: Date?
  private let circuitBreakerWindow: TimeInterval = 300 // 5 minutes
  private let circuitBreakerThreshold = 5

  // Concurrency control
  private var activeTasks: [URL: Task<TranscriptMetadata, Error>] = [:]
  private let maxConcurrentLLMCalls = 2
  private var currentLLMCalls = 0

  // MARK: - Public API

  /// Ensures metadata exists for a session, generating if needed
  func ensureMetadata(
    for session: TranscriptSession,
    forceRegenerate: Bool = false
  ) async throws -> TranscriptMetadata {
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
    let cachedMetadata: TranscriptMetadata? = await MainActor.run {
      if !forceRegenerate,
         let cached = try? store.load(for: session.fileURL),
         store.isFresh(
          cached,
          for: session.fileURL,
          promptVersion: currentPromptVersion,
          generatorVersion: currentGeneratorVersion
         ) {
        return cached
      }
      return nil
    }

    if let cached = cachedMetadata {
      log.info("Using cached metadata for \(session.identifier, privacy: .public)")
      return cached
    }

    log.info("Generating metadata for \(session.identifier, privacy: .public)")

    // Parse exchanges
    let parseStart = Date()
    let exchanges = try await MainActor.run {
      try parser.parseExchanges(url: session.fileURL)
    }
    let parseTime = Date().timeIntervalSince(parseStart)

    // Handle very short transcripts with heuristic
    if exchanges.count < 3 {
      log.info("Very short transcript (\(exchanges.count) exchanges), using heuristic")
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      try await store.save(metadata, for: session.fileURL)
      return metadata
    }

    // Select strategy
    let strategy: GenerationStrategy = exchanges.count <= 60 ? .full : .adaptive

    // Check circuit breaker
    if shouldUseCircuitBreaker() {
      log.warning("Circuit breaker active, using heuristic fallback")
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      try await store.save(metadata, for: session.fileURL)
      return metadata
    }

    // Build context
    let samplingStart = Date()
    let context = try await MainActor.run {
      try builder.build(exchanges: exchanges, strategy: strategy)
    }
    let samplingTime = Date().timeIntervalSince(samplingStart)

    // Call LLM (with fallback to bookends on failure)
    var metadata: TranscriptMetadata
    let llmStart = Date()

    do {
      // Wait for LLM slot
      await waitForLLMSlot()
      defer { releaseLLMSlot() }

      #if canImport(FoundationModels)
      if #available(macOS 26, *) {
        let guided = try await llm.singlePass(
          context: context.text,
          sampledCount: context.sampledCount,
          totalCount: exchanges.count
        )

        // Post-process
        metadata = await MainActor.run {
          postProcessor.apply(to: guided, context: context.text)
        }
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
        let bookendContext = try await MainActor.run {
          try builder.build(exchanges: exchanges, strategy: .bookends)
        }

        do {
          await waitForLLMSlot()
          defer { releaseLLMSlot() }

          #if canImport(FoundationModels)
          if #available(macOS 26, *) {
            let guided = try await llm.singlePass(
              context: bookendContext.text,
              sampledCount: bookendContext.sampledCount,
              totalCount: exchanges.count
            )

            metadata = await MainActor.run {
              postProcessor.apply(to: guided, context: bookendContext.text)
            }
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
    metadata.transcriptSHA256 = try await MainActor.run {
      try store.sha256(url: session.fileURL)
    }
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
    guard let lastFailure = lastFailureTime else {
      return false
    }

    let elapsed = Date().timeIntervalSince(lastFailure)
    if elapsed > circuitBreakerWindow {
      // Window expired, reset
      failureCount = 0
      lastFailureTime = nil
      return false
    }

    return failureCount >= circuitBreakerThreshold
  }

  private func recordSuccess() {
    failureCount = 0
    lastFailureTime = nil
  }

  private func recordFailure() {
    failureCount += 1
    lastFailureTime = Date()

    if failureCount >= circuitBreakerThreshold {
      log.warning("Circuit breaker triggered after \(self.failureCount) failures")
    }
  }

  // MARK: - Concurrency Control

  private func waitForLLMSlot() async {
    while currentLLMCalls >= maxConcurrentLLMCalls {
      try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
    currentLLMCalls += 1
  }

  private func releaseLLMSlot() {
    currentLLMCalls -= 1
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
