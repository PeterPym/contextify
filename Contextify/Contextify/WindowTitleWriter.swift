import SwiftUI

struct WindowTitleWriter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateWindowTitle(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateWindowTitle(for: nsView)
    }

    private func updateWindowTitle(for view: NSView) {
        DispatchQueue.main.async {
            view.window?.title = title
        }
    }
}
