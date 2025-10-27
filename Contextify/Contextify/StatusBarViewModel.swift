//
//  StatusBarViewModel.swift
//  Contextify
//
//  Event-driven view model for status bar with proper lifecycle management
//

import Foundation
import Observation

@MainActor
@Observable
final class StatusBarViewModel {
    // MARK: - Dependencies
    private let queueProvider: (any QueueStatsProvider)?

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
    private var queueObservationTask: Task<Void, Never>?
    private var isStarted: Bool = false

    init(queueProvider: (any QueueStatsProvider)?) {
        self.queueProvider = queueProvider
    }

    // MARK: - Lifecycle (called by View)

    /// Start observing queue and check AI health
    /// Idempotent: safe to call multiple times
    func start() {
        // Idempotence guard
        guard !isStarted else { return }
        isStarted = true

        guard let provider = queueProvider else {
            monitoringActive = false
            return
        }

        monitoringActive = true

        // Start event stream observation
        queueObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for await stats in provider.observeQueue() {
                guard !Task.isCancelled else { break }
                self.applyQueueStats(stats)
            }

            // Stream finished
            self.monitoringActive = false
        }

        // Check Apple Intelligence (one-shot)
        Task { @MainActor [weak self] in
            await self?.checkAppleIntelligenceHealth()
        }
    }

    /// Stop observing (called on view disappear)
    func stop() {
        queueObservationTask?.cancel()
        queueObservationTask = nil
        isStarted = false
        monitoringActive = false
    }

    // MARK: - State Application

    /// Apply queue stats (change detection to avoid unnecessary updates)
    private func applyQueueStats(_ stats: QueueStats) {
        // Only update if changed (reduces SwiftUI invalidation)
        if queueDepth != stats.pending ||
           isProcessing != stats.isProcessing ||
           estimatedSecondsRemaining != stats.estimatedSecondsRemaining ||
           recentErrorCount != stats.recentErrorCount ||
           topErrorReason != stats.topErrorReason {

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
            return
        }

        // Use existing health checker with 30s TTL
        let health = await LLMHealthCheck.shared.checkHealth()

        switch health {
        case .healthy:
            aiStatus = .available

        case .unavailable(let reason):
            aiStatus = .unavailable(reason: reason.userFacingMessage)
        }
    }

    // MARK: - Manual Actions

    /// Refresh AI status (for retry button)
    func refreshAIStatus() async {
        await checkAppleIntelligenceHealth()
    }
}
