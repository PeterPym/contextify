import XCTest
@testable import Contextify

@MainActor
final class GitDetectionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedRoot()
    }

    override func tearDown() {
        clearPersistedRoot()
        super.tearDown()
    }

    func testBranchDetectionViaSetProjectRoot() throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate .git from test path: \(#filePath)")
            return
        }

        let model = HUDViewModel()
        XCTAssertTrue(model.setProjectRoot(url: repo))
        // updateGitInfo is called inside setProjectRoot; branch should be set synchronously on main
        XCTAssertFalse(model.branch.isEmpty, "Branch should not be empty")
        XCTAssertNotEqual(model.branch, "—", "Branch should be resolved, not placeholder")
        XCTAssertEqual(model.projectRootURL?.path, repo.path)
    }

    func testCwdDiscoveryPersistsRootAndBranch() throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let fm = FileManager.default
        let original = fm.currentDirectoryPath
        XCTAssertTrue(fm.changeCurrentDirectoryPath(repo.path))
        defer { _ = fm.changeCurrentDirectoryPath(original) }

        let model = HUDViewModel()
        model.updateGitInfo()

        XCTAssertEqual(model.projectRootURL?.path, repo.path)
        XCTAssertNotEqual(model.branch, "—")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dev.contextify.projectRoot"), repo.path)
        XCTAssertEqual(UserDefaults(suiteName: "dev.contextify")?.string(forKey: "dev.contextify.projectRoot"), repo.path)
    }

    func testEnvDiscoveryPersistsRoot() throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let model = HUDViewModel()
        model.updateGitInfo(env: ["CONTEXTIFY_PROJECT_ROOT": repo.path])

        XCTAssertEqual(model.projectRootURL?.path, repo.path)
        XCTAssertNotEqual(model.branch, "—")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dev.contextify.projectRoot"), repo.path)
        XCTAssertEqual(UserDefaults(suiteName: "dev.contextify")?.string(forKey: "dev.contextify.projectRoot"), repo.path)
    }
}

private func locateRepoRoot(from filePath: String = #filePath) -> URL? {
    var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
    let fm = FileManager.default
    for _ in 0..<12 { // safety limit
        let dotGit = dir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) { return dir }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { break }
        dir = parent
    }
    return nil
}

private func clearPersistedRoot() {
    let key = "dev.contextify.projectRoot"
    UserDefaults.standard.removeObject(forKey: key)
    UserDefaults(suiteName: "dev.contextify")?.removeObject(forKey: key)
}
