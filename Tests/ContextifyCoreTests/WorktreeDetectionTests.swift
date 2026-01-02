import XCTest
@testable import ContextifyCore

final class WorktreeDetectionTests: XCTestCase {

    func testCanonicalizePathExpandsTilde() {
        let config = WorktreeConfig(schemaVersion: 1, worktrees: [
            WorktreeEntry(name: "main", path: "~/code/test", archived: nil)
        ])
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(config.nameFor(path: "\(homeDir)/code/test"), "main")
    }

    func testWorktreeConfigIsArchived() {
        let config = WorktreeConfig(schemaVersion: 1, worktrees: [
            WorktreeEntry(name: "archived", path: "~/code/archived", archived: true),
            WorktreeEntry(name: "active", path: "~/code/active", archived: false)
        ])
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(config.isArchived(path: "\(homeDir)/code/archived"))
        XCTAssertFalse(config.isArchived(path: "\(homeDir)/code/active"))
    }

    func testWorktreeConfigDefaultNotArchived() {
        let config = WorktreeConfig(schemaVersion: 1, worktrees: [
            WorktreeEntry(name: "default", path: "~/code/default", archived: nil)
        ])
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(config.isArchived(path: "\(homeDir)/code/default"))
    }
}
