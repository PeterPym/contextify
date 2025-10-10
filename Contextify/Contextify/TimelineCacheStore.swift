//
//  TimelineCacheStore.swift
//  Contextify
//
//  Thread-safe storage for timeline caches with atomic writes, checksums, and quarantine.
//

import Foundation
import CryptoKit

/// Thread-safe storage for timeline caches (all methods called from actor context)
struct TimelineCacheStore: Sendable {
  private let cacheDirectory: URL
  private let indexURL: URL

  nonisolated init() {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    cacheDirectory = appSupport.appendingPathComponent("Contextify/TimelineCache", isDirectory: true)
    indexURL = cacheDirectory.appendingPathComponent("Index.json")

    // Ensure directories exist
    try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
  }

  // MARK: - Index Management

  func loadIndex() throws -> CacheIndex {
    guard FileManager.default.fileExists(atPath: indexURL.path) else {
      return CacheIndex()
    }
    let data = try Data(contentsOf: indexURL)
    return try JSONDecoder.iso8601ms.decode(CacheIndex.self, from: data)
  }

  func saveIndex(_ index: CacheIndex) async throws {
    let data = try JSONEncoder.prettyISO8601.encode(index)
    try await atomicWrite(data: data, to: indexURL)
  }

  // MARK: - Cache File Operations

  nonisolated func cacheFileURL(for conversationURL: URL) throws -> URL {
    let hash = sha256(string: conversationURL.path)
    return cacheDirectory
      .appendingPathComponent(hash, isDirectory: true)
      .appendingPathComponent("entries.json")
  }

  @MainActor func load(for conversationURL: URL) throws -> TimelineCache? {
    let fileURL = try cacheFileURL(for: conversationURL)

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return nil
    }

    // Verify checksum first
    let checksumURL = fileURL.appendingPathExtension("checksum")
    if FileManager.default.fileExists(atPath: checksumURL.path) {
      let expectedChecksum = try String(contentsOf: checksumURL, encoding: .utf8)
      let actualChecksum = try sha256(url: fileURL)

      if expectedChecksum != actualChecksum {
        // Corruption detected! Quarantine and return nil
        try quarantine(fileURL: fileURL, reason: "checksum-mismatch")
        return nil
      }
    }

    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder.iso8601ms
    return try decoder.decode(TimelineCache.self, from: data)
  }

  func save(_ cache: TimelineCache, for conversationURL: URL) async throws {
    let fileURL = try cacheFileURL(for: conversationURL)

    // Ensure parent directory exists
    let parentDir = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

    let encoder = JSONEncoder.prettyISO8601
    let data = try encoder.encode(cache)

    // Atomic write with checksum
    try await atomicWrite(data: data, to: fileURL)

    let checksum = sha256(data: data)
    let checksumURL = fileURL.appendingPathExtension("checksum")
    try checksum.write(to: checksumURL, atomically: true, encoding: .utf8)
  }

  // MARK: - Corruption Handling

  nonisolated private func quarantine(fileURL: URL, reason: String) throws {
    let quarantineDir = cacheDirectory.appendingPathComponent("Quarantine", isDirectory: true)
    try FileManager.default.createDirectory(at: quarantineDir, withIntermediateDirectories: true)

    let timestamp = ISO8601ms.encode(Date())
    let badFilename = "\(fileURL.deletingPathExtension().lastPathComponent)-\(timestamp)-\(reason).bad.json"
    let quarantineURL = quarantineDir.appendingPathComponent(badFilename)

    try FileManager.default.moveItem(at: fileURL, to: quarantineURL)

    // Also move checksum if exists
    let checksumURL = fileURL.appendingPathExtension("checksum")
    if FileManager.default.fileExists(atPath: checksumURL.path) {
      let checksumQuarantineURL = quarantineURL.appendingPathExtension("checksum")
      try? FileManager.default.moveItem(at: checksumURL, to: checksumQuarantineURL)
    }
  }

  // MARK: - Hashing Utilities

  nonisolated func sha256(data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
  }

  nonisolated func sha256(string: String) -> String {
    sha256(data: Data(string.utf8))
  }

  nonisolated func sha256(url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return sha256(data: data)
  }

  // MARK: - Atomic Write

  nonisolated private func atomicWrite(data: Data, to url: URL) async throws {
    let dir = url.deletingLastPathComponent()
    let tempURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString)")

    // Create temp file and write data
    FileManager.default.createFile(atPath: tempURL.path, contents: nil)
    let fileHandle = try FileHandle(forWritingTo: tempURL)
    defer { try? fileHandle.close() }

    try fileHandle.write(contentsOf: data)
    try fileHandle.synchronize()  // fsync file contents

    // Replace atomically
    _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)

    // fsync the directory for extra safety (ensures directory entry is flushed)
    let dirFd = open(dir.path, O_RDONLY)
    if dirFd >= 0 {
      fsync(dirFd)
      close(dirFd)
    }
  }
}

// MARK: - Encoding/Decoding Extensions

extension JSONEncoder {
  nonisolated static var prettyISO8601: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(ISO8601ms.encode(date))
    }
    return encoder
  }
}

extension JSONDecoder {
  nonisolated static var iso8601ms: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)
      guard let date = ISO8601ms.decode(string) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
      }
      return date
    }
    return decoder
  }
}
