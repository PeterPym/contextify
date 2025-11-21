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
      Button("Show Transcripts") {
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
    startupLog.notice("🚀 Contextify launched (Phase 3 Lazy Loading)")

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

    // Phase 3: Start AppStateOrchestrator (replaces old startup logic)
    Task { @MainActor in
      // PHASE 0: Pre-warm LLM health check (makes first StatusBarViewModel instant)
      #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        startupLog.info("🔍 Pre-warming LLM health check...")
        _ = await LLMHealthCheck.shared.checkHealth()
        startupLog.info("✅ LLM health check cached")
      }
      #endif

      // PHASE 1: Lightweight startup via AppStateOrchestrator (<200ms target)
      await AppStateOrchestrator.shared.startup()
      startupLog.info("✅ AppStateOrchestrator startup complete")

      // PHASE 2: Start legacy coordinators (for now - will migrate later)
      await StartupCoordinator.shared.start()
      ProjectSwitcherState.shared.start()
      startupLog.info("✅ Legacy coordinators started")
    }
  }

  var body: some Scene {
    Window("Contextify", id: "main") {
      Group {
        if let vm = projectsViewModel {
          // C2.2: Pass ProjectsViewModel via environment
          ContentView()
            .frame(minHeight: 500)
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
        // Initialize projects system and auto-discover at app launch
        await initializeProjectsSystem()
      }
      .onReceive(NotificationCenter.default.publisher(for: .startupRequiresWelcomeModal)) { _ in
        let startupLog = Logger(subsystem: "dev.contextify", category: "Projects")
        startupLog.info("[WELCOME-TRIGGERED] Welcome modal notification received")
        startupLog.info("[WELCOME-STATE] Setting showWelcomeModal = true")
        showWelcomeModal = true
      }
    }
    .defaultSize(width: 400, height: 500)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(replacing: .newItem) { }
      ProjectRootCommands()
      WindowCommands()
      HelpCommands()
      CommandMenu("Diagnostics") {
        Button("Force Hoover Rescan") {
          ProjectSwitcherState.shared.triggerManualHooverRescan(reason: "DiagnosticsMenu")
        }
        .keyboardShortcut("r", modifiers: [.command, .option, .shift])
      }
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

    Window("Transcripts", id: "transcript-inventory") {
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
          // Initialize projects system (single source of truth with accessProvider)
          await initializeProjectsSystem()
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

  /// Run quick-discovery and ingest newest transcript (called after authorization granted in App Store builds)

  /// Reconfigures the access provider after permissions are granted.
  /// This rebuilds the SandboxTranscriptAccessProvider with newly granted URLs
  /// and reconfigures AppStateOrchestrator so discovery can succeed.
  @MainActor
  static func reconfigureAccessProvider(folderAccessController: FolderAccessController) async {
    #if APPSTORE_BUILD
    let log = Logger(subsystem: "dev.contextify", category: "Projects")
    log.info("[RECONFIG-ACCESS] Rebuilding access provider with newly granted permissions")

    // Read fresh authorizations from FolderAccessController
    let claudeAuth = await folderAccessController.authorization(for: .claude)
    let codexAuth = await folderAccessController.authorization(for: .codex)

    var claudeURL: URL? = nil
    if let auth = claudeAuth, auth.status == .authorized {
      claudeURL = try? await folderAccessController.resolve(auth).url
    }

    var codexURL: URL? = nil
    if let auth = codexAuth, auth.status == .authorized {
      codexURL = try? await folderAccessController.resolve(auth).url
    }

    log.info("[RECONFIG-ACCESS] Claude: \(claudeURL != nil ? "authorized" : "nil"), Codex: \(codexURL != nil ? "authorized" : "nil")")

    // Create new provider with fresh URLs
    let newProvider = SandboxTranscriptAccessProvider(
      claudeRoot: claudeURL,
      codexRoot: codexURL
    )

    // Reconfigure orchestrator
    await AppStateOrchestrator.shared.configureAccessProvider(newProvider)
    log.info("[RECONFIG-ACCESS] ✅ AppStateOrchestrator reconfigured with new access provider")
    #endif
  }

  static func runQuickDiscoveryAndIngest(projectsVM: ProjectsViewModel) async {
    let log = Logger(subsystem: "dev.contextify", category: "Projects")
    log.info("[QUICK-DISCOVERY] Starting lightweight scan for newest project (post-authorization)")
    let quickStart = Date()

    do {
      // Run quick-discovery with 2-second timeout
      let quickResult = try await withThrowingTaskGroup(of: (projectPath: URL, transcriptFile: URL, mtime: Date)?.self) { group in
        // Quick-discovery task
        group.addTask {
          await projectsVM.discoveryService.quickDiscoverNewest()
        }

        // Timeout task (2 seconds max)
        group.addTask {
          try await Task.sleep(for: .seconds(2))
          return nil
        }

        // Wait for first to complete
        let result = try await group.next()
        group.cancelAll()
        return result ?? nil
      }

      let quickDuration = Date().timeIntervalSince(quickStart)

      if let newest = quickResult {
        log.info("[QUICK-DISCOVERY] Found newest: \(newest.projectPath.path, privacy: .public) transcript: \(newest.transcriptFile.lastPathComponent, privacy: .public) (took \(Int(quickDuration * 1000))ms)")

        // If different from current, switch immediately
        if let currentPath = StartupCoordinator.shared.current?.path,
           currentPath != newest.projectPath.path {
          log.notice("[QUICK-DISCOVERY-SWITCH] Switching from \(currentPath, privacy: .public) to \(newest.projectPath.path, privacy: .public)")

          do {
            // Ensure project exists in database before switching
            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
            let projectId = try orchestrator.getOrCreateProject(name: nil, rootPath: newest.projectPath.path)

            // Now switch to the project
            try await StartupCoordinator.shared.switchProject(to: newest.projectPath.path)
            log.info("[QUICK-DISCOVERY-SWITCH] ✅ Switch complete, project_id: \(projectId, privacy: .public)")

            // Ingest newest transcript
            await ingestNewestTranscript(
              projectId: projectId,
              projectPath: newest.projectPath,
              transcriptFile: newest.transcriptFile,
              orchestrator: orchestrator
            )
          } catch {
            log.error("[QUICK-DISCOVERY-SWITCH] ❌ Switch failed: \(error.localizedDescription)")
          }
        } else {
          log.info("[QUICK-DISCOVERY-SWITCH] No switch needed (already at newest project)")

          // Even if no switch, still ingest newest transcript for fast timeline
          do {
            let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
            let projectId = try orchestrator.getOrCreateProject(name: nil, rootPath: newest.projectPath.path)

            await ingestNewestTranscript(
              projectId: projectId,
              projectPath: newest.projectPath,
              transcriptFile: newest.transcriptFile,
              orchestrator: orchestrator
            )
          } catch {
            log.error("[QUICK-DISCOVERY-INGEST] ❌ Failed to ingest newest transcript: \(error.localizedDescription)")
          }
        }
      } else {
        log.info("[QUICK-DISCOVERY] No projects found or scan timed out (took \(Int(quickDuration * 1000))ms)")
      }
    } catch {
      let quickDuration = Date().timeIntervalSince(quickStart)
      log.error("[QUICK-DISCOVERY] Error: \(error.localizedDescription) (took \(Int(quickDuration * 1000))ms)")
    }
  }

  @MainActor
  private func initializeProjectsSystem() async {
    let log = Logger(subsystem: "dev.contextify", category: "Projects")
    log.info("🔍 Initializing projects system at app launch")

    // Log build type (compile-time check)
    #if APPSTORE_BUILD
    log.info("[INIT-BUILD-TYPE] Compiled with APPSTORE_BUILD flag (sandboxed)")
    #else
    log.info("[INIT-BUILD-TYPE] Compiled WITHOUT APPSTORE_BUILD flag (DMG/unsandboxed)")
    #endif

    do {
      // Initialize projects view model (C2.1 - may already be set from window .task)
      if projectsViewModel == nil {
        // Only use folder access controller in sandboxed builds
        // Use compile-time check based on entitlements (runtime check is unreliable)
        let controller: FolderAccessController? = Sandbox.isSandboxed ? folderAccessController : nil

        log.info("[INIT-SANDBOX-CHECK] Sandbox.isSandboxed = \(Sandbox.isSandboxed, privacy: .public)")
        log.info("[INIT-CONTROLLER] FolderAccessController: \(controller == nil ? "nil" : "present", privacy: .public)")

        // Build TranscriptAccessProvider
        let accessProvider: TranscriptAccessProvider

        #if APPSTORE_BUILD
        // App Store build: security-scoped URLs from FolderAccessController
        let claudeAuth = await folderAccessController.authorization(for: .claude)
        let codexAuth  = await folderAccessController.authorization(for: .codex)

        var claudeURL: URL? = nil
        if let auth = claudeAuth, auth.status == .authorized {
          claudeURL = try? await folderAccessController.resolve(auth).url
        }

        var codexURL: URL? = nil
        if let auth = codexAuth, auth.status == .authorized {
          codexURL = try? await folderAccessController.resolve(auth).url
        }

        accessProvider = SandboxTranscriptAccessProvider(
          claudeRoot: claudeURL,
          codexRoot: codexURL
        )
        log.info("[INIT] Created sandbox access provider (claude: \(claudeAuth?.status.rawValue ?? "none"), codex: \(codexAuth?.status.rawValue ?? "none"))")

        #else
        // DMG build: direct filesystem access
        accessProvider = PassthroughAccessProvider()
        log.info("[INIT] Created passthrough access provider (DMG build)")
        #endif

        // Configure AppStateOrchestrator with access provider
        await AppStateOrchestrator.shared.configureAccessProvider(accessProvider)

        // Initialize orchestrator with access provider
        let orchestrator = try TranscriptOrchestrator(
          dbManager: .shared,
          accessProvider: accessProvider
        )
        let discoveryService = ProjectDiscoveryService(
          db: try DatabaseManager.shared.pool,
          orchestrator: orchestrator,
          folderAccessController: controller
        )
        let vm = ProjectsViewModel(
          discoveryService: discoveryService,
          orchestrator: orchestrator,
          hudModel: HUDViewModel.shared
        )
        self.projectsViewModel = vm
        timeline.configureSharedOrchestrator(orchestrator)
      }

      guard let vm = projectsViewModel else {
        log.error("ProjectsViewModel not available")
        return
      }

      // Show welcome modal for onboarding when database is empty (0 projects).
      // Applies to ALL builds (DMG + App Store).
      //
      // The modal handles conditional logic internally:
      // - App Store builds: show permissions step first (if no bookmarks exist)
      // - DMG builds: skip permissions, go straight to discovery progress
      //
      // See WelcomeModalView.swift for complete onboarding workflow documentation.

      let isEmptyDB: Bool
      do {
        let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
        let projectCount = (try? orchestrator.listProjects().count) ?? 0
        isEmptyDB = projectCount == 0

        log.info("[INIT-DB-STATE] Database has \(projectCount, privacy: .public) projects, isEmpty: \(isEmptyDB, privacy: .public)")

        // Show welcome modal for all empty database cases (onboarding workflow)
        if isEmptyDB {
          log.info("[WELCOME-DECISION] DB empty = WILL show modal (sandboxed: \(Sandbox.isSandboxed, privacy: .public))")
          log.info("📋 Empty database detected - showing welcome modal for onboarding")
          // Post notification to show welcome modal BEFORE discovery starts
          await MainActor.run {
            NotificationCenter.default.post(name: .startupRequiresWelcomeModal, object: nil)
          }
        } else {
          log.info("[WELCOME-DECISION] DB not empty (\(projectCount, privacy: .public) projects) = will NOT show modal")
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

      let shouldResetDisplayOrder = isEmptyDB

      if shouldResetDisplayOrder {
        // Reset display_order for first-launch sorting by activity
        // (On fresh database, all projects should sort by newest entry, not persisted order)
        do {
          let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
          try orchestrator.resetDisplayOrder()
          log.info("🔄 Reset display_order for activity-based sorting")
        } catch {
          log.warning("Failed to reset display_order: \(error.localizedDescription)")
        }
      }

      // Auto-discover all projects at launch with timeout protection (60s max)
      log.info("🔍 Starting auto-discovery at app launch")

      // PHASE 2: Quick-discovery to identify newest project BEFORE full scan
      // This ensures timeline primes the correct project immediately
      //
      // For App Store builds with empty DB: skip quick-discovery now (no authorization yet)
      // and run it after user grants permissions in welcome modal
      let shouldSkipQuickDiscovery = Sandbox.isSandboxed && isEmptyDB

      if shouldSkipQuickDiscovery {
        log.info("[QUICK-DISCOVERY] Skipping quick-discovery (sandboxed build, will run after authorization)")
      } else if let vm = projectsViewModel {
        log.info("[QUICK-DISCOVERY] Starting lightweight scan for newest project")
        let quickStart = Date()

        do {
          // Run quick-discovery with 2-second timeout
          let quickResult = try await withThrowingTaskGroup(of: (projectPath: URL, transcriptFile: URL, mtime: Date)?.self) { group in
            // Quick-discovery task
            group.addTask {
              await vm.discoveryService.quickDiscoverNewest()
            }

            // Timeout task (2 seconds max)
            group.addTask {
              try await Task.sleep(for: .seconds(2))
              return nil
            }

            // Wait for first to complete
            let result = try await group.next()
            group.cancelAll()
            return result ?? nil
          }

          let quickDuration = Date().timeIntervalSince(quickStart)

          if let newest = quickResult {
            log.info("[QUICK-DISCOVERY] Found newest: \(newest.projectPath.path, privacy: .public) transcript: \(newest.transcriptFile.lastPathComponent, privacy: .public) (took \(Int(quickDuration * 1000))ms)")

            // If different from current, switch immediately
            if let currentPath = StartupCoordinator.shared.current?.path,
               currentPath != newest.projectPath.path {
              log.notice("[QUICK-DISCOVERY-SWITCH] Switching from \(currentPath, privacy: .public) to \(newest.projectPath.path, privacy: .public)")

              do {
                // Ensure project exists in database before switching
                let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
                let projectId = try orchestrator.getOrCreateProject(name: nil, rootPath: newest.projectPath.path)

                // Now switch to the project
                try await StartupCoordinator.shared.switchProject(to: newest.projectPath.path)
                log.info("[QUICK-DISCOVERY-SWITCH] ✅ Switch complete, project_id: \(projectId, privacy: .public)")

                // PHASE 2: Upsert transcript record and trigger FastPath
                await Self.ingestNewestTranscript(
                  projectId: projectId,
                  projectPath: newest.projectPath,
                  transcriptFile: newest.transcriptFile,
                  orchestrator: orchestrator
                )
              } catch {
                log.error("[QUICK-DISCOVERY-SWITCH] ❌ Switch failed: \(error.localizedDescription)")
                // Continue with full discovery - not fatal
              }
            } else {
              log.info("[QUICK-DISCOVERY-SWITCH] No switch needed (already at newest project)")

              // PHASE 2: Even if no switch, still ingest newest transcript for fast timeline
              do {
                let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
                let projectId = try orchestrator.getOrCreateProject(name: nil, rootPath: newest.projectPath.path)

                await Self.ingestNewestTranscript(
                  projectId: projectId,
                  projectPath: newest.projectPath,
                  transcriptFile: newest.transcriptFile,
                  orchestrator: orchestrator
                )
              } catch {
                log.error("[QUICK-DISCOVERY-INGEST] ❌ Failed to ingest newest transcript: \(error.localizedDescription)")
              }
            }
          } else {
            log.info("[QUICK-DISCOVERY] No projects found or scan timed out (took \(Int(quickDuration * 1000))ms)")
          }
        } catch {
          let quickDuration = Date().timeIntervalSince(quickStart)
          log.error("[QUICK-DISCOVERY] Error: \(error.localizedDescription) (took \(Int(quickDuration * 1000))ms)")
          // Continue with full discovery - not fatal
        }
      }

      // Phase 3: Old discovery system disabled - AppStateOrchestrator handles all discovery
      // The orchestrator already ran in ContextifyApp.init() and completed lightweight scan
      log.info("✅ Phase 3: Skipping old discovery system (orchestrator already ran)")

      // LEGACY: This would run the old eager-loading discovery
      // do {
      //   try await withThrowingTaskGroup(of: Void.self) { group in
      //     group.addTask {
      //       await vm.discoverProjects()
      //     }
      //     try await group.next()
      //   }
      // }

      // Phase 3: Seed display order if needed (after orchestrator discovery)
      if shouldResetDisplayOrder {
        do {
          let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
          try orchestrator.seedDisplayOrderFromTranscriptActivityIfUnset()
        } catch {
          log.warning("Failed to seed display_order from transcript activity: \(error.localizedDescription)")
        }
      }

      await persistNewestProjectBookmarkIfAvailable(log: log)

      // C4.2: Auto-select most recent project if coordinator has no current project
      var shouldAutoSelect = false
      var discoveredProjects: [DiscoveredProject] = []
      await MainActor.run {
        discoveredProjects = vm.projects
        guard StartupCoordinator.shared.current == nil, !discoveredProjects.isEmpty else {
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
        if Sandbox.isSandboxed {
          log.info("🎯 [AUTOSELECT] Skipping auto-selection (sandbox build requires explicit user choice)")
          vm.setDiscoveryProgress(DiscoveryProgress(
            phase: .complete,
            projectsCompleted: vm.projects.count,
            projectsTotal: vm.projects.count,
            message: "Select a project to continue"
          ))
          shouldAutoSelect = false
        } else {
          shouldAutoSelect = true
        }
      }

      if shouldAutoSelect {
        do {
          let orchestrator = try TranscriptOrchestrator(dbManager: .shared)

          // Try to get project with newest transcript entry (most recent work)
          if let mostRecent = try orchestrator.getProjectWithNewestEntry() {
            log.notice("🎯 Auto-selecting project with newest entry: \(mostRecent.rootPath, privacy: .public)")
            try await StartupCoordinator.shared.switchProject(to: mostRecent.rootPath)
          } else if let first = discoveredProjects.first {
            // Fallback: select first discovered project
            log.notice("🎯 Auto-selecting first discovered project: \(first.name)")
            try await StartupCoordinator.shared.switchProject(to: first.path.path)
          }

          // Wait for timeline to start monitoring before closing modal
          log.info("⏳ Waiting for timeline to initialize...")
          try await Task.sleep(for: .milliseconds(500))

          let total = discoveredProjects.count
          // Show completion message with happy emoji
          await MainActor.run {
            vm.setDiscoveryProgress(DiscoveryProgress(
              phase: .complete,
              projectsCompleted: total,
              projectsTotal: total,
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

  /// Ingests the newest transcript found by quick-discovery to enable fast timeline population
  @MainActor
  private static func ingestNewestTranscript(
    projectId: String,
    projectPath: URL,
    transcriptFile: URL,
    orchestrator: TranscriptOrchestrator
  ) async {
    let log = Logger(subsystem: "dev.contextify", category: "Projects")
    let startTime = Date()

    do {
      // Determine provider from file path
      let provider: DiscoveredProject.Provider
      if transcriptFile.path.contains("/.claude/projects/") {
        provider = .claudeCode
      } else if transcriptFile.path.contains("/.codex/sessions/") {
        provider = .codexCLI
      } else {
        log.warning("[QUICK-DISCOVERY-INGEST] Unknown provider for transcript: \(transcriptFile.path, privacy: .public)")
        return
      }

      // Extract session ID from filename
      let sessionId = transcriptFile.deletingPathExtension().lastPathComponent

      log.info("[QUICK-DISCOVERY-INGEST] Creating transcript record: \(sessionId, privacy: .public)")

      // Create discovered transcript
      let discovered = DiscoveredTranscript(
        fileURL: transcriptFile,
        provider: provider,
        sessionId: sessionId
      )

      // Upsert transcript record
      let resolved = try orchestrator.upsertTranscripts(
        projectId: projectId,
        discovered: [discovered]
      )

      guard let transcriptId = resolved.first?.transcriptId else {
        log.error("[QUICK-DISCOVERY-INGEST] Failed to get transcript ID after upsert")
        return
      }

      log.info("[QUICK-DISCOVERY-INGEST] Transcript record created: \(transcriptId, privacy: .public)")

      // Trigger preview ingestion (first 25 entries)
      try await orchestrator.ingestTranscript(
        transcriptId: transcriptId,
        mode: .preview(entries: 25),
        notifyUI: true
      )

      let duration = Date().timeIntervalSince(startTime)
      log.info("[QUICK-DISCOVERY-INGEST] ✅ Preview ingestion complete in \(Int(duration * 1000))ms")

    } catch {
      let duration = Date().timeIntervalSince(startTime)
      log.error("[QUICK-DISCOVERY-INGEST] ❌ Failed after \(Int(duration * 1000))ms: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func persistNewestProjectBookmarkIfAvailable(log: Logger) async {
    do {
      let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
      guard let mostRecent = try orchestrator.getProjectWithNewestEntry() else {
        log.debug("[PERSIST-ROOT] No ingested projects yet; skipping persisted root update")
        return
      }

      let rootPath = mostRecent.rootPath
      if SandboxPathFilter.isSandboxContainerPath(rootPath) {
        log.debug("[PERSIST-ROOT] Skipping sandbox container path: \(rootPath, privacy: .public)")
        return
      }

      HUDPreferences.setPersistedRoot(rootPath)
      log.notice("[PERSIST-ROOT] 💾 Updated persisted root to newest project: \(rootPath, privacy: .public)")
    } catch {
      log.warning("[PERSIST-ROOT] Failed to update persisted root: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func startProjectDirectoryMonitoring(viewModel: ProjectsViewModel) async {
    let log = Logger(subsystem: "dev.contextify", category: "Projects")


    if Sandbox.isSandboxed {
      log.info("[INIT] Skipping FSEvents project directory monitoring in App Store build")
      return
    }

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
