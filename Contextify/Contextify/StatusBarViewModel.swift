//
//  StatusBarViewModel.swift
//  Contextify
//
//  Event-driven view model for status bar with proper lifecycle management
//

import Foundation
import Observation
import OSLog

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

    // Apple Intelligence status
    enum AIStatus: Sendable, Equatable {
        case available
        case unavailable(reason: String)
        case error(message: String)
    }
    private(set) var aiStatus: AIStatus = .unavailable(reason: "macOS 26+ required")

    // MARK: - Lifecycle State
    private var queueObservationTasks: [Task<Void, Never>] = []
    private var aiHealthCheckTask: Task<Void, Never>?
    private var isStarted: Bool = false

    init(queueProviders: [any QueueStatsProvider]) {
        self.queueProviders = queueProviders
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

        // Start observation task for each provider
        for provider in self.queueProviders {
            let task = Task { @MainActor [weak self] in
                guard let self else { return }

                for await stats in provider.observeQueue() {
                    guard !Task.isCancelled else { break }
                    self.aggregateStats(from: stats)
                }

                // Stream finished (provider ended or cancelled) - clear stale state
                self.monitoringActive = false
                self.queueDepth = 0
                self.isProcessing = false
                self.estimatedSecondsRemaining = 0
                self.recentErrorCount = 0
                self.topErrorReason = nil
            }
            queueObservationTasks.append(task)
        }

        // Check Apple Intelligence periodically (every 30s to respect cache)
        aiHealthCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Initial check
            await self.checkAppleIntelligenceHealth()

            // Periodic refresh (every 30s)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled else { break }
                await self.checkAppleIntelligenceHealth()
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
        isStarted = false
        monitoringActive = false

        // Clear transient values to avoid stale visuals if view hides
        queueDepth = 0
        isProcessing = false
        estimatedSecondsRemaining = 0
    }

    // MARK: - State Aggregation

    /// Aggregate stats from a single provider
    /// Note: This is called from multiple streams, so we need to aggregate
    private func aggregateStats(from stats: QueueStats) {
        // For now, just use the latest stats from any provider
        // A more sophisticated approach would maintain separate state per provider
        // and sum/max the values, but this simple approach works for MVP

        // Only update if changed (reduces SwiftUI invalidation)
        if queueDepth != stats.pending
            || isProcessing != stats.isProcessing
            || estimatedSecondsRemaining != stats.estimatedSecondsRemaining
            || recentErrorCount != stats.recentErrorCount
            || topErrorReason != stats.topErrorReason {

            queueDepth = stats.pending
            isProcessing = stats.isProcessing
            estimatedSecondsRemaining = stats.estimatedSecondsRemaining
            recentErrorCount = stats.recentErrorCount
            topErrorReason = stats.topErrorReason
        }
    }

    // MARK: - Apple Intelligence Health

    /// Check AI availability using existing LLMHealthCheck
    private func checkAppleIntelligenceHealth() async {
        guard #available(macOS 26.0, *) else {
            aiStatus = .unavailable(reason: "Requires macOS 26+")
            log.debug("Apple Intelligence check: macOS < 26")
            return
        }

        // Use existing health checker with 30s TTL
        let health = await LLMHealthCheck.shared.checkHealth()
        log.info("Apple Intelligence health check result: \(String(describing: health))")

        switch health {
        case .healthy:
            log.info("Apple Intelligence: Available ✓")
            aiStatus = .available

        case .unavailable(let reason):
            log.warning("Apple Intelligence: Unavailable - \(reason.userFacingMessage)")
            aiStatus = .unavailable(reason: reason.userFacingMessage)
        }
    }

    // MARK: - Manual Actions

    /// Refresh AI status (for retry button)
    func refreshAIStatus() async {
        await checkAppleIntelligenceHealth()
    }
}
