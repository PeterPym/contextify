import Foundation
import GRDB

// MARK: - Project

public struct Project: Codable, FetchableRecord, PersistableRecord {
  public var id: String
  public var name: String?
  public var rootPath: String
  public var rootBookmark: Data?
  public var createdAt: Int
  public var updatedAt: Int

  public static let databaseTableName = "projects"

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case rootPath = "root_path"
    case rootBookmark = "root_bookmark"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

// MARK: - Transcript

public struct Transcript: Codable, FetchableRecord, PersistableRecord {
  public var id: String
  public var projectId: String
  public var filePath: String
  public var provider: String
  public var providerSessionId: String?
  public var lastModified: Int
  public var fileSize: Int?
  public var lineCount: Int
  public var bookmark: Data?
  public var lastProcessedLine: Int
  public var lastProcessedEntryId: String?
  public var parserVersion: Int
  public var status: String
  public var lastError: String?
  public var createdAt: Int
  public var updatedAt: Int

  public static let databaseTableName = "transcripts"

  enum CodingKeys: String, CodingKey {
    case id
    case projectId = "project_id"
    case filePath = "file_path"
    case provider
    case providerSessionId = "provider_session_id"
    case lastModified = "last_modified"
    case fileSize = "file_size"
    case lineCount = "line_count"
    case bookmark
    case lastProcessedLine = "last_processed_line"
    case lastProcessedEntryId = "last_processed_entry_id"
    case parserVersion = "parser_version"
    case status
    case lastError = "last_error"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

// MARK: - Transcript Entry

/// Canonical source data from CLI AI tool transcripts (Claude Code, Codex CLI, etc.)
///
/// **IMPORTANT DATA ARCHITECTURE PRINCIPLE:**
/// This table stores ONLY canonical data parsed directly from transcript files.
/// DO NOT add derived/computed fields (summaries, classifications, flags, etc.)
///
/// - Derived data belongs in `timeline_cache` (LLM-generated summaries, disposition, etc.)
/// - Transcript-level metadata belongs in `transcript_metadata` (titles, descriptions, topics)
///
/// **Exception:** `project_id` is intentionally denormalized from `transcripts.project_id`
/// for query performance (allows single-table queries without JOIN).
///
/// **v6 Migration (2025-10-23):** Removed denormalized fields that violated this principle:
/// - `summary`, `disposition`, `is_completion`, `is_directive` → moved to `timeline_cache`
///
/// **UI Flags:** Derive at runtime from `timeline_cache.disposition`:
/// ```swift
/// isCompletion = cached?.disposition == "completion"
/// isDirective = ["directive", "affirmative", "negative"].contains(cached?.disposition)
/// ```
///
/// See: `build/notes/technical-reference/sql-backend-architecture.md` (Schema Evolution section)
public struct TranscriptEntry: Codable, FetchableRecord, PersistableRecord {
  public var id: String
  public var transcriptId: String
  public var projectId: String  // ONLY denormalized field (performance optimization)
  public var sessionId: String?
  public var provider: String
  public var kind: String
  public var timestamp: Int
  public var content: String
  public var contentSha256: String
  public var displayInTimeline: Int
  public var parentId: String?
  public var gitBranch: String?
  public var gitCommit: String?
  public var cwd: String?
  // Window context for cache key computation (prev entries for LLM context)
  public var prev1Id: String?
  public var prev2Id: String?
  public var windowSha256: String?
  public var createdAt: Int
  public var updatedAt: Int

  public static let databaseTableName = "transcript_entries"
  public static let databaseColumnCount = 19

  enum CodingKeys: String, CodingKey {
    case id
    case transcriptId = "transcript_id"
    case projectId = "project_id"
    case sessionId = "session_id"
    case provider
    case kind
    case timestamp
    case content
    case contentSha256 = "content_sha256"
    case displayInTimeline = "display_in_timeline"
    case parentId = "parent_id"
    case gitBranch = "git_branch"
    case gitCommit = "git_commit"
    case cwd
    case prev1Id = "prev1_id"
    case prev2Id = "prev2_id"
    case windowSha256 = "window_sha256"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

// MARK: - Cache Key

public struct CacheKey: Hashable, Codable, Sendable {
  public let content: String
  public let window: String

  public init(content: String, window: String) {
    self.content = content
    self.window = window
  }

  public var compositeKey: String {
    "\(content)|\(window)"
  }

  /// Shorter alias for compositeKey - use this for new code
  public var composite: String {
    "\(content)|\(window)"
  }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when timeline entry cache is updated
    /// - Object: CacheKey struct
    /// - UserInfo: None
    static let timelineCacheUpdated = Notification.Name("TimelineCacheUpdated")

    /// Posted when transcript metadata is updated
    /// - Object: String (transcript_id)
    /// - UserInfo: None
    static let transcriptMetadataUpdated = Notification.Name("TranscriptMetadataUpdated")

    /// Posted when transcript file is updated (for file watcher)
    /// - Object: String (transcript_id)
    /// - UserInfo: ["projectId": String]
    static let transcriptFileUpdated = Notification.Name("TranscriptFileUpdated")

    static let projectRootDidChange = Notification.Name("ProjectRootDidChange")
}

// MARK: - Timeline Cache

/// LLM-generated summaries and classifications for timeline entries (DERIVED DATA)
///
/// **DATA ARCHITECTURE PRINCIPLE:**
/// This table stores ALL derived/computed data generated by LLMs or other processes.
/// It is keyed by content+window hash to enable caching and reuse.
///
/// **Key Fields:**
/// - `disposition`: Message classification (SOURCE OF TRUTH for UI flags)
///   - Values: "directive", "affirmative", "negative", "completion", "analysis", "proposal", "question", "unknown"
///   - Derived flags: `isDirective = disposition IN ('directive', 'affirmative', 'negative')`
///   - Derived flags: `isCompletion = disposition == 'completion'`
/// - `presentForm`/`pastForm`: LLM-generated timeline summaries (e.g., "Claude proposes...", "Claude proposed...")
/// - `generatorSignature`: Prompt version for cache invalidation
///
/// **Separation from TranscriptEntry:**
/// - `transcript_entries`: Canonical source data from transcript files (immutable)
/// - `timeline_cache`: Derived data (can be regenerated without touching source)
///
/// **v6 Refactor (2025-10-23):** Removed denormalized fields from `transcript_entries`.
/// All classification/summary fields now ONLY live here.
///
/// See: `build/notes/technical-reference/timeline-cache-llm-architecture.md`
public struct TimelineCache: Codable, FetchableRecord, PersistableRecord, Sendable {
  public var contentSha256: String
  public var windowSha256: String
  public var entryId: String
  public var generatorSignature: String
  public var disposition: String  // SOURCE OF TRUTH for isDirective/isCompletion flags
  public var presentForm: String
  public var pastForm: String
  public var selectedForm: String
  public var verbLemma: String?
  public var generatedAt: Int
  public var userEdited: Int
  public var userText: String?
  public var editedAt: Int?
  public var requestId: String?
  public var duration: Double?

  public init(
    contentSha256: String,
    windowSha256: String,
    entryId: String,
    generatorSignature: String,
    disposition: String,
    presentForm: String,
    pastForm: String,
    selectedForm: String,
    verbLemma: String? = nil,
    generatedAt: Int,
    userEdited: Int,
    userText: String? = nil,
    editedAt: Int? = nil,
    requestId: String? = nil,
    duration: Double? = nil
  ) {
    self.contentSha256 = contentSha256
    self.windowSha256 = windowSha256
    self.entryId = entryId
    self.generatorSignature = generatorSignature
    self.disposition = disposition
    self.presentForm = presentForm
    self.pastForm = pastForm
    self.selectedForm = selectedForm
    self.verbLemma = verbLemma
    self.generatedAt = generatedAt
    self.userEdited = userEdited
    self.userText = userText
    self.editedAt = editedAt
    self.requestId = requestId
    self.duration = duration
  }

  public static let databaseTableName = "timeline_cache"
  public static let databaseColumnCount = 15

  enum CodingKeys: String, CodingKey {
    case contentSha256 = "content_sha256"
    case windowSha256 = "window_sha256"
    case entryId = "entry_id"
    case generatorSignature = "generator_signature"
    case disposition
    case presentForm = "present_form"
    case pastForm = "past_form"
    case selectedForm = "selected_form"
    case verbLemma = "verb_lemma"
    case generatedAt = "generated_at"
    case userEdited = "user_edited"
    case userText = "user_text"
    case editedAt = "edited_at"
    case requestId = "request_id"
    case duration
  }
}

// MARK: - Transcript Metadata

public struct TranscriptMetadataRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public var transcriptId: String
  public var projectId: String
  public var title: String
  public var description: String
  public var topics: String // JSON array
  public var confidence: Double
  public var mayContainHallucinations: Int
  public var needsReview: Int
  public var generatedAt: Int
  public var model: String
  public var promptVersion: Int
  public var generatorVersion: Int
  public var transcriptSha256: String
  public var messageCount: Int
  public var strategy: String
  public var llmCalls: Int
  public var latencyMs: Int
  public var createdAt: Int
  public var updatedAt: Int

  public init(
    transcriptId: String,
    projectId: String,
    title: String,
    description: String,
    topics: String,
    confidence: Double,
    mayContainHallucinations: Int,
    needsReview: Int,
    generatedAt: Int,
    model: String,
    promptVersion: Int,
    generatorVersion: Int,
    transcriptSha256: String,
    messageCount: Int,
    strategy: String,
    llmCalls: Int,
    latencyMs: Int,
    createdAt: Int,
    updatedAt: Int
  ) {
    self.transcriptId = transcriptId
    self.projectId = projectId
    self.title = title
    self.description = description
    self.topics = topics
    self.confidence = confidence
    self.mayContainHallucinations = mayContainHallucinations
    self.needsReview = needsReview
    self.generatedAt = generatedAt
    self.model = model
    self.promptVersion = promptVersion
    self.generatorVersion = generatorVersion
    self.transcriptSha256 = transcriptSha256
    self.messageCount = messageCount
    self.strategy = strategy
    self.llmCalls = llmCalls
    self.latencyMs = latencyMs
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public static let databaseTableName = "transcript_metadata"

  enum CodingKeys: String, CodingKey {
    case transcriptId = "transcript_id"
    case projectId = "project_id"
    case title
    case description
    case topics
    case confidence
    case mayContainHallucinations = "may_contain_hallucinations"
    case needsReview = "needs_review"
    case generatedAt = "generated_at"
    case model
    case promptVersion = "prompt_version"
    case generatorVersion = "generator_version"
    case transcriptSha256 = "transcript_sha256"
    case messageCount = "message_count"
    case strategy
    case llmCalls = "llm_calls"
    case latencyMs = "latency_ms"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

// MARK: - Parse Error

public struct ParseError: Codable, FetchableRecord, PersistableRecord {
  public var id: String
  public var transcriptId: String
  public var lineNumber: Int
  public var rawLine: String
  public var errorMessage: String
  public var createdAt: Int

  public static let databaseTableName = "parse_errors"

  enum CodingKeys: String, CodingKey {
    case id
    case transcriptId = "transcript_id"
    case lineNumber = "line_number"
    case rawLine = "raw_line"
    case errorMessage = "error_message"
    case createdAt = "created_at"
  }
}
