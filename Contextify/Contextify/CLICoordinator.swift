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
import AppKit  // For NSAlert

private let log = Logger(subsystem: "dev.contextify", category: "CLICoordinator")

// MARK: - QA Test Support
//
// DMGInstallDirOverride: UserDefaults key used by QA-13 (CLI Install E2E test) to redirect
// CLI installation to a temporary directory. This allows the test to:
// 1. Install the shim to a controlled location (/tmp/contextify-qa-bin/)
// 2. Validate the shim works without touching real system paths
// 3. Clean up without leaving artifacts in /opt/homebrew/bin or /usr/local/bin
//
// This is only checked in DMG builds (non-sandboxed). The key is set via:
//   defaults write sh.contextify.Contextify Contextify.QueryCLI.DMGInstallDirOverride "/tmp/test-dir"
//
// See: scripts/qa/tests/QA-13-cli-install-dmg.sh
private let kDMGInstallDirOverrideKey = "Contextify.QueryCLI.DMGInstallDirOverride"

/// Returns the QA test override path if set, nil otherwise.
/// Only applies to DMG builds - sandboxed builds ignore this.
private func dmgInstallDirOverride() -> URL? {
  guard !Sandbox.isSandboxed else { return nil }
  guard let override = UserDefaults.standard.string(forKey: kDMGInstallDirOverrideKey),
        !override.isEmpty else {
    return nil
  }
  log.info("[CLI-QA-OVERRIDE] Using test override path: \(override, privacy: .public)")
  return URL(fileURLWithPath: override)
}

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

  /// Reasons why CLI installation needs repair
  public enum RepairReason: Equatable {
    case claudeSkillMissing
    case codexSkillMissing
    case bothSkillsMissing
    case manifestMissing
  }

  /// CLI state - computed from filesystem, not stored separately
  public enum State: Equatable {
    case disabled
    case installing
    case enabled(version: String, pathWarning: Bool, repairIssue: RepairReason?)
    case enabledViaHomebrew(version: String)  // App Store: CLI installed via Homebrew
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

  /// Returns true if CLI is enabled (shim + plugin for DMG, or Homebrew CLI for App Store)
  public var isEnabled: Bool {
    switch state {
    case .enabled, .enabledViaHomebrew:
      return true
    default:
      return false
    }
  }

  /// Returns true if PATH warning should be shown
  /// Only relevant when enabled and shim is in ~/bin
  public var needsPathWarning: Bool {
    if case .enabled(_, let pathWarning, _) = state {
      return pathWarning
    }
    return false
  }

  /// Returns the repair reason if CLI needs repair, nil otherwise
  public var repairReason: RepairReason? {
    if case .enabled(_, _, let repairIssue) = state {
      return repairIssue
    }
    return nil
  }

  /// Returns true if CLI needs repair (partial installation)
  public var needsRepair: Bool {
    return repairReason != nil
  }

  /// Enable CLI - installs shim and plugin
  public func enable() async {
    isHandlingOperation = true
    defer { isHandlingOperation = false }

    state = .installing
    log.info("[CLI-ENABLE-START]")

    do {
      try await installShimAndPlugin()
      refreshState(force: true)  // Force refresh after operation completes
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
    refreshState(force: true)  // Force refresh after operation completes
    log.info("[CLI-DISABLE-COMPLETE]")
  }

  /// Repair CLI - reinstalls skills without full reinstall
  /// Used when skills are missing but shim exists
  public func repair() async {
    isHandlingOperation = true
    defer { isHandlingOperation = false }

    log.info("[CLI-REPAIR-START]")

    // Find the shim to run install-plugin
    guard let shimPath = Self.findInstalledShim() else {
      log.error("[CLI-REPAIR-FAILED] No shim found")
      state = .failed(error: "CLI shim not found - try Disable then Enable")
      return
    }

    // Run install-plugin to reinstall skills
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shimPath)
    process.arguments = ["install-plugin"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
      if process.terminationStatus == 0 {
        log.info("[CLI-REPAIR-SUCCESS] Skills reinstalled")
      } else {
        log.warning("[CLI-REPAIR] install-plugin exited with status \(process.terminationStatus)")
      }
    } catch {
      log.error("[CLI-REPAIR-FAILED] \(error.localizedDescription)")
      state = .failed(error: "Repair failed: \(error.localizedDescription)")
      return
    }

    refreshState(force: true)
    log.info("[CLI-REPAIR-COMPLETE]")
  }

  /// Check for installation/upgrades and install if needed
  /// Called on app launch (DMG only)
  public func checkAndUpgrade() async {
    // App Store builds: Skip auto-install - requires file picker for user to grant access
    // User must manually enable via Settings → CLI tab
    if Sandbox.isSandboxed {
      log.info("[CLI-AUTO-INSTALL-SKIP] App Store build - user must enable via Settings")
      return
    }

    // For DMG builds: auto-install on first launch IF writable paths exist (homebrew users)
    // For non-homebrew users: stay disabled, require manual enable

    let bundledVersion = readBundledVersion()

    switch state {
    case .disabled:
      // Only auto-install if we have writable system paths (homebrew users)
      let hasWritablePath = await hasWritableSystemPath()

      if hasWritablePath {
        // Homebrew user: silent auto-install
        log.info("[CLI-AUTO-INSTALL-START] version=\(bundledVersion)")
        isHandlingOperation = true
        defer { isHandlingOperation = false }

        state = .installing
        do {
          try await installShimAndPlugin()
          refreshState(force: true)  // Force refresh after operation completes
          log.info("[CLI-AUTO-INSTALL-SUCCESS] version=\(bundledVersion)")
        } catch {
          state = .failed(error: error.localizedDescription)
          log.error("[CLI-AUTO-INSTALL-FAILED] error=\(error.localizedDescription)")
        }
      } else {
        // Non-homebrew user: stay disabled, require manual enable
        log.info("[CLI-AUTO-INSTALL-SKIP] No writable paths, requires manual enable")
      }

    case .enabled(let installedVersion, _, _):
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
        refreshState(force: true)  // Force refresh after operation completes
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
  /// Throttled to avoid expensive checks unless force=true
  public func refreshState(force: Bool = false) {
    let now = Date()
    if !force, let lastCheck = lastCheckTime,
       now.timeIntervalSince(lastCheck) < checkThrottleDuration {
      log.debug("[CLI-REFRESH] throttled, skipping")
      return
    }

    log.info("[CLI-REFRESH] checking... sandboxed=\(Sandbox.isSandboxed)")
    let oldState = state
    state = Self.computeState()
    log.info("[CLI-REFRESH] oldState=\(String(describing: oldState)) newState=\(String(describing: self.state))")
    if state != oldState {
      log.info("[CLI-REFRESH] state changed to \(String(describing: self.state))")
    }
    lastCheckTime = now
  }

  // MARK: - Private Implementation

  private static func computeState() -> State {
    log.info("[CLI-COMPUTE-STATE] Starting state computation...")

    // App Store builds: Cannot detect Homebrew CLI due to sandbox restrictions
    // Just show install instructions - user verifies in terminal
    if Sandbox.isSandboxed {
      log.info("[CLI-COMPUTE-STATE] Sandboxed build, returning disabled")
      return .disabled
    }

    // DMG builds: Check for shim + plugin installation
    guard let shimPath = findInstalledShim() else {
      log.info("[CLI-COMPUTE-STATE] No shim found, returning disabled")
      return .disabled
    }
    log.info("[CLI-COMPUTE-STATE] Shim found at: \(shimPath, privacy: .public)")

    // ============================================================================
    // Check installation components and determine repair state
    // TODO: #CLI-DOCTOR - Replace with `contextify-query doctor --json` integration
    // See: build/notes/todo-support/LINUX-TOTAL-RECALL-spec.md
    // ============================================================================

    let fileManager = FileManager.default
    let homeDir = fileManager.homeDirectoryForCurrentUser

    // Check manifest for version (may be missing in partial install)
    let pluginVersion = readInstalledPluginVersion()
    let manifestMissing = (pluginVersion == nil)
    log.info("[CLI-COMPUTE-STATE] Manifest: \(manifestMissing ? "MISSING" : pluginVersion!, privacy: .public)")

    // Check skill files
    let claudeSkillPath = homeDir.appendingPathComponent(".claude/skills/total-recall/SKILL.md").path
    let codexSkillPath = homeDir.appendingPathComponent(".codex/skills/total-recall/SKILL.md").path

    let claudeSkillExists = fileManager.fileExists(atPath: claudeSkillPath)
    let codexSkillExists = fileManager.fileExists(atPath: codexSkillPath)

    log.info("[CLI-COMPUTE-STATE] Skills: claude=\(claudeSkillExists) codex=\(codexSkillExists)")

    // Determine repair reason (if any)
    let repairIssue: RepairReason?
    if manifestMissing && !claudeSkillExists && !codexSkillExists {
      // Everything broken except shim - treat as disabled
      log.warning("[CLI-COMPUTE-STATE] Manifest and all skills missing, returning disabled")
      return .disabled
    } else if manifestMissing {
      // Manifest missing but at least one skill works
      repairIssue = .manifestMissing
      log.warning("[CLI-COMPUTE-STATE] Manifest missing, needs repair")
    } else if !claudeSkillExists && !codexSkillExists {
      // Both skills missing
      repairIssue = .bothSkillsMissing
      log.warning("[CLI-COMPUTE-STATE] Both skills missing, needs repair")
    } else if !claudeSkillExists {
      repairIssue = .claudeSkillMissing
      log.warning("[CLI-COMPUTE-STATE] Claude skill missing, needs repair")
    } else if !codexSkillExists {
      repairIssue = .codexSkillMissing
      log.warning("[CLI-COMPUTE-STATE] Codex skill missing, needs repair")
    } else {
      repairIssue = nil
      log.info("[CLI-COMPUTE-STATE] All components present")
    }

    // Check if shim's parent directory is on PATH
    // Note: Homebrew paths work in user shells even if not in GUI app's PATH
    let shimDir = URL(fileURLWithPath: shimPath).deletingLastPathComponent().path
    let isHomebrewPath = shimDir == "/opt/homebrew/bin" || shimDir == "/usr/local/bin"
    let pathWarning = !isHomebrewPath && !isDirectoryOnPath(shimDir)

    // Use placeholder version if manifest is missing
    let version = pluginVersion ?? "unknown"
    return .enabled(version: version, pathWarning: pathWarning, repairIssue: repairIssue)
  }

  /// Find contextify-query at known Homebrew paths
  /// Note: Sandboxed apps cannot run `which`, so we check paths directly
  private static func findHomebrewCLI() -> String? {
    let homebrewPaths = [
      "/opt/homebrew/bin/contextify-query",  // Apple Silicon Homebrew
      "/usr/local/bin/contextify-query"      // Intel Homebrew
    ]

    for path in homebrewPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        log.debug("[CLI] Found Homebrew CLI at \(path, privacy: .public)")
        return path
      }
    }

    log.debug("[CLI] No Homebrew CLI found at standard paths")
    return nil
  }

  /// Read version from CLI binary
  /// Note: Sandboxed apps cannot spawn processes, so we return "installed" as placeholder
  /// The actual version can be checked by running `contextify-query --version` in terminal
  private static func readVersionFromCLI(at path: String) -> String? {
    // In sandbox, we can't run the CLI to get version
    // Just confirm it exists and return a placeholder
    if Sandbox.isSandboxed {
      log.debug("[CLI] Sandboxed - returning 'installed' as version placeholder")
      return "installed"
    }

    // Non-sandboxed: actually run the CLI
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }

    guard process.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

    // Parse version from output (e.g., "contextify-query 0.8.5" -> "0.8.5")
    if let output = output {
      let parts = output.split(separator: " ")
      if parts.count >= 2 {
        return String(parts[1])
      }
    }

    return output
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
    guard let bundledShimURL = Bundle.main.url(forResource: "contextify-query/shim/contextify-query-shim", withExtension: nil) else {
      throw InstallError.bundledShimMissing
    }
    try fileManager.copyItem(at: bundledShimURL, to: tempShimURL)

    // 2. Make shim executable
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempShimURL.path)

    // 3. Copy plugin to temp location
    let tempPluginURL = tempDir.appendingPathComponent("contextify-plugin-\(UUID().uuidString)")
    guard let bundledPluginURL = Bundle.main.resourceURL?
      .appendingPathComponent("contextify-query/claude-plugin") else {
      throw InstallError.bundledPluginMissing
    }
    try fileManager.copyItem(at: bundledPluginURL, to: tempPluginURL)

    // 4. Determine final locations (may show dialog/picker)
    let (finalShimURL, requiresAdmin) = try await determineShimPath()
    let finalPluginURL = pluginCachePath()

    // 5. For sandboxed builds, start security-scoped access to shim directory
    var accessStarted = false
    let shimParent = finalShimURL.deletingLastPathComponent()
    if Sandbox.isSandboxed {
      accessStarted = shimParent.startAccessingSecurityScopedResource()
      if !accessStarted {
        log.error("[CLI-INSTALL] Failed to start security-scoped access to \(shimParent.path, privacy: .public)")
        throw InstallError.permissionDenied
      }
      log.info("[CLI-INSTALL] Started security-scoped access to \(shimParent.path, privacy: .public)")
    }

    defer {
      if accessStarted {
        shimParent.stopAccessingSecurityScopedResource()
        log.info("[CLI-INSTALL] Stopped security-scoped access")
      }
    }

    // 6. Create parent directories if needed
    if !fileManager.fileExists(atPath: shimParent.path) {
      try fileManager.createDirectory(at: shimParent, withIntermediateDirectories: true)
    }
    let pluginParent = finalPluginURL.deletingLastPathComponent()
    if !fileManager.fileExists(atPath: pluginParent.path) {
      try fileManager.createDirectory(at: pluginParent, withIntermediateDirectories: true)
    }

    // 7. Install shim
    if Sandbox.isSandboxed {
      // App Store: Write shell script shim (binary won't pass Gatekeeper)
      let shellScript = """
#!/bin/bash
# Contextify CLI shim - finds and runs contextify-query from Contextify.app

# 1. Production: /Applications (App Store install)
CLI="/Applications/Contextify.app/Contents/MacOS/contextify-query"
[ -x "$CLI" ] && exec "$CLI" "$@"

# 2. Dev: running Contextify process (works with any build location)
RUNNING=$(ps -xo comm= | grep -m1 '/Contextify.app/Contents/MacOS/Contextify$' | sed 's|/Contents/MacOS/Contextify$||')
if [ -n "$RUNNING" ]; then
  CLI="$RUNNING/Contents/MacOS/contextify-query"
  [ -x "$CLI" ] && exec "$CLI" "$@"
fi

# 3. Fallback: Spotlight search
for APP in $(mdfind "kMDItemCFBundleIdentifier == 'sh.contextify.Contextify'" 2>/dev/null); do
  CLI="$APP/Contents/MacOS/contextify-query"
  [ -x "$CLI" ] && exec "$CLI" "$@"
done

echo "Error: Contextify.app with CLI not found" >&2
exit 1
"""
      if fileManager.fileExists(atPath: finalShimURL.path) {
        try fileManager.removeItem(at: finalShimURL)
      }
      try shellScript.write(to: finalShimURL, atomically: true, encoding: .utf8)
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: finalShimURL.path)
      // Clean up unused temp shim
      try? fileManager.removeItem(at: tempShimURL)
      log.info("[CLI-INSTALL] Wrote shell script shim for App Store build")
    } else if requiresAdmin {
      // DMG with admin: Use osascript with admin privileges
      try await installWithAdmin(shimSource: tempShimURL, destination: finalShimURL)
      // Clean up temp file manually (osascript created the target)
      try? fileManager.removeItem(at: tempShimURL)
    } else {
      // DMG without admin: Regular file move (atomic)
      if fileManager.fileExists(atPath: finalShimURL.path) {
        try fileManager.removeItem(at: finalShimURL)
      }
      try fileManager.moveItem(at: tempShimURL, to: finalShimURL)
    }

    // 8. Install plugin (always regular move)
    if fileManager.fileExists(atPath: finalPluginURL.path) {
      try fileManager.removeItem(at: finalPluginURL)
    }
    try fileManager.moveItem(at: tempPluginURL, to: finalPluginURL)

    // 9. Update plugin manifest
    try updatePluginManifest(version: readBundledVersion(), pluginPath: finalPluginURL)

    // 10. For DMG builds: run install-plugin to install user skill
    // This installs /total-recall to ~/.claude/skills/total-recall/
    if !Sandbox.isSandboxed {
      log.info("[CLI-INSTALL] Running install-plugin to install user skill...")
      let process = Process()
      process.executableURL = finalShimURL
      process.arguments = ["install-plugin"]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
          log.info("[CLI-INSTALL] User skill installed successfully")
        } else {
          log.warning("[CLI-INSTALL] install-plugin exited with status \(process.terminationStatus)")
        }
      } catch {
        log.warning("[CLI-INSTALL] Failed to run install-plugin: \(error.localizedDescription)")
        // Non-fatal: shim and plugin are installed, user can run manually
      }
    }

    log.info("[CLI-INSTALL-SUCCESS] shim=\(finalShimURL.path, privacy: .public) plugin=\(finalPluginURL.path, privacy: .public)")
  }

  private func upgradePlugin(to version: String) async throws {
    log.info("[CLI-UPGRADE] Upgrading to version \(version)...")
    // Upgrade is same as install (overwrites existing)
    try await installShimAndPlugin()
  }

  private func removeShimAndPlugin() {
    log.info("[CLI-REMOVE] Removing shim and plugin...")
    let fileManager = FileManager.default

    // For sandboxed builds: use stored bookmark location
    if Sandbox.isSandboxed {
      if let storedURL = resolveStoredCLIBookmark() {
        let shimPath = storedURL.appendingPathComponent("contextify-query")

        // Start security-scoped access
        guard storedURL.startAccessingSecurityScopedResource() else {
          log.error("[CLI-REMOVE] Failed to access stored location: \(storedURL.path, privacy: .public)")
          // Clear bookmark anyway since we can't access it
          HUDPreferences.clearCLIInstallLocation()
          return
        }

        defer {
          storedURL.stopAccessingSecurityScopedResource()
        }

        if fileManager.fileExists(atPath: shimPath.path) {
          try? fileManager.removeItem(at: shimPath)
          log.info("[CLI-REMOVE] Removed shim at \(shimPath.path, privacy: .public)")
        }

        // Clear the stored bookmark
        HUDPreferences.clearCLIInstallLocation()
      } else {
        log.warning("[CLI-REMOVE] No stored bookmark for sandboxed build")
      }
    } else {
      // QA test override: check override directory first (see kDMGInstallDirOverrideKey)
      if let overrideDir = dmgInstallDirOverride() {
        let overridePath = overrideDir.appendingPathComponent("contextify-query").path
        if fileManager.fileExists(atPath: overridePath) {
          try? fileManager.removeItem(atPath: overridePath)
          log.info("[CLI-REMOVE] Removed shim at override path \(overridePath, privacy: .public)")
        }
      }

      // DMG: Remove shim from all possible locations
      let possibleShimPaths = [
        "/opt/homebrew/bin/contextify-query",
        "/usr/local/bin/contextify-query",
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("bin/contextify-query").path,
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/contextify-query").path
      ]

      for path in possibleShimPaths {
        if fileManager.fileExists(atPath: path) {
          try? fileManager.removeItem(atPath: path)
          log.info("[CLI-REMOVE] Removed shim at \(path, privacy: .public)")
        }
      }
    }

    // Remove plugin directory (same for both builds - we have access to ~/.claude/)
    let pluginDir = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/plugins/cache/contextify")
    if fileManager.fileExists(atPath: pluginDir.path) {
      try? fileManager.removeItem(at: pluginDir)
      log.info("[CLI-REMOVE] Removed plugin at \(pluginDir.path, privacy: .public)")
    }

    // Remove skill directories
    let claudeSkillDir = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/skills/total-recall")
    if fileManager.fileExists(atPath: claudeSkillDir.path) {
      try? fileManager.removeItem(at: claudeSkillDir)
      log.info("[CLI-REMOVE] Removed Claude skill at \(claudeSkillDir.path, privacy: .public)")
    }

    let codexSkillDir = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/skills/total-recall")
    if fileManager.fileExists(atPath: codexSkillDir.path) {
      try? fileManager.removeItem(at: codexSkillDir)
      log.info("[CLI-REMOVE] Removed Codex skill at \(codexSkillDir.path, privacy: .public)")
    }

    // Update manifest to remove plugin entry
    removePluginFromManifest()
  }

  // MARK: - Admin Install Support

  private enum AdminInstallChoice {
    case install
    case cancel
  }

  @MainActor
  private func showAdminInstallDialog() async -> AdminInstallChoice {
    let alert = NSAlert()
    alert.messageText = "Administrator Access Required"
    alert.informativeText = """
      Contextify will request administrator privileges to install the 'contextify-query' command to /usr/local/bin.

      The request to make changes will come from 'osascript'. This one-time access is used solely to add the contextify-query command to your system path.
      """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Install")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()

    switch response {
    case .alertFirstButtonReturn:
      log.info("[CLI-ADMIN-DIALOG-APPROVED]")
      return .install
    default:
      log.info("[CLI-ADMIN-DIALOG-CANCELLED]")
      return .cancel
    }
  }

  private func installWithAdmin(shimSource: URL, destination: URL) async throws {
    log.info("[CLI-ADMIN-INSTALL-START] destination=\(destination.path)")

    // Use cp to copy the actual file (not create symlink to temp file)
    // cp -f will overwrite existing regular files; chmod to ensure it's executable
    let script = """
      do shell script "cp -f '\(shimSource.path)' '\(destination.path)' && chmod 755 '\(destination.path)'" with administrator privileges
    """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"

      // Detect user cancellation by exit code or error message
      // osascript returns 1 with "User canceled" message when user cancels password prompt
      let userCancelled = process.terminationStatus == 128 ||
                          process.terminationStatus == -128 ||
                          errorMessage.lowercased().contains("user cancel")

      if userCancelled {
        log.info("[CLI-ADMIN-INSTALL-CANCELLED]")
        throw InstallError.userCancelled
      }

      log.error("[CLI-ADMIN-INSTALL-FAILED] error=\(errorMessage)")
      throw InstallError.adminInstallFailed(message: errorMessage)
    }

    log.info("[CLI-ADMIN-INSTALL-SUCCESS] destination=\(destination.path)")
  }

  // MARK: - Helper Methods

  /// Check if any writable system paths exist (homebrew detection)
  private func hasWritableSystemPath() async -> Bool {
    let fileManager = FileManager.default
    let systemPaths = [
      "/opt/homebrew/bin",      // Apple Silicon homebrew
      "/usr/local/bin"          // Intel homebrew (if user-owned)
    ]

    for path in systemPaths {
      if fileManager.isWritableFile(atPath: path) {
        return true
      }
    }

    return false
  }

  /// Find installed shim in common locations
  private static func findInstalledShim() -> String? {
    let fileManager = FileManager.default

    // For sandboxed builds: check stored bookmark location first
    if Sandbox.isSandboxed {
      if let stored = HUDPreferences.getCLIInstallLocation() {
        let shimPath = URL(fileURLWithPath: stored.path).appendingPathComponent("contextify-query").path
        // Note: We can't check fileExists without security-scoped access,
        // but if we have a stored bookmark, assume it's installed there
        // The actual existence will be verified when we try to use it
        return shimPath
      }
      // No stored bookmark = not installed in sandboxed build
      return nil
    }

    // QA test override: check override directory first (see kDMGInstallDirOverrideKey)
    if let overrideDir = dmgInstallDirOverride() {
      let overridePath = overrideDir.appendingPathComponent("contextify-query").path
      if fileManager.fileExists(atPath: overridePath) {
        return overridePath
      }
    }

    // DMG: check all possible locations
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

  /// Check if a directory is on the system PATH
  private static func isDirectoryOnPath(_ dir: String) -> Bool {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    // Normalize the directory path (remove trailing slash) for comparison
    let normalizedDir = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
    return path.split(separator: ":").contains { String($0) == normalizedDir }
  }

  /// Determine where to install shim (DMG: homebrew/local/admin, App Store: user-selected folder)
  /// Returns tuple: (url: final install path, requiresAdmin: whether to use osascript)
  private func determineShimPath() async throws -> (url: URL, requiresAdmin: Bool) {
    let fileManager = FileManager.default

    // App Store: Use stored bookmark or show file picker
    if Sandbox.isSandboxed {
      // Check for existing bookmark first
      if let existingURL = resolveStoredCLIBookmark() {
        log.info("[CLI-APPSTORE] Using stored location: \(existingURL.path, privacy: .public)")
        return (url: existingURL.appendingPathComponent("contextify-query"), requiresAdmin: false)
      }

      // No stored bookmark - show file picker
      let (selectedDir, bookmark) = try await showInstallLocationPicker()

      // Store for future use (upgrades)
      HUDPreferences.setCLIInstallLocation(selectedDir, bookmarkData: bookmark)

      return (url: selectedDir.appendingPathComponent("contextify-query"), requiresAdmin: false)
    }

    // QA test override: install to specified directory (see kDMGInstallDirOverrideKey)
    if let overrideDir = dmgInstallDirOverride() {
      return (
        url: overrideDir.appendingPathComponent("contextify-query"),
        requiresAdmin: false
      )
    }

    // DMG: Try writable system paths (homebrew-enabled systems)
    // Check WRITABILITY, not just existence - /usr/local/bin exists but may be root-owned
    let systemPaths = [
      "/opt/homebrew/bin",      // Apple Silicon homebrew
      "/usr/local/bin"          // Intel homebrew (if user-owned)
    ]

    for path in systemPaths {
      if fileManager.isWritableFile(atPath: path) {
        return (
          url: URL(fileURLWithPath: "\(path)/contextify-query"),
          requiresAdmin: false
        )
      }
    }

    // No writable system paths - request admin install
    log.info("[CLI-NO-WRITABLE-PATHS] Requesting admin install")

    let choice = await showAdminInstallDialog()

    switch choice {
    case .install:
      return (
        url: URL(fileURLWithPath: "/usr/local/bin/contextify-query"),
        requiresAdmin: true
      )
    case .cancel:
      throw InstallError.userCancelled
    }
  }

  // MARK: - App Store File Picker

  /// Resolve stored bookmark to get access to CLI install location
  private func resolveStoredCLIBookmark() -> URL? {
    HUDPreferences.resolveCLIInstallBookmark()
  }

  /// Show file picker for App Store builds to choose CLI install location
  /// Returns (directory URL, bookmark data) on success, throws on cancel or error
  @MainActor
  private func showInstallLocationPicker() async throws -> (url: URL, bookmark: Data) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true  // User can create ~/bin if it doesn't exist
    panel.prompt = "Open"
    panel.message = "Select where to install contextify-query"

    // Start in home directory, prefer ~/bin if it exists
    let homeURL = FileManager.default.homeDirectoryForCurrentUser
    let suggestedBin = homeURL.appendingPathComponent("bin")

    if FileManager.default.fileExists(atPath: suggestedBin.path) {
      panel.directoryURL = suggestedBin
    } else {
      panel.directoryURL = homeURL
    }

    log.info("[CLI-PICKER] Showing file picker, starting at: \(panel.directoryURL?.path ?? "nil", privacy: .public)")

    let response = panel.runModal()
    guard response == .OK, let selectedURL = panel.url else {
      log.info("[CLI-PICKER] User cancelled")
      throw InstallError.userCancelled
    }

    log.info("[CLI-PICKER] User selected: \(selectedURL.path, privacy: .public)")

    // Create security-scoped bookmark for persistent access
    let bookmarkData = try selectedURL.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    return (url: selectedURL, bookmark: bookmarkData)
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
    case adminInstallFailed(message: String)
    case userCancelled

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
      case .adminInstallFailed(let message):
        return "Admin installation failed: \(message)"
      case .userCancelled:
        return "Installation cancelled"
      }
    }
  }
}
