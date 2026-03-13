import XCTest
@testable import ContextifyCore

final class GitProjectIdentityTests: XCTestCase {
  func testDeriveRepoGroupKeyPrefersNormalizedOrigin() {
    let groupKey = GitProjectIdentity.deriveRepoGroupKey(
      repoOriginNormalized: "github.com/example/project",
      repoIdentity: "git-common-dir:abc123"
    )

    XCTAssertEqual(
      groupKey,
      "repo-origin-sha256:\(CrossPlatformCrypto.sha256("github.com/example/project"))"
    )
  }

  func testDeriveRepoGroupKeyFallsBackToRepoIdentity() {
    XCTAssertEqual(
      GitProjectIdentity.deriveRepoGroupKey(
        repoOriginNormalized: nil,
        repoIdentity: "git-common-dir:abc123"
      ),
      "git-common-dir:abc123"
    )
  }

  func testDeriveRepoGroupKeyReturnsNilWithoutOriginOrIdentity() {
    XCTAssertNil(
      GitProjectIdentity.deriveRepoGroupKey(
        repoOriginNormalized: nil,
        repoIdentity: nil
      )
    )
  }

  func testNormalizeOriginURLHandlesCommonGitFormats() {
    XCTAssertEqual(
      GitProjectIdentity.normalizeOriginURL("git@github.com:owner/repo.git"),
      "github.com/owner/repo"
    )
    XCTAssertEqual(
      GitProjectIdentity.normalizeOriginURL("https://GitHub.com/owner/repo.git"),
      "github.com/owner/repo"
    )
    XCTAssertEqual(
      GitProjectIdentity.normalizeOriginURL("ssh://git@gitlab.com/group/repo"),
      "gitlab.com/group/repo"
    )
  }

  func testResolveReturnsNilForNonGitDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    XCTAssertNil(GitProjectIdentity.resolve(forProjectRootPath: directory.path))
  }

  func testResolveSharesRepoIdentityAcrossMainRepoAndWorktree() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let remote = tempRoot.appendingPathComponent("remote.git", isDirectory: true)
    let repo = tempRoot.appendingPathComponent("repo", isDirectory: true)
    let worktree = tempRoot.appendingPathComponent("repo-wb1", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    try runGit(["init", "--bare", "--initial-branch=main", remote.path], in: tempRoot)
    try runGit(["init", "--initial-branch=main", repo.path], in: tempRoot)
    try runGit(["config", "user.email", "test@example.com"], in: repo)
    try runGit(["config", "user.name", "Test User"], in: repo)
    try "seed".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try runGit(["add", "README.md"], in: repo)
    try runGit(["commit", "-m", "Initial commit"], in: repo)
    try runGit(["remote", "add", "origin", remote.path], in: repo)
    try runGit(["push", "-u", "origin", "main"], in: repo)
    try runGit(["remote", "set-head", "origin", "-a"], in: repo)
    try runGit(["worktree", "add", worktree.path, "-b", "feature/worktree-grouping"], in: repo)

    let mainIdentity = try XCTUnwrap(GitProjectIdentity.resolve(forProjectRootPath: repo.path))
    let worktreeIdentity = try XCTUnwrap(GitProjectIdentity.resolve(forProjectRootPath: worktree.path))

    XCTAssertEqual(mainIdentity.repoIdentity, worktreeIdentity.repoIdentity)
    XCTAssertEqual(mainIdentity.repoGroupKey, worktreeIdentity.repoGroupKey)
    XCTAssertEqual(mainIdentity.repoOriginNormalized, worktreeIdentity.repoOriginNormalized)
    XCTAssertEqual(mainIdentity.gitCommonDir, worktreeIdentity.gitCommonDir)
    XCTAssertEqual(mainIdentity.defaultBranch, "main")
    XCTAssertEqual(worktreeIdentity.defaultBranch, "main")
    XCTAssertEqual(mainIdentity.repoName, "repo")
    XCTAssertEqual(worktreeIdentity.repoName, "repo")
    XCTAssertFalse(mainIdentity.isWorktree)
    XCTAssertTrue(worktreeIdentity.isWorktree)
    XCTAssertNil(mainIdentity.worktreeName)
    XCTAssertEqual(worktreeIdentity.worktreeName, "repo-wb1")
    XCTAssertEqual(mainIdentity.vcsProvider, nil)
    XCTAssertEqual(mainIdentity.repoGroupKey, mainIdentity.repoIdentity)
  }

  private func runGit(_ arguments: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory

    let output = Pipe()
    process.standardOutput = output
    process.standardError = output

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      let data = output.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8) ?? ""
      XCTFail("git \(arguments.joined(separator: " ")) failed: \(message)")
    }
  }
}
