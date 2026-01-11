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
  .library(name: "ContextifyQueryCore", targets: ["ContextifyQueryCore"]),
  .executable(name: "contextify-ingest", targets: ["ContextifyIngestionCLI"]),
  .executable(name: "contextify-query", targets: ["ContextifyQueryCLI"]),
]

// Files included in Linux ingestion build (requires GRDB)
// Paths are relative to app/Sources/ContextifyCore/
let linuxIngestionSources: [String] = [
  // Platform abstractions (cross-platform)
  "Platform/CrossPlatformCrypto.swift",
  "Platform/CrossPlatformLock.swift",
  "Platform/CrossPlatformLogger.swift",
  "Platform/IngestionEventSink.swift",
  "Platform/PlatformSandbox.swift",
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
  // Discovery
  "Discovery/LightweightDiscoveryService.swift",
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

// Minimal files for query CLI (doctor command only - no GRDB needed)
// Paths are relative to app/Sources/ContextifyCore/
let linuxQuerySources: [String] = [
  // Installation (CLI health checking) - no dependencies
  "Installation/CLIHealthChecker.swift",
]

let targets: [Target] = [
  // Cross-platform ingestion library (requires GRDB for database operations)
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
  // Lightweight query library (no GRDB - doctor command only)
  .target(
    name: "ContextifyQueryCore",
    dependencies: [],
    path: "app/Sources/ContextifyCore",
    sources: linuxQuerySources,
    swiftSettings: [
      .define("SWIFT_PACKAGE"),
      .define("QUERY_CORE"),  // Flag for conditional compilation
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
  // Query CLI for Linux - doctor command only (no GRDB needed)
  .executableTarget(
    name: "ContextifyQueryCLI",
    dependencies: [
      "ContextifyQueryCore",
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
