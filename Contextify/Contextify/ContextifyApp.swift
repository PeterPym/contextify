import SwiftUI
import AppKit
import ContextifyCore
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Discovery Errors

enum DiscoveryError: Error {
  case timeout
}

struct WindowCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Window") {
      Button("Show Transcript Inventory") {
        openWindow(id: "transcript-inventory")
      }
      .keyboardShortcut("i", modifiers: [.command, .control])

      Button("Projects") {
        openWindow(id: "projects")
      }
      .keyboardShortcut("p", modifiers: [.command, .shift])

      Button("Transcript Sources...") {
        openWindow(id: "transcript-sources")
      }
      .keyboardShortcut("t", modifiers: [.command, .option])

      Divider()

      Button("Previous Project") {
        Task {
          await ProjectSwitcherState.shared.cycleToPreviousProject()
        }
      }
      .keyboardShortcut("[", modifiers: [.command, .shift])

      Button("Next Project") {
        Task {
          await ProjectSwitcherState.shared.cycleToNextProject()
        }
      }
      .keyboardShortcut("]", modifiers: [.command, .shift])
    }
  }
}

struct HelpCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    // Replace the default help menu with custom structure
    CommandGroup(replacing: .help) {
      // Quick access to documentation
      Button("Getting Started") {
        openHelpTopic(.gettingStarted)
      }

      Divider()

      // Feature-specific help
      Menu("Feature Guides") {
        Button("Projects & Discovery") {
          openHelpTopic(.projects)
        }
        Button("Timeline Monitoring") {
          openHelpTopic(.timeline)
        }
        Button("AI Integration") {
          openHelpTopic(.aiIntegration)
        }
        Button("Database & Sync") {
          openHelpTopic(.database)
        }
      }

      Menu("Troubleshooting") {
        Button("AI Unavailable") {
          openHelpTopic(.troubleshootingAI)
        }
        Button("Project Not Found") {
          openHelpTopic(.troubleshootingProject)
        }
        Button("Database Issues") {
          openHelpTopic(.troubleshootingDatabase)
        }
        Button("LLM Generation Failures") {
          openHelpTopic(.troubleshootingLLM)
        }
      }

      Divider()

      Button("Keyboard Shortcuts") {
        openHelpTopic(.keyboardShortcuts)
      }

      Divider()

      Button("Contact Support...") {
        SystemInfo.openSupportEmail()
      }
    }
  }

  private func openHelpTopic(_ topic: HelpTopic) {
    // For now, open a simple help window. In future, this could be:
    // - Local HTML help book
    // - Online documentation
    // - In-app help viewer
    if let url = topic.url {
      NSWorkspace.shared.open(url)
    }
  }
}

// MARK: - Help Topics

enum HelpTopic {
  case gettingStarted
  case projects
  case timeline
  case aiIntegration
  case database
  case troubleshootingAI
  case troubleshootingProject
  case troubleshootingDatabase
  case troubleshootingLLM
  case keyboardShortcuts

  var url: URL? {
    // For now, return nil to indicate help content not yet implemented
    // In future, this would return URLs to:
    // - GitHub wiki pages
    // - Local help book pages
    // - Online documentation site
    return nil
  }

  var title: String {
    switch self {
    case .gettingStarted: return "Getting Started with Contextify"
    case .projects: return "Projects & Discovery"
    case .timeline: return "Timeline Monitoring"
    case .aiIntegration: return "AI Integration"
    case .database: return "Database & Sync"
    case .troubleshootingAI: return "Troubleshooting: AI Unavailable"
    case .troubleshootingProject: return "Troubleshooting: Project Not Found"
    case .troubleshootingDatabase: return "Troubleshooting: Database Issues"
    case .troubleshootingLLM: return "Troubleshooting: LLM Failures"
    case .keyboardShortcuts: return "Keyboard Shortcuts"
    }
  }
}

// Shared container for background tasks that need lifecycle management
@MainActor
final class AppLifecycleState {
  static let shared = AppLifecycleState()
  var projectMonitoringTask: Task<Void, Never>?

  private init() {}
}

@main
struct ContextifyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let model = HUDViewModel.shared
  private let timeline = ConversationMonitor.shared
  @StateObject private var folderAccessController = FolderAccessController()  // App Store authorization
  @State private var projectsViewModel: ProjectsViewModel?
  @State private var backgroundRefreshTimer: Timer?
  @State private var projectDirectoryMonitor: FSEventsMonitor?
  @State private var showWelcomeModal = false  // C3.2: Welcome modal state

  init() {
    let startupLog = Logger(subsystem: "dev.contextify", category: "Startup")
    startupLog.notice("🚀 Contextify launched")

    // Pre-warm expensive framework initialization off main thread
    // (Unified logging, Security.framework, CoreFoundation, Bundle parsing)
    StartupWarmup.run()

    // Check for existing instance
    if isAnotherInstanceRunning() {
      // In development, kill the old instance and proceed
      #if DEBUG
      if let existing = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == Bundle.main.bundleIdentifier &&
        $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
      }) {
        existing.terminate()
        // Give it a moment to shut down
        Thread.sleep(forTimeInterval: 0.5)
      }
      #else
      // In production, show alert and quit
      showSingleInstanceAlert()
      NSApplication.shared.terminate(nil)
      #endif
    }

    // Start coordinator and ProjectSwitcherState from app init for deterministic startup
    Task { @MainActor in
      // PHASE 0: Pre-warm LLM health check (makes first StatusBarViewModel instant)
      #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        startupLog.info("🔍 Pre-warming LLM health check...")
        _ = await LLMHealthCheck.shared.checkHealth()
        startupLog.info("✅ LLM health check cached")
      }
      #endif

      // PHASE 1: Start coordinator FIRST (establishes project identity)
      // Note: start() now gracefully handles "no project" state (never throws)
      await StartupCoordinator.shared.start()
      startupLog.info("✅ StartupCoordinator started successfully")

      // PHASE 2: Start dependent systems (now safe - coordinator has published context)
      ProjectSwitcherState.shared.start()
      startupLog.info("✅ ProjectSwitcherState started")

      // PHASE 3: Subscribe to welcome modal trigger (C3.3)
      // Note: Using onReceive in view body instead of manual NotificationCenter
      // to work with SwiftUI's state management (@State cannot be mutated from closure)
    }
  }

  var body: some Scene {
    Window("Contextify", id: "main") {
      Group {
        if let vm = projectsViewModel {
          // C2.2: Pass ProjectsViewModel via environment
          ContentView()
            .environment(model)
            .environment(timeline)
            .environment(DeveloperMode.shared)
            .environment(ProjectSwitcherState.shared)
            .environment(vm)  // Add ProjectsViewModel
            .background(WindowAccessor())
            .sheet(isPresented: $showWelcomeModal) {
              // C3.4: Welcome modal sheet
              // User must manually dismiss to ensure they see progress complete
              WelcomeModalView(folderAccessController: folderAccessController)
                .environment(vm)
                .interactiveDismissDisabled(vm.isDiscovering || vm.isIngesting)
            }
        } else {
          // Initialization loading state (brief)
          VStack(spacing: 12) {
            ProgressView()
            Text("Initializing...")
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .task {
        // C2.1: Initialize ProjectsViewModel early
        if projectsViewModel == nil {
          do {
            // Only use folder access controller in sandboxed builds
            #if APPSTORE
            let controller: FolderAccessController? = folderAccessController
            #else
            let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            let controller: FolderAccessController? = isSandboxed ? folderAccessController : nil
            #endif

            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
            let discoveryService = ProjectDiscoveryService(
              db: try DatabaseManager.shared.pool,
              orchestrator: orchestrator,
              folderAccessController: controller
            )
            let vm = ProjectsViewModel(
              discoveryService: discoveryService,
              hudModel: HUDViewModel.shared
            )
            self.projectsViewModel = vm
          } catch {
            let log = Logger(subsystem: "dev.contextify", category: "Startup")
            log.error("Failed to initialize ProjectsViewModel: \(error.localizedDescription)")
          }
        }

        // Initialize projects system and auto-discover at app launch
        await initializeProjectsSystem()
      }
      .onReceive(NotificationCenter.default.publisher(for: .startupRequiresWelcomeModal)) { _ in
        showWelcomeModal = true
      }
    }
    .defaultSize(width: 940, height: 360)  // Main content (640) + Timeline sidebar (300)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(replacing: .newItem) { }
      ProjectRootCommands()
      WindowCommands()
      HelpCommands()
    }

    Settings {
      SettingsView()
    }

    // Transcript Sources settings window
    Window("Transcript Sources", id: "transcript-sources") {
      TranscriptSourcesSettingsView(folderAccessController: folderAccessController)
    }
    .defaultSize(width: 500, height: 350)
    .windowResizability(.contentSize)

    Window("Transcript Inventory", id: "transcript-inventory") {
      TranscriptInventoryWindow()
        .environment(HUDViewModel.shared)
        .environment(ConversationMonitor.shared)
        .environment(DeveloperMode.shared)
    }
    .defaultSize(width: 1000, height: 700)

    Window("Projects", id: "projects") {
      if let viewModel = projectsViewModel {
        ProjectsWindow()
          .environment(viewModel)
          .environment(ConversationMonitor.shared)
      } else {
        VStack(spacing: 12) {
          ProgressView()
          Text("Initializing projects...")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
          // Initialize on first window open
          do {
            // Only use folder access controller in sandboxed builds
            #if APPSTORE
            let controller: FolderAccessController? = folderAccessController
            #else
            let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            let controller: FolderAccessController? = isSandboxed ? folderAccessController : nil
            #endif

            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
            let discoveryService = ProjectDiscoveryService(
              db: try DatabaseManager.shared.pool,
              orchestrator: orchestrator,
              folderAccessController: controller
            )
            let vm = ProjectsViewModel(
              discoveryService: discoveryService,
              hudModel: HUDViewModel.shared
            )
            self.projectsViewModel = vm

            // Auto-discover
            await vm.discoverProjects()
          } catch {
            let log = Logger(subsystem: "dev.contextify", category: "Projects")
            log.error("Failed to initialize projects: \(error.localizedDescription)")
          }
        }
      }
    }
    .defaultSize(width: 800, height: 600)
  }

  private func isAnotherInstanceRunning() -> Bool {
    let runningApps = NSWorkspace.shared.runningApplications
    let contextifyApps = runningApps.filter { app in
      app.bundleIdentifier == Bundle.main.bundleIdentifier &&
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
    return !contextifyApps.isEmpty
  }

  private func showSingleInstanceAlert() {
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.messageText = "Contextify is Already Running"
      alert.informativeText = "Only one instance of Contextify can run at a time. The existing instance will be brought to the front."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "OK")
      alert.runModal()

      // Activate the existing instance
      if let existing = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == Bundle.main.bundleIdentifier &&
        $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
      }) {
        existing.activate()
      }
    }
  }

  @MainActor
  private func initializeProjectsSystem() async {
    let log = Logger(subsystem: "dev.contextify", category: "Projects")
    log.info("🔍 Initializing projects system at app launch")

    do {
      // Initialize projects view model (C2.1 - may already be set from window .task)
      if projectsViewModel == nil {
        // Only use folder access controller in sandboxed builds
        #if APPSTORE
        let controller: FolderAccessController? = folderAccessController
        #else
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let controller: FolderAccessController? = isSandboxed ? folderAccessController : nil
        #endif

        let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
        let discoveryService = ProjectDiscoveryService(
          db: try DatabaseManager.shared.pool,
          orchestrator: orchestrator,
          folderAccessController: controller
        )
        let vm = ProjectsViewModel(
          discoveryService: discoveryService,
          hudModel: HUDViewModel.shared
        )
        self.projectsViewModel = vm
      }

      guard let vm = projectsViewModel else {
        log.error("ProjectsViewModel not available")
        return
      }

      // Check if database is empty BEFORE starting discovery
      // This avoids race condition where ingestion completes before we check
      let isEmptyDB: Bool
      do {
        let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
        isEmptyDB = (try? orchestrator.listProjects().isEmpty) ?? false
        if isEmptyDB {
          log.info("📋 Empty database detected - showing welcome modal before discovery starts")
          // Post notification to show welcome modal BEFORE discovery starts
          await MainActor.run {
            NotificationCenter.default.post(name: .startupRequiresWelcomeModal, object: nil)
          }
        }
      } catch {
        log.warning("Failed to check if database is empty: \(error.localizedDescription)")
        isEmptyDB = false
      }

      // Reconcile pending assistant_usage records at startup
      do {
        let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
        try orchestrator.reconcileAssistantUsage()
      } catch {
        log.warning("Failed to reconcile assistant usage: \(error.localizedDescription)")
      }

      // Reset display_order for first-launch sorting by activity
      // (On fresh database, all projects should sort by newest entry, not persisted order)
      do {
        let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
        try orchestrator.resetDisplayOrder()
        log.info("🔄 Reset display_order for activity-based sorting")
      } catch {
        log.warning("Failed to reset display_order: \(error.localizedDescription)")
      }

      // Auto-discover all projects at launch with timeout protection (60s max)
      log.info("🔍 Starting auto-discovery at app launch")

      do {
        try await withThrowingTaskGroup(of: Void.self) { group in
          // Discovery task
          group.addTask {
            await vm.discoverProjects()
          }

          // Timeout task (60 seconds max)
          group.addTask {
            try await Task.sleep(for: .seconds(60))
            throw DiscoveryError.timeout
          }

          // Wait for first to complete
          try await group.next()
          group.cancelAll()
        }
        log.info("✅ Auto-discovery complete")
      } catch is DiscoveryError {
        log.error("❌ Discovery timed out after 60s")
        // Continue with whatever projects were found
      }

      // Reset display_order AFTER ingestion so projects sort by activity
      // (getOrCreateProject assigns incrementing display_order during ingestion)
      do {
        let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
        try orchestrator.resetDisplayOrder()
        log.info("[BACKEND-RESET-POST] Reset display_order after ingestion complete")
      } catch {
        log.warning("Failed to reset display_order after ingestion: \(error.localizedDescription)")
      }

      // C4.2: Auto-select most recent project if coordinator has no current project
      // Fix: Use MainActor.run for atomic check-and-set to prevent TOCTOU race
      await MainActor.run {
        // Only proceed if still no project (atomic check)
        guard StartupCoordinator.shared.current == nil, !vm.projects.isEmpty else {
          if StartupCoordinator.shared.current != nil {
            // Normal launch with existing project - keep modal open until timeline populated
            // Modal will auto-dismiss once user has content to view
            log.debug("Normal launch with existing project - keeping modal open until content ready")
          } else {
            // C6.1: No projects found - keep modal open to show "no projects" state
            log.warning("⚠️  Discovery complete but no projects found")
          }
          return
        }

        // Atomically perform selection within MainActor context
        Task {
          do {
            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)

            // Try to get project with newest transcript entry (most recent work)
            if let mostRecent = try orchestrator.getProjectWithNewestEntry() {
              log.notice("🎯 Auto-selecting project with newest entry: \(mostRecent.rootPath, privacy: .public)")
              try await StartupCoordinator.shared.switchProject(to: mostRecent.rootPath)
            } else if let first = vm.projects.first {
              // Fallback: select first discovered project
              log.notice("🎯 Auto-selecting first discovered project: \(first.name)")
              try await StartupCoordinator.shared.switchProject(to: first.path.path)
            }

            // Wait for timeline to start monitoring before closing modal
            log.info("⏳ Waiting for timeline to initialize...")
            try await Task.sleep(for: .milliseconds(500))

            // Show completion message with happy emoji
            await MainActor.run {
              vm.setDiscoveryProgress(DiscoveryProgress(
                phase: .complete,
                projectsCompleted: vm.projects.count,
                projectsTotal: vm.projects.count,
                message: "🎉 Initial setup complete! Welcome to Contextify"
              ))
            }

            // C4.3: Leave modal open - let user click "Get Started" button
            // (Auto-dismiss was causing UX issues - user should control when to close)
            log.info("✅ Auto-selection complete, modal showing completion state")

          } catch {
            log.error("Failed to auto-select project: \(error.localizedDescription, privacy: .public)")
            // Keep modal open so user can see error state or manually select
          }
        }
      }

      // Post notification for coordination
      NotificationCenter.default.post(
        name: .projectsDiscoveryComplete,
        object: vm.projects
      )

      // Start FSEvents monitoring for new projects
      await startProjectDirectoryMonitoring(viewModel: vm)

    } catch {
      log.error("❌ Failed to initialize projects system: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func startProjectDirectoryMonitoring(viewModel: ProjectsViewModel) async {
    let log = Logger(subsystem: "dev.contextify", category: "Projects")

    // Get paths to monitor - Claude Code project directories and Codex CLI session directories
    let claudeProjectsPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/projects")
      .path
    let codexProjectsPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/sessions")
      .path

    // Only watch directories that exist
    var pathsToWatch: [String] = []
    if FileManager.default.fileExists(atPath: claudeProjectsPath) {
      pathsToWatch.append(claudeProjectsPath)
      log.info("📁 Monitoring Claude Code projects: \(claudeProjectsPath)")
    }
    if FileManager.default.fileExists(atPath: codexProjectsPath) {
      pathsToWatch.append(codexProjectsPath)
      log.info("📁 Monitoring Codex CLI sessions: \(codexProjectsPath)")
    }

    guard !pathsToWatch.isEmpty else {
      log.warning("⚠️ No project directories found to monitor")
      return
    }

    // Create FSEvents monitor with 0.5s latency
    let monitor = FSEventsMonitor(paths: pathsToWatch, latency: 0.5)
    self.projectDirectoryMonitor = monitor

    // Start monitoring in background task (off MainActor to avoid UI blocking)
    let monitoringTask = Task(priority: .utility) { [weak viewModel] in
      log.info("👀 Starting FSEvents monitoring for new projects")
      let stream = monitor.start()

      for await event in stream {
        // Check if this is a directory creation event
        let isCreated = (event.flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)) != 0 &&
                       (event.flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0

        if isCreated {
          log.info("🆕 New project directory detected: \(event.path)")

          // Debounce - wait a moment for files to be written
          try? await Task.sleep(for: .seconds(1))

          // Re-discover projects (hop to main for VM interaction)
          guard let vm = viewModel else { continue }
          await vm.discoverProjects()
          log.info("✅ Project discovery triggered by FSEvents")
        }
      }
    }

    AppLifecycleState.shared.projectMonitoringTask = monitoringTask
  }
}

struct ProjectRootCommands: Commands {
  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Open project...") { pickProjectRoot() }
    }
  }

  @MainActor
  private func pickProjectRoot() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    if panel.runModal() == .OK, let url = panel.urls.first {
      _ = HUDViewModel.shared.setProjectRoot(url: url)
    }
  }
}
