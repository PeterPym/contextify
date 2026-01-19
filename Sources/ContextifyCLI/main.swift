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
        contextify search "query"      Search your conversations
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
      // Query commands
      SearchCommand.self,
      ActivityCommand.self,
      ProjectsCommand.self,
      ContextCommand.self,
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

  /// Entry point
  static func main() async {
    // Export version to environment for subcommand libraries to read
    setenv("CONTEXTIFY_CLI_VERSION", cliVersion, 1)

    // ArgumentParser's main(_:) expects args WITHOUT argv[0]
    await Contextify.main(Array(CommandLine.arguments.dropFirst()))
  }
}
