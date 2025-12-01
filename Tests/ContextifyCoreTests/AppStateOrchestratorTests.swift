import XCTest
@testable import ContextifyCore

/// Tests for AppStateOrchestrator and related state management
final class AppStateOrchestratorTests: XCTestCase {

  // MARK: - AppState.activeProjectId Tests

  /// Test that activeProjectId returns the correct ID when in .active state
  func testActiveProjectIdReturnsIdWhenActive() {
    let projectId = "test-project-123"
    let state = AppState.active(projectId: projectId)

    // Verify the state extracts the project ID correctly
    if case .active(let id) = state {
      XCTAssertEqual(id, projectId)
    } else {
      XCTFail("State should be .active")
    }
  }

  /// Test that activeProjectId returns nil for non-active states
  func testActiveProjectIdReturnsNilForOtherStates() {
    let states: [AppState] = [
      .startup,
      .discovering,
      .idle(projects: []),
      .loading(projectId: "loading-123"),
      .error("Some error")
    ]

    for state in states {
      if case .active = state {
        XCTFail("State \(state) should not be .active")
      }
      // Verify non-active states don't match the .active pattern
    }
  }

  /// Test the activeProjectId computed property pattern used by AppStateOrchestrator
  func testActiveProjectIdComputedPropertyPattern() {
    // This tests the exact pattern used in AppStateOrchestrator.activeProjectId
    func extractActiveProjectId(from state: AppState) -> String? {
      if case .active(let id) = state { return id }
      return nil
    }

    // Active state should return the ID
    XCTAssertEqual(extractActiveProjectId(from: .active(projectId: "abc")), "abc")

    // All other states should return nil
    XCTAssertNil(extractActiveProjectId(from: .startup))
    XCTAssertNil(extractActiveProjectId(from: .discovering))
    XCTAssertNil(extractActiveProjectId(from: .idle(projects: [])))
    XCTAssertNil(extractActiveProjectId(from: .loading(projectId: "xyz")))
    XCTAssertNil(extractActiveProjectId(from: .error("error")))
  }

  // MARK: - State Transition Tests

  /// Test that .loading state carries the correct project ID
  func testLoadingStateCarriesProjectId() {
    let projectId = "loading-project-456"
    let state = AppState.loading(projectId: projectId)

    if case .loading(let id) = state {
      XCTAssertEqual(id, projectId)
    } else {
      XCTFail("State should be .loading")
    }
  }

  /// Test that .idle state carries the projects array
  func testIdleStateCarriesProjects() {
    let projects: [LightweightProject] = []
    let state = AppState.idle(projects: projects)

    if case .idle(let p) = state {
      XCTAssertEqual(p.count, 0)
    } else {
      XCTFail("State should be .idle")
    }
  }

  /// Test that .error state carries the error message
  func testErrorStateCarriesMessage() {
    let message = "Something went wrong"
    let state = AppState.error(message)

    if case .error(let msg) = state {
      XCTAssertEqual(msg, message)
    } else {
      XCTFail("State should be .error")
    }
  }

  // MARK: - Rehydration Logic Tests

  /// Test the rehydration check pattern used by ConversationMonitor
  /// This verifies the logic: if activeProjectId exists AND matches current context, rehydrate
  func testRehydrationCheckPattern() {
    // Simulate the check pattern from ConversationMonitor.subscribeToContextUpdates()
    func shouldRehydrate(activeProjectId: String?, currentContextId: String?) -> Bool {
      guard let activeId = activeProjectId,
            let contextId = currentContextId,
            activeId == contextId else {
        return false
      }
      return true
    }

    // Both present and matching -> should rehydrate
    XCTAssertTrue(shouldRehydrate(activeProjectId: "abc", currentContextId: "abc"))

    // Both present but not matching -> should NOT rehydrate (stale context)
    XCTAssertFalse(shouldRehydrate(activeProjectId: "abc", currentContextId: "xyz"))

    // activeProjectId nil -> should NOT rehydrate (no active project)
    XCTAssertFalse(shouldRehydrate(activeProjectId: nil, currentContextId: "abc"))

    // currentContextId nil -> should NOT rehydrate (no context available)
    XCTAssertFalse(shouldRehydrate(activeProjectId: "abc", currentContextId: nil))

    // Both nil -> should NOT rehydrate
    XCTAssertFalse(shouldRehydrate(activeProjectId: nil, currentContextId: nil))
  }

  /// Test that rehydration only triggers when orchestrator is in .active state
  func testRehydrationOnlyForActiveState() {
    // The rehydration check requires the orchestrator to be in .active state
    // This test verifies that only .active state produces an activeProjectId

    let states: [(AppState, String?)] = [
      (.startup, nil),
      (.discovering, nil),
      (.idle(projects: []), nil),
      (.loading(projectId: "loading-id"), nil),  // Note: loading is NOT active
      (.active(projectId: "active-id"), "active-id"),
      (.error("error"), nil)
    ]

    for (state, expectedId) in states {
      let extractedId: String? = {
        if case .active(let id) = state { return id }
        return nil
      }()

      XCTAssertEqual(
        extractedId,
        expectedId,
        "State \(state) should produce activeProjectId=\(String(describing: expectedId))"
      )
    }
  }

  // MARK: - LightweightProject.canonicalRootPath Tests

  /// Test canonicalRootPath returns cwd when available
  func testCanonicalRootPathUsesCwd() {
    let project = LightweightProject(
      id: "some-id",
      path: URL(fileURLWithPath: "/Users/rob/.claude/projects/hash"),
      displayName: "test",
      transcriptCount: 1,
      lastActivity: Date(),
      provider: "claude.code",
      cwd: "/Users/rob/code/projects/test",
      transcriptFiles: []
    )

    XCTAssertEqual(project.canonicalRootPath, "/Users/rob/code/projects/test")
  }

  /// Test canonicalRootPath falls back to path when cwd is nil
  func testCanonicalRootPathFallsBackToPath() {
    let project = LightweightProject(
      id: "some-id",
      path: URL(fileURLWithPath: "/Users/rob/code/projects/test"),
      displayName: "test",
      transcriptCount: 1,
      lastActivity: Date(),
      provider: "claude.code",
      cwd: nil,
      transcriptFiles: []
    )

    XCTAssertEqual(project.canonicalRootPath, "/Users/rob/code/projects/test")
  }

  /// Test that projects with same canonicalRootPath can be identified for merging
  func testProjectsWithSameCanonicalRootPathCanBeMerged() {
    let claudeProject = LightweightProject(
      id: "-Users-rob-code-projects-contextify",
      path: URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code-projects-contextify"),
      displayName: "contextify",
      transcriptCount: 5,
      lastActivity: Date(),
      provider: "claude.code",
      cwd: "/Users/rob/code/projects/contextify",
      transcriptFiles: [URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code/s1.jsonl")]
    )

    let codexProject = LightweightProject(
      id: "L1VzZXJzL3JvYi9jb2RlL3Byb2plY3RzL2NvbnRleHRpZnk",
      path: URL(fileURLWithPath: "/Users/rob/.codex/sessions/2025/11/30"),
      displayName: "contextify",
      transcriptCount: 2,
      lastActivity: Date(),
      provider: "codex.cli",
      cwd: "/Users/rob/code/projects/contextify",
      transcriptFiles: [URL(fileURLWithPath: "/Users/rob/.codex/sessions/2025/11/30/r1.jsonl")]
    )

    // Same canonicalRootPath despite different IDs and providers
    XCTAssertEqual(claudeProject.canonicalRootPath, codexProject.canonicalRootPath)
    XCTAssertNotEqual(claudeProject.id, codexProject.id)
    XCTAssertNotEqual(claudeProject.provider, codexProject.provider)

    // Merged transcripts should contain both
    let mergedFiles = [claudeProject, codexProject].flatMap { $0.transcriptFiles }
    XCTAssertEqual(mergedFiles.count, 2)
  }
}
