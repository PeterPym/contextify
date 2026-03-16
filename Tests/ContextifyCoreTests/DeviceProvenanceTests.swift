import XCTest
import GRDB
@testable import ContextifyCore

final class DeviceProvenanceTests: XCTestCase {
  var tempDir: URL!
  var dbPath: URL!

  override func setUp() async throws {
    try await super.setUp()
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
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - Schema Tests

  func testV36MigrationAddsDeviceColumns() throws {
    let pool = try makeMigratedPool(at: dbPath)

    let columns = try pool.read { db in
      try String.fetchAll(db, sql: """
        SELECT name FROM pragma_table_info('transcript_entries')
      """)
    }

    XCTAssertTrue(columns.contains("source_device_id"), "source_device_id column should exist after v36 migration")
    XCTAssertTrue(columns.contains("source_device_name"), "source_device_name column should exist after v36 migration")
  }

  // MARK: - Ingest Stamp Tests

  func testLocalIngestStampsDeviceId() throws {
    let manager = BulkIngestManager(dbPath: dbPath.path)
    try manager.open()
    defer { manager.close() }

    let pool = try DatabasePool(path: dbPath.path)
    let (projectId, transcriptId) = try createTestProjectAndTranscript(pool: pool)

    let entry = makeTestEntry(
      id: UUID().uuidString,
      transcriptId: transcriptId,
      projectId: projectId,
      kind: "user",
      content: "Hello",
      sourceDeviceId: "ctx-test-device-123",
      sourceDeviceName: "Test MacBook"
    )

    let inserted = try manager.commitBatch(entries: [entry], toolInvocations: [])
    XCTAssertEqual(inserted, 1)

    // Verify device fields were persisted
    let (deviceId, deviceName) = try pool.read { db -> (String?, String?) in
      let row = try Row.fetchOne(db, sql: """
        SELECT source_device_id, source_device_name
        FROM transcript_entries WHERE id = ?
      """, arguments: [entry.id])
      return (row?["source_device_id"] as? String, row?["source_device_name"] as? String)
    }

    XCTAssertEqual(deviceId, "ctx-test-device-123")
    XCTAssertEqual(deviceName, "Test MacBook")
  }

  // MARK: - Null Device ID Tests

  func testNullDeviceIdLoadsWithoutError() throws {
    let pool = try DatabasePool(path: dbPath.path)
    let (projectId, transcriptId) = try createTestProjectAndTranscript(pool: pool)
    let entryId = UUID().uuidString
    let now = Int(Date().timeIntervalSince1970)

    // Insert entry WITHOUT device fields (simulating pre-migration data)
    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO transcript_entries (id, transcript_id, project_id, provider, kind,
          timestamp, content, content_sha256, display_in_timeline,
          created_at, updated_at, is_queued, is_sidechain)
        VALUES (?, ?, ?, 'claude.code', 'user', ?, 'test', 'abc123', 1, ?, ?, 0, 0)
      """, arguments: [entryId, transcriptId, projectId, now, now, now])
    }

    // Verify it loads via TranscriptEntry model without error
    let entry = try pool.read { db in
      try TranscriptEntry.fetchOne(db, sql: """
        SELECT * FROM transcript_entries WHERE id = ?
      """, arguments: [entryId])
    }

    XCTAssertNotNil(entry, "Entry with null device fields should load successfully")
    XCTAssertNil(entry?.sourceDeviceId, "source_device_id should be nil for pre-migration entries")
    XCTAssertNil(entry?.sourceDeviceName, "source_device_name should be nil for pre-migration entries")
  }

  // MARK: - Cloud Pull Stamp Tests

  func testCloudPullStampsDeviceId() throws {
    let pool = try makeMigratedPool(at: dbPath)
    let service = try ContextifyQueryService(databaseURL: dbPath, readOnly: false)

    let projectId = UUID().uuidString
    let transcriptId = UUID().uuidString
    let entryId = UUID().uuidString
    let now = Int(Date().timeIntervalSince1970)

    let projects: [[String: Any]] = [
      ["id": projectId, "root_path": "/test/pulled-project", "name": "Pulled Project"]
    ]
    let transcripts: [[String: Any]] = [
      ["id": transcriptId, "project_id": projectId, "file_path": "/test/tx.jsonl", "provider": "claude.code"]
    ]
    let entries: [[String: Any]] = [
      [
        "id": entryId,
        "transcript_id": transcriptId,
        "project_id": projectId,
        "provider": "claude.code",
        "kind": "user",
        "timestamp": now,
        "content": "Pulled entry",
        "content_sha256": "pullsha256",
        "display_in_timeline": true,
        "created_at": now,
        "updated_at": now,
        "source_device_id": "remote-device-uuid-456",
      ] as [String: Any]
    ]

    let result = try service.importFromCloudPull(
      projects: projects,
      transcripts: transcripts,
      entries: entries,
      summaries: []
    )

    XCTAssertEqual(result.entriesImported, 1)

    // Verify device ID was persisted from pull
    let deviceId = try pool.read { db -> String? in
      try String.fetchOne(db, sql: """
        SELECT source_device_id FROM transcript_entries WHERE id = ?
      """, arguments: [entryId])
    }

    XCTAssertEqual(deviceId, "remote-device-uuid-456")
  }

  // MARK: - DeviceName Utility Tests

  func testDeviceNameReturnsNonEmpty() {
    let name = DeviceName.current()
    XCTAssertFalse(name.isEmpty, "DeviceName.current() should return a non-empty string")
  }

  func testDeviceNameIsCached() {
    let name1 = DeviceName.current()
    let name2 = DeviceName.current()
    XCTAssertEqual(name1, name2, "DeviceName should return the same value on subsequent calls")
  }

  // MARK: - Helpers

  private func createTestProjectAndTranscript(pool: DatabasePool) throws -> (String, String) {
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

    return (projectId, transcriptId)
  }

  private func makeTestEntry(
    id: String,
    transcriptId: String,
    projectId: String,
    kind: String,
    content: String,
    sourceDeviceId: String? = nil,
    sourceDeviceName: String? = nil
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
      isSidechain: 0,
      sourceDeviceId: sourceDeviceId,
      sourceDeviceName: sourceDeviceName
    )
  }

  private func makeMigratedPool(at url: URL) throws -> DatabasePool {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let pool = try DatabasePool(path: url.path, configuration: config)
    let migrator = DatabaseSchema.createMigrator()
    try migrator.migrate(pool)
    return pool
  }
}
