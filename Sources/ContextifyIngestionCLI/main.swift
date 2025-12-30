import ArgumentParser
#if os(macOS)
import ContextifyCore
#else
import ContextifyIngestionCore
#endif

/// CLI version - in CI builds, Version.generated.swift defines generatedCLIVersion
/// For local development, fallback to dev version
#if GENERATED_VERSION
let cliVersion = generatedCLIVersion
#else
let cliVersion = "1.0.0-dev"
#endif

/// Cross-Platform Ingestion CLI for Contextify.
///
/// This CLI ingests Claude Code/Codex transcripts on both macOS and Linux,
/// producing a Contextify-compatible SQLite database.
///
/// Usage:
///   contextify-ingest discover                    # Find transcripts
///   contextify-ingest ingest --db path.db         # Ingest transcripts
///   contextify-ingest verify --db path.db         # Verify database
///   contextify-ingest schema dump --db path.db    # Dump schema
@main
struct ContextifyIngest: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "contextify-ingest",
    abstract: "Ingest Claude Code/Codex transcripts into Contextify database",
    version: "\(cliVersion) (schema v\(DatabaseSchema.currentVersion))",
    subcommands: [
      IngestCommand.self,
      VerifyCommand.self,
      SchemaCommand.self,
      DiscoverCommand.self
    ],
    defaultSubcommand: nil
  )
}
