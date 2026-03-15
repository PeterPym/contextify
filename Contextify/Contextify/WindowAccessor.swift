import SwiftUI
import AppKit
import ContextifyCore

/// Applies or removes always-on-top window behavior.
/// Called from both WindowAccessor (startup) and WindowCommands (runtime toggle)
/// to keep behavior consistent.
func applyKeepOnTop(_ window: NSWindow, enabled: Bool) {
  window.collectionBehavior.insert(.fullScreenAuxiliary)
  if enabled {
    window.level = .floating
    window.hidesOnDeactivate = false
    window.collectionBehavior.insert(.canJoinAllSpaces)
  } else {
    window.level = .normal
    window.hidesOnDeactivate = true
    window.collectionBehavior.remove(.canJoinAllSpaces)
  }
}

struct WindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        AppPresentationController.shared.registerMainWindow(window)
        window.isReleasedWhenClosed = false
        // Enforce minimum window size: compose(100) + timeline(340) + divider(11) + padding(16) = 467px
        window.minSize = NSSize(width: 467, height: 360)
        // Apply saved always-on-top preference
        applyKeepOnTop(window, enabled: HUDPreferences.isWindowAlwaysOnTop())
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
