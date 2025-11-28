import Foundation

/// Centralized helper for filtering sandbox container paths (e.g. ~/Library/Containers/.../Data).
public enum SandboxPathFilter {
  /// Returns true when the provided path resolves inside ANY app's sandbox container.
  /// Note: This check works regardless of whether the current app is sandboxed,
  /// which is important because the ContextifyCore package doesn't see APPSTORE_BUILD flag.
  public static func isSandboxContainerPath(_ path: String) -> Bool {
    // Standardize path to remove .. components
    let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
    guard normalized.contains("/Library/Containers/") else { return false }
    let components = normalized.split(separator: "/")
    guard let containersIdx = components.firstIndex(of: "Containers") else { return false }
    // Expect: .../Containers/<bundle-id>/Data/...
    let dataIdx = containersIdx + 2
    guard components.indices.contains(dataIdx) else { return false }
    return components[dataIdx] == "Data"
  }

  /// Helper that returns nil when the path should be filtered.
  public static func sanitizedPath(_ path: String?) -> String? {
    guard let path, !isSandboxContainerPath(path) else { return nil }
    return path
  }
}
