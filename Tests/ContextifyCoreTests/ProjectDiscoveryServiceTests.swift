import XCTest
import GRDB
@testable import ContextifyCore

final class ProjectDiscoveryServiceTests: XCTestCase {

  var tempDir: URL!
  var dbManager: DatabaseManager!
  var service: ProjectDiscoveryService!

  override func setUp() async throws {
    try await super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ProjectDiscoveryServiceTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Create test database using the standard testing pattern
    let dbPath = tempDir.appendingPathComponent("test.db")
    dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)

    // Create orchestrator and service
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    service = ProjectDiscoveryService(
      db: try dbManager.pool,
      orchestrator: orchestrator,
      folderAccessController: nil
    )
  }

  override func tearDown() async throws {
    service = nil
    dbManager = nil
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
    try await super.tearDown()
  }

  // MARK: - Helper Methods

  /// Creates a fake Claude transcript directory with a JSONL file containing the specified content
  private func createTranscriptDir(name: String, jsonContent: String) throws -> URL {
    let claudeDir = tempDir.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

    let transcriptPath = claudeDir.appendingPathComponent("test-session.jsonl")
    try jsonContent.write(to: transcriptPath, atomically: true, encoding: .utf8)

    return claudeDir
  }

  /// Creates a project directory that exists on disk
  private func createProjectDir(name: String) throws -> URL {
    let projectDir = tempDir.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    return projectDir
  }

  // MARK: - reversePathMapping Tests

  func testReversePathMapping_CwdLike_DirectoryExists() throws {
    // Given: A transcript with cwd pointing to an existing directory
    let projectDir = try createProjectDir(name: "my-project")
    let claudeDir = try createTranscriptDir(
      name: "-Users-test-my-project",
      jsonContent: """
        {"cwd":"\(projectDir.path)","timestamp":"2025-01-01T00:00:00Z"}
        """
    )

    // When: Resolving the path
    let result = service.reversePathMapping(dirURL: claudeDir)

    // Then: Should return the existing project path
    XCTAssertEqual(result?.path, projectDir.path)
  }

  func testReversePathMapping_CwdLike_DirectoryMissing_ReturnsNil() throws {
    // Given: A transcript with cwd pointing to a non-existent directory (orphaned project)
    let missingPath = tempDir.appendingPathComponent("deleted-project").path
    let claudeDir = try createTranscriptDir(
      name: "-Users-test-deleted-project",
      jsonContent: """
        {"cwd":"\(missingPath)","timestamp":"2025-01-01T00:00:00Z"}
        """
    )

    // When: Resolving the path
    let result = service.reversePathMapping(dirURL: claudeDir)

    // Then: Should return nil (orphan detected, no parent traversal)
    XCTAssertNil(result, "Orphaned cwd should return nil, not traverse to parent")
  }

  func testReversePathMapping_FileLike_DirectoryPath() throws {
    // Given: A transcript with "path" field pointing to an existing directory
    let projectDir = try createProjectDir(name: "file-project")
    let claudeDir = try createTranscriptDir(
      name: "-Users-test-file-project",
      jsonContent: """
        {"path":"\(projectDir.path)","timestamp":"2025-01-01T00:00:00Z"}
        """
    )

    // When: Resolving the path
    let result = service.reversePathMapping(dirURL: claudeDir)

    // Then: Should return the directory path
    XCTAssertEqual(result?.path, projectDir.path)
  }

  func testReversePathMapping_FileLike_FilePathWithExistingParent() throws {
    // Given: A transcript with "file" field pointing to a file, parent directory exists
    let projectDir = try createProjectDir(name: "parent-project")
    let srcDir = projectDir.appendingPathComponent("src")
    try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

    // Create an actual file
    let filePath = srcDir.appendingPathComponent("main.py")
    try "# test".write(to: filePath, atomically: true, encoding: .utf8)

    let claudeDir = try createTranscriptDir(
      name: "-Users-test-parent-project",
      jsonContent: """
        {"file":"\(filePath.path)","timestamp":"2025-01-01T00:00:00Z"}
        """
    )

    // When: Resolving the path
    let result = service.reversePathMapping(dirURL: claudeDir)

    // Then: Should traverse up to find project directory (src or parent-project)
    XCTAssertNotNil(result)
    // The parent traversal should find either src or parent-project
    XCTAssertTrue(
      result!.path == srcDir.path || result!.path == projectDir.path,
      "Expected \(srcDir.path) or \(projectDir.path), got \(result!.path)"
    )
  }

  func testReversePathMapping_MixedHints_CwdTakesPrecedence() throws {
    // Given: A transcript with both cwd (missing) and file (valid) - cwd should win
    let existingDir = try createProjectDir(name: "existing-project")
    let missingCwd = tempDir.appendingPathComponent("missing-cwd-project").path

    let claudeDir = try createTranscriptDir(
      name: "-Users-test-mixed",
      jsonContent: """
        {"cwd":"\(missingCwd)","file":"\(existingDir.path)/src/main.py","timestamp":"2025-01-01T00:00:00Z"}
        """
    )

    // When: Resolving the path
    let result = service.reversePathMapping(dirURL: claudeDir)

    // Then: Should return nil because cwd is authoritative and missing
    XCTAssertNil(result, "cwd should be authoritative - missing cwd means orphan even if file hint exists")
  }

  func testReversePathMapping_NoJsonPatterns_UsesFallback() throws {
    // Given: A transcript with no cwd/path/file patterns (should fall back to reverseManglePath)
    // Note: This test verifies the fallback is attempted, though it may fail for invalid paths
    let claudeDir = try createTranscriptDir(
      name: "-tmp-some-project",
      jsonContent: """
        {"message":"no path hints here","timestamp":"2025-01-01T00:00:00Z"}
        """
    )

    // When: Resolving the path
    let result = service.reversePathMapping(dirURL: claudeDir)

    // Then: Result depends on whether reverseManglePath can handle this
    // The key behavior is that it doesn't crash and tries the fallback
    // For this test case, the fallback path /tmp/some/project likely doesn't exist
    // so we expect nil, but the important thing is no crash
    XCTAssertNil(result, "Fallback to non-existent demangled path should return nil")
  }

  func testReversePathMapping_NoJsonlFiles_ReturnsNil() throws {
    // Given: A transcript directory with no JSONL files
    let emptyDir = tempDir.appendingPathComponent("-Users-test-empty")
    try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

    // When: Resolving the path
    let result = service.reversePathMapping(dirURL: emptyDir)

    // Then: Should return nil gracefully
    XCTAssertNil(result)
  }

  // MARK: - Duplicate Key Prevention Tests

  func testDuplicateProjectPaths_DoNotCrash() throws {
    // This test documents the behavior that prevents crashes when multiple
    // transcript directories resolve to the same project path.
    //
    // The fix uses Dictionary(_:uniquingKeysWith:) with max to handle duplicates.
    //
    // We can't easily test quickDiscoverNewest() without a full orchestrator setup,
    // but we verify the dictionary merging logic works correctly.

    let date1 = Date(timeIntervalSince1970: 1000)
    let date2 = Date(timeIntervalSince1970: 2000)
    let date3 = Date(timeIntervalSince1970: 1500)

    // Simulate what quickDiscoverNewest does: build a dictionary from candidates
    let candidates: [(path: String, mtime: Date)] = [
      ("/Users/rob/code", date1),
      ("/Users/rob/code", date2),  // Duplicate path, newer mtime
      ("/Users/rob/code", date3),  // Duplicate path, middle mtime
      ("/Users/rob/other", date1),
    ]

    // This should NOT crash (unlike Dictionary(uniqueKeysWithValues:))
    let baseline = Dictionary(candidates.map { ($0.path, $0.mtime) }, uniquingKeysWith: max)

    // Should keep the max mtime for duplicates
    XCTAssertEqual(baseline["/Users/rob/code"], date2)
    XCTAssertEqual(baseline["/Users/rob/other"], date1)
    XCTAssertEqual(baseline.count, 2)
  }
}
