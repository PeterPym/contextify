import Foundation
import Combine

/// Typed event for active session changes
/// P2-3: Published via NotificationCenter for broad compatibility
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
  /// UserInfo contains ActiveSessionDidChangeEvent as the object
  public static let activeSessionDidChange = Notification.Name("ActiveSessionDidChange")
}
