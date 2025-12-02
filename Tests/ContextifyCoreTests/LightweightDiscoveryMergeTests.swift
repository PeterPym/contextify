import XCTest
@testable import ContextifyCore

final class LightweightDiscoveryMergeTests: XCTestCase {

  var service: LightweightDiscoveryService!

  override func setUp() async throws {
    try await super.setUp()
    service = LightweightDiscoveryService()
  }

  override func tearDown() async throws {
    service = nil
    try await super.tearDown()
  }

  // MARK: - Multi-Provider Merge Tests

  /// Test: Claude + Codex projects with same canonical path merge into single "multi" provider
  func testMultiProviderMerge_SamePath_MergesIntoMulti() {
    // Arrange: 1 Claude project and 1 Codex project pointing to same canonical path
    let canonicalPath = "/Users/rob/code/my-project"
    let now = Date()

    let claudeProject = LightweightProject(
      id: "-Users-rob-code-my-project",
      path: URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code-my-project"),
      displayName: "my-project",
      transcriptCount: 3,
      lastActivity: now.addingTimeInterval(-3600),  // 1 hour ago
      provider: "claude.code",
      cwd: canonicalPath,
      transcriptFiles: [
        URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code-my-project/session1.jsonl"),
        URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code-my-project/session2.jsonl"),
        URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code-my-project/session3.jsonl"),
      ]
    )

    let codexProject = LightweightProject(
      id: "L1VzZXJzL3JvYi9jb2RlL215LXByb2plY3Q",  // base64 of /Users/rob/code/my-project
      path: URL(fileURLWithPath: canonicalPath),
      displayName: "my-project",
      transcriptCount: 2,
      lastActivity: now,  // More recent
      provider: "codex.cli",
      cwd: canonicalPath,
      transcriptFiles: [
        URL(fileURLWithPath: "/Users/rob/.codex/sessions/2025/01/01/session-a.jsonl"),
        URL(fileURLWithPath: "/Users/rob/.codex/sessions/2025/01/02/session-b.jsonl"),
      ]
    )

    // Act
    let result = service.mergeByCanonicalPath([claudeProject, codexProject])

    // Assert
    XCTAssertEqual(result.count, 1, "Should merge into single project")

    let merged = result[0]
    XCTAssertEqual(merged.provider, "multi", "Provider should be 'multi' after merge")
    XCTAssertEqual(merged.transcriptCount, 5, "Transcript count should be sum of both (3 + 2)")
    XCTAssertEqual(merged.transcriptFiles.count, 5, "Should contain files from both providers")
    XCTAssertEqual(merged.canonicalRootPath, canonicalPath, "Canonical path should remain stable")
    XCTAssertEqual(merged.lastActivity, now, "Should keep most recent activity date")
    XCTAssertEqual(merged.cwd, canonicalPath, "CWD should be preserved")

    // Verify transcript files contain both Claude and Codex files
    let claudeFiles = merged.transcriptFiles.filter { $0.path.contains(".claude") }
    let codexFiles = merged.transcriptFiles.filter { $0.path.contains(".codex") }
    XCTAssertEqual(claudeFiles.count, 3, "Should contain 3 Claude files")
    XCTAssertEqual(codexFiles.count, 2, "Should contain 2 Codex files")
  }

  /// Test: Projects with different canonical paths should NOT merge
  func testSingleProviderStability_DifferentPaths_NoMerge() {
    // Arrange: 2 Claude projects with DIFFERENT canonical roots
    let now = Date()

    let projectA = LightweightProject(
      id: "-Users-rob-code-project-a",
      path: URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code-project-a"),
      displayName: "project-a",
      transcriptCount: 2,
      lastActivity: now,
      provider: "claude.code",
      cwd: "/Users/rob/code/project-a",
      transcriptFiles: [
        URL(fileURLWithPath: "/path/a1.jsonl"),
        URL(fileURLWithPath: "/path/a2.jsonl"),
      ]
    )

    let projectB = LightweightProject(
      id: "-Users-rob-code-project-b",
      path: URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code-project-b"),
      displayName: "project-b",
      transcriptCount: 1,
      lastActivity: now.addingTimeInterval(-7200),
      provider: "claude.code",
      cwd: "/Users/rob/code/project-b",
      transcriptFiles: [
        URL(fileURLWithPath: "/path/b1.jsonl"),
      ]
    )

    // Act
    let result = service.mergeByCanonicalPath([projectA, projectB])

    // Assert
    XCTAssertEqual(result.count, 2, "Should NOT merge projects with different paths")

    // Both should remain separate with original properties
    let sortedResult = result.sorted { $0.displayName < $1.displayName }
    XCTAssertEqual(sortedResult[0].displayName, "project-a")
    XCTAssertEqual(sortedResult[0].provider, "claude.code")
    XCTAssertEqual(sortedResult[0].transcriptCount, 2)
    XCTAssertEqual(sortedResult[1].displayName, "project-b")
    XCTAssertEqual(sortedResult[1].provider, "claude.code")
    XCTAssertEqual(sortedResult[1].transcriptCount, 1)
  }

  /// Test: Projects where cwd == nil vs cwd != nil should not incorrectly merge
  /// (Different canonicalRootPath means different projects)
  func testOrphanCase_DifferentCanonicalPaths_NoMerge() {
    // Arrange: One project with cwd, one "orphan" project without cwd
    // The orphan uses path.path as canonicalRootPath instead of cwd
    let now = Date()

    // Project with real cwd
    let projectWithCwd = LightweightProject(
      id: "-Users-rob-code-real-project",
      path: URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-rob-code-real-project"),
      displayName: "real-project",
      transcriptCount: 2,
      lastActivity: now,
      provider: "claude.code",
      cwd: "/Users/rob/code/real-project",  // Has cwd
      transcriptFiles: []
    )

    // Orphan project (cwd is nil, uses hash folder path as canonical)
    let orphanProject = LightweightProject(
      id: "-Users-deleted-project",
      path: URL(fileURLWithPath: "/Users/rob/.claude/projects/-Users-deleted-project"),
      displayName: "deleted-project",
      transcriptCount: 1,
      lastActivity: now.addingTimeInterval(-86400),
      provider: "claude.code",
      cwd: nil,  // Orphan - no cwd
      transcriptFiles: []
    )

    // Act
    let result = service.mergeByCanonicalPath([projectWithCwd, orphanProject])

    // Assert: Different canonical paths means no merge
    XCTAssertEqual(result.count, 2, "Orphan and non-orphan should NOT merge (different canonical paths)")

    // Verify canonical paths are indeed different
    XCTAssertEqual(projectWithCwd.canonicalRootPath, "/Users/rob/code/real-project")
    XCTAssertEqual(orphanProject.canonicalRootPath, "/Users/rob/.claude/projects/-Users-deleted-project")
    XCTAssertNotEqual(projectWithCwd.canonicalRootPath, orphanProject.canonicalRootPath)
  }

  /// Test: Three-way merge scenario (Claude + Codex + another Codex session)
  func testThreeWayMerge_AllSamePath_MergesIntoOne() {
    // Arrange: Multiple providers/sessions for same canonical path
    let canonicalPath = "/Users/rob/code/shared-project"
    let now = Date()

    let claude = LightweightProject(
      id: "claude-hash",
      path: URL(fileURLWithPath: "/path/claude"),
      displayName: "shared-project",
      transcriptCount: 1,
      lastActivity: now.addingTimeInterval(-7200),
      provider: "claude.code",
      cwd: canonicalPath,
      transcriptFiles: [URL(fileURLWithPath: "/claude/s1.jsonl")]
    )

    let codex1 = LightweightProject(
      id: "codex-hash-1",
      path: URL(fileURLWithPath: canonicalPath),
      displayName: "shared-project",
      transcriptCount: 2,
      lastActivity: now.addingTimeInterval(-3600),
      provider: "codex.cli",
      cwd: canonicalPath,
      transcriptFiles: [
        URL(fileURLWithPath: "/codex/s1.jsonl"),
        URL(fileURLWithPath: "/codex/s2.jsonl"),
      ]
    )

    // Note: In practice this wouldn't happen (Codex aggregates by cwd), but test the merge logic
    let codex2 = LightweightProject(
      id: "codex-hash-2",
      path: URL(fileURLWithPath: canonicalPath),
      displayName: "shared-project",
      transcriptCount: 1,
      lastActivity: now,  // Most recent
      provider: "codex.cli",
      cwd: canonicalPath,
      transcriptFiles: [URL(fileURLWithPath: "/codex/s3.jsonl")]
    )

    // Act
    let result = service.mergeByCanonicalPath([claude, codex1, codex2])

    // Assert
    XCTAssertEqual(result.count, 1, "All three should merge into one")

    let merged = result[0]
    XCTAssertEqual(merged.provider, "multi", "Should be 'multi' provider")
    XCTAssertEqual(merged.transcriptCount, 4, "Should sum all transcripts (1 + 2 + 1)")
    XCTAssertEqual(merged.lastActivity, now, "Should keep most recent activity")
  }

  /// Test: Same provider, same path - should merge but NOT become "multi"
  func testSameProviderSamePath_MergesButNotMulti() {
    // Arrange: Two Claude projects that somehow have the same canonical path
    // (This could happen with symlinks or path normalization edge cases)
    let canonicalPath = "/Users/rob/code/project"
    let now = Date()

    let project1 = LightweightProject(
      id: "hash-1",
      path: URL(fileURLWithPath: "/path/1"),
      displayName: "project",
      transcriptCount: 2,
      lastActivity: now.addingTimeInterval(-3600),
      provider: "claude.code",
      cwd: canonicalPath,
      transcriptFiles: [
        URL(fileURLWithPath: "/p1.jsonl"),
        URL(fileURLWithPath: "/p2.jsonl"),
      ]
    )

    let project2 = LightweightProject(
      id: "hash-2",
      path: URL(fileURLWithPath: "/path/2"),
      displayName: "project",
      transcriptCount: 1,
      lastActivity: now,
      provider: "claude.code",  // Same provider
      cwd: canonicalPath,
      transcriptFiles: [URL(fileURLWithPath: "/p3.jsonl")]
    )

    // Act
    let result = service.mergeByCanonicalPath([project1, project2])

    // Assert
    XCTAssertEqual(result.count, 1, "Should merge into one")

    let merged = result[0]
    XCTAssertEqual(merged.provider, "claude.code", "Same provider should NOT become 'multi'")
    XCTAssertEqual(merged.transcriptCount, 3, "Should combine transcripts")
  }

  /// Test: Empty input returns empty output
  func testEmptyInput_ReturnsEmpty() {
    let result = service.mergeByCanonicalPath([])
    XCTAssertTrue(result.isEmpty, "Empty input should return empty output")
  }

  /// Test: Single project passes through unchanged
  func testSingleProject_PassesThrough() {
    let project = LightweightProject(
      id: "single",
      path: URL(fileURLWithPath: "/path"),
      displayName: "single-project",
      transcriptCount: 5,
      lastActivity: Date(),
      provider: "claude.code",
      cwd: "/Users/rob/single",
      transcriptFiles: []
    )

    let result = service.mergeByCanonicalPath([project])

    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].id, "single")
    XCTAssertEqual(result[0].transcriptCount, 5)
    XCTAssertEqual(result[0].provider, "claude.code")
  }
}
