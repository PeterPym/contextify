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

  enum CodingKeys: String, CodingKey {
    case serverURL = "server_url"
    case apiKey = "api_key"
    case deviceId = "device_id"
    case deviceName = "device_name"
    case enabled
    case lastPullSequence = "last_pull_sequence"
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

    // Populate device identity
    let machineId = getStableMachineId()
    let machineName: String
    #if os(macOS)
    machineName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    #else
    machineName = ProcessInfo.processInfo.hostName
    #endif

    // Test connection
    print("Testing connection to \(cloudURL)...")
    let testConfig = CLICloudConfig(
      serverURL: cloudURL, apiKey: apiKey,
      deviceId: machineId, deviceName: machineName)
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
    print("Saved to \(CLICloudConfig.configFile.path)")
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
    let config: CLICloudConfig
    do {
      config = try CLICloudConfig.load()
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
        obj["cloud_url"] = config.serverURL
        obj["last_pull_sequence"] = config.lastPullSequence
        let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        print(String(data: out, encoding: .utf8)!)
      } else {
        print(String(data: data, encoding: .utf8) ?? "{}")
      }
    } else {
      print("Cloud Sync Status")
      print("=================")
      print("Server:     \(config.serverURL)")
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
    let config = try CLICloudConfig.load()

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

    // Keyset pagination: loop batches until a short page is returned
    var afterTimestamp: Int?
    var afterEntryId: String?
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
            print("No entries to push.")
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
        print("Pushing batch \(batchCount): \(exportData.entries.count) entries to \(config.serverURL)...")
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
      }

      // Advance keyset cursor from last entry in this batch
      if let last = exportData.entries.last {
        afterTimestamp = last.timestamp
        afterEntryId = last.id
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
        print("Push complete: \(totalAccepted) accepted, \(totalDuplicates) duplicates (\(batchCount) batch\(batchCount == 1 ? "" : "es"))")
        if !totalErrors.isEmpty {
          print("Errors: \(totalErrors.count)")
          for e in totalErrors.prefix(5) { print("  - \(e)") }
        }
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
      print("Pulling from \(config.serverURL) (cursor: \(cursor))...")
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
          print("  Received \(entries.count) entries, imported \(importResult.entriesImported), skipped \(importResult.entriesSkipped) (cursor: \(cursor))")
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
      print("Pull complete: \(totalPulled) received, \(totalImported) imported, cursor at \(cursor)")
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
    if !json { print("=== Push ===") }
    var push = CloudPushCommand()
    push.db = db
    push.limit = 500
    push.json = json
    try push.run()

    if !json { print("\n=== Pull ===") }
    var pull = CloudPullCommand()
    pull.db = db
    pull.project = project
    pull.json = json
    try pull.run()

    if !json { print("\nSync complete.") }
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
        print("Cloud not configured. Run 'contextify cloud setup' first.")
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
        print("Authentication failed (HTTP \(status)). Check your API key or run 'contextify cloud setup'.")
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
      print("No results found for \"\(trimmedQuery)\".")
      return
    }

    print("Found \(totalCount) result\(totalCount == 1 ? "" : "s") for \"\(trimmedQuery)\" (\(formatQueryMs(queryMs)))\n")

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

      print("\(num). [\(kind)] \(dateStr)  (project: \(displayProject), score: \(String(format: "%.2f", score)))")
      // Strip HTML bold tags and sanitize control characters for terminal safety
      let cleanSnippet = sanitizeForTerminal(stripHTMLBoldTags(snippet))
      // Indent snippet lines
      let lines = cleanSnippet.components(separatedBy: "\n")
      for line in lines.prefix(4) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          print("   \(trimmed)")
        }
      }
      print()
    }

    // Pagination hint
    if hasMore {
      let nextOffset = offset + limit
      print("Showing \(offset + 1)-\(offset + results.count) of \(totalCount) results. Use --offset \(nextOffset) for next page.")
    } else if totalCount > results.count {
      print("Showing \(offset + 1)-\(offset + results.count) of \(totalCount) results.")
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

  /// Strip <b> and </b> HTML tags from snippet text for terminal display
  private func stripHTMLBoldTags(_ text: String) -> String {
    return text
      .replacingOccurrences(of: "<b>", with: "")
      .replacingOccurrences(of: "</b>", with: "")
  }

  /// Remove terminal control characters (including ANSI escape sequences)
  /// while preserving newlines and tabs for readable output.
  private func sanitizeForTerminal(_ text: String) -> String {
    String(text.unicodeScalars.filter { s in
      if s == "\n" || s == "\r" || s == "\t" { return true }
      return !s.properties.isControl
    })
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
