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
    let contentSha256: String
    let windowSha256: String
    let content: String
    let context: String  // Surrounding context for better summaries
    let kind: String
    let provider: String

    /// Composite key for deduplication
    var cacheKey: String {
        "\(contentSha256)|\(windowSha256)"
    }
}

/// Background actor that generates timeline summaries for cache misses
actor TimelineCacheMissGenerator {
    private let log = Logger(subsystem: "dev.contextify.timeline", category: "CacheMissGenerator")
    private let orchestrator: TranscriptOrchestrator
    private var pendingMisses: [String: CacheMiss] = [:]  // Keyed by cacheKey for de-duplication
    private var generationTask: Task<Void, Never>?
    private var isProcessing = false

    // Queue management
    private let maxQueueSize = 5000
    private let maxBatchSize = 10
    private let batchDelayNs: UInt64 = 2_000_000_000  // 2 seconds

    init(orchestrator: TranscriptOrchestrator) {
        self.orchestrator = orchestrator
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

            // Compute key inline to avoid actor isolation issues
            let key = "\(miss.contentSha256)|\(miss.windowSha256)"
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

            // Take a batch from dictionary
            let keys = Array(pendingMisses.keys.prefix(maxBatchSize))
            var batch: [CacheMiss] = []
            for key in keys {
                if let miss = pendingMisses.removeValue(forKey: key) {
                    batch.append(miss)
                }
            }

            // Reset sessions for the specific kinds and providers in this batch
            // Use dictionary to deduplicate kind+provider pairs
            var seenPairs: Set<String> = []
            for miss in batch {
                let pairKey = "\(miss.kind)|\(miss.provider)"
                if !seenPairs.contains(pairKey) {
                    seenPairs.insert(pairKey)
                    let kind = TimelineEntryKind(rawValue: miss.kind) ?? .assistant
                    let provider = TimelineSourceContext.Provider(rawValue: miss.provider)
                    if #available(macOS 26.0, *) {
                        await FoundationLLM.shared.resetSession(kind: kind, provider: provider)
                    }
                }
            }

            log.info("Processing batch of \(batch.count) cache misses (\(self.pendingMisses.count) remaining)")

            // Process batch off-main
            await processBatch(batch)

            // Rate limit: wait between batches
            if !pendingMisses.isEmpty {
                try? await Task.sleep(nanoseconds: batchDelayNs)
            }
        }

        isProcessing = false
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
            do {
                try await processMissWithRetry(miss, onSkip: { skipCount += 1 })
                successCount += 1
                successfulMisses.append(miss)
                consecutiveFailures = 0  // Reset on success
            } catch {
                let reason: String
                if let tErr = error as? TimelineError {
                    reason = tErr.userMessage
                } else {
                    reason = error.localizedDescription
                }
                log.error("Failed to generate cache after retries: \(reason, privacy: .public)")
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

        // Post notification with specific keys that were successfully updated
        if !successfulMisses.isEmpty {
            await postCacheUpdateNotification(for: successfulMisses)
        }
    }

    /// Process a single cache miss with exponential backoff retry
    private func processMissWithRetry(_ miss: CacheMiss, maxAttempts: Int = 3, onSkip: () -> Void) async throws {
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            do {
                // Check if cache already exists (race condition protection)
                // No MainActor.run needed - TranscriptOrchestrator methods are nonisolated
                let existing = try? orchestrator.getCachedTimeline(
                    contentSha256: miss.contentSha256,
                    windowSha256: miss.windowSha256
                )

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

                    log.warning("Attempt \(attempt)/\(maxAttempts) failed, retrying in \(String(format: "%.1f", delaySeconds))s: \(error.localizedDescription)")

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

        // Call FoundationLLM for dual-form generation
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
            disposition: result.disposition.rawValue
        )
    }

    /// Upsert cache entry (never clobber user_edited=1)
    private func upsertCache(miss: CacheMiss, summary: GeneratedSummary) async throws {
        // Check if entry exists and is user-edited (double-check for safety)
        let existing = try? orchestrator.getCachedTimeline(
            contentSha256: miss.contentSha256,
            windowSha256: miss.windowSha256
        )

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
}

/// Result of LLM summary generation
struct GeneratedSummary: Sendable {
    let presentForm: String
    let pastForm: String
    let selectedForm: String
    let disposition: String
}
