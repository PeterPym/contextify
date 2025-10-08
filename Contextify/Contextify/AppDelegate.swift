import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard isAppleIntelligenceAvailable() else {
      presentAvailabilityAlert()
      NSApp.terminate(nil)
      return
    }

    // Register global hotkey (Shift+G+G)
    Task { @MainActor in
      GlobalHotkeyManager.shared.registerContextifyHotkey()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Unregister global hotkey
    Task { @MainActor in
      GlobalHotkeyManager.shared.unregister()
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    urls.forEach { ComposeURLRouter.handle($0) }
  }

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
  func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

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
}
