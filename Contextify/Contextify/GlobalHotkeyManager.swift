import Foundation
import AppKit
import CoreGraphics
import OSLog

/// Modern global hotkey manager using CGEventTap API.
///
/// Implements Cmd+Shift+K+K chord detection to trigger terminal content capture.
/// Uses CGEventTap for reliable system-wide keyboard monitoring on macOS 14+.
@MainActor
final class GlobalHotkeyManager {
  static let shared = GlobalHotkeyManager()

  private let log = Logger(subsystem: "dev.contextify", category: "Hotkey")

  // Event tap
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  // State tracking for K+K chord
  private var firstCmdShiftKPressed = false
  private var chordResetTimer: Timer?

  // Configuration
  private let chordTimeout: TimeInterval = 0.5 // 500ms window for second K
  private let targetKeyCode: CGKeyCode = 40 // K key
  private let targetModifiers: CGEventFlags = [.maskCommand, .maskShift]
  private let undoKeyCode: CGKeyCode = 6 // Z key

  private init() {}

  // MARK: - Lifecycle

  /// Registers the Cmd+Shift+K+K global hotkey using CGEventTap.
  ///
  /// Call this during app initialization (e.g., applicationDidFinishLaunching).
  func registerContextifyHotkey() {
    NSLog("🔥 GlobalHotkeyManager: registerContextifyHotkey called")
    log.info("Setting up CGEventTap for Cmd+Shift+K+K hotkey")

    // Check accessibility permissions first
    let hasPermissions = checkAccessibilityPermissions()
    NSLog("🔥 Accessibility permissions: \(hasPermissions)")

    guard hasPermissions else {
      log.error("Accessibility permissions not granted")
      promptForAccessibilityPermissions()
      return
    }

    // Create event tap for key down events
    let eventMask = (1 << CGEventType.keyDown.rawValue)

    let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(eventMask),
      callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
        guard let refcon = refcon else { return Unmanaged.passRetained(event) }

        let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

        // Handle on main actor
        Task { @MainActor in
          manager.handleKeyDown(event: event)
        }

        // Pass through the event (don't consume it)
        return Unmanaged.passRetained(event)
      },
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    )

    NSLog("🔥 Event tap created: \(tap != nil)")

    guard let tap = tap else {
      log.error("Failed to create event tap")
      NSLog("🔥 FAILED to create event tap - showing alert")
      showAlert(
        title: "Event Tap Failed",
        message: "Failed to create keyboard event monitor.\n\nPlease ensure Contextify has Accessibility permissions in:\nSystem Settings > Privacy & Security > Accessibility"
      )
      return
    }

    eventTap = tap

    // Create run loop source and add to current run loop
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

    self.runLoopSource = runLoopSource

    // Enable the event tap
    CGEvent.tapEnable(tap: tap, enable: true)

    NSLog("🔥 ✅ Successfully registered CGEventTap for Cmd+Shift+K+K hotkey")
    log.info("✅ Successfully registered CGEventTap for Cmd+Shift+K+K hotkey")
  }

  /// Unregisters the global hotkey.
  ///
  /// Call this during app termination (e.g., applicationWillTerminate).
  func unregister() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
      eventTap = nil
    }

    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
      runLoopSource = nil
    }

    chordResetTimer?.invalidate()
    chordResetTimer = nil
    firstCmdShiftKPressed = false

    log.info("Unregistered event tap")
  }

  // MARK: - Event Handling

  private func handleKeyDown(event: CGEvent) {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
    let activeModifiers = flags.intersection(relevantFlags)

    if keyCode == Int64(undoKeyCode),
       activeModifiers == [.maskCommand],
       TerminalTextHistory.shared.hasEntries,
       NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.googlecode.iterm2" {
      Task { @MainActor in
        await TerminalUndoManager.shared.performUndo()
      }
      return
    }

    // Check if this is Cmd+Shift+K
    guard keyCode == Int64(targetKeyCode),
          flags.contains(.maskCommand),
          flags.contains(.maskShift) else {
      return
    }

    // Filter out extra modifiers (allow only Cmd+Shift, not Cmd+Shift+Ctrl+etc)
    guard activeModifiers == targetModifiers else {
      return
    }

    log.debug("Cmd+Shift+K detected")

    if firstCmdShiftKPressed {
      // Second K detected - trigger capture!
      log.info("Cmd+Shift+K+K chord completed - triggering capture")

      chordResetTimer?.invalidate()
      firstCmdShiftKPressed = false

      triggerContextifyCapture()
    } else {
      // First K detected - start timer
      log.debug("First Cmd+Shift+K pressed - waiting for second")

      firstCmdShiftKPressed = true

      // Reset state after timeout if second K not pressed
      chordResetTimer?.invalidate()
      chordResetTimer = Timer.scheduledTimer(
        withTimeInterval: chordTimeout,
        repeats: false
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.log.debug("Chord timeout - resetting state")
          self.firstCmdShiftKPressed = false
        }
      }
    }
  }

  private func triggerContextifyCapture() {
    log.info("Triggering terminal content capture")
    TerminalContentReader.shared.captureAndSendToContextify()
  }

  // MARK: - Accessibility Permissions

  private func checkAccessibilityPermissions() -> Bool {
    return AXIsProcessTrusted()
  }

  private func promptForAccessibilityPermissions() {
    // Trigger system prompt
    let options = NSDictionary(dictionary: [
      "AXTrustedCheckOptionPrompt" as CFString: true
    ])
    _ = AXIsProcessTrustedWithOptions(options)

    showAlert(
      title: "Accessibility Permission Required",
      message: """
      Contextify needs accessibility access to monitor keyboard events for the global hotkey (Cmd+Shift+K+K).

      Please enable it in:
      System Settings > Privacy & Security > Accessibility

      Then restart Contextify.
      """
    )
  }

  // MARK: - Helper

  private func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.runModal()
  }
}
