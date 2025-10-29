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
      // Claude Code uses mangled directory names that cannot be reliably reversed
      // (e.g., path hyphens look identical to directory-name hyphens).
      // Instead, read the CWD from the first JSONL record in any transcript file.

      // Find first .jsonl file in directory
      let transcriptFiles = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      ).filter { $0.pathExtension == "jsonl" }

      guard let firstTranscript = transcriptFiles.first else {
        throw ProjectIdentityError.cannotReadSessionMetadata
      }

      // Read first line to extract CWD
      guard let fileHandle = FileHandle(forReadingAtPath: firstTranscript.path) else {
        throw ProjectIdentityError.cannotReadSessionMetadata
      }
      defer { fileHandle.closeFile() }

      // Read first 8KB (enough for first record)
      let data = fileHandle.readData(ofLength: 8192)
      guard let content = String(data: data, encoding: .utf8),
            let firstLine = content.components(separatedBy: .newlines).first else {
        throw ProjectIdentityError.cannotReadSessionMetadata
      }

      // Parse JSON to extract CWD
      struct FirstRecord: Codable {
        let cwd: String?
      }

      guard let jsonData = firstLine.data(using: .utf8),
            let record = try? JSONDecoder().decode(FirstRecord.self, from: jsonData),
            let cwd = record.cwd else {
        throw ProjectIdentityError.cannotReadSessionMetadata
      }

      return try canonicalizePath(cwd)

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
