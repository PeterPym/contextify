import Foundation
import OSLog

/// Fast-path transcript ingestion coordinator.
/// NOTE: This class is manually synchronized and is safe to send across concurrency domains.
/// The `enqueuedCompletions` and `notifiedProjects` state is protected by the serial `completionQueue`
/// or by being accessed only from the serial loop in `runFastPath`. The `orchestrator` dependency
/// is already `@unchecked Sendable`.
public final class FastPathIngestionCoordinator: @unchecked Sendable {
  private let orchestrator: TranscriptOrchestrator
  private let previewLimit: Int
  private let maxPreviewConcurrency: Int
  private let maxTranscriptsPerProject: Int
  private let completionQueue = DispatchQueue(label: "dev.contextify.fastpath.completions", qos: .utility)
  private var enqueuedCompletions: Set<String> = []
  private var notifiedProjects: Set<String> = []
  private let log = Logger(subsystem: "dev.contextify", category: "FastPathIngestion")

  public init(
    orchestrator: TranscriptOrchestrator,
    previewLimit: Int = 25,
    maxPreviewConcurrency: Int = 4,
    maxTranscriptsPerProject: Int = 5
  ) {
    self.orchestrator = orchestrator
    self.previewLimit = previewLimit
    self.maxPreviewConcurrency = max(1, maxPreviewConcurrency)
    self.maxTranscriptsPerProject = max(1, maxTranscriptsPerProject)
  }

  public func resumePendingCompletions() {
    completionQueue.async {
      guard let partials = try? self.orchestrator.getPartialTranscripts() else {
        self.log.error("[FAST-PATH-RESUME] Failed to load partial transcripts")
        return
      }
      if !partials.isEmpty {
        self.log.info("[FAST-PATH-RESUME] Resuming \(partials.count, privacy: .public) partial transcripts")
      }
      partials.forEach { self.enqueueCompletion(transcriptId: $0.id) }
    }
  }

  public func runFastPath(projectIds: [String], activeProjectId: String?) async {
    let startTime = Date()
    let orderedIds = orderProjects(projectIds: projectIds, activeProjectId: activeProjectId)

    log.info("[FAST-PATH-PREVIEW-START] projects=\(projectIds.count, privacy: .public) active=\(activeProjectId ?? "none", privacy: .public)")

    for projectId in orderedIds {
      await processProject(projectId: projectId)
    }

    let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
    log.info("[FAST-PATH-PREVIEW-DONE] duration_ms=\(durationMs, privacy: .public) projects=\(orderedIds.count, privacy: .public)")
  }

  private func orderProjects(projectIds: [String], activeProjectId: String?) -> [String] {
    var ordered: [String] = []
    var seen: Set<String> = []

    if let active = activeProjectId {
      if seen.insert(active).inserted {
        ordered.append(active)
      }
    }

    for projectId in projectIds {
      if seen.insert(projectId).inserted {
        ordered.append(projectId)
      }
    }
    return ordered
  }

  private func processProject(projectId: String) async {
    log.info("[FAST-PATH-ENTRY] processProject started for project: \(projectId, privacy: .public)")

    let transcripts: [Transcript]
    do {
      transcripts = try orchestrator.getTranscripts(forProject: projectId)
    } catch {
      log.error("[FAST-PATH] Failed to load transcripts for \(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return
    }

    // Log each transcript's state BEFORE filtering
    log.info("[FAST-PATH-TRANSCRIPT] Found \(transcripts.count, privacy: .public) transcripts for project \(projectId, privacy: .public)")
    for transcript in transcripts.prefix(10) {
      log.info("[FAST-PATH-TRANSCRIPT] Transcript \(transcript.id.prefix(8), privacy: .public) ingestState: \(transcript.ingestState, privacy: .public) lastProcessedLine: \(transcript.lastProcessedLine, privacy: .public)")
    }

    let targets = transcripts.filter { $0.ingestState != "complete" }

    // Log filter results
    log.info("[FAST-PATH-FILTER] Filtered \(targets.count, privacy: .public) targets from \(transcripts.count, privacy: .public) total transcripts for project \(projectId, privacy: .public)")

    guard !targets.isEmpty else {
      log.info("[FAST-PATH-FILTER] No partial transcripts to process, bailing out for project \(projectId, privacy: .public)")
      return
    }

    let subset = Array(targets.prefix(maxTranscriptsPerProject))
    log.info("[FAST-PATH-PROJECT] Processing \(subset.count, privacy: .public) transcripts for project \(projectId, privacy: .public)")

    // Only notify UI once per project (on first transcript completion)
    let shouldNotifyUI = !notifiedProjects.contains(projectId)
    if shouldNotifyUI {
      notifiedProjects.insert(projectId)
    }

    // Protect isFirstTranscript flag from concurrent access within TaskGroup
    let isFirstTranscript = OSAllocatedUnfairLock(initialState: true)
    await withTaskGroup(of: Void.self) { group in
      for transcript in subset {
        group.addTask {
          // Atomic check-and-set to ensure only one task notifies UI
          let shouldNotifyForThisOne = isFirstTranscript.withLock { isFirst in
            let result = isFirst
            isFirst = false
            return result
          }
          let notifyForThisTranscript = shouldNotifyUI && shouldNotifyForThisOne

          self.log.info("[FAST-PATH-NOTIFY] Transcript \(transcript.id.prefix(8), privacy: .public) notifyUI: \(notifyForThisTranscript, privacy: .public) (shouldNotifyUI: \(shouldNotifyUI, privacy: .public), isFirst: \(shouldNotifyForThisOne, privacy: .public))")

          do {
            let needsCompletion = try self.orchestrator.ingestTranscript(
              transcriptId: transcript.id,
              mode: .preview(entries: self.previewLimit),
              notifyUI: notifyForThisTranscript
            )
            if needsCompletion {
              self.enqueueCompletion(transcriptId: transcript.id)
            }
          } catch {
            self.log.error("[FAST-PATH] Preview ingest failed for \(transcript.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
          }
        }
      }
    }
  }

  private func enqueueCompletion(transcriptId: String) {
    completionQueue.async {
      guard !self.enqueuedCompletions.contains(transcriptId) else { return }
      self.enqueuedCompletions.insert(transcriptId)

      Task(priority: .utility) {
        defer {
          self.completionQueue.async {
            self.enqueuedCompletions.remove(transcriptId)
          }
        }

        do {
          _ = try self.orchestrator.ingestTranscript(
            transcriptId: transcriptId,
            mode: .complete,
            notifyUI: false  // UI already notified during preview
          )
        } catch {
          self.log.error("[FAST-PATH] Background completion failed for \(transcriptId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }
}
