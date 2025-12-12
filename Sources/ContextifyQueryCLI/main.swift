import ContextifyCore
import Foundation

private let responseSchemaVersion = 1

private struct SuccessEnvelope<T: Encodable>: Encodable {
  let type: String
  let schemaVersion: Int
  let data: T
  let meta: [String: String]?
}

private struct ErrorEnvelope: Encodable {
  let type: String = "error"
  let code: String
  let message: String
}

private enum ExitCode: Int32 {
  case success = 0
  case entryNotFound = 1
  case dbNotFound = 2
  case featureUnavailable = 3
  case invalidArgs = 64
  case unknown = 70
}

private struct CLIError: Error {
  let code: String
  let message: String
  let exitCode: ExitCode
}

@main
struct ContextifyQueryCLI {
  enum Command: String {
    case search
    case activity
    case projects
    case summaries
    case stats
    case version
  }

  struct Options {
    var dbPath: String?
    var dbDir: String?
    var projectId: String?
    var project: String?
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

      // Parse global flags anywhere (before/after the command).
      var remaining: [String] = []
      var index = 0
      while index < args.count {
        let arg = args[index]
        switch arg {
        case "--db-path":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing path after --db-path", exitCode: .invalidArgs) }
          options.dbPath = args[index]
        case "--db-dir":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing dir after --db-dir", exitCode: .invalidArgs) }
          options.dbDir = args[index]
        case "--project-id":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing id after --project-id", exitCode: .invalidArgs) }
          options.projectId = args[index]
        case "--project":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing path after --project", exitCode: .invalidArgs) }
          options.project = args[index]
        case "--limit":
          index += 1
          guard index < args.count, let n = Int(args[index]) else {
            throw CLIError(code: "invalidArgs", message: "Missing/invalid number after --limit", exitCode: .invalidArgs)
          }
          guard n > 0 else { throw CLIError(code: "invalidArgs", message: "--limit must be > 0", exitCode: .invalidArgs) }
          options.limit = n
        case "--json":
          options.jsonOutput = true
        case "--help", "-h":
          usage(nil)
        default:
          if arg.hasPrefix("--") {
            throw CLIError(code: "invalidArgs", message: "Unknown option: \(arg)", exitCode: .invalidArgs)
          }
          remaining.append(arg)
        }
        index += 1
      }

      // Remaining args contain command + command args.
      guard let commandString = remaining.first, let command = Command(rawValue: commandString) else {
        usage("Missing or unknown command")
      }
      let commandArgs = Array(remaining.dropFirst())

      let dbURL = try resolveDatabaseURL(options: options)
      let service = try ContextifyQueryService(databaseURL: dbURL)
      let versionInfo = try service.versionInfo()

      switch command {
      case .search:
        guard !commandArgs.isEmpty else {
          throw CLIError(code: "invalidArgs", message: "Missing search query", exitCode: .invalidArgs)
        }
        let query = commandArgs.joined(separator: " ")
        try validateCapability(command: command, dbURL: dbURL, versionInfo: versionInfo)
        let results = try service.ftsSearch(query: query, projectId: options.projectId, limit: options.limit)
        try printResponse(type: "search", data: results, json: options.jsonOutput) {
          printTranscriptEntries(results)
        }

      case .activity:
        let results = try service.recentActivity(projectId: options.projectId, limit: options.limit)
        try printResponse(type: "activity", data: results, json: options.jsonOutput) {
          printTranscriptEntries(results)
        }

      case .projects:
        let results = try service.listProjects(includeHidden: false, limit: nil)
        try printResponse(type: "projects", data: results, json: options.jsonOutput) {
          printProjects(results)
        }

      case .summaries:
        try validateCapability(command: command, dbURL: dbURL, versionInfo: versionInfo)
        let results = try service.summaries(projectId: options.projectId, limit: options.limit)
        try printResponse(type: "summaries", data: results, json: options.jsonOutput) {
          printTranscriptSummaries(results)
        }

      case .stats:
        let results = try service.projectStats(projectId: options.projectId)
        try printResponse(type: "stats", data: results, json: options.jsonOutput) {
          printProjectStats(results)
        }

      case .version:
        try printResponse(type: "version", data: versionInfo, json: options.jsonOutput) {
          printVersionInfo(versionInfo)
        }
      }
    } catch let cliError as CLIError {
      emitError(cliError, json: CommandLine.arguments.contains("--json"))
      exit(cliError.exitCode.rawValue)
    } catch {
      let cliError = CLIError(code: "unknown", message: error.localizedDescription, exitCode: .unknown)
      emitError(cliError, json: CommandLine.arguments.contains("--json"))
      exit(cliError.exitCode.rawValue)
    }
  }

  private static func resolveDatabaseURL(options: Options) throws -> URL {
    if let dbPath = options.dbPath {
      let url = URL(fileURLWithPath: dbPath)
      guard isRegularFile(url) else {
        throw CLIError(code: "dbNotFound", message: "Database file not found at \(dbPath).", exitCode: .dbNotFound)
      }
      return url
    }
    if let dbDir = options.dbDir {
      let url = URL(fileURLWithPath: dbDir).appendingPathComponent("contextify.db")
      guard isRegularFile(url) else {
        throw CLIError(code: "dbNotFound", message: "Database file not found at \(url.path).", exitCode: .dbNotFound)
      }
      return url
    }

    // Preferences resolution (custom path, if set).
    if let customDir = HUDPreferences.getCustomDatabaseLocation() {
      let url = URL(fileURLWithPath: customDir).appendingPathComponent("contextify.db")
      if isRegularFile(url) {
        return url
      }
    }
    if let legacyDir = HUDPreferences.getLegacyDatabaseLocation() {
      let url = URL(fileURLWithPath: legacyDir).appendingPathComponent("contextify.db")
      if isRegularFile(url) {
        return url
      }
    }

    // Sidecar discovery at default locations (DMG + App Store container).
    for root in try candidateDatabaseDirectories() {
      let stateURL = root.appendingPathComponent(".state/state.json")
      if let discovered = try discoverDatabaseURL(from: stateURL), isRegularFile(discovered) {
        return discovered
      }

      let dbURL = root.appendingPathComponent("contextify.db")
      if isRegularFile(dbURL) {
        return dbURL
      }
    }

    throw NSError(
      domain: "contextify-query",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "Open Contextify once to initialize discovery."]
    )
  }

  private static func candidateDatabaseDirectories() throws -> [URL] {
    var candidates: [URL] = [try defaultDatabaseDirectory()]

    let home = FileManager.default.homeDirectoryForCurrentUser
    for bundleId in ["sh.contextify.Contextify"] {
      let containerSupport = home
        .appendingPathComponent("Library/Containers", isDirectory: true)
        .appendingPathComponent(bundleId, isDirectory: true)
        .appendingPathComponent("Data/Library/Application Support/Contextify", isDirectory: true)
      candidates.append(containerSupport)
    }

    return candidates
  }

  private static func discoverDatabaseURL(from stateURL: URL) throws -> URL? {
    guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
    let data = try Data(contentsOf: stateURL)
    let sidecar = try JSONDecoder().decode(StateSidecar.self, from: data)
    guard let databasePath = sidecar.databasePath else { return nil }
    return URL(fileURLWithPath: databasePath)
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

  private static func validateCapability(
    command: Command,
    dbURL: URL,
    versionInfo: ContextifyQueryService.VersionInfo
  ) throws {
    let dir = dbURL.deletingLastPathComponent()
    let sidecarURL = dir.appendingPathComponent(".state/state.json")

    var sidecarCapabilities: [String]?
    if FileManager.default.fileExists(atPath: sidecarURL.path) {
      let data = try Data(contentsOf: sidecarURL)
      let sidecar = try JSONDecoder().decode(StateSidecar.self, from: data)
      sidecarCapabilities = sidecar.capabilities
    }

    let required: String?
    switch command {
    case .search:
      required = "fts_search"
    case .summaries:
      required = "summaries"
    default:
      required = nil
    }

    guard let required else { return }

    let sidecarDenies = sidecarCapabilities.map { !$0.contains(required) } ?? false
    let liveSupports: Bool
    switch command {
    case .search:
      liveSupports = versionInfo.ftsEnabled
    case .summaries:
      liveSupports = versionInfo.summariesEnabled
    default:
      liveSupports = true
    }

    guard liveSupports else {
      let reason: String
      switch command {
      case .search:
        reason = "FTS search table missing (transcript_entries_fts)."
      case .summaries:
        reason = "Summaries table missing (transcript_metadata)."
      default:
        reason = "Database does not support this command."
      }
      throw CLIError(
        code: "featureUnavailable",
        message: "\(reason) Open Contextify to run migrations, or pass a different --db-path.",
        exitCode: .featureUnavailable
      )
    }

    if sidecarDenies {
      // Sidecar is treated as an advisory hint; prefer live DB state.
      return
    }
  }

  private static func printResponse<T: Encodable>(
    type: String,
    data: T,
    json: Bool,
    human: () -> Void
  ) throws {
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let payload = SuccessEnvelope(type: type, schemaVersion: responseSchemaVersion, data: data, meta: nil)
      let out = try encoder.encode(payload)
      FileHandle.standardOutput.write(out)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      human()
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
        --project <path>     Resolve project id from a path
        --limit <n>          Limit results (default 50)
        --json               Emit JSON output

      Commands:
        search <query>       Full-text search entries
        activity             Recent timeline activity
        projects             List projects
        summaries            Recent transcript summaries
        stats                Project statistics
        version              Database version info
      """,
      stderr
    )
    exit(message == nil ? 0 : 1)
  }
}

private func isRegularFile(_ url: URL) -> Bool {
  var isDirectory: ObjCBool = false
  guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
  return !isDirectory.boolValue
}

private func printVersionInfo(_ info: ContextifyQueryService.VersionInfo) {
  print("sqlite_user_version: \(info.sqliteUserVersion)")
  print("app_schema_version: \(info.appSchemaVersion)")
  print("fts_enabled: \(info.ftsEnabled)")
  print("summaries_enabled: \(info.summariesEnabled)")
}

private func printProjectStats(_ stats: [ContextifyQueryService.ProjectStats]) {
  if stats.isEmpty {
    print("(no projects)")
    return
  }
  for row in stats {
    let name = row.projectName?.isEmpty == false ? row.projectName! : row.projectId
    let lastTs = row.lastEntryTimestamp.map(String.init) ?? "-"
    print("\(name)  transcripts=\(row.transcriptCount)  entries=\(row.entryCount)  last_ts=\(lastTs)")
  }
}

private func printTranscriptSummaries(_ summaries: [TranscriptMetadataRecord]) {
  if summaries.isEmpty {
    print("(no summaries)")
    return
  }
  for summary in summaries {
    let title = summary.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOr("-")
    let description = summary.description.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOr("-")
    print("[\(summary.generatedAt)] \(title)")
    print("  \(description)")
  }
}

private func printTranscriptEntries(_ entries: [TranscriptEntry]) {
  if entries.isEmpty {
    print("(no results)")
    return
  }
  for entry in entries {
    let ts = String(entry.timestamp)
    let kind = entry.kind
    let preview = entry.content
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(200)
    print("[\(ts)] \(kind): \(preview)")
  }
}

private extension String {
  func nonEmptyOr(_ fallback: String) -> String {
    isEmpty ? fallback : self
  }
}

private func printProjects(_ projects: [ContextifyQueryService.ProjectListItem]) {
  if projects.isEmpty {
    print("(no projects)")
    return
  }
  for project in projects {
    let name = project.name?.isEmpty == false ? project.name! : project.id
    let lastActivity = project.lastActivityTimestamp.map(String.init) ?? "-"
    let transcripts = project.transcriptCount.map(String.init) ?? "-"
    let entries = project.entryCount.map(String.init) ?? "-"
    print("\(name)  last_ts=\(lastActivity)  transcripts=\(transcripts)  entries=\(entries)")
    print("  \(project.rootPath)")
  }
}

private func emitError(_ cliError: CLIError, json: Bool) {
  if json {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let payload = ErrorEnvelope(code: cliError.code, message: cliError.message)
      let out = try encoder.encode(payload)
      FileHandle.standardOutput.write(out)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      fputs("Error: \(cliError.message)\n", stderr)
    }
  } else {
    fputs("Error: \(cliError.message)\n", stderr)
  }
}
