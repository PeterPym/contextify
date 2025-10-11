import Foundation
import CryptoKit

// MARK: - SHA256 Utilities

public enum SHA256Utils {
  /// Computes SHA256 hash of a string and returns hex representation
  public static func hash(_ string: String) -> String {
    let data = Data(string.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }

  /// Computes SHA256 hash of data and returns hex representation
  public static func hash(_ data: Data) -> String {
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }

  /// Computes window SHA256 for timeline cache
  /// Explicit versioned format: "win:v1|{prev2}|{prev1}"
  /// Uses "-" for nil entries to ensure stable cache keys
  public static func computeWindowSHA256(prev2: String?, prev1: String?) -> String {
    let s = "win:v1|\(prev2 ?? "-")|\(prev1 ?? "-")"
    return hash(s)
  }

  /// Incremental SHA256 hasher for streaming transcript hashing
  public final class IncrementalHasher {
    private var hasher = CryptoKit.SHA256()

    public init() {}

    /// Update hash with a line of data
    public func update(lineData: Data) {
      hasher.update(data: lineData)
      hasher.update(data: Data([0x0A])) // newline
    }

    /// Finalize and return hex string
    public func finalize() -> String {
      let hash = hasher.finalize()
      return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
  }
}

// MARK: - Generator Signature

/// Helper for constructing/parsing generator signatures
/// Format: "{model}@{modelVersion}:{prompt}@{promptVersion}"
/// Example: "gpt-4o@2025-09:timeline@3"
public struct GeneratorSignature {
  public let model: String
  public let modelVersion: String
  public let prompt: String
  public let promptVersion: String

  public init(model: String, modelVersion: String, prompt: String, promptVersion: String) {
    self.model = model
    self.modelVersion = modelVersion
    self.prompt = prompt
    self.promptVersion = promptVersion
  }

  public var string: String {
    "\(model)@\(modelVersion):\(prompt)@\(promptVersion)"
  }

  public static func parse(_ sig: String) -> GeneratorSignature? {
    let parts = sig.split(separator: ":")
    guard parts.count == 2 else { return nil }
    let m = parts[0].split(separator: "@")
    let p = parts[1].split(separator: "@")
    guard m.count == 2, p.count == 2 else { return nil }
    return .init(
      model: String(m[0]),
      modelVersion: String(m[1]),
      prompt: String(p[0]),
      promptVersion: String(p[1])
    )
  }
}

// MARK: - Deterministic Entry ID Generation

public enum EntryIDGenerator {
  /// Generates deterministic entry ID for Codex CLI entries
  /// Based on SHA256 hash of (timestamp|role|lineNumber|sessionID)
  public static func generateEntryID(
    timestamp: Date,
    role: String,
    lineNumber: Int,
    sessionID: String
  ) -> String {
    let components = "\(timestamp.timeIntervalSince1970)|\(role)|\(lineNumber)|\(sessionID)"
    let hashString = SHA256Utils.hash(components)

    // Convert to UUID format (8-4-4-4-12)
    let prefix8 = String(hashString.prefix(8))
    let part1 = String(hashString.dropFirst(8).prefix(4))
    let part2 = String(hashString.dropFirst(12).prefix(4))
    let part3 = String(hashString.dropFirst(16).prefix(4))
    let suffix12 = String(hashString.dropFirst(20).prefix(12))

    return "\(prefix8)-\(part1)-\(part2)-\(part3)-\(suffix12)"
  }
}

// MARK: - Path Canonicalization

public enum PathUtils {
  /// Canonicalizes a file path by resolving symlinks
  public static func canonicalizePath(_ path: String) -> String {
    URL(fileURLWithPath: path)
      .resolvingSymlinksInPath()
      .standardizedFileURL
      .path
  }

  /// Canonicalizes a file URL
  public static func canonicalize(_ url: URL) -> URL {
    url.resolvingSymlinksInPath().standardizedFileURL
  }
}
