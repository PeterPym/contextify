import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        MainWindowTracker.shared.window = window
        window.isReleasedWhenClosed = false
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
