import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// MARK: - Cross-Platform Crypto

/// Cross-platform SHA256 utilities.
///
/// ## Platform Implementation
/// - Darwin: Uses `CryptoKit.SHA256`
/// - Linux: Uses `Crypto.SHA256` from swift-crypto package
///
/// The API is intentionally simple to minimize platform-specific code at call sites.
public enum CrossPlatformCrypto {

  /// Compute SHA256 hash of data and return as lowercase hex string.
  ///
  /// - Parameter data: The data to hash.
  /// - Returns: A 64-character lowercase hexadecimal string representing the SHA256 hash.
  public static func sha256(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  /// Compute SHA256 hash of a string (UTF-8 encoded) and return as lowercase hex string.
  ///
  /// - Parameter string: The string to hash.
  /// - Returns: A 64-character lowercase hexadecimal string representing the SHA256 hash.
  public static func sha256(_ string: String) -> String {
    sha256(Data(string.utf8))
  }

  /// Compute SHA256 hash and return the first N hex characters (truncated hash).
  ///
  /// Useful for logging or display purposes where full hash is not needed.
  ///
  /// - Parameters:
  ///   - data: The data to hash.
  ///   - length: Number of hex characters to return (clamped to 0...64).
  /// - Returns: A truncated lowercase hexadecimal string.
  public static func sha256Prefix(_ data: Data, length: Int = 12) -> String {
    let hash = sha256(data)
    // Clamp length to valid range [0, 64] to handle negative or excessive values
    let clampedLength = max(0, min(length, 64))
    return String(hash.prefix(clampedLength))
  }

  /// Compute SHA256 hash of string and return the first N hex characters.
  ///
  /// - Parameters:
  ///   - string: The string to hash.
  ///   - length: Number of hex characters to return (max 64).
  /// - Returns: A truncated lowercase hexadecimal string.
  public static func sha256Prefix(_ string: String, length: Int = 12) -> String {
    sha256Prefix(Data(string.utf8), length: length)
  }
}
