import ContextifyCore
import Foundation

private struct Envelope<T: Encodable>: Encodable {
  let type: String
  let data: T
}

@main
struct ContextifyQueryCLI {
  enum Command: String {
    case search
    case activity
    case summaries
    case stats
    case version
  }

  struct Options {
    var dbPath: String?
    var dbDir: String?
    var projectId: String?
    var limit: Int = 50
    var jsonOutput: Bool = false
  }

  struct StateSidecar: Decodable {
    let databasePath: String?
    let schemaVersion: Int?
    let capabilities: [String]?

    enum CodingKeys: String, CodingKey {
      case databasePath = "database_path"
      case schemaVersion = "schema_version"
      case capabilities
    }
  }

  static func main() {
    do {
      var options = Options()
      let args = Array(CommandLine.arguments.dropFirst())

      // Parse global flags.
      var index = 0
      while index < args.count, args[index].hasPrefix("--") || args[index] == "-h" {
        let arg = args[index]
        switch arg {
        case "--db-path":
          index += 1
          guard index < args.count else { usage("Missing path after --db-path") }
          options.dbPath = args[index]
        case "--db-dir":
          index += 1
          guard index < args.count else { usage("Missing dir after --db-dir") }
          options.dbDir = args[index]
        case "--project-id":
          index += 1
          guard index < args.count else { usage("Missing id after --project-id") }
          options.projectId = args[index]
        case "--limit":
          index += 1
          guard index < args.count, let n = Int(args[index]) else { usage("Missing/invalid number after --limit") }
          options.limit = n
        case "--json":
          options.jsonOutput = true
        case "--help", "-h":
          usage(nil)
        default:
          usage("Unknown option: \(arg)")
        }
        index += 1
      }

      // Remaining args contain command + command args.
      let remaining = Array(args.dropFirst(index))
      guard let commandString = remaining.first, let command = Command(rawValue: commandString) else {
        usage("Missing or unknown command")
      }
      let commandArgs = Array(remaining.dropFirst())

      let dbURL = try resolveDatabaseURL(options: options)
      let service = try ContextifyQueryService(databaseURL: dbURL)

      switch command {
      case .search:
        guard let query = commandArgs.first else { usage("Missing search query") }
        try validateCapability(command: command, dbURL: dbURL)
        let results = try service.ftsSearch(query: query, projectId: options.projectId, limit: options.limit)
        try printResponse(type: "search", data: results, json: options.jsonOutput)

      case .activity:
        let results = try service.recentActivity(projectId: options.projectId, limit: options.limit)
        try printResponse(type: "activity", data: results, json: options.jsonOutput)

      case .summaries:
        try validateCapability(command: command, dbURL: dbURL)
        let results = try service.summaries(projectId: options.projectId, limit: options.limit)
        try printResponse(type: "summaries", data: results, json: options.jsonOutput)

      case .stats:
        let results = try service.projectStats(projectId: options.projectId)
        try printResponse(type: "stats", data: results, json: options.jsonOutput)

      case .version:
        let info = try service.versionInfo()
        try printResponse(type: "version", data: info, json: options.jsonOutput)
      }
    } catch {
      fputs("Error: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }

  private static func resolveDatabaseURL(options: Options) throws -> URL {
    if let dbPath = options.dbPath {
      return URL(fileURLWithPath: dbPath)
    }
    if let dbDir = options.dbDir {
      return URL(fileURLWithPath: dbDir).appendingPathComponent("contextify.db")
    }

    // DMG-only preference resolution.
    if !Sandbox.isSandboxed, let customDir = HUDPreferences.getCustomDatabaseLocation() {
      return URL(fileURLWithPath: customDir).appendingPathComponent("contextify.db")
    }

    // Sidecar discovery at default location.
    let defaultDir = try defaultDatabaseDirectory()
    let sidecarURL = defaultDir.appendingPathComponent(".state/state.json")
    if FileManager.default.fileExists(atPath: sidecarURL.path) {
      let data = try Data(contentsOf: sidecarURL)
      let sidecar = try JSONDecoder().decode(StateSidecar.self, from: data)
      if let databasePath = sidecar.databasePath {
        return URL(fileURLWithPath: databasePath)
      }
    }

    throw NSError(
      domain: "contextify-query",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "Open Contextify once to initialize discovery."]
    )
  }

  private static func defaultDatabaseDirectory() throws -> URL {
    let appSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false
    )
    return appSupport.appendingPathComponent("Contextify", isDirectory: true)
  }

  private static func validateCapability(command: Command, dbURL: URL) throws {
    let dir = dbURL.deletingLastPathComponent()
    let sidecarURL = dir.appendingPathComponent(".state/state.json")
    guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return }

    let data = try Data(contentsOf: sidecarURL)
    let sidecar = try JSONDecoder().decode(StateSidecar.self, from: data)
    guard let capabilities = sidecar.capabilities else { return }

    let required: String?
    switch command {
    case .search:
      required = "fts_search"
    case .summaries:
      required = "summaries"
    default:
      required = nil
    }

    if let required, !capabilities.contains(required) {
      throw NSError(
        domain: "contextify-query",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Database does not advertise capability '\(required)'."]
      )
    }
  }

  private static func printResponse<T: Encodable>(type: String, data: T, json: Bool) throws {
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let payload = Envelope(type: type, data: data)
      let out = try encoder.encode(payload)
      FileHandle.standardOutput.write(out)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      print(data)
    }
  }

  private static func usage(_ message: String?) -> Never {
    if let message {
      fputs("Error: \(message)\n\n", stderr)
    }
    fputs(
      """
      Usage: swift run contextify-query [options] <command> [args]

      Options:
        --db-path <path>     Full path to contextify.db
        --db-dir <dir>       Directory containing contextify.db
        --project-id <id>    Scope queries to a project
        --limit <n>          Limit results (default 50)
        --json               Emit JSON output

      Commands:
        search <query>       Full-text search entries
        activity             Recent timeline activity
        summaries            Recent transcript summaries
        stats                Project statistics
        version              Database version info
      """,
      stderr
    )
    exit(message == nil ? 0 : 1)
  }
}
