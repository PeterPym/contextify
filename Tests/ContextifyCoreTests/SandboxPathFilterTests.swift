import XCTest
@testable import ContextifyCore

final class SandboxPathFilterTests: XCTestCase {

    // MARK: - isSandboxContainerPath Tests

    func testContainerPath_exactDataDirectory_returnsTrue() {
        let path = "/Users/test/Library/Containers/sh.contextify.Contextify/Data"
        XCTAssertTrue(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testContainerPath_subdirectoryOfData_returnsTrue() {
        let path = "/Users/test/Library/Containers/sh.contextify.Contextify/Data/Documents/Project"
        XCTAssertTrue(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testContainerPath_libraryPreferences_returnsTrue() {
        let path = "/Users/test/Library/Containers/sh.contextify.Contextify/Data/Library/Preferences"
        XCTAssertTrue(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testContainerPath_differentBundleId_returnsTrue() {
        // Any app's container should be filtered, not just ours
        let path = "/Users/test/Library/Containers/com.apple.Safari/Data"
        XCTAssertTrue(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testContainerPath_withDotDotSegments_returnsTrue() {
        // Path that normalizes to container path
        let path = "/Users/test/Library/Containers/sh.contextify.Contextify/Data/../Data/Documents"
        XCTAssertTrue(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testNormalPath_userProjects_returnsFalse() {
        let path = "/Users/test/Projects/my-app"
        XCTAssertFalse(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testNormalPath_applicationSupport_returnsFalse() {
        let path = "/Users/test/Library/Application Support/Contextify"
        XCTAssertFalse(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testNormalPath_homeDirectory_returnsFalse() {
        let path = "/Users/test"
        XCTAssertFalse(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testNormalPath_tmpDirectory_returnsFalse() {
        let path = "/tmp/test-project"
        XCTAssertFalse(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testNormalPath_containsContainersButNotPattern_returnsFalse() {
        // Has "Containers" in path but not the full pattern
        let path = "/Users/test/Projects/Containers/MyApp"
        XCTAssertFalse(SandboxPathFilter.isSandboxContainerPath(path))
    }

    func testContainerPath_missingDataComponent_returnsFalse() {
        // Container path without Data subdirectory
        let path = "/Users/test/Library/Containers/sh.contextify.Contextify"
        XCTAssertFalse(SandboxPathFilter.isSandboxContainerPath(path))
    }

    // MARK: - sanitizedPath Tests

    func testSanitizedPath_normalPath_returnsPath() {
        let path = "/Users/test/Projects/my-app"
        XCTAssertEqual(SandboxPathFilter.sanitizedPath(path), path)
    }

    func testSanitizedPath_containerPath_returnsNil() {
        let path = "/Users/test/Library/Containers/sh.contextify.Contextify/Data"
        XCTAssertNil(SandboxPathFilter.sanitizedPath(path))
    }

    func testSanitizedPath_nilInput_returnsNil() {
        XCTAssertNil(SandboxPathFilter.sanitizedPath(nil))
    }
}
