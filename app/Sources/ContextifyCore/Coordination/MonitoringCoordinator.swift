import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "MonitoringCoordinator")

/// Coordinates watcher lifecycle around the active project with hysteresis to avoid thrash.
public actor MonitoringCoordinator {
  private let orchestrator: TranscriptOrchestrator

  private(set) var activeProjectId: String?
  private var pendingTeardowns: [String: Task<Void, Never>] = [:]
  private let teardownDelay: Duration = .seconds(5)

  public init(orchestrator: TranscriptOrchestrator) {
    self.orchestrator = orchestrator
  }

  /// Activate a project and start per-file watchers for it.
  public func activateProject(_ projectId: String) async {
    if let teardown = pendingTeardowns[projectId] {
      teardown.cancel()
      pendingTeardowns.removeValue(forKey: projectId)
      log.info("[LAZY-WATCHER] Cancelled teardown for project=\(projectId, privacy: .public)")
    }

    if let previousId = activeProjectId, previousId != projectId {
      scheduleTeardown(for: previousId)
    }

    activeProjectId = projectId

    do {
      let summary = try orchestrator.ensureProjectWatcher(projectId: projectId)
      log.info("[LAZY-WATCHER] activeProjectId=\(projectId, privacy: .public) watcherCount=\(summary.startedCount + summary.alreadyActiveCount, privacy: .public)")
    } catch {
      log.error("[LAZY-WATCHER] Failed to start watchers for project=\(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    // Run rehoover in the background to avoid blocking activation.
    Task.detached(priority: .utility) { [orchestrator] in
      _ = try? await orchestrator.rehooverDirtyTranscripts(projectId: projectId)
    }
  }

  /// Stop watchers for all projects and cancel any pending teardown.
  public func deactivateAll() async {
    pendingTeardowns.values.forEach { $0.cancel() }
    pendingTeardowns.removeAll()

    if let activeId = activeProjectId {
      try? orchestrator.stopAllWatchers(forProjectId: activeId)
      log.info("[LAZY-WATCHER] Stopped watchers for project=\(activeId, privacy: .public)")
    }

    activeProjectId = nil
  }

  public func isActiveProject(_ projectId: String) -> Bool {
    activeProjectId == projectId
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
