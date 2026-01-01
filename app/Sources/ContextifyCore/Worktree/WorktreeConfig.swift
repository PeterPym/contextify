import Foundation

/// Configuration from .worktrees.json
public struct WorktreeConfig: Decodable {
    public let schemaVersion: Int
    public let worktrees: [WorktreeEntry]

    public func nameFor(path: String) -> String? {
        let expandedPath = canonicalizePath(path)
        return worktrees.first {
            canonicalizePath($0.path) == expandedPath
        }?.name
    }

    public func isArchived(path: String) -> Bool {
        let expandedPath = canonicalizePath(path)
        return worktrees.first {
            canonicalizePath($0.path) == expandedPath
        }?.archived ?? false
    }

    private func canonicalizePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardized.resolvingSymlinksInPath().path
    }
}

public struct WorktreeEntry: Decodable {
    public let name: String
    public let path: String
    public let archived: Bool?
}

/// Load .worktrees.json from git root
public func loadWorktreeConfig(gitRoot: URL) -> WorktreeConfig? {
    let configPath = gitRoot.appendingPathComponent(".worktrees.json")
    guard let data = try? Data(contentsOf: configPath) else { return nil }
    return try? JSONDecoder().decode(WorktreeConfig.self, from: data)
}
