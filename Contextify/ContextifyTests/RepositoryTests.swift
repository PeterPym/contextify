import XCTest
import GRDB
@testable import ContextifyCore

/// Regression tests for display_in_timeline filter enforcement
/// Prevents recurrence of bugs fixed in commit ad190448
final class RepositoryTests: XCTestCase {
  var tempDir: URL!
  var pool: DatabasePool!
  var projectRepo: ProjectRepositoryImpl!
  var transcriptRepo: TranscriptRepositoryImpl!
  var entryRepo: EntryRepositoryImpl!
  var projectId: String!
  var transcriptId: String!

  override func setUp() async throws {
    try await super.setUp()

    // Create temporary directory for test database
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Setup database with migrations
    let dbPath = tempDir.appendingPathComponent("test.db")
    var config = Configuration()
    config.foreignKeysEnabled = true
    pool = try DatabasePool(path: dbPath.path, configuration: config)
    let migrator = DatabaseSchema.createMigrator()
    try migrator.migrate(pool)

    // Setup repositories
    projectRepo = ProjectRepositoryImpl(db: pool)
    transcriptRepo = TranscriptRepositoryImpl(db: pool)
    entryRepo = EntryRepositoryImpl(db: pool)

    // Create test project and transcript
    projectId = try projectRepo.create(name: "Test Project", rootPath: "/test", bookmark: nil)
    transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: URL(fileURLWithPath: "/test/transcript.jsonl"),
      provider: "claude.code",
      providerSessionId: "session-test",
      lastModified: Date(),
      fileSize: 1024
    )
  }

  override func tearDown() async throws {
    try await super.tearDown()

    // Clean up temp directory
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - Helper Methods

  /// Create a test entry with specified displayInTimeline value
  private func createEntry(
    content: String,
    displayInTimeline: Int,
    timestamp: Int? = nil
  ) throws -> TranscriptEntry {
    let now = timestamp ?? Int(Date().timeIntervalSince1970)
    let entry = TranscriptEntry(
      id: UUID().uuidString,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: "session-test",
      provider: "claude.code",
      kind: "user",
      timestamp: now,
      content: content,
      contentSha256: SHA256Utils.hash(content),
      displayInTimeline: displayInTimeline,
      parentId: nil,
      gitBranch: nil,
      gitCommit: nil,
      cwd: nil,
      prev1Id: nil,
      prev2Id: nil,
      windowSha256: nil,
      createdTs: Double(now),
      createdAt: now,
      updatedAt: now
    )
    try entryRepo.insertBatch([entry])
    return entry
  }

  // MARK: - byTranscript() Filter Tests

  func testByTranscriptExcludesHiddenEntries() throws {
    // Given: mix of visible and hidden entries in the same transcript
    try createEntry(content: "Visible message 1", displayInTimeline: 1, timestamp: 1000)
    try createEntry(content: "Hidden message", displayInTimeline: 0, timestamp: 1001)
    try createEntry(content: "Visible message 2", displayInTimeline: 1, timestamp: 1002)

    // When: querying entries by transcript
    let entries = try entryRepo.byTranscript(transcriptId)

    // Then: only visible entries are returned
    XCTAssertEqual(entries.count, 2, "Should return only visible entries")
    XCTAssertTrue(
      entries.allSatisfy { $0.displayInTimeline == 1 },
      "All returned entries should have displayInTimeline == 1"
    )
    XCTAssertEqual(entries[0].content, "Visible message 1")
    XCTAssertEqual(entries[1].content, "Visible message 2")
  }

  func testByTranscriptWithTimestampFilterExcludesHidden() throws {
    // Given: entries before and after a timestamp, some hidden
    try createEntry(content: "Old visible", displayInTimeline: 1, timestamp: 1000)
    try createEntry(content: "Old hidden", displayInTimeline: 0, timestamp: 1001)
    try createEntry(content: "New visible", displayInTimeline: 1, timestamp: 2000)
    try createEntry(content: "New hidden", displayInTimeline: 0, timestamp: 2001)

    // When: querying entries after timestamp 1500
    let entries = try entryRepo.byTranscript(transcriptId, afterTimestamp: 1500)

    // Then: only visible entries after timestamp are returned
    XCTAssertEqual(entries.count, 1, "Should return only visible entries after timestamp")
    XCTAssertEqual(entries[0].content, "New visible")
    XCTAssertEqual(entries[0].displayInTimeline, 1)
  }

  func testByTranscriptReturnsEmptyWhenAllHidden() throws {
    // Given: only hidden entries
    try createEntry(content: "Hidden 1", displayInTimeline: 0, timestamp: 1000)
    try createEntry(content: "Hidden 2", displayInTimeline: 0, timestamp: 1001)

    // When: querying entries
    let entries = try entryRepo.byTranscript(transcriptId)

    // Then: empty array is returned
    XCTAssertEqual(entries.count, 0, "Should return empty array when all entries are hidden")
  }

  // MARK: - search() Filter Tests

  func testSearchExcludesHiddenEntries() throws {
    // Given: mix of visible and hidden entries with matching content
    try createEntry(content: "Test message visible", displayInTimeline: 1, timestamp: 1000)
    try createEntry(content: "Test message hidden", displayInTimeline: 0, timestamp: 1001)
    try createEntry(content: "Another test visible", displayInTimeline: 1, timestamp: 1002)

    // When: searching for "test"
    let entries = try entryRepo.search(content: "test", projectId: projectId)

    // Then: only visible entries are returned
    XCTAssertEqual(entries.count, 2, "Should return only visible entries matching search")
    XCTAssertTrue(
      entries.allSatisfy { $0.displayInTimeline == 1 },
      "All search results should have displayInTimeline == 1"
    )
    XCTAssertTrue(entries[0].content.lowercased().contains("test"))
    XCTAssertTrue(entries[1].content.lowercased().contains("test"))
  }

  func testSearchWithoutProjectFilterExcludesHidden() throws {
    // Given: entries across projects, some hidden
    let project2Id = try projectRepo.create(name: "Project 2", rootPath: "/test2", bookmark: nil)
    let transcript2Id = try transcriptRepo.upsert(
      projectId: project2Id,
      fileURL: URL(fileURLWithPath: "/test2/transcript.jsonl"),
      provider: "claude.code",
      providerSessionId: "session-test-2",
      lastModified: Date(),
      fileSize: 1024
    )

    // Create entries in first project
    try createEntry(content: "Search term visible", displayInTimeline: 1, timestamp: 1000)
    try createEntry(content: "Search term hidden", displayInTimeline: 0, timestamp: 1001)

    // Create entries in second project
    let now = Int(Date().timeIntervalSince1970)
    let entry2 = TranscriptEntry(
      id: UUID().uuidString,
      transcriptId: transcript2Id,
      projectId: project2Id,
      sessionId: "session-test-2",
      provider: "claude.code",
      kind: "user",
      timestamp: now,
      content: "Search term in project 2",
      contentSha256: SHA256Utils.hash("Search term in project 2"),
      displayInTimeline: 1,
      parentId: nil,
      gitBranch: nil,
      gitCommit: nil,
      cwd: nil,
      prev1Id: nil,
      prev2Id: nil,
      windowSha256: nil,
      createdTs: Double(now),
      createdAt: now,
      updatedAt: now
    )
    try entryRepo.insertBatch([entry2])

    // When: searching across all projects (no projectId filter)
    let entries = try entryRepo.search(content: "Search term", projectId: nil)

    // Then: only visible entries are returned from all projects
    XCTAssertEqual(entries.count, 2, "Should return visible entries from all projects")
    XCTAssertTrue(
      entries.allSatisfy { $0.displayInTimeline == 1 },
      "All search results should be visible"
    )
  }

  func testSearchReturnsEmptyWhenOnlyHiddenMatch() throws {
    // Given: only hidden entries match search
    try createEntry(content: "Unique search term", displayInTimeline: 0, timestamp: 1000)
    try createEntry(content: "Visible but different", displayInTimeline: 1, timestamp: 1001)

    // When: searching for term that only matches hidden entry
    let entries = try entryRepo.search(content: "Unique", projectId: projectId)

    // Then: empty array is returned
    XCTAssertEqual(entries.count, 0, "Should return empty when only hidden entries match")
  }

  // MARK: - entriesAfterCursor() Filter Tests

  func testEntriesAfterCursorWithCursorExcludesHidden() throws {
    // Given: entries before and after cursor, some hidden
    let visible1 = try createEntry(content: "Before cursor visible", displayInTimeline: 1, timestamp: 1000)
    try createEntry(content: "Before cursor hidden", displayInTimeline: 0, timestamp: 1001)
    try createEntry(content: "After cursor visible", displayInTimeline: 1, timestamp: 2000)
    try createEntry(content: "After cursor hidden", displayInTimeline: 0, timestamp: 2001)

    // When: querying entries after a cursor
    let cursor = (timestamp: visible1.timestamp, createdAt: visible1.createdAt, id: visible1.id)
    let entries = try entryRepo.entriesAfterCursor(projectId: projectId, after: cursor)

    // Then: only visible entries after cursor are returned
    XCTAssertEqual(entries.count, 1, "Should return only visible entries after cursor")
    XCTAssertEqual(entries[0].content, "After cursor visible")
    XCTAssertEqual(entries[0].displayInTimeline, 1)
    XCTAssertGreaterThan(entries[0].timestamp, cursor.timestamp)
  }

  func testEntriesAfterCursorHandlesEdgeCaseAtSameTimestamp() throws {
    // Given: multiple entries at same timestamp with different created_at/id
    let baseTimestamp = 1000
    let entry1 = try createEntry(content: "Entry 1 visible", displayInTimeline: 1, timestamp: baseTimestamp)
    try createEntry(content: "Entry 2 hidden", displayInTimeline: 0, timestamp: baseTimestamp)
    let entry3 = try createEntry(content: "Entry 3 visible", displayInTimeline: 1, timestamp: baseTimestamp)

    // Wait a moment to ensure different created_at times
    try Task.sleep(nanoseconds: 10_000_000) // 10ms

    try createEntry(content: "Entry 4 visible", displayInTimeline: 1, timestamp: baseTimestamp)

    // When: querying after first entry
    let cursor = (timestamp: entry1.timestamp, createdAt: entry1.createdAt, id: entry1.id)
    let entries = try entryRepo.entriesAfterCursor(projectId: projectId, after: cursor)

    // Then: only visible entries after cursor (using tuple comparison) are returned
    XCTAssertGreaterThan(entries.count, 0, "Should return entries after cursor")
    XCTAssertTrue(
      entries.allSatisfy { $0.displayInTimeline == 1 },
      "All entries should be visible"
    )
    // Verify entries are actually after the cursor (by tuple comparison)
    for entry in entries {
      let isAfter = entry.timestamp > cursor.timestamp ||
        (entry.timestamp == cursor.timestamp && entry.createdAt > cursor.createdAt) ||
        (entry.timestamp == cursor.timestamp && entry.createdAt == cursor.createdAt && entry.id > cursor.id)
      XCTAssertTrue(isAfter, "Entry should be after cursor by tuple comparison")
    }
  }

  // MARK: - TranscriptOrchestrator getEntriesAfterCursor() Tests

  func testOrchestratorGetEntriesAfterCursorWithCursorExcludesHidden() throws {
    // Setup orchestrator
    let dbPath = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    // Given: entries with mix of visible and hidden
    let visible1 = try createEntry(content: "First visible", displayInTimeline: 1, timestamp: 1000)
    try createEntry(content: "Hidden entry", displayInTimeline: 0, timestamp: 1500)
    try createEntry(content: "Second visible", displayInTimeline: 1, timestamp: 2000)

    // When: querying with cursor
    let cursor = EntryCursor(timestamp: visible1.timestamp, createdAt: visible1.createdAt, id: visible1.id)
    let entries = try orchestrator.getEntriesAfterCursor(projectId: projectId, after: cursor)

    // Then: only visible entries after cursor are returned
    XCTAssertEqual(entries.count, 1, "Should return only visible entries after cursor")
    XCTAssertEqual(entries[0].content, "Second visible")
    XCTAssertEqual(entries[0].displayInTimeline, 1)
  }

  func testOrchestratorGetEntriesAfterCursorWithoutCursorExcludesHidden() throws {
    // Setup orchestrator
    let dbPath = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    // Given: mix of visible and hidden entries
    try createEntry(content: "Visible 1", displayInTimeline: 1, timestamp: 1000)
    try createEntry(content: "Hidden 1", displayInTimeline: 0, timestamp: 1500)
    try createEntry(content: "Visible 2", displayInTimeline: 1, timestamp: 2000)
    try createEntry(content: "Hidden 2", displayInTimeline: 0, timestamp: 2500)

    // When: querying without cursor (initial load)
    let entries = try orchestrator.getEntriesAfterCursor(projectId: projectId, after: nil)

    // Then: only visible entries are returned
    XCTAssertEqual(entries.count, 2, "Should return only visible entries")
    XCTAssertTrue(
      entries.allSatisfy { $0.displayInTimeline == 1 },
      "All entries should be visible"
    )
    XCTAssertEqual(entries[0].content, "Visible 1")
    XCTAssertEqual(entries[1].content, "Visible 2")
  }

  // MARK: - Integration Test: Real-world Scenario

  func testRealWorldScenarioMixedHiddenAndVisibleEntries() throws {
    // Setup orchestrator
    let dbPath = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    // Given: realistic conversation with hidden system entries
    try createEntry(content: "User: Hello", displayInTimeline: 1, timestamp: 1000)
    try createEntry(content: "System: Session started", displayInTimeline: 0, timestamp: 1001)
    try createEntry(content: "Assistant: Hi there!", displayInTimeline: 1, timestamp: 1002)
    try createEntry(content: "System: Tool execution", displayInTimeline: 0, timestamp: 1003)
    try createEntry(content: "User: Can you help?", displayInTimeline: 1, timestamp: 1004)
    try createEntry(content: "System: Internal state", displayInTimeline: 0, timestamp: 1005)
    try createEntry(content: "Assistant: Of course!", displayInTimeline: 1, timestamp: 1006)

    // When: loading initial timeline
    let initialEntries = try orchestrator.getEntriesAfterCursor(projectId: projectId, after: nil)

    // Then: only user and assistant messages are visible
    XCTAssertEqual(initialEntries.count, 4, "Should return 4 visible entries")
    XCTAssertTrue(
      initialEntries.allSatisfy { $0.displayInTimeline == 1 },
      "All timeline entries should be visible"
    )

    // When: searching for "help"
    let searchResults = try entryRepo.search(content: "help", projectId: projectId)

    // Then: only visible entries matching search are returned
    XCTAssertEqual(searchResults.count, 1, "Should find 1 visible match")
    XCTAssertEqual(searchResults[0].content, "User: Can you help?")
    XCTAssertEqual(searchResults[0].displayInTimeline, 1)

    // When: loading incremental updates after third visible entry
    let thirdVisible = initialEntries[2]
    let cursor = EntryCursor(timestamp: thirdVisible.timestamp, createdAt: thirdVisible.createdAt, id: thirdVisible.id)
    let newEntries = try orchestrator.getEntriesAfterCursor(projectId: projectId, after: cursor)

    // Then: only new visible entries are returned
    XCTAssertEqual(newEntries.count, 1, "Should return 1 new visible entry")
    XCTAssertEqual(newEntries[0].content, "Assistant: Of course!")
    XCTAssertEqual(newEntries[0].displayInTimeline, 1)
  }
}
