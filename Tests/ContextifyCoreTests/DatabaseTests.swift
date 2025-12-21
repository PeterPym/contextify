import XCTest
import GRDB
@testable import ContextifyCore

final class DatabaseTests: XCTestCase {
  var tempDir: URL!
  var dbManager: DatabaseManager!

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

  // MARK: - Schema Tests

  func testDatabaseSchemaCreation() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    // Verify tables exist
    let tables = try pool.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    }

    XCTAssertTrue(tables.contains("projects"))
    XCTAssertTrue(tables.contains("transcripts"))
    XCTAssertTrue(tables.contains("transcript_entries"))
    XCTAssertTrue(tables.contains("timeline_cache"))
    XCTAssertTrue(tables.contains("transcript_metadata"))
    XCTAssertTrue(tables.contains("parse_errors"))
  }

  // MARK: - Repository Tests

  func testProjectRepository() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let repo = ProjectRepositoryImpl(db: pool)

    // Create project
    let projectId = try repo.create(name: "Test Project", rootPath: "/test/path", bookmark: nil)
    XCTAssertFalse(projectId.isEmpty)

    // Get project
    let project = try repo.get(id: projectId)
    XCTAssertNotNil(project)
    XCTAssertEqual(project?.name, "Test Project")
    XCTAssertEqual(project?.rootPath, "/test/path")

    // List projects
    let projects = try repo.list()
    XCTAssertEqual(projects.count, 1)

    // Update project
    try repo.update(id: projectId, name: "Updated Project", bookmark: nil)
    let updated = try repo.get(id: projectId)
    XCTAssertEqual(updated?.name, "Updated Project")

    // Delete project
    try repo.delete(id: projectId)
    let deleted = try repo.get(id: projectId)
    XCTAssertNil(deleted)
  }

  func testTranscriptRepository() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)

    // Create project first
    let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)

    // Create transcript
    let fileURL = URL(fileURLWithPath: "/test/transcript.jsonl")
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: fileURL,
      provider: "claude.code",
      providerSessionId: "session-123",
      lastModified: Date(),
      fileSize: 1024
    )

    XCTAssertFalse(transcriptId.isEmpty)

    // Get transcript
    let transcript = try transcriptRepo.get(transcriptId)
    XCTAssertNotNil(transcript)
    XCTAssertEqual(transcript?.provider, "claude.code")

    // Update ingestion state
    try transcriptRepo.setIngestionState(
      id: transcriptId,
      lastProcessedLine: 100,
      lineCount: 100,
      parserVersion: 1,
      status: "active",
      ingestState: "complete",
      lastError: nil
    )

    let updated = try transcriptRepo.get(transcriptId)
    XCTAssertEqual(updated?.lastProcessedLine, 100)
    XCTAssertEqual(updated?.lineCount, 100)
  }

  func testEntryRepository() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let entryRepo = EntryRepositoryImpl(db: pool)

    // Create project and transcript
    let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: URL(fileURLWithPath: "/test/t.jsonl"),
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: nil
    )

    // Create entries
    let now = Int(Date().timeIntervalSince1970)
    let entries = [
      TranscriptEntry(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        projectId: projectId,
        sessionId: nil,
        provider: "claude.code",
        kind: "user",
        timestamp: now,
        content: "Test message 1",
        contentSha256: SHA256Utils.hash("Test message 1"),
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
        updatedAt: now,
        isQueued: 0,
        isSidechain: 0
      ),
      TranscriptEntry(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        projectId: projectId,
        sessionId: nil,
        provider: "claude.code",
        kind: "assistant",
        timestamp: now + 1,
        content: "Test message 2",
        contentSha256: SHA256Utils.hash("Test message 2"),
        displayInTimeline: 1,
        parentId: nil,
        gitBranch: nil,
        gitCommit: nil,
        cwd: nil,
        prev1Id: nil,
        prev2Id: nil,
        windowSha256: nil,
        createdTs: Double(now + 1),
        createdAt: now + 1,
        updatedAt: now + 1,
        isQueued: 0,
        isSidechain: 0
      )
    ]

    try entryRepo.insertBatch(entries)

    // Query entries
    let fetched = try entryRepo.byTranscript(transcriptId)
    XCTAssertEqual(fetched.count, 2)

    let recent = try entryRepo.recentByProject(projectId, limit: 10)
    XCTAssertEqual(recent.count, 2)
  }

  // MARK: - Parser Tests

  func testClaudeCodeParser() throws {
    let parser = ClaudeCodeLineParser()

    let json = """
    {
      "uuid": "test-uuid-123",
      "type": "user",
      "timestamp": "2025-10-11T12:00:00.000Z",
      "sessionId": "session-456",
      "message": {
        "role": "user",
        "content": "Hello, world!"
      },
      "gitBranch": "main",
      "cwd": "/test/path"
    }
    """

    let entry = try parser.parse(
      line: json,
      lineNumber: 1,
      transcriptId: "transcript-1",
      projectId: "project-1",
      provider: "claude.code",
      sessionId: nil
    )

    XCTAssertEqual(entry.id, "test-uuid-123")
    XCTAssertEqual(entry.kind, "user")
    XCTAssertEqual(entry.content, "Hello, world!")
    XCTAssertEqual(entry.gitBranch, "main")
    XCTAssertEqual(entry.cwd, "/test/path")
  }

  func testCodexParser() throws {
    let parser = CodexLineParser()

    // User messages in Codex format come from event_msg records, not response_item
    // (response_item with role=user are now skipped to filter out system-injected messages)
    let json = """
    {
      "timestamp": "2025-10-11T12:00:00.000Z",
      "type": "event_msg",
      "payload": {
        "type": "user_message",
        "message": "Test content"
      }
    }
    """

    let entry = try parser.parse(
      line: json,
      lineNumber: 1,
      transcriptId: "transcript-1",
      projectId: "project-1",
      provider: "codex.cli",
      sessionId: "session-789"
    )

    XCTAssertEqual(entry.kind, "user")
    XCTAssertEqual(entry.content, "Test content")
    XCTAssertEqual(entry.sessionId, "session-789")
  }

  // MARK: - Key Generation Tests

  func testSHA256Hash() {
    let input = "Hello, world!"
    let hash = SHA256Utils.hash(input)

    // SHA256 hash should be 64 hex characters
    XCTAssertEqual(hash.count, 64)

    // Same input should produce same hash
    let hash2 = SHA256Utils.hash(input)
    XCTAssertEqual(hash, hash2)
  }

  func testWindowSHA256() {
    let prev2 = "entry-1"
    let prev1 = "entry-2"

    let hash = SHA256Utils.computeWindowSHA256(prev2: prev2, prev1: prev1)
    XCTAssertEqual(hash.count, 64)

    // Should be deterministic
    let hash2 = SHA256Utils.computeWindowSHA256(prev2: prev2, prev1: prev1)
    XCTAssertEqual(hash, hash2)
  }

  func testDeterministicEntryID() {
    let timestamp = Date(timeIntervalSince1970: 1697000000)
    let role = "user"
    let lineNumber = 42
    let sessionID = "session-123"

    let id1 = EntryIDGenerator.generateEntryID(
      timestamp: timestamp,
      role: role,
      lineNumber: lineNumber,
      sessionID: sessionID
    )

    let id2 = EntryIDGenerator.generateEntryID(
      timestamp: timestamp,
      role: role,
      lineNumber: lineNumber,
      sessionID: sessionID
    )

    // Should be deterministic
    XCTAssertEqual(id1, id2)

    // Should be valid UUID format
    XCTAssertTrue(id1.contains("-"))
    XCTAssertEqual(id1.count, 36) // UUID format: 8-4-4-4-12
  }

  func testGeneratorSignature() {
    let sig = GeneratorSignature(
      model: "gpt-4o",
      modelVersion: "2025-09",
      prompt: "timeline",
      promptVersion: "3"
    )

    let string = sig.string
    XCTAssertEqual(string, "gpt-4o@2025-09:timeline@3")

    // Test parsing
    let parsed = GeneratorSignature.parse(string)
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.model, "gpt-4o")
    XCTAssertEqual(parsed?.modelVersion, "2025-09")
    XCTAssertEqual(parsed?.prompt, "timeline")
    XCTAssertEqual(parsed?.promptVersion, "3")
  }

  // MARK: - Crash Recovery Tests

  // MARK: - Denormalization Tests

  func testDenormalizationInvariant() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let entryRepo = EntryRepositoryImpl(db: pool)

    // Create project and transcript
    let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: URL(fileURLWithPath: "/test/t.jsonl"),
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: nil
    )

    // Create entry
    let now = Int(Date().timeIntervalSince1970)
    let entry = TranscriptEntry(
      id: UUID().uuidString,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: nil,
      provider: "claude.code",
      kind: "user",
      timestamp: now,
      content: "Test",
      contentSha256: SHA256Utils.hash("Test"),
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
      updatedAt: now,
      isQueued: 0,
        isSidechain: 0
    )
    try entryRepo.insertBatch([entry])

    // Run denormalization invariant check (should return no rows)
    let row = try pool.read { db in
      try Row.fetchOne(db, sql: """
        SELECT e.id
        FROM transcript_entries e
        LEFT JOIN transcripts t ON t.id = e.transcript_id
        WHERE t.project_id IS NULL OR e.project_id <> t.project_id
        LIMIT 1
      """)
    }

    XCTAssertNil(row, "Denormalization invariant violated")
  }

  func testCrashRecovery() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)

    // Create project and transcript
    let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: URL(fileURLWithPath: "/test/t.jsonl"),
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: nil
    )

    // Simulate partial processing
    try transcriptRepo.setIngestionState(
      id: transcriptId,
      lastProcessedLine: 50,
      lineCount: 100,
      parserVersion: 1,
      status: "active",
      ingestState: "complete",
      lastError: nil
    )

    // Verify checkpoint was saved
    let transcript = try transcriptRepo.get(transcriptId)
    XCTAssertEqual(transcript?.lastProcessedLine, 50)
    XCTAssertEqual(transcript?.lineCount, 100)

    // Should resume from line 50 on next hoover
    XCTAssertTrue(transcript!.lastProcessedLine < transcript!.lineCount)
  }

  // MARK: - v3 Migration Tests

  func testMigrationIdempotence() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)
    // Run migration twice - should not error
    try applySchema(pool)

    // Verify v3 columns exist
    let columns = try pool.read { db in
      try Row.fetchAll(db, sql: "PRAGMA table_info(transcripts)")
    }
    let columnNames = Set(columns.map { $0["name"] as! String })

    XCTAssertTrue(columnNames.contains("normalized_path"))
    XCTAssertTrue(columnNames.contains("path_hash"))
    XCTAssertTrue(columnNames.contains("content_length"))
    XCTAssertTrue(columnNames.contains("mtime_ms"))

    // Verify indexes exist
    let indexes = try pool.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='transcripts'")
    }

    XCTAssertTrue(indexes.contains("uq_tr_provider_session"))
    XCTAssertTrue(indexes.contains("uq_tr_provider_path_hash"))
    XCTAssertTrue(indexes.contains("idx_tr_mtime_ms"))
  }

  // DELETED: testMigrationBackfillMtimeMs
  // This test validated the v3 migration (mtime_ms backfill), but that migration
  // was collapsed into v16_collapsed_schema (commit af8c1437). The test created
  // a manual v2 schema then ran modern migrations, which fails because v16+
  // assumes either fresh DB or already-migrated DB. The migration path being
  // tested no longer exists.

  // MARK: - Identity Resolution Tests

  func testSessionIdTakesPrecedence() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)

    let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)

    // Create transcript with session ID
    let transcriptId1 = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: URL(fileURLWithPath: "/test/session.jsonl"),
      provider: "claude.code",
      providerSessionId: "session-123",
      lastModified: Date(),
      fileSize: 1024
    )

    // Upsert again with same session ID but different path - should find existing
    let transcriptId2 = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: URL(fileURLWithPath: "/test/different-path.jsonl"),
      provider: "claude.code",
      providerSessionId: "session-123",
      lastModified: Date(),
      fileSize: 2048
    )

    // Should be same transcript (session ID takes precedence)
    XCTAssertEqual(transcriptId1, transcriptId2)
  }

  func testPathHashFallback() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)

    let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)

    // Create transcript without session ID
    let transcriptId1 = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: URL(fileURLWithPath: "/test/nosession.jsonl"),
      provider: "codex.cli",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: 1024
    )

    // Upsert again with same path - should find existing via path hash
    let transcriptId2 = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: URL(fileURLWithPath: "/test/nosession.jsonl"),
      provider: "codex.cli",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: 2048
    )

    // Should be same transcript (path hash fallback)
    XCTAssertEqual(transcriptId1, transcriptId2)
  }

  // MARK: - Watcher Invalidation Tests

  func testWatcherMetadataInvalidation() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)

    // Create test transcript file
    let testFile = tempDir.appendingPathComponent("test.jsonl")
    try "test content".write(to: testFile, atomically: true, encoding: .utf8)

    let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: testFile,
      provider: "claude.code",
      providerSessionId: "session-test",
      lastModified: Date(),
      fileSize: 100
    )

    // Track invalidation calls
    var invalidationCalled = false
    var invalidatedId: String?

    let invalidator: (String) throws -> Void = { id in
      invalidationCalled = true
      invalidatedId = id
    }

    // Simulate watcher callback
    try invalidator(transcriptId)

    XCTAssertTrue(invalidationCalled)
    XCTAssertEqual(invalidatedId, transcriptId)
  }

  // MARK: - Fast-Path Ingestion Tests

  func testHooverEnginePreviewLimit() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    // Create test transcript file with 20 entries
    let transcriptFile = tempDir.appendingPathComponent("test-transcript.jsonl")
    var lines: [String] = []
    for i in 1...20 {
      lines.append("""
        {"type":"user","timestamp":"\(Date().addingTimeInterval(TimeInterval(i)).ISO8601Format())","uuid":"user-\(i)","message":{"role":"user","content":[{"type":"text","text":"Test message \(i)"}]}}
        """)
    }
    try lines.joined(separator: "\n").write(to: transcriptFile, atomically: true, encoding: .utf8)

    // Setup repositories and engine
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let entryRepo = EntryRepositoryImpl(db: pool)
    let errorRepo = ParseErrorRepositoryImpl(db: pool)
    let parser = ClaudeCodeLineParser()
    let metadataParser = ClaudeCodeMetadataParser()

    let hooverEngine = HooverEngine(
      db: pool,
      transcriptRepo: transcriptRepo,
      entryRepo: entryRepo,
      errorRepo: errorRepo,
      parser: parser,
      fileSnapshotRepo: FileSnapshotRepositoryImpl(db: pool),
      trackedFileRepo: TrackedFileRepositoryImpl(db: pool),
      transcriptSummaryRepo: TranscriptSummaryRepositoryImpl(db: pool),
      systemEventRepo: SystemEventRepositoryImpl(db: pool),
      assistantUsageRepo: AssistantUsageRepositoryImpl(db: pool),
      metadataParser: metadataParser
    )

    // Create project and transcript records
    let projectRepo = ProjectRepositoryImpl(db: pool)
    let projectId = try projectRepo.create(name: "Test Project", rootPath: tempDir.path, bookmark: nil)

    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: transcriptFile,
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: lines.joined().count
    )

    let transcript = try transcriptRepo.get(transcriptId)!

    // Test 1: Hoover with limit of 10 entries
    let progressSink = NoOpProgressSink()
    let outcome1 = try hooverEngine.hooverTranscript(
      transcript,
      fileURL: transcriptFile,
      progress: progressSink,
      limit: .entries(10)
    )

    XCTAssertEqual(outcome1.newEntries, 10, "Should ingest exactly 10 entries")
    XCTAssertFalse(outcome1.reachedEOF, "Should not reach EOF with limit")
    XCTAssertNil(outcome1.contentSha256, "Should not compute SHA when not at EOF")

    // Verify transcript state is partial
    let partialTranscript = try transcriptRepo.get(transcriptId)!
    XCTAssertEqual(partialTranscript.ingestState, "partial", "Should mark as partial")
    XCTAssertGreaterThan(partialTranscript.lastProcessedLine, 0, "Should have processed lines")

    // Test 2: Resume and complete ingestion
    let updatedTranscript = try transcriptRepo.get(transcriptId)!
    let outcome2 = try hooverEngine.hooverTranscript(
      updatedTranscript,
      fileURL: transcriptFile,
      progress: progressSink,
      limit: .none
    )

    XCTAssertEqual(outcome2.newEntries, 10, "Should ingest remaining 10 entries")
    XCTAssertTrue(outcome2.reachedEOF, "Should reach EOF")
    XCTAssertNotNil(outcome2.contentSha256, "Should compute SHA at EOF")

    // Verify transcript state is complete
    let completeTranscript = try transcriptRepo.get(transcriptId)!
    XCTAssertEqual(completeTranscript.ingestState, "complete", "Should mark as complete")

    // Verify total entries
    let totalEntries = try pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = ?", arguments: [transcriptId]) ?? 0
    }
    XCTAssertEqual(totalEntries, 20, "Should have ingested all 20 entries")
  }

  func testHooverEngineSinglePassNoTrailingNewline() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    // Create test transcript file with 20 entries and NO trailing newline
    let transcriptFile = tempDir.appendingPathComponent("test-no-newline.jsonl")
    var lines: [String] = []
    for i in 1...20 {
      lines.append("""
        {"type":"user","timestamp":"\(Date().addingTimeInterval(TimeInterval(i)).ISO8601Format())","uuid":"user-\(i)","message":{"role":"user","content":[{"type":"text","text":"Test message \(i)"}]}}
        """)
    }
    // Join with newlines but don't add trailing newline
    try lines.joined(separator: "\n").write(to: transcriptFile, atomically: true, encoding: .utf8)

    // Setup repositories and engine
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let entryRepo = EntryRepositoryImpl(db: pool)
    let errorRepo = ParseErrorRepositoryImpl(db: pool)
    let parser = ClaudeCodeLineParser()
    let metadataParser = ClaudeCodeMetadataParser()

    let hooverEngine = HooverEngine(
      db: pool,
      transcriptRepo: transcriptRepo,
      entryRepo: entryRepo,
      errorRepo: errorRepo,
      parser: parser,
      fileSnapshotRepo: FileSnapshotRepositoryImpl(db: pool),
      trackedFileRepo: TrackedFileRepositoryImpl(db: pool),
      transcriptSummaryRepo: TranscriptSummaryRepositoryImpl(db: pool),
      systemEventRepo: SystemEventRepositoryImpl(db: pool),
      assistantUsageRepo: AssistantUsageRepositoryImpl(db: pool),
      metadataParser: metadataParser
    )

    // Create project and transcript records
    let projectRepo = ProjectRepositoryImpl(db: pool)
    let projectId = try projectRepo.create(name: "Test Project", rootPath: tempDir.path, bookmark: nil)

    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: transcriptFile,
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: lines.joined(separator: "\n").count
    )

    let transcript = try transcriptRepo.get(transcriptId)!

    // Ingest in single pass with no limit
    let progressSink = NoOpProgressSink()
    let outcome = try hooverEngine.hooverTranscript(
      transcript,
      fileURL: transcriptFile,
      progress: progressSink,
      limit: .none
    )

    // Verify all 20 entries ingested (including final partial line)
    XCTAssertEqual(outcome.newEntries, 20, "Should ingest all 20 entries including final partial line")
    XCTAssertTrue(outcome.reachedEOF, "Should reach EOF")
    XCTAssertNotNil(outcome.contentSha256, "Should compute SHA at EOF")

    // Verify transcript state is complete
    let completeTranscript = try transcriptRepo.get(transcriptId)!
    XCTAssertEqual(completeTranscript.ingestState, "complete", "Should mark as complete")
    XCTAssertEqual(completeTranscript.lastProcessedLine, 20, "Should have processed all 20 lines")

    // Verify total entries in database
    let totalEntries = try pool.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries WHERE transcript_id = ?", arguments: [transcriptId]) ?? 0
    }
    XCTAssertEqual(totalEntries, 20, "Should have ingested all 20 entries")
  }

  func testIngestionLockPreventsParallelIngest() async throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    // Disable scheduler to force synchronous ingestion for testing
    ContextifyConfig.shared.hooverSchedulerEnabled = false
    defer { ContextifyConfig.shared.hooverSchedulerEnabled = true }

    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    // Create test project
    let projectRepo = ProjectRepositoryImpl(db: pool)
    let projectId = try projectRepo.create(name: "Test Project", rootPath: tempDir.path, bookmark: nil)

    // Create transcript with enough entries to remain partial during preview
    let transcriptFile = tempDir.appendingPathComponent("test-transcript.jsonl")
    var lines: [String] = []
    for i in 1...20 {
      lines.append("""
        {"type":"user","timestamp":"\(Date().addingTimeInterval(TimeInterval(i)).ISO8601Format())","uuid":"user-\(i)","message":{"role":"user","content":[{"type":"text","text":"Test message \(i)"}]}}
        """)
    }
    try lines.joined(separator: "\n").write(to: transcriptFile, atomically: true, encoding: .utf8)

    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: transcriptFile,
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: lines.joined(separator: "\n").count
    )

    // Test lock behavior
    var secondCallResult: Bool = false

    // First call should succeed (acquire lock and ingest)
    // Note: Return value indicates partial state, not lock acquisition success
    _ = try await orchestrator.ingestTranscript(
      transcriptId: transcriptId,
      mode: .preview(entries: 10),
      notifyUI: false
    )

    // Verify ingestion happened
    let afterFirst = try transcriptRepo.get(transcriptId)!
    XCTAssertGreaterThan(afterFirst.lastProcessedLine, 0, "First call should have processed lines")

    // Manually acquire lock to simulate concurrent access
    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO ingestion_locks(transcript_id, locked_at)
        VALUES (?, ?)
      """, arguments: [transcriptId, Int(Date().timeIntervalSince1970)])
    }

    // Second call should fail to acquire lock and return current state
    secondCallResult = try await orchestrator.ingestTranscript(
      transcriptId: transcriptId,
      mode: .preview(entries: 10),
      notifyUI: false
    )

    // Verify lock prevented parallel access
    XCTAssertFalse(secondCallResult, "Second call should return false (already complete or locked)")
  }

  func testMarkTranscriptUnavailableRemovesFromPartialResumption() async throws {
    let dbPath = tempDir.appendingPathComponent("test-unavailable.db")
    let pool = try makeMigratedPool(at: dbPath)

    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let projectId = try projectRepo.create(name: "Test Project", rootPath: tempDir.path, bookmark: nil)

    let transcriptFile = tempDir.appendingPathComponent("unavailable-transcript.jsonl")
    try "[]\n".write(to: transcriptFile, atomically: true, encoding: .utf8)

    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: transcriptFile,
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: 3
    )

    try transcriptRepo.setIngestionState(
      id: transcriptId,
      lastProcessedLine: 0,
      lineCount: 0,
      parserVersion: 1,
      status: "active",
      ingestState: "partial",
      lastError: nil
    )

    try orchestrator.markTranscriptUnavailable(transcriptId: transcriptId, lastError: "Permission denied")

    let updated = try transcriptRepo.get(transcriptId)!
    XCTAssertEqual(updated.status, "unavailable")
    XCTAssertEqual(updated.ingestState, "complete")
    XCTAssertEqual(updated.lastError, "Permission denied")

    let partials = try orchestrator.getPartialTranscripts()
    XCTAssertFalse(partials.contains(where: { $0.id == transcriptId }), "Unavailable transcripts should not be returned as partials")
  }

  func testIngestStateIndexExists() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    var config = Configuration()
    config.foreignKeysEnabled = true

    let pool = try DatabasePool(path: dbPath.path, configuration: config)
    try applySchema(pool)

    // Verify index exists
    let indexes = try pool.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='transcripts'")
    }

    XCTAssertTrue(indexes.contains("idx_tr_ingest_state_updated_at"), "Index for ingest_state should exist")
  }

  // MARK: - Project Discovery Tests

  func testGetOrCreateProjectReturnsWasCreatedTrueForNewProject() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    _ = try makeMigratedPool(at: dbPath)

    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    // First call should create a new project
    let result = try orchestrator.getOrCreateProject(
      name: "New Project",
      rootPath: "/test/new-project"
    )

    XCTAssertTrue(result.wasCreated, "First call should indicate project was created")
    XCTAssertFalse(result.projectId.isEmpty, "Project ID should not be empty")
  }

  func testGetOrCreateProjectReturnsWasCreatedFalseForExistingProject() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    _ = try makeMigratedPool(at: dbPath)

    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    // First call creates the project
    let firstResult = try orchestrator.getOrCreateProject(
      name: "Existing Project",
      rootPath: "/test/existing-project"
    )
    XCTAssertTrue(firstResult.wasCreated, "First call should create project")

    // Second call with same path should find existing project
    let secondResult = try orchestrator.getOrCreateProject(
      name: "Existing Project",
      rootPath: "/test/existing-project"
    )

    XCTAssertFalse(secondResult.wasCreated, "Second call should find existing project")
    XCTAssertEqual(secondResult.projectId, firstResult.projectId, "Should return same project ID")
  }

  func testGetOrCreateProjectReturnsSameIdForSamePath() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    _ = try makeMigratedPool(at: dbPath)

    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    // Create project
    let result1 = try orchestrator.getOrCreateProject(name: "Project", rootPath: "/test/path")

    // Call again with same path but different name (name is ignored for lookup)
    let result2 = try orchestrator.getOrCreateProject(name: "Different Name", rootPath: "/test/path")

    XCTAssertEqual(result1.projectId, result2.projectId, "Same path should return same project ID")
    XCTAssertTrue(result1.wasCreated)
    XCTAssertFalse(result2.wasCreated)
  }

  // MARK: - Project Activation Tests (#P1-PROJECT-ACTIVATED)

  /// Tests that markProjectActivated() consolidates three separate calls into one atomic operation.
  /// This is the red-green test for #P1-PROJECT-ACTIVATED.
  func testMarkProjectActivated_ReturnsVisitAndUnreadCount() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    // Create a project first
    let projectRepo = ProjectRepositoryImpl(db: pool)
    let projectId = try projectRepo.create(name: "Test Project", rootPath: "/test/activated", bookmark: nil)

    // Call the new unified method
    let timestamp = "2025-01-15T10:30:00.000Z"
    let result = try orchestrator.markProjectActivated(projectId: projectId, timestamp: timestamp)

    // Verify it returns both the visit and unread count
    XCTAssertEqual(result.visit.projectId, projectId)
    XCTAssertEqual(result.visit.lastViewedAt, timestamp)
    XCTAssertNotNil(result.visit.lastSelectedAt, "lastSelectedAt should be set by markProjectSelected")
    XCTAssertEqual(result.unreadCount, 0, "New project should have 0 unread count")
  }

  /// Tests that markProjectActivated() properly updates all three pieces of state atomically.
  func testMarkProjectActivated_UpdatesAllState() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    // Create project and add some entries to generate unread count
    let projectRepo = ProjectRepositoryImpl(db: pool)
    let projectId = try projectRepo.create(name: "Test Project", rootPath: "/test/activated2", bookmark: nil)

    // First activation
    let timestamp1 = "2025-01-15T10:30:00.000Z"
    let result1 = try orchestrator.markProjectActivated(projectId: projectId, timestamp: timestamp1)

    // Verify initial state
    XCTAssertEqual(result1.visit.lastViewedAt, timestamp1)

    // Second activation with later timestamp
    let timestamp2 = "2025-01-15T11:00:00.000Z"
    let result2 = try orchestrator.markProjectActivated(projectId: projectId, timestamp: timestamp2)

    // Verify state was updated
    XCTAssertEqual(result2.visit.lastViewedAt, timestamp2)
    XCTAssertNotNil(result2.visit.lastSelectedAt)
  }

  /// Tests that markProjectActivated() returns unread count based on the provided timestamp boundary.
  func testMarkProjectActivated_ComputesUnreadCountRelativeToTimestamp() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let entryRepo = EntryRepositoryImpl(db: pool)

    let projectId = try projectRepo.create(name: "Test Project", rootPath: "/test/activated3", bookmark: nil)

    // Create backing transcript and two entries on either side of the view timestamp
    let transcriptFile = tempDir.appendingPathComponent("activation-timestamp.jsonl")
    try "test".write(to: transcriptFile, atomically: true, encoding: .utf8)
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: transcriptFile,
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: 4
    )

    let viewTimestamp = "2025-01-15T10:30:00.000Z"
    guard let viewDate = ISO8601Z.date(from: viewTimestamp) else {
      XCTFail("Failed to parse view timestamp")
      return
    }

    let olderSeconds = viewDate.addingTimeInterval(-60).timeIntervalSince1970
    let newerSeconds = viewDate.addingTimeInterval(60).timeIntervalSince1970

    let olderCreated = TimeUnits.truncateToMillis(olderSeconds)
    let newerCreated = TimeUnits.truncateToMillis(newerSeconds)

    let entries = [
      TranscriptEntry(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        projectId: projectId,
        sessionId: nil,
        provider: "claude.code",
        kind: "user",
        timestamp: Int(olderSeconds),
        content: "old",
        contentSha256: "old-hash",
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
        createdTs: olderCreated,
        createdAt: Int(olderCreated),
        updatedAt: Int(olderCreated),
        isQueued: 0,
        isSidechain: 0
      ),
      TranscriptEntry(
        id: UUID().uuidString,
        transcriptId: transcriptId,
        projectId: projectId,
        sessionId: nil,
        provider: "claude.code",
        kind: "assistant",
        timestamp: Int(newerSeconds),
        content: "new",
        contentSha256: "new-hash",
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
        createdTs: newerCreated,
        createdAt: Int(newerCreated),
        updatedAt: Int(newerCreated),
        isQueued: 0,
        isSidechain: 0
      )
    ]
    try entryRepo.insertBatch(entries)

    let result = try orchestrator.markProjectActivated(projectId: projectId, timestamp: viewTimestamp)

    // Only the newer entry should remain unread after applying the boundary
    XCTAssertEqual(result.unreadCount, 1)
    XCTAssertEqual(result.visit.lastViewedAt, viewTimestamp)
    XCTAssertNotNil(result.visit.lastSelectedAt)
  }

  /// Tests that markProjectActivated() rolls back all changes when a failure occurs mid-transaction.
  func testMarkProjectActivated_RollsBackOnFailure() throws {
    enum InjectedActivationError: Error { case forcedFailure }

    let dbPath = tempDir.appendingPathComponent("test.db")
    let pool = try makeMigratedPool(at: dbPath)

    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let visitsRepo = ProjectVisitsRepositoryImpl(db: pool)
    let entryRepo = EntryRepositoryImpl(db: pool)

    let projectId = try projectRepo.create(name: "Test Project", rootPath: "/test/activated4", bookmark: nil)

    // Seed transcript and one entry so unread count is non-zero before activation
    let transcriptFile = tempDir.appendingPathComponent("activation-failure.jsonl")
    try "test".write(to: transcriptFile, atomically: true, encoding: .utf8)
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: transcriptFile,
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: Date(),
      fileSize: 4
    )

    let created = TimeUnits.truncateToMillis(Date().timeIntervalSince1970)
    let entry = TranscriptEntry(
      id: UUID().uuidString,
      transcriptId: transcriptId,
      projectId: projectId,
      sessionId: nil,
      provider: "claude.code",
      kind: "user",
      timestamp: Int(created),
      content: "will remain unread",
      contentSha256: "failure-hash",
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
      createdTs: created,
      createdAt: Int(created),
      updatedAt: Int(created),
      isQueued: 0,
        isSidechain: 0
    )
    try entryRepo.insert(entry)

    TranscriptOrchestrator.setActivationFailureHookForTesting {
      throw InjectedActivationError.forcedFailure
    }
    defer { TranscriptOrchestrator.setActivationFailureHookForTesting(nil) }

    XCTAssertThrowsError(
      try orchestrator.markProjectActivated(projectId: projectId, timestamp: ISO8601Z.string(from: Date()))
    ) { error in
      XCTAssertTrue(error is InjectedActivationError)
    }

    // Verify no visit record was created due to rollback
    let visit = try visitsRepo.getVisit(projectId: projectId)
    XCTAssertNil(visit?.lastViewedAt)
    XCTAssertNil(visit?.lastSelectedAt)

    // Unread count should remain unchanged (entry still unread)
    let unreadCount = try visitsRepo.getUnreadCount(projectId: projectId)
    XCTAssertEqual(unreadCount, 1)
  }

  // MARK: - Helpers

  private func makeMigratedPool(at url: URL) throws -> DatabasePool {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let pool = try DatabasePool(path: url.path, configuration: config)
    try applySchema(pool)
    return pool
  }

  private func applySchema(_ writer: DatabaseWriter) throws {
    let migrator = DatabaseSchema.createMigrator()
    try migrator.migrate(writer)
  }
}

// Helper for testing
private final class NoOpProgressSink: IngestProgressSink, @unchecked Sendable {
  func didStartTranscript(name: String, totalLines: Int?) {}
  func didAdvance(linesProcessed: Int, totalLines: Int?) {}
  func didCompleteTranscript(durationMs: Int) {}
  func didFailTranscript(error: String) {}
  func didStartProject(name: String, transcriptCount: Int) {}
  func didCompleteProject(name: String) {}
}
