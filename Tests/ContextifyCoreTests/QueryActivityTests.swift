import XCTest
import GRDB
@testable import ContextifyCore

final class QueryActivityTests: XCTestCase {

  func testActivityRespectsTimeRangeAndNoContent() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-query-activity-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let project = Project(
      id: "p1",
      name: "Test",
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

    let e1 = TranscriptEntry(
      id: "e1",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "user",
      timestamp: 100,
      content: "one",
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

    let e2 = TranscriptEntry(
      id: "e2",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "assistant",
      timestamp: 200,
      content: "two",
      contentSha256: "sha2",
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
      createdAt: 200,
      updatedAt: 200,
      isQueued: 0,
        isSidechain: 0
    )

    try await pool.write { db in
      try project.insert(db)
      try transcript.insert(db)
      try e1.insert(db)
      try e2.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)
    let range = QueryTimeRange(sinceTimestamp: 150, untilTimestamp: nil)
    let results = try service.activity(projectId: "p1", limit: 50, timeRange: range, includeContent: false)
    XCTAssertEqual(results.map(\.entry.id), ["e2"])
    XCTAssertNil(results.first?.entry.content)
  }

  /// Test that includeSidechains is decoupled from includeHidden in activity()
  func testActivitySidechainFilteringDecoupled() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-activity-sidechain-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    let pool = try dbManager.pool

    let project = Project(
      id: "p1",
      name: "Test",
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

    // e1: visible, main-chain
    let e1 = TranscriptEntry(
      id: "e1",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "user",
      timestamp: 100,
      content: "visible main-chain",
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

    // e2: visible, SIDECHAIN
    let e2Sidechain = TranscriptEntry(
      id: "e2",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "assistant",
      timestamp: 200,
      content: "sidechain entry",
      contentSha256: "sha2",
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
      createdAt: 200,
      updatedAt: 200,
      isQueued: 0,
      isSidechain: 1
    )

    // e3: HIDDEN, main-chain
    let e3Hidden = TranscriptEntry(
      id: "e3",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "system",
      timestamp: 300,
      content: "hidden entry",
      contentSha256: "sha3",
      displayInTimeline: 0,
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
      createdAt: 300,
      updatedAt: 300,
      isQueued: 0,
      isSidechain: 0
    )

    // e4: visible, main-chain
    let e4 = TranscriptEntry(
      id: "e4",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "user",
      timestamp: 400,
      content: "visible main-chain 2",
      contentSha256: "sha4",
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
      createdAt: 400,
      updatedAt: 400,
      isQueued: 0,
      isSidechain: 0
    )

    try await pool.write { db in
      try project.insert(db)
      try transcript.insert(db)
      try e1.insert(db)
      try e2Sidechain.insert(db)
      try e3Hidden.insert(db)
      try e4.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Test 1: Default (includeHidden: false, includeSidechains: false)
    // Should see: e1, e4 (visible main-chain only)
    let defaultResults = try service.activity(
      projectId: "p1",
      limit: 50,
      includeHidden: false,
      includeSidechains: false
    )
    XCTAssertEqual(Set(defaultResults.map(\.entry.id)), Set(["e1", "e4"]))

    // Test 2: includeSidechains: true, includeHidden: false
    // Should see: e1, e2 (sidechain), e4
    let sidechainResults = try service.activity(
      projectId: "p1",
      limit: 50,
      includeHidden: false,
      includeSidechains: true
    )
    XCTAssertEqual(Set(sidechainResults.map(\.entry.id)), Set(["e1", "e2", "e4"]))

    // Test 3: includeHidden: true, includeSidechains: false
    // Should see: e1, e3 (hidden), e4
    let hiddenResults = try service.activity(
      projectId: "p1",
      limit: 50,
      includeHidden: true,
      includeSidechains: false
    )
    XCTAssertEqual(Set(hiddenResults.map(\.entry.id)), Set(["e1", "e3", "e4"]))

    // Test 4: includeHidden: true, includeSidechains: true (debug mode)
    // Should see: all entries
    let allResults = try service.activity(
      projectId: "p1",
      limit: 50,
      includeHidden: true,
      includeSidechains: true
    )
    XCTAssertEqual(Set(allResults.map(\.entry.id)), Set(["e1", "e2", "e3", "e4"]))
  }
}

