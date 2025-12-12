//
//  LLMAvailability.swift
//  Contextify
//
//  Centralized LLM availability detection with lite mode support
//

import Foundation
import OSLog

/// Centralized LLM availability detection.
///
/// Use `isLiteModeActive()` to check if lite mode is active.
/// In "lite mode" (macOS < 26 or simulation), summaries are disabled but
/// timeline monitoring, indexing, and search still work.
///
/// Use `LLMAvailability.current` for detailed status (e.g., status bar display).
enum LLMAvailability: Sendable, Equatable {
  case available
  case unavailableOldOS
  case unavailableNotEnabled(reason: String)
  case unavailableOther(reason: String)

  /// True if running in lite mode (no LLM summaries)
  var isLiteMode: Bool {
    switch self {
    case .available:
      return false
    case .unavailableOldOS, .unavailableNotEnabled, .unavailableOther:
      return true
    }
  }

  /// User-facing description for status bar
  var statusText: String {
    switch self {
    case .available:
      return "Apple Intelligence"
    case .unavailableOldOS:
      return "Lite Mode"
    case .unavailableNotEnabled(let reason):
      return reason
    case .unavailableOther(let reason):
      return reason
    }
  }

  // MARK: - Availability Checks

  /// Whether simulating legacy macOS via launch argument (DEBUG only)
  static var simulateLegacyMacOS: Bool {
    #if DEBUG
    return ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos")
    #else
    return false
    #endif
  }

  /// Current LLM availability status (for detailed status display)
  ///
  /// Use `isLiteModeActive()` for simple boolean checks. Use this for status bar
  /// display where you need the specific reason or status text.
  static var current: LLMAvailability {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos") {
      return .unavailableOldOS
    }
    #endif
    guard #available(macOS 26, *) else { return .unavailableOldOS }
    return .available
  }
}

// MARK: - Global Helper

/// Check if lite mode is active (no LLM summaries available).
///
/// This is the canonical check for lite mode - use it everywhere.
/// Safe to call from any context (views, actors, async code).
///
/// Note: `nonisolated` is required for Swift 6 to allow calling from actors
/// without async/await. The check is a pure computation (OS version + launch args).
nonisolated func isLiteModeActive() -> Bool {
  #if DEBUG
  if ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos") {
    return true
  }
  #endif
  if #available(macOS 26, *) {
    return false
  }
  return true
}

// MARK: - Logging

extension LLMAvailability {
  private static let log = Logger(subsystem: "dev.contextify", category: "LLMAvailability")

  /// Log current availability status (call once at startup)
  static func logStatus() {
    let status = current
    switch status {
    case .available:
      log.info("[LLM-AVAILABILITY] Full mode - Apple Intelligence available")
    case .unavailableOldOS:
      if simulateLegacyMacOS {
        log.notice("[LLM-AVAILABILITY] Lite mode - simulating legacy macOS via launch argument")
      } else {
        log.notice("[LLM-AVAILABILITY] Lite mode - macOS version < 26")
      }
    case .unavailableNotEnabled(let reason):
      log.warning("[LLM-AVAILABILITY] Lite mode - \(reason, privacy: .public)")
    case .unavailableOther(let reason):
      log.warning("[LLM-AVAILABILITY] Lite mode - \(reason, privacy: .public)")
    }
  }
}
