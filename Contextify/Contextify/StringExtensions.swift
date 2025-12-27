//
//  StringExtensions.swift
//  Contextify
//
//  Shared string utilities for the app target
//

import Foundation
import CryptoKit

// MARK: - SHA1 Hashing

extension String {
    /// Compute SHA1 hash of string, returning hex representation
    /// Used for stable UserDefaults keys (cursor persistence)
    nonisolated func sha1Hex() -> String {
        let digest = Insecure.SHA1.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
