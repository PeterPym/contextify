import AppKit
import ContextifyCore
import OSLog

@MainActor
final class AppPresentationController {
  static let shared = AppPresentationController()

  private let log = Logger(subsystem: "dev.contextify", category: "AppPresentation")
  private var hasHandledInitialMainWindow = false
  private var windowCloseObserver: NSObjectProtocol?

  private init() {}

  var isMainWindowVisible: Bool {
    MainWindowTracker.shared.window?.isVisible == true
  }

  /// Whether utility mode (background/accessory) is currently enabled.
  private var isUtilityMode: Bool {
    HUDPreferences.isBackgroundUtilityModeEnabled()
  }

  private var shouldStartWithoutMainWindow: Bool {
    AppPresentationPreferences.shouldStartWithoutMainWindow(
      quietLaunch: LaunchArguments.shared.quiet,
      backgroundUtilityModeEnabled: isUtilityMode
    )
  }

  /// Desired activation policy based on current state.
  /// - .regular when utility mode is OFF (normal app behavior)
  /// - .accessory when utility mode is ON and no "regular" windows are showing
  /// - .regular when utility mode is ON but a window is visible (temporary promotion)
  private var desiredActivationPolicy: NSApplication.ActivationPolicy {
    guard isUtilityMode else { return .regular }
    return hasAnyVisibleRegularWindow ? .regular : .accessory
  }

  /// Check whether any "regular" window (main, settings, projects, transcripts) is visible.
  /// Excludes the menu bar extra popover and other transient panels.
  private var hasAnyVisibleRegularWindow: Bool {
    guard let windows = NSApp?.windows else { return false }
    return windows.contains { window in
      window.isVisible
        && !window.isKind(of: NSPanel.self)
        && window.level == .normal
        && window.styleMask.contains(.titled)
    }
  }

  func refreshActivationPolicy() {
    applyActivationPolicy()
  }

  func registerMainWindow(_ window: NSWindow) {
    MainWindowTracker.shared.window = window

    guard !hasHandledInitialMainWindow else { return }
    hasHandledInitialMainWindow = true

    // Start observing window close events for activation policy management
    startObservingWindowLifecycle()

    guard shouldStartWithoutMainWindow else { return }

    DispatchQueue.main.async {
      window.orderOut(nil)
    }
  }

  /// Temporarily promote activation policy to .regular when opening a window
  /// from the menu bar (Projects, Transcripts, Settings). This ensures the app
  /// appears in Dock and Command-Tab while a window is visible.
  /// For the main window, use showMainWindow() instead (which calls this internally).
  func promoteForWindowPresentation() {
    guard isUtilityMode else { return }
    guard let app = NSApp, app.activationPolicy() != .regular else { return }
    log.info("[POLICY] Promoting to .regular for auxiliary window presentation")
    app.setActivationPolicy(.regular)
  }

  func showMainWindow(openWindow: (() -> Void)? = nil) {
    // When in utility mode, temporarily promote to .regular so the app
    // gets Dock icon and Command-Tab presence while a window is open.
    if isUtilityMode {
      log.info("[POLICY] Promoting to .regular for window presentation")
      NSApp?.setActivationPolicy(.regular)
    }

    if let window = MainWindowTracker.shared.window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    openWindow?()

    DispatchQueue.main.async {
      if let window = MainWindowTracker.shared.window {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
      }
    }
  }

  func hideMainWindow() {
    MainWindowTracker.shared.window?.orderOut(nil)
    // After hiding, re-evaluate activation policy (may return to .accessory)
    applyActivationPolicyAfterWindowChange()
  }

  func toggleMainWindow(openWindow: (() -> Void)? = nil) {
    if isMainWindowVisible {
      hideMainWindow()
    } else {
      showMainWindow(openWindow: openWindow)
    }
  }

  // MARK: - Window Lifecycle Observation

  /// Observe window close/miniaturize notifications to return to .accessory
  /// policy when all regular windows are closed in utility mode.
  private func startObservingWindowLifecycle() {
    guard windowCloseObserver == nil else { return }

    windowCloseObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self else { return }
      guard notification.object is NSWindow else { return }
      // Defer policy check to let the window fully close first.
      // Already on main queue (observer queue: .main), so just async to next run loop.
      DispatchQueue.main.async {
        self.applyActivationPolicyAfterWindowChange()
      }
    }
  }

  // MARK: - Activation Policy

  /// Re-evaluate and apply activation policy after a window visibility change.
  /// This is the path used when windows open or close at runtime.
  private func applyActivationPolicyAfterWindowChange() {
    guard isUtilityMode else { return }
    let desired = desiredActivationPolicy
    guard let app = NSApp, app.activationPolicy() != desired else { return }
    log.info("[POLICY] Window change -> switching to \(desired == .regular ? ".regular" : ".accessory", privacy: .public)")
    app.setActivationPolicy(desired)

    // When returning to .accessory, deactivate so the Dock icon disappears promptly
    if desired == .accessory {
      app.deactivate()
    }
  }

  /// Apply the initial activation policy (called once at launch and from Settings).
  private func applyActivationPolicy() {
    guard let app = NSApp else {
      DispatchQueue.main.async { [weak self] in
        self?.applyActivationPolicy()
      }
      return
    }

    let desired = desiredActivationPolicy
    guard app.activationPolicy() != desired else { return }
    log.info("[POLICY] Setting activation policy to \(desired == .regular ? ".regular" : ".accessory", privacy: .public)")
    app.setActivationPolicy(desired)
  }
}
