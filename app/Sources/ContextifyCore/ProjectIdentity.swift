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
      // Extract CWD from transcript JSONL files using robust multi-file strategy.

      // Get all .jsonl files, sorted by size (larger files more likely to contain CWD)
      let transcriptFiles = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )
      .filter { $0.pathExtension == "jsonl" }
      .sorted { (url1, url2) -> Bool in
        let size1 = (try? url1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let size2 = (try? url2.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size1 > size2  // Larger files first
      }

      guard !transcriptFiles.isEmpty else {
        throw ProjectIdentityError.cannotReadSessionMetadata
      }

      // Try each file until we find a CWD
      for transcriptFile in transcriptFiles {
        if let cwd = try? extractCwdFromTranscript(transcriptFile) {
          return try canonicalizePath(cwd)
        }
      }

      // No CWD found in any transcript file
      throw ProjectIdentityError.cannotReadSessionMetadata

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

  /// Extract CWD from a Claude Code transcript JSONL file (for orphaned project detection)
  /// Returns the CWD path WITHOUT validation - use for orphaned projects where directory may not exist
  /// - Parameter fileURL: URL to transcript file
  /// - Returns: CWD string if found, nil otherwise
  public static func extractCwdFromTranscriptForOrphaned(_ fileURL: URL) throws -> String? {
    guard let fileHandle = FileHandle(forReadingAtPath: fileURL.path) else {
      return nil
    }
    defer { fileHandle.closeFile() }

    // Read up to 64KB (enough for most transcript headers + initial messages)
    let data = fileHandle.readData(ofLength: 65536)
    guard let content = String(data: data, encoding: .utf8) else {
      return nil
    }

    // Parse each line until we find one with a CWD field
    // Supports both Claude Code (top-level cwd) and Codex (payload.cwd)
    struct RecordWithCwd: Codable {
      let cwd: String?
    }
    struct CodexPayload: Codable {
      let cwd: String?
    }
    struct CodexRecord: Codable {
      let payload: CodexPayload?
    }

    let lines = content.components(separatedBy: .newlines)
    for line in lines where !line.isEmpty {
      guard let jsonData = line.data(using: .utf8) else {
        continue
      }

      // Try Claude Code format (top-level cwd)
      if let record = try? JSONDecoder().decode(RecordWithCwd.self, from: jsonData),
         let cwd = record.cwd {
        return cwd
      }

      // Try Codex format (payload.cwd)
      if let record = try? JSONDecoder().decode(CodexRecord.self, from: jsonData),
         let cwd = record.payload?.cwd {
        return cwd
      }
    }

    return nil
  }

  /// Extract CWD from a Claude Code transcript JSONL file
  /// - Parameter fileURL: URL to transcript file
  /// - Returns: CWD string if found, nil otherwise
  private static func extractCwdFromTranscript(_ fileURL: URL) throws -> String? {
    guard let fileHandle = FileHandle(forReadingAtPath: fileURL.path) else {
      return nil
    }
    defer { fileHandle.closeFile() }

    // Read up to 64KB (enough for most transcript headers + initial messages)
    let data = fileHandle.readData(ofLength: 65536)
    guard let content = String(data: data, encoding: .utf8) else {
      return nil
    }

    // Parse each line until we find one with a CWD field
    struct RecordWithCwd: Codable {
      let cwd: String?
    }

    let lines = content.components(separatedBy: .newlines)
    for line in lines where !line.isEmpty {
      guard let jsonData = line.data(using: .utf8),
            let record = try? JSONDecoder().decode(RecordWithCwd.self, from: jsonData),
            let cwd = record.cwd else {
        continue
      }

      return cwd
    }

    return nil
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
