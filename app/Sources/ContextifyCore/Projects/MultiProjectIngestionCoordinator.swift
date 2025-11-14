import Foundation
import OSLog

struct TranscriptDescriptor: Sendable {
  let fileURL: URL
  let provider: String
  let sessionId: String?
  let lastModified: Date
}

struct ProjectTranscriptBatch: Sendable {
  let projectId: String
  let transcripts: [TranscriptDescriptor]
}

private struct PrimerQueueEntry: Sendable {
  let projectId: String
  let descriptor: TranscriptDescriptor
}

final class MultiProjectIngestionCoordinator {
  private let orchestrator: TranscriptOrchestrator
  private let config: ContextifyConfig
  private let log = Logger(subsystem: "dev.contextify", category: "MultiProjectIngestion")

  init(orchestrator: TranscriptOrchestrator, config: ContextifyConfig = .shared) {
    self.orchestrator = orchestrator
    self.config = config
  }

  func runPrimerAndBackfill(batches: [ProjectTranscriptBatch]) async throws {
    guard !batches.isEmpty else {
      log.info("[PRIMER-SKIP] No project batches available for ingestion")
      return
    }

    let primerTarget = config.primerTargetEntries
    let primerBatchLimit = max(1, config.primerBatchLimit)

    orchestrator.resetPrimerTracking()

    var primerProjects: [String] = []
    var primerBuckets: [String: [TranscriptDescriptor]] = [:]
    var backfillBatches: [ProjectTranscriptBatch] = []

    for batch in batches {
      guard !batch.transcripts.isEmpty else { continue }

      let entryCount = (try? orchestrator.getEntryCount(forProject: batch.projectId)) ?? 0

      if entryCount < primerTarget {
        let primerCount = min(primerBatchLimit, batch.transcripts.count)
        if primerCount > 0 {
          let primerSlice = Array(batch.transcripts.prefix(primerCount))
          primerBuckets[batch.projectId] = primerSlice
          primerProjects.append(batch.projectId)
          orchestrator.registerPrimer(projectId: batch.projectId, target: primerTarget)
          log.info(
            "[PRIMER-START] project=\(batch.projectId, privacy: .public) target=\(primerTarget, privacy: .public) entries=\(entryCount, privacy: .public) primer_transcripts=\(primerSlice.count, privacy: .public)"
          )
        }

        let remainder = Array(batch.transcripts.dropFirst(primerCount))
        if !remainder.isEmpty {
          backfillBatches.append(ProjectTranscriptBatch(projectId: batch.projectId, transcripts: remainder))
        }
      } else {
        backfillBatches.append(batch)
      }
    }

    let primerQueue = buildPrimerQueue(order: primerProjects, buckets: primerBuckets)

    if !primerQueue.isEmpty {
      log.info(
        "[PRIMER-QUEUE] entries=\(primerQueue.count, privacy: .public) projects=\(Set(primerProjects).count, privacy: .public) target=\(primerTarget, privacy: .public) limit=\(primerBatchLimit, privacy: .public)"
      )
      try await runPrimer(queue: primerQueue)
    } else {
      log.info("[PRIMER-SKIP] All projects already above target; skipping primer sweep")
    }

    if !backfillBatches.isEmpty {
      log.info("[BACKFILL-START] batches=\(backfillBatches.count, privacy: .public)")
    }

    for batch in backfillBatches {
      let transcriptFiles = batch.transcripts.map { descriptor in
        (url: descriptor.fileURL, provider: descriptor.provider, sessionId: descriptor.sessionId)
      }
      try await orchestrator.discoverTranscripts(
        projectId: batch.projectId,
        transcriptFiles: transcriptFiles,
        progress: nil,
        concurrency: 8
      )
    }
  }

  private func runPrimer(queue: [PrimerQueueEntry]) async throws {
    let scheduler = orchestrator.hooverScheduler
    let active = await scheduler.activeTaskCount
    let queued = await scheduler.queueDepth
    log.info(
      "[HOOVER-SCHED-PRIMER-STATUS] active=\(active, privacy: .public) queued=\(queued, privacy: .public) primer_entries=\(queue.count, privacy: .public)"
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      for entry in queue {
        log.info(
          "[PRIMER-ENQUEUE] project=\(entry.projectId, privacy: .public) transcript=\(entry.descriptor.fileURL.lastPathComponent, privacy: .public) provider=\(entry.descriptor.provider, privacy: .public)"
        )
        group.addTask { [orchestrator] in
          try await orchestrator.discoverTranscript(
            projectId: entry.projectId,
            fileURL: entry.descriptor.fileURL,
            provider: entry.descriptor.provider,
            providerSessionId: entry.descriptor.sessionId,
            startWatching: true,
            progress: nil,
            ingestLimit: .none
          )
        }
      }
      try await group.waitForAll()
    }
  }

  private func buildPrimerQueue(order: [String], buckets: [String: [TranscriptDescriptor]]) -> [PrimerQueueEntry] {
    guard !order.isEmpty else { return [] }
    var queue: [PrimerQueueEntry] = []
    var workingOrder = order
    var workingBuckets = buckets

    while !workingOrder.isEmpty {
      var index = 0
      while index < workingOrder.count {
        let projectId = workingOrder[index]
        guard var transcripts = workingBuckets[projectId], !transcripts.isEmpty else {
          workingOrder.remove(at: index)
          continue
        }

        let descriptor = transcripts.removeFirst()
        queue.append(PrimerQueueEntry(projectId: projectId, descriptor: descriptor))
        workingBuckets[projectId] = transcripts

        if transcripts.isEmpty {
          workingOrder.remove(at: index)
        } else {
          index += 1
        }
      }
    }

    return queue
  }
}

