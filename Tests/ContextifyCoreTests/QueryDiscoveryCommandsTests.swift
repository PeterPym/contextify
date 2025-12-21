import XCTest
import GRDB
@testable import ContextifyCore

final class QueryDiscoveryCommandsTests: XCTestCase {

  func testListTranscriptsAndSearch() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-query-discovery-test-\(UUID().uuidString)")
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

    let entry = TranscriptEntry(
      id: "e1",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "assistant",
      timestamp: 200,
      content: "Unread count updated",
      contentSha256: "sha",
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
      try entry.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    let transcripts = try service.listTranscripts(projectId: "p1", limit: 10)
    XCTAssertEqual(transcripts.first?.id, "t1")
    XCTAssertEqual(transcripts.first?.lastEntryTimestamp, 200)

    let hits = try service.search(query: "unread count", projectId: "p1", transcriptId: "t1", limit: 10)
    XCTAssertEqual(hits.first?.id, "e1")
    XCTAssertEqual(hits.first?.projectId, "p1")
    XCTAssertEqual(hits.first?.transcriptId, "t1")
    XCTAssertFalse(hits.first?.contentSnippet.isEmpty ?? true)
  }
}

