import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "MonitoringCoordinator")

/// Protocol for orchestrator operations used by MonitoringCoordinator.
/// Enables testing with mock implementations.
public protocol TranscriptOrchestratorProtocol: Sendable {
  nonisolated func ensureProjectWatcher(projectId: String, targetTranscriptId: String?) throws -> WatcherRecoverySummary
  nonisolated func stopAllWatchers(forProjectId: String) throws
  nonisolated func rehooverDirtyTranscripts(projectId: String) async throws -> Int
}

/// Extension to make TranscriptOrchestrator conform to the protocol
extension TranscriptOrchestrator: TranscriptOrchestratorProtocol {}

/// Coordinates watcher lifecycle around the active project with hysteresis to avoid thrash.
public actor MonitoringCoordinator {
  private let orchestrator: any TranscriptOrchestratorProtocol

  private(set) var activeProjectId: String?
  private var watchersReadyProjectId: String? = nil
  private var pendingTeardowns: [String: Task<Void, Never>] = [:]
  private let teardownDelay: Duration = .seconds(5)

  public init(orchestrator: any TranscriptOrchestratorProtocol) {
    self.orchestrator = orchestrator
  }

  /// Convenience initializer for production use with TranscriptOrchestrator
  public init(orchestrator: TranscriptOrchestrator) {
    self.orchestrator = orchestrator
  }

  /// Activate a project and start per-file watchers for it.
  public func activateProject(_ projectId: String) async {
    // Cancel any pending teardown for this project (reactivation)
    if let teardown = pendingTeardowns[projectId] {
      teardown.cancel()
      pendingTeardowns.removeValue(forKey: projectId)
      log.info("[LAZY-WATCHER] Cancelled teardown for project=\(projectId, privacy: .public)")
    }

    let previousId = activeProjectId

    do {
      let summary = try orchestrator.ensureProjectWatcher(projectId: projectId, targetTranscriptId: nil)

      // Only schedule teardown for previous AFTER new watchers started
      if let previousId, previousId != projectId {
        scheduleTeardown(for: previousId)
      }

      activeProjectId = projectId
      watchersReadyProjectId = projectId
      log.info("[LAZY-WATCHER] activeProjectId=\(projectId, privacy: .public) watcherCount=\(summary.startedCount + summary.alreadyActiveCount, privacy: .public)")
    } catch {
      log.error("[LAZY-WATCHER] Failed to start watchers for project=\(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
      // Leave previous project active, don't schedule its teardown
    }

    // Run rehoover in the background to avoid blocking activation.
    Task.detached(priority: .utility) { [orchestrator] in
      do {
        let count = try await orchestrator.rehooverDirtyTranscripts(projectId: projectId)
        if count > 0 {
          log.info("[LAZY-WATCHER] Rehoovered \(count, privacy: .public) transcripts on activation")
        }
      } catch {
        log.error("[LAZY-WATCHER] Rehoover failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Stop watchers for all projects and cancel any pending teardown.
  public func deactivateAll() async {
    // P0.2 FIX: Stop watchers for ALL projects (active + pending teardown)
    let idsToStop = Set(pendingTeardowns.keys).union(activeProjectId.map { [$0] } ?? [])

    pendingTeardowns.values.forEach { $0.cancel() }
    pendingTeardowns.removeAll()

    for id in idsToStop {
      try? orchestrator.stopAllWatchers(forProjectId: id)
      log.info("[LAZY-WATCHER] Stopped watchers for project=\(id, privacy: .public)")
    }

    activeProjectId = nil
    watchersReadyProjectId = nil
  }

  /// Internal helper to check if a project is selected/active.
  /// Private to prevent accidental misuse - use isActiveProjectWithWatchers for watcher decisions.
  private func isActiveProject(_ projectId: String) -> Bool {
    activeProjectId == projectId
  }

  /// P0.1: Check if project is active AND has watchers ready
  /// Use this for determining whether FSEvents should handle a project
  public func isActiveProjectWithWatchers(_ projectId: String) -> Bool {
    activeProjectId == projectId && watchersReadyProjectId == projectId
  }

  /// Check if a project has a pending teardown scheduled.
  /// Exposed for testing purposes.
  public func hasPendingTeardown(for projectId: String) -> Bool {
    pendingTeardowns[projectId] != nil
  }

  // MARK: - Private helpers

  private func scheduleTeardown(for projectId: String) {
    pendingTeardowns[projectId]?.cancel()

    log.info("[LAZY-WATCHER] Teardown scheduled project=\(projectId, privacy: .public)")

    let delay = teardownDelay
    let task = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard let self else { return }
      guard !Task.isCancelled else { return }
      await self.executeTeardown(for: projectId)
    }

    pendingTeardowns[projectId] = task
  }

  private func executeTeardown(for projectId: String) async {
    do {
      try orchestrator.stopAllWatchers(forProjectId: projectId)
      log.info("[LAZY-WATCHER] Teardown executed project=\(projectId, privacy: .public)")
    } catch {
      log.error("[LAZY-WATCHER] Teardown failed project=\(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    pendingTeardowns.removeValue(forKey: projectId)
  }
}
