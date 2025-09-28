import XCTest
@testable import Contextify

@MainActor
final class GitDetectionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedRoot()
        HUDPreferences.setAutoPersist(true)
    }

    override func tearDown() {
        clearPersistedRoot()
        HUDPreferences.setAutoPersist(true)
        super.tearDown()
    }

    func testBranchDetectionViaSetProjectRoot() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate .git from test path: \(#filePath)")
            return
        }

        let model = HUDViewModel()
        switch model.setProjectRoot(url: repo) {
        case .success(let detected):
            XCTAssertEqual(detected.path, repo.resolvingSymlinksInPath().path)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        try await waitForCondition("Branch should resolve via setProjectRoot") {
            model.branchDisplay != "—"
        }
        XCTAssertEqual(model.projectRootURL?.path, repo.resolvingSymlinksInPath().path)
        XCTAssertEqual(HUDPreferences.getPersistedRoot(), repo.resolvingSymlinksInPath().path)
    }

    func testCwdDiscoveryPersistsRootAndBranch() async throws {
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

        try await waitForCondition("CWD discovery should detect repo") {
            model.projectRootURL?.path == repo.resolvingSymlinksInPath().path
        }
        XCTAssertNotEqual(model.branchDisplay, "—")
        XCTAssertEqual(HUDPreferences.getPersistedRoot(), repo.resolvingSymlinksInPath().path)
        if let suite = UserDefaults(suiteName: "dev.contextify") {
            XCTAssertEqual(suite.string(forKey: HUDPreferences.projectRootKey), repo.resolvingSymlinksInPath().path)
        }
    }

    func testEnvDiscoveryPersistsRoot() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let model = HUDViewModel()
        model.updateGitInfo(env: ["CONTEXTIFY_PROJECT_ROOT": repo.path])

        try await waitForCondition("Env discovery should detect repo") {
            model.projectRootURL?.path == repo.resolvingSymlinksInPath().path
        }
        XCTAssertNotEqual(model.branchDisplay, "—")
        XCTAssertEqual(HUDPreferences.getPersistedRoot(), repo.resolvingSymlinksInPath().path)
        if let suite = UserDefaults(suiteName: "dev.contextify") {
            XCTAssertEqual(suite.string(forKey: HUDPreferences.projectRootKey), repo.resolvingSymlinksInPath().path)
        }
    }

    func testEnvInvalidPathDoesNotPersist() async throws {
        let model = HUDViewModel()
        model.updateGitInfo(env: ["CONTEXTIFY_PROJECT_ROOT": "/tmp/definitely/not/a/repo"])
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(model.projectRootURL)
        XCTAssertNil(HUDPreferences.getPersistedRoot())
        XCTAssertNil(UserDefaults.standard.string(forKey: HUDPreferences.projectRootKey))
    }

    func testEnvironmentOverridesPersistedRoot() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let dotGit = temp.appendingPathComponent(".git", isDirectory: true)
        try fm.createDirectory(at: dotGit, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: dotGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let refsHeads = dotGit.appendingPathComponent("refs/heads", isDirectory: true)
        try fm.createDirectory(at: refsHeads, withIntermediateDirectories: true)
        try "0123456".write(to: refsHeads.appendingPathComponent("main"), atomically: true, encoding: .utf8)

        clearPersistedRoot()
        HUDPreferences.setPersistedRoot(temp)

        let model = HUDViewModel()
        model.updateGitInfo(env: ["CONTEXTIFY_PROJECT_ROOT": repo.path])

        try await waitForCondition("Environment variable should override persisted root") {
            model.projectRootURL?.path == repo.resolvingSymlinksInPath().path
        }
        XCTAssertEqual(model.projectRootURL?.path, repo.resolvingSymlinksInPath().path)
        XCTAssertEqual(HUDPreferences.getPersistedRoot(), repo.resolvingSymlinksInPath().path)
    }

    func testResolveGitDirHandlesGitFile() throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let gitFile = temp.appendingPathComponent(".git")
        let gitDirPath = repo.appendingPathComponent(".git").path
        try "gitdir: \(gitDirPath)\n".write(to: gitFile, atomically: true, encoding: .utf8)
        let resolved = GitRepositoryResolver.resolveGitDir(for: temp)
        XCTAssertEqual(resolved?.path, gitDirPath)
    }

    func testAutoPersistDisabledSkipsPersistence() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        HUDPreferences.setAutoPersist(false)
        let model = HUDViewModel()
        model.updateGitInfo(env: ["CONTEXTIFY_PROJECT_ROOT": repo.path])
        try await waitForCondition("Env detection should still resolve root") {
            model.projectRootURL?.path == repo.resolvingSymlinksInPath().path
        }
        XCTAssertNil(HUDPreferences.getPersistedRoot())
    }

    func testCanonicalPathIsPersisted() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let symlink = temp.appendingPathComponent("link", isDirectory: true)
        try fm.createSymbolicLink(at: symlink, withDestinationURL: repo)

        let model = HUDViewModel()
        switch model.setProjectRoot(url: symlink) {
        case .success(let detected):
            try await waitForCondition("Persistence should update to canonical") {
                HUDPreferences.getPersistedRoot() == repo.resolvingSymlinksInPath().path
            }
            XCTAssertEqual(detected.path, repo.resolvingSymlinksInPath().path)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testParseHeadReturnsFullRef() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let dotGit = temp.appendingPathComponent(".git", isDirectory: true)
        try fm.createDirectory(at: dotGit, withIntermediateDirectories: true)
        let headFile = dotGit.appendingPathComponent("HEAD")
        try "ref: refs/heads/feature/foo\n".write(to: headFile, atomically: true, encoding: .utf8)

        let branch = GitRepositoryResolver.parseHEAD(at: temp)
        XCTAssertEqual(branch, "refs/heads/feature/foo")
    }

    #if DEBUG
    func testCoalescedGitUpdatesFlushPending() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let model = HUDViewModel()
        _ = model.setProjectRoot(url: repo)
        model.debugHandleHeadEvent([.write])
        model.debugHandleHeadEvent([.write])

        XCTAssertTrue(model.debugPendingUpdate)
        try await waitForCondition("Pending updates should flush") {
            model.debugPendingUpdate == false
        }
    }

    func testHeadWatcherIncludesRearmEvents() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let model = HUDViewModel()
        _ = model.setProjectRoot(url: repo)
        model.updateHeadWatcher()
        guard let mask = model.debugHeadWatcherMask else {
            XCTFail("Watcher mask should be available")
            return
        }
        XCTAssertTrue(mask.contains(.delete))
        XCTAssertTrue(mask.contains(.rename))
        XCTAssertTrue(mask.contains(.revoke))
    }

    func testHeadWatcherRearmsOnRename() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let model = HUDViewModel()
        _ = model.setProjectRoot(url: repo)
        let initial = model.debugHeadWatcherArms
        model.debugHandleHeadEvent([.rename])

        try await waitForCondition("Watcher should rearm on rename") {
            model.debugHeadWatcherArms > initial
        }
    }
    #endif
}

private func locateRepoRoot(from filePath: String = #filePath) -> URL? {
    var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
    let fm = FileManager.default
    for _ in 0..<12 {
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
    HUDPreferences.clearPersistedRoot()
}

@MainActor
private func waitForCondition(_ message: String, timeout: TimeInterval = 2.0, predicate: @escaping () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() { return }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    if predicate() { return }
    XCTFail(message)
}
