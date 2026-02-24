import XCTest
import GRDB
@testable import ContextifyCore

// MARK: - ChronicleModelsTests

final class ChronicleModelsTests: XCTestCase {

  // MARK: - ArcStatus

  func testArcStatusRawValues() {
    XCTAssertEqual(ArcStatus.active.rawValue, "active")
    XCTAssertEqual(ArcStatus.completing.rawValue, "completing")
    XCTAssertEqual(ArcStatus.completed.rawValue, "completed")
    XCTAssertEqual(ArcStatus.blocked.rawValue, "blocked")
    XCTAssertEqual(ArcStatus.abandoned.rawValue, "abandoned")
    XCTAssertEqual(ArcStatus.allCases.count, 5)
  }

  // MARK: - SignpostKind

  func testSignpostKindRawValues() {
    XCTAssertEqual(SignpostKind.decision.rawValue, "decision")
    XCTAssertEqual(SignpostKind.discovery.rawValue, "discovery")
    XCTAssertEqual(SignpostKind.pivot.rawValue, "pivot")
    XCTAssertEqual(SignpostKind.milestone.rawValue, "milestone")
    XCTAssertEqual(SignpostKind.blocker.rawValue, "blocker")
    XCTAssertEqual(SignpostKind.resolution.rawValue, "resolution")
    XCTAssertEqual(SignpostKind.allCases.count, 6)
  }

  // MARK: - ContinuitySignal

  func testContinuitySignalRawValues() {
    XCTAssertEqual(ContinuitySignal.clearCommand.rawValue, "clearCommand")
    XCTAssertEqual(ContinuitySignal.compaction.rawValue, "compaction")
    XCTAssertEqual(ContinuitySignal.timeProximity.rawValue, "timeProximity")
    XCTAssertEqual(ContinuitySignal.explicitReference.rawValue, "explicitReference")
    XCTAssertEqual(ContinuitySignal.allCases.count, 4)
  }

  // MARK: - ChronicleArc JSON helpers

  func testChronicleArcTranscriptIds() {
    let now = Int(Date().timeIntervalSince1970)
    let arc = ChronicleArc(
      id: UUID().uuidString,
      projectId: "proj-1",
      intent: "Test intent",
      startedAt: now,
      lastActivityAt: now,
      transcriptIdsJson: "[\"a\",\"b\"]"
    )
    XCTAssertEqual(arc.transcriptIds, ["a", "b"])
  }

  func testChronicleArcEmptyTranscriptIds() {
    let now = Int(Date().timeIntervalSince1970)
    let arc = ChronicleArc(
      id: UUID().uuidString,
      projectId: "proj-1",
      intent: "Test intent",
      startedAt: now,
      lastActivityAt: now,
      transcriptIdsJson: "[]"
    )
    XCTAssertEqual(arc.transcriptIds, [])
  }

  func testChronicleArcEncodeTranscriptIds() throws {
    let ids = ["x", "y"]
    let json = ChronicleArc.encodeTranscriptIds(ids)
    XCTAssertFalse(json.isEmpty)

    // Round-trip: decoded result must equal original
    let data = try XCTUnwrap(json.data(using: .utf8))
    let decoded = try JSONDecoder().decode([String].self, from: data)
    XCTAssertEqual(decoded, ids)
  }

  // MARK: - NarrativeState JSON helpers

  func testNarrativeStateArcStack() {
    let state = NarrativeState(
      projectId: "proj-1",
      arcStackJson: "[\"arc1\",\"arc2\"]"
    )
    XCTAssertEqual(state.arcStack, ["arc1", "arc2"])
  }

  func testNarrativeStateRollingWindow() throws {
    let summaries = [
      ExchangeSummary(entryId: "e1", summary: "First exchange"),
      ExchangeSummary(entryId: "e2", summary: "Second exchange")
    ]
    let json = NarrativeState.encodeRollingWindow(summaries)
    let state = NarrativeState(
      projectId: "proj-1",
      rollingWindowJson: json
    )

    let window = state.rollingWindow
    XCTAssertEqual(window.count, 2)
    XCTAssertEqual(window[0].entryId, "e1")
    XCTAssertEqual(window[0].summary, "First exchange")
    XCTAssertEqual(window[1].entryId, "e2")
    XCTAssertEqual(window[1].summary, "Second exchange")
  }

  func testNarrativeStateEncodeHelpers() throws {
    // Arc stack round-trip
    let arcIds = ["arc-a", "arc-b", "arc-c"]
    let arcJson = NarrativeState.encodeArcStack(arcIds)
    let arcData = try XCTUnwrap(arcJson.data(using: .utf8))
    let decodedArcs = try JSONDecoder().decode([String].self, from: arcData)
    XCTAssertEqual(decodedArcs, arcIds)

    // Rolling window round-trip
    let summaries = [ExchangeSummary(entryId: "e1", summary: "summary text")]
    let windowJson = NarrativeState.encodeRollingWindow(summaries)
    let windowData = try XCTUnwrap(windowJson.data(using: .utf8))
    let decodedWindow = try JSONDecoder().decode([ExchangeSummary].self, from: windowData)
    XCTAssertEqual(decodedWindow.count, 1)
    XCTAssertEqual(decodedWindow[0].entryId, "e1")
    XCTAssertEqual(decodedWindow[0].summary, "summary text")
  }

  // MARK: - ExchangeSummary

  func testExchangeSummaryCodable() throws {
    let original = ExchangeSummary(entryId: "entry-123", summary: "Did a thing")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ExchangeSummary.self, from: data)
    XCTAssertEqual(decoded.entryId, original.entryId)
    XCTAssertEqual(decoded.summary, original.summary)
    XCTAssertEqual(decoded, original)
  }
}

// MARK: - ChronicleRepositoryTests

final class ChronicleRepositoryTests: XCTestCase {
  var tempDir: URL!
  var db: DatabasePool!
  var repo: ChronicleRepositoryImpl!

  // Reusable project and transcript IDs for FK-constrained records
  var testProjectId: String!
  var testTranscriptId: String!
  var testTranscriptId2: String!

  override func setUp() async throws {
    try await super.setUp()

    // Create temporary directory for test database
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Set up DatabasePool with foreign key support and run all migrations
    var config = Configuration()
    config.foreignKeysEnabled = true
    let dbPath = tempDir.appendingPathComponent("chronicle-test.db")
    db = try DatabasePool(path: dbPath.path, configuration: config)

    let migrator = DatabaseSchema.createMigrator()
    try migrator.migrate(db)

    // Seed a project row (required by chronicle_arcs and chronicle_narrative_state FKs)
    let projectRepo = ProjectRepositoryImpl(db: db)
    testProjectId = try projectRepo.create(name: "Chronicle Test Project", rootPath: "/tmp/chronicle-test", bookmark: nil)

    // Seed two transcript rows (required by transcript_continuity FKs)
    let transcriptRepo = TranscriptRepositoryImpl(db: db)
    let fileURL1 = URL(fileURLWithPath: "/tmp/chronicle-test/transcript1.jsonl")
    testTranscriptId = try transcriptRepo.upsert(
      projectId: testProjectId,
      fileURL: fileURL1,
      provider: "claude.code",
      providerSessionId: "session-chron-1",
      lastModified: Date(),
      fileSize: 512
    )
    let fileURL2 = URL(fileURLWithPath: "/tmp/chronicle-test/transcript2.jsonl")
    testTranscriptId2 = try transcriptRepo.upsert(
      projectId: testProjectId,
      fileURL: fileURL2,
      provider: "claude.code",
      providerSessionId: "session-chron-2",
      lastModified: Date(),
      fileSize: 512
    )

    repo = ChronicleRepositoryImpl(db: db)
  }

  override func tearDown() async throws {
    try await super.tearDown()
    repo = nil
    db = nil
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
    tempDir = nil
  }

  // MARK: - Arc Tests

  func testSaveAndFetchArc() throws {
    let now = Int(Date().timeIntervalSince1970)
    let arcId = UUID().uuidString
    let arc = ChronicleArc(
      id: arcId,
      projectId: testProjectId,
      intent: "Implement search feature",
      strategicContext: "Part of phase 2 roadmap",
      status: .active,
      startedAt: now,
      lastActivityAt: now,
      transcriptIdsJson: "[\"t1\",\"t2\"]"
    )

    try repo.saveArc(arc)

    let fetched = try repo.fetchArc(id: arcId)
    XCTAssertNotNil(fetched)
    XCTAssertEqual(fetched?.id, arcId)
    XCTAssertEqual(fetched?.projectId, testProjectId)
    XCTAssertEqual(fetched?.intent, "Implement search feature")
    XCTAssertEqual(fetched?.strategicContext, "Part of phase 2 roadmap")
    XCTAssertEqual(fetched?.status, .active)
    XCTAssertEqual(fetched?.startedAt, now)
    XCTAssertEqual(fetched?.lastActivityAt, now)
    XCTAssertEqual(fetched?.transcriptIds, ["t1", "t2"])
  }

  func testFetchActiveArcs() throws {
    let now = Int(Date().timeIntervalSince1970)

    let activeArc1 = ChronicleArc(
      id: UUID().uuidString,
      projectId: testProjectId,
      intent: "Active arc 1",
      status: .active,
      startedAt: now,
      lastActivityAt: now
    )
    let activeArc2 = ChronicleArc(
      id: UUID().uuidString,
      projectId: testProjectId,
      intent: "Active arc 2",
      status: .active,
      startedAt: now,
      lastActivityAt: now - 10
    )
    let completedArc = ChronicleArc(
      id: UUID().uuidString,
      projectId: testProjectId,
      intent: "Completed arc",
      status: .completed,
      startedAt: now - 100,
      completedAt: now - 50,
      lastActivityAt: now - 50
    )

    try repo.saveArc(activeArc1)
    try repo.saveArc(activeArc2)
    try repo.saveArc(completedArc)

    let activeArcs = try repo.fetchActiveArcs(for: testProjectId)
    XCTAssertEqual(activeArcs.count, 2)
    XCTAssertTrue(activeArcs.allSatisfy { $0.status == .active })
  }

  func testUpdateArcStatus() throws {
    let now = Int(Date().timeIntervalSince1970)
    let arcId = UUID().uuidString
    let arc = ChronicleArc(
      id: arcId,
      projectId: testProjectId,
      intent: "Arc to complete",
      status: .active,
      startedAt: now,
      lastActivityAt: now
    )

    try repo.saveArc(arc)

    let completedAt = now + 3600
    try repo.updateArcStatus(id: arcId, status: .completed, completedAt: completedAt)

    let updated = try repo.fetchArc(id: arcId)
    XCTAssertEqual(updated?.status, .completed)
    XCTAssertEqual(updated?.completedAt, completedAt)
  }

  func testArcForDifferentProject() throws {
    let now = Int(Date().timeIntervalSince1970)

    // Create a second project
    let projectRepo = ProjectRepositoryImpl(db: db)
    let otherProjectId = try projectRepo.create(name: "Other Project", rootPath: "/tmp/other-project", bookmark: nil)

    let arc = ChronicleArc(
      id: UUID().uuidString,
      projectId: testProjectId,
      intent: "Arc for project A",
      status: .active,
      startedAt: now,
      lastActivityAt: now
    )
    try repo.saveArc(arc)

    // Fetch active arcs for the OTHER project (should be empty)
    let arcs = try repo.fetchActiveArcs(for: otherProjectId)
    XCTAssertEqual(arcs.count, 0)
  }

  // MARK: - Signpost Tests

  func testSaveAndFetchSignpost() throws {
    let now = Int(Date().timeIntervalSince1970)
    let arcId = UUID().uuidString
    let arc = ChronicleArc(
      id: arcId,
      projectId: testProjectId,
      intent: "Arc for signpost test",
      status: .active,
      startedAt: now,
      lastActivityAt: now
    )
    try repo.saveArc(arc)

    let signpostId = UUID().uuidString
    let signpost = ChronicleSignpost(
      id: signpostId,
      arcId: arcId,
      kind: .decision,
      summary: "Chose GRDB over CoreData",
      detail: "Performance requirements favor GRDB",
      timestamp: now
    )
    try repo.saveSignpost(signpost)

    let fetched = try repo.fetchSignposts(for: arcId)
    XCTAssertEqual(fetched.count, 1)
    XCTAssertEqual(fetched[0].id, signpostId)
    XCTAssertEqual(fetched[0].arcId, arcId)
    XCTAssertEqual(fetched[0].kind, .decision)
    XCTAssertEqual(fetched[0].summary, "Chose GRDB over CoreData")
    XCTAssertEqual(fetched[0].detail, "Performance requirements favor GRDB")
    XCTAssertEqual(fetched[0].timestamp, now)
  }

  func testFetchSignpostsOrdering() throws {
    let now = Int(Date().timeIntervalSince1970)
    let arcId = UUID().uuidString
    let arc = ChronicleArc(
      id: arcId,
      projectId: testProjectId,
      intent: "Arc for ordering test",
      status: .active,
      startedAt: now,
      lastActivityAt: now
    )
    try repo.saveArc(arc)

    // Insert signposts with non-sequential timestamps
    let signpost1 = ChronicleSignpost(
      id: UUID().uuidString,
      arcId: arcId,
      kind: .milestone,
      summary: "Earliest signpost",
      timestamp: now - 200
    )
    let signpost2 = ChronicleSignpost(
      id: UUID().uuidString,
      arcId: arcId,
      kind: .discovery,
      summary: "Middle signpost",
      timestamp: now - 100
    )
    let signpost3 = ChronicleSignpost(
      id: UUID().uuidString,
      arcId: arcId,
      kind: .pivot,
      summary: "Latest signpost",
      timestamp: now
    )

    // Insert in non-sequential order
    try repo.saveSignpost(signpost3)
    try repo.saveSignpost(signpost1)
    try repo.saveSignpost(signpost2)

    let fetched = try repo.fetchSignposts(for: arcId)
    XCTAssertEqual(fetched.count, 3)
    // Verify ascending timestamp order
    XCTAssertEqual(fetched[0].summary, "Earliest signpost")
    XCTAssertEqual(fetched[1].summary, "Middle signpost")
    XCTAssertEqual(fetched[2].summary, "Latest signpost")
    XCTAssertLessThan(fetched[0].timestamp, fetched[1].timestamp)
    XCTAssertLessThan(fetched[1].timestamp, fetched[2].timestamp)
  }

  // MARK: - NarrativeState Tests

  func testSaveAndFetchNarrativeState() throws {
    let now = Int(Date().timeIntervalSince1970)
    let arcId = UUID().uuidString
    let arc = ChronicleArc(
      id: arcId,
      projectId: testProjectId,
      intent: "Current arc",
      status: .active,
      startedAt: now,
      lastActivityAt: now
    )
    try repo.saveArc(arc)

    let summaries = [ExchangeSummary(entryId: "e1", summary: "Did something")]
    let state = NarrativeState(
      projectId: testProjectId,
      currentArcId: arcId,
      arcStackJson: NarrativeState.encodeArcStack([arcId]),
      rollingWindowJson: NarrativeState.encodeRollingWindow(summaries),
      updatedAt: now
    )
    try repo.saveNarrativeState(state)

    let fetched = try repo.fetchNarrativeState(for: testProjectId)
    XCTAssertNotNil(fetched)
    XCTAssertEqual(fetched?.projectId, testProjectId)
    XCTAssertEqual(fetched?.currentArcId, arcId)
    XCTAssertEqual(fetched?.arcStack, [arcId])
    XCTAssertEqual(fetched?.rollingWindow.count, 1)
    XCTAssertEqual(fetched?.rollingWindow[0].entryId, "e1")
    XCTAssertEqual(fetched?.updatedAt, now)
  }

  func testNarrativeStateUpsert() throws {
    let now = Int(Date().timeIntervalSince1970)

    let state1 = NarrativeState(
      projectId: testProjectId,
      arcStackJson: "[]",
      rollingWindowJson: "[]",
      updatedAt: now
    )
    try repo.saveNarrativeState(state1)

    // Save again with updated content (upsert behavior)
    let state2 = NarrativeState(
      projectId: testProjectId,
      arcStackJson: "[\"arc-updated\"]",
      rollingWindowJson: "[]",
      updatedAt: now + 60
    )
    try repo.saveNarrativeState(state2)

    // Verify only one row exists in the database
    let rowCount = try db.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chronicle_narrative_state WHERE project_id = ?", arguments: [testProjectId]) ?? 0
    }
    XCTAssertEqual(rowCount, 1)

    // Verify the second save's data is present
    let fetched = try repo.fetchNarrativeState(for: testProjectId)
    XCTAssertEqual(fetched?.arcStack, ["arc-updated"])
    XCTAssertEqual(fetched?.updatedAt, now + 60)
  }

  // MARK: - TranscriptContinuity Tests

  func testSaveAndFetchTranscriptContinuity() throws {
    let now = Int(Date().timeIntervalSince1970)
    let continuity = TranscriptContinuity(
      fromTranscriptId: testTranscriptId,
      toTranscriptId: testTranscriptId2,
      continuitySignal: .clearCommand,
      confidence: 0.95,
      detectedAt: now
    )
    try repo.saveTranscriptContinuity(continuity)

    let fetched = try repo.fetchContinuity(from: testTranscriptId)
    XCTAssertEqual(fetched.count, 1)
    XCTAssertEqual(fetched[0].fromTranscriptId, testTranscriptId)
    XCTAssertEqual(fetched[0].toTranscriptId, testTranscriptId2)
    XCTAssertEqual(fetched[0].continuitySignal, .clearCommand)
    XCTAssertEqual(fetched[0].confidence, 0.95, accuracy: 0.001)
    XCTAssertEqual(fetched[0].detectedAt, now)
  }

  // MARK: - Cascade Delete Tests

  func testCascadeDeleteArc() throws {
    let now = Int(Date().timeIntervalSince1970)
    let arcId = UUID().uuidString
    let arc = ChronicleArc(
      id: arcId,
      projectId: testProjectId,
      intent: "Arc to cascade delete",
      status: .active,
      startedAt: now,
      lastActivityAt: now
    )
    try repo.saveArc(arc)

    let signpost = ChronicleSignpost(
      id: UUID().uuidString,
      arcId: arcId,
      kind: .blocker,
      summary: "Signpost attached to arc",
      timestamp: now
    )
    try repo.saveSignpost(signpost)

    // Verify signpost exists before deletion
    let before = try repo.fetchSignposts(for: arcId)
    XCTAssertEqual(before.count, 1)

    // Delete arc directly via SQL (repository has no delete method)
    try db.write { db in
      try db.execute(sql: "DELETE FROM chronicle_arcs WHERE id = ?", arguments: [arcId])
    }

    // Verify signpost is gone (CASCADE delete)
    let after = try repo.fetchSignposts(for: arcId)
    XCTAssertEqual(after.count, 0)

    // Verify the arc is also gone
    let deletedArc = try repo.fetchArc(id: arcId)
    XCTAssertNil(deletedArc)
  }
}
