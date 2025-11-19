import Foundation
import ContextifyCore

/// Concrete provider for App Store (sandboxed) builds.
/// Built once during app initialization with security-scoped URLs.
///
/// Note: Security-scoped access is started when bookmarks are resolved
/// and remains active for the lifetime of the URL references.
struct SandboxTranscriptAccessProvider: TranscriptAccessProvider {
  let claudeRoot: URL?
  let codexRoot: URL?

  init(claudeRoot: URL?, codexRoot: URL?) {
    self.claudeRoot = claudeRoot
    self.codexRoot = codexRoot

    // Start security-scoped access for both roots if available
    // This keeps access open for the lifetime of the provider
    _ = claudeRoot?.startAccessingSecurityScopedResource()
    _ = codexRoot?.startAccessingSecurityScopedResource()
  }

  func withAccess<T>(
    for provider: String,
    _ body: @Sendable (URL) throws -> T
  ) throws -> T {
    let root: URL
    switch provider {
    case TranscriptProviderID.claude:
      guard let url = claudeRoot else {
        throw FolderAccessError.securityScopeAccessDenied(
          FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        )
      }
      root = url

    case TranscriptProviderID.codex:
      guard let url = codexRoot else {
        throw FolderAccessError.securityScopeAccessDenied(
          FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        )
      }
      root = url

    default:
      assertionFailure("Unknown transcript provider: \(provider)")
      root = FileManager.default.homeDirectoryForCurrentUser
    }

    // Security scope already started in init, just return URL
    return try body(root)
  }
}
