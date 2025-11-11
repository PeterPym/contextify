import Foundation

extension Notification.Name {
  /// Posted when project discovery completes
  /// Object contains [DiscoveredProject] array
  static let projectsDiscoveryComplete = Notification.Name("contextify.projectsDiscoveryComplete")

  /// Posted when ALL project transcript ingestion (hoovering) completes
  /// This fires after all hoover operations finish, unlike projectsDiscoveryComplete which fires early
  static let projectsIngestionComplete = Notification.Name("contextify.projectsIngestionComplete")
}
