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

  private struct PendingItem {
    let work: WorkItem
    let isPrimer: Bool
    let continuation: CheckedContinuation<Void, Error>
  }

  private let orchestrator: TranscriptOrchestrator
  private let maxConcurrency: Int
  private var activeCount: Int = 0

  // Proper queue with continuations (not Task.sleep)
  private var pendingWork: [PendingItem] = []

  // Recursion prevention - track both queued and actively processing paths
  private var queuedPaths: Set<String> = []
  private var processingPaths: Set<String> = []
  private var skipCount: Int = 0

  // Progress tracking for notifications
  private var completedByProject: [String: Int] = [:]  // projectId -> completed count
  private var totalByProject: [String: Int] = [:]      // projectId -> total count

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
    sessionId: String?,
    isPrimer: Bool = false
  ) async throws {
    // Prevent recursion/duplicates - check both queued and processing
    if queuedPaths.contains(fileURL.path) || processingPaths.contains(fileURL.path) {
      skipCount += 1
      log.info("[HOOVER-SCHED-SKIP] Already queued/processing: \(fileURL.lastPathComponent, privacy: .public)")
      return
    }

    let item = WorkItem(
      projectId: projectId,
      fileURL: fileURL,
      provider: provider,
      sessionId: sessionId
    )

    // Track total transcripts for progress notifications
    totalByProject[projectId, default: 0] += 1

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
        let pending = PendingItem(work: item, isPrimer: isPrimer, continuation: continuation)
        if isPrimer {
          self.pendingWork.insert(pending, at: 0)
        } else {
          self.pendingWork.append(pending)
        }
        log.info(
          "[HOOVER-SCHED-QUEUE] \(fileURL.lastPathComponent, privacy: .public) active=\(self.activeCount, privacy: .public)/\(self.maxConcurrency, privacy: .public) queued=\(self.pendingWork.count, privacy: .public) primer=\(isPrimer, privacy: .public) primer_pending=\(self.pendingPrimerCount, privacy: .public)"
        )
      }
    }

    // Continuation resumed - execute work
    defer {
      Task { await self.taskCompleted(fileURL: fileURL, projectId: item.projectId) }
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

  private func taskCompleted(fileURL: URL, projectId: String) {
    processingPaths.remove(fileURL.path)
    activeCount -= 1

    // Track progress per project and post notification if needed
    completedByProject[projectId, default: 0] += 1
    let completed = completedByProject[projectId]!
    let total = totalByProject[projectId] ?? 0

    // Post progress notification at intervals: first 3, then every 10, plus final completion
    let shouldNotify = completed <= 3 || completed % 10 == 0 || completed == total
    if shouldNotify {
      log.info("[HOOVER-PROGRESS] project=\(projectId, privacy: .public) completed=\(completed, privacy: .public)/\(total, privacy: .public)")
      Task { @MainActor in
        NotificationCenter.default.post(
          name: .transcriptHooveringProgress,
          object: projectId,
          userInfo: [
            "transcriptCount": completed,
            "totalTranscripts": total,
            "projectId": projectId
          ]
        )
      }
    }

    log.debug("[HOOVER-SCHED-COMPLETE] active=\(self.activeCount, privacy: .public)")

    // Resume next pending item if any
    if !pendingWork.isEmpty {
      let pending = pendingWork.removeFirst()
      queuedPaths.remove(pending.work.fileURL.path)  // No longer queued
      processingPaths.insert(pending.work.fileURL.path)  // Now processing
      activeCount += 1
      log.info(
        "[HOOVER-SCHED-RESUME] \(pending.work.fileURL.lastPathComponent, privacy: .public) active=\(self.activeCount, privacy: .public)/\(self.maxConcurrency, privacy: .public) queued=\(self.pendingWork.count, privacy: .public) primer=\(pending.isPrimer, privacy: .public) primer_pending=\(self.pendingPrimerCount, privacy: .public)"
      )
      pending.continuation.resume()
    }
  }

  // Telemetry
  public var queueDepth: Int { pendingWork.count }
  public var activeTaskCount: Int { activeCount }

  private var pendingPrimerCount: Int {
    pendingWork.filter { $0.isPrimer }.count
  }

  public func logStatus() {
    log.info(
      "[HOOVER-SCHED-STATUS] active=\(self.activeCount, privacy: .public) queued=\(self.pendingWork.count, privacy: .public) primer_pending=\(self.pendingPrimerCount, privacy: .public) skipped=\(self.skipCount, privacy: .public) capacity=\(self.maxConcurrency, privacy: .public)"
    )
  }
}
