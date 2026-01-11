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
      // Healthy means no errors, possibly no warnings
      XCTAssertFalse(report.issues.contains { $0.severity == .error })

    case .degraded:
      // Degraded means warnings but no errors, or specific missing components
      // Either has warnings or specific missing components that warrant degraded
      break

    case .broken:
      // Broken should have error-level issues
      XCTAssertTrue(report.issues.contains { $0.severity == .error })

    case .unconfigured:
      // Unconfigured means shim not installed or everything missing
      #if os(macOS)
      // On macOS: either no shim, or shim with nothing else
      if report.components.shim.installed {
        XCTAssertFalse(report.components.manifest.present)
        XCTAssertFalse(report.components.skills.claudeSkillPresent)
        XCTAssertFalse(report.components.skills.codexSkillPresent)
      }
      #endif
    }
  }
}
