import Foundation
import CryptoKit

/// Errors related to project identity resolution
public enum ProjectIdentityError: Error {
  case unknownProvider(String)
  case invalidDirectory
  case cannotReadSessionMetadata
  case invalidPath
}

/// Project identity and reverse path-mangling utilities
public enum ProjectIdentity {

  /// Compute stable project ID from provider and normalized path
  /// - Parameters:
  ///   - provider: Provider name (e.g., "claude.code", "codex.cli")
  ///   - path: Normalized absolute project path
  /// - Returns: SHA256 hash of "<provider>:<normalizedAbsolutePath>"
  public static func computeProjectID(provider: String, path: String) -> String {
    let input = "\(provider):\(path)"
    let hash = SHA256.hash(data: Data(input.utf8))
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }

  /// Reverse-mangle a project directory name back to absolute project path
  /// - Parameters:
  ///   - provider: Provider name (e.g., "claude.code", "codex.cli")
  ///   - directory: Directory URL containing the mangled project name
  /// - Returns: Canonicalized absolute project path
  /// - Throws: ProjectIdentityError if provider is unknown or path is invalid
  public static func reverseManglePath(provider: String, directory: URL) throws -> String {
    switch provider {
    case "claude.code":
      // Claude Code mangles paths: /Users/rob/my-app → Users__rob__my-app or Users%2Frob%2Fmy-app
      let name = directory.lastPathComponent

      // Step 1: URL decode (handle %2F → /)
      let unescaped = name.removingPercentEncoding ?? name

      // Step 2: Replace __ with /
      let unmangled = unescaped.replacingOccurrences(of: "__", with: "/")

      // Step 3: Ensure leading slash (absolute path)
      let absolutePath = unmangled.hasPrefix("/") ? unmangled : "/" + unmangled

      // Step 4: Canonicalize (resolve symlinks, remove trailing slash)
      return try canonicalizePath(absolutePath)

    case "codex.cli":
      // Codex CLI uses hash-based directory names, read session metadata
      let metaPath = directory.appendingPathComponent("session.json")

      guard FileManager.default.fileExists(atPath: metaPath.path) else {
        throw ProjectIdentityError.cannotReadSessionMetadata
      }

      let data = try Data(contentsOf: metaPath)

      // Parse session.json for project_root field
      struct CodexSessionMeta: Codable {
        let project_root: String
      }

      let meta = try JSONDecoder().decode(CodexSessionMeta.self, from: data)
      return try canonicalizePath(meta.project_root)

    default:
      throw ProjectIdentityError.unknownProvider(provider)
    }
  }

  /// Canonicalize a path (resolve symlinks, remove trailing slash, expand tilde)
  /// - Parameter path: Path to canonicalize
  /// - Returns: Canonicalized absolute path
  /// - Throws: ProjectIdentityError if path is invalid
  public static func canonicalizePath(_ path: String) throws -> String {
    // Expand tilde
    let expanded = NSString(string: path).expandingTildeInPath

    // Convert to URL for symlink resolution
    let url = URL(fileURLWithPath: expanded)
    let resolved = url.resolvingSymlinksInPath()

    // Remove trailing slash
    var canonical = resolved.path
    if canonical.hasSuffix("/") && canonical.count > 1 {
      canonical = String(canonical.dropLast())
    }

    // Verify path exists
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: canonical, isDirectory: &isDir) else {
      throw ProjectIdentityError.invalidPath
    }

    return canonical
  }
}
