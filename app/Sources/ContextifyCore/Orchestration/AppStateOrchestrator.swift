import Foundation
import SwiftUI
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "AppOrchestrator")

/// Application-wide state
public enum AppState: Sendable {
  case startup
  case discovering
  case idle(projects: [LightweightProject])
  case loading(projectId: String)
  case active(projectId: String)
  case error(String)
}

/// The central coordinator for all app state transitions
/// Replaces the fragmented responsibilities of StartupCoordinator, ProjectActivityMonitor, and ProjectsViewModel ingestion logic
@MainActor
public final class AppStateOrchestrator: ObservableObject {
  public static let shared = AppStateOrchestrator()

  // Dependencies
  private let discovery: LightweightDiscoveryService
  private let orchestrator: TranscriptOrchestrator
  private let fastPath: FastPathIngestionCoordinator

  // State
  @Published public private(set) var state: AppState = .startup
  private var knownProjects: [LightweightProject] = []
  private var backgroundTask: Task<Void, Never>?

  private init() {
    let db = DatabaseManager.shared
    self.orchestrator = try! TranscriptOrchestrator(dbManager: db)
    self.discovery = LightweightDiscoveryService()
    self.fastPath = FastPathIngestionCoordinator(orchestrator: orchestrator)
  }

  /// Update state and notify observers
  private func setState(_ newState: AppState) {
    self.state = newState
    // Post notification for compatibility with NotificationCenter observers
    NotificationCenter.default.post(name: .appStateDidChange, object: newState)
    log.debug("[ORCH-STATE] State changed to: \(String(describing: newState))")
  }

  // MARK: - Startup Flow

  /// Performs lightweight startup: filesystem scan only, NO DB writes
  /// Expected duration: <200ms
  public func startup() async {
    log.info("[ORCH-STARTUP] Beginning lightweight startup...")
    let startTime = Date()

    setState(.discovering)

    // 1. Lightweight Scan (stat-only, no file reads, no DB writes)
    let projects = await discovery.discoverProjectsLightweight()
    self.knownProjects = projects
    log.info("[ORCH-STARTUP] Discovered \(projects.count, privacy: .public) projects")

    // 2. Update projects table metadata ONLY (single transaction, no transcripts)
    do {
      try await orchestrator.updateProjectsMetadataOnly(projects)
      log.debug("[ORCH-STARTUP] Updated projects table metadata")
    } catch {
      log.error("[ORCH-STARTUP] Failed to update project metadata: \(error.localizedDescription, privacy: .public)")
    }

    // 3. Show UI immediately
    setState(.idle(projects: projects))

    let duration = Date().timeIntervalSince(startTime)
    log.info("[ORCH-STARTUP] Startup complete in \(String(format: "%.3f", duration), privacy: .public)s. UI ready.")

    // 4. PATCH C: Auto-select most recent project (projects are already sorted by activity)
    if let mostRecent = projects.first {
      log.info("[ORCH-STARTUP] Auto-selecting most recent project: \(mostRecent.id, privacy: .public)")
      await selectProject(id: mostRecent.id)
    } else {
      log.info("[ORCH-STARTUP] No projects found - showing empty state")
      // 5. Optional: Start background indexing (low priority)
      startBackgroundIndexing()
    }
  }

  // MARK: - User Selection Flow

  /// User clicked a project - perform JIT (Just-In-Time) ingestion
  /// Expected duration: <1s for typical project
  public func selectProject(id: String) async {
    log.info("[ORCH-SELECT] User selected project: \(id, privacy: .public)")

    // 1. Cancel background work
    backgroundTask?.cancel()
    await fastPath.cancel()

    guard let project = knownProjects.first(where: { $0.id == id }) else {
      log.error("[ORCH-SELECT] Project not found: \(id, privacy: .public)")
      setState(.error("Project not found"))
      return
    }

    // 2. UI Loading State
    setState(.loading(projectId: id))

    let startTime = Date()
    log.info("[ORCH-SELECT] Loading project: \(project.path.lastPathComponent, privacy: .public)")

    do {
      // 3. JIT Ingestion (FastPath with batching)
      // This will ingest ONLY this project's transcripts on demand
      try await fastPath.ingestProjectJIT(project)

      // 4. PATCH B: Wire ConversationMonitor via StartupCoordinator
      // This updates ActiveProjectContext and triggers timeline loading
      let projectPath = project.cwd ?? project.path.path
      do {
        try await StartupCoordinator.shared.switchProject(to: projectPath)
        log.debug("[ORCH-SELECT] StartupCoordinator updated with path: \(projectPath, privacy: .public)")
      } catch {
        log.warning("[ORCH-SELECT] Failed to update StartupCoordinator: \(error.localizedDescription, privacy: .public)")
        // Non-fatal - continue with activation
      }

      // 5. Activate
      setState(.active(projectId: id))

      let duration = Date().timeIntervalSince(startTime)
      log.info("[ORCH-SELECT] Project ready in \(String(format: "%.3f", duration), privacy: .public)s")

      // 6. Notify other components (Timeline, etc.)
      NotificationCenter.default.post(name: .projectDidActivate, object: id)

    } catch {
      log.error("[ORCH-SELECT] Failed to load project: \(error.localizedDescription, privacy: .public)")
      setState(.error("Failed to load project: \(error.localizedDescription)"))
    }

    // 6. Resume background work
    startBackgroundIndexing()
  }

  // MARK: - Background Indexing

  /// Low-priority background task to pre-ingest inactive projects
  private func startBackgroundIndexing() {
    backgroundTask?.cancel()

    backgroundTask = Task(priority: .utility) { @MainActor in
      // Wait 5 seconds after user activity before starting
      try? await Task.sleep(nanoseconds: 5_000_000_000)

      log.info("[ORCH-BACKGROUND] Starting background indexing...")

      // Ingest projects one at a time, checking for cancellation
      for project in self.knownProjects {
        if Task.isCancelled {
          log.info("[ORCH-BACKGROUND] Indexing cancelled")
          break
        }

        // Skip if already ingested
        let hasTranscripts = (try? await self.orchestrator.getTranscripts(forProject: project.id).isEmpty) == false
        if hasTranscripts {
          continue
        }

        // Ingest this project
        do {
          try await self.fastPath.ingestProjectJIT(project)
          log.debug("[ORCH-BACKGROUND] Ingested project: \(project.id, privacy: .public)")
        } catch {
          log.warning("[ORCH-BACKGROUND] Failed to ingest \(project.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        // Yield between projects
        await Task.yield()
      }

      log.info("[ORCH-BACKGROUND] Background indexing complete")
    }
  }
}

// MARK: - Supporting Types

/// Lightweight project metadata (no DB required)
public struct LightweightProject: Sendable, Identifiable, Hashable {
  public let id: String
  public let path: URL
  public let transcriptCount: Int
  public let lastActivity: Date
  public let provider: String
  public let cwd: String?  // Current working directory (for Codex) or repo path (for Claude)
  public let transcriptFiles: [URL]  // File paths discovered during scan (for JIT ingestion)

  public init(id: String, path: URL, transcriptCount: Int, lastActivity: Date, provider: String, cwd: String? = nil, transcriptFiles: [URL] = []) {
    self.id = id
    self.path = path
    self.transcriptCount = transcriptCount
    self.lastActivity = lastActivity
    self.provider = provider
    self.cwd = cwd
    self.transcriptFiles = transcriptFiles
  }
}

// MARK: - Notifications

extension Notification.Name {
  public static let projectDidActivate = Notification.Name("projectDidActivate")
  public static let appStateDidChange = Notification.Name("appStateDidChange")
}
