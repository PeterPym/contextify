import Foundation
import OSLog
import Darwin

/// Fast-path transcript ingestion coordinator with bounded worker pool.
/// Coordinates preview ingestion to populate the UI instantly and queues full ingestion
/// work in the background. Actor isolation guarantees safe access to shared state.
///
/// Key design decisions:
/// - Preview only for active project (watchers created only for preview subset)
/// - Remaining transcripts enqueued immediately (not blocked on preview)
/// - Completion work always uses startWatching: false
/// - Bounded worker pool (4 workers max) prevents unbounded task growth
/// - Pause/resume for project switching, shutdown for app termination
public actor FastPathIngestionCoordinator {
  // MARK: - Configuration
  private let maxWorkers: Int
  private let maxTranscriptsPerProject: Int
  private let maxAttempts: Int = 3
  private let previewLimit: Int
  private let forcedPreviewCount: Int

  // MARK: - Queue State (Completion work always uses startWatching: false)
  private struct CompletionWork: Sendable {
    let transcriptId: String
    var attempt: Int = 1
  }

  private var completionQueue: [CompletionWork] = []
  private var headIndex: Int = 0
  private var enqueuedCompletions: Set<String> = []

  // MARK: - Worker State (Fixed-Size Slots)
  private var workerSlots: [Task<Void, Never>?]
  private var activeWorkerCount: Int = 0
  private var inFlightCount: Int = 0

  // MARK: - Preview State (Active Project Only)
  private var activePreviewTask: Task<Void, Never>?

  // MARK: - Lifecycle Flags (Two Flags, Not Three)
  private var isBackfillPaused: Bool = false      // Non-terminal, resumable
  private var isShutdownCancelled: Bool = false   // Terminal, clears everything

  // MARK: - Metrics
  private var totalCompleted: Int = 0
  private var totalFailed: Int = 0
  private var peakQueueDepth: Int = 0

  // MARK: - Correlation
  private var runId: String = UUID().uuidString
  private var resumeAttempt: Int = 0

  // MARK: - Project Notification (First-notification-per-project tracking)
  private var notifiedProjects: Set<String> = []
  private var pendingNotificationTokens: Set<String> = []

  // MARK: - Dependencies
  private let orchestrator: TranscriptOrchestrator
  private let log = Logger(subsystem: "dev.contextify", category: "FastPathIngestion")

  public init(
    orchestrator: TranscriptOrchestrator,
    previewLimit: Int = 25,
    maxTranscriptsPerProject: Int = 5,
    forcedPreviewCount: Int = 25,
    maxWorkers: Int = 4
  ) {
    self.orchestrator = orchestrator
    self.previewLimit = previewLimit
    self.maxTranscriptsPerProject = max(1, maxTranscriptsPerProject)
    self.forcedPreviewCount = max(1, forcedPreviewCount)
    self.maxWorkers = max(1, maxWorkers)
    self.workerSlots = Array(repeating: nil, count: max(1, maxWorkers))
  }

  // MARK: - Queue Depth

  private var queueDepth: Int {
    completionQueue.count - headIndex
  }

  private func updatePeakQueueDepth() {
    if queueDepth > peakQueueDepth {
      peakQueueDepth = queueDepth
    }
  }

  // MARK: - Enqueue (standard path - respects dedupe)

  private func enqueueCompletion(transcriptId: String) {
    guard !isShutdownCancelled else { return }
    guard enqueuedCompletions.insert(transcriptId).inserted else { return }

    completionQueue.append(CompletionWork(transcriptId: transcriptId))
    updatePeakQueueDepth()

    log.debug("[FAST-PATH-ENQUEUE] \(transcriptId.prefix(8), privacy: .public) queueDepth=\(self.queueDepth, privacy: .public) runId=\(self.runId, privacy: .public)")

    startWorkersIfNeeded()
  }

  // MARK: - Requeue Front (for cancellation - bypasses dedupe)

  private func requeueFront(_ work: CompletionWork) {
    guard !isShutdownCancelled else { return }

    // Insert at current head position (priority)
    if headIndex > 0 {
      headIndex -= 1
      completionQueue[headIndex] = work
    } else {
      // Queue is compacted, prepend
      completionQueue.insert(work, at: 0)
    }
    updatePeakQueueDepth()

    log.debug("[FAST-PATH-REQUEUE-FRONT] \(work.transcriptId.prefix(8), privacy: .public) attempt=\(work.attempt, privacy: .public) queueDepth=\(self.queueDepth, privacy: .public) runId=\(self.runId, privacy: .public)")
  }

  // MARK: - Requeue Back (for retry with backoff)

  private func requeueBack(_ work: CompletionWork) {
    guard !isShutdownCancelled else { return }

    completionQueue.append(work)
    updatePeakQueueDepth()

    log.debug("[FAST-PATH-REQUEUE-BACK] \(work.transcriptId.prefix(8), privacy: .public) attempt=\(work.attempt, privacy: .public) queueDepth=\(self.queueDepth, privacy: .public) runId=\(self.runId, privacy: .public)")
  }

  // MARK: - Retry Backoff

  private nonisolated func retryDelay(for attempt: Int) -> UInt64 {
    switch attempt {
    case 2:
      // 50-150ms jittered
      return UInt64.random(in: 50_000_000...150_000_000)
    case 3:
      // 200-500ms jittered
      return UInt64.random(in: 200_000_000...500_000_000)
    default:
      return 0  // No delay for first attempt or terminal
    }
  }

  private nonisolated func isNonRetryableError(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
      // File not found, permission denied, etc.
      return nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoPermissionError
    }
    if nsError.domain == NSPOSIXErrorDomain {
      // Common "won't succeed without external change" POSIX failures.
      return nsError.code == Int(ENOENT) || nsError.code == Int(EACCES) || nsError.code == Int(EPERM)
    }
    return false
  }

  // MARK: - Worker Management

  private func startWorkersIfNeeded() {
    guard !isBackfillPaused && !isShutdownCancelled else { return }

    for slotIndex in 0..<maxWorkers {
      guard queueDepth > 0 else { break }
      guard workerSlots[slotIndex] == nil else { continue }

      activeWorkerCount += 1
      let task = Task(priority: .utility) {
        await self.runWorker(slotIndex: slotIndex)
      }
      workerSlots[slotIndex] = task
      log.debug("[FAST-PATH-WORKER-START] slot=\(slotIndex, privacy: .public) activeWorkers=\(self.activeWorkerCount, privacy: .public) runId=\(self.runId, privacy: .public)")
    }
  }

  private func runWorker(slotIndex: Int) async {
    var completed = 0
    var failed = 0
    let startTime = Date()

    while true {
      // CHECK BEFORE DEQUEUE - prevents dropping work on pause
      if isBackfillPaused || isShutdownCancelled || Task.isCancelled {
        let reason = isShutdownCancelled ? "shutdown" : isBackfillPaused ? "paused" : "cancelled"
        log.info("[FAST-PATH-WORKER-PAUSE] slot=\(slotIndex, privacy: .public) reason=\(reason, privacy: .public) completed=\(completed, privacy: .public) runId=\(self.runId, privacy: .public)")
        break
      }

      // Now safe to dequeue
      guard var work = dequeueNext() else {
        break  // Queue empty, exit normally
      }

      inFlightCount += 1

      // Apply retry backoff if this is a retry
      if work.attempt > 1 {
        let delay = retryDelay(for: work.attempt)
        if delay > 0 {
          try? await Task.sleep(nanoseconds: delay)
          // Re-check cancellation after sleep
          if isBackfillPaused || isShutdownCancelled || Task.isCancelled {
            inFlightCount = max(0, inFlightCount - 1)
            requeueFront(work)
            break
          }
        }
      }

      do {
        _ = try await orchestrator.ingestTranscript(
          transcriptId: work.transcriptId,
          mode: .complete,
          notifyUI: false,
          startWatching: false  // Completion NEVER creates watchers
        )
        completed += 1
        totalCompleted += 1

        // Success - remove from dedupe set
        enqueuedCompletions.remove(work.transcriptId)

        if completed % 25 == 0 {
          let elapsed = Date().timeIntervalSince(startTime)
          let rate = Double(completed) / max(elapsed, 0.001)
          log.info("[FAST-PATH-PROGRESS] slot=\(slotIndex, privacy: .public) completed=\(completed, privacy: .public) remaining=\(self.queueDepth, privacy: .public) inFlight=\(self.inFlightCount, privacy: .public) rate=\(String(format: "%.1f", rate), privacy: .public)/s runId=\(self.runId, privacy: .public) attempt=\(self.resumeAttempt, privacy: .public)")
        }
      } catch is CancellationError {
        // Cancellation: requeue at front with same attempt count
        inFlightCount = max(0, inFlightCount - 1)
        requeueFront(work)
        log.info("[FAST-PATH-CANCELLED] slot=\(slotIndex, privacy: .public) transcript=\(work.transcriptId.prefix(8), privacy: .public) requeued runId=\(self.runId, privacy: .public)")
        break  // Exit worker loop on cancellation
      } catch {
        // Check if non-retryable
        if isNonRetryableError(error) {
          failed += 1
          totalFailed += 1
          enqueuedCompletions.remove(work.transcriptId)
          do {
            try orchestrator.markTranscriptUnavailable(
              transcriptId: work.transcriptId,
              lastError: error.localizedDescription
            )
          } catch {
            log.error("[FAST-PATH-FAIL-PERMANENT] Failed to mark transcript unavailable: \(work.transcriptId.prefix(8), privacy: .public) error=\(error.localizedDescription, privacy: .public) runId=\(self.runId, privacy: .public)")
          }
          log.error("[FAST-PATH-FAIL-PERMANENT] slot=\(slotIndex, privacy: .public) transcript=\(work.transcriptId.prefix(8), privacy: .public) error=\(error.localizedDescription, privacy: .public) runId=\(self.runId, privacy: .public)")
        } else {
          // Retryable error
          if work.attempt < maxAttempts {
            work.attempt += 1
            // Requeue for retry (at back, with backoff applied on next dequeue)
            requeueBack(work)
            log.warning("[FAST-PATH-RETRY] slot=\(slotIndex, privacy: .public) transcript=\(work.transcriptId.prefix(8), privacy: .public) attempt=\(work.attempt, privacy: .public)/\(self.maxAttempts, privacy: .public) error=\(error.localizedDescription, privacy: .public) runId=\(self.runId, privacy: .public)")
          } else {
            // Max attempts exceeded - terminal failure
            failed += 1
            totalFailed += 1
            enqueuedCompletions.remove(work.transcriptId)
            log.error("[FAST-PATH-FAIL] slot=\(slotIndex, privacy: .public) transcript=\(work.transcriptId.prefix(8), privacy: .public) error=\(error.localizedDescription, privacy: .public) runId=\(self.runId, privacy: .public)")
          }
        }
      }

      inFlightCount = max(0, inFlightCount - 1)
    }

    // SYNCHRONOUS slot cleanup (v6 fix - no Task { } wrapper)
    workerDidExit(slotIndex: slotIndex, completed: completed, failed: failed, startTime: startTime)
  }

  private func workerDidExit(slotIndex: Int, completed: Int, failed: Int, startTime: Date) {
    let elapsed = Date().timeIntervalSince(startTime)
    log.info("[FAST-PATH-WORKER-DONE] slot=\(slotIndex, privacy: .public) completed=\(completed, privacy: .public) failed=\(failed, privacy: .public) elapsed=\(String(format: "%.1f", elapsed), privacy: .public)s runId=\(self.runId, privacy: .public)")

    // Clear slot
    workerSlots[slotIndex] = nil
    activeWorkerCount = max(0, activeWorkerCount - 1)

    // Check if queue drained
    if queueDepth == 0 && activeWorkerCount == 0 && inFlightCount == 0 {
      log.info("[FAST-PATH-QUEUE-DRAINED] totalCompleted=\(self.totalCompleted, privacy: .public) totalFailed=\(self.totalFailed, privacy: .public) peakQueueDepth=\(self.peakQueueDepth, privacy: .public) runId=\(self.runId, privacy: .public) attempt=\(self.resumeAttempt, privacy: .public)")
    }

    // Restart if more work and not paused
    if queueDepth > 0 && !isBackfillPaused && !isShutdownCancelled {
      startWorkersIfNeeded()
    }
  }

  // MARK: - O(1) Dequeue with Compaction

  private func dequeueNext() -> CompletionWork? {
    guard headIndex < completionQueue.count else {
      compactQueueIfNeeded()
      return nil
    }
    let work = completionQueue[headIndex]
    headIndex += 1
    compactQueueIfNeeded()
    return work
  }

  private func compactQueueIfNeeded() {
    // Compact when headIndex > 100 AND more than half is waste
    if headIndex > 100 && headIndex > completionQueue.count / 2 {
      completionQueue.removeFirst(headIndex)
      headIndex = 0
      log.debug("[FAST-PATH-COMPACT] newSize=\(self.completionQueue.count, privacy: .public) runId=\(self.runId, privacy: .public)")
    }
  }

  // MARK: - Preview (Actor Method for Isolation)

  /// Run preview for a set of transcripts. Called from Task closure.
  private func runPreview(
    subset: [Transcript],
    projectId: String,
    isActiveProject: Bool
  ) async {
    // Only notify UI once per project (on first successful transcript completion)
    let shouldNotifyUI = registerProjectNotificationIfNeeded(projectId: projectId)
    if shouldNotifyUI {
      pendingNotificationTokens.insert(projectId)
    }

    await withTaskGroup(of: Void.self) { group in
      for transcript in subset {
        // Check cancellation before spawning
        if Task.isCancelled || isShutdownCancelled { break }

        group.addTask { [orchestrator, previewLimit, log] in
          // Check cancellation before heavy work
          guard !Task.isCancelled else { return }

          let tokenConsumed = await self.consumeNotificationToken(for: projectId)
          let notifyForThisTranscript = shouldNotifyUI && tokenConsumed

          do {
            let needsCompletion = try await orchestrator.ingestTranscript(
              transcriptId: transcript.id,
              mode: .preview(entries: previewLimit),
              notifyUI: notifyForThisTranscript,
              startWatching: isActiveProject  // Only active project gets watchers
            )
            if notifyForThisTranscript {
              await self.markProjectNotified(projectId: projectId)
            }
            if needsCompletion {
              await self.enqueueCompletion(transcriptId: transcript.id)
            }
          } catch {
            if notifyForThisTranscript {
              await self.restoreNotificationTokenIfNeeded(for: projectId)
            }
            log.error("[FAST-PATH] Preview failed: \(transcript.id.prefix(8), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
          }
        }
      }
    }

    if shouldNotifyUI {
      pendingNotificationTokens.remove(projectId)
    }
  }

  // MARK: - Pause / Resume / Shutdown

  /// Pause backfill - workers exit gracefully, queue preserved
  /// Use when switching projects
  public func pauseBackfill() {
    guard !isBackfillPaused && !isShutdownCancelled else { return }
    log.info("[FAST-PATH-PAUSE-BACKFILL] queueDepth=\(self.queueDepth, privacy: .public) inFlight=\(self.inFlightCount, privacy: .public) runId=\(self.runId, privacy: .public)")
    isBackfillPaused = true
    // Workers will exit on next loop iteration
  }

  /// Resume backfill after pause
  public func resumeBackfill() {
    guard isBackfillPaused && !isShutdownCancelled else { return }
    resumeAttempt += 1
    log.info("[FAST-PATH-RESUME-BACKFILL] queueDepth=\(self.queueDepth, privacy: .public) runId=\(self.runId, privacy: .public) attempt=\(self.resumeAttempt, privacy: .public)")
    isBackfillPaused = false
    startWorkersIfNeeded()
  }

  /// Cancel active preview (for project switch)
  public func cancelPreview() {
    activePreviewTask?.cancel()
    activePreviewTask = nil
    log.info("[FAST-PATH-CANCEL-PREVIEW] runId=\(self.runId, privacy: .public)")
  }

  /// Full shutdown - terminal, clears queue, cancels all tasks
  /// Use on app termination
  public func shutdown() {
    log.info("[FAST-PATH-SHUTDOWN] queueDepth=\(self.queueDepth, privacy: .public) activeWorkers=\(self.activeWorkerCount, privacy: .public) runId=\(self.runId, privacy: .public)")
    isShutdownCancelled = true
    isBackfillPaused = true

    // Cancel preview
    activePreviewTask?.cancel()
    activePreviewTask = nil

    // Cancel all worker tasks
    for i in workerSlots.indices {
      workerSlots[i]?.cancel()
      workerSlots[i] = nil
    }
    activeWorkerCount = 0
    inFlightCount = 0

    // Clear state
    completionQueue.removeAll()
    headIndex = 0
    enqueuedCompletions.removeAll()
  }

  /// Legacy cancel() - maps to pauseBackfill for backwards compatibility
  /// Does NOT set isShutdownCancelled, so resume works
  public func cancel() {
    cancelPreview()
    pauseBackfill()
  }

  // MARK: - Test Hooks

  /// Wait for true idle: queue empty AND no in-flight work
  public func waitForIdle(timeout: TimeInterval = 30) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while (queueDepth > 0 || inFlightCount > 0 || activeWorkerCount > 0) && Date() < deadline {
      try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
    }
    return queueDepth == 0 && inFlightCount == 0 && activeWorkerCount == 0
  }

  /// Expose state for tests/diagnostics
  public var pendingCompletionCount: Int { queueDepth }
  public var currentInFlightCount: Int { inFlightCount }
  public var currentActiveWorkerCount: Int { activeWorkerCount }
  public var metrics: (completed: Int, failed: Int, peak: Int) {
    (totalCompleted, totalFailed, peakQueueDepth)
  }

  // MARK: - Public API (Legacy Compatibility)

  public func resumePendingCompletions() async {
    guard let partials = try? orchestrator.getPartialTranscripts() else {
      log.error("[FAST-PATH-RESUME] Failed to load partial transcripts")
      return
    }
    log.info("[FAST-PATH-RESUME] Found \(partials.count, privacy: .public) partial transcripts")
    for transcript in partials {
      enqueueCompletion(transcriptId: transcript.id)
    }
  }

  /// Just-in-time ingestion for a single project (Phase 3 lazy loading)
  /// Ingests ALL transcripts for this project synchronously
  /// Returns the database project ID (UUID) for use by caller
  public func ingestProjectJIT(_ project: LightweightProject) async throws -> String {
    let startTime = Date()
    log.info("[JIT-INGEST] Starting JIT ingestion for project: \(project.displayName, privacy: .public) lightweightId=\(project.id, privacy: .public)")

    let canonicalRootPath = project.canonicalRootPath

    // 1. Ensure project exists in DB (mapping Path → UUID)
    let projectId: String
    do {
      projectId = try orchestrator.getOrCreateProject(name: project.displayName, rootPath: canonicalRootPath).projectId
      log.info("[JIT-INGEST-ID-MAP] lightweightId=\(project.id, privacy: .public) dbProjectId=\(projectId, privacy: .public) match=\(project.id == projectId, privacy: .public)")
    } catch {
      log.error("[JIT-INGEST] Failed to get/create project: \(error.localizedDescription, privacy: .public)")
      throw error
    }

    // 2. Register primer for App Store build path (Option B-Prime)
    let entryCount = (try? orchestrator.getEntryCount(forProject: projectId)) ?? 0
    let primerTarget = ContextifyConfig.shared.primerTargetEntries
    if entryCount < primerTarget {
      orchestrator.registerPrimer(projectId: projectId, target: primerTarget)
      log.info("[JIT-PRIMER-REGISTER] projectId=\(projectId, privacy: .public) entryCount=\(entryCount, privacy: .public) target=\(primerTarget, privacy: .public)")
    } else {
      log.debug("[JIT-PRIMER-SKIP] projectId=\(projectId, privacy: .public) entryCount=\(entryCount, privacy: .public) >= target=\(primerTarget, privacy: .public)")
    }

    // 3. Populate transcripts table BEFORE calling FastPath
    if !project.transcriptFiles.isEmpty {
      log.info("[JIT-INGEST] Populating DB with \(project.transcriptFiles.count, privacy: .public) transcript records...")

      let discovered = project.transcriptFiles.map { url in
        let providerString = TranscriptProviderID.fromTranscriptURL(url) ?? TranscriptProviderID.claude
        let providerEnum: DiscoveredProject.Provider = providerString == TranscriptProviderID.claude ? .claudeCode : .codexCLI
        return DiscoveredTranscript(
          fileURL: url,
          provider: providerEnum,
          sessionId: url.deletingPathExtension().lastPathComponent
        )
      }

      do {
        _ = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)
        log.info("[JIT-INGEST] Upserted \(discovered.count, privacy: .public) transcript records to DB")
      } catch {
        log.error("[JIT-INGEST] Failed to upsert transcripts: \(error.localizedDescription, privacy: .public)")
      }
    } else {
      log.debug("[JIT-INGEST] No transcript files to upsert (empty project)")
    }

    // 4. Now run FastPath (which queries the DB we just populated)
    await runFastPath(projectIds: [projectId], activeProjectId: projectId)

    let duration = Date().timeIntervalSince(startTime)
    log.info("[JIT-INGEST] Complete in \(String(format: "%.3f", duration), privacy: .public)s for project: \(project.displayName, privacy: .public)")

    return projectId
  }

  public func runFastPath(projectIds: [String], activeProjectId: String?) async {
    // Rotate runId only when we're idle; otherwise keep stable for in-flight correlation.
    if activeWorkerCount == 0 && inFlightCount == 0 {
      runId = UUID().uuidString
    }

    // If we have a paused backlog from a previous run, resume it and re-kick workers.
    if isBackfillPaused {
      resumeBackfill()
    } else if queueDepth > 0 {
      startWorkersIfNeeded()
    }

    let startTime = Date()
    let orderedIds = orderProjects(projectIds: projectIds, activeProjectId: activeProjectId)

    log.info("[FAST-PATH-PREVIEW-START] projects=\(projectIds.count, privacy: .public) active=\(activeProjectId ?? "none", privacy: .public) runId=\(self.runId, privacy: .public)")

    for projectId in orderedIds {
      if isShutdownCancelled || Task.isCancelled || isBackfillPaused {
        let reason = isBackfillPaused ? "paused" : "cancelled"
        log.info("[FAST-PATH] Aborting runFastPath due to \(reason, privacy: .public) runId=\(self.runId, privacy: .public)")
        break
      }
      await processProject(projectId: projectId, activeProjectId: activeProjectId)
    }

    let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
    log.info("[FAST-PATH-PREVIEW-DONE] duration_ms=\(durationMs, privacy: .public) projects=\(orderedIds.count, privacy: .public) runId=\(self.runId, privacy: .public)")
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

  /// Prioritize transcripts for FastPath processing.
  /// 1. Non-agent files first (main conversations have displayable content)
  /// 2. Then by file size descending (larger files = more content)
  func prioritizeForFastPath(_ transcripts: [Transcript]) -> [Transcript] {
    transcripts.sorted { lhs, rhs in
      let lhsName = URL(fileURLWithPath: lhs.filePath).lastPathComponent
      let rhsName = URL(fileURLWithPath: rhs.filePath).lastPathComponent

      let lhsIsClaude = lhs.provider == "claude.code"
      let rhsIsClaude = rhs.provider == "claude.code"
      let lhsIsAgent = lhsIsClaude && lhsName.hasPrefix("agent-")
      let rhsIsAgent = rhsIsClaude && rhsName.hasPrefix("agent-")

      if lhsIsAgent != rhsIsAgent {
        return !lhsIsAgent
      }

      return (lhs.fileSize ?? 0) > (rhs.fileSize ?? 0)
    }
  }

  private func processProject(projectId: String, activeProjectId: String?) async {
    if isShutdownCancelled || Task.isCancelled || isBackfillPaused {
      let reason = isBackfillPaused ? "paused" : "cancelled"
      log.info("[FAST-PATH] Skipping project \(projectId, privacy: .public) due to \(reason, privacy: .public) runId=\(self.runId, privacy: .public)")
      return
    }

    // Load project
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

    // Filter for transcripts that still need processing
    var targets = transcripts.filter { $0.ingestState != "complete" && $0.status == "active" }
    log.info("[FAST-PATH-FILTER-STATS] project=\(projectId, privacy: .public) total=\(transcripts.count, privacy: .public) partial=\(targets.count, privacy: .public)")

    // Force reset if needed (complete but 0 entries scenario)
    if targets.isEmpty, !transcripts.isEmpty {
      let entryCount = (try? orchestrator.getEntryCount(forProject: projectId)) ?? 0
      if entryCount == 0 {
        do {
          let forcedIds = try orchestrator.forceResetIngestState(projectId: projectId, limit: forcedPreviewCount)
          if !forcedIds.isEmpty {
            log.warning("[FAST-PATH-RESET] project=\(projectId, privacy: .public) forced=\(forcedIds.count, privacy: .public)")
            let forcedSet = Set(forcedIds)
            targets = transcripts.filter { forcedSet.contains($0.id) }
          }
        } catch {
          log.error("[FAST-PATH-RESET] Failed to reset ingest state for \(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
      }
    }

    guard !targets.isEmpty else {
      log.info("[FAST-PATH-FILTER] No partial transcripts to process for project \(projectId, privacy: .public)")
      return
    }

    let prioritized = prioritizeForFastPath(targets)
    let isActiveProject = (projectId == activeProjectId)

    // Split: active project gets preview + remaining; inactive projects skip preview
    let subset: [Transcript]
    let remaining: [Transcript]

    if isActiveProject {
      subset = Array(prioritized.prefix(maxTranscriptsPerProject))
      remaining = Array(prioritized.dropFirst(maxTranscriptsPerProject))
    } else {
      // Inactive projects: no preview, all go to completion queue
      subset = []
      remaining = prioritized
    }

    log.info("[FAST-PATH-PROJECT] project=\(projectId, privacy: .public) total=\(targets.count, privacy: .public) preview=\(subset.count, privacy: .public) background=\(remaining.count, privacy: .public) isActive=\(isActiveProject, privacy: .public) runId=\(self.runId, privacy: .public)")

    // Enqueue ALL remaining IMMEDIATELY (don't block on preview)
    // This ensures backfill proceeds even if preview stalls or is cancelled
    for transcript in remaining {
      enqueueCompletion(transcriptId: transcript.id)
    }

    // Run preview for active project only
    if isActiveProject && !subset.isEmpty {
      // Spawn preview task (actor-isolated pattern)
      activePreviewTask = Task {
        await self.runPreview(subset: subset, projectId: projectId, isActiveProject: true)
      }

      // Await preview for UI timing (but backfill already started via enqueue above)
      await activePreviewTask?.value
      activePreviewTask = nil
    }

    log.info("[FAST-PATH-PROJECT-DONE] project=\(projectId, privacy: .public) enqueued=\(remaining.count, privacy: .public) queueDepth=\(self.queueDepth, privacy: .public) runId=\(self.runId, privacy: .public)")
  }

  private func registerProjectNotificationIfNeeded(projectId: String) -> Bool {
    !notifiedProjects.contains(projectId)
  }

  private func consumeNotificationToken(for projectId: String) -> Bool {
    pendingNotificationTokens.remove(projectId) != nil
  }

  private func restoreNotificationTokenIfNeeded(for projectId: String) {
    guard !notifiedProjects.contains(projectId) else { return }
    pendingNotificationTokens.insert(projectId)
  }

  private func markProjectNotified(projectId: String) {
    notifiedProjects.insert(projectId)
    pendingNotificationTokens.remove(projectId)
  }
}
