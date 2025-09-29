import XCTest
@testable import Contextify

private enum TestGitRepoBuilder {
    static func makeRepo(withPackedRefs: Bool = true) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let git = dir.appendingPathComponent(".git", isDirectory: true)
        try fm.createDirectory(at: git, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let heads = git.appendingPathComponent("refs/heads", isDirectory: true)
        try fm.createDirectory(at: heads, withIntermediateDirectories: true)
        try "0123456789abcdef\n".write(to: heads.appendingPathComponent("main"), atomically: true, encoding: .utf8)
        if withPackedRefs {
            fm.createFile(atPath: git.appendingPathComponent("packed-refs").path, contents: Data())
        }
        return dir
    }
}

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

    func testEnvInvalidFallsBackToPersisted() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        clearPersistedRoot()
        HUDPreferences.setPersistedRoot(repo)

        let model = HUDViewModel()
        model.updateGitInfo(env: ["CONTEXTIFY_PROJECT_ROOT": "/tmp/definitely/not/a/repo"])

        try await waitForCondition("Invalid ENV should fall back to persisted root") {
            model.projectRootURL?.path == repo.resolvingSymlinksInPath().path
        }
        XCTAssertEqual(model.projectRootURL?.path, repo.resolvingSymlinksInPath().path)
        XCTAssertEqual(HUDPreferences.getPersistedRoot(), repo.resolvingSymlinksInPath().path)
    }

    func testComputeGitInfoCollectsEnvAlert() {
        let result = GitRepositoryResolver.computeGitInfo(
            environment: ["CONTEXTIFY_PROJECT_ROOT": "/tmp/definitely/not/a/repo"],
            persistedPath: nil,
            currentRoot: nil,
            autoPersist: true
        )
        XCTAssertNil(result.root)
        XCTAssertNotNil(result.alertMessage)
        XCTAssertTrue(result.alertMessage?.contains("CONTEXTIFY_PROJECT_ROOT") ?? false)
    }

    func testPersistedInvalidFallsBackToCwd() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let fm = FileManager.default
        let original = fm.currentDirectoryPath
        defer { _ = fm.changeCurrentDirectoryPath(original) }

        clearPersistedRoot()
        let invalidDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: invalidDir, withIntermediateDirectories: true)
        HUDPreferences.setPersistedRoot(invalidDir)
        XCTAssertTrue(fm.changeCurrentDirectoryPath(repo.path))

        let model = HUDViewModel()
        model.updateGitInfo()

        try await waitForCondition("Invalid persisted root should fall back to CWD") {
            model.projectRootURL?.path == repo.resolvingSymlinksInPath().path
        }
        XCTAssertEqual(model.projectRootURL?.path, repo.resolvingSymlinksInPath().path)
        XCTAssertEqual(HUDPreferences.getPersistedRoot(), repo.resolvingSymlinksInPath().path)
    }

    func testPersistedInvalidFallsBackToExistingRoot() async throws {
        guard let repo = locateRepoRoot() else {
            XCTFail("Could not locate repo root")
            return
        }

        let fm = FileManager.default
        let original = fm.currentDirectoryPath
        defer { _ = fm.changeCurrentDirectoryPath(original) }

        clearPersistedRoot()
        let model = HUDViewModel()
        switch model.setProjectRoot(url: repo) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        let invalidDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: invalidDir, withIntermediateDirectories: true)
        HUDPreferences.setPersistedRoot(invalidDir)
        XCTAssertTrue(fm.changeCurrentDirectoryPath(fm.temporaryDirectory.path))

        model.updateGitInfo()

        try await waitForCondition("Existing root should survive invalid persisted path") {
            model.projectRootURL?.path == repo.resolvingSymlinksInPath().path
        }
        XCTAssertEqual(model.projectRootURL?.path, repo.resolvingSymlinksInPath().path)
        try await waitForCondition("Persisted root should clear when invalid") {
            HUDPreferences.getPersistedRoot() == nil
        }
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

    func testParseHeadHandlesDetachedHead() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let dotGit = temp.appendingPathComponent(".git", isDirectory: true)
        try fm.createDirectory(at: dotGit, withIntermediateDirectories: true)
        let headFile = dotGit.appendingPathComponent("HEAD")
        try "1234567890abcdef\n".write(to: headFile, atomically: true, encoding: .utf8)

        let branch = GitRepositoryResolver.parseHEAD(at: temp)
        XCTAssertEqual(branch, "detached@1234567")
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

    func testPackedRefsWatcherArms() async throws {
        let repo = try TestGitRepoBuilder.makeRepo(withPackedRefs: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let model = HUDViewModel()
        _ = model.setProjectRoot(url: repo)

        try await waitForCondition("Packed refs watcher should arm") {
            model.debugPackedWatcherActive
        }
        XCTAssertTrue(model.debugRefWatcherActive)
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
