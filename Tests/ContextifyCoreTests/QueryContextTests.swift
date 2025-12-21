import XCTest
import GRDB
@testable import ContextifyCore

final class QueryContextTests: XCTestCase {

  func testContextWindowOrderingAndFlags() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-query-context-test-\(UUID().uuidString)")
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

    let e3Hidden = TranscriptEntry(
      id: "e3",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "system",
      timestamp: 300,
      content: "hidden",
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

    let e4 = TranscriptEntry(
      id: "e4",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "assistant",
      timestamp: 400,
      content: "four",
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
      try e2.insert(db)
      try e3Hidden.insert(db)
      try e4.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    let context = try service.context(entryId: "e2", beforeCount: 1, afterCount: 2, includeHidden: false)
    XCTAssertEqual(context.before.map(\.id), ["e1"])
    XCTAssertEqual(context.anchor.id, "e2")
    XCTAssertEqual(context.after.map(\.id), ["e4"])
    XCTAssertFalse(context.meta.hasMoreAfter)
    XCTAssertFalse(context.meta.hasMoreBefore)
    XCTAssertEqual(context.meta.transcriptEntryCount, 3)

    let contextWithHidden = try service.context(entryId: "e2", beforeCount: 1, afterCount: 2, includeHidden: true)
    XCTAssertEqual(contextWithHidden.after.map(\.id), ["e3", "e4"])
    XCTAssertFalse(contextWithHidden.meta.hasMoreAfter)
    XCTAssertEqual(contextWithHidden.meta.transcriptEntryCount, 4)
  }

  func testEntryTruncationPreservesUTF8() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-query-context-test-\(UUID().uuidString)")
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

    let big = String(repeating: "🙂", count: 2000)
    let entry = TranscriptEntry(
      id: "e1",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "assistant",
      timestamp: 100,
      content: big,
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

    try await pool.write { db in
      try project.insert(db)
      try transcript.insert(db)
      try entry.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)
    let result = try service.entry(entryId: "e1", includeContent: true, fullContent: false, maxContentBytes: 2048)
    XCTAssertNotNil(result.entry.content)
    XCTAssertTrue(result.entry.contentTruncated ?? false)
    XCTAssertNotNil(result.entry.contentFullSize)
    XCTAssertTrue(result.entry.content?.data(using: .utf8) != nil)
  }
}
