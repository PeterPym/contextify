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

    XCTAssertThrowsError(
      try parser.parse(
        line: assistantLine,
        lineNumber: 1,
        transcriptId: transcriptId,
        projectId: projectId,
        provider: "claude.code",
        sessionId: "session"
      )
    )

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
}
