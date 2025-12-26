//
//  HealthMonitoringCoordinator.swift
//  Contextify
//
//  Extracted from ConversationMonitor - manages health monitoring loop and recovery backoff
//

import Foundation
import OSLog
import ContextifyCore

/// Actor that coordinates health monitoring loop and recovery backoff logic
/// Extracted from ConversationMonitor to reduce god object complexity
actor HealthMonitoringCoordinator {
    private let log = Logger(subsystem: "dev.contextify.timeline", category: "HealthMonitor")

    // Recovery backoff state (previously in ConversationMonitor)
    private var watcherRecoveryFailureCount = 0
    private var lastWatcherRecoveryFailure: Date?
    private var lastHealthCheck: Date?

    // Monitoring task
    private var monitoringTask: Task<Void, Never>?

    /// State snapshot provided by ConversationMonitor for each health check
    struct HealthCheckContext: Sendable {
        let projectId: String?
        let orchestrator: TranscriptOrchestrator?
        let isSwitchingProjects: Bool
        let hasPendingIdleAlert: Bool
    }

    /// Recovery action types
    enum RecoveryAction: Sendable {
        case watcher(projectId: String, orchestrator: TranscriptOrchestrator, targetTranscriptId: String?)
        case hoover(projectId: String, orchestrator: TranscriptOrchestrator)
    }

    /// Callback types for ConversationMonitor integration
    typealias ContextProvider = @Sendable () async -> HealthCheckContext
    typealias DiagnosticsProvider = @Sendable () async -> TimelineDiagnosticsSnapshot?
    typealias RecoveryHandler = @Sendable (RecoveryAction) async -> Void
    typealias IdleAlertHandler = @Sendable () async -> Void

    // MARK: - Public API

    /// Start health monitoring loop
    /// - Parameters:
    ///   - contextProvider: Provides current state from ConversationMonitor
    ///   - diagnosticsProvider: Captures diagnostic snapshot for health check
    ///   - recoveryHandler: Handles recovery actions (watcher/hoover recovery)
    ///   - idleAlertHandler: Called when idle alert should be cleared
    func startMonitoring(
        contextProvider: @escaping ContextProvider,
        diagnosticsProvider: @escaping DiagnosticsProvider,
        recoveryHandler: @escaping RecoveryHandler,
        idleAlertHandler: @escaping IdleAlertHandler
    ) {
        // Cancel any existing monitoring
        monitoringTask?.cancel()

        // Reset backoff state for new monitoring session
        watcherRecoveryFailureCount = 0
        lastWatcherRecoveryFailure = nil

        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await self.runHealthMonitoring(
                contextProvider: contextProvider,
                diagnosticsProvider: diagnosticsProvider,
                recoveryHandler: recoveryHandler,
                idleAlertHandler: idleAlertHandler
            )
        }

        log.info("[HEALTH-COORD] Started health monitoring")
    }

    /// Stop health monitoring
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        log.info("[HEALTH-COORD] Stopped health monitoring")
    }

    /// Reset recovery backoff (call when project switches or user fixes permissions)
    func resetRecoveryBackoff() {
        watcherRecoveryFailureCount = 0
        lastWatcherRecoveryFailure = nil
        log.debug("[HEALTH-COORD] Reset recovery backoff")
    }

    /// Get current backoff state for diagnostics
    var recoveryState: (failureCount: Int, lastFailure: Date?) {
        (watcherRecoveryFailureCount, lastWatcherRecoveryFailure)
    }

    // MARK: - Private Implementation

    private func runHealthMonitoring(
        contextProvider: @escaping ContextProvider,
        diagnosticsProvider: @escaping DiagnosticsProvider,
        recoveryHandler: @escaping RecoveryHandler,
        idleAlertHandler: @escaping IdleAlertHandler
    ) async {
        log.info("🏥 Health monitoring started")

        while !Task.isCancelled {
            do {
                let context = await contextProvider()

                // Check for pending idle alert (triggers immediate check)
                if context.hasPendingIdleAlert {
                    await idleAlertHandler()
                    await performHealthCheck(
                        trigger: "restart-guard",
                        contextProvider: contextProvider,
                        diagnosticsProvider: diagnosticsProvider,
                        recoveryHandler: recoveryHandler
                    )
                    continue
                }

                // Wait 30s between checks
                try await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }

                await performHealthCheck(
                    trigger: "interval",
                    contextProvider: contextProvider,
                    diagnosticsProvider: diagnosticsProvider,
                    recoveryHandler: recoveryHandler
                )

            } catch is CancellationError {
                break
            } catch {
                log.error("Health monitoring error: \(error.localizedDescription)")
            }
        }

        log.info("🏥 Health monitoring stopped")
    }

    private func performHealthCheck(
        trigger: String,
        contextProvider: @escaping ContextProvider,
        diagnosticsProvider: @escaping DiagnosticsProvider,
        recoveryHandler: @escaping RecoveryHandler
    ) async {
        lastHealthCheck = Date()

        let context = await contextProvider()

        guard let projectId = context.projectId else {
            log.debug("🏥 Health check skipped (no current project)")
            return
        }

        guard let orchestrator = context.orchestrator else {
            log.warning("🏥 Health check skipped (no orchestrator)")
            return
        }

        // Capture diagnostic snapshot
        guard let snapshot = await diagnosticsProvider() else {
            return
        }

        log.debug("🏥 Health check (trigger=\(trigger, privacy: .public)): \(snapshot.issues.count) issues")

        // Skip during project switch to avoid spurious recovery attempts
        guard !context.isSwitchingProjects else {
            log.debug("🏥 Skipping health check during project switch")
            return
        }

        // Check for critical issues and attempt recovery
        for issue in snapshot.issues where issue.severity == .critical {
            log.warning("🏥 Critical issue detected: \(issue.message, privacy: .public)")

            if issue.category == .watcherMissing {
                // Check backoff before attempting recovery
                if shouldAttemptRecovery() {
                    log.warning("[RECOVERY-TRIGGER] Recovering ALL watchers for project=\(projectId, privacy: .public)")
                    await recoveryHandler(.watcher(
                        projectId: projectId,
                        orchestrator: orchestrator,
                        targetTranscriptId: nil  // nil = recover ALL
                    ))
                }
            } else if issue.category == .hooverStall {
                await recoveryHandler(.hoover(projectId: projectId, orchestrator: orchestrator))
            }
        }
    }

    /// Check if recovery should be attempted based on backoff state
    private func shouldAttemptRecovery() -> Bool {
        // After 5 failures, give up (security scope likely unavailable)
        let failureCount = self.watcherRecoveryFailureCount
        if failureCount >= 5 {
            log.warning("[RECOVERY-BACKOFF] Recovery disabled after \(failureCount) consecutive failures")
            return false
        }

        // Check exponential backoff
        if failureCount > 0 {
            let backoffSeconds = min(30 * (1 << failureCount), 600)  // 60s, 120s, 240s, 480s
            if let lastFailure = self.lastWatcherRecoveryFailure,
               Date().timeIntervalSince(lastFailure) < Double(backoffSeconds) {
                log.debug("[RECOVERY-BACKOFF] Skipping recovery (backoff: \(backoffSeconds)s, failures: \(failureCount))")
                return false
            }
        }

        return true
    }

    /// Record recovery success (resets backoff)
    func recordRecoverySuccess() {
        self.watcherRecoveryFailureCount = 0
        self.lastWatcherRecoveryFailure = nil
        log.info("[RECOVERY-BACKOFF] Recovery succeeded, backoff reset")
    }

    /// Record recovery failure (increments backoff)
    func recordRecoveryFailure() {
        self.watcherRecoveryFailureCount += 1
        self.lastWatcherRecoveryFailure = Date()
        let count = self.watcherRecoveryFailureCount
        log.warning("[RECOVERY-BACKOFF] Recovery failed, failure count: \(count)")
    }
}
