import XCTest
import GRDB
import Foundation

// MARK: - OpenCode Parser PoC
//
// Proof-of-concept parser for OpenCode's SQLite transcript database.
// Validates that OpenCode's session/message/files schema can be read
// and mapped to Contextify's data model.
//
// This is NOT production code. It lives in the test target only.
// See ct-1051 design spec for production architecture.

// MARK: - Intermediate Data Model

/// Minimal intermediate representation for a parsed OpenCode message.
/// In production, this would map to EntryInsert.
struct OpenCodeParsedEntry: Equatable {
  let id: String
  let sessionId: String
  let role: String           // "user", "assistant", "system", "tool"
  let content: String
  let timestamp: Date
  let provider: String       // always "opencode"
  let model: String?
  let toolCalls: [OpenCodeToolCall]
  let reasoning: String?     // thinking/reasoning text, if present

  static func == (lhs: OpenCodeParsedEntry, rhs: OpenCodeParsedEntry) -> Bool {
    lhs.id == rhs.id
      && lhs.sessionId == rhs.sessionId
      && lhs.role == rhs.role
      && lhs.content == rhs.content
      && lhs.provider == rhs.provider
      && lhs.model == rhs.model
      && lhs.toolCalls.count == rhs.toolCalls.count
  }
}

struct OpenCodeToolCall: Equatable {
  let id: String?
  let name: String
  let input: String?
  let isFinished: Bool

  static func == (lhs: OpenCodeToolCall, rhs: OpenCodeToolCall) -> Bool {
    lhs.name == rhs.name && lhs.id == rhs.id
  }
}

/// Parsed session metadata from the sessions table.
struct OpenCodeSession {
  let id: String
  let title: String?
  let messageCount: Int
  let promptTokens: Int
  let completionTokens: Int
  let cost: Double
  let createdAt: Date
  let updatedAt: Date
}

// MARK: - Parser Implementation

/// Parses an OpenCode SQLite database into Contextify's data model.
/// Uses GRDB for SQLite access (already a project dependency).
struct OpenCodeParser {
  /// Parse all sessions and messages from an OpenCode database.
  func parseSessions(from reader: some DatabaseReader) throws -> [OpenCodeSession] {
    try reader.read { db in
      let rows = try Row.fetchAll(db, sql: """
        SELECT id, title, message_count, prompt_tokens, completion_tokens,
               cost, created_at, updated_at
        FROM sessions
        ORDER BY created_at ASC, id ASC
        """)

      return rows.map { row in
        OpenCodeSession(
          id: row["id"],
          title: row["title"],
          messageCount: row["message_count"],
          promptTokens: row["prompt_tokens"],
          completionTokens: row["completion_tokens"],
          cost: row["cost"],
          createdAt: dateFromUnixMs(row["created_at"] as Int64),
          updatedAt: dateFromUnixMs(row["updated_at"] as Int64)
        )
      }
    }
  }

  /// Parse all messages for a given session, ordered by creation time.
  func parseMessages(from reader: some DatabaseReader, sessionId: String) throws -> [OpenCodeParsedEntry] {
    try reader.read { db in
      let rows = try Row.fetchAll(db, sql: """
        SELECT id, session_id, role, parts, model, created_at, updated_at, finished_at
        FROM messages
        WHERE session_id = ?
        ORDER BY created_at ASC, id ASC
        """, arguments: [sessionId])

      return rows.compactMap { row -> OpenCodeParsedEntry? in
        let messageId: String = row["id"]
        let role: String = row["role"]
        let partsJSON: String? = row["parts"]
        let model: String? = row["model"]
        let createdAt: Int64 = row["created_at"]

        // Parse the double-encoded JSON parts column
        let (textContent, toolCalls, reasoning) = parseParts(partsJSON)

        // Skip entries with no meaningful content
        guard !textContent.isEmpty || !toolCalls.isEmpty || reasoning != nil else {
          return nil
        }

        // Build display content
        let displayContent: String
        if textContent.isEmpty && !toolCalls.isEmpty {
          displayContent = toolCalls.map { "[Tool: \($0.name)]" }.joined(separator: " ")
        } else {
          displayContent = textContent
        }

        return OpenCodeParsedEntry(
          id: "opencode-\(messageId)",
          sessionId: sessionId,
          role: role,
          content: displayContent,
          timestamp: dateFromUnixMs(createdAt),
          provider: "opencode",
          model: model,
          toolCalls: toolCalls,
          reasoning: reasoning
        )
      }
    }
  }

  /// Parse all messages across all sessions in the database.
  func parseAllMessages(from reader: some DatabaseReader) throws -> [OpenCodeParsedEntry] {
    let sessions = try parseSessions(from: reader)
    var allEntries: [OpenCodeParsedEntry] = []
    for session in sessions {
      let entries = try parseMessages(from: reader, sessionId: session.id)
      allEntries.append(contentsOf: entries)
    }
    return allEntries
  }

  // MARK: - Parts JSON Parsing

  /// Parse the double-encoded `parts` JSON column.
  /// Format: JSON string containing array of { type: string, data: ContentPart }
  /// Types: "text", "reasoning", "tool-call", "tool-result", "image-url", "binary", "finish"
  private func parseParts(_ partsJSON: String?) -> (text: String, toolCalls: [OpenCodeToolCall], reasoning: String?) {
    guard let partsJSON = partsJSON,
          let data = partsJSON.data(using: .utf8),
          let parts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return ("", [], nil)
    }

    var textParts: [String] = []
    var toolCalls: [OpenCodeToolCall] = []
    var reasoningParts: [String] = []

    for part in parts {
      guard let type = part["type"] as? String,
            let partData = part["data"] as? [String: Any] else {
        continue
      }

      switch type {
      case "text":
        if let text = partData["text"] as? String, !text.isEmpty {
          textParts.append(text)
        }

      case "reasoning":
        if let thinking = partData["thinking"] as? String, !thinking.isEmpty {
          reasoningParts.append(thinking)
        }

      case "tool-call":
        let toolCall = OpenCodeToolCall(
          id: partData["id"] as? String,
          name: (partData["name"] as? String) ?? "unknown",
          input: (partData["input"] as? String),
          isFinished: (partData["finished"] as? Bool) ?? false
        )
        toolCalls.append(toolCall)

      case "tool-result":
        // Tool results are associated with tool calls via tool_call_id
        // For the PoC, we extract tool name for indexing
        if let content = partData["content"] as? String, !content.isEmpty {
          let toolName = (partData["name"] as? String) ?? "tool-result"
          textParts.append("[\(toolName)] \(content)")
        }

      case "finish":
        // Finish markers indicate end of response; skip
        break

      case "image-url", "binary":
        // Non-text content; skip for PoC
        break

      default:
        // Unknown type; skip gracefully
        break
      }
    }

    let reasoning = reasoningParts.isEmpty ? nil : reasoningParts.joined(separator: "\n")
    return (textParts.joined(separator: "\n"), toolCalls, reasoning)
  }
}

// MARK: - Helpers

private func dateFromUnixMs(_ ms: Int64) -> Date {
  Date(timeIntervalSince1970: Double(ms) / 1000.0)
}

// MARK: - Test Database Setup

/// Creates an in-memory GRDB database with the OpenCode schema and sample data.
/// Uses DatabaseQueue (not DatabasePool) because DatabasePool requires WAL mode
/// which is not supported for in-memory databases.
private func makeOpenCodeTestDB() throws -> DatabaseQueue {
  let db = try DatabaseQueue()

  try db.write { db in
    // Create OpenCode schema (from the initial migration)
    try db.execute(sql: """
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        parent_session_id TEXT,
        title TEXT,
        message_count INTEGER NOT NULL DEFAULT 0,
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        cost REAL NOT NULL DEFAULT 0.0,
        summary_message_id TEXT,
        updated_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      );

      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id),
        role TEXT NOT NULL,
        parts TEXT,
        model TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        finished_at INTEGER
      );

      CREATE TABLE files (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id),
        path TEXT NOT NULL,
        content TEXT,
        version TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );

      CREATE INDEX idx_messages_session ON messages(session_id);
      CREATE INDEX idx_files_session ON files(session_id);
      """)
  }

  return db
}

/// Insert sample session + messages into the test database.
private func insertSampleData(into db: DatabaseQueue) throws {
  try db.write { db in
    // Session 1: A typical coding session
    let session1CreatedAt: Int64 = 1704067200000  // 2024-01-01T00:00:00Z in ms
    try db.execute(sql: """
      INSERT INTO sessions (id, title, message_count, prompt_tokens, completion_tokens,
                            cost, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "sess-001", "Fix parser bug", 5, 1200, 450, 0.0034,
        session1CreatedAt, session1CreatedAt + 120000
      ])

    // User message with text part
    let userParts = """
    [{"type":"text","data":{"text":"Fix the parser bug in tokenizer.ts"}}]
    """
    try db.execute(sql: """
      INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "msg-001", "sess-001", "user", userParts, nil,
        session1CreatedAt + 100, session1CreatedAt + 100
      ])

    // Assistant message with text + reasoning
    let assistantParts = """
    [{"type":"reasoning","data":{"thinking":"The bug is likely in the tokenizer split logic."}},{"type":"text","data":{"text":"I found the bug. The tokenizer was splitting on the wrong delimiter."}}]
    """
    try db.execute(sql: """
      INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at, finished_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "msg-002", "sess-001", "assistant", assistantParts, "claude-3-opus",
        session1CreatedAt + 5000, session1CreatedAt + 5000, session1CreatedAt + 8000
      ])

    // Assistant message with tool call
    let toolCallParts = """
    [{"type":"tool-call","data":{"id":"tc-001","name":"edit_file","input":"tokenizer.ts","finished":true}}]
    """
    try db.execute(sql: """
      INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "msg-003", "sess-001", "assistant", toolCallParts, "claude-3-opus",
        session1CreatedAt + 10000, session1CreatedAt + 10000
      ])

    // Tool result message
    let toolResultParts = """
    [{"type":"tool-result","data":{"tool_call_id":"tc-001","name":"edit_file","content":"File edited successfully","is_error":false}}]
    """
    try db.execute(sql: """
      INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "msg-004", "sess-001", "tool", toolResultParts, nil,
        session1CreatedAt + 12000, session1CreatedAt + 12000
      ])

    // Final assistant message with finish marker
    let finishParts = """
    [{"type":"text","data":{"text":"The fix has been applied. The tokenizer now correctly handles edge cases."}},{"type":"finish","data":{"reason":"stop","time":8000}}]
    """
    try db.execute(sql: """
      INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at, finished_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "msg-005", "sess-001", "assistant", finishParts, "claude-3-opus",
        session1CreatedAt + 15000, session1CreatedAt + 15000, session1CreatedAt + 17000
      ])

    // Session 2: Empty session (no messages)
    let session2CreatedAt: Int64 = 1704153600000  // 2024-01-02T00:00:00Z
    try db.execute(sql: """
      INSERT INTO sessions (id, title, message_count, prompt_tokens, completion_tokens,
                            cost, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "sess-002", nil, 0, 0, 0, 0.0,
        session2CreatedAt, session2CreatedAt
      ])

    // Session 3: Child session (hierarchical)
    let session3CreatedAt: Int64 = 1704240000000  // 2024-01-03T00:00:00Z
    try db.execute(sql: """
      INSERT INTO sessions (id, parent_session_id, title, message_count,
                            prompt_tokens, completion_tokens, cost, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "sess-003", "sess-001", "Sub-task: run tests", 1, 200, 50, 0.0005,
        session3CreatedAt, session3CreatedAt
      ])

    let subTaskParts = """
    [{"type":"text","data":{"text":"Running tests to verify the fix."}}]
    """
    try db.execute(sql: """
      INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "msg-006", "sess-003", "user", subTaskParts, nil,
        session3CreatedAt + 100, session3CreatedAt + 100
      ])

    // File snapshot for session 1
    try db.execute(sql: """
      INSERT INTO files (id, session_id, path, content, version, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        "file-001", "sess-001", "src/tokenizer.ts",
        "export function tokenize(input: string) { ... }",
        "1", session1CreatedAt + 10000, session1CreatedAt + 10000
      ])
  }
}

// MARK: - Tests

final class OpenCodeParserPoCTests: XCTestCase {
  private var dbQueue: DatabaseQueue!
  private let parser = OpenCodeParser()

  override func setUp() async throws {
    try await super.setUp()
    dbQueue = try makeOpenCodeTestDB()
    try insertSampleData(into: dbQueue)
  }

  override func tearDown() async throws {
    dbQueue = nil
    try await super.tearDown()
  }

  // MARK: - Session Parsing

  func testParseSessions_returnsAllSessions() throws {
    let sessions = try parser.parseSessions(from: dbQueue)

    XCTAssertEqual(sessions.count, 3)
    XCTAssertEqual(sessions[0].id, "sess-001")
    XCTAssertEqual(sessions[0].title, "Fix parser bug")
    XCTAssertEqual(sessions[0].messageCount, 5)
    XCTAssertEqual(sessions[0].promptTokens, 1200)
    XCTAssertEqual(sessions[0].completionTokens, 450)
    XCTAssertEqual(sessions[0].cost, 0.0034, accuracy: 0.0001)
  }

  func testParseSessions_emptySessionIncluded() throws {
    let sessions = try parser.parseSessions(from: dbQueue)
    let emptySession = sessions.first { $0.id == "sess-002" }

    XCTAssertNotNil(emptySession)
    XCTAssertNil(emptySession?.title)
    XCTAssertEqual(emptySession?.messageCount, 0)
  }

  func testParseSessions_orderedByCreatedAt() throws {
    let sessions = try parser.parseSessions(from: dbQueue)

    for i in 1..<sessions.count {
      XCTAssertTrue(
        sessions[i].createdAt >= sessions[i - 1].createdAt,
        "Sessions should be ordered by created_at ascending"
      )
    }
  }

  // MARK: - Message Parsing

  func testParseMessages_session1HasFiveEntries() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")

    // 5 messages, all should produce entries
    XCTAssertEqual(entries.count, 5)
  }

  func testParseMessages_userTextExtracted() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")

    let userEntry = entries.first { $0.id == "opencode-msg-001" }
    XCTAssertNotNil(userEntry)
    XCTAssertEqual(userEntry?.role, "user")
    XCTAssertEqual(userEntry?.content, "Fix the parser bug in tokenizer.ts")
    XCTAssertEqual(userEntry?.provider, "opencode")
    XCTAssertNil(userEntry?.model, "User messages should not have a model")
  }

  func testParseMessages_assistantWithReasoningExtracted() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")

    let assistantEntry = entries.first { $0.id == "opencode-msg-002" }
    XCTAssertNotNil(assistantEntry)
    XCTAssertEqual(assistantEntry?.role, "assistant")
    XCTAssertEqual(assistantEntry?.model, "claude-3-opus")
    XCTAssertTrue(assistantEntry?.content.contains("found the bug") ?? false)
    XCTAssertNotNil(assistantEntry?.reasoning)
    XCTAssertTrue(assistantEntry?.reasoning?.contains("tokenizer split logic") ?? false)
  }

  func testParseMessages_toolCallExtracted() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")

    let toolCallEntry = entries.first { $0.id == "opencode-msg-003" }
    XCTAssertNotNil(toolCallEntry)
    XCTAssertEqual(toolCallEntry?.role, "assistant")
    XCTAssertEqual(toolCallEntry?.toolCalls.count, 1)
    XCTAssertEqual(toolCallEntry?.toolCalls.first?.name, "edit_file")
    XCTAssertEqual(toolCallEntry?.toolCalls.first?.id, "tc-001")
    XCTAssertTrue(toolCallEntry?.toolCalls.first?.isFinished ?? false)
    XCTAssertEqual(toolCallEntry?.content, "[Tool: edit_file]")
  }

  func testParseMessages_toolResultExtracted() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")

    let toolResultEntry = entries.first { $0.id == "opencode-msg-004" }
    XCTAssertNotNil(toolResultEntry)
    XCTAssertEqual(toolResultEntry?.role, "tool")
    XCTAssertTrue(toolResultEntry?.content.contains("edit_file") ?? false)
    XCTAssertTrue(toolResultEntry?.content.contains("File edited successfully") ?? false)
  }

  func testParseMessages_finishMarkerIgnored() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")

    let finalEntry = entries.first { $0.id == "opencode-msg-005" }
    XCTAssertNotNil(finalEntry)
    // Text should be extracted but the "finish" part type should be ignored
    XCTAssertTrue(finalEntry?.content.contains("fix has been applied") ?? false)
    // Content should NOT contain any finish marker text
    XCTAssertFalse(finalEntry?.content.contains("stop") ?? true)
  }

  // MARK: - Timestamp Handling

  func testTimestampConversion_unixMsToDate() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")

    let firstEntry = entries.first { $0.id == "opencode-msg-001" }
    XCTAssertNotNil(firstEntry)

    // session1CreatedAt = 1704067200000 ms, msg offset = 100 ms
    // So timestamp = 1704067200.100 seconds
    let expected = Date(timeIntervalSince1970: 1704067200.100)
    XCTAssertEqual(
      firstEntry?.timestamp.timeIntervalSince1970 ?? 0,
      expected.timeIntervalSince1970,
      accuracy: 0.001
    )
  }

  func testSessionTimestamps_convertedCorrectly() throws {
    let sessions = try parser.parseSessions(from: dbQueue)

    let sess1 = sessions.first { $0.id == "sess-001" }
    XCTAssertNotNil(sess1)

    // 1704067200000 ms = 2024-01-01T00:00:00Z
    let expected = Date(timeIntervalSince1970: 1704067200.0)
    XCTAssertEqual(
      sess1?.createdAt.timeIntervalSince1970 ?? 0,
      expected.timeIntervalSince1970,
      accuracy: 0.001
    )
  }

  // MARK: - Empty & Edge Cases

  func testParseMessages_emptySession() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-002")
    XCTAssertEqual(entries.count, 0, "Empty session should produce no entries")
  }

  func testParseMessages_nonexistentSession() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "does-not-exist")
    XCTAssertEqual(entries.count, 0)
  }

  func testParseMessages_childSession() throws {
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-003")
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries[0].content, "Running tests to verify the fix.")
    XCTAssertEqual(entries[0].sessionId, "sess-003")
  }

  func testParseMessages_nullPartsColumn() throws {
    // Insert a message with NULL parts
    try dbQueue.write { db in
      try db.execute(sql: """
        INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          "msg-null", "sess-001", "system", nil, nil,
          1704067200000 as Int64, 1704067200000 as Int64
        ])
    }

    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")
    // The null-parts message should be skipped (no content)
    let nullEntry = entries.first { $0.id == "opencode-msg-null" }
    XCTAssertNil(nullEntry, "Message with null parts should be skipped")
  }

  func testParseMessages_malformedPartsJSON() throws {
    // Insert a message with invalid JSON in parts
    try dbQueue.write { db in
      try db.execute(sql: """
        INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          "msg-bad", "sess-001", "assistant", "<<<not json>>>", "model-x",
          1704067200000 as Int64, 1704067200000 as Int64
        ])
    }

    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")
    // The malformed-parts message should be skipped (no parseable content)
    let badEntry = entries.first { $0.id == "opencode-msg-bad" }
    XCTAssertNil(badEntry, "Message with malformed parts JSON should be skipped")
  }

  func testParseMessages_emptyTextPartsSkipped() throws {
    // Insert a message with empty text content
    try dbQueue.write { db in
      let emptyParts = """
      [{"type":"text","data":{"text":""}}]
      """
      try db.execute(sql: """
        INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          "msg-empty", "sess-001", "assistant", emptyParts, nil,
          1704067200000 as Int64, 1704067200000 as Int64
        ])
    }

    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")
    let emptyEntry = entries.first { $0.id == "opencode-msg-empty" }
    XCTAssertNil(emptyEntry, "Message with empty text should be skipped")
  }

  // MARK: - All Messages Across Sessions

  func testParseAllMessages_acrossSessions() throws {
    let allEntries = try parser.parseAllMessages(from: dbQueue)

    // sess-001: 5 messages, sess-002: 0, sess-003: 1
    XCTAssertEqual(allEntries.count, 6)

    let sess1Entries = allEntries.filter { $0.sessionId == "sess-001" }
    let sess3Entries = allEntries.filter { $0.sessionId == "sess-003" }
    XCTAssertEqual(sess1Entries.count, 5)
    XCTAssertEqual(sess3Entries.count, 1)
  }

  // MARK: - Provider ID Consistency

  func testAllEntries_haveCorrectProviderID() throws {
    let allEntries = try parser.parseAllMessages(from: dbQueue)

    for entry in allEntries {
      XCTAssertEqual(entry.provider, "opencode")
    }
  }

  // MARK: - Schema Validation

  func testSchemaPresence_tablesExist() throws {
    let tables = try dbQueue.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
      )
    }

    XCTAssertTrue(tables.contains("sessions"), "sessions table must exist")
    XCTAssertTrue(tables.contains("messages"), "messages table must exist")
    XCTAssertTrue(tables.contains("files"), "files table must exist")
  }

  func testSchemaPresence_messagesColumns() throws {
    let columns = try dbQueue.read { db -> [String] in
      let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(messages)")
      return rows.map { $0["name"] as String }
    }

    let expected = ["id", "session_id", "role", "parts", "model", "created_at", "updated_at", "finished_at"]
    for col in expected {
      XCTAssertTrue(columns.contains(col), "messages table should have column '\(col)'")
    }
  }

  // MARK: - Double-Encoded JSON (Parts Column)

  func testPartsDoubleEncoding_correctlyHandled() throws {
    // The parts column is a TEXT column containing a JSON string.
    // This test verifies our parser handles the string-to-JSON deserialization.
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")

    // All entries should have parsed their parts successfully
    XCTAssertTrue(entries.count > 0, "Should have parsed at least one entry")

    // Check that text was extracted (not raw JSON)
    let userEntry = entries.first { $0.role == "user" }
    XCTAssertNotNil(userEntry)
    XCTAssertFalse(
      userEntry?.content.contains("\"type\"") ?? true,
      "Content should be extracted text, not raw JSON"
    )
  }

  // MARK: - Ordering Determinism

  func testParseMessages_sameTimestampUsesStableTieBreak() throws {
    try dbQueue.write { db in
      let parts = #"[{"type":"text","data":{"text":"same ts"}}]"#
      try db.execute(sql: """
        INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          "msg-010", "sess-001", "user", parts, nil, 1704067400000 as Int64, 1704067400000 as Int64,
          "msg-009", "sess-001", "assistant", parts, nil, 1704067400000 as Int64, 1704067400000 as Int64
        ])
    }
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")
    // Filter to just the two tie-break entries
    let tied = entries.filter { $0.id == "opencode-msg-009" || $0.id == "opencode-msg-010" }
    // id ASC means msg-009 comes before msg-010
    XCTAssertEqual(tied.map(\.id), ["opencode-msg-009", "opencode-msg-010"])
  }

  // MARK: - Multiple Reasoning Parts

  func testParseMessages_multipleReasoningPartsAccumulated() throws {
    try dbQueue.write { db in
      let parts = """
      [{"type":"reasoning","data":{"thinking":"First thought."}},{"type":"reasoning","data":{"thinking":"Second thought."}},{"type":"text","data":{"text":"Final answer."}}]
      """
      try db.execute(sql: """
        INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          "msg-multi-reason", "sess-001", "assistant", parts, nil,
          1704067500000 as Int64, 1704067500000 as Int64
        ])
    }
    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")
    let entry = entries.first { $0.id == "opencode-msg-multi-reason" }
    XCTAssertNotNil(entry)
    XCTAssertEqual(entry?.content, "Final answer.")
    XCTAssertTrue(entry?.reasoning?.contains("First thought.") ?? false, "First reasoning part should be preserved")
    XCTAssertTrue(entry?.reasoning?.contains("Second thought.") ?? false, "Second reasoning part should be preserved")
  }

  // MARK: - Mixed Part Types in Single Message

  func testMixedPartsInSingleMessage() throws {
    // Insert a message with multiple part types
    try dbQueue.write { db in
      let mixedParts = """
      [{"type":"reasoning","data":{"thinking":"Let me think about this."}},{"type":"text","data":{"text":"Here is my analysis."}},{"type":"tool-call","data":{"id":"tc-mix","name":"read_file","input":"main.ts","finished":true}},{"type":"finish","data":{"reason":"stop","time":5000}}]
      """
      try db.execute(sql: """
        INSERT INTO messages (id, session_id, role, parts, model, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          "msg-mixed", "sess-001", "assistant", mixedParts, "gpt-4o",
          1704067300000 as Int64, 1704067300000 as Int64
        ])
    }

    let entries = try parser.parseMessages(from: dbQueue, sessionId: "sess-001")
    let mixedEntry = entries.first { $0.id == "opencode-msg-mixed" }

    XCTAssertNotNil(mixedEntry)
    XCTAssertEqual(mixedEntry?.role, "assistant")
    XCTAssertEqual(mixedEntry?.model, "gpt-4o")
    XCTAssertTrue(mixedEntry?.content.contains("Here is my analysis") ?? false)
    XCTAssertEqual(mixedEntry?.reasoning, "Let me think about this.")
    XCTAssertEqual(mixedEntry?.toolCalls.count, 1)
    XCTAssertEqual(mixedEntry?.toolCalls.first?.name, "read_file")
  }
}
