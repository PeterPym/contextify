import SwiftUI
import AppKit
import ContextifyCore

struct WindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        MainWindowTracker.shared.window = window
        window.isReleasedWhenClosed = false
        // Enforce minimum window size: compose(100) + timeline(340) + divider(11) + padding(16) = 467px
        window.minSize = NSSize(width: 467, height: 360)
        // Allow window to appear alongside full-screen apps on the same display
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        // Apply saved always-on-top preference
        if HUDPreferences.isWindowAlwaysOnTop() {
          window.level = .floating
          // Stay visible when another app is focused (the whole point of float-on-top)
          window.hidesOnDeactivate = false
        }
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
