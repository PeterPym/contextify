import Foundation
import AppKit
import Carbon
import OSLog

/// Manages global hotkey registration for Contextify.
///
/// Implements Shift+G+G chord detection to trigger terminal content capture.
/// Uses Carbon's RegisterEventHotKey API for system-wide keyboard monitoring.
@MainActor
final class GlobalHotkeyManager {
  static let shared = GlobalHotkeyManager()

  private let log = Logger(subsystem: "dev.contextify", category: "Hotkey")

  // Carbon hotkey registration
  private var eventHotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?

  // State tracking for G+G chord
  private var firstShiftGPressed = false
  private var chordResetTimer: Timer?

  // Configuration
  private let chordTimeout: TimeInterval = 0.5 // 500ms window for second G
  private let hotkeyID: UInt32 = 1
  private let hotkeySignature: OSType = UTGetOSTypeFromString("CTFY" as CFString)

  private init() {}

  // MARK: - Lifecycle

  /// Registers the Cmd+Shift+G+G global hotkey.
  ///
  /// Call this during app initialization (e.g., applicationDidFinishLaunching).
  func registerContextifyHotkey() {
    log.info("Attempting to register Cmd+Shift+G hotkey...")

    // Register Cmd+Shift+G using Carbon API
    var glyph = EventHotKeyID(signature: hotkeySignature, id: hotkeyID)
    let modifiers: UInt32 = UInt32(cmdKey) + UInt32(shiftKey) // Cmd+Shift modifiers
    let keyCode: UInt32 = 5 // 'G' key code

    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      glyph,
      GetEventDispatcherTarget(),
      0,
      &eventHotKeyRef
    )

    if status != noErr {
      log.error("Failed to register hotkey: \(status, privacy: .public)")

      // Show alert to user
      let alert = NSAlert()
      alert.messageText = "Hotkey Registration Failed"
      alert.informativeText = "Failed to register Cmd+Shift+G hotkey. Error code: \(status)"
      alert.alertStyle = .warning
      alert.runModal()
      return
    }

    log.info("Successfully called RegisterEventHotKey")

    // Install event handler
    var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                    eventKind: UInt32(kEventHotKeyPressed))]
    let callback: EventHandlerUPP = { (_, event, userData) -> OSStatus in
      guard let userData = userData else { return OSStatus(eventNotHandledErr) }
      let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()

      Task { @MainActor in
        manager.handleShiftGPressed()
      }

      return noErr
    }

    let handlerStatus = InstallEventHandler(
      GetEventDispatcherTarget(),
      callback,
      1,
      &eventTypes,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )

    if handlerStatus != noErr {
      log.error("Failed to install event handler: \(handlerStatus, privacy: .public)")

      let alert = NSAlert()
      alert.messageText = "Event Handler Failed"
      alert.informativeText = "Failed to install event handler. Error code: \(handlerStatus)"
      alert.alertStyle = .warning
      alert.runModal()
      return
    }

    log.info("✅ Successfully registered Cmd+Shift+G+G global hotkey")
  }

  /// Unregisters the global hotkey.
  ///
  /// Call this during app termination (e.g., applicationWillTerminate).
  func unregister() {
    if let ref = eventHotKeyRef {
      UnregisterEventHotKey(ref)
      eventHotKeyRef = nil
    }

    if let handler = eventHandler {
      RemoveEventHandler(handler)
      eventHandler = nil
    }

    chordResetTimer?.invalidate()
    chordResetTimer = nil
    firstShiftGPressed = false

    log.info("Unregistered global hotkey")
  }

  // MARK: - Hotkey Handling

  private func handleShiftGPressed() {
    if firstShiftGPressed {
      // Second G detected - trigger capture!
      log.info("Shift+G+G detected - triggering capture")

      chordResetTimer?.invalidate()
      firstShiftGPressed = false

      triggerContextifyCapture()
    } else {
      // First G detected - start timer
      log.debug("First Shift+G pressed - waiting for second")

      firstShiftGPressed = true

      // Reset state after timeout if second G not pressed
      chordResetTimer?.invalidate()
      chordResetTimer = Timer.scheduledTimer(
        withTimeInterval: chordTimeout,
        repeats: false
      ) { [weak self] _ in
        self?.log.debug("Chord timeout - resetting state")
        self?.firstShiftGPressed = false
      }
    }
  }

  private func triggerContextifyCapture() {
    log.info("Triggering terminal content capture")
    TerminalContentReader.shared.captureAndSendToContextify()
  }
}
