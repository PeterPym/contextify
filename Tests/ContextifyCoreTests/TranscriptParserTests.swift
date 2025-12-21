@testable import ContextifyCore
import XCTest

final class TranscriptParserTests: XCTestCase {
  private let projectId = "proj"
  private let transcriptId = "transcript"

  func testToolResultMatchesKnownToolUse() throws {
    let parser = ClaudeCodeLineParser()
    parser.debug_resetTelemetry()

    let assistantLine = """
    {"type":"assistant","uuid":"assistant-1","timestamp":"2025-11-16T12:00:00Z","message":{"content":[{"type":"tool_use","id":"toolu_123","name":"bash","input":{"command":"ls"}}],"stop_reason":"tool_use"}}
    """

    // Tool_use messages now produce entries (Issue #2 fix)
    let assistantEntry = try parser.parse(
      line: assistantLine,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    XCTAssertEqual(assistantEntry.kind, "assistant")
    XCTAssertTrue(assistantEntry.content.contains("[Tool: bash]"), "Tool use should be indexed as searchable marker")
    XCTAssertFalse(assistantEntry.hasTextContent, "Tool-only entries should be hidden from timeline")

    // Tool_result-only messages are skipped (structural), so add text content for timeline display
    let userLine = """
    {"type":"user","uuid":"user-1","timestamp":"2025-11-16T12:00:01Z","message":{"content":[{"type":"text","text":"Command output"},{"type":"tool_result","tool_use_id":"toolu_123","content":"ok"}]}}
    """

    let entry = try parser.parse(
      line: userLine,
      lineNumber: 2,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    XCTAssertEqual(entry.kind, "user")
    XCTAssertEqual(entry.content, "Command output")

    let telemetry = parser.debug_telemetrySnapshot()
    XCTAssertEqual(telemetry.toolResultValidated, 1)
    XCTAssertEqual(telemetry.toolResultMissing, 0)
    XCTAssertEqual(telemetry.stopReasonCoerced, 0)
  }

  func testToolResultMissingToolUseIncrementsMetric() throws {
    let parser = ClaudeCodeLineParser()
    parser.debug_resetTelemetry()

    // Tool_result-only messages are skipped (structural), so add text content for timeline display
    let userLine = """
    {"type":"user","uuid":"user-2","timestamp":"2025-11-16T12:00:05Z","message":{"content":[{"type":"text","text":"Error output"},{"type":"tool_result","tool_use_id":"toolu_missing","content":"stderr"}]}}
    """

    _ = try parser.parse(
      line: userLine,
      lineNumber: 1,
      transcriptId: "other-transcript",
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    let telemetry = parser.debug_telemetrySnapshot()
    XCTAssertEqual(telemetry.toolResultValidated, 0)
    XCTAssertEqual(telemetry.toolResultMissing, 1)
  }

  func testStopReasonCoercionRecordsMetric() throws {
    let parser = ClaudeCodeLineParser()
    parser.debug_resetTelemetry()

    let assistantLine = """
    {"type":"assistant","uuid":"assistant-2","timestamp":"2025-11-16T12:00:10Z","message":{"content":[{"type":"text","text":"thinking..."}],"stop_reason":"tool_use"}}
    """

    _ = try parser.parse(
      line: assistantLine,
      lineNumber: 1,
      transcriptId: "stop-reason",
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    let telemetry = parser.debug_telemetrySnapshot()
    XCTAssertEqual(telemetry.stopReasonCoerced, 1)
  }

  func testBashStdoutEntriesHidden() throws {
    let parser = ClaudeCodeLineParser()

    let bashOutputLine = """
    {"type":"user","uuid":"bash-stdout","timestamp":"2025-11-24T12:00:00Z","message":{"content":"<bash-stdout>output</bash-stdout><bash-stderr></bash-stderr>"},"parentUuid":"input-uuid"}
    """

    let entry = try parser.parse(
      line: bashOutputLine,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    XCTAssertFalse(entry.hasTextContent, "Shell stdout entries should be hidden from the timeline")
  }

  // MARK: - Tool Use Extraction Tests (Issue #2 fix)

  func testToolUseOnlyMessage() throws {
    let parser = ClaudeCodeLineParser()
    let line = """
    {"type":"assistant","uuid":"test-uuid","timestamp":"2025-01-01T00:00:00Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/test"}}]}}
    """

    let entry = try parser.parse(
      line: line,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertTrue(entry.content.contains("[Tool: Read]"), "Tool use blocks should be extracted as searchable markers")
    XCTAssertFalse(entry.hasTextContent, "Tool-only entries should be hidden from timeline")
  }

  func testMixedContentBlocks_NoiseFilter() throws {
    let parser = ClaudeCodeLineParser()
    let line = """
    {"type":"assistant","uuid":"test-uuid","timestamp":"2025-01-01T00:00:00Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Analyzing..."},{"type":"tool_use","name":"Grep","input":{}},{"type":"text","text":"Found results"}]}}
    """

    let entry = try parser.parse(
      line: line,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertTrue(entry.content.contains("Analyzing"), "Thinking content should be included")
    XCTAssertTrue(entry.content.contains("Found results"), "Text content should be included")
    XCTAssertFalse(entry.content.contains("[Tool:"), "Tool markers should be filtered out when text is present (noise filter)")
    XCTAssertTrue(entry.hasTextContent, "Messages with text blocks should be displayable")
  }

  func testSidechainEntryIsParsed() throws {
    let parser = ClaudeCodeLineParser()
    let line = """
    {"type":"assistant","uuid":"sidechain-1","timestamp":"2025-01-01T00:00:00Z","isSidechain":true,"agentId":"agent-123","message":{"role":"assistant","content":[{"type":"text","text":"Sidechain response"}]}}
    """

    let entry = try parser.parse(
      line: line,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertEqual(entry.content, "Sidechain response")
    XCTAssertTrue(entry.isSidechain)
    XCTAssertEqual(entry.agentId, "agent-123")
  }

  func testTaskToolUseAndResultExtraction() throws {
    let parser = ClaudeCodeLineParser()

    let assistantLine = """
    {"type":"assistant","uuid":"assistant-task","timestamp":"2025-01-01T00:00:00Z","message":{"content":[{"type":"tool_use","id":"toolu_task","name":"Task","input":{"subagent_type":"query:contextify-researcher","prompt":"Find things"}}]}}
    """

    let assistantEntry = try parser.parse(
      line: assistantLine,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    XCTAssertEqual(assistantEntry.toolInvocations.count, 1)
    XCTAssertEqual(assistantEntry.toolInvocations.first?.toolName, "Task")
    XCTAssertEqual(assistantEntry.toolInvocations.first?.toolKey, "query:contextify-researcher")
    XCTAssertTrue(assistantEntry.toolInvocations.first?.isContextify ?? false)

    let userLine = """
    {"type":"user","uuid":"user-task","timestamp":"2025-01-01T00:00:01Z","toolUseResult":{"status":"completed","agentId":"agent-xyz"},"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_task","content":[{"type":"text","text":"Agent output"}]}]}}
    """

    let userEntry = try parser.parse(
      line: userLine,
      lineNumber: 2,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    XCTAssertEqual(userEntry.content, "Agent output")
    XCTAssertTrue(userEntry.hasTextContent)
    XCTAssertEqual(userEntry.toolResultData.count, 1)
    XCTAssertEqual(userEntry.toolResultData.first?.agentId, "agent-xyz")
    XCTAssertEqual(userEntry.toolResultData.first?.status, "completed")
  }

  func testThinkingOnlyMessage() throws {
    let parser = ClaudeCodeLineParser()
    let line = """
    {"type":"assistant","uuid":"test-uuid","timestamp":"2025-01-01T00:00:00Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Planning approach"}]}}
    """

    let entry = try parser.parse(
      line: line,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertTrue(entry.content.contains("Planning approach"), "Thinking content should be extracted")
    XCTAssertFalse(entry.hasTextContent, "Thinking-only entries should be hidden from timeline")
  }

  func testBackwardsCompat_MissingTypeField_Text() throws {
    let parser = ClaudeCodeLineParser()
    let line = """
    {"type":"assistant","uuid":"test-uuid","timestamp":"2025-01-01T00:00:00Z","message":{"role":"assistant","content":[{"text":"Hello"}]}}
    """

    let entry = try parser.parse(
      line: line,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertTrue(entry.content.contains("Hello"), "Text blocks without type field should still be extracted")
    XCTAssertTrue(entry.hasTextContent, "Text content should be displayable")
  }

  func testBackwardsCompat_MissingTypeField_ToolUse() throws {
    let parser = ClaudeCodeLineParser()
    let line = """
    {"type":"assistant","uuid":"test-uuid","timestamp":"2025-01-01T00:00:00Z","message":{"role":"assistant","content":[{"name":"Read","input":{"file_path":"/test"}}]}}
    """

    let entry = try parser.parse(
      line: line,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertTrue(entry.content.contains("[Tool: Read]"), "Tool use blocks without type field should be detected via shape")
    XCTAssertFalse(entry.hasTextContent, "Tool markers are not displayable text")
  }
}
