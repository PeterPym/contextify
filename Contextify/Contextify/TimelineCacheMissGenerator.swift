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
    // LIFO queue (newest first) with viewport-aware pruning and deduplication
    private var pendingMisses: [CacheMiss] = []  // LIFO: newest entries at front (insert at 0), prioritizes current viewport
    private var pendingKeys: Set<CacheKey> = []  // Fast deduplication lookup
    private var generationTask: Task<Void, Never>?
    private var isProcessing = false

    /// The entry ID currently being processed (for pulse animation)
    /// Note: Database uses String IDs, but timeline uses UUIDs - convert at boundary
    @MainActor private(set) var activeEntryID: UUID?

    // Queue management
    private let maxQueueSize = 5000
    private let maxBatchSize = 1  // Sequential processing (FoundationLLM limitation: one request at a time)
    private let batchDelayNs: UInt64 = 0  // No inter-item delay (FoundationLLM is local, no rate limits)

    // Stabilization delay to prevent flooding LLM with requests that get cancelled
    // Gives pruning mechanism time to cancel entries before they reach LLM
    private let stabilizationDelayMs: Int = 750

    // MARK: - Observer Infrastructure (Status Bar Support)

    // UUID-keyed dictionary for proper cleanup (continuations are structs!)
    private var queueObservers: [UUID: AsyncStream<QueueStats>.Continuation] = [:]

    // Latency tracking for data-driven ETA
    private var recentBatchLatencies: [TimeInterval] = []
    private let maxLatencyHistory = 10

    // In-flight tracking for accurate ETA
    private var inFlightCount: Int = 0
    private let entryTimeoutSeconds: TimeInterval = 15
    private let stallThresholdSeconds: TimeInterval = 30
    private var lastProgress: Date = Date()
    private var stallLogged = false

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
        pendingKeys.removeAll()
        isProcessing = false
        inFlightCount = 0

        // Clear active entry ID
        Task { @MainActor in
            activeEntryID = nil
        }

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
        let keptMisses = pendingMisses.filter { miss in
            guard let activeId = activeProjectId else { return false }
            return miss.projectId == activeId
        }

        // Rebuild deduplication set from kept misses
        pendingKeys = Set(keptMisses.map { $0.cacheKey })
        pendingMisses = keptMisses

        let removed = beforeCount - pendingMisses.count
        if removed > 0 {
            log.info("Cleared \(removed) pending misses for inactive projects (kept \(self.pendingMisses.count) for active project)")
            notifyQueueChanged()
        }
    }

    /// Prune pending queue to keep only entries visible in viewport
    /// - Parameter visibleIDs: Set of entry IDs currently visible to user
    func pruneQueue(keepOnly visibleIDs: Set<String>) async {
        let beforeCount = pendingMisses.count
        log.debug("[PRUNE] Checking queue: \(beforeCount) pending, \(visibleIDs.count) visible IDs")
        guard beforeCount > 0 else {
            log.debug("[PRUNE] Queue empty, nothing to prune")
            return
        }

        // Remove entries not in visible set (keep actively processing entry via activeEntryID check)
        let activeID = await MainActor.run { activeEntryID }
        log.debug("[PRUNE] Active entry ID: \(activeID?.uuidString.prefix(8) ?? "none")")

        pendingMisses.removeAll { miss in
            let isVisible = visibleIDs.contains(miss.entryId)
            let isActive = UUID(uuidString: miss.entryId) == activeID
            let shouldKeep = isVisible || isActive
            if !shouldKeep {
                log.debug("[PRUNE] Removing entry \(miss.entryId.prefix(8)): visible=\(isVisible), active=\(isActive)")
            }
            return !shouldKeep
        }

        // Update pendingKeys to match
        pendingKeys = Set(pendingMisses.map { CacheKey(content: $0.contentSha256, window: $0.windowSha256) })

        let prunedCount = beforeCount - pendingMisses.count
        if prunedCount > 0 {
            log.info("[PRUNE] Removed \(prunedCount) entries no longer visible (kept \(self.pendingMisses.count))")
            notifyQueueChanged()
        } else {
            log.debug("[PRUNE] No entries removed (all \(beforeCount) still visible or active)")
        }
    }

    /// Queue cache misses for background generation with de-duplication and cap
    func queueMisses(_ misses: [CacheMiss]) async {
        log.info("[GENERATOR] queueMisses() called with \(misses.count) entries")
        guard !misses.isEmpty else {
            log.info("[GENERATOR] Empty misses array, returning")
            return
        }

        // 1) Enforce referential integrity: keep only misses whose entry_id exists
        log.info("[FK-CHECK] Checking \(misses.count, privacy: .public) misses for FK safety...")
        let safeMisses = await filterFKSafe(misses)
        if safeMisses.count != misses.count {
            log.info("[FK-CHECK] Filtered: \(misses.count, privacy: .public) → \(safeMisses.count, privacy: .public) (dropped \(misses.count - safeMisses.count, privacy: .public) without entry_id in DB)")
        }
        guard !safeMisses.isEmpty else {
            log.info("[FK-CHECK] ALL \(misses.count, privacy: .public) misses skipped - no entry_id exists in transcript_entries yet")
            return
        }
        log.debug("[FK-CHECK] \(safeMisses.count) entries passed FK check")

        let beforeCount = pendingMisses.count
        var skippedDuplicates = 0
        var skippedCapacity = 0

        // Add to ordered queue with deduplication
        for miss in safeMisses {
            // Skip if queue at capacity
            if pendingMisses.count >= maxQueueSize {
                skippedCapacity += 1
                continue
            }

            // Use cached composite key for deduplication
            let key = miss.cacheKey
            if pendingKeys.contains(key) {
                skippedDuplicates += 1
            } else {
                pendingMisses.insert(miss, at: 0)  // Add to front (LIFO: newest entries processed first)
                pendingKeys.insert(key)
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

        // Ensure processing task is running
        await ensureProcessing()
    }

    /// Ensure a processing task is running (idempotent; restarts a stuck handle)
    private func ensureProcessing() async {
        // Spawn if missing
        if generationTask == nil {
            let count = pendingMisses.count
            log.debug("Spawning processing task (pending: \(count))")
            generationTask = Task { await self.processQueue() }  // Strong capture by design
            return
        }
        // Defensive: if we have work queued but not processing, restart
        if !isProcessing && !pendingMisses.isEmpty {
            log.warning("Processing handle exists but not active; restarting worker (pending: \(self.pendingMisses.count))")
            generationTask?.cancel()
            generationTask = Task { await self.processQueue() }
        }
    }

    // MARK: - FK preflight

    /// Drop misses that would violate `timeline_cache(entry_id) → timeline_entries(id)`.
    /// Returns only misses whose entry_id already exists in timeline_entries table.
    private func filterFKSafe(_ misses: [CacheMiss]) async -> [CacheMiss] {
        guard !misses.isEmpty else { return [] }

        // Collect unique entry IDs to check
        let ids = Array(Set(misses.map { $0.entryId }))

        do {
            // Query which IDs exist in timeline_entries using orchestrator
            let existing = try orchestrator.existingEntryIds(ids)

            // Fast path: all IDs exist
            if existing.count == ids.count { return misses }

            // Filter to only misses with existing entry_id
            let filtered = misses.filter { existing.contains($0.entryId) }
            if filtered.count != misses.count {
                let dropped = misses.count - filtered.count
                log.debug("filterFKSafe: dropped \(dropped) misses without timeline_entries row (kept \(filtered.count))")
            }
            return filtered
        } catch {
            log.error("filterFKSafe read failed: \(String(describing: error), privacy: .public)")
            // On failure, be conservative: skip to avoid FK exceptions
            return []
        }
    }

    /// Background processing loop
    private func processQueue() async {
        log.debug("processQueue: start (pending: \(self.pendingMisses.count))")
        while !pendingMisses.isEmpty {
            if Task.isCancelled { break }
            if Date().timeIntervalSince(self.lastProgress) > stallThresholdSeconds && !self.stallLogged {
                log.warning("[STATUSBAR-SUMM-STALL] pending=\(self.pendingMisses.count + self.inFlightCount) elapsed=\(Int(Date().timeIntervalSince(self.lastProgress)))s")
                self.stallLogged = true
            }
            isProcessing = true
            notifyQueueChanged()  // Notify that processing started

            // Take next item from front of queue (LIFO: newest entries processed first)
            // Note: maxBatchSize is always 1 due to FoundationLLM sequential processing limitation
            let batchSize = min(maxBatchSize, pendingMisses.count)
            let batch = Array(pendingMisses.prefix(batchSize))
            pendingMisses.removeFirst(batchSize)

            // Remove from deduplication set
            for miss in batch {
                pendingKeys.remove(miss.cacheKey)
            }
            inFlightCount = batch.count

            // Set active entry ID for pulse animation (first item in batch)
            // Convert String ID from database to UUID for timeline comparison
            if let firstMiss = batch.first,
               let uuid = UUID(uuidString: firstMiss.entryId) {
                await MainActor.run {
                    activeEntryID = uuid
                }
            }

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

            // Update active entry ID to next in queue (or nil if empty)
            // Convert String ID to UUID for timeline comparison
            let nextEntryID: UUID? = {
                guard let entryId = pendingMisses.first?.entryId else { return nil }
                return UUID(uuidString: entryId)
            }()
            await MainActor.run {
                activeEntryID = nextEntryID
            }

            // Rate limit: wait between batches
            if !pendingMisses.isEmpty {
                try? await Task.sleep(nanoseconds: batchDelayNs)
            }
        }

        isProcessing = false

        // Clear active entry ID when queue is empty
        await MainActor.run {
            activeEntryID = nil
        }

        notifyQueueChanged()  // Notify that processing finished
        generationTask = nil
        log.info("Cache miss generation queue empty")
        markProgress()
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

            // Stabilization delay before sending to LLM to allow pruning to catch scroll-aways
            // This prevents flooding Apple Intelligence with requests that will be cancelled
            if self.stabilizationDelayMs > 0 {
                log.debug("[STAB-DELAY] Waiting \(self.stabilizationDelayMs)ms before sending to LLM...")
                try? await Task.sleep(nanoseconds: UInt64(self.stabilizationDelayMs) * 1_000_000)

                // Check cancellation again after delay (user may have scrolled away)
                if Task.isCancelled {
                    log.info("[STAB-DELAY] Cancelled during \(self.stabilizationDelayMs)ms delay (processed \(successCount)/\(batch.count))")
                    break
                }
                log.debug("[STAB-DELAY] Delay complete, proceeding to processing")
            } else {
                log.debug("[STAB-DELAY] Stabilization delay disabled (would wait \(750)ms if enabled)")
            }

            let entryStart = Date()
            log.info("[SUMM-GENERATOR-START] entry=\(miss.entryId, privacy: .public) provider=\(miss.provider, privacy: .public)")
            do {
                let result = try await runWithTimeout(seconds: entryTimeoutSeconds) {
                    try await self.processMissWithRetry(miss)
                }

                switch result {
                case .generated:
                    successCount += 1
                    successfulMisses.append(miss)
                    consecutiveFailures = 0  // Reset on success
                    trackSuccess()  // Track success for error auto-clearing
                    let elapsedMs = Int(Date().timeIntervalSince(entryStart) * 1000)
                    log.info("[SUMM-GENERATOR-DONE] entry=\(miss.entryId, privacy: .public) status=success elapsed_ms=\(elapsedMs, privacy: .public)")
                    markProgress()

                    // Post immediate UI update for this entry (don't wait for batch to complete)
                    await postCacheUpdateNotification(for: [miss])

                case .skipped:
                    skipCount += 1
                    let elapsedMs = Int(Date().timeIntervalSince(entryStart) * 1000)
                    log.info("[SUMM-GENERATOR-DONE] entry=\(miss.entryId, privacy: .public) status=skipped elapsed_ms=\(elapsedMs, privacy: .public)")
                    markProgress()

                case .tombstone(let reason):
                    // Tombstone written - counts as "handled" but not success
                    // Don't increment errorCount since trackError was already called where appropriate
                    let elapsedMs = Int(Date().timeIntervalSince(entryStart) * 1000)
                    log.info("[SUMM-GENERATOR-DONE] entry=\(miss.entryId, privacy: .public) status=tombstone reason=\(reason, privacy: .public) elapsed_ms=\(elapsedMs, privacy: .public)")
                    markProgress()
                }
            } catch is SummaryTimeoutError {
                let elapsedMs = Int(Date().timeIntervalSince(entryStart) * 1000)
                log.error("[SUMM-GENERATOR-TIMEOUT] entry=\(miss.entryId, privacy: .public) provider=\(miss.provider, privacy: .public) elapsed_ms=\(elapsedMs, privacy: .public)")
                trackError(reason: "timeout")
                errorCount += 1
                consecutiveFailures += 1
                markProgress()
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
                markProgress()

                // Circuit breaker: stop batch on sustained failures
                // NOTE: With maxBatchSize=1, this only breaks out of the current single-entry batch,
                // then processQueue() immediately grabs the next entry. The circuit breaker is
                // effectively disabled. It would only be useful with maxBatchSize > 1 to skip the
                // remaining entries in a multi-entry batch.
                // TODO: If batch size stays at 1, consider removing this logic or making it stop
                // the entire processQueue() loop instead of just the batch loop.
                if maxBatchSize > 1 && consecutiveFailures >= 5 {
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
    private func processMissWithRetry(_ miss: CacheMiss, maxAttempts: Int = 3) async throws -> MissProcessingResult {
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
                    return .skipped
                }

                // Skip if already fresh (same generator signature) - P0.10
                if let existing = existing,
                   existing.userEdited == 0,
                   existing.generatorSignature == timelineGeneratorSignature() {
                    log.debug("Skipping - cache already fresh with matching signature")
                    return .skipped
                }

                // Generate summary using LLM
                let summary = try await generateSummary(for: miss)

                // Upsert to cache (respecting user_edited flag)
                try await upsertCache(miss: miss, summary: summary)

                // Success!
                return .generated
            } catch let timelineError as TimelineError {
                // Check if it's a guardrail violation
                if case .guardrailViolation = timelineError {
                    // Safety guardrail triggered - don't retry, just mark as filtered
                    log.info("Apple Intelligence filtered entry \(miss.entryId.prefix(8)) - marking as safety-filtered")

                    // Generate fallback summary (truncated content preview)
                    let fallbackSummary: String
                    if miss.content.isEmpty {
                        fallbackSummary = "[No content]"
                    } else {
                        fallbackSummary = String(miss.content.prefix(100)) + (miss.content.count > 100 ? "…" : "")
                    }

                    // Save special cache entry indicating safety filtering
                    let filteredCache = TimelineCache(
                        contentSha256: miss.contentSha256,
                        windowSha256: miss.windowSha256,
                        entryId: miss.entryId,
                        generatorSignature: timelineGeneratorSignature(),
                        disposition: "safety-filtered",  // Special marker for UI
                        presentForm: fallbackSummary,
                        pastForm: fallbackSummary,
                        selectedForm: "present",
                        generatedAt: Int(Date().timeIntervalSince1970),
                        userEdited: 0
                    )

                    try orchestrator.saveCachedTimeline(filteredCache)

                    // Post immediate UI update notification
                    await postCacheUpdateNotification(for: [miss])

                    // Treat as success - no retry needed
                    return .generated
                }

                // Check for other permanent failures - write tombstone and don't retry
                if case .contextOverflow = timelineError {
                    log.error("Context overflow for entry \(miss.entryId.prefix(8)) - writing tombstone")
                    try await writeErrorTombstone(miss: miss, errorType: "overflow", error: timelineError)
                    trackError(reason: timelineError.userMessage)
                    return .tombstone(reason: "overflow")
                }

                if case .decodingFailure = timelineError {
                    log.error("Decoding failure for entry \(miss.entryId.prefix(8)) - writing tombstone")
                    try await writeErrorTombstone(miss: miss, errorType: "decoding", error: timelineError)
                    // Don't trackError - show (i) icon but not status bar error
                    return .tombstone(reason: "decoding")
                }

                if case .validationFailure = timelineError {
                    log.info("Validation failure for entry \(miss.entryId.prefix(8)) - writing tombstone")
                    try await writeErrorTombstone(miss: miss, errorType: "validation", error: timelineError)
                    // Don't trackError - show (i) icon but not status bar error
                    return .tombstone(reason: "validation")
                }

                if case .unexpected = timelineError {
                    log.error("Unexpected error for entry \(miss.entryId.prefix(8)) - writing tombstone")
                    try await writeErrorTombstone(miss: miss, errorType: "unexpected", error: timelineError)
                    trackError(reason: timelineError.userMessage)
                    return .tombstone(reason: "unexpected")
                }

                if case .databaseError = timelineError {
                    log.error("Database error for entry \(miss.entryId.prefix(8)) - writing tombstone")
                    try await writeErrorTombstone(miss: miss, errorType: "database", error: timelineError)
                    trackError(reason: timelineError.userMessage)
                    return .tombstone(reason: "database")
                }

                // Transient errors (timeout, unavailable, cancelled) - continue to retry logic
                lastError = timelineError
                attempt += 1

                if attempt < maxAttempts {
                        // Exponential backoff with jitter: base 2^attempt seconds
                        let baseDelay = pow(2.0, Double(attempt))
                        let jitter = Double.random(in: 0...0.3) * baseDelay
                        let delaySeconds = baseDelay + jitter

                        log.warning("Attempt \(attempt, privacy: .public)/\(maxAttempts, privacy: .public) failed, retrying in \(String(format: "%.1f", delaySeconds), privacy: .public)s: \(timelineError.localizedDescription, privacy: .public)")

                        try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    }
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

        // CXT-13: Fail-fast if Apple Intelligence is unavailable
        // Prevents project switch lag from waiting through retries when AI is down
        let healthStatus = await LLMHealthCheck.shared.checkHealth()
        if case .unavailable(let reason) = healthStatus {
            if case .healthCheckCancelled = reason {
                log.debug("[HEALTH-CHECK] Health check cancelled, allowing LLM call to proceed (not a real failure)")
            } else {
                throw TimelineError.llmUnavailable(reason: "Apple Intelligence unavailable: \(reason.userFacingMessage)")
            }
        }

        // Check cancellation RIGHT BEFORE calling LLM to avoid wasted compute
        // The stabilization delay above gives pruning time to cancel obsolete requests
        log.debug("[CANCEL-CHECK] About to send entry \(miss.entryId.prefix(8)) to LLM, checking cancellation...")
        do {
            try Task.checkCancellation()
            log.debug("[CANCEL-CHECK] Not cancelled, proceeding to LLM")
        } catch {
            log.info("[CANCEL-CHECK] Task cancelled before LLM call for entry \(miss.entryId.prefix(8)) - saved compute!")
            throw error
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

        // Log entry being summarized (helps trace queued flag behavior)
        log.debug("[CACHE-UPSERT] Saving summary for entry=\(miss.entryId.prefix(8), privacy: .public) content_sha256=\(miss.contentSha256.prefix(12), privacy: .public) window_sha256=\(miss.windowSha256.prefix(12), privacy: .public)")
        log.debug("[CACHE-UPSERT]   content preview: \(miss.content.prefix(60), privacy: .public)...")
        log.debug("[CACHE-UPSERT]   summary: \(summary.selectedForm.prefix(60), privacy: .public)...")

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

        log.debug("[CACHE-UPSERT] Successfully saved summary for entry=\(miss.entryId.prefix(8), privacy: .public)")
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

    /// Check if an entry is queued for generation
    func isEntryQueued(_ entryId: String) -> Bool {
        return pendingMisses.contains(where: { $0.entryId == entryId })
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

    // MARK: - Error Tombstone Writing

    /// Write a tombstone for permanent failures to prevent infinite viewport retries
    /// Similar to guardrailViolation handling, but for other non-retryable errors
    private func writeErrorTombstone(miss: CacheMiss, errorType: String, error: TimelineError) async throws {
        log.info("Writing error tombstone for entry \(miss.entryId.prefix(8)) - type: \(errorType)")

        // Generate fallback summary (truncated content preview)
        let fallbackSummary: String
        if miss.content.isEmpty {
            fallbackSummary = "[No content]"
        } else {
            fallbackSummary = String(miss.content.prefix(100)) + (miss.content.count > 100 ? "…" : "")
        }

        // Write tombstone to cache with error disposition
        let tombstone = TimelineCache(
            contentSha256: miss.contentSha256,
            windowSha256: miss.windowSha256,
            entryId: miss.entryId,
            generatorSignature: timelineGeneratorSignature(),
            disposition: "error-\(errorType)",  // Marks as permanent failure
            presentForm: fallbackSummary,
            pastForm: fallbackSummary,
            selectedForm: "present",
            generatedAt: Int(Date().timeIntervalSince1970),
            userEdited: 0
        )

        try orchestrator.saveCachedTimeline(tombstone)

        // Post immediate UI update notification
        await postCacheUpdateNotification(for: [miss])

        log.info("Error tombstone written for \(miss.entryId.prefix(8)) - will not retry")
    }
}

private struct SummaryTimeoutError: Error, Sendable {}

private enum MissProcessingResult {
    case generated
    case skipped
    case tombstone(reason: String)  // Permanent failure, wrote error tombstone
}

extension TimelineCacheMissGenerator {
    private func runWithTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                return try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SummaryTimeoutError()
            }
            guard let result = try await group.next() else {
                throw SummaryTimeoutError()
            }
            group.cancelAll()
            return result
        }
    }

    private func markProgress() {
        lastProgress = Date()
        stallLogged = false
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
