//
//  ViewportTrackingCoordinator.swift
//  Contextify
//
//  Extracted from ConversationMonitor - handles viewport state machine and visibility tracking
//

import Foundation
import OSLog
import SwiftUI
import ContextifyCore

// MARK: - Viewport Context

/// Context for viewport tracking operations
/// Note: Currently defined for potential future Phase 2/3 use - not actively used by coordinator
public struct ViewportContext: Equatable, Sendable {
    public let projectId: String
    public let sessionId: String?

    public init(projectId: String, sessionId: String?) {
        self.projectId = projectId
        self.sessionId = sessionId
    }
}

// MARK: - Viewport Tracking Delegate

/// Delegate protocol for viewport coordinator callbacks to ConversationMonitor
@MainActor
protocol ViewportTrackingDelegate: AnyObject {
    /// Called when viewport settles after debounce period
    func viewportDidSettle(visibleIDs: Set<UUID>)

    /// Called to queue cache misses for generation
    /// Note: Reserved for Phase 2/3 - not currently called by coordinator
    func queueCacheMisses(_ misses: [CacheMiss]) async

    /// Lookup entry by ID
    func lookupEntry(_ id: UUID) -> TimelineEntry?

    /// Get currently buffered visible entries
    var visibleEntries: [TimelineEntry] { get }

    /// Get current project ID
    func getCurrentProjectId() -> String?

    /// Cache miss generator
    var cacheMissGenerator: TimelineCacheMissGenerator? { get }

    /// Contextify entry info lookup
    /// Note: Reserved for Phase 2/3 - not currently called by coordinator
    func getContextifyEntryInfo(for entryId: String) -> TranscriptOrchestrator.ContextifyEntryInfo?

    /// Called when user has been at bottom long enough to mark as viewed
    func markActiveProjectAsViewed() async

    /// Get current entry IDs for pruning viewed set
    func getCurrentEntryIDs() -> Set<UUID>

    /// Max entries for pruning cap calculation
    var maxEntries: Int { get }
}

// MARK: - Viewport Tracking Coordinator

/// Coordinates viewport state machine and visibility tracking
/// Extracted from ConversationMonitor to reduce god object complexity
@MainActor
final class ViewportTrackingCoordinator {
    private let log = Logger(subsystem: "dev.contextify.timeline", category: "ViewportCoordinator")

    // Delegate for callbacks
    weak var delegate: ViewportTrackingDelegate?

    // Initial viewport state machine
    private var stateMachine = InitialViewportStateMachine()
    private var pendingInitialVisibleIDs: Set<UUID>?
    private var initialViewportFallbackTask: Task<Void, Never>?
    private var initialViewportSnapshotIDs = Set<UUID>()
    private var initialViewportSnapshotTimestamp: Date?
    private var initialViewportStarvationTask: Task<Void, Never>?
    private var initialViewportFallbackFireCount = 0
    private var initialViewportFallbackArmedCount = 0

    // Visibility tracking
    private var lastVisibleIDs = Set<UUID>()
    private var coalesceTask: Task<Void, Never>?
    private var visibleEntryTimestamps: [UUID: Date] = [:]
    private let viewportEntryRetentionDuration: TimeInterval = 1.0
    private var viewedEntryIDs = Set<UUID>()

    // Scroll control
    private var doingProgrammaticScroll = false
    private var isUserScrollActive = false
    private var scrollGateTimeoutTask: Task<Void, Never>?

    // Unread tracking
    private var isAtBottom = false
    private var clearUnreadTask: Task<Void, Never>?

    // Configuration
    private let visibleEntryLimit = 25
    private let initialViewportFallbackCount = 12
    private let initialViewportFallbackDelay: UInt64 = 500_000_000  // 500ms (matches original)

    // MARK: - State Accessors

    /// Whether we're awaiting initial visibility snapshot
    var needsInitialVisibilitySnapshot: Bool {
        stateMachine.isAwaiting
    }

    /// Current awaiting context (if any)
    var awaitingContext: InitialViewportStateMachine.Context? {
        stateMachine.awaitingContext
    }

    /// Active context (awaiting or accepted)
    var activeContext: InitialViewportStateMachine.Context? {
        stateMachine.activeContext
    }

    /// Current visible entry IDs
    var currentVisibleIDs: Set<UUID> {
        lastVisibleIDs
    }

    // MARK: - Initialization

    init() {}

    // MARK: - State Machine Control

    /// Reset viewport state machine
    func reset(reason: String) {
        stateMachine.reset()
        pendingInitialVisibleIDs = nil
        initialViewportSnapshotIDs.removeAll()
        initialViewportSnapshotTimestamp = nil
        initialViewportFallbackFireCount = 0
        initialViewportFallbackArmedCount = 0
        cancelStarvationCheck()
        cancelFallback(reason: reason)
        log.debug("[VIEWPORT-RESET] State reset (\(reason, privacy: .public))")
    }

    /// Full reset of all viewport state (for project/session changes)
    func fullReset(reason: String) {
        reset(reason: reason)
        viewedEntryIDs.removeAll(keepingCapacity: false)
        doingProgrammaticScroll = false
        isUserScrollActive = false
        scrollGateTimeoutTask?.cancel()
        scrollGateTimeoutTask = nil
        lastVisibleIDs.removeAll()
        coalesceTask?.cancel()
        coalesceTask = nil
        isAtBottom = false
        clearUnreadTask?.cancel()
        clearUnreadTask = nil
        visibleEntryTimestamps.removeAll()
        log.debug("[VIEWPORT-FULL-RESET] All viewport state cleared (\(reason, privacy: .public))")
    }

    /// Begin awaiting initial viewport snapshot
    func beginAwaiting(projectId: String, sessionId: String?, reason: String) {
        guard stateMachine.beginAwaiting(projectId: projectId, sessionId: sessionId) else {
            return
        }
        pendingInitialVisibleIDs = nil
        log.debug("[VIEWPORT-ARM] Awaiting initial snapshot for project \(projectId, privacy: .public) (\(reason, privacy: .public))")
        scheduleFallback(using: nil, reason: reason)
    }

    /// Replay pending initial viewport snapshot if available
    func replayPendingSnapshot(reason: String) {
        guard needsInitialVisibilitySnapshot else { return }
        guard let snapshot = pendingInitialVisibleIDs, !snapshot.isEmpty else { return }
        log.debug("[VIEWPORT-REPLAY] Replaying pending snapshot (\(snapshot.count, privacy: .public) IDs) reason=\(reason, privacy: .public)")
        processInitialSnapshot(snapshot)
    }

    // MARK: - Scroll Control

    /// Begin programmatic scroll - gates visibility updates
    func beginProgrammaticScroll() {
        doingProgrammaticScroll = true
        pendingInitialVisibleIDs = nil
        log.debug("[SCROLL] Programmatic scroll started, gating visibility updates")

        scrollGateTimeoutTask?.cancel()
        scrollGateTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return  // Cancelled - don't clear gate
            }
            await MainActor.run {
                guard let self, self.doingProgrammaticScroll else { return }
                self.doingProgrammaticScroll = false
                self.log.warning("[SCROLL] Clearing programmatic scroll gate after timeout")
            }
        }
    }

    /// Handle scroll phase change
    func handleScrollPhaseChange(_ phase: ScrollPhase) {
        switch phase {
        case .idle:
            if doingProgrammaticScroll {
                scrollGateTimeoutTask?.cancel()
                doingProgrammaticScroll = false
                log.debug("[SCROLL] Programmatic scroll completed")
                if needsInitialVisibilitySnapshot,
                   let pending = pendingInitialVisibleIDs,
                   !pending.isEmpty {
                    log.debug("[VIEWPORT-DEFER] Processing deferred snapshot after scroll completion (\(pending.count, privacy: .public) IDs)")
                    processInitialSnapshot(pending)
                }
            } else if isUserScrollActive {
                isUserScrollActive = false
                log.debug("[SCROLL] User scroll became idle")
            }
        default:
            if doingProgrammaticScroll { return }
            if !isUserScrollActive {
                isUserScrollActive = true
                log.debug("[SCROLL] User scroll started")
            }
        }
    }

    // MARK: - Visibility Snapshot

    /// Replace visible snapshot with new IDs
    func replaceVisibleSnapshot(_ ids: [UUID]) {
        let current = Set(ids)

        // Initial snapshot handling
        if needsInitialVisibilitySnapshot {
            handleInitialSnapshotUpdate(current)
            return
        }

        // Skip unchanged viewport
        if current == lastVisibleIDs {
            log.debug("[VIEWPORT-SKIP] Viewport unchanged (\(ids.count) entries)")
            return
        }

        // Update tracking
        lastVisibleIDs = current
        recordTimestamps(current)

        // Debounced processing
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_250_000_000)  // 1.25s debounce
            } catch { return }

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.log.info("[VIEWPORT-SETTLED] Timer completed, notifying delegate")
                // Union/prune before callback to keep viewed set current before downstream work
                self.viewedEntryIDs.formUnion(self.lastVisibleIDs)
                self.pruneViewedIDsIfNeeded()
                if let delegate = self.delegate {
                    delegate.viewportDidSettle(visibleIDs: self.lastVisibleIDs)
                } else {
                    self.log.warning("[VIEWPORT-SETTLED] Delegate nil - settle callback dropped (teardown in progress?)")
                }
            }
        }
    }

    /// Mark single entry as visible
    func markEntryVisible(_ entryId: UUID) {
        guard !viewedEntryIDs.contains(entryId) else { return }
        viewedEntryIDs.insert(entryId)
        pruneViewedIDsIfNeeded()
    }

    // MARK: - Scroll Position Tracking

    /// Update scroll position for unread clearing
    func updateScrollPosition(visibleRect: CGRect, contentHeight: CGFloat) {
        let threshold: CGFloat = 50.0
        let scrollBottom = visibleRect.maxY
        let newIsAtBottom = (contentHeight - scrollBottom) <= threshold || contentHeight <= visibleRect.height

        if newIsAtBottom != isAtBottom {
            isAtBottom = newIsAtBottom
            if isAtBottom {
                log.debug("[UNREAD-CLEAR] User scrolled to bottom")
                scheduleMarkAsViewed()
            } else {
                clearUnreadTask?.cancel()
                clearUnreadTask = nil
            }
        }
    }

    // MARK: - Recent Visible IDs

    /// Get IDs that were visible within retention duration
    func recentVisibleIDs() -> Set<UUID> {
        let now = Date()
        return Set(visibleEntryTimestamps.compactMap { id, ts in
            now.timeIntervalSince(ts) <= viewportEntryRetentionDuration ? id : nil
        })
    }

    // MARK: - Private: Initial Snapshot Handling

    private func handleInitialSnapshotUpdate(_ current: Set<UUID>) {
        guard let delegate else {
            log.warning("[VIEWPORT-INIT] Delegate nil - resetting initial viewport state")
            reset(reason: "nil-delegate")
            return
        }
        guard let context = activeContext,
              context.projectId == delegate.getCurrentProjectId() else {
            log.debug("[VIEWPORT-INIT] Ignoring snapshot from stale project context")
            return
        }

        if doingProgrammaticScroll {
            log.debug("[VIEWPORT-INIT] Programmatic scroll in progress - deferring initial snapshot")
            scheduleFallback(using: current.isEmpty ? nil : current, reason: "programmatic-scroll")
            return
        }

        guard !current.isEmpty else {
            log.debug("[VIEWPORT-INIT] Ignoring empty initial snapshot - waiting for visible IDs")
            scheduleFallback(using: nil, reason: "empty-snapshot")
            return
        }

        cancelFallback(reason: "snapshot-ready")
        processInitialSnapshot(current)
    }

    private func processInitialSnapshot(_ current: Set<UUID>) {
        guard let delegate else {
            log.warning("[VIEWPORT-INIT] Delegate nil in processInitialSnapshot - resetting initial viewport state")
            reset(reason: "nil-delegate")
            return
        }
        guard let context = awaitingContext,
              context.projectId == delegate.getCurrentProjectId() else {
            log.debug("[VIEWPORT-INIT] Snapshot ignored - project context changed")
            return
        }

        guard !current.isEmpty else {
            log.debug("[VIEWPORT-INIT] Snapshot empty - keeping initial guard active")
            scheduleFallback(using: nil, reason: "empty-initial-snapshot")
            return
        }

        guard delegate.cacheMissGenerator != nil else {
            pendingInitialVisibleIDs = current
            log.debug("[VIEWPORT-DEFER] Generator unavailable; stored \(current.count, privacy: .public) IDs")
            return
        }

        pendingInitialVisibleIDs = nil
        let accepted = stateMachine.acceptSnapshot(
            projectId: context.projectId,
            sessionId: context.sessionId
        )
        doingProgrammaticScroll = false
        cancelFallback(reason: "initial-processed")

        if accepted {
            log.info("[VIEWPORT-ACCEPTED] Initial viewport snapshot: \(current.count, privacy: .public) visible")
        }

        initialViewportSnapshotIDs = current
        initialViewportSnapshotTimestamp = Date()
        scheduleStarvationCheck()

        // Union before callback for consistency with debounce path
        viewedEntryIDs.formUnion(current)
        lastVisibleIDs = current

        // Notify delegate (also sets debugVisibleIDs in ConversationMonitor)
        delegate.viewportDidSettle(visibleIDs: current)
    }

    // MARK: - Private: Fallback Timer

    private func scheduleFallback(using candidate: Set<UUID>?, reason: String) {
        guard needsInitialVisibilitySnapshot else { return }
        if let candidate, !candidate.isEmpty {
            pendingInitialVisibleIDs = candidate
        }

        initialViewportFallbackTask?.cancel()
        let delay = initialViewportFallbackDelay
        initialViewportFallbackTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch { return }
            await MainActor.run { [weak self] in
                self?.fireFallback(reason: reason)
            }
        }

        initialViewportFallbackArmedCount &+= 1  // wrapping increment (matches original)
        let delayMs = initialViewportFallbackDelay / 1_000_000
        log.debug("[VIEWPORT-FALLBACK] Armed fallback timer (\(reason, privacy: .public)) - firing in \(delayMs, privacy: .public)ms (armed #\(self.initialViewportFallbackArmedCount, privacy: .public))")
    }

    private func cancelFallback(reason: String?) {
        guard initialViewportFallbackTask != nil else { return }
        initialViewportFallbackTask?.cancel()
        initialViewportFallbackTask = nil
        if let reason {
            log.debug("[VIEWPORT-FALLBACK] Cancelled (\(reason, privacy: .public))")
        }
    }

    private func fireFallback(reason: String) {
        guard needsInitialVisibilitySnapshot else { return }
        let snapshot = pendingInitialVisibleIDs ?? computeFallbackIDs()
        guard !snapshot.isEmpty else {
            log.warning("[VIEWPORT-FALLBACK] Timeout fired but no IDs available (\(reason, privacy: .public))")
            return
        }

        initialViewportFallbackFireCount &+= 1  // wrapping increment (matches original)
        log.warning("[VIEWPORT-FALLBACK] Triggering fallback snapshot (\(snapshot.count, privacy: .public) IDs, reason=\(reason, privacy: .public)) (count #\(self.initialViewportFallbackFireCount, privacy: .public))")
        processInitialSnapshot(snapshot)
    }

    private func computeFallbackIDs() -> Set<UUID> {
        guard let entries = delegate?.visibleEntries else { return Set() }
        let candidates = entries.suffix(initialViewportFallbackCount)
        return Set(candidates.map { $0.id })
    }

    // MARK: - Private: Starvation Check

    private func scheduleStarvationCheck() {
        cancelStarvationCheck()
        let snapshotIDs = initialViewportSnapshotIDs
        guard !snapshotIDs.isEmpty,
              let snapshotTimestamp = initialViewportSnapshotTimestamp else {
            return
        }

        initialViewportStarvationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds (matches original)
            } catch {
                return
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                // Only warn if same snapshot context
                guard self.initialViewportSnapshotTimestamp == snapshotTimestamp else { return }
                let elapsed = Date().timeIntervalSince(snapshotTimestamp)
                // Only warn if entries are still unsummarized
                let stillPending = snapshotIDs.filter { id in
                    guard let entry = self.delegate?.lookupEntry(id) else { return false }
                    return entry.action == .unsummarized
                }
                guard !stillPending.isEmpty else { return }
                let preview = stillPending.prefix(4).map { String($0.uuidString.prefix(8)) }.joined(separator: ", ")
                self.log.warning("[SUMM-VIEWPORT-STARVATION] \(stillPending.count, privacy: .public) initial entries still unsummarized after \(Int(elapsed * 1000), privacy: .public)ms: \(preview, privacy: .public)")
            }
        }
    }

    private func cancelStarvationCheck() {
        initialViewportStarvationTask?.cancel()
        initialViewportStarvationTask = nil
    }

    // MARK: - Private: Timestamp Tracking

    private func recordTimestamps(_ ids: Set<UUID>) {
        let now = Date()
        visibleEntryTimestamps = visibleEntryTimestamps.filter {
            now.timeIntervalSince($0.value) <= viewportEntryRetentionDuration
        }
        let toRemove = visibleEntryTimestamps.keys.filter { !ids.contains($0) }
        for key in toRemove {
            visibleEntryTimestamps.removeValue(forKey: key)
        }
        ids.forEach { visibleEntryTimestamps[$0] = now }
    }

    // MARK: - Private: Viewed IDs Pruning

    private func pruneViewedIDsIfNeeded() {
        // Use delegate's maxEntries to match original behavior (config.maxEntries * 4)
        let cap = (delegate?.maxEntries ?? visibleEntryLimit) * 4
        guard viewedEntryIDs.count > cap else { return }
        if let currentIDs = delegate?.getCurrentEntryIDs() {
            viewedEntryIDs.formIntersection(currentIDs)
        }
        log.debug("Pruned viewedEntryIDs to \(self.viewedEntryIDs.count)")
    }

    // MARK: - Private: Mark as Viewed

    private func scheduleMarkAsViewed() {
        clearUnreadTask?.cancel()
        clearUnreadTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                guard !Task.isCancelled else { return }
                await self?.delegate?.markActiveProjectAsViewed()
            } catch {}
        }
    }
}
