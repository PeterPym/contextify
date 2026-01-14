import ArgumentParser
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
import ContextifyIngestionCommands
#endif

// MARK: - Version

/// CLI version - in CI builds, Version.generated.swift defines generatedCLIVersion
/// For local development, fallback to dev version
#if GENERATED_VERSION
let cliVersion = generatedCLIVersion
#else
let cliVersion = "1.1.0-dev"
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

// MARK: - argv[0] Dispatch

/// Determine how the binary was invoked and handle backwards compatibility
private func handleArgv0Dispatch() -> [String]? {
  let executableName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

  switch executableName {
  case "contextify-ingest":
    warnDeprecated("'contextify-ingest' is deprecated. Use 'contextify ingest' instead.")
    // Transform: contextify-ingest [args] -> contextify ingest [args]
    var newArgs = Array(CommandLine.arguments.dropFirst())
    // If no subcommand given, default to "ingest"
    if newArgs.isEmpty || newArgs[0].hasPrefix("-") {
      newArgs.insert("ingest", at: 0)
    }
    return newArgs

  case "contextify-query":
    warnDeprecated("'contextify-query' is deprecated. Use 'contextify doctor', 'contextify install-skill', or 'contextify uninstall-skill' instead.")
    // Transform contextify-query commands to contextify equivalents
    var args = Array(CommandLine.arguments.dropFirst())
    if let first = args.first {
      switch first {
      case "install-plugin":
        args[0] = "install-skill"
      case "uninstall-plugin":
        args[0] = "uninstall-skill"
      case "doctor":
        // Already matches
        break
      default:
        // Unknown command - pass through
        break
      }
    }
    return args

  default:
    // Normal invocation as 'contextify'
    return nil
  }
}

// MARK: - Main Command

/// Contextify CLI - Search and manage your AI coding conversations
///
/// This is the unified command-line interface for Contextify, providing
/// transcript ingestion, database management, and search capabilities.
@main
struct Contextify: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "contextify",
    abstract: "Search and manage your AI coding conversations",
    discussion: """
      Contextify indexes transcripts from Claude Code and Codex CLI into a
      searchable database. Use the subcommands below to ingest transcripts,
      query your conversation history, and manage the CLI installation.

      GETTING STARTED:
        contextify ingest              Index new transcripts
        contextify status              Show what's indexed
        contextify install-skill       Install Total Recall skill
        contextify install-service     Set up automatic ingestion (Linux)
        contextify doctor              Check installation health

      DATABASE LOCATION (in order of precedence):
        1. --db flag on individual commands
        2. CONTEXTIFY_DB_PATH environment variable
        3. XDG_DATA_HOME/contextify/contextify.db
        4. ~/.local/share/contextify/contextify.db (default)

      DOCUMENTATION: https://contextify.sh/docs/
      """,
    version: "\(cliVersion) (schema v\(DatabaseSchema.currentVersion))",
    subcommands: [
      // Ingestion and database commands
      IngestCommand.self,
      StatusCommand.self,
      DiscoverCommand.self,
      VerifyCommand.self,
      MigrateDbCommand.self,
      SchemaCommand.self,
      // Service management (Linux)
      InstallServiceCommand.self,
      UninstallServiceCommand.self,
      ServiceStatusCommand.self,
      // Skill/plugin management
      InstallSkillCommand.self,
      UninstallSkillCommand.self,
      // Health check
      DoctorCommand.self,
    ],
    defaultSubcommand: nil
  )

  /// Entry point - handles argv[0] dispatch for backwards compatibility
  static func main() async {
    // Export version to environment for subcommand libraries to read
    setenv("CONTEXTIFY_CLI_VERSION", cliVersion, 1)

    // Check for backwards-compatible invocation
    if let transformedArgs = handleArgv0Dispatch() {
      // Re-invoke with transformed arguments
      let allArgs = ["contextify"] + transformedArgs
      await Contextify.main(allArgs)
    } else {
      // Normal invocation - pass through original arguments
      // Note: Must call main(_:) not main() to avoid infinite recursion
      await Contextify.main(CommandLine.arguments)
    }
  }
}
