import Foundation

extension Notification.Name {
  /// Posted when project discovery completes
  /// Object contains [DiscoveredProject] array
  static let projectsDiscoveryComplete = Notification.Name("contextify.projectsDiscoveryComplete")
}
