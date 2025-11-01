import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        MainWindowTracker.shared.window = window
        window.isReleasedWhenClosed = false
        // Enforce minimum window size to prevent timeline from being crushed
        window.minSize = NSSize(width: 340, height: 360)
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
