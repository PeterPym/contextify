import Foundation
import ContextifyCore

/// Represents the complete context of a project, including working directory,
/// git repository root, and all potential worktrees. Used for transcript discovery.
struct ProjectContext: Hashable, Sendable {
  let workingDirectory: URL
  let gitRepoRoot: URL?
  let projectIdentifier: String

  init(workingDirectory: URL, gitRepoRoot: URL? = nil) {
    self.workingDirectory = workingDirectory
    self.gitRepoRoot = gitRepoRoot
    self.projectIdentifier = (gitRepoRoot ?? workingDirectory).lastPathComponent
  }

  /// Creates ProjectContext from the current HUDViewModel state
  @available(*, deprecated, message: "Use StartupCoordinator.shared.current instead. This method queries HUDViewModel which may be stale during startup.")
  static func current() -> ProjectContext? {
    guard let projectURL = HUDViewModel.shared.projectRootURL else {
      return nil
    }

    let gitRoot = GitRepositoryResolver.findGitRoot(startingAt: projectURL)
    return ProjectContext(workingDirectory: projectURL, gitRepoRoot: gitRoot)
  }

  /// Discovers all git worktrees associated with this project
  func discoverWorktrees() -> [URL] {
    guard let gitRoot = gitRepoRoot else { return [] }

    let gitDir = GitRepositoryResolver.resolveGitDir(for: gitRoot)
    let worktreesDir = (gitDir ?? gitRoot.appendingPathComponent(".git"))
      .appendingPathComponent("worktrees")

    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: worktreesDir.path, isDirectory: &isDir), isDir.boolValue else {
      return []
    }

    do {
      let subdirs = try fm.contentsOfDirectory(
        at: worktreesDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )

      return subdirs.compactMap { worktreeMetaDir -> URL? in
        let gitdirFile = worktreeMetaDir.appendingPathComponent("gitdir")
        guard let gitdirContent = try? String(contentsOf: gitdirFile, encoding: .utf8) else {
          return nil
        }

        // gitdir file contains path to worktree's .git file (e.g., /path/to/worktree/.git)
        let worktreeGitPath = gitdirContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let worktreePath = URL(fileURLWithPath: worktreeGitPath).deletingLastPathComponent()

        var worktreeIsDir: ObjCBool = false
        guard fm.fileExists(atPath: worktreePath.path, isDirectory: &worktreeIsDir),
              worktreeIsDir.boolValue else {
          return nil
        }

        return worktreePath
      }
    } catch {
      return []
    }
  }

  /// Returns all project paths that should be checked for transcripts:
  /// working directory, git root (if different), and all worktrees
  func allProjectPaths() -> [URL] {
    var paths: [URL] = [workingDirectory]

    if let gitRoot = gitRepoRoot, gitRoot != workingDirectory {
      paths.append(gitRoot)
    }

    paths.append(contentsOf: discoverWorktrees())

    // Deduplicate by path
    var seen = Set<String>()
    return paths.filter { url in
      let canonical = url.resolvingSymlinksInPath().path
      return seen.insert(canonical).inserted
    }
  }
}
