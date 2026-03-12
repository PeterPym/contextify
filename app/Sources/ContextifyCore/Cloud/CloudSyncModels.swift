// SPDX-License-Identifier: MIT
// CloudSyncModels.swift - Codable types mirroring the contextify-cloud server schemas
//
// These types correspond to the Pydantic models in contextify_cloud/schemas.py.
// They are used by both the CLI (contextify cloud push/pull) and the macOS app
// for serializing/deserializing cloud sync API requests and responses.
//
// All types use explicit CodingKeys with snake_case values so they work correctly
// with any JSONEncoder/JSONDecoder regardless of key encoding strategy settings.

import Foundation

// MARK: - Configuration

/// Client-side cloud sync configuration, stored in ~/.config/contextify/cloud.json.
///
/// Contains the server URL, API key, device identity, and sync cursor state.
/// The CLI's CloudConfig in CloudCommand.swift is a simpler version of this;
/// this type is the canonical representation for ContextifyCore consumers.
public struct CloudConfig: Codable, Sendable {
  /// Base URL of the contextify-cloud server (e.g. "https://cloud.contextify.sh").
  public var serverURL: String

  /// API key for authentication (prefixed with "ctx_").
  public var apiKey: String

  /// Stable machine identifier for device registration.
  public var deviceId: String

  /// Human-readable device name (e.g. "Rob's MacBook Pro").
  public var deviceName: String

  /// Whether cloud sync is enabled.
  public var enabled: Bool

  /// Server sequence cursor from the last successful pull.
  /// Used as the "since" parameter for incremental pull requests.
  public var lastPullSequence: Int

  /// Timestamp of the newest entry pushed in the last successful push cycle.
  /// Used as the keyset cursor to avoid re-uploading the entire database.
  /// When nil, push starts from the beginning (full upload).
  public var lastPushTimestamp: Int?

  /// Entry ID tiebreaker for the last push cursor (same timestamp as lastPushTimestamp).
  /// Required for correct keyset pagination when multiple entries share a timestamp.
  public var lastPushEntryId: String?

  /// Active push sync session ID (UUID string) for deterministic batch resume.
  public var lastPushSessionId: String?

  /// Last completed push batch sequence for the active session.
  public var lastPushBatchSeq: Int?

  public init(
    serverURL: String,
    apiKey: String,
    deviceId: String = "",
    deviceName: String = "",
    enabled: Bool = true,
    lastPullSequence: Int = 0,
    lastPushTimestamp: Int? = nil,
    lastPushEntryId: String? = nil,
    lastPushSessionId: String? = nil,
    lastPushBatchSeq: Int? = nil
  ) {
    self.serverURL = serverURL
    self.apiKey = apiKey
    self.deviceId = deviceId
    self.deviceName = deviceName
    self.enabled = enabled
    self.lastPullSequence = lastPullSequence
    self.lastPushTimestamp = lastPushTimestamp
    self.lastPushEntryId = lastPushEntryId
    self.lastPushSessionId = lastPushSessionId
    self.lastPushBatchSeq = lastPushBatchSeq
  }

  enum CodingKeys: String, CodingKey {
    case serverURL = "server_url"
    case apiKey = "api_key"
    case deviceId = "device_id"
    case deviceName = "device_name"
    case enabled
    case lastPullSequence = "last_pull_sequence"
    case lastPushTimestamp = "last_push_timestamp"
    case lastPushEntryId = "last_push_entry_id"
    case lastPushSessionId = "last_push_session_id"
    case lastPushBatchSeq = "last_push_batch_seq"
  }

  // MARK: File Locations

  /// Directory for cloud sync configuration files.
  public static var configDir: URL {
    if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
      return URL(fileURLWithPath: xdg).appendingPathComponent("contextify")
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/contextify")
  }

  /// Path to the cloud.json configuration file.
  public static var configFile: URL {
    configDir.appendingPathComponent("cloud.json")
  }

  /// Load configuration from disk.
  public static func load() throws -> CloudConfig {
    let data = try Data(contentsOf: configFile)
    return try JSONDecoder().decode(CloudConfig.self, from: data)
  }

  /// Persist configuration to disk, creating the directory if needed.
  public func save() throws {
    try FileManager.default.createDirectory(
      at: CloudConfig.configDir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(self)
    try data.write(to: CloudConfig.configFile, options: .atomic)
  }
}

// MARK: - Device Info

/// Device identity sent with push requests and returned in status responses.
/// Maps to the server's `DeviceInfo` Pydantic model.
public struct CloudDeviceInfo: Codable, Sendable {
  /// Stable machine identifier (e.g. IOPlatformUUID on macOS, /etc/machine-id on Linux).
  public let machineId: String

  /// Human-readable machine name.
  public let machineName: String

  /// Operating system identifier (e.g. "macos", "linux").
  public let os: String?

  /// Application version string.
  public let appVersion: String?

  public init(
    machineId: String,
    machineName: String,
    os: String? = nil,
    appVersion: String? = nil
  ) {
    self.machineId = machineId
    self.machineName = machineName
    self.os = os
    self.appVersion = appVersion
  }

  enum CodingKeys: String, CodingKey {
    case machineId = "machine_id"
    case machineName = "machine_name"
    case os
    case appVersion = "app_version"
  }
}

// MARK: - Entry Kind

/// The set of entry kinds recognized by the cloud sync protocol.
/// Maps to the server's regex constraint: `^(user|assistant|system|summary)$`
public enum CloudEntryKind: String, Codable, Sendable {
  case user
  case assistant
  case system
  case summary
}

// MARK: - Push Types

/// A project record included in a push request.
/// Maps to the server's `SyncProject` Pydantic model.
public struct CloudPushProject: Codable, Sendable {
  public let id: String
  public let name: String?
  public let rootPath: String

  public init(id: String, name: String? = nil, rootPath: String) {
    self.id = id
    self.name = name
    self.rootPath = rootPath
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case rootPath = "root_path"
  }
}

/// A transcript record included in a push request.
/// Maps to the server's `SyncTranscript` Pydantic model.
public struct CloudPushTranscript: Codable, Sendable {
  public let id: String
  public let projectId: String
  public let filePath: String
  public let provider: String
  public let providerSessionId: String?
  public let lineCount: Int
  public let createdAt: Int
  public let updatedAt: Int

  public init(
    id: String,
    projectId: String,
    filePath: String,
    provider: String,
    providerSessionId: String? = nil,
    lineCount: Int = 0,
    createdAt: Int,
    updatedAt: Int
  ) {
    self.id = id
    self.projectId = projectId
    self.filePath = filePath
    self.provider = provider
    self.providerSessionId = providerSessionId
    self.lineCount = lineCount
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case id
    case projectId = "project_id"
    case filePath = "file_path"
    case provider
    case providerSessionId = "provider_session_id"
    case lineCount = "line_count"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// A transcript entry record included in a push request.
/// Maps to the server's `SyncEntry` Pydantic model.
///
/// The `kind` field is constrained to user/assistant/system/summary on the server.
/// The `contentSha256` must be exactly 64 hex characters (SHA-256 digest).
public struct CloudPushEntry: Codable, Sendable {
  public let id: String
  public let transcriptId: String
  public let projectId: String
  public let sessionId: String?
  public let provider: String
  /// Entry kind. Must be one of: user, assistant, system, summary.
  public let kind: String
  public let timestamp: Int
  /// Entry content text. Server enforces a 1MB limit.
  public let content: String
  /// SHA-256 hex digest of the content (64 characters).
  public let contentSha256: String
  public let displayInTimeline: Bool
  public let gitBranch: String?
  public let gitCommit: String?
  public let cwd: String?
  public let createdAt: Int
  public let updatedAt: Int

  public init(
    id: String,
    transcriptId: String,
    projectId: String,
    sessionId: String? = nil,
    provider: String,
    kind: String,
    timestamp: Int,
    content: String,
    contentSha256: String,
    displayInTimeline: Bool = true,
    gitBranch: String? = nil,
    gitCommit: String? = nil,
    cwd: String? = nil,
    createdAt: Int,
    updatedAt: Int
  ) {
    self.id = id
    self.transcriptId = transcriptId
    self.projectId = projectId
    self.sessionId = sessionId
    self.provider = provider
    self.kind = kind
    self.timestamp = timestamp
    self.content = content
    self.contentSha256 = contentSha256
    self.displayInTimeline = displayInTimeline
    self.gitBranch = gitBranch
    self.gitCommit = gitCommit
    self.cwd = cwd
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

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
    case gitBranch = "git_branch"
    case gitCommit = "git_commit"
    case cwd
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// An entry-level summary record included in a push request.
/// Maps to the server's `SyncSummary` Pydantic model.
public struct CloudPushSummary: Codable, Sendable {
  public let entryId: String
  public let contentSha256: String
  public let windowSha256: String
  public let presentForm: String
  public let pastForm: String
  public let disposition: String?
  public let generatedAt: Int

  public init(
    entryId: String,
    contentSha256: String,
    windowSha256: String,
    presentForm: String,
    pastForm: String,
    disposition: String? = nil,
    generatedAt: Int
  ) {
    self.entryId = entryId
    self.contentSha256 = contentSha256
    self.windowSha256 = windowSha256
    self.presentForm = presentForm
    self.pastForm = pastForm
    self.disposition = disposition
    self.generatedAt = generatedAt
  }

  enum CodingKeys: String, CodingKey {
    case entryId = "entry_id"
    case contentSha256 = "content_sha256"
    case windowSha256 = "window_sha256"
    case presentForm = "present_form"
    case pastForm = "past_form"
    case disposition
    case generatedAt = "generated_at"
  }
}

/// An LLM usage record included in a push request.
/// Maps to the server's `SyncUsage` Pydantic model.
public struct CloudPushUsage: Codable, Sendable {
  public let entryId: String
  public let requestId: String
  public let model: String
  public let inputTokens: Int
  public let outputTokens: Int
  public let cacheCreationTokens: Int
  public let cacheReadTokens: Int

  public init(
    entryId: String,
    requestId: String,
    model: String,
    inputTokens: Int,
    outputTokens: Int,
    cacheCreationTokens: Int = 0,
    cacheReadTokens: Int = 0
  ) {
    self.entryId = entryId
    self.requestId = requestId
    self.model = model
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cacheCreationTokens = cacheCreationTokens
    self.cacheReadTokens = cacheReadTokens
  }

  enum CodingKeys: String, CodingKey {
    case entryId = "entry_id"
    case requestId = "request_id"
    case model
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case cacheCreationTokens = "cache_creation_tokens"
    case cacheReadTokens = "cache_read_tokens"
  }
}

/// A tool invocation record included in a push request.
/// Maps to the server's `SyncToolInvocation` Pydantic model.
public struct CloudPushToolInvocation: Codable, Sendable {
  public let id: String
  public let entryId: String
  public let transcriptId: String
  public let toolName: String
  public let toolKey: String?
  public let status: String
  public let startedAt: Int?
  public let completedAt: Int?
  public let metadataJson: [String: String]?
  public let createdAt: Int
  public let updatedAt: Int

  public init(
    id: String,
    entryId: String,
    transcriptId: String,
    toolName: String,
    toolKey: String? = nil,
    status: String = "unknown",
    startedAt: Int? = nil,
    completedAt: Int? = nil,
    metadataJson: [String: String]? = nil,
    createdAt: Int,
    updatedAt: Int
  ) {
    self.id = id
    self.entryId = entryId
    self.transcriptId = transcriptId
    self.toolName = toolName
    self.toolKey = toolKey
    self.status = status
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.metadataJson = metadataJson
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case id
    case entryId = "entry_id"
    case transcriptId = "transcript_id"
    case toolName = "tool_name"
    case toolKey = "tool_key"
    case status
    case startedAt = "started_at"
    case completedAt = "completed_at"
    case metadataJson = "metadata_json"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// Transcript-level metadata record included in a push request.
/// Maps to the server's `SyncTranscriptMetadata` Pydantic model.
public struct CloudPushTranscriptMetadata: Codable, Sendable {
  public let transcriptId: String
  public let projectId: String
  public let title: String
  public let description: String?
  public let topics: [String]
  public let confidence: Double
  public let generatedAt: Int
  public let model: String
  public let createdAt: Int
  public let updatedAt: Int

  public init(
    transcriptId: String,
    projectId: String,
    title: String,
    description: String? = nil,
    topics: [String] = [],
    confidence: Double,
    generatedAt: Int,
    model: String,
    createdAt: Int,
    updatedAt: Int
  ) {
    self.transcriptId = transcriptId
    self.projectId = projectId
    self.title = title
    self.description = description
    self.topics = topics
    self.confidence = confidence
    self.generatedAt = generatedAt
    self.model = model
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case transcriptId = "transcript_id"
    case projectId = "project_id"
    case title
    case description
    case topics
    case confidence
    case generatedAt = "generated_at"
    case model
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

// MARK: - Push Payload & Response

/// Top-level push request body sent to POST /api/v1/sync/push.
/// Maps to the server's `SyncPushRequest` Pydantic model.
///
/// Contains device identity, an optional idempotency key for safe retries,
/// and arrays of projects, transcripts, and entries to upload.
/// The `idempotencyKey` enables the server to return cached responses for
/// duplicate requests, which is critical for robustness with intermittent connectivity.
public struct CloudPushPayload: Codable, Sendable {
  /// Client-generated UUID to prevent duplicate batch processing on retries.
  public let idempotencyKey: String?
  /// Sequence number within a multi-batch sync session.
  public let batchSeq: Int?
  /// Session UUID for deterministic multi-batch upload identity.
  public let syncSessionId: String?
  /// Optional client-declared entries count for sanity checks.
  public let entriesSent: Int?
  /// Device identity for this push.
  public let device: CloudDeviceInfo
  /// Projects referenced by the entries being pushed.
  public let projects: [CloudPushProject]
  /// Transcripts referenced by the entries being pushed.
  public let transcripts: [CloudPushTranscript]
  /// Transcript entries to push.
  public let entries: [CloudPushEntry]
  /// Entry-level summaries to push.
  public let summaries: [CloudPushSummary]
  /// LLM usage records to push.
  public let usage: [CloudPushUsage]
  /// Tool invocation records to push.
  public let toolInvocations: [CloudPushToolInvocation]
  /// Transcript-level metadata (titles, topics) to push.
  public let transcriptMetadata: [CloudPushTranscriptMetadata]

  public init(
    idempotencyKey: String? = nil,
    batchSeq: Int? = nil,
    syncSessionId: String? = nil,
    entriesSent: Int? = nil,
    device: CloudDeviceInfo,
    projects: [CloudPushProject] = [],
    transcripts: [CloudPushTranscript] = [],
    entries: [CloudPushEntry] = [],
    summaries: [CloudPushSummary] = [],
    usage: [CloudPushUsage] = [],
    toolInvocations: [CloudPushToolInvocation] = [],
    transcriptMetadata: [CloudPushTranscriptMetadata] = []
  ) {
    self.idempotencyKey = idempotencyKey
    self.batchSeq = batchSeq
    self.syncSessionId = syncSessionId
    self.entriesSent = entriesSent
    self.device = device
    self.projects = projects
    self.transcripts = transcripts
    self.entries = entries
    self.summaries = summaries
    self.usage = usage
    self.toolInvocations = toolInvocations
    self.transcriptMetadata = transcriptMetadata
  }

  enum CodingKeys: String, CodingKey {
    case idempotencyKey = "idempotency_key"
    case batchSeq = "batch_seq"
    case syncSessionId = "sync_session_id"
    case entriesSent = "entries_sent"
    case device
    case projects
    case transcripts
    case entries
    case summaries
    case usage
    case toolInvocations = "tool_invocations"
    case transcriptMetadata = "transcript_metadata"
  }
}

/// Server response from POST /api/v1/sync/push.
/// Maps to the server's `SyncPushResponse` Pydantic model.
public struct CloudPushResponse: Codable, Sendable {
  /// Number of entries accepted by the server.
  public let accepted: Int
  /// Number of entries skipped because they already existed on the server.
  public let duplicatesSkipped: Int
  /// Any errors encountered during processing.
  public let errors: [String]
  /// Opaque sync token for future use.
  public let syncToken: String?
  /// Echoed back for client correlation with the request.
  public let idempotencyKey: String?
  /// Session UUID returned by the server for multi-batch resume.
  public let syncSessionId: String?
  /// Echoed batch sequence.
  public let batchSeq: Int?
  /// Entries declared in this batch.
  public let entriesSent: Int?
  /// Entries newly accepted from this batch.
  public let entriesAccepted: Int?
  /// Entries resolved as duplicates.
  public let entriesDuplicates: Int?
  /// Entries rejected due to content conflicts.
  public let entriesConflicted: Int?
  /// Entries blocked by policy/filtering.
  public let entriesBlockedPolicy: Int?
  /// Entries that failed with retriable errors.
  public let entriesRetriableFailed: Int?
  /// Entries resolved for checkpoint decisions.
  public let entriesResolved: Int?
  /// Whether cursor advancement is safe for this batch.
  public let checkpointSafe: Bool?
  /// Batch/session outcome state from server.
  public let completionState: String?
  /// Count requiring user attention.
  public let needsAttentionCount: Int?
  /// Stable error classification codes.
  public let errorCodes: [String]?
  /// Server-side high-water mark sequence number after this push.
  public let serverSequence: Int

  public init(
    accepted: Int,
    duplicatesSkipped: Int = 0,
    errors: [String] = [],
    syncToken: String? = nil,
    idempotencyKey: String? = nil,
    syncSessionId: String? = nil,
    batchSeq: Int? = nil,
    entriesSent: Int? = nil,
    entriesAccepted: Int? = nil,
    entriesDuplicates: Int? = nil,
    entriesConflicted: Int? = nil,
    entriesBlockedPolicy: Int? = nil,
    entriesRetriableFailed: Int? = nil,
    entriesResolved: Int? = nil,
    checkpointSafe: Bool? = nil,
    completionState: String? = nil,
    needsAttentionCount: Int? = nil,
    errorCodes: [String]? = nil,
    serverSequence: Int = 0
  ) {
    self.accepted = accepted
    self.duplicatesSkipped = duplicatesSkipped
    self.errors = errors
    self.syncToken = syncToken
    self.idempotencyKey = idempotencyKey
    self.syncSessionId = syncSessionId
    self.batchSeq = batchSeq
    self.entriesSent = entriesSent
    self.entriesAccepted = entriesAccepted
    self.entriesDuplicates = entriesDuplicates
    self.entriesConflicted = entriesConflicted
    self.entriesBlockedPolicy = entriesBlockedPolicy
    self.entriesRetriableFailed = entriesRetriableFailed
    self.entriesResolved = entriesResolved
    self.checkpointSafe = checkpointSafe
    self.completionState = completionState
    self.needsAttentionCount = needsAttentionCount
    self.errorCodes = errorCodes
    self.serverSequence = serverSequence
  }

  enum CodingKeys: String, CodingKey {
    case accepted
    case duplicatesSkipped = "duplicates_skipped"
    case errors
    case syncToken = "sync_token"
    case idempotencyKey = "idempotency_key"
    case syncSessionId = "sync_session_id"
    case batchSeq = "batch_seq"
    case entriesSent = "entries_sent"
    case entriesAccepted = "entries_accepted"
    case entriesDuplicates = "entries_duplicates"
    case entriesConflicted = "entries_conflicted"
    case entriesBlockedPolicy = "entries_blocked_policy"
    case entriesRetriableFailed = "entries_retriable_failed"
    case entriesResolved = "entries_resolved"
    case checkpointSafe = "checkpoint_safe"
    case completionState = "completion_state"
    case needsAttentionCount = "needs_attention_count"
    case errorCodes = "error_codes"
    case serverSequence = "server_sequence"
  }
}

// MARK: - Pull Types

/// An entry returned from GET /api/v1/sync/pull.
/// Maps to the server's `PullEntry` Pydantic model.
///
/// Extends the push entry shape with server-assigned fields:
/// `uploadedByUserId`, `uploadedByDeviceId`, and `serverSequence`.
/// The `kind` field is constrained to user/assistant/system/summary.
public struct CloudPullEntry: Codable, Sendable {
  public let id: String
  public let transcriptId: String
  public let projectId: String
  public let sessionId: String?
  public let provider: String
  /// Entry kind. One of: user, assistant, system, summary.
  public let kind: String
  public let timestamp: Int
  public let content: String
  public let contentSha256: String
  public let displayInTimeline: Bool
  public let gitBranch: String?
  public let gitCommit: String?
  public let cwd: String?
  /// The user ID that uploaded this entry.
  public let uploadedByUserId: String
  /// The device ID that uploaded this entry.
  public let uploadedByDeviceId: String?
  /// Monotonically increasing server sequence number. Used as cursor for pull pagination.
  public let serverSequence: Int
  public let createdAt: Int
  public let updatedAt: Int

  public init(
    id: String,
    transcriptId: String,
    projectId: String,
    sessionId: String? = nil,
    provider: String,
    kind: String,
    timestamp: Int,
    content: String,
    contentSha256: String,
    displayInTimeline: Bool = true,
    gitBranch: String? = nil,
    gitCommit: String? = nil,
    cwd: String? = nil,
    uploadedByUserId: String,
    uploadedByDeviceId: String? = nil,
    serverSequence: Int,
    createdAt: Int,
    updatedAt: Int
  ) {
    self.id = id
    self.transcriptId = transcriptId
    self.projectId = projectId
    self.sessionId = sessionId
    self.provider = provider
    self.kind = kind
    self.timestamp = timestamp
    self.content = content
    self.contentSha256 = contentSha256
    self.displayInTimeline = displayInTimeline
    self.gitBranch = gitBranch
    self.gitCommit = gitCommit
    self.cwd = cwd
    self.uploadedByUserId = uploadedByUserId
    self.uploadedByDeviceId = uploadedByDeviceId
    self.serverSequence = serverSequence
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

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
    case gitBranch = "git_branch"
    case gitCommit = "git_commit"
    case cwd
    case uploadedByUserId = "uploaded_by_user_id"
    case uploadedByDeviceId = "uploaded_by_device_id"
    case serverSequence = "server_sequence"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// A project returned from GET /api/v1/sync/pull.
/// Maps to the server's `PullProject` Pydantic model.
public struct CloudPullProject: Codable, Sendable {
  public let id: String
  public let name: String?
  public let rootPath: String

  public init(id: String, name: String? = nil, rootPath: String) {
    self.id = id
    self.name = name
    self.rootPath = rootPath
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case rootPath = "root_path"
  }
}

/// A transcript returned from GET /api/v1/sync/pull.
/// Maps to the server's `PullTranscript` Pydantic model.
public struct CloudPullTranscript: Codable, Sendable {
  public let id: String
  public let projectId: String
  public let filePath: String
  public let provider: String

  public init(id: String, projectId: String, filePath: String, provider: String) {
    self.id = id
    self.projectId = projectId
    self.filePath = filePath
    self.provider = provider
  }

  enum CodingKeys: String, CodingKey {
    case id
    case projectId = "project_id"
    case filePath = "file_path"
    case provider
  }
}

/// A summary returned from GET /api/v1/sync/pull.
/// Maps to the server's `PullSummary` Pydantic model.
public struct CloudPullSummary: Codable, Sendable {
  public let entryId: String
  public let presentForm: String
  public let pastForm: String
  public let disposition: String?

  public init(
    entryId: String,
    presentForm: String,
    pastForm: String,
    disposition: String? = nil
  ) {
    self.entryId = entryId
    self.presentForm = presentForm
    self.pastForm = pastForm
    self.disposition = disposition
  }

  enum CodingKeys: String, CodingKey {
    case entryId = "entry_id"
    case presentForm = "present_form"
    case pastForm = "past_form"
    case disposition
  }
}

/// Top-level response from GET /api/v1/sync/pull.
/// Maps to the server's `SyncPullResponse` Pydantic model.
///
/// Uses cursor-based pagination: pass `nextCursor` as the `since` query parameter
/// in subsequent requests. Continue pulling while `hasMore` is true.
public struct CloudPullResponse: Codable, Sendable {
  /// Entries from other devices since the requested cursor.
  public let entries: [CloudPullEntry]
  /// Projects referenced by the returned entries.
  public let projects: [CloudPullProject]
  /// Transcripts referenced by the returned entries.
  public let transcripts: [CloudPullTranscript]
  /// Summaries for the returned entries.
  public let summaries: [CloudPullSummary]
  /// Whether more entries are available beyond this page.
  public let hasMore: Bool
  /// Cursor value to use for the next pull request.
  public let nextCursor: Int
  /// Current server-side high-water mark sequence number.
  public let serverSequence: Int

  public init(
    entries: [CloudPullEntry],
    projects: [CloudPullProject] = [],
    transcripts: [CloudPullTranscript] = [],
    summaries: [CloudPullSummary] = [],
    hasMore: Bool = false,
    nextCursor: Int = 0,
    serverSequence: Int = 0
  ) {
    self.entries = entries
    self.projects = projects
    self.transcripts = transcripts
    self.summaries = summaries
    self.hasMore = hasMore
    self.nextCursor = nextCursor
    self.serverSequence = serverSequence
  }

  enum CodingKeys: String, CodingKey {
    case entries
    case projects
    case transcripts
    case summaries
    case hasMore = "has_more"
    case nextCursor = "next_cursor"
    case serverSequence = "server_sequence"
  }
}

// MARK: - Status Types

/// Response from GET /api/v1/sync/status.
/// Maps to the server's `SyncStatusResponse` Pydantic model.
public struct CloudActivePushSessionStatus: Codable, Sendable {
  public let syncSessionId: String
  public let phase: String
  public let entriesResolved: Int?
  public let entriesTotal: Int?
  public let progressPercent: Double?
  public let throughputEntriesPerMin: Double?
  public let etaSeconds: Int?
  public let checkpointSafe: Bool?
  public let completionState: String?
  public let needsAttentionCount: Int?
  public let lastBatchAt: String?

  enum CodingKeys: String, CodingKey {
    case syncSessionId = "sync_session_id"
    case phase
    case entriesResolved = "entries_resolved"
    case entriesTotal = "entries_total"
    case progressPercent = "progress_percent"
    case throughputEntriesPerMin = "throughput_entries_per_min"
    case etaSeconds = "eta_seconds"
    case checkpointSafe = "checkpoint_safe"
    case completionState = "completion_state"
    case needsAttentionCount = "needs_attention_count"
    case lastBatchAt = "last_batch_at"
  }
}

public struct CloudSyncStatus: Codable, Sendable {
  /// ISO 8601 timestamp of the last sync, or nil if never synced.
  public let lastSync: String?
  /// Total number of entries synced to the server.
  public let entriesSynced: Int
  /// Devices that have synced with this account.
  public let devices: [CloudDeviceInfo]
  /// Current server-side high-water mark sequence number.
  public let serverSequence: Int
  /// Number of active in-progress sessions (legacy field).
  public let pendingBatches: Int?
  /// Rich active push session projection for UI progress.
  public let activePushSession: CloudActivePushSessionStatus?

  public init(
    lastSync: String? = nil,
    entriesSynced: Int = 0,
    devices: [CloudDeviceInfo] = [],
    serverSequence: Int = 0,
    pendingBatches: Int? = nil,
    activePushSession: CloudActivePushSessionStatus? = nil
  ) {
    self.lastSync = lastSync
    self.entriesSynced = entriesSynced
    self.devices = devices
    self.serverSequence = serverSequence
    self.pendingBatches = pendingBatches
    self.activePushSession = activePushSession
  }

  enum CodingKeys: String, CodingKey {
    case lastSync = "last_sync"
    case entriesSynced = "entries_synced"
    case devices
    case serverSequence = "server_sequence"
    case pendingBatches = "pending_batches"
    case activePushSession = "active_push_session"
  }
}
