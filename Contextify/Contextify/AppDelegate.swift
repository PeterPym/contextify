import AppKit
import ContextifyCore
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let log = Logger(subsystem: "dev.contextify", category: "AppDelegate")

  /// Track if this is the first activation (avoid refresh on initial launch)
  private var hasLaunchedOnce = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Suppress window restoration when utility mode is active.
    // This prevents restored windows from flashing on screen during background startup.
    if HUDPreferences.isBackgroundUtilityModeEnabled() {
      UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
      log.info("[LIFECYCLE] NSQuitAlwaysKeepsWindows set to false (utility mode active)")
    }

    AppPresentationController.shared.refreshActivationPolicy()

    // Log build stamp for debugging (critical for VM testing)
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    log.info("[BUILD] Contextify v\(version, privacy: .public) (\(build, privacy: .public))")

    // Log LLM availability status at startup
    LLMAvailability.logStatus()

    // XPC bookmark PoC - opt-in via launch argument (debug only)
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--xpc-bookmark-poc") {
      XPCBookmarkPoC.run()
    }
    #endif

    // In lite mode, skip LLM health check - the app works without Apple Intelligence
    guard !isLiteModeActive() else {
      log.info("Lite mode active - skipping LLM health check")
      return
    }

    // Perform comprehensive LLM health check (only when Apple Intelligence is available)
    Task {
      await performLLMHealthCheck()
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // With SQL backend, cache is automatically persisted - no flush needed
    return .terminateNow
  }

  func applicationWillTerminate(_ notification: Notification) {
    Task { @MainActor in
      // Cancel FSEvents monitoring task
      AppLifecycleState.shared.projectMonitoringTask?.cancel()
    }
  }

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
  func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

  func applicationDidBecomeActive(_ notification: Notification) {
    // Skip refresh on initial launch (startup() handles that)
    guard hasLaunchedOnce else {
      hasLaunchedOnce = true
      return
    }

    // Refresh onboarding state to detect stale bookmarks (folder deleted while in background)
    Task { @MainActor in
      AppStoreOnboardingCoordinator.shared.refreshState()
    }

    // In App Store (sandbox) builds, FSEvents monitoring is disabled.
    // Refresh projects when app returns to foreground to detect new projects
    // created by Claude Code/Codex while we were in background.
    // NOTE: Only refresh after onboarding is complete - the access provider
    // isn't configured during onboarding, so discovery would fail.
    #if APPSTORE_BUILD
    if HUDPreferences.hasCompletedAppStoreOnboarding() {
      log.info("[APP-ACTIVE] App became active - refreshing projects (sandbox mode)")
      Task { @MainActor in
        await AppStateOrchestrator.shared.refreshProjects()
      }
    } else {
      log.info("[APP-ACTIVE] App became active - skipping refresh (onboarding not complete)")
    }
    #endif
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // When utility mode or menu bar extra is active, keep the app running
    // after all windows are closed. Otherwise, allow normal termination.
    let utilityMode = HUDPreferences.isBackgroundUtilityModeEnabled()
    let menuBarExtra = HUDPreferences.isMenuBarExtraEnabled()
    let shouldKeepRunning = utilityMode || menuBarExtra
    if shouldKeepRunning {
      log.debug("[LIFECYCLE] Last window closed - keeping alive (utility=\(utilityMode), menuBar=\(menuBarExtra))")
    }
    return !shouldKeepRunning
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // When the user clicks the Dock icon (or re-opens via Finder), show the main
    // window and temporarily switch to .regular activation policy so the app
    // appears in Dock and Command-Tab while the window is visible.
    log.info("[LIFECYCLE] applicationShouldHandleReopen (hasVisibleWindows=\(flag))")
    AppPresentationController.shared.showMainWindow()
    return false
  }

  // MARK: - Window Restoration Suppression

  func application(_ application: NSApplication, willEncodeRestorableState coder: NSCoder) {
    // Intentionally empty: prevent window restoration state from being saved
    // when utility mode is enabled. This avoids restored windows breaking
    // the hidden/background startup experience.
    if HUDPreferences.isBackgroundUtilityModeEnabled() {
      log.debug("[LIFECYCLE] Suppressing restorable state encoding (utility mode)")
    }
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    // Return true for modern secure coding compliance, but willEncodeRestorableState
    // is empty so nothing is actually persisted when utility mode is active.
    return true
  }


  private func performLLMHealthCheck() async {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      let status = await LLMHealthCheck.shared.checkHealth()

      switch status {
      case .healthy:
        log.info("LLM health check: PASSED")

      case .unavailable(let reason):
        log.error("LLM health check: FAILED - \(reason.userFacingMessage)")

        // TEMPORARY: Using toast notification for LLM health errors on launch.
        // TODO: Replace with persistent status bar indicator (see TODOS.md lines 404-603)
        // that shows:
        //   - Green dot: LLM available
        //   - Red dot: LLM unavailable (with popover showing error details)
        //   - Gray dot: LLM not ready
        // The status bar approach is better UX because:
        //   1. Always visible (not dismissible)
        //   2. Shows real-time status updates
        //   3. Click for details instead of blocking screen space
        //   4. Integrates with periodic health checks
        // For now, toast provides immediate visibility of critical LLM failures.
        //
        // NOTE: The metadata.json bug occurs in macOS 26.0.1 production builds,
        // not just betas. This health check is critical for real users.
        await MainActor.run {
          NotificationCenter.default.post(
            name: .contextifyShowToast,
            object: nil,
            userInfo: [
              ToastPayloadKey.message: reason.userFacingMessage,
              ToastPayloadKey.duration: 30.0  // 30 seconds (15x default) for critical errors
            ]
          )
        }
      }
    }
    #endif
  }
}
