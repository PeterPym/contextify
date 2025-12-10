import SwiftUI
import AppKit
import Combine
import ContextifyCore
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif
#if SPARKLE
import Sparkle
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
  private static let gitHubIssuesURL = "https://github.com/PeterPym/contextify/issues"

  var body: some Commands {
    CommandGroup(replacing: .help) {
      Button("Contextify Help") {
        if let url = URL(string: "https://contextify.sh/help/?ref=app-help-menu") {
          NSWorkspace.shared.open(url)
        }
      }
      .keyboardShortcut("?", modifiers: [.command])

      Divider()

      Button("Report a Bug...") {
        if let url = URL(string: "\(Self.gitHubIssuesURL)/new?template=bug_report.md") {
          NSWorkspace.shared.open(url)
        }
      }

      Button("Request a Feature...") {
        if let url = URL(string: "\(Self.gitHubIssuesURL)/new?template=feature_request.md") {
          NSWorkspace.shared.open(url)
        }
      }

      Divider()

      Button("Contact Support...") {
        SystemInfo.openSupportEmail()
      }
    }
  }
}

// Shared container for background tasks that need lifecycle management.
// This singleton exists for the app's lifetime, ensuring notification observers
// are always active regardless of which windows are open.
@MainActor
final class AppLifecycleState {
  static let shared = AppLifecycleState()
  var projectMonitoringTask: Task<Void, Never>?
  private var permissionObserver: AnyCancellable?
  private let permLog = Logger(subsystem: "dev.contextify", category: "Permissions")

  private init() {}

  /// Set up permission change observer for post-onboarding permission grants.
  ///
  /// Called once after `ProjectsViewModel` is initialized via `initializeProjectsSystem()`.
  /// This ensures the observer exists for the app's lifetime, not tied to any window.
  ///
  /// **Important:** The observer explicitly skips handling during onboarding wizard flow
  /// (when `hasCompletedAppStoreOnboarding()` is false). This is correct because:
  /// 1. During onboarding, `SourceAuthorizationRow` posts the same notification
  /// 2. But the wizard's `onComplete` Task owns the full startup sequence
  /// 3. That Task calls `buildAndConfigureAccessProvider()` → `startup()` → `initializeProjectsSystem()`
  /// 4. So the observer would cause duplicate/racing reconfiguration if it also ran
  ///
  /// After onboarding completes, this observer handles Settings > Permissions grants.
  /// - Important: `projectsVM` is captured by the observer closure. This assumes
  ///   `ProjectsViewModel` is created once per app lifetime and never replaced.
  ///   If that invariant changes, switch to fetching the current VM via a closure.
  func setupPermissionObserver(
    folderAccessController: FolderAccessController,
    projectsVM: ProjectsViewModel?
  ) {
    #if APPSTORE_BUILD
    assert(projectsVM != nil, "setupPermissionObserver must be called after ProjectsViewModel is created")

    guard permissionObserver == nil else {
      permLog.debug("[PERMISSIONS] Observer already set up, skipping")
      return
    }

    permissionObserver = NotificationCenter.default
      .publisher(for: .permissionAuthorizationDidChange)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] notification in
        guard let self = self else { return }
        let source = notification.object as? SourceID
        self.permLog.info("[PERMISSIONS] 📬 Received permissionAuthorizationDidChange for \(source?.rawValue ?? "unknown", privacy: .public)")

        // Skip if onboarding hasn't completed yet - the onboarding flow handles its own startup.
        // This observer is for Settings > Permissions grants after initial setup.
        guard HUDPreferences.hasCompletedAppStoreOnboarding() else {
          self.permLog.info("[PERMISSIONS] ⏭️ Skipping reconfiguration - onboarding not complete (onboarding handles its own startup)")
          return
        }

        Task { @MainActor in
          self.permLog.info("[PERMISSIONS] 🔄 Reconfiguring access provider after Settings permission grant...")
          await ContextifyApp.reconfigureAccessProvider(
            folderAccessController: folderAccessController,
            projectsVM: projectsVM
          )

          self.permLog.info("[PERMISSIONS] 🔍 Triggering discovery refresh to pick up new permissions...")
          await AppStateOrchestrator.shared.startup()

          self.permLog.info("[PERMISSIONS] ✅ Permission reconfiguration complete")
        }
      }

    permLog.info("[PERMISSIONS] 🔔 Permission observer set up in AppLifecycleState")
    #else
    permLog.debug("[PERMISSIONS] DMG build - permission observer not needed (direct filesystem access)")
    #endif
  }
}

@main
struct ContextifyApp: App {
  // MARK: - Sandbox Startup Contract
  //
  // The startup sequence differs between DMG and App Store builds to ensure the
  // TranscriptAccessProvider is configured BEFORE discovery runs in sandbox builds.
  //
  // **DMG builds:**
  //   init() -> startup() -> [window .task] -> initializeProjectsSystem()
  //   (PassthroughAccessProvider doesn't need configuration; order doesn't matter)
  //
  // **App Store builds (first launch):**
  //   init() -> [exits early] -> [onboarding wizard] ->
  //   buildAndConfigureAccessProvider() -> completeOnboardingInitialization() ->
  //   startup() -> initializeProjectsSystem(existingProvider:)
  //
  // **App Store builds (subsequent launches):**
  //   init() -> [logs and returns] -> [window .task] -> initializeProjectsSystem() ->
  //   buildAndConfigureAccessProvider() -> startup() -> StartupCoordinator.start()
  //
  // Key invariants:
  // 1. In App Store builds, startup() must NEVER be called from init(); it is only
  //    invoked from post-onboarding flows and initializeProjectsSystem().
  // 2. buildAndConfigureAccessProvider() MUST be called before startup() in sandbox builds.
  // 3. buildAndConfigureAccessProvider() is startup-only; use reconfigureAccessProvider() mid-session.
  // 4. reconfigureAccessProvider() does NOT update sharedAccessProvider (different code path).
  // 5. After onboarding, the onComplete Task owns the startup sequence (isHandlingCompletion flag
  //    prevents the window's .task from racing).

  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let model = HUDViewModel.shared
  private let timeline = ConversationMonitor.shared
  @StateObject private var folderAccessController = FolderAccessController()  // App Store authorization
  @ObservedObject private var onboardingCoordinator = AppStoreOnboardingCoordinator.shared  // Singleton, use @ObservedObject not @StateObject
  @State private var projectsViewModel: ProjectsViewModel?
  @State private var backgroundRefreshTimer: Timer?
  @State private var projectDirectoryMonitor: FSEventsMonitor?
  @State private var showWelcomeModal = false  // C3.2: Welcome modal state

  /// Startup-only cache for the access provider. Ensures single construction per process.
  /// NOTE: Mid-session reconfigureAccessProvider() does NOT update this cache.
  /// Do not call buildAndConfigureAccessProvider() after reconfigure.
  @State private var sharedAccessProvider: TranscriptAccessProvider?

  /// DEBUG flag: tracks whether reconfigureAccessProvider() has been called this process.
  /// Used to detect misuse of buildAndConfigureAccessProvider() after mid-session reconfigure.
  #if DEBUG
  private static var hasReconfiguredAccessProvider = false
  #endif

  #if SPARKLE
  /// Sparkle updater controller for DMG distribution auto-updates.
  /// Initialized with `startingUpdater: true` to enable automatic background checks.
  private let updaterController: SPUStandardUpdaterController
  #endif

  init() {
    #if SPARKLE
    // Initialize Sparkle updater for DMG builds
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    #endif

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
    //
    // For App Store builds: startup() is called from initializeProjectsSystem() AFTER
    // the access provider is properly configured. This ensures discovery works correctly.
    // For DMG builds: startup() is called here since no access provider configuration needed.
    #if APPSTORE_BUILD
    // App Store builds: defer startup to initializeProjectsSystem()
    // This ensures the access provider is configured BEFORE discovery runs.
    Task { @MainActor in
      if !HUDPreferences.hasCompletedAppStoreOnboarding() {
        startupLog.notice("[STARTUP-GATE] App Store build without onboarding - deferring startup to post-onboarding")
      } else {
        startupLog.notice("[STARTUP-GATE] App Store subsequent launch - deferring startup to initializeProjectsSystem()")
      }
    }
    #else
    // DMG builds: run startup immediately
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
      startupLog.info("✅ Legacy coordinator started (StartupCoordinator) - ProjectSwitcherState starts during project initialization")
    }
    #endif

  }

  var body: some Scene {
    Window("Contextify", id: "main") {
      Group {
        // App Store builds: show onboarding wizard if not complete
        // Note: shouldShowWizard returns false for DMG builds (isComplete always true)
        if onboardingCoordinator.shouldShowWizard {
          AppStoreOnboardingView(
            folderAccessController: folderAccessController,
            onComplete: {
              // Mark onboarding complete and trigger app startup
              onboardingCoordinator.markComplete()

              // Now run the deferred startup sequence
              // This Task owns the full pipeline; .task is blocked by isHandlingCompletion
              Task { @MainActor in
                // Give SwiftUI time to process the state change and dismiss wizard.
                // Task.yield() alone isn't enough - we need to let the render cycle complete.
                // 50ms is enough for one frame at 60fps plus some buffer.
                try? await Task.sleep(for: .milliseconds(50))

                let startupLog = Logger(subsystem: "dev.contextify", category: "Startup")
                startupLog.info("[POST-ONBOARD] Running deferred startup sequence")

                // CRITICAL: Configure access provider BEFORE startup
                let provider = await buildAndConfigureAccessProvider()

                // Initialize DB components (moved from markComplete() to avoid blocking UI)
                AppStateOrchestrator.shared.completeOnboardingInitialization()

                await AppStateOrchestrator.shared.startup()
                await StartupCoordinator.shared.start()

                // Pass the already-built provider to avoid reconstruction
                await initializeProjectsSystem(existingProvider: provider)

                // Signal completion - allows .task to run on subsequent view updates
                onboardingCoordinator.finishHandlingCompletion()
              }
            }
          )
        } else if let vm = projectsViewModel {
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
              // WelcomeModalView handles its own interactiveDismissDisabled internally
              // Don't add it here - it blocks Cmd+Q from working
              WelcomeModalView(folderAccessController: folderAccessController)
                .environment(vm)
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
        // Skip if:
        // - Onboarding wizard is still visible (handled by wizard completion)
        // - Onboarding just completed (onComplete Task owns the startup sequence)
        guard !onboardingCoordinator.shouldShowWizard,
              !onboardingCoordinator.isHandlingCompletion else { return }
        await initializeProjectsSystem()
      }
      .onReceive(NotificationCenter.default.publisher(for: .startupRequiresWelcomeModal)) { _ in
        let startupLog = Logger(subsystem: "dev.contextify", category: "Projects")
        startupLog.info("[WELCOME-TRIGGERED] Welcome modal notification received")

        // App Store builds use the onboarding wizard for first-run UX.
        // The welcome modal is only for DMG builds which don't have the wizard.
        #if APPSTORE_BUILD
        startupLog.info("[WELCOME-SKIP] App Store build - onboarding wizard handles first-run, skipping welcome modal")
        return
        #else
        // Guard: Don't show welcome modal if projects already exist (race condition protection)
        let tabProjectCount = ProjectSwitcherState.shared.tabProjects.count
        let vmProjectCount = projectsViewModel?.projects.count ?? 0
        if tabProjectCount > 0 || vmProjectCount > 0 {
          startupLog.info("[WELCOME-SKIP] Skipping welcome modal - projects already exist (tabs=\(tabProjectCount), vm=\(vmProjectCount))")
          return
        }

        startupLog.info("[WELCOME-STATE] Setting showWelcomeModal = true")
        showWelcomeModal = true
        #endif
      }
      // NOTE: Permission notification observer is in AppLifecycleState (not tied to window).
      // NOTE: Database reset in App Store builds requires restart.
    }
    // Width minimum: 340 (ContentView.timelineMin) + 16 (padding) + ~9 (chrome) = ~365pt
    // Height minimum: 360 (ContentView.minHeight) + ~25 (titlebar)
    // Actual window dimensions: max(width, ~365pt), height + ~25pt (titlebar)
    // These are in points. On Retina (2x), multiply by 2 for pixel dimensions in screenshots.
    .defaultSize(width: 480, height: 515)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(replacing: .newItem) { }
      #if SPARKLE
      CommandGroup(after: .appInfo) {
        CheckForUpdatesView(updater: updaterController.updater)
      }
      #endif
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
      SettingsView(folderAccessController: folderAccessController)
    }

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

  // MARK: - Access Provider Management

  /// Builds and configures the TranscriptAccessProvider for the current build type.
  /// MUST be called before AppStateOrchestrator.startup() in all sandbox paths.
  /// Returns the cached provider if already built (idempotent).
  ///
  /// Startup-only; not used after mid-session reconfigureAccessProvider().
  @MainActor
  private func buildAndConfigureAccessProvider() async -> TranscriptAccessProvider {
    // Guard against misuse: this function should never be called after reconfigureAccessProvider()
    #if DEBUG
    assert(
      !Self.hasReconfiguredAccessProvider || sharedAccessProvider == nil,
      "buildAndConfigureAccessProvider() called after reconfigureAccessProvider(). " +
      "This would return a stale cached provider. Use reconfigureAccessProvider() for mid-session changes."
    )
    #endif

    // Return cached provider if already built
    if let existing = sharedAccessProvider {
      return existing
    }

    let log = Logger(subsystem: "dev.contextify", category: "AccessProvider")

    #if APPSTORE_BUILD
    let claudeAuth = await folderAccessController.authorization(for: .claude)
    let codexAuth  = await folderAccessController.authorization(for: .codex)

    var claudeURL: URL? = nil
    if let auth = claudeAuth, auth.status == .authorized {
      claudeURL = try? await folderAccessController.resolve(auth).url
      log.info("[ACCESS-PROVIDER] Claude authorized: \(claudeURL?.path ?? "nil", privacy: .public)")
    } else {
      log.info("[ACCESS-PROVIDER] Claude not authorized")
    }

    var codexURL: URL? = nil
    if let auth = codexAuth, auth.status == .authorized {
      codexURL = try? await folderAccessController.resolve(auth).url
      log.info("[ACCESS-PROVIDER] Codex authorized: \(codexURL?.path ?? "nil", privacy: .public)")
    } else {
      log.info("[ACCESS-PROVIDER] Codex not authorized")
    }

    let provider = SandboxTranscriptAccessProvider(
      claudeRoot: claudeURL,
      codexRoot: codexURL
    )
    log.info("[ACCESS-PROVIDER] Created SandboxTranscriptAccessProvider")

    #else
    let provider = PassthroughAccessProvider()
    log.info("[ACCESS-PROVIDER] Created PassthroughAccessProvider (DMG build)")
    #endif

    await AppStateOrchestrator.shared.configureAccessProvider(provider)
    sharedAccessProvider = provider
    return provider
  }

  /// Reconfigures the access provider after permissions are granted mid-session.
  /// This rebuilds the SandboxTranscriptAccessProvider with newly granted URLs
  /// and reconfigures AppStateOrchestrator so discovery can succeed.
  ///
  /// NOTE: Does not update ContextifyApp.sharedAccessProvider. Do not call
  /// buildAndConfigureAccessProvider() after reconfigure in the same process.
  @MainActor
  static func reconfigureAccessProvider(
    folderAccessController: FolderAccessController,
    projectsVM: ProjectsViewModel?
  ) async {
    #if APPSTORE_BUILD
    // Mark that reconfigure has been called - buildAndConfigureAccessProvider() should not be used after this
    #if DEBUG
    hasReconfiguredAccessProvider = true
    #endif

    let log = Logger(subsystem: "dev.contextify", category: "Projects")
    log.info("[RECONFIG-ACCESS] ▶ ENTRY - Rebuilding access provider with newly granted permissions")

    // Read fresh authorizations from FolderAccessController
    let claudeAuth = await folderAccessController.authorization(for: .claude)
    let codexAuth = await folderAccessController.authorization(for: .codex)

    log.info("[RECONFIG-ACCESS] Claude auth status: \(claudeAuth?.status.rawValue ?? "nil", privacy: .public)")
    log.info("[RECONFIG-ACCESS] Codex auth status: \(codexAuth?.status.rawValue ?? "nil", privacy: .public)")

    var claudeURL: URL? = nil
    if let auth = claudeAuth, auth.status == .authorized {
      do {
        claudeURL = try await folderAccessController.resolve(auth).url
        log.info("[RECONFIG-ACCESS] Claude URL resolved: \(claudeURL?.path ?? "nil", privacy: .public)")
      } catch {
        log.error("[RECONFIG-ACCESS] ❌ Claude bookmark resolution FAILED: \(error.localizedDescription, privacy: .public)")
      }
    } else {
      log.info("[RECONFIG-ACCESS] Claude not authorized (auth=\(claudeAuth != nil), status=\(claudeAuth?.status.rawValue ?? "nil"))")
    }

    var codexURL: URL? = nil
    if let auth = codexAuth, auth.status == .authorized {
      do {
        codexURL = try await folderAccessController.resolve(auth).url
        log.info("[RECONFIG-ACCESS] Codex URL resolved: \(codexURL?.path ?? "nil", privacy: .public)")
      } catch {
        log.error("[RECONFIG-ACCESS] ❌ Codex bookmark resolution FAILED: \(error.localizedDescription, privacy: .public)")
      }
    } else {
      log.info("[RECONFIG-ACCESS] Codex not authorized (auth=\(codexAuth != nil), status=\(codexAuth?.status.rawValue ?? "nil"))")
    }

    log.info("[RECONFIG-ACCESS] Summary - Claude: \(claudeURL != nil ? "✓" : "✗"), Codex: \(codexURL != nil ? "✓" : "✗")")

    // Create new provider with fresh URLs (start security scope in init)
    let newProvider = SandboxTranscriptAccessProvider(
      claudeRoot: claudeURL,
      codexRoot: codexURL
    )

    // Reconfigure orchestrators with new provider
    do {
      let sharedOrchestrator = try TranscriptOrchestrator(
        dbManager: .shared,
        accessProvider: newProvider
      )

      await AppStateOrchestrator.shared.configureAccessProvider(newProvider)
      ConversationMonitor.shared.configureSharedOrchestrator(sharedOrchestrator)
      ProjectSwitcherState.shared.configureSharedOrchestrator(sharedOrchestrator)
      projectsVM?.applyAccessProvider(newProvider, folderAccessController: folderAccessController)
      log.info("[RECONFIG-ACCESS] ✅ Shared orchestrators reconfigured with new access provider")
    } catch {
      log.error("[RECONFIG-ACCESS-ERROR] Failed to build shared orchestrator: \(error.localizedDescription, privacy: .public)")
    }
    #endif
  }

  @MainActor
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

        do {
          // Skip quick-discovery if we don't have access to this provider (sandbox builds)
          if let provider = TranscriptProviderID.fromTranscriptURL(newest.transcriptFile),
             let sandbox = projectsVM.accessProvider as? SandboxTranscriptAccessProvider {
            if provider == TranscriptProviderID.claude && sandbox.claudeRoot == nil {
              log.warning("[QUICK-DISCOVERY] Skipping preview ingest (no Claude authorization)")
              return
            }
            if provider == TranscriptProviderID.codex && sandbox.codexRoot == nil {
              log.warning("[QUICK-DISCOVERY] Skipping preview ingest (no Codex authorization)")
              return
            }
          }
          // Refresh authorization snapshot in case permissions just changed
          await projectsVM.refreshAuthorizationStateIfNeeded()

          let orchestrator = projectsVM.orchestrator
          let projectId = try await activateProjectForQuickDiscovery(
            path: newest.projectPath,
            orchestrator: orchestrator,
            logger: log
          )

          await ingestNewestTranscript(
            projectId: projectId,
            projectPath: newest.projectPath,
            transcriptFile: newest.transcriptFile,
            orchestrator: orchestrator,
            accessProvider: projectsVM.accessProvider
          )
        } catch {
          log.error("[QUICK-DISCOVERY-SWITCH] ❌ Failed to activate or ingest newest transcript: \(error.localizedDescription)")
        }
      } else {
        log.info("[QUICK-DISCOVERY] No projects found or scan timed out (took \(Int(quickDuration * 1000))ms)")
      }
    } catch {
      let quickDuration = Date().timeIntervalSince(quickStart)
      log.error("[QUICK-DISCOVERY] Error: \(error.localizedDescription) (took \(Int(quickDuration * 1000))ms)")
    }
  }

  /// Ensures quick discovery activates the desired project before ingesting.
  @MainActor
  private static func activateProjectForQuickDiscovery(
    path: URL,
    orchestrator: TranscriptOrchestrator,
    logger: Logger
  ) async throws -> String {
    let projectId = try orchestrator.getOrCreateProject(name: nil, rootPath: path.path).projectId
    let currentPath = StartupCoordinator.shared.current?.path
    let needsSwitch = currentPath == nil || currentPath != path.path

    ProjectSwitcherState.shared.start()

    if needsSwitch {
      logger.notice("[QUICK-DISCOVERY-SWITCH] Activating project for path: \(path.path, privacy: .public)")
      await ProjectSwitcherState.shared.switchToProject(projectId)
      logger.info("[QUICK-DISCOVERY-SWITCH] Project activated: \(projectId, privacy: .public)")
    } else {
      logger.info("[QUICK-DISCOVERY-SWITCH] Project already active for path: \(path.path, privacy: .public)")
    }

    return projectId
  }

  @MainActor
  private func initializeProjectsSystem(existingProvider: TranscriptAccessProvider? = nil) async {
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

        // Reuse existing provider, or cached provider, or build new one
        let accessProvider: TranscriptAccessProvider
        if let existing = existingProvider {
          accessProvider = existing
          log.info("[INIT] Reusing existing access provider")
        } else if let cached = sharedAccessProvider {
          accessProvider = cached
          log.info("[INIT] Reusing cached access provider")
        } else {
          accessProvider = await buildAndConfigureAccessProvider()
          log.info("[INIT] Built new access provider")

          // App Store subsequent launches: run startup() now that provider is configured
          // (startup was deferred from init to here to ensure provider is ready)
          #if APPSTORE_BUILD
          if HUDPreferences.hasCompletedAppStoreOnboarding() {
            log.info("[INIT] Running deferred startup sequence (App Store subsequent launch)")
            await AppStateOrchestrator.shared.startup()
            await StartupCoordinator.shared.start()
          }
          #endif
        }

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
          hudModel: HUDViewModel.shared,
          folderAccessController: controller,
          accessProvider: accessProvider
        )
        self.projectsViewModel = vm
        timeline.configureSharedOrchestrator(orchestrator)
        ProjectSwitcherState.shared.configureSharedOrchestrator(orchestrator)
        ProjectSwitcherState.shared.start()

        // Set up permission observer now that we have a valid projectsViewModel.
        // The guard in setupPermissionObserver ensures this only runs once.
        AppLifecycleState.shared.setupPermissionObserver(
          folderAccessController: folderAccessController,
          projectsVM: vm
        )
      }

      guard let vm = projectsViewModel else {
        log.error("ProjectsViewModel not available")
        return
      }
      let orchestrator = vm.orchestrator

      // Welcome modal decision:
      // - DMG builds: No modal. Discovery runs in background, app shows content as it arrives.
      // - Sandbox builds: Defer to AppStateOrchestrator.startup() which checks AFTER discovery
      //   (shows modal only if no projects found after full discovery scan)

      let projectCount = (try? orchestrator.listProjects().count) ?? 0
      let isEmptyDB = projectCount == 0
      log.info("[INIT-DB-STATE] Database has \(projectCount, privacy: .public) projects, isEmpty: \(isEmptyDB, privacy: .public)")

      if Sandbox.isSandboxed {
        log.info("[WELCOME-DECISION] Sandbox build - deferring to post-discovery check in AppStateOrchestrator")
      } else {
        log.info("[WELCOME-DECISION] DMG build - no welcome modal, discovery runs in background")
      }

      // Reconcile pending assistant_usage records at startup
      do {
        try orchestrator.reconcileAssistantUsage()
      } catch {
        log.warning("Failed to reconcile assistant usage: \(error.localizedDescription)")
      }

      let shouldResetDisplayOrder = isEmptyDB

      if shouldResetDisplayOrder {
        // Reset display_order for first-launch sorting by activity
        // (On fresh database, all projects should sort by newest entry, not persisted order)
        do {
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

            do {
              let orchestrator = vm.orchestrator
              let projectId = try await Self.activateProjectForQuickDiscovery(
                path: newest.projectPath,
                orchestrator: orchestrator,
                logger: log
              )

              await Self.ingestNewestTranscript(
                projectId: projectId,
                projectPath: newest.projectPath,
                transcriptFile: newest.transcriptFile,
                orchestrator: orchestrator,
                accessProvider: vm.accessProvider
              )
            } catch {
              log.error("[QUICK-DISCOVERY-SWITCH] ❌ Failed to activate or ingest newest transcript: \(error.localizedDescription)")
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

      await persistNewestProjectBookmarkIfAvailable(log: log, orchestrator: orchestrator)

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
    orchestrator: TranscriptOrchestrator,
    accessProvider: TranscriptAccessProvider?
  ) async {
    let log = Logger(subsystem: "dev.contextify", category: "Projects")
    let startTime = Date()

    do {
      // Determine provider from file path
      let provider: DiscoveredProject.Provider
      let providerID: String
      if transcriptFile.path.contains("/.claude/projects/") {
        provider = .claudeCode
        providerID = TranscriptProviderID.claude
      } else if transcriptFile.path.contains("/.codex/sessions/") {
        provider = .codexCLI
        providerID = TranscriptProviderID.codex
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

      // Upsert transcript record (requires security scope on App Store)
      let transcriptId: String = try {
        if let accessProvider {
          return try accessProvider.withAccess(for: providerID) { _ in
            let resolved = try orchestrator.upsertTranscripts(
              projectId: projectId,
              discovered: [discovered]
            )
            guard let id = resolved.first?.transcriptId else {
              throw FolderAccessError.bookmarkResolutionFailed
            }
            return id
          }
        } else {
          let resolved = try orchestrator.upsertTranscripts(
            projectId: projectId,
            discovered: [discovered]
          )
          guard let id = resolved.first?.transcriptId else {
            throw FolderAccessError.bookmarkResolutionFailed
          }
          return id
        }
      }()

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
      log.error("[QUICK-DISCOVERY-INGEST] ❌ Failed after \(Int(duration * 1000))ms: \(String(describing: error), privacy: .public)")
    }
  }

  @MainActor
  private func persistNewestProjectBookmarkIfAvailable(
    log: Logger,
    orchestrator: TranscriptOrchestrator
  ) async {
    do {
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
