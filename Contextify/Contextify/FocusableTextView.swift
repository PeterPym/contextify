import AppKit
import SwiftUI

extension Notification.Name {
  static let contextifyFocusEditor = Notification.Name("contextifyFocusEditor")
}

struct FocusableTextView: NSViewRepresentable {
  @Binding var text: String

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false

    let textView = NSTextView()
    textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.usesAdaptiveColorMappingForDarkAppearance = true
    textView.string = text
    textView.allowsUndo = true
    textView.delegate = context.coordinator

    context.coordinator.textView = textView

    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let textView = context.coordinator.textView else { return }
    if textView.string != text {
      textView.string = text
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: FocusableTextView
    weak var textView: NSTextView?

    init(_ parent: FocusableTextView) {
      self.parent = parent
      super.init()
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleFocusNotification),
        name: .contextifyFocusEditor,
        object: nil
      )
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    func textDidChange(_ notification: Notification) {
      guard let textView else { return }
      parent.text = textView.string
    }

    @objc private func handleFocusNotification() {
      guard let textView else { return }
      textView.window?.makeFirstResponder(textView)
      let length = (textView.string as NSString).length
      textView.setSelectedRange(NSRange(location: length, length: 0))
      textView.scrollRangeToVisible(NSRange(location: length, length: 0))
    }
  }
}
