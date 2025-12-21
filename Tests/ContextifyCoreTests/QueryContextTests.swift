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

  /// Test that includeSidechains is decoupled from includeHidden
  func testContextSidechainFilteringDecoupled() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-query-sidechain-test-\(UUID().uuidString)")
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

    // e1: visible, main-chain (should appear in default filter)
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

    // e2: anchor - visible, main-chain
    let e2 = TranscriptEntry(
      id: "e2",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "assistant",
      timestamp: 200,
      content: "anchor",
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

    // e3: visible, SIDECHAIN (should only appear with includeSidechains: true)
    let e3Sidechain = TranscriptEntry(
      id: "e3",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "assistant",
      timestamp: 300,
      content: "sidechain entry",
      contentSha256: "sha3",
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
      createdAt: 300,
      updatedAt: 300,
      isQueued: 0,
      isSidechain: 1
    )

    // e4: HIDDEN, main-chain (should only appear with includeHidden: true)
    let e4Hidden = TranscriptEntry(
      id: "e4",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "system",
      timestamp: 400,
      content: "hidden entry",
      contentSha256: "sha4",
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
      createdAt: 400,
      updatedAt: 400,
      isQueued: 0,
      isSidechain: 0
    )

    // e5: visible, main-chain
    let e5 = TranscriptEntry(
      id: "e5",
      transcriptId: "t1",
      projectId: "p1",
      sessionId: nil,
      provider: "claude.code",
      kind: "user",
      timestamp: 500,
      content: "visible main-chain 2",
      contentSha256: "sha5",
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
      createdAt: 500,
      updatedAt: 500,
      isQueued: 0,
      isSidechain: 0
    )

    try await pool.write { db in
      try project.insert(db)
      try transcript.insert(db)
      try e1.insert(db)
      try e2.insert(db)
      try e3Sidechain.insert(db)
      try e4Hidden.insert(db)
      try e5.insert(db)
    }

    let service = try ContextifyQueryService(databaseURL: dbURL)

    // Test 1: Default (includeHidden: false, includeSidechains: false)
    // Should see: e1, e2 (anchor), e5
    // Should NOT see: e3 (sidechain), e4 (hidden)
    let defaultContext = try service.context(
      entryId: "e2",
      beforeCount: 5,
      afterCount: 5,
      includeHidden: false,
      includeSidechains: false
    )
    XCTAssertEqual(defaultContext.before.map(\.id), ["e1"])
    XCTAssertEqual(defaultContext.after.map(\.id), ["e5"])
    XCTAssertEqual(defaultContext.meta.transcriptEntryCount, 3)

    // Test 2: includeSidechains: true, includeHidden: false
    // Should see: e1, e2 (anchor), e3 (sidechain), e5
    // Should NOT see: e4 (hidden)
    let sidechainContext = try service.context(
      entryId: "e2",
      beforeCount: 5,
      afterCount: 5,
      includeHidden: false,
      includeSidechains: true
    )
    XCTAssertEqual(sidechainContext.before.map(\.id), ["e1"])
    XCTAssertEqual(sidechainContext.after.map(\.id), ["e3", "e5"])
    XCTAssertEqual(sidechainContext.meta.transcriptEntryCount, 4)

    // Test 3: includeHidden: true, includeSidechains: false
    // Should see: e1, e2 (anchor), e4 (hidden), e5
    // Should NOT see: e3 (sidechain)
    let hiddenContext = try service.context(
      entryId: "e2",
      beforeCount: 5,
      afterCount: 5,
      includeHidden: true,
      includeSidechains: false
    )
    XCTAssertEqual(hiddenContext.before.map(\.id), ["e1"])
    XCTAssertEqual(hiddenContext.after.map(\.id), ["e4", "e5"])
    XCTAssertEqual(hiddenContext.meta.transcriptEntryCount, 4)

    // Test 4: includeHidden: true, includeSidechains: true (debug mode)
    // Should see: all entries
    let allContext = try service.context(
      entryId: "e2",
      beforeCount: 5,
      afterCount: 5,
      includeHidden: true,
      includeSidechains: true
    )
    XCTAssertEqual(allContext.before.map(\.id), ["e1"])
    XCTAssertEqual(allContext.after.map(\.id), ["e3", "e4", "e5"])
    XCTAssertEqual(allContext.meta.transcriptEntryCount, 5)
  }
}
