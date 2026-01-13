import ArgumentParser
import Foundation

#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

/// Check the health of the Contextify CLI installation
struct DoctorCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Check CLI installation health",
    discussion: """
      Performs a health check of the Contextify CLI installation, verifying
      that all components are properly configured and accessible.

      CHECKS PERFORMED:
        - Skill files (Claude Code and Codex CLI)
        - Database accessibility (if configured)
        - Component versions

      EXIT CODES:
        0 - Healthy: All components present and valid
        1 - Degraded: Some issues but core functionality works
        2 - Broken/Unconfigured: Critical components missing
      """
  )

  @Flag(name: .long, help: "Output result as JSON")
  var json: Bool = false

  func run() throws {
    let report = CLIHealthChecker.checkHealth()

    if json {
      // JSON output
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(report)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      // Human-readable output
      printDoctorReport(report)
    }

    // Exit with appropriate code based on health status
    switch report.overall {
    case .healthy:
      // Exit 0 (success) - handled by normal return
      break
    case .degraded:
      throw ExitCode(1)
    case .broken, .unconfigured:
      throw ExitCode(2)
    }
  }

  private func printDoctorReport(_ report: CLIHealthChecker.HealthReport) {
    // Header with overall status
    let statusEmoji: String
    let statusText: String
    switch report.overall {
    case .healthy:
      statusEmoji = "ok"
      statusText = "healthy"
    case .degraded:
      statusEmoji = "!!"
      statusText = "degraded"
    case .broken:
      statusEmoji = "XX"
      statusText = "broken"
    case .unconfigured:
      statusEmoji = "--"
      statusText = "unconfigured"
    }

    print("Contextify CLI Health Check")
    print("===========================")
    print("")
    print("Status: [\(statusEmoji)] \(statusText)")
    print("Platform: \(report.platform)")
    print("")

    // Components section
    print("Components:")

    // Shim
    let shimStatus = report.components.shim.installed ? "installed" : "not installed"
    print("  Shim: \(shimStatus)")
    if let path = report.components.shim.path {
      print("    Path: \(path)")
      print("    On PATH: \(report.components.shim.onPath ? "yes" : "no")")
    }

    // Manifest
    let manifestStatus = report.components.manifest.present ? "present" : "missing"
    print("  Manifest: \(manifestStatus)")
    if let version = report.components.manifest.version {
      print("    Version: \(version)")
    }

    // Skills
    print("  Skills:")
    print("    Claude Code: \(report.components.skills.claudeSkillPresent ? "installed" : "missing")")
    if let path = report.components.skills.claudeSkillPath {
      print("      Path: \(path)")
    }
    print("    Codex CLI: \(report.components.skills.codexSkillPresent ? "installed" : "missing")")
    if let path = report.components.skills.codexSkillPath {
      print("      Path: \(path)")
    }

    // Issues section
    if !report.issues.isEmpty {
      print("")
      print("Issues:")
      for issue in report.issues {
        let severityMarker = issue.severity == .error ? "[ERROR]" : "[WARN]"
        print("  \(severityMarker) \(issue.code): \(issue.message)")
        if let fix = issue.fix {
          print("    Fix: \(fix)")
        }
      }
    }

    print("")
  }
}
