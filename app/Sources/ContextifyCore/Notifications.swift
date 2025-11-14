import Foundation

// MARK: - Notification Names

extension Notification.Name {
  /// Posted when the project root changes (via HUD, ProjectSwitcher, or startup)
  public static let projectRootDidChange = Notification.Name("projectRootDidChange")

  /// Backward-compatibility alias (deprecated)
  @available(*, deprecated, renamed: "projectRootDidChange")
  public static let ProjectRootDidChange = Notification.Name("projectRootDidChange")

  /// Posted when ALL project transcript ingestion (hoovering) completes
  /// This fires after all hoover operations finish, unlike projectsDiscoveryComplete which fires early
  /// SUBSCRIBERS: ProjectSwitcherState uses this to refresh tabs after welcome modal ingestion
  /// (handles race where watchers already exist so .discovered events aren't emitted)
  public static let projectsIngestionComplete = Notification.Name("contextify.projectsIngestionComplete")

  /// Posted when a project's primer target has been reached (fast-path entries available)
  /// Object: projectId (String). userInfo["entries"]: Int entry count snapshot.
  public static let timelinePrimerReady = Notification.Name("contextify.timelinePrimerReady")

  /// Posted during transcript hoovering to report incremental progress
  /// Emitted after first 3 transcripts and every 10 thereafter for real-time timeline updates
  /// userInfo contains: "transcriptCount" (Int), "totalTranscripts" (Int), "projectId" (String)
  public static let transcriptHooveringProgress = Notification.Name("contextify.transcriptHooveringProgress")
}

// MARK: - Notification UserInfo Keys

/// UserInfo keys for .projectRootDidChange notification
public enum ProjectRootDidChangeKeys {
  /// URL of the project root (canonical path)
  public static let url = "url"
  /// String path (absolute, canonical) of the project root
  public static let path = "path"
  /// Source of the change (e.g., "switchToProject", "setProjectRoot", "startup")
  public static let source = "source"
  /// Nonce for self-suppression in notification observers (replaces time-window approach)
  public static let nonce = "nonce"
}
