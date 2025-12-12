//
//  StatusBarViewModel.swift
//  Contextify
//
//  Event-driven view model for status bar with proper lifecycle management
//

import Foundation
import Observation
import OSLog
import ContextifyCore

@MainActor
@Observable
final class StatusBarViewModel {
    private let log = Logger(subsystem: "dev.contextify", category: "StatusBar")
    // MARK: - Dependencies
    private let queueProviders: [any QueueStatsProvider]

    // MARK: - Observable State
    private(set) var queueDepth: Int = 0
    private(set) var isProcessing: Bool = false
    private(set) var estimatedSecondsRemaining: Int = 0
    private(set) var recentErrorCount: Int = 0
    private(set) var topErrorReason: String?
    private(set) var monitoringActive: Bool = false

    // MARK: - Per-Provider State (Phase 5: True Aggregation)
    private var providerStats: [Int: QueueStats] = [:]  // Track stats by provider index

    // Apple Intelligence status
    enum AIStatus: Sendable, Equatable {
        case checking  // Initial state before first health check completes
        case available
        case unavailable(reason: String)
        case error(message: String)
    }
    private(set) var aiStatus: AIStatus = .checking

    // Hoover status
    private(set) var hooverMessage: String? = nil
    private(set) var hooverLastScan: Date? = nil
    private(set) var backgroundIngestMessage: String? = nil

    // MARK: - Lifecycle State
    private var queueObservationTasks: [Task<Void, Never>] = []
    private var aiHealthCheckTask: Task<Void, Never>?
    private var hooverObservationTask: Task<Void, Never>?
    private var hooverFadeTask: Task<Void, Never>?
    private var backgroundObservationTask: Task<Void, Never>?
    private var isStarted: Bool = false
    private var aiCancellationEvents: [Date] = []
    private var cancellationBurstActive = false
    private var lastAIWarningReason: String?

    init(queueProviders: [any QueueStatsProvider]) {
        self.queueProviders = queueProviders

        // Initialize with last known AI status to avoid flicker on project switches
        // We'll load this in start() via loadCachedAIStatus(), which runs immediately
        // The key is that loadCachedAIStatus() is very fast (just reads cached value)
    }

    // MARK: - Lifecycle (called by View)

    /// Start observing queue and check AI health
    /// Idempotent: safe to call multiple times
    func start() {
        log.info("StatusBar starting...")

        // Idempotence guard
        guard !isStarted else {
            log.debug("StatusBar already started (idempotence guard)")
            return
        }
        isStarted = true

        guard !queueProviders.isEmpty else {
            log.warning("StatusBar: No queue providers available")
            monitoringActive = false
            return
        }

        log.info("StatusBar: \(self.queueProviders.count) queue provider(s) available, starting observation")
        monitoringActive = true

        // Skip queue observation in lite mode - no LLM processing will happen
        if !isLiteModeActive() {
            // Start observation task for each provider (Phase 5: track by index)
            for (index, provider) in self.queueProviders.enumerated() {
                let task = Task { @MainActor [weak self] in
                    guard let self else { return }

                    for await stats in provider.observeQueue() {
                        guard !Task.isCancelled else { break }
                        self.aggregateStats(from: stats, providerIndex: index)
                    }

                    // Stream finished (provider ended or cancelled) - remove from tracking
                    self.providerStats.removeValue(forKey: index)
                    self.recomputeAggregateState()
                }
                queueObservationTasks.append(task)
            }
        } else {
            log.info("StatusBar: Lite mode - skipping queue observation")
        }

        // Check Apple Intelligence periodically (every 30s to respect cache)
        // In lite mode, just set status once and skip periodic checks
        if isLiteModeActive() {
            aiStatus = .unavailable(reason: LLMAvailability.current.statusText)
            log.info("StatusBar: Lite mode - skipping AI health check task")
        } else {
            aiHealthCheckTask = Task { @MainActor [weak self] in
                guard let self else { return }

                // Load cached status immediately to avoid flicker on project switches
                await self.loadCachedAIStatus()

                // Then perform full health check (will use cache if recent)
                await self.checkAppleIntelligenceHealth()

                // Periodic refresh (every 30s)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    guard !Task.isCancelled else { break }
                    await self.checkAppleIntelligenceHealth()
                }
            }
        }

        // Observe hoover events from ProjectActivityMonitor
        startHooverObservation()

        backgroundObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = NotificationCenter.default.notifications(named: .backgroundIngestProgress)
            for await note in stream {
                guard
                    let total = note.userInfo?["total"] as? Int,
                    let remaining = note.userInfo?["remaining"] as? Int
                else { continue }
                self.handleBackgroundProgress(total: total, remaining: remaining)
            }
        }
    }

    /// Stop observing (called on view disappear)
    func stop() {
        for task in queueObservationTasks {
            task.cancel()
        }
        queueObservationTasks.removeAll()
        aiHealthCheckTask?.cancel()
        aiHealthCheckTask = nil
        hooverObservationTask?.cancel()
        hooverObservationTask = nil
        hooverFadeTask?.cancel()
        hooverFadeTask = nil
        backgroundObservationTask?.cancel()
        backgroundObservationTask = nil
        isStarted = false
        monitoringActive = false

        // Clear transient values to avoid stale visuals if view hides
        queueDepth = 0
        isProcessing = false
        estimatedSecondsRemaining = 0
        hooverMessage = nil
        backgroundIngestMessage = nil
        aiCancellationEvents.removeAll()
        cancellationBurstActive = false
        lastAIWarningReason = nil
    }

    // MARK: - State Aggregation (Phase 5: True Sum)

    /// Update stats from a single provider and recompute aggregate state
    private func aggregateStats(from stats: QueueStats, providerIndex: Int) {
        log.debug("[COORD-STATS] Provider[\(providerIndex, privacy: .public)] pending=\(stats.pending, privacy: .public), isProcessing=\(stats.isProcessing), eta=\(stats.estimatedSecondsRemaining, privacy: .public)s")

        // Store provider's stats
        providerStats[providerIndex] = stats

        // Recompute aggregate state from all providers
        recomputeAggregateState()
    }

    private func handleBackgroundProgress(total: Int, remaining: Int) {
        guard total > 0 else {
            backgroundIngestMessage = nil
            return
        }
        if remaining <= 0 {
            backgroundIngestMessage = nil
            return
        }
        let completed = total - remaining
        let currentlyProcessing = completed + 1
        backgroundIngestMessage = "Indexing \(currentlyProcessing)/\(total) projects…"
    }

    /// Recompute aggregate state from all provider stats (Phase 5: True Sum)
    private func recomputeAggregateState() {
        guard !providerStats.isEmpty else {
            // No providers reporting - clear state
            log.debug("[COORD-AGGREGATE] No providers reporting, clearing state")
            monitoringActive = false
            queueDepth = 0
            isProcessing = false
            estimatedSecondsRemaining = 0
            recentErrorCount = 0
            topErrorReason = nil
            return
        }

        let allStats = Array(providerStats.values)
        log.debug("[COORD-AGGREGATE] Recomputing from \(self.providerStats.count, privacy: .public) provider(s)")

        // TRUE SUM: Aggregate pending counts from all providers
        let totalPending = allStats.reduce(0) { $0 + $1.pending }
        log.debug("[COORD-AGGREGATE] Total pending (sum across all providers): \(totalPending, privacy: .public)")

        // ANY: Processing if any provider is processing
        let anyProcessing = allStats.contains { $0.isProcessing }

        // MAX: Use longest ETA (conservative estimate)
        let maxETA = allStats.map { $0.estimatedSecondsRemaining }.max() ?? 0

        // SUM: Total error count across all providers
        let totalErrors = allStats.reduce(0) { $0 + $1.recentErrorCount }

        // FIRST: Use first non-nil error reason (could be enhanced to show all)
        let firstErrorReason = allStats.compactMap { $0.topErrorReason }.first

        // Guard: only show processing when we actually have items to process
        let uiProcessing = anyProcessing && totalPending > 0

        // Only update if changed (reduces SwiftUI invalidation)
        if queueDepth != totalPending
            || isProcessing != uiProcessing
            || estimatedSecondsRemaining != maxETA
            || recentErrorCount != totalErrors
            || topErrorReason != firstErrorReason {

            log.info("[COORD-UPDATE] UI update - queueDepth: \(self.queueDepth, privacy: .public)→\(totalPending, privacy: .public), isProcessing: \(self.isProcessing)→\(uiProcessing), providers: \(allStats.count, privacy: .public)")

            // Log details when queue depth is high
            if totalPending > 100 {
                log.info("[COORD-QUEUE-HIGH] ⚠️ High queue depth: \(totalPending, privacy: .public) items")
                for stat in allStats where stat.pending > 0 {
                    log.info("[COORD-QUEUE-PROVIDER] Provider has \(stat.pending, privacy: .public) pending items")
                }
            }

            queueDepth = totalPending
            isProcessing = uiProcessing
            estimatedSecondsRemaining = uiProcessing ? maxETA : 0
            recentErrorCount = totalErrors
            topErrorReason = firstErrorReason

            // Log when status transitions to "Up to date"
            if totalPending == 0 && !uiProcessing && totalErrors == 0 {
                log.info("[COORD-READY] ✅ Status bar shows 'Up to date' (all queues empty, not processing, no errors)")
            }
        }
    }

    // MARK: - Apple Intelligence Health

    /// Load cached AI status immediately BEFORE viewModel assignment (prevents flicker)
    /// This is called from StatusBarView before assigning the new viewModel to @State
    func loadCachedAIStatusSync() async {
        await loadCachedAIStatus()
    }

    /// Load cached AI status immediately (no health check)
    /// This avoids flicker when creating new StatusBarViewModel during project switches
    private func loadCachedAIStatus() async {
        // Check lite mode first (covers both old OS and simulation)
        if isLiteModeActive() {
            aiStatus = .unavailable(reason: LLMAvailability.current.statusText)
            return
        }

        guard #available(macOS 26.0, *) else {
            aiStatus = .unavailable(reason: "Requires macOS 26+")
            return
        }

        // Get last known status from health checker
        if let cachedHealth = await LLMHealthCheck.shared.getLastKnownStatus() {
            switch cachedHealth {
            case .healthy:
                aiStatus = .available
                log.debug("Loaded cached AI status: available")
            case .unavailable(let reason):
                aiStatus = .unavailable(reason: reason.userFacingMessage)
                log.debug("Loaded cached AI status: unavailable (\(reason.userFacingMessage))")
            }
        } else {
            // No cached status available - keep .checking
            log.debug("No cached AI status available, will check shortly")
        }
    }

    /// Check AI availability using existing LLMHealthCheck
    private func checkAppleIntelligenceHealth() async {
        // Check lite mode first (covers both old OS and simulation)
        if isLiteModeActive() {
            aiStatus = .unavailable(reason: LLMAvailability.current.statusText)
            log.debug("Apple Intelligence check: lite mode active")
            return
        }

        guard #available(macOS 26.0, *) else {
            aiStatus = .unavailable(reason: "Requires macOS 26+")
            log.debug("Apple Intelligence check: macOS < 26")
            return
        }

        // Use existing health checker with 30s TTL
        let health = await LLMHealthCheck.shared.checkHealth()
        // NOTE: Keep privacy .public for diagnostics - health status is not sensitive
        log.info("Apple Intelligence health check result: \(String(describing: health), privacy: .public)")

        switch health {
        case .healthy:
            log.info("Apple Intelligence: Available ✓")
            aiStatus = .available
            lastAIWarningReason = nil
            aiCancellationEvents.removeAll()
            cancellationBurstActive = false

        case .unavailable(let reason):
            switch reason {
            case .healthCheckCancelled:
                log.debug("Apple Intelligence: health check cancelled during startup")
                recordCancellationEvent()
                aiStatus = .checking
                lastAIWarningReason = nil
            default:
                if lastAIWarningReason != reason.userFacingMessage {
                    log.warning("Apple Intelligence: Unavailable - \(reason.userFacingMessage)")
                    lastAIWarningReason = reason.userFacingMessage
                } else {
                    log.debug("Apple Intelligence: Repeated unavailable reason - \(reason.userFacingMessage)")
                }
                aiCancellationEvents.removeAll()
                cancellationBurstActive = false
                aiStatus = .unavailable(reason: reason.userFacingMessage)
            }
        }
    }

    private func recordCancellationEvent(window: TimeInterval = 30) {
        let now = Date()
        self.aiCancellationEvents.append(now)
        let cutoff = now.addingTimeInterval(-window)
        self.aiCancellationEvents = self.aiCancellationEvents.filter { $0 >= cutoff }

        if self.aiCancellationEvents.count > 3 {
            if !cancellationBurstActive {
                log.warning("[AI-HEALTH] cancellationCount=\(self.aiCancellationEvents.count) window=\(Int(window))s")
                cancellationBurstActive = true
            }
        } else if cancellationBurstActive {
            cancellationBurstActive = false
        }
    }

    // MARK: - Manual Actions

    /// Refresh AI status (for retry button)
    func refreshAIStatus() async {
        await checkAppleIntelligenceHealth()
    }

    // MARK: - Hoover Observation

    private func startHooverObservation() {
        // DISABLED: AsyncStream can only have ONE consumer. ProjectSwitcherState already observes
        // the ProjectActivityMonitor event stream. Multiple observers cause the stream to terminate
        // prematurely, breaking project switching. If we need hoover events here, we should either:
        // 1. Have ProjectSwitcherState multicast events, or
        // 2. Observe ProjectSwitcherState's state changes instead
        // For now, hoover toast messages are disabled.
        self.log.info("StatusBar: hoover observation disabled (prevents AsyncStream multi-consumer issue)")
    }

    private func handleHooverEvent(_ event: ProjectEvent) async {
        hooverLastScan = Date()

        switch event.kind {
        case .transcriptUpdated:
            // Get project name if available
            let projectName = await getProjectName(for: event.projectId) ?? "project"
            showHooverMessage("Updated: \(projectName)")

        case .discovered:
            let projectName = await getProjectName(for: event.projectId) ?? "new project"
            showHooverMessage("Discovered: \(projectName)")

        case .removed:
            // Don't show removal messages
            break

        case .reordered:
            // Don't show reorder messages in status bar
            break
        }
    }

    private func showHooverMessage(_ message: String) {
        hooverMessage = message

        // Auto-fade after 3 seconds
        hooverFadeTask?.cancel()
        hooverFadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            self?.hooverMessage = nil
        }
    }

    private func getProjectName(for projectId: String) async -> String? {
        do {
            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
            let project = try orchestrator.getProject(id: projectId)
            return project?.name ?? URL(fileURLWithPath: project?.rootPath ?? "").lastPathComponent
        } catch {
            return nil
        }
    }
}
