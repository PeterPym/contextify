import Foundation
import OSLog
import os.lock

private let parserLog = Logger(subsystem: "dev.contextify", category: "TranscriptParser")
private let metadataRecordTypes: Set<String> = [
  "file-history-snapshot",
  "summary",
  "timeline-state",
  "queue-operation-result"
]

// MARK: - Shared ISO8601 Date Formatters (Performance)

/// Cached ISO8601 formatters to avoid expensive re-initialization on every parse.
/// Creating formatters is ~500x slower than reusing them due to ICU locale/pattern loading.
///
/// Thread safety: These formatters are immutable after initialization (read-only usage).
/// ISO8601DateFormatter.date(from:) is thread-safe for concurrent reads.
nonisolated(unsafe) private let iso8601FormatterWithFractional: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()

nonisolated(unsafe) private let iso8601FormatterStandard = ISO8601DateFormatter()

// MARK: - Multi-Provider Parser

/// Parser that delegates to provider-specific implementations
public final class MultiProviderParser: TranscriptLineParser {
  private let claudeParser: ClaudeCodeLineParser
  private let codexParser: CodexLineParser

  public init(
    claudeParser: ClaudeCodeLineParser = ClaudeCodeLineParser(),
    codexParser: CodexLineParser = CodexLineParser()
  ) {
    self.claudeParser = claudeParser
    self.codexParser = codexParser
  }

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
      return try claudeParser.parse(
        line: line,
        lineNumber: lineNumber,
        transcriptId: transcriptId,
        projectId: projectId,
        provider: provider,
        sessionId: sessionId
      )
    case "codex.cli":
      return try codexParser.parse(
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

public final class ClaudeCodeLineParser: TranscriptLineParser {
  private let trackerLock = OSAllocatedUnfairLock(initialState: ToolCallTrackerState())

  public init() {}

  public func parse(
    line: String,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    sessionId: String?
  ) throws -> EntryInsert {
    // Convert to Data for JSON parsing (already validated as UTF-8 by HooverEngine)
    guard let data = line.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ParserError.invalidJSON
    }

    // Required fields - check type first
    guard let type = json["type"] as? String else {
      parserLog.warning("[PARSER-WARN] Missing type field line=\(lineNumber, privacy: .public) transcript=\(transcriptId, privacy: .public) – skipping entry")
      throw ParserError.skipEntry
    }

    // Handle queue-operation records with enqueue operation (user messages sent while Claude was working)
    if type == "queue-operation" {
      guard let operation = json["operation"] as? String, operation == "enqueue" else {
        throw ParserError.skipEntry  // Skip "remove", "popAll", and "dequeue" operations for now
      }

      // Feature flag: skip creating synthetic queue entries if disabled
      guard MonitorConfig.showQueuedMessages else {
        throw ParserError.skipEntry
      }

      guard let queueContent = json["content"] as? String, !queueContent.isEmpty else {
        throw ParserError.skipEntry  // Skip if no content
      }
      guard let timestampStr = json["timestamp"] as? String,
            let timestamp = parseISO8601(timestampStr) else {
        throw ParserError.skipEntry
      }
      // Generate stable UUID from timestamp and content for queue-operation entries
      let queueUuid = "queue-\(abs(timestampStr.hashValue))-\(abs(queueContent.hashValue))"
      let contentSha256 = SHA256Utils.hash(queueContent)
      let providerSessionId = json["sessionId"] as? String ?? sessionId

      parserLog.info("[QUEUE-ENQUEUE] Creating synthetic entry id=\(queueUuid, privacy: .public) ts=\(timestampStr, privacy: .public) content=\"\(String(queueContent.prefix(40)), privacy: .public)\"")

      return EntryInsert(
        id: queueUuid,
        transcriptId: transcriptId,
        projectId: projectId,
        sessionId: providerSessionId,
        provider: provider,
        kind: "user",
        timestamp: timestamp,
        content: queueContent,
        contentSha256: contentSha256,
        parentId: nil,
        gitBranch: json["gitBranch"] as? String,
        gitCommit: nil,
        cwd: json["cwd"] as? String,
        hasTextContent: true,
        isQueued: true  // Mark as queued - UI will show "QUEUED" badge
      )
    }

    // Skip structural metadata records (no conversation content)
    if metadataRecordTypes.contains(type) {
      throw ParserError.skipEntry
    }

    guard let uuid = json["uuid"] as? String else {
      throw ParserError.missingRequiredField("uuid")
    }

    guard let timestampStr = json["timestamp"] as? String,
          let timestamp = parseISO8601(timestampStr) else {
      throw ParserError.missingRequiredField("timestamp")
    }

    let isMetaMessage = (json["isMeta"] as? Bool) == true

    let isSidechain = (json["isSidechain"] as? Bool) == true
    let agentId = json["agentId"] as? String

    // Extract content and determine if it should be displayed
    var content: String = ""
    var hasTextContent: Bool = false
    var toolInvocations: [ToolInvocationInsert] = []
    var toolResultData: [ToolResultData] = []
    var toolResultTextParts: [String] = []
    if var message = json["message"] as? [String: Any] {
      let messageId = message["id"] as? String

      if type == "assistant",
         let msgId = messageId,
         let buffered = takeBufferedAssistantMessage(transcriptId: transcriptId, messageId: msgId) {
        if let bufferedBlocks = decodeBufferedContent(buffered) {
          if let currentBlocks = message["content"] as? [[String: Any]] {
            message["content"] = bufferedBlocks + currentBlocks
          } else {
            message["content"] = bufferedBlocks
          }
          if message["stop_reason"] == nil {
            message["stop_reason"] = buffered.stopReason
          }
        }
      }

      let shouldBuffer = try validateMessageIntegrity(
        message: message,
        type: type,
        uuid: uuid,
        lineNumber: lineNumber,
        transcriptId: transcriptId,
        messageId: messageId
      )

      if shouldBuffer {
        if type == "assistant",
           let msgId = messageId,
           let blocks = message["content"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: blocks) {
          bufferAssistantMessage(
            transcriptId: transcriptId,
            messageId: msgId,
            uuid: uuid,
            stopReason: message["stop_reason"] as? String,
            contentData: data
          )
        } else if type == "assistant" {
          parserLog.info("[PARSER-INFO] stop_reason mismatch line=\(lineNumber, privacy: .public) uuid=\(uuid, privacy: .public) message_id=none – coercing to end_turn")
        }
        throw ParserError.skipEntry
      }

      if let contentBlocks = message["content"] as? [[String: Any]] {
        if type == "assistant" {
          for block in contentBlocks where block["type"] as? String == "tool_use" {
            let toolName = block["name"] as? String ?? "unknown"
            let toolKey = extractToolKey(from: block)
            let toolUseId = block["id"] as? String
            let isContextify = isContextifyTool(block)
            let metadataJson = encodeToolMetadata(block["input"])

            toolInvocations.append(ToolInvocationInsert(
              toolName: toolName,
              toolKey: toolKey,
              toolUseId: toolUseId,
              isContextify: isContextify,
              startedAt: timestamp,
              metadataJson: metadataJson
            ))
          }
        }

        if type == "user" {
          for block in contentBlocks where block["type"] as? String == "tool_result" {
            let toolUseId = block["tool_use_id"] as? String
            let toolUseResult = json["toolUseResult"] as? [String: Any]
            let resultAgentId = toolUseResult?["agentId"] as? String
            let status = toolUseResult?["status"] as? String

            toolResultData.append(ToolResultData(
              toolUseId: toolUseId,
              entryId: uuid,
              agentId: resultAgentId,
              status: status,
              timestamp: timestamp
            ))

            if let toolUseId,
               let info = toolUseInfo(for: toolUseId, transcriptId: transcriptId),
               ["Skill", "Task"].contains(info.toolName),
               let toolText = extractToolResultText(from: block),
               !toolText.isEmpty {
              toolResultTextParts.append(toolText)
            }
          }
        }
      }

      let (extractedContent, hasText) = extractContentWithType(message["content"])
      content = extractedContent
      let shouldHideShellOutput = type == "user" && containsShellOutput(content)
      hasTextContent = (type == "user") ? !shouldHideShellOutput : hasText

      // For Task tool invocations: extract prompt as meaningful content
      // This makes agent-spawn entries visible and summarizable in the timeline
      if type == "assistant" && !hasText,
         let taskInvocation = toolInvocations.first(where: { $0.toolName == "Task" }),
         let contentBlocks = message["content"] as? [[String: Any]],
         let taskBlock = contentBlocks.first(where: {
           $0["type"] as? String == "tool_use" && $0["name"] as? String == "Task"
         }),
         let input = taskBlock["input"] as? [String: Any],
         let prompt = input["prompt"] as? String,
         !prompt.isEmpty {
        // Extract subagent type and model for display context
        let subagentType = taskInvocation.toolKey ?? "agent"
        let model = input["model"] as? String
        let modelSuffix = model.map { " (\($0))" } ?? ""

        // Use first line of prompt as summary, with agent context prefix
        let firstLine = prompt.components(separatedBy: .newlines)
          .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? prompt
        let truncated = String(firstLine.prefix(300))
        content = "[\(subagentType)\(modelSuffix)] \(truncated)"
        hasTextContent = true
      }

      if content.isEmpty && !toolResultTextParts.isEmpty {
        content = toolResultTextParts.joined(separator: "\n")
        hasTextContent = true
      }
      if content.isEmpty && !toolResultData.isEmpty {
        content = "[Tool Result]"
        hasTextContent = false
      }
      // Skip entries with empty content (tool_use blocks, etc.)
      guard !content.isEmpty else {
        throw ParserError.skipEntry
      }

      // Skip empty local-command-stdout wrappers (structural artifacts with no semantic value)
      if content == "<local-command-stdout></local-command-stdout>" {
        throw ParserError.skipEntry
      }

      if isMetaMessage && !containsCommandContent(content) {
        throw ParserError.skipEntry
      }
    } else {
      parserLog.warning("[PARSER-WARN] Missing message.content line=\(lineNumber, privacy: .public) uuid=\(uuid, privacy: .public) – skipping entry")
      throw ParserError.skipEntry
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
      hasTextContent: hasTextContent,
      isSidechain: isSidechain,
      agentId: agentId,
      toolInvocations: toolInvocations,
      toolResultData: toolResultData
    )
  }

  /// Extract content from message and track if it contains displayable text
  /// Returns: (content: String, hasTextContent: Bool)
  /// - hasTextContent: true if content contains "text" blocks (displayable)
  ///                   false if only "thinking" or "tool_use" blocks (hidden from timeline)
  private func extractContentWithType(_ content: Any?) -> (String, Bool) {
    if let str = content as? String {
      return (str, true)  // String content is displayable
    }
    guard let arr = content as? [[String: Any]] else {
      return ("", false)
    }

    var textParts: [String] = []
    var thinkingParts: [String] = []
    var toolParts: [String] = []

    for block in arr {
      // Prefer explicit type when available, but tolerate missing type (backwards compat)
      let blockType = block["type"] as? String

      // Text blocks (displayable)
      if blockType == "text" || (blockType == nil && block["text"] != nil) {
        if let text = block["text"] as? String, !text.isEmpty {
          textParts.append(text)
        }
        continue
      }

      // Thinking blocks (internal reasoning)
      if blockType == "thinking" || (blockType == nil && block["thinking"] != nil) {
        if let thinking = block["thinking"] as? String, !thinking.isEmpty {
          thinkingParts.append(thinking)
        }
        continue
      }

      // Tool use blocks (NEW - searchable markers)
      // Backwards compat: detect tool blocks even without explicit type field
      let hasToolShape = block["name"] != nil && block["input"] != nil &&
                         block["text"] == nil && block["thinking"] == nil
      if blockType == "tool_use" || (blockType == nil && hasToolShape) {
        if let name = block["name"] as? String, !name.isEmpty {
          toolParts.append("[Tool: \(name)]")
        }
        continue
      }

      // Tool result blocks (permission dialogs)
      if blockType == "tool_result",
         let isError = block["is_error"] as? Bool, isError,
         let toolResultContent = block["content"] as? String,
         let markerRange = toolResultContent.range(of: "To tell you how to proceed, the user said:\n") {
        let customText = String(toolResultContent[markerRange.upperBound...])
        if !customText.isEmpty {
          textParts.append(customText)  // User text is displayable
        }
        continue
      }
    }

    let hasText = !textParts.isEmpty

    // Q8 noise filter: only include tool markers when there was no normal text
    let parts = hasText
      ? (textParts + thinkingParts)
      : (thinkingParts + toolParts)

    return (parts.joined(separator: "\n"), hasText)
  }

  private func containsCommandContent(_ text: String) -> Bool {
    text.contains("<command-name>") || text.contains("/clear")
  }

  private func containsShellOutput(_ text: String) -> Bool {
    text.contains("<bash-stdout>") || text.contains("<bash-stderr>")
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
    // Use cached formatters to avoid expensive ICU initialization on every call
    return iso8601FormatterWithFractional.date(from: str) ?? iso8601FormatterStandard.date(from: str)
  }

  /// Validate message integrity to detect Claude Code Web corruption patterns
  ///
  /// **Background:** Claude Code Web (new product) can create corrupted transcripts when
  /// "teleporting" conversations to CLI. Common corruption patterns:
  ///
  /// 1. **Orphaned tool_result**: User message contains tool_result but no preceding tool_use
  /// 2. **stop_reason mismatch**: Assistant has stop_reason="tool_use" but no tool_use blocks
  ///
  /// These corruptions cause API 400 errors and prevent session continuation.
  ///
  /// - Parameters:
  ///   - message: The message dictionary from JSON
  ///   - type: Message type ("user" or "assistant")
  ///   - uuid: Message UUID for error reporting
  ///   - lineNumber: Line number in transcript for error reporting
  /// - Throws: ParserError.corruptedRecord if corruption detected
private func validateMessageIntegrity(
    message: [String: Any],
    type: String,
    uuid: String,
    lineNumber: Int,
    transcriptId: String,
    messageId: String?
  ) throws -> Bool {
    guard let contentBlocks = message["content"] as? [[String: Any]] else {
      // String content is always valid
      return false
    }

    resetTrackerIfNeeded(transcriptId: transcriptId, lineNumber: lineNumber)

    // VALIDATION 1: Check for orphaned tool_result (user messages)
    if type == "user" {
      var validatedCount = 0
      var missingIds: [String] = []

      for block in contentBlocks {
        if block["type"] as? String == "tool_result",
           let toolUseId = block["tool_use_id"] as? String {
          if consumeToolUse(id: toolUseId, transcriptId: transcriptId) {
            validatedCount += 1
          } else {
            missingIds.append(toolUseId)
          }
        }
      }

      if !missingIds.isEmpty {
        recordToolResultMissing(count: missingIds.count)
        let missingList = missingIds.joined(separator: ", ")
        parserLog.warning("[PARSER-WARN] Orphaned tool_result detected line=\(lineNumber, privacy: .public) uuid=\(uuid, privacy: .public) tool_use_id=\(missingList, privacy: .public) – continuing without throwing")
        return false
      }

      if validatedCount > 0 {
        recordToolResultValidated(count: validatedCount)
        return false
      }
    }

    // VALIDATION 2: Check stop_reason/content mismatch (assistant messages)
    if type == "assistant" {
      let stopReason = message["stop_reason"] as? String
      let hasToolUse = contentBlocks.contains { block in
        block["type"] as? String == "tool_use"
      }

      recordToolUses(in: contentBlocks, transcriptId: transcriptId)

      if stopReason == "tool_use" && !hasToolUse {
        recordStopReasonCoercion()
        if messageId != nil {
          return true
        } else {
          let contentTypes = contentBlocks.compactMap { $0["type"] as? String }.joined(separator: ", ")
          parserLog.info("[PARSER-INFO] stop_reason mismatch line=\(lineNumber, privacy: .public) uuid=\(uuid, privacy: .public) message_id=none stop_reason=tool_use content=[\(contentTypes)] – coercing to end_turn")
          return false
        }
      }
    }

    // VALIDATION 3: Check for invalid content block structures
    for block in contentBlocks {
      // Backwards compat: 'type' field is optional (can infer from shape)
      if let blockType = block["type"] as? String {
        // Validate tool_result has required fields
        if blockType == "tool_result" {
          guard block["tool_use_id"] is String else {
            let details = """
              Line \(lineNumber): Invalid tool_result block (uuid=\(uuid), missing tool_use_id).
              tool_result blocks must have a tool_use_id field.
              """
            throw ParserError.corruptedRecord(.invalidContentBlock, details: details)
          }
        }
      }
    }

    return false
  }
}

private func extractToolKey(from block: [String: Any]) -> String? {
  guard let name = block["name"] as? String,
        let input = block["input"] as? [String: Any] else {
    return nil
  }

  switch name {
  case "Skill":
    return input["skill"] as? String
  case "Task":
    return input["subagent_type"] as? String
  default:
    return nil
  }
}

private func isContextifyTool(_ block: [String: Any]) -> Bool {
  guard let name = block["name"] as? String,
        let input = block["input"] as? [String: Any] else {
    return false
  }

  switch name {
  case "Skill":
    return input["skill"] as? String == "query:contextify-reinject"
  case "Task":
    return input["subagent_type"] as? String == "query:contextify-researcher"
  default:
    return false
  }
}

private func encodeToolMetadata(_ input: Any?) -> String? {
  guard let input else { return nil }
  guard JSONSerialization.isValidJSONObject(input),
        let data = try? JSONSerialization.data(withJSONObject: input),
        let json = String(data: data, encoding: .utf8) else {
    return nil
  }
  return json
}

private func extractToolResultText(from block: [String: Any]) -> String? {
  if let text = block["content"] as? String {
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  if let items = block["content"] as? [[String: Any]] {
    let parts = items.compactMap { item -> String? in
      guard item["type"] as? String == "text",
            let text = item["text"] as? String,
            !text.isEmpty else { return nil }
      return text
    }
    if parts.isEmpty { return nil }
    return parts.joined(separator: "\n")
  }
  return nil
}

// MARK: - Tool Call Tracking

private struct ToolCallTrackerState {
  var toolUseBuffers: [String: ToolUseBuffer] = [:]
  var assistantBuffers: [String: [String: BufferedAssistantMessage]] = [:]
  var toolUseInfo: [String: [String: ToolUseInfo]] = [:]
  var metrics = ParserMetrics()
}

private struct ToolUseInfo: Sendable {
  let toolName: String
  let toolKey: String?
}

private struct BufferedAssistantMessage: Sendable {
  let messageId: String
  let uuid: String
  let stopReason: String?
  let contentData: Data
}

private struct ToolUseBuffer {
  private var ids: Set<String> = []
  private var order: [String] = []
  private static let maxTrackedIds = 512

  mutating func reset() {
    ids.removeAll(keepingCapacity: true)
    order.removeAll(keepingCapacity: true)
  }

  mutating func insert(_ id: String) {
    guard ids.insert(id).inserted else { return }
    order.append(id)
    pruneIfNeeded()
  }

  mutating func consume(_ id: String) -> Bool {
    guard ids.remove(id) != nil else { return false }
    if let idx = order.firstIndex(of: id) {
      order.remove(at: idx)
    }
    return true
  }

  private mutating func pruneIfNeeded() {
    while order.count > Self.maxTrackedIds, let id = order.first {
      order.removeFirst()
      ids.remove(id)
    }
  }
}

private struct ParserMetrics {
  var toolResultValidated: Int = 0
  var toolResultMissing: Int = 0
  var stopReasonCoerced: Int = 0
}

private extension ClaudeCodeLineParser {
  func resetTrackerIfNeeded(transcriptId: String, lineNumber: Int) {
    guard lineNumber == 1 else { return }
    trackerLock.withLock { state in
      var buffer = state.toolUseBuffers[transcriptId, default: ToolUseBuffer()]
      buffer.reset()
      state.toolUseBuffers[transcriptId] = buffer
      state.assistantBuffers[transcriptId]?.removeAll()
      state.toolUseInfo[transcriptId]?.removeAll()
    }
  }

  func recordToolUses(in blocks: [[String: Any]], transcriptId: String) {
    let toolUses: [(id: String, name: String, toolKey: String?)] = blocks.compactMap { block -> (String, String, String?)? in
      guard block["type"] as? String == "tool_use",
            let id = block["id"] as? String,
            let name = block["name"] as? String else { return nil }
      let toolKey = extractToolKey(from: block)
      return (id, name, toolKey)
    }
    guard !toolUses.isEmpty else { return }

    trackerLock.withLock { state in
      var buffer = state.toolUseBuffers[transcriptId, default: ToolUseBuffer()]
      for toolUse in toolUses {
        buffer.insert(toolUse.id)
      }
      state.toolUseBuffers[transcriptId] = buffer

      var infoMap = state.toolUseInfo[transcriptId] ?? [:]
      for toolUse in toolUses {
        infoMap[toolUse.id] = ToolUseInfo(toolName: toolUse.name, toolKey: toolUse.toolKey)
      }
      state.toolUseInfo[transcriptId] = infoMap
    }
  }

  func consumeToolUse(id: String, transcriptId: String) -> Bool {
    trackerLock.withLock { state in
      var buffer = state.toolUseBuffers[transcriptId, default: ToolUseBuffer()]
      let consumed = buffer.consume(id)
      state.toolUseBuffers[transcriptId] = buffer
      return consumed
    }
  }

  func toolUseInfo(for toolUseId: String, transcriptId: String) -> ToolUseInfo? {
    trackerLock.withLock { state in
      state.toolUseInfo[transcriptId]?[toolUseId]
    }
  }

  func recordToolResultValidated(count: Int) {
    trackerLock.withLock { state in
      state.metrics.toolResultValidated += count
    }
  }

  func recordToolResultMissing(count: Int) {
    trackerLock.withLock { state in
      state.metrics.toolResultMissing += count
    }
  }

  func recordStopReasonCoercion() {
    trackerLock.withLock { state in
      state.metrics.stopReasonCoerced += 1
    }
  }

  func bufferAssistantMessage(
    transcriptId: String,
    messageId: String,
    uuid: String,
    stopReason: String?,
    contentData: Data
  ) {
    trackerLock.withLock { state in
      var transcriptBuffers = state.assistantBuffers[transcriptId] ?? [:]
      transcriptBuffers[messageId] = BufferedAssistantMessage(
        messageId: messageId,
        uuid: uuid,
        stopReason: stopReason,
        contentData: contentData
      )
      state.assistantBuffers[transcriptId] = transcriptBuffers
    }
  }

  func takeBufferedAssistantMessage(
    transcriptId: String,
    messageId: String
  ) -> BufferedAssistantMessage? {
    trackerLock.withLock { state in
      guard var transcriptBuffers = state.assistantBuffers[transcriptId],
            let buffered = transcriptBuffers.removeValue(forKey: messageId) else {
        return nil
      }
      state.assistantBuffers[transcriptId] = transcriptBuffers
      return buffered
    }
  }

  func decodeBufferedContent(_ message: BufferedAssistantMessage) -> [[String: Any]]? {
    guard let json = try? JSONSerialization.jsonObject(with: message.contentData) as? [[String: Any]] else {
      parserLog.warning("[PARSER-WARN] Failed to decode buffered assistant message id=\(message.messageId, privacy: .public)")
      return nil
    }
    return json
  }
}

#if DEBUG
extension ClaudeCodeLineParser {
  struct TelemetrySnapshot: Equatable {
    let toolResultValidated: Int
    let toolResultMissing: Int
    let stopReasonCoerced: Int
  }

  func debug_telemetrySnapshot() -> TelemetrySnapshot {
    trackerLock.withLock { state in
      TelemetrySnapshot(
        toolResultValidated: state.metrics.toolResultValidated,
        toolResultMissing: state.metrics.toolResultMissing,
        stopReasonCoerced: state.metrics.stopReasonCoerced
      )
    }
  }

  func debug_resetTelemetry() {
    trackerLock.withLock { state in
      state.metrics = ParserMetrics()
    }
  }
}
#endif

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
    // Convert to Data for JSON parsing (already validated as UTF-8 by HooverEngine)
    guard let data = line.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ParserError.invalidJSON
    }

    // Required fields
    guard let timestampStr = json["timestamp"] as? String,
          let timestamp = parseISO8601(timestampStr) else {
      parserLog.warning("[PARSER-WARN] Codex line missing timestamp line=\(lineNumber, privacy: .public) transcript=\(transcriptId, privacy: .public) – skipping entry")
      throw ParserError.skipEntry
    }

    guard let type = json["type"] as? String else {
      parserLog.warning("[PARSER-WARN] Codex line missing type line=\(lineNumber, privacy: .public) transcript=\(transcriptId, privacy: .public)")
      throw ParserError.skipEntry
    }

    guard let payload = json["payload"] as? [String: Any] else {
      parserLog.warning("[PARSER-WARN] Codex line missing payload line=\(lineNumber, privacy: .public) transcript=\(transcriptId, privacy: .public)")
      throw ParserError.skipEntry
    }

    guard let payloadType = payload["type"] as? String else {
      throw ParserError.skipEntry
    }

    // Handle event_msg records - these contain real user messages
    // System-injected messages (AGENTS.md + environment) appear as response_item
    // but do NOT have companion event_msg records
    if type == "event_msg" && payloadType == "user_message" {
      return try parseUserMessageFromEventMsg(
        payload: payload,
        timestamp: timestamp,
        lineNumber: lineNumber,
        transcriptId: transcriptId,
        projectId: projectId,
        provider: provider,
        sessionId: sessionId
      )
    }

    // Handle response_item records
    if type == "response_item" && payloadType == "message" {
      guard let role = payload["role"] as? String else {
        parserLog.warning("[PARSER-WARN] Codex message missing role line=\(lineNumber, privacy: .public) transcript=\(transcriptId, privacy: .public)")
        throw ParserError.skipEntry
      }

      // Skip user response_items - we parse user messages from event_msg records instead
      // This automatically filters out system-injected messages (AGENTS.md + environment)
      if role == "user" {
        throw ParserError.skipEntry
      }

      // Process assistant messages from response_item
      if role == "assistant" {
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
    }

    // Skip all other record types
    throw ParserError.skipEntry
  }

  /// Parse user message from event_msg record
  /// event_msg records with type=user_message contain real user input
  /// System-injected messages do NOT have event_msg records
  private func parseUserMessageFromEventMsg(
    payload: [String: Any],
    timestamp: Date,
    lineNumber: Int,
    transcriptId: String,
    projectId: String,
    provider: String,
    sessionId: String?
  ) throws -> EntryInsert {
    guard let message = payload["message"] as? String else {
      parserLog.warning("[PARSER-WARN] Codex event_msg missing message line=\(lineNumber, privacy: .public) transcript=\(transcriptId, privacy: .public)")
      throw ParserError.skipEntry
    }

    // Generate deterministic ID
    let entryId = EntryIDGenerator.generateEntryID(
      timestamp: timestamp,
      role: "user",
      lineNumber: lineNumber,
      sessionID: sessionId ?? transcriptId
    )

    // Compute content hash
    let contentSha256 = SHA256Utils.hash(message)

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
      kind: "user",
      timestamp: timestamp,
      content: message,
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
    // Use cached formatters to avoid expensive ICU initialization on every call
    return iso8601FormatterWithFractional.date(from: str) ?? iso8601FormatterStandard.date(from: str)
  }
}

// MARK: - Metadata Parser (v7)

/// Queue operation for clearing is_queued flags
public struct QueueOperation {
  public enum Kind: String {
    case remove   // clear one or more queued messages by content hash
    case popAll   // clear entire queue for a session
    case dequeue  // clear entire queue for a session
  }

  public let kind: Kind
  public let transcriptId: String
  public let sessionId: String
  public let contentSha256: String?  // non-nil for .remove; nil for .popAll/.dequeue
  public let timestamp: Date

  public init(
    kind: Kind,
    transcriptId: String,
    sessionId: String,
    contentSha256: String?,
    timestamp: Date
  ) {
    self.kind = kind
    self.transcriptId = transcriptId
    self.sessionId = sessionId
    self.contentSha256 = contentSha256
    self.timestamp = timestamp
  }
}

/// Result of parsing metadata from a transcript line
public struct MetadataParseResult {
  public let fileSnapshot: FileSnapshot?
  public let trackedFiles: [TrackedFile]
  public let transcriptSummary: TranscriptSummary?
  public let systemEvent: SystemEvent?
  public let assistantUsage: AssistantUsage?
  public let queueOperations: [QueueOperation]

  public init(
    fileSnapshot: FileSnapshot? = nil,
    trackedFiles: [TrackedFile] = [],
    transcriptSummary: TranscriptSummary? = nil,
    systemEvent: SystemEvent? = nil,
    assistantUsage: AssistantUsage? = nil,
    queueOperations: [QueueOperation] = []
  ) {
    self.fileSnapshot = fileSnapshot
    self.trackedFiles = trackedFiles
    self.transcriptSummary = transcriptSummary
    self.systemEvent = systemEvent
    self.assistantUsage = assistantUsage
    self.queueOperations = queueOperations
  }

  public var hasMetadata: Bool {
    fileSnapshot != nil || !trackedFiles.isEmpty || transcriptSummary != nil || systemEvent != nil || assistantUsage != nil || !queueOperations.isEmpty
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

    // queue-operation metadata (remove/popAll/dequeue)
    if type == "queue-operation" {
      guard let opString = json["operation"] as? String else {
        throw ParserError.missingRequiredField("operation")
      }

      // Ignore enqueue here; enqueue is handled in ClaudeCodeLineParser.parse
      if opString == "enqueue" {
        return MetadataParseResult()
      }

      guard let kind = QueueOperation.Kind(rawValue: opString) else {
        // Unknown operation type; treat as no-op metadata
        return MetadataParseResult()
      }

      guard let sessionId = json["sessionId"] as? String, !sessionId.isEmpty else {
        parserLog.warning("[QUEUE-OP] queue-operation \(opString, privacy: .public) missing sessionId; skipping line=\(lineNumber, privacy: .public) transcript=\(transcriptId, privacy: .public)")
        return MetadataParseResult()
      }

      var contentSha256: String? = nil
      switch kind {
      case .remove:
        // Claude Code's remove doesn't include content; use FIFO matching in HooverEngine
        contentSha256 = nil

      case .popAll, .dequeue:
        // Full-queue clear for the session; no per-message content hash needed
        contentSha256 = nil
      }

      let op = QueueOperation(
        kind: kind,
        transcriptId: transcriptId,
        sessionId: sessionId,
        contentSha256: contentSha256,
        timestamp: timestamp
      )

      return MetadataParseResult(queueOperations: [op])
    }

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
    // Use cached formatters to avoid expensive ICU initialization on every call
    return iso8601FormatterWithFractional.date(from: str) ?? iso8601FormatterStandard.date(from: str)
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
