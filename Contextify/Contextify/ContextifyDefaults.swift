import Foundation

/// Shared UserDefaults selection for Contextify.
///
/// Prefers the legacy `dev.contextify` suite when writable so automation and
/// runbooks can interact with stable keys across distributions. Falls back to
/// `UserDefaults.standard` when the suite is unavailable or not writable.
enum ContextifyDefaults {
  static let shared: UserDefaults = {
    if let suite = UserDefaults(suiteName: "dev.contextify"), probeWriteability(suite) {
      return suite
    }
    return .standard
  }()

  private static func probeWriteability(_ defaults: UserDefaults) -> Bool {
    let probeKey = "dev.contextify.defaults.probe"
    defaults.set(true, forKey: probeKey)
    if defaults.bool(forKey: probeKey) != true {
      defaults.removeObject(forKey: probeKey)
      return false
    }
    defaults.removeObject(forKey: probeKey)
    return true
  }
}

