import Foundation
import OSLog
import Darwin

public enum WatcherTier: String, Sendable {
  case hot
  case warm
  case cold
}

public actor WatcherBudgetCoordinator {
  private let orchestrator: TranscriptOrchestrator
  private let log = Logger(subsystem: "dev.contextify", category: "WatcherBudget")

  private let maxActiveProjects = 3
  private let hotTranscriptLimit = 20
  private let warmTranscriptLimit = 10
  private let maxWatchersGlobal = 150
  private let promotionDebounceMs = 300
  private let residencyWindow: TimeInterval = 20.0

  private var lruProjects: [String] = []
  private var tiersByProject: [String: WatcherTier] = [:]
  private var watchedTranscriptsByProject: [String: Set<String>] = [:]
  private var promotionDebounceTasksByProject: [String: Task<Void, Never>] = [:]
  private var residencyUntilByTranscript: [String: Date] = [:]
  private var degradedModeHotOnly = false
  private var residencyRecomputeTask: Task<Void, Never>?

  // Generation token for activation ordering (P0.1 fix: prevents stale activations from racing)
  private var lastAppliedGeneration: UInt64 = 0

  public init(orchestrator: TranscriptOrchestrator) {
    self.orchestrator = orchestrator
  }

  public func activateProject(_ projectId: String, generation: UInt64 = 0) async {
    // Guard against stale activations (P0.1 fix)
    // Generation 0 is used for internal/test calls that don't need ordering
    if generation > 0 && generation <= lastAppliedGeneration {
      let lastGen = lastAppliedGeneration
      log.info("[ACTIVATION-STALE] Ignoring stale activation project=\(projectId, privacy: .public) gen=\(generation, privacy: .public) last=\(lastGen, privacy: .public)")
      return
    }
    if generation > 0 {
      lastAppliedGeneration = generation
    }

    updateLRU(projectId)
    assignTiers()
    await recomputePlan(reason: "activation")
    await runActivationCatchup(projectId: projectId)
  }

  public func deactivateAll() async {
    // Note: This is a shutdown-style teardown. It preserves degraded-mode state
    // and generation gating to avoid re-enabling warm watching mid-session.
    orchestrator.stopAllWatchingTranscripts(reason: "deactivate_all")

    lruProjects.removeAll()
    tiersByProject.removeAll()
    promotionDebounceTasksByProject.values.forEach { $0.cancel() }
    promotionDebounceTasksByProject.removeAll()
    residencyRecomputeTask?.cancel()
    residencyRecomputeTask = nil
    residencyUntilByTranscript.removeAll()
    watchedTranscriptsByProject.removeAll()
  }

  public func isTranscriptWatched(projectId: String, transcriptId: String) async -> Bool {
    return watchedTranscriptsByProject[projectId]?.contains(transcriptId) ?? false
  }

  public func noteTranscriptActivity(projectId: String, transcriptId: String) async {
    schedulePromotionRecompute(projectId: projectId)
  }

  public func currentTier(for projectId: String) async -> WatcherTier {
    return tiersByProject[projectId] ?? .cold
  }

  private func updateLRU(_ projectId: String) {
    lruProjects.removeAll(where: { $0 == projectId })
    lruProjects.insert(projectId, at: 0)
    if lruProjects.count > maxActiveProjects {
      lruProjects = Array(lruProjects.prefix(maxActiveProjects))
    }
  }

  private func assignTiers() {
    tiersByProject.removeAll(keepingCapacity: true)
    for (index, projectId) in lruProjects.enumerated() {
      let tier: WatcherTier
      if index == 0 {
        tier = .hot
      } else if index <= 2 {
        tier = .warm
      } else {
        tier = .cold
      }
      tiersByProject[projectId] = tier
      log.info("[TIER-ASSIGNMENT] project=\(projectId, privacy: .public) tier=\(tier.rawValue, privacy: .public) lru_index=\(index, privacy: .public)")
    }
  }

  private func schedulePromotionRecompute(projectId: String) {
    promotionDebounceTasksByProject[projectId]?.cancel()
    let delayMs = promotionDebounceMs
    let task = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(delayMs))
      guard !Task.isCancelled else { return }
      await self?.recomputePlan(reason: "promotion")
    }
    promotionDebounceTasksByProject[projectId] = task
  }

  private func scheduleResidencyRecompute(after expiry: Date) {
    // Cancel any existing residency recompute task
    residencyRecomputeTask?.cancel()

    let delay = max(expiry.timeIntervalSinceNow + 0.1, 0.1) // Add 100ms buffer
    let delayMs = Int(delay * 1000)
    residencyRecomputeTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(delayMs))
      guard !Task.isCancelled else { return }
      self?.log.info("[RESIDENCY-RECOMPUTE-TRIGGER] reason=residency_expired")
      await self?.recomputePlan(reason: "residency_expired")
    }
  }

  private func recomputePlan(reason: String) async {
    let plan = await computePlan()
    await applyPlan(plan)
  }

  private func computePlan() async -> WatcherPlan {
    var plan = WatcherPlan()
    var totalTarget = 0

    for projectId in lruProjects {
      let tier = tiersByProject[projectId] ?? .cold
      let limit = limitForTier(tier)
      let ranked = await rankedTranscripts(for: projectId)
      let target = Array(ranked.prefix(limit))
      plan.projectPlans[projectId] = ProjectPlan(
        projectId: projectId,
        tier: tier,
        rankedTranscriptIds: ranked,
        targetTranscriptIds: target
      )
      totalTarget += target.count
    }

    let watchedProjects = Set(watchedTranscriptsByProject.keys)
    let coldProjects = watchedProjects.subtracting(lruProjects)
    for projectId in coldProjects {
      plan.projectPlans[projectId] = ProjectPlan(
        projectId: projectId,
        tier: .cold,
        rankedTranscriptIds: [],
        targetTranscriptIds: []
      )
    }

    if totalTarget > maxWatchersGlobal {
      reducePlanForBudget(&plan, totalTarget: totalTarget)
    }

    let hotTarget = plan.projectPlans.values.filter { $0.tier == .hot }.reduce(0) { $0 + $1.targetTranscriptIds.count }
    let warmTarget = plan.projectPlans.values.filter { $0.tier == .warm }.reduce(0) { $0 + $1.targetTranscriptIds.count }
    log.info("[PLAN-COMPUTED] total_target=\(hotTarget + warmTarget, privacy: .public) hot_target=\(hotTarget, privacy: .public) warm_target=\(warmTarget, privacy: .public) budget=\(self.maxWatchersGlobal, privacy: .public) degraded=\(self.degradedModeHotOnly ? 1 : 0, privacy: .public)")

    return plan
  }

  private func applyPlan(_ plan: WatcherPlan) async {
    let currentWatched = await buildCurrentWatchedSnapshot(plan: plan)
    let diff = computeDiff(plan: plan, currentWatched: currentWatched)

    log.info("[DIFF-COMPUTED] to_start=\(diff.starts.count, privacy: .public) to_stop=\(diff.stops.count, privacy: .public)")

    let now = Date()
    var stopped = 0
    var skippedDueToResidency = 0
    var earliestResidencyExpiry: Date?

    for stop in diff.stops {
      if !degradedModeHotOnly,
         let residencyUntil = residencyUntilByTranscript[stop.transcriptId],
         now < residencyUntil {
        skippedDueToResidency += 1
        let remainingMs = Int((residencyUntil.timeIntervalSince(now)) * 1000)
        log.info("[WATCHER-STOP-SKIP] transcript=\(stop.transcriptId, privacy: .public) reason=residency remaining_ms=\(remainingMs, privacy: .public)")
        // Track earliest expiry for delayed recompute
        if earliestResidencyExpiry == nil || residencyUntil < earliestResidencyExpiry! {
          earliestResidencyExpiry = residencyUntil
        }
        continue
      }
      orchestrator.stopWatchingTranscript(transcriptId: stop.transcriptId)
      watchedTranscriptsByProject[stop.projectId]?.remove(stop.transcriptId)
      residencyUntilByTranscript.removeValue(forKey: stop.transcriptId)
      stopped += 1
      log.info("[WATCHER-STOP] transcript=\(stop.transcriptId, privacy: .public) project=\(stop.projectId, privacy: .public) reason=\(stop.reason, privacy: .public)")
    }

    // Schedule delayed recompute if any stops were skipped due to residency
    if skippedDueToResidency > 0, let expiry = earliestResidencyExpiry {
      scheduleResidencyRecompute(after: expiry)
      log.info("[RESIDENCY-RECOMPUTE-SCHEDULED] skipped=\(skippedDueToResidency, privacy: .public) delay_ms=\(Int(expiry.timeIntervalSince(now) * 1000), privacy: .public)")
    }

    var failedStarts: [WatcherPlanFailure] = []
    for start in diff.starts {
      do {
        let fileURL = URL(fileURLWithPath: start.filePath)
        try orchestrator.startWatchingTranscript(
          transcriptId: start.transcriptId,
          fileURL: fileURL,
          provider: start.provider
        )
        var projectSet = watchedTranscriptsByProject[start.projectId] ?? Set()
        projectSet.insert(start.transcriptId)
        watchedTranscriptsByProject[start.projectId] = projectSet
        residencyUntilByTranscript[start.transcriptId] = Date().addingTimeInterval(residencyWindow)
        log.info("[WATCHER-START] transcript=\(start.transcriptId, privacy: .public) project=\(start.projectId, privacy: .public) tier=\(start.tier.rawValue, privacy: .public)")
      } catch {
        let fdExhaustion = (error as? TranscriptWatcherError).map {
          if case let .fileDescriptorOpenFailed(errno) = $0 {
            return errno == EMFILE || errno == ENFILE
          }
          return false
        } ?? false
        failedStarts.append(
          WatcherPlanFailure(
            transcriptId: start.transcriptId,
            isFdExhaustion: fdExhaustion,
            errorDescription: error.localizedDescription
          )
        )
        log.error("[PLAN-APPLY-FAILURE] transcript=\(start.transcriptId, privacy: .public) project=\(start.projectId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
      }
    }

    if failedStarts.contains(where: { $0.isFdExhaustion }) {
      if !degradedModeHotOnly {
        degradedModeHotOnly = true
        residencyUntilByTranscript.removeAll()
        log.error("[DEGRADED-MODE] enabled=1 reason=fd_exhaustion")
        await recomputePlan(reason: "degraded")
      } else {
        log.error("[DEGRADED-MODE] already_enabled=1 additional_fd_exhaustion=1")
      }
    }
  }

  private func limitForTier(_ tier: WatcherTier) -> Int {
    switch tier {
    case .hot:
      return hotTranscriptLimit
    case .warm:
      return degradedModeHotOnly ? 0 : warmTranscriptLimit
    case .cold:
      return 0
    }
  }

  private func rankedTranscripts(for projectId: String) async -> [String] {
    do {
      let transcripts = try orchestrator.getTranscripts(forProject: projectId)
      let ranked = transcripts.sorted { lhs, rhs in
        if lhs.lastModified != rhs.lastModified {
          return lhs.lastModified > rhs.lastModified
        }
        let lhsActivity = lhs.lastActivityDetectedAt ?? 0
        let rhsActivity = rhs.lastActivityDetectedAt ?? 0
        if lhsActivity != rhsActivity {
          return lhsActivity > rhsActivity
        }
        return lhs.id < rhs.id
      }
      return ranked.map { $0.id }
    } catch {
      return []
    }
  }

  private func reducePlanForBudget(_ plan: inout WatcherPlan, totalTarget: Int) {
    var total = totalTarget
    let warmProjects = lruProjects.filter { tiersByProject[$0] == .warm }.reversed()
    for projectId in warmProjects {
      guard total > maxWatchersGlobal else { break }
      guard var projectPlan = plan.projectPlans[projectId] else { continue }
      while total > maxWatchersGlobal && !projectPlan.targetTranscriptIds.isEmpty {
        projectPlan.targetTranscriptIds.removeLast()
        total -= 1
      }
      plan.projectPlans[projectId] = projectPlan
    }

    if total > maxWatchersGlobal, let hotProjectId = lruProjects.first {
      guard var projectPlan = plan.projectPlans[hotProjectId] else { return }
      while total > maxWatchersGlobal && !projectPlan.targetTranscriptIds.isEmpty {
        projectPlan.targetTranscriptIds.removeLast()
        total -= 1
      }
      plan.projectPlans[hotProjectId] = projectPlan
    }
  }

  private func buildCurrentWatchedSnapshot(plan: WatcherPlan) async -> [String: Set<String>] {
    var snapshot: [String: Set<String>] = [:]
    for (projectId, _) in plan.projectPlans {
      do {
        let transcripts = try orchestrator.getTranscripts(forProject: projectId)
        let watched = transcripts
          .filter { orchestrator.isWatchingTranscript(transcriptId: $0.id) }
          .map { $0.id }
        snapshot[projectId] = Set(watched)
        watchedTranscriptsByProject[projectId] = Set(watched)
      } catch {
        snapshot[projectId] = []
      }
    }
    return snapshot
  }

  private func computeDiff(
    plan: WatcherPlan,
    currentWatched: [String: Set<String>]
  ) -> WatcherDiff {
    var stops: [StopAction] = []
    var starts: [StartAction] = []

    for (projectId, projectPlan) in plan.projectPlans {
      let targetSet = Set(projectPlan.targetTranscriptIds)
      let currentSet = currentWatched[projectId] ?? []
      let toStop = currentSet.subtracting(targetSet)
      let toStart = targetSet.subtracting(currentSet)

      for transcriptId in toStop {
        let reason: String
        if projectPlan.tier == .cold {
          reason = "eviction"
        } else {
          reason = "plan"
        }
        stops.append(
          StopAction(
            transcriptId: transcriptId,
            projectId: projectId,
            reason: reason,
            rank: rankIndex(for: transcriptId, in: projectPlan)
          )
        )
      }

      let transcripts = fetchTranscriptDetails(projectId: projectId, ids: Array(toStart))
      for transcript in transcripts {
        starts.append(
          StartAction(
            transcriptId: transcript.id,
            projectId: projectId,
            tier: projectPlan.tier,
            filePath: transcript.filePath,
            provider: transcript.provider,
            rank: rankIndex(for: transcript.id, in: projectPlan)
          )
        )
      }
    }

    stops.sort { lhs, rhs in
      if lhs.reason != rhs.reason {
        return lhs.reason == "eviction"
      }
      return lhs.rank > rhs.rank
    }

    starts.sort { lhs, rhs in
      if lhs.tier != rhs.tier {
        return lhs.tier == .hot
      }
      if lhs.tier == .warm, lhs.projectId != rhs.projectId {
        return lruProjects.firstIndex(of: lhs.projectId) ?? 0
          < lruProjects.firstIndex(of: rhs.projectId) ?? 0
      }
      return lhs.rank < rhs.rank
    }

    return WatcherDiff(stops: stops, starts: starts)
  }

  private func rankIndex(for transcriptId: String, in plan: ProjectPlan) -> Int {
    return plan.rankedTranscriptIds.firstIndex(of: transcriptId) ?? Int.max
  }

  private func fetchTranscriptDetails(projectId: String, ids: [String]) -> [Transcript] {
    do {
      let transcripts = try orchestrator.getTranscripts(forProject: projectId)
      let idSet = Set(ids)
      return transcripts.filter { idSet.contains($0.id) }
    } catch {
      return []
    }
  }

  private func runActivationCatchup(projectId: String) async {
    guard let plan = await computePlanForProject(projectId: projectId) else { return }
    let hotTargets = Set(plan.targetTranscriptIds)

    log.info("[CATCHUP-START] project=\(projectId, privacy: .public) mode=foreground restrict=1 candidates=\(hotTargets.count, privacy: .public)")
    let foregroundStart = Date()
    do {
      let count = try await orchestrator.rehooverDirtyTranscripts(
        projectId: projectId,
        restrictToTranscriptIds: hotTargets
      )
      let ms = Int(Date().timeIntervalSince(foregroundStart) * 1000)
      log.info("[CATCHUP-DONE] project=\(projectId, privacy: .public) mode=foreground rehoovered=\(count, privacy: .public) ms=\(ms, privacy: .public)")
    } catch {
      let ms = Int(Date().timeIntervalSince(foregroundStart) * 1000)
      log.error("[CATCHUP-DONE] project=\(projectId, privacy: .public) mode=foreground rehoovered=0 ms=\(ms, privacy: .public)")
    }

    let logger = log
    Task.detached(priority: .utility) { [orchestrator, logger, projectId] in
      let backgroundStart = Date()
      logger.info("[CATCHUP-START] project=\(projectId, privacy: .public) mode=background restrict=0 candidates=0")
      let count = (try? await orchestrator.rehooverDirtyTranscripts(
        projectId: projectId,
        restrictToTranscriptIds: nil
      )) ?? 0
      let ms = Int(Date().timeIntervalSince(backgroundStart) * 1000)
      logger.info("[CATCHUP-DONE] project=\(projectId, privacy: .public) mode=background rehoovered=\(count, privacy: .public) ms=\(ms, privacy: .public)")
    }
  }

  private func computePlanForProject(projectId: String) async -> ProjectPlan? {
    let tier = tiersByProject[projectId] ?? .cold
    let limit = limitForTier(tier)
    let ranked = await rankedTranscripts(for: projectId)
    let target = Array(ranked.prefix(limit))
    return ProjectPlan(
      projectId: projectId,
      tier: tier,
      rankedTranscriptIds: ranked,
      targetTranscriptIds: target
    )
  }
}

private struct ProjectPlan {
  let projectId: String
  let tier: WatcherTier
  let rankedTranscriptIds: [String]
  var targetTranscriptIds: [String]
}

private struct WatcherPlan {
  var projectPlans: [String: ProjectPlan] = [:]
}

private struct StopAction {
  let transcriptId: String
  let projectId: String
  let reason: String
  let rank: Int
}

private struct StartAction {
  let transcriptId: String
  let projectId: String
  let tier: WatcherTier
  let filePath: String
  let provider: String
  let rank: Int
}

private struct WatcherDiff {
  let stops: [StopAction]
  let starts: [StartAction]
}
