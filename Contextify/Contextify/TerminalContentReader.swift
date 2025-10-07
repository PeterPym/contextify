import Foundation
import AppKit
import ApplicationServices
import OSLog

/// Reads terminal content using AppleScript or Accessibility API.
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
  /// 2. Prefer iTerm2 Python API (with AppleScript fallback) or Accessibility API
  /// 3. Parse Claude Code input with ClaudeCodeParser
  /// 4. Route to ComposeURLRouter with base64 encoding
  /// 5. Focus compose textarea
  func captureAndSendToContextify() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.captureAndSendToContextifyAsync()
    }
  }

  private func captureAndSendToContextifyAsync() async {
    // Check accessibility permissions first
    guard checkAccessibilityPermissions() else {
      log.warning("Accessibility permissions not granted")
      promptForAccessibilityPermissions()
      return
    }

    // Read terminal content
    guard let terminalContent = await readActiveTerminalContent() else {
      log.warning("Failed to read terminal content")
      return
    }

    log.info("Captured terminal content: \(terminalContent.count, privacy: .public) chars")

    // TEMPORARY DEBUG: Log FULL content line-by-line to avoid truncation
    NSLog("🔥 ========== FULL TERMINAL CONTENT (\(terminalContent.count) chars) ==========")
    let lines = terminalContent.components(separatedBy: .newlines)
    NSLog("🔥 Total lines: \(lines.count)")
    for (i, line) in lines.enumerated() {
      NSLog("🔥 Line \(i): [\(line)]")
    }
    NSLog("🔥 ========== END TERMINAL CONTENT ==========")

    // Parse Claude Code input
    let extractedText = ClaudeCodeParser.parseInput(from: terminalContent) ?? ""

    if extractedText.isEmpty {
      log.warning("No valid Claude Code input found in terminal content - focusing compose area anyway")
      NSLog("🔥 No '> ' marker found, but still focusing compose window")
    } else {
      log.info("Extracted Claude Code input: \(extractedText.count, privacy: .public) chars")
    }

    // Send to Contextify using URL scheme (even if empty, to focus the window)
    openComposeWithText(extractedText)
    NotificationCenter.default.post(name: .contextifyTimelineManualRefresh, object: nil)
  }

  // MARK: - Accessibility Permissions

  private func checkAccessibilityPermissions() -> Bool {
    return AXIsProcessTrusted()
  }

  private func promptForAccessibilityPermissions() {
    // Trigger system prompt (suppress concurrency warning for C API)
    let options = NSDictionary(dictionary: [
      "AXTrustedCheckOptionPrompt" as CFString: true
    ])
    _ = AXIsProcessTrustedWithOptions(options)

    // Show user-friendly alert
    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText = """
    Contextify needs accessibility access to capture text from your terminal.

    Please enable it in:
    System Settings > Privacy & Security > Accessibility

    Then press Cmd+Shift+K+K again to capture text.
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

  private func readActiveTerminalContent() async -> String? {
    // Get frontmost application
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
      log.error("No frontmost application")
      return nil
    }

    let bundleID = frontmostApp.bundleIdentifier ?? "unknown"
    log.info("Reading from app: \(frontmostApp.localizedName ?? "unknown", privacy: .public) (Bundle: \(bundleID, privacy: .public))")
    NSLog("🔥 Reading from: \(frontmostApp.localizedName ?? "unknown") - Bundle: \(bundleID)")

    // Use daemon for iTerm2 with fallback to legacy Python reader
    if bundleID == "com.googlecode.iterm2" {
      // Ensure daemon is running
      await ITerm2DaemonClient.shared.ensureRunning()

      // Wait briefly for daemon to initialize on first start (discovery file race)
      try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

      // Try daemon first (fast path)
      switch await ITerm2DaemonClient.shared.getContent(maxLines: 100) {
      case .success(let content):
        NSLog("🔥 ✅ Got content from daemon: \(content.count) chars")
        return content

      case .failure(let error):
        NSLog("🔥 ❌ Daemon failed: \(error) - CANNOT USE LEGACY (too slow)")
        log.error("Daemon failed: \(error.description, privacy: .public)")

        // Show user-friendly error alert
        let alert = NSAlert()
        alert.messageText = "iTerm2 Daemon Not Available"
        alert.informativeText = """
        The fast iTerm2 daemon failed to start: \(error.description)

        This is likely because the Python environment is not bundled in the app.

        Expected: <30ms response time
        Legacy fallback: 1-2 seconds (unacceptable)

        Please check the daemon logs:
        ~/Library/Application Support/Contextify/logs/daemon.stderr.log
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()

        return nil
      }
    }

    // Use AppleScript for Terminal.app
    if bundleID == "com.apple.Terminal" {
      NSLog("🔥 Using AppleScript method for Terminal.app")
      return readFromTerminalAppUsingAppleScript()
    }

    // Fall back to Accessibility API for other terminal apps
    NSLog("🔥 Using Accessibility API for \(bundleID)")
    return readUsingAccessibilityAPI(frontmostApp)
  }

  // MARK: - AppleScript Methods
  private func readFromITerm2UsingAppleScript() -> String? {
    let script = """
    tell application "iTerm2"
      tell current session of current window
        get contents
      end tell
    end tell
    """

    return executeAppleScript(script, appName: "iTerm2")
  }

  private func readFromTerminalAppUsingAppleScript() -> String? {
    let script = """
    tell application "Terminal"
      get contents of selected tab of front window
    end tell
    """

    return executeAppleScript(script, appName: "Terminal")
  }

  func captureCurrentLineFast() async -> String? {
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
    let bundleID = frontmostApp.bundleIdentifier ?? "unknown"

    if bundleID == "com.googlecode.iterm2" {
      await ITerm2DaemonClient.shared.ensureRunning()
      switch await ITerm2DaemonClient.shared.getContent(maxLines: 4) {
      case .success(let content):
        if let parsed = ClaudeCodeParser.parseInput(from: content) {
          return parsed
        }
        return content.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespacesAndNewlines)
      case .failure:
        if let fallback = readFromITerm2UsingAppleScript() {
          if let parsed = ClaudeCodeParser.parseInput(from: fallback) {
            return parsed
          }
          return fallback.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
      }
    }

    if bundleID == "com.apple.Terminal" {
      if let text = readFromTerminalAppUsingAppleScript() {
        if let parsed = ClaudeCodeParser.parseInput(from: text) {
          return parsed
        }
        return text.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return nil
    }

    if let accessibilityText = readUsingAccessibilityAPI(frontmostApp) {
      if let parsed = ClaudeCodeParser.parseInput(from: accessibilityText) {
        return parsed
      }
      return accessibilityText.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return nil
  }

  private func executeAppleScript(_ source: String, appName: String) -> String? {
    var error: NSDictionary?
    guard let scriptObject = NSAppleScript(source: source) else {
      log.error("Failed to create AppleScript for \(appName)")
      NSLog("🔥 ERROR: Failed to create AppleScript for \(appName)")
      return nil
    }

    let output = scriptObject.executeAndReturnError(&error)

    if let error = error {
      log.error("AppleScript error for \(appName): \(error)")
      NSLog("🔥 AppleScript error for \(appName): \(error)")
      return nil
    }

    let content = output.stringValue ?? ""
    NSLog("🔥 ✅ Got \(appName) content via AppleScript: \(content.count) chars")
    log.info("Got \(appName) content via AppleScript: \(content.count, privacy: .public) chars")
    return content
  }

  // MARK: - Accessibility API Fallback

  private func readUsingAccessibilityAPI(_ frontmostApp: NSRunningApplication) -> String? {
    let pid = frontmostApp.processIdentifier
    let bundleID = frontmostApp.bundleIdentifier ?? "unknown"
    let appElement = AXUIElementCreateApplication(pid)

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
      NSLog("🔥 ERROR: Failed to get focused element from \(bundleID). Error: \(focusedError.rawValue)")
      NSLog("🔥 This error (-25204) = kAXErrorInvalidUIElement")
      NSLog("🔥 Possible causes:")
      NSLog("🔥   1. App doesn't have permission to access \(bundleID)")
      NSLog("🔥   2. Focused element doesn't support Accessibility API")
      NSLog("🔥   3. Terminal app may require AppleScript instead")
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
      NSLog("🔥 ✅ Got content via Accessibility API: \(textValue.count) chars")
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
      NSLog("🔥 ✅ Got selected text via Accessibility API: \(selected.count) chars")
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
        NSLog("🔥 ✅ Got parent content via Accessibility API: \(parentText.count) chars")
        return parentText
      }
    }

    log.error("All fallback methods failed. valueError=\(valueError.rawValue, privacy: .public), selectedError=\(selectedError.rawValue, privacy: .public)")
    NSLog("🔥 ERROR: All Accessibility API methods failed")
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
