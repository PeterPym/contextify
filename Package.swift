// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ContextifySPM",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "ContextifyCore", targets: ["ContextifyCore"]),
    .executable(name: "TranscriptValidatorCLI", targets: ["TranscriptValidatorCLI"]),
    .executable(name: "contextify-query", targets: ["ContextifyQueryCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.0")
  ],
  targets: [
    .target(
      name: "ContextifyCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift")
      ],
      path: "app/Sources/ContextifyCore",
      swiftSettings: [
        .define("SWIFT_PACKAGE")
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
    .testTarget(
      name: "ContextifyCoreTests",
      dependencies: [
        "ContextifyCore",
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax")
      ],
      path: "Tests/ContextifyCoreTests"
    )
  ]
)
