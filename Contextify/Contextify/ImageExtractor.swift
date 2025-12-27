import Foundation
import AppKit
import OSLog

/// Represents an image extracted from a transcript entry
struct ExtractedImage: Identifiable, Sendable {
    let id = UUID()
    let mediaType: String
    let data: Data

    /// Decode the image data to NSImage
    var nsImage: NSImage? {
        NSImage(data: data)
    }
}

/// Result of extracting images from an entry, including accompanying prompt text
struct ImageExtractionResult: Sendable {
    let images: [ExtractedImage]
    let promptText: String?  // Text content that accompanied the images

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
actor ImageExtractor {
    static let shared = ImageExtractor()

    private let log = Logger(subsystem: "dev.contextify.timeline", category: "ImageExtractor")

    /// Cache of extraction results by entry ID
    private var cache: [String: ImageExtractionResult] = [:]

    /// Maximum number of entries to cache
    private let maxCacheSize = 100

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

        guard let path = transcriptPath else {
            log.debug("[IMAGE-EXTRACT] No transcript path for entry \(entryId.prefix(8), privacy: .public)")
            return ImageExtractionResult(images: [], promptText: nil)
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            log.debug("[IMAGE-EXTRACT] Transcript file not found: \(path, privacy: .public)")
            return ImageExtractionResult(images: [], promptText: nil)
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)

            for line in lines {
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let uuid = json["uuid"] as? String,
                      uuid == entryId else {
                    continue
                }

                // Found the entry, extract images and text from message content
                let result = extractContentFromEntry(json)

                // Cache the result
                cacheResult(result, forEntry: entryId)

                if !result.images.isEmpty {
                    log.info("[IMAGE-EXTRACT] Extracted \(result.images.count, privacy: .public) images from entry \(entryId.prefix(8), privacy: .public)")
                }

                return result
            }

            // Entry not found, cache empty result
            let emptyResult = ImageExtractionResult(images: [], promptText: nil)
            cacheResult(emptyResult, forEntry: entryId)
            return emptyResult

        } catch {
            log.warning("[IMAGE-EXTRACT] Failed to read transcript: \(error.localizedDescription, privacy: .public)")
            return ImageExtractionResult(images: [], promptText: nil)
        }
    }

    /// Extract image blocks and text from an entry's JSON
    private func extractContentFromEntry(_ json: [String: Any]) -> ImageExtractionResult {
        guard let message = json["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            return ImageExtractionResult(images: [], promptText: nil)
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
        return ImageExtractionResult(images: images, promptText: promptText)
    }

    /// Cache result with LRU eviction
    private func cacheResult(_ result: ImageExtractionResult, forEntry entryId: String) {
        // Simple eviction: remove oldest if over limit
        if cache.count >= maxCacheSize {
            // Remove first (oldest) entry
            if let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
        }
        cache[entryId] = result
    }

    /// Clear the image cache
    func clearCache() {
        cache.removeAll()
        log.info("[IMAGE-EXTRACT] Cache cleared")
    }

    /// Check if an entry has cached result (without loading)
    func hasCachedImages(entryId: String) -> Bool {
        cache[entryId] != nil
    }
}
