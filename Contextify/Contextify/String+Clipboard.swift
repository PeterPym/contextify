import AppKit

extension String {
  /// Copy this string to the system clipboard
  func copyToClipboard() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(self, forType: .string)
  }
}
