import AppKit
import ContextifyCore

@MainActor
final class AppPresentationController {
  static let shared = AppPresentationController()

  private var hasHandledInitialMainWindow = false

  private init() {}

  var isMainWindowVisible: Bool {
    MainWindowTracker.shared.window?.isVisible == true
  }

  private var shouldStartWithoutMainWindow: Bool {
    AppPresentationPreferences.shouldStartWithoutMainWindow(
      quietLaunch: LaunchArguments.shared.quiet,
      backgroundUtilityModeEnabled: HUDPreferences.isBackgroundUtilityModeEnabled()
    )
  }

  func refreshActivationPolicy() {
    applyActivationPolicy()
  }

  func registerMainWindow(_ window: NSWindow) {
    MainWindowTracker.shared.window = window

    guard !hasHandledInitialMainWindow else { return }
    hasHandledInitialMainWindow = true

    guard shouldStartWithoutMainWindow else { return }

    DispatchQueue.main.async {
      window.orderOut(nil)
    }
  }

  func showMainWindow(openWindow: (() -> Void)? = nil) {
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
  }

  func toggleMainWindow(openWindow: (() -> Void)? = nil) {
    if isMainWindowVisible {
      hideMainWindow()
    } else {
      showMainWindow(openWindow: openWindow)
    }
  }

  private func applyActivationPolicy() {
    guard let app = NSApp else {
      DispatchQueue.main.async { [weak self] in
        self?.applyActivationPolicy()
      }
      return
    }

    let desiredPolicy: NSApplication.ActivationPolicy = shouldStartWithoutMainWindow ? .accessory : .regular
    guard app.activationPolicy() != desiredPolicy else { return }
    app.setActivationPolicy(desiredPolicy)
  }
}
