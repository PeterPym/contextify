import Foundation
import OSLog

/// Pre-warms expensive framework initialization off the main thread
/// to avoid first-use stalls during UI-critical operations.
///
/// This utility touches:
/// - Unified logging (OSLog/Logger) - triggers XPC to logd, trace buffers
/// - Security.framework (Keychain) - triggers dylib load, IPC setup
/// - CoreFoundation hostname lookup - triggers sysctl/configd IPC
/// - Bundle info dictionary - triggers plist parsing
///
/// Usage: Call `StartupWarmup.run()` early in app lifecycle, before UI appears.
public enum StartupWarmup {

  /// Runs warmup tasks on a background queue to avoid blocking main thread
  /// during first-use framework initialization.
  ///
  /// Should be called once during app startup, before any UI-critical code paths.
  public static func run() {
    // NOTE: Using Task.detached because this warmup should complete independently
    // on app launch. Fire-and-forget initialization with no UI dependency.
    Task.detached(priority: .userInitiated) {
      // 1. Warm unified logging (triggers _os_trace_init_slow, XPC bundle parsing)
      let warmupLogger = Logger(subsystem: "dev.contextify", category: "Warmup")
      warmupLogger.debug("Warmup: unified logging initialized")

      // 2. Warm Security.framework via Keychain read (triggers SecItemCopyMatching setup)
      let _ = MachineID.current()
      warmupLogger.debug("Warmup: Security framework initialized")

      // 3. Warm CoreFoundation hostname lookup (triggers sysctl/configd IPC)
      let _ = Host.current().localizedName
      warmupLogger.debug("Warmup: CoreFoundation hostname lookup initialized")

      // 4. Warm Bundle info dictionary access (triggers plist parsing)
      let _ = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      warmupLogger.debug("Warmup: Bundle info dictionary initialized")

      warmupLogger.info("Startup warmup complete - all expensive frameworks pre-initialized")
    }
  }
}
