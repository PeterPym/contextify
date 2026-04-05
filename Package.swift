// swift-tools-version: 6.0
import PackageDescription

// ============================================================================
// Cross-Platform Package Configuration
// ============================================================================
//
// This package supports both macOS (full app) and Linux (CLI).
//
// Architecture:
// - Linux: ContextifyIngestionCore + unified `contextify` CLI
// - macOS: ContextifyCore (full library) + existing CLIs + tests
//
// The ContextifyIngestionCore target shares sources with ContextifyCore for now.
// On macOS, we build ContextifyCore (full features). On Linux, we build
// ContextifyIngestionCore (ingestion subset). Phase 3 will split the sources
// properly and establish the inverted dependency (Core -> IngestionCore).
//
// CLI Architecture (Linux):
// - `contextify` is the unified CLI binary with all commands
// - `contextify-ingest` and `contextify-query` are symlinks for backwards compat
// - Commands are in ContextifyIngestionCommands (shared library)
//
// NOTE: The `platforms:` stanza only affects Apple platforms (sets minimum
// deployment targets). Linux builds are unaffected per Swift Evolution SE-0236.
// ============================================================================

#if os(macOS)
// macOS: Full build with all targets
// Unified CLI: 'contextify' is primary, 'contextify-query' kept for backwards compat
let products: [Product] = [
  .library(name: "ContextifyCore", targets: ["ContextifyCore"]),
  .library(name: "ContextifyCloudCommands", targets: ["ContextifyCloudCommands"]),
  .executable(name: "TranscriptValidatorCLI", targets: ["TranscriptValidatorCLI"]),
  .executable(name: "contextify", targets: ["ContextifyQueryCLI"]),
  .executable(name: "contextify-query", targets: ["ContextifyQueryCLI"]),
  .executable(name: "contextify-ingest", targets: ["ContextifyIngestionCLI"]),
]

let targets: [Target] = [
  .target(
    name: "ContextifyCore",
    dependencies: [
      .product(name: "GRDB", package: "GRDB.swift"),
      .product(name: "Crypto", package: "swift-crypto"),
    ],
    path: "app/Sources/ContextifyCore",
    swiftSettings: [
      .define("SWIFT_PACKAGE"),
    ]
  ),
  // Shared cloud commands library - exposes CloudCommand (ArgumentParser-based)
  // via CloudCommandBridge to ContextifyQueryCLI on macOS.
  // On Linux, CloudCommand.swift is compiled as part of ContextifyCLI directly.
  .target(
    name: "ContextifyCloudCommands",
    dependencies: [
      "ContextifyCore",
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    path: "Sources/ContextifyCLI",
    sources: ["Commands/CloudCommand.swift", "CLIStyle.swift", "CloudCommandBridge.swift"]
  ),
  .executableTarget(
    name: "TranscriptValidatorCLI",
    dependencies: ["ContextifyCore"],
    path: "Sources/TranscriptValidatorCLI"
  ),
  .executableTarget(
    name: "ContextifyQueryCLI",
    dependencies: [
      "ContextifyCore",
      "ContextifyCloudCommands",
    ],
    path: "Sources/ContextifyQueryCLI"
  ),
  // Cross-platform CLI - on macOS, depends on ContextifyCore
  .executableTarget(
    name: "ContextifyIngestionCLI",
    dependencies: [
      "ContextifyCore",
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    path: "Sources/ContextifyIngestionCLI",
    swiftSettings: [
      .unsafeFlags(["-parse-as-library"])
    ]
  ),
  .testTarget(
    name: "ContextifyCoreTests",
    dependencies: [
      "ContextifyCore",
      .product(name: "GRDB", package: "GRDB.swift"),
      .product(name: "SwiftSyntax", package: "swift-syntax"),
      .product(name: "SwiftParser", package: "swift-syntax"),
    ],
    path: "Tests/ContextifyCoreTests"
  ),
]
#else
// Linux: Unified CLI with backwards-compatible aliases
let products: [Product] = [
  .library(name: "ContextifyIngestionCore", targets: ["ContextifyIngestionCore"]),
  // Unified CLI binary - the main entry point
  .executable(name: "contextify", targets: ["ContextifyCLI"]),
  // Legacy binary (kept for backwards compatibility during transition)
  .executable(name: "contextify-ingest", targets: ["ContextifyIngestionCLI"]),
]

// Files included in Linux ingestion build (requires GRDB)
// Paths are relative to app/Sources/ContextifyCore/
let linuxIngestionSources: [String] = [
  // Platform abstractions (cross-platform)
  "Platform/CrossPlatformCrypto.swift",
  "Platform/CrossPlatformLock.swift",
  "Platform/CrossPlatformLogger.swift",
  "Platform/IngestionEventSink.swift",
  "Platform/MachineID.swift",
  "Platform/PlatformSandbox.swift",
  "Platform/XDGPaths.swift",
  // Database layer (ingestion only - no OSLog privacy modifiers)
  "Database/BulkIngestManager.swift",
  "Database/DatabaseSchema.swift",
  "Database/KeyGeneration.swift",
  "Database/Models.swift",
  "Database/PathNormalizer.swift",
  "Database/Repositories.swift",
  "Database/HooverEngine.swift",
  "Database/TranscriptParsers.swift",
  "Database/IngestProgress.swift",
  "Database/Utilities/TimeUnits.swift",
  // Query service (search, activity, context, projects)
  "Database/EntryFilter.swift",
  "Database/QueryTimeFilters.swift",
  "Database/QueryContentTruncator.swift",
  "Database/FTSQueryBuilder.swift",
  "Database/ContextifyQueryService.swift",
  // Discovery
  "Discovery/LightweightDiscoveryService.swift",
  // Installation (CLI health checking)
  "Installation/CLIHealthChecker.swift",
  // Core types
  "Clock.swift",
  "ContextifyConfig.swift",
  "LaunchArguments.swift",
  "LoggingConfig.swift",
  "ProjectIdentity.swift",
  "Projects/ProjectModels.swift",
  "Projects/TranscriptAccessProvider.swift",
  "Projects/TranscriptProviderID.swift",
]

let targets: [Target] = [
  // Cross-platform ingestion library (requires GRDB for database operations)
  // Also includes CLIHealthChecker for unified CLI
  .target(
    name: "ContextifyIngestionCore",
    dependencies: [
      .product(name: "GRDB", package: "GRDB.swift"),
      .product(name: "Crypto", package: "swift-crypto"),
    ],
    path: "app/Sources/ContextifyCore",
    sources: linuxIngestionSources,
    swiftSettings: [
      .define("SWIFT_PACKAGE"),
      .define("INGESTION_CORE"),  // Flag for conditional compilation
    ]
  ),
  // Shared ingestion commands library
  // Contains IngestCommand, VerifyCommand, SchemaCommand, DiscoverCommand
  .target(
    name: "ContextifyIngestionCommands",
    dependencies: [
      "ContextifyIngestionCore",
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    path: "Sources/ContextifyIngestionCLI",
    exclude: ["main.swift"],  // Exclude the entry point
    swiftSettings: [
      .define("SWIFT_PACKAGE"),
    ]
  ),
  // Unified CLI - the recommended entry point for Linux users
  // Includes all commands: ingest, discover, verify, schema, install-skill, doctor
  .executableTarget(
    name: "ContextifyCLI",
    dependencies: [
      "ContextifyIngestionCore",
      "ContextifyIngestionCommands",
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    path: "Sources/ContextifyCLI",
    swiftSettings: [
      .unsafeFlags(["-parse-as-library"])
    ]
  ),
  // Legacy ingestion CLI - DEPRECATED, use 'contextify ingest' instead
  .executableTarget(
    name: "ContextifyIngestionCLI",
    dependencies: [
      "ContextifyIngestionCore",
      "ContextifyIngestionCommands",
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    path: "Sources/ContextifyIngestionCLI",
    sources: ["main.swift"],  // Only include the entry point
    swiftSettings: [
      .unsafeFlags(["-parse-as-library"])
    ]
  ),
]
#endif

// Platform-conditional dependencies
// swift-syntax is only used by tests (macOS only)
#if os(macOS)
let packageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
  .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.0"),
  .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
  .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
]
#else
let packageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
  .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
  .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
]
#endif

let package = Package(
  name: "ContextifySPM",
  // NOTE: platforms stanza only affects Apple platforms. Linux builds are unaffected.
  // Per Swift Evolution SE-0236, non-Apple platforms are implicitly supported.
  platforms: [
    .macOS(.v14)
  ],
  products: products,
  dependencies: packageDependencies,
  targets: targets
)
