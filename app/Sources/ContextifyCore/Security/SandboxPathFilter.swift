import Foundation

/// Centralized helper for filtering sandbox container paths (e.g. ~/Library/Containers/.../Data).
public enum SandboxPathFilter {
  /// Returns true when the provided path resolves inside the app's sandbox container.
  public static func isSandboxContainerPath(_ path: String) -> Bool {
    guard Sandbox.isSandboxed else { return false }
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
