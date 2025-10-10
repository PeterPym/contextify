import Foundation
import OSLog

/// Parses JSONL transcript files into Exchange structs
nonisolated struct TranscriptParser: Sendable {
  private let log = Logger(subsystem: "dev.contextify.metadata", category: "TranscriptParser")
  private let maxMessageLength = 2000
  private let maxCorruptionRate = 0.10 // 10%

  enum ParseError: Error, LocalizedError {
    case corruptionThresholdExceeded(rate: Double)
    case fileReadError(underlying: Error)
    case invalidFormat(String)

    var errorDescription: String? {
      switch self {
      case .corruptionThresholdExceeded(let rate):
        return "Too many corrupted lines (\(Int(rate * 100))% > 10%)"
      case .fileReadError(let error):
        return "Failed to read file: \(error.localizedDescription)"
      case .invalidFormat(let message):
        return "Invalid format: \(message)"
      }
    }
  }

  /// Parse exchanges from a transcript file URL
  func parseExchanges(url: URL) throws -> [Exchange] {
    log.info("Parsing transcript: \(url.lastPathComponent, privacy: .public)")

    let content: String
    do {
      content = try String(contentsOf: url, encoding: .utf8)
    } catch {
      throw ParseError.fileReadError(underlying: error)
    }

    let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard !lines.isEmpty else {
      log.info("Empty transcript, returning empty array")
      return []
    }

    var exchanges: [Exchange] = []
    var corruptedCount = 0

    for (index, line) in lines.enumerated() {
      guard let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        corruptedCount += 1
        log.warning("Failed to parse line \(index + 1)")
        continue
      }

      // Skip non-message types
      guard let type = json["type"] as? String else {
        continue
      }

      // Parse timestamp
      guard let timestampStr = json["timestamp"] as? String,
            let timestamp = parseTimestamp(timestampStr) else {
        continue
      }

      // Process based on type
      switch type {
      case "user":
        if let exchange = parseUserMessage(json, timestamp: timestamp) {
          exchanges.append(exchange)
        }
      case "assistant":
        if let parsedExchanges = parseAssistantMessage(json, timestamp: timestamp) {
          exchanges.append(contentsOf: parsedExchanges)
        }
      case "response_item":
        // Codex format: extract payload
        if let parsedExchanges = parseCodexResponseItem(json, timestamp: timestamp) {
          exchanges.append(contentsOf: parsedExchanges)
        }
      case "message":
        // Older Codex format: direct message type
        if let exchange = parseCodexMessage(json, timestamp: timestamp) {
          exchanges.append(exchange)
        }
      default:
        // Skip other types (session_meta, tool_use, etc.)
        continue
      }
    }

    // Check corruption rate
    let corruptionRate = Double(corruptedCount) / Double(lines.count)
    if corruptionRate > maxCorruptionRate {
      throw ParseError.corruptionThresholdExceeded(rate: corruptionRate)
    }

    log.info("Parsed \(exchanges.count) exchanges from \(lines.count) lines (corrupted: \(corruptedCount))")
    return exchanges
  }

  // MARK: - Private Parsing Methods

  private func parseUserMessage(_ json: [String: Any], timestamp: Date) -> Exchange? {
    guard let message = json["message"] as? [String: Any] else {
      return nil
    }

    // Skip meta messages
    if (json["isMeta"] as? Bool) == true {
      return nil
    }

    // Skip sidechain messages
    if (json["isSidechain"] as? Bool) == true {
      return nil
    }

    // Extract text from various content formats
    guard let text = extractTextFromContent(message["content"]) else {
      return nil
    }

    // Skip command wrappers
    if text.contains("<command-name>") || text.contains("<local-command-stdout>") {
      return nil
    }

    let sanitized = sanitizeText(text)
    guard !sanitized.isEmpty else {
      return nil
    }

    return Exchange(role: .user, text: sanitized, timestamp: timestamp)
  }

  private func parseAssistantMessage(_ json: [String: Any], timestamp: Date) -> [Exchange]? {
    guard let message = json["message"] as? [String: Any],
          let contentBlocks = message["content"] as? [[String: Any]] else {
      return nil
    }

    var exchanges: [Exchange] = []

    for block in contentBlocks {
      guard let blockType = block["type"] as? String else {
        continue
      }

      // Only extract text blocks, skip tool_use
      if blockType == "text",
         let text = block["text"] as? String {
        let sanitized = sanitizeText(text)
        if !sanitized.isEmpty {
          exchanges.append(Exchange(role: .assistant, text: sanitized, timestamp: timestamp))
        }
      }
    }

    return exchanges.isEmpty ? nil : exchanges
  }

  private func extractTextFromContent(_ content: Any?) -> String? {
    if let directString = content as? String {
      return directString
    }

    if let contentBlocks = content as? [[String: Any]] {
      // Find first text block
      for block in contentBlocks {
        guard let blockType = block["type"] as? String else { continue }

        switch blockType {
        case "text":
          if let text = block["text"] as? String, !text.isEmpty {
            return text
          }
          if let text = block["content"] as? String, !text.isEmpty {
            return text
          }
        case "tool_result":
          if let text = block["content"] as? String, !text.isEmpty {
            return text
          }
        default:
          continue
        }
      }
    }

    if let stringArray = content as? [String],
       let first = stringArray.first(where: { !$0.isEmpty }) {
      return first
    }

    return nil
  }

  private func parseTimestamp(_ timestampStr: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestampStr) {
      return date
    }

    // Fallback to simpler format
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: timestampStr)
  }

  private func sanitizeText(_ text: String) -> String {
    // Collapse whitespace
    var sanitized = text.replacingOccurrences(
      of: #"\s+"#,
      with: " ",
      options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    // Strip control characters
    sanitized = sanitized.filter { !$0.isNewline || $0 == "\n" }
      .replacingOccurrences(of: "\n", with: " ")

    // Clamp length
    if sanitized.count > maxMessageLength {
      sanitized = String(sanitized.prefix(maxMessageLength))
    }

    return sanitized
  }

  // MARK: - Codex Format Parsing

  /// Parse Codex response_item record (newer format)
  private func parseCodexResponseItem(_ json: [String: Any], timestamp: Date) -> [Exchange]? {
    guard let payload = json["payload"] as? [String: Any],
          payload["type"] as? String == "message",
          let role = payload["role"] as? String else {
      return nil
    }

    // Extract text from content array
    guard let text = extractCodexContent(payload["content"]) else {
      return nil
    }

    let sanitized = sanitizeText(text)
    guard !sanitized.isEmpty else {
      return nil
    }

    let exchangeRole: Exchange.Role = (role == "user") ? .user : .assistant
    return [Exchange(role: exchangeRole, text: sanitized, timestamp: timestamp)]
  }

  /// Parse Codex message record (older format without response_item wrapper)
  private func parseCodexMessage(_ json: [String: Any], timestamp: Date) -> Exchange? {
    guard let role = json["role"] as? String else {
      return nil
    }

    // Extract text from content array
    guard let text = extractCodexContent(json["content"]) else {
      return nil
    }

    let sanitized = sanitizeText(text)
    guard !sanitized.isEmpty else {
      return nil
    }

    let exchangeRole: Exchange.Role = (role == "user") ? .user : .assistant
    return Exchange(role: exchangeRole, text: sanitized, timestamp: timestamp)
  }

  /// Extract text from Codex content array format
  /// Codex uses: content: [{"type": "input_text"|"output_text"|"markdown", "text": "..."}]
  private func extractCodexContent(_ content: Any?) -> String? {
    guard let contentBlocks = content as? [[String: Any]] else {
      return nil
    }

    // Collect all text blocks (Codex can have multiple content blocks per message)
    var textParts: [String] = []

    for block in contentBlocks {
      guard let blockType = block["type"] as? String else { continue }

      switch blockType {
      case "input_text", "output_text", "text", "markdown":
        if let text = block["text"] as? String, !text.isEmpty {
          textParts.append(text)
        }
      default:
        continue
      }
    }

    // Join multiple parts with newline
    let combined = textParts.joined(separator: "\n")
    return combined.isEmpty ? nil : combined
  }
}
