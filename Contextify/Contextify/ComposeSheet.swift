import AppKit
import SwiftUI

@MainActor
struct ComposeSheet: View {
  enum Delivery {
    case keystrokes
    case keystrokesNoNewline
  }

  @State private var text: String
  let onSubmit: (_ text: String, _ delivery: Delivery) -> Void
  let onCancel: () -> Void

  init(
    initialText: String,
    onSubmit: @escaping (_ text: String, _ delivery: Delivery) -> Void,
    onCancel: @escaping () -> Void = {}
  ) {
    _text = State(initialValue: initialText)
    self.onSubmit = onSubmit
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Compose").font(.headline)
        Text("Prepare text for iTerm2 or any compatible target.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      FocusableTextView(text: $text)
        .frame(minHeight: 240)

      HStack(spacing: 12) {
        Button("As keystrokes") {
          guard !text.isEmpty else { return }
          onSubmit(text, .keystrokes)
        }
        Button("As keystrokes (no newline)") {
          guard !text.isEmpty else { return }
          onSubmit(text, .keystrokesNoNewline)
        }
        Spacer()
        Button("Cancel") { onCancel() }
        Button("Send") {
          onSubmit(text, .keystrokes)
        }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(text.isEmpty)
      }
    }
    .padding(16)
    .frame(minWidth: 640, minHeight: 360)
  }
}
