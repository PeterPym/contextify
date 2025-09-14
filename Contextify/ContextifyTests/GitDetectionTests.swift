import XCTest
@testable import Contextify

@MainActor
final class GitDetectionTests: XCTestCase {
    func testBranchDetectionViaSetProjectRoot() throws {
        // Walk up from current file location to repo root containing .git
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        var found: URL? = nil
        for _ in 0..<12 { // safety limit
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) { found = dir; break }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        guard let repo = found else {
            XCTFail("Could not locate .git from test path: \(#filePath)")
            return
        }

        let model = HUDViewModel()
        XCTAssertTrue(model.setProjectRoot(url: repo))
        // updateGitInfo is called inside setProjectRoot; branch should be set synchronously on main
        XCTAssertFalse(model.branch.isEmpty, "Branch should not be empty")
        XCTAssertNotEqual(model.branch, "—", "Branch should be resolved, not placeholder")
    }
}
