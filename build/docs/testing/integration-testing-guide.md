# Integration Testing Strategy

**Last Updated:** 2025-11-18
**Context:** Added lazy loading architecture testing patterns

**Audience:** Developers writing integration tests for Contextify

---

## Testing Scope

**Key components requiring integration tests:**
- AppStateOrchestrator state machine transitions
- LightweightDiscoveryService (<200ms validation)
- JIT ingestion flows (FastPathIngestionCoordinator)
- Background indexing cancellation

---

## Table of Contents

1. [Overview](#overview)
2. [Test Architecture](#test-architecture)
3. [Database Integration Tests](#database-integration-tests)
4. [Transcript Ingestion Tests](#transcript-ingestion-tests)
5. [LLM Integration Tests](#llm-integration-tests)
6. [AppStateOrchestrator Testing](#appstateorchestrator-testing)
7. [Lazy Loading Integration Tests](#lazy-loading-integration-tests)
8. [Mock Implementations](#mock-implementations)
9. [Test Fixtures](#test-fixtures)
10. [UI Integration Tests](#ui-integration-tests)
11. [Fixture Management](#fixture-management)
12. [Test Isolation & Cleanup](#test-isolation--cleanup)
13. [Performance Testing](#performance-testing)
14. [CI/CD Integration](#cicd-integration)
15. [Troubleshooting Tests](#troubleshooting-tests)

---

## Overview

### Purpose

This guide documents Contextify's integration testing strategy, covering database, transcript ingestion, LLM, and UI integration tests. Integration tests verify that multiple components work correctly together, complementing unit tests that verify individual components in isolation.

### Test Categories

| Category | Scope | Example |
|----------|-------|---------|
| **Database Integration** | Repository layer + GRDB schema | `DatabaseTests.swift` |
| **Transcript Ingestion** | Parser + HooverEngine + repositories | `IntegrationTests.swift` |
| **LLM Integration** | FoundationLLM + SessionController + post-processing | `FoundationLLMTests.swift` |
| **UI Integration** | SwiftUI views + ViewModels + state coordination | `ContextifyUITests.swift` |
| **End-to-End** | Full pipeline from file drop to timeline display | (Not yet implemented) |

### Test Coverage (Current)

```
Contextify/ContextifyTests/
├── DatabaseTests.swift           (835 lines) - Repository + schema tests
├── IntegrationTests.swift        (268 lines) - HooverEngine workflow tests
├── FoundationLLMTests.swift      (549 lines) - LLM formatting, grounding, intent tests
├── TranscriptParserTests.swift   (91 lines)  - Parser telemetry tests
├── ProjectDiscoveryTests.swift   (124 lines) - Path mapping tests
├── GitDetectionTests.swift       - Git resolution tests
├── MetadataParserTests.swift     - Metadata extraction tests
├── MulticastStreamTests.swift    - AsyncStream multicast tests
├── LLMHealthCheckTests.swift     - LLM availability tests
├── ProjectIdentityTests.swift    - Project identity tests
├── ContextifyTests.swift         - Basic app tests
└── TestHelpers.swift             (73 lines)  - Shared test utilities

Contextify/ContextifyUITests/
├── ContextifyUITests.swift       (42 lines)  - Basic UI tests
└── ContextifyUITestsLaunchTests.swift        - Launch performance tests
```

**Total Test Files:** 13
**Estimated Coverage:** 15-20% (based on architecture-refactoring-analysis.md)

---

## Test Architecture

### XCTest Framework

All tests use Apple's XCTest framework with the following patterns:

```swift
import XCTest
import GRDB
@testable import ContextifyCore

final class MyIntegrationTests: XCTestCase {
  var tempDir: URL!

  override func setUp() async throws {
    try await super.setUp()
    // Create test environment
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try await super.tearDown()
    // Clean up test environment
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  func testFeature() throws {
    // Arrange
    // Act
    // Assert
  }
}
```

### Test Isolation Principles

1. **Unique Temporary Directories:** Each test gets a UUID-based temp directory
2. **In-Memory or Temp Databases:** Tests never touch production database
3. **No Shared State:** Tests are independent and can run in parallel
4. **Clean Teardown:** All resources released in `tearDown()`

### Async Testing

Tests support async/await for concurrent operations:

```swift
func testAsyncOperation() async throws {
  let result = await someAsyncFunction()
  XCTAssertNotNil(result)

  // Wait for condition with timeout
  try await waitForCondition("data loaded", timeout: 2.0) {
    dataIsReady()
  }
}
```

**Helper:** `waitForCondition(_:timeout:poll:condition:)` in `TestHelpers.swift:58`

---

## Database Integration Tests

### Test File: `DatabaseTests.swift`

**Location:** `Contextify/ContextifyTests/DatabaseTests.swift` (835 lines)

### Schema Creation Tests

**Function:** `testDatabaseSchemaCreation()` (DatabaseTests.swift:29)

Verifies all required tables exist after migration:

```swift
func testDatabaseSchemaCreation() throws {
  let dbPath = tempDir.appendingPathComponent("test.db")
  let pool = try makeMigratedPool(at: dbPath)

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
```

**Verified Tables:**
- `projects` - Project records
- `transcripts` - Transcript metadata
- `transcript_entries` - Parsed entries
- `timeline_cache` - LLM-generated summaries
- `transcript_metadata` - Session metadata
- `parse_errors` - Ingestion error tracking

### Repository Tests

#### ProjectRepository Tests

**Function:** `testProjectRepository()` (DatabaseTests.swift:48)

Tests CRUD operations for projects:

```swift
func testProjectRepository() throws {
  let dbPath = tempDir.appendingPathComponent("test.db")
  let pool = try makeMigratedPool(at: dbPath)
  let repo = ProjectRepositoryImpl(db: pool)

  // Create
  let projectId = try repo.create(name: "Test Project", rootPath: "/test/path", bookmark: nil)
  XCTAssertFalse(projectId.isEmpty)

  // Read
  let project = try repo.get(id: projectId)
  XCTAssertEqual(project?.name, "Test Project")

  // Update
  try repo.update(id: projectId, name: "Updated Project", bookmark: nil)

  // Delete
  try repo.delete(id: projectId)
  XCTAssertNil(try repo.get(id: projectId))
}
```

#### TranscriptRepository Tests

**Function:** `testTranscriptRepository()` (DatabaseTests.swift:79)

Tests transcript upsert and ingestion state tracking:

```swift
func testTranscriptRepository() throws {
  let transcriptId = try transcriptRepo.upsert(
    projectId: projectId,
    fileURL: fileURL,
    provider: "claude.code",
    providerSessionId: "session-123",
    lastModified: Date(),
    fileSize: 1024
  )

  // Update ingestion state (checkpoint)
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
}
```

**Key Operations Tested:**
- `upsert()` - Insert or update transcript by session ID or path hash
- `setIngestionState()` - Update ingestion checkpoint
- `get()` - Retrieve transcript by ID

#### EntryRepository Tests

**Function:** `testEntryRepository()` (DatabaseTests.swift:123)

Tests batch insertion and querying:

```swift
func testEntryRepository() throws {
  let entries = [
    TranscriptEntry(id: "1", transcriptId: transcriptId, projectId: projectId, ...),
    TranscriptEntry(id: "2", transcriptId: transcriptId, projectId: projectId, ...)
  ]

  try entryRepo.insertBatch(entries)

  // Query by transcript
  let fetched = try entryRepo.byTranscript(transcriptId)
  XCTAssertEqual(fetched.count, 2)

  // Query recent by project
  let recent = try entryRepo.recentByProject(projectId, limit: 10)
  XCTAssertEqual(recent.count, 2)
}
```

### Parser Tests

#### Claude Code Parser

**Function:** `testClaudeCodeParser()` (DatabaseTests.swift:203)

Tests parsing of Claude Code JSONL format:

```swift
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
```

#### Codex Parser

**Function:** `testCodexParser()` (DatabaseTests.swift:237)

Tests parsing of Codex CLI JSONL format:

```swift
func testCodexParser() throws {
  let parser = CodexLineParser()
  let json = """
  {
    "timestamp": "2025-10-11T12:00:00.000Z",
    "type": "response_item",
    "payload": {
      "type": "message",
      "role": "user",
      "content": [
        { "type": "input_text", "text": "Test content" }
      ]
    }
  }
  """

  let entry = try parser.parse(/* ... */)
  XCTAssertEqual(entry.kind, "user")
  XCTAssertEqual(entry.content, "Test content")
}
```

### Migration Tests

#### Migration Idempotence

**Function:** `testMigrationIdempotence()` (DatabaseTests.swift:445)

Verifies migrations can be run multiple times safely:

```swift
func testMigrationIdempotence() throws {
  let pool = try makeMigratedPool(at: dbPath)
  // Run migration twice - should not error
  try applySchema(pool)

  // Verify schema v26 columns exist
  let columns = try pool.read { db in
    try Row.fetchAll(db, sql: "PRAGMA table_info(transcripts)")
  }
  let columnNames = Set(columns.map { $0["name"] as! String })

  XCTAssertTrue(columnNames.contains("normalized_path"))
  XCTAssertTrue(columnNames.contains("path_hash"))
  XCTAssertTrue(columnNames.contains("content_length"))
  XCTAssertTrue(columnNames.contains("mtime_ms"))
}
```

#### Migration Backfill

**Function:** `testMigrationBackfillMtimeMs()` (DatabaseTests.swift:472)

Tests backfill of `mtime_ms` from legacy `mtime_ns`:

```swift
func testMigrationBackfillMtimeMs() throws {
  // Create v2 schema with mtime_ns
  try db.execute(sql: "INSERT INTO transcripts VALUES ('t1', 'p1', 'claude.code', 1234567890000000000)")

  // Run v3 migration (adds mtime_ms column)
  try applySchema(pool)

  // Verify backfill
  let result = try pool.read { db in
    try Row.fetchOne(db, sql: "SELECT mtime_ns, mtime_ms FROM transcripts WHERE id = 't1'")
  }

  let mtimeNs: Int64 = result!["mtime_ns"]
  let mtimeMs: Int64 = result!["mtime_ms"]
  XCTAssertEqual(mtimeMs, mtimeNs / 1000000) // ns to ms conversion
}
```

### Identity Resolution Tests

#### Session ID Precedence

**Function:** `testSessionIdTakesPrecedence()` (DatabaseTests.swift:540)

Verifies session ID is used for identity before path hash:

```swift
func testSessionIdTakesPrecedence() throws {
  // Create transcript with session ID
  let transcriptId1 = try transcriptRepo.upsert(
    projectId: projectId,
    fileURL: URL(fileURLWithPath: "/test/session.jsonl"),
    provider: "claude.code",
    providerSessionId: "session-123",
    lastModified: Date(),
    fileSize: 1024
  )

  // Upsert again with same session ID but different path
  let transcriptId2 = try transcriptRepo.upsert(
    projectId: projectId,
    fileURL: URL(fileURLWithPath: "/test/different-path.jsonl"),
    provider: "claude.code",
    providerSessionId: "session-123", // Same session
    lastModified: Date(),
    fileSize: 2048
  )

  // Should be same transcript (session ID takes precedence)
  XCTAssertEqual(transcriptId1, transcriptId2)
}
```

#### Path Hash Fallback

**Function:** `testPathHashFallback()` (DatabaseTests.swift:573)

Verifies path hash is used when no session ID:

```swift
func testPathHashFallback() throws {
  // Create transcript without session ID
  let transcriptId1 = try transcriptRepo.upsert(
    projectId: projectId,
    fileURL: URL(fileURLWithPath: "/test/nosession.jsonl"),
    provider: "codex.cli",
    providerSessionId: nil, // No session ID
    lastModified: Date(),
    fileSize: 1024
  )

  // Upsert again with same path
  let transcriptId2 = try transcriptRepo.upsert(
    projectId: projectId,
    fileURL: URL(fileURLWithPath: "/test/nosession.jsonl"), // Same path
    provider: "codex.cli",
    providerSessionId: nil,
    lastModified: Date(),
    fileSize: 2048
  )

  // Should be same transcript (path hash fallback)
  XCTAssertEqual(transcriptId1, transcriptId2)
}
```

### Denormalization Invariant Tests

**Function:** `testDenormalizationInvariant()` (DatabaseTests.swift:346)

Verifies `transcript_entries.project_id` matches `transcripts.project_id`:

```swift
func testDenormalizationInvariant() throws {
  // Create entry with denormalized project_id
  let entry = TranscriptEntry(
    id: UUID().uuidString,
    transcriptId: transcriptId,
    projectId: projectId, // Denormalized for performance
    // ...
  )
  try entryRepo.insertBatch([entry])

  // Check invariant (should return no rows)
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
```

**Invariant Rule:** `transcript_entries.project_id` must always equal the `project_id` of its parent transcript. This denormalization enables fast project-level queries without joins.

### Fast-Path Ingestion Tests

#### Preview Limit Test

**Function:** `testHooverEnginePreviewLimit()` (DatabaseTests.swift:647)

Tests partial ingestion with entry limit:

```swift
func testHooverEnginePreviewLimit() throws {
  // Create transcript with 20 entries
  let transcriptFile = tempDir.appendingPathComponent("test-transcript.jsonl")
  var lines: [String] = []
  for i in 1...20 {
    lines.append("""
      {"type":"user","timestamp":"...","uuid":"user-\(i)","message":{"role":"user","content":[{"type":"text","text":"Test message \(i)"}]}}
      """)
  }
  try lines.joined(separator: "\n").write(to: transcriptFile, atomically: true, encoding: .utf8)

  // Hoover with limit of 10 entries
  let outcome1 = try hooverEngine.hooverTranscript(
    transcript,
    fileURL: transcriptFile,
    progress: progressSink,
    limit: .entries(10) // Preview mode
  )

  XCTAssertEqual(outcome1.newEntries, 10, "Should ingest exactly 10 entries")
  XCTAssertFalse(outcome1.reachedEOF, "Should not reach EOF with limit")
  XCTAssertNil(outcome1.contentSha256, "Should not compute SHA when not at EOF")

  // Verify transcript state is partial
  let partialTranscript = try transcriptRepo.get(transcriptId)!
  XCTAssertEqual(partialTranscript.ingestState, "partial", "Should mark as partial")

  // Resume and complete ingestion
  let outcome2 = try hooverEngine.hooverTranscript(
    updatedTranscript,
    fileURL: transcriptFile,
    progress: progressSink,
    limit: .none // Full ingestion
  )

  XCTAssertEqual(outcome2.newEntries, 10, "Should ingest remaining 10 entries")
  XCTAssertTrue(outcome2.reachedEOF, "Should reach EOF")
  XCTAssertNotNil(outcome2.contentSha256, "Should compute SHA at EOF")
}
```

**Fast-Path Pattern:**
1. **Preview ingestion:** `limit: .entries(10)` for startup fast-path
2. **Partial state:** `ingestState = "partial"`, no content SHA256
3. **Resume ingestion:** `limit: .none` processes remaining lines
4. **Complete state:** `ingestState = "complete"`, content SHA256 computed

#### Ingestion Lock Test

**Function:** `testIngestionLockPreventsParallelIngest()` (DatabaseTests.swift:739)

Tests that ingestion locks prevent concurrent processing:

```swift
func testIngestionLockPreventsParallelIngest() async throws {
  // First call should acquire lock
  let firstCallResult = try await orchestrator.ingestTranscript(
    transcriptId: transcriptId,
    mode: .preview(entries: 10),
    notifyUI: false
  )
  XCTAssertTrue(firstCallResult, "First call should acquire lock")

  // Manually acquire lock to simulate concurrent access
  try await pool.write { db in
    try db.execute(sql: """
      INSERT INTO ingestion_locks(transcript_id, locked_at)
      VALUES (?, ?)
    """, arguments: [transcriptId, Int(Date().timeIntervalSince1970)])
  }

  // Second call should fail to acquire lock
  let secondCallResult = try await orchestrator.ingestTranscript(
    transcriptId: transcriptId,
    mode: .preview(entries: 10),
    notifyUI: false
  )

  XCTAssertFalse(secondCallResult, "Second call should return false (already complete or locked)")
}
```

**Locking Strategy:**
- Ingestion locks stored in `ingestion_locks` table
- Row inserted at ingestion start, deleted at completion
- Prevents parallel ingestion of same transcript (race condition protection)

### Index Verification Tests

**Function:** `testIngestStateIndexExists()` (DatabaseTests.swift:794)

Verifies required indexes exist for performance:

```swift
func testIngestStateIndexExists() throws {
  let indexes = try pool.read { db in
    try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='transcripts'")
  }

  XCTAssertTrue(indexes.contains("idx_tr_ingest_state_updated_at"), "Index for ingest_state should exist")
}
```

**Required Indexes (Schema v26):**
- `uq_tr_provider_session` - Unique constraint on (provider, provider_session_id)
- `uq_tr_provider_path_hash` - Unique constraint on (provider, path_hash)
- `idx_tr_mtime_ms` - Index on mtime_ms for fast discovery
- `idx_tr_ingest_state_updated_at` - Index for querying partial transcripts

### Test Helpers

**Function:** `makeMigratedPool(at:)` (DatabaseTests.swift:812)

Creates a fresh database with all migrations applied:

```swift
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
```

**Pattern:** All database tests use this helper to ensure consistent schema setup.

---

## Transcript Ingestion Tests

### Test File: `IntegrationTests.swift`

**Location:** `Contextify/ContextifyTests/IntegrationTests.swift` (268 lines)

### Initial Hoover Workflow

**Function:** `disabled_testInitialHooverWorkflow()` (IntegrationTests.swift:29)

**Status:** ⚠️ Disabled (needs HooverEngine API update)

Tests end-to-end transcript ingestion workflow:

```swift
func disabled_testInitialHooverWorkflow() throws {
  // 1. Set up database
  let dbPath = tempDir.appendingPathComponent("test.db")
  let pool = try DatabasePool(path: dbPath.path, configuration: config)
  try migrator.migrate(pool)

  // 2. Create repositories
  let projectRepo = ProjectRepositoryImpl(db: pool)
  let transcriptRepo = TranscriptRepositoryImpl(db: pool)
  let entryRepo = EntryRepositoryImpl(db: pool)

  // 3. Create hoover engine
  let hooverEngine = HooverEngine(
    db: pool,
    transcriptRepo: transcriptRepo,
    entryRepo: entryRepo,
    errorRepo: errorRepo,
    parser: MultiProviderParser(),
    // ... all repository dependencies
  )

  // 4. Create test project
  let projectId = try projectRepo.create(
    name: "Test Project",
    rootPath: "/Users/rob/code/projects/contextify",
    bookmark: nil
  )

  // 5. Create mock transcript file
  let transcriptPath = tempDir.appendingPathComponent("test-transcript.jsonl")
  let mockTranscript = """
  {"uuid":"msg-1","type":"user","timestamp":"2025-10-11T12:00:00.000Z","sessionId":"session-123","message":{"role":"user","content":"Hello"},"gitBranch":"main"}
  {"uuid":"msg-2","type":"assistant","timestamp":"2025-10-11T12:00:01.000Z","sessionId":"session-123","message":{"role":"assistant","content":"Hi there!"},"gitBranch":"main"}
  {"uuid":"msg-3","type":"user","timestamp":"2025-10-11T12:00:02.000Z","sessionId":"session-123","message":{"role":"user","content":"How are you?"},"gitBranch":"main"}
  """
  try mockTranscript.write(to: transcriptPath, atomically: true, encoding: .utf8)

  // 6. Register transcript
  let transcriptId = try transcriptRepo.upsert(
    projectId: projectId,
    fileURL: transcriptPath,
    provider: "claude.code",
    providerSessionId: "session-123",
    lastModified: Date(),
    fileSize: mockTranscript.utf8.count
  )

  // 7. Kick off hoover
  let progress = LoggingProgressSink(log: Logger(subsystem: "test", category: "hoover"))
  let outcome = try hooverEngine.hooverTranscript(
    transcript,
    fileURL: transcriptPath,
    progress: progress
  )

  // 8. Verify results
  XCTAssertTrue(outcome.reachedEOF, "Should reach EOF for small transcript")

  // Check entries
  let entries = try entryRepo.byTranscript(transcriptId, afterTimestamp: nil)
  XCTAssertEqual(entries.count, 3, "Should have 3 entries")
  XCTAssertEqual(entries[0].content, "Hello")
  XCTAssertEqual(entries[1].content, "Hi there!")
  XCTAssertEqual(entries[2].content, "How are you?")

  // Check ingestion state
  let updated = try transcriptRepo.get(transcriptId)
  XCTAssertEqual(updated?.lastProcessedLine, 3)
  XCTAssertEqual(updated?.lineCount, 3)
}
```

**Workflow Steps:**
1. Create database pool with migrations
2. Instantiate all repositories
3. Create HooverEngine with dependencies
4. Create test project
5. Write mock transcript JSONL to temp file
6. Register transcript in database
7. Run hoover ingestion
8. Verify entries, content, and checkpoint state

### Crash Recovery Test

**Function:** `disabled_testCrashRecovery()` (IntegrationTests.swift:185)

**Status:** ⚠️ Disabled (needs HooverEngine API update)

Tests resume from checkpoint after simulated crash:

```swift
func disabled_testCrashRecovery() throws {
  // Create transcript with 10 lines
  let lines = (1...10).map { i in
    """
    {"uuid":"msg-\(i)","type":"user","timestamp":"...","sessionId":"s1","message":{"role":"user","content":"Message \(i)"}}
    """
  }
  try lines.joined(separator: "\n").write(to: transcriptPath, atomically: true, encoding: .utf8)

  // Simulate crash after processing 5 lines
  try transcriptRepo.setIngestionState(
    id: transcriptId,
    lastProcessedLine: 5,
    lineCount: 10,
    parserVersion: 1,
    status: "active",
    ingestState: "complete",
    lastError: nil
  )

  // Resume hoover (should start from line 6)
  _ = try hooverEngine.hooverTranscript(
    transcript,
    fileURL: transcriptPath,
    progress: NoOpProgressSink()
  )

  // Verify it processed remaining lines (6-10)
  let entries = try entryRepo.byTranscript(transcriptId, afterTimestamp: nil)
  XCTAssertEqual(entries.count, 5, "Should only process new lines (6-10)")
}
```

**Crash Recovery Pattern:**
1. HooverEngine reads `lastProcessedLine` from transcript
2. Seeks to resume position in JSONL file
3. Processes only new lines since checkpoint
4. Updates checkpoint after each batch (1000 lines)

### Orchestrator Workflow Test

**Function:** `disabled_testOrchestratorWorkflow()` (IntegrationTests.swift:143)

**Status:** ⚠️ Disabled (needs TranscriptOrchestrator API update)

Documents recommended high-level API usage:

```swift
func disabled_testOrchestratorWorkflow() throws {
  // Recommended production workflow (commented out - API changed)

  // 1. Create orchestrator (uses default DB location)
  // let orchestrator = try TranscriptOrchestrator()

  // 2. Create or get project
  // let projectId = try orchestrator.createProject(
  //   name: "My Project",
  //   rootPath: "/Users/rob/code/projects/myproject",
  //   bookmark: nil
  // )

  // 3. Discover transcripts
  // let claudeDir = FileManager.default.homeDirectoryForCurrentUser
  //   .appendingPathComponent(".claude/projects/myproject")
  // let transcriptFiles = try FileManager.default.contentsOfDirectory(...)

  // 4. Batch discover and hoover
  // let files = transcriptFiles.map { (url: $0, provider: "claude.code", sessionId: nil) }
  // try orchestrator.discoverTranscripts(
  //   projectId: projectId,
  //   transcriptFiles: files,
  //   progress: LoggingProgressSink(log: log)
  // )

  // 5. Query results
  // let recentEntries = try orchestrator.getRecentEntries(forProject: projectId, limit: 50)
}
```

**Note:** This test is disabled because `TranscriptOrchestrator` API has changed. It serves as documentation of the intended high-level workflow.

### Progress Sink Helpers

**Class:** `NoOpProgressSink` (IntegrationTests.swift:827)

```swift
private final class NoOpProgressSink: IngestProgressSink, @unchecked Sendable {
  func didStartTranscript(name: String, totalLines: Int?) {}
  func didAdvance(linesProcessed: Int, totalLines: Int?) {}
  func didCompleteTranscript(durationMs: Int) {}
  func didFailTranscript(error: String) {}
  func didStartProject(name: String, transcriptCount: Int) {}
  func didCompleteProject(name: String) {}
}
```

**Usage:** Silent progress sink for tests that don't need logging.

---

## LLM Integration Tests

### Test File: `FoundationLLMTests.swift`

**Location:** `Contextify/ContextifyTests/FoundationLLMTests.swift` (549 lines)

### Formatting Tests

**Test Class:** `FormattingTests` (FoundationLLMTests.swift:8)

#### Assistant Prefix and Length

**Function:** `testAssistantPrefixAndLength()` (FoundationLLMTests.swift:9)

```swift
func testAssistantPrefixAndLength() async {
  let sanitized = await FoundationLLM.shared._testSanitize(String(repeating: "x", count: 200), kind: .assistant)
  XCTAssertTrue(sanitized.hasPrefix("Claude"))
  XCTAssertLessThanOrEqual(sanitized.count, 140)
}
```

**Rule:** Assistant messages prefixed with "Claude" and truncated to 140 chars.

#### User Message Preservation

**Function:** `testUserPrefixesRespected()` (FoundationLLMTests.swift:15)

```swift
func testUserPrefixesRespected() async {
  let made = await FoundationLLM.shared._testSanitize("You made the change.", kind: .user)
  XCTAssertEqual(made, "You made the change.")
}
```

**Rule:** User messages passed through without prefix.

#### Truncation Word Boundaries

**Function:** `testTruncationRespectsWordBoundaries()` (FoundationLLMTests.swift:20)

```swift
func testTruncationRespectsWordBoundaries() async {
  let longText = "You made a detailed implementation plan for converting existing files to /build/notes/current.md, replacing prior contents, and appending the complete state of all related files."
  let sanitized = await FoundationLLM.shared._testSanitize(longText, kind: .user)

  XCTAssertLessThanOrEqual(sanitized.count, 140)
  XCTAssertFalse(sanitized.hasSuffix("th"), "Should not truncate mid-word")

  // Should end with ellipsis if truncated
  if sanitized.count < longText.count {
    XCTAssertTrue(sanitized.hasSuffix("…"), "Truncated text should end with ellipsis")
  }
}
```

**Rule:** Truncation must not cut words in half. Last character before ellipsis should be alphanumeric or punctuation.

### Grounding Tests (macOS 26+)

**Test Class:** `GroundingTests` (FoundationLLMTests.swift:51)

**Availability:** `@available(macOS 26.0, *)`

#### Ungrounded Acknowledgment Correction

**Function:** `testUngroundedAckIsCorrected()` (FoundationLLMTests.swift:52)

```swift
func testUngroundedAckIsCorrected() async throws {
  let payload = GuidedTimelineSummary(
    summary: "Claude proposes reviewing the backfill logic for edge cases.",
    isCompletion: false,
    disposition: "analysis",
    grounding: "ungrounded",
    confidence: 0.4
  )
  let result = try await FoundationLLM.shared._testPostProcess(kind: .assistant, payload: payload, message: "Ack!")
  XCTAssertEqual(result.summary, "Claude acknowledges the request.")
  XCTAssertFalse(result.isCompletion)
}
```

**Rule:** When LLM returns ungrounded summary but message is short acknowledgment, replace with standard "Claude acknowledges the request."

#### Minimal Leakage Acceptance

**Function:** `testGroundedWithMinimalLeakageAccepted()` (FoundationLLMTests.swift:146)

```swift
func testGroundedWithMinimalLeakageAccepted() async throws {
  let message = "I've updated the configuration file to use the new API endpoint."
  let payload = GuidedTimelineSummary(
    summary: "Claude updated the configuration file",
    isCompletion: true,
    disposition: "completion",
    grounding: "grounded",
    confidence: 0.9
  )
  let result = try await FoundationLLM.shared._testPostProcess(kind: .assistant, payload: payload, message: message)
  XCTAssertTrue(result.summary.contains("updated"))
  XCTAssertTrue(result.summary.contains("configuration"))
}
```

**Rule:** Summaries with minimal leakage (<3 tokens not in message) and high confidence (≥0.75) are accepted.

#### Substantial Leakage Rejection

**Function:** `testSubstantialLeakageTriggersRejection()` (FoundationLLMTests.swift:102)

```swift
func testSubstantialLeakageTriggersRejection() async {
  let message = "The file is located at /tmp/foo.txt"
  let payload = GuidedTimelineSummary(
    summary: "Claude explains the database connection pooling strategy",
    isCompletion: false,
    disposition: "analysis",
    grounding: "ungrounded",
    confidence: 0.8
  )
  // Should throw because summary introduces many topics not in message
  do {
    _ = try await FoundationLLM.shared._testPostProcess(kind: .assistant, payload: payload, message: message)
    XCTFail("Expected error to be thrown")
  } catch {
    // Expected - summary should be rejected and trigger retry
  }
}
```

**Rule:** Summaries with substantial leakage (new topics not in message) are rejected regardless of confidence.

#### Low Confidence Rejection

**Function:** `testLowConfidenceWithLeakageTriggersRejection()` (FoundationLLMTests.swift:124)

```swift
func testLowConfidenceWithLeakageTriggersRejection() async {
  let message = "The value is 42."
  let payload = GuidedTimelineSummary(
    summary: "Claude analyzes the configuration parameters",
    isCompletion: false,
    disposition: "analysis",
    grounding: "grounded",
    confidence: 0.2
  )
  // Should throw because confidence is very low
  do {
    _ = try await FoundationLLM.shared._testPostProcess(/* ... */)
    XCTFail("Expected error to be thrown")
  } catch {
    // Expected - summary should be rejected and trigger retry
  }
}
```

**Rule:** Summaries with confidence <0.5 are rejected, even if marked "grounded".

### User Intent Tests

**Test Class:** `UserIntentTests` (FoundationLLMTests.swift:199)

#### Imperative Directive Detection

**Function:** `testImperativeDirectiveAtStart()` (FoundationLLMTests.swift:200)

```swift
func testImperativeDirectiveAtStart() async throws {
  let intent = await FoundationLLM.shared._testClassifyUserIntent("Commit your changes with a note")
  XCTAssertEqual(intent, .directive)
}
```

**Rule:** Messages starting with imperative verbs (commit, update, fix, etc.) are classified as `.directive`.

#### Question Detection

**Function:** `testQuestionDetection()` (FoundationLLMTests.swift:212)

```swift
func testQuestionDetection() async throws {
  let intent = await FoundationLLM.shared._testClassifyUserIntent("What does the validateVenv function do?")
  XCTAssertEqual(intent, .question)
}
```

**Rule:** Messages starting with question words (what, how, why, etc.) are classified as `.question`.

#### Affirmative Detection

**Function:** `testBareAffirmative()` (FoundationLLMTests.swift:222)

```swift
func testBareAffirmative() async throws {
  let intent = await FoundationLLM.shared._testClassifyUserIntent("ok proceed")
  XCTAssertEqual(intent, .affirmative)
}
```

**Rule:** Bare affirmatives (ok, yes, proceed, etc.) are classified as `.affirmative`.

#### Word Boundary Tests (INT-1)

**Function:** `testImperativeWordBoundaries()` (FoundationLLMTests.swift:244)

```swift
func testImperativeWordBoundaries() async throws {
  // "read" as imperative should be directive
  let readIntent = await FoundationLLM.shared._testClassifyUserIntent("read the log")
  XCTAssertEqual(readIntent, .directive, "Standalone 'read' should be directive")

  // "readme" should NOT be classified as directive
  let readmeIntent = await FoundationLLM.shared._testClassifyUserIntent("readme updated")
  XCTAssertNotEqual(readmeIntent, .directive, "'readme' should not match imperative 'read'")
}
```

**Rule:** Intent classification must respect word boundaries (no substring matches).

#### Contraction Normalization

**Function:** `testContractionWithTrailingPunctuation()` (FoundationLLMTests.swift:381)

```swift
func testContractionWithTrailingPunctuation() async throws {
  let commaIntent = await FoundationLLM.shared._testClassifyUserIntent("dont, do that")
  XCTAssertEqual(commaIntent, .directive, "'dont,' should normalize to 'don't' and be directive")

  let exclamIntent = await FoundationLLM.shared._testClassifyUserIntent("dont! that's wrong")
  XCTAssertEqual(exclamIntent, .directive, "'dont!' should normalize to 'don't' and be directive")
}
```

**Rule:** Missing apostrophes in contractions (dont → don't, couldnt → couldn't) are normalized before classification.

### Action Hint Tests

**Test Class:** `ActionHintTests` (FoundationLLMTests.swift:184)

**Function:** `testAffirmWithHintExtraction()` (FoundationLLMTests.swift:186)

```swift
@MainActor
func testAffirmWithHintExtraction() {
  let hint = ConversationMonitor.shared._testDistilledActionHint(from: "Would you like me to ensure five displayable entries?")
  XCTAssertEqual(hint, "Would you like me to ensure five displayable entries")
}
```

**Rule:** Action hints extracted from assistant questions (trailing `?` removed).

**Function:** `testUseActionHintGate()` (FoundationLLMTests.swift:192)

```swift
@MainActor
func testUseActionHintGate() {
  XCTAssertTrue(ConversationMonitor.shared._testShouldUseActionHint("Yes."))
  XCTAssertTrue(ConversationMonitor.shared._testShouldUseActionHint("OK, proceed"))
  XCTAssertFalse(ConversationMonitor.shared._testShouldUseActionHint("Yes, but also explain why."))
}
```

**Rule:** Action hints only used for bare affirmatives (no additional instructions).

### Performance Benchmarks

**Test Class:** `LLMBenchmarks` (FoundationLLMTests.swift:414)

**Availability:** `@available(macOS 26.0, *)`

**Function:** `testSessionCreationBenchmark()` (FoundationLLMTests.swift:416)

```swift
func testSessionCreationBenchmark() throws {
  guard ProcessInfo.processInfo.environment["RUN_LLM_BENCH"] == "1" else {
    throw XCTSkip("Set RUN_LLM_BENCH=1 to run performance benchmarks")
  }

  let iterations = 1_000
  let instructions = "Summarize text concisely."

  let start = Date()
  for _ in 0..<iterations {
    _ = LanguageModelSession(instructions: instructions)
  }
  let elapsed = Date().timeIntervalSince(start)
  let avgMs = (elapsed * 1000.0) / Double(iterations)

  print(String(format: "Session creation avg: %.3f ms", avgMs))
  print("Decision: use stateless if < 1-2ms, pooled+reset otherwise")
}
```

**Usage:** Run with `RUN_LLM_BENCH=1 xcodebuild test` to measure session creation cost.

**Decision Threshold:** If session creation <2ms, use stateless mode. Otherwise, pool sessions and reset between requests.

### Concurrency and Lifecycle Tests

**Test Class:** `ConcurrencyAndLifecycleTests` (FoundationLLMTests.swift:443)

**Availability:** `@available(macOS 26.0, *)` + `#if DEBUG`

#### Session Controller FIFO

**Function:** `testSessionControllerFIFO()` (FoundationLLMTests.swift:457)

```swift
func testSessionControllerFIFO() async throws {
  #if DEBUG
  let controller = SessionController(instructions: "Test", forceStateless: false)

  // Initially no waiters
  let initialCount = await controller._debugWaiterCount()
  XCTAssertEqual(initialCount, 0, "Queue should start empty")
  #else
  throw XCTSkip("DEBUG hooks only available in debug builds")
  #endif
}
```

**Rule:** DEBUG builds expose `_debugWaiterCount()` for testing FIFO queue behavior.

#### Circuit Breaker

**Function:** `testCircuitBreakerBehavior()` (FoundationLLMTests.swift:489)

```swift
func testCircuitBreakerBehavior() async throws {
  #if DEBUG
  let controller = SessionController(instructions: "Test", forceStateless: false)

  let requestCount = await controller._debugRequestCount()
  let errorCount = await controller._debugConsecutiveErrors()
  XCTAssertEqual(requestCount, 0, "Request count should start at 0")
  XCTAssertEqual(errorCount, 0, "Error count should start at 0")

  // Circuit breaker limits:
  // - Max 15 requests per session
  // - Max 3 consecutive errors
  #else
  throw XCTSkip("DEBUG hooks only available in debug builds")
  #endif
}
```

**Rule:** SessionController circuit breaker trips after 3 consecutive errors OR 15 total requests.

#### Epoch Tracking

**Function:** `testEpochTracking()` (FoundationLLMTests.swift:509)

```swift
func testEpochTracking() async throws {
  #if DEBUG
  let controller = SessionController(instructions: "Test", forceStateless: false)

  let initialEpoch = await controller._debugEpoch()

  await controller.reset()
  let afterFirstReset = await controller._debugEpoch()
  XCTAssertGreaterThan(afterFirstReset, initialEpoch, "Epoch should increment after reset")
  #else
  throw XCTSkip("DEBUG hooks only available in debug builds")
  #endif
}
```

**Rule:** Epoch increments on each `reset()`. Used to invalidate stale waiter continuations.

---

## AppStateOrchestrator Testing

### Overview

AppStateOrchestrator is the central state coordinator managing startup, project discovery, JIT ingestion, and background indexing. Tests verify state machine correctness, performance targets, cancellation behavior, and cache coherency.

### Test Goals

1. **State Machine Correctness** - All valid transitions work, invalid transitions handled gracefully
2. **Performance** - Startup <200ms, JIT ingestion <1s
3. **Cancellation** - Background work cancels gracefully on user interaction
4. **Error Handling** - Failures transition to error state with user-facing messages
5. **Cache Coherency** - Project lookup cache stays synchronized with database

### Test Infrastructure

**Setup Pattern:**

```swift
@MainActor
class AppStateOrchestratorTests: XCTestCase {
  var orchestrator: AppStateOrchestrator!
  var tempDB: URL!

  override func setUp() async throws {
    try await super.setUp()

    // Create temporary database
    tempDB = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("db")

    // Initialize orchestrator
    // Note: Full DI will be added in Phase 4
    // For now, tests use real services with temp DB
    orchestrator = AppStateOrchestrator.shared

    // Reset to clean state
    await orchestrator.reset()  // Requires test API addition
  }

  override func tearDown() async throws {
    try await super.tearDown()
    if let tempDB = tempDB {
      try? FileManager.default.removeItem(at: tempDB)
    }
  }
}
```

**Note:** Full dependency injection requires Phase 4 refactor. Current tests use real services with temporary database.

---

### State Machine Transition Tests

**Test 1: Startup Flow**

Verify normal startup sequence (startup → discovering → idle):

```swift
@MainActor
func testStartupFlow() async throws {
  // Given: Fresh app state
  XCTAssertEqual(orchestrator.state, .startup)

  // When: Call startup
  await orchestrator.startup()

  // Then: Should transition to idle with discovered projects
  await Task.yield()  // Let async work complete

  guard case .idle(let projects) = orchestrator.state else {
    XCTFail("Expected idle state, got: \(orchestrator.state)")
    return
  }

  XCTAssertFalse(projects.isEmpty, "Should discover projects")
}
```

**Test 2: Project Selection (JIT)**

Verify JIT ingestion on project selection (idle → loading → active):

```swift
@MainActor
func testProjectSelectionJIT() async throws {
  // Given: Idle state with projects
  await orchestrator.startup()
  await Task.yield()

  guard case .idle(let projects) = orchestrator.state,
        let firstProject = projects.first else {
    XCTFail("No projects available")
    return
  }

  // When: Select project
  await orchestrator.selectProject(id: firstProject.id)

  // Then: Should transition through loading to active
  await Task.yield()

  guard case .active(let projectId) = orchestrator.state else {
    XCTFail("Expected active state, got: \(orchestrator.state)")
    return
  }

  XCTAssertEqual(projectId, firstProject.id)
}
```

**Test 3: Invalid Transition Prevention**

Verify graceful handling of invalid state transitions:

```swift
@MainActor
func testInvalidTransitionPrevention() async throws {
  // Given: Startup state (before discovery)
  XCTAssertEqual(orchestrator.state, .startup)

  // When: Try to select project before discovery completes
  let fakeId = "nonexistent-project-id"
  await orchestrator.selectProject(id: fakeId)
  await Task.yield()

  // Then: Should transition to error state (not crash)
  guard case .error(let message) = orchestrator.state else {
    XCTFail("Expected error state for invalid transition, got: \(orchestrator.state)")
    return
  }

  XCTAssertFalse(message.isEmpty, "Error message should be present")
}
```

**Test 4: Error State Transition**

Verify error handling during ingestion failures:

```swift
@MainActor
func testErrorStateOnIngestionFailure() async throws {
  // Given: Idle state
  await orchestrator.startup()
  await Task.yield()

  // When: Select project that will fail ingestion
  // (Requires corrupt test fixture or mock that throws)
  let corruptProjectId = "corrupt-project"
  await orchestrator.selectProject(id: corruptProjectId)
  await Task.yield()

  // Then: Should be in error state with user-facing message
  guard case .error(let message) = orchestrator.state else {
    XCTFail("Expected error state after ingestion failure")
    return
  }

  XCTAssertFalse(message.isEmpty, "Error message should explain failure")
}
```

---

### Performance Tests

**Test 5: Startup Performance**

Measure startup time (target: <200ms):

```swift
@MainActor
func testStartupPerformance() async throws {
  measure(metrics: [XCTClockMetric()]) {
    Task { @MainActor in
      await orchestrator.startup()
    }
  }

  // XCTest baseline will track regressions
  // Manual assertion (if baseline not set):
  // XCTAssertLessThan(duration, 0.2, "Startup too slow")
}
```

**Test 6: JIT Ingestion Performance**

Measure project selection time (target: <1s for typical project):

```swift
@MainActor
func testJITIngestionPerformance() async throws {
  // Given: Idle state with projects
  await orchestrator.startup()

  guard case .idle(let projects) = orchestrator.state,
        let firstProject = projects.first else {
    XCTFail("No projects available")
    return
  }

  // When: Measure project selection duration
  let start = Date()
  await orchestrator.selectProject(id: firstProject.id)
  let duration = Date().timeIntervalSince(start)

  // Then: Should complete in <1s for typical project
  XCTAssertLessThan(duration, 1.0,
    "JIT ingestion too slow: \(duration)s")
}
```

---

### Cancellation Tests

**Test 7: Background Work Cancellation**

Verify background indexing cancels when user selects project:

```swift
@MainActor
func testBackgroundWorkCancellation() async throws {
  // Given: Background indexing running
  await orchestrator.startup()
  await Task.yield()

  // Background indexing starts automatically after idle timeout (5s)
  // For testing, verify cancellation on user action

  guard case .idle(let projects) = orchestrator.state,
        let project = projects.first else {
    XCTFail("No projects available")
    return
  }

  // When: User selects project (should cancel background work)
  await orchestrator.selectProject(id: project.id)

  // Then: Background work should be cancelled
  // Note: Requires test API to inspect backgroundTask state
  // Phase 4: Add cancellation verification methods
}
```

---

### Cache Coherency Tests

**Test 8: Project Lookup Cache Hit**

Verify project lookup cache works correctly:

```swift
@MainActor
func testProjectLookupCacheHit() async throws {
  // Given: Projects discovered and cached
  await orchestrator.startup()

  guard case .idle(let projects) = orchestrator.state,
        let firstProject = projects.first else {
    XCTFail("No projects available")
    return
  }

  // When: Select project by ID (should hit cache)
  await orchestrator.selectProject(id: firstProject.id)

  // Then: Should resolve from cache (fast, no DB query)
  // Verify via logs showing cache hit
  // Phase 4: Add cache metrics for assertion
}
```

**Test 9: Cache Miss Fallback**

Verify cache miss falls back to database correctly:

```swift
@MainActor
func testCacheMissFallbackToDatabase() async throws {
  // Given: Project exists in DB but not in cache
  // (Simulate by inserting project directly via DB)

  let testProjectId = "cache-miss-test"

  // Insert project to database...
  // (Requires database access in test)

  // When: Select project not in cache
  await orchestrator.selectProject(id: testProjectId)

  // Then: Should fall back to DB and succeed
  guard case .active(let projectId) = orchestrator.state else {
    XCTFail("Expected active state after cache miss, got: \(orchestrator.state)")
    return
  }

  XCTAssertEqual(projectId, testProjectId)
}
```

---

## Lazy Loading Integration Tests

### Overview

Lazy loading architecture defers transcript ingestion until project selection. Tests verify startup stays lightweight (no ingestion), JIT ingestion works correctly, and background indexing functions as expected.

### Test Goals

1. **Startup Lightweight** - No ingestion at startup (0 transcripts written)
2. **JIT Ingestion** - Only selected project ingested (not others)
3. **Background Indexing** - Inactive projects ingested in background
4. **Memory Efficiency** - Startup memory 3-5x lower than eager loading

---

### Database State Tests

**Test 1: Startup Does Not Ingest**

Verify startup only updates project metadata (no transcript ingestion):

```swift
func testStartupDoesNotIngestTranscripts() async throws {
  // Given: Fresh database
  let db = try DatabaseManager(path: tempDB)
  let transcriptCountBefore = try db.read { db in
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts") ?? 0
  }

  // When: App starts
  await orchestrator.startup()
  await Task.yield()

  // Then: No transcripts ingested (only project metadata updated)
  let transcriptCountAfter = try db.read { db in
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts") ?? 0
  }

  XCTAssertEqual(transcriptCountBefore, transcriptCountAfter,
    "Startup should not ingest transcripts")

  // Verify project metadata was updated
  let projectCount = try db.read { db in
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects") ?? 0
  }
  XCTAssertGreaterThan(projectCount, 0,
    "Projects metadata should be created/updated")
}
```

**Test 2: JIT Ingests Only Selected Project**

Verify JIT ingestion affects only selected project:

```swift
func testJITIngestsOnlySelectedProject() async throws {
  // Given: Multiple projects, none ingested
  await orchestrator.startup()

  guard case .idle(let projects) = orchestrator.state,
        projects.count >= 2 else {
    XCTFail("Need at least 2 projects for this test")
    return
  }

  let selectedProject = projects[0]
  let otherProject = projects[1]

  // When: Select first project only
  await orchestrator.selectProject(id: selectedProject.id)
  await Task.yield()

  // Then: First project has transcripts, second doesn't
  let db = try DatabaseManager(path: tempDB)

  let selectedTranscripts = try db.read { db in
    try Int.fetchOne(db, sql:
      "SELECT COUNT(*) FROM transcripts WHERE project_id = ?",
      arguments: [selectedProject.id]
    ) ?? 0
  }
  XCTAssertGreaterThan(selectedTranscripts, 0,
    "Selected project should have ingested transcripts")

  let otherTranscripts = try db.read { db in
    try Int.fetchOne(db, sql:
      "SELECT COUNT(*) FROM transcripts WHERE project_id = ?",
      arguments: [otherProject.id]
    ) ?? 0
  }
  XCTAssertEqual(otherTranscripts, 0,
    "Other project should NOT have transcripts yet (lazy loading)")
}
```

---

### Memory Efficiency Tests

**Test 3: Startup Memory Footprint**

Verify startup memory increase is minimal:

```swift
func testStartupMemoryFootprint() async throws {
  // Measure memory before startup
  let memoryBefore = getMemoryUsage()

  // When: App starts
  await orchestrator.startup()
  await Task.yield()

  // Then: Memory increase should be <50 MB
  let memoryAfter = getMemoryUsage()
  let increase = memoryAfter - memoryBefore

  XCTAssertLessThan(increase, 50_000_000,  // 50 MB
    "Startup memory increase too high: \(increase / 1_000_000) MB")
}

private func getMemoryUsage() -> UInt64 {
  var info = mach_task_basic_info()
  var count = mach_msg_type_number_t(
    MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
  )

  let result = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO),
        $0, &count)
    }
  }

  return result == KERN_SUCCESS ? info.resident_size : 0
}
```

---

### Background Indexing Tests

**Test 4: Background Indexing After Idle**

Verify background indexing starts after idle timeout:

```swift
func testBackgroundIndexingAfterIdle() async throws {
  // Given: Idle state with multiple projects
  await orchestrator.startup()

  guard case .idle(let projects) = orchestrator.state,
        projects.count > 1 else {
    XCTFail("Need multiple projects for background indexing test")
    return
  }

  // When: Wait for background indexing to start
  // (Background indexing has 5s delay after idle)
  try await Task.sleep(nanoseconds: 6_000_000_000)  // 6 seconds

  // Then: Some projects should be ingested in background
  let db = try DatabaseManager(path: tempDB)
  let ingestedProjectCount = try db.read { db in
    try Int.fetchOne(db, sql:
      "SELECT COUNT(DISTINCT project_id) FROM transcripts"
    ) ?? 0
  }

  XCTAssertGreaterThan(ingestedProjectCount, 0,
    "Background indexing should have ingested projects")
}
```

---

## Mock Implementations

**Note:** Full mocking requires dependency injection (planned for Phase 4). These are proposed patterns for future implementation.

### MockLightweightDiscoveryService

```swift
actor MockLightweightDiscoveryService {
  var mockProjects: [LightweightProject] = []
  var scanDelay: TimeInterval = 0.1  // Simulated delay

  func discoverProjectsLightweight() async -> [LightweightProject] {
    try? await Task.sleep(nanoseconds: UInt64(scanDelay * 1_000_000_000))
    return mockProjects
  }

  // Test helper
  func addMockProject(id: String, name: String) {
    mockProjects.append(LightweightProject(
      id: id,
      path: URL(fileURLWithPath: "/mock/\(name)"),
      displayName: name,
      transcriptCount: 5,
      lastActivity: Date(),
      provider: "mock",
      cwd: "/mock/\(name)",
      transcriptFiles: []
    ))
  }
}
```

### MockFastPathIngestionCoordinator

```swift
actor MockFastPathIngestionCoordinator {
  var shouldFail = false
  var ingestionDelay: TimeInterval = 0.5

  func ingestProjectJIT(_ project: LightweightProject) async throws -> String {
    try await Task.sleep(nanoseconds: UInt64(ingestionDelay * 1_000_000_000))

    if shouldFail {
      throw IngestionError.mockFailure
    }

    return project.id
  }

  func cancel() async {
    // Mock cancellation
  }
}

enum IngestionError: Error {
  case mockFailure
}
```

### Usage Example (Phase 4)

```swift
@MainActor
func testWithMocks() async throws {
  let mockDiscovery = MockLightweightDiscoveryService()
  mockDiscovery.addMockProject(id: "test1", name: "Test Project 1")
  mockDiscovery.addMockProject(id: "test2", name: "Test Project 2")

  let mockIngestion = MockFastPathIngestionCoordinator()

  // Inject mocks (requires DI refactor in Phase 4)
  let orchestrator = AppStateOrchestrator(
    discovery: mockDiscovery,
    ingestion: mockIngestion
  )

  // Test with controlled environment
  await orchestrator.startup()
  // Assertions...
}
```

---

## Test Fixtures

### Lightweight Project Fixtures

**Location:** `ContextifyTests/Fixtures/LightweightProjects.swift`

```swift
struct LightweightProjectFixtures {
  static let typical = LightweightProject(
    id: "test-project-1",
    path: URL(fileURLWithPath: "/tmp/test-project-1"),
    displayName: "Test Project 1",
    transcriptCount: 5,
    lastActivity: Date(),
    provider: "claude.code",
    cwd: "/Users/test/repos/project-1",
    transcriptFiles: [
      URL(fileURLWithPath: "/tmp/test-project-1/transcript1.jsonl"),
      URL(fileURLWithPath: "/tmp/test-project-1/transcript2.jsonl")
    ]
  )

  static let empty = LightweightProject(
    id: "test-project-empty",
    path: URL(fileURLWithPath: "/tmp/test-project-empty"),
    displayName: "Empty Project",
    transcriptCount: 0,
    lastActivity: Date().addingTimeInterval(-86400),  // 1 day ago
    provider: "claude.code",
    cwd: nil,
    transcriptFiles: []
  )

  static let large = LightweightProject(
    id: "test-project-large",
    path: URL(fileURLWithPath: "/tmp/test-project-large"),
    displayName: "Large Project",
    transcriptCount: 100,
    lastActivity: Date(),
    provider: "codex.cli",
    cwd: "/Users/test/repos/large-project",
    transcriptFiles: (0..<100).map { i in
      URL(fileURLWithPath: "/tmp/test-project-large/transcript\(i).jsonl")
    }
  )
}
```

### AppState Fixtures

```swift
extension AppState {
  static var fixtureIdle: AppState {
    .idle(projects: [
      LightweightProjectFixtures.typical,
      LightweightProjectFixtures.empty
    ])
  }

  static var fixtureLoading: AppState {
    .loading(projectId: "test-project-1")
  }

  static var fixtureActive: AppState {
    .active(projectId: "test-project-1")
  }

  static var fixtureError: AppState {
    .error("Test error message")
  }
}
```

---

## UI Integration Tests

### Test Files

**Location:** `Contextify/ContextifyUITests/`

- `ContextifyUITests.swift` (42 lines) - Basic UI interaction tests
- `ContextifyUITestsLaunchTests.swift` - Launch performance tests

### Basic UI Test

**Function:** `testExample()` (ContextifyUITests.swift:26)

```swift
@MainActor
func testExample() throws {
  let app = XCUIApplication()
  app.launch()

  // Use XCTAssert and related functions to verify your tests produce the correct results.
}
```

**Status:** ⚠️ Placeholder (no assertions)

### Launch Performance Test

**Function:** `testLaunchPerformance()` (ContextifyUITests.swift:35)

```swift
@MainActor
func testLaunchPerformance() throws {
  measure(metrics: [XCTApplicationLaunchMetric()]) {
    XCUIApplication().launch()
  }
}
```

**Metrics:** Measures cold start time using `XCTApplicationLaunchMetric`.

### UI Test Gaps

**Missing Coverage:**
- ❌ HUD view interaction (file drop, project switching)
- ❌ Timeline display rendering
- ❌ ConversationMonitor state transitions
- ❌ Settings panel interactions (database migration, folder access)
- ❌ Accessibility compliance

**Recommendation:** Add UI integration tests for:
1. Project switcher dropdown population
2. Timeline entry rendering (user vs assistant messages)
3. LLM summary display
4. Error state handling (database locked, parse errors)
5. Drag-and-drop file ingestion

---

## Fixture Management

### Current Approach

Tests create mock data programmatically:

```swift
// Example: Mock transcript JSONL
let mockTranscript = """
{"uuid":"msg-1","type":"user","timestamp":"2025-10-11T12:00:00.000Z","sessionId":"session-123","message":{"role":"user","content":"Hello"},"gitBranch":"main"}
{"uuid":"msg-2","type":"assistant","timestamp":"2025-10-11T12:00:01.000Z","sessionId":"session-123","message":{"role":"assistant","content":"Hi there!"},"gitBranch":"main"}
"""
try mockTranscript.write(to: transcriptPath, atomically: true, encoding: .utf8)
```

### Fixture File Strategy (Recommended)

For complex test scenarios, store fixtures in repository:

```
Contextify/ContextifyTests/Fixtures/
├── transcripts/
│   ├── claude-code-simple.jsonl       (3 messages)
│   ├── claude-code-tool-use.jsonl     (tool_use + tool_result blocks)
│   ├── codex-cli-session.jsonl        (global session format)
│   └── malformed-entries.jsonl        (parse error scenarios)
├── databases/
│   └── sample-projects.sql            (Pre-populated test data)
└── git-repos/
    └── minimal-repo.zip               (Git worktree test cases)
```

### Fixture Loading Helper

```swift
extension XCTestCase {
  func loadFixture(name: String, extension ext: String = "jsonl") throws -> URL {
    let bundle = Bundle(for: type(of: self))
    guard let url = bundle.url(forResource: name, withExtension: ext) else {
      throw XCTSkip("Fixture \(name).\(ext) not found")
    }
    return url
  }

  func loadFixtureContents(name: String, extension ext: String = "jsonl") throws -> String {
    let url = try loadFixture(name: name, extension: ext)
    return try String(contentsOf: url, encoding: .utf8)
  }
}
```

**Usage:**

```swift
func testComplexTranscriptIngestion() throws {
  let transcriptContents = try loadFixtureContents(name: "claude-code-tool-use")
  let transcriptPath = tempDir.appendingPathComponent("test.jsonl")
  try transcriptContents.write(to: transcriptPath, atomically: true, encoding: .utf8)

  // ... run ingestion test
}
```

### Fixture Maintenance

**Best Practices:**
1. **Version fixtures** alongside schema changes
2. **Document fixture contents** in header comments
3. **Keep fixtures minimal** (only necessary data)
4. **Regenerate from production** when format changes

---

## Test Isolation & Cleanup

### Temporary Directory Pattern

All tests use unique temporary directories:

```swift
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
```

**Guarantees:**
- No conflicts between parallel tests
- No leftover state from previous tests
- Automatic cleanup on test completion

### Database Isolation

Tests use in-memory or temp file databases:

```swift
// Option 1: In-memory (fastest)
let pool = try DatabaseQueue()

// Option 2: Temp file (more realistic)
let dbPath = tempDir.appendingPathComponent("test.db")
let pool = try DatabasePool(path: dbPath.path, configuration: config)
```

**Rule:** NEVER use production database path in tests.

### Security-Scoped Resource Cleanup

Tests that use security-scoped bookmarks must clean up:

```swift
@MainActor
func testSecurityScope() throws {
  let scoped = allowSecurityScopedAccess(to: testURL)
  defer {
    scoped.stopAccessingSecurityScopedResource()
  }

  // ... test code
}

override func tearDown() async throws {
  resetSecurityScopedAccess() // Release all scoped resources
  try await super.tearDown()
}
```

**Helper:** `resetSecurityScopedAccess()` in `TestHelpers.swift:49`

### Async Test Cleanup

For tests with async operations, ensure cleanup waits for completion:

```swift
func testAsyncIngestion() async throws {
  let task = Task {
    try await runIngestion()
  }

  defer {
    task.cancel()
  }

  let result = try await task.value
  XCTAssertNotNil(result)
}
```

**Rule:** Use `defer` to ensure cleanup runs even if test throws.

---

## Performance Testing

### XCTest Metrics

XCTest provides performance testing with `measure(metrics:)`:

```swift
func testIngestionPerformance() throws {
  // Create large transcript (10,000 entries)
  let largeTranscript = (1...10_000).map { i in
    """
    {"uuid":"msg-\(i)","type":"user","timestamp":"...","message":{"role":"user","content":"Message \(i)"}}
    """
  }.joined(separator: "\n")

  let transcriptPath = tempDir.appendingPathComponent("large.jsonl")
  try largeTranscript.write(to: transcriptPath, atomically: true, encoding: .utf8)

  // Measure ingestion time
  measure(metrics: [XCTClockMetric()]) {
    _ = try! hooverEngine.hooverTranscript(transcript, fileURL: transcriptPath, progress: NoOpProgressSink())
  }
}
```

**Available Metrics:**
- `XCTClockMetric()` - Wall clock time
- `XCTCPUMetric()` - CPU time
- `XCTMemoryMetric()` - Memory usage
- `XCTStorageMetric()` - Disk I/O

### Performance Baselines

**Recommended Targets:**

| Operation | Target | Measured | Status |
|-----------|--------|----------|--------|
| HooverEngine batch (1000 lines) | <500ms | TBD | ⏳ |
| Database migration (v25→v26) | <2s | TBD | ⏳ |
| LLM summary generation | <1s | TBD | ⏳ |
| Timeline cache lookup | <50ms | TBD | ⏳ |
| Project discovery scan | <3s | TBD | ⏳ |

**Note:** Performance baselines should be established and tracked in CI.

### Profiling Integration

For deeper performance analysis, use Instruments:

```bash
# Build test bundle
xcodebuild test -scheme Contextify -destination 'platform=macOS' -only-testing:ContextifyTests/DatabaseTests/testIngestionPerformance SKIP_INSTALL=NO

# Profile with Instruments
instruments -t "Time Profiler" -D trace.trace /path/to/test/bundle
```

**Instruments Templates:**
- **Time Profiler** - CPU hotspots
- **Allocations** - Memory allocation patterns
- **Leaks** - Memory leak detection
- **System Trace** - File I/O, threading, system calls

---

## CI/CD Integration

### GitHub Actions Workflow

**File:** `.github/workflows/test.yml` (not yet created)

**Recommended Configuration:**

```yaml
name: Tests

on:
  push:
    branches: [ main, claude/* ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-14

    steps:
    - uses: actions/checkout@v4

    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_16.0.app

    - name: Run Tests
      run: |
        xcodebuild test \
          -project Contextify/Contextify.xcodeproj \
          -scheme Contextify \
          -destination 'platform=macOS' \
          -resultBundlePath TestResults.xcresult

    - name: Upload Test Results
      if: failure()
      uses: actions/upload-artifact@v4
      with:
        name: test-results
        path: TestResults.xcresult
```

### Test Parallelization

Enable parallel testing for faster CI:

```bash
xcodebuild test \
  -scheme Contextify \
  -destination 'platform=macOS' \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 4
```

**Note:** Requires test isolation (no shared state).

### Code Coverage

Enable code coverage collection:

```bash
xcodebuild test \
  -scheme Contextify \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult
```

Extract coverage report:

```bash
xcrun xccov view --report TestResults.xcresult > coverage.txt
```

**Target:** 50% code coverage (currently ~15-20%)

### Flaky Test Detection

Track test failures over time to identify flaky tests:

```bash
# Run tests 10 times
for i in {1..10}; do
  xcodebuild test -scheme Contextify -destination 'platform=macOS' | tee "test-run-$i.log"
done

# Analyze failures
grep "Test Case.*failed" test-run-*.log | sort | uniq -c
```

**Rule:** Tests that fail <10% of runs are considered flaky and should be fixed or disabled.

---

## Troubleshooting Tests

### Common Test Failures

#### 1. Database Lock Errors

**Symptom:** `database is locked` error in tests

**Cause:** Multiple test instances accessing same database

**Fix:** Ensure unique temp directory per test:

```swift
tempDir = FileManager.default.temporaryDirectory
  .appendingPathComponent(UUID().uuidString, isDirectory: true) // Must be unique
```

#### 2. Security-Scoped Access Failures

**Symptom:** `Operation not permitted` when accessing files

**Cause:** Missing `startAccessingSecurityScopedResource()` call

**Fix:** Use `allowSecurityScopedAccess()` helper (TestHelpers.swift:32)

#### 3. Async Test Timeouts

**Symptom:** Test hangs indefinitely

**Cause:** Awaiting task that never completes

**Fix:** Add timeout with `waitForCondition()`:

```swift
try await waitForCondition("data loaded", timeout: 2.0) {
  dataReady
}
```

#### 4. Disabled Tests (`skip_` prefix)

**Symptom:** Tests with `skip_` prefix not running

**Cause:** Test disabled due to API changes

**Fix:** Update test for current API or use `throw XCTSkip("reason")`

#### 5. LLM Tests Failing on macOS <26

**Symptom:** `FoundationModels` not available

**Cause:** `@available(macOS 26.0, *)` guard

**Fix:** Tests automatically skip on older OS versions

### Debug Logging in Tests

Enable verbose logging:

```swift
let log = Logger(subsystem: "dev.contextify.tests", category: "integration")
log.debug("Starting ingestion: \(transcriptPath.path)")

let progress = LoggingProgressSink(log: log)
try hooverEngine.hooverTranscript(transcript, fileURL: transcriptPath, progress: progress)
```

View logs during test run:

```bash
xcodebuild test -scheme Contextify 2>&1 | grep "dev.contextify.tests"
```

### Test Isolation Verification

Verify tests don't share state:

```bash
# Run tests in random order
xcodebuild test -scheme Contextify -test-iterations 5 -run-tests-until-failure
```

**Rule:** All tests should pass regardless of execution order.

---

## Summary

### Current Test Coverage

| Category | Files | Status | Coverage |
|----------|-------|--------|----------|
| Database Integration | DatabaseTests.swift | ✅ Active | High |
| Transcript Ingestion | IntegrationTests.swift | ⚠️ Needs Update | Medium |
| LLM Integration | FoundationLLMTests.swift | ✅ Active | High |
| Parser Tests | TranscriptParserTests.swift | ✅ Active | Medium |
| Project Discovery | ProjectDiscoveryTests.swift | ⚠️ Partial | Low |
| UI Tests | ContextifyUITests.swift | ⚠️ Placeholder | Very Low |

### Gaps & Recommendations

**High Priority:**
1. ✅ Update `IntegrationTests.swift` for current HooverEngine API
2. ✅ Add fixture-based transcript ingestion tests
3. ✅ Implement UI integration tests (timeline, project switcher)
4. ✅ Establish performance baselines and CI tracking

**Medium Priority:**
5. ✅ Add end-to-end tests (file drop → timeline display)
6. ✅ Test error handling paths (parse errors, database failures)
7. ✅ Test security-scoped bookmark edge cases
8. ✅ Add mutation testing to verify test quality

**Low Priority:**
9. ✅ Increase code coverage from 15-20% to 50%+
10. ✅ Add property-based testing for parsers (SwiftCheck)
11. ✅ Test concurrent ingestion scenarios
12. ✅ Add accessibility testing for UI components

### Next Steps

1. **Update disabled tests** - Fix `IntegrationTests.swift` for current API
2. **Create fixture library** - Add representative JSONL samples
3. **Implement UI tests** - Cover core user workflows
4. **Set up CI** - Automated test runs on all branches
5. **Track coverage** - Monitor and improve test coverage over time

---

## References

### Internal Documentation

- **`build/docs/architecture/sql-backend.md`** - Database schema and repositories
- **`build/docs/specifications/transcript-formats.md`** - JSONL format specs
- **`build/docs/guides/logging-best-practices.md`** - Test logging conventions
- **`build/docs/testing/first-run-qa-guide.md`** - Manual QA procedures

### Test Files (Code Verification)

- `Contextify/ContextifyTests/DatabaseTests.swift` (835 lines)
- `Contextify/ContextifyTests/IntegrationTests.swift` (268 lines)
- `Contextify/ContextifyTests/FoundationLLMTests.swift` (549 lines)
- `Contextify/ContextifyTests/TestHelpers.swift` (73 lines)

### External Resources

- **XCTest Documentation:** https://developer.apple.com/documentation/xctest
- **Swift Testing Guide:** https://developer.apple.com/swift/blog/?id=67
- **GRDB Testing:** https://github.com/groue/GRDB.swift#testing

---

**Document Status:** ✅ Complete
**Last Code Verification:** 2025-11-17 (Schema v26, DatabaseTests.swift:835, IntegrationTests.swift:268, FoundationLLMTests.swift:549)
**Next Review:** After test coverage improvements or API changes
