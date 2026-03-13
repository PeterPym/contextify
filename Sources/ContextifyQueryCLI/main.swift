#if os(macOS)
import ContextifyCore
#else
import ContextifyQueryCore
#endif
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if os(macOS)
import GRDB
#endif

// MARK: - Deprecation Warnings

/// Check if stderr is a TTY (for deprecation warning gating)
private func isStderrTTY() -> Bool {
  return isatty(STDERR_FILENO) != 0
}

/// Emit a deprecation warning to stderr if appropriate
/// Only shows when stderr is a TTY and CONTEXTIFY_NO_DEPRECATIONS is not set
private func warnDeprecated(_ message: String) {
  // Show on TTY unless explicitly suppressed
  guard isStderrTTY() ||
        ProcessInfo.processInfo.environment["CONTEXTIFY_SHOW_DEPRECATIONS"] == "1" else {
    return
  }
  guard ProcessInfo.processInfo.environment["CONTEXTIFY_NO_DEPRECATIONS"] != "1" else {
    return
  }
  FileHandle.standardError.write(Data("Warning: \(message)\n".utf8))
}

/// Get the executable name from argv[0]
private func executableName() -> String {
  return URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
}

/// Check if running as legacy contextify-query
private func isLegacyInvocation() -> Bool {
  return executableName() == "contextify-query"
}

// MARK: - Response Types

private enum ResponseConstants {
  static let schemaVersion = 1
  static let maxContextWindowCap = 2000
}

private struct SuccessEnvelope<T: Encodable>: Encodable {
  let type: String
  let schemaVersion: Int
  let data: T
  let metadata: JSONValue?
}

private struct ErrorEnvelope: Encodable {
  let type: String = "error"
  let code: String
  let message: String
  let details: JSONValue?
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
  let details: JSONValue?

  init(code: String, message: String, exitCode: ExitCode, details: JSONValue? = nil) {
    self.code = code
    self.message = message
    self.exitCode = exitCode
    self.details = details
  }
}

/// Result of resolving project scope for worktree expansion
private struct ProjectScope {
  let projectIds: [String]
  let displayNames: [String]
  let unresolvedSiblings: [String]
  let excluded: [String]
  let worktreeGroupDetected: Bool  // Was a worktree group found?
  let worktreesConsidered: [String]  // All worktrees in the group
  let expansionApplied: Bool  // Did multiple worktrees resolve to DB?
}

@main
struct ContextifyQueryCLI {
  enum Command: String {
    #if os(macOS)
    case search
    case activity
    case projects
    case transcripts
    case entry
    case context
    case status
    case feedback
    case summaries
    case stats
    case version
    #endif
    case installPlugin = "install-plugin"
    case uninstallPlugin = "uninstall-plugin"
    case doctor
  }

  struct Options {
    var dbPath: String?
    var dbDir: String?
    var projectId: String?
    var project: String?
    var transcriptId: String?
    var since: String?
    var until: String?
    var days: Int?
    var includeHidden: Bool = false
    var before: Int?
    var after: Int?
    var kinds: String?
    var noContent: Bool = false
    var fullContent: Bool = false
    var maxWindow: Int?
    var limitWasProvided: Bool = false
    var limit: Int = 50
    var offset: Int = 0
    var snippetTokens: Int?
    var jsonOutput: Bool = false

    // Feedback options
    var intent: String?
    var gap: String?
    var workaround: String?
    var proposal: String?
    var format: String?
    var olderThanDays: Int?
    var all: Bool = false
    var force: Bool = false
    var edit: Bool = false

    // Search options
    var countOnly: Bool = false
    var termCounts: Bool = false
    var anchorGit: Bool = false

    // Worktree options
    var thisWorktreeOnly: Bool = false
    var exclude: String?
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

  static let cliVersion = "1.3.2"

  static func main() {
    // Emit deprecation warning if invoked as contextify-query
    if isLegacyInvocation() {
      warnDeprecated("'contextify-query' is deprecated. Use 'contextify' instead.")
    }

    // Handle --version early (before any other parsing)
    let allArgs = CommandLine.arguments
    if allArgs.contains("--version") || allArgs.contains("-v") {
      // Use actual executable name in version output
      print("\(executableName()) \(cliVersion)")
      exit(0)
    }

    let jsonWanted = allArgs.contains("--json")
    do {
      var options = Options()
      let args = Array(allArgs.dropFirst())

      // Parse global flags anywhere (before/after the command).
      var remaining: [String] = []
      var index = 0
      while index < args.count {
        let arg = args[index]
        switch arg {
        case "--":
          let restIndex = index + 1
          if restIndex < args.count {
            remaining.append(contentsOf: args[restIndex...])
          }
          index = args.count
          continue
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
        case "--transcript-id":
          index += 1
          guard index < args.count else {
            throw CLIError(code: "invalidArgs", message: "Missing id after --transcript-id", exitCode: .invalidArgs)
          }
          options.transcriptId = args[index]
        case "--since":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing value after --since", exitCode: .invalidArgs) }
          options.since = args[index]
        case "--until":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing value after --until", exitCode: .invalidArgs) }
          options.until = args[index]
        case "--days":
          index += 1
          guard index < args.count, let n = Int(args[index]) else {
            throw CLIError(code: "invalidArgs", message: "Missing/invalid number after --days", exitCode: .invalidArgs)
          }
          options.days = n
        case "--include-hidden":
          options.includeHidden = true
        case "--before":
          index += 1
          guard index < args.count, let n = Int(args[index]), n >= 0 else {
            throw CLIError(code: "invalidArgs", message: "Missing/invalid number after --before", exitCode: .invalidArgs)
          }
          options.before = n
        case "--after":
          index += 1
          guard index < args.count, let n = Int(args[index]), n >= 0 else {
            throw CLIError(code: "invalidArgs", message: "Missing/invalid number after --after", exitCode: .invalidArgs)
          }
          options.after = n
        case "--kinds":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing value after --kinds", exitCode: .invalidArgs) }
          options.kinds = args[index]
        case "--no-content":
          options.noContent = true
        case "--full-content":
          options.fullContent = true
        case "--max-window":
          index += 1
          guard index < args.count, let n = Int(args[index]), n > 0 else {
            throw CLIError(code: "invalidArgs", message: "Missing/invalid number after --max-window", exitCode: .invalidArgs)
          }
          guard n <= ResponseConstants.maxContextWindowCap else {
            throw CLIError(code: "invalidArgs", message: "--max-window must be <= \(ResponseConstants.maxContextWindowCap)", exitCode: .invalidArgs)
          }
          options.maxWindow = n
        case "--intent":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing value after --intent", exitCode: .invalidArgs) }
          options.intent = args[index]
        case "--gap":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing value after --gap", exitCode: .invalidArgs) }
          options.gap = args[index]
        case "--workaround":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing value after --workaround", exitCode: .invalidArgs) }
          options.workaround = args[index]
        case "--proposal":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing value after --proposal", exitCode: .invalidArgs) }
          options.proposal = args[index]
        case "--format":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing value after --format", exitCode: .invalidArgs) }
          options.format = args[index]
        case "--older-than-days":
          index += 1
          guard index < args.count, let n = Int(args[index]), n >= 0 else {
            throw CLIError(code: "invalidArgs", message: "Missing/invalid number after --older-than-days", exitCode: .invalidArgs)
          }
          options.olderThanDays = n
        case "--all":
          options.all = true
        case "--force":
          options.force = true
        case "--edit":
          options.edit = true
        case "--limit":
          index += 1
          guard index < args.count, let n = Int(args[index]) else {
            throw CLIError(code: "invalidArgs", message: "Missing/invalid number after --limit", exitCode: .invalidArgs)
          }
          guard n > 0 else { throw CLIError(code: "invalidArgs", message: "--limit must be > 0", exitCode: .invalidArgs) }
          options.limitWasProvided = true
          options.limit = n
        case "--offset":
          index += 1
          guard index < args.count, let n = Int(args[index]) else {
            throw CLIError(code: "invalidArgs", message: "Missing/invalid number after --offset", exitCode: .invalidArgs)
          }
          guard n >= 0 else { throw CLIError(code: "invalidArgs", message: "--offset must be >= 0", exitCode: .invalidArgs) }
          options.offset = n
        case "--snippet-tokens":
          index += 1
          guard index < args.count, let n = Int(args[index]) else {
            throw CLIError(code: "invalidArgs", message: "Missing/invalid number after --snippet-tokens", exitCode: .invalidArgs)
          }
          guard n >= 1 && n <= 100 else {
            throw CLIError(code: "invalidArgs", message: "--snippet-tokens must be between 1 and 100", exitCode: .invalidArgs)
          }
          options.snippetTokens = n
        case "--json":
          options.jsonOutput = true
        case "--count-only":
          options.countOnly = true
        case "--term-counts":
          options.termCounts = true
        case "--anchor-git":
          options.anchorGit = true
        case "--this-worktree":
          options.thisWorktreeOnly = true
        case "--exclude":
          index += 1
          guard index < args.count else { throw CLIError(code: "invalidArgs", message: "Missing value after --exclude", exitCode: .invalidArgs) }
          options.exclude = args[index]
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

      // Commands that don't need database connection
      switch command {
      case .installPlugin:
        try runInstallPlugin(options: options)
        return

      case .uninstallPlugin:
        try runUninstallPlugin(options: options)
        return

      case .doctor:
        try runDoctor(options: options)
        return

      #if os(macOS)
      default:
        break
      #endif
      }

      #if os(macOS)
      // All other commands need database (macOS only)
      let dbURL = try resolveDatabaseURL(options: options)
      let service = try ContextifyQueryService(databaseURL: dbURL)
      let versionInfo = try service.versionInfo()
      let timeRange = try parseTimeRange(options: options)

      switch command {
      case .search:
        guard !commandArgs.isEmpty else {
          throw CLIError(code: "invalidArgs", message: "Missing search query", exitCode: .invalidArgs)
        }
        guard options.limit <= 500 else {
          throw CLIError(code: "invalidArgs", message: "--limit must be <= 500 for search", exitCode: .invalidArgs)
        }
        if options.noContent {
          fputs("Warning: --no-content has no effect on search (snippets are always returned)\n", stderr)
        }
        let rawQuery = commandArgs.joined(separator: " ")
        let query = try buildSearchQuery(rawQuery)
        try validateCapability(command: command, dbURL: dbURL, versionInfo: versionInfo)
        let scope = try resolveProjectScope(options: options, service: service)

        // Print scope info to stderr when worktree group detected
        if scope.worktreeGroupDetected {
          if options.thisWorktreeOnly {
            fputs("Worktree group detected; searching current only (--this-worktree)\n", stderr)
          } else if scope.expansionApplied {
            fputs("Including worktrees: \(scope.displayNames.joined(separator: ", "))\n", stderr)
            fputs("(use --this-worktree to search only current)\n", stderr)
          } else {
            // Only one worktree resolved to DB (others excluded/archived/not indexed)
            fputs("Worktree group detected, but only \(scope.displayNames.first ?? "current") is indexed\n", stderr)
          }

          if !scope.unresolvedSiblings.isEmpty {
            fputs("Note: \(scope.unresolvedSiblings.joined(separator: ", ")) not in database\n", stderr)
          }
          if !scope.excluded.isEmpty {
            fputs("Excluded: \(scope.excluded.joined(separator: ", "))\n", stderr)
          }
        }

        let kinds = parseCSV(options.kinds)?.map { $0.lowercased() }
        let projectIds = scope.projectIds.isEmpty ? nil : scope.projectIds

        if options.countOnly {
          // Count-only mode: return total count (and term counts for OR queries) without result bodies
          let totalCount = try service.searchCount(
            query: query,
            projectIds: projectIds,
            transcriptId: options.transcriptId,
            includeHidden: options.includeHidden,
            timeRange: timeRange,
            kinds: kinds,
            treatAsFTS: true
          )

          var metadataDict: [String: JSONValue] = [
            "totalCount": .number(Double(totalCount))
          ]

          if options.termCounts {
            if let termCounts = try service.searchTermCounts(
              query: query,
              projectIds: projectIds,
              transcriptId: options.transcriptId,
              includeHidden: options.includeHidden,
              timeRange: timeRange,
              kinds: kinds
            ) {
              metadataDict["termCounts"] = .object(
                termCounts.reduce(into: [String: JSONValue]()) { dict, pair in
                  dict[pair.key] = .number(Double(pair.value))
                }
              )
            }
          }

          let emptyResults: [ContextifyQueryService.SearchHit] = []
          let metadata: JSONValue = .object(metadataDict)
          try printResponse(type: "search", data: emptyResults, json: options.jsonOutput, metadata: metadata) {
            if let tc = metadataDict["termCounts"], case .object(let terms) = tc {
              let lines = terms.sorted(by: { $0.key < $1.key }).map { key, val -> String in
                if case .number(let n) = val { return "  \(key): \(Int(n))" }
                return "  \(key): ?"
              }
              print("Term counts:\n\(lines.joined(separator: "\n"))")
              print("Total: \(totalCount)")
            } else {
              print("Total matches: \(totalCount)")
            }
          }
        } else {
          // Normal mode: fetch results with metadata
          let requestedLimit = options.limit
          let requestedOffset = options.offset
          let anchorCues = options.anchorGit ? GitAnchorSearch.extractCues(from: rawQuery) : []
          let anchorPlan = anchorCues.isEmpty ? nil : resolveGitAnchorPlan(cues: anchorCues, options: options)

          if options.anchorGit {
            if let anchorPlan {
              let fileLabels = anchorPlan.fileLabels
              if !fileLabels.isEmpty {
                fputs("Using git anchors from: \(fileLabels.joined(separator: ", "))\n", stderr)
              } else {
                fputs("Using git anchors from query cues: \(anchorPlan.triggerKinds.joined(separator: ", "))\n", stderr)
              }
              fputs("Found \(anchorPlan.commits.count) relevant commits, narrowing search to nearby conversations\n", stderr)
            } else if !anchorCues.isEmpty {
              fputs("Git anchor path found no strong commit signal, continuing with broad text search\n", stderr)
            }
          }

          let fetchLimit = anchorPlan == nil ? requestedLimit + 1 : min(max(requestedLimit * 3, 25), 100)
          let results = try service.search(
            query: query,
            projectIds: projectIds,
            transcriptId: options.transcriptId,
            limit: fetchLimit,
            offset: requestedOffset,
            includeHidden: options.includeHidden,
            timeRange: timeRange,
            kinds: kinds,
            snippetTokens: options.snippetTokens ?? 10,
            treatAsFTS: true
          )
          let anchorResult = anchorPlan.map {
            GitAnchorSearch.rerank(hits: results, using: $0, requestedLimit: requestedLimit)
          }
          let displayResults = anchorResult?.hits ?? Array(results.prefix(requestedLimit))
          let trimmedResults = Array(displayResults.prefix(requestedLimit))
          let hasMore = results.count > requestedLimit

          // Compute source counts by grouping results by projectId
          let sourceCounts = Dictionary(grouping: trimmedResults, by: { $0.projectId })
            .mapValues { $0.count }
            .sorted { $0.key < $1.key }
            .reduce(into: [String: JSONValue]()) { dict, pair in
              dict[pair.key] = .number(Double(pair.value))
            }

          let totalCount: Int
          if hasMore || anchorResult != nil {
            totalCount = try service.searchCount(
              query: query,
              projectIds: projectIds,
              transcriptId: options.transcriptId,
              includeHidden: options.includeHidden,
              timeRange: timeRange,
              kinds: kinds,
              treatAsFTS: true
            )
          } else {
            totalCount = trimmedResults.count
          }

          var metadataDict: [String: JSONValue] = [
            "returned": .number(Double(trimmedResults.count)),
            "limit": .number(Double(requestedLimit)),
            "offset": .number(Double(requestedOffset)),
            "hasMore": .bool(hasMore),
            "totalCount": .number(Double(totalCount))
          ]

          // Add per-term counts for OR queries (opt-in via --term-counts)
          if options.termCounts {
            if let termCounts = try service.searchTermCounts(
              query: query,
              projectIds: projectIds,
              transcriptId: options.transcriptId,
              includeHidden: options.includeHidden,
              timeRange: timeRange,
              kinds: kinds
            ) {
              metadataDict["termCounts"] = .object(
                termCounts.reduce(into: [String: JSONValue]()) { dict, pair in
                  dict[pair.key] = .number(Double(pair.value))
                }
              )
            }
          }

          if let anchorPlan {
            metadataDict["gitAnchor"] = .object([
              "enabled": .bool(true),
              "triggerKinds": .array(anchorPlan.triggerKinds.map(JSONValue.string)),
              "files": .array(anchorPlan.fileLabels.map(JSONValue.string)),
              "commitCount": .number(Double(anchorPlan.commits.count)),
              "topResultsChanged": .bool(anchorResult?.topResultsChanged ?? false)
            ])

            if anchorResult?.topResultsChanged == true {
              fputs("Git anchors changed the top result ordering\n", stderr)
            }
          }

          // Add worktree expansion metadata when group detected
          if scope.worktreeGroupDetected {
            metadataDict["worktreeExpansion"] = .object([
              "enabled": .bool(scope.expansionApplied),
              "worktrees": .array(scope.displayNames.map { .string($0) }),
              "excluded": .array(scope.excluded.map { .string($0) }),
              "unresolved": .array(scope.unresolvedSiblings.map { .string($0) })
            ])
            metadataDict["sourceCounts"] = .object(sourceCounts)

            // Skew warning: when results truncated and >90% from one worktree
            // Only show when expansion was actually applied and we have 2+ projects
            if hasMore && !trimmedResults.isEmpty && scope.expansionApplied && scope.projectIds.count >= 2 {
              let maxCount = sourceCounts.values.compactMap { value -> Int? in
                if case .number(let n) = value { return Int(n) }
                return nil
              }.max() ?? 0
              let total = trimmedResults.count
              // Also require minimum result count to avoid noisy warnings for small limits
              if total >= 10 && Double(maxCount) / Double(total) > 0.9 {
                fputs("Note: Results heavily skewed to one worktree. Consider --limit \(requestedLimit * 2)\n", stderr)
              }
            }
          }

          let metadata: JSONValue = .object(metadataDict)
          try printResponse(type: "search", data: trimmedResults, json: options.jsonOutput, metadata: metadata) {
            printSearchHits(trimmedResults)
          }
        }

      case .activity:
        let scope = try resolveProjectScope(options: options, service: service)

        // Print scope info to stderr when worktree group detected
        if scope.worktreeGroupDetected {
          if options.thisWorktreeOnly {
            fputs("Worktree group detected; searching current only (--this-worktree)\n", stderr)
          } else if scope.expansionApplied {
            fputs("Including worktrees: \(scope.displayNames.joined(separator: ", "))\n", stderr)
            fputs("(use --this-worktree to search only current)\n", stderr)
          } else {
            // Only one worktree resolved to DB (others excluded/archived/not indexed)
            fputs("Worktree group detected, but only \(scope.displayNames.first ?? "current") is indexed\n", stderr)
          }

          if !scope.unresolvedSiblings.isEmpty {
            fputs("Note: \(scope.unresolvedSiblings.joined(separator: ", ")) not in database\n", stderr)
          }
          if !scope.excluded.isEmpty {
            fputs("Excluded: \(scope.excluded.joined(separator: ", "))\n", stderr)
          }
        }

        let results = try service.activity(
          projectIds: scope.projectIds.isEmpty ? nil : scope.projectIds,
          transcriptId: options.transcriptId,
          limit: options.limit,
          includeHidden: options.includeHidden,
          timeRange: timeRange,
          includeContent: !options.noContent,
          fullContent: options.fullContent,
          maxContentBytes: 2048
        )
        try printResponse(type: "activity", data: results, json: options.jsonOutput) {
          printActivity(results)
        }

      case .projects:
        let limit = options.limitWasProvided ? options.limit : nil
        let results = try service.listProjects(includeHidden: options.includeHidden, limit: limit)
        try printResponse(type: "projects", data: results, json: options.jsonOutput) {
          printProjects(results)
        }

      case .transcripts:
        guard let resolvedProjectId = try resolveProjectId(options: options, service: service, required: true) else {
          throw CLIError(code: "invalidArgs", message: "Missing --project-id or --project", exitCode: .invalidArgs)
        }
        let results = try service.listTranscripts(projectId: resolvedProjectId, limit: options.limit, timeRange: timeRange)
        try printResponse(type: "transcripts", data: results, json: options.jsonOutput) {
          printTranscripts(results)
        }

      case .entry:
        guard let entryId = commandArgs.first else {
          throw CLIError(code: "invalidArgs", message: "Missing entry id", exitCode: .invalidArgs)
        }
        do {
          let result = try service.entry(
            entryId: entryId,
            includeContent: !options.noContent,
            fullContent: options.fullContent,
            maxContentBytes: 2048
          )
          try printResponse(type: "entry", data: result, json: options.jsonOutput) {
            printEntryResult(result)
          }
        } catch let error as ContextifyQueryService.EntryLookupError {
          switch error {
          case let .notFound(entryId):
            throw CLIError(code: "entryNotFound", message: "No entry with id '\(entryId)'", exitCode: .entryNotFound)
          }
        }

      case .context:
        guard let entryId = commandArgs.first else {
          throw CLIError(code: "invalidArgs", message: "Missing entry id", exitCode: .invalidArgs)
        }
        if options.project != nil || options.projectId != nil {
          fputs("Warning: --project/--project-id has no effect on context (context retrieves entries by ID regardless of project)\n", stderr)
        }
        let beforeCount = options.before ?? 10
        let afterCount = options.after ?? 20
        let maxWindow = options.maxWindow ?? 200
        guard maxWindow <= ResponseConstants.maxContextWindowCap else {
          throw CLIError(code: "invalidArgs", message: "--max-window must be <= \(ResponseConstants.maxContextWindowCap)", exitCode: .invalidArgs)
        }
        guard beforeCount + afterCount <= maxWindow else {
          throw CLIError(code: "invalidArgs", message: "--before + --after must be <= --max-window (\(maxWindow))", exitCode: .invalidArgs)
        }
        let kinds = parseCSV(options.kinds)
        do {
          let result = try service.context(
            entryId: entryId,
            beforeCount: beforeCount,
            afterCount: afterCount,
            includeHidden: options.includeHidden,
            kinds: kinds,
            includeContent: !options.noContent,
            fullContent: options.fullContent,
            maxContentBytes: 2048
          )
          try printResponse(type: "context", data: result, json: options.jsonOutput) {
            printContextResult(result)
          }
        } catch let error as ContextifyQueryService.EntryLookupError {
          switch error {
          case let .notFound(entryId):
            throw CLIError(code: "entryNotFound", message: "No entry with id '\(entryId)'", exitCode: .entryNotFound)
          }
        }

      case .status:
        let counts = try service.counts()
        let payload = StatusPayload(
          databasePath: dbURL.path,
          sqliteUserVersion: versionInfo.sqliteUserVersion,
          expectedSchemaVersion: versionInfo.expectedSchemaVersion,
          ftsEnabled: versionInfo.ftsEnabled,
          summariesEnabled: versionInfo.summariesEnabled,
          projectCount: counts.projectCount,
          transcriptCount: counts.transcriptCount,
          entryCount: counts.entryCount
        )
        try printResponse(type: "status", data: payload, json: options.jsonOutput) {
          printStatus(payload)
        }

      case .feedback:
        try runFeedback(commandArgs: commandArgs, options: options, dbURL: dbURL, versionInfo: versionInfo)

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

      case .installPlugin, .uninstallPlugin, .doctor:
        // Handled above (before database connection)
        fatalError("Unreachable")
      }
      #endif  // os(macOS)
    } catch let cliError as CLIError {
      emitError(cliError, json: jsonWanted)
      exit(cliError.exitCode.rawValue)
    } catch {
      // Handle platform-specific error types
      #if os(macOS)
      if let error = error as? ContextifyQueryService.QueryError {
        switch error {
        case let .featureUnavailable(_, message):
          let cliError = CLIError(code: "featureUnavailable", message: message, exitCode: .featureUnavailable)
          emitError(cliError, json: jsonWanted)
          exit(cliError.exitCode.rawValue)
        }
      }
      if let error = error as? QueryCLIFeedbackError {
        let cliError: CLIError
        switch error {
        case let .notFound(id):
          cliError = CLIError(code: "invalidArgs", message: "No feedback with id '\(id)'", exitCode: .invalidArgs)
        case let .invalidArgs(message):
          cliError = CLIError(code: "invalidArgs", message: message, exitCode: .invalidArgs)
        case let .ioError(message):
          cliError = CLIError(code: "invalidArgs", message: message, exitCode: .invalidArgs)
        }
        emitError(cliError, json: jsonWanted)
        exit(cliError.exitCode.rawValue)
      }
      if let error = error as? QueryTimeParseError {
        let cliError = CLIError(code: "invalidArgs", message: String(describing: error), exitCode: .invalidArgs)
        emitError(cliError, json: jsonWanted)
        exit(cliError.exitCode.rawValue)
      }
      if let error = error as? DatabaseError {
        let mapped = mapDatabaseError(error)
        emitError(mapped, json: jsonWanted)
        exit(mapped.exitCode.rawValue)
      }
      #endif
      // Fallback for unhandled errors
      let cliError = CLIError(code: "unknown", message: error.localizedDescription, exitCode: .unknown)
      emitError(cliError, json: jsonWanted)
      exit(cliError.exitCode.rawValue)
    }
  }

  #if os(macOS)
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

    throw CLIError(
      code: "dbNotFound",
      message: """
        Contextify database not found.

        If Contextify is installed:
          Open Contextify once to initialize the database.

        If Contextify is not installed:
          Install from the Mac App Store: https://apps.apple.com/app/contextify

        Or specify the database location:
          --db-path /path/to/contextify.db
          --db-dir  /path/to/directory/containing/db
        """,
      exitCode: .dbNotFound
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

  fileprivate static func printResponse<T: Encodable>(
    type: String,
    data: T,
    json: Bool,
    metadata: JSONValue? = nil,
    human: () -> Void
  ) throws {
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let payload = SuccessEnvelope(type: type, schemaVersion: ResponseConstants.schemaVersion, data: data, metadata: metadata)
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
      Usage: contextify [options] <command> [args]

      Options:
        --db-path <path>     Full path to contextify.db
        --db-dir <dir>       Directory containing contextify.db
        --project-id <id>    Scope queries to a project
        --project <path>     Resolve project id from a path
        --transcript-id <id> Scope queries to a transcript
        --since <ts|iso>     Filter by time (inclusive)
        --until <ts|iso>     Filter by time (inclusive)
        --days <n>           Shorthand for --since (now - n days)
        --include-hidden     Include non-timeline entries
        --before <n>         Context: entries before anchor (default 10)
        --after <n>          Context: entries after anchor (default 20)
        --max-window <n>     Context: cap before+after (default 200)
        --kinds <csv>        Filter by kinds (e.g. user,assistant,system)
        --no-content         Emit content as null (metadata only)
        --full-content       Disable truncation (default truncates >2KB)
        --limit <n>          Limit results (default 50; projects defaults to all)
        --offset <n>         Skip first n results (for pagination, default 0)
        --snippet-tokens <n> Search snippet length in tokens (default 10, max 100)
        --count-only         Search: return only totalCount (no result bodies)
        --term-counts        Search: include per-term counts for OR queries (opt-in)
        --anchor-git         Search: use local git history as an additive ranking signal
        --json               Emit JSON output

      Commands:
        search <query>       Full-text search entries
        activity             Recent timeline activity
        projects             List projects
        transcripts          List transcripts for a project
        entry <uuid>         Fetch an entry by id (UUID)
        context <uuid>       Fetch context around an entry (UUID)
        status               Show database status
        feedback             Record or manage CLI feedback
        summaries            Recent transcript summaries
        stats                Project statistics
        version              Database version info
        install-plugin       Install Claude Code and Codex CLI skills
        uninstall-plugin     Remove Claude Code and Codex CLI skills
        doctor               Check CLI installation health

      Search query syntax (FTS5):
        Use OR/AND/NOT operators (e.g. "bug OR fix"), or quoted phrases ("memory leak").
        Regex operators like "|" are not supported.

      Feedback commands:
        feedback "<summary>"
        feedback list|show <id>
        feedback export <id> --format md|todo|json
        feedback dismiss <id>
        feedback archive [--older-than-days <n>]
        feedback clear --all

      Feedback options:
        --intent <text>         Why you were trying it
        --gap <text>            What capability is missing
        --workaround <text>     How you did it instead
        --proposal <text>       What you think we should add
        --format <md|todo|json> Export format
        --older-than-days <n>   Archive items older than N days
        --all                   Apply to all items (clear)
        --force                 Override warnings/guardrails
        --edit                  Capture feedback via $CONTEXTIFY_QUERY_EDITOR, $VISUAL, or $EDITOR
      """,
      stderr
    )
    exit(message == nil ? 0 : 1)
  }
  #else
  // Linux: simplified usage for install/doctor commands only
  private static func usage(_ message: String?) -> Never {
    if let message = message {
      FileHandle.standardError.write(Data("Error: \(message)\n\n".utf8))
    }
    FileHandle.standardError.write(Data("""
      Usage: contextify-query <command>

      Commands:
        install-plugin   Install Claude Code and Codex CLI skills
        uninstall-plugin Remove Claude Code and Codex CLI skills
        doctor           Check CLI installation health

      Options:
        --json    Emit JSON output

      Note: Full query commands require macOS.
      """.utf8))
    FileHandle.standardError.write(Data("\n".utf8))
    exit(message == nil ? 0 : 1)
  }
  #endif  // os(macOS) - static methods
}

private func isRegularFile(_ url: URL) -> Bool {
  var isDirectory: ObjCBool = false
  guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
  return !isDirectory.boolValue
}

#if os(macOS)
private func printVersionInfo(_ info: ContextifyQueryService.VersionInfo) {
  print("db_schema_version: \(info.sqliteUserVersion)")
  print("expected_schema_version: \(info.expectedSchemaVersion)")
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

private func printEntryResult(_ result: ContextifyQueryService.EntryResult) {
  let project = result.projectName?.isEmpty == false ? result.projectName! : result.entry.projectId
  let transcript = result.transcriptTitle?.isEmpty == false ? result.transcriptTitle! : result.entry.transcriptId
  print("\(result.entry.id)  [\(result.entry.timestamp)]  \(project) / \(transcript)  \(result.entry.kind)")
  if let content = result.entry.content {
    print(content)
  } else {
    print("(content omitted)")
  }
}

private func printContextResult(_ result: ContextifyQueryService.ContextResult) {
  let all = result.before + [result.anchor] + result.after
  for entry in all {
    let content = entry.content ?? "(content omitted)"
    let preview = content
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(300)
    print("[\(entry.timestamp)] \(entry.kind): \(preview)")
  }
  print("meta: before_more=\(result.meta.hasMoreBefore) after_more=\(result.meta.hasMoreAfter) count=\(result.meta.transcriptEntryCount ?? 0)")
}

private func parseCSV(_ value: String?) -> [String]? {
  guard let value else { return nil }
  let parts = value
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  return parts.isEmpty ? nil : parts
}

private func buildSearchQuery(_ rawQuery: String) throws -> String {
  let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    throw CLIError(code: "invalidArgs", message: "Missing search query", exitCode: .invalidArgs)
  }

  if trimmed.contains("|") {
    throw CLIError(
      code: "invalidQuery",
      message: "Unsupported query syntax: '|' is not allowed. Use FTS5 syntax like \"term1 OR term2\".",
      exitCode: .invalidArgs
    )
  }

  let operatorPattern = "\\b(OR|AND|NOT)\\b"
  let hasOperators = trimmed.range(of: operatorPattern, options: [.regularExpression, .caseInsensitive]) != nil
  if hasOperators || trimmed.contains("\"") {
    return trimmed
  }

  return ConversationSearchService.buildSafeFTSQuery(trimmed)
}

private func resolveAnchorBasePath(options: ContextifyQueryCLI.Options) -> String {
  if let project = options.project {
    return (project == "." || project == "current")
      ? FileManager.default.currentDirectoryPath
      : project
  }
  return FileManager.default.currentDirectoryPath
}

private func resolveGitAnchorPlan(
  cues: [GitAnchorCue],
  options: ContextifyQueryCLI.Options
) -> GitAnchorPlan? {
  guard !cues.isEmpty else { return nil }

  let basePath = resolveAnchorBasePath(options: options)
  guard
    let repoRoot = runProcess("/usr/bin/env", arguments: ["git", "-C", basePath, "rev-parse", "--show-toplevel"])?
      .trimmingCharacters(in: .whitespacesAndNewlines),
    !repoRoot.isEmpty
  else {
    return nil
  }

  let trackedFiles = trackedGitFiles(repoRoot: repoRoot)
  let files = resolveGitAnchorFiles(cues: cues, trackedFiles: trackedFiles, repoRoot: repoRoot)
  guard !files.isEmpty else { return nil }

  let commits = resolveGitAnchorCommits(files: files, repoRoot: repoRoot)
  guard !commits.isEmpty else { return nil }

  return GitAnchorPlan(cues: cues, files: files, commits: commits)
}

private func trackedGitFiles(repoRoot: String) -> [String] {
  guard let output = runProcess("/usr/bin/env", arguments: ["git", "-C", repoRoot, "ls-files"]) else {
    return []
  }
  return output
    .split(separator: "\n")
    .map(String.init)
}

private func resolveGitAnchorFiles(
  cues: [GitAnchorCue],
  trackedFiles: [String],
  repoRoot: String
) -> [String] {
  guard !trackedFiles.isEmpty else { return [] }

  var matched: [String] = []
  var seen = Set<String>()

  func add(_ relativePath: String) {
    guard seen.insert(relativePath).inserted else { return }
    matched.append(relativePath)
  }

  for cue in cues {
    let needle = cue.normalized.lowercased()
    switch cue.kind {
    case .file:
      for path in trackedFiles {
        let lowercasedPath = path.lowercased()
        let basename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if lowercasedPath == needle || lowercasedPath.hasSuffix("/\(needle)") || basename == needle {
          add(path)
        }
      }
    case .command, .symbol:
      for path in trackedFiles {
        let lowercasedPath = path.lowercased()
        let basename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
        if basename == needle || lowercasedPath.contains("/\(needle)") || lowercasedPath.contains(needle) {
          add(path)
        }
      }
    }

    if matched.count >= 8 {
      break
    }
  }

  return Array(matched.prefix(8)).map { relativePath in
    URL(fileURLWithPath: repoRoot).appendingPathComponent(relativePath).path
  }
}

private func resolveGitAnchorCommits(files: [String], repoRoot: String) -> [GitAnchorCommit] {
  var commitsByHash: [String: GitAnchorCommit] = [:]

  for file in files.prefix(6) {
    guard let output = runProcess(
      "/usr/bin/env",
      arguments: ["git", "-C", repoRoot, "log", "--format=%H %ct", "-n", "4", "--", file]
    ) else {
      continue
    }

    for line in output.split(separator: "\n") {
      let parts = line.split(separator: " ")
      guard parts.count == 2, let timestamp = Int(parts[1]) else { continue }
      let hash = String(parts[0])
      let commit = GitAnchorCommit(hash: hash, timestamp: timestamp)
      if let existing = commitsByHash[hash] {
        if commit.timestamp > existing.timestamp {
          commitsByHash[hash] = commit
        }
      } else {
        commitsByHash[hash] = commit
      }
    }
  }

  return commitsByHash.values
    .sorted { lhs, rhs in
      if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
      return lhs.hash < rhs.hash
    }
    .prefix(8)
    .map { $0 }
}

private func runProcess(_ executable: String, arguments: [String]) -> String? {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  let stdout = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdout
  process.standardError = stderrPipe

  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    return nil
  }

  guard process.terminationStatus == 0 else { return nil }
  let data = stdout.fileHandleForReading.readDataToEndOfFile()
  return String(data: data, encoding: .utf8)
}

private func runFeedback(
  commandArgs: [String],
  options: ContextifyQueryCLI.Options,
  dbURL: URL,
  versionInfo: ContextifyQueryService.VersionInfo
) throws {
  let inboxRoot = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
  ).appendingPathComponent("Contextify", isDirectory: true)
  let inbox = QueryCLIFeedbackInbox(root: inboxRoot)

  let cliVersion = ProcessInfo.processInfo.environment["CONTEXTIFY_QUERY_VERSION"] ?? "dev"

  func printWarnings(_ warnings: [String]) {
    for warning in warnings {
      fputs("Warning: \(warning)\n", stderr)
    }
  }

  if options.edit {
    let input = try editFeedbackInput()
    try recordFeedback(
      input: input,
      options: options,
      inbox: inbox,
      dbURL: dbURL,
      versionInfo: versionInfo,
      cliVersion: cliVersion,
      printWarnings: printWarnings
    )
    return
  }

  if commandArgs.isEmpty, !stdinIsTTY() {
    let input = try readFeedbackInputFromStdin()
    try recordFeedback(
      input: input,
      options: options,
      inbox: inbox,
      dbURL: dbURL,
      versionInfo: versionInfo,
      cliVersion: cliVersion,
      printWarnings: printWarnings
    )
    return
  }

  if let sub = commandArgs.first {
    switch sub {
    case "list":
      let items = try inbox.list()
      let payload = FeedbackListPayload(items: items, count: items.count)
      try ContextifyQueryCLI.printResponse(type: "feedbackList", data: payload, json: options.jsonOutput) {
        printFeedbackList(items)
      }
      return

    case "show":
      guard commandArgs.count >= 2 else { throw CLIError(code: "invalidArgs", message: "Missing feedback id", exitCode: .invalidArgs) }
      let item = try inbox.load(id: commandArgs[1])
      try ContextifyQueryCLI.printResponse(type: "feedbackShow", data: item, json: options.jsonOutput) {
        print(inbox.exportMarkdown(item: item))
      }
      return

    case "export":
      guard commandArgs.count >= 2 else { throw CLIError(code: "invalidArgs", message: "Missing feedback id", exitCode: .invalidArgs) }
      let id = commandArgs[1]
      let item = try inbox.load(id: id)
      let format = QueryCLIFeedbackFormat(rawValue: options.format ?? "md") ?? .md
      switch format {
      case .json:
        try ContextifyQueryCLI.printResponse(type: "feedbackExport", data: item, json: options.jsonOutput) {
          print(inbox.exportMarkdown(item: item))
        }
      case .md:
        let content = inbox.exportMarkdown(item: item)
        try ContextifyQueryCLI.printResponse(type: "feedbackExport", data: FeedbackExportPayload(id: id, format: "md", content: content), json: options.jsonOutput) {
          print(content)
        }
      case .todo:
        let content = inbox.exportTodoLine(item: item)
        try ContextifyQueryCLI.printResponse(type: "feedbackExport", data: FeedbackExportPayload(id: id, format: "todo", content: content), json: options.jsonOutput) {
          print(content)
        }
      }
      return

    case "dismiss":
      guard commandArgs.count >= 2 else { throw CLIError(code: "invalidArgs", message: "Missing feedback id", exitCode: .invalidArgs) }
      try inbox.dismiss(id: commandArgs[1])
      try ContextifyQueryCLI.printResponse(type: "feedbackDismissed", data: ["id": commandArgs[1]], json: options.jsonOutput) {
        print("Dismissed \(commandArgs[1])")
      }
      return

    case "archive":
      let moved = try inbox.archive(olderThanDays: options.olderThanDays)
      try ContextifyQueryCLI.printResponse(type: "feedbackArchived", data: ["moved": moved], json: options.jsonOutput) {
        print("Archived \(moved) item(s)")
      }
      return

    case "clear":
      guard options.all else { throw CLIError(code: "invalidArgs", message: "Use `feedback clear --all`", exitCode: .invalidArgs) }
      let moved = try inbox.clearAll()
      try ContextifyQueryCLI.printResponse(type: "feedbackCleared", data: ["moved": moved], json: options.jsonOutput) {
        print("Cleared \(moved) item(s)")
      }
      return

    default:
      break
    }
  }

  guard !commandArgs.isEmpty else { throw CLIError(code: "invalidArgs", message: "Missing feedback summary", exitCode: .invalidArgs) }
  let input = FeedbackInput(
    summary: commandArgs.joined(separator: " "),
    intent: options.intent,
    gap: options.gap,
    workaround: options.workaround,
    proposal: options.proposal
  )
  try recordFeedback(
    input: input,
    options: options,
    inbox: inbox,
    dbURL: dbURL,
    versionInfo: versionInfo,
    cliVersion: cliVersion,
    printWarnings: printWarnings
  )
}

private struct FeedbackListPayload: Codable {
  let items: [QueryCLIFeedbackListItem]
  let count: Int
}

private struct FeedbackRecordedPayload: Codable {
  let id: String
  let path: String
  let summary: String
  let warnings: [String]
}

private struct FeedbackExportPayload: Codable {
  let id: String
  let format: String
  let content: String
}

private func printFeedbackList(_ items: [QueryCLIFeedbackListItem]) {
  if items.isEmpty {
    print("(no feedback)")
    return
  }
  for item in items {
    print("\(item.id)  \(item.timestamp)")
    print("  \(item.summary)")
  }
}

private func capabilitiesFrom(versionInfo: ContextifyQueryService.VersionInfo) -> [String] {
  var caps: [String] = []
  if versionInfo.ftsEnabled { caps.append("fts_search") }
  if versionInfo.summariesEnabled { caps.append("summaries") }
  return caps
}

private struct FeedbackInput: Codable {
  let summary: String
  let intent: String?
  let gap: String?
  let workaround: String?
  let proposal: String?
}

private func recordFeedback(
  input: FeedbackInput,
  options: ContextifyQueryCLI.Options,
  inbox: QueryCLIFeedbackInbox,
  dbURL: URL,
  versionInfo: ContextifyQueryService.VersionInfo,
  cliVersion: String,
  printWarnings: ([String]) -> Void
) throws {
  let capabilities = capabilitiesFrom(versionInfo: versionInfo)
  let result = try inbox.record(
    summary: input.summary,
    intent: input.intent,
    gap: input.gap,
    workaround: input.workaround,
    proposal: input.proposal,
    cliVersion: cliVersion,
    appSchemaVersion: versionInfo.appSchemaVersion,
    capabilities: capabilities,
    force: options.force
  )

  if !options.jsonOutput {
    printWarnings(result.warnings)
  }

  let payload = FeedbackRecordedPayload(
    id: result.recorded.id,
    path: result.recorded.path,
    summary: result.recorded.summary,
    warnings: result.warnings
  )
  try ContextifyQueryCLI.printResponse(type: "feedbackRecorded", data: payload, json: options.jsonOutput) {
    if !result.warnings.isEmpty {
      printWarnings(result.warnings)
    }
    print("Recorded \(payload.id)")
    print(payload.path)
  }
}

private func stdinIsTTY() -> Bool {
  isatty(fileno(stdin)) != 0
}

private func readFeedbackInputFromStdin() throws -> FeedbackInput {
  let data = try readAllStdin(maxBytes: 256 * 1024)
  guard !data.isEmpty else { throw CLIError(code: "invalidArgs", message: "Empty stdin", exitCode: .invalidArgs) }
  do {
    return try JSONDecoder().decode(FeedbackInput.self, from: data)
  } catch {
    throw CLIError(code: "invalidArgs", message: "Invalid JSON on stdin", exitCode: .invalidArgs)
  }
}

private func editFeedbackInput() throws -> FeedbackInput {
  let env = ProcessInfo.processInfo.environment
  let editorSpec = env["CONTEXTIFY_QUERY_EDITOR"] ?? env["VISUAL"] ?? env["EDITOR"] ?? ""
  guard !editorSpec.isEmpty else {
    throw CLIError(
      code: "invalidArgs",
      message: "Missing editor. Set $CONTEXTIFY_QUERY_EDITOR, $VISUAL, or $EDITOR for --edit.",
      exitCode: .invalidArgs
    )
  }

  let template = FeedbackInput(summary: "", intent: nil, gap: nil, workaround: nil, proposal: nil)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  let data = try encoder.encode(template)

  let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("contextify-query-feedback-\(UUID().uuidString).json")
  try data.write(to: tmpURL, options: .atomic)
  defer { try? FileManager.default.removeItem(at: tmpURL) }

  let editorArgs = parseCommandLine(editorSpec) ?? [editorSpec]
  guard let editorExe = editorArgs.first, !editorExe.isEmpty else {
    throw CLIError(code: "invalidArgs", message: "Invalid editor command in $CONTEXTIFY_QUERY_EDITOR/$VISUAL/$EDITOR", exitCode: .invalidArgs)
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = editorArgs + [tmpURL.path]
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    throw CLIError(code: "invalidArgs", message: "$EDITOR exited with status \(process.terminationStatus)", exitCode: .invalidArgs)
  }

  let edited = try Data(contentsOf: tmpURL)
  let input = try JSONDecoder().decode(FeedbackInput.self, from: edited)
  if input.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    throw CLIError(code: "invalidArgs", message: "Feedback summary is required", exitCode: .invalidArgs)
  }
  return input
}

private func readAllStdin(maxBytes: Int) throws -> Data {
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while true {
    let n = read(STDIN_FILENO, &buffer, buffer.count)
    if n < 0 {
      throw CLIError(code: "invalidArgs", message: "Failed reading stdin", exitCode: .invalidArgs)
    }
    if n == 0 { break }
    if data.count + n > maxBytes {
      throw CLIError(code: "invalidArgs", message: "Stdin payload too large (max \(maxBytes) bytes)", exitCode: .invalidArgs)
    }
    data.append(buffer, count: n)
  }
  return data
}

private func parseCommandLine(_ input: String) -> [String]? {
  var args: [String] = []
  var current = ""
  var inSingle = false
  var inDouble = false
  var escape = false

  func flush() {
    if !current.isEmpty {
      args.append(current)
      current = ""
    }
  }

  for scalar in input.unicodeScalars {
    let ch = Character(scalar)
    if escape {
      current.append(ch)
      escape = false
      continue
    }

    if ch == "\\" && !inSingle {
      escape = true
      continue
    }

    if ch == "'" && !inDouble {
      inSingle.toggle()
      continue
    }
    if ch == "\"" && !inSingle {
      inDouble.toggle()
      continue
    }

    if !inSingle && !inDouble, ch.isWhitespace {
      flush()
      continue
    }
    current.append(ch)
  }

  if escape || inSingle || inDouble {
    return nil
  }
  flush()
  return args.isEmpty ? nil : args
}

private func printTranscripts(_ transcripts: [ContextifyQueryService.TranscriptListItem]) {
  if transcripts.isEmpty {
    print("(no transcripts)")
    return
  }
  for transcript in transcripts {
    let title = transcript.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOr("-") ?? "-"
    let firstTs = transcript.firstEntryTimestamp.map(String.init) ?? "-"
    let lastTs = transcript.lastEntryTimestamp.map(String.init) ?? "-"
    let count = transcript.entryCount.map(String.init) ?? "-"
    print("\(transcript.id)  provider=\(transcript.provider)  entries=\(count)  first_ts=\(firstTs)  last_ts=\(lastTs)")
    print("  \(title)")
  }
}

private func printSearchHits(_ hits: [ContextifyQueryService.SearchHit]) {
  if hits.isEmpty {
    print("(no results)")
    return
  }
  for hit in hits {
    let projectLabel = hit.projectName?.isEmpty == false ? hit.projectName! : hit.projectId
    let transcriptLabel = hit.transcriptTitle?.isEmpty == false ? hit.transcriptTitle! : hit.transcriptId
    print("[\(hit.timestamp)] \(projectLabel) / \(transcriptLabel)  \(hit.kind)  score=\(hit.score)")
    print("  \(hit.contentSnippet)")
  }
}

private struct StatusPayload: Encodable {
  let databasePath: String
  let sqliteUserVersion: Int
  let expectedSchemaVersion: Int
  let ftsEnabled: Bool
  let summariesEnabled: Bool
  let projectCount: Int
  let transcriptCount: Int
  let entryCount: Int

  var appSchemaVersion: Int { expectedSchemaVersion }

  enum CodingKeys: String, CodingKey {
    case databasePath
    case sqliteUserVersion
    case expectedSchemaVersion
    case appSchemaVersion
    case ftsEnabled
    case summariesEnabled
    case projectCount
    case transcriptCount
    case entryCount
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(databasePath, forKey: .databasePath)
    try container.encode(sqliteUserVersion, forKey: .sqliteUserVersion)
    try container.encode(expectedSchemaVersion, forKey: .expectedSchemaVersion)
    try container.encode(expectedSchemaVersion, forKey: .appSchemaVersion)
    try container.encode(ftsEnabled, forKey: .ftsEnabled)
    try container.encode(summariesEnabled, forKey: .summariesEnabled)
    try container.encode(projectCount, forKey: .projectCount)
    try container.encode(transcriptCount, forKey: .transcriptCount)
    try container.encode(entryCount, forKey: .entryCount)
  }
}

private func printStatus(_ status: StatusPayload) {
  print("db_path: \(status.databasePath)")
  print("db_schema_version: \(status.sqliteUserVersion)")
  print("expected_schema_version: \(status.expectedSchemaVersion)")
  print("fts_enabled: \(status.ftsEnabled)")
  print("summaries_enabled: \(status.summariesEnabled)")
  print("projects: \(status.projectCount)")
  print("transcripts: \(status.transcriptCount)")
  print("entries: \(status.entryCount)")
}

private func printActivity(_ items: [ContextifyQueryService.ActivityItem]) {
  if items.isEmpty {
    print("(no activity)")
    return
  }
  for item in items {
    let project = item.projectName?.isEmpty == false ? item.projectName! : item.entry.projectId
    let transcript = item.transcriptTitle?.isEmpty == false ? item.transcriptTitle! : item.entry.transcriptId
    let content = item.entry.content ?? "(content omitted)"
    let preview = content
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(200)
    print("[\(item.entry.timestamp)] \(project) / \(transcript)  \(item.entry.kind): \(preview)")
  }
}

private func parseTimeRange(options: ContextifyQueryCLI.Options) throws -> QueryTimeRange {
  do {
    return try QueryTimeParser.parseSinceUntil(since: options.since, until: options.until, days: options.days)
  } catch {
    throw CLIError(code: "invalidArgs", message: String(describing: error), exitCode: .invalidArgs)
  }
}

private func resolveProjectId(
  options: ContextifyQueryCLI.Options,
  service: ContextifyQueryService,
  required: Bool = false
) throws -> String? {
  if let id = options.projectId { return id }
  guard let project = options.project else {
    if required {
      throw CLIError(code: "invalidArgs", message: "Missing --project-id or --project", exitCode: .invalidArgs)
    }
    return nil
  }

  let path: String
  if project == "." || project == "current" {
    path = FileManager.default.currentDirectoryPath
  } else {
    path = project
  }

  do {
    return try service.resolveProjectId(forPath: path)
  } catch let error as ContextifyQueryService.ProjectResolutionError {
    switch error {
    case let .notFound(path, suggestions, totalProjectCount):
      let projects = suggestions.map { "\($0.name ?? $0.id) (\($0.rootPath))" }.joined(separator: "\n  - ")
      let suggestionObjects: [JSONValue] = suggestions.map { project in
        jsonProjectSuggestion(project)
      }
      let detailsObject: [String: JSONValue] = [
        "path": .string(path),
        "suggestions": .array(suggestionObjects),
        "totalProjectCount": .number(Double(totalProjectCount)),
      ]
      let details: JSONValue = .object(detailsObject)
      throw CLIError(
        code: "dbProjectNotFound",
        message: "No Contextify project found for \(path).\n\nKnown projects:\n  - \(projects)\n\nTotal projects: \(totalProjectCount)",
        exitCode: .dbNotFound,
        details: details
      )
    case let .ambiguous(path, candidates):
      let projects = candidates.map { "\($0.name ?? $0.id) (\($0.rootPath))" }.joined(separator: "\n  - ")
      let candidateObjects: [JSONValue] = candidates.map { project in
        jsonProjectSuggestion(project)
      }
      let detailsObject: [String: JSONValue] = [
        "path": .string(path),
        "candidates": .array(candidateObjects),
      ]
      let details: JSONValue = .object(detailsObject)
      throw CLIError(
        code: "dbProjectNotFound",
        message: "Ambiguous project match for \(path).\n\nCandidates:\n  - \(projects)",
        exitCode: .dbNotFound,
        details: details
      )
    }
  }
}

private func resolveProjectScope(
  options: ContextifyQueryCLI.Options,
  service: ContextifyQueryService
) throws -> ProjectScope {
  // 1. Resolve base path
  let basePath: String
  if let project = options.project {
    basePath = (project == "." || project == "current")
      ? FileManager.default.currentDirectoryPath
      : project
  } else {
    return ProjectScope(projectIds: [], displayNames: [],
                       unresolvedSiblings: [], excluded: [],
                       worktreeGroupDetected: false, worktreesConsidered: [],
                       expansionApplied: false)
  }

  // 2. Check for worktree expansion disabled
  if options.thisWorktreeOnly {
    if let id = try? service.resolveProjectId(forPath: basePath) {
      return ProjectScope(projectIds: [id],
                         displayNames: [URL(fileURLWithPath: basePath).lastPathComponent],
                         unresolvedSiblings: [], excluded: [],
                         worktreeGroupDetected: false, worktreesConsidered: [],
                         expansionApplied: false)
    }
    throw CLIError(code: "projectNotFound", message: "Project not found: \(basePath)", exitCode: .dbNotFound)
  }

  // 3. Detect worktree group
  guard let group = WorktreeDetector.findWorktreeGroup(from: URL(fileURLWithPath: basePath)) else {
    // Not a worktree group, single project
    if let id = try? service.resolveProjectId(forPath: basePath) {
      return ProjectScope(projectIds: [id],
                         displayNames: [URL(fileURLWithPath: basePath).lastPathComponent],
                         unresolvedSiblings: [], excluded: [],
                         worktreeGroupDetected: false, worktreesConsidered: [],
                         expansionApplied: false)
    }
    throw CLIError(code: "projectNotFound", message: "Project not found: \(basePath)", exitCode: .dbNotFound)
  }

  // 4. Load config for archived/names
  let config = loadWorktreeConfig(gitRoot: group.commonGitDir.deletingLastPathComponent())
  // Parse exclude list, trimming whitespace and ignoring empty segments (e.g., "a,,b")
  let excludeList = options.exclude?
    .split(separator: ",")
    .map { String($0).trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty } ?? []

  // 5. Build list of all worktrees considered (for messaging)
  let worktreesConsidered = group.worktrees.map { worktree -> String in
    config?.nameFor(path: worktree.path) ?? worktree.lastPathComponent
  }

  // 6. Resolve each sibling
  var projectIds: [String] = []
  var displayNames: [String] = []
  var unresolvedSiblings: [String] = []
  var excluded: [String] = []

  for worktree in group.worktrees {
    let pathString = worktree.path
    let displayName = config?.nameFor(path: pathString) ?? worktree.lastPathComponent

    // Check if archived
    if config?.isArchived(path: pathString) == true {
      excluded.append(displayName)
      continue
    }

    // Check if user-excluded
    if excludeList.contains(displayName) || excludeList.contains(worktree.lastPathComponent) {
      excluded.append(displayName)
      continue
    }

    // Resolve in database
    if let id = try? service.resolveProjectId(forPath: pathString) {
      projectIds.append(id)
      displayNames.append(displayName)
    } else {
      unresolvedSiblings.append(displayName)
    }
  }

  return ProjectScope(
    projectIds: projectIds,
    displayNames: displayNames,
    unresolvedSiblings: unresolvedSiblings,
    excluded: excluded,
    worktreeGroupDetected: true,
    worktreesConsidered: worktreesConsidered,
    expansionApplied: projectIds.count > 1
  )
}

private func jsonProjectSuggestion(_ project: ContextifyQueryService.ProjectSuggestion) -> JSONValue {
  var object: [String: JSONValue] = [
    "id": .string(project.id),
    "rootPath": .string(project.rootPath),
  ]
  object["name"] = project.name.map(JSONValue.string) ?? .null
  return .object(object)
}
#endif  // os(macOS)

private func emitError(_ cliError: CLIError, json: Bool) {
  if json {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let payload = ErrorEnvelope(code: cliError.code, message: cliError.message, details: cliError.details)
      let out = try encoder.encode(payload)
      FileHandle.standardOutput.write(out)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      FileHandle.standardError.write(Data("Error: \(cliError.message)\n".utf8))
    }
  } else {
    FileHandle.standardError.write(Data("Error: \(cliError.message)\n".utf8))
  }
}

private enum JSONValue: Encodable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  case array([JSONValue])
  case object([String: JSONValue])

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .string(value):
      try container.encode(value)
    case let .number(value):
      try container.encode(value)
    case let .bool(value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    case let .array(values):
      try container.encode(values)
    case let .object(values):
      try container.encode(values)
    }
  }
}

#if os(macOS)
private func mapDatabaseError(_ error: DatabaseError) -> CLIError {
  let message = (error.message ?? error.localizedDescription).trimmingCharacters(in: .whitespacesAndNewlines)
  let result = error.resultCode
  let extended = error.extendedResultCode

  switch result {
  case .SQLITE_CANTOPEN, .SQLITE_NOTADB, .SQLITE_PERM, .SQLITE_AUTH, .SQLITE_READONLY, .SQLITE_IOERR:
    return CLIError(code: "dbNotFound", message: message, exitCode: .dbNotFound)
  default:
    break
  }

  if extended == .SQLITE_CANTOPEN || extended == .SQLITE_NOTADB || extended == .SQLITE_PERM || extended == .SQLITE_AUTH || extended == .SQLITE_READONLY || extended == .SQLITE_IOERR {
    return CLIError(code: "dbNotFound", message: message, exitCode: .dbNotFound)
  }

  if message.contains("no such table: transcript_entries_fts") {
    return CLIError(code: "featureUnavailable", message: "FTS search table missing (transcript_entries_fts). Open Contextify to run migrations, or pass a different --db-path.", exitCode: .featureUnavailable)
  }
  if message.contains("no such table: transcript_metadata") {
    return CLIError(code: "featureUnavailable", message: "Summaries table missing (transcript_metadata). Open Contextify to run migrations, or pass a different --db-path.", exitCode: .featureUnavailable)
  }
  if message.localizedCaseInsensitiveContains("fts5") &&
      (message.localizedCaseInsensitiveContains("syntax") || message.localizedCaseInsensitiveContains("parse")) {
    return CLIError(code: "invalidQuery", message: "Invalid FTS query syntax: \(message)", exitCode: .invalidArgs)
  }
  if let table = parseMissingTableName(message: message) {
    return CLIError(
      code: "dbNotFound",
      message: "Database schema is missing required table '\(table)'. Is this a Contextify database? (\(message))",
      exitCode: .dbNotFound
    )
  }
  return CLIError(code: "unknown", message: message, exitCode: .unknown)
}

private func parseMissingTableName(message: String) -> String? {
  let marker = "no such table:"
  guard let range = message.range(of: marker) else { return nil }
  let suffix = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
  guard !suffix.isEmpty else { return nil }
  let table = suffix.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
  guard let table else { return nil }
  if let dot = table.lastIndex(of: ".") {
    return String(table[table.index(after: dot)...])
  }
  return table
}
#endif

// MARK: - Plugin Installation

private let pluginVersion = ContextifyQueryCLI.cliVersion
#if os(macOS)
private let pluginName = "query"
private let pluginNamespace = "contextify"
private let pluginIdentifier = "\(pluginName)@\(pluginNamespace)"

private func runInstallPlugin(options: ContextifyQueryCLI.Options) throws {
  let home = FileManager.default.homeDirectoryForCurrentUser
  let pluginsDir = home.appendingPathComponent(".claude/plugins")
  let cacheDir = pluginsDir.appendingPathComponent("cache/\(pluginNamespace)/\(pluginName)/\(pluginVersion)")
  let manifestPath = pluginsDir.appendingPathComponent("installed_plugins.json")

  // Find sources - plugin and user skill
  let sources = try findPluginSources()

  // Track Codex installation status for output message
  var codexInstalled = false

  // 1. Install user skill to ~/.claude/skills/total-recall/
  if let userSkillSource = sources.userSkill {
    let skillFile = userSkillSource.appendingPathComponent("SKILL.md")
    let sourceKind = sources.userSkillSourceKind ?? .unknown
    let skillsDir = home.appendingPathComponent(".claude/skills/total-recall")
    _ = try installSkillFile(
      from: skillFile,
      to: skillsDir,
      target: "claude",
      sourceKind: sourceKind
    )

    if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
      fputs("Warning: CODEX_HOME is set to \(codexHome)\n", stderr)
      fputs("Skill installed to default ~/.codex/skills/ - you may need to copy manually.\n", stderr)
    }

    // Install Codex skill using copy-by-content to guarantee a real file (not symlink)
    let codexSkillsDir = home.appendingPathComponent(".codex/skills/total-recall")
    do {
      let codexSkillDest = try installSkillFile(
        from: skillFile,
        to: codexSkillsDir,
        target: "codex",
        sourceKind: sourceKind
      )

      // Verify destination is not a symlink
      let resourceValues = try codexSkillDest.resourceValues(forKeys: [.isSymbolicLinkKey])
      if resourceValues.isSymbolicLink == true {
        fputs("Warning: Codex skill unexpectedly created as symlink\n", stderr)
      } else {
        codexInstalled = true
      }
    } catch {
      fputs("Warning: Failed to install Codex CLI skill at \(codexSkillsDir.path): \(error.localizedDescription)\n", stderr)
    }
  }

  // 2. Clean up old plugin skill location (if exists)
  let oldPluginSkillDir = cacheDir.appendingPathComponent("skills/contextify-reinject")
  if FileManager.default.fileExists(atPath: oldPluginSkillDir.path) {
    try FileManager.default.removeItem(at: oldPluginSkillDir)
  }
  let oldPluginSkillsDir = cacheDir.appendingPathComponent("skills")
  if FileManager.default.fileExists(atPath: oldPluginSkillsDir.path) {
    // Remove entire skills/ directory from plugin
    try FileManager.default.removeItem(at: oldPluginSkillsDir)
  }

  // 3. Clean up old user skill name (if exists)
  let oldUserSkillDir = home.appendingPathComponent(".claude/skills/contextify-reinject")
  if FileManager.default.fileExists(atPath: oldUserSkillDir.path) {
    try FileManager.default.removeItem(at: oldUserSkillDir)
  }

  // 4. Create plugins directory structure
  try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

  // 5. Copy plugin files (agents + hooks only, no skills/)
  let sourceContents = try FileManager.default.contentsOfDirectory(at: sources.plugin, includingPropertiesForKeys: nil)
  for item in sourceContents {
    let destPath = cacheDir.appendingPathComponent(item.lastPathComponent)
    if FileManager.default.fileExists(atPath: destPath.path) {
      try FileManager.default.removeItem(at: destPath)
    }
    try FileManager.default.copyItem(at: item, to: destPath)
  }

  // 6. Update manifest
  try updatePluginManifest(manifestPath: manifestPath, installPath: cacheDir.path, version: pluginVersion)

  let payload = PluginInstallPayload(
    action: "installed",
    identifier: pluginIdentifier,
    version: pluginVersion,
    path: cacheDir.path,
    skillSourceKind: sources.userSkillSourceKind?.rawValue,
    skillSourcePath: sources.userSkill?.appendingPathComponent("SKILL.md").resolvingSymlinksInPath().path
  )

  try ContextifyQueryCLI.printResponse(type: "pluginInstalled", data: payload, json: options.jsonOutput) {
    print("Contextify Total Recall installed!")
    if let skillSource = sources.userSkill {
      print("  Skill source: \(describeSkillSource(sources.userSkillSourceKind))")
      print("    \(skillSource.appendingPathComponent("SKILL.md").resolvingSymlinksInPath().path)")
      if sources.userSkillSourceKind == .repo {
        print("  Warning: repo-local skill source is active (developer install)")
      }
    }
    print("  Claude Code: \(home.appendingPathComponent(".claude/skills/total-recall").path)")
    if codexInstalled {
      print("  Codex CLI:   \(home.appendingPathComponent(".codex/skills/total-recall").path)")
    } else {
      print("  Codex CLI:   (failed - see warnings)")
    }
    print("")
    print("Restart your CLI tool, then use /total-recall to search history.")
  }
}

private func runUninstallPlugin(options: ContextifyQueryCLI.Options) throws {
  let home = FileManager.default.homeDirectoryForCurrentUser
  let pluginsDir = home.appendingPathComponent(".claude/plugins")
  let cacheDir = pluginsDir.appendingPathComponent("cache/\(pluginNamespace)")
  let manifestPath = pluginsDir.appendingPathComponent("installed_plugins.json")

  // Remove user skill
  let userSkillDir = home.appendingPathComponent(".claude/skills/total-recall")
  if FileManager.default.fileExists(atPath: userSkillDir.path) {
    try FileManager.default.removeItem(at: userSkillDir)
  }

  // Remove Codex skill (best-effort - don't fail if this fails)
  let codexUserSkillDir = home.appendingPathComponent(".codex/skills/total-recall")
  do {
    if FileManager.default.fileExists(atPath: codexUserSkillDir.path) {
      try FileManager.default.removeItem(at: codexUserSkillDir)
    }
  } catch {
    fputs("Warning: Failed to remove Codex skill at \(codexUserSkillDir.path): \(error.localizedDescription)\n", stderr)
  }

  // Remove old user skill name (if exists)
  let oldUserSkillDir = home.appendingPathComponent(".claude/skills/contextify-reinject")
  if FileManager.default.fileExists(atPath: oldUserSkillDir.path) {
    try FileManager.default.removeItem(at: oldUserSkillDir)
  }

  // Remove plugin cache directory
  if FileManager.default.fileExists(atPath: cacheDir.path) {
    try FileManager.default.removeItem(at: cacheDir)
  }

  // Update manifest to remove our entry
  try removeFromPluginManifest(manifestPath: manifestPath)

  let payload = PluginInstallPayload(
    action: "uninstalled",
    identifier: pluginIdentifier,
    version: pluginVersion,
    path: cacheDir.path,
    skillSourceKind: nil,
    skillSourcePath: nil
  )

  try ContextifyQueryCLI.printResponse(type: "pluginUninstalled", data: payload, json: options.jsonOutput) {
    print("Uninstalled \(pluginIdentifier)")
    print("")
    print("Restart your CLI tool to complete removal.")
  }
}

private struct PluginSources {
  let plugin: URL
  let userSkill: URL?
  let userSkillSourceKind: CLIHealthChecker.SkillInstallSourceKind?
}

private func writeSkillInstallMetadata(
  _ metadata: CLIHealthChecker.SkillInstallMetadata,
  forSkillFile skillFile: URL
) throws {
  let metadataURL = CLIHealthChecker.skillMetadataURL(forSkillFile: skillFile)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  let data = try encoder.encode(metadata)
  try data.write(to: metadataURL, options: .atomic)
}

private func installSkillFile(
  from sourceSkillFile: URL,
  to destinationDirectory: URL,
  target: String,
  sourceKind: CLIHealthChecker.SkillInstallSourceKind
) throws -> URL {
  try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

  let destinationSkillFile = destinationDirectory.appendingPathComponent("SKILL.md")
  let skillData = try Data(contentsOf: sourceSkillFile)
  let installedHash = CrossPlatformCrypto.sha256(skillData)

  if FileManager.default.fileExists(atPath: destinationSkillFile.path) {
    try FileManager.default.removeItem(at: destinationSkillFile)
  }

  try skillData.write(to: destinationSkillFile, options: .atomic)

  let metadata = CLIHealthChecker.SkillInstallMetadata(
    installedAt: ISO8601DateFormatter().string(from: Date()),
    installerVersion: pluginVersion,
    target: target,
    installSourceKind: sourceKind,
    installSourcePath: sourceSkillFile.resolvingSymlinksInPath().path,
    sourceSkillSHA256: installedHash,
    installedSkillSHA256: installedHash
  )
  try writeSkillInstallMetadata(metadata, forSkillFile: destinationSkillFile)

  return destinationSkillFile
}

private func describeSkillSource(_ sourceKind: CLIHealthChecker.SkillInstallSourceKind?) -> String {
  switch sourceKind ?? .unknown {
  case .repo:
    return "repo-local source"
  case .bundle:
    return "app bundle source"
  case .sibling:
    return "CLI-adjacent source"
  case .cellar:
    return "Homebrew Cellar source"
  case .unknown:
    return "unknown source"
  }
}

private func findPluginSources() throws -> PluginSources {
  // 0. Check repo-local source (development runs from repo root)
  let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let repoPlugin = cwdURL.appendingPathComponent("contextify-query/claude-plugin")
  if FileManager.default.fileExists(atPath: repoPlugin.path) {
    let repoUserSkill = cwdURL.appendingPathComponent("contextify-query/user-skill/total-recall")
    return PluginSources(
      plugin: repoPlugin,
      userSkill: FileManager.default.fileExists(atPath: repoUserSkill.path) ? repoUserSkill : nil,
      userSkillSourceKind: .repo
    )
  }

  // 1. Check if running from app bundle (DMG build)
  if let bundleURL = Bundle.main.resourceURL {
    let bundledPlugin = bundleURL.appendingPathComponent("contextify-query/claude-plugin")
    if FileManager.default.fileExists(atPath: bundledPlugin.path) {
      let bundledUserSkill = bundleURL.appendingPathComponent("contextify-query/user-skill/total-recall")
      return PluginSources(
        plugin: bundledPlugin,
        userSkill: FileManager.default.fileExists(atPath: bundledUserSkill.path) ? bundledUserSkill : nil,
        userSkillSourceKind: .bundle
      )
    }
  }

  // Get the executable path - need to handle case where argv[0] has no path
  var executablePath = CommandLine.arguments[0]

  // If argv[0] doesn't contain a path separator, look it up via PATH
  if !executablePath.contains("/") {
    // Use `which` to find the actual path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [executablePath]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
         !path.isEmpty {
        executablePath = path
      }
    }
  }

  // 2. Check alongside the executable (Homebrew install - tarball extraction)
  let executableURL = URL(fileURLWithPath: executablePath)
  let execDir = executableURL.deletingLastPathComponent()
  let siblingPlugin = execDir.appendingPathComponent("claude-plugin")
  if FileManager.default.fileExists(atPath: siblingPlugin.path) {
    let siblingUserSkill = execDir.appendingPathComponent("user-skill/total-recall")
    return PluginSources(
      plugin: siblingPlugin,
      userSkill: FileManager.default.fileExists(atPath: siblingUserSkill.path) ? siblingUserSkill : nil,
      userSkillSourceKind: .sibling
    )
  }

  // 3. Resolve symlinks and check Homebrew Cellar structure
  // /opt/homebrew/bin/contextify-query -> ../Cellar/contextify-query/1.0.3/bin/contextify-query
  // Plugin at: /opt/homebrew/Cellar/contextify-query/1.0.3/share/claude-plugin/
  // User skill at: /opt/homebrew/Cellar/contextify-query/1.0.3/share/user-skill/total-recall/
  let resolvedExec = URL(fileURLWithPath: (executablePath as NSString).resolvingSymlinksInPath)
  let cellarBin = resolvedExec.deletingLastPathComponent()  // .../1.0.3/bin/
  let cellarRoot = cellarBin.deletingLastPathComponent()    // .../1.0.3/
  let cellarShare = cellarRoot.appendingPathComponent("share/claude-plugin")
  if FileManager.default.fileExists(atPath: cellarShare.path) {
    let cellarUserSkill = cellarRoot.appendingPathComponent("share/user-skill/total-recall")
    return PluginSources(
      plugin: cellarShare,
      userSkill: FileManager.default.fileExists(atPath: cellarUserSkill.path) ? cellarUserSkill : nil,
      userSkillSourceKind: .cellar
    )
  }

  throw CLIError(
    code: "pluginNotFound",
    message: """
      Plugin files not found.

      If installed via Homebrew:
        brew reinstall contextify-query

      If using the DMG version:
        Open Contextify.app → Settings → CLI → Enable
      """,
    exitCode: .unknown
  )
}

private func findPluginSource() throws -> URL {
  return try findPluginSources().plugin
}

private struct PluginManifest: Codable {
  var version: Int
  var plugins: [String: [PluginEntry]]

  struct PluginEntry: Codable {
    var scope: String
    var installPath: String
    var version: String
    var installedAt: String
    var lastUpdated: String
    var isLocal: Bool?  // Optional: external plugins may not have this field
  }
}

private func updatePluginManifest(manifestPath: URL, installPath: String, version: String) throws {
  var manifest: PluginManifest

  if FileManager.default.fileExists(atPath: manifestPath.path) {
    let data = try Data(contentsOf: manifestPath)
    manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
  } else {
    manifest = PluginManifest(version: 2, plugins: [:])
  }

  let now = ISO8601DateFormatter().string(from: Date())
  let entry = PluginManifest.PluginEntry(
    scope: "user",
    installPath: installPath,
    version: version,
    installedAt: manifest.plugins[pluginIdentifier]?.first?.installedAt ?? now,
    lastUpdated: now,
    isLocal: true
  )

  manifest.plugins[pluginIdentifier] = [entry]

  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(manifest)

  // Ensure parent directory exists
  try FileManager.default.createDirectory(
    at: manifestPath.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try data.write(to: manifestPath, options: .atomic)
}

private func removeFromPluginManifest(manifestPath: URL) throws {
  guard FileManager.default.fileExists(atPath: manifestPath.path) else { return }

  let data = try Data(contentsOf: manifestPath)
  var manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

  manifest.plugins.removeValue(forKey: pluginIdentifier)

  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let newData = try encoder.encode(manifest)
  try newData.write(to: manifestPath, options: .atomic)
}

private struct PluginInstallPayload: Encodable {
  let action: String
  let identifier: String
  let version: String
  let path: String
  let skillSourceKind: String?
  let skillSourcePath: String?
}
#endif  // os(macOS)

#if os(Linux)
private func runInstallPlugin(options: ContextifyQueryCLI.Options) throws {
  let home = FileManager.default.homeDirectoryForCurrentUser
  let userSkillSource = try findUserSkillSource()

  let skillsDir = home.appendingPathComponent(".claude/skills/total-recall")
  let skillFile = userSkillSource.directory.appendingPathComponent("SKILL.md")
  _ = try installSkillFile(
    from: skillFile,
    to: skillsDir,
    target: "claude",
    sourceKind: userSkillSource.sourceKind
  )

  if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
    let warning = "Warning: CODEX_HOME is set to \(codexHome)\nSkill installed to default ~/.codex/skills/ - you may need to copy manually.\n"
    FileHandle.standardError.write(Data(warning.utf8))
  }

  let codexSkillsDir = home.appendingPathComponent(".codex/skills/total-recall")
  _ = try installSkillFile(
    from: skillFile,
    to: codexSkillsDir,
    target: "codex",
    sourceKind: userSkillSource.sourceKind
  )

  struct SkillInstallPayload: Encodable {
    let action: String
    let claudeSkillPath: String
    let codexSkillPath: String
    let skillSourceKind: String
    let skillSourcePath: String
  }

  let payload = SkillInstallPayload(
    action: "installed",
    claudeSkillPath: skillsDir.path,
    codexSkillPath: codexSkillsDir.path,
    skillSourceKind: userSkillSource.sourceKind.rawValue,
    skillSourcePath: skillFile.resolvingSymlinksInPath().path
  )

  if options.jsonOutput {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let envelope = SuccessEnvelope(type: "pluginInstalled", schemaVersion: ResponseConstants.schemaVersion, data: payload, metadata: nil)
    let data = try encoder.encode(envelope)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  } else {
    print("Contextify Total Recall installed!")
    print("  Skill source: \(describeSkillSource(userSkillSource.sourceKind))")
    print("    \(skillFile.resolvingSymlinksInPath().path)")
    if userSkillSource.sourceKind == .repo {
      print("  Warning: repo-local skill source is active (developer install)")
    }
    print("  Claude Code: \(skillsDir.path)")
    print("  Codex CLI:   \(codexSkillsDir.path)")
    print("")
    print("Restart your CLI tool, then use /total-recall to search history.")
  }
}

private func runUninstallPlugin(options: ContextifyQueryCLI.Options) throws {
  let home = FileManager.default.homeDirectoryForCurrentUser
  let claudeSkillDir = home.appendingPathComponent(".claude/skills/total-recall")
  if FileManager.default.fileExists(atPath: claudeSkillDir.path) {
    try FileManager.default.removeItem(at: claudeSkillDir)
  }

  let codexSkillDir = home.appendingPathComponent(".codex/skills/total-recall")
  if FileManager.default.fileExists(atPath: codexSkillDir.path) {
    try FileManager.default.removeItem(at: codexSkillDir)
  }

  struct SkillUninstallPayload: Encodable {
    let action: String
    let claudeSkillPath: String
    let codexSkillPath: String
  }

  let payload = SkillUninstallPayload(
    action: "uninstalled",
    claudeSkillPath: claudeSkillDir.path,
    codexSkillPath: codexSkillDir.path
  )

  if options.jsonOutput {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let envelope = SuccessEnvelope(type: "pluginUninstalled", schemaVersion: ResponseConstants.schemaVersion, data: payload, metadata: nil)
    let data = try encoder.encode(envelope)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  } else {
    print("Uninstalled Total Recall skills")
  }
}

private struct ResolvedUserSkillSource {
  let directory: URL
  let sourceKind: CLIHealthChecker.SkillInstallSourceKind
}

private func findUserSkillSource() throws -> ResolvedUserSkillSource {
  let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let repoUserSkill = cwdURL.appendingPathComponent("contextify-query/user-skill/total-recall")
  if FileManager.default.fileExists(atPath: repoUserSkill.path) {
    return ResolvedUserSkillSource(directory: repoUserSkill, sourceKind: .repo)
  }

  var executablePath = CommandLine.arguments[0]
  if !executablePath.contains("/") {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [executablePath]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
         !path.isEmpty {
        executablePath = path
      }
    }
  }

  let executableURL = URL(fileURLWithPath: executablePath)
  let execDir = executableURL.deletingLastPathComponent()
  let siblingUserSkill = execDir.appendingPathComponent("user-skill/total-recall")
  if FileManager.default.fileExists(atPath: siblingUserSkill.path) {
    return ResolvedUserSkillSource(directory: siblingUserSkill, sourceKind: .sibling)
  }

  let resolvedExec = URL(fileURLWithPath: (executablePath as NSString).resolvingSymlinksInPath)
  let cellarBin = resolvedExec.deletingLastPathComponent()
  let cellarRoot = cellarBin.deletingLastPathComponent()
  let cellarUserSkill = cellarRoot.appendingPathComponent("share/user-skill/total-recall")
  if FileManager.default.fileExists(atPath: cellarUserSkill.path) {
    return ResolvedUserSkillSource(directory: cellarUserSkill, sourceKind: .cellar)
  }

  throw CLIError(
    code: "pluginNotFound",
    message: """
      Skill files not found.

      If using the Linux release tarball:
        Extract the archive and run install-skill from that directory.
      """,
    exitCode: .unknown
  )
}
#endif  // os(Linux)

// MARK: - Doctor Command

private func runDoctor(options: ContextifyQueryCLI.Options) throws {
  let report = CLIHealthChecker.checkHealth()

  if options.jsonOutput {
    // JSON output: encode the full health report
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let payload = SuccessEnvelope(
      type: "doctor",
      schemaVersion: ResponseConstants.schemaVersion,
      data: report,
      metadata: nil
    )
    let data = try encoder.encode(payload)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  } else {
    // Human-readable output
    printDoctorReport(report)
  }

  // Exit with non-zero if not healthy
  switch report.overall {
  case .healthy:
    break
  case .degraded:
    exit(1)
  case .broken, .unconfigured:
    exit(2)
  }
}

private func printDoctorReport(_ report: CLIHealthChecker.HealthReport) {
  // Header with overall status
  let statusEmoji: String
  let statusText: String
  switch report.overall {
  case .healthy:
    statusEmoji = "ok"
    statusText = "healthy"
  case .degraded:
    statusEmoji = "!!"
    statusText = "degraded"
  case .broken:
    statusEmoji = "XX"
    statusText = "broken"
  case .unconfigured:
    statusEmoji = "--"
    statusText = "unconfigured"
  }

  print("Contextify CLI Health Check")
  print("===========================")
  print("")
  print("Status: [\(statusEmoji)] \(statusText)")
  print("Platform: \(report.platform)")
  print("")

  // Components section
  print("Components:")

  // Shim
  let shimStatus = report.components.shim.installed ? "installed" : "not installed"
  print("  Shim: \(shimStatus)")
  if let path = report.components.shim.path {
    print("    Path: \(path)")
    print("    On PATH: \(report.components.shim.onPath ? "yes" : "no")")
  }

  // Manifest
  let manifestStatus = report.components.manifest.present ? "present" : "missing"
  print("  Manifest: \(manifestStatus)")
  if let version = report.components.manifest.version {
    print("    Version: \(version)")
  }

  // Skills
  print("  Skills:")
  print("    Claude Code: \(report.components.skills.claudeSkillPresent ? "installed" : "missing")")
  if let path = report.components.skills.claudeSkillPath {
    print("      Path: \(path)")
  }
  printSkillDetails(report.components.skills.claudeSkillDetails)
  print("    Codex CLI: \(report.components.skills.codexSkillPresent ? "installed" : "missing")")
  if let path = report.components.skills.codexSkillPath {
    print("      Path: \(path)")
  }
  printSkillDetails(report.components.skills.codexSkillDetails)

  // Issues section
  if !report.issues.isEmpty {
    print("")
    print("Issues:")
    for issue in report.issues {
      let severityMarker = issue.severity == .error ? "[ERROR]" : "[WARN]"
      print("  \(severityMarker) \(issue.code): \(issue.message)")
      if let fix = issue.fix {
        print("    Fix: \(fix)")
      }
    }
  }

  print("")
}

private func printSkillDetails(_ details: CLIHealthChecker.InstalledSkillStatus) {
  if let status = details.provenanceStatus {
    print("      Provenance: \(describeProvenanceStatus(status))")
  }
  if let sourceKind = details.installSourceKind {
    print("      Source: \(describeSkillSource(sourceKind))")
  }
  if let sourcePath = details.installSourcePath {
    print("        \(sourcePath)")
  }
  if let installedAt = details.installedAt {
    print("      Installed at: \(installedAt)")
  }
  if let installerVersion = details.installerVersion {
    print("      Installed by CLI: \(installerVersion)")
  }
}

private func describeProvenanceStatus(_ status: CLIHealthChecker.SkillProvenanceStatus) -> String {
  switch status {
  case .current:
    return "current"
  case .metadataMissing:
    return "metadata missing"
  case .metadataUnreadable:
    return "metadata unreadable"
  case .skillUnreadable:
    return "skill unreadable"
  case .modified:
    return "installed file modified"
  case .sourceChanged:
    return "source changed since install"
  case .sourceMissing:
    return "recorded source missing"
  }
}
