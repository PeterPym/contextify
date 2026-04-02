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

  /// Regression test for ct-834: pull must not crash when a transcript already
  /// exists locally with a different ID but the same (project_id, file_path).
  func testImportFromCloudPull_skipsTranscriptWithDuplicateProjectIdAndFilePath() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-cloud-pull-dup-transcript-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Seed a project and transcript as if local ingest created them
    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES ('local-proj', 'TestProject', '/test/cloud-push', 0, 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider,
          last_modified, line_count, last_processed_line, parser_version,
          status, ingest_state, created_at, updated_at)
        VALUES ('local-transcript', 'local-proj',
          '/root/.claude/projects/test-hash/session.jsonl', 'claude.code',
          100, 3, 3, 1, 'active', 'complete', 100, 100)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)

    // Pull delivers the same transcript with a DIFFERENT id but same
    // project_id + file_path. Before ct-834 fix this caused a UNIQUE
    // constraint violation.
    let result = try service.importFromCloudPull(
      projects: [[
        "id": "local-proj",
        "name": "TestProject",
        "root_path": "/test/cloud-push",
      ]],
      transcripts: [[
        "id": "cloud-transcript-different-id",
        "project_id": "local-proj",
        "file_path": "/root/.claude/projects/test-hash/session.jsonl",
        "provider": "claude.code",
        "line_count": 3,
        "created_at": 100,
        "updated_at": 100,
      ]],
      entries: [[
        "id": "cloud-entry-1",
        "transcript_id": "cloud-transcript-different-id",
        "project_id": "local-proj",
        "provider": "claude.code",
        "kind": "user",
        "timestamp": 100,
        "content": "test entry for ct-834",
        "content_sha256": "sha-ct834",
        "display_in_timeline": true,
        "created_at": 100,
        "updated_at": 100,
      ]],
      summaries: []
    )

    // Transcript should be skipped (already exists), not crash
    XCTAssertEqual(result.transcriptsImported, 0)
    // Entry should still import (remapped to the local transcript ID)
    XCTAssertEqual(result.entriesImported, 1)

    try pool.read { db in
      let transcriptCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts")
      XCTAssertEqual(transcriptCount, 1, "Should still have only the original transcript")

      // Entry should reference the LOCAL transcript ID, not the cloud one
      let entryTranscriptId = try String.fetchOne(
        db, sql: "SELECT transcript_id FROM transcript_entries WHERE id = 'cloud-entry-1'")
      XCTAssertEqual(entryTranscriptId, "local-transcript",
        "Entry should be remapped to local transcript ID")
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

  // MARK: - ct-735 regression: resolveProjectByNameWithPath returns rootPath

  func testResolveProjectByNameWithPath_returnsRootPath() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-name-path-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let project = Project(
      id: "proj-abc",
      name: "MyProject",
      rootPath: "/Users/test/code/my-project",
      rootBookmark: nil,
      lastViewedTs: 0,
      hidden: false,
      displayOrder: nil,
      isOrphaned: false,
      orphanedSince: nil,
      createdAt: 0,
      updatedAt: 0
    )
    try pool.write { db in
      try project.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Name-based lookup should return both id and rootPath
    let result = try service.resolveProjectByNameWithPath("MyProject")
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.id, "proj-abc")
    XCTAssertEqual(result?.rootPath, "/Users/test/code/my-project")

    // Case-insensitive match
    let resultLower = try service.resolveProjectByNameWithPath("myproject")
    XCTAssertNotNil(resultLower)
    XCTAssertEqual(resultLower?.id, "proj-abc")

    // Directory name match
    let resultDir = try service.resolveProjectByNameWithPath("my-project")
    XCTAssertNotNil(resultDir)
    XCTAssertEqual(resultDir?.rootPath, "/Users/test/code/my-project")

    // No match
    let resultNone = try service.resolveProjectByNameWithPath("nonexistent")
    XCTAssertNil(resultNone)
  }

  // MARK: - ct-725 regression: fuzzyProjectSuggestions with edit distance

  func testFuzzyProjectSuggestions_editDistance() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-fuzzy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let project = Project(
      id: "proj-ctx",
      name: "contextify",
      rootPath: "/Users/test/code/contextify",
      rootBookmark: nil,
      lastViewedTs: 0,
      hidden: false,
      displayOrder: nil,
      isOrphaned: false,
      orphanedSince: nil,
      createdAt: 0,
      updatedAt: 0
    )
    try pool.write { db in
      try project.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Typo: "contxtify" (missing 'e') should suggest "contextify"
    let result1 = try service.fuzzyProjectSuggestions("contxtify")
    XCTAssertEqual(result1.count, 1)
    XCTAssertEqual(result1.first?.name, "contextify")

    // Typo: "contexify" (missing 't') should suggest "contextify"
    let result2 = try service.fuzzyProjectSuggestions("contexify")
    XCTAssertEqual(result2.count, 1)
    XCTAssertEqual(result2.first?.name, "contextify")

    // Substring match should still work
    let result3 = try service.fuzzyProjectSuggestions("context")
    XCTAssertEqual(result3.count, 1)

    // Completely different name should return empty
    let result4 = try service.fuzzyProjectSuggestions("foobar")
    XCTAssertTrue(result4.isEmpty)

    // Exact match via substring
    let result5 = try service.fuzzyProjectSuggestions("contextify")
    XCTAssertEqual(result5.count, 1)
  }

  // MARK: - ct-795 regression: scan all projects, not just recent 100

  func testFuzzyProjectSuggestions_findsOlderProjectBeyond100() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-fuzzy-101-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Insert 101 projects. The target project has the oldest lastViewedTs.
    try pool.write { db in
      let target = Project(
        id: "proj-target",
        name: "my-special-app",
        rootPath: "/Users/test/code/my-special-app",
        rootBookmark: nil,
        lastViewedTs: 0,
        hidden: false,
        displayOrder: nil,
        isOrphaned: false,
        orphanedSince: nil,
        createdAt: 0,
        updatedAt: 0
      )
      try target.insert(db)

      for i in 1...100 {
        let filler = Project(
          id: "proj-filler-\(i)",
          name: "filler-project-\(i)",
          rootPath: "/Users/test/code/filler-\(i)",
          rootBookmark: nil,
          lastViewedTs: Double(i),
          hidden: false,
          displayOrder: nil,
          isOrphaned: false,
          orphanedSince: nil,
          createdAt: 0,
          updatedAt: 0
        )
        try filler.insert(db)
      }
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Typo of the oldest project should still be found
    let result = try service.fuzzyProjectSuggestions("my-specail-app")
    XCTAssertFalse(result.isEmpty, "Oldest project (beyond top-100) must still be discoverable")
    XCTAssertEqual(result.first?.name, "my-special-app")
  }

  // MARK: - ct-795 regression: short name does not outrank actual match

  func testFuzzyProjectSuggestions_shortNameDoesNotOutrankActualMatch() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-fuzzy-short-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      // Short name that could match via reverse-substring
      let short = Project(
        id: "proj-api",
        name: "api",
        rootPath: "/Users/test/code/api",
        rootBookmark: nil,
        lastViewedTs: 100,
        hidden: false,
        displayOrder: nil,
        isOrphaned: false,
        orphanedSince: nil,
        createdAt: 0,
        updatedAt: 0
      )
      try short.insert(db)

      // Actual match for the query
      let actual = Project(
        id: "proj-my-api-server",
        name: "my-api-server",
        rootPath: "/Users/test/code/my-api-server",
        rootBookmark: nil,
        lastViewedTs: 50,
        hidden: false,
        displayOrder: nil,
        isOrphaned: false,
        orphanedSince: nil,
        createdAt: 0,
        updatedAt: 0
      )
      try actual.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // "my-api-server" should be a substring match (distance 0).
    // "api" should NOT be distance 0 because it's too short for reverse-substring.
    let result = try service.fuzzyProjectSuggestions("my-api-servr")
    XCTAssertFalse(result.isEmpty)
    // The actual match should come first (edit distance 1 for the typo),
    // and "api" should either not appear or not outrank it
    XCTAssertEqual(result.first?.name, "my-api-server")

    // Direct check: "api" should NOT be distance-0 for a long unrelated input
    let reverseCheck = try service.fuzzyProjectSuggestions("contextify-api-service")
    let apiMatch = reverseCheck.first(where: { $0.name == "api" })
    XCTAssertNil(apiMatch, "Short name 'api' must not match unrelated long input via reverse-substring")
  }

  // MARK: - ct-93 regression: status includes newestEntryTimestamp

  func testCounts_includesNewestEntryTimestamp() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-counts-ts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let project = Project(
      id: "proj-ts", name: "test-project",
      rootPath: "/Users/test/code/test-project",
      rootBookmark: nil, lastViewedTs: 0, hidden: false,
      displayOrder: nil, isOrphaned: false, orphanedSince: nil,
      createdAt: 0, updatedAt: 0
    )
    try pool.write { db in
      try project.insert(db)
      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count, last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES ('tx-ts', 'proj-ts', '/tmp/test.jsonl', 'claude.code', 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, content, content_sha256,
          timestamp, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES
          ('e1', 'tx-ts', 'proj-ts', 'claude.code', 'user', 'first entry', 'sha1', 1000, 1, 0, 0, 0, 0),
          ('e2', 'tx-ts', 'proj-ts', 'claude.code', 'assistant', 'second entry', 'sha2', 5000, 1, 0, 0, 0, 0)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)
    let counts = try service.counts()
    XCTAssertEqual(counts.newestEntryTimestamp, 5000)
    XCTAssertEqual(counts.entryCount, 2)
    XCTAssertEqual(counts.deviceCount, 0)  // no source_device_id set
  }

  // MARK: - Review feedback: fuzzy fast-path fallback still finds old projects

  func testFuzzyProjectSuggestions_fallbackToFullScan_beyond500() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-fuzzy-fallback-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      // Target project with oldest lastViewedTs (outside recent-500 window)
      let target = Project(
        id: "proj-old-target", name: "my-rare-project",
        rootPath: "/Users/test/code/my-rare-project",
        rootBookmark: nil, lastViewedTs: 0, hidden: false,
        displayOrder: nil, isOrphaned: false, orphanedSince: nil,
        createdAt: 0, updatedAt: 0
      )
      try target.insert(db)

      for i in 1...500 {
        let filler = Project(
          id: "proj-fill-\(i)", name: "filler-project-\(i)",
          rootPath: "/Users/test/code/filler-\(i)",
          rootBookmark: nil, lastViewedTs: Double(i), hidden: false,
          displayOrder: nil, isOrphaned: false, orphanedSince: nil,
          createdAt: 0, updatedAt: 0
        )
        try filler.insert(db)
      }
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Typo of the oldest project should trigger full-scan fallback
    let result = try service.fuzzyProjectSuggestions("my-rar-project")
    XCTAssertFalse(result.isEmpty, "Fallback to full scan must find project beyond recent-500")
    XCTAssertEqual(result.first?.name, "my-rare-project")
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

  // MARK: - Entry ID Prefix Resolution (ct-794)

  func testResolveEntryId_fullUUID() throws {
    let service = try makeServiceWithEntry(
      entryId: "abcd1234-5678-9abc-def0-123456789abc",
      content: "test content"
    )
    let resolved = try service.resolveEntryId("abcd1234-5678-9abc-def0-123456789abc")
    XCTAssertEqual(resolved, "abcd1234-5678-9abc-def0-123456789abc")
  }

  func testResolveEntryId_8charPrefix() throws {
    let service = try makeServiceWithEntry(
      entryId: "abcd1234-5678-9abc-def0-123456789abc",
      content: "test content"
    )
    let resolved = try service.resolveEntryId("abcd1234")
    XCTAssertEqual(resolved, "abcd1234-5678-9abc-def0-123456789abc")
  }

  func testResolveEntryId_notFound() throws {
    let service = try makeServiceWithEntry(
      entryId: "abcd1234-5678-9abc-def0-123456789abc",
      content: "test content"
    )
    XCTAssertThrowsError(try service.resolveEntryId("zzzzzzzz")) { error in
      guard case ContextifyQueryService.EntryLookupError.notFound = error else {
        XCTFail("Expected notFound, got \(error)")
        return
      }
    }
  }

  func testResolveEntryId_tooShort() throws {
    let service = try makeServiceWithEntry(
      entryId: "abcd1234-5678-9abc-def0-123456789abc",
      content: "test content"
    )
    XCTAssertThrowsError(try service.resolveEntryId("abcd")) { error in
      guard case ContextifyQueryService.EntryLookupError.notFound = error else {
        XCTFail("Expected notFound for short prefix, got \(error)")
        return
      }
    }
  }

  func testResolveEntryId_ambiguous() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-prefix-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, root_path, hidden, created_at, updated_at)
        VALUES ('p1', '/test', 0, 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count, last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES ('t1', 'p1', '/test/t.jsonl', 'claude.code', 0, 1, 0, 1, 'active', 'complete', 0, 0)
      """)
      // Two entries sharing the same 8-char prefix
      try db.execute(sql: """
        INSERT INTO transcript_entries (id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256, display_in_timeline, is_sidechain, created_at, updated_at)
        VALUES ('abcd1234-aaaa-0000-0000-000000000001', 't1', 'p1', 'claude.code', 'user', 100, 'first', 'sha1', 1, 0, 100, 100)
      """)
      try db.execute(sql: """
        INSERT INTO transcript_entries (id, transcript_id, project_id, provider, kind, timestamp, content, content_sha256, display_in_timeline, is_sidechain, created_at, updated_at)
        VALUES ('abcd1234-aaaa-0000-0000-000000000002', 't1', 'p1', 'claude.code', 'user', 200, 'second', 'sha2', 1, 0, 200, 200)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
    XCTAssertThrowsError(try service.resolveEntryId("abcd1234")) { error in
      guard let lookupError = error as? ContextifyQueryService.EntryLookupError,
            case let .ambiguousId(prefix, candidates, totalMatches) = lookupError else {
        XCTFail("Expected ambiguousId, got \(error)")
        return
      }
      XCTAssertEqual(prefix, "abcd1234")
      XCTAssertEqual(candidates.count, 2)
      XCTAssertEqual(totalMatches, 2)
    }
  }

  func testResolveEntryId_ambiguousMoreThanFive_reportsTotalMatches() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-prefix-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, root_path, hidden, created_at, updated_at)
        VALUES ('p1', '/test', 0, 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count, last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES ('t1', 'p1', '/test/t.jsonl', 'claude.code', 0, 1, 0, 1, 'active', 'complete', 0, 0)
      """)
      // 6 entries sharing the same 8-char prefix
      for i in 1...6 {
        try db.execute(
          sql: """
            INSERT INTO transcript_entries (
              id, transcript_id, project_id, provider, kind, timestamp,
              content, content_sha256, display_in_timeline, is_sidechain, created_at, updated_at
            )
            VALUES (?, 't1', 'p1', 'claude.code', 'user', ?, 'entry', ?, 1, 0, 100, 100)
          """,
          arguments: ["aaaa1234-bbbb-0000-0000-00000000000\(i)", i * 100, "sha\(i)"]
        )
      }
    }

    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
    XCTAssertThrowsError(try service.resolveEntryId("aaaa1234")) { error in
      guard let lookupError = error as? ContextifyQueryService.EntryLookupError,
            case let .ambiguousId(prefix, candidates, totalMatches) = lookupError else {
        XCTFail("Expected ambiguousId, got \(error)")
        return
      }
      XCTAssertEqual(prefix, "aaaa1234")
      XCTAssertEqual(candidates.count, 5)
      XCTAssertEqual(totalMatches, 6)
    }
  }

  func testResolveEntryId_prefixWithUnderscore_isEscaped() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-prefix-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, root_path, hidden, created_at, updated_at)
        VALUES ('p1', '/test', 0, 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count, last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES ('t1', 'p1', '/test/t.jsonl', 'claude.code', 0, 1, 0, 1, 'active', 'complete', 0, 0)
      """)
      // Entry with underscore in ID
      try db.execute(
        sql: """
          INSERT INTO transcript_entries (
            id, transcript_id, project_id, provider, kind, timestamp,
            content, content_sha256, display_in_timeline, is_sidechain, created_at, updated_at
          )
          VALUES (?, 't1', 'p1', 'claude.code', 'user', 100, 'target', 'sha1', 1, 0, 100, 100)
        """,
        arguments: ["ab_d1234-5678-9abc-def0-123456789abc"]
      )
      // Entry that would match if _ were treated as wildcard (abXd1234...)
      try db.execute(
        sql: """
          INSERT INTO transcript_entries (
            id, transcript_id, project_id, provider, kind, timestamp,
            content, content_sha256, display_in_timeline, is_sidechain, created_at, updated_at
          )
          VALUES (?, 't1', 'p1', 'claude.code', 'user', 200, 'decoy', 'sha2', 1, 0, 200, 200)
        """,
        arguments: ["abzd1234-5678-9abc-def0-123456789abc"]
      )
    }

    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
    // Searching for "ab_d1234" should find exactly 1 match (the underscore entry),
    // not 2 (which would happen if _ were treated as LIKE wildcard)
    let resolved = try service.resolveEntryId("ab_d1234")
    XCTAssertEqual(resolved, "ab_d1234-5678-9abc-def0-123456789abc")
  }

  func testResolveEntryId_contentWithQuotes() throws {
    let service = try makeServiceWithEntry(
      entryId: "abcd1234-5678-9abc-def0-123456789abc",
      content: "Bob's test with \"quotes\""
    )
    let result = try service.entry(entryId: "abcd1234")
    XCTAssertEqual(result.entry.id, "abcd1234-5678-9abc-def0-123456789abc")
  }

  func testEntryCommand_resolvesPrefix() throws {
    let service = try makeServiceWithEntry(
      entryId: "abcd1234-5678-9abc-def0-123456789abc",
      content: "test content"
    )
    let result = try service.entry(entryId: "abcd1234")
    XCTAssertEqual(result.entry.id, "abcd1234-5678-9abc-def0-123456789abc")
  }

  func testContextCommand_resolvesPrefix() throws {
    let service = try makeServiceWithEntry(
      entryId: "abcd1234-5678-9abc-def0-123456789abc",
      content: "test content"
    )
    let result = try service.context(entryId: "abcd1234")
    XCTAssertEqual(result.anchor.id, "abcd1234-5678-9abc-def0-123456789abc")
  }

  // MARK: - Test Helpers

  private func makeServiceWithEntry(
    entryId: String,
    content: String
  ) throws -> ContextifyQueryService {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-prefix-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, root_path, hidden, created_at, updated_at)
        VALUES ('p1', '/test', 0, 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count, last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES ('t1', 'p1', '/test/t.jsonl', 'claude.code', 0, 1, 0, 1, 'active', 'complete', 0, 0)
      """)
      try db.execute(
        sql: """
          INSERT INTO transcript_entries (
            id, transcript_id, project_id, provider, kind, timestamp,
            content, content_sha256, display_in_timeline, is_sidechain, created_at, updated_at
          )
          VALUES (?, 't1', 'p1', 'claude.code', 'user', 100, ?, 'sha1', 1, 0, 100, 100)
        """,
        arguments: [entryId, content]
      )
    }

    return try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
  }

  // MARK: - ct-796: CLI contract tests (databaseSummary shape, non-path resolution)

  /// Verify counts() returns all fields needed for databaseSummary metadata.
  /// The CLI wraps this as the "databaseSummary" key in search JSON responses.
  func testCounts_returnsDatabaseSummaryFields() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-dbsummary-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES ('p1', 'alpha', '/test/alpha', 0, 0, 100),
               ('p2', 'beta', '/test/beta', 0, 0, 50)
      """)
      try db.execute(sql: """
        INSERT INTO transcripts (id, project_id, file_path, provider, last_modified, line_count, last_processed_line, parser_version, status, ingest_state, created_at, updated_at)
        VALUES ('t1', 'p1', '/tmp/t1.jsonl', 'claude.code', 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """)
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, content, content_sha256,
          timestamp, display_in_timeline, is_sidechain, created_at, updated_at, is_queued,
          source_device_id
        ) VALUES
          ('e1', 't1', 'p1', 'claude.code', 'user', 'hello', 'sha1', 1000, 1, 0, 0, 0, 0, 'device-a'),
          ('e2', 't1', 'p1', 'claude.code', 'assistant', 'world', 'sha2', 2000, 1, 0, 0, 0, 0, 'device-b')
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)
    let counts = try service.counts()

    // All fields that back databaseSummary must be present and correct
    XCTAssertEqual(counts.entryCount, 2)
    XCTAssertEqual(counts.projectCount, 2)
    XCTAssertEqual(counts.deviceCount, 2)
    XCTAssertEqual(counts.newestEntryTimestamp, 2000)
  }

  /// Verify that databaseSummary counts are global, not filtered by project.
  /// This was the P1 issue from the ChatGPT review: scopeSummary reported global
  /// counts while claiming to describe the filtered search scope.
  func testCounts_areGlobal_notFilteredByProject() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-global-counts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES ('p1', 'alpha', '/test/alpha', 0, 0, 100),
               ('p2', 'beta', '/test/beta', 0, 0, 50),
               ('p3', 'gamma', '/test/gamma', 0, 0, 25)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // counts() always returns global totals regardless of any filtering
    let counts = try service.counts()
    XCTAssertEqual(counts.projectCount, 3, "counts() must return ALL projects, not a filtered subset")
  }

  /// Verify resolveProjectByName returns nil for an unknown name,
  /// enabling the caller to terminate without filesystem fallback.
  func testResolveProjectByName_unknownName_returnsNil() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-resolve-nil-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    try pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES ('p1', 'real-project', '/test/real-project', 0, 0, 100)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Name lookup for unknown project returns nil (not an error, not a path)
    let result = try service.resolveProjectByName("totally-unknown-project")
    XCTAssertNil(result, "Unknown project name must return nil, not fall through to path resolution")

    // Fuzzy suggestions for a completely unrelated name should be empty
    let fuzzy = try service.fuzzyProjectSuggestions("zzzzz-no-match")
    XCTAssertTrue(fuzzy.isEmpty, "Completely unrelated name must produce no fuzzy suggestions")
  }

  // MARK: - Transcript Tag Tests

  /// Tags can be added, listed, and removed via the query service.
  func testTagOperations_addListRemove() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-tags-\(UUID().uuidString)")
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
    }

    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)

    // Initially no tags
    let initial = try service.getTags(transcriptId: "t1")
    XCTAssertTrue(initial.isEmpty)

    // Add a tag
    try service.addTag(transcriptId: "t1", tag: "benchmark")
    let afterAdd = try service.getTags(transcriptId: "t1")
    XCTAssertEqual(afterAdd, ["benchmark"])

    // Add same tag again (idempotent)
    try service.addTag(transcriptId: "t1", tag: "benchmark")
    XCTAssertEqual(try service.getTags(transcriptId: "t1"), ["benchmark"])

    // Add second tag
    try service.addTag(transcriptId: "t1", tag: "evaluation")
    XCTAssertEqual(try service.getTags(transcriptId: "t1"), ["benchmark", "evaluation"])

    // Remove a tag
    try service.removeTag(transcriptId: "t1", tag: "benchmark")
    XCTAssertEqual(try service.getTags(transcriptId: "t1"), ["evaluation"])

    // Remove last tag
    try service.removeTag(transcriptId: "t1", tag: "evaluation")
    XCTAssertTrue(try service.getTags(transcriptId: "t1").isEmpty)
  }

  /// Search with --exclude-tags filters out entries from tagged transcripts.
  func testSearch_excludeTags_filtersTaggedTranscripts() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-excl-tags-\(UUID().uuidString)")
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
      // Two transcripts: one will be tagged, one won't
      for (tid, path) in [("t-real", "/test/real.jsonl"), ("t-bench", "/test/bench.jsonl")] {
        try db.execute(sql: """
          INSERT INTO transcripts (
            id, project_id, file_path, normalized_path, path_hash, provider,
            last_modified, file_size, content_length, mtime_ms,
            line_count, last_processed_line, parser_version, status, ingest_state,
            created_at, updated_at
          ) VALUES (?, 'p1', ?, ?, ?, 'claude.code', 0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
        """, arguments: [tid, path, path, "h-\(tid)"])
      }
      // Both have entries matching "deploy pipeline"
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES
          ('e-real', 't-real', 'p1', 'claude.code', 'user', 100, 'fix the deploy pipeline', 'sha-r', 1, 0, 100, 100, 0),
          ('e-bench', 't-bench', 'p1', 'claude.code', 'user', 200, 'search for deploy pipeline issues', 'sha-b', 1, 0, 200, 200, 0)
      """)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)

    // Without excludeTags, both results appear
    let allResults = try service.search(query: "deploy pipeline", limit: 10)
    XCTAssertEqual(allResults.count, 2, "Without tag filter, both entries match")

    // Tag the benchmark transcript
    try service.addTag(transcriptId: "t-bench", tag: "benchmark")

    // With excludeTags=["benchmark"], only the real entry appears
    let filtered = try service.search(query: "deploy pipeline", limit: 10, excludeTags: ["benchmark"])
    XCTAssertEqual(filtered.count, 1, "With --exclude-tags benchmark, only non-tagged entry matches")
    XCTAssertEqual(filtered.first?.id, "e-real")

    // searchCount also respects the filter
    let filteredCount = try service.searchCount(query: "deploy pipeline", excludeTags: ["benchmark"])
    XCTAssertEqual(filteredCount, 1)

    // Untagged transcript is never affected
    let noFilter = try service.search(query: "deploy pipeline", limit: 10, excludeTags: ["nonexistent"])
    XCTAssertEqual(noFilter.count, 2, "Excluding a tag that no transcript has should return all results")
  }

  /// Tags are normalized to lowercase.
  func testTags_normalizedToLowercase() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-tag-norm-\(UUID().uuidString)")
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
    }

    let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)

    try service.addTag(transcriptId: "t1", tag: "Benchmark")
    let tags = try service.getTags(transcriptId: "t1")
    XCTAssertEqual(tags, ["benchmark"], "Tags should be normalized to lowercase")

    // Adding same tag with different case should be idempotent
    try service.addTag(transcriptId: "t1", tag: "BENCHMARK")
    XCTAssertEqual(try service.getTags(transcriptId: "t1"), ["benchmark"])
  }
}
