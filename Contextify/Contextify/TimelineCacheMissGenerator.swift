//
//  TimelineCacheMissGenerator.swift
//  Contextify
//
//  Background pipeline for generating timeline cache entries for misses
//

import Foundation
import OSLog
import ContextifyCore

/// Represents a cache miss that needs LLM generation
struct CacheMiss: Sendable {
    let entryId: String
    let projectId: String  // SQL project ID - for cancellation when switching projects
    let contentSha256: String
    let windowSha256: String
    let content: String
    let context: String  // Surrounding context for better summaries
    let kind: String
    let provider: String

    /// Composite key for deduplication (returns struct for type safety)
    nonisolated var cacheKey: CacheKey {
        CacheKey(content: contentSha256, window: windowSha256)
    }
}

/// Background actor that generates timeline summaries for cache misses
actor TimelineCacheMissGenerator {
    private let log = Logger(subsystem: "dev.contextify.timeline", category: "CacheMissGenerator")
    private let orchestrator: TranscriptOrchestrator
    private var pendingMisses: [CacheKey: CacheMiss] = [:]  // Keyed by CacheKey for de-duplication
    private var generationTask: Task<Void, Never>?
    private var isProcessing = false

    // Queue management
    private let maxQueueSize = 5000
    private let maxBatchSize = 10
    private let batchDelayNs: UInt64 = 2_000_000_000  // 2 seconds

    // MARK: - Observer Infrastructure (Status Bar Support)

    // UUID-keyed dictionary for proper cleanup (continuations are structs!)
    private var queueObservers: [UUID: AsyncStream<QueueStats>.Continuation] = [:]

    // Latency tracking for data-driven ETA
    private var recentBatchLatencies: [TimeInterval] = []
    private let maxLatencyHistory = 10

    // In-flight tracking for accurate ETA
    private var inFlightCount: Int = 0

    // Error tracking (5-minute sliding window with auto-clear on success)
    private var recentErrors: [(timestamp: Date, reason: String)] = []
    private let errorWindowSeconds: TimeInterval = 300  // 5 minutes
    private var consecutiveSuccesses: Int = 0
    private let successClearThreshold = 3  // Clear 1 error after 3 successes

    init(orchestrator: TranscriptOrchestrator) {
        self.orchestrator = orchestrator
    }

    /// Shutdown generator and cancel any in-flight processing
    func shutdown() {
        log.info("Shutting down cache miss generator (pending: \(self.pendingMisses.count))")
        generationTask?.cancel()
        generationTask = nil
        pendingMisses.removeAll()
        isProcessing = false
        inFlightCount = 0

        // Notify observers of shutdown
        notifyQueueChanged()

        // Close all observer streams
        for (_, continuation) in queueObservers {
            continuation.finish()
        }
        queueObservers.removeAll()
    }

    /// Clear pending misses for projects that are not currently active
    /// Call this when user switches projects to prevent wasting resources on invisible entries
    func clearPendingMisses(exceptProjectId activeProjectId: String?) {
        let beforeCount = pendingMisses.count

        // Remove misses that don't match the active project
        pendingMisses = pendingMisses.filter { _, miss in
            guard let activeId = activeProjectId else { return false }
            return miss.projectId == activeId
        }

        let removed = beforeCount - pendingMisses.count
        if removed > 0 {
            log.info("Cleared \(removed) pending misses for inactive projects (kept \(self.pendingMisses.count) for active project)")
            notifyQueueChanged()
        }
    }

    /// Queue cache misses for background generation with de-duplication and cap
    func queueMisses(_ misses: [CacheMiss]) {
        guard !misses.isEmpty else { return }

        let beforeCount = pendingMisses.count
        var skippedDuplicates = 0
        var skippedCapacity = 0

        // Add to dictionary (automatic de-dup by cacheKey)
        for miss in misses {
            // Skip if queue at capacity
            if pendingMisses.count >= maxQueueSize {
                skippedCapacity += 1
                continue
            }

            // Use cached composite key for deduplication
            let key = miss.cacheKey
            if pendingMisses[key] != nil {
                skippedDuplicates += 1
            } else {
                pendingMisses[key] = miss
            }
        }

        let added = pendingMisses.count - beforeCount
        if skippedCapacity > 0 {
            log.warning("Cache miss queue at capacity (\(self.maxQueueSize)), dropped \(skippedCapacity) new misses")
        }
        if skippedDuplicates > 0 {
            log.debug("Skipped \(skippedDuplicates) duplicate cache misses")
        }
        log.info("Queued \(added) cache misses (total pending: \(self.pendingMisses.count))")

        // Notify observers of queue change
        notifyQueueChanged()

        // Start processing if not already running
        if generationTask == nil {
            generationTask = Task { [weak self] in
                await self?.processQueue()
            }
        }
    }

    /// Background processing loop
    private func processQueue() async {
        while !pendingMisses.isEmpty {
            if Task.isCancelled { break }
            isProcessing = true
            notifyQueueChanged()  // Notify that processing started

            // Take a batch from dictionary
            let keys = Array(pendingMisses.keys.prefix(maxBatchSize))
            var batch: [CacheMiss] = []
            for key in keys {
                if let miss = pendingMisses.removeValue(forKey: key) {
                    batch.append(miss)
                }
            }
            inFlightCount = batch.count

            // Reset sessions for the specific kinds and providers in this batch
            // Use struct-based set to deduplicate kind+provider pairs (no delimiter collisions)
            struct KindProviderPair: Hashable {
                let kind: String
                let provider: String
            }
            var seenPairs: Set<KindProviderPair> = []
            for miss in batch {
                let pairKey = KindProviderPair(kind: miss.kind, provider: miss.provider)
                if !seenPairs.contains(pairKey) {
                    seenPairs.insert(pairKey)
                    let kind = TimelineEntryKind(rawValue: miss.kind) ?? .assistant
                    let provider = TimelineSourceContext.Provider(rawValue: miss.provider)
                    if #available(macOS 26.0, *) {
                        await FoundationLLM.shared.resetSession(kind: kind, provider: provider)
                    }
                }
            }

            // Log which distinct session types were reset
            if !seenPairs.isEmpty {
                let descriptions = seenPairs.map { "\($0.kind)/\($0.provider)" }.sorted()
                log.info("Batch reset \(seenPairs.count) distinct session types: \(descriptions.joined(separator: ", "))")
            }

            log.info("Processing batch of \(batch.count) cache misses (\(self.pendingMisses.count) remaining)")

            // Process batch off-main and track latency
            let startTime = Date()
            await processBatch(batch)
            let latency = Date().timeIntervalSince(startTime)
            trackBatchLatency(latency)
            inFlightCount = 0

            // Rate limit: wait between batches
            if !pendingMisses.isEmpty {
                try? await Task.sleep(nanoseconds: batchDelayNs)
            }
        }

        isProcessing = false
        notifyQueueChanged()  // Notify that processing finished
        generationTask = nil
        log.info("Cache miss generation queue empty")
    }

    /// Process a batch of cache misses with retry logic and circuit breaker
    private func processBatch(_ batch: [CacheMiss]) async {
        let startTime = Date()
        var successCount = 0
        var skipCount = 0
        var errorCount = 0
        var successfulMisses: [CacheMiss] = []
        var consecutiveFailures = 0

        for miss in batch {
            // Check for cancellation INSIDE the batch loop (CXT-7)
            // This allows rapid cancellation during project switches without waiting for entire batch
            if Task.isCancelled {
                log.info("Batch processing cancelled mid-batch (processed \(successCount)/\(batch.count))")
                break
            }

            do {
                try await processMissWithRetry(miss, onSkip: { skipCount += 1 })
                successCount += 1
                successfulMisses.append(miss)
                consecutiveFailures = 0  // Reset on success
                trackSuccess()  // Track success for error auto-clearing

                // Post immediate UI update for this entry (don't wait for batch to complete)
                await postCacheUpdateNotification(for: [miss])
            } catch {
                let reason: String
                if let tErr = error as? TimelineError {
                    reason = tErr.userMessage
                } else {
                    reason = error.localizedDescription
                }
                log.error("Failed to generate cache after retries: \(reason, privacy: .public)")
                trackError(reason: reason)  // Track error for status bar
                errorCount += 1
                consecutiveFailures += 1

                // Circuit breaker: stop batch on sustained failures
                if consecutiveFailures >= 5 {
                    log.error("Circuit breaker: stopping batch after \(consecutiveFailures) consecutive failures")
                    break
                }
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        log.info("Batch complete: \(successCount) generated, \(skipCount) skipped, \(errorCount) errors in \(Int(elapsed * 1000))ms")

        // UI updates are now posted immediately after each entry (line 160)
        // No batch-end notification needed
    }

    /// Process a single cache miss with exponential backoff retry
    private func processMissWithRetry(_ miss: CacheMiss, maxAttempts: Int = 3, onSkip: () -> Void) async throws {
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            do {
                // Check if cache already exists (race condition protection)
                // No MainActor.run needed - TranscriptOrchestrator methods are nonisolated
                let key = CacheKey(content: miss.contentSha256, window: miss.windowSha256)
                let existing = try? orchestrator.getCachedTimeline(key: key)

                // Skip if user edited
                if let existing = existing, existing.userEdited == 1 {
                    log.debug("Skipping - user edited entry exists")
                    onSkip()
                    return
                }

                // Skip if already fresh (same generator signature) - P0.10
                if let existing = existing,
                   existing.userEdited == 0,
                   existing.generatorSignature == timelineGeneratorSignature() {
                    log.debug("Skipping - cache already fresh with matching signature")
                    onSkip()
                    return
                }

                // Generate summary using LLM
                let summary = try await generateSummary(for: miss)

                // Upsert to cache (respecting user_edited flag)
                try await upsertCache(miss: miss, summary: summary)

                // Success!
                return
            } catch {
                lastError = error
                attempt += 1

                if attempt < maxAttempts {
                    // Exponential backoff with jitter: base 2^attempt seconds
                    let baseDelay = pow(2.0, Double(attempt))
                    let jitter = Double.random(in: 0...0.3) * baseDelay
                    let delaySeconds = baseDelay + jitter

                    log.warning("Attempt \(attempt, privacy: .public)/\(maxAttempts, privacy: .public) failed, retrying in \(String(format: "%.1f", delaySeconds), privacy: .public)s: \(error.localizedDescription, privacy: .public)")

                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                }
            }
        }

        // All attempts exhausted - P0.11: Preserve root error
        guard let error = lastError else {
            fatalError("Retry exhausted without capturing error")
        }
        throw error
    }

    /// Generate summary for a cache miss using LLM
    private func generateSummary(for miss: CacheMiss) async throws -> GeneratedSummary {
        // Parse kind and provider
        let kind = TimelineEntryKind(rawValue: miss.kind) ?? .assistant
        let provider = TimelineSourceContext.Provider(rawValue: miss.provider) ?? .other

        // Call FoundationLLM for dual-form generation (requires macOS 26+)
        guard #available(macOS 26.0, *) else {
            throw TimelineError.llmUnavailable(reason: "FoundationModels requires macOS 26.0+")
        }

        let llm = FoundationLLM.shared
        let result = try await llm.summarizeTimelineWithForms(
            kind: kind,
            text: miss.content,
            provider: provider,
            contextWindow: [] // TODO: Add prev1/prev2 context if needed
        )

        // Map to GeneratedSummary
        return GeneratedSummary(
            presentForm: result.presentForm,
            pastForm: result.pastForm,
            selectedForm: result.disposition == .completion ? "past" : "present",
            disposition: result.disposition.rawValue,
            isDirective: result.isDirective,
            isCompletion: result.isCompletion
        )
    }

    /// Upsert cache entry (never clobber user_edited=1)
    private func upsertCache(miss: CacheMiss, summary: GeneratedSummary) async throws {
        // Check if entry exists and is user-edited (double-check for safety)
        let key = CacheKey(content: miss.contentSha256, window: miss.windowSha256)
        let existing = try? orchestrator.getCachedTimeline(key: key)

        if let existing = existing, existing.userEdited == 1 {
            log.warning("Refusing to overwrite user-edited cache entry")
            return
        }

        // Create TimelineCache object with entryId from miss
        let now = Int(Date().timeIntervalSince1970)
        let cache = TimelineCache(
            contentSha256: miss.contentSha256,
            windowSha256: miss.windowSha256,
            entryId: miss.entryId,
            generatorSignature: timelineGeneratorSignature(),
            disposition: summary.disposition,
            presentForm: summary.presentForm,
            pastForm: summary.pastForm,
            selectedForm: summary.selectedForm,
            generatedAt: now,
            userEdited: 0
        )

        // Save to database (no MainActor.run needed)
        try orchestrator.saveCachedTimeline(cache)
    }

    /// Post notification to trigger lightweight UI refresh with specific keys
    private func postCacheUpdateNotification(for successfulMisses: [CacheMiss]) async {
        // Convert to CacheKey for type-safe notification
        let keys = successfulMisses.map { miss in
            CacheKey(content: miss.contentSha256, window: miss.windowSha256)
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: .timelineCacheUpdated,
                object: nil,
                userInfo: ["keys": keys]
            )
        }
    }

    /// Get current queue status
    func getStatus() -> (pending: Int, isProcessing: Bool) {
        return (pendingMisses.count, isProcessing)
    }

    // MARK: - Public Observation API

    /// Subscribe to queue state changes
    /// Returns: AsyncStream that yields QueueStats on every state transition
    nonisolated func observeQueue() -> AsyncStream<QueueStats> {
        let observerId = UUID()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // Register observer (need to access actor-isolated state)
            Task { [weak self] in
                guard let self else { return }
                await self.registerObserver(id: observerId, continuation: continuation)
            }

            // Cleanup on termination (no capture of continuation itself!)
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeObserver(id: observerId) }
            }
        }
    }

    /// Register observer (actor-isolated helper)
    private func registerObserver(id: UUID, continuation: AsyncStream<QueueStats>.Continuation) {
        queueObservers[id] = continuation

        // Send current state immediately
        let stats = makeQueueStats()
        continuation.yield(stats)
    }

    /// Remove observer by UUID (called on stream termination)
    private func removeObserver(id: UUID) {
        queueObservers.removeValue(forKey: id)
    }

    // MARK: - Notification

    /// Notify all active observers of queue state changes
    private func notifyQueueChanged() {
        let stats = makeQueueStats()

        // Yield to all observers (finished ones are already removed)
        for (_, continuation) in queueObservers {
            continuation.yield(stats)
        }
    }

    // MARK: - Stats Builder

    /// Build QueueStats with actual latency and error data
    private func makeQueueStats() -> QueueStats {
        // Data-driven ETA calculation
        // Default: assume 2.5s per item (25s per 10-item batch) if no history
        let avgBatchLatency = recentBatchLatencies.isEmpty ? (2.5 * Double(maxBatchSize)) :
                              recentBatchLatencies.reduce(0, +) / Double(recentBatchLatencies.count)

        // Accurate ETA using in-flight count
        let avgSecondsPerItem = avgBatchLatency / Double(maxBatchSize)
        let fullBatchesRemaining = max(0, pendingMisses.count / maxBatchSize)

        // ETA for items currently being processed
        let partialBatchETA = Double(inFlightCount) * avgSecondsPerItem
        let fullBatchETA = Double(fullBatchesRemaining) * avgBatchLatency

        let estimatedSeconds = Int(ceil(partialBatchETA + fullBatchETA))

        // Count recent errors (last 5 minutes)
        let cutoff = Date().addingTimeInterval(-errorWindowSeconds)
        let errorCount = recentErrors.filter { $0.timestamp > cutoff }.count

        // Get most recent error reason
        let topError = recentErrors.last?.reason

        return QueueStats(
            pending: pendingMisses.count,
            isProcessing: isProcessing,
            currentBatchSize: isProcessing ? maxBatchSize : 0,
            estimatedSecondsRemaining: estimatedSeconds,
            recentErrorCount: errorCount,
            topErrorReason: topError
        )
    }

    // MARK: - Latency Tracking

    /// Track batch completion time for ETA calculation
    private func trackBatchLatency(_ latency: TimeInterval) {
        recentBatchLatencies.append(latency)
        if recentBatchLatencies.count > maxLatencyHistory {
            recentBatchLatencies.removeFirst()
        }
    }

    // MARK: - Error Tracking

    /// Record error for recent error count display
    private func trackError(reason: String) {
        let now = Date()
        recentErrors.append((timestamp: now, reason: reason))
        consecutiveSuccesses = 0  // Reset success counter on error

        // Prune errors outside the time window
        let cutoff = now.addingTimeInterval(-errorWindowSeconds)
        recentErrors.removeAll { $0.timestamp < cutoff }

        // Hard cap to prevent unbounded growth
        if recentErrors.count > 50 {
            recentErrors.removeFirst(recentErrors.count - 50)
        }
    }

    /// Track successful generation and auto-clear errors after threshold
    private func trackSuccess() {
        guard !recentErrors.isEmpty else { return }  // No errors to clear

        consecutiveSuccesses += 1

        // Auto-clear one error after threshold consecutive successes
        if consecutiveSuccesses >= successClearThreshold {
            // Remove oldest error (FIFO - first in, first out)
            if !recentErrors.isEmpty {
                recentErrors.removeFirst()
                log.debug("Auto-cleared 1 error after \(self.consecutiveSuccesses) consecutive successes")
            }
            consecutiveSuccesses = 0  // Reset counter
        }
    }
}

/// Result of LLM summary generation
struct GeneratedSummary: Sendable {
    let presentForm: String
    let pastForm: String
    let selectedForm: String
    let disposition: String
    let isDirective: Bool
    let isCompletion: Bool
}

// MARK: - Queue Stats Model

/// Sendable stats snapshot for status bar
struct QueueStats: Sendable, Equatable {
    let pending: Int
    let isProcessing: Bool
    let currentBatchSize: Int
    let estimatedSecondsRemaining: Int
    let recentErrorCount: Int
    let topErrorReason: String?
}
