import Foundation
import CryptoKit

/// Manages sidecar JSON metadata storage with atomic writes and cache invalidation
struct SidecarMetadataStore: Sendable {
  // MARK: - Public API

  /// Returns the sidecar URL for a given transcript URL
  nonisolated func sidecarURL(for transcriptURL: URL) -> URL {
    transcriptURL.deletingPathExtension().appendingPathExtension("metadata.json")
  }

  /// Loads metadata from sidecar file if it exists
  func load(for url: URL) throws -> TranscriptMetadata? {
    let sidecarPath = sidecarURL(for: url)

    guard FileManager.default.fileExists(atPath: sidecarPath.path) else {
      return nil
    }

    let data = try Data(contentsOf: sidecarPath)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(TranscriptMetadata.self, from: data)
  }

  /// Saves metadata to sidecar file atomically
  func save(_ metadata: TranscriptMetadata, for url: URL) async throws {
    let sidecarPath = sidecarURL(for: url)
    let tmpPath = sidecarPath
      .deletingLastPathComponent()
      .appendingPathComponent(".\(UUID().uuidString).tmp")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data = try encoder.encode(metadata)
    try data.write(to: tmpPath, options: .atomic)

    // Atomic replace
    let fm = FileManager.default
    if fm.fileExists(atPath: sidecarPath.path) {
      _ = try? fm.replaceItemAt(
        sidecarPath,
        withItemAt: tmpPath,
        backupItemName: nil,
        options: .usingNewMetadataOnly
      )
    } else {
      try fm.moveItem(at: tmpPath, to: sidecarPath)
    }
  }

  /// Checks if cached metadata is still fresh
  func isFresh(
    _ metadata: TranscriptMetadata,
    for url: URL,
    promptVersion: Int,
    generatorVersion: Int
  ) -> Bool {
    guard let currentHash = try? sha256(url: url) else {
      return false
    }

    return metadata.transcriptSHA256 == currentHash
      && metadata.promptVersion == promptVersion
      && metadata.generatorVersion == generatorVersion
  }

  /// Computes SHA256 hash of transcript file
  func sha256(url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let digest = SHA256.hash(data: data)
    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
  }

  /// Deletes the sidecar metadata file for a transcript
  func delete(for url: URL) throws {
    let sidecarPath = sidecarURL(for: url)
    let fm = FileManager.default

    guard fm.fileExists(atPath: sidecarPath.path) else {
      return // Already deleted
    }

    try fm.removeItem(at: sidecarPath)
  }

  /// Flushes all heuristic-generated metadata (Developer Chat, Brief Session)
  /// Returns count of flushed files
  func flushHeuristicMetadata(for sessions: [TranscriptSession]) -> Int {
    var flushedCount = 0

    for session in sessions {
      guard let metadata = try? load(for: session.fileURL) else {
        continue
      }

      // Check if it's heuristic metadata
      let isHeuristic = metadata.model == "heuristic" ||
                        metadata.title == "Developer Chat" ||
                        metadata.title == "Brief Session" ||
                        metadata.strategy.contains("heuristic")

      if isHeuristic {
        try? delete(for: session.fileURL)
        flushedCount += 1
      }
    }

    return flushedCount
  }
}
