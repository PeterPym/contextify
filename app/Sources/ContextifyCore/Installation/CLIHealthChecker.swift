import Foundation

/// Shared health checker for CLI installation state.
/// Used by both CLICoordinator (app) and contextify-query doctor (CLI).
public struct CLIHealthChecker: Sendable {

  // MARK: - Types

  /// Overall health status of the CLI installation
  public enum HealthStatus: String, Codable, Sendable {
    case healthy       // All components present and valid
    case degraded      // Some issues but core functionality works
    case broken        // Critical components missing
    case unconfigured  // Nothing installed
  }

  /// Severity of an issue
  public enum Severity: String, Codable, Sendable {
    case error    // Critical - blocks functionality
    case warning  // Non-critical - functionality may be limited
  }

  /// A specific issue found during health check
  public struct Issue: Codable, Sendable, Equatable {
    public let component: String
    public let severity: Severity
    public let code: String
    public let message: String
    public let fix: String?

    public init(component: String, severity: Severity, code: String, message: String, fix: String? = nil) {
      self.component = component
      self.severity = severity
      self.code = code
      self.message = message
      self.fix = fix
    }
  }

  /// Status of the shim binary
  public struct ShimStatus: Codable, Sendable {
    public let installed: Bool
    public let path: String?
    public let onPath: Bool

    public init(installed: Bool, path: String?, onPath: Bool) {
      self.installed = installed
      self.path = path
      self.onPath = onPath
    }
  }

  /// Status of the plugin manifest
  public struct ManifestStatus: Codable, Sendable {
    public let present: Bool
    public let version: String?

    public init(present: Bool, version: String?) {
      self.present = present
      self.version = version
    }
  }

  /// Status of skill files
  public struct SkillsStatus: Codable, Sendable {
    public let claudeSkillPresent: Bool
    public let codexSkillPresent: Bool
    public let claudeSkillPath: String?
    public let codexSkillPath: String?

    public init(claudeSkillPresent: Bool, codexSkillPresent: Bool,
                claudeSkillPath: String?, codexSkillPath: String?) {
      self.claudeSkillPresent = claudeSkillPresent
      self.codexSkillPresent = codexSkillPresent
      self.claudeSkillPath = claudeSkillPath
      self.codexSkillPath = codexSkillPath
    }
  }

  /// All component statuses
  public struct Components: Codable, Sendable {
    public let shim: ShimStatus
    public let manifest: ManifestStatus
    public let skills: SkillsStatus

    public init(shim: ShimStatus, manifest: ManifestStatus, skills: SkillsStatus) {
      self.shim = shim
      self.manifest = manifest
      self.skills = skills
    }
  }

  /// Complete health report
  public struct HealthReport: Codable, Sendable {
    public let timestamp: Date
    public let platform: String
    public let overall: HealthStatus
    public let components: Components
    public let issues: [Issue]

    public init(timestamp: Date, platform: String, overall: HealthStatus,
                components: Components, issues: [Issue]) {
      self.timestamp = timestamp
      self.platform = platform
      self.overall = overall
      self.components = components
      self.issues = issues
    }
  }

  // MARK: - Configuration

  /// Known paths where shim may be installed (macOS)
  public static let knownShimPaths: [String] = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      "/opt/homebrew/bin/contextify-query",
      "/usr/local/bin/contextify-query",
      home.appendingPathComponent("bin/contextify-query").path,
      home.appendingPathComponent(".local/bin/contextify-query").path
    ]
  }()

  /// Homebrew paths that are assumed to be on PATH in user shells
  public static let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

  // MARK: - Main Entry Point

  /// Perform a complete health check of the CLI installation
  public static func checkHealth() -> HealthReport {
    #if os(macOS)
    return checkHealthMacOS()
    #else
    return checkHealthLinux()
    #endif
  }

  // MARK: - macOS Health Check

  #if os(macOS)
  private static func checkHealthMacOS() -> HealthReport {
    let fileManager = FileManager.default
    let homeDir = fileManager.homeDirectoryForCurrentUser
    var issues: [Issue] = []

    // Check shim
    let shimStatus = checkShimMacOS(fileManager: fileManager)

    // Check manifest (may return an issue for unreadable/malformed)
    let (manifestStatus, manifestIssue) = checkManifestMacOS(homeDir: homeDir)
    if let issue = manifestIssue {
      issues.append(issue)
    }

    // Check skills
    let skillsStatus = checkSkills(homeDir: homeDir, fileManager: fileManager)

    // Build issues list
    if !shimStatus.installed {
      issues.append(Issue(
        component: "shim",
        severity: .error,
        code: "SHIM_NOT_FOUND",
        message: "contextify-query binary not found",
        fix: "Run: contextify-query install-plugin"
      ))
    } else if !shimStatus.onPath {
      issues.append(Issue(
        component: "shim",
        severity: .warning,
        code: "SHIM_NOT_ON_PATH",
        message: "contextify-query not on PATH: \(shimStatus.path ?? "unknown")",
        fix: "Add \(URL(fileURLWithPath: shimStatus.path ?? "").deletingLastPathComponent().path) to your PATH"
      ))
    }

    if !manifestStatus.present {
      issues.append(Issue(
        component: "manifest",
        severity: .warning,
        code: "MANIFEST_MISSING",
        message: "Plugin manifest not found",
        fix: "Run: contextify-query install-plugin"
      ))
    }

    if !skillsStatus.claudeSkillPresent {
      issues.append(Issue(
        component: "skills",
        severity: .warning,
        code: "CLAUDE_SKILL_MISSING",
        message: "Claude Code skill not found",
        fix: "Run: contextify-query install-plugin"
      ))
    }

    if !skillsStatus.codexSkillPresent {
      issues.append(Issue(
        component: "skills",
        severity: .warning,
        code: "CODEX_SKILL_MISSING",
        message: "Codex CLI skill not found",
        fix: "Run: contextify-query install-plugin"
      ))
    }

    // Determine overall status
    let overall = determineOverallStatus(
      shimInstalled: shimStatus.installed,
      manifestPresent: manifestStatus.present,
      claudeSkillPresent: skillsStatus.claudeSkillPresent,
      codexSkillPresent: skillsStatus.codexSkillPresent,
      issues: issues
    )

    let components = Components(shim: shimStatus, manifest: manifestStatus, skills: skillsStatus)

    return HealthReport(
      timestamp: Date(),
      platform: "darwin",
      overall: overall,
      components: components,
      issues: issues
    )
  }

  private static func checkShimMacOS(fileManager: FileManager) -> ShimStatus {
    for path in knownShimPaths {
      if fileManager.fileExists(atPath: path) {
        let shimDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let onPath = isDirectoryOnPath(shimDir) || homebrewPaths.contains(shimDir)
        return ShimStatus(installed: true, path: path, onPath: onPath)
      }
    }
    return ShimStatus(installed: false, path: nil, onPath: false)
  }

  /// Result of reading plugin manifest
  enum ManifestReadResult: Equatable {
    case notFound
    case unreadable
    case malformed
    case missingPluginEntry  // File exists and is valid JSON, but no query@contextify entry
    case success(version: String)
  }

  private static func checkManifestMacOS(homeDir: URL) -> (ManifestStatus, Issue?) {
    let v1ManifestURL = homeDir.appendingPathComponent(".claude/plugins/installed_plugins.json")
    let v2ManifestURL = homeDir.appendingPathComponent(".claude/plugins/installed_plugins_v2.json")

    // Check both manifests - don't short-circuit on v1 errors
    let v1Result = readPluginVersion(at: v1ManifestURL)
    let v2Result = readPluginVersion(at: v2ManifestURL)

    // Priority: prefer v1 success, then v2 success, then handle errors
    // This ensures we find the plugin entry if it exists in either manifest

    // 1. If v1 has our entry, use it (v1 is authoritative when present)
    if case .success(let version) = v1Result {
      return (ManifestStatus(present: true, version: version), nil)
    }

    // 2. If v2 has our entry, use it (fallback to v2)
    if case .success(let version) = v2Result {
      return (ManifestStatus(present: true, version: version), nil)
    }

    // 3. Neither has our entry - determine why
    // Check for unreadable/malformed files (prefer reporting v1 issues over v2)
    if case .unreadable = v1Result {
      return (ManifestStatus(present: false, version: nil),
              Issue(component: "manifest", severity: .warning, code: "MANIFEST_UNREADABLE",
                    message: "Plugin manifest exists but cannot be read",
                    fix: "Check permissions on \(v1ManifestURL.path)"))
    }
    if case .malformed = v1Result {
      return (ManifestStatus(present: false, version: nil),
              Issue(component: "manifest", severity: .warning, code: "MANIFEST_MALFORMED",
                    message: "Plugin manifest is corrupted or invalid JSON",
                    fix: "Run: contextify-query install-plugin"))
    }
    if case .unreadable = v2Result {
      return (ManifestStatus(present: false, version: nil),
              Issue(component: "manifest", severity: .warning, code: "MANIFEST_UNREADABLE",
                    message: "Plugin manifest exists but cannot be read",
                    fix: "Check permissions on \(v2ManifestURL.path)"))
    }
    if case .malformed = v2Result {
      return (ManifestStatus(present: false, version: nil),
              Issue(component: "manifest", severity: .warning, code: "MANIFEST_MALFORMED",
                    message: "Plugin manifest is corrupted or invalid JSON",
                    fix: "Run: contextify-query install-plugin"))
    }

    // 4. If either file exists but our entry is missing
    if case .missingPluginEntry = v1Result {
      return (ManifestStatus(present: false, version: nil),
              Issue(component: "manifest", severity: .warning, code: "MANIFEST_ENTRY_MISSING",
                    message: "Plugin manifest exists but Contextify is not registered",
                    fix: "Run: contextify-query install-plugin"))
    }
    if case .missingPluginEntry = v2Result {
      return (ManifestStatus(present: false, version: nil),
              Issue(component: "manifest", severity: .warning, code: "MANIFEST_ENTRY_MISSING",
                    message: "Plugin manifest exists but Contextify is not registered",
                    fix: "Run: contextify-query install-plugin"))
    }

    // 5. Both files not found - no manifest at all
    return (ManifestStatus(present: false, version: nil), nil)
  }

  static func readPluginVersion(at url: URL) -> ManifestReadResult {
    let fileManager = FileManager.default

    // Check if file exists
    guard fileManager.fileExists(atPath: url.path) else {
      return .notFound
    }

    // Try to read file
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      return .unreadable
    }

    // Try to parse JSON
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return .malformed
    }

    // Extract version - if our plugin entry is missing, that's a distinct state
    guard let plugins = json["plugins"] as? [String: Any],
          let pluginEntries = plugins["query@contextify"] as? [[String: Any]],
          let firstEntry = pluginEntries.first,
          let version = firstEntry["version"] as? String else {
      return .missingPluginEntry
    }

    return .success(version: version)
  }
  #endif

  // MARK: - Linux Health Check

  #if !os(macOS)
  private static func checkHealthLinux() -> HealthReport {
    let fileManager = FileManager.default
    let homeDir = fileManager.homeDirectoryForCurrentUser
    var issues: [Issue] = []

    // Linux: shim/manifest not applicable (binary is on PATH directly, no manifest)
    // installed=true means "this code is running from the CLI binary" - we don't verify
    // the binary location or PATH, just that the binary is executing (which it must be).
    // present=false for manifest since there's no manifest on Linux.
    let shimStatus = ShimStatus(installed: true, path: nil, onPath: true)
    let manifestStatus = ManifestStatus(present: false, version: nil)

    // Check skills
    let skillsStatus = checkSkills(homeDir: homeDir, fileManager: fileManager)

    if !skillsStatus.claudeSkillPresent {
      issues.append(Issue(
        component: "skills",
        severity: .warning,
        code: "CLAUDE_SKILL_MISSING",
        message: "Claude Code skill not found",
        fix: "Run: contextify-query install-plugin"
      ))
    }

    if !skillsStatus.codexSkillPresent {
      issues.append(Issue(
        component: "skills",
        severity: .warning,
        code: "CODEX_SKILL_MISSING",
        message: "Codex CLI skill not found",
        fix: "Run: contextify-query install-plugin"
      ))
    }

    // Determine overall status (Linux: skills-focused)
    let overall: HealthStatus
    if skillsStatus.claudeSkillPresent && skillsStatus.codexSkillPresent {
      overall = .healthy
    } else if skillsStatus.claudeSkillPresent || skillsStatus.codexSkillPresent {
      overall = .degraded
    } else {
      overall = .unconfigured
    }

    let components = Components(shim: shimStatus, manifest: manifestStatus, skills: skillsStatus)

    return HealthReport(
      timestamp: Date(),
      platform: "linux",
      overall: overall,
      components: components,
      issues: issues
    )
  }
  #endif

  // MARK: - Shared Checks

  private static func checkSkills(homeDir: URL, fileManager: FileManager) -> SkillsStatus {
    let claudeSkillPath = homeDir.appendingPathComponent(".claude/skills/total-recall/SKILL.md")
    let codexSkillPath = homeDir.appendingPathComponent(".codex/skills/total-recall/SKILL.md")

    let claudeExists = fileManager.fileExists(atPath: claudeSkillPath.path)
    let codexExists = fileManager.fileExists(atPath: codexSkillPath.path)

    return SkillsStatus(
      claudeSkillPresent: claudeExists,
      codexSkillPresent: codexExists,
      claudeSkillPath: claudeExists ? claudeSkillPath.path : nil,
      codexSkillPath: codexExists ? codexSkillPath.path : nil
    )
  }

  private static func isDirectoryOnPath(_ dir: String) -> Bool {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let normalizedDir = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
    return path.split(separator: ":").contains { entry in
      let entryStr = String(entry)
      let normalizedEntry = entryStr.hasSuffix("/") ? String(entryStr.dropLast()) : entryStr
      return normalizedEntry == normalizedDir
    }
  }

  private static func determineOverallStatus(
    shimInstalled: Bool,
    manifestPresent: Bool,
    claudeSkillPresent: Bool,
    codexSkillPresent: Bool,
    issues: [Issue]
  ) -> HealthStatus {
    // No shim = unconfigured (nothing installed)
    if !shimInstalled {
      return .unconfigured
    }

    // Shim exists but everything else missing = broken (partial/corrupt install)
    // This is different from unconfigured: the user attempted to install but something went wrong
    if !manifestPresent && !claudeSkillPresent && !codexSkillPresent {
      return .broken
    }

    // Check for any errors (critical issues)
    let hasErrors = issues.contains { $0.severity == .error }
    if hasErrors {
      return .broken
    }

    // Check for warnings (non-critical issues)
    let hasWarnings = issues.contains { $0.severity == .warning }
    if hasWarnings {
      return .degraded
    }

    return .healthy
  }
}
