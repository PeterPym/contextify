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
@Observable
final class LaunchAtLoginManager {
  static let shared = LaunchAtLoginManager()

  private(set) var status: SMAppService.Status = .notRegistered
  private let log = Logger(subsystem: "dev.contextify", category: "LaunchAtLogin")

  var isEnabled: Bool {
    status == .enabled
  }

  var requiresApproval: Bool {
    status == .requiresApproval
  }

  func refreshStatus() {
    status = SMAppService.mainApp.status
    log.debug("Launch at login status: \(String(describing: self.status), privacy: .public)")
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
        log.info("Registered launch at login")
      } else {
        try SMAppService.mainApp.unregister()
        log.info("Unregistered launch at login")
      }
    } catch {
      log.error("Failed to \(enabled ? "register" : "unregister", privacy: .public) launch at login: \(error.localizedDescription, privacy: .public)")
    }
    refreshStatus()
  }

  private init() {
    refreshStatus()
  }
}
