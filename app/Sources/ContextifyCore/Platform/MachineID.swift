import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "MachineID")

/// Provides a stable, per-machine identifier using Application Support storage
/// App Store-safe, no user prompts required
public enum MachineID {
  private static let filename = "machine-id.txt"

  /// Path to machine ID file in Application Support
  private static var machineIDFile: URL? {
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      return nil
    }

    let contextifyDir = appSupport.appendingPathComponent("Contextify", isDirectory: true)

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
      // Try to read from file
      if let id = readFromFile() {
        return id
      }

      // Generate new stable ID
      let id = "ctx-" + UUID().uuidString.lowercased()
      if saveToFile(id) {
        log.info("Generated new machine ID (stored in Application Support)")
        return id
      }

      // Fallback if file system unavailable (extremely rare)
      log.warning("Application Support unavailable; using hostname-based ID")
      return Host.current().localizedName ?? "unknown-\(UUID().uuidString)"
    }()
  }

  /// Returns the stable machine ID for this Mac
  /// Creates and stores a new one if this is the first run
  public static func current() -> String {
    Cache.machineID
  }

  /// Reads machine ID from Application Support
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

  /// Saves machine ID to Application Support
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
}
