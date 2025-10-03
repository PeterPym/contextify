import Foundation
import AppKit
import ApplicationServices
import OSLog

/// Reads terminal content using macOS Accessibility API.
///
/// This class provides methods to capture text from the active terminal window
/// and route it to Contextify's compose interface.
@MainActor
final class TerminalContentReader {
  static let shared = TerminalContentReader()

  private let log = Logger(subsystem: "dev.contextify", category: "HotkeyCapture")

  private init() {}

  /// Captures text from the active terminal and sends it to Contextify compose.
  ///
  /// Workflow:
  /// 1. Check Accessibility permissions
  /// 2. Read terminal content via Accessibility API
  /// 3. Parse Claude Code input with ClaudeCodeParser
  /// 4. Route to ComposeURLRouter with base64 encoding
  /// 5. Focus compose textarea
  func captureAndSendToContextify() {
    // Check accessibility permissions first
    guard checkAccessibilityPermissions() else {
      log.warning("Accessibility permissions not granted")
      promptForAccessibilityPermissions()
      return
    }

    // Read terminal content
    guard let terminalContent = readActiveTerminalContent() else {
      log.warning("Failed to read terminal content")
      return
    }

    log.info("Captured terminal content: \(terminalContent.count, privacy: .public) chars")

    // Parse Claude Code input
    guard let extractedText = ClaudeCodeParser.parseInput(from: terminalContent) else {
      log.warning("No valid Claude Code input found in terminal content")
      return
    }

    log.info("Extracted Claude Code input: \(extractedText.count, privacy: .public) chars")

    // Send to Contextify using URL scheme
    openComposeWithText(extractedText)
  }

  // MARK: - Accessibility Permissions

  private func checkAccessibilityPermissions() -> Bool {
    return AXIsProcessTrusted()
  }

  private func promptForAccessibilityPermissions() {
    let options: NSDictionary = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ]
    _ = AXIsProcessTrustedWithOptions(options)

    // Show user-friendly alert
    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText = """
    Contextify needs accessibility access to capture text from your terminal.

    Please enable it in:
    System Settings > Privacy & Security > Accessibility

    Then press Shift+G+G again to capture text.
    """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
      }
    }
  }

  // MARK: - Terminal Content Reading

  private func readActiveTerminalContent() -> String? {
    // Get frontmost application
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
      log.error("No frontmost application")
      return nil
    }

    let pid = frontmostApp.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    log.info("Reading from app: \(frontmostApp.localizedName ?? "unknown", privacy: .public) (PID: \(pid, privacy: .public))")

    // Get focused element (terminal window/text area)
    var focusedElement: CFTypeRef?
    let focusedError = AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedUIElementAttribute as CFString,
      &focusedElement
    )

    guard focusedError == .success,
          let element = focusedElement as! AXUIElement? else {
      log.error("Failed to get focused element: \(focusedError.rawValue, privacy: .public)")
      return nil
    }

    // Try to get value (text content) from focused element
    var value: CFTypeRef?
    let valueError = AXUIElementCopyAttributeValue(
      element,
      kAXValueAttribute as CFString,
      &value
    )

    if valueError == .success, let textValue = value as? String {
      log.info("Got value attribute: \(textValue.count, privacy: .public) chars")
      return textValue
    }

    // Fallback: try to get selected text first
    var selectedText: CFTypeRef?
    let selectedError = AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextAttribute as CFString,
      &selectedText
    )

    if selectedError == .success, let selected = selectedText as? String {
      log.info("Got selected text: \(selected.count, privacy: .public) chars")
      return selected
    }

    // Fallback 2: Try to get the entire text area content
    // Navigate up to find the text area/scroll view
    var parent: CFTypeRef?
    let parentError = AXUIElementCopyAttributeValue(
      element,
      kAXParentAttribute as CFString,
      &parent
    )

    if parentError == .success, let parentElement = parent as! AXUIElement? {
      var parentValue: CFTypeRef?
      let parentValueError = AXUIElementCopyAttributeValue(
        parentElement,
        kAXValueAttribute as CFString,
        &parentValue
      )

      if parentValueError == .success, let parentText = parentValue as? String {
        log.info("Got parent value: \(parentText.count, privacy: .public) chars")
        return parentText
      }
    }

    log.error("All fallback methods failed. valueError=\(valueError.rawValue, privacy: .public), selectedError=\(selectedError.rawValue, privacy: .public)")
    return nil
  }

  // MARK: - Compose Integration

  private func openComposeWithText(_ text: String) {
    // Use base64 encoding to safely pass text via URL scheme
    let base64Text = text.data(using: .utf8)?.base64EncodedString() ?? ""
    let urlEncodedBase64 = base64Text.addingPercentEncoding(
      withAllowedCharacters: .urlQueryAllowed
    ) ?? ""

    let urlString = "contextify-dev://compose?title=Compose&text64=\(urlEncodedBase64)"

    guard let url = URL(string: urlString) else {
      log.error("Failed to create URL from text")
      return
    }

    log.info("Opening compose with URL scheme")
    NSWorkspace.shared.open(url)
  }
}
