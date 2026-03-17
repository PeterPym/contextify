import SwiftUI
import AppKit
import ContextifyCore

/// The window level used for Settings/auxiliary windows when Keep on Top is
/// active. One step above .floating so they can appear in front of the main
/// window without interfering with system-level panels.
let keepOnTopAuxiliaryLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

/// Returns true if the given window is the SwiftUI Settings window.
func isSettingsWindow(_ window: NSWindow) -> Bool {
  window.identifier?.rawValue == "com.apple.SwiftUI.Settings"
    || (window.styleMask.contains(.titled)
      && (window.title.localizedCaseInsensitiveContains("settings")
        || window.title.localizedCaseInsensitiveContains("preferences")))
}

/// Applies or removes always-on-top window behavior.
/// Called from both WindowAccessor (startup) and WindowCommands (runtime toggle)
/// to keep behavior consistent.
///
/// Also immediately adjusts any open Settings window so it stays above the
/// floating main window. The didBecomeKey observer in AppPresentationController
/// handles Settings windows that open after Keep on Top is already active.
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

  // Keep Settings window above the main window regardless of Keep on Top state.
  let settingsLevel: NSWindow.Level = enabled ? keepOnTopAuxiliaryLevel : .normal
  NSApp.windows.filter { isSettingsWindow($0) }.forEach { $0.level = settingsLevel }
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
