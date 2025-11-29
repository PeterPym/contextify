import XCTest
import GRDB
@testable import ContextifyCore

/// Tests for FastPathIngestionCoordinator, particularly the sidechain transcript prioritization logic.
final class FastPathIngestionTests: XCTestCase {
  var tempDir: URL!

  override func setUp() async throws {
    try await super.setUp()

    // Create temporary directory for test database
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try await super.tearDown()

    // Clean up temp directory
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - prioritizeForFastPath Tests

  /// Test that main conversation files are prioritized over sidechain/agent files.
  /// This is the core fix for the sidechain transcript bug where agent-*.jsonl files
  /// were being processed first and producing 0 entries.
  func testPrioritizeForFastPath_MainFilesBeforeAgentFiles() async throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let coordinator = FastPathIngestionCoordinator(orchestrator: orchestrator)

    // Create test transcripts mimicking real-world scenario:
    // - 11 agent-*.jsonl sidechain files (small, ~1KB each)
    // - 1 main session file (large, 31KB)

    // Create main session transcript (large file)
    let mainTranscript = makeTranscript(
      id: "343a0493-bc8b-43de-8ca6-5ae9c7394fa2",
      filePath: "/test/project/343a0493-bc8b-43de-8ca6-5ae9c7394fa2.jsonl",
      fileSize: 31830  // 31KB - main conversation
    )

    // Create sidechain transcripts (small files)
    let sidechainIds = [
      "agent-10bae299", "agent-30cc28b5", "agent-4ff1bfb1",
      "agent-5e0aea26", "agent-63cdf9fc", "agent-65788c07",
      "agent-a5d1bc56", "agent-a7e91dd6", "agent-a914b912",
      "agent-f2989f55", "agent-f6e98e45"
    ]

    let sidechainTranscripts = sidechainIds.enumerated().map { index, id in
      makeTranscript(
        id: id,
        filePath: "/test/project/\(id).jsonl",
        fileSize: 850 + index * 100  // 850-1950 bytes - small sidechain files
      )
    }

    // Combine transcripts in "worst case" order: all sidechains first, main last
    // This mimics the order that caused the bug (alphabetical/insertion order)
    var allTranscripts = sidechainTranscripts
    allTranscripts.append(mainTranscript)

    // Run prioritization
    let prioritized = await coordinator.prioritizeForFastPath(allTranscripts)

    // Verify main transcript is first
    XCTAssertEqual(prioritized.first?.id, mainTranscript.id,
      "Main conversation file should be first after prioritization")

    // Verify main transcript is NOT an agent file
    let firstFileName = URL(fileURLWithPath: prioritized.first!.filePath).lastPathComponent
    XCTAssertFalse(firstFileName.hasPrefix("agent-"),
      "First prioritized transcript should not be an agent file")

    // Verify taking first 5 includes the main transcript
    let firstFive = Array(prioritized.prefix(5))
    XCTAssertTrue(firstFive.contains(where: { $0.id == mainTranscript.id }),
      "First 5 transcripts should include the main conversation file")
  }

  /// Test that among non-agent files, larger files are prioritized.
  func testPrioritizeForFastPath_LargerFilesFirst() async throws {
    let dbPath = tempDir.appendingPathComponent("test2.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let coordinator = FastPathIngestionCoordinator(orchestrator: orchestrator)

    // Create multiple main session transcripts with different sizes
    let transcripts = [
      makeTranscript(id: "small-session", filePath: "/test/small-session.jsonl", fileSize: 1000),
      makeTranscript(id: "large-session", filePath: "/test/large-session.jsonl", fileSize: 50000),
      makeTranscript(id: "medium-session", filePath: "/test/medium-session.jsonl", fileSize: 10000),
    ]

    let prioritized = await coordinator.prioritizeForFastPath(transcripts)

    // Verify larger files come first
    XCTAssertEqual(prioritized[0].id, "large-session", "Largest file should be first")
    XCTAssertEqual(prioritized[1].id, "medium-session", "Medium file should be second")
    XCTAssertEqual(prioritized[2].id, "small-session", "Smallest file should be last")
  }

  /// Test that agent files are sorted by size among themselves (secondary sort).
  func testPrioritizeForFastPath_AgentFilesSortedBySize() async throws {
    let dbPath = tempDir.appendingPathComponent("test3.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let coordinator = FastPathIngestionCoordinator(orchestrator: orchestrator)

    // Create only agent transcripts
    let transcripts = [
      makeTranscript(id: "agent-small", filePath: "/test/agent-small.jsonl", fileSize: 500),
      makeTranscript(id: "agent-large", filePath: "/test/agent-large.jsonl", fileSize: 2000),
      makeTranscript(id: "agent-medium", filePath: "/test/agent-medium.jsonl", fileSize: 1000),
    ]

    let prioritized = await coordinator.prioritizeForFastPath(transcripts)

    // Verify agent files are sorted by size (largest first)
    XCTAssertEqual(prioritized[0].id, "agent-large", "Largest agent file should be first")
    XCTAssertEqual(prioritized[1].id, "agent-medium", "Medium agent file should be second")
    XCTAssertEqual(prioritized[2].id, "agent-small", "Smallest agent file should be last")
  }

  /// Test mixed scenario: non-agent files always come before agent files regardless of size.
  func testPrioritizeForFastPath_NonAgentAlwaysBeforeAgent() async throws {
    let dbPath = tempDir.appendingPathComponent("test4.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let coordinator = FastPathIngestionCoordinator(orchestrator: orchestrator)

    // Create mix where agent file is larger than main file
    let transcripts = [
      makeTranscript(id: "agent-huge", filePath: "/test/agent-huge.jsonl", fileSize: 100000),  // Large agent
      makeTranscript(id: "main-tiny", filePath: "/test/main-tiny.jsonl", fileSize: 100),  // Tiny main
    ]

    let prioritized = await coordinator.prioritizeForFastPath(transcripts)

    // Main file should still be first despite being smaller
    XCTAssertEqual(prioritized[0].id, "main-tiny",
      "Non-agent file should be first even if smaller than agent file")
    XCTAssertEqual(prioritized[1].id, "agent-huge",
      "Agent file should be second even if larger")
  }

  // MARK: - Helpers

  private func makeTranscript(id: String, filePath: String, fileSize: Int) -> Transcript {
    Transcript(
      id: id,
      projectId: "test-project",
      filePath: filePath,
      provider: "claude.code",
      providerSessionId: id,
      lastModified: Int(Date().timeIntervalSince1970),
      fileSize: fileSize,
      lineCount: 1,
      bookmark: nil,
      lastProcessedLine: 0,
      lastProcessedEntryId: nil,
      parserVersion: 1,
      status: "active",
      ingestState: "partial",
      lastError: nil,
      createdAt: Int(Date().timeIntervalSince1970),
      updatedAt: Int(Date().timeIntervalSince1970)
    )
  }
}
