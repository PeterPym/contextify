import AppKit
import ContextifyCore

@MainActor
final class ComposeWindowManager {
    static let shared = ComposeWindowManager()

    private init() {}

    func present(initialText: String, title: String, sendOnSubmit: Bool) {
        let model = HUDViewModel.shared
        model.updateComposeText(initialText)
        model.lastCapturedTerminalText = initialText

        var window = MainWindowTracker.shared.window
        if window == nil {
            NSApp.activate(ignoringOtherApps: true)
            if let candidate = NSApp.windows.first {
                MainWindowTracker.shared.window = candidate
                window = candidate
            }
        }

        guard let window else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let wasKey = window.isKeyWindow
        if window.title != title {
            window.title = title
        }

        if !wasKey {
            window.makeKeyAndOrderFront(nil)
        }

        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .contextifyFocusEditor, object: nil)
        }
    }
}
