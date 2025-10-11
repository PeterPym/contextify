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
    let contentSha256: String
    let windowSha256: String
    let content: String
    let context: String  // Surrounding context for better summaries
}

/// Background actor that generates timeline summaries for cache misses
actor TimelineCacheMissGenerator {
    private let log = Logger(subsystem: "dev.contextify.timeline", category: "CacheMissGenerator")
    private let orchestrator: TranscriptOrchestrator
    private var pendingMisses: [CacheMiss] = []
    private var generationTask: Task<Void, Never>?
    private var isProcessing = false

    // Rate limiting
    private let maxBatchSize = 10
    private let batchDelayMs: UInt64 = 2_000_000_000  // 2 seconds

    init(orchestrator: TranscriptOrchestrator) {
        self.orchestrator = orchestrator
    }

    /// Queue cache misses for background generation
    func queueMisses(_ misses: [CacheMiss]) {
        guard !misses.isEmpty else { return }

        pendingMisses.append(contentsOf: misses)
        log.info("Queued \(misses.count) cache misses (total pending: \(self.pendingMisses.count))")

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
            isProcessing = true

            // Take a batch
            let batch = Array(pendingMisses.prefix(maxBatchSize))
            pendingMisses.removeFirst(min(maxBatchSize, pendingMisses.count))

            log.info("Processing batch of \(batch.count) cache misses (\(self.pendingMisses.count) remaining)")

            // Process batch off-main
            await processBatch(batch)

            // Rate limit: wait between batches
            if !pendingMisses.isEmpty {
                try? await Task.sleep(nanoseconds: batchDelayMs)
            }
        }

        isProcessing = false
        generationTask = nil
        log.info("Cache miss generation queue empty")
    }

    /// Process a batch of cache misses
    private func processBatch(_ batch: [CacheMiss]) async {
        let startTime = Date()
        var successCount = 0
        var skipCount = 0
        var errorCount = 0

        for miss in batch {
            do {
                // Check if cache already exists (race condition protection)
                let existing = try await MainActor.run {
                    try? orchestrator.getCachedTimeline(
                        contentSha256: miss.contentSha256,
                        windowSha256: miss.windowSha256
                    )
                }

                if let existing = existing {
                    // Skip if user edited (never clobber)
                    if existing.userEdited == 1 {
                        log.debug("Skipping cache miss - user edited entry exists")
                        skipCount += 1
                        continue
                    }
                }

                // Generate summary using LLM
                let summary = try await generateSummary(for: miss)

                // Upsert to cache (respecting user_edited flag)
                try await upsertCache(miss: miss, summary: summary)

                successCount += 1
            } catch {
                log.error("Failed to generate cache for miss: \(error.localizedDescription, privacy: .public)")
                errorCount += 1
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        log.info("Batch complete: \(successCount) generated, \(skipCount) skipped, \(errorCount) errors in \(Int(elapsed * 1000))ms")

        // Post notification for UI refresh if any succeeded
        if successCount > 0 {
            await postCacheUpdateNotification()
        }
    }

    /// Generate summary for a cache miss using LLM
    private func generateSummary(for miss: CacheMiss) async throws -> GeneratedSummary {
        // TODO: Replace with actual LLM API call
        // For now, use simple heuristic as placeholder

        let content = miss.content
        let truncated = String(content.prefix(150))

        // Generate present and past forms
        let presentForm = truncated + (content.count > 150 ? "…" : "")
        let pastForm = truncated + (content.count > 150 ? "…" : "")

        return GeneratedSummary(
            presentForm: presentForm,
            pastForm: pastForm,
            selectedForm: "present",
            disposition: "active"
        )
    }

    /// Upsert cache entry (never clobber user_edited=1)
    private func upsertCache(miss: CacheMiss, summary: GeneratedSummary) async throws {
        // Check if entry exists and is user-edited
        let existing = try await MainActor.run {
            try? orchestrator.getCachedTimeline(
                contentSha256: miss.contentSha256,
                windowSha256: miss.windowSha256
            )
        }

        if let existing = existing, existing.userEdited == 1 {
            log.warning("Refusing to overwrite user-edited cache entry")
            return
        }

        // Create TimelineCache object
        let now = Int(Date().timeIntervalSince1970)
        let cache = TimelineCache(
            contentSha256: miss.contentSha256,
            windowSha256: miss.windowSha256,
            entryId: "",  // Not needed for cache lookup
            generatorSignature: timelineGeneratorSignature(),
            disposition: summary.disposition,
            presentForm: summary.presentForm,
            pastForm: summary.pastForm,
            selectedForm: summary.selectedForm,
            generatedAt: now,
            userEdited: 0
        )

        // Save to database
        try await MainActor.run {
            try orchestrator.saveCachedTimeline(cache)
        }
    }

    /// Post notification to trigger lightweight UI refresh
    private func postCacheUpdateNotification() async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("TimelineCacheUpdated"),
                object: nil
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
