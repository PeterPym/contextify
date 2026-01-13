// SPDX-License-Identifier: MIT
// UninstallServiceCommand.swift - Remove systemd timer for automatic ingestion

import ArgumentParser
import Foundation

#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct UninstallServiceCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "uninstall-service",
    abstract: "Remove automatic background ingestion",
    discussion: """
      Stops and disables the systemd timer, then removes the service files.

      EXAMPLES:
        contextify uninstall-service

      This does NOT delete your database or any indexed data.
      """
  )

  public init() {}

  public mutating func run() throws {
    #if os(Linux)
    try uninstallService()
    #else
    print("Error: uninstall-service is only available on Linux.")
    throw ExitCode.failure
    #endif
  }

  #if os(Linux)
  private func uninstallService() throws {
    let systemdDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/systemd/user")
    let servicePath = systemdDir.appendingPathComponent("contextify.service")
    let timerPath = systemdDir.appendingPathComponent("contextify.timer")

    let fm = FileManager.default
    let serviceExists = fm.fileExists(atPath: servicePath.path)
    let timerExists = fm.fileExists(atPath: timerPath.path)

    if !serviceExists && !timerExists {
      print("Contextify service is not installed.")
      throw ExitCode(CLIExitCode.noop.rawValue)
    }

    // Stop and disable timer (ignore errors - may not be running)
    print("Stopping timer...")
    _ = runSystemctl(["--user", "stop", "contextify.timer"])
    _ = runSystemctl(["--user", "disable", "contextify.timer"])

    // Remove files
    print("Removing service files...")
    if timerExists {
      try? fm.removeItem(at: timerPath)
      print("Removed: \(timerPath.path)")
    }
    if serviceExists {
      try? fm.removeItem(at: servicePath)
      print("Removed: \(servicePath.path)")
    }

    // Reload daemon
    _ = runSystemctl(["--user", "daemon-reload"])

    print("")
    print("Contextify background ingestion removed.")
    print("")
    print("Your database and indexed data are preserved.")
    print("To re-enable: contextify install-service")
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
