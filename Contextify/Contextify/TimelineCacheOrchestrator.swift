//
//  TimelineCacheOrchestrator.swift
//  Contextify
//
//  Production-grade actor for coordinating timeline cache operations.
//

import Foundation
import OSLog

/// Actor-based orchestrator for timeline cache operations with concurrency safety
actor TimelineCacheOrchestrator {
  static let shared = TimelineCacheOrchestrator()

  private let log = Logger(subsystem: "dev.contextify.timeline", category: "Cache")
  private let store: TimelineCacheStore

  private var cache: TimelineCache?
  private var conversationURL: URL?
  private var dirty = false
  private var lastFlush = Date.distantPast
  private let flushDebounceInterval: UInt64 = 2_000_000_000  // 2 seconds in nanoseconds
  private var pendingFlush: Task<Void, Never>?

  // Generator signature components
  private let modelId = "foundation-small"
  private let modelVersion = "2025.10"
  private let promptVersion = "3.2.1"
  private let promptParams: [String: String] = [:]  // For future use

  private init() {
    self.store = TimelineCacheStore()
  }

  // MARK: - Public API

  /// Load cache for a conversation
  func loadCache(for url: URL) async throws {
    guard conversationURL != url else { return }

    // Flush any pending changes from previous conversation
    if dirty {
      try await persistCache()
    }

    conversationURL = url
    cache = try await store.load(for: url)

    if cache == nil {
      // Create new empty cache
      cache = TimelineCache(
        conversationPath: url.path,
        generatedAt: Date(),
        metadata: CacheMetadata()
      )
      log.info("Created new cache for \(url.lastPathComponent, privacy: .public)")
    } else {
      log.info("Loaded cache with \(self.cache?.entries.count ?? 0) entries for \(url.lastPathComponent, privacy: .public)")
    }
  }

  /// Get cached entry or generate new one
  func getCachedEntry(
    messageUUID: String,
    messageJSON: [String: Any],
    contextWindow: [String],  // UUIDs of context messages
    text: String,
    kind: TimelineEntryKind
  ) async throws -> RenderedTimelineEntry {

    guard var cache = cache else {
      throw CacheError.notLoaded
    }

    // Compute hashes
    let contentHash = computeContentHash(messageJSON: messageJSON)
    let windowHash = computeWindowHash(contextUUIDs: contextWindow)
    let sig = generatorSignature()

    // Check cache
    if let entry = cache.entries[messageUUID],
       entry.contentHash == contentHash,
       entry.windowHash == windowHash,
       entry.generatorSignature == sig {

      // Cache HIT
      cache.metadata.cacheHits += 1
      self.cache = cache
      markDirty()

      log.info("Cache HIT for \(messageUUID, privacy: .public)")
      let summary = entry.render()
      let disposition = entry.disposition
      let isCompletion = entry.isCompletion
      let isDirective = entry.isDirective
      let requestId = entry.requestId
      let duration = entry.duration

      return RenderedTimelineEntry(
        summary: summary,
        disposition: disposition,
        isCompletion: isCompletion,
        isDirective: isDirective,
        requestId: requestId,
        duration: duration
      )
    }

    // Cache MISS - need to call LLM
    cache.metadata.cacheMisses += 1

    if cache.entries[messageUUID] != nil {
      cache.metadata.regenerations += 1
      log.info("Cache REGENERATE for \(messageUUID, privacy: .public) (content/window/signature changed)")
    } else {
      log.info("Cache MISS for \(messageUUID, privacy: .public) (new message)")
    }

    // Call LLM (this is the slow path)
    let llmResult = try await FoundationLLM.shared.summarizeTimelineWithForms(
      kind: kind,
      text: text,
      contextWindow: contextWindow
    )

    // Create new cache entry
    let entry = CachedTimelineEntry(
      contentHash: contentHash,
      windowHash: windowHash,
      generatorSignature: sig,
      disposition: llmResult.disposition,
      presentForm: llmResult.presentForm,
      pastForm: llmResult.pastForm,
      selectedForm: llmResult.disposition == .completion ? .pastSimple : .presentContinuous,
      verbLemma: llmResult.verbLemma,
      generatedAt: Date()
    )

    cache.entries[messageUUID] = entry
    cache.metadata.totalEntries = cache.entries.count
    self.cache = cache
    markDirty()

    let summary = entry.render()
    let disposition = entry.disposition
    let isCompletion = entry.isCompletion
    let isDirective = entry.isDirective

    return RenderedTimelineEntry(
      summary: summary,
      disposition: disposition,
      isCompletion: isCompletion,
      isDirective: isDirective,
      requestId: nil,
      duration: nil
    )
  }

  /// Flip tense from present → past (no regex, just field toggle!)
  func flipTenseToPast(messageUUID: String) async throws {
    guard var cache = cache else { return }
    guard var entry = cache.entries[messageUUID] else { return }
    guard entry.selectedForm == .presentContinuous else { return }

    entry.selectedForm = .pastSimple
    cache.entries[messageUUID] = entry
    self.cache = cache
    markDirty()

    log.info("Flipped tense to past for \(messageUUID, privacy: .public)")
  }

  /// Update entry with user edit
  func setUserEdit(messageUUID: String, text: String) async throws {
    guard var cache = cache else { return }
    guard var entry = cache.entries[messageUUID] else { return }

    entry.userEdited = true
    entry.userText = text
    entry.editedAt = Date()

    cache.entries[messageUUID] = entry
    self.cache = cache
    markDirty()

    log.info("User edited entry \(messageUUID, privacy: .public)")
  }

  /// Persist cache to disk
  func persistCache() async throws {
    guard dirty, let cache = cache, let url = conversationURL else { return }

    let start = Date()
    try await store.save(cache, for: url)
    let elapsed = Date().timeIntervalSince(start)

    lastFlush = Date()
    dirty = false

    log.info("Flushed cache in \(Int(elapsed * 1000))ms (\(cache.entries.count) entries)")
  }

  /// Invalidate cache (forces regeneration)
  func invalidateCache(for url: URL) async throws {
    conversationURL = nil
    cache = nil
    dirty = false

    // Delete cache file
    let fileURL = try store.cacheFileURL(for: url)
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try FileManager.default.removeItem(at: fileURL)
      log.warning("Invalidated cache for \(url.lastPathComponent, privacy: .public)")
    }
  }

  // MARK: - Private Helpers

  private func markDirty() {
    dirty = true
    scheduleFlush()
  }

  private func scheduleFlush() {
    // Cancel any pending flush
    pendingFlush?.cancel()

    // Schedule a new flush after debounce interval
    let interval = flushDebounceInterval
    pendingFlush = Task { [weak self] in
      try? await Task.sleep(nanoseconds: interval)
      guard !Task.isCancelled else { return }
      guard let self = self else { return }
      try? await self.persistCache()
    }
  }

  private func computeContentHash(messageJSON: [String: Any]) -> String {
    // Canonicalize JSON and hash
    let canonical = canonicalizeJSON(messageJSON)
    return store.sha256(string: canonical)
  }

  private func computeWindowHash(contextUUIDs: [String]) -> String {
    let joined = contextUUIDs.joined(separator: "|")
    return store.sha256(string: joined)
  }

  private func generatorSignature() -> String {
    let blob = "\(modelId)|\(modelVersion)|\(promptVersion)|params:empty"
    return "sig:" + store.sha256(string: blob)
  }

  private func canonicalizeJSON(_ json: [String: Any]) -> String {
    // Sort keys and encode to stable string
    guard let data = try? JSONSerialization.data(withJSONObject: json, options: .sortedKeys),
          let string = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return string
  }
}

// MARK: - Result Types

/// Result type returned by cache lookups
struct RenderedTimelineEntry: Sendable {
  let summary: String
  let disposition: Disposition
  let isCompletion: Bool
  let isDirective: Bool
  let requestId: String?
  let duration: TimeInterval?
}

/// Cache-specific errors
enum CacheError: Error {
  case notLoaded
  case corruptCache
}
