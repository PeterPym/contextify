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

        // Always bring window to front and activate app
        window.makeKeyAndOrderFront(nil)

        if window.title != title {
            window.title = title
        }

        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }

        // Post focus notification with slight delay to ensure window is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .contextifyFocusEditor, object: nil)
        }
    }
}
