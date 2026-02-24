//
//  ChronicleService.swift
//  Contextify
//
//  Background service that analyzes transcript entries to build development narratives.
//  Subscribes to TranscriptUpdated notifications and orchestrates LLM analysis.
//
//  Lives in the app target because it depends on NarrativeAnalyzer (FoundationModels).
//  Data persistence is delegated to ChronicleRepository in ContextifyCore.
//

import Foundation
import ContextifyCore
import OSLog

/// Background service that analyzes transcript entries to build development narratives.
/// Subscribes to TranscriptUpdated notifications and orchestrates LLM analysis.
///
/// Lives in the app target because it depends on NarrativeAnalyzer (FoundationModels).
/// Data persistence is delegated to ChronicleRepository in ContextifyCore.
@MainActor
@Observable
final class ChronicleService {
  static let shared = ChronicleService()

  private let log = Logger(subsystem: "dev.contextify", category: "ChronicleService")

  /// Whether the service is actively processing
  private(set) var isProcessing = false

  /// Last error encountered during analysis
  private(set) var lastError: String?

  /// Count of entries analyzed since last start
  private(set) var entriesAnalyzed = 0

  /// Debounce interval to avoid processing during active typing
  private let debounceInterval: TimeInterval = 5.0

  /// Minimum entries required before running analysis on a new project
  private let minimumEntryThreshold = 3

  /// Maximum entries to process per notification batch
  private let maxBatchSize = 20

  /// Rolling window size for narrative context
  private let rollingWindowSize = 5

  private var notificationObserver: NSObjectProtocol?
  private var bulkCompleteObserver: NSObjectProtocol?
  private var pendingProjectIds: Set<String> = []
  private var debounceTask: Task<Void, Never>?
  private var repository: ChronicleRepositoryImpl?

  private init() {}

  // MARK: - Lifecycle

  /// Start the chronicle service. Call once at app launch.
  /// Subscribes to TranscriptUpdated notifications and begins background analysis.
  func start() {
    guard notificationObserver == nil else {
      log.debug("[CHRONICLE] Service already started, skipping")
      return
    }

    // Lite mode: Chronicle requires Apple Intelligence for analysis
    guard !isLiteModeActive() else {
      log.info("[CHRONICLE-LITE] Lite mode active, chronicle service disabled")
      return
    }

    // Initialize repository from shared DatabaseManager
    do {
      let pool = try DatabaseManager.shared.pool
      self.repository = ChronicleRepositoryImpl(db: pool)
    } catch {
      log.error("[CHRONICLE] Failed to initialize repository: \(error.localizedDescription, privacy: .public)")
      return
    }

    // Subscribe to per-transcript update notification (file-watcher triggered)
    notificationObserver = NotificationCenter.default.addObserver(
      forName: .transcriptUpdated,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      guard let projectId = notification.userInfo?["projectId"] as? String else {
        return
      }
      Task { @MainActor [weak self] in
        self?.scheduleAnalysis(for: projectId)
      }
    }

    // Subscribe to bulk ingest completion
    bulkCompleteObserver = NotificationCenter.default.addObserver(
      forName: .projectsIngestionComplete,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.flushPendingAnalysis()
      }
    }

    log.info("[CHRONICLE] Service started, listening for transcript updates")
  }

  /// Stop the chronicle service and remove notification observers.
  func stop() {
    if let observer = notificationObserver {
      NotificationCenter.default.removeObserver(observer)
      notificationObserver = nil
    }
    if let observer = bulkCompleteObserver {
      NotificationCenter.default.removeObserver(observer)
      bulkCompleteObserver = nil
    }
    debounceTask?.cancel()
    debounceTask = nil
    pendingProjectIds.removeAll()
    log.info("[CHRONICLE] Service stopped")
  }

  // MARK: - Debounce

  /// Schedule analysis for a project with debouncing.
  /// Multiple rapid notifications for the same project are coalesced.
  private func scheduleAnalysis(for projectId: String) {
    pendingProjectIds.insert(projectId)

    // Cancel previous debounce and start a new one
    debounceTask?.cancel()
    debounceTask = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .seconds(self.debounceInterval))
      guard !Task.isCancelled else { return }
      self.flushPendingAnalysis()
    }
  }

  /// Flush all pending project IDs and run analysis for each.
  private func flushPendingAnalysis() {
    let projectIds = pendingProjectIds
    pendingProjectIds.removeAll()
    debounceTask?.cancel()
    debounceTask = nil

    for projectId in projectIds {
      Task {
        await self.processProject(projectId: projectId)
      }
    }
  }

  // MARK: - Analysis Pipeline

  /// Process new entries for a given project
  private func processProject(projectId: String) async {
    guard let repository else {
      log.error("[CHRONICLE] Repository not initialized")
      return
    }

    isProcessing = true
    defer { isProcessing = false }

    do {
      // Fetch current narrative state for this project
      let currentState = try repository.fetchNarrativeState(for: projectId)

      // Fetch new entries since last processed
      let entries = try repository.fetchRecentEntries(
        for: projectId,
        after: currentState?.lastProcessedEntryId,
        limit: maxBatchSize
      )

      guard entries.count >= minimumEntryThreshold || currentState != nil else {
        log.debug("[CHRONICLE] Not enough entries for project \(projectId, privacy: .public) (\(entries.count) < \(self.minimumEntryThreshold))")
        return
      }

      guard !entries.isEmpty else {
        log.debug("[CHRONICLE] No new entries for project \(projectId, privacy: .public)")
        return
      }

      log.info("[CHRONICLE] Processing \(entries.count) entries for project \(projectId, privacy: .public)")

      // Process entries in exchange pairs
      var updatedState = currentState ?? NarrativeState(projectId: projectId)
      var currentArc: ChronicleArc? = nil
      if let arcId = updatedState.currentArcId {
        currentArc = try repository.fetchArc(id: arcId)
      }

      // Group entries into exchange pairs
      let exchanges = groupIntoExchanges(entries)

      for exchange in exchanges {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
          let recentSummaries = updatedState.rollingWindow.map { $0.summary }

          let analysis = await NarrativeAnalyzer.shared.analyzeExchange(
            entryId: exchange.assistantEntryId ?? exchange.userEntryId,
            userContent: exchange.userContent,
            assistantContent: exchange.assistantContent ?? "",
            currentArcIntent: currentArc?.intent,
            recentSummaries: recentSummaries
          )

          guard let analysis else { continue }

          // Apply analysis results
          let result = try applyAnalysis(
            analysis,
            exchange: exchange,
            currentArc: &currentArc,
            state: &updatedState,
            projectId: projectId,
            repository: repository
          )

          if result.newArcCreated {
            log.info("[CHRONICLE] New arc created: \(currentArc?.intent ?? "unknown", privacy: .public)")
          }

          entriesAnalyzed += 1
        }
        #endif
      }

      // Save updated narrative state
      if let lastEntry = entries.last {
        updatedState.lastProcessedEntryId = lastEntry.id
      }
      updatedState.updatedAt = Int(Date().timeIntervalSince1970)
      try repository.saveNarrativeState(updatedState)

      log.info("[CHRONICLE] Processed \(exchanges.count) exchanges for project \(projectId, privacy: .public)")

      // Generate narrative document if current arc has enough signposts
      if let arc = currentArc {
        let signposts = try repository.fetchSignposts(for: arc.id)
        if signposts.count >= 3 {
          _ = try await generateNarrativeDocument(for: arc.id)
        }
      }

    } catch {
      lastError = error.localizedDescription
      log.error("[CHRONICLE] Error processing project \(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Exchange Grouping

  private struct Exchange {
    let userEntryId: String
    let userContent: String
    let assistantEntryId: String?
    let assistantContent: String?
    let timestamp: Int
    let transcriptId: String
  }

  /// Group entries into user/assistant exchange pairs
  private func groupIntoExchanges(
    _ entries: [(id: String, kind: String, content: String, timestamp: Int, transcriptId: String)]
  ) -> [Exchange] {
    var exchanges: [Exchange] = []
    var i = 0
    while i < entries.count {
      let entry = entries[i]
      if entry.kind == "user" {
        // Look for following assistant response
        if i + 1 < entries.count && entries[i + 1].kind == "assistant" {
          let assistant = entries[i + 1]
          exchanges.append(Exchange(
            userEntryId: entry.id,
            userContent: entry.content,
            assistantEntryId: assistant.id,
            assistantContent: assistant.content,
            timestamp: entry.timestamp,
            transcriptId: entry.transcriptId
          ))
          i += 2
        } else {
          // User message without assistant response (yet)
          exchanges.append(Exchange(
            userEntryId: entry.id,
            userContent: entry.content,
            assistantEntryId: nil,
            assistantContent: nil,
            timestamp: entry.timestamp,
            transcriptId: entry.transcriptId
          ))
          i += 1
        }
      } else {
        // Standalone assistant entry (e.g., system prompt response)
        i += 1
      }
    }
    return exchanges
  }

  // MARK: - Analysis Application

  private struct ApplyResult {
    let newArcCreated: Bool
  }

  #if canImport(FoundationModels)
  /// Apply LLM analysis results to the narrative state
  @available(macOS 26.0, *)
  private func applyAnalysis(
    _ analysis: ExchangeAnalysis,
    exchange: Exchange,
    currentArc: inout ChronicleArc?,
    state: inout NarrativeState,
    projectId: String,
    repository: ChronicleRepositoryImpl
  ) throws -> ApplyResult {
    let now = Int(Date().timeIntervalSince1970)
    var newArcCreated = false

    // Handle arc status from the nested ArcStatusResult
    switch analysis.arcStatus.status {
    case .discovering, .pivoting:
      // Create a new arc
      let intent = analysis.arcStatus.updatedIntent ?? analysis.exchangeSummary
      let newArc = ChronicleArc(
        projectId: projectId,
        intent: intent,
        strategicContext: analysis.arcStatus.updatedStrategicContext,
        status: .active,
        parentArcId: currentArc?.id,
        discoveredFromEntryId: exchange.userEntryId,
        startedAt: now,
        lastActivityAt: now,
        transcriptIdsJson: ChronicleArc.encodeTranscriptIds([exchange.transcriptId])
      )
      try repository.saveArc(newArc)

      // If discovering, push current arc onto stack
      if analysis.arcStatus.status == .discovering, let existingArc = currentArc {
        var stack = state.arcStack
        stack.append(existingArc.id)
        state.arcStackJson = NarrativeState.encodeArcStack(stack)
      }

      currentArc = newArc
      state.currentArcId = newArc.id
      newArcCreated = true

    case .completing:
      // Mark current arc as completing
      if let arc = currentArc {
        try repository.updateArcStatus(id: arc.id, status: .completing, completedAt: nil)

        // Pop from discovery stack if there is a parent
        var stack = state.arcStack
        if !stack.isEmpty {
          let parentArcId = stack.removeLast()
          state.arcStackJson = NarrativeState.encodeArcStack(stack)
          state.currentArcId = parentArcId
          currentArc = try repository.fetchArc(id: parentArcId)
        }
      }

    case .resuming:
      // Returning from a nested arc - pop stack
      if let arc = currentArc {
        try repository.updateArcStatus(id: arc.id, status: .completed, completedAt: now)
      }
      var stack = state.arcStack
      if let parentId = stack.popLast() {
        state.arcStackJson = NarrativeState.encodeArcStack(stack)
        if let parentArc = try repository.fetchArc(id: parentId) {
          currentArc = parentArc
          state.currentArcId = parentArc.id
        }
      }

    case .continuing:
      // Update last activity on current arc
      if var arc = currentArc {
        var transcriptIds = arc.transcriptIds
        if !transcriptIds.contains(exchange.transcriptId) {
          transcriptIds.append(exchange.transcriptId)
        }
        try repository.updateArcActivity(
          id: arc.id,
          lastActivityAt: now,
          transcriptIdsJson: ChronicleArc.encodeTranscriptIds(transcriptIds)
        )
        arc.lastActivityAt = now
        arc.transcriptIdsJson = ChronicleArc.encodeTranscriptIds(transcriptIds)
        currentArc = arc
      } else {
        // No current arc, create one from this exchange
        let newArc = ChronicleArc(
          projectId: projectId,
          intent: analysis.exchangeSummary,
          status: .active,
          startedAt: now,
          lastActivityAt: now,
          transcriptIdsJson: ChronicleArc.encodeTranscriptIds([exchange.transcriptId])
        )
        try repository.saveArc(newArc)
        currentArc = newArc
        state.currentArcId = newArc.id
        newArcCreated = true
      }
    }

    // Save signposts
    for signpostResult in analysis.signposts {
      guard let kind = SignpostKind(rawValue: signpostResult.kind) else { continue }
      let signpost = ChronicleSignpost(
        arcId: currentArc?.id ?? "",
        entryId: exchange.assistantEntryId ?? exchange.userEntryId,
        kind: kind,
        summary: signpostResult.summary,
        detail: signpostResult.detail,
        reasoning: nil,
        revisitConditions: nil,
        timestamp: exchange.timestamp
      )
      try repository.saveSignpost(signpost)
    }

    // Update rolling window
    var window = state.rollingWindow
    window.append(ExchangeSummary(
      entryId: exchange.assistantEntryId ?? exchange.userEntryId,
      summary: analysis.exchangeSummary
    ))
    // Keep only the last N entries
    if window.count > rollingWindowSize {
      window = Array(window.suffix(rollingWindowSize))
    }
    state.rollingWindowJson = NarrativeState.encodeRollingWindow(window)

    return ApplyResult(newArcCreated: newArcCreated)
  }
  #endif

  // MARK: - Narrative Document Generation

  /// Generate a markdown chronicle document for a specific arc and write to /tmp/.
  /// Returns the file path of the generated document.
  func generateNarrativeDocument(for arcId: String) async throws -> String {
    guard let repository else {
      throw ChronicleError.repositoryNotInitialized
    }

    guard let arc = try repository.fetchArc(id: arcId) else {
      throw ChronicleError.arcNotFound(arcId)
    }

    let signposts = try repository.fetchSignposts(for: arcId)

    // Build markdown document
    var doc = """
    # Arc: \(arc.intent)

    **Strategic Context:** \(arc.strategicContext ?? "Not specified")
    **Status:** \(arc.status.rawValue)
    **Started:** \(formatTimestamp(arc.startedAt))
    """

    if let completedAt = arc.completedAt {
      doc += "\n**Completed:** \(formatTimestamp(completedAt))"
    }

    if let parentId = arc.parentArcId,
       let parent = try repository.fetchArc(id: parentId) {
      doc += "\n**Parent Arc:** \(parent.intent)"
    }

    doc += "\n\n## Timeline\n"

    for signpost in signposts {
      let label: String
      switch signpost.kind {
      case .decision: label = "Decision"
      case .discovery: label = "Discovery"
      case .pivot: label = "Pivot"
      case .milestone: label = "Milestone"
      case .blocker: label = "Blocker"
      case .resolution: label = "Resolution"
      }
      doc += "\n- \(formatTimestamp(signpost.timestamp)): **\(label)** - \(signpost.summary)"
      if let detail = signpost.detail {
        doc += "\n  \(detail)"
      }
    }

    if signposts.contains(where: { $0.kind == .decision }) {
      doc += "\n\n## Key Decisions\n"
      for signpost in signposts where signpost.kind == .decision {
        doc += "\n1. **\(signpost.summary)**"
        if let reasoning = signpost.reasoning {
          doc += " - \(reasoning)"
        }
        if let revisit = signpost.revisitConditions {
          doc += "\n   - Revisit if: \(revisit)"
        }
      }
    }

    if signposts.contains(where: { $0.kind == .discovery }) {
      doc += "\n\n## Discoveries\n"
      for signpost in signposts where signpost.kind == .discovery {
        doc += "\n1. \(signpost.summary)"
        if let detail = signpost.detail {
          doc += " - \(detail)"
        }
      }
    }

    doc += "\n\n## Related Transcripts\n"
    for transcriptId in arc.transcriptIds {
      doc += "\n- \(transcriptId)"
    }

    // Write to /tmp/
    let dateStr = ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    let filename = "chronicle-\(arc.projectId)-\(dateStr).md"
    let path = "/tmp/\(filename)"
    try doc.write(toFile: path, atomically: true, encoding: .utf8)

    log.info("[CHRONICLE] Generated narrative document: \(path, privacy: .public)")
    return path
  }

  /// Generate a project-level chronicle summary
  func generateProjectChronicle(for projectId: String) async throws -> String {
    guard let repository else {
      throw ChronicleError.repositoryNotInitialized
    }

    let arcs = try repository.fetchArcs(for: projectId)
    let state = try repository.fetchNarrativeState(for: projectId)

    let activeArcs = arcs.filter { $0.status == .active || $0.status == .completing }
    let completedArcs = arcs.filter { $0.status == .completed }

    var doc = """
    # Project Chronicle

    **Last Updated:** \(formatTimestamp(Int(Date().timeIntervalSince1970)))
    **Active Arcs:** \(activeArcs.count)
    **Completed Arcs:** \(completedArcs.count)

    ## Current Focus

    """

    if let currentArcId = state?.currentArcId,
       let currentArc = arcs.first(where: { $0.id == currentArcId }) {
      doc += "\(currentArc.intent)"
      if let context = currentArc.strategicContext {
        doc += " - \(context)"
      }
    } else {
      doc += "No active work thread detected."
    }

    doc += "\n\n## Active Arcs\n"
    for arc in activeArcs {
      let signposts = try repository.fetchSignposts(for: arc.id)
      doc += "\n### \(arc.intent) (\(arc.status.rawValue))\n"
      if let context = arc.strategicContext {
        doc += "\(context)\n"
      }
      let decisions = signposts.filter { $0.kind == .decision }
      if !decisions.isEmpty {
        doc += "- Key decisions: \(decisions.map { $0.summary }.joined(separator: "; "))\n"
      }
      let discoveries = signposts.filter { $0.kind == .discovery }
      if !discoveries.isEmpty {
        doc += "- Discovered: \(discoveries.map { $0.summary }.joined(separator: "; "))\n"
      }
    }

    if !completedArcs.isEmpty {
      doc += "\n## Completed Arcs\n"
      for arc in completedArcs.prefix(10) {
        doc += "\n### \(arc.intent) (completed)\n"
        if let completedAt = arc.completedAt {
          doc += "Completed: \(formatTimestamp(completedAt))\n"
        }
      }
    }

    // Write to /tmp/
    let dateStr = ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    let filename = "chronicle-project-\(projectId)-\(dateStr).md"
    let path = "/tmp/\(filename)"
    try doc.write(toFile: path, atomically: true, encoding: .utf8)

    log.info("[CHRONICLE] Generated project chronicle: \(path, privacy: .public)")
    return path
  }

  // MARK: - Helpers

  private func formatTimestamp(_ ts: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(ts))
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}

// MARK: - Errors

enum ChronicleError: Error, LocalizedError {
  case repositoryNotInitialized
  case arcNotFound(String)
  case analysisUnavailable

  var errorDescription: String? {
    switch self {
    case .repositoryNotInitialized:
      return "Chronicle repository not initialized"
    case .arcNotFound(let id):
      return "Arc not found: \(id)"
    case .analysisUnavailable:
      return "LLM analysis unavailable (lite mode or macOS < 26)"
    }
  }
}
