import Foundation

/// Centralized configuration with UserDefaults-backed feature flags
public final class ContextifyConfig: @unchecked Sendable {
  public static let shared = ContextifyConfig()

  private let defaults = UserDefaults.standard

  private enum Key {
    static let preflightEnabled = "contextify.preflight.enabled"
    static let preflightCaching = "contextify.preflight.caching"
    static let schedulerEnabled = "contextify.scheduler.enabled"
    static let maxConcurrentHoovers = "contextify.scheduler.maxConcurrency"
    static let gitHighPriority = "contextify.priority.gitHigh"
    static let bulkLowPriority = "contextify.priority.bulkLow"
  }

  // Fix #1: Preflight
  public var preflightValidationEnabled: Bool {
    get { defaults.object(forKey: Key.preflightEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.preflightEnabled) }
  }

  public var preflightCachingEnabled: Bool {
    get { defaults.object(forKey: Key.preflightCaching) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.preflightCaching) }
  }

  // Fix #2: Scheduler
  public var hooverSchedulerEnabled: Bool {
    get { defaults.object(forKey: Key.schedulerEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.schedulerEnabled) }
  }

  public var maxConcurrentHoovers: Int {
    get { defaults.object(forKey: Key.maxConcurrentHoovers) as? Int ?? 6 }
    set { defaults.set(newValue, forKey: Key.maxConcurrentHoovers) }
  }

  // Fix #3: Priorities
  public var gitHighPriorityEnabled: Bool {
    get { defaults.object(forKey: Key.gitHighPriority) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.gitHighPriority) }
  }

  public var bulkLowPriorityEnabled: Bool {
    get { defaults.object(forKey: Key.bulkLowPriority) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.bulkLowPriority) }
  }

  // Targets for validation
  public let gitLatencyTargetMs: Int = 200
  public let hooverLatencyTargetMs: Int = 5000

  private init() {}

  /// Reset to defaults (for testing)
  public func resetToDefaults() {
    defaults.removeObject(forKey: Key.preflightEnabled)
    defaults.removeObject(forKey: Key.preflightCaching)
    defaults.removeObject(forKey: Key.schedulerEnabled)
    defaults.removeObject(forKey: Key.maxConcurrentHoovers)
    defaults.removeObject(forKey: Key.gitHighPriority)
    defaults.removeObject(forKey: Key.bulkLowPriority)
  }
}
