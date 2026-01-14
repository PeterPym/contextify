// SPDX-License-Identifier: MIT
// ServiceStatusCommand.swift - Check background service status

import ArgumentParser
import Foundation

#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct ServiceStatusCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "service-status",
    abstract: "Check background ingestion service status",
    discussion: """
      Shows the status of the systemd timer including:
      - Whether the timer is active
      - Next scheduled run time
      - Recent execution results

      EXAMPLES:
        contextify service-status

      For detailed logs, use:
        journalctl --user -u contextify -n 20
      """
  )

  @Flag(name: .long, help: "Output as JSON for scripting")
  public var json: Bool = false

  public init() {}

  public mutating func run() throws {
    #if os(Linux)
    try showStatus()
    #else
    print("Error: service-status is only available on Linux.")
    throw ExitCode.failure
    #endif
  }

  #if os(Linux)
  private func showStatus() throws {
    // First check if systemd user session is available
    let systemdCheck = checkSystemdAvailability()
    if !systemdCheck.available {
      if json {
        outputJSON(systemdAvailable: false, isInstalled: false, isActive: false, nextRun: nil, lastRunSuccess: nil, error: systemdCheck.error)
      } else {
        print("Contextify Ingestion Service")
        print("============================")
        print("")
        print("Status: systemd unavailable")
        if let err = systemdCheck.error, !err.isEmpty {
          print("Error: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        print("")
        print("systemd user session is required for the background service.")
        print("See 'contextify install-service --help' for alternatives.")
      }
      // Exit with error code for scripting (systemd not available is an error condition)
      throw ExitCode.failure
    }

    // Check if service is installed via systemctl (more reliable than file check)
    let loadState = runSystemctl(["--user", "show", "contextify.timer", "--property=LoadState", "--value"])
    let isInstalled = loadState.exitCode == 0 && loadState.output.trimmingCharacters(in: .whitespacesAndNewlines) == "loaded"

    // Check if timer is active
    let activeCheck = runSystemctl(["--user", "is-active", "contextify.timer"])
    let isActive = activeCheck.exitCode == 0

    // Get next run time
    var nextRunDate: Date?
    if isActive {
      let nextRun = runSystemctl(["--user", "show", "contextify.timer", "--property=NextElapseUSecRealtime", "--value"])
      if nextRun.exitCode == 0, let usec = Int64(nextRun.output.trimmingCharacters(in: .whitespacesAndNewlines)), usec > 0 {
        nextRunDate = Date(timeIntervalSince1970: Double(usec) / 1_000_000)
      }
    }

    // Get last run result
    var lastRunSuccess: Bool?
    if isInstalled {
      let lastResult = runSystemctl(["--user", "show", "contextify.service", "--property=ExecMainStatus", "--value"])
      if lastResult.exitCode == 0 {
        let statusStr = lastResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        // ExecMainStatus: 0 = success, 2 = noop (also success)
        if let status = Int(statusStr) {
          lastRunSuccess = (status == 0 || status == 2)
        }
      }
    }

    if json {
      outputJSON(systemdAvailable: true, isInstalled: isInstalled, isActive: isActive, nextRun: nextRunDate, lastRunSuccess: lastRunSuccess, error: nil)
    } else {
      outputHuman(isInstalled: isInstalled, isActive: isActive, nextRun: nextRunDate, lastRunSuccess: lastRunSuccess)
    }
  }

  private func checkSystemdAvailability() -> (available: Bool, error: String?) {
    // Use show-environment as a reliable probe - it's fast and manager-level
    let result = runSystemctl(["--user", "show-environment"])
    // Check for common failure patterns in output
    let output = result.output.lowercased()
    if output.contains("failed to connect") ||
       output.contains("no such file or directory") ||
       output.contains("permission denied") {
      return (false, result.output)
    }
    if result.exitCode == 0 {
      return (true, nil)
    }
    return (false, result.output)
  }

  private func outputHuman(isInstalled: Bool, isActive: Bool, nextRun: Date?, lastRunSuccess: Bool?) {
    print("Contextify Ingestion Service")
    print("============================")
    print("")

    if !isInstalled {
      print("Status: not installed")
      print("")
      print("To enable automatic ingestion:")
      print("  contextify install-service")
      return
    }

    if isActive {
      print("Status: active (running)")
      if let next = nextRun {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .short
        timeFormatter.timeStyle = .short
        let relative = formatRelativeTime(from: Date(), to: next)
        print("Next run: \(timeFormatter.string(from: next)) (\(relative))")
      }
    } else {
      print("Status: stopped")
      print("")
      print("To start the service:")
      print("  systemctl --user start contextify.timer")
    }

    if let success = lastRunSuccess {
      print("Last run: \(success ? "success" : "failed")")
    }

    print("")
    print("View logs: journalctl --user -u contextify -n 20")
  }

  /// Format relative time without RelativeDateTimeFormatter (not available on Linux)
  private func formatRelativeTime(from: Date, to: Date) -> String {
    let seconds = to.timeIntervalSince(from)
    if seconds < 0 {
      return "in the past"
    } else if seconds < 60 {
      return "in less than a minute"
    } else if seconds < 3600 {
      let minutes = Int(seconds / 60)
      return "in \(minutes) minute\(minutes == 1 ? "" : "s")"
    } else if seconds < 86400 {
      let hours = Int(seconds / 3600)
      let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
      if minutes > 0 {
        return "in \(hours) hour\(hours == 1 ? "" : "s"), \(minutes) minute\(minutes == 1 ? "" : "s")"
      }
      return "in \(hours) hour\(hours == 1 ? "" : "s")"
    } else {
      let days = Int(seconds / 86400)
      return "in \(days) day\(days == 1 ? "" : "s")"
    }
  }

  private func outputJSON(systemdAvailable: Bool, isInstalled: Bool, isActive: Bool, nextRun: Date?, lastRunSuccess: Bool?, error: String?) {
    var output: [String: Any] = [
      "format_version": 1,
      "systemd_available": systemdAvailable,
      "installed": isInstalled,
      "active": isActive
    ]

    if let next = nextRun {
      output["next_run"] = ISO8601DateFormatter().string(from: next)
    }

    if let success = lastRunSuccess {
      output["last_run_success"] = success
    }

    if let err = error, !err.isEmpty {
      output["error"] = err.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if let jsonData = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
       let jsonString = String(data: jsonData, encoding: .utf8) {
      print(jsonString)
    }
  }

  private func runSystemctl(_ args: [String]) -> (exitCode: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: XDGPaths.envPath)
    process.arguments = ["systemctl"] + args
    process.standardOutput = pipe
    process.standardError = errorPipe

    do {
      try process.run()
      process.waitUntilExit()
      let outData = pipe.fileHandleForReading.readDataToEndOfFile()
      let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: outData, encoding: .utf8) ?? ""
      let errOutput = String(data: errData, encoding: .utf8) ?? ""
      return (process.terminationStatus, output + errOutput)
    } catch {
      return (1, error.localizedDescription)
    }
  }
  #endif
}
