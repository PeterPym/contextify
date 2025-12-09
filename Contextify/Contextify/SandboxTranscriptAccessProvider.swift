import Foundation
import ContextifyCore
import OSLog

/// Concrete provider for App Store (sandboxed) builds.
/// Built once during app initialization with security-scoped URLs.
///
/// Note: Security-scoped access is started when bookmarks are resolved
/// and remains active for the lifetime of the URL references.
struct SandboxTranscriptAccessProvider: TranscriptAccessProvider {
  private static let log = Logger(subsystem: "dev.contextify", category: "AccessProvider")

  let claudeRoot: URL?
  let codexRoot: URL?

  init(claudeRoot: URL?, codexRoot: URL?) {
    self.claudeRoot = claudeRoot
    self.codexRoot = codexRoot

    Self.log.info("[PROVIDER-INIT] Creating SandboxTranscriptAccessProvider")
    Self.log.info("[PROVIDER-INIT] Claude root: \(claudeRoot?.path ?? "nil", privacy: .public)")
    Self.log.info("[PROVIDER-INIT] Codex root: \(codexRoot?.path ?? "nil", privacy: .public)")

    // Start security-scoped access for both roots if available
    // This keeps access open for the lifetime of the provider
    if let claude = claudeRoot {
      let success = claude.startAccessingSecurityScopedResource()
      Self.log.info("[PROVIDER-INIT] Claude security scope started: \(success ? "✓" : "✗")")
      if !success {
        Self.log.error("[PROVIDER-INIT] ❌ Claude startAccessingSecurityScopedResource FAILED")
      }
    }

    if let codex = codexRoot {
      let success = codex.startAccessingSecurityScopedResource()
      Self.log.info("[PROVIDER-INIT] Codex security scope started: \(success ? "✓" : "✗")")
      if !success {
        Self.log.error("[PROVIDER-INIT] ❌ Codex startAccessingSecurityScopedResource FAILED")
      }
    }

    Self.log.info("[PROVIDER-INIT] ✅ Provider created (claude=\(claudeRoot != nil), codex=\(codexRoot != nil))")
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
