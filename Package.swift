// swift-tools-version: 6.0
import PackageDescription

// ============================================================================
// Cross-Platform Package Configuration
// ============================================================================
//
// This package supports both macOS (full app) and Linux (ingestion CLI only).
//
// Architecture:
// - Linux: ContextifyIngestionCore + ContextifyIngestionCLI
// - macOS: ContextifyCore (full library) + existing CLIs + tests
//
// The ContextifyIngestionCore target shares sources with ContextifyCore for now.
// On macOS, we build ContextifyCore (full features). On Linux, we build
// ContextifyIngestionCore (ingestion subset). Phase 3 will split the sources
// properly and establish the inverted dependency (Core -> IngestionCore).
//
// NOTE: The `platforms:` stanza only affects Apple platforms (sets minimum
// deployment targets). Linux builds are unaffected per Swift Evolution SE-0236.
// ============================================================================

#if os(macOS)
// macOS: Full build with all targets
let products: [Product] = [
  .library(name: "ContextifyCore", targets: ["ContextifyCore"]),
  .executable(name: "TranscriptValidatorCLI", targets: ["TranscriptValidatorCLI"]),
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
  .executableTarget(
    name: "TranscriptValidatorCLI",
    dependencies: ["ContextifyCore"],
    path: "Sources/TranscriptValidatorCLI"
  ),
  .executableTarget(
    name: "ContextifyQueryCLI",
    dependencies: ["ContextifyCore"],
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
// Linux: Cross-platform ingestion and query CLI
let products: [Product] = [
  .library(name: "ContextifyIngestionCore", targets: ["ContextifyIngestionCore"]),
  .executable(name: "contextify-ingest", targets: ["ContextifyIngestionCLI"]),
  .executable(name: "contextify-query", targets: ["ContextifyQueryCLI"]),
]

// Files included in Linux build
// Paths are relative to app/Sources/ContextifyCore/
let linuxSources: [String] = [
  // Platform abstractions (cross-platform)
  "Platform/CrossPlatformCrypto.swift",
  "Platform/CrossPlatformLock.swift",
  "Platform/CrossPlatformLogger.swift",
  "Platform/IngestionEventSink.swift",
  "Platform/PlatformSandbox.swift",
  // Database layer
  "Database/BulkIngestManager.swift",   // Bulk write optimization
  "Database/ContextifyQueryService.swift",  // Query service for CLI
  "Database/DatabaseManager.swift",     // Database connection management
  "Database/DatabaseMigration.swift",   // Schema migrations
  "Database/DatabaseSchema.swift",
  "Database/EntryFilter.swift",         // Entry filtering
  "Database/KeyGeneration.swift",
  "Database/Models.swift",
  "Database/PathNormalizer.swift",
  "Database/QueryContentTruncator.swift",  // Content truncation
  "Database/QueryTimeFilters.swift",    // Time range filtering
  "Database/Repositories.swift",        // Repository protocols and implementations
  "Database/HooverEngine.swift",        // Transcript parsing engine
  "Database/TranscriptOrchestrator.swift",  // High-level DB API
  "Database/TranscriptParsers.swift",   // Line parsers and metadata parsers
  "Database/IngestProgress.swift",      // Progress reporting protocol
  "Database/Utilities/TimeUnits.swift", // Time unit conversion helpers
  // Discovery
  "Discovery/LightweightDiscoveryService.swift",
  // Installation (CLI health checking)
  "Installation/CLIHealthChecker.swift",
  // Query CLI support
  "QueryCLI/ContextifyQueryShimMarker.swift",
  "QueryCLI/FeedbackInbox.swift",
  // Search
  "Search/ConversationSearchService.swift",
  // Worktree detection
  "Worktree/WorktreeConfig.swift",
  "Worktree/WorktreeDetector.swift",
  // Core types
  "Clock.swift",
  "ContextifyConfig.swift",
  "LaunchArguments.swift",              // CLI argument parsing
  "LoggingConfig.swift",
  "ProjectIdentity.swift",
  "Projects/ProjectModels.swift",
  "Projects/TranscriptAccessProvider.swift",
  "Projects/TranscriptProviderID.swift",
]

let targets: [Target] = [
  // Cross-platform ingestion library (explicit source list for Linux)
  .target(
    name: "ContextifyIngestionCore",
    dependencies: [
      .product(name: "GRDB", package: "GRDB.swift"),
      .product(name: "Crypto", package: "swift-crypto"),
    ],
    path: "app/Sources/ContextifyCore",
    sources: linuxSources,
    swiftSettings: [
      .define("SWIFT_PACKAGE"),
      .define("INGESTION_CORE"),  // Flag for conditional compilation
    ]
  ),
  // Cross-platform CLI - on Linux, depends on ContextifyIngestionCore
  .executableTarget(
    name: "ContextifyIngestionCLI",
    dependencies: [
      "ContextifyIngestionCore",
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    path: "Sources/ContextifyIngestionCLI",
    swiftSettings: [
      .unsafeFlags(["-parse-as-library"])
    ]
  ),
  // Query CLI for Linux - install-plugin and doctor commands
  .executableTarget(
    name: "ContextifyQueryCLI",
    dependencies: [
      "ContextifyIngestionCore",
    ],
    path: "Sources/ContextifyQueryCLI"
  ),
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
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
  ],
  targets: targets
)
