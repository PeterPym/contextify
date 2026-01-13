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
    let systemdDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/systemd/user")
    let timerPath = systemdDir.appendingPathComponent("contextify.timer")

    // Check if service is installed
    let isInstalled = FileManager.default.fileExists(atPath: timerPath.path)

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
    var lastRunDate: Date?
    if isInstalled {
      let lastResult = runSystemctl(["--user", "show", "contextify.service", "--property=ActiveState,ExecMainStatus,ExecMainExitTimestamp", "--value"])
      if lastResult.exitCode == 0 {
        let lines = lastResult.output.components(separatedBy: "\n")
        if lines.count >= 2 {
          // ExecMainStatus: 0 = success, 2 = noop (also success)
          if let status = Int(lines[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
            lastRunSuccess = (status == 0 || status == 2)
          }
        }
      }
    }

    if json {
      outputJSON(isInstalled: isInstalled, isActive: isActive, nextRun: nextRunDate, lastRunSuccess: lastRunSuccess)
    } else {
      outputHuman(isInstalled: isInstalled, isActive: isActive, nextRun: nextRunDate, lastRunSuccess: lastRunSuccess)
    }
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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: next, relativeTo: Date())
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .short
        timeFormatter.timeStyle = .short
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

  private func outputJSON(isInstalled: Bool, isActive: Bool, nextRun: Date?, lastRunSuccess: Bool?) {
    var output: [String: Any] = [
      "format_version": 1,
      "installed": isInstalled,
      "active": isActive
    ]

    if let next = nextRun {
      output["next_run"] = ISO8601DateFormatter().string(from: next)
    }

    if let success = lastRunSuccess {
      output["last_run_success"] = success
    }

    if let jsonData = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
       let jsonString = String(data: jsonData, encoding: .utf8) {
      print(jsonString)
    }
  }

  private func runSystemctl(_ args: [String]) -> (exitCode: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: XDGPaths.envPath)
    process.arguments = ["systemctl"] + args
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      return (process.terminationStatus, output)
    } catch {
      return (1, "")
    }
  }
  #endif
}
