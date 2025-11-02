import Foundation
import Security
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "MachineID")

/// Provides a stable, per-machine identifier using Keychain storage
/// App Store-safe alternative to IOKit hardware UUID
public enum MachineID {
  private static let account = "Contextify.machineID"
  private static let service = "dev.contextify"

  /// Returns the stable machine ID for this Mac
  /// Creates and stores a new one if this is the first run
  public static func current() -> String {
    if let id = readFromKeychain() {
      return id
    }

    // Generate new stable ID
    let id = "ctx-" + UUID().uuidString.lowercased()
    if saveToKeychain(id) {
      log.info("Generated new machine ID (stored in Keychain)")
      return id
    }

    // Fallback if Keychain unavailable (rare)
    log.warning("Keychain unavailable; using hostname-based ID")
    return Host.current().localizedName ?? "unknown-\(UUID().uuidString)"
  }

  /// Reads machine ID from Keychain
  private static func readFromKeychain() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    guard status == errSecSuccess,
          let data = item as? Data,
          let id = String(data: data, encoding: .utf8) else {
      return nil
    }

    return id
  }

  /// Saves machine ID to Keychain
  @discardableResult
  private static func saveToKeychain(_ id: String) -> Bool {
    guard let data = id.data(using: .utf8) else { return false }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]

    // Try to add; if exists, update instead
    var status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updateQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
      ]
      let updateAttrs: [String: Any] = [kSecValueData as String: data]
      status = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
    }

    return status == errSecSuccess
  }
}
