import Foundation

/// Developer-only features and debugging tools
/// Enable via: defaults write dev.contextify.Contextify DeveloperModeEnabled -bool true
@MainActor
@Observable
final class DeveloperMode {
  static let shared = DeveloperMode()

  private let userDefaultsKey = "DeveloperModeEnabled"

  /// Whether developer mode is enabled (shows test UIs, debug tools, etc.)
  var isEnabled: Bool {
    get {
      UserDefaults.standard.bool(forKey: userDefaultsKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
    }
  }

  private init() {}

  /// Terminal command to enable developer mode:
  /// defaults write dev.contextify.Contextify DeveloperModeEnabled -bool true
  ///
  /// Terminal command to disable developer mode:
  /// defaults write dev.contextify.Contextify DeveloperModeEnabled -bool false
  ///
  /// Check current status:
  /// defaults read dev.contextify.Contextify DeveloperModeEnabled
}
