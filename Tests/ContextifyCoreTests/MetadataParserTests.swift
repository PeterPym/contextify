import XCTest
@testable import ContextifyCore

final class MetadataParserTests: XCTestCase {

  // MARK: - File History Snapshot Parsing

  func testParseFileHistorySnapshot() throws {
    let json = """
    {
      "uuid": "test-uuid-123",
      "type": "file-history-snapshot",
      "timestamp": "2025-01-15T10:30:00.000Z",
      "isSnapshotUpdate": true,
      "snapshot": {
        "timestamp": "2024-01-15T10:30:00.000Z",
        "trackedFileBackups": {
          "/path/to/file1.swift": {
            "version": 1,
            "backupTime": "2024-01-15T10:30:00.000Z",
            "backupFileName": "file1.swift.1705314600.bak"
          },
          "/path/to/file2.swift": {
            "version": 2,
            "backupTime": "2024-01-15T10:30:01.000Z"
          }
        }
      }
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "test-transcript",
      projectId: "test-project",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertNotNil(result.fileSnapshot)
    XCTAssertEqual(result.fileSnapshot?.transcriptId, "test-transcript")
    XCTAssertEqual(result.fileSnapshot?.messageId, "test-uuid-123")
    XCTAssertEqual(result.fileSnapshot?.snapshotTimestamp, 1705314600)
    XCTAssertEqual(result.fileSnapshot?.isSnapshotUpdate, 1)

    XCTAssertEqual(result.trackedFiles.count, 2)

    // Find files by path (dictionary order is not guaranteed)
    let file1 = result.trackedFiles.first { $0.filePath == "/path/to/file1.swift" }
    let file2 = result.trackedFiles.first { $0.filePath == "/path/to/file2.swift" }

    XCTAssertNotNil(file1)
    XCTAssertEqual(file1?.version, 1)
    XCTAssertEqual(file1?.backupFilename, "file1.swift.1705314600.bak")

    XCTAssertNotNil(file2)
    XCTAssertEqual(file2?.version, 2)
    XCTAssertNil(file2?.backupFilename)
  }

  // MARK: - Summary Parsing

  func testParseTranscriptSummary() throws {
    let json = """
    {
      "uuid": "summary-uuid",
      "type": "summary",
      "timestamp": "2025-01-15T10:30:00.000Z",
      "summary": "Implemented metadata storage system",
      "leaf_uuid": "leaf-123",
      "cwd": "/Users/rob/code/project"
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "test-transcript",
      projectId: "test-project",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertNotNil(result.transcriptSummary)
    XCTAssertEqual(result.transcriptSummary?.transcriptId, "test-transcript")
    XCTAssertEqual(result.transcriptSummary?.summary, "Implemented metadata storage system")
    XCTAssertEqual(result.transcriptSummary?.leafUuid, "leaf-123")
    XCTAssertEqual(result.transcriptSummary?.cwd, "/Users/rob/code/project")
  }

  // MARK: - System Event Parsing

  func testParseSystemEvent() throws {
    let json = """
    {
      "uuid": "system-uuid",
      "type": "system",
      "timestamp": "2025-01-15T10:30:00.000Z",
      "subtype": "slash_command",
      "level": "info",
      "message": {
        "content": [
          {
            "text": "/build command executed"
          }
        ]
      }
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "test-transcript",
      projectId: "test-project",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertNotNil(result.systemEvent)
    XCTAssertEqual(result.systemEvent?.transcriptId, "test-transcript")
    XCTAssertEqual(result.systemEvent?.subtype, "slash_command")
    XCTAssertEqual(result.systemEvent?.level, "info")
    XCTAssertEqual(result.systemEvent?.content, "/build command executed")
  }

  // MARK: - Assistant Usage Parsing

  func testParseAssistantUsage() throws {
    let json = """
    {
      "uuid": "assistant-uuid",
      "type": "assistant",
      "timestamp": "2025-01-15T10:30:00.000Z",
      "message": {
        "id": "msg_123",
        "model": "claude-sonnet-4-5",
        "service_tier": "standard",
        "content": [
          {
            "text": "Here is the implementation..."
          }
        ],
        "usage": {
          "input_tokens": 1500,
          "output_tokens": 500,
          "cache_creation_input_tokens": 200,
          "cache_read_input_tokens": 800,
          "ephemeral_5m_tokens": 100,
          "ephemeral_1h_tokens": 50
        }
      }
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "test-transcript",
      projectId: "test-project",
      provider: "claude.code",
      entryId: "entry-123"
    )

    XCTAssertNotNil(result.assistantUsage)
    XCTAssertEqual(result.assistantUsage?.entryId, "entry-123")
    XCTAssertEqual(result.assistantUsage?.requestId, "msg_123")
    XCTAssertEqual(result.assistantUsage?.model, "claude-sonnet-4-5")
    XCTAssertEqual(result.assistantUsage?.inputTokens, 1500)
    XCTAssertEqual(result.assistantUsage?.outputTokens, 500)
    XCTAssertEqual(result.assistantUsage?.cacheCreationTokens, 200)
    XCTAssertEqual(result.assistantUsage?.cacheReadTokens, 800)
    XCTAssertEqual(result.assistantUsage?.serviceTier, "standard")
    XCTAssertEqual(result.assistantUsage?.ephemeral5mTokens, 100)
    XCTAssertEqual(result.assistantUsage?.ephemeral1hTokens, 50)
  }

  // MARK: - Queue Operations

  func testParseQueueOperation_RemoveWithoutContent() throws {
    // Claude Code's "remove" operation does NOT include the message content,
    // only the sessionId. We must parse it anyway (using FIFO matching in HooverEngine).
    let json = """
    {
      "uuid": "queue-uuid",
      "type": "queue-operation",
      "timestamp": "2025-01-15T10:30:00.000Z",
      "operation": "remove",
      "sessionId": "session-abc123"
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "test-transcript",
      projectId: "test-project",
      provider: "claude.code",
      entryId: nil
    )

    // Must produce a QueueOperation even without content
    XCTAssertEqual(result.queueOperations.count, 1)
    let op = result.queueOperations[0]
    XCTAssertEqual(op.kind, .remove)
    XCTAssertEqual(op.sessionId, "session-abc123")
    XCTAssertEqual(op.transcriptId, "test-transcript")
    XCTAssertNil(op.contentSha256, "Remove op should have nil contentSha256 for FIFO matching")
  }

  func testParseQueueOperation_PopAllClearsAllQueued() throws {
    // "popAll" clears all queued messages for a session
    let json = """
    {
      "uuid": "queue-uuid",
      "type": "queue-operation",
      "timestamp": "2025-01-15T10:30:00.000Z",
      "operation": "popAll",
      "sessionId": "session-abc123"
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "test-transcript",
      projectId: "test-project",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertEqual(result.queueOperations.count, 1)
    let op = result.queueOperations[0]
    XCTAssertEqual(op.kind, .popAll)
    XCTAssertEqual(op.sessionId, "session-abc123")
    XCTAssertNil(op.contentSha256, "popAll clears all, no content hash needed")
  }

  // MARK: - No Metadata

  func testParseUserMessage_NoMetadata() throws {
    let json = """
    {
      "uuid": "user-uuid",
      "type": "user",
      "timestamp": "2025-01-15T10:30:00.000Z",
      "message": {
        "content": [
          {
            "text": "Please help me with this code"
          }
        ]
      }
    }
    """

    let parser = ClaudeCodeMetadataParser()
    let result = try parser.parseMetadata(
      line: json,
      lineNumber: 1,
      transcriptId: "test-transcript",
      projectId: "test-project",
      provider: "claude.code",
      entryId: nil
    )

    XCTAssertFalse(result.hasMetadata)
    XCTAssertNil(result.fileSnapshot)
    XCTAssertNil(result.transcriptSummary)
    XCTAssertNil(result.systemEvent)
    XCTAssertNil(result.assistantUsage)
    XCTAssertTrue(result.trackedFiles.isEmpty)
  }
}
