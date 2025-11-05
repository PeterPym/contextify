// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ContextifySPM",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "ContextifyCore", targets: ["ContextifyCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0")
  ],
  targets: [
    .target(
      name: "ContextifyCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
      ],
      path: "app/Sources/ContextifyCore",
      swiftSettings: [
        .define("SWIFT_PACKAGE")
      ]
    )
  ]
)
