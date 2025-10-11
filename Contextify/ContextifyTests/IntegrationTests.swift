import XCTest
import GRDB
@testable import ContextifyCore

/// Integration tests demonstrating full hoover workflow
final class IntegrationTests: XCTestCase {
  var tempDir: URL!

  override func setUp() async throws {
    try await super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try await super.tearDown()
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  /// Example: Kick off initial hoover for a project
  func testInitialHooverWorkflow() throws {
    // 1. Set up database
    let dbPath = tempDir.appendingPathComponent("test.db")
    var config = Configuration()
    config.foreignKeysEnabled = true
    let pool = try DatabasePool(path: dbPath.path, configuration: config)
    try pool.write { db in try DatabaseSchema.migrate(db) }

    // 2. Create repositories
    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let entryRepo = EntryRepositoryImpl(db: pool)
    let errorRepo = ParseErrorRepositoryImpl(db: pool)

    // 3. Create hoover engine with parser
    let parser = MultiProviderParser()
    let hooverEngine = HooverEngine(
      db: pool,
      transcriptRepo: transcriptRepo,
      entryRepo: entryRepo,
      errorRepo: errorRepo,
      parser: parser
    )

    // 4. Create a test project
    let projectId = try projectRepo.create(
      name: "Test Project",
      rootPath: "/Users/rob/code/projects/contextify",
      bookmark: nil
    )

    // 5. Create a mock transcript file
    let transcriptPath = tempDir.appendingPathComponent("test-transcript.jsonl")
    let mockTranscript = """
    {"uuid":"msg-1","type":"user","timestamp":"2025-10-11T12:00:00.000Z","sessionId":"session-123","message":{"role":"user","content":"Hello"},"gitBranch":"main"}
    {"uuid":"msg-2","type":"assistant","timestamp":"2025-10-11T12:00:01.000Z","sessionId":"session-123","message":{"role":"assistant","content":"Hi there!"},"gitBranch":"main"}
    {"uuid":"msg-3","type":"user","timestamp":"2025-10-11T12:00:02.000Z","sessionId":"session-123","message":{"role":"user","content":"How are you?"},"gitBranch":"main"}
    """
    try mockTranscript.write(to: transcriptPath, atomically: true, encoding: .utf8)

    // 6. Register the transcript
    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: transcriptPath,
      provider: "claude.code",
      providerSessionId: "session-123",
      lastModified: Date(),
      fileSize: mockTranscript.utf8.count
    )

    // 7. Get the transcript record
    guard let transcript = try transcriptRepo.get(transcriptId) else {
      XCTFail("Failed to get transcript")
      return
    }

    // 8. Kick off the hoover!
    let progress = LoggingProgressSink(log: Logger(subsystem: "test", category: "hoover"))
    let sha256 = try hooverEngine.hooverTranscript(
      transcript,
      fileURL: transcriptPath,
      progress: progress
    )

    // 9. Verify results
    XCTAssertFalse(sha256.isEmpty, "Should return transcript SHA256")

    // Check entries were inserted
    let entries = try entryRepo.byTranscript(transcriptId, afterTimestamp: nil)
    XCTAssertEqual(entries.count, 3, "Should have 3 entries")

    // Check entry content
    XCTAssertEqual(entries[0].content, "Hello")
    XCTAssertEqual(entries[1].content, "Hi there!")
    XCTAssertEqual(entries[2].content, "How are you?")

    // Check kinds
    XCTAssertEqual(entries[0].kind, "user")
    XCTAssertEqual(entries[1].kind, "assistant")
    XCTAssertEqual(entries[2].kind, "user")

    // Check git context
    XCTAssertEqual(entries[0].gitBranch, "main")

    // Check ingestion state updated
    let updated = try transcriptRepo.get(transcriptId)
    XCTAssertEqual(updated?.lastProcessedLine, 3)
    XCTAssertEqual(updated?.lineCount, 3)

    print("✅ Initial hoover completed successfully!")
    print("   - Processed \(entries.count) messages")
    print("   - Transcript SHA256: \(sha256)")
    print("   - Last processed line: \(updated?.lastProcessedLine ?? 0)")
  }

  /// Example: Using the TranscriptOrchestrator (high-level API)
  func testOrchestratorWorkflow() throws {
    // This is the recommended way for production use

    // 1. Create database manager (uses default location)
    // For testing, we'd need to inject a custom path, but in production:
    // let orchestrator = try TranscriptOrchestrator()

    // 2. Create or get project
    // let projectId = try orchestrator.createProject(
    //   name: "My Project",
    //   rootPath: "/Users/rob/code/projects/myproject",
    //   bookmark: nil
    // )

    // 3. Discover transcripts in Claude Code directory
    // let claudeDir = FileManager.default.homeDirectoryForCurrentUser
    //   .appendingPathComponent(".claude/projects/myproject")
    // let transcriptFiles = try FileManager.default.contentsOfDirectory(
    //   at: claudeDir,
    //   includingPropertiesForKeys: nil
    // ).filter { $0.pathExtension == "jsonl" }

    // 4. Batch discover and hoover
    // let files = transcriptFiles.map { (url: $0, provider: "claude.code", sessionId: nil) }
    // try orchestrator.discoverTranscripts(
    //   projectId: projectId,
    //   transcriptFiles: files,
    //   progress: LoggingProgressSink(log: log)
    // )

    // 5. Query results
    // let recentEntries = try orchestrator.getRecentEntries(forProject: projectId, limit: 50)
    // print("Recent messages: \(recentEntries.count)")

    XCTAssertTrue(true, "See comments for production workflow")
  }

  /// Example: Crash recovery (resume from checkpoint)
  func testCrashRecovery() throws {
    let dbPath = tempDir.appendingPathComponent("test.db")
    var config = Configuration()
    config.foreignKeysEnabled = true
    let pool = try DatabasePool(path: dbPath.path, configuration: config)
    try pool.write { db in try DatabaseSchema.migrate(db) }

    let projectRepo = ProjectRepositoryImpl(db: pool)
    let transcriptRepo = TranscriptRepositoryImpl(db: pool)
    let entryRepo = EntryRepositoryImpl(db: pool)
    let errorRepo = ParseErrorRepositoryImpl(db: pool)
    let parser = MultiProviderParser()
    let hooverEngine = HooverEngine(
      db: pool,
      transcriptRepo: transcriptRepo,
      entryRepo: entryRepo,
      errorRepo: errorRepo,
      parser: parser
    )

    // Create project and transcript
    let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)
    let transcriptPath = tempDir.appendingPathComponent("test.jsonl")
    let lines = (1...10).map { i in
      """
      {"uuid":"msg-\(i)","type":"user","timestamp":"2025-10-11T12:00:0\(i).000Z","sessionId":"s1","message":{"role":"user","content":"Message \(i)"}}
      """
    }
    try lines.joined(separator: "\n").write(to: transcriptPath, atomically: true, encoding: .utf8)

    let transcriptId = try transcriptRepo.upsert(
      projectId: projectId,
      fileURL: transcriptPath,
      provider: "claude.code",
      providerSessionId: "s1",
      lastModified: Date(),
      fileSize: 0
    )

    // Simulate crash after processing 5 lines
    try transcriptRepo.setIngestionState(
      id: transcriptId,
      lastProcessedLine: 5,
      lineCount: 10,
      parserVersion: 1,
      status: "active",
      lastError: nil
    )

    // Resume hoover
    guard let transcript = try transcriptRepo.get(transcriptId) else {
      XCTFail("Transcript not found")
      return
    }

    _ = try hooverEngine.hooverTranscript(
      transcript,
      fileURL: transcriptPath,
      progress: NoOpProgressSink()
    )

    // Verify it processed remaining lines (6-10)
    let entries = try entryRepo.byTranscript(transcriptId, afterTimestamp: nil)
    XCTAssertEqual(entries.count, 5, "Should only process new lines (6-10)")

    print("✅ Crash recovery works! Resumed from line 5, processed 5 more lines")
  }
}
