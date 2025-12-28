import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "MonitoringCoordinator")

/// Coordinates watcher lifecycle around the active project with hysteresis to avoid thrash.
public actor MonitoringCoordinator {
  private let orchestrator: TranscriptOrchestrator

  private(set) var activeProjectId: String?
  private var watchersReady: Bool = false
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

    // P0.1 FIX: Only mark as active AFTER watchers successfully start
    watchersReady = false

    do {
      let summary = try orchestrator.ensureProjectWatcher(projectId: projectId)
      activeProjectId = projectId
      watchersReady = true
      log.info("[LAZY-WATCHER] activeProjectId=\(projectId, privacy: .public) watcherCount=\(summary.startedCount + summary.alreadyActiveCount, privacy: .public)")
    } catch {
      log.error("[LAZY-WATCHER] Failed to start watchers for project=\(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
      // Note: activeProjectId remains previous value; FSEvents will handle this project
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
    watchersReady = false
  }

  public func isActiveProject(_ projectId: String) -> Bool {
    activeProjectId == projectId
  }

  /// P0.1: Check if project is active AND has watchers ready
  /// Use this for determining whether FSEvents should handle a project
  public func isActiveProjectWithWatchers(_ projectId: String) -> Bool {
    activeProjectId == projectId && watchersReady
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
