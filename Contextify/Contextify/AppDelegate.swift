import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
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
