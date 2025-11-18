import Foundation
import OSLog

/// Fast-path transcript ingestion coordinator.
/// Coordinates preview ingestion to populate the UI instantly and queues full ingestion
/// work in the background. Actor isolation guarantees safe access to shared state.
public actor FastPathIngestionCoordinator {
  private let orchestrator: TranscriptOrchestrator
  private let previewLimit: Int
  private let maxPreviewConcurrency: Int
  private let maxTranscriptsPerProject: Int
  private var enqueuedCompletions: Set<String> = []
  private var notifiedProjects: Set<String> = []
  private var pendingNotificationTokens: Set<String> = []
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

  public func resumePendingCompletions() async {
    guard let partials = try? orchestrator.getPartialTranscripts() else {
      log.error("[FAST-PATH-RESUME] Failed to load partial transcripts")
      return
    }
    if !partials.isEmpty {
      log.info("[FAST-PATH-RESUME] Resuming \(partials.count, privacy: .public) partial transcripts")
    }
    for transcript in partials {
      await enqueueCompletion(transcriptId: transcript.id)
    }
  }

  /// Cancel any running ingestion tasks (for Phase 3 Orchestrator)
  public func cancel() {
    log.info("[FAST-PATH-CANCEL] Cancellation requested (Phase 3)")
    // Actor-isolated cancellation - implement if needed
    // For now, processProject checks Task.isCancelled between batches
  }

  /// Just-in-time ingestion for a single project (Phase 3 lazy loading)
  /// Ingests ALL transcripts for this project synchronously
  public func ingestProjectJIT(_ project: LightweightProject) async throws {
    let startTime = Date()
    log.info("[JIT-INGEST] Starting JIT ingestion for project: \(project.id, privacy: .public)")

    // 1. Ensure project exists in DB
    let projectId: String
    do {
      projectId = try orchestrator.getOrCreateProject(name: nil, rootPath: project.path.path)
      log.debug("[JIT-INGEST] Project ID: \(projectId, privacy: .public)")
    } catch {
      log.error("[JIT-INGEST] Failed to get/create project: \(error.localizedDescription, privacy: .public)")
      throw error
    }

    // 2. Use existing runFastPath for this single project
    // TODO: Optimize to batch all transcripts, not just preview limit (5)
    await runFastPath(projectIds: [projectId], activeProjectId: projectId)

    let duration = Date().timeIntervalSince(startTime)
    log.info("[JIT-INGEST] Complete in \(String(format: "%.3f", duration), privacy: .public)s for project: \(project.id, privacy: .public)")
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

    // Check if this is a container path project (should be filtered out)
    let project: Project
    do {
      guard let p = try orchestrator.getProject(id: projectId) else {
        log.warning("[FAST-PATH] Project not found: \(projectId, privacy: .public)")
        return
      }
      project = p
    } catch {
      log.error("[FAST-PATH] Failed to load project \(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return
    }

    // Skip sandbox container paths (defensive check)
    if SandboxPathFilter.isSandboxContainerPath(project.rootPath) {
      log.warning("[FAST-PATH-FILTER] Skipping sandbox container path project: \(project.name ?? project.id, privacy: .public) at \(project.rootPath, privacy: .public)")
      return
    }

    let transcripts: [Transcript]
    do {
      transcripts = try orchestrator.getTranscripts(forProject: projectId)
    } catch {
      log.error("[FAST-PATH] Failed to load transcripts for \(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return
    }

    log.info("[FAST-PATH-TRANSCRIPT] Found \(transcripts.count, privacy: .public) transcripts for project \(projectId, privacy: .public)")

    // Filter for transcripts that still need processing (ingest_state != complete)
    let targets = transcripts.filter { $0.ingestState != "complete" && $0.status == "active" }

    // Log filter results
    log.info("[FAST-PATH-FILTER] Filtered \(targets.count, privacy: .public) targets from \(transcripts.count, privacy: .public) total transcripts for project \(projectId, privacy: .public)")

    guard !targets.isEmpty else {
      log.info("[FAST-PATH-FILTER] No partial transcripts to process, bailing out for project \(projectId, privacy: .public)")
      return
    }

    let subset = Array(targets.prefix(maxTranscriptsPerProject))
    log.info("[FAST-PATH-PROJECT] Processing \(subset.count, privacy: .public) transcripts for project \(projectId, privacy: .public)")

    // Only notify UI once per project (on first transcript completion)
    let shouldNotifyUI = registerProjectNotificationIfNeeded(projectId: projectId)
    if shouldNotifyUI {
      pendingNotificationTokens.insert(projectId)
    }

    await withTaskGroup(of: Void.self) { group in
      for transcript in subset {
        group.addTask { [previewLimit = self.previewLimit, orchestrator = self.orchestrator, log = self.log] in
          let tokenConsumed = await self.consumeNotificationToken(for: projectId)
          let notifyForThisTranscript = shouldNotifyUI && tokenConsumed

          log.info("[FAST-PATH-NOTIFY] Transcript \(transcript.id.prefix(8), privacy: .public) notifyUI: \(notifyForThisTranscript, privacy: .public) (shouldNotifyUI: \(shouldNotifyUI, privacy: .public))")

          do {
            let needsCompletion = try await orchestrator.ingestTranscript(
              transcriptId: transcript.id,
              mode: .preview(entries: previewLimit),
              notifyUI: notifyForThisTranscript
            )
            if needsCompletion {
              await self.enqueueCompletion(transcriptId: transcript.id)
            }
          } catch {
            log.error("[FAST-PATH] Preview ingest failed for \(transcript.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
          }
        }
      }
    }

    if shouldNotifyUI {
      pendingNotificationTokens.remove(projectId)
    }
  }

  private func enqueueCompletion(transcriptId: String) async {
    guard enqueuedCompletions.insert(transcriptId).inserted else { return }

    let orchestrator = self.orchestrator
    let log = self.log

    Task.detached(priority: .utility) { [weak self] in
      do {
        _ = try await orchestrator.ingestTranscript(
          transcriptId: transcriptId,
          mode: .complete,
          notifyUI: false  // UI already notified during preview
        )
      } catch {
        log.error("[FAST-PATH] Background completion failed for \(transcriptId, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }

      if let self {
        await self.removeEnqueuedCompletion(transcriptId: transcriptId)
      }
    }
  }

  private func removeEnqueuedCompletion(transcriptId: String) {
    enqueuedCompletions.remove(transcriptId)
  }

  private func registerProjectNotificationIfNeeded(projectId: String) -> Bool {
    guard !notifiedProjects.contains(projectId) else { return false }
    notifiedProjects.insert(projectId)
    return true
  }

  private func consumeNotificationToken(for projectId: String) -> Bool {
    pendingNotificationTokens.remove(projectId) != nil
  }
}
