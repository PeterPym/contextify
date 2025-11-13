import Foundation
import ContextifyCore

/// Concrete provider for App Store (sandboxed) builds.
/// Built once during app initialization with security-scoped URLs.
struct SandboxTranscriptAccessProvider: TranscriptAccessProvider {
  let claudeRoot: URL?
  let codexRoot: URL?

  init(claudeRoot: URL?, codexRoot: URL?) {
    self.claudeRoot = claudeRoot
    self.codexRoot = codexRoot
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

    guard root.startAccessingSecurityScopedResource() else {
      throw FolderAccessError.securityScopeAccessDenied(root)
    }
    defer { root.stopAccessingSecurityScopedResource() }

    return try body(root)
  }
}
