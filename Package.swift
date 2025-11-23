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
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
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
    .testTarget(
      name: "ContextifyCoreTests",
      dependencies: [
        "ContextifyCore",
        .product(name: "GRDB", package: "GRDB.swift")
      ],
      path: "Tests/ContextifyCoreTests"
    )
  ]
)
