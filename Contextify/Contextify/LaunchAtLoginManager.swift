import ServiceManagement
import OSLog

/// Manages the "launch at login" registration using SMAppService.
///
/// SMAppService.mainApp works for both sandboxed (App Store) and unsandboxed (DMG) builds
/// on macOS 13+. No additional entitlements are required.
///
/// Usage:
///   - Read `isEnabled` / `requiresApproval` for current state
///   - Call `setEnabled(_:)` to register or unregister
///   - Call `refreshStatus()` to re-read system state (e.g., on Settings appear)
@MainActor
@Observable
final class LaunchAtLoginManager {
  static let shared = LaunchAtLoginManager()

  private(set) var status: SMAppService.Status = .notRegistered
  private(set) var lastErrorMessage: String?
  private let log = Logger(subsystem: "dev.contextify", category: "LaunchAtLogin")

  var isEnabled: Bool {
    status == .enabled
  }

  var requiresApproval: Bool {
    status == .requiresApproval
  }

  func refreshStatus() {
    status = SMAppService.mainApp.status
    // Clear stale error when status recovers (e.g., user fixed it in System Settings)
    if status == .enabled || status == .notRegistered {
      lastErrorMessage = nil
    }
    log.debug("Launch at login status: \(String(describing: self.status), privacy: .public)")
  }

  @discardableResult
  func setEnabled(_ enabled: Bool) -> SMAppService.Status {
    lastErrorMessage = nil
    do {
      if enabled {
        try SMAppService.mainApp.register()
        log.info("Registered launch at login")
      } else {
        try SMAppService.mainApp.unregister()
        log.info("Unregistered launch at login")
      }
    } catch {
      lastErrorMessage = error.localizedDescription
      log.error("Failed to \(enabled ? "register" : "unregister", privacy: .public) launch at login: \(error.localizedDescription, privacy: .public)")
    }
    refreshStatus()
    return status
  }

  private init() {
    refreshStatus()
  }
}
