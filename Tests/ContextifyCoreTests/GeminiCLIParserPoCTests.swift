import XCTest
import Foundation

// MARK: - Gemini CLI Parser PoC
//
// Proof-of-concept parser for Gemini CLI transcript formats.
// Validates that Gemini CLI's logs.json and checkpoint files can be parsed
// and mapped to Contextify's data model.
//
// This is NOT production code. It lives in the test target only.
// See ct-1051 design spec for production architecture.

// MARK: - Intermediate Data Model

/// Minimal intermediate representation for a parsed Gemini CLI message.
/// In production, this would map to EntryInsert.
struct GeminiParsedEntry: Equatable {
  let id: String
  let sessionId: String
  let role: String          // "user" or "assistant"
  let content: String
  let timestamp: Date?      // nil for checkpoint-derived entries (no timestamps)
  let provider: String      // always "gemini.cli"
  let toolCalls: [GeminiToolCall]

  static func == (lhs: GeminiParsedEntry, rhs: GeminiParsedEntry) -> Bool {
    lhs.id == rhs.id
      && lhs.sessionId == rhs.sessionId
      && lhs.role == rhs.role
      && lhs.content == rhs.content
      && lhs.provider == rhs.provider
      && lhs.toolCalls.count == rhs.toolCalls.count
  }
}

struct GeminiToolCall: Equatable {
  let name: String
  let args: [String: Any]?

  static func == (lhs: GeminiToolCall, rhs: GeminiToolCall) -> Bool {
    lhs.name == rhs.name
  }
}

// MARK: - Parser Implementation

/// Parses Gemini CLI logs.json files (JSON array of user-only log entries).
struct GeminiLogsParser {
  /// Parse a logs.json file content into entries.
  /// logs.json is a JSON array (NOT JSONL) of LogEntry objects.
  /// Each entry has: sessionId, messageId, timestamp (ISO), type ("user"), message.
  func parse(data: Data) throws -> [GeminiParsedEntry] {
    guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw GeminiParserError.invalidFormat("logs.json must be a JSON array of objects")
    }

    return array.compactMap { entry -> GeminiParsedEntry? in
      guard let sessionId = entry["sessionId"] as? String,
            let messageId = entry["messageId"] as? Int,
            let message = entry["message"] as? String else {
        return nil
      }

      let timestamp = parseISO8601(entry["timestamp"] as? String)
      let type = entry["type"] as? String ?? "user"

      // Gemini logs.json only contains user messages;
      // map "user" type to "user" role
      let role = type == "user" ? "user" : type

      return GeminiParsedEntry(
        id: "gemini-\(sessionId)-\(messageId)",
        sessionId: sessionId,
        role: role,
        content: message,
        timestamp: timestamp,
        provider: "gemini.cli",
        toolCalls: []
      )
    }
  }
}

/// Parses Gemini CLI checkpoint files (full conversation history).
/// Handles both legacy (bare Content[] array) and current ({ history: Content[] }) formats.
struct GeminiCheckpointParser {
  /// Parse a checkpoint file content into entries.
  /// Detects format by checking if top-level is array (legacy) or object (current).
  func parse(data: Data, checkpointTag: String) throws -> [GeminiParsedEntry] {
    let json = try JSONSerialization.jsonObject(with: data)

    let contentArray: [[String: Any]]

    if let object = json as? [String: Any],
       let history = object["history"] as? [[String: Any]] {
      // Current format: { history: Content[] }
      contentArray = history
    } else if let array = json as? [[String: Any]] {
      // Legacy format: bare Content[] array
      contentArray = array
    } else {
      throw GeminiParserError.invalidFormat(
        "Checkpoint must be either { history: Content[] } or bare Content[] array"
      )
    }

    return contentArray.enumerated().compactMap { index, content -> GeminiParsedEntry? in
      guard let role = content["role"] as? String,
            let parts = content["parts"] as? [[String: Any]] else {
        return nil
      }

      // Extract text content from parts
      var textParts: [String] = []
      var toolCalls: [GeminiToolCall] = []

      for part in parts {
        if let text = part["text"] as? String {
          textParts.append(text)
        }
        if let functionCall = part["functionCall"] as? [String: Any],
           let name = functionCall["name"] as? String {
          let args = functionCall["args"] as? [String: Any]
          toolCalls.append(GeminiToolCall(name: name, args: args))
        }
        // functionResponse parts are informational; skip for content extraction
      }

      let combinedText = textParts.joined(separator: "\n")
      guard !combinedText.isEmpty || !toolCalls.isEmpty else {
        return nil
      }

      // Map Gemini roles: "user" -> "user", "model" -> "assistant"
      let mappedRole = role == "model" ? "assistant" : role

      // Content for tool-only entries
      let displayContent: String
      if combinedText.isEmpty && !toolCalls.isEmpty {
        displayContent = toolCalls.map { "[Tool: \($0.name)]" }.joined(separator: " ")
      } else {
        displayContent = combinedText
      }

      return GeminiParsedEntry(
        id: "gemini-\(checkpointTag)-\(index)",
        sessionId: checkpointTag,
        role: mappedRole,
        content: displayContent,
        timestamp: nil,  // Checkpoints have no per-message timestamps
        provider: "gemini.cli",
        toolCalls: toolCalls
      )
    }
  }
}

/// Combined parser that handles both file types and deduplication.
struct GeminiCLIParser {
  private let logsParser = GeminiLogsParser()
  private let checkpointParser = GeminiCheckpointParser()

  /// Parse a Gemini CLI project directory.
  /// Prefers checkpoint (full conversation) when available.
  /// Falls back to logs.json (user-only) otherwise.
  func parseProject(
    logsData: Data?,
    checkpoints: [(tag: String, data: Data)]
  ) throws -> [GeminiParsedEntry] {
    var allEntries: [GeminiParsedEntry] = []
    var sessionsWithCheckpoints = Set<String>()

    // Parse checkpoints first (they have full conversations)
    for (tag, data) in checkpoints {
      let entries = try checkpointParser.parse(data: data, checkpointTag: tag)
      allEntries.append(contentsOf: entries)
      // Track which sessions have checkpoints so we can skip duplicate logs
      if !entries.isEmpty {
        sessionsWithCheckpoints.insert(tag)
      }
    }

    // Parse logs.json if available
    if let logsData = logsData {
      let logEntries = try logsParser.parse(data: logsData)
      // Only include log entries for sessions that DON'T have checkpoints
      let filteredEntries = logEntries.filter { entry in
        !sessionsWithCheckpoints.contains(entry.sessionId)
      }
      allEntries.append(contentsOf: filteredEntries)
    }

    return allEntries
  }
}

enum GeminiParserError: Error, LocalizedError {
  case invalidFormat(String)
  case missingField(String)

  var errorDescription: String? {
    switch self {
    case .invalidFormat(let reason): return "Invalid Gemini format: \(reason)"
    case .missingField(let field): return "Missing field: \(field)"
    }
  }
}

// MARK: - ISO8601 Helper

private func parseISO8601(_ string: String?) -> Date? {
  guard let string = string else { return nil }
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: string) { return date }
  // Retry without fractional seconds
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: string)
}

// MARK: - Sample Test Data

/// Test data constants derived from the ct-1049 research findings.
private enum GeminiTestData {
  /// A logs.json with 3 user messages across 2 sessions.
  static let logsJSON = """
  [
    {
      "sessionId": "session-abc-123",
      "messageId": 0,
      "timestamp": "2026-01-15T10:30:00.000Z",
      "type": "user",
      "message": "Hello, help me refactor the parser module"
    },
    {
      "sessionId": "session-abc-123",
      "messageId": 1,
      "timestamp": "2026-01-15T10:35:22.500Z",
      "type": "user",
      "message": "Can you also add error handling for the edge cases?"
    },
    {
      "sessionId": "session-def-456",
      "messageId": 0,
      "timestamp": "2026-01-15T14:00:00.000Z",
      "type": "user",
      "message": "What dependencies does this project use?"
    }
  ]
  """.data(using: .utf8)!

  /// A checkpoint file in the current format (wrapped { history: Content[] }).
  static let checkpointCurrent = """
  {
    "history": [
      {
        "role": "user",
        "parts": [{"text": "Hello, help me refactor the parser module"}]
      },
      {
        "role": "model",
        "parts": [{"text": "I'd be happy to help refactor the parser module. Let me start by examining the current structure."}]
      },
      {
        "role": "user",
        "parts": [{"text": "Can you also add error handling for the edge cases?"}]
      },
      {
        "role": "model",
        "parts": [{"text": "Of course! Here are the error handling improvements I suggest."}]
      }
    ]
  }
  """.data(using: .utf8)!

  /// A checkpoint file in the legacy format (bare Content[] array).
  static let checkpointLegacy = """
  [
    {
      "role": "user",
      "parts": [{"text": "Fix the build script"}]
    },
    {
      "role": "model",
      "parts": [{"text": "I'll fix the build script. The issue is in the path resolution."}]
    }
  ]
  """.data(using: .utf8)!

  /// A checkpoint with function calls (tool use).
  static let checkpointWithToolCalls = """
  {
    "history": [
      {
        "role": "user",
        "parts": [{"text": "List the files in src/"}]
      },
      {
        "role": "model",
        "parts": [
          {
            "functionCall": {
              "name": "list_files",
              "args": {"directory": "src/", "recursive": false}
            }
          }
        ]
      },
      {
        "role": "user",
        "parts": [
          {
            "functionResponse": {
              "name": "list_files",
              "response": {"result": "main.ts\\nparser.ts\\nutils.ts"}
            }
          }
        ]
      },
      {
        "role": "model",
        "parts": [{"text": "The src/ directory contains three files: main.ts, parser.ts, and utils.ts."}]
      }
    ]
  }
  """.data(using: .utf8)!

  /// Empty logs.json (valid JSON, no entries).
  static let emptyLogs = "[]".data(using: .utf8)!

  /// Checkpoint with missing optional fields.
  static let checkpointSparse = """
  {
    "history": [
      {
        "role": "user",
        "parts": [{"text": "Hello"}]
      },
      {
        "role": "model",
        "parts": []
      }
    ]
  }
  """.data(using: .utf8)!

  /// Checkpoint with mixed content parts (text + inline data).
  static let checkpointMixedParts = """
  {
    "history": [
      {
        "role": "user",
        "parts": [
          {"text": "Describe this image"},
          {"inlineData": {"mimeType": "image/png", "data": "iVBOR..."}}
        ]
      },
      {
        "role": "model",
        "parts": [{"text": "The image shows a flowchart of the system architecture."}]
      }
    ]
  }
  """.data(using: .utf8)!
}

// MARK: - Tests

final class GeminiCLIParserPoCTests: XCTestCase {

  // MARK: - logs.json Tests

  func testParseLogsJSON_multipleSessionsAndMessages() throws {
    let parser = GeminiLogsParser()
    let entries = try parser.parse(data: GeminiTestData.logsJSON)

    XCTAssertEqual(entries.count, 3)

    // First entry
    XCTAssertEqual(entries[0].id, "gemini-session-abc-123-0")
    XCTAssertEqual(entries[0].sessionId, "session-abc-123")
    XCTAssertEqual(entries[0].role, "user")
    XCTAssertEqual(entries[0].content, "Hello, help me refactor the parser module")
    XCTAssertEqual(entries[0].provider, "gemini.cli")
    XCTAssertNotNil(entries[0].timestamp)

    // Second entry (same session, different messageId)
    XCTAssertEqual(entries[1].id, "gemini-session-abc-123-1")
    XCTAssertEqual(entries[1].sessionId, "session-abc-123")

    // Third entry (different session)
    XCTAssertEqual(entries[2].sessionId, "session-def-456")
    XCTAssertEqual(entries[2].content, "What dependencies does this project use?")
  }

  func testParseLogsJSON_onlyContainsUserMessages() throws {
    let parser = GeminiLogsParser()
    let entries = try parser.parse(data: GeminiTestData.logsJSON)

    // All entries should be user role (logs.json never has model turns)
    for entry in entries {
      XCTAssertEqual(entry.role, "user", "logs.json should only contain user messages")
    }
  }

  func testParseLogsJSON_timestampsAreParsedCorrectly() throws {
    let parser = GeminiLogsParser()
    let entries = try parser.parse(data: GeminiTestData.logsJSON)

    // First message: 2026-01-15T10:30:00.000Z
    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents(
      in: TimeZone(identifier: "UTC")!,
      from: entries[0].timestamp!
    )
    XCTAssertEqual(components.year, 2026)
    XCTAssertEqual(components.month, 1)
    XCTAssertEqual(components.day, 15)
    XCTAssertEqual(components.hour, 10)
    XCTAssertEqual(components.minute, 30)
  }

  func testParseLogsJSON_emptyArray() throws {
    let parser = GeminiLogsParser()
    let entries = try parser.parse(data: GeminiTestData.emptyLogs)
    XCTAssertEqual(entries.count, 0)
  }

  func testParseLogsJSON_invalidJSONThrows() {
    let parser = GeminiLogsParser()
    let badData = "not json at all".data(using: .utf8)!
    XCTAssertThrowsError(try parser.parse(data: badData))
  }

  func testParseLogsJSON_objectInsteadOfArrayThrows() {
    let parser = GeminiLogsParser()
    let objectData = "{\"key\": \"value\"}".data(using: .utf8)!
    XCTAssertThrowsError(try parser.parse(data: objectData)) { error in
      let geminiError = error as? GeminiParserError
      XCTAssertNotNil(geminiError)
    }
  }

  func testParseLogsJSON_missingFieldsAreSkipped() throws {
    let parser = GeminiLogsParser()
    // Entry missing sessionId should be skipped (compactMap)
    let partialData = """
    [
      {"messageId": 0, "timestamp": "2026-01-01T00:00:00Z", "message": "test"},
      {"sessionId": "s1", "messageId": 1, "timestamp": "2026-01-01T00:00:01Z", "message": "valid"}
    ]
    """.data(using: .utf8)!

    let entries = try parser.parse(data: partialData)
    XCTAssertEqual(entries.count, 1, "Entry missing sessionId should be skipped")
    XCTAssertEqual(entries[0].sessionId, "s1")
  }

  // MARK: - Checkpoint Tests (Current Format)

  func testParseCheckpoint_currentFormat() throws {
    let parser = GeminiCheckpointParser()
    let entries = try parser.parse(
      data: GeminiTestData.checkpointCurrent,
      checkpointTag: "session-abc-123"
    )

    XCTAssertEqual(entries.count, 4)

    // User turns
    XCTAssertEqual(entries[0].role, "user")
    XCTAssertEqual(entries[0].content, "Hello, help me refactor the parser module")
    XCTAssertEqual(entries[0].id, "gemini-session-abc-123-0")

    // Model turns mapped to "assistant"
    XCTAssertEqual(entries[1].role, "assistant")
    XCTAssertTrue(entries[1].content.contains("happy to help"))

    XCTAssertEqual(entries[2].role, "user")
    XCTAssertEqual(entries[3].role, "assistant")

    // All entries should have nil timestamps (checkpoints don't have them)
    for entry in entries {
      XCTAssertNil(entry.timestamp, "Checkpoint entries should not have timestamps")
    }
  }

  // MARK: - Checkpoint Tests (Legacy Format)

  func testParseCheckpoint_legacyBareArrayFormat() throws {
    let parser = GeminiCheckpointParser()
    let entries = try parser.parse(
      data: GeminiTestData.checkpointLegacy,
      checkpointTag: "legacy-session"
    )

    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries[0].role, "user")
    XCTAssertEqual(entries[0].content, "Fix the build script")
    XCTAssertEqual(entries[1].role, "assistant")
    XCTAssertTrue(entries[1].content.contains("path resolution"))
  }

  // MARK: - Checkpoint with Tool Calls

  func testParseCheckpoint_functionCallsExtracted() throws {
    let parser = GeminiCheckpointParser()
    let entries = try parser.parse(
      data: GeminiTestData.checkpointWithToolCalls,
      checkpointTag: "tool-session"
    )

    // 3 entries: user ask, model tool call, model answer.
    // The functionResponse entry (user role) is skipped because it has
    // no text parts and no functionCall parts (functionResponse is not
    // extracted as content).
    XCTAssertEqual(entries.count, 3)

    // Second entry (model) should have a tool call
    let toolCallEntry = entries[1]
    XCTAssertEqual(toolCallEntry.role, "assistant")
    XCTAssertEqual(toolCallEntry.toolCalls.count, 1)
    XCTAssertEqual(toolCallEntry.toolCalls[0].name, "list_files")
    XCTAssertEqual(toolCallEntry.content, "[Tool: list_files]")

    // Third entry (model text response after tool use)
    XCTAssertEqual(entries[2].role, "assistant")
    XCTAssertTrue(entries[2].content.contains("three files"))
  }

  // MARK: - Edge Cases

  func testParseCheckpoint_emptyPartsSkipped() throws {
    let parser = GeminiCheckpointParser()
    let entries = try parser.parse(
      data: GeminiTestData.checkpointSparse,
      checkpointTag: "sparse"
    )

    // Model entry with empty parts should be skipped
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries[0].role, "user")
    XCTAssertEqual(entries[0].content, "Hello")
  }

  func testParseCheckpoint_mixedPartTypes() throws {
    let parser = GeminiCheckpointParser()
    let entries = try parser.parse(
      data: GeminiTestData.checkpointMixedParts,
      checkpointTag: "mixed"
    )

    XCTAssertEqual(entries.count, 2)
    // User message should extract only the text part (inlineData is ignored)
    XCTAssertEqual(entries[0].content, "Describe this image")
    XCTAssertEqual(entries[1].content, "The image shows a flowchart of the system architecture.")
  }

  func testParseCheckpoint_invalidJSONThrows() {
    let parser = GeminiCheckpointParser()
    let badData = "<<<not json>>>".data(using: .utf8)!
    XCTAssertThrowsError(try parser.parse(data: badData, checkpointTag: "bad"))
  }

  func testParseCheckpoint_wrongStructureThrows() {
    let parser = GeminiCheckpointParser()
    // A JSON object without "history" key and not an array
    let badStructure = "{\"something\": \"else\"}".data(using: .utf8)!
    XCTAssertThrowsError(try parser.parse(data: badStructure, checkpointTag: "bad")) { error in
      let geminiError = error as? GeminiParserError
      XCTAssertNotNil(geminiError)
    }
  }

  // MARK: - Combined Parser Tests

  func testCombinedParser_prefersCheckpointOverLogs() throws {
    let parser = GeminiCLIParser()
    let entries = try parser.parseProject(
      logsData: GeminiTestData.logsJSON,
      checkpoints: [("session-abc-123", GeminiTestData.checkpointCurrent)]
    )

    // Checkpoint has 4 entries (user+assistant), logs has 3 user-only entries
    // For session-abc-123: checkpoint should be used (4 entries),
    //   logs entries for that session should be filtered out (2 entries).
    // For session-def-456: no checkpoint, logs entry included (1 entry).
    let sessionABC = entries.filter { $0.sessionId == "session-abc-123" }
    let sessionDEF = entries.filter { $0.sessionId == "session-def-456" }

    XCTAssertEqual(sessionABC.count, 4, "Session with checkpoint should use full checkpoint data")
    XCTAssertEqual(sessionDEF.count, 1, "Session without checkpoint should use logs.json")

    // Verify the checkpoint entries include assistant turns
    let assistantEntries = sessionABC.filter { $0.role == "assistant" }
    XCTAssertEqual(assistantEntries.count, 2, "Checkpoint should provide assistant turns")
  }

  func testCombinedParser_logsOnlyWhenNoCheckpoints() throws {
    let parser = GeminiCLIParser()
    let entries = try parser.parseProject(
      logsData: GeminiTestData.logsJSON,
      checkpoints: []
    )

    XCTAssertEqual(entries.count, 3)
    // All should be user-only
    for entry in entries {
      XCTAssertEqual(entry.role, "user")
    }
  }

  func testCombinedParser_checkpointsOnlyWhenNoLogs() throws {
    let parser = GeminiCLIParser()
    let entries = try parser.parseProject(
      logsData: nil,
      checkpoints: [("session-1", GeminiTestData.checkpointCurrent)]
    )

    XCTAssertEqual(entries.count, 4)
    let hasAssistant = entries.contains { $0.role == "assistant" }
    XCTAssertTrue(hasAssistant, "Checkpoint-only parse should include assistant turns")
  }

  func testCombinedParser_noDataReturnsEmpty() throws {
    let parser = GeminiCLIParser()
    let entries = try parser.parseProject(logsData: nil, checkpoints: [])
    XCTAssertEqual(entries.count, 0)
  }

  func testCombinedParser_multipleCheckpoints() throws {
    let parser = GeminiCLIParser()
    let entries = try parser.parseProject(
      logsData: nil,
      checkpoints: [
        ("session-a", GeminiTestData.checkpointCurrent),
        ("session-b", GeminiTestData.checkpointLegacy),
      ]
    )

    let sessionA = entries.filter { $0.sessionId == "session-a" }
    let sessionB = entries.filter { $0.sessionId == "session-b" }

    XCTAssertEqual(sessionA.count, 4)
    XCTAssertEqual(sessionB.count, 2)
  }

  // MARK: - Provider ID Consistency

  func testAllEntries_haveCorrectProviderID() throws {
    let logsParser = GeminiLogsParser()
    let checkpointParser = GeminiCheckpointParser()

    let logEntries = try logsParser.parse(data: GeminiTestData.logsJSON)
    let checkpointEntries = try checkpointParser.parse(
      data: GeminiTestData.checkpointCurrent,
      checkpointTag: "test"
    )

    for entry in logEntries + checkpointEntries {
      XCTAssertEqual(entry.provider, "gemini.cli")
    }
  }
}
