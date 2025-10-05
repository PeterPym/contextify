import Foundation
import AppKit
import OSLog
import ApplicationServices // AppleEvents types (kept for future preflight if desired)

/// Contextify → iTerm2 bridge using Apple Events (AppleScript).
/// Requirements for a sandboxed build:
///   - com.apple.security.app-sandbox = true
///   - com.apple.security.automation.apple-events = true
///   - com.apple.security.temporary-exception.apple-events = ["com.googlecode.iterm2"]
///
/// Notes:
/// - We always *attempt* to foreground iTerm2 after delivery. If Secure Keyboard Entry (SKE)
///   is enabled in iTerm2, activation may be suppressed by the OS; delivery still succeeds.
/// - We avoid depending on activation for delivery.
@MainActor
enum ITerm2Bridge {
  private static let log = Logger(subsystem: "dev.contextify", category: "ITerm2")
  private static let iTermBundleID = "com.googlecode.iterm2"

  enum SendMode {
    case append
    case replace(existingLine: String?)
  }

  enum BridgeError: LocalizedError {
    case notAuthorized            // TCC denied (-1743)
    case notRunning               // iTerm not found/couldn’t be launched (-600/-1728 path)
    case timeout                  // AppleScript timed out (-1712)
    case compile(String)          // NSAppleScript failed to init
    case general(String)

    var errorDescription: String? {
      switch self {
      case .notAuthorized: return "Not authorized to control iTerm2 (Automation)."
      case .notRunning:    return "iTerm2 is not running or couldn’t be launched."
      case .timeout:       return "AppleScript timed out talking to iTerm2."
      case .compile(let m):return "AppleScript compile error: \(m)"
      case .general(let m):return m
      }
    }
  }

  // MARK: - Public API

  /// Returns the name of the current iTerm2 session/tab, or nil if unavailable.
  static func getCurrentSessionName() async -> String? {
    let script = """
    tell application id "\(iTermBundleID)"
      if not (exists current window) then
        return ""
      end if
      tell current window
        tell current session
          return name
        end tell
      end tell
    end tell
    """

    switch runAppleScript(script) {
    case .success(let descriptor):
      return descriptor.stringValue
    case .failure(let error):
      log.warning("Failed to get session name: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  /// Ensures iTerm2 is available, then delivers `text` to the current session.
  /// Attempts to foreground iTerm2 afterward (may be ignored under SKE).
  static func send(text: String, newline: Bool, mode: SendMode = .append) async -> Result<Void, Error> {
    do {
      // 1) Launch (non-activating) or grab the running instance.
      let app = try await ensureITermIsRunning()

      // 2) Cold-start warm-up: tiny AE so iTerm2 publishes its target (avoids -600/-1728).
      _ = waitForITermReady(timeout: 2.0)

      // 3) Stage payload to disk (avoids giant-literal escaping).
      let payloadURL = try writePayload(text: text)
      defer { try? FileManager.default.removeItem(at: payloadURL) }

      // 4) AppleScript: read file → ensure window/session → delete → bracketed paste.
      let escapedPath = payloadURL.path.replacingOccurrences(of: "\"", with: "\\\"")
      let (clearSequence, requiresNewline) = deleteSequence(for: mode)

      let script = """
      set payload to read POSIX file "\(escapedPath)" as «class utf8»
      tell application id "\(iTermBundleID)"
        if not (exists current window) then
          create window with default profile
        end if
        tell current session of current window
          \(clearSequence)
          write text ((ASCII character 27) & "[200~") newline false
          write text payload newline false
          write text ((ASCII character 27) & "[201~") newline false
          \(newline ? "write text \"\" newline true" : "")
          \(requiresNewline ? "write text \"\" newline true" : "")
        end tell
      end tell
      """

      let t0 = Date()
      let result = runAppleScript(script)
      let ms = Int(Date().timeIntervalSince(t0) * 1000)

      switch result {
      case .success:
        log.info("Sent \(text.count, privacy: .public) chars to iTerm2 in \(ms)ms")
        // 5) Best-effort foreground (ignore if SKE prevents activation).
        await foregroundITermIfPossible(app)
        return .success(())
      case .failure(let err):
        log.error("iTerm send failed: \(String(describing: err), privacy: .public)")
        copyToClipboard(text)
        return .failure(err)
      }
    } catch {
      copyToClipboard(text)
      return .failure(error)
    }
  }

  // MARK: - Foregrounding (best effort)

  /// Try to bring iTerm2 to the front.
  /// 1) NSRunningApplication.activate with non-deprecated options.
  /// 2) If still not active, send AppleScript `activate` as a fallback.
  /// If SKE is on, both may be ignored by the system; that's fine.
  private static func foregroundITermIfPossible(_ app: NSRunningApplication) async {
    // First try: bring all windows forward (modern option set).
    let ok = app.activate(options: [.activateAllWindows])
    // Brief settle time for the system to update active app state.
    try? await Task.sleep(nanoseconds: 120_000_000)
    if ok, app.isActive { return }

    // Fallback: AppleScript `activate` (may be ignored under SKE).
    let script = """
    tell application id "\(iTermBundleID)"
      activate
    end tell
    """
    _ = runAppleScript(script)
    try? await Task.sleep(nanoseconds: 120_000_000)
    // No noisy logging; foregrounding is opportunistic.
  }

  // MARK: - Launch / Availability

  /// Launch iTerm2 if needed, non-activating (SKE-safe).
  private static func ensureITermIsRunning(timeout: TimeInterval = 8.0) async throws -> NSRunningApplication {
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: iTermBundleID).first {
      return running
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleID) else {
      throw BridgeError.notRunning
    }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    return try await withCheckedThrowingContinuation { cont in
      NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
        if let app { cont.resume(returning: app) }
        else if let error { cont.resume(throwing: BridgeError.general(error.localizedDescription)) }
        else { cont.resume(throwing: BridgeError.notRunning) }
      }
    }
  }

  /// Small bounded wait that exercises iTerm2’s AE target until ready.
  /// This naturally triggers the first-time TCC prompt (since we send an AE),
  /// assuming the sandbox entitlements allow events to reach iTerm2.
  private static func waitForITermReady(timeout: TimeInterval = 2.0) -> Bool {
    let script = """
    tell application id "\(iTermBundleID)"
      count of windows
    end tell
    """
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      switch runAppleScript(script) {
      case .success: return true
      case .failure(let e):
        if case .notAuthorized = e { return false } // user denied; don't spin
        usleep(120_000) // 120ms backoff for cold-start race
      }
    } while Date() < deadline
    return false
  }

  // MARK: - AppleScript runner

  private static func runAppleScript(_ source: String) -> Result<NSAppleEventDescriptor, BridgeError> {
    var errorInfo: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
      return .failure(.compile("failed to create script"))
    }
    let descriptor = script.executeAndReturnError(&errorInfo)
    if let dict = errorInfo as? [String: Any] {
      let code = dict["NSAppleScriptErrorNumber"] as? Int ?? -1
      let message = dict[NSLocalizedDescriptionKey] as? String ?? "AppleScript error (\(code))"
      switch code {
      case -1743: return .failure(.notAuthorized)
      case -1712: return .failure(.timeout)
      case -1728, -600: return .failure(.notRunning)
      default:    return .failure(.general(message))
      }
    }
    return .success(descriptor)
  }

  // MARK: - Payload / Clipboard

  private static func writePayload(text: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("contextify", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private static func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private static func deleteSequence(for mode: SendMode) -> (String, Bool) {
    guard case .replace(let existingLine) = mode else { return ("", false) }
    let line = existingLine ?? ""
    let count = line.count
    guard count > 0 else { return ("", false) }
    let sequence = """
          repeat \(count) times
            write text (ASCII character 8) newline false
          end repeat
    """
    return (sequence, false)
  }
}
