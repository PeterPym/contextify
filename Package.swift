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
    .package(url: "https://github.com/soffes/HotKey", from: "0.2.1")
  ],
  targets: [
    .target(
      name: "ContextifyCore",
      path: "app/Sources/ContextifyCore",
      swiftSettings: [
        .define("SWIFT_PACKAGE")
      ]
    )
  ]
)
