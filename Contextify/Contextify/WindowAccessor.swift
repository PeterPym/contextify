import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        MainWindowTracker.shared.window = window
        window.isReleasedWhenClosed = false
        // Enforce minimum window size: compose(100) + timeline(340) + divider(11) + padding(16) = 467px
        window.minSize = NSSize(width: 467, height: 360)
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
