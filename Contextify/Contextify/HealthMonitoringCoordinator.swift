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

    // Recovery backoff state - uses pure Core type for testability
    private var backoff = RecoveryBackoff()

    // Monitoring task and generation token (P1.4: prevents overlap on quick restart)
    private var monitoringTask: Task<Void, Never>?
    private var generation = UUID()

    /// State snapshot provided by ConversationMonitor for each health check
    /// NOTE: Does NOT include orchestrator - that stays on MainActor (P1.1)
    struct HealthCheckContext: Sendable {
        let projectId: String?
        let hasOrchestrator: Bool  // Just check existence, don't transport across actors
        let isSwitchingProjects: Bool
        let hasPendingIdleAlert: Bool
    }

    /// Recovery action types - orchestrator fetched on MainActor side (P1.1)
    enum RecoveryAction: Sendable {
        case watcher(projectId: String, targetTranscriptId: String?)
        case hoover(projectId: String)
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
        // Cancel any existing monitoring task
        monitoringTask?.cancel()
        monitoringTask = nil

        // Reset backoff state for new monitoring session (session boundary)
        backoff.reset()

        // New generation for this monitoring session
        // (single authoritative value - cancellation is the primary invalidation)
        let currentGeneration = UUID()
        generation = currentGeneration

        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await self.runHealthMonitoring(
                generation: currentGeneration,
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
        // Bump generation to ensure any loop iteration in progress exits promptly
        generation = UUID()
        monitoringTask?.cancel()
        monitoringTask = nil
        log.info("[HEALTH-COORD] Stopped health monitoring")
    }

    /// Reset recovery backoff (call when project switches or user fixes permissions)
    func resetRecoveryBackoff() {
        backoff.reset()
        log.debug("[HEALTH-COORD] Reset recovery backoff")
    }

    /// Get current backoff state for diagnostics
    var recoveryState: (failureCount: Int, lastFailure: Date?) {
        (backoff.failureCount, backoff.lastFailure)
    }

    // MARK: - Private Implementation

    private func runHealthMonitoring(
        generation: UUID,
        contextProvider: @escaping ContextProvider,
        diagnosticsProvider: @escaping DiagnosticsProvider,
        recoveryHandler: @escaping RecoveryHandler,
        idleAlertHandler: @escaping IdleAlertHandler
    ) async {
        log.info("🏥 Health monitoring started")

        while !Task.isCancelled {
            // P1.4: Bail if generation changed (new startMonitoring was called)
            guard generation == self.generation else {
                log.debug("🏥 Health monitoring stopped (generation mismatch)")
                return
            }

            do {
                let context = await contextProvider()

                // Check for pending idle alert (triggers immediate check)
                if context.hasPendingIdleAlert {
                    await idleAlertHandler()
                    // Bail if stopped/restarted during handler
                    guard !Task.isCancelled, generation == self.generation else { return }
                    // Re-fetch context after handler - state may have changed
                    let freshContext = await contextProvider()
                    await performHealthCheck(
                        trigger: "restart-guard",
                        context: freshContext,
                        generation: generation,
                        diagnosticsProvider: diagnosticsProvider,
                        recoveryHandler: recoveryHandler
                    )
                    continue
                }

                // Wait 30s between checks
                try await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }

                // P1.4: Check generation again after sleep
                guard generation == self.generation else {
                    log.debug("🏥 Health monitoring stopped (generation mismatch after sleep)")
                    return
                }

                // Fetch fresh context after sleep (state may have changed)
                let freshContext = await contextProvider()
                await performHealthCheck(
                    trigger: "interval",
                    context: freshContext,
                    generation: generation,
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

    // P2.1: Takes context directly instead of calling contextProvider
    private func performHealthCheck(
        trigger: String,
        context: HealthCheckContext,
        generation: UUID,
        diagnosticsProvider: @escaping DiagnosticsProvider,
        recoveryHandler: @escaping RecoveryHandler
    ) async {
        guard let projectId = context.projectId else {
            log.debug("🏥 Health check skipped (no current project)")
            return
        }

        // P1.1: Just check existence, orchestrator stays on MainActor
        guard context.hasOrchestrator else {
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

        // P1.3: Track which recovery types we've attempted this check (at most once per category)
        var didAttemptWatcherRecovery = false
        var didAttemptHooverRecovery = false

        // Check for critical issues and attempt recovery
        for issue in snapshot.issues where issue.severity == .critical {
            log.warning("🏥 Critical issue detected: \(issue.message, privacy: .public)")

            if issue.category == .watcherMissing, !didAttemptWatcherRecovery {
                // Check backoff before attempting recovery
                if shouldAttemptRecovery() {
                    // Final generation check before high-impact side effect
                    guard generation == self.generation else { return }
                    didAttemptWatcherRecovery = true
                    log.warning("[RECOVERY-TRIGGER] Recovering ALL watchers for project=\(projectId, privacy: .public)")
                    await recoveryHandler(.watcher(
                        projectId: projectId,
                        targetTranscriptId: nil  // nil = recover ALL
                    ))
                }
            } else if issue.category == .hooverStall, !didAttemptHooverRecovery {
                // Hoover recovery is exempt from backoff gating because:
                // 1. It's a lightweight restart of the ingestion loop, not a file system operation
                // 2. Hoover stalls are usually transient (unlike permission issues)
                // 3. The 30s health check interval already provides natural throttling
                guard generation == self.generation else { return }
                didAttemptHooverRecovery = true
                await recoveryHandler(.hoover(projectId: projectId))
            }
        }
    }

    /// Check if recovery should be attempted based on backoff state
    private func shouldAttemptRecovery() -> Bool {
        let shouldAttempt = backoff.shouldAttempt()

        // Log why recovery is blocked (for diagnostics)
        // Extract to locals for Swift 6 closure capture rules
        if !shouldAttempt {
            let failureCount = backoff.failureCount
            let backoffSeconds = backoff.currentBackoffSeconds
            if failureCount >= RecoveryBackoff.failureCap {
                log.warning("[RECOVERY-BACKOFF] Recovery disabled after \(failureCount) consecutive failures")
            } else {
                log.debug("[RECOVERY-BACKOFF] Skipping recovery (backoff: \(backoffSeconds)s, failures: \(failureCount))")
            }
        }

        return shouldAttempt
    }

    /// Record recovery success (resets backoff)
    func recordRecoverySuccess() {
        backoff.recordSuccess()
        log.info("[RECOVERY-BACKOFF] Recovery succeeded, backoff reset")
    }

    /// Record recovery failure (increments backoff)
    func recordRecoveryFailure() {
        backoff.recordFailure()
        let count = backoff.failureCount
        log.warning("[RECOVERY-BACKOFF] Recovery failed, failure count: \(count)")
    }
}
