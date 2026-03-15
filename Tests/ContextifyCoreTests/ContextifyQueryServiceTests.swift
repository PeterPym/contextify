import XCTest
import GRDB
@testable import ContextifyCore

final class ContextifyQueryServiceTests: XCTestCase {

  func testRecentActivityAndSearch() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-query-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let project = Project(
      id: "p1",
      name: "Test Project",
      rootPath: "/test",
      rootBookmark: nil,
      lastViewedTs: 0,
      hidden: false,
      displayOrder: nil,
      isOrphaned: false,
      orphanedSince: nil,
      createdAt: 0,
      updatedAt: 0
    )

    let transcript = Transcript(
      id: "t1",
      projectId: "p1",
      filePath: "/test/transcript.jsonl",
      provider: "claude.code",
      providerSessionId: nil,
      lastModified: 0,
      fileSize: nil,
      lineCount: 1,
      bookmark: nil,
      lastProcessedLine: 0,
      lastProcessedEntryId: nil,
      parserVersion: 1,
      status: "active",
      ingestState: "complete",
      lastError: nil,
      createdAt: 0,
      updatedAt: 0
    )

    let entry1 = TranscriptEntry(
      id: "e1",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "user",
      timestamp: 100,
      content: "Hello world",
      contentSha256: "sha1",
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
      createdTs: nil,
      createdAt: 100,
      updatedAt: 100,
      isQueued: 0,
        isSidechain: 0
    )

    let entry2 = TranscriptEntry(
      id: "e2",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "assistant",
      timestamp: 200,
      content: "Unread count updated",
      contentSha256: "sha2",
      displayInTimeline: 1,
      parentId: nil,
      gitBranch: nil,
      gitCommit: "abc123def456",
      cwd: "/test",
      prev1Id: nil,
      prev2Id: nil,
      windowSha256: nil,
      embedding: nil,
      embeddingVersion: nil,
      embeddingGeneratedAt: nil,
      createdTs: nil,
      createdAt: 200,
      updatedAt: 200,
      isQueued: 0,
        isSidechain: 0
    )

    let metadata = TranscriptMetadataRecord(
      transcriptId: "t1",
      projectId: "p1",
      title: "Title",
      description: "Desc",
      topics: "[]",
      confidence: 0.9,
      mayContainHallucinations: 0,
      needsReview: 0,
      generatedAt: 300,
      model: "gpt",
      promptVersion: 1,
      generatorVersion: 1,
      transcriptSha256: "sha-t1",
      messageCount: 2,
      strategy: "full",
      llmCalls: 1,
      latencyMs: 10,
      createdAt: 300,
      updatedAt: 300
    )

    try await pool.write { db in
      try project.insert(db)
      try transcript.insert(db)
      try entry1.insert(db)
      try entry2.insert(db)
      try metadata.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    let recent = try service.recentActivity(projectId: "p1", limit: 10)
    XCTAssertEqual(recent.first?.id, "e2")

    let search = try service.ftsSearch(query: "unread count", projectId: "p1", limit: 10)
    XCTAssertEqual(search.first?.id, "e2")
    XCTAssertEqual(search.first?.gitCommit, "abc123def456")
    XCTAssertEqual(search.first?.cwd, "/test")

    let summaries = try service.summaries(projectId: "p1", limit: 10)
    XCTAssertEqual(summaries.first?.transcriptId, "t1")

    let stats = try service.projectStats(projectId: "p1")
    XCTAssertEqual(stats.first?.projectId, "p1")
    XCTAssertEqual(stats.first?.entryCount, 2)
  }

  func testMissingFTSTableReturnsFriendlyError() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-query-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    _ = try DatabaseQueue(path: dbURL.path)

    let service = try ContextifyQueryService(databaseURL: dbURL)

    XCTAssertThrowsError(try service.ftsSearch(query: "hello", projectId: nil, limit: 10)) { error in
      guard case let ContextifyQueryService.QueryError.featureUnavailable(feature, message) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
      XCTAssertEqual(feature, "fts_search")
      XCTAssertTrue(message.contains("FTS search is not available"))
    }

    let info = try service.versionInfo()
    XCTAssertFalse(info.ftsEnabled)
  }

  func testMissingSummariesTableReturnsFriendlyError() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-query-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    _ = try DatabaseQueue(path: dbURL.path)

    let service = try ContextifyQueryService(databaseURL: dbURL)

    XCTAssertThrowsError(try service.summaries(projectId: nil, limit: 10)) { error in
      guard case let ContextifyQueryService.QueryError.featureUnavailable(feature, message) = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
      XCTAssertEqual(feature, "summaries")
      XCTAssertTrue(message.contains("Summaries are not available"))
    }

    let info = try service.versionInfo()
    XCTAssertFalse(info.summariesEnabled)
  }

  /// Regression test: projectStats should not over-count entries due to join multiplication
  /// When a project has multiple transcripts, COUNT(e.id) would be multiplied by transcript count.
  /// Fix: Use COUNT(DISTINCT e.id) to avoid inflation.
  func testProjectStats_multipleTranscripts_noJoinMultiplication() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-projectstats-join-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Setup: 1 project, 2 transcripts, 3 entries total
    // Without DISTINCT, join would produce 2×3=6 entry rows
    try await pool.write { db in
      // Create project
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES ('p1', 'Test Project', '/test', 0, 0, 0)
      """)

      // Create 2 transcripts
      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES
          ('t1', 'p1', '/test/t1.jsonl', '/test/t1.jsonl', 'hash1', 'claude.code',
            0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0),
          ('t2', 'p1', '/test/t2.jsonl', '/test/t2.jsonl', 'hash2', 'claude.code',
            0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """)

      // Create 3 entries (all visible, main-chain)
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES
          ('e1', 't1', 'p1', 'claude.code', 'user', 100, 'msg1', 'sha1', 1, 0, 100, 100, 0),
          ('e2', 't1', 'p1', 'claude.code', 'assistant', 200, 'msg2', 'sha2', 1, 0, 200, 200, 0),
          ('e3', 't2', 'p1', 'claude.code', 'user', 300, 'msg3', 'sha3', 1, 0, 300, 300, 0)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)
    let stats = try service.projectStats(projectId: "p1")

    // Assert: Should have exactly 1 project stat
    XCTAssertEqual(stats.count, 1, "Should return exactly 1 project stat")

    guard let stat = stats.first else {
      XCTFail("No stats returned")
      return
    }

    // Assert: transcriptCount should be 2 (not inflated)
    XCTAssertEqual(stat.transcriptCount, 2, "Should count 2 transcripts")

    // Assert: entryCount should be 3 (not 6 from join multiplication)
    // Without COUNT(DISTINCT e.id), this would be 6 (2 transcripts × 3 entries)
    XCTAssertEqual(stat.entryCount, 3,
      "Entry count should be 3, not 6 (join multiplication bug)")

    // Assert: lastEntryTimestamp should be the max timestamp
    XCTAssertEqual(stat.lastEntryTimestamp, 300,
      "Last entry timestamp should be 300")
  }

  func testImportFromCloudPull_remapsDuplicateRootPathToExistingLocalProject() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-cloud-pull-remap-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES ('local-project', 'Contextify', '/Users/rob/code/projects/contextify', 0, 0, 0)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
    let result = try service.importFromCloudPull(
      projects: [[
        "id": "cloud-project",
        "name": "Contextify",
        "root_path": "/Users/rob/code/projects/contextify",
      ]],
      transcripts: [[
        "id": "cloud-transcript",
        "project_id": "cloud-project",
        "file_path": "/Users/rob/code/projects/contextify/.claude/transcript.jsonl",
        "provider": "claude.code",
        "line_count": 1,
        "created_at": 100,
        "updated_at": 100,
      ]],
      entries: [[
        "id": "cloud-entry",
        "transcript_id": "cloud-transcript",
        "project_id": "cloud-project",
        "provider": "claude.code",
        "kind": "user",
        "timestamp": 100,
        "content": "hello",
        "content_sha256": "sha-cloud-entry",
        "display_in_timeline": true,
        "created_at": 100,
        "updated_at": 100,
      ]],
      summaries: []
    )

    XCTAssertEqual(result.projectsImported, 0)
    XCTAssertEqual(result.transcriptsImported, 1)
    XCTAssertEqual(result.entriesImported, 1)

    try pool.read { db in
      let projectCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects")
      XCTAssertEqual(projectCount, 1)

      let transcriptProjectId = try String.fetchOne(
        db,
        sql: "SELECT project_id FROM transcripts WHERE id = 'cloud-transcript'"
      )
      XCTAssertEqual(transcriptProjectId, "local-project")

      let entryProjectId = try String.fetchOne(
        db,
        sql: "SELECT project_id FROM transcript_entries WHERE id = 'cloud-entry'"
      )
      XCTAssertEqual(entryProjectId, "local-project")
    }
  }

  // MARK: - FTS Search Correctness & Query Plan Guards (ct-178)

  /// Verifies OR queries return correct results through search, searchCount, and searchTermCounts.
  func testSearch_withORQuery_returnsResults() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-fts-perf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES ('p1', 'Test', '/test', 0, 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES ('t1', 'p1', '/test/t1.jsonl', '/test/t1.jsonl', 'h1', 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES
          ('e1', 't1', 'p1', 'claude.code', 'user', 100, 'merge train broke production', 'sha1', 1, 0, 100, 100, 0),
          ('e2', 't1', 'p1', 'claude.code', 'user', 200, 'merge queue is slow today', 'sha2', 1, 0, 200, 200, 0),
          ('e3', 't1', 'p1', 'claude.code', 'user', 300, 'unrelated message about weather', 'sha3', 1, 0, 300, 300, 0)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Test OR query finds both matching entries
    let results = try service.search(
      query: "\"merge train\" OR \"merge queue\"",
      projectIds: ["p1"],
      limit: 10,
      treatAsFTS: true
    )
    XCTAssertEqual(results.count, 2, "OR query should find 2 matching entries")

    // Test searchCount returns correct count
    let count = try service.searchCount(
      query: "\"merge train\" OR \"merge queue\"",
      projectIds: ["p1"],
      treatAsFTS: true
    )
    XCTAssertEqual(count, 2, "searchCount should return 2 for OR query")

    // Test searchTermCounts returns per-term breakdown
    let termCounts = try service.searchTermCounts(
      query: "\"merge train\" OR \"merge queue\"",
      projectIds: ["p1"]
    )
    XCTAssertNotNil(termCounts, "OR query should produce term counts")
    XCTAssertEqual(termCounts?["\"merge train\""], 1)
    XCTAssertEqual(termCounts?["\"merge queue\""], 1)
  }

  /// Regression test: searchCount without filters should use fast FTS-only path (no JOIN)
  func testSearchCount_withoutFilters_usesFTSOnlyPath() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-fts-count-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES ('p1', 'Test', '/test', 0, 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES ('t1', 'p1', '/test/t1.jsonl', '/test/t1.jsonl', 'h1', 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES
          ('e1', 't1', 'p1', 'claude.code', 'user', 100, 'hello world', 'sha1', 1, 0, 100, 100, 0),
          ('e2', 't1', 'p1', 'claude.code', 'user', 200, 'hello again', 'sha2', 1, 0, 200, 200, 0)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Without filters (includeHidden=true, no project/time filter) -> uses FTS-only count fast path
    let countAll = try service.searchCount(
      query: "hello",
      includeHidden: true,
      treatAsFTS: true
    )
    XCTAssertEqual(countAll, 2, "FTS-only count should find both entries")

    // With project filter -> adds WHERE clause, uses JOIN path
    let countFiltered = try service.searchCount(
      query: "hello",
      projectIds: ["p1"],
      treatAsFTS: true
    )
    XCTAssertEqual(countFiltered, 2, "Filtered count with project should find both entries")
  }

  /// Regression test: parseORTerms correctly identifies OR queries
  func testParseORTerms_validAndInvalid() {
    // Valid OR queries
    let simple = ContextifyQueryService.parseORTerms("alpha OR beta")
    XCTAssertEqual(simple, ["alpha", "beta"])

    let quoted = ContextifyQueryService.parseORTerms("\"merge train\" OR \"merge queue\"")
    XCTAssertEqual(quoted, ["\"merge train\"", "\"merge queue\""])

    let multi = ContextifyQueryService.parseORTerms("a OR b OR c OR d")
    XCTAssertEqual(multi, ["a", "b", "c", "d"])

    // Invalid: not an OR query
    let noOR = ContextifyQueryService.parseORTerms("simple query")
    XCTAssertEqual(noOR, [])

    // Invalid: contains AND
    let withAND = ContextifyQueryService.parseORTerms("a AND b OR c")
    XCTAssertEqual(withAND, [])

    // Invalid: contains NOT
    let withNOT = ContextifyQueryService.parseORTerms("a OR NOT b")
    XCTAssertEqual(withNOT, [])

    // Single term returns empty (not an OR query)
    let single = ContextifyQueryService.parseORTerms("single")
    XCTAssertEqual(single, [])
  }

  /// Query plan guard: FTS JOIN must use PK index, not partial index scan.
  /// Before ct-178: SQLite chose idx_entries_cursor (SCAN 483K rows, 64s).
  /// After ct-178: INDEXED BY forces PK lookup (SEARCH by id, 7ms).
  func testFTSSearch_queryPlan_usesPKIndex() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-fts-plan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Insert minimal data so FTS table exists
    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES ('p1', 'Test', '/test', 0, 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES ('t1', 'p1', '/test/t1.jsonl', '/test/t1.jsonl', 'h1', 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES ('e1', 't1', 'p1', 'claude.code', 'user', 100, 'test content', 'sha1', 1, 0, 100, 100, 0)
      """)
    }

    // Verify PK index is detected
    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Run EXPLAIN QUERY PLAN for the search SQL pattern
    try await pool.read { db in
      let sql = """
        EXPLAIN QUERY PLAN
        SELECT e.id, bm25(transcript_entries_fts) AS score
        FROM transcript_entries_fts
        \(service.ftsJoinEntries())
        WHERE transcript_entries_fts MATCH 'test'
          AND e.display_in_timeline = 1
        ORDER BY score ASC
        LIMIT 10
      """
      let rows = try Row.fetchAll(db, sql: sql)
      let plan = rows.map { $0["detail"] as? String ?? "" }.joined(separator: "\n")

      // FTS must be scanned first (not the entries table)
      XCTAssertTrue(
        plan.contains("SCAN transcript_entries_fts"),
        "Query plan must scan FTS table first, got: \(plan)"
      )
      // Entries table must use index lookup, not full scan
      XCTAssertTrue(
        plan.contains("USING INDEX") || plan.contains("SEARCH e"),
        "Query plan must use index for entries lookup, got: \(plan)"
      )
      // Must NOT use the partial index that causes the catastrophic plan
      XCTAssertFalse(
        plan.contains("idx_entries_cursor"),
        "Query plan must NOT use idx_entries_cursor (causes full table scan), got: \(plan)"
      )
    }
  }
}
