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

  func runPrimerAndBackfill(
    batches: [ProjectTranscriptBatch],
    activeProjectId: String?
  ) async throws {
    guard !batches.isEmpty else {
      log.info("[PRIMER-SKIP] No project batches available for ingestion")
      return
    }

    let primerTarget = config.primerTargetEntries
    let primerBatchLimit = max(1, config.primerBatchLimit)
    let activePrimerBatchLimit = max(primerBatchLimit, primerBatchLimit * 2)

    orchestrator.resetPrimerTracking()

    var primerProjects: [String] = []
    var primerBuckets: [String: [TranscriptDescriptor]] = [:]
    var backfillBatches: [ProjectTranscriptBatch] = []

    for batch in batches {
      guard !batch.transcripts.isEmpty else { continue }

      let entryCount = (try? orchestrator.getEntryCount(forProject: batch.projectId)) ?? 0
      let isActiveProject = (batch.projectId == activeProjectId)
      let effectivePrimerLimit = isActiveProject ? activePrimerBatchLimit : primerBatchLimit

      if entryCount < primerTarget {
        let primerCount = min(effectivePrimerLimit, batch.transcripts.count)
        if primerCount > 0 {
          let primerSlice = Array(batch.transcripts.prefix(primerCount))
          if primerBuckets[batch.projectId] == nil {
            primerProjects.append(batch.projectId)
          }
          primerBuckets[batch.projectId] = primerSlice
          orchestrator.registerPrimer(projectId: batch.projectId, target: primerTarget)
          log.info(
            "[PRIMER-START] project=\(batch.projectId, privacy: .public) target=\(primerTarget, privacy: .public) entries=\(entryCount, privacy: .public) primer_transcripts=\(primerSlice.count, privacy: .public) bias=\(isActiveProject, privacy: .public)"
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

    if let activeProjectId {
      await forcePrimerRegistrationIfNeeded(
        projectId: activeProjectId,
        primerTarget: primerTarget,
        limit: activePrimerBatchLimit,
        primerProjects: &primerProjects,
        primerBuckets: &primerBuckets,
        sourceBatches: batches
      )
    }

    var orderedProjects = primerProjects
    if let activeProjectId,
       primerBuckets[activeProjectId] != nil {
      orderedProjects.removeAll(where: { $0 == activeProjectId })
      orderedProjects.insert(activeProjectId, at: 0)
      if let activeDescriptors = primerBuckets[activeProjectId] {
        log.info(
          "[PRIMER-BIAS] project=\(activeProjectId, privacy: .public) primer_transcripts=\(activeDescriptors.count, privacy: .public)"
        )
      }
    }

    let primerQueue = buildPrimerQueue(order: orderedProjects, buckets: primerBuckets)

    if !primerQueue.isEmpty {
      log.info(
        "[PRIMER-QUEUE] entries=\(primerQueue.count, privacy: .public) projects=\(Set(primerProjects).count, privacy: .public) target=\(primerTarget, privacy: .public) limit=\(primerBatchLimit, privacy: .public)"
      )
      let startWatchingForProject: (String) -> Bool = { projectId in
        guard MonitorConfig.lazyWatchersEnabled else { return true }
        return projectId == activeProjectId
      }
      try await runPrimer(queue: primerQueue, startWatchingForProject: startWatchingForProject)
    } else {
      log.info("[PRIMER-SKIP] All projects already above target; skipping primer sweep")
    }

    if !backfillBatches.isEmpty {
      log.info("[BACKFILL-START] batches=\(backfillBatches.count, privacy: .public)")
    }

    for batch in backfillBatches {
      let shouldStartWatching: Bool
      if MonitorConfig.lazyWatchersEnabled {
        shouldStartWatching = (batch.projectId == activeProjectId)
      } else {
        shouldStartWatching = true
      }
      let transcriptFiles = batch.transcripts.map { descriptor in
        (url: descriptor.fileURL, provider: descriptor.provider, sessionId: descriptor.sessionId)
      }
      try await orchestrator.discoverTranscripts(
        projectId: batch.projectId,
        transcriptFiles: transcriptFiles,
        progress: nil,
        concurrency: 8,
        startWatching: shouldStartWatching
      )
    }
  }

  private func forcePrimerRegistrationIfNeeded(
    projectId: String,
    primerTarget: Int,
    limit: Int,
    primerProjects: inout [String],
    primerBuckets: inout [String: [TranscriptDescriptor]],
    sourceBatches: [ProjectTranscriptBatch]
  ) async {
    guard primerBuckets[projectId] == nil else { return }

    let entryCount = (try? orchestrator.getEntryCount(forProject: projectId)) ?? 0
    guard entryCount < primerTarget else { return }

    if let descriptors = prepareDescriptors(for: projectId, limit: limit, sourceBatches: sourceBatches), !descriptors.isEmpty {
      primerBuckets[projectId] = descriptors
      if !primerProjects.contains(projectId) {
        primerProjects.append(projectId)
      }
      orchestrator.registerPrimer(projectId: projectId, target: primerTarget)
      log.info(
        "[PRIMER-FORCE] project=\(projectId, privacy: .public) descriptors=\(descriptors.count, privacy: .public) entry_count=\(entryCount, privacy: .public)"
      )
    } else {
      log.warning("[PRIMER-FORCE] Unable to prepare descriptors for project \(projectId, privacy: .public)")
    }
  }

  private func prepareDescriptors(
    for projectId: String,
    limit: Int,
    sourceBatches: [ProjectTranscriptBatch]
  ) -> [TranscriptDescriptor]? {
    if let batch = sourceBatches.first(where: { $0.projectId == projectId }),
       !batch.transcripts.isEmpty {
      return Array(batch.transcripts.prefix(limit))
    }

    guard let transcripts = try? orchestrator.getTranscripts(forProject: projectId),
          !transcripts.isEmpty else { return nil }

    let sorted = transcripts.sorted { lhs, rhs in
      lhs.lastModified > rhs.lastModified
    }

    let mapped = sorted.prefix(limit).map { transcript in
      TranscriptDescriptor(
        fileURL: URL(fileURLWithPath: transcript.filePath),
        provider: transcript.provider,
        sessionId: transcript.providerSessionId,
        lastModified: Date(timeIntervalSince1970: TimeInterval(transcript.lastModified))
      )
    }
    return mapped
  }

  private func runPrimer(
    queue: [PrimerQueueEntry],
    startWatchingForProject: @escaping (String) -> Bool
  ) async throws {
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
        let startWatching = startWatchingForProject(entry.projectId)
        group.addTask { [orchestrator, startWatching] in
          try await orchestrator.discoverTranscript(
            projectId: entry.projectId,
            fileURL: entry.descriptor.fileURL,
            provider: entry.descriptor.provider,
            providerSessionId: entry.descriptor.sessionId,
            startWatching: startWatching,
            progress: nil,
            ingestLimit: .none,
            isPrimer: true
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
