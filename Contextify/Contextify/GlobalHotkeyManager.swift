import Foundation
import AppKit
import HotKey
import OSLog

/// Manages global hotkey registration for Contextify.
///
/// Implements Shift+G+G chord detection to trigger terminal content capture.
/// Uses a state machine to track the first G press and validate the second press.
@MainActor
final class GlobalHotkeyManager {
  static let shared = GlobalHotkeyManager()

  private let log = Logger(subsystem: "dev.contextify", category: "Hotkey")

  // Hotkey configuration
  private var shiftGHotKey: HotKey?

  // State tracking for G+G chord
  private var firstShiftGPressed = false
  private var chordResetTimer: Timer?

  // Configuration
  private let chordTimeout: TimeInterval = 0.5 // 500ms window for second G

  private init() {}

  // MARK: - Lifecycle

  /// Registers the Shift+G+G global hotkey.
  ///
  /// Call this during app initialization (e.g., applicationDidFinishLaunching).
  func registerContextifyHotkey() {
    // Register Shift+G
    shiftGHotKey = HotKey(
      key: .g,
      modifiers: [.shift]
    )

    shiftGHotKey?.keyDownHandler = { [weak self] in
      self?.handleShiftGPressed()
    }

    log.info("Registered Shift+G+G global hotkey")
  }

  /// Unregisters the global hotkey.
  ///
  /// Call this during app termination (e.g., applicationWillTerminate).
  func unregister() {
    shiftGHotKey = nil
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
