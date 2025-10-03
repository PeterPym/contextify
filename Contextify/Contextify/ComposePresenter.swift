import SwiftUI
import AppKit

@MainActor
enum ComposePresenter {
  static func present(
    initialText: String,
    title: String = "Compose",
    tmpFilePath: String? = nil,
    sendToITermOnSubmit: Bool = true
  ) {
    ComposeWindowController.shared.present(
      initialText: initialText,
      title: title,
      tmpFilePath: tmpFilePath,
      sendToITermOnSubmit: sendToITermOnSubmit
    )
  }
}
