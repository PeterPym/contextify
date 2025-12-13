//
//  LLMAvailability.swift
//  Contextify
//
//  Centralized LLM availability detection with lite mode support
//

import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

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
  case unavailableSimulated
  case unavailableNotEnabled
  case unavailableDeviceNotEligible
  case unavailableModelNotReady
  case unavailableOther(reason: String)

  /// True if running in lite mode (no LLM summaries)
  var isLiteMode: Bool {
    switch self {
    case .available:
      return false
    case .unavailableOldOS, .unavailableSimulated, .unavailableNotEnabled,
         .unavailableDeviceNotEligible, .unavailableModelNotReady, .unavailableOther:
      return true
    }
  }

  /// User-facing label for status bar (short)
  var statusText: String {
    switch self {
    case .available:
      return "Apple Intelligence"
    case .unavailableOldOS, .unavailableSimulated, .unavailableNotEnabled,
         .unavailableDeviceNotEligible, .unavailableModelNotReady, .unavailableOther:
      return "Lite Mode"
    }
  }

  /// User-facing reason for (i) tooltip (detailed explanation)
  var reasonText: String {
    switch self {
    case .available:
      return "Apple Intelligence is available"
    case .unavailableOldOS:
      return "Requires macOS 26 (Tahoe) or later"
    case .unavailableSimulated:
      return "Lite mode simulated via launch argument"
    case .unavailableNotEnabled:
      return "Enable Apple Intelligence in System Settings"
    case .unavailableDeviceNotEligible:
      return "Requires Apple Silicon Mac"
    case .unavailableModelNotReady:
      return "Apple Intelligence is still downloading"
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
  ///
  /// On macOS 26+, this checks `SystemLanguageModel.default.availability` to get
  /// the actual reason (disabled, Intel Mac, downloading, etc.).
  static var current: LLMAvailability {
    // Check simulation first (DEBUG only)
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos") {
      return .unavailableSimulated
    }
    #endif

    // Check OS version
    guard #available(macOS 26, *) else {
      return .unavailableOldOS
    }

    // On macOS 26+, check actual SystemLanguageModel availability
    #if canImport(FoundationModels)
    switch SystemLanguageModel.default.availability {
    case .available:
      return .available
    case .unavailable(let reason):
      switch reason {
      case .appleIntelligenceNotEnabled:
        return .unavailableNotEnabled
      case .deviceNotEligible:
        return .unavailableDeviceNotEligible
      case .modelNotReady:
        return .unavailableModelNotReady
      @unknown default:
        return .unavailableOther(reason: "Apple Intelligence unavailable")
      }
    }
    #else
    return .available
    #endif
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
/// We inline the simulation check here rather than using LLMAvailability.simulateLegacyMacOS
/// to avoid actor isolation issues in Swift 6.
nonisolated func isLiteModeActive() -> Bool {
  #if DEBUG
  if ProcessInfo.processInfo.arguments.contains("-simulate-legacy-macos") { return true }
  #endif
  if #available(macOS 26, *) { return false }
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
      log.notice("[LLM-AVAILABILITY] Lite mode - macOS version < 26")
    case .unavailableSimulated:
      log.notice("[LLM-AVAILABILITY] Lite mode - simulating via launch argument")
    case .unavailableNotEnabled:
      log.warning("[LLM-AVAILABILITY] Lite mode - Apple Intelligence not enabled in System Settings")
    case .unavailableDeviceNotEligible:
      log.warning("[LLM-AVAILABILITY] Lite mode - device not eligible (Intel Mac)")
    case .unavailableModelNotReady:
      log.warning("[LLM-AVAILABILITY] Lite mode - model not ready (still downloading)")
    case .unavailableOther(let reason):
      log.warning("[LLM-AVAILABILITY] Lite mode - \(reason, privacy: .public)")
    }
  }
}
