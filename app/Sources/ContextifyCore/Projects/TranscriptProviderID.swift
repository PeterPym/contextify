import Foundation

/// Canonical identifiers for transcript providers.
public enum TranscriptProviderID {
  public static let claude = "claude.code"
  public static let codex  = "codex.cli"

  /// Derives provider ID from transcript file URL path.
  /// Claude transcripts live in ~/.claude/projects/, Codex in ~/.codex/sessions/
  ///
  /// - Parameter url: The transcript file URL
  /// - Returns: The provider ID string, or nil if path doesn't match known patterns
  public static func fromTranscriptURL(_ url: URL) -> String? {
    let path = url.path
    if path.contains("/.claude/") {
      return claude
    }
    if path.contains("/.codex/") {
      return codex
    }
    return nil
  }
}
