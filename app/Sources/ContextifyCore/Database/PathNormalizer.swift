//
//  PathNormalizer.swift
//  ContextifyCore
//
//  Path normalization utilities for canonical transcript identification.
//  Handles symlinks, case-insensitive filesystems, and path standardization.
//

import Foundation
import CryptoKit

/// Path normalization for canonical transcript identification
/// - Resolves symlinks
/// - Standardizes paths (removes .., ., etc.)
/// - Case-folds on case-insensitive filesystems (macOS default)
public enum PathNormalizer {

    /// Normalize a file path for canonical comparison
    /// - Parameter path: Raw file path
    /// - Returns: Normalized path (lowercased on macOS, standardized)
    public static func normalize(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)

        // Resolve symlinks and standardize
        let resolved = (try? url.resolvingSymlinksInPath()) ?? url
        let standardized = resolved.standardized.path

        // Case-fold on case-insensitive FS (macOS default HFS+/APFS)
        #if os(macOS)
        return standardized.lowercased()
        #else
        return standardized
        #endif
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
