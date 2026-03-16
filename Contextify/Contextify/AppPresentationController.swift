import AppKit
import ContextifyCore
import OSLog

@MainActor
final class AppPresentationController {
  static let shared = AppPresentationController()

  private let log = Logger(subsystem: "dev.contextify", category: "AppPresentation")
  private var hasHandledInitialMainWindow = false
  private var windowCloseObserver: NSObjectProtocol?
  private var windowKeyObserver: NSObjectProtocol?

  private init() {}

  var isMainWindowVisible: Bool {
    // Check the tracked window first, fall back to scanning NSApp windows.
    // The weak reference in MainWindowTracker can go nil if SwiftUI releases
    // the window, so the fallback ensures detection still works.
    if let window = MainWindowTracker.shared.window {
      return window.isVisible
    }
    // Fallback: look for any visible, titled window from this app that matches
    // the main window characteristics. Include .floating level for Keep on Top.
    return NSApp?.windows.contains(where: {
      $0.isVisible
        && ($0.level == .normal || $0.level == .floating)
        && $0.styleMask.contains(.titled)
        && $0.title.contains("Contextify")
    }) == true
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
  /// - .accessory when utility mode is ON
  ///
  /// When utility mode is ON the policy is always .accessory so the Dock icon
  /// and Command-Tab entry disappear as soon as the toggle is flipped.
  /// promoteForWindowPresentation() handles the temporary .regular raise when
  /// a window is explicitly opened via the menu bar popover.
  private var desiredActivationPolicy: NSApplication.ActivationPolicy {
    isUtilityMode ? .accessory : .regular
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

    // Window reference is nil (released by SwiftUI scene management).
    // Use the openWindow callback to ask SwiftUI to recreate it, then
    // also try activating via NSApp as a fallback.
    openWindow?()
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.async {
      if let window = MainWindowTracker.shared.window {
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

  /// Observe window lifecycle to manage activation policy and Keep on Top
  /// level ordering.
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

    // When Settings (or any auxiliary window) becomes key, ensure its window
    // level sits above the floating main window if Keep on Top is active.
    windowKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification,
      object: nil,
      queue: .main
    ) { notification in
      guard let window = notification.object as? NSWindow else { return }
      guard isSettingsWindow(window) else { return }
      if HUDPreferences.isWindowAlwaysOnTop() {
        window.level = keepOnTopAuxiliaryLevel
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

    // Deactivate so the Dock icon disappears promptly when entering utility mode.
    if desired == .accessory {
      app.deactivate()
    }
  }
}
