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
  nonisolated func load(for url: URL) throws -> TranscriptMetadata? {
    let sidecarPath = sidecarURL(for: url)

    guard FileManager.default.fileExists(atPath: sidecarPath.path) else {
      return nil
    }

    let data = try Data(contentsOf: sidecarPath)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)
      guard let date = ISO8601ms.decode(string) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
      }
      return date
    }
    return try decoder.decode(TranscriptMetadata.self, from: data)
  }

  /// Saves metadata to sidecar file atomically
  nonisolated func save(_ metadata: TranscriptMetadata, for url: URL) async throws {
    let sidecarPath = sidecarURL(for: url)

    // Ensure parent directory exists
    let parentDir = sidecarPath.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(ISO8601ms.encode(date))
    }
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data = try encoder.encode(metadata)
    // Write directly with .atomic option - no need for manual temp file
    try data.write(to: sidecarPath, options: .atomic)
  }

  /// Checks if cached metadata is still fresh
  nonisolated func isFresh(
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

  /// Computes SHA256 hash of transcript file using streaming to avoid memory spikes
  nonisolated func sha256(url: URL) throws -> String {
    let bufferSize = 64 * 1024 // 64 KB chunks
    guard let inputStream = InputStream(url: url) else {
      throw NSError(domain: "SidecarMetadataStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open input stream"])
    }

    inputStream.open()
    defer { inputStream.close() }

    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while inputStream.hasBytesAvailable {
      let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
      if bytesRead > 0 {
        hasher.update(data: Data(buffer[0..<bytesRead]))
      } else if bytesRead < 0 {
        throw inputStream.streamError ?? NSError(domain: "SidecarMetadataStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Stream read error"])
      } else {
        break
      }
    }

    let digest = hasher.finalize()
    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
  }

  /// Deletes the sidecar metadata file for a transcript
  nonisolated func delete(for url: URL) throws {
    let sidecarPath = sidecarURL(for: url)
    let fm = FileManager.default

    guard fm.fileExists(atPath: sidecarPath.path) else {
      return // Already deleted
    }

    try fm.removeItem(at: sidecarPath)
  }

  /// Flushes all heuristic-generated metadata (Developer Chat, Brief Session)
  /// Returns count of flushed files
  nonisolated func flushHeuristicMetadata(for sessions: [TranscriptSession]) -> Int {
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
