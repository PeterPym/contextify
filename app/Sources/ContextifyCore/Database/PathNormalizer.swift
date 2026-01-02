//
//  PathNormalizer.swift
//  ContextifyCore
//
//  Path normalization utilities for canonical transcript identification.
//  Handles symlinks, case-insensitive filesystems, Unicode normalization, and path standardization.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Path normalization for canonical transcript identification
/// - Resolves symlinks (if file exists)
/// - Standardizes paths (removes .., ., etc.)
/// - Unicode canonical composition (NFC)
/// - Case-folds on case-insensitive volumes only
public enum PathNormalizer {

    /// Normalize a file path for canonical comparison
    /// - Parameter path: Raw file path
    /// - Returns: Normalized path (Unicode NFC, conditionally lowercased)
    public static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return "" }

        let rawURL = URL(fileURLWithPath: path)

        // Only resolve symlinks if file exists (avoid errors on non-existent paths)
        let resolved: URL
        if FileManager.default.fileExists(atPath: path) {
            resolved = rawURL.resolvingSymlinksInPath()
        } else {
            resolved = rawURL
        }

        // Standardize and apply Unicode canonical composition (NFC)
        let standardized = resolved.standardized.path.precomposedStringWithCanonicalMapping

        #if os(macOS)
        // Check if volume is case-sensitive (some APFS volumes are case-sensitive)
        let volumeURL = resolved.deletingLastPathComponent()
        if let resourceValues = try? volumeURL.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]),
           resourceValues.volumeSupportsCaseSensitiveNames == false {
            // Case-insensitive volume - lowercase with POSIX locale for consistency
            return standardized.lowercased(with: Locale(identifier: "en_US_POSIX"))
        }
        #endif

        return standardized
    }

    /// Compute SHA256 hash of normalized path
    /// - Parameter normalizedPath: Already-normalized path
    /// - Returns: Hex-encoded SHA256 hash (64 characters)
    public static func hash(_ normalizedPath: String) -> String {
        let data = Data(normalizedPath.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Normalize and hash in one operation
    /// - Parameter path: Raw file path
    /// - Returns: Tuple of (normalized path, hash)
    public static func normalizeAndHash(_ path: String) -> (normalized: String, hash: String) {
        let normalized = normalize(path)
        let pathHash = hash(normalized)
        return (normalized, pathHash)
    }
}
