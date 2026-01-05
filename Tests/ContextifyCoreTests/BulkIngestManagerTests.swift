import XCTest
import GRDB
@testable import ContextifyCore

final class BulkIngestManagerTests: XCTestCase {
  var tempDir: URL!
  var dbPath: URL!

  override func setUp() async throws {
    try await super.setUp()

    // Create temporary directory for test database
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    dbPath = tempDir.appendingPathComponent("test.db")

    // Create migrated database
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    _ = try dbManager.pool  // Triggers migration
  }

  override func tearDown() async throws {
    try await super.tearDown()

    // Clean up temp directory
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - Test: open() creates connection

  func testOpenCreatesConnection() throws {
    let manager = BulkIngestManager(dbPath: dbPath.path)

    XCTAssertFalse(manager.isOpen, "Manager should not be open initially")

    try manager.open()

    XCTAssertTrue(manager.isOpen, "Manager should be open after open() call")

    manager.close()
  }

  // MARK: - Test: close() releases connection

  func testCloseReleasesConnection() throws {
    let manager = BulkIngestManager(dbPath: dbPath.path)

    try manager.open()
    XCTAssertTrue(manager.isOpen)

    manager.close()
    XCTAssertFalse(manager.isOpen, "Manager should not be open after close()")

    // Verify close() can be called multiple times without error
    manager.close()
    manager.close()
    XCTAssertFalse(manager.isOpen, "Manager should remain closed after multiple close() calls")
  }

  // MARK: - Test: commitBatch inserts entries

  func testCommitBatchInsertsEntries() throws {
    let manager = BulkIngestManager(dbPath: dbPath.path)
    try manager.open()
    defer { manager.close() }

    // Create test project and transcript first (foreign key constraints)
    let pool = try DatabasePool(path: dbPath.path)
    let projectId = UUID().uuidString
    let transcriptId = UUID().uuidString
    let now = Int(Date().timeIntervalSince1970)

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, root_path, last_viewed_ts, hidden, is_orphaned, created_at, updated_at)
        VALUES (?, '/test/path', 0, 0, 0, ?, ?)
      """, arguments: [projectId, now, now])

      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count,
          last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES (?, ?, '/test/transcript.jsonl', 'claude.code', ?, 0, 0, 1, 'active', 'partial', ?, ?)
      """, arguments: [transcriptId, projectId, now, now, now])
    }

    // Create test entries
    let entries = [
      makeTestEntry(id: UUID().uuidString, transcriptId: transcriptId, projectId: projectId, kind: "user", content: "Hello"),
      makeTestEntry(id: UUID().uuidString, transcriptId: transcriptId, projectId: projectId, kind: "assistant", content: "Hi there")
    ]

    // Insert via bulk ingest
    let insertedCount = try manager.commitBatch(entries: entries, toolInvocations: [])

    XCTAssertEqual(insertedCount, 2, "Should insert 2 entries")

    // Verify entries exist in database
    let count = try pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = ?", arguments: [transcriptId])
    }
    XCTAssertEqual(count, 2, "Database should contain 2 entries")
  }

  // MARK: - Test: commitBatch inserts tool invocations

  func testCommitBatchInsertsToolInvocations() throws {
    let manager = BulkIngestManager(dbPath: dbPath.path)
    try manager.open()
    defer { manager.close() }

    // Create test project, transcript, and entry first
    let pool = try DatabasePool(path: dbPath.path)
    let projectId = UUID().uuidString
    let transcriptId = UUID().uuidString
    let entryId = UUID().uuidString
    let now = Int(Date().timeIntervalSince1970)

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, root_path, last_viewed_ts, hidden, is_orphaned, created_at, updated_at)
        VALUES (?, '/test/path', 0, 0, 0, ?, ?)
      """, arguments: [projectId, now, now])

      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count,
          last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES (?, ?, '/test/transcript.jsonl', 'claude.code', ?, 0, 0, 1, 'active', 'partial', ?, ?)
      """, arguments: [transcriptId, projectId, now, now, now])
    }

    // Create entry and tool invocations
    let entry = makeTestEntry(id: entryId, transcriptId: transcriptId, projectId: projectId, kind: "assistant", content: "Running tool")

    let toolInvocations = [
      makeTestToolInvocation(id: UUID().uuidString, entryId: entryId, transcriptId: transcriptId, toolName: "Read"),
      makeTestToolInvocation(id: UUID().uuidString, entryId: entryId, transcriptId: transcriptId, toolName: "Write")
    ]

    // Insert via bulk ingest
    _ = try manager.commitBatch(entries: [entry], toolInvocations: toolInvocations)

    // Verify tool invocations exist in database
    let count = try pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tool_invocations WHERE transcript_id = ?", arguments: [transcriptId])
    }
    XCTAssertEqual(count, 2, "Database should contain 2 tool invocations")

    // Verify tool names
    let toolNames = try pool.read { db in
      try String.fetchAll(db, sql: "SELECT tool_name FROM tool_invocations WHERE transcript_id = ? ORDER BY tool_name", arguments: [transcriptId])
    }
    XCTAssertEqual(toolNames, ["Read", "Write"])
  }

  // MARK: - Test: commitBatch returns inserted count

  func testCommitBatchReturnsInsertedCount() throws {
    let manager = BulkIngestManager(dbPath: dbPath.path)
    try manager.open()
    defer { manager.close() }

    // Create test project and transcript
    let pool = try DatabasePool(path: dbPath.path)
    let projectId = UUID().uuidString
    let transcriptId = UUID().uuidString
    let now = Int(Date().timeIntervalSince1970)

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, root_path, last_viewed_ts, hidden, is_orphaned, created_at, updated_at)
        VALUES (?, '/test/path', 0, 0, 0, ?, ?)
      """, arguments: [projectId, now, now])

      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count,
          last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES (?, ?, '/test/transcript.jsonl', 'claude.code', ?, 0, 0, 1, 'active', 'partial', ?, ?)
      """, arguments: [transcriptId, projectId, now, now, now])
    }

    // Insert 3 entries
    let entries = [
      makeTestEntry(id: UUID().uuidString, transcriptId: transcriptId, projectId: projectId, kind: "user", content: "One"),
      makeTestEntry(id: UUID().uuidString, transcriptId: transcriptId, projectId: projectId, kind: "assistant", content: "Two"),
      makeTestEntry(id: UUID().uuidString, transcriptId: transcriptId, projectId: projectId, kind: "user", content: "Three")
    ]

    let insertedCount = try manager.commitBatch(entries: entries, toolInvocations: [])

    XCTAssertEqual(insertedCount, 3, "Should return count of 3 inserted entries")
  }

  // MARK: - Test: commitBatch ignores duplicates

  func testCommitBatchIgnoresDuplicates() throws {
    let manager = BulkIngestManager(dbPath: dbPath.path)
    try manager.open()
    defer { manager.close() }

    // Create test project and transcript
    let pool = try DatabasePool(path: dbPath.path)
    let projectId = UUID().uuidString
    let transcriptId = UUID().uuidString
    let duplicateId = UUID().uuidString
    let now = Int(Date().timeIntervalSince1970)

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, root_path, last_viewed_ts, hidden, is_orphaned, created_at, updated_at)
        VALUES (?, '/test/path', 0, 0, 0, ?, ?)
      """, arguments: [projectId, now, now])

      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count,
          last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES (?, ?, '/test/transcript.jsonl', 'claude.code', ?, 0, 0, 1, 'active', 'partial', ?, ?)
      """, arguments: [transcriptId, projectId, now, now, now])
    }

    // Insert first batch with unique entry
    let entry1 = makeTestEntry(id: duplicateId, transcriptId: transcriptId, projectId: projectId, kind: "user", content: "Original")
    let count1 = try manager.commitBatch(entries: [entry1], toolInvocations: [])
    XCTAssertEqual(count1, 1, "First insert should succeed")

    // Insert second batch with same ID (duplicate)
    let entry2 = makeTestEntry(id: duplicateId, transcriptId: transcriptId, projectId: projectId, kind: "user", content: "Duplicate")
    let entry3 = makeTestEntry(id: UUID().uuidString, transcriptId: transcriptId, projectId: projectId, kind: "user", content: "New")

    let count2 = try manager.commitBatch(entries: [entry2, entry3], toolInvocations: [])

    // Should only count the new entry (duplicate is ignored via INSERT OR IGNORE)
    XCTAssertEqual(count2, 1, "Second batch should only insert 1 new entry, ignoring duplicate")

    // Verify total entries in database
    let totalCount = try pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = ?", arguments: [transcriptId])
    }
    XCTAssertEqual(totalCount, 2, "Database should contain 2 entries total")

    // Verify original content was preserved (not overwritten)
    let content = try pool.read { db in
      try String.fetchOne(db, sql: "SELECT content FROM transcript_entries WHERE id = ?", arguments: [duplicateId])
    }
    XCTAssertEqual(content, "Original", "Original entry content should be preserved")
  }

  // MARK: - Test: commitBatch without open throws

  func testCommitBatchWithoutOpenThrows() throws {
    let manager = BulkIngestManager(dbPath: dbPath.path)

    // Attempt to commit without opening
    let entries = [
      makeTestEntry(id: UUID().uuidString, transcriptId: "t1", projectId: "p1", kind: "user", content: "Test")
    ]

    XCTAssertThrowsError(try manager.commitBatch(entries: entries, toolInvocations: [])) { error in
      guard let bulkError = error as? BulkIngestError else {
        XCTFail("Expected BulkIngestError, got \(type(of: error))")
        return
      }
      XCTAssertEqual(bulkError, .notOpen, "Should throw BulkIngestError.notOpen")
    }
  }

  // MARK: - Helpers

  private func makeTestEntry(
    id: String,
    transcriptId: String,
    projectId: String,
    kind: String,
    content: String
  ) -> TranscriptEntry {
    let now = Int(Date().timeIntervalSince1970)
    return TranscriptEntry(
      id: id,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: nil,
      provider: "claude.code",
      kind: kind,
      timestamp: now,
      content: content,
      contentSha256: SHA256Utils.hash(content),
      displayInTimeline: 1,
      parentId: nil,
      gitBranch: nil,
      gitCommit: nil,
      cwd: nil,
      prev1Id: nil,
      prev2Id: nil,
      windowSha256: nil,
      embedding: nil,
      embeddingVersion: nil,
      embeddingGeneratedAt: nil,
      createdTs: Double(now),
      createdAt: now,
      updatedAt: now,
      isQueued: 0,
      isSidechain: 0
    )
  }

  private func makeTestToolInvocation(
    id: String,
    entryId: String,
    transcriptId: String,
    toolName: String
  ) -> ToolInvocation {
    let now = Int(Date().timeIntervalSince1970)
    return ToolInvocation(
      id: id,
      entryId: entryId,
      transcriptId: transcriptId,
      parentInvocationId: nil,
      toolName: toolName,
      toolKey: nil,
      toolUseId: nil,
      toolResultEntryId: nil,
      sidechainTranscriptId: nil,
      sidechainAgentId: nil,
      startedAt: now,
      completedAt: nil,
      status: "pending",
      isContextify: 0,
      metadataJson: nil,
      createdAt: now,
      updatedAt: now
    )
  }
}
