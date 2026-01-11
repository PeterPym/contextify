import XCTest

/// Tests for plugin manifest JSON decoding resilience.
/// The manifest format must tolerate:
/// 1. Missing optional fields (isLocal may not exist in older/external entries)
/// 2. Unknown fields (gitCommitSha, future fields from Claude's plugin system)
final class PluginManifestDecodingTests: XCTestCase {

  // MARK: - Structs that mirror production code

  /// This struct has isLocal as NON-optional, which will FAIL on real manifests.
  /// This demonstrates the bug before the fix.
  private struct PluginManifestStrict: Codable {
    var version: Int
    var plugins: [String: [PluginEntryStrict]]

    struct PluginEntryStrict: Codable {
      var scope: String
      var installPath: String
      var version: String
      var installedAt: String
      var lastUpdated: String
      var isLocal: Bool  // NON-optional - this is the bug!
    }
  }

  /// This struct has isLocal as optional, which correctly handles real manifests.
  /// This is the fix.
  private struct PluginManifest: Codable {
    var version: Int
    var plugins: [String: [PluginEntry]]

    struct PluginEntry: Codable {
      var scope: String
      var installPath: String
      var version: String
      var installedAt: String
      var lastUpdated: String
      var isLocal: Bool?  // Optional - tolerates missing field
    }
  }

  // MARK: - Tests

  /// Real-world manifest JSON that lacks `isLocal` field.
  /// This is what Claude's plugin system actually produces.
  private let realWorldManifestJSON = """
  {
    "version": 2,
    "plugins": {
      "query@contextify": [{
        "scope": "user",
        "installPath": "/Users/test/.claude/plugins/cache/contextify/query/1.1.0",
        "version": "1.1.0",
        "installedAt": "2026-01-10T22:51:01Z",
        "lastUpdated": "2026-01-10T22:51:01Z"
      }],
      "swift-lsp@claude-plugins-official": [{
        "scope": "user",
        "installPath": "/Users/test/.claude/plugins/cache/claude-plugins-official/swift-lsp/1.0.0",
        "version": "1.0.0",
        "installedAt": "2026-01-10T23:04:54.671Z",
        "lastUpdated": "2026-01-10T23:04:54.671Z",
        "gitCommitSha": "f1be96f0fb58d5aaf2840ca7d7036d5c0923742c"
      }]
    }
  }
  """.data(using: .utf8)!

  func testStrictStructFailsOnRealWorldManifest() throws {
    // This test demonstrates the BUG: strict struct fails on real data
    // The real manifest lacks `isLocal`, so decoding fails.
    XCTAssertThrowsError(
      try JSONDecoder().decode(PluginManifestStrict.self, from: realWorldManifestJSON)
    ) { error in
      // Verify it's a key not found error for "isLocal"
      guard case DecodingError.keyNotFound(let key, _) = error else {
        XCTFail("Expected keyNotFound error, got: \(error)")
        return
      }
      XCTAssertEqual(key.stringValue, "isLocal")
    }
  }

  func testFlexibleStructSucceedsOnRealWorldManifest() throws {
    // This test shows the FIX: flexible struct handles real data
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: realWorldManifestJSON)

    XCTAssertEqual(manifest.version, 2)
    XCTAssertEqual(manifest.plugins.count, 2)
    XCTAssertEqual(manifest.plugins["query@contextify"]?.first?.version, "1.1.0")
    XCTAssertNil(manifest.plugins["query@contextify"]?.first?.isLocal)  // Missing field = nil
    XCTAssertEqual(manifest.plugins["swift-lsp@claude-plugins-official"]?.first?.version, "1.0.0")
  }

  func testDecodesManifestWithKnownFieldsOnly() throws {
    let json = """
    {
      "version": 2,
      "plugins": {
        "query@contextify": [{
          "scope": "user",
          "installPath": "/Users/test/.claude/plugins/cache/contextify/query/1.1.0",
          "version": "1.1.0",
          "installedAt": "2026-01-10T22:51:01Z",
          "lastUpdated": "2026-01-10T22:51:01Z",
          "isLocal": true
        }]
      }
    }
    """.data(using: .utf8)!

    let manifest = try JSONDecoder().decode(PluginManifest.self, from: json)

    XCTAssertEqual(manifest.version, 2)
    XCTAssertEqual(manifest.plugins.count, 1)
    XCTAssertEqual(manifest.plugins["query@contextify"]?.first?.version, "1.1.0")
  }

  func testDecodesManifestWithUnknownFields() throws {
    // This JSON includes `gitCommitSha` which is not in our PluginEntry struct.
    // Real-world manifests from Claude's plugin system may have additional fields.
    // Our decoder MUST tolerate unknown fields to avoid breaking when Claude adds new ones.
    let json = """
    {
      "version": 2,
      "plugins": {
        "query@contextify": [{
          "scope": "user",
          "installPath": "/Users/test/.claude/plugins/cache/contextify/query/1.1.0",
          "version": "1.1.0",
          "installedAt": "2026-01-10T22:51:01Z",
          "lastUpdated": "2026-01-10T22:51:01Z",
          "isLocal": true
        }],
        "swift-lsp@claude-plugins-official": [{
          "scope": "user",
          "installPath": "/Users/test/.claude/plugins/cache/claude-plugins-official/swift-lsp/1.0.0",
          "version": "1.0.0",
          "installedAt": "2026-01-10T23:04:54.671Z",
          "lastUpdated": "2026-01-10T23:04:54.671Z",
          "gitCommitSha": "f1be96f0fb58d5aaf2840ca7d7036d5c0923742c"
        }]
      }
    }
    """.data(using: .utf8)!

    // This should NOT throw - unknown fields should be ignored
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: json)

    XCTAssertEqual(manifest.version, 2)
    XCTAssertEqual(manifest.plugins.count, 2)
    XCTAssertEqual(manifest.plugins["query@contextify"]?.first?.version, "1.1.0")
    XCTAssertEqual(manifest.plugins["swift-lsp@claude-plugins-official"]?.first?.version, "1.0.0")
  }

  func testDecodesManifestWithFutureUnknownFields() throws {
    // Simulate a future version of Claude adding new fields we don't know about yet
    let json = """
    {
      "version": 2,
      "plugins": {
        "some-plugin@vendor": [{
          "scope": "user",
          "installPath": "/some/path",
          "version": "1.0.0",
          "installedAt": "2026-01-10T00:00:00Z",
          "lastUpdated": "2026-01-10T00:00:00Z",
          "futureField1": "some value",
          "futureField2": 42,
          "futureField3": { "nested": "object" },
          "futureField4": ["array", "of", "values"]
        }]
      }
    }
    """.data(using: .utf8)!

    // Must not throw - forward compatibility is critical
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: json)

    XCTAssertEqual(manifest.plugins["some-plugin@vendor"]?.first?.version, "1.0.0")
  }
}
