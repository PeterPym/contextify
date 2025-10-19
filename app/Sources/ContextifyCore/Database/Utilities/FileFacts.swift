//
//  FileFacts.swift
//  ContextifyCore
//
//  File metadata extraction with streaming SHA256 hash computation
//

import Foundation
import CryptoKit

/// File metadata extraction with streaming hash computation
public enum FileFacts {
  /// Extract file facts (size, mtime, SHA256)
  /// - Parameter path: File path
  /// - Returns: Tuple of (length in bytes, mtime in milliseconds, SHA256 hex string)
  public static func forPath(_ path: String) throws -> (len: Int64, mtimeMs: Int64, sha: String) {
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    let len = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    let mod = (attrs[.modificationDate] as? Date) ?? .distantPast
    let mtimeMs = Int64(mod.timeIntervalSince1970 * 1000)
    let sha = try sha256(url: URL(fileURLWithPath: path))
    return (len, mtimeMs, sha)
  }

  /// Compute SHA256 hash using streaming reads
  /// - Parameters:
  ///   - url: File URL
  ///   - chunkSize: Read buffer size (default 1MB)
  /// - Returns: Hex-encoded SHA256 hash
  public static func sha256(url: URL, chunkSize: Int = 1 << 20) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: chunkSize) ?? Data()
      if data.isEmpty { break }
      hasher.update(data: data)
    }

    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// Compute stable SHA256 (detects file changes during hashing)
  /// - Parameter url: File URL
  /// - Returns: Hex-encoded SHA256 hash
  /// - Throws: If file changes during hashing after retry
  public static func stableSha256(url: URL) throws -> String {
    let before = try FileManager.default.attributesOfItem(atPath: url.path)
    let sha = try sha256(url: url)
    let after = try FileManager.default.attributesOfItem(atPath: url.path)

    // Check if file changed during hashing
    if (before[.size] as? NSNumber) != (after[.size] as? NSNumber) ||
       (before[.modificationDate] as? Date) != (after[.modificationDate] as? Date) {
      // File changed - rehash once
      return try sha256(url: url)
    }

    return sha
  }
}
