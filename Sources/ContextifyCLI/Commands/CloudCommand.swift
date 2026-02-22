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

/// Configuration for cloud sync, stored in ~/.config/contextify/cloud.json
struct CloudConfig: Codable {
  var cloudURL: String
  var apiKey: String
  var enabled: Bool = true
  var lastPullSequence: Int = 0

  static var configDir: URL {
    if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
      return URL(fileURLWithPath: xdg).appendingPathComponent("contextify")
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/contextify")
  }

  static var configFile: URL { configDir.appendingPathComponent("cloud.json") }

  static func load() throws -> CloudConfig {
    let data = try Data(contentsOf: configFile)
    return try JSONDecoder().decode(CloudConfig.self, from: data)
  }

  func save() throws {
    try FileManager.default.createDirectory(
      at: CloudConfig.configDir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(self)
    try data.write(to: CloudConfig.configFile, options: .atomic)
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
  config: CloudConfig,
  method: String,
  path: String,
  body: Data? = nil,
  queryItems: [URLQueryItem]? = nil
) throws -> (Data, Int) {
  let baseURL = config.cloudURL.hasSuffix("/")
    ? String(config.cloudURL.dropLast())
    : config.cloudURL

  var components = URLComponents(string: "\(baseURL)\(path)")!
  if let queryItems = queryItems {
    components.queryItems = queryItems
  }

  var request = URLRequest(url: components.url!)
  request.httpMethod = method
  request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = body

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
  semaphore.wait()

  if let error = requestError {
    throw CloudError.networkError(error.localizedDescription)
  }
  guard let data = responseData else {
    throw CloudError.networkError("No response received")
  }
  return (data, statusCode)
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

      DOCUMENTATION: https://contextify.sh/docs/cloud/
      """,
    subcommands: [
      CloudSetupCommand.self,
      CloudStatusCommand.self,
      CloudPushCommand.self,
      CloudPullCommand.self,
      CloudSyncCommand.self,
    ]
  )
}

// MARK: - Setup Command

struct CloudSetupCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "setup",
    abstract: "Configure cloud sync connection",
    discussion: """
      Set up cloud sync by providing your cloud server URL and API key.
      Configuration is stored in ~/.config/contextify/cloud.json.

      EXAMPLES:
        contextify cloud setup
        contextify cloud setup --url https://100.x.y.z:8443 --key ctx_abc123_def456
      """
  )

  @Option(name: .long, help: "Cloud server URL")
  var url: String?

  @Option(name: .long, help: "API key (ctx_...)")
  var key: String?

  func run() throws {
    let cloudURL: String
    let apiKey: String

    if let u = url, let k = key {
      cloudURL = u
      apiKey = k
    } else {
      print("Contextify Cloud Setup")
      print("======================")
      print()
      print("Enter your cloud server URL")
      print("  (e.g., https://cloud.contextify.sh or http://100.x.y.z:8443)")
      print("> ", terminator: "")
      guard let inputURL = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !inputURL.isEmpty else {
        throw ValidationError("URL is required")
      }
      cloudURL = inputURL

      print()
      print("Enter your API key (starts with ctx_)")
      print("> ", terminator: "")
      guard let inputKey = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !inputKey.isEmpty else {
        throw ValidationError("API key is required")
      }
      apiKey = inputKey
    }

    guard URL(string: cloudURL) != nil else {
      throw ValidationError("Invalid URL: \(cloudURL)")
    }
    guard apiKey.hasPrefix("ctx_") else {
      throw ValidationError("API key must start with 'ctx_'")
    }

    // Test connection
    print("Testing connection to \(cloudURL)...")
    let testConfig = CloudConfig(cloudURL: cloudURL, apiKey: apiKey)
    do {
      let (_, status) = try cloudRequest(
        config: testConfig, method: "GET", path: "/api/v1/sync/status")
      if status == 200 {
        print("Connection successful!")
      } else if status == 401 || status == 403 {
        print("Warning: Authentication failed (HTTP \(status)). Check your API key.")
      } else {
        print("Warning: Server returned HTTP \(status). Saving config anyway.")
      }
    } catch {
      print("Warning: Could not connect: \(error)")
      print("Saving configuration anyway.")
    }

    try testConfig.save()
    print()
    print("Saved to \(CloudConfig.configFile.path)")
    print("Run 'contextify cloud status' to verify.")
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
    let config: CloudConfig
    do {
      config = try CloudConfig.load()
    } catch {
      if json {
        print(#"{"configured":false,"error":"not_configured"}"#)
      } else {
        print("Cloud sync not configured. Run 'contextify cloud setup' first.")
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
        obj["cloud_url"] = config.cloudURL
        obj["last_pull_sequence"] = config.lastPullSequence
        let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        print(String(data: out, encoding: .utf8)!)
      } else {
        print(String(data: data, encoding: .utf8) ?? "{}")
      }
    } else {
      print("Cloud Sync Status")
      print("=================")
      print("Server:     \(config.cloudURL)")
      print("Enabled:    \(config.enabled ? "yes" : "no")")
      print()

      if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let lastSync = obj["last_sync"] as? String {
          print("Last sync:  \(lastSync)")
        } else {
          print("Last sync:  never")
        }
        if let entries = obj["entries_synced"] as? Int {
          print("Entries:    \(entries)")
        }
        if let seq = obj["server_sequence"] as? Int {
          print("Server seq: \(seq)")
        }
        if let devices = obj["devices"] as? [[String: Any]] {
          print("Devices:    \(devices.count)")
          for d in devices {
            let name = d["machine_name"] as? String ?? "unknown"
            let os = d["os"] as? String ?? ""
            print("  - \(name) (\(os))")
          }
        }
      }
      print()
      print("Local pull cursor: \(config.lastPullSequence)")
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
    let config = try CloudConfig.load()

    // Resolve database path using same logic as other commands
    let dbPath = resolveDbPath()
    guard FileManager.default.fileExists(atPath: dbPath) else {
      throw ValidationError("Database not found at \(dbPath)")
    }

    let dbURL = URL(fileURLWithPath: dbPath)
    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Export entries for push using the query service
    let exportData = try service.exportForCloudPush(limit: limit)

    if exportData.entries.isEmpty {
      if json {
        print(#"{"accepted":0,"duplicates_skipped":0,"errors":[]}"#)
      } else {
        print("No entries to push.")
      }
      return
    }

    // Build push payload
    #if os(macOS)
    let osName = "macos"
    #else
    let osName = "linux"
    #endif

    let machineId = getStableMachineId()
    let payload = buildPushPayload(
      exportData: exportData,
      machineId: machineId,
      osName: osName
    )
    let bodyData = try JSONSerialization.data(withJSONObject: payload)

    if !json {
      print("Pushing \(exportData.entries.count) entries to \(config.cloudURL)...")
    }

    let (responseData, status) = try cloudRequest(
      config: config, method: "POST", path: "/api/v1/sync/push", body: bodyData)

    guard status == 200 else {
      let body = String(data: responseData, encoding: .utf8) ?? "unknown"
      throw CloudError.apiError(status, body)
    }

    if json {
      print(String(data: responseData, encoding: .utf8) ?? "{}")
    } else if let result = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
      let accepted = result["accepted"] as? Int ?? 0
      let duplicates = result["duplicates_skipped"] as? Int ?? 0
      let errors = result["errors"] as? [String] ?? []
      print("Push complete: \(accepted) accepted, \(duplicates) duplicates")
      if !errors.isEmpty {
        print("Errors: \(errors.count)")
        for e in errors.prefix(5) { print("  - \(e)") }
      }
    }
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

  @Option(name: .long, help: "Filter to specific project ID")
  var project: String?

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    var config = try CloudConfig.load()

    var totalPulled = 0
    var cursor = config.lastPullSequence
    var hasMore = true

    if !json {
      print("Pulling from \(config.cloudURL) (cursor: \(cursor))...")
    }

    while hasMore {
      var queryItems = [
        URLQueryItem(name: "since", value: String(cursor)),
        URLQueryItem(name: "limit", value: "500"),
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
      hasMore = result["has_more"] as? Bool ?? false
      cursor = result["next_cursor"] as? Int ?? cursor

      totalPulled += entries.count

      if !json && !entries.isEmpty {
        print("  Received \(entries.count) entries (cursor: \(cursor))")
      }

      // TODO: Insert pulled entries into local SQLite via ContextifyQueryService
      // For now we track the cursor; local insert requires extending the query service
    }

    config.lastPullSequence = cursor
    try config.save()

    if json {
      let output: [String: Any] = ["pulled": totalPulled, "cursor": cursor]
      let data = try JSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
      print(String(data: data, encoding: .utf8)!)
    } else {
      print("Pull complete: \(totalPulled) entries, cursor at \(cursor)")
    }
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

  @Option(name: .long, help: "Filter to specific project name")
  var project: String?

  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false

  func run() throws {
    if !json { print("=== Push ===") }
    var push = CloudPushCommand()
    push.db = db
    push.limit = 500
    push.json = json
    try push.run()

    if !json { print("\n=== Pull ===") }
    var pull = CloudPullCommand()
    pull.project = project
    pull.json = json
    try pull.run()

    if !json { print("\nSync complete.") }
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

/// Build push payload from exported data
private func buildPushPayload(
  exportData: CloudPushExport,
  machineId: String,
  osName: String
) -> [String: Any] {
  let appVersion = ProcessInfo.processInfo.environment["CONTEXTIFY_CLI_VERSION"] ?? "unknown"
  let machineName: String
  #if os(macOS)
  machineName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
  #else
  machineName = ProcessInfo.processInfo.hostName
  #endif

  return [
    "idempotency_key": UUID().uuidString,
    "device": [
      "machine_id": machineId,
      "machine_name": machineName,
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
