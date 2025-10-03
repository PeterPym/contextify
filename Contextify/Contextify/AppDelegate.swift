import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
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
}
