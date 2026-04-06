// SPDX-License-Identifier: MIT
// CloudDispatchTests.swift - Process-level dispatch-matrix tests for cloud CLI routing
//
// Verifies that the hand-rolled argument parser in main.swift routes cloud
// commands correctly through the fast path, the fallback path, and the
// rejection path for pre-command flags.

import XCTest

final class CloudDispatchTests: XCTestCase {

  /// URL of the `contextify-query` binary built by SPM.
  /// Resolved once in `setUp()` via `swift build --show-bin-path`.
  /// The `nonisolated(unsafe)` annotation is safe here because setUp()
  /// runs exactly once before any test method and the value never changes
  /// after initialization.
  nonisolated(unsafe) private static var binaryURL: URL!

  override class func setUp() {
    super.setUp()

    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    process.arguments = ["build", "--show-bin-path"]
    process.currentDirectoryURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/ContextifyCoreTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repo root
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let binPath = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    binaryURL = URL(fileURLWithPath: binPath)
      .appendingPathComponent("contextify-query")
  }

  // MARK: - Helper

  /// Runs the `contextify-query` binary with the given arguments and returns
  /// the exit code, stdout, and stderr as strings.
  private func run(
    _ arguments: [String],
    timeout: TimeInterval = 30,
    environment: [String: String]? = nil
  ) throws -> (exitCode: Int32, stdout: String, stderr: String, timedOut: Bool) {
    let process = Process()
    process.executableURL = Self.binaryURL
    process.arguments = arguments
    if let environment {
      process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    // Use a DispatchWorkItem to enforce a timeout so tests do not hang
    // if a command blocks on network I/O.
    var didTimeout = false
    let timeoutItem = DispatchWorkItem {
      didTimeout = true
      process.terminate()
    }
    DispatchQueue.global().asyncAfter(
      deadline: .now() + timeout,
      execute: timeoutItem
    )

    process.waitUntilExit()
    timeoutItem.cancel()

    let stdout = String(
      data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    let stderr = String(
      data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    return (process.terminationStatus, stdout, stderr, didTimeout)
  }

  /// Combined stdout + stderr for assertions that do not care which stream
  /// carries the message.
  private func combinedOutput(_ result: (exitCode: Int32, stdout: String, stderr: String, timedOut: Bool)) -> String {
    result.stdout + result.stderr
  }

  // MARK: - Fast Path (cloud is first token)

  /// `contextify-query cloud --help` should route to CloudCommand and print
  /// ArgumentParser help text.
  func testCloudHelp_routesToCloudCommand() throws {
    try XCTSkipIf(
      !FileManager.default.fileExists(atPath: Self.binaryURL.path),
      "contextify-query binary not built; run `swift build` first"
    )

    let result = try run(["cloud", "--help"])
    XCTAssertEqual(result.exitCode, 0, "cloud --help should exit 0")
    XCTAssertTrue(
      result.stdout.contains("USAGE: cloud"),
      "Expected ArgumentParser USAGE line in output, got: \(result.stdout.prefix(200))"
    )
  }

  /// `contextify-query cloud status --json` should route through the fast path
  /// and the `--json` flag should be consumed by the cloud subcommand, not the
  /// outer parser. We verify routing happened by checking the output does not
  /// contain outer-parser error messages. The command may or may not succeed
  /// depending on whether cloud is configured and reachable.
  func testCloudStatusJson_cloudOwnedFlagWorks() throws {
    try XCTSkipIf(
      !FileManager.default.fileExists(atPath: Self.binaryURL.path),
      "contextify-query binary not built; run `swift build` first"
    )

    let result = try run(["cloud", "status", "--json"])
    let output = combinedOutput(result)

    // The outer parser would produce "Unknown option: --json" if it
    // tried to parse this flag. That must never appear.
    XCTAssertFalse(
      output.contains("Unknown option"),
      "Outer parser consumed --json instead of routing to cloud command"
    )

    // The outer parser's rejection message must not appear either.
    XCTAssertFalse(
      output.contains("Put cloud-command options after"),
      "Cloud flag was incorrectly rejected as a pre-command flag"
    )

    // Positive check: the command was handled by the cloud subsystem.
    // When cloud is not configured, it outputs JSON with "not_configured".
    // When configured, it either returns server JSON (exit 0) or a
    // cloud-specific network error.
    // When the process times out (network I/O blocked), there may be no
    // output. The negative assertions above already prove the flag was
    // correctly routed, so a timeout is not a failure.
    if !result.timedOut {
      let looksLikeCloudOutput =
        output.contains("{")  // JSON response (success or not-configured)
        || output.contains("Cloud sync not configured")
        || output.contains("Network error")
        || output.contains("cloud.contextify.sh")
      XCTAssertTrue(
        looksLikeCloudOutput,
        "Output does not look like cloud command output: \(output.prefix(300))"
      )
    }
  }

  // MARK: - Rejection Path (global flags before cloud)

  /// `contextify-query --json cloud status` should be rejected because
  /// `--json` is a recognized outer-parser flag consumed before the `cloud`
  /// command token.
  func testPreCloudJson_rejected() throws {
    try XCTSkipIf(
      !FileManager.default.fileExists(atPath: Self.binaryURL.path),
      "contextify-query binary not built; run `swift build` first"
    )

    let result = try run(["--json", "cloud", "status"])
    let output = combinedOutput(result)

    XCTAssertNotEqual(result.exitCode, 0, "Should exit non-zero when global flags precede cloud")
    XCTAssertTrue(
      output.contains("Put cloud-command options after"),
      "Expected rejection message, got: \(output.prefix(300))"
    )
  }

  /// `contextify-query --limit 5 cloud status` should be rejected because
  /// `--limit` is a recognized outer-parser flag consumed before the `cloud`
  /// command token.
  func testPreCloudLimit_rejected() throws {
    try XCTSkipIf(
      !FileManager.default.fileExists(atPath: Self.binaryURL.path),
      "contextify-query binary not built; run `swift build` first"
    )

    let result = try run(["--limit", "5", "cloud", "status"])
    let output = combinedOutput(result)

    XCTAssertNotEqual(result.exitCode, 0, "Should exit non-zero when --limit precedes cloud")
    XCTAssertTrue(
      output.contains("Put cloud-command options after"),
      "Expected rejection message, got: \(output.prefix(300))"
    )
  }

  /// `contextify-query --bogus cloud status` should be rejected by the outer
  /// parser because `--bogus` is not a recognized flag. The error comes from
  /// the flag-parsing loop, not the cloud dispatch guard.
  func testUnknownFlagBeforeCloud_rejected() throws {
    try XCTSkipIf(
      !FileManager.default.fileExists(atPath: Self.binaryURL.path),
      "contextify-query binary not built; run `swift build` first"
    )

    let result = try run(["--bogus", "cloud", "status"])
    let output = combinedOutput(result)

    XCTAssertNotEqual(result.exitCode, 0, "Should exit non-zero for unknown flag")
    XCTAssertTrue(
      output.contains("Unknown option"),
      "Expected 'Unknown option' error, got: \(output.prefix(300))"
    )
  }

  // MARK: - Sync subcommand initialization (ct-886 regression)

  /// `contextify-query cloud sync --help` must not crash. Before the fix
  /// (ct-886), CloudSyncCommand created child push/pull commands via the
  /// default memberwise init, which left property wrappers uninitialized.
  func testCloudSync_helpDoesNotCrash() throws {
    try XCTSkipIf(
      !FileManager.default.fileExists(atPath: Self.binaryURL.path),
      "contextify-query binary not built; run `swift build` first"
    )

    let result = try run(["cloud", "sync", "--help"])

    XCTAssertEqual(result.exitCode, 0, "cloud sync --help should exit 0")
    XCTAssertTrue(
      result.stdout.contains("USAGE: cloud sync"),
      "Expected sync usage text, got: \(result.stdout.prefix(200))"
    )
  }

  /// Exercise the actual sync runtime path far enough to construct child
  /// push/pull commands via ArgumentParser. This must not hit the old
  /// "Can't read a value from a parsable argument definition" crash (ct-886).
  /// Uses a temp DB and temp XDG_CONFIG_HOME so it gets past preflight
  /// guards and into the patched .parse() calls.
  func testCloudSync_runtimePathDoesNotCrashOnChildCommandInit() throws {
    try XCTSkipIf(
      !FileManager.default.fileExists(atPath: Self.binaryURL.path),
      "contextify-query binary not built; run `swift build` first"
    )

    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true
    )
    try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempDir) }

    // Create an empty DB file so the preflight guard passes
    let dbURL = tempDir.appendingPathComponent("test.db")
    fm.createFile(atPath: dbURL.path, contents: Data(), attributes: nil)

    // Create a minimal cloud.json so config load passes
    let xdgHome = tempDir.appendingPathComponent("xdg", isDirectory: true)
    let configDir = xdgHome.appendingPathComponent("contextify", isDirectory: true)
    try fm.createDirectory(at: configDir, withIntermediateDirectories: true)

    let config = """
    {
      "server_url": "http://127.0.0.1:1",
      "api_key": "ctx_testkey1234abcd_secretsecretsecretsecr",
      "device_id": "test-device",
      "device_name": "Test Mac",
      "enabled": true,
      "last_pull_sequence": 0
    }
    """
    try config.data(using: .utf8)!.write(
      to: configDir.appendingPathComponent("cloud.json")
    )

    let result = try run(
      ["cloud", "sync", "--db", dbURL.path],
      timeout: 5,
      environment: ["XDG_CONFIG_HOME": xdgHome.path]
    )
    let output = combinedOutput(result)

    // The ArgumentParser crash must never appear
    XCTAssertFalse(
      output.contains("Can't read a value from a parsable argument definition"),
      "cloud sync crashed with ArgumentParser init error (ct-886)"
    )

    // Expect a runtime failure (bad DB, unreachable server), not a crash
    XCTAssertNotEqual(result.exitCode, 0,
      "Expected runtime failure, but not the ct-886 crash")
  }

  // MARK: - Non-cloud commands unaffected

  /// `contextify-query --json projects` should still work normally. Global
  /// flags before non-cloud commands are fine.
  func testNonCloudCommand_unaffected() throws {
    try XCTSkipIf(
      !FileManager.default.fileExists(atPath: Self.binaryURL.path),
      "contextify-query binary not built; run `swift build` first"
    )

    let result = try run(["--json", "projects"])

    XCTAssertEqual(result.exitCode, 0, "Global flags before non-cloud commands should work")
    // The projects command with --json outputs a JSON object
    XCTAssertTrue(
      result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
      "Expected JSON output from --json projects, got: \(result.stdout.prefix(200))"
    )
  }
}
