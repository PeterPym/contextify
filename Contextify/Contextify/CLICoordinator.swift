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

  /// Check for installation/upgrades and install if needed
  /// Called on app launch (DMG only)
  public func checkAndUpgrade() async {
    // For DMG builds: auto-install on first launch or auto-upgrade if outdated
    // For App Store builds: this should not be called (requires permission first)

    let bundledVersion = readBundledVersion()

    switch state {
    case .disabled:
      // First-time install: auto-enable for DMG builds
      log.info("[CLI-AUTO-INSTALL-START] version=\(bundledVersion)")
      isHandlingOperation = true
      defer { isHandlingOperation = false }

      state = .installing
      do {
        try await installShimAndPlugin()
        refreshState()
        log.info("[CLI-AUTO-INSTALL-SUCCESS] version=\(bundledVersion)")
      } catch {
        state = .failed(error: error.localizedDescription)
        log.error("[CLI-AUTO-INSTALL-FAILED] error=\(error.localizedDescription)")
      }

    case .enabled(let installedVersion, _):
      // Check if upgrade needed
      guard bundledVersion != installedVersion else {
        log.info("[CLI-UPGRADE-SKIP] version=\(bundledVersion) (already installed)")
        return
      }

      log.info("[CLI-UPGRADE-START] from=\(installedVersion) to=\(bundledVersion)")
      isHandlingOperation = true
      defer { isHandlingOperation = false }

      state = .upgrading(from: installedVersion, to: bundledVersion)
      do {
        try await upgradePlugin(to: bundledVersion)
        refreshState()
        log.info("[CLI-UPGRADE-SUCCESS] version=\(bundledVersion)")
      } catch {
        state = .failed(error: error.localizedDescription)
        log.error("[CLI-UPGRADE-FAILED] error=\(error.localizedDescription)")
      }

    default:
      // Don't auto-install if installing, upgrading, or failed
      return
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

  // MARK: - Private Implementation

  private static func computeState() -> State {
    // Check if shim exists
    guard let shimPath = findInstalledShim() else {
      return .disabled
    }

    // Check if plugin exists
    guard let pluginVersion = readInstalledPluginVersion() else {
      return .disabled
    }

    // Check if ~/bin is on PATH (for App Store builds)
    let pathWarning = shimPath.contains("/bin/") && !isHomeBinOnPath()

    return .enabled(version: pluginVersion, pathWarning: pathWarning)
  }

  private func readBundledVersion() -> String {
    return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
  }

  private func installShimAndPlugin() async throws {
    log.info("[CLI-INSTALL] Starting installation...")

    // Atomic installation: temp → final location
    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory

    // 1. Copy shim to temp location
    let tempShimURL = tempDir.appendingPathComponent("contextify-query-\(UUID().uuidString)")
    guard let bundledShimURL = Bundle.main.url(forResource: "contextify-query/contextify-query", withExtension: nil) else {
      throw InstallError.bundledShimMissing
    }
    try fileManager.copyItem(at: bundledShimURL, to: tempShimURL)

    // 2. Copy plugin to temp location
    let tempPluginURL = tempDir.appendingPathComponent("contextify-plugin-\(UUID().uuidString)")
    guard let bundledPluginURL = Bundle.main.resourceURL?
      .appendingPathComponent("contextify-query/claude-plugin") else {
      throw InstallError.bundledPluginMissing
    }
    try fileManager.copyItem(at: bundledPluginURL, to: tempPluginURL)

    // 3. Make shim executable
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempShimURL.path)

    // 4. Determine final locations
    let finalShimURL = determineShimPath()
    let finalPluginURL = pluginCachePath()

    // 5. Create parent directories if needed
    let shimParent = finalShimURL.deletingLastPathComponent()
    if !fileManager.fileExists(atPath: shimParent.path) {
      try fileManager.createDirectory(at: shimParent, withIntermediateDirectories: true)
    }
    let pluginParent = finalPluginURL.deletingLastPathComponent()
    if !fileManager.fileExists(atPath: pluginParent.path) {
      try fileManager.createDirectory(at: pluginParent, withIntermediateDirectories: true)
    }

    // 6. Atomic moves to final locations
    // Remove existing files first if they exist
    if fileManager.fileExists(atPath: finalShimURL.path) {
      try fileManager.removeItem(at: finalShimURL)
    }
    if fileManager.fileExists(atPath: finalPluginURL.path) {
      try fileManager.removeItem(at: finalPluginURL)
    }

    try fileManager.moveItem(at: tempShimURL, to: finalShimURL)
    try fileManager.moveItem(at: tempPluginURL, to: finalPluginURL)

    // 7. Update plugin manifest
    try updatePluginManifest(version: readBundledVersion(), pluginPath: finalPluginURL)

    log.info("[CLI-INSTALL-SUCCESS] shim=\(finalShimURL.path) plugin=\(finalPluginURL.path)")
  }

  private func upgradePlugin(to version: String) async throws {
    log.info("[CLI-UPGRADE] Upgrading to version \(version)...")
    // Upgrade is same as install (overwrites existing)
    try await installShimAndPlugin()
  }

  private func removeShimAndPlugin() {
    log.info("[CLI-REMOVE] Removing shim and plugin...")
    let fileManager = FileManager.default

    // Remove shim from all possible locations
    let possibleShimPaths = [
      "/opt/homebrew/bin/contextify-query",
      "/usr/local/bin/contextify-query",
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent("bin/contextify-query").path,
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/contextify-query").path
    ]

    for path in possibleShimPaths {
      if fileManager.fileExists(atPath: path) {
        try? fileManager.removeItem(atPath: path)
        log.info("[CLI-REMOVE] Removed shim at \(path)")
      }
    }

    // Remove plugin directory
    let pluginDir = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/plugins/cache/contextify")
    if fileManager.fileExists(atPath: pluginDir.path) {
      try? fileManager.removeItem(at: pluginDir)
      log.info("[CLI-REMOVE] Removed plugin at \(pluginDir.path)")
    }

    // Update manifest to remove plugin entry
    removePluginFromManifest()
  }

  // MARK: - Helper Methods

  /// Find installed shim in common locations
  private static func findInstalledShim() -> String? {
    let fileManager = FileManager.default
    let possiblePaths = [
      "/opt/homebrew/bin/contextify-query",
      "/usr/local/bin/contextify-query",
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent("bin/contextify-query").path,
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/contextify-query").path
    ]

    for path in possiblePaths {
      if fileManager.fileExists(atPath: path) {
        return path
      }
    }
    return nil
  }

  /// Read installed plugin version from manifest
  private static func readInstalledPluginVersion() -> String? {
    let manifestURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/plugins/installed_plugins_v2.json")

    guard let data = try? Data(contentsOf: manifestURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let plugins = json["plugins"] as? [String: Any],
          let pluginEntries = plugins["query@contextify"] as? [[String: Any]],
          let firstEntry = pluginEntries.first,
          let version = firstEntry["version"] as? String else {
      return nil
    }

    return version
  }

  /// Check if ~/bin is on PATH
  private static func isHomeBinOnPath() -> Bool {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let homeBin = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("bin").path
    return path.split(separator: ":").contains { String($0) == homeBin }
  }

  /// Determine where to install shim (DMG: homebrew/local, App Store: ~/bin)
  private func determineShimPath() -> URL {
    let fileManager = FileManager.default

    // App Store: always use ~/bin (no permissions needed)
    if Sandbox.isSandboxed {
      return fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("bin/contextify-query")
    }

    // DMG: prefer homebrew/local paths
    if fileManager.fileExists(atPath: "/opt/homebrew/bin") {
      return URL(fileURLWithPath: "/opt/homebrew/bin/contextify-query")
    }
    if fileManager.fileExists(atPath: "/usr/local/bin") {
      return URL(fileURLWithPath: "/usr/local/bin/contextify-query")
    }

    // Fallback: ~/bin
    return fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("bin/contextify-query")
  }

  /// Plugin cache path (same for DMG and App Store)
  private func pluginCachePath() -> URL {
    let version = readBundledVersion()
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/plugins/cache/contextify/query/\(version)")
  }

  /// Update installed_plugins_v2.json manifest
  private func updatePluginManifest(version: String, pluginPath: URL) throws {
    let manifestURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/plugins/installed_plugins_v2.json")

    // Read existing manifest or create new one
    var manifest: [String: Any]
    if let data = try? Data(contentsOf: manifestURL),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      manifest = json
    } else {
      manifest = ["version": 2, "plugins": [:]]
    }

    // Get or create plugins dictionary
    var plugins = (manifest["plugins"] as? [String: Any]) ?? [:]

    // Create plugin entry
    let now = ISO8601DateFormatter().string(from: Date())
    let pluginEntry: [String: Any] = [
      "scope": "user",
      "installPath": pluginPath.path,
      "version": version,
      "installedAt": now,
      "lastUpdated": now,
      "isLocal": true
    ]

    // Update or add entry
    plugins["query@contextify"] = [pluginEntry]
    manifest["plugins"] = plugins

    // Write back to file
    let jsonData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try jsonData.write(to: manifestURL)

    log.info("[CLI-MANIFEST-UPDATE] version=\(version) path=\(pluginPath.path)")
  }

  /// Remove plugin entry from manifest
  private func removePluginFromManifest() {
    let manifestURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/plugins/installed_plugins_v2.json")

    guard let data = try? Data(contentsOf: manifestURL),
          var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          var plugins = manifest["plugins"] as? [String: Any] else {
      return
    }

    plugins.removeValue(forKey: "query@contextify")
    manifest["plugins"] = plugins

    if let jsonData = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
      try? jsonData.write(to: manifestURL)
      log.info("[CLI-MANIFEST-REMOVE] Removed query@contextify entry")
    }
  }

  // MARK: - Error Types

  enum InstallError: LocalizedError {
    case bundledShimMissing
    case bundledPluginMissing
    case permissionDenied
    case manifestWriteFailed

    var errorDescription: String? {
      switch self {
      case .bundledShimMissing:
        return "Bundled CLI shim not found in app bundle"
      case .bundledPluginMissing:
        return "Bundled plugin not found in app bundle"
      case .permissionDenied:
        return "Permission denied to install plugin (grant access in Settings)"
      case .manifestWriteFailed:
        return "Failed to update plugin manifest"
      }
    }
  }
}
