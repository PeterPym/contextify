import Foundation

/// Typed event for active session changes
/// P2: Published via NotificationCenter (no Combine dependency)
public struct ActiveSessionDidChangeEvent: Sendable {
  public let projectPath: String
  public let sessionId: String
  public let provider: String
  public let mode: String       // "automatic" | "manual"
  public let reason: String     // matches SwitchReason.rawValue
  public let timestamp: Date

  public init(
    projectPath: String,
    sessionId: String,
    provider: String,
    mode: String,
    reason: String,
    timestamp: Date
  ) {
    self.projectPath = projectPath
    self.sessionId = sessionId
    self.provider = provider
    self.mode = mode
    self.reason = reason
    self.timestamp = timestamp
  }
}

extension Notification.Name {
  /// Posted when the active session changes
  /// R4: The event is delivered as the Notification `object` (cast to `ActiveSessionDidChangeEvent`)
  public static let activeSessionDidChange = Notification.Name("ActiveSessionDidChange")
}

// R4: Convenience accessor for type-safe event access
extension Notification {
  /// Safely extract the ActiveSessionDidChangeEvent from the notification object
  public var activeSessionEvent: ActiveSessionDidChangeEvent? {
    object as? ActiveSessionDidChangeEvent
  }
}
