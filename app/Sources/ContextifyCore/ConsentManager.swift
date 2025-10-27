import Foundation

/// Manager for user consent to multi-project mode
public final class ConsentManager: @unchecked Sendable {
  public nonisolated(unsafe) static let shared = ConsentManager()

  private let preferenceKey = "dev.contextify.multiProjectMode.enabled"
  private let defaults: UserDefaults

  private init() {
    // Use app group defaults if available, fallback to standard
    if let suite = UserDefaults(suiteName: "dev.contextify") {
      self.defaults = suite
    } else {
      self.defaults = .standard
    }
  }

  /// Check if multi-project mode is enabled
  /// Default to true (auto opt-in) if not explicitly set
  public var isMultiProjectModeEnabled: Bool {
    get {
      // Auto opt-in: return true if never set, otherwise use stored value
      if !hasConsentDecision {
        return true
      }
      return defaults.bool(forKey: preferenceKey)
    }
    set {
      defaults.set(newValue, forKey: preferenceKey)
    }
  }

  /// Check if user has made a consent decision (true if key exists)
  public var hasConsentDecision: Bool {
    defaults.object(forKey: preferenceKey) != nil
  }

  /// Enable multi-project mode
  public func enableMultiProjectMode() {
    isMultiProjectModeEnabled = true
  }

  /// Disable multi-project mode
  public func disableMultiProjectMode() {
    isMultiProjectModeEnabled = false
  }
}
