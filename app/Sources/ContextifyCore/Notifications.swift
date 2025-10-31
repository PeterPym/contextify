import Foundation

// MARK: - Notification Names

extension Notification.Name {
  /// Posted when the project root changes (via HUD, ProjectSwitcher, or startup)
  public static let projectRootDidChange = Notification.Name("projectRootDidChange")

  /// Backward-compatibility alias (deprecated)
  @available(*, deprecated, renamed: "projectRootDidChange")
  public static let ProjectRootDidChange = Notification.Name("projectRootDidChange")
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
}
