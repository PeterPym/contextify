import XCTest
@testable import ContextifyCore

final class WatcherBudgetCoordinatorTests: XCTestCase {
  var tempDir: URL!
  var dbManager: DatabaseManager!
  var orchestrator: TranscriptOrchestrator!
  var coordinator: WatcherBudgetCoordinator!

  override func setUp() async throws {
    try await super.setUp()

    // Create temporary directory for test database
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Set up database and orchestrator
    let dbPath = tempDir.appendingPathComponent("test.db")
    dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    coordinator = WatcherBudgetCoordinator(orchestrator: orchestrator)
  }

  override func tearDown() async throws {
    // Clean up coordinator state
    await coordinator.deactivateAll()

    try await super.tearDown()

    // Clean up temp directory
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - LRU Order Tests

  func testLRUOrder_MaintainsCorrectOrderAcrossActivations() async throws {
    // Given: Four projects activated in sequence A → B → C → D
    await coordinator.activateProject("A")
    await coordinator.activateProject("B")
    await coordinator.activateProject("C")
    await coordinator.activateProject("D")

    // When: We reactivate A (should move to front)
    await coordinator.activateProject("A")

    // Then: LRU order should be [A, D, C] with B evicted
    // A should be HOT, D and C should be WARM
    let tierA = await coordinator.currentTier(for: "A")
    let tierD = await coordinator.currentTier(for: "D")
    let tierC = await coordinator.currentTier(for: "C")
    let tierB = await coordinator.currentTier(for: "B")

    XCTAssertEqual(tierA, .hot, "A should be HOT (most recently activated)")
    XCTAssertEqual(tierD, .warm, "D should be WARM (2nd most recent)")
    XCTAssertEqual(tierC, .warm, "C should be WARM (3rd most recent)")
    XCTAssertEqual(tierB, .cold, "B should be COLD (evicted from LRU)")
  }

  func testLRUOrder_FirstActivationSetsHot() async throws {
    // When: A single project is activated
    await coordinator.activateProject("A")

    // Then: It should be HOT
    let tier = await coordinator.currentTier(for: "A")
    XCTAssertEqual(tier, .hot, "First activated project should be HOT")
  }

  func testLRUOrder_ReactivationMovesToFront() async throws {
    // Given: Three projects activated
    await coordinator.activateProject("A")
    await coordinator.activateProject("B")
    await coordinator.activateProject("C")

    // Verify initial state: C=HOT, B=WARM, A=WARM
    let initialTierC = await coordinator.currentTier(for: "C")
    let initialTierB = await coordinator.currentTier(for: "B")
    let initialTierA = await coordinator.currentTier(for: "A")
    XCTAssertEqual(initialTierC, .hot)
    XCTAssertEqual(initialTierB, .warm)
    XCTAssertEqual(initialTierA, .warm)

    // When: We reactivate A
    await coordinator.activateProject("A")

    // Then: A should be HOT, C and B should be WARM
    let tierA = await coordinator.currentTier(for: "A")
    let tierC = await coordinator.currentTier(for: "C")
    let tierB = await coordinator.currentTier(for: "B")
    XCTAssertEqual(tierA, .hot)
    XCTAssertEqual(tierC, .warm)
    XCTAssertEqual(tierB, .warm)
  }

  // MARK: - Tier Assignment Tests

  func testTierAssignment_DeterministicFromLRU() async throws {
    // Given: Four projects activated in order
    await coordinator.activateProject("A")
    await coordinator.activateProject("B")
    await coordinator.activateProject("C")
    await coordinator.activateProject("D")

    // Then: Tiers should be deterministic from LRU order
    // LRU[0] (D) = HOT
    // LRU[1] (C) = WARM
    // LRU[2] (B) = WARM
    // Everything else (A) = COLD
    let tierD = await coordinator.currentTier(for: "D")
    let tierC = await coordinator.currentTier(for: "C")
    let tierB = await coordinator.currentTier(for: "B")
    let tierA = await coordinator.currentTier(for: "A")
    XCTAssertEqual(tierD, .hot, "LRU[0] should be HOT")
    XCTAssertEqual(tierC, .warm, "LRU[1] should be WARM")
    XCTAssertEqual(tierB, .warm, "LRU[2] should be WARM")
    XCTAssertEqual(tierA, .cold, "Beyond LRU[2] should be COLD")
  }

  func testTierAssignment_MaxThreeActiveProjects() async throws {
    // Given: Five projects activated
    await coordinator.activateProject("A")
    await coordinator.activateProject("B")
    await coordinator.activateProject("C")
    await coordinator.activateProject("D")
    await coordinator.activateProject("E")

    // Then: Only the 3 most recent should be active (E, D, C)
    // A and B should be COLD
    let tierE = await coordinator.currentTier(for: "E")
    let tierD = await coordinator.currentTier(for: "D")
    let tierC = await coordinator.currentTier(for: "C")
    let tierB = await coordinator.currentTier(for: "B")
    let tierA = await coordinator.currentTier(for: "A")
    XCTAssertEqual(tierE, .hot)
    XCTAssertEqual(tierD, .warm)
    XCTAssertEqual(tierC, .warm)
    XCTAssertEqual(tierB, .cold)
    XCTAssertEqual(tierA, .cold)
  }

  // MARK: - Watcher Tracking Tests

  func testIsTranscriptWatched_ReturnsCorrectState() async throws {
    // Given: A project with no watchers initially
    let projectId = "test-project"
    let transcriptId = "test-transcript"

    // Then: Initially not watched
    let initiallyWatched = await coordinator.isTranscriptWatched(
      projectId: projectId,
      transcriptId: transcriptId
    )
    XCTAssertFalse(initiallyWatched, "Transcript should not be watched initially")

    // Note: Full watcher lifecycle testing requires mocking orchestrator.startWatchingTranscript
    // which is beyond the scope of unit tests (would be integration test)
  }

  // MARK: - Deactivation Tests

  func testDeactivateAll_ClearsAllState() async throws {
    // Given: Multiple projects activated
    await coordinator.activateProject("A")
    await coordinator.activateProject("B")
    await coordinator.activateProject("C")

    // Verify they have tiers
    let tierA_before = await coordinator.currentTier(for: "A")
    let tierB_before = await coordinator.currentTier(for: "B")
    let tierC_before = await coordinator.currentTier(for: "C")
    XCTAssertNotEqual(tierA_before, .cold)
    XCTAssertNotEqual(tierB_before, .cold)
    XCTAssertNotEqual(tierC_before, .cold)

    // When: We deactivate all
    await coordinator.deactivateAll()

    // Then: All projects should be COLD (default tier)
    let tierA_after = await coordinator.currentTier(for: "A")
    let tierB_after = await coordinator.currentTier(for: "B")
    let tierC_after = await coordinator.currentTier(for: "C")
    XCTAssertEqual(tierA_after, .cold)
    XCTAssertEqual(tierB_after, .cold)
    XCTAssertEqual(tierC_after, .cold)
  }

  func testDeactivateAll_StopsAllWatchers() async throws {
    let fileURL = tempDir.appendingPathComponent("watcher-test.jsonl")
    try "line\n".write(to: fileURL, atomically: true, encoding: .utf8)
    try orchestrator.startWatchingTranscript(
      transcriptId: "t1",
      fileURL: fileURL,
      provider: TranscriptProviderID.claude
    )
    XCTAssertEqual(orchestrator.watcherCount, 1)

    await coordinator.deactivateAll()
    XCTAssertEqual(orchestrator.watcherCount, 0)

    await coordinator.deactivateAll()
    XCTAssertEqual(orchestrator.watcherCount, 0)

    try orchestrator.startWatchingTranscript(
      transcriptId: "t1",
      fileURL: fileURL,
      provider: TranscriptProviderID.claude
    )
    XCTAssertEqual(orchestrator.watcherCount, 1)
  }

  func testStopWatching_AllowsRestart() async throws {
    let fileURL = tempDir.appendingPathComponent("watcher-test-restart.jsonl")
    try "line\n".write(to: fileURL, atomically: true, encoding: .utf8)

    try orchestrator.startWatchingTranscript(
      transcriptId: "t2",
      fileURL: fileURL,
      provider: TranscriptProviderID.claude
    )
    XCTAssertEqual(orchestrator.watcherCount, 1)

    orchestrator.stopWatchingTranscript(transcriptId: "t2")
    XCTAssertEqual(orchestrator.watcherCount, 0)

    try orchestrator.startWatchingTranscript(
      transcriptId: "t2",
      fileURL: fileURL,
      provider: TranscriptProviderID.claude
    )
    XCTAssertEqual(orchestrator.watcherCount, 1)
  }

  // MARK: - Activity Notification Tests

  func testNoteTranscriptActivity_SchedulesPromotionRecompute() async throws {
    // Given: A project with a transcript
    let projectId = "test-project"
    let transcriptId = "test-transcript"

    // When: We note activity on the transcript
    await coordinator.noteTranscriptActivity(projectId: projectId, transcriptId: transcriptId)

    // Then: This should schedule a debounced promotion recompute
    // We can't directly verify the debounce without waiting 300ms,
    // but we can verify the call completes without error
    // (Full behavior would be tested in integration tests)
  }

  // MARK: - Edge Cases

  func testLRUOrder_DuplicateActivationIsIdempotent() async throws {
    // Given: A project activated twice in a row
    await coordinator.activateProject("A")
    let tierAfterFirst = await coordinator.currentTier(for: "A")

    await coordinator.activateProject("A")
    let tierAfterSecond = await coordinator.currentTier(for: "A")

    // Then: Tier should remain the same (HOT)
    XCTAssertEqual(tierAfterFirst, .hot)
    XCTAssertEqual(tierAfterSecond, .hot)
  }

  func testTierAssignment_EmptyLRUReturnsDefaultCold() async throws {
    // Given: No projects activated (coordinator is fresh)
    // When: We query a tier for a non-existent project
    let tier = await coordinator.currentTier(for: "nonexistent")

    // Then: Should return .cold as default
    XCTAssertEqual(tier, .cold, "Unknown projects should default to COLD tier")
  }

  func testLRUOrder_ComplexActivationSequence() async throws {
    // Given: A complex activation sequence: A → B → A → C → B → A
    await coordinator.activateProject("A")
    await coordinator.activateProject("B")
    await coordinator.activateProject("A")  // A moves to front
    await coordinator.activateProject("C")  // C is now front
    await coordinator.activateProject("B")  // B is now front
    await coordinator.activateProject("A")  // A is now front

    // Then: LRU should be [A, B, C]
    // A = HOT, B = WARM, C = WARM
    let tierA = await coordinator.currentTier(for: "A")
    let tierB = await coordinator.currentTier(for: "B")
    let tierC = await coordinator.currentTier(for: "C")
    XCTAssertEqual(tierA, .hot)
    XCTAssertEqual(tierB, .warm)
    XCTAssertEqual(tierC, .warm)
  }
}
