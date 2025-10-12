//
//  SidecarMetadataStore.swift
//  Contextify
//
//  Temporary stub for metadata storage during SQL migration
//  TODO: Migrate to SQL backend (see sql-integration-plan-v2.md Part 7)
//

import Foundation
import CryptoKit

/// Temporary in-memory metadata store (no persistence)
/// This stub allows the inventory view to continue working during SQL cutover
actor SidecarMetadataStore {
  private var cache: [URL: TranscriptMetadata] = [:]

  func load(for url: URL) -> TranscriptMetadata? {
    return cache[url]
  }

  func save(_ metadata: TranscriptMetadata, for url: URL) {
    cache[url] = metadata
  }

  func isFresh(
    _ metadata: TranscriptMetadata,
    for url: URL,
    promptVersion: Int,
    generatorVersion: Int
  ) -> Bool {
    // Check if versions match
    guard metadata.promptVersion == promptVersion,
          metadata.generatorVersion == generatorVersion else {
      return false
    }

    // Check if file has been modified since metadata was generated
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let modDate = attrs[.modificationDate] as? Date else {
      return false
    }

    let metaDate = metadata.generatedAt
    return modDate <= metaDate
  }

  func sha256(url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }

  func flushHeuristicMetadata(for url: URL, exchanges: [Exchange]) {
    // Stub: generate simple heuristic metadata
    let metadata = HeuristicMetadata.generate(exchanges: exchanges)
    cache[url] = metadata
  }

  // Batch flush for inventory view
  func flushHeuristicMetadata(for sessions: [TranscriptSession]) -> Int {
    var flushed = 0
    for session in sessions {
      // Skip if already has metadata
      if cache[session.fileURL] != nil { continue }

      // Quick parse to get exchanges
      let parser = TranscriptParser()
      guard let exchanges = try? parser.parseExchanges(url: session.fileURL) else { continue }

      // Generate and cache heuristic metadata
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      cache[session.fileURL] = metadata
      flushed += 1
    }
    return flushed
  }
}
