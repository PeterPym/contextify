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

    /// Cache of extracted images by entry ID
    private var cache: [String: [ExtractedImage]] = [:]

    /// Maximum number of entries to cache
    private let maxCacheSize = 100

    /// Extract images for a given entry from its transcript file
    /// - Parameters:
    ///   - entryId: The entry's source identifier (UUID string)
    ///   - transcriptPath: Path to the transcript JSONL file
    /// - Returns: Array of extracted images, empty if none found
    func extractImages(entryId: String, transcriptPath: String?) async -> [ExtractedImage] {
        // Check cache first
        if let cached = cache[entryId] {
            log.debug("[IMAGE-EXTRACT] Cache hit for entry \(entryId.prefix(8), privacy: .public)")
            return cached
        }

        guard let path = transcriptPath else {
            log.debug("[IMAGE-EXTRACT] No transcript path for entry \(entryId.prefix(8), privacy: .public)")
            return []
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            log.debug("[IMAGE-EXTRACT] Transcript file not found: \(path, privacy: .public)")
            return []
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

                // Found the entry, extract images from message content
                let images = extractImagesFromEntry(json)

                // Cache the result
                cacheImages(images, forEntry: entryId)

                if !images.isEmpty {
                    log.info("[IMAGE-EXTRACT] Extracted \(images.count, privacy: .public) images from entry \(entryId.prefix(8), privacy: .public)")
                }

                return images
            }

            // Entry not found, cache empty result
            cacheImages([], forEntry: entryId)
            return []

        } catch {
            log.warning("[IMAGE-EXTRACT] Failed to read transcript: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Extract image blocks from an entry's JSON
    private func extractImagesFromEntry(_ json: [String: Any]) -> [ExtractedImage] {
        guard let message = json["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            return []
        }

        var images: [ExtractedImage] = []

        for block in contentBlocks {
            guard let type = block["type"] as? String,
                  type == "image",
                  let source = block["source"] as? [String: Any],
                  let sourceType = source["type"] as? String,
                  sourceType == "base64",
                  let mediaType = source["media_type"] as? String,
                  let base64String = source["data"] as? String else {
                continue
            }

            // Decode base64 data
            guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
                log.warning("[IMAGE-EXTRACT] Failed to decode base64 image data")
                continue
            }

            images.append(ExtractedImage(mediaType: mediaType, data: data))
        }

        return images
    }

    /// Cache images with LRU eviction
    private func cacheImages(_ images: [ExtractedImage], forEntry entryId: String) {
        // Simple eviction: remove oldest if over limit
        if cache.count >= maxCacheSize {
            // Remove first (oldest) entry
            if let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
        }
        cache[entryId] = images
    }

    /// Clear the image cache
    func clearCache() {
        cache.removeAll()
        log.info("[IMAGE-EXTRACT] Cache cleared")
    }

    /// Check if an entry has cached images (without loading)
    func hasCachedImages(entryId: String) -> Bool {
        cache[entryId] != nil
    }
}
