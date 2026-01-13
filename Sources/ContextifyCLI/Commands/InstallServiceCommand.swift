// SPDX-License-Identifier: MIT
// InstallServiceCommand.swift - Set up systemd timer for automatic ingestion

import ArgumentParser
import Foundation

#if canImport(Glibc)
import Glibc
#endif

#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

public struct InstallServiceCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "install-service",
    abstract: "Set up automatic background ingestion via systemd",
    discussion: """
      Creates and enables a systemd user timer that runs 'contextify ingest'
      periodically in the background.

      EXAMPLES:
        contextify install-service                 # Default: every 15 minutes
        contextify install-service --interval 5min # Every 5 minutes
        contextify install-service --interval 1h   # Every hour

      REQUIREMENTS:
        - systemd with user session support
        - User lingering enabled (for timer to run when not logged in)

      If systemd is not available, instructions for cron-based scheduling
      will be provided as an alternative.
      """
  )

  @Option(name: .long, help: "Timer interval in systemd time format (e.g., 15min, 1h, 30s)")
  public var interval: String = "15min"

  public init() {}

  public mutating func run() throws {
    #if os(Linux)
    try installService()
    #else
    print("Error: install-service is only available on Linux.")
    print("On macOS, use the Contextify app for background ingestion.")
    throw ExitCode.failure
    #endif
  }

  #if os(Linux)
  private func installService() throws {
    // 1. Detect binary location
    let binaryPath = resolveBinaryPath()
    guard FileManager.default.fileExists(atPath: binaryPath) else {
      print("Error: Could not find contextify binary at \(binaryPath)")
      throw ExitCode.failure
    }

    // 2. Resolve database path (same logic as ingest command)
    let dbPath = XDGPaths.databasePath.path

    // 3. Check systemd availability
    let systemdCheck = checkSystemdAvailability()
    guard systemdCheck.available else {
      printSystemdFallback(error: systemdCheck.error)
      throw ExitCode.failure
    }

    // 4. Create systemd user directory
    let systemdDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/systemd/user")
    if !XDGPaths.ensureSecureDirectory(systemdDir) {
      print("Error: Could not create systemd user directory")
      throw ExitCode.failure
    }

    // 5. Generate service file
    let serviceContent = generateServiceFile(binaryPath: binaryPath, dbPath: dbPath)
    let servicePath = systemdDir.appendingPathComponent("contextify.service")
    try serviceContent.write(to: servicePath, atomically: true, encoding: .utf8)
    print("Created: \(servicePath.path)")

    // 6. Generate timer file
    let timerContent = generateTimerFile(interval: interval)
    let timerPath = systemdDir.appendingPathComponent("contextify.timer")
    try timerContent.write(to: timerPath, atomically: true, encoding: .utf8)
    print("Created: \(timerPath.path)")

    // 7. Reload systemd and enable timer
    print("")
    print("Enabling systemd timer...")

    let reload = runSystemctl(["--user", "daemon-reload"])
    guard reload.exitCode == 0 else {
      print("Error: Failed to reload systemd: \(reload.output)")
      throw ExitCode.failure
    }

    let enable = runSystemctl(["--user", "enable", "--now", "contextify.timer"])
    guard enable.exitCode == 0 else {
      print("Error: Failed to enable timer: \(enable.output)")
      throw ExitCode.failure
    }

    // 8. Show status
    print("")
    print("Contextify background ingestion installed!")
    print("")
    printTimerStatus()
    print("")
    print("View logs: journalctl --user -u contextify")
  }

  private func resolveBinaryPath() -> String {
    // Try to find the binary via /proc/self/exe (most reliable on Linux)
    if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe") {
      return resolved
    }
    // Fallback to argv[0] resolved path
    let argv0 = CommandLine.arguments[0]
    if argv0.hasPrefix("/") {
      return argv0
    }
    // Relative path - resolve against cwd
    let cwd = FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: cwd).appendingPathComponent(argv0).standardized.path
  }

  private func checkSystemdAvailability() -> (available: Bool, error: String?) {
    let result = runSystemctl(["--user", "status"])
    // Exit code 0 or 3 (no units) means systemd is available
    if result.exitCode == 0 || result.exitCode == 3 {
      return (true, nil)
    }
    return (false, result.output)
  }

  private func printSystemdFallback(error: String?) {
    print("Error: systemd user session not available.")
    if let err = error, !err.isEmpty {
      print("Details: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    print("")
    print("Possible fixes:")
    print("")
    print("  1. Enable user lingering (may require sudo):")
    print("     sudo loginctl enable-linger $USER")
    print("")
    print("  2. If on WSL, enable systemd in /etc/wsl.conf:")
    print("     [boot]")
    print("     systemd=true")
    print("     Then restart WSL.")
    print("")
    print("  3. Use cron instead:")
    let binaryPath = resolveBinaryPath()
    let dbPath = XDGPaths.databasePath.path
    print("     crontab -e")
    print("     Add: */15 * * * * \(binaryPath) ingest --quiet --db \(dbPath)")
    print("")
    print("  4. Run manually when needed:")
    print("     contextify ingest")
  }

  private func generateServiceFile(binaryPath: String, dbPath: String) -> String {
    return """
      [Unit]
      Description=Contextify transcript ingestion
      Documentation=https://contextify.sh/docs/

      [Service]
      Type=oneshot
      ExecStart=\(binaryPath) ingest --systemd --db \(dbPath)
      # Exit code 2 = "nothing to do" (not an error)
      SuccessExitStatus=2
      StandardOutput=journal
      StandardError=journal
      """
  }

  private func generateTimerFile(interval: String) -> String {
    return """
      [Unit]
      Description=Run Contextify ingestion periodically
      Documentation=https://contextify.sh/docs/

      [Timer]
      OnBootSec=2min
      OnUnitActiveSec=\(interval)
      Persistent=true

      [Install]
      WantedBy=timers.target
      """
  }

  private func printTimerStatus() {
    let status = runSystemctl(["--user", "is-active", "contextify.timer"])
    let isActive = status.exitCode == 0

    if isActive {
      print("Timer: active")
      // Get next run time
      let nextRun = runSystemctl(["--user", "show", "contextify.timer", "--property=NextElapseUSecRealtime", "--value"])
      if nextRun.exitCode == 0, let usec = Int64(nextRun.output.trimmingCharacters(in: .whitespacesAndNewlines)), usec > 0 {
        let nextDate = Date(timeIntervalSince1970: Double(usec) / 1_000_000)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        print("Next run: \(formatter.string(from: nextDate))")
      }
    } else {
      print("Timer: not active")
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
