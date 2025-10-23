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
      hasTextContent = hasText
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
