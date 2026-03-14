// SPDX-License-Identifier: MIT
// CloudCommand.swift - Cloud sync commands for multi-machine sync

import ArgumentParser
import Foundation

#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

// MARK: - Cloud Config

/// Configuration for cloud sync, stored in ~/.config/contextify/cloud.json.
/// Uses snake_case keys to match the Core CloudConfig schema so both CLI and app
/// can read/write the same file without format mismatches.
struct CLICloudConfig: Codable {
  var serverURL: String
  var apiKey: String
  var deviceId: String = ""
  var deviceName: String = ""
  var enabled: Bool = true
  var lastPullSequence: Int = 0
  var lastPushTimestamp: Int?
  var lastPushEntryId: String?

  enum CodingKeys: String, CodingKey {
    case serverURL = "server_url"
    case apiKey = "api_key"
    case deviceId = "device_id"
    case deviceName = "device_name"
    case enabled
    case lastPullSequence = "last_pull_sequence"
    case lastPushTimestamp = "last_push_timestamp"
    case lastPushEntryId = "last_push_entry_id"
  }

  static var configDir: URL {
    if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
      return URL(fileURLWithPath: xdg).appendingPathComponent("contextify")
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/contextify")
  }

  static var configFile: URL { configDir.appendingPathComponent("cloud.json") }

  /// Legacy config format used before the snake_case unification.
  /// Supports migration from configs written with the old CLI.
  private struct Legacy: Codable {
    var cloudURL: String
    var apiKey: String
    var enabled: Bool?
    var lastPullSequence: Int?
  }

  static func load() throws -> CLICloudConfig {
    let data = try Data(contentsOf: configFile)
    // Try current format first
    if let cfg = try? JSONDecoder().decode(CLICloudConfig.self, from: data) {
      return cfg
    }
    // Fall back to legacy format and migrate
    let legacy = try JSONDecoder().decode(Legacy.self, from: data)
    let migrated = CLICloudConfig(
      serverURL: legacy.cloudURL,
      apiKey: legacy.apiKey,
      enabled: legacy.enabled ?? true,
      lastPullSequence: legacy.lastPullSequence ?? 0
    )
    // Best-effort persist in new format; ignore failures (read-only FS, perms, etc.)
    try? migrated.save()
    return migrated
  }

  func save() throws {
    try FileManager.default.createDirectory(
      at: CLICloudConfig.configDir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(self)
    try data.write(to: CLICloudConfig.configFile, options: .atomic)
  }
}

// MARK: - HTTP Helpers

enum CloudError: Error, CustomStringConvertible {
  case notConfigured
  case networkError(String)
  case apiError(Int, String)
  case invalidResponse

  var description: String {
    switch self {
    case .notConfigured:
      return "Cloud sync not configured. Run 'contextify cloud setup' first."
    case .networkError(let msg):
      return "Network error: \(msg)"
    case .apiError(let code, let msg):
      return "API error (\(code)): \(msg)"
    case .invalidResponse:
      return "Invalid response from cloud server"
    }
  }
}

/// Synchronous HTTP request helper for cloud API calls
private func cloudRequest(
  config: CLICloudConfig,
  method: String,
  path: String,
  body: Data? = nil,
  queryItems: [URLQueryItem]? = nil,
  timeoutSeconds: TimeInterval = 30
) throws -> (Data, Int) {
  let baseURL = config.serverURL.hasSuffix("/")
    ? String(config.serverURL.dropLast())
    : config.serverURL

  var components = URLComponents(string: "\(baseURL)\(path)")!
  if let queryItems = queryItems {
    components.queryItems = queryItems
  }

  var request = URLRequest(url: components.url!)
  request.httpMethod = method
  request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = body
  request.timeoutInterval = timeoutSeconds

  let semaphore = DispatchSemaphore(value: 0)
  var responseData: Data?
  var statusCode: Int = 0
  var requestError: Error?

  let task = URLSession.shared.dataTask(with: request) { data, response, error in
    responseData = data
    statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
    requestError = error
    semaphore.signal()
  }
  task.resume()
  let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds + 5)
  if waitResult == .timedOut {
    task.cancel()
    throw CloudError.networkError("Request timed out after \(Int(timeoutSeconds))s")
  }

  if let error = requestError {
    throw CloudError.networkError(error.localizedDescription)
  }
  guard let data = responseData else {
    throw CloudError.networkError("No response received")
  }
  return (data, statusCode)
}

/// Synchronous HTTP request without authentication, for device flow endpoints
private func unauthenticatedRequest(
  url urlString: String,
  method: String,
  body: Data? = nil,
  timeoutSeconds: TimeInterval = 15
) throws -> (Data, Int) {
  guard let url = URL(string: urlString) else {
    throw CloudError.networkError("Invalid URL: \(urlString)")
  }

  var request = URLRequest(url: url)
  request.httpMethod = method
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = body
  request.timeoutInterval = timeoutSeconds

  let semaphore = DispatchSemaphore(value: 0)
  var responseData: Data?
  var statusCode: Int = 0
  var requestError: Error?

  let task = URLSession.shared.dataTask(with: request) { data, response, error in
    responseData = data
    statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
    requestError = error
    semaphore.signal()
  }
  task.resume()
  let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds + 5)
  if waitResult == .timedOut {
    task.cancel()
    throw CloudError.networkError("Request timed out after \(Int(timeoutSeconds))s")
  }

  if let error = requestError {
    throw CloudError.networkError(error.localizedDescription)
  }
  guard let data = responseData else {
    throw CloudError.networkError("No response received")
  }
  return (data, statusCode)
}

// MARK: - Device Flow Types

/// Response from POST /api/v1/auth/device/code
struct DeviceCodeResponse: Codable {
  let deviceCode: String
  let userCode: String
  let verificationUri: String
  let expiresIn: Int
  let interval: Int

  enum CodingKeys: String, CodingKey {
    case deviceCode = "device_code"
    case userCode = "user_code"
    case verificationUri = "verification_uri"
    case expiresIn = "expires_in"
    case interval
  }
}

/// Success response from POST /api/v1/auth/device/token
struct DeviceTokenResponse: Codable {
  let apiKey: String
  let apiKeyPrefix: String?
  let email: String?
  let name: String?
  let role: String?
  let plan: String?
  let tenantName: String?

  enum CodingKeys: String, CodingKey {
    case apiKey = "api_key"
    case apiKeyPrefix = "api_key_prefix"
    case email, name, role, plan
    case tenantName = "tenant_name"
  }
}

/// Error response from POST /api/v1/auth/device/token (RFC 8628 section 3.5)
struct DeviceTokenError: Codable {
  let error: String
  let errorDescription: String?

  enum CodingKeys: String, CodingKey {
    case error
    case errorDescription = "error_description"
  }
}

// MARK: - Device Flow Helpers

/// Request a device code from the server to start the device flow
private func requestDeviceCode(baseURL: String) throws -> DeviceCodeResponse {
  let endpoint = "\(baseURL)/api/v1/auth/device/code"
  let body = try JSONEncoder().encode(["client_name": "contextify-cli"])

  let (data, statusCode) = try unauthenticatedRequest(
    url: endpoint, method: "POST", body: body)

  guard statusCode == 200 else {
    let body = String(data: data, encoding: .utf8) ?? "unknown"
    throw CloudError.apiError(statusCode, "Failed to start device flow: \(body)")
  }

  return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
}

/// Poll the device token endpoint until authorization is granted, denied, or expired.
/// Uses a text-based spinner to indicate waiting. Returns the API key on success.
private func pollForDeviceToken(
  baseURL: String,
  deviceCode: String,
  interval: Int,
  expiresIn: Int
) throws -> DeviceTokenResponse {
  let endpoint = "\(baseURL)/api/v1/auth/device/token"
  var currentInterval = interval
  let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))

  // Simple spinner frames for the waiting indicator
  let spinnerFrames = ["*", "o", "O", "o"]
  var frameIndex = 0

  while Date() < deadline {
    Thread.sleep(forTimeInterval: TimeInterval(currentInterval))

    // Show spinner progress
    if CLIStyle.isStyled {
      let frame = spinnerFrames[frameIndex % spinnerFrames.count]
      print("\r  \(frame) Waiting for browser authorization...", terminator: "")
      fflush(stdout)
      frameIndex += 1
    }

    let body = try JSONEncoder().encode([
      "device_code": deviceCode,
      "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
    ])

    let data: Data
    let statusCode: Int
    do {
      (data, statusCode) = try unauthenticatedRequest(
        url: endpoint, method: "POST", body: body)
    } catch {
      // Network error during polling - back off and retry per RFC 8628
      currentInterval = min(currentInterval + 5, 30)
      continue
    }

    if statusCode == 200 {
      // Clear spinner line
      if CLIStyle.isStyled {
        print("\r\u{001B}[2K", terminator: "")
        fflush(stdout)
      }
      return try JSONDecoder().decode(DeviceTokenResponse.self, from: data)
    }

    if statusCode == 400 {
      let errorResponse = try JSONDecoder().decode(DeviceTokenError.self, from: data)
      switch errorResponse.error {
      case "authorization_pending":
        continue
      case "slow_down":
        currentInterval += 5
        continue
      case "expired_token":
        if CLIStyle.isStyled {
          print("\r\u{001B}[2K", terminator: "")
          fflush(stdout)
        }
        throw CloudError.networkError("Authorization timed out. The code has expired. Please run setup again.")
      case "access_denied":
        if CLIStyle.isStyled {
          print("\r\u{001B}[2K", terminator: "")
          fflush(stdout)
        }
        throw CloudError.networkError("Authorization was denied by the user.")
      default:
        if CLIStyle.isStyled {
          print("\r\u{001B}[2K", terminator: "")
          fflush(stdout)
        }
        throw CloudError.networkError(
          errorResponse.errorDescription ?? "Unknown error: \(errorResponse.error)")
      }
    }

    // Unexpected status code
    if CLIStyle.isStyled {
      print("\r\u{001B}[2K", terminator: "")
      fflush(stdout)
    }
    let respBody = String(data: data, encoding: .utf8) ?? ""
    throw CloudError.apiError(statusCode, respBody)
  }

  // Expired by local deadline
  if CLIStyle.isStyled {
    print("\r\u{001B}[2K", terminator: "")
    fflush(stdout)
  }
  throw CloudError.networkError("Authorization timed out after \(expiresIn) seconds.")
}

/// Attempt to open a URL in the user's default browser.
/// Returns true if the browser was opened, false otherwise.
private func tryOpenBrowser(url urlString: String) -> Bool {
  #if os(macOS)
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  process.arguments = [urlString]
  process.standardError = FileHandle.nullDevice
  process.standardOutput = FileHandle.nullDevice
  do {
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
  } catch {
    return false
  }
  #else
  // Linux: try xdg-open
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["xdg-open", urlString]
  process.standardError = FileHandle.nullDevice
  process.standardOutput = FileHandle.nullDevice
  do {
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
  } catch {
    return false
  }
  #endif
}

// MARK: - Cloud Command Group

/// Cloud sync commands for multi-machine synchronization
struct CloudCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "cloud",
    abstract: "Cloud sync for multi-machine access",
    discussion: """
      Sync your Contextify database with a cloud server for multi-machine
      access. Requires a Contextify Cloud account or self-hosted server.

      GETTING STARTED:
        contextify cloud setup                Set up cloud connection
        contextify cloud status               Check sync status
        contextify cloud push                 Push local entries to cloud
        contextify cloud pull                 Pull entries from other devices
        contextify cloud sync                 Full sync (push + pull)
        contextify cloud search "query"       Search cloud entries

      DOCUMENTATION: https://contextify.sh/docs/cloud/
      """,
    subcommands: [
      CloudSetupCommand.self,
      CloudStatusCommand.self,
      CloudPushCommand.self,
      CloudPullCommand.self,
      CloudSyncCommand.self,
      CloudSearchCommand.self,
    ]
  )
}

// MARK: - Setup Command

/// Default cloud server URL for the managed service
private let defaultCloudServerURL = "https://cloud.contextify.sh"

struct CloudSetupCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "setup",
    abstract: "Configure cloud sync connection",
    discussion: """
      Set up cloud sync with your Contextify Cloud account.

      The default flow opens your browser to sign in (device flow auth).
      For headless environments or CI, use --key to provide an API key directly.

      EXAMPLES:
        contextify cloud setup                                    # Browser sign-in
        contextify cloud setup --key ctx_abc123_def456             # Direct API key
        contextify cloud setup --url https://self-hosted:8443 --key ctx_abc123
        contextify cloud setup --no-device-flow                   # Legacy URL + key prompts
      """
  )

  @Option(name: .long, help: "Cloud server URL (default: cloud.contextify.sh)")
  var url: String?

  @Option(name: .long, help: "API key (ctx_...) for non-interactive setup")
  var key: String?

  @Flag(name: .long, help: "Disable all interactive prompts; fail if --key is not provided")
  var noInput: Bool = false

  @Flag(name: .long, help: "Skip device flow auth; use legacy URL + key prompts")
  var noDeviceFlow: Bool = false

  func run() throws {
    if let apiKey = key {
      // Path A: Direct API key (CI/headless/non-interactive)
      try setupWithAPIKey(apiKey: apiKey, serverURL: url ?? defaultCloudServerURL)
    } else if noInput {
      // Non-interactive without key is an error
      print(CLIStyle.error("--key is required when using --no-input"))
      print(CLIStyle.dimText("  Example: contextify cloud setup --no-input --key ctx_abc123"))
      throw ExitCode(1)
    } else if noDeviceFlow || isCustomServerURL() {
      // Path C: Legacy interactive prompts (user explicitly chose, or self-hosted server)
      try setupWithLegacyPrompts(serverURL: url)
    } else {
      // Path B: Device flow (default for interactive sessions with managed server)
      try setupWithDeviceFlow(serverURL: url ?? defaultCloudServerURL)
    }
  }

  /// Whether the user specified a custom (non-default) server URL
  private func isCustomServerURL() -> Bool {
    guard let u = url else { return false }
    return u != defaultCloudServerURL && u != "https://cloud.contextify.sh"
  }

  // MARK: - Path A: Direct API Key

  private func setupWithAPIKey(apiKey: String, serverURL: String) throws {
    guard URL(string: serverURL) != nil else {
      throw ValidationError("Invalid URL: \(serverURL)")
    }
    guard apiKey.hasPrefix("ctx_") else {
      throw ValidationError("API key must start with 'ctx_'")
    }

    let machineId = getStableMachineId()
    let machineName = getLocalMachineName()

    print()
    print("Testing connection to \(CLIStyle.cyanText(serverURL))...")
    let config = CLICloudConfig(
      serverURL: serverURL, apiKey: apiKey,
      deviceId: machineId, deviceName: machineName)
    do {
      let (_, status) = try cloudRequest(
        config: config, method: "GET", path: "/api/v1/sync/status")
      if status == 200 {
        print(CLIStyle.success("Connection successful"))
      } else if status == 401 || status == 403 {
        print(CLIStyle.warning("Authentication failed (HTTP \(status)). Check your API key."))
      } else {
        print(CLIStyle.warning("Server returned HTTP \(status). Saving config anyway."))
      }
    } catch {
      print(CLIStyle.warning("Could not connect: \(error)"))
      print(CLIStyle.dimText("Saving configuration anyway."))
    }

    try config.save()
    print()
    print(CLIStyle.success("Cloud sync configured (\(serverURL))"))
    let configPath = CLIStyle.link(
      CLICloudConfig.configFile.path,
      url: "file://\(CLICloudConfig.configFile.path)")
    print(CLIStyle.labelValue("Config:", " \(configPath)"))
    print()
    print(CLIStyle.dimText("Next: \(CLIStyle.cyanText("contextify cloud sync"))"))
  }

  // MARK: - Path B: Device Flow

  private func setupWithDeviceFlow(serverURL: String) throws {
    print()
    print(CLIStyle.header("Contextify Cloud Setup"))
    print()

    // Step 1: Request device code
    print("\(CLIStyle.bold)Step 1:\(CLIStyle.reset) Authenticate")

    let codeResponse: DeviceCodeResponse
    do {
      codeResponse = try requestDeviceCode(baseURL: serverURL)
    } catch {
      // Device flow not available: fall back to legacy prompts
      print(CLIStyle.warning("Device flow unavailable: \(error)"))
      print(CLIStyle.dimText("Falling back to manual setup..."))
      print()
      try setupWithLegacyPrompts(serverURL: serverURL)
      return
    }

    // Display verification URL and code
    let verificationLink = CLIStyle.link(
      codeResponse.verificationUri, url: codeResponse.verificationUri)

    // Try to open browser
    let browserOpened = tryOpenBrowser(url: codeResponse.verificationUri)

    if browserOpened {
      print("  Opening browser...")
    } else {
      print("  Open this URL on any device to sign in:")
    }
    print("  \(verificationLink)")
    print()
    print("  Enter code: \(CLIStyle.boldText(codeResponse.userCode))")
    print()

    // Step 2: Poll for authorization
    if !CLIStyle.isStyled {
      print("  Waiting for authorization...")
    }

    let tokenResponse: DeviceTokenResponse
    do {
      tokenResponse = try pollForDeviceToken(
        baseURL: serverURL,
        deviceCode: codeResponse.deviceCode,
        interval: codeResponse.interval,
        expiresIn: codeResponse.expiresIn)
    } catch {
      print(CLIStyle.error("\(error)"))
      throw ExitCode(1)
    }

    let emailDisplay = tokenResponse.email ?? "your account"
    print(CLIStyle.success("Authenticated as \(emailDisplay)"))
    print()

    // Step 2: Configure device
    print("\(CLIStyle.bold)Step 2:\(CLIStyle.reset) Configure")

    let machineId = getStableMachineId()
    let machineName = getLocalMachineName()

    #if os(macOS)
    let osLabel = "macOS"
    #else
    let osLabel = "Linux"
    #endif
    print("  Device: \(machineName) (\(osLabel))")

    let config = CLICloudConfig(
      serverURL: serverURL,
      apiKey: tokenResponse.apiKey,
      deviceId: machineId,
      deviceName: machineName)
    try config.save()

    print(CLIStyle.success("Cloud sync configured"))
    print()

    // Summary
    if let email = tokenResponse.email {
      print(CLIStyle.labelValue("  Account:", " \(email)"))
    }
    if let team = tokenResponse.tenantName {
      print(CLIStyle.labelValue("  Team:", "    \(team)"))
    }
    if let plan = tokenResponse.plan {
      print(CLIStyle.labelValue("  Plan:", "    \(plan)"))
    }
    let configPath = CLIStyle.link(
      CLICloudConfig.configFile.path,
      url: "file://\(CLICloudConfig.configFile.path)")
    print(CLIStyle.labelValue("  Config:", "  \(configPath)"))
    print(CLIStyle.labelValue("  Next:", "    \(CLIStyle.cyanText("contextify cloud sync"))"))
  }

  // MARK: - Path C: Legacy Interactive Prompts

  private func setupWithLegacyPrompts(serverURL: String?) throws {
    let cloudURL: String
    let apiKey: String

    print()
    print(CLIStyle.header("Contextify Cloud Setup"))
    print()

    if let u = serverURL {
      cloudURL = u
      print("  Server: \(CLIStyle.cyanText(u))")
      print()
    } else {
      print("\(CLIStyle.bold)[1/2]\(CLIStyle.reset) Enter your cloud server URL")
      let exampleURL = CLIStyle.link(
        "cloud.contextify.sh", url: "https://cloud.contextify.sh")
      print(CLIStyle.dimText("  (e.g., https://\(exampleURL) or http://100.x.y.z:8443)"))
      print("\(CLIStyle.bold)\(CLIStyle.cyan)> \(CLIStyle.reset)", terminator: "")
      guard let inputURL = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !inputURL.isEmpty else {
        throw ValidationError("URL is required")
      }
      cloudURL = inputURL
    }

    let stepLabel = serverURL != nil ? "[1/1]" : "[2/2]"
    print()
    print("\(CLIStyle.bold)\(stepLabel)\(CLIStyle.reset) Enter your API key \(CLIStyle.dimText("(starts with ctx_)"))")
    print("\(CLIStyle.bold)\(CLIStyle.cyan)> \(CLIStyle.reset)", terminator: "")
    guard let inputKey = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          !inputKey.isEmpty else {
      throw ValidationError("API key is required")
    }
    apiKey = inputKey

    guard URL(string: cloudURL) != nil else {
      throw ValidationError("Invalid URL: \(cloudURL)")
    }
    guard apiKey.hasPrefix("ctx_") else {
      throw ValidationError("API key must start with 'ctx_'")
    }

    try setupWithAPIKey(apiKey: apiKey, serverURL: cloudURL)
  }
}

// MARK: - Status Command

struct CloudStatusCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Show cloud sync status"
  )

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    let config: CLICloudConfig
    do {
      config = try CLICloudConfig.load()
    } catch {
      if json {
        print(#"{"configured":false,"error":"not_configured"}"#)
      } else {
        print(CLIStyle.error("Cloud sync not configured. Run '\(CLIStyle.cyanText("contextify cloud setup"))' first."))
      }
      return
    }

    let (data, status) = try cloudRequest(
      config: config, method: "GET", path: "/api/v1/sync/status")

    guard status == 200 else {
      let body = String(data: data, encoding: .utf8) ?? "unknown"
      throw CloudError.apiError(status, body)
    }

    if json {
      // Merge local config into server response
      if var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        obj["configured"] = true
        obj["cloud_url"] = config.serverURL
        obj["last_pull_sequence"] = config.lastPullSequence
        obj["last_push_timestamp"] = config.lastPushTimestamp ?? NSNull()
        obj["last_push_entry_id"] = config.lastPushEntryId ?? NSNull()
        let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        print(String(data: out, encoding: .utf8)!)
      } else {
        print(String(data: data, encoding: .utf8) ?? "{}")
      }
    } else {
      let labelWidth = 12
      print()
      print(CLIStyle.header("Cloud Sync Status"))
      print()
      let serverLink = CLIStyle.link(config.serverURL, url: config.serverURL)
      print(CLIStyle.labelValue("Server:", serverLink, padTo: labelWidth))
      let enabledValue = config.enabled
        ? CLIStyle.greenText("yes")
        : CLIStyle.redText("no")
      print(CLIStyle.labelValue("Enabled:", enabledValue, padTo: labelWidth))
      print()

      if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let lastSync = obj["last_sync"] as? String {
          print(CLIStyle.labelValue("Last sync:", lastSync, padTo: labelWidth))
        } else {
          print(CLIStyle.labelValue("Last sync:", CLIStyle.yellowText("never"), padTo: labelWidth))
        }
        if let entries = obj["entries_synced"] as? Int {
          print(CLIStyle.labelValue("Entries:", CLIStyle.boldText("\(entries)"), padTo: labelWidth))
        }
        if let seq = obj["server_sequence"] as? Int {
          print(CLIStyle.labelValue("Server seq:", "\(seq)", padTo: labelWidth))
        }
        if let devices = obj["devices"] as? [[String: Any]] {
          print(CLIStyle.labelValue("Devices:", CLIStyle.boldText("\(devices.count)"), padTo: labelWidth))
          for d in devices {
            let name = d["machine_name"] as? String ?? "unknown"
            let os = d["os"] as? String ?? ""
            print("  \(CLIStyle.dimText("-")) \(CLIStyle.boldText(name)) \(CLIStyle.dimText("(\(os))"))")
          }
        }
      }
      print()
      print(CLIStyle.labelValue("Pull cursor:", "\(config.lastPullSequence)", padTo: labelWidth))
      if let ts = config.lastPushTimestamp {
        let suffix = config.lastPushEntryId.map { " \(CLIStyle.dimText("(\($0))"))" } ?? ""
        print(CLIStyle.labelValue("Push cursor:", "\(ts)\(suffix)", padTo: labelWidth))
      } else {
        print(CLIStyle.labelValue("Push cursor:", CLIStyle.yellowText("none") + CLIStyle.dimText(" (full upload on next push)"), padTo: labelWidth))
      }
    }
  }
}

// MARK: - Push Command

struct CloudPushCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "push",
    abstract: "Push local entries to cloud",
    discussion: """
      Push locally-indexed transcript entries to your cloud server.
      The server deduplicates entries by ID and content hash.

      EXAMPLES:
        contextify cloud push                    # Push entries
        contextify cloud push --db /path/to.db   # Specify database
        contextify cloud push --limit 100        # Limit batch size
      """
  )

  @Option(name: .long, help: "Path to the SQLite database file")
  var db: String?

  @Option(name: .long, help: "Maximum entries per batch (default: 500)")
  var limit: Int = 500

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    var config = try CLICloudConfig.load()

    // Resolve database path using same logic as other commands
    let dbPath = resolveDbPath()
    guard FileManager.default.fileExists(atPath: dbPath) else {
      throw ValidationError("Database not found at \(dbPath)")
    }

    let dbURL = URL(fileURLWithPath: dbPath)
    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Build device info once
    #if os(macOS)
    let osName = "macos"
    #else
    let osName = "linux"
    #endif
    let machineId = config.deviceId.isEmpty ? getStableMachineId() : config.deviceId

    // Keyset pagination: resume from saved cursor for incremental push
    var afterTimestamp: Int? = config.lastPushTimestamp
    var afterEntryId: String? = config.lastPushEntryId
    var totalAccepted = 0
    var totalDuplicates = 0
    var totalErrors: [String] = []
    var batchCount = 0

    while true {
      let exportData = try service.exportForCloudPush(
        afterTimestamp: afterTimestamp,
        afterEntryId: afterEntryId,
        limit: limit
      )

      if exportData.entries.isEmpty {
        if batchCount == 0 {
          if json {
            print(#"{"accepted":0,"duplicates_skipped":0,"errors":[]}"#)
          } else {
            print(CLIStyle.dimText("No entries to push."))
          }
        }
        break
      }

      batchCount += 1
      let payload = buildPushPayload(
        exportData: exportData,
        machineId: machineId,
        machineName: config.deviceName.isEmpty ? nil : config.deviceName,
        osName: osName
      )
      let bodyData = try JSONSerialization.data(withJSONObject: payload)

      if !json {
        print("Pushing batch \(CLIStyle.boldText("\(batchCount)")): \(exportData.entries.count) entries to \(CLIStyle.cyanText(config.serverURL))...")
      }

      let (responseData, status) = try cloudRequest(
        config: config, method: "POST", path: "/api/v1/sync/push", body: bodyData)

      guard status == 200 else {
        let body = String(data: responseData, encoding: .utf8) ?? "unknown"
        throw CloudError.apiError(status, body)
      }

      if let result = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
        totalAccepted += result["accepted"] as? Int ?? 0
        totalDuplicates += result["duplicates_skipped"] as? Int ?? 0
        let batchErrors = result["errors"] as? [String] ?? []
        totalErrors.append(contentsOf: batchErrors)
        // Fail closed: checkpoint cursor at last successful batch, then stop
        if !batchErrors.isEmpty {
          break
        }
      }

      // Advance keyset cursor from last entry in this batch
      if let last = exportData.entries.last {
        afterTimestamp = last.timestamp
        afterEntryId = last.id
      }

      // Checkpoint cursor after each successful batch so retries
      // resume from here instead of replaying all prior batches
      if let ts = afterTimestamp, let eid = afterEntryId {
        config.lastPushTimestamp = ts
        config.lastPushEntryId = eid
        try config.save()
      }

      // Short page means we have exported everything
      if exportData.entries.count < limit {
        break
      }
    }

    // Print final summary
    if batchCount > 0 {
      if json {
        let output: [String: Any] = [
          "accepted": totalAccepted,
          "duplicates_skipped": totalDuplicates,
          "errors": Array(totalErrors.prefix(10)),
          "batches": batchCount,
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
        print(String(data: data, encoding: .utf8) ?? "{}")
      } else {
        print(CLIStyle.success("Push complete: \(totalAccepted) accepted, \(totalDuplicates) duplicates (\(batchCount) batch\(batchCount == 1 ? "" : "es"))"))
        if !totalErrors.isEmpty {
          print(CLIStyle.error("Errors: \(totalErrors.count)"))
          for e in totalErrors.prefix(5) { print("  \(CLIStyle.redText("-")) \(e)") }
        }
      }
    }

    if !totalErrors.isEmpty { throw ExitCode(1) }
  }

  private func resolveDbPath() -> String {
    if let dbFlag = db { return XDGPaths.expandTilde(dbFlag) }
    return XDGPaths.databasePath.path
  }
}

// MARK: - Pull Command

struct CloudPullCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pull",
    abstract: "Pull entries from other devices",
    discussion: """
      Pull transcript entries from your cloud server into the local
      database. Uses cursor-based pagination to efficiently sync.

      EXAMPLES:
        contextify cloud pull
        contextify cloud pull --project myproject
      """
  )

  @Option(name: .long, help: "Path to the SQLite database file")
  var db: String?

  @Option(name: .long, help: "Filter to specific project ID")
  var project: String?

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    var config = try CLICloudConfig.load()

    let dbPath = resolveDbPath()
    let queryService = try ContextifyQueryService(databasePath: dbPath)

    var totalPulled = 0
    var totalImported = 0
    var cursor = config.lastPullSequence
    var hasMore = true

    if !json {
      print("Pulling from \(CLIStyle.cyanText(config.serverURL)) \(CLIStyle.dimText("(cursor: \(cursor))"))...")
    }

    while hasMore {
      var queryItems = [
        URLQueryItem(name: "since", value: String(cursor)),
        URLQueryItem(name: "limit", value: "200"),
      ]
      if let proj = project {
        queryItems.append(URLQueryItem(name: "project_id", value: proj))
      }

      let (data, status) = try cloudRequest(
        config: config, method: "GET", path: "/api/v1/sync/pull",
        queryItems: queryItems)

      guard status == 200 else {
        let body = String(data: data, encoding: .utf8) ?? "unknown"
        throw CloudError.apiError(status, body)
      }

      guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CloudError.invalidResponse
      }

      let entries = result["entries"] as? [[String: Any]] ?? []
      let projects = result["projects"] as? [[String: Any]] ?? []
      let transcripts = result["transcripts"] as? [[String: Any]] ?? []
      let summaries = result["summaries"] as? [[String: Any]] ?? []
      hasMore = result["has_more"] as? Bool ?? false
      let nextCursor = result["next_cursor"] as? Int ?? cursor

      // Guard against non-advancing cursors to prevent infinite loops
      if hasMore && nextCursor <= cursor {
        throw CloudError.apiError(500, "Protocol error: next_cursor did not advance (stuck at \(cursor))")
      }
      cursor = nextCursor

      totalPulled += entries.count

      if !entries.isEmpty {
        let importResult = try queryService.importFromCloudPull(
          projects: projects,
          transcripts: transcripts,
          entries: entries,
          summaries: summaries
        )
        totalImported += importResult.entriesImported

        if !json {
          print(CLIStyle.dimText("  Received \(entries.count) entries, imported \(importResult.entriesImported), skipped \(importResult.entriesSkipped) (cursor: \(cursor))"))
        }
      }
    }

    config.lastPullSequence = cursor
    try config.save()

    if json {
      let output: [String: Any] = [
        "pulled": totalPulled, "imported": totalImported, "cursor": cursor,
      ]
      let data = try JSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
      print(String(data: data, encoding: .utf8)!)
    } else {
      print(CLIStyle.success("Pull complete: \(totalPulled) received, \(totalImported) imported, cursor at \(cursor)"))
    }
  }

  private func resolveDbPath() -> String {
    if let dbFlag = db { return XDGPaths.expandTilde(dbFlag) }
    return XDGPaths.databasePath.path
  }
}

// MARK: - Sync Command

struct CloudSyncCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sync",
    abstract: "Full sync (push + pull)",
    discussion: """
      Push local entries to cloud, then pull entries from other devices.

      EXAMPLES:
        contextify cloud sync
      """
  )

  @Option(name: .long, help: "Path to the SQLite database file")
  var db: String?

  @Option(name: .long, help: "Filter to specific project ID")
  var project: String?

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    if !json { print("\n\(CLIStyle.header("Push"))") }
    var push = CloudPushCommand()
    push.db = db
    push.limit = 500
    push.json = json
    try push.run()

    if !json { print("\n\(CLIStyle.header("Pull"))") }
    var pull = CloudPullCommand()
    pull.db = db
    pull.project = project
    pull.json = json
    try pull.run()

    if !json { print("\n" + CLIStyle.success("Sync complete.")) }
  }
}

// MARK: - Search Command

struct CloudSearchCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "search",
    abstract: "Search cloud entries",
    discussion: """
      Full-text search across all transcript entries synced to your cloud server.
      Returns ranked results with highlighted snippet excerpts.

      EXAMPLES:
        contextify cloud search "memory leak"
        contextify cloud search "refactor" --project contextify
        contextify cloud search "database" --limit 10
        contextify cloud search "config" --json
        contextify cloud search "error" --offset 20
      """
  )

  private static let entryDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f
  }()

  @Argument(help: "Search query text")
  var query: String

  @Option(name: .long, help: "Filter to specific project ID")
  var project: String?

  @Option(name: .long, help: "Maximum number of results (default: 20, max: 100)")
  var limit: Int = 20

  @Option(name: .long, help: "Offset for pagination (default: 0)")
  var offset: Int = 0

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    // Validate inputs
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      throw ValidationError("Search query cannot be empty")
    }
    guard limit >= 1 && limit <= 100 else {
      throw ValidationError("--limit must be between 1 and 100")
    }
    guard offset >= 0 else {
      throw ValidationError("--offset must be >= 0")
    }

    // Load cloud config
    let config: CLICloudConfig
    do {
      config = try CLICloudConfig.load()
    } catch {
      if json {
        print(#"{"error":"not_configured","message":"Cloud not configured. Run 'contextify cloud setup' first."}"#)
      } else {
        print(CLIStyle.error("Cloud not configured. Run '\(CLIStyle.cyanText("contextify cloud setup"))' first."))
      }
      throw ExitCode(1)
    }

    // Build query parameters
    var queryItems = [
      URLQueryItem(name: "q", value: trimmedQuery),
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "offset", value: String(offset)),
    ]
    if let proj = project {
      queryItems.append(URLQueryItem(name: "project_id", value: proj))
    }

    // Make the request
    let (data, status) = try cloudRequest(
      config: config, method: "GET", path: "/api/v1/search",
      queryItems: queryItems)

    // Handle error responses
    if status == 401 || status == 403 {
      if json {
        print(#"{"error":"auth_error","message":"Authentication failed. Check your API key."}"#)
      } else {
        print(CLIStyle.error("Authentication failed (HTTP \(status)). Check your API key or run '\(CLIStyle.cyanText("contextify cloud setup"))'."))
      }
      throw ExitCode(1)
    }

    guard status == 200 else {
      let body = String(data: data, encoding: .utf8) ?? "unknown"
      throw CloudError.apiError(status, body)
    }

    // JSON mode: pass through the server response directly
    if json {
      print(String(data: data, encoding: .utf8) ?? "{}")
      return
    }

    // Human-readable mode: parse and format
    guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CloudError.invalidResponse
    }

    let results = response["results"] as? [[String: Any]] ?? []
    let totalCount = (response["total_count"] as? NSNumber)?.intValue ?? 0
    let queryMs = (response["query_ms"] as? NSNumber)?.doubleValue ?? 0
    let hasMore = response["has_more"] as? Bool ?? false

    if results.isEmpty {
      print(CLIStyle.dimText("No results found for \"\(trimmedQuery)\"."))
      return
    }

    print("\(CLIStyle.boldText("Found \(totalCount) result\(totalCount == 1 ? "" : "s")")) for \"\(CLIStyle.cyanText(trimmedQuery))\" \(CLIStyle.dimText("(\(formatQueryMs(queryMs)))"))\n")

    for (index, result) in results.enumerated() {
      let kind = result["kind"] as? String ?? "unknown"
      let rawTs = (result["timestamp"] as? NSNumber)?.doubleValue ?? 0
      let timestamp = Int(rawTs)
      let projectId = result["project_id"] as? String ?? ""
      let projectName = result["project_name"] as? String
      let score = (result["score"] as? NSNumber)?.doubleValue ?? 0
      let snippet = result["snippet"] as? String ?? ""

      let displayProject = projectName ?? projectId
      let dateStr = formatEntryTimestamp(timestamp)
      let num = offset + index + 1

      print("\(CLIStyle.boldText("\(num).")) \(CLIStyle.cyanText("[\(kind)]")) \(dateStr)  \(CLIStyle.dimText("(project: \(displayProject), score: \(String(format: "%.2f", score)))"))")
      // Apply ANSI bold from HTML bold tags with escape injection protection
      let cleanSnippet = CLIStyle.styledSnippet(snippet)
      // Indent snippet lines
      let lines = cleanSnippet.components(separatedBy: "\n")
      for line in lines.prefix(4) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          print("   \(CLIStyle.dimText(trimmed))")
        }
      }
      print()
    }

    // Pagination hint
    if hasMore {
      let nextOffset = offset + limit
      print(CLIStyle.dimText("Showing \(offset + 1)-\(offset + results.count) of \(totalCount) results. Use \(CLIStyle.cyanText("--offset \(nextOffset)")) for next page."))
    } else if totalCount > results.count {
      print(CLIStyle.dimText("Showing \(offset + 1)-\(offset + results.count) of \(totalCount) results."))
    }
  }

  /// Format query duration for display
  private func formatQueryMs(_ ms: Double) -> String {
    if ms < 1 {
      return "<1ms"
    }
    return "\(Int(ms.rounded()))ms"
  }

  /// Format epoch timestamp as human-readable date/time.
  /// Tolerates both seconds and milliseconds from the server.
  private func formatEntryTimestamp(_ timestamp: Int) -> String {
    guard timestamp > 0 else { return "unknown" }
    // Heuristic: timestamps above 10 billion are likely milliseconds
    let seconds = timestamp > 10_000_000_000 ? Double(timestamp) / 1000.0 : Double(timestamp)
    let date = Date(timeIntervalSince1970: seconds)
    return Self.entryDateFormatter.string(from: date)
  }

}

// MARK: - Helpers

/// Stable machine identifier for device registration
private func getStableMachineId() -> String {
  #if os(macOS)
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
  process.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  try? process.run()
  process.waitUntilExit()
  let output = String(
    data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  if let range = output.range(of: "IOPlatformUUID\" = \"") {
    let start = range.upperBound
    if let end = output[start...].firstIndex(of: "\"") {
      return String(output[start..<end])
    }
  }
  return ProcessInfo.processInfo.hostName
  #else
  if let id = try? String(contentsOfFile: "/etc/machine-id", encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines) {
    return id
  }
  return ProcessInfo.processInfo.hostName
  #endif
}

/// Get a human-readable machine name for device identity
private func getLocalMachineName() -> String {
  #if os(macOS)
  return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
  #else
  return ProcessInfo.processInfo.hostName
  #endif
}

/// Build push payload from exported data
private func buildPushPayload(
  exportData: CloudPushExport,
  machineId: String,
  machineName: String?,
  osName: String
) -> [String: Any] {
  let appVersion = ProcessInfo.processInfo.environment["CONTEXTIFY_CLI_VERSION"] ?? "unknown"
  let resolvedName: String
  if let name = machineName, !name.isEmpty {
    resolvedName = name
  } else {
    #if os(macOS)
    resolvedName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    #else
    resolvedName = ProcessInfo.processInfo.hostName
    #endif
  }

  return [
    "idempotency_key": UUID().uuidString,
    "device": [
      "machine_id": machineId,
      "machine_name": resolvedName,
      "os": osName,
      "app_version": appVersion,
    ] as [String: Any],
    "projects": exportData.projects.map { $0.asDictionary },
    "transcripts": exportData.transcripts.map { $0.asDictionary },
    "entries": exportData.entries.map { $0.asDictionary },
    "summaries": [] as [Any],
    "usage": [] as [Any],
    "tool_invocations": [] as [Any],
    "transcript_metadata": [] as [Any],
  ]
}
