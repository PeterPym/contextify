//
//  TimelineCache.swift
//  Contextify
//
//  Models for timeline cache storage with dual-form tense support.
//

import Foundation

/// Root cache structure for a conversation's timeline entries
struct TimelineCache: Codable, Sendable {
  var schemaVersion: String = "1.0.0"
  var cacheFormatVersion: Int = 1
  var conversationBookmark: Data?  // Security-scoped bookmark
  var conversationPath: String
  var generatedAt: Date
  var entries: [String: CachedTimelineEntry] = [:]  // UUID → Entry
  var metadata: CacheMetadata
}

/// A cached timeline entry with dual-form tense and validation metadata
struct CachedTimelineEntry: Codable, Sendable {
  // MARK: - Identity & Validation

  /// SHA256 hash of canonicalized message JSON (detects content changes)
  let contentHash: String

  /// SHA256 hash of context window UUIDs (detects context changes affecting interpretation)
  let windowHash: String

  /// Model+version+prompt signature (invalidates on LLM changes)
  let generatorSignature: String

  // MARK: - Disposition

  let disposition: Disposition

  // MARK: - Dual-Form Tense (No Regex Mutation!)

  /// Present continuous form: "Claude is implementing X"
  let presentForm: String

  /// Past simple form: "Claude implemented X"
  let pastForm: String

  /// Which form to display
  var selectedForm: Tense

  /// Base verb lemma for future conjugation (optional)
  let verbLemma: String?

  // MARK: - Metadata

  let generatedAt: Date

  // MARK: - User Overrides

  var userEdited: Bool = false
  var userText: String? = nil
  var editedAt: Date? = nil

  // MARK: - Completion Tracking

  var requestId: String? = nil
  var duration: TimeInterval? = nil

  // MARK: - Computed Properties

  nonisolated var isCompletion: Bool { disposition == .completion }
  nonisolated var isDirective: Bool { disposition == .directive }

  // MARK: - Rendering

  /// Returns the appropriate summary text based on user edits and tense selection
  nonisolated func render() -> String {
    if let userText = userText, userEdited {
      return userText
    }
    return selectedForm == .pastSimple ? pastForm : presentForm
  }
}

/// Cache-level metadata for tracking performance and statistics
struct CacheMetadata: Codable, Sendable {
  var totalEntries: Int = 0
  var lastFlush: Date = .distantPast
  var cacheHits: Int = 0
  var cacheMisses: Int = 0
  var regenerations: Int = 0
}

/// Bookmark index for tracking multiple conversations
struct CacheIndex: Codable, Sendable {
  var version: String = "1.0.0"
  var bookmarkToCacheFile: [String: String] = [:]  // bookmark base64 → cache filename
  var lastPruned: Date = .distantPast
}
