import SwiftUI
import AppKit
import ContextifyCore
import OSLog

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
  @State private var projectsViewModel: ProjectsViewModel?
  @State private var backgroundRefreshTimer: Timer?
  @State private var projectDirectoryMonitor: FSEventsMonitor?

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
      // PHASE 1: Start coordinator FIRST (establishes project identity)
      do {
        try await StartupCoordinator.shared.start()
        startupLog.info("✅ StartupCoordinator started successfully")
      } catch {
        startupLog.error("❌ StartupCoordinator failed: \(error.localizedDescription)")
        // Continue anyway - ProjectSwitcherState will handle missing context gracefully
      }

      // PHASE 2: Start dependent systems (now safe - coordinator has published context)
      ProjectSwitcherState.shared.start()
      startupLog.info("✅ ProjectSwitcherState started")
    }
  }

  var body: some Scene {
    Window("Contextify", id: "main") {
      ContentView()
        .environment(model)
        .environment(timeline)
        .environment(DeveloperMode.shared)
        .environment(ProjectSwitcherState.shared)  // Inject singleton so UI uses same instance
        .background(WindowAccessor())
        .task {
          // Initialize projects system and auto-discover at app launch
          await initializeProjectsSystem()
        }
    }
    .defaultSize(width: 1200, height: 360)  // Timeline-only default for v1.0
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
            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
            let discoveryService = ProjectDiscoveryService(
              db: try DatabaseManager.shared.pool,
              orchestrator: orchestrator
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
      // Initialize projects view model
      let orchestrator = try TranscriptOrchestrator(dbManager: .shared)

      // Reconcile pending assistant_usage records at startup
      try? orchestrator.reconcileAssistantUsage()

      let discoveryService = ProjectDiscoveryService(
        db: try DatabaseManager.shared.pool,
        orchestrator: orchestrator
      )
      let vm = ProjectsViewModel(
        discoveryService: discoveryService,
        hudModel: HUDViewModel.shared
      )
      self.projectsViewModel = vm

      // Auto-discover all projects at launch
      log.info("🔍 Starting auto-discovery at app launch")
      await vm.discoverProjects()
      log.info("✅ Auto-discovery complete")

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
