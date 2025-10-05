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

        guard let window = MainWindowTracker.shared.window else {
            NotificationCenter.default.post(name: .contextifyFocusEditor, object: nil)
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

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            NotificationCenter.default.post(name: .contextifyFocusEditor, object: nil)
        }
    }
}
