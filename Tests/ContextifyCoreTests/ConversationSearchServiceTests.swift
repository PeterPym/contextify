import XCTest
import GRDB
@testable import ContextifyCore

final class ConversationSearchServiceTests: XCTestCase {

  // MARK: - Query Builder Tests

  func testBuildSafeFTSQuery_simpleTokens() {
    let result = ConversationSearchService.buildSafeFTSQuery("unread count")
    XCTAssertEqual(result, "\"unread\" AND \"count\"")
  }

  func testBuildSafeFTSQuery_singleToken() {
    let result = ConversationSearchService.buildSafeFTSQuery("search")
    XCTAssertEqual(result, "\"search\"")
  }

  func testBuildSafeFTSQuery_phraseSearch() {
    let result = ConversationSearchService.buildSafeFTSQuery("\"exact phrase\"")
    XCTAssertEqual(result, "\"exact phrase\"")
  }

  func testBuildSafeFTSQuery_phraseSearchStripsInternalQuotes() {
    let result = ConversationSearchService.buildSafeFTSQuery("\"exact \"quoted\" phrase\"")
    XCTAssertEqual(result, "\"exact quoted phrase\"")
  }

  func testBuildSafeFTSQuery_specialCharacters() {
    let result = ConversationSearchService.buildSafeFTSQuery("foo* (bar) \"baz\"")
    XCTAssertEqual(result, "\"foo\" AND \"bar\" AND \"baz\"")
  }

  func testBuildSafeFTSQuery_emptyString() {
    let result = ConversationSearchService.buildSafeFTSQuery("")
    XCTAssertEqual(result, "")
  }

  func testBuildSafeFTSQuery_whitespaceOnly() {
    let result = ConversationSearchService.buildSafeFTSQuery("   ")
    XCTAssertEqual(result, "")
  }

  func testBuildSafeFTSQuery_leadingTrailingWhitespace() {
    let result = ConversationSearchService.buildSafeFTSQuery("  hello world  ")
    XCTAssertEqual(result, "\"hello\" AND \"world\"")
  }

  func testBuildSafeFTSQuery_multipleSpaces() {
    let result = ConversationSearchService.buildSafeFTSQuery("hello   world")
    XCTAssertEqual(result, "\"hello\" AND \"world\"")
  }

  func testBuildSafeFTSQuery_codeIdentifier() {
    // Should treat code identifiers as single tokens
    let result = ConversationSearchService.buildSafeFTSQuery("UNREAD_COUNT_UPDATED")
    XCTAssertEqual(result, "\"UNREAD_COUNT_UPDATED\"")
  }

  func testBuildSafeFTSQuery_mixedCasePreserved() {
    let result = ConversationSearchService.buildSafeFTSQuery("UnreadCount")
    XCTAssertEqual(result, "\"UnreadCount\"")
  }

  func testBuildSafeFTSQuery_parenthesesRemoved() {
    let result = ConversationSearchService.buildSafeFTSQuery("function()")
    XCTAssertEqual(result, "\"function\"")
  }

  func testBuildSafeFTSQuery_asterisksRemoved() {
    let result = ConversationSearchService.buildSafeFTSQuery("test*")
    XCTAssertEqual(result, "\"test\"")
  }

  // MARK: - Search Scope Tests

  func testSearchScope_project() {
    let scope = ConversationSearchScope.project("project-123")
    XCTAssertEqual(scope, ConversationSearchScope.project("project-123"))
  }

  func testSearchScope_allProjects() {
    let scope = ConversationSearchScope.allProjects
    XCTAssertEqual(scope, ConversationSearchScope.allProjects)
  }

  func testSearchScope_multipleProjects() {
    let scope = ConversationSearchScope.projects(["p1", "p2", "p3"])
    XCTAssertEqual(scope, ConversationSearchScope.projects(["p1", "p2", "p3"]))
  }

  // MARK: - Search Request Tests

  func testSearchRequest_defaultValues() {
    let request = ConversationSearchRequest(query: "test", scope: .allProjects)
    XCTAssertEqual(request.query, "test")
    XCTAssertEqual(request.scope, .allProjects)
    XCTAssertEqual(request.limit, 50)
    XCTAssertEqual(request.offset, 0)
  }

  func testSearchRequest_limitCapped() {
    let request = ConversationSearchRequest(query: "test", scope: .allProjects, limit: 100)
    XCTAssertEqual(request.limit, 50)  // Should be capped at 50
  }

  func testSearchRequest_offsetCapped() {
    let request = ConversationSearchRequest(query: "test", scope: .allProjects, offset: 10000)
    XCTAssertEqual(request.offset, 5000)  // Should be capped at 5000
  }

  func testSearchRequest_validValues() {
    let request = ConversationSearchRequest(query: "test", scope: .project("p1"), limit: 25, offset: 100)
    XCTAssertEqual(request.query, "test")
    XCTAssertEqual(request.scope, .project("p1"))
    XCTAssertEqual(request.limit, 25)
    XCTAssertEqual(request.offset, 100)
  }

  // MARK: - Search Result Tests

  func testSearchResult_cappedResults() {
    let result = ConversationSearchResult(
      hits: [],
      totalCount: 5000,
      cappedResults: true,
      query: "test",
      scope: .allProjects
    )
    XCTAssertTrue(result.cappedResults)
    XCTAssertEqual(result.totalCount, 5000)
  }

  func testSearchResult_uncappedResults() {
    let result = ConversationSearchResult(
      hits: [],
      totalCount: 100,
      cappedResults: false,
      query: "test",
      scope: .project("p1")
    )
    XCTAssertFalse(result.cappedResults)
    XCTAssertEqual(result.totalCount, 100)
  }

  // MARK: - Search Hit Tests

  func testSearchHit_identifiable() {
    let hit = ConversationSearchHit(
      id: "entry-123",
      projectId: "project-456",
      projectName: "Test Project",
      provider: "claude.code",
      role: "user",
      content: "Hello world",
      createdAt: Date(),
      rank: -0.5,
      snippet: "Hello <mark>world</mark>"
    )

    XCTAssertEqual(hit.id, "entry-123")
    XCTAssertEqual(hit.projectId, "project-456")
    XCTAssertEqual(hit.projectName, "Test Project")
    XCTAssertEqual(hit.provider, "claude.code")
    XCTAssertEqual(hit.role, "user")
  }

  func testSearchHit_equatable() {
    let date = Date()
    let hit1 = ConversationSearchHit(
      id: "entry-123",
      projectId: "p1",
      projectName: "Project",
      provider: "claude.code",
      role: "user",
      content: "content",
      createdAt: date,
      rank: -0.5,
      snippet: "snippet"
    )

    let hit2 = ConversationSearchHit(
      id: "entry-123",
      projectId: "p1",
      projectName: "Project",
      provider: "claude.code",
      role: "user",
      content: "content",
      createdAt: date,
      rank: -0.5,
      snippet: "snippet"
    )

    XCTAssertEqual(hit1, hit2)
  }

  // MARK: - isSelectable Tests (UI Hidden-Hit Policy)

  func testSearchHit_isSelectable_visibleMainChain() {
    let hit = ConversationSearchHit(
      id: "e1",
      projectId: "p1",
      projectName: "Project",
      provider: "claude.code",
      role: "user",
      content: "visible main-chain",
      createdAt: Date(),
      rank: -0.5,
      snippet: "snippet",
      displayInTimeline: true,
      isSidechain: false
    )
    XCTAssertTrue(hit.isSelectable, "Visible main-chain hits should be selectable")
  }

  func testSearchHit_isSelectable_visibleSidechain() {
    let hit = ConversationSearchHit(
      id: "e1",
      projectId: "p1",
      projectName: "Project",
      provider: "claude.code",
      role: "assistant",
      content: "sidechain entry",
      createdAt: Date(),
      rank: -0.5,
      snippet: "snippet",
      displayInTimeline: true,
      isSidechain: true
    )
    XCTAssertTrue(hit.isSelectable, "Visible sidechain hits should be selectable")
  }

  func testSearchHit_isSelectable_hiddenMainChain() {
    let hit = ConversationSearchHit(
      id: "e1",
      projectId: "p1",
      projectName: "Project",
      provider: "claude.code",
      role: "system",
      content: "hidden entry",
      createdAt: Date(),
      rank: -0.5,
      snippet: "snippet",
      displayInTimeline: false,
      isSidechain: false
    )
    XCTAssertFalse(hit.isSelectable, "Hidden main-chain hits should NOT be selectable")
  }

  func testSearchHit_isSelectable_hiddenSidechain() {
    let hit = ConversationSearchHit(
      id: "e1",
      projectId: "p1",
      projectName: "Project",
      provider: "claude.code",
      role: "system",
      content: "hidden sidechain",
      createdAt: Date(),
      rank: -0.5,
      snippet: "snippet",
      displayInTimeline: false,
      isSidechain: true
    )
    XCTAssertFalse(hit.isSelectable, "Hidden sidechain hits should NOT be selectable")
  }

  // MARK: - getContext Integration Tests

  /// Test that getContext returns the hit entry itself in the context
  func testGetContext_includesHitEntry() async throws {
    // Setup: Create test database with entries
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Insert test project and transcript
    let projectId = "test-project-1"
    let transcriptId = "transcript-1"
    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES (?, 'Test Project', '/test', 0, 0, 0)
      """, arguments: [projectId])

      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES (?, ?, '/test/file.jsonl', '/test/file.jsonl', 'hash123', 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """, arguments: [transcriptId, projectId])

      // Insert 25 entries with sequential timestamps
      let baseTimestamp = 1000
      for i in 1...25 {
        let entryId = "entry-\(i)"
        let ts = baseTimestamp + i
        try db.execute(sql: """
          INSERT INTO transcript_entries (
            id, transcript_id, project_id, provider, kind, timestamp, content,
            content_sha256, display_in_timeline, created_at, updated_at, is_queued
          ) VALUES (?, ?, ?, 'claude.code', 'user', ?, 'Message \(i)',
            'sha-\(i)', 1, ?, ?, 0)
        """, arguments: [entryId, transcriptId, projectId, ts, ts, ts])
      }
    }

    // Test: Get context for entry 15 (middle entry)
    let service = ConversationSearchService(dbManager: dbManager)
    let hitEntryId = "entry-15"
    let context = try await service.getContext(entryId: hitEntryId, before: 10, after: 10)

    // Assert: The hit entry MUST be in the context
    let contextIds = context.map { $0.id }
    XCTAssertTrue(contextIds.contains(hitEntryId), "Context must include the hit entry itself")

    // Also verify we got reasonable context around it
    XCTAssertGreaterThan(context.count, 1, "Context should include surrounding entries")
  }

  /// Test that getContext handles timestamp collisions correctly
  /// When multiple entries have the same timestamp, the hit must still be included
  func testGetContext_timestampCollision_includesHit() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Insert test project and transcript
    let projectId = "test-project-collision"
    let transcriptId = "transcript-1"
    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES (?, 'Test Project', '/test', 0, 0, 0)
      """, arguments: [projectId])

      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES (?, ?, '/test/file.jsonl', '/test/file.jsonl', 'hash456', 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """, arguments: [transcriptId, projectId])

      // Insert 15 entries ALL with the same timestamp (worst case collision)
      let sameTimestamp = 5000
      for i in 1...15 {
        let entryId = "collision-entry-\(i)"
        try db.execute(sql: """
          INSERT INTO transcript_entries (
            id, transcript_id, project_id, provider, kind, timestamp, content,
            content_sha256, display_in_timeline, created_at, updated_at, is_queued
          ) VALUES (?, ?, ?, 'claude.code', 'user', ?, 'Collision message \(i)',
            'sha-\(i)', 1, ?, ?, 0)
        """, arguments: [entryId, transcriptId, projectId, sameTimestamp, sameTimestamp, sameTimestamp])
      }
    }

    // Test: Get context for entry in the middle (entry 8)
    let service = ConversationSearchService(dbManager: dbManager)
    let hitEntryId = "collision-entry-8"
    let context = try await service.getContext(entryId: hitEntryId, before: 10, after: 10)

    // Assert: The hit entry MUST be in the context even with timestamp collision
    let contextIds = context.map { $0.id }
    XCTAssertTrue(contextIds.contains(hitEntryId),
      "Context must include hit entry even when multiple entries share the same timestamp")
  }

  /// Test that getContext handles timestamp collision with many entries
  /// This tests the edge case where the hit might be excluded due to LIMIT
  func testGetContext_timestampCollision_manyEntries() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Insert test project and transcript
    let projectId = "test-project-many"
    let transcriptId = "transcript-1"
    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES (?, 'Test Project', '/test', 0, 0, 0)
      """, arguments: [projectId])

      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES (?, ?, '/test/file.jsonl', '/test/file.jsonl', 'hashmany', 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """, arguments: [transcriptId, projectId])

      // Insert 30 entries ALL with the same timestamp
      // With before=10, the query gets 11 entries max from the "before" side
      // If the hit is not in those 11 due to non-deterministic ordering, it fails
      let sameTimestamp = 5000
      for i in 1...30 {
        // Use UUIDs to simulate real-world conditions where ID ordering is random
        let entryId = "entry-\(String(format: "%02d", i))-\(UUID().uuidString)"
        try db.execute(sql: """
          INSERT INTO transcript_entries (
            id, transcript_id, project_id, provider, kind, timestamp, content,
            content_sha256, display_in_timeline, created_at, updated_at, is_queued
          ) VALUES (?, ?, ?, 'claude.code', 'user', ?, 'Message \(i)',
            'sha-\(i)', 1, ?, ?, 0)
        """, arguments: [entryId, transcriptId, projectId, sameTimestamp, sameTimestamp, sameTimestamp])
      }
    }

    // Get the 15th entry ID (middle of the pack)
    let hitEntryId = try await pool.read { db -> String in
      let rows = try Row.fetchAll(db, sql: """
        SELECT id FROM transcript_entries WHERE project_id = ? ORDER BY rowid LIMIT 1 OFFSET 14
      """, arguments: [projectId])
      return rows.first!["id"]
    }

    // Test: Get context for that entry
    let service = ConversationSearchService(dbManager: dbManager)
    let context = try await service.getContext(entryId: hitEntryId, before: 10, after: 10)

    // Assert: The hit entry MUST be in the context
    let contextIds = context.map { $0.id }
    XCTAssertTrue(contextIds.contains(hitEntryId),
      "Context must include hit entry even with 30 entries sharing the same timestamp. Hit: \(hitEntryId), got \(contextIds.count) entries")
  }

  /// Test that getContext works for a single entry project
  func testGetContext_singleEntry() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Insert test project and transcript
    let projectId = "test-project-single"
    let transcriptId = "transcript-1"
    let entryId = "single-entry"
    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES (?, 'Test Project', '/test', 0, 0, 0)
      """, arguments: [projectId])

      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES (?, ?, '/test/file.jsonl', '/test/file.jsonl', 'hash789', 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """, arguments: [transcriptId, projectId])

      // Insert single entry
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, created_at, updated_at, is_queued
        ) VALUES (?, ?, ?, 'claude.code', 'user', 1000, 'Only message',
          'sha-1', 1, 1000, 1000, 0)
      """, arguments: [entryId, transcriptId, projectId])
    }

    // Test: Get context for the only entry
    let service = ConversationSearchService(dbManager: dbManager)
    let context = try await service.getContext(entryId: entryId, before: 10, after: 10)

    // Assert: Should return exactly the one entry
    XCTAssertEqual(context.count, 1, "Single entry project should return exactly 1 entry")
    XCTAssertEqual(context.first?.id, entryId, "The single entry should be the hit")
  }

  // MARK: - Search Result Visibility Tests (Phase 3 Entry Filter Architecture)

  /// Test that search() returns hidden hits with displayInTimeline=false
  func testSearch_hiddenEntries_haveFalseDisplayInTimeline() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-search-hidden-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Use UUID everywhere to ensure complete isolation
    let testUUID = UUID().uuidString
    let projectId = "hidden-test-\(testUUID)"
    let transcriptId = "transcript-\(testUUID)"
    let visibleEntryId = "visible-\(testUUID)"
    let hiddenEntryId = "hidden-\(testUUID)"
    let searchTerm = "hiddenSearchTestXYZ\(testUUID.prefix(8))"

    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES (?, 'Test Project', '/test', 0, 0, 0)
      """, arguments: [projectId])

      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES (?, ?, '/test/file.jsonl', '/test/file.jsonl', ?, 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """, arguments: [transcriptId, projectId, "hash-\(testUUID)"])

      // Insert visible entry
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES (?, ?, ?, 'claude.code', 'user', 1000,
          '\(searchTerm) visible content', 'sha-v', 1, 0, 1000, 1000, 0)
      """, arguments: [visibleEntryId, transcriptId, projectId])

      // Insert hidden entry (display_in_timeline = 0)
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES (?, ?, ?, 'claude.code', 'system', 2000,
          '\(searchTerm) hidden content', 'sha-h', 0, 0, 2000, 2000, 0)
      """, arguments: [hiddenEntryId, transcriptId, projectId])

      // Insert FTS entries for both (required for FTS search)
      try db.execute(sql: """
        INSERT INTO transcript_entries_fts (entry_id, project_id, role, content, created_at)
        VALUES (?, ?, 'user', '\(searchTerm) visible content', 1000)
      """, arguments: [visibleEntryId, projectId])
      try db.execute(sql: """
        INSERT INTO transcript_entries_fts (entry_id, project_id, role, content, created_at)
        VALUES (?, ?, 'system', '\(searchTerm) hidden content', 2000)
      """, arguments: [hiddenEntryId, projectId])
    }

    // Test: Search should find both entries
    let service = ConversationSearchService(dbManager: dbManager)
    let request = ConversationSearchRequest(query: searchTerm, scope: .project(projectId))
    let result = try await service.search(request)

    // Assert: At least both entries should be found
    XCTAssertGreaterThanOrEqual(result.hits.count, 2, "Search should find at least both entries")

    // Assert: Visible entry has displayInTimeline=true
    let visibleHit = result.hits.first { $0.id == visibleEntryId }
    XCTAssertNotNil(visibleHit, "Should find visible entry with ID \(visibleEntryId)")
    XCTAssertTrue(visibleHit!.displayInTimeline, "Visible entry should have displayInTimeline=true")
    XCTAssertTrue(visibleHit!.isSelectable, "Visible entry should be selectable")

    // Assert: Hidden entry has displayInTimeline=false
    let hiddenHit = result.hits.first { $0.id == hiddenEntryId }
    XCTAssertNotNil(hiddenHit, "Should find hidden entry with ID \(hiddenEntryId)")
    XCTAssertFalse(hiddenHit!.displayInTimeline, "Hidden entry should have displayInTimeline=false")
    XCTAssertFalse(hiddenHit!.isSelectable, "Hidden entry should NOT be selectable")
  }

  /// Test that search() returns sidechain hits with isSidechain=true
  func testSearch_sidechainEntries_haveTrueIsSidechain() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-search-sidechain-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    // Use UUID everywhere to ensure complete isolation
    let testUUID = UUID().uuidString
    let projectId = "sidechain-test-\(testUUID)"
    let transcriptId = "transcript-\(testUUID)"
    let mainEntryId = "main-\(testUUID)"
    let sidechainEntryId = "sidechain-\(testUUID)"
    let searchTerm = "sidechainSearchTestXYZ\(testUUID.prefix(8))"

    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES (?, 'Test Project', '/test', 0, 0, 0)
      """, arguments: [projectId])

      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES (?, ?, '/test/file.jsonl', '/test/file.jsonl', ?, 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """, arguments: [transcriptId, projectId, "hash-\(testUUID)"])

      // Insert main-chain entry
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES (?, ?, ?, 'claude.code', 'user', 1000,
          '\(searchTerm) main chain content', 'sha-m', 1, 0, 1000, 1000, 0)
      """, arguments: [mainEntryId, transcriptId, projectId])

      // Insert sidechain entry (is_sidechain = 1)
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES (?, ?, ?, 'claude.code', 'assistant', 2000,
          '\(searchTerm) sidechain content', 'sha-s', 1, 1, 2000, 2000, 0)
      """, arguments: [sidechainEntryId, transcriptId, projectId])

      // Insert FTS entries for both
      try db.execute(sql: """
        INSERT INTO transcript_entries_fts (entry_id, project_id, role, content, created_at)
        VALUES (?, ?, 'user', '\(searchTerm) main chain content', 1000)
      """, arguments: [mainEntryId, projectId])
      try db.execute(sql: """
        INSERT INTO transcript_entries_fts (entry_id, project_id, role, content, created_at)
        VALUES (?, ?, 'assistant', '\(searchTerm) sidechain content', 2000)
      """, arguments: [sidechainEntryId, projectId])
    }

    // Test: Search should find both entries
    let service = ConversationSearchService(dbManager: dbManager)
    let request = ConversationSearchRequest(query: searchTerm, scope: .project(projectId))
    let result = try await service.search(request)

    // Assert: At least both entries should be found
    XCTAssertGreaterThanOrEqual(result.hits.count, 2, "Search should find at least both entries")

    // Assert: Main-chain entry has isSidechain=false
    let mainHit = result.hits.first { $0.id == mainEntryId }
    XCTAssertNotNil(mainHit, "Should find main-chain entry with ID \(mainEntryId)")
    XCTAssertFalse(mainHit!.isSidechain, "Main-chain entry should have isSidechain=false")
    XCTAssertTrue(mainHit!.isSelectable, "Main-chain entry should be selectable")

    // Assert: Sidechain entry has isSidechain=true
    let sidechainHit = result.hits.first { $0.id == sidechainEntryId }
    XCTAssertNotNil(sidechainHit, "Should find sidechain entry with ID \(sidechainEntryId)")
    XCTAssertTrue(sidechainHit!.isSidechain, "Sidechain entry should have isSidechain=true")
    XCTAssertTrue(sidechainHit!.displayInTimeline, "Visible sidechain should have displayInTimeline=true")
    XCTAssertTrue(sidechainHit!.isSelectable, "Visible sidechain entry should be selectable")
  }

  /// Regression test: sidechain hit -> getContext() returns non-empty window
  /// This verifies the fix for the original bug where sidechain hits returned empty context
  func testGetContext_sidechainHit_returnsNonEmptyWindow() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-sidechain-context-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("test.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let projectId = "test-project-sidechain-context"
    let transcriptId = "transcript-1"
    try await pool.write { db in
      try db.execute(sql: """
        INSERT INTO projects (id, name, root_path, created_at, updated_at, last_viewed_ts)
        VALUES (?, 'Test Project', '/test', 0, 0, 0)
      """, arguments: [projectId])

      try db.execute(sql: """
        INSERT INTO transcripts (
          id, project_id, file_path, normalized_path, path_hash, provider,
          last_modified, file_size, content_length, mtime_ms,
          line_count, last_processed_line, parser_version, status, ingest_state,
          created_at, updated_at
        ) VALUES (?, ?, '/test/file.jsonl', '/test/file.jsonl', 'hash-sc-ctx', 'claude.code',
          0, 0, 0, 0, 0, 0, 1, 'active', 'complete', 0, 0)
      """, arguments: [transcriptId, projectId])

      // Insert a sequence of entries in the same transcript:
      // 1. Main-chain entry (before sidechain)
      // 2. Sidechain entry (the hit)
      // 3. Main-chain entry (after sidechain)
      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES ('before-entry', ?, ?, 'claude.code', 'user', 1000,
          'before sidechain', 'sha-b', 1, 0, 1000, 1000, 0)
      """, arguments: [transcriptId, projectId])

      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES ('sidechain-hit', ?, ?, 'claude.code', 'assistant', 2000,
          'sidechain entry content', 'sha-s', 1, 1, 2000, 2000, 0)
      """, arguments: [transcriptId, projectId])

      try db.execute(sql: """
        INSERT INTO transcript_entries (
          id, transcript_id, project_id, provider, kind, timestamp, content,
          content_sha256, display_in_timeline, is_sidechain, created_at, updated_at, is_queued
        ) VALUES ('after-entry', ?, ?, 'claude.code', 'user', 3000,
          'after sidechain', 'sha-a', 1, 0, 3000, 3000, 0)
      """, arguments: [transcriptId, projectId])
    }

    // Test: Get context for the sidechain entry
    let service = ConversationSearchService(dbManager: dbManager)
    let context = try await service.getContext(entryId: "sidechain-hit", before: 10, after: 10)

    // Assert: Context should NOT be empty (this was the original bug)
    XCTAssertFalse(context.isEmpty, "Context for sidechain hit should NOT be empty")

    // Assert: The sidechain hit itself should be in the context
    let hitIds = context.map { $0.id }
    XCTAssertTrue(hitIds.contains("sidechain-hit"), "Context should include the sidechain hit itself")

    // Assert: Context should include neighbors from the same transcript
    // Note: getContext uses displayInTimeline filter, so it returns visible entries only.
    // The sidechain hit is visible (displayInTimeline=1), so it should be returned.
    XCTAssertGreaterThanOrEqual(context.count, 1, "Context should include at least the hit entry")
  }
}
