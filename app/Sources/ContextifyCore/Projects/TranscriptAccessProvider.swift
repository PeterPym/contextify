import Foundation
import OSLog

/// Errors for CLI transcript path validation
enum TranscriptPathError: LocalizedError {
  case pathNotFound(String)
  case missingBothProviders(String)

  var errorDescription: String? {
    switch self {
    case .pathNotFound(let path):
      return "Transcript path not found: \(path)"
    case .missingBothProviders(let path):
      return """
        No transcript directories found at --transcript-path location: \(path)

        Expected structure:
          \(path)/.claude/projects/  (for Claude Code transcripts)
          \(path)/.codex/sessions/   (for Codex CLI transcripts)

        At least one provider directory must exist.
        See: scripts/benchmarks/create-snapshot.sh
        """
    }
  }
}

/// Protocol for providing security-scoped access to transcript directories.
///
/// Synchronous by design: onboarding obtains permissions ahead of time.
/// This protocol just wraps file operations in a scope (e.g. security-scoped).
public protocol TranscriptAccessProvider: Sendable {
  /// Execute file operations with access to the provider's transcript root.
  ///
  /// - Parameters:
  ///   - provider: Provider identifier (e.g. TranscriptProviderID.claude)
  ///   - body: Closure to execute with access to the provider's root directory.
  ///           Note: Runs synchronously on the calling thread - no async work allowed.
  /// - Returns: Result from the body closure.
  /// - Throws: An error if authorization is missing in sandboxed builds
  ///           or any error thrown by the body closure.
  func withAccess<T>(
    for provider: String,
    _ body: @Sendable (URL) throws -> T
  ) throws -> T
}

/// No-op provider for DMG builds (direct filesystem access).
public struct PassthroughAccessProvider: TranscriptAccessProvider {
  public init() {}

  /// Validate transcript path structure on first access (fail-fast at subsystem init)
  public static func validateTranscriptPath() throws {
    guard let transcriptPath = LaunchArguments.shared.transcriptPath else { return }

    // App Store builds: reject path flags
    #if APPSTORE_BUILD
    fputs("Error: --transcript-path is not supported in App Store builds\n", stderr)
    exit(64)  // EX_USAGE
    #endif

    let base = URL(fileURLWithPath: transcriptPath)

    // Check base path exists and is a directory
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: transcriptPath, isDirectory: &isDir),
          isDir.boolValue else {
      throw TranscriptPathError.pathNotFound(transcriptPath)
    }

    // Check at least one provider directory exists (verify they are directories too)
    let claudePath = base.appendingPathComponent(".claude/projects")
    let codexPath = base.appendingPathComponent(".codex/sessions")

    var claudeIsDir: ObjCBool = false
    var codexIsDir: ObjCBool = false
    let hasClaude = FileManager.default.fileExists(atPath: claudePath.path, isDirectory: &claudeIsDir)
        && claudeIsDir.boolValue
    let hasCodex = FileManager.default.fileExists(atPath: codexPath.path, isDirectory: &codexIsDir)
        && codexIsDir.boolValue

    if !hasClaude && !hasCodex {
      throw TranscriptPathError.missingBothProviders(transcriptPath)
    }
  }

  public func withAccess<T>(
    for provider: String,
    _ body: @Sendable (URL) throws -> T
  ) throws -> T {
    let base: URL
    if let transcriptPath = LaunchArguments.shared.transcriptPath {
      base = URL(fileURLWithPath: transcriptPath)
    } else {
      base = FileManager.default.homeDirectoryForCurrentUser
    }

    let root: URL
    switch provider {
    case TranscriptProviderID.claude:
      root = base.appendingPathComponent(".claude/projects")
    case TranscriptProviderID.codex:
      root = base.appendingPathComponent(".codex/sessions")
    default:
      root = base
    }
    return try body(root)
  }
}
