import Foundation

/// Manages excluded projects (projects hidden from discovery)
public actor ProjectExclusionManager {
  private let defaults: UserDefaults
  private let excludedProjectsKey = "contextify.excludedProjects"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  // MARK: - Public API

  /// Gets the list of excluded project paths
  public func getExcludedProjects() -> Set<String> {
    let array = defaults.stringArray(forKey: excludedProjectsKey) ?? []
    return Set(array)
  }

  /// Excludes a project from discovery
  /// - Parameter projectPath: Full path to the project
  public func excludeProject(_ projectPath: String) {
    var excluded = getExcludedProjects()
    excluded.insert(projectPath)
    save(excluded)
  }

  /// Includes a previously excluded project
  /// - Parameter projectPath: Full path to the project
  public func includeProject(_ projectPath: String) {
    var excluded = getExcludedProjects()
    excluded.remove(projectPath)
    save(excluded)
  }

  /// Checks if a project is excluded
  /// - Parameter projectPath: Full path to the project
  /// - Returns: True if the project is excluded
  public func isExcluded(_ projectPath: String) -> Bool {
    getExcludedProjects().contains(projectPath)
  }

  /// Clears all exclusions
  public func clearAll() {
    defaults.removeObject(forKey: excludedProjectsKey)
  }

  // MARK: - Private Helpers

  private func save(_ excluded: Set<String>) {
    let array = Array(excluded).sorted()
    defaults.set(array, forKey: excludedProjectsKey)
  }
}
