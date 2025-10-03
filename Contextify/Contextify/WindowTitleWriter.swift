#if os(macOS)
import SwiftUI
import AppKit

@MainActor
struct WindowTitleWriter: NSViewRepresentable {
    let title: String

    final class TitleView: NSView {
        var title: String = ""
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.title = title
            window?.titleVisibility = .visible
        }
    }

    func makeNSView(context: Context) -> TitleView {
        let view = TitleView()
        view.title = title
        return view
    }

    func updateNSView(_ nsView: TitleView, context: Context) {
        nsView.title = title
        nsView.window?.title = title
    }
}
#else
import SwiftUI

struct WindowTitleWriter: View {
    let title: String
    var body: some View { EmptyView() }
}
#endif
