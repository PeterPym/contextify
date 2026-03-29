import Foundation

#if canImport(OSLog)
import OSLog
#endif

private let log = Logger(subsystem: "dev.contextify", category: "MachineID")

/// Provides a stable, per-machine identifier.
///
/// - macOS: Stores a generated `ctx-...` UUID in Application Support.
/// - Linux: Reads `/etc/machine-id`, falls back to hostname.
public enum MachineID {
  private static let filename = "machine-id.txt"

  /// Path to machine ID file in a platform-appropriate directory
  private static var machineIDFile: URL? {
    #if os(macOS)
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      return nil
    }
    let contextifyDir = appSupport.appendingPathComponent("Contextify", isDirectory: true)
    #else
    let xdgData = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
      ?? (NSHomeDirectory() + "/.local/share")
    let contextifyDir = URL(fileURLWithPath: xdgData)
      .appendingPathComponent("contextify", isDirectory: true)
    #endif

    // Ensure directory exists
    try? FileManager.default.createDirectory(
      at: contextifyDir,
      withIntermediateDirectories: true,
      attributes: nil
    )

    return contextifyDir.appendingPathComponent(filename)
  }

  /// Thread-safe cached machine ID
  /// static let initializer is lazy and guaranteed once-only with no races
  private enum Cache {
    static let machineID: String = {
      #if !os(macOS)
      // Linux: prefer /etc/machine-id (systemd standard)
      if let sysId = try? String(contentsOfFile: "/etc/machine-id", encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
         !sysId.isEmpty {
        return sysId
      }
      #endif

      // Try to read from persisted file
      if let id = readFromFile() {
        return id
      }

      // Generate new stable ID
      let id = "ctx-" + UUID().uuidString.lowercased()
      if saveToFile(id) {
        log.info("Generated new machine ID (stored in persistent storage)")
        return id
      }

      // Fallback if file system unavailable (extremely rare)
      log.warning("Persistent storage unavailable; using hostname-based ID")
      return platformHostname() ?? "unknown-\(UUID().uuidString)"
    }()
  }

  /// Returns the stable machine ID for this device.
  /// Creates and stores a new one if this is the first run.
  public static func current() -> String {
    Cache.machineID
  }

  /// Returns the normalized cloud device ID.
  ///
  /// Older cloud sync builds stored raw hardware identifiers in cloud.json.
  /// Newer builds use the persisted app-level machine ID (`ctx-...`) so the
  /// app, CLI, and other local identity surfaces stay aligned.
  public static func normalizedCloudDeviceID(_ storedID: String?) -> String {
    guard let storedID, !storedID.isEmpty else {
      return current()
    }
    #if os(macOS)
    if storedID.hasPrefix("ctx-") {
      return storedID
    }
    log.info("Migrating legacy cloud device ID to app-level machine ID")
    return current()
    #else
    return storedID
    #endif
  }

  /// Reads machine ID from persistent storage
  private static func readFromFile() -> String? {
    guard let fileURL = machineIDFile else { return nil }

    do {
      let id = try String(contentsOf: fileURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return id.isEmpty ? nil : id
    } catch {
      // File doesn't exist yet (first run) or read error
      return nil
    }
  }

  /// Saves machine ID to persistent storage
  @discardableResult
  private static func saveToFile(_ id: String) -> Bool {
    guard let fileURL = machineIDFile else { return false }

    do {
      try id.write(to: fileURL, atomically: true, encoding: .utf8)
      return true
    } catch {
      log.error("Failed to save machine ID: \(error.localizedDescription)")
      return false
    }
  }

  /// Platform-appropriate hostname
  private static func platformHostname() -> String? {
    #if os(macOS)
    return Host.current().localizedName
    #else
    return ProcessInfo.processInfo.hostName
    #endif
  }
}

/// Provides the human-readable device name.
/// Used alongside MachineID for device provenance on transcript entries.
public enum DeviceName {
  private enum Cache {
    static let name: String = {
      #if os(macOS)
      Host.current().localizedName ?? ProcessInfo.processInfo.hostName
      #else
      ProcessInfo.processInfo.hostName
      #endif
    }()
  }

  /// Returns the human-readable device name (e.g. "Rob's MacBook Pro").
  /// Cached on first access for thread safety and performance.
  public static func current() -> String {
    Cache.name
  }
}
