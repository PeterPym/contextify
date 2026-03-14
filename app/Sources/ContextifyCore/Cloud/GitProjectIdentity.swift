import Foundation

public struct GitProjectIdentity: Sendable, Equatable {
  public let repoGroupKey: String?
  public let repoIdentity: String?
  public let repoOriginNormalized: String?
  public let gitCommonDir: String?
  public let isWorktree: Bool
  public let defaultBranch: String?
  public let vcsProvider: String?
  public let worktreeName: String?
  public let repoName: String?

  public init(
    repoGroupKey: String?,
    repoIdentity: String?,
    repoOriginNormalized: String?,
    gitCommonDir: String?,
    isWorktree: Bool,
    defaultBranch: String?,
    vcsProvider: String?,
    worktreeName: String?,
    repoName: String?
  ) {
    self.repoGroupKey = repoGroupKey
    self.repoIdentity = repoIdentity
    self.repoOriginNormalized = repoOriginNormalized
    self.gitCommonDir = gitCommonDir
    self.isWorktree = isWorktree
    self.defaultBranch = defaultBranch
    self.vcsProvider = vcsProvider
    self.worktreeName = worktreeName
    self.repoName = repoName
  }

  public static func resolve(forProjectRootPath rootPath: String) -> GitProjectIdentity? {
    let projectURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    guard let gitRoot = GitRepositoryResolver.findGitRoot(startingAt: projectURL),
          let commonDirResult = resolveCommonGitDir(forGitRoot: gitRoot) else {
      return nil
    }

    let mainGitRoot = GitRepositoryResolver.findMainGitRoot(startingAt: projectURL) ?? gitRoot
    let commonGitDir = commonDirResult.commonGitDir.standardizedFileURL.resolvingSymlinksInPath()
    let repoIdentity = "git-common-dir:\(CrossPlatformCrypto.sha256(commonGitDir.path))"
    let originURL = parseOriginURL(fromCommonGitDir: commonGitDir)
    let normalizedOrigin = originURL.flatMap(normalizeOriginURL)
    let repoGroupKey = deriveRepoGroupKey(
      repoOriginNormalized: normalizedOrigin,
      repoIdentity: repoIdentity
    )
    let repoName = repoName(fromNormalizedOrigin: normalizedOrigin) ?? mainGitRoot.lastPathComponent

    return GitProjectIdentity(
      repoGroupKey: repoGroupKey,
      repoIdentity: repoIdentity,
      repoOriginNormalized: normalizedOrigin,
      gitCommonDir: commonGitDir.path,
      isWorktree: commonDirResult.isWorktree,
      defaultBranch: resolveDefaultBranch(fromCommonGitDir: commonGitDir),
      vcsProvider: normalizedOrigin.flatMap(vcsProvider(fromNormalizedOrigin:)),
      worktreeName: commonDirResult.isWorktree ? gitRoot.lastPathComponent : nil,
      repoName: repoName.isEmpty ? nil : repoName
    )
  }

  public static func deriveRepoGroupKey(
    repoOriginNormalized: String?,
    repoIdentity: String?
  ) -> String? {
    if let repoOriginNormalized, !repoOriginNormalized.isEmpty {
      return "repo-origin-sha256:\(CrossPlatformCrypto.sha256(repoOriginNormalized))"
    }
    if let repoIdentity, !repoIdentity.isEmpty {
      return repoIdentity
    }
    return nil
  }

  static func normalizeOriginURL(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.hasPrefix("git@"), let colon = trimmed.firstIndex(of: ":") {
      let authority = String(trimmed[..<colon])
      let host = authority.split(separator: "@").last.map(String.init)?.lowercased() ?? authority.lowercased()
      let path = normalizedRepoPath(String(trimmed[trimmed.index(after: colon)...]))
      return path.map { "\(host)/\($0)" }
    }

    if let components = URLComponents(string: trimmed), let host = components.host?.lowercased() {
      let path = normalizedRepoPath(components.path)
      return path.map { "\(host)/\($0)" }
    }

    return nil
  }

  private struct CommonGitDirResult {
    let commonGitDir: URL
    let isWorktree: Bool
  }

  private static func resolveCommonGitDir(forGitRoot gitRoot: URL) -> CommonGitDirResult? {
    let dotGit = gitRoot.appendingPathComponent(".git")
    let fm = FileManager.default
    var isDirectory: ObjCBool = false

    guard fm.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
      return nil
    }

    if isDirectory.boolValue {
      return CommonGitDirResult(
        commonGitDir: dotGit.resolvingSymlinksInPath(),
        isWorktree: false
      )
    }

    guard let gitDir = parseGitDirPointer(dotGit) else {
      return nil
    }

    let gitDirPath = gitDir.standardizedFileURL.resolvingSymlinksInPath().path
    if let worktreesRange = gitDirPath.range(of: "/worktrees/") {
      let commonGitDir = URL(fileURLWithPath: String(gitDirPath[..<worktreesRange.lowerBound]))
      return CommonGitDirResult(commonGitDir: commonGitDir, isWorktree: true)
    }

    return CommonGitDirResult(commonGitDir: gitDir, isWorktree: false)
  }

  private static func parseGitDirPointer(_ dotGit: URL) -> URL? {
    guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
          let range = contents.range(of: "gitdir:") else {
      return nil
    }

    let pointer = contents[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pointer.isEmpty else { return nil }

    if pointer.hasPrefix("/") {
      return URL(fileURLWithPath: pointer, isDirectory: true)
    }

    return dotGit.deletingLastPathComponent()
      .appendingPathComponent(pointer, isDirectory: true)
      .standardizedFileURL
  }

  private static func parseOriginURL(fromCommonGitDir commonGitDir: URL) -> String? {
    let configURL = commonGitDir.appendingPathComponent("config")
    guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
      return nil
    }

    var inOriginSection = false
    for rawLine in contents.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("[") {
        inOriginSection = line == #"[remote "origin"]"#
        continue
      }
      guard inOriginSection else { continue }
      guard let separator = line.firstIndex(of: "=") else { continue }
      let key = line[..<separator].trimmingCharacters(in: .whitespaces)
      if key == "url" {
        return String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      }
    }

    return nil
  }

  private static func resolveDefaultBranch(fromCommonGitDir commonGitDir: URL) -> String? {
    let originHeadURL = commonGitDir
      .appendingPathComponent("refs", isDirectory: true)
      .appendingPathComponent("remotes", isDirectory: true)
      .appendingPathComponent("origin", isDirectory: true)
      .appendingPathComponent("HEAD")
    guard let line = try? String(contentsOf: originHeadURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines),
      line.hasPrefix("ref:") else {
      return nil
    }

    let ref = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
    return ref.split(separator: "/").last.map(String.init)
  }

  private static func vcsProvider(fromNormalizedOrigin origin: String) -> String? {
    guard let host = origin.split(separator: "/").first?.lowercased() else {
      return nil
    }
    if host.contains("github") {
      return "github"
    }
    if host.contains("gitlab") {
      return "gitlab"
    }
    if host.contains("bitbucket") {
      return "bitbucket"
    }
    return nil
  }

  private static func repoName(fromNormalizedOrigin origin: String?) -> String? {
    guard let origin else { return nil }
    return origin.split(separator: "/").last.map(String.init)
  }

  private static func normalizedRepoPath(_ rawPath: String) -> String? {
    var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    while path.hasPrefix("/") {
      path.removeFirst()
    }
    while path.hasSuffix("/") {
      path.removeLast()
    }
    if path.hasSuffix(".git") {
      path.removeLast(4)
    }
    return path.isEmpty ? nil : path
  }
}
