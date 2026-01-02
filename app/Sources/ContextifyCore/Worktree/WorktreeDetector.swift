import Foundation

/// Represents a group of related git worktrees
public struct WorktreeGroup {
    /// The common .git directory shared by all worktrees
    public let commonGitDir: URL
    /// All worktree root paths in this group
    public let worktrees: [URL]
    /// The worktree we're currently in
    public let currentWorktree: URL
}

/// Detects git worktree relationships for query expansion
public struct WorktreeDetector {

    /// Find the worktree group containing the given directory
    /// Returns nil if not in a worktree group or only one worktree exists
    public static func findWorktreeGroup(from directory: URL) -> WorktreeGroup? {
        // Try git CLI first (more reliable)
        if let group = findWorktreeGroupViaGit(from: directory) {
            return group
        }
        // Fall back to filesystem parsing
        return findWorktreeGroupViaFilesystem(from: directory)
    }

    // MARK: - Git CLI Method

    private static func findWorktreeGroupViaGit(from directory: URL) -> WorktreeGroup? {
        guard let repoRoot = runGit(["rev-parse", "--show-toplevel"], in: directory) else {
            return nil
        }

        // Try --path-format=absolute first (Git 2.31+), fallback to manual resolution
        let resolvedGitDir: URL
        if let absoluteGitDir = runGit(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: directory),
           absoluteGitDir.hasPrefix("/") {
            resolvedGitDir = URL(fileURLWithPath: absoluteGitDir).resolvingSymlinksInPath()
        } else if let commonGitDir = runGit(["rev-parse", "--git-common-dir"], in: directory) {
            // Fallback: resolve relative path (e.g., ".git") against repo root
            if commonGitDir.hasPrefix("/") {
                resolvedGitDir = URL(fileURLWithPath: commonGitDir).resolvingSymlinksInPath()
            } else {
                resolvedGitDir = URL(fileURLWithPath: repoRoot)
                    .appendingPathComponent(commonGitDir)
                    .standardized
                    .resolvingSymlinksInPath()
            }
        } else {
            return nil
        }

        guard let worktreeListOutput = runGit(["worktree", "list", "--porcelain"], in: directory) else {
            return nil
        }

        let worktrees = parseWorktreeList(worktreeListOutput)
        guard worktrees.count > 1 else {
            return nil  // Single worktree, no expansion needed
        }

        return WorktreeGroup(
            commonGitDir: resolvedGitDir,
            worktrees: worktrees,
            currentWorktree: URL(fileURLWithPath: repoRoot)
        )
    }

    /// Default timeout for git commands (seconds)
    private static let gitTimeoutSeconds: TimeInterval = 5.0

    private static func runGit(_ args: [String], in directory: URL, timeout: TimeInterval = gitTimeoutSeconds) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory

        // Hardening: prevent hangs from prompts, pagers, or odd configs
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_PAGER"] = "cat"
        env["LC_ALL"] = "C"
        process.environment = env

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        // Merge stderr into stdout to avoid separate pipe buffer deadlock
        process.standardError = stdoutPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Use DispatchSemaphore for timeout with proper pipe draining
        let semaphore = DispatchSemaphore(value: 0)
        var outputData = Data()
        var timedOut = false

        // Read stdout asynchronously to avoid pipe buffer deadlock
        let readQueue = DispatchQueue(label: "dev.contextify.git-read")
        readQueue.async {
            outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }

        // Wait for process with timeout
        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            timedOut = true
            process.terminate()
            // Give it a moment, then force kill if needed
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            return nil
        }

        guard !timedOut && process.terminationStatus == 0 else {
            return nil
        }

        // Give the read queue a moment to finish
        readQueue.sync {}

        return String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseWorktreeList(_ output: String) -> [URL] {
        // Parse porcelain output:
        // worktree /path/to/main
        // HEAD abc123
        // branch refs/heads/main
        //
        // worktree /path/to/wt1
        // ...
        var worktrees: [URL] = []
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                let path = String(line.dropFirst(9))
                worktrees.append(URL(fileURLWithPath: path))
            }
        }
        return worktrees
    }

    // MARK: - Filesystem Fallback

    private static func findWorktreeGroupViaFilesystem(from directory: URL) -> WorktreeGroup? {
        // Walk up to find .git
        var current = directory
        while current.path != "/" {
            let gitPath = current.appendingPathComponent(".git")
            var isDir: ObjCBool = false

            if FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    // Main worktree: .git is a directory
                    return discoverFromMainWorktree(gitDir: gitPath, repoRoot: current)
                } else {
                    // Linked worktree: .git is a file
                    return discoverFromLinkedWorktree(gitFile: gitPath, worktreeRoot: current)
                }
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private static func discoverFromLinkedWorktree(gitFile: URL, worktreeRoot: URL) -> WorktreeGroup? {
        guard let content = try? String(contentsOf: gitFile, encoding: .utf8) else {
            return nil
        }

        guard content.hasPrefix("gitdir: ") else { return nil }
        var gitdirPath = String(content.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)

        // Resolve relative paths
        if !gitdirPath.hasPrefix("/") {
            let baseDir = gitFile.deletingLastPathComponent()
            gitdirPath = baseDir.appendingPathComponent(gitdirPath).standardized.path
        }

        // Validate this is a worktree (not a submodule)
        guard gitdirPath.contains("/.git/worktrees/") else {
            return nil
        }

        // Navigate to main .git dir
        let gitDirURL = URL(fileURLWithPath: gitdirPath)
        let mainGitDir = gitDirURL.deletingLastPathComponent().deletingLastPathComponent()
        let mainRepoRoot = mainGitDir.deletingLastPathComponent()

        return discoverFromMainWorktree(gitDir: mainGitDir, repoRoot: mainRepoRoot)
    }

    private static func discoverFromMainWorktree(gitDir: URL, repoRoot: URL) -> WorktreeGroup? {
        var siblings: [URL] = [repoRoot]

        let worktreesDir = gitDir.appendingPathComponent("worktrees")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: worktreesDir, includingPropertiesForKeys: nil) else {
            return nil  // No worktrees directory
        }

        for entry in entries {
            let gitdirFile = entry.appendingPathComponent("gitdir")
            if let content = try? String(contentsOf: gitdirFile, encoding: .utf8) {
                var worktreePath = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if worktreePath.hasSuffix("/.git") {
                    worktreePath = String(worktreePath.dropLast(5))
                }
                siblings.append(URL(fileURLWithPath: worktreePath))
            }
        }

        guard siblings.count > 1 else {
            return nil
        }

        return WorktreeGroup(
            commonGitDir: gitDir,
            worktrees: siblings,
            currentWorktree: repoRoot
        )
    }
}
