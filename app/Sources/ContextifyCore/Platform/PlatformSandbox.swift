import Foundation

// MARK: - Platform Sandbox Detection

/// Cross-platform sandbox detection.
///
/// This provides a unified API for checking sandbox status across platforms.
/// The existing `Sandbox` enum in `HUDCore.swift` is macOS-specific; this file
/// provides the Linux stub and re-exports the Darwin implementation.
///
/// ## Usage
/// Code that needs sandbox detection should use `Sandbox.isSandboxed` which:
/// - On macOS: Returns true when running in App Store sandbox
/// - On Linux: Always returns false (no sandbox concept)
///
/// ## Note
/// The primary `Sandbox` enum is defined in `HUDCore.swift` for macOS.
/// This file only provides the Linux stub implementation.
#if !os(macOS) && !os(iOS) && !os(tvOS) && !os(watchOS) && !os(visionOS)

/// Linux stub for Sandbox detection.
/// Always returns false since Linux doesn't have App Store sandbox.
public enum Sandbox {
  /// Returns true when running in a sandboxed environment.
  /// On Linux, this is always false.
  public static var isSandboxed: Bool { false }

  /// Runtime check for sandbox.
  /// On Linux, this is always false.
  public static var isRuntimeSandboxed: Bool { false }
}

#endif
