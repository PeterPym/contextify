#if os(macOS)
import SwiftUI
import AppKit

@MainActor
struct WindowTitleWriter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
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
