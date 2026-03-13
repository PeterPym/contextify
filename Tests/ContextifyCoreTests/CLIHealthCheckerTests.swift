import XCTest
@testable import ContextifyCore

/// Tests for CLIHealthChecker.
///
/// These tests verify the health checking logic for CLI installation state.
/// Most tests run against the actual filesystem state since CLIHealthChecker
/// uses standard system paths.
final class CLIHealthCheckerTests: XCTestCase {

  // MARK: - API Shape Tests

  func testHealthReportHasRequiredFields() {
    // Verify the HealthReport has all expected fields
    let report = CLIHealthChecker.checkHealth()

    // Timestamp should be recent
    XCTAssertLessThan(Date().timeIntervalSince(report.timestamp), 5.0)

    // Platform should be darwin on macOS
    #if os(macOS)
    XCTAssertEqual(report.platform, "darwin")
    #else
    XCTAssertEqual(report.platform, "linux")
    #endif

    // Overall status should be one of the valid values
    let validStatuses: [CLIHealthChecker.HealthStatus] = [.healthy, .degraded, .broken, .unconfigured]
    XCTAssertTrue(validStatuses.contains(report.overall))

    // Components should exist
    XCTAssertNotNil(report.components.shim)
    XCTAssertNotNil(report.components.manifest)
    XCTAssertNotNil(report.components.skills)

    // Issues should be an array (may be empty)
    XCTAssertNotNil(report.issues)
  }

  func testHealthReportIsCodable() throws {
    let report = CLIHealthChecker.checkHealth()

    // Should encode to JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    XCTAssertFalse(data.isEmpty)

    // Should decode back
    let decoded = try JSONDecoder().decode(CLIHealthChecker.HealthReport.self, from: data)
    XCTAssertEqual(decoded.platform, report.platform)
    XCTAssertEqual(decoded.overall, report.overall)
    XCTAssertEqual(decoded.components.shim.installed, report.components.shim.installed)
    XCTAssertEqual(decoded.components.manifest.present, report.components.manifest.present)
  }

  func testHealthStatusEnumValues() {
    // Verify enum raw values match expected strings (used in JSON output)
    XCTAssertEqual(CLIHealthChecker.HealthStatus.healthy.rawValue, "healthy")
    XCTAssertEqual(CLIHealthChecker.HealthStatus.degraded.rawValue, "degraded")
    XCTAssertEqual(CLIHealthChecker.HealthStatus.broken.rawValue, "broken")
    XCTAssertEqual(CLIHealthChecker.HealthStatus.unconfigured.rawValue, "unconfigured")
  }

  func testSeverityEnumValues() {
    XCTAssertEqual(CLIHealthChecker.Severity.error.rawValue, "error")
    XCTAssertEqual(CLIHealthChecker.Severity.warning.rawValue, "warning")
  }

  // MARK: - Issue Structure Tests

  func testIssueHasRequiredFields() {
    let issue = CLIHealthChecker.Issue(
      component: "test",
      severity: .warning,
      code: "TEST_CODE",
      message: "Test message",
      fix: "Run test fix"
    )

    XCTAssertEqual(issue.component, "test")
    XCTAssertEqual(issue.severity, .warning)
    XCTAssertEqual(issue.code, "TEST_CODE")
    XCTAssertEqual(issue.message, "Test message")
    XCTAssertEqual(issue.fix, "Run test fix")
  }

  func testIssueWithNilFix() {
    let issue = CLIHealthChecker.Issue(
      component: "test",
      severity: .error,
      code: "NO_FIX",
      message: "No fix available"
    )

    XCTAssertNil(issue.fix)
  }

  func testIssueEquatable() {
    let issue1 = CLIHealthChecker.Issue(
      component: "skills",
      severity: .warning,
      code: "CODEX_SKILL_MISSING",
      message: "Codex CLI skill not found"
    )

    let issue2 = CLIHealthChecker.Issue(
      component: "skills",
      severity: .warning,
      code: "CODEX_SKILL_MISSING",
      message: "Codex CLI skill not found"
    )

    XCTAssertEqual(issue1, issue2)
  }

  // MARK: - Known Paths Tests

  func testKnownShimPathsIncludesExpectedLocations() {
    let paths = CLIHealthChecker.knownShimPaths

    // Should include Homebrew paths
    XCTAssertTrue(paths.contains("/opt/homebrew/bin/contextify-query"))
    XCTAssertTrue(paths.contains("/usr/local/bin/contextify-query"))

    // Should include user paths
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    XCTAssertTrue(paths.contains("\(home)/bin/contextify-query"))
    XCTAssertTrue(paths.contains("\(home)/.local/bin/contextify-query"))
  }

  func testHomebrewPathsAreRecognized() {
    XCTAssertTrue(CLIHealthChecker.homebrewPaths.contains("/opt/homebrew/bin"))
    XCTAssertTrue(CLIHealthChecker.homebrewPaths.contains("/usr/local/bin"))
  }

  // MARK: - Component Status Tests

  func testShimStatusFields() {
    let status = CLIHealthChecker.ShimStatus(
      installed: true,
      path: "/opt/homebrew/bin/contextify-query",
      onPath: true
    )

    XCTAssertTrue(status.installed)
    XCTAssertEqual(status.path, "/opt/homebrew/bin/contextify-query")
    XCTAssertTrue(status.onPath)
  }

  func testManifestStatusFields() {
    let status = CLIHealthChecker.ManifestStatus(
      present: true,
      version: "1.1.0"
    )

    XCTAssertTrue(status.present)
    XCTAssertEqual(status.version, "1.1.0")
  }

  func testSkillsStatusFields() {
    let status = CLIHealthChecker.SkillsStatus(
      claudeSkillPresent: true,
      codexSkillPresent: false,
      claudeSkillPath: "/Users/test/.claude/skills/total-recall/SKILL.md",
      codexSkillPath: nil
    )

    XCTAssertTrue(status.claudeSkillPresent)
    XCTAssertFalse(status.codexSkillPresent)
    XCTAssertNotNil(status.claudeSkillPath)
    XCTAssertNil(status.codexSkillPath)
  }

  // MARK: - Integration Tests (Run Against Real Filesystem)

  func testCheckHealthReturnsConsistentResults() {
    // Multiple calls should return consistent results
    let report1 = CLIHealthChecker.checkHealth()
    let report2 = CLIHealthChecker.checkHealth()

    XCTAssertEqual(report1.overall, report2.overall)
    XCTAssertEqual(report1.components.shim.installed, report2.components.shim.installed)
    XCTAssertEqual(report1.components.manifest.present, report2.components.manifest.present)
    XCTAssertEqual(report1.components.skills.claudeSkillPresent, report2.components.skills.claudeSkillPresent)
    XCTAssertEqual(report1.components.skills.codexSkillPresent, report2.components.skills.codexSkillPresent)
  }

  func testCheckHealthIssuesMatchComponentState() {
    let report = CLIHealthChecker.checkHealth()

    // If shim not installed, should have SHIM_NOT_FOUND issue
    if !report.components.shim.installed {
      XCTAssertTrue(report.issues.contains { $0.code == "SHIM_NOT_FOUND" })
    }

    // If Claude skill missing, should have CLAUDE_SKILL_MISSING issue
    if !report.components.skills.claudeSkillPresent {
      XCTAssertTrue(report.issues.contains { $0.code == "CLAUDE_SKILL_MISSING" })
    }

    // If Codex skill missing, should have CODEX_SKILL_MISSING issue
    if !report.components.skills.codexSkillPresent {
      XCTAssertTrue(report.issues.contains { $0.code == "CODEX_SKILL_MISSING" })
    }
  }

  func testCheckHealthOverallStatusMatchesComponents() {
    let report = CLIHealthChecker.checkHealth()

    switch report.overall {
    case .healthy:
      // Healthy means no errors, no warnings
      XCTAssertFalse(report.issues.contains { $0.severity == .error })
      XCTAssertFalse(report.issues.contains { $0.severity == .warning })

    case .degraded:
      // Degraded means warnings but no errors
      XCTAssertFalse(report.issues.contains { $0.severity == .error })
      XCTAssertTrue(report.issues.contains { $0.severity == .warning })

    case .broken:
      // Broken means shim exists but nothing else works (partial/corrupt install),
      // or has error-level issues
      #if os(macOS)
      let hasErrors = report.issues.contains { $0.severity == .error }
      let allMissing = !report.components.manifest.present &&
                       !report.components.skills.claudeSkillPresent &&
                       !report.components.skills.codexSkillPresent
      // Broken when: has errors OR (shim installed but everything else missing)
      XCTAssertTrue(hasErrors || (report.components.shim.installed && allMissing))
      #endif

    case .unconfigured:
      // Unconfigured means shim not installed at all
      #if os(macOS)
      XCTAssertFalse(report.components.shim.installed)
      #endif
    }
  }

  // MARK: - Manifest Read Result Tests (File-Based)

  #if os(macOS)
  func testReadPluginVersion_NotFound() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let nonExistentFile = tempDir.appendingPathComponent("non_existent_\(UUID().uuidString).json")

    let result = CLIHealthChecker.readPluginVersion(at: nonExistentFile)
    XCTAssertEqual(result, .notFound)
  }

  func testReadPluginVersion_MalformedJSON() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let malformedFile = tempDir.appendingPathComponent("malformed_\(UUID().uuidString).json")
    try "{ not valid json".write(to: malformedFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: malformedFile) }

    let result = CLIHealthChecker.readPluginVersion(at: malformedFile)
    XCTAssertEqual(result, .malformed)
  }

  func testReadPluginVersion_MissingPluginEntry() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let emptyPluginsFile = tempDir.appendingPathComponent("empty_plugins_\(UUID().uuidString).json")
    // Valid JSON but no query@contextify entry
    let json = """
    {
      "plugins": {
        "some-other-plugin": [{"version": "1.0.0"}]
      }
    }
    """
    try json.write(to: emptyPluginsFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: emptyPluginsFile) }

    let result = CLIHealthChecker.readPluginVersion(at: emptyPluginsFile)
    XCTAssertEqual(result, .missingPluginEntry)
  }

  func testReadPluginVersion_Success() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let validFile = tempDir.appendingPathComponent("valid_\(UUID().uuidString).json")
    let json = """
    {
      "plugins": {
        "query@contextify": [{"version": "1.2.3"}]
      }
    }
    """
    try json.write(to: validFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: validFile) }

    let result = CLIHealthChecker.readPluginVersion(at: validFile)
    XCTAssertEqual(result, .success(version: "1.2.3"))
  }

  func testReadPluginVersion_EmptyPluginsObject() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let emptyFile = tempDir.appendingPathComponent("empty_obj_\(UUID().uuidString).json")
    // Valid JSON with empty plugins object
    let json = """
    {
      "plugins": {}
    }
    """
    try json.write(to: emptyFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: emptyFile) }

    let result = CLIHealthChecker.readPluginVersion(at: emptyFile)
    XCTAssertEqual(result, .missingPluginEntry)
  }

  func testReadPluginVersion_NoPluginsKey() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let noKeyFile = tempDir.appendingPathComponent("no_key_\(UUID().uuidString).json")
    // Valid JSON but no plugins key at all
    let json = """
    {
      "version": "2",
      "metadata": {}
    }
    """
    try json.write(to: noKeyFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: noKeyFile) }

    let result = CLIHealthChecker.readPluginVersion(at: noKeyFile)
    XCTAssertEqual(result, .missingPluginEntry)
  }
  #endif

  func testCheckSkillsMarksLegacyInstallWhenMetadataMissing() throws {
    let homeDir = try makeTemporaryHomeDirectory()
    defer { try? FileManager.default.removeItem(at: homeDir) }

    _ = try writeInstalledSkill(
      homeDir: homeDir,
      clientDirectory: ".claude",
      content: "legacy skill"
    )

    let status = CLIHealthChecker.checkSkills(homeDir: homeDir, fileManager: .default)
    XCTAssertEqual(status.claudeSkillDetails.provenanceStatus, .metadataMissing)
    XCTAssertTrue(status.claudeSkillPresent)
  }

  func testCheckSkillsDetectsInstalledSkillModification() throws {
    let homeDir = try makeTemporaryHomeDirectory()
    defer { try? FileManager.default.removeItem(at: homeDir) }

    let sourceFile = try writeSourceSkill(named: "source-modified", content: "source content")
    _ = try writeInstalledSkill(
      homeDir: homeDir,
      clientDirectory: ".claude",
      content: "edited installed content",
      metadata: makeMetadata(
        target: "claude",
        sourceFile: sourceFile,
        sourceContent: "source content"
      )
    )

    let status = CLIHealthChecker.checkSkills(homeDir: homeDir, fileManager: .default)
    XCTAssertEqual(status.claudeSkillDetails.provenanceStatus, .modified)
    XCTAssertEqual(status.claudeSkillDetails.installSourceKind, .repo)
  }

  func testCheckSkillsDetectsSourceChangedSinceInstall() throws {
    let homeDir = try makeTemporaryHomeDirectory()
    defer { try? FileManager.default.removeItem(at: homeDir) }

    let sourceFile = try writeSourceSkill(named: "source-changed", content: "original source")
    _ = try writeInstalledSkill(
      homeDir: homeDir,
      clientDirectory: ".claude",
      content: "original source",
      metadata: makeMetadata(
        target: "claude",
        sourceFile: sourceFile,
        sourceContent: "original source"
      )
    )

    try "updated source".write(to: sourceFile, atomically: true, encoding: .utf8)

    let status = CLIHealthChecker.checkSkills(homeDir: homeDir, fileManager: .default)
    XCTAssertEqual(status.claudeSkillDetails.provenanceStatus, .sourceChanged)
    XCTAssertEqual(status.claudeSkillDetails.installSourcePath, sourceFile.path)
  }

  private func makeTemporaryHomeDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cli-health-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func writeSourceSkill(named name: String, content: String) throws -> URL {
    let sourceDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("cli-health-source-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    let sourceFile = sourceDir.appendingPathComponent("SKILL.md")
    try content.write(to: sourceFile, atomically: true, encoding: .utf8)
    return sourceFile
  }

  @discardableResult
  private func writeInstalledSkill(
    homeDir: URL,
    clientDirectory: String,
    content: String,
    metadata: CLIHealthChecker.SkillInstallMetadata? = nil
  ) throws -> URL {
    let skillDir = homeDir.appendingPathComponent("\(clientDirectory)/skills/total-recall")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    let skillFile = skillDir.appendingPathComponent("SKILL.md")
    try content.write(to: skillFile, atomically: true, encoding: .utf8)

    if let metadata {
      let metadataURL = CLIHealthChecker.skillMetadataURL(forSkillFile: skillFile)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(metadata)
      try data.write(to: metadataURL, options: .atomic)
    }

    return skillFile
  }

  private func makeMetadata(
    target: String,
    sourceFile: URL,
    sourceContent: String
  ) -> CLIHealthChecker.SkillInstallMetadata {
    let hash = CrossPlatformCrypto.sha256(sourceContent)
    return CLIHealthChecker.SkillInstallMetadata(
      installedAt: "2026-03-12T12:00:00Z",
      installerVersion: "1.3.0-dev",
      target: target,
      installSourceKind: .repo,
      installSourcePath: sourceFile.path,
      sourceSkillSHA256: hash,
      installedSkillSHA256: hash
    )
  }
}
