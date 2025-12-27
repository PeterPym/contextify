//
//  TimelineCacheCoordinator.swift
//  Contextify
//
//  Coordinates cache miss creation and queue management for timeline entries.
//  Extracted from ConversationMonitor Phase 3.
//

import Foundation
import OSLog
import ContextifyCore

// MARK: - Cache Coordinator Delegate

/// Protocol for TimelineCacheCoordinator to access ConversationMonitor state
/// Note: Extends ViewportTrackingDelegate which already provides most required methods
@MainActor
protocol CacheCoordinatorDelegate: ViewportTrackingDelegate {
    /// Get recent visible IDs from viewport coordinator (for prune protection)
    func getRecentVisibleIDs() -> Set<UUID>
}

// MARK: - Timeline Cache Coordinator

/// Coordinates cache miss creation and queue management for timeline entries.
/// Extracted from ConversationMonitor to reduce god object complexity.
///
/// Responsibilities:
/// - Cache miss creation (CacheMiss struct instantiation)
/// - Settle-driven queueing (queueing visible unsummarized entries)
/// - Queue pruning (removing non-visible entries from queue)
/// - Immediate regeneration queueing (user-initiated via right-click)
/// - Coordination between viewport events and cache miss generator
///
/// Concurrency notes:
/// - All state is @MainActor-isolated, making settleGeneration checks race-free.
/// - Delegate may become nil mid-operation; this is "best effort" - we capture what
///   we need at entry and bail gracefully. Next settle or user action will recover.
@MainActor
final class TimelineCacheCoordinator {
    private let log = Logger(subsystem: "dev.contextify.timeline", category: "CacheCoordinator")

    // Delegate for callbacks to ConversationMonitor
    weak var delegate: CacheCoordinatorDelegate?

    // Coalescing: ensure "last settle wins" under rapid settle events.
    // MainActor serialization makes generation checks race-free - no concurrent mutation possible.
    private var settleTask: Task<Void, Never>?
    private var settleGeneration: UInt64 = 0

    // MARK: - Initialization

    init() {}

    // MARK: - Viewport Settle Handling

    /// Handle viewport settle event - prune queue and queue visible entries
    /// Called from ViewportTrackingDelegate.viewportDidSettle
    func handleViewportSettle(visibleIDs: Set<UUID>) {
        settleGeneration &+= 1
        let generation = settleGeneration

        settleTask?.cancel()
        settleTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.performViewportSettle(visibleIDs: visibleIDs, generation: generation)
        }
    }

    private func performViewportSettle(visibleIDs: Set<UUID>, generation: UInt64) async {
        guard !Task.isCancelled else { return }
        guard generation == settleGeneration else { return }

        await pruneQueueToVisible(visibleIDs)

        guard !Task.isCancelled else { return }
        guard generation == settleGeneration else { return }

        await queueVisibleGeneratingEntries(visibleIDs)

        // Clean up task reference for cleaner state inspection
        settleTask = nil
    }

    // MARK: - Queue Management (Extracted from ConversationMonitor)

    /// Prune generator queue to keep only visible entries
    private func pruneQueueToVisible(_ ids: Set<UUID>) async {
        guard !Task.isCancelled else { return }
        guard let delegate else {
            log.warning("[CACHE-COORD] pruneQueueToVisible - delegate nil")
            return
        }
        guard let generator = delegate.cacheMissGenerator else { return }

        #if DEBUG
        log.debug("[CACHE-COORD-PRUNE-START] Pruning queue to \(ids.count, privacy: .public) visible entries")

        // Check queue depth before pruning
        let beforeCount = await generator.getStatus().pending
        log.debug("[CACHE-COORD-PRUNE-BEFORE] Queue depth before pruning: \(beforeCount, privacy: .public)")
        #endif

        let relevantUUIDs = ids.union(delegate.getRecentVisibleIDs())
        // Convert UUID set to entry ID strings (sourceIdentifier)
        let visibleEntryIDs = Set(delegate.visibleEntries
            .filter { relevantUUIDs.contains($0.id) }
            .map { $0.sourceIdentifier })

        #if DEBUG
        log.debug("[CACHE-COORD-PRUNE-VISIBLE-IDS] Keeping \(visibleEntryIDs.count, privacy: .public) visible entry IDs")
        #endif

        await generator.pruneQueue(keepOnly: visibleEntryIDs)

        #if DEBUG
        guard !Task.isCancelled else { return }
        // Check queue depth after pruning
        let afterCount = await generator.getStatus().pending
        log.debug("[CACHE-COORD-PRUNE-AFTER] Queue depth after pruning: \(afterCount, privacy: .public)")
        log.debug("[CACHE-COORD-PRUNE-REMOVED] Removed \(beforeCount - afterCount, privacy: .public) items from queue")
        #endif
    }

    /// Queue entries that are both visible and generating summaries
    private func queueVisibleGeneratingEntries(_ ids: Set<UUID>) async {
        guard !Task.isCancelled else { return }
        guard let delegate else {
            log.warning("[CACHE-COORD] queueVisibleGeneratingEntries - delegate nil")
            return
        }
        guard let projectId = delegate.getCurrentProjectId(), let generator = delegate.cacheMissGenerator else {
            let pidStr = delegate.getCurrentProjectId()?.prefix(8) ?? "nil"
            let genStr = delegate.cacheMissGenerator != nil ? "exists" : "nil"
            log.debug("[CACHE-COORD-QUEUE] Cannot queue - projectId=\(pidStr, privacy: .public), generator=\(genStr, privacy: .public)")
            return
        }

        // Debug: check what's available
        // Note: ids = actually visible on screen (viewport tracking)
        //       visibleEntries = buffered entries (up to 25, may not all be visible)
        let bufferedEntries = delegate.visibleEntries.filter { ids.contains($0.id) }
        let unsummarizedVisible = bufferedEntries.filter { $0.action == .unsummarized }

        log.debug("[CACHE-COORD-QUEUE] Checking \(ids.count) actually-visible IDs (buffered: \(delegate.visibleEntries.count))")
        log.debug("[CACHE-COORD-QUEUE] Matching in buffer: \(bufferedEntries.count), Unsummarized: \(unsummarizedVisible.count)")

        var misses: [CacheMiss] = []
        for entry in bufferedEntries where entry.action == .unsummarized {
            guard let contentSha = entry.contentSha256,
                  let windowSha = entry.windowSha256,
                  let sourceText = entry.sourceContent else {
                continue
            }

            let entryId = entry.sourceIdentifier
            if await generator.isEntryQueued(entryId) {
                log.debug(
                    "[CACHE-COORD-QUEUE-SKIP] Entry \(entryId.prefix(8), privacy: .public) already queued, skipping re-queue"
                )
                continue
            }

            let ctxInfo = delegate.getContextifyEntryInfo(for: entryId)
            misses.append(CacheMiss(
                entryId: entryId,  // Use original DB ID, not UUID
                projectId: projectId,
                contentSha256: contentSha,
                windowSha256: windowSha,
                content: sourceText,
                context: entry.detail,
                kind: entry.kind.rawValue,
                provider: entry.sourceContext?.provider.rawValue ?? "other",
                isContextify: ctxInfo != nil,
                contextifyToolKey: ctxInfo?.toolKey,
                isContextifyResult: ctxInfo?.isResult ?? false
            ))
        }

        guard !misses.isEmpty else {
            log.debug("[CACHE-COORD-QUEUE] No entries need queueing (all visible entries have summaries)")
            return
        }

        log.info("[CACHE-COORD-QUEUE-INITIAL] About to queue visible entries needing summaries")
        log.info("[CACHE-COORD-QUEUE-VISIBLE-COUNT] Visible IDs: \(ids.count, privacy: .public)")
        log.info("[CACHE-COORD-QUEUE-NEEDS-SUMMARY-COUNT] Entries needing summaries: \(misses.count, privacy: .public)")

        log.info("[CACHE-COORD-QUEUE] Queueing \(misses.count, privacy: .public) visible unsummarized entries:")

        #if DEBUG
        // Per-entry logging with content preview (gated to avoid leaking sensitive text in production)
        let entryLookup = Dictionary(uniqueKeysWithValues: delegate.visibleEntries.map { ($0.sourceIdentifier, $0) })
        for miss in misses {
            let contentPreview = String(miss.content.prefix(15))
            let isQueued = entryLookup[miss.entryId]?.isQueued ?? false
            log.info("  [CACHE-COORD-QUEUE] Entry \(miss.entryId.prefix(8), privacy: .public): \(miss.kind, privacy: .public) | isQueued=\(isQueued, privacy: .public) | \"\(contentPreview, privacy: .public)...\"")
        }
        #endif

        log.debug("[CACHE-COORD-QUEUE] Calling generator.queueMisses() with \(misses.count) entries")
        await generator.queueMisses(misses)
        log.debug("[CACHE-COORD-QUEUE] generator.queueMisses() completed")
    }

    // MARK: - Regeneration Queueing

    /// Queue a regenerated entry immediately for summarization
    ///
    /// This bypasses the normal viewport tracking and debounce mechanism to provide
    /// immediate feedback when user explicitly requests regeneration via right-click menu.
    /// Without this, user would need to scroll the entry out of view and back in to
    /// trigger the viewport-based queueing (with 1.25s settling time).
    func queueForRegeneration(contentSha256: String, windowSha256: String) {
        guard let delegate else {
            log.warning("[CACHE-COORD-REGEN] Cannot queue - delegate nil")
            return
        }
        guard let projectId = delegate.getCurrentProjectId(), let generator = delegate.cacheMissGenerator else {
            log.warning("[CACHE-COORD-REGEN] Cannot queue - projectId or generator not available")
            return
        }

        // Find the entry that matches these hashes
        guard let entry = delegate.visibleEntries.first(where: {
            $0.contentSha256 == contentSha256 && $0.windowSha256 == windowSha256
        }) else {
            log.warning("[CACHE-COORD-REGEN] Entry not found for regeneration (may not be in visible entries)")
            return
        }

        guard entry.action == .unsummarized else {
            log.debug("[CACHE-COORD-REGEN] Entry already has summary or is processing")
            return
        }

        guard let content = entry.sourceContent else {
            log.warning("[CACHE-COORD-REGEN] Entry missing source content")
            return
        }

        // Create cache miss
        let ctxInfo = delegate.getContextifyEntryInfo(for: entry.sourceIdentifier)
        let miss = CacheMiss(
            entryId: entry.sourceIdentifier,
            projectId: projectId,
            contentSha256: contentSha256,
            windowSha256: windowSha256,
            content: content,
            context: entry.detail,
            kind: entry.kind.rawValue,
            provider: entry.sourceContext?.provider.rawValue ?? "other",
            isContextify: ctxInfo != nil,
            contextifyToolKey: ctxInfo?.toolKey,
            isContextifyResult: ctxInfo?.isResult ?? false
        )

        // Queue with high priority (user explicitly requested it)
        Task(priority: .userInitiated) {
            log.info("[CACHE-COORD-REGEN] Immediately queueing entry for regeneration: \(entry.id.uuidString.prefix(8), privacy: .public)")
            await generator.queueMisses([miss])
        }
    }

    // MARK: - Cache Miss Factory Methods

    /// Create cache misses for feed load entries
    /// Returns array of CacheMiss for entries that have no cache
    func createMissesForFeed(
        entries: [(TranscriptEntry, TimelineCache?)],
        projectId: String,
        contextifyEntryInfo: [String: TranscriptOrchestrator.ContextifyEntryInfo]
    ) -> [CacheMiss] {
        var misses: [CacheMiss] = []

        for (entry, cache) in entries {
            // Collect cache miss for background generation
            if cache == nil, let windowSha = entry.windowSha256 {
                let ctxInfo = contextifyEntryInfo[entry.id]
                let miss = CacheMiss(
                    entryId: entry.id,
                    projectId: projectId,
                    contentSha256: entry.contentSha256,
                    windowSha256: windowSha,
                    content: entry.content,
                    context: entry.content,  // TODO: Add surrounding context
                    kind: entry.kind,
                    provider: entry.provider,
                    isContextify: ctxInfo != nil,
                    contextifyToolKey: ctxInfo?.toolKey,
                    isContextifyResult: ctxInfo?.isResult ?? false
                )
                misses.append(miss)
            }
        }

        return misses
    }

    /// Create cache misses for incremental update entries
    /// Returns array of CacheMiss for new entries that have no cache
    func createMissesForUpdate(
        entries: [TranscriptEntry],
        projectId: String,
        contextifyEntryInfo: [String: TranscriptOrchestrator.ContextifyEntryInfo],
        cacheForEntry: (TranscriptEntry) -> TimelineCache?
    ) -> [CacheMiss] {
        var misses: [CacheMiss] = []

        for entry in entries {
            let cache = cacheForEntry(entry)

            // Collect cache miss for background generation
            if cache == nil, let windowSha = entry.windowSha256 {
                let ctxInfo = contextifyEntryInfo[entry.id]
                let miss = CacheMiss(
                    entryId: entry.id,
                    projectId: projectId,
                    contentSha256: entry.contentSha256,
                    windowSha256: windowSha,
                    content: entry.content,
                    context: entry.content,  // TODO: Add surrounding context
                    kind: entry.kind,
                    provider: entry.provider,
                    isContextify: ctxInfo != nil,
                    contextifyToolKey: ctxInfo?.toolKey,
                    isContextifyResult: ctxInfo?.isResult ?? false
                )
                misses.append(miss)
            }
        }

        return misses
    }

    // MARK: - Diagnostics

    /// Derive entry status for logging (cached/queued/generating/not_queued/error)
    func getEntryStatus(_ entry: TimelineEntry) async -> String {
        if entry.isError { return "error" }
        if entry.action != .unsummarized { return "cached" }
        if let generator = delegate?.cacheMissGenerator {
            // activeEntryID is @MainActor-isolated in the actor, so synchronous access is safe here
            if generator.activeEntryID == entry.id { return "generating" }
            if await generator.isEntryQueued(entry.sourceIdentifier) {
                return "queued"
            }
        }
        return "not_queued"
    }
}
