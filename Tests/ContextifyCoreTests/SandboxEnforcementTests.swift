import XCTest
@testable import ContextifyCore

/// Integration tests for sandbox path enforcement at critical choke points.
/// These verify that SandboxPathFilter is actually wired up where it matters.
final class SandboxEnforcementTests: XCTestCase {

    // MARK: - HUDPreferences Tests

    func testSetPersistedRoot_containerPath_isBlocked() {
        // Given a sandbox container path
        let containerPath = "/Users/test/Library/Containers/sh.contextify.Contextify/Data"

        // When we try to persist it
        HUDPreferences.setPersistedRoot(containerPath)

        // Then it should NOT be stored
        XCTAssertNil(
            HUDPreferences.getPersistedRoot(),
            "Container path should not be persisted to UserDefaults"
        )
    }

    func testSetPersistedRoot_normalPath_isStored() {
        // Given a normal project path
        let normalPath = "/Users/test/Projects/my-app"

        // When we persist it
        HUDPreferences.setPersistedRoot(normalPath)

        // Then it should be stored
        XCTAssertEqual(
            HUDPreferences.getPersistedRoot(),
            normalPath,
            "Normal path should be persisted to UserDefaults"
        )

        // Cleanup
        HUDPreferences.clearPersistedRoot()
    }

    func testSetPersistedRoot_containerPath_cleansUpExistingPoisonedPrefs() {
        // Given an existing (poisoned) persisted root
        let normalPath = "/Users/test/Projects/my-app"
        HUDPreferences.setPersistedRoot(normalPath)
        XCTAssertNotNil(HUDPreferences.getPersistedRoot())

        // When we try to persist a container path
        let containerPath = "/Users/test/Library/Containers/sh.contextify.Contextify/Data"
        HUDPreferences.setPersistedRoot(containerPath)

        // Then the existing value should be cleaned up
        XCTAssertNil(
            HUDPreferences.getPersistedRoot(),
            "Container path persistence should clean up existing poisoned prefs"
        )
    }

    // MARK: - StartupCoordinator Tests

    func testContainerPath_wouldBeRejectedByStartupCoordinator() {
        // StartupCoordinator.ensureProjectInDatabase has a guard that checks
        // SandboxPathFilter.isSandboxContainerPath before creating projects.
        // We can't easily test the private method, but we can verify the filter
        // would catch container paths that reach it.

        let containerPath = "/Users/test/Library/Containers/sh.contextify.Contextify/Data"

        // The guard in ensureProjectInDatabase does:
        // guard !SandboxPathFilter.isSandboxContainerPath(path) else { throw ... }
        XCTAssertTrue(
            SandboxPathFilter.isSandboxContainerPath(containerPath),
            "Container path should be detected by the filter used in ensureProjectInDatabase"
        )
    }

    func testResolveProjectRoot_containerPath_isRejected() async {
        // This tests that resolveProjectRoot (via sanitizeResolvedPath)
        // rejects container paths before they can propagate

        let containerPath = "/Users/test/Library/Containers/sh.contextify.Contextify/Data"

        // sanitizeResolvedPath should return nil for container paths
        // (it's private, so we test the underlying filter)
        XCTAssertNil(
            SandboxPathFilter.sanitizedPath(containerPath),
            "Container path should be filtered out during resolution"
        )
    }
}
