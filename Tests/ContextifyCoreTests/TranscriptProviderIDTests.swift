import XCTest
@testable import ContextifyCore

/// Tests for TranscriptProviderID provider derivation from URLs
final class TranscriptProviderIDTests: XCTestCase {

  // MARK: - fromTranscriptURL Tests

  func testFromTranscriptURLReturnsClaudeForClaudePath() {
    let url = URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code/session.jsonl")
    XCTAssertEqual(TranscriptProviderID.fromTranscriptURL(url), TranscriptProviderID.claude)
  }

  func testFromTranscriptURLReturnsCodexForCodexPath() {
    let url = URL(fileURLWithPath: "/Users/rob/.codex/sessions/2025/11/30/rollout.jsonl")
    XCTAssertEqual(TranscriptProviderID.fromTranscriptURL(url), TranscriptProviderID.codex)
  }

  func testFromTranscriptURLReturnsNilForUnknownPath() {
    let url = URL(fileURLWithPath: "/Users/rob/Downloads/random.jsonl")
    XCTAssertNil(TranscriptProviderID.fromTranscriptURL(url))
  }

  func testFromTranscriptURLHandlesMixedBatch() {
    let urls = [
      "/Users/rob/.claude/projects/-Users-rob-code/session1.jsonl",
      "/Users/rob/.codex/sessions/2025/11/30/rollout1.jsonl",
      "/Users/rob/.claude/projects/-Users-rob-code/session2.jsonl",
      "/Users/rob/.codex/sessions/2025/11/30/rollout2.jsonl",
    ].map { URL(fileURLWithPath: $0) }

    let providers = urls.compactMap { TranscriptProviderID.fromTranscriptURL($0) }

    XCTAssertEqual(providers, [
      TranscriptProviderID.claude,
      TranscriptProviderID.codex,
      TranscriptProviderID.claude,
      TranscriptProviderID.codex
    ])
  }

  // MARK: - Edge Cases

  func testFromTranscriptURLHandlesNestedClaudePath() {
    // Ensure we match /.claude/ not just "claude" anywhere in path
    let url = URL(fileURLWithPath: "/Users/claude/.claude/projects/test/session.jsonl")
    XCTAssertEqual(TranscriptProviderID.fromTranscriptURL(url), TranscriptProviderID.claude)
  }

  func testFromTranscriptURLHandlesNestedCodexPath() {
    let url = URL(fileURLWithPath: "/home/user/.codex/sessions/2025/01/01/test.jsonl")
    XCTAssertEqual(TranscriptProviderID.fromTranscriptURL(url), TranscriptProviderID.codex)
  }

  func testFromTranscriptURLDoesNotMatchPartialPaths() {
    // "claude" without the dot-prefix shouldn't match
    let url = URL(fileURLWithPath: "/Users/rob/claude/projects/test.jsonl")
    XCTAssertNil(TranscriptProviderID.fromTranscriptURL(url))
  }
}
