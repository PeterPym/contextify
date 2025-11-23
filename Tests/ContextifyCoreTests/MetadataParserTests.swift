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
      "snapshotTimestamp": 1705314600,
      "files": [
        {
          "path": "/path/to/file1.swift",
          "version": 1,
          "backupTime": 1705314600,
          "backupFilename": "file1.swift.1705314600.bak"
        },
        {
          "path": "/path/to/file2.swift",
          "version": 2,
          "backupTime": 1705314601
        }
      ]
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
    XCTAssertEqual(result.trackedFiles[0].filePath, "/path/to/file1.swift")
    XCTAssertEqual(result.trackedFiles[0].version, 1)
    XCTAssertEqual(result.trackedFiles[0].backupFilename, "file1.swift.1705314600.bak")

    XCTAssertEqual(result.trackedFiles[1].filePath, "/path/to/file2.swift")
    XCTAssertEqual(result.trackedFiles[1].version, 2)
    XCTAssertNil(result.trackedFiles[1].backupFilename)
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
