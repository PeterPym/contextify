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
    guard isAppleIntelligenceAvailable() else {
      presentAvailabilityAlert()
      NSApp.terminate(nil)
      return
    }

    // Perform comprehensive LLM health check
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

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if let window = MainWindowTracker.shared.window {
      window.makeKeyAndOrderFront(nil)
    }
    return false
  }

  private func presentAvailabilityAlert() {
    let alert = NSAlert()
    alert.messageText = "Apple Intelligence Not Available"
    alert.informativeText = "Enable Apple Intelligence in System Settings and ensure on-device models are ready."
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Quit")
    alert.runModal()
  }

  private func isAppleIntelligenceAvailable() -> Bool {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      switch SystemLanguageModel.default.availability {
      case .available:
        return true
      case .unavailable:
        return false
      @unknown default:
        return false
      }
    }
    #endif
    return false
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
