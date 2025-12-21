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
}
