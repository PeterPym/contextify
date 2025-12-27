import Foundation
import AppKit
import OSLog
import ContextifyCore

/// Represents an image extracted from a transcript entry
struct ExtractedImage: Identifiable, Sendable {
  let id = UUID()
  let mediaType: String
  let data: Data

  /// Decode the image data to NSImage
  /// AppKit types are main-thread/actor oriented; require MainActor to avoid accidental background usage.
  @MainActor
  var nsImage: NSImage? {
    NSImage(data: data)
  }
}

/// Result of extracting images from an entry, including accompanying prompt text
struct ImageExtractionResult: Sendable {
  let images: [ExtractedImage]
  let promptText: String?  // Text content that accompanied the images
  let didReadFile: Bool    // Whether file was successfully opened and read
  let didFindEntry: Bool   // Whether the target entry UUID was found in the file

  nonisolated init(images: [ExtractedImage] = [], promptText: String? = nil, didReadFile: Bool = false, didFindEntry: Bool = false) {
    self.images = images
    self.promptText = promptText
    self.didReadFile = didReadFile
    self.didFindEntry = didFindEntry
  }

  /// Convenience for checking if result has images
  var isEmpty: Bool { images.isEmpty }
}

/// Extracts images from transcript files on-demand
///
/// Images in Claude Code transcripts are stored as base64-encoded content blocks:
/// ```json
/// {
///   "type": "image",
///   "source": {
///     "type": "base64",
///     "media_type": "image/png",
///     "data": "iVBORw0KGgo..."
///   }
/// }
/// ```
///
/// Architecture notes:
/// - Actor provides cache and in-flight task de-duplication
/// - File I/O runs in Task.detached to avoid blocking actor
/// - Uses line-by-line streaming via FileHandle (not loading entire file)
actor ImageExtractor {
  static let shared = ImageExtractor()

  private let log = Logger(subsystem: "dev.contextify.timeline", category: "ImageExtractor")

  /// Cache of extraction results by entry ID
  private var cache: [String: ImageExtractionResult] = [:]

  /// Track insertion order for FIFO eviction
  private var cacheOrder: [String] = []

  /// Track cached bytes for memory pressure management
  private var cachedBytes: Int = 0

  /// In-flight extraction tasks to avoid duplicate reads
  private var inFlight: [String: Task<ImageExtractionResult, Never>] = [:]

  /// Maximum number of entries to cache
  private let maxCacheSize = 100

  /// Maximum bytes to cache (100 MB default)
  private let maxCacheBytes = 100 * 1024 * 1024

  /// Access provider for sandbox builds (set once during app initialization)
  private var accessProvider: TranscriptAccessProvider?

  /// Configure the access provider (call once during app setup)
  func configure(accessProvider: TranscriptAccessProvider?) {
    self.accessProvider = accessProvider
    log.info("[IMAGE-EXTRACT] Access provider configured: \(accessProvider != nil ? "yes" : "no", privacy: .public)")
  }

  /// Extract images for a given entry from its transcript file
  /// - Parameters:
  ///   - entryId: The entry's source identifier (UUID string)
  ///   - transcriptPath: Path to the transcript JSONL file
  /// - Returns: Extraction result with images and prompt text
  func extractImages(entryId: String, transcriptPath: String?) async -> ImageExtractionResult {
    // Check cache first
    if let cached = cache[entryId] {
      log.debug("[IMAGE-EXTRACT] Cache hit for entry \(entryId.prefix(8), privacy: .public)")
      return cached
    }

    // Return existing in-flight task to avoid duplicate reads
    if let existingTask = inFlight[entryId] {
      log.debug("[IMAGE-EXTRACT] Joining in-flight extraction for entry \(entryId.prefix(8), privacy: .public)")
      return await existingTask.value
    }

    guard let path = transcriptPath else {
      log.debug("[IMAGE-EXTRACT] No transcript path for entry \(entryId.prefix(8), privacy: .public)")
      return ImageExtractionResult()
    }

    // Capture values for detached task (avoid capturing self)
    let targetEntryId = entryId
    let filePath = path
    let provider = accessProvider

    // Create extraction task that runs outside actor
    let task = Task.detached(priority: .utility) { [log] in
      await Self.performExtraction(
        entryId: targetEntryId,
        filePath: filePath,
        accessProvider: provider,
        log: log
      )
    }

    // Track in-flight task
    inFlight[entryId] = task
    defer { inFlight[entryId] = nil }

    // Await result
    let result = await task.value

    // Cache the result only if we successfully found the entry
    // (Don't cache mid-write/incomplete JSONL reads or missing entries)
    if result.didFindEntry {
      cacheResult(result, forEntry: entryId)
    }

    return result
  }

  /// Perform the actual extraction outside the actor (nonisolated)
  /// Uses FileHandle for line-by-line streaming to avoid loading entire file
  private static func performExtraction(
    entryId: String,
    filePath: String,
    accessProvider: TranscriptAccessProvider?,
    log: Logger
  ) async -> ImageExtractionResult {
    let url = URL(fileURLWithPath: filePath)

    // Determine provider ID for sandbox access
    let providerID = TranscriptProviderID.fromTranscriptURL(url)

    // Defensive log for sandbox mismatch (provider set but no providerID)
    if accessProvider != nil && providerID == nil {
      log.debug("[IMAGE-EXTRACT] Sandbox mismatch: accessProvider set but providerID is nil for path \(url.path, privacy: .public)")
    }

    do {
      // Wrap file access for sandbox builds
      let hasAccessProvider = accessProvider != nil
      let result: ImageExtractionResult = try {
        if let provider = accessProvider, let provID = providerID {
          return try provider.withAccess(for: provID) { _ in
            try Self.extractFromFile(entryId: entryId, url: url, hasAccessProvider: hasAccessProvider, log: log)
          }
        } else {
          // DMG build or unknown provider - direct access
          return try Self.extractFromFile(entryId: entryId, url: url, hasAccessProvider: hasAccessProvider, log: log)
        }
      }()

      return result
    } catch {
      log.warning("[IMAGE-EXTRACT] Failed to read transcript: \(error.localizedDescription, privacy: .public)")
      return ImageExtractionResult()
    }
  }

  /// Extract from file using line-by-line streaming
  private static func extractFromFile(
    entryId: String,
    url: URL,
    hasAccessProvider: Bool,
    log: Logger
  ) throws -> ImageExtractionResult {
    guard let fileHandle = FileHandle(forReadingAtPath: url.path) else {
      // Sandbox failure is likely a permission issue (warning)
      // File missing in DMG build is normal churn (debug)
      if hasAccessProvider {
        log.warning("[IMAGE-EXTRACT] Could not open file (likely missing security scope): \(url.path, privacy: .public)")
      } else {
        log.debug("[IMAGE-EXTRACT] Could not open file for reading: \(url.path, privacy: .public)")
      }
      // File not found/unreadable - don't cache this result
      return ImageExtractionResult()
    }

    defer { try? fileHandle.close() }

    // Read line by line using a buffered approach
    var buffer = Data()
    let chunkSize = 64 * 1024  // 64KB chunks
    let newline = UInt8(ascii: "\n")

    while true {
      // Read a chunk
      guard let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
        break
      }
      buffer.append(chunk)

      // Process complete lines in the buffer
      while let newlineIndex = buffer.firstIndex(of: newline) {
        let lineData = buffer[buffer.startIndex..<newlineIndex]
        buffer = Data(buffer[(newlineIndex + 1)...])

        // Try to parse this line as JSON
        guard !lineData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let uuid = json["uuid"] as? String,
              uuid == entryId else {
          continue
        }

        // Found the entry - extract images and text
        let result = extractContentFromEntry(json, log: log)

        if !result.images.isEmpty {
          log.info("[IMAGE-EXTRACT] Extracted \(result.images.count, privacy: .public) images from entry \(entryId.prefix(8), privacy: .public)")
        }

        return ImageExtractionResult(
          images: result.images,
          promptText: result.promptText,
          didReadFile: true,
          didFindEntry: true
        )
      }
    }

    // Process any remaining data in buffer (last line without newline)
    if !buffer.isEmpty {
      if let json = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any],
         let uuid = json["uuid"] as? String,
         uuid == entryId {
        let result = extractContentFromEntry(json, log: log)
        if !result.images.isEmpty {
          log.info("[IMAGE-EXTRACT] Extracted \(result.images.count, privacy: .public) images from entry \(entryId.prefix(8), privacy: .public)")
        }
        return ImageExtractionResult(
          images: result.images,
          promptText: result.promptText,
          didReadFile: true,
          didFindEntry: true
        )
      }
    }

    // Entry not found in file (but file was read successfully)
    // Don't cache this - could be mid-write JSONL or incomplete data
    return ImageExtractionResult(didReadFile: true, didFindEntry: false)
  }

  /// Extract image blocks and text from an entry's JSON
  private static func extractContentFromEntry(_ json: [String: Any], log: Logger) -> ImageExtractionResult {
    guard let message = json["message"] as? [String: Any],
          let contentBlocks = message["content"] as? [[String: Any]] else {
      // Note: didReadFile and didFindEntry will be set by caller
      return ImageExtractionResult()
    }

    var images: [ExtractedImage] = []
    var textParts: [String] = []

    for block in contentBlocks {
      guard let type = block["type"] as? String else { continue }

      if type == "text", let text = block["text"] as? String {
        // Collect text blocks
        textParts.append(text)
      } else if type == "image",
                let source = block["source"] as? [String: Any],
                let sourceType = source["type"] as? String,
                sourceType == "base64",
                let mediaType = source["media_type"] as? String,
                let base64String = source["data"] as? String {
        // Decode base64 image data
        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
          log.warning("[IMAGE-EXTRACT] Failed to decode base64 image data")
          continue
        }
        images.append(ExtractedImage(mediaType: mediaType, data: data))
      }
    }

    let promptText = textParts.isEmpty ? nil : textParts.joined(separator: "\n")
    // Note: didReadFile and didFindEntry will be set by caller
    return ImageExtractionResult(images: images, promptText: promptText)
  }

  /// Compute the byte size of a cached result
  private func byteSize(of result: ImageExtractionResult) -> Int {
    let imageBytes = result.images.reduce(0) { $0 + $1.data.count }
    let textBytes = result.promptText?.utf8.count ?? 0
    return imageBytes + textBytes
  }

  /// Cache result with FIFO eviction based on both entry count and byte size
  private func cacheResult(_ result: ImageExtractionResult, forEntry entryId: String) {
    // Verify cache/cacheOrder invariants
    #if DEBUG
    let keySet = Set(cache.keys)
    let orderSet = Set(cacheOrder)
    assert(orderSet.count == cacheOrder.count, "cacheOrder contains duplicates")
    assert(orderSet == keySet, "cache and cacheOrder keysets diverged")
    #endif

    let resultBytes = byteSize(of: result)

    // If a single result is larger than the entire cache budget, don't cache it.
    // (Still return it to the caller; just skip retention.)
    guard resultBytes <= maxCacheBytes else {
      log.info(
        "[IMAGE-EXTRACT] Skipping cache for oversized result (\(resultBytes, privacy: .public) bytes) entry \(entryId.prefix(8), privacy: .public)"
      )
      return
    }

    // Byte drift detection (pre-mutation) to pinpoint the first call site that introduced drift.
    #if DEBUG
    let preComputedBytes = cache.values.reduce(0) { $0 + byteSize(of: $1) }
    assert(preComputedBytes == cachedBytes, "cachedBytes drifted pre-mutation: computed=\(preComputedBytes) stored=\(cachedBytes)")
    #endif

    // Defensive: if we're re-caching the same entryId, remove old accounting + ordering.
    if let existing = cache.removeValue(forKey: entryId) {
      cachedBytes -= byteSize(of: existing)
    }
    if let idx = cacheOrder.firstIndex(of: entryId) {
      cacheOrder.remove(at: idx)
    }
    if cachedBytes < 0 { cachedBytes = 0 } // defensive against drift

    // Evict until BOTH constraints are satisfied.
    while (cachedBytes + resultBytes > maxCacheBytes || cache.count >= maxCacheSize),
          let oldest = cacheOrder.first {
      cacheOrder.removeFirst()
      if let evicted = cache.removeValue(forKey: oldest) {
        cachedBytes -= byteSize(of: evicted)
        if cachedBytes < 0 { cachedBytes = 0 }
      }
    }

    cache[entryId] = result
    cacheOrder.append(entryId)
    cachedBytes += resultBytes

    // Verify post-mutation invariants
    #if DEBUG
    let postKeySet = Set(cache.keys)
    let postOrderSet = Set(cacheOrder)
    assert(postOrderSet.count == cacheOrder.count, "cacheOrder contains duplicates after mutation")
    assert(postOrderSet == postKeySet, "cache and cacheOrder keysets diverged after mutation")

    // Byte drift detection
    let computedBytes = cache.values.reduce(0) { $0 + byteSize(of: $1) }
    assert(computedBytes == cachedBytes, "cachedBytes drifted: computed=\(computedBytes) stored=\(cachedBytes)")

    // Post-conditions after insertion
    assert(cachedBytes <= maxCacheBytes, "cachedBytes exceeds budget: \(cachedBytes) > \(maxCacheBytes)")
    assert(cache.count <= maxCacheSize, "cache exceeds entry cap: \(cache.count) > \(maxCacheSize)")

    // Empty-cache sanity
    if cacheOrder.isEmpty {
      assert(cache.isEmpty, "cacheOrder empty but cache not empty")
      assert(cachedBytes == 0, "cache empty but cachedBytes nonzero: \(cachedBytes)")
    }
    #endif
  }

  /// Clear the image cache
  func clearCache() {
    cache.removeAll()
    cacheOrder.removeAll()
    cachedBytes = 0
    log.info("[IMAGE-EXTRACT] Cache cleared")
  }

  /// Check if an entry has cached result (without loading)
  func hasCachedImages(entryId: String) -> Bool {
    cache[entryId] != nil
  }
}
