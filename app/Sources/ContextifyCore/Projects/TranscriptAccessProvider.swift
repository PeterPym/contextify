import Foundation

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

  public func withAccess<T>(
    for provider: String,
    _ body: @Sendable (URL) throws -> T
  ) throws -> T {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let root: URL
    switch provider {
    case TranscriptProviderID.claude:
      root = home.appendingPathComponent(".claude/projects")
    case TranscriptProviderID.codex:
      root = home.appendingPathComponent(".codex/sessions")
    default:
      root = home
    }
    return try body(root)
  }
}
