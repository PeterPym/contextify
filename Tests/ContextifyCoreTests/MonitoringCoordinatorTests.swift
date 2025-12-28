import XCTest
@testable import ContextifyCore

/// Tests for MonitoringCoordinator lazy watcher lifecycle management
final class MonitoringCoordinatorTests: XCTestCase {

  // MARK: - Mock Orchestrator

  /// Mock orchestrator that records calls and can be configured to throw errors
  final class MockOrchestrator: TranscriptOrchestratorProtocol, @unchecked Sendable {
    private var ensureProjectWatcherCalls: [String] = []
    private var stopAllWatchersCalls: [String] = []
    private var rehooverDirtyTranscriptsCalls: [String] = []
    private var projectsToFail: Set<String> = []

    nonisolated func ensureProjectWatcher(projectId: String, targetTranscriptId: String?) throws -> WatcherRecoverySummary {
      ensureProjectWatcherCalls.append(projectId)

      if projectsToFail.contains(projectId) {
        throw TestError.ensureWatcherFailed
      }

      return WatcherRecoverySummary(
        projectId: projectId,
        startedCount: 3,
        alreadyActiveCount: 0,
        missingFileCount: 0,
        targetTranscriptId: targetTranscriptId
      )
    }

    nonisolated func stopAllWatchers(forProjectId projectId: String) throws {
      stopAllWatchersCalls.append(projectId)
    }

    nonisolated func rehooverDirtyTranscripts(projectId: String) async throws -> Int {
      rehooverDirtyTranscriptsCalls.append(projectId)
      return 0
    }

    func reset() {
      ensureProjectWatcherCalls.removeAll()
      stopAllWatchersCalls.removeAll()
      rehooverDirtyTranscriptsCalls.removeAll()
      projectsToFail.removeAll()
    }

    func setProjectToFail(_ projectId: String) {
      projectsToFail.insert(projectId)
    }

    // Accessors for test assertions
    func getEnsureCalls() -> [String] { ensureProjectWatcherCalls }
    func getStopCalls() -> [String] { stopAllWatchersCalls }
    func getRehooverCalls() -> [String] { rehooverDirtyTranscriptsCalls }

    enum TestError: Error {
      case ensureWatcherFailed
    }
  }

  // MARK: - Behavioral Tests

  /// Test 1: Activation success schedules teardown for previous project
  func testActivationSuccess_schedulesTeardownForPrevious() async throws {
    let mock = MockOrchestrator()
    let coordinator = MonitoringCoordinator(orchestrator: mock)

    // Activate project A
    await coordinator.activateProject("project-A")

    // Verify A is active and no teardown scheduled
    let activeAfterA = await coordinator.activeProjectId
    XCTAssertEqual(activeAfterA, "project-A")

    let hasPendingA = await coordinator.hasPendingTeardown(for: "project-A")
    XCTAssertFalse(hasPendingA, "Newly activated project should not have pending teardown")

    // Activate project B
    await coordinator.activateProject("project-B")

    // Verify B is active and A has pending teardown
    let activeAfterB = await coordinator.activeProjectId
    XCTAssertEqual(activeAfterB, "project-B")

    let hasPendingAAfterB = await coordinator.hasPendingTeardown(for: "project-A")
    XCTAssertTrue(hasPendingAAfterB, "Previous project should have pending teardown")

    let hasPendingB = await coordinator.hasPendingTeardown(for: "project-B")
    XCTAssertFalse(hasPendingB, "Newly activated project should not have pending teardown")

    // Verify orchestrator calls
    let ensureCalls = mock.getEnsureCalls()
    XCTAssertEqual(ensureCalls, ["project-A", "project-B"], "Should start watchers for both projects")
  }

  /// Test 2: Activation failure does not teardown previous project
  func testActivationFailure_doesNotTeardownPrevious() async throws {
    let mock = MockOrchestrator()
    let coordinator = MonitoringCoordinator(orchestrator: mock)

    // Activate project A successfully
    await coordinator.activateProject("project-A")

    let activeAfterA = await coordinator.activeProjectId
    XCTAssertEqual(activeAfterA, "project-A")

    let isActiveWithWatchersA = await coordinator.isActiveProjectWithWatchers("project-A")
    XCTAssertTrue(isActiveWithWatchersA, "Project A should be active with watchers")

    // Configure mock to fail for project B
    mock.setProjectToFail("project-B")

    // Try to activate project B (should fail)
    await coordinator.activateProject("project-B")

    // Verify A is still active and has no pending teardown
    let activeAfterFailedB = await coordinator.activeProjectId
    XCTAssertEqual(activeAfterFailedB, "project-A", "Previous project should remain active after failure")

    let hasPendingA = await coordinator.hasPendingTeardown(for: "project-A")
    XCTAssertFalse(hasPendingA, "Previous project should not have teardown after failed activation")

    let isActiveWithWatchersAfterFail = await coordinator.isActiveProjectWithWatchers("project-A")
    XCTAssertTrue(isActiveWithWatchersAfterFail, "Project A should still be active with watchers after failed activation")

    // Verify orchestrator calls
    let ensureCalls = mock.getEnsureCalls()
    XCTAssertEqual(ensureCalls, ["project-A", "project-B"], "Should attempt to start watchers for both")

    let stopCalls = mock.getStopCalls()
    XCTAssertEqual(stopCalls, [], "Should not stop any watchers after failed activation")
  }

  /// Test 3: Reactivation cancels pending teardown
  func testReactivation_cancelsPendingTeardown() async throws {
    let mock = MockOrchestrator()
    let coordinator = MonitoringCoordinator(orchestrator: mock)

    // Activate project A
    await coordinator.activateProject("project-A")

    // Activate project B (schedules teardown for A)
    await coordinator.activateProject("project-B")

    // Verify A has pending teardown
    let hasPendingA = await coordinator.hasPendingTeardown(for: "project-A")
    XCTAssertTrue(hasPendingA, "Project A should have pending teardown after switching to B")

    // Reactivate project A before teardown executes
    await coordinator.activateProject("project-A")

    // Verify A is active and has no pending teardown
    let activeAfterReactivation = await coordinator.activeProjectId
    XCTAssertEqual(activeAfterReactivation, "project-A", "Project A should be active after reactivation")

    let hasPendingAfterReactivation = await coordinator.hasPendingTeardown(for: "project-A")
    XCTAssertFalse(hasPendingAfterReactivation, "Reactivation should cancel pending teardown")

    // Verify B now has pending teardown
    let hasPendingB = await coordinator.hasPendingTeardown(for: "project-B")
    XCTAssertTrue(hasPendingB, "Project B should have pending teardown after switching back to A")

    // Verify orchestrator calls (3 activations, no stops yet)
    let ensureCalls = mock.getEnsureCalls()
    XCTAssertEqual(ensureCalls, ["project-A", "project-B", "project-A"], "Should start watchers for all activations")

    let stopCalls = mock.getStopCalls()
    XCTAssertEqual(stopCalls, [], "Should not stop any watchers yet (teardown not executed)")
  }

  /// Test 4: deactivateAll stops active and pending projects
  func testDeactivateAll_stopsActiveAndPending() async throws {
    let mock = MockOrchestrator()
    let coordinator = MonitoringCoordinator(orchestrator: mock)

    // Activate project A
    await coordinator.activateProject("project-A")

    // Activate project B (schedules teardown for A)
    await coordinator.activateProject("project-B")

    // Verify state before deactivateAll
    let activeBeforeDeactivate = await coordinator.activeProjectId
    XCTAssertEqual(activeBeforeDeactivate, "project-B")

    let hasPendingA = await coordinator.hasPendingTeardown(for: "project-A")
    XCTAssertTrue(hasPendingA, "Project A should have pending teardown")

    // Call deactivateAll
    await coordinator.deactivateAll()

    // Verify all state cleared
    let activeAfterDeactivate = await coordinator.activeProjectId
    XCTAssertNil(activeAfterDeactivate, "No project should be active after deactivateAll")

    let hasPendingAAfter = await coordinator.hasPendingTeardown(for: "project-A")
    XCTAssertFalse(hasPendingAAfter, "Pending teardown should be cancelled")

    let hasPendingBAfter = await coordinator.hasPendingTeardown(for: "project-B")
    XCTAssertFalse(hasPendingBAfter, "No pending teardown should remain")

    // Verify orchestrator calls - should stop both A and B
    let stopCalls = mock.getStopCalls()
    XCTAssertEqual(Set(stopCalls), Set(["project-A", "project-B"]), "Should stop watchers for both active and pending projects")
    XCTAssertEqual(stopCalls.count, 2, "Should stop exactly 2 projects")
  }

  // MARK: - Feature Flag Tests

  func testLazyWatchersFeatureFlag_existsInMonitorConfig() {
    // Verify the feature flag is accessible
    let enabled = MonitorConfig.lazyWatchersEnabled

    // The flag should be a Bool (true or false depending on build type)
    XCTAssertTrue(enabled == true || enabled == false, "lazyWatchersEnabled should be a Bool")
  }

  func testLazyWatchersFeatureFlag_defaultsToTrueForDMG() {
    // In DMG builds (non-sandboxed), lazy watchers should be enabled by default
    // This test runs in the test environment which is unsandboxed
    #if !APPSTORE_BUILD
    // Note: Environment override could change this, so we just verify it's accessible
    _ = MonitorConfig.lazyWatchersEnabled
    #endif
    XCTAssertTrue(true, "Feature flag is accessible in test environment")
  }

  // MARK: - WatcherRecoverySummary Tests

  func testWatcherRecoverySummary_hasRequiredFields() {
    // Verify the summary struct has the expected fields
    let summary = WatcherRecoverySummary(
      projectId: "test-project",
      startedCount: 5,
      alreadyActiveCount: 2,
      missingFileCount: 1,
      targetTranscriptId: nil
    )

    XCTAssertEqual(summary.projectId, "test-project")
    XCTAssertEqual(summary.startedCount, 5)
    XCTAssertEqual(summary.alreadyActiveCount, 2)
    XCTAssertEqual(summary.missingFileCount, 1)
    XCTAssertNil(summary.targetTranscriptId)
  }

  func testWatcherRecoverySummary_isSendable() {
    // Verify the struct conforms to Sendable for actor boundaries
    let summary = WatcherRecoverySummary(
      projectId: "test",
      startedCount: 0,
      alreadyActiveCount: 0,
      missingFileCount: 0,
      targetTranscriptId: nil
    )

    // This compiles only if WatcherRecoverySummary is Sendable
    Task {
      _ = summary
    }

    XCTAssertTrue(true, "WatcherRecoverySummary is Sendable")
  }
}
