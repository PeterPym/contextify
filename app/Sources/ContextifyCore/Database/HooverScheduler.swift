import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "HooverScheduler")

/// Actor-based scheduler with continuation-based suspension
/// Uses proper continuation queue to avoid stack buildup
public actor HooverScheduler {
  private struct WorkItem {
    let projectId: String
    let fileURL: URL
    let provider: String
    let sessionId: String?
  }

  private let orchestrator: TranscriptOrchestrator
  private let maxConcurrency: Int
  private var activeCount: Int = 0

  // Proper queue with continuations (not Task.sleep)
  private var pendingWork: [(WorkItem, CheckedContinuation<Void, Error>)] = []

  // Recursion prevention - track both queued and actively processing paths
  private var queuedPaths: Set<String> = []
  private var processingPaths: Set<String> = []

  public init(
    orchestrator: TranscriptOrchestrator,
    maxConcurrency: Int = 6
  ) {
    self.orchestrator = orchestrator
    self.maxConcurrency = maxConcurrency
    log.info("[HOOVER-SCHED-INIT] maxConcurrency=\(maxConcurrency, privacy: .public)")
  }

  /// Enqueue work - suspends via continuation if at capacity
  public func enqueue(
    projectId: String,
    fileURL: URL,
    provider: String,
    sessionId: String?
  ) async throws {
    // Prevent recursion/duplicates - check both queued and processing
    if queuedPaths.contains(fileURL.path) || processingPaths.contains(fileURL.path) {
      log.debug("[HOOVER-SCHED-SKIP] Already queued/processing: \(fileURL.lastPathComponent, privacy: .public)")
      return
    }

    let item = WorkItem(
      projectId: projectId,
      fileURL: fileURL,
      provider: provider,
      sessionId: sessionId
    )

    // Suspend if at capacity (proper continuation-based)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      if self.activeCount < self.maxConcurrency {
        // Execute immediately
        self.processingPaths.insert(fileURL.path)
        self.activeCount += 1
        log.info("[HOOVER-SCHED-START] \(fileURL.lastPathComponent, privacy: .public) active=\(self.activeCount, privacy: .public)/\(self.maxConcurrency, privacy: .public) queued=0")
        continuation.resume()
      } else {
        // Queue for later
        self.queuedPaths.insert(fileURL.path)
        self.pendingWork.append((item, continuation))
        log.info("[HOOVER-SCHED-QUEUE] \(fileURL.lastPathComponent, privacy: .public) active=\(self.activeCount, privacy: .public)/\(self.maxConcurrency, privacy: .public) queued=\(self.pendingWork.count, privacy: .public)")
      }
    }

    // Continuation resumed - execute work
    defer {
      Task { await self.taskCompleted(fileURL: fileURL) }
    }

    try orchestrator.discoverTranscriptInternal(
      projectId: item.projectId,
      fileURL: item.fileURL,
      provider: item.provider,
      providerSessionId: item.sessionId,
      startWatching: true,
      bypassScheduler: true
    )
  }

  private func taskCompleted(fileURL: URL) {
    processingPaths.remove(fileURL.path)
    activeCount -= 1
    log.debug("[HOOVER-SCHED-COMPLETE] active=\(self.activeCount, privacy: .public)")

    // Resume next pending item if any
    if !pendingWork.isEmpty {
      let (item, continuation) = pendingWork.removeFirst()
      queuedPaths.remove(item.fileURL.path)  // No longer queued
      processingPaths.insert(item.fileURL.path)  // Now processing
      activeCount += 1
      log.info("[HOOVER-SCHED-RESUME] \(item.fileURL.lastPathComponent, privacy: .public) active=\(self.activeCount, privacy: .public)/\(self.maxConcurrency, privacy: .public) queued=\(self.pendingWork.count, privacy: .public)")
      continuation.resume()
    }
  }

  // Telemetry
  public var queueDepth: Int { pendingWork.count }
  public var activeTaskCount: Int { activeCount }

  public func logStatus() {
    log.info("[HOOVER-SCHED-STATUS] active=\(self.activeCount, privacy: .public) queued=\(self.pendingWork.count, privacy: .public) capacity=\(self.maxConcurrency, privacy: .public)")
  }
}
