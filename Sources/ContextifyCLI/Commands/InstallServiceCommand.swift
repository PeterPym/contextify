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
    let serviceContent: String
    do {
      serviceContent = try generateServiceFile(binaryPath: binaryPath, dbPath: dbPath)
    } catch let error as ValidationError {
      print("Error: \(error)")
      throw ExitCode.failure
    }
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
    let wasActive = isTimerActive()
    print(wasActive ? "Updating systemd timer..." : "Enabling systemd timer...")

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

    // If timer was already active, restart to apply any interval changes
    if wasActive {
      let restart = runSystemctl(["--user", "restart", "contextify.timer"])
      if restart.exitCode != 0 {
        print("Warning: Timer enabled but restart failed: \(restart.output)")
        print("New interval may not take effect until next reboot.")
      }
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
    // If argv0 contains no path separator, search PATH
    if !argv0.contains("/") {
      if let found = searchPath(for: argv0) {
        return found
      }
    }
    // Relative path - resolve against cwd
    let cwd = FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: cwd).appendingPathComponent(argv0).standardized.path
  }

  /// Search PATH for a binary (without depending on external 'which' command)
  private func searchPath(for name: String) -> String? {
    guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
      return nil
    }
    let fm = FileManager.default
    // Skip empty components (:: or leading/trailing :)
    for dir in pathEnv.split(separator: ":", omittingEmptySubsequences: true) {
      let candidate = String(dir) + "/" + name
      if fm.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }

  private func checkSystemdAvailability() -> (available: Bool, error: String?) {
    // Use show-environment as a more reliable probe - it's fast and manager-level
    let result = runSystemctl(["--user", "show-environment"])
    // Check for common failure patterns in output (more reliable than exit codes)
    let output = result.output.lowercased()
    if output.contains("failed to connect") ||
       output.contains("no such file or directory") ||
       output.contains("permission denied") {
      return (false, result.output)
    }
    // Exit code 0 means systemd user session is available
    if result.exitCode == 0 {
      return (true, nil)
    }
    return (false, result.output)
  }

  /// Check if the timer is already enabled/active
  private func isTimerActive() -> Bool {
    let result = runSystemctl(["--user", "is-active", "contextify.timer"])
    return result.exitCode == 0
  }

  /// Escape a path for use in systemd ExecStart
  /// See: https://www.freedesktop.org/software/systemd/man/systemd.service.html
  /// systemd has its own quoting rules (not shell):
  /// - $ must become $$ (literal dollar)
  /// - % must become %% (specifier escape)
  /// - \ and " need escaping for quoting
  /// - Wrap in quotes if whitespace present
  /// Throws if path contains control characters that can't be safely represented.
  private func escapeSystemdPath(_ path: String) throws -> String {
    // Reject paths with control characters (can't be safely represented in unit files)
    for char in path.unicodeScalars {
      if char.value < 0x20 || char == "\u{7F}" {
        throw ValidationError.unsafePath(path, reason: "contains control character (\\u{\(String(format: "%04X", char.value))})")
      }
    }
    var escaped = path
    // Escape backslash first (before adding more backslashes)
    escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
    // Escape double quotes for systemd quoting
    escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
    // systemd-specific: $ -> $$ (literal dollar sign)
    escaped = escaped.replacingOccurrences(of: "$", with: "$$")
    // systemd-specific: % -> %% (specifier escape)
    escaped = escaped.replacingOccurrences(of: "%", with: "%%")
    // Wrap in quotes if whitespace present
    if path.contains(" ") || path.contains("\t") {
      return "\"\(escaped)\""
    }
    return escaped
  }

  /// Validation errors for install-service
  private enum ValidationError: Error, CustomStringConvertible {
    case unsafePath(String, reason: String)

    var description: String {
      switch self {
      case .unsafePath(let path, let reason):
        return "Unsafe path '\(path)': \(reason). Cannot write to systemd unit file."
      }
    }
  }

  /// Escape a path for use in cron (shell quoting)
  private func escapeShellPath(_ path: String) -> String {
    // Use single quotes and escape any single quotes in the path
    let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
    return "'\(escaped)'"
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
    print("  2. If on WSL2, enable systemd in /etc/wsl.conf:")
    print("     [boot]")
    print("     systemd=true")
    print("     Then restart: wsl --shutdown (from Windows)")
    print("     Note: WSL1 does not support systemd.")
    print("")
    print("  3. Use cron instead:")
    let binaryPath = resolveBinaryPath()
    let dbPath = XDGPaths.databasePath.path
    let escapedBinary = escapeShellPath(binaryPath)
    let escapedDb = escapeShellPath(dbPath)
    // Convert interval to cron format (approximate)
    let cronInterval = intervalToCron(interval)
    print("     crontab -e")
    print("     Add: \(cronInterval) \(escapedBinary) ingest --quiet --db \(escapedDb) 2>&1 | logger -t contextify")
    print("")
    print("     Note: cron runs with minimal PATH/locale. Use absolute paths.")
    print("")
    print("  4. Run manually when needed:")
    print("     contextify ingest")
  }

  /// Convert systemd interval format to approximate cron schedule
  private func intervalToCron(_ interval: String) -> String {
    // Parse common formats: 15min, 1h, 30s, etc.
    let lower = interval.lowercased()
    if lower.hasSuffix("min") || lower.hasSuffix("m") {
      let numStr = lower.replacingOccurrences(of: "min", with: "").replacingOccurrences(of: "m", with: "")
      if let mins = Int(numStr), mins > 0 && mins <= 59 {
        return "*/\(mins) * * * *"
      }
    } else if lower.hasSuffix("h") {
      let numStr = lower.replacingOccurrences(of: "h", with: "")
      if let hours = Int(numStr), hours > 0 {
        return "0 */\(hours) * * *"
      }
    }
    // Default to every 15 minutes
    return "*/15 * * * *"
  }

  private func generateServiceFile(binaryPath: String, dbPath: String) throws -> String {
    let escapedBinary = try escapeSystemdPath(binaryPath)
    let escapedDb = try escapeSystemdPath(dbPath)
    return """
      [Unit]
      Description=Contextify transcript ingestion
      Documentation=https://contextify.sh/docs/

      [Service]
      Type=oneshot
      ExecStart=\(escapedBinary) ingest --systemd --db \(escapedDb)
      # Exit code 2 = "nothing to do" (not an error)
      SuccessExitStatus=2
      SyslogIdentifier=contextify
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
        formatter.dateStyle = .short
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
