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

@main
struct ContextifyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let model = HUDViewModel.shared
  private let timeline = ConversationMonitor.shared
  @State private var projectsViewModel: ProjectsViewModel?
  @State private var backgroundRefreshTimer: Timer?

  init() {
    let startupLog = Logger(subsystem: "dev.contextify", category: "Startup")
    startupLog.fault("🚀🚀🚀 CONTEXTIFY LAUNCHED - NEW BUILD WITH DIAGNOSTIC LOGGING 🚀🚀🚀")

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
  }

  var body: some Scene {
    Window("Contextify", id: "main") {
      ContentView()
        .environment(model)
        .environment(timeline)
        .environment(DeveloperMode.shared)
        .background(WindowAccessor())
        .task {
          // Initialize projects system and auto-discover at app launch
          await initializeProjectsSystem()
        }
    }
    .defaultSize(width: 940, height: 360)
    .commands {
      CommandGroup(replacing: .newItem) { }
      ProjectRootCommands()
      WindowCommands()
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

      // Start background refresh timer (every 10 minutes)
      startBackgroundRefresh(viewModel: vm)

    } catch {
      log.error("❌ Failed to initialize projects system: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func startBackgroundRefresh(viewModel: ProjectsViewModel) {
    let log = Logger(subsystem: "dev.contextify", category: "Projects")
    log.info("⏰ Starting background refresh timer (10 minutes)")

    // Cancel any existing timer
    backgroundRefreshTimer?.invalidate()

    // Create new timer
    backgroundRefreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
      Task { @MainActor in
        log.debug("⏰ Background refresh triggered")
        await viewModel.discoverProjects()
      }
    }
  }
}

struct ProjectRootCommands: Commands {
  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Open project...") { pickProjectRoot() }
    }
  }

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
