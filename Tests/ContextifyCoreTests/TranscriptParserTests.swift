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

  // MARK: - Agent Result Attribution Tests

  func testAgentResult_attributedAsAssistant() throws {
    let parser = ClaudeCodeLineParser()

    // First, send the Task invocation to register the tool use
    let assistantLine = """
    {"type":"assistant","uuid":"assistant-task","timestamp":"2025-01-01T00:00:00Z","message":{"content":[{"type":"tool_use","id":"toolu_agent","name":"Task","input":{"subagent_type":"Explore","prompt":"Find code"}}]}}
    """
    _ = try parser.parse(
      line: assistantLine,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    // Agent result comes in as type="user" but should be attributed as "assistant"
    let agentResultLine = """
    {"type":"user","uuid":"agent-result","timestamp":"2025-01-01T00:00:01Z","toolUseResult":{"status":"completed","agentId":"agent-123"},"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_agent","content":[{"type":"text","text":"Agent found code"}]}]}}
    """

    let entry = try parser.parse(
      line: agentResultLine,
      lineNumber: 2,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    // Assert: Agent result should be attributed as assistant, not user
    XCTAssertEqual(entry.kind, "assistant", "Agent result should be attributed as assistant")
    XCTAssertEqual(entry.content, "Agent found code")
    XCTAssertTrue(entry.hasTextContent, "Agent result should be visible")
  }

  func testAgentResult_withShellOutput_notHidden() throws {
    let parser = ClaudeCodeLineParser()

    // First, send the Task invocation
    let assistantLine = """
    {"type":"assistant","uuid":"assistant-task","timestamp":"2025-01-01T00:00:00Z","message":{"content":[{"type":"tool_use","id":"toolu_agent","name":"Task","input":{"subagent_type":"Explore","prompt":"Run command"}}]}}
    """
    _ = try parser.parse(
      line: assistantLine,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    // Agent result with shell-like output (should NOT be hidden unlike regular user shell output)
    let agentResultLine = """
    {"type":"user","uuid":"agent-result","timestamp":"2025-01-01T00:00:01Z","toolUseResult":{"status":"completed","agentId":"agent-123"},"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_agent","content":[{"type":"text","text":"<bash-stdout>ls output</bash-stdout>"}]}]}}
    """

    let entry = try parser.parse(
      line: agentResultLine,
      lineNumber: 2,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    // Assert: Agent result with shell output should still be visible
    XCTAssertTrue(entry.hasTextContent, "Agent result with shell output should NOT be hidden")
    XCTAssertEqual(entry.kind, "assistant", "Agent result should be attributed as assistant")
  }

  func testRegularUserShellOutput_stillHidden() throws {
    let parser = ClaudeCodeLineParser()

    // Regular user shell output (NOT an agent result) should still be hidden
    let userShellLine = """
    {"type":"user","uuid":"user-shell","timestamp":"2025-01-01T00:00:00Z","message":{"content":"<bash-stdout>ls output</bash-stdout><bash-stderr></bash-stderr>"}}
    """

    let entry = try parser.parse(
      line: userShellLine,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: "session"
    )

    // Assert: Regular user shell output should be hidden
    XCTAssertFalse(entry.hasTextContent, "Regular user shell output should be hidden")
    XCTAssertEqual(entry.kind, "user", "Regular user should remain as user")
  }

  // MARK: - Format Drift Tests (ct-1095)

  func testNewMetadataRecordTypes_AreSkipped() throws {
    let parser = ClaudeCodeLineParser()
    let newTypes = [
      "attachment",
      "last-prompt",
      "permission-mode",
      "progress",
      "agent-name",
      "custom-title",
      "pr-link",
    ]

    for recordType in newTypes {
      let line = """
      {"type":"\(recordType)","uuid":"skip-\(recordType)","timestamp":"2025-01-01T00:00:00Z","message":{"content":[{"type":"text","text":"should be skipped"}]}}
      """
      XCTAssertThrowsError(
        try parser.parse(
          line: line,
          lineNumber: 1,
          transcriptId: transcriptId,
          projectId: projectId,
          provider: "claude.code",
          sessionId: nil
        ),
        "Record type '\(recordType)' should be skipped"
      ) { error in
        guard case ParserError.skipEntry = error else {
          XCTFail("Expected ParserError.skipEntry for '\(recordType)', got \(error)")
          return
        }
      }
    }
  }

  func testCompoundSystemTypes_AreSkipped() throws {
    let parser = ClaudeCodeLineParser()
    let compoundTypes = [
      "system/turn_duration",
      "system/usage_summary",
      "system/other_subtype",
    ]

    for recordType in compoundTypes {
      let line = """
      {"type":"\(recordType)","uuid":"sys-\(recordType)","timestamp":"2025-01-01T00:00:00Z"}
      """
      XCTAssertThrowsError(
        try parser.parse(
          line: line,
          lineNumber: 1,
          transcriptId: transcriptId,
          projectId: projectId,
          provider: "claude.code",
          sessionId: nil
        ),
        "Compound system type '\(recordType)' should be skipped"
      ) { error in
        guard case ParserError.skipEntry = error else {
          XCTFail("Expected ParserError.skipEntry for '\(recordType)', got \(error)")
          return
        }
      }
    }
  }

  func testSlugAndEntrypoint_ExtractedFromUserRecord() throws {
    let parser = ClaudeCodeLineParser()
    let line = """
    {"type":"user","uuid":"slug-test","timestamp":"2025-01-01T00:00:00Z","slug":"my-project-slug","entrypoint":"my-entrypoint","message":{"content":"Hello world"}}
    """

    let entry = try parser.parse(
      line: line,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertEqual(entry.slug, "my-project-slug")
    XCTAssertEqual(entry.entrypoint, "my-entrypoint")
    XCTAssertEqual(entry.content, "Hello world")
  }

  func testSlugAndEntrypoint_ExtractedFromAssistantRecord() throws {
    let parser = ClaudeCodeLineParser()
    let line = """
    {"type":"assistant","uuid":"slug-assist","timestamp":"2025-01-01T00:00:00Z","slug":"assist-slug","entrypoint":"assist-entry","message":{"content":[{"type":"text","text":"Response"}]}}
    """

    let entry = try parser.parse(
      line: line,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertEqual(entry.slug, "assist-slug")
    XCTAssertEqual(entry.entrypoint, "assist-entry")
  }

  func testSlugAndEntrypoint_NilWhenAbsent() throws {
    let parser = ClaudeCodeLineParser()
    let line = """
    {"type":"user","uuid":"no-slug","timestamp":"2025-01-01T00:00:00Z","message":{"content":"No slug here"}}
    """

    let entry = try parser.parse(
      line: line,
      lineNumber: 1,
      transcriptId: transcriptId,
      projectId: projectId,
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertNil(entry.slug)
    XCTAssertNil(entry.entrypoint)
  }
}
