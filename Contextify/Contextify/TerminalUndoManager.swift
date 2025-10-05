import Foundation
import ContextifyCore

@MainActor
final class TerminalUndoManager {
    static let shared = TerminalUndoManager()

    private init() {}

    func performUndo() async {
        guard let entry = TerminalTextHistory.shared.pop() else {
            NotificationCenter.default.post(
                name: .contextifyShowToast,
                object: nil,
                userInfo: [ToastPayloadKey.message: "Nothing to undo"]
            )
            return
        }

        let result = await ITerm2Bridge.send(text: entry.text, newline: false)
        switch result {
        case .success:
            HUDViewModel.shared.composeText = entry.text
            HUDViewModel.shared.lastCapturedTerminalText = entry.text
            NotificationCenter.default.post(name: .contextifyFocusEditor, object: nil)
            NotificationCenter.default.post(
                name: .contextifyShowToast,
                object: nil,
                userInfo: [ToastPayloadKey.message: "Restored previous command"]
            )
        case .failure(let error):
            TerminalTextHistory.shared.requeue(entry)
            NotificationCenter.default.post(
                name: .contextifyShowToast,
                object: nil,
                userInfo: [ToastPayloadKey.message: "Undo failed: \(error.localizedDescription)"]
            )
        }
    }
}
