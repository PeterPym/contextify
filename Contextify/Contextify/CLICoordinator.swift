//
//  CLICoordinator.swift
//  Contextify
//
//  Central coordinator for CLI (shim + plugin) installation state.
//  Manages enable/disable state and auto-install/upgrade logic.
//
//  Pattern follows AppStoreOnboardingCoordinator:
//  - Singleton with @MainActor
//  - State computed from filesystem (no separate UserDefaults flag)
//  - Throttled refresh to avoid expensive checks
//  - isHandlingOperation prevents UI races
//

import SwiftUI
import Combine
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "CLICoordinator")

/// Coordinates CLI (shim + plugin) installation state.
///
/// **Responsibilities:**
/// - Own and publish CLI enable/disable state
/// - Provide single source of truth for CLI status
/// - Handle auto-install/upgrade on app launch
/// - Handle enable/disable from Settings UI
///
/// **State is computed from filesystem:**
/// - Enabled if both shim and plugin exist
/// - Disabled if either is missing
/// - No separate UserDefaults flag
///
/// **Usage:**
/// - Inject as `@ObservedObject` or access via `CLICoordinator.shared`
/// - Check `isEnabled` to determine if CLI is active
/// - Call `enable()` to install shim + plugin
/// - Call `disable()` to remove shim + plugin
/// - Call `checkAndUpgrade()` on app launch
@MainActor
public final class CLICoordinator: ObservableObject {
  public static let shared = CLICoordinator()

  /// CLI state - computed from filesystem, not stored separately
  public enum State: Equatable {
    case disabled
    case installing
    case enabled(version: String, pathWarning: Bool)
    case upgrading(from: String, to: String)
    case failed(error: String)
  }

  /// Published CLI state
  @Published public private(set) var state: State

  /// True while enable/disable/upgrade operation is running
  /// Used to prevent UI races (similar to AppStoreOnboardingCoordinator.isHandlingCompletion)
  @Published public private(set) var isHandlingOperation: Bool = false

  /// Throttle refreshState() calls to avoid expensive filesystem checks
  private var lastCheckTime: Date?
  private let checkThrottleDuration: TimeInterval = 5.0

  private init() {
    self.state = Self.computeState()
    log.info("[CLI-INIT] state=\(String(describing: self.state))")
  }

  /// Returns true if CLI is enabled (shim + plugin both exist)
  public var isEnabled: Bool {
    if case .enabled = state { return true }
    return false
  }

  /// Returns true if PATH warning should be shown
  /// Only relevant when enabled and shim is in ~/bin
  public var needsPathWarning: Bool {
    if case .enabled(_, let pathWarning) = state {
      return pathWarning
    }
    return false
  }

  /// Enable CLI - installs shim and plugin
  public func enable() async {
    isHandlingOperation = true
    defer { isHandlingOperation = false }

    state = .installing
    log.info("[CLI-ENABLE-START]")

    do {
      try await installShimAndPlugin()
      refreshState()
      log.info("[CLI-ENABLE-SUCCESS] state=\(String(describing: self.state))")
    } catch {
      state = .failed(error: error.localizedDescription)
      log.error("[CLI-ENABLE-FAILED] error=\(error.localizedDescription)")
    }
  }

  /// Disable CLI - removes shim and plugin
  public func disable() async {
    isHandlingOperation = true
    defer { isHandlingOperation = false }

    log.info("[CLI-DISABLE-START]")
    removeShimAndPlugin()
    state = .disabled
    log.info("[CLI-DISABLE-COMPLETE]")
  }

  /// Check for upgrades and install if bundled version > installed version
  /// Called on app launch
  public func checkAndUpgrade() async {
    guard case .enabled(let installedVersion, _) = state else {
      // Not installed, nothing to upgrade
      return
    }

    let bundledVersion = readBundledVersion()
    guard bundledVersion != installedVersion else {
      log.info("[CLI-UPGRADE-SKIP] version=\(bundledVersion) (already installed)")
      return
    }

    isHandlingOperation = true
    defer { isHandlingOperation = false }

    state = .upgrading(from: installedVersion, to: bundledVersion)
    log.info("[CLI-UPGRADE-START] from=\(installedVersion) to=\(bundledVersion)")

    do {
      try await upgradePlugin(to: bundledVersion)
      refreshState()
      log.info("[CLI-UPGRADE-SUCCESS] version=\(bundledVersion)")
    } catch {
      state = .failed(error: error.localizedDescription)
      log.error("[CLI-UPGRADE-FAILED] error=\(error.localizedDescription)")
    }
  }

  /// Refresh state by re-computing from filesystem
  /// Throttled to avoid expensive checks
  public func refreshState() {
    let now = Date()
    if let lastCheck = lastCheckTime,
       now.timeIntervalSince(lastCheck) < checkThrottleDuration {
      return
    }

    let oldState = state
    state = Self.computeState()
    if state != oldState {
      log.info("[CLI-REFRESH] state=\(String(describing: self.state))")
    }
    lastCheckTime = now
  }

  // MARK: - Private Implementation (stubs for now)

  private static func computeState() -> State {
    // TODO: Implement filesystem checks
    // Check if shim exists
    // Check if plugin exists
    // Check if ~/bin on PATH
    return .disabled
  }

  private func readBundledVersion() -> String {
    // TODO: Read from Info.plist CFBundleShortVersionString
    return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
  }

  private func installShimAndPlugin() async throws {
    // TODO: Implement atomic installation
    log.info("[CLI-INSTALL] Starting installation...")
  }

  private func upgradePlugin(to version: String) async throws {
    // TODO: Implement upgrade (same as install but logs differently)
    log.info("[CLI-INSTALL] Upgrading to version \(version)...")
  }

  private func removeShimAndPlugin() {
    // TODO: Implement removal
    log.info("[CLI-REMOVE] Removing shim and plugin...")
  }
}
