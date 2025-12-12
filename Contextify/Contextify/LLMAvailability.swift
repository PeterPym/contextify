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
/// Use `LLMAvailability.current` to check if LLM features are available.
/// In "lite mode" (macOS 15 or simulation), summaries are disabled but
/// timeline monitoring, indexing, and search still work.
///
/// **Design note:** `current` is NOT @MainActor because it's a pure check
/// (OS version + launch args) with no UI state. This allows calling from
/// any context: SwiftUI views, actors, view models.
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

  // MARK: - Availability Check

  /// Current LLM availability
  ///
  /// Check this before any LLM operations. In lite mode, skip LLM calls entirely.
  /// This is a pure computation (no side effects) so it's safe to call from any context.
  static var current: LLMAvailability {
    // Check simulation flag first (DEBUG only)
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos") {
      return .unavailableOldOS
    }
    #endif

    // Check OS version
    guard #available(macOS 26, *) else {
      return .unavailableOldOS
    }
    return .available
  }

  /// Launch argument to simulate lite mode on macOS 26 for testing
  ///
  /// Usage:
  /// - Xcode: Edit Scheme > Run > Arguments > Add `-simulate-legacy-macos`
  /// - Terminal: `./Contextify.app/Contents/MacOS/Contextify -simulate-legacy-macos`
  ///
  /// Only available in DEBUG builds to prevent end-users from forcing lite mode.
  static var simulateLegacyMacOS: Bool {
    #if DEBUG
    return ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos")
    #else
    return false
    #endif
  }
}

// MARK: - Nonisolated Helper

/// Nonisolated helper for checking lite mode from any context (including actors).
/// Use this instead of `LLMAvailability.current.isLiteMode` within actors.
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
