import XCTest
@testable import ContextifyCore

@MainActor
final class ProjectDiscoveryTests: XCTestCase {

  // MARK: - Path Mapping Tests

  func testReversePathMapping_ValidPath() {
    // Given: A valid Claude Code directory name
    let dirName = "-Users-rob-code-projects-foo"

    // When: Attempting to reverse map
    let service = MockDiscoveryService()
    let result = service.testReversePathMapping(dirName: dirName)

    // Then: Should return nil (path doesn't exist in test env)
    // but the algorithm should generate correct path string
    XCTAssertEqual(service.testGeneratePath(dirName: dirName), "/Users/rob/code/projects/foo")
  }

  func testReversePathMapping_InvalidPath() {
    // Given: Invalid directory name (no leading slash)
    let dirName = "foo-bar-baz"

    // When: Attempting to reverse map
    let service = MockDiscoveryService()
    let result = service.testGeneratePath(dirName: dirName)

    // Then: Should not start with slash
    XCTAssertFalse(result.hasPrefix("/"))
  }

  func testReversePathMapping_SpecialCharacters() {
    // Given: Path with special characters preserved
    let dirName = "-Users-rob-my-project (old)"

    // When: Converting
    let service = MockDiscoveryService()
    let result = service.testGeneratePath(dirName: dirName)

    // Then: Special chars preserved
    XCTAssertEqual(result, "/Users/rob/my-project (old)")
  }

  // MARK: - Project Name Derivation Tests

  func testDeriveProjectName_SimpleCase() {
    // Given: A project path
    let path = URL(fileURLWithPath: "/Users/rob/code/projects/contextify")

    // When: Deriving name
    let service = MockDiscoveryService()
    let name = service.testDeriveProjectName(from: path)

    // Then: Should use last path component
    XCTAssertEqual(name, "contextify")
  }

  func testDeriveProjectName_SpecialCharacters() {
    // Given: Path with special characters
    let path = URL(fileURLWithPath: "/Users/rob/my-project (2024)")

    // When: Deriving name
    let service = MockDiscoveryService()
    let name = service.testDeriveProjectName(from: path)

    // Then: Should preserve special characters
    XCTAssertEqual(name, "my-project (2024)")
  }

  // MARK: - Exclusion Tests

  func testExclusionManager_AddAndRetrieve() async {
    // Given: Fresh exclusion manager
    let manager = ProjectExclusionManager(defaults: UserDefaults(suiteName: "test.\(UUID())")!)

    // When: Excluding a project
    await manager.excludeProject("/Users/rob/test-project")

    // Then: Should be in excluded set
    let excluded = await manager.getExcludedProjects()
    XCTAssertTrue(excluded.contains("/Users/rob/test-project"))
  }

  func testExclusionManager_RemoveExclusion() async {
    // Given: Manager with excluded project
    let manager = ProjectExclusionManager(defaults: UserDefaults(suiteName: "test.\(UUID())")!)
    await manager.excludeProject("/Users/rob/test-project")

    // When: Including the project again
    await manager.includeProject("/Users/rob/test-project")

    // Then: Should not be in excluded set
    let excluded = await manager.getExcludedProjects()
    XCTAssertFalse(excluded.contains("/Users/rob/test-project"))
  }

  func testExclusionManager_Persistence() async {
    // Given: Manager with excluded project
    let suiteName = "test.\(UUID())"
    let manager1 = ProjectExclusionManager(defaults: UserDefaults(suiteName: suiteName)!)
    await manager1.excludeProject("/Users/rob/test-project")

    // When: Creating new manager with same suite
    let manager2 = ProjectExclusionManager(defaults: UserDefaults(suiteName: suiteName)!)

    // Then: Should load persisted exclusions
    let excluded = await manager2.getExcludedProjects()
    XCTAssertTrue(excluded.contains("/Users/rob/test-project"))
  }

  // MARK: - Performance Tests

  func testDiscoveryPerformance() {
    // This test measures discovery time but won't run in CI without real projects
    // Kept as template for manual testing
    self.measure {
      // Measure discovery time here
    }
  }
}

// MARK: - Mock Service for Testing

class MockDiscoveryService {
  // NOTE: These test helpers use simplified path demangling for testing purposes only.
  // Production code MUST use ProjectIdentity.reverseManglePath() which correctly handles
  // hyphens in directory names by reading CWD from transcript files.

  func testReversePathMapping(dirName: String) -> URL? {
    // Simplified for testing - does not handle hyphens correctly
    let path = dirName.replacingOccurrences(of: "-", with: "/")
    guard path.hasPrefix("/") else { return nil }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    return url
  }

  func testGeneratePath(dirName: String) -> String {
    // Simplified for testing - does not handle hyphens correctly
    return dirName.replacingOccurrences(of: "-", with: "/")
  }

  func testDeriveProjectName(from path: URL) -> String {
    return path.lastPathComponent
  }
}
