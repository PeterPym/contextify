import Foundation

// MARK: - Multi-Provider Parser

/// Parser that delegates to provider-specific implementations
public final class MultiProviderParser: TranscriptLineParser {
  public init() {}

  public func parse(
    line: String,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    sessionId: String?
  ) throws -> EntryInsert {
    switch provider {
    case "claude.code":
      return try ClaudeCodeLineParser().parse(
        line: line,
        lineNumber: lineNumber,
        transcriptId: transcriptId,
        projectId: projectId,
        provider: provider,
        sessionId: sessionId
      )
    case "codex.cli":
      return try CodexLineParser().parse(
        line: line,
        lineNumber: lineNumber,
        transcriptId: transcriptId,
        projectId: projectId,
        provider: provider,
        sessionId: sessionId
      )
    default:
      throw ParserError.unsupportedProvider(provider)
    }
  }
}

// MARK: - Claude Code Parser

public struct ClaudeCodeLineParser: TranscriptLineParser {
  public init() {}

  public func parse(
    line: String,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    sessionId: String?
  ) throws -> EntryInsert {
    guard let data = line.data(using: .utf8) else {
      throw ParserError.invalidFormat("Not valid UTF-8")
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ParserError.invalidJSON
    }

    // Required fields
    guard let uuid = json["uuid"] as? String else {
      throw ParserError.missingRequiredField("uuid")
    }

    guard let type = json["type"] as? String else {
      throw ParserError.missingRequiredField("type")
    }

    guard let timestampStr = json["timestamp"] as? String,
          let timestamp = parseISO8601(timestampStr) else {
      throw ParserError.missingRequiredField("timestamp")
    }

    // Skip meta messages (system/command wrappers)
    if (json["isMeta"] as? Bool) == true {
      throw ParserError.skipEntry
    }

    // Skip sidechain messages
    if (json["isSidechain"] as? Bool) == true {
      throw ParserError.skipEntry
    }

    // Extract content and determine if it should be displayed
    let content: String
    let hasTextContent: Bool
    if let message = json["message"] as? [String: Any] {
      let (extractedContent, hasText) = extractContentWithType(message["content"])
      content = extractedContent
      // User messages should ALWAYS be displayed in timeline, regardless of thinking metadata
      hasTextContent = (type == "user") ? true : hasText
      // Skip entries with empty content (tool_use blocks, etc.)
      guard !content.isEmpty else {
        throw ParserError.skipEntry
      }
    } else {
      throw ParserError.missingRequiredField("message.content")
    }

    // Optional fields
    let parentUuid = json["parentUuid"] as? String
    let gitBranch = json["gitBranch"] as? String
    let gitCommit = json["gitCommit"] as? String
    let cwd = json["cwd"] as? String
    let providerSessionId = json["sessionId"] as? String ?? sessionId

    // Map kind
    let kind = mapKind(type)

    // Compute content hash
    let contentSha256 = SHA256Utils.hash(content)

    return EntryInsert(
      id: uuid,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: providerSessionId,
      provider: provider,
      kind: kind,
      timestamp: timestamp,
      content: content,
      contentSha256: contentSha256,
      parentId: parentUuid,
      gitBranch: gitBranch,
      gitCommit: gitCommit,
      cwd: cwd,
      hasTextContent: hasTextContent
    )
  }

  /// Extract content from message and track if it contains displayable text
  /// Returns: (content: String, hasTextContent: Bool)
  /// - hasTextContent: true if content contains "text" blocks (displayable)
  ///                   false if only "thinking" blocks (hidden from timeline)
  private func extractContentWithType(_ content: Any?) -> (String, Bool) {
    if let str = content as? String {
      return (str, true)  // String content is displayable
    } else if let arr = content as? [[String: Any]] {
      var hasText = false
      let parts = arr.compactMap { block -> String? in
        if let text = block["text"] as? String {
          hasText = true
          return text
        } else if let thinking = block["thinking"] as? String {
          return thinking
        }
        return nil
      }
      return (parts.joined(separator: "\n"), hasText)
    } else {
      return ("", false)
    }
  }

  private func mapKind(_ type: String) -> String {
    switch type.lowercased() {
    case "user": return "user"
    case "assistant": return "assistant"
    case "system": return "system"
    default:
      // Unknown types default to system to avoid DB constraint violations
      return "system"
    }
  }

  private func parseISO8601(_ str: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
  }
}

// MARK: - Codex CLI Parser

public struct CodexLineParser: TranscriptLineParser {
  public init() {}

  public func parse(
    line: String,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    sessionId: String?
  ) throws -> EntryInsert {
    guard let data = line.data(using: .utf8) else {
      throw ParserError.invalidFormat("Not valid UTF-8")
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ParserError.invalidJSON
    }

    // Required fields
    guard let timestampStr = json["timestamp"] as? String,
          let timestamp = parseISO8601(timestampStr) else {
      throw ParserError.missingRequiredField("timestamp")
    }

    guard let payload = json["payload"] as? [String: Any] else {
      throw ParserError.missingRequiredField("payload")
    }

    guard let payloadType = payload["type"] as? String, payloadType == "message" else {
      throw ParserError.invalidFormat("Not a message record")
    }

    guard let role = payload["role"] as? String else {
      throw ParserError.missingRequiredField("payload.role")
    }

    // Extract content
    let content = extractContentArray(payload["content"])

    // Generate deterministic ID
    let entryId = EntryIDGenerator.generateEntryID(
      timestamp: timestamp,
      role: role,
      lineNumber: lineNumber,
      sessionID: sessionId ?? transcriptId
    )

    // Compute content hash
    let contentSha256 = SHA256Utils.hash(content)

    // TODO: Extract git context from session metadata if available
    let gitBranch: String? = nil
    let gitCommit: String? = nil
    let cwd: String? = nil

    return EntryInsert(
      id: entryId,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: sessionId,
      provider: provider,
      kind: role,
      timestamp: timestamp,
      content: content,
      contentSha256: contentSha256,
      parentId: nil,
      gitBranch: gitBranch,
      gitCommit: gitCommit,
      cwd: cwd
    )
  }

  private func extractContentArray(_ content: Any?) -> String {
    guard let arr = content as? [[String: Any]] else {
      return ""
    }

    return arr.compactMap { block in
      block["text"] as? String
    }.joined(separator: "\n")
  }

  private func parseISO8601(_ str: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
  }
}

// MARK: - Metadata Parser (v7)

/// Result of parsing metadata from a transcript line
public struct MetadataParseResult {
  public let fileSnapshot: FileSnapshot?
  public let trackedFiles: [TrackedFile]
  public let transcriptSummary: TranscriptSummary?
  public let systemEvent: SystemEvent?
  public let assistantUsage: AssistantUsage?

  public init(
    fileSnapshot: FileSnapshot? = nil,
    trackedFiles: [TrackedFile] = [],
    transcriptSummary: TranscriptSummary? = nil,
    systemEvent: SystemEvent? = nil,
    assistantUsage: AssistantUsage? = nil
  ) {
    self.fileSnapshot = fileSnapshot
    self.trackedFiles = trackedFiles
    self.transcriptSummary = transcriptSummary
    self.systemEvent = systemEvent
    self.assistantUsage = assistantUsage
  }

  public var hasMetadata: Bool {
    fileSnapshot != nil || !trackedFiles.isEmpty || transcriptSummary != nil || systemEvent != nil || assistantUsage != nil
  }
}

/// Protocol for extracting metadata from transcript lines
public protocol TranscriptMetadataParser {
  func parseMetadata(
    line: String,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    entryId: String?
  ) throws -> MetadataParseResult
}

// MARK: - Claude Code Metadata Parser

public struct ClaudeCodeMetadataParser: TranscriptMetadataParser {
  public init() {}

  public func parseMetadata(
    line: String,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    entryId: String?
  ) throws -> MetadataParseResult {
    guard let data = line.data(using: .utf8) else {
      throw ParserError.invalidFormat("Not valid UTF-8")
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ParserError.invalidJSON
    }

    guard let type = json["type"] as? String else {
      throw ParserError.missingRequiredField("type")
    }

    // UUID is required for user/assistant messages, but metadata records use messageId
    let uuid = json["uuid"] as? String ?? json["messageId"] as? String ?? ""

    // Timestamp is optional for some metadata records (e.g., file-history-snapshot uses snapshot.timestamp)
    let timestamp: Date
    if let timestampStr = json["timestamp"] as? String,
       let parsedTimestamp = parseISO8601(timestampStr) {
      timestamp = parsedTimestamp
    } else {
      timestamp = Date()  // Fallback for metadata records without top-level timestamp
    }

    let now = Int(Date().timeIntervalSince1970)

    // file-history-snapshot
    if type == "file-history-snapshot" {
      guard let isSnapshotUpdate = json["isSnapshotUpdate"] as? Bool,
            let snapshotDict = json["snapshot"] as? [String: Any],
            let timestampStr = snapshotDict["timestamp"] as? String else {
        throw ParserError.missingRequiredField("snapshot fields")
      }

      // Parse ISO8601 timestamp
      guard let snapshotDate = parseISO8601(timestampStr) else {
        throw ParserError.missingRequiredField("snapshot.timestamp (invalid ISO8601)")
      }
      let snapshotTimestamp = Int(snapshotDate.timeIntervalSince1970)

      let snapshot = FileSnapshot(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        messageId: uuid,
        snapshotTimestamp: snapshotTimestamp,
        isSnapshotUpdate: isSnapshotUpdate ? 1 : 0,
        createdAt: now
      )

      // Extract trackedFileBackups from snapshot dictionary
      var trackedFiles: [TrackedFile] = []
      if let fileBackups = snapshotDict["trackedFileBackups"] as? [String: [String: Any]] {
        for (filePath, fileInfo) in fileBackups {
          guard let version = fileInfo["version"] as? Int,
                let backupTimeStr = fileInfo["backupTime"] as? String,
                let backupDate = parseISO8601(backupTimeStr) else {
            continue  // Skip malformed entries
          }

          let trackedFile = TrackedFile(
            id: UUID().uuidString,
            snapshotId: snapshot.id,
            filePath: filePath,
            backupFilename: fileInfo["backupFileName"] as? String,
            version: version,
            backupTime: Int(backupDate.timeIntervalSince1970)
          )
          trackedFiles.append(trackedFile)
        }
      }

      return MetadataParseResult(fileSnapshot: snapshot, trackedFiles: trackedFiles)
    }

    // summary
    if type == "summary" {
      guard let summaryText = json["summary"] as? String else {
        throw ParserError.missingRequiredField("summary")
      }

      let summary = TranscriptSummary(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        summary: summaryText,
        leafUuid: json["leaf_uuid"] as? String,
        cwd: json["cwd"] as? String,
        createdAt: now
      )

      return MetadataParseResult(transcriptSummary: summary)
    }

    // system
    if type == "system" {
      guard let subtype = json["subtype"] as? String else {
        throw ParserError.missingRequiredField("subtype")
      }

      let level = json["level"] as? String ?? "info"
      let content: String?
      if let message = json["message"] as? [String: Any],
         let contentBlocks = message["content"] as? [[String: Any]] {
        content = contentBlocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
      } else {
        content = nil
      }

      let event = SystemEvent(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        timestamp: Int(timestamp.timeIntervalSince1970),
        subtype: subtype,
        level: level,
        content: content,
        error: json["error"] as? String,
        retryAttempt: json["retryAttempt"] as? Int,
        maxRetries: json["maxRetries"] as? Int,
        retryInMs: json["retryInMs"] as? Int,
        parentUuid: json["parentUuid"] as? String,
        logicalParentUuid: json["logicalParentUuid"] as? String,
        compactMetadata: json["compactMetadata"] as? String,
        createdAt: now
      )

      return MetadataParseResult(systemEvent: event)
    }

    // assistant usage
    if type == "assistant", let entryId = entryId {
      if let message = json["message"] as? [String: Any],
         let usage = message["usage"] as? [String: Any],
         let model = message["model"] as? String,
         let inputTokens = usage["input_tokens"] as? Int,
         let outputTokens = usage["output_tokens"] as? Int {

        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

        let assistantUsage = AssistantUsage(
          entryId: entryId,
          requestId: (message["id"] as? String) ?? entryId,  // Fallback to entryId if missing
          model: model,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          cacheCreationTokens: cacheCreation,
          cacheReadTokens: cacheRead,
          serviceTier: message["service_tier"] as? String,
          ephemeral5mTokens: usage["ephemeral_5m_tokens"] as? Int,
          ephemeral1hTokens: usage["ephemeral_1h_tokens"] as? Int
        )

        return MetadataParseResult(assistantUsage: assistantUsage)
      }
    }

    // No metadata found
    return MetadataParseResult()
  }

  private func parseISO8601(_ str: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
  }
}

// MARK: - Multi-Provider Metadata Parser

public struct MultiProviderMetadataParser: TranscriptMetadataParser {
  public init() {}

  public func parseMetadata(
    line: String,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    entryId: String?
  ) throws -> MetadataParseResult {
    switch provider {
    case "claude.code":
      return try ClaudeCodeMetadataParser().parseMetadata(
        line: line,
        lineNumber: lineNumber,
        transcriptId: transcriptId,
        projectId: projectId,
        provider: provider,
        entryId: entryId
      )
    case "codex.cli":
      // Codex CLI doesn't have metadata records yet
      return MetadataParseResult()
    default:
      throw ParserError.unsupportedProvider(provider)
    }
  }
}
