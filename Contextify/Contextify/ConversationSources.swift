import Foundation

struct TranscriptSession: Hashable, Sendable {
    let provider: TimelineSourceContext.Provider
    let identifier: String
    let fileURL: URL
    let lastActivity: Date
}

// MARK: - DEPRECATED: File-based providers (replaced by database-backed discovery)

// The code below is DEAD CODE kept for reference only.
// Session discovery now uses the database layer:
// - ConversationMonitor.switchToClaudeCodeSession() discovers files and calls orchestrator.upsertTranscripts()
// - allSessions is populated via orchestrator.getTranscripts(), not these providers
// - These providers read transcript files directly, violating bronze-layer architecture

#if false
protocol ConversationTranscriptProvider: Sendable {
    func sessions(for projectPath: String) -> [TranscriptSession]
    func sessions(for context: ProjectContext) -> [TranscriptSession]
}

extension ConversationTranscriptProvider {
    // Default implementation for backward compatibility
    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        return sessions(for: context.workingDirectory.path)
    }
}

struct ClaudeTranscriptProvider: ConversationTranscriptProvider {
    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        var allSessions: [TranscriptSession] = []

        // Collect sessions from all project paths (working directory, git root, worktrees)
        for projectURL in context.allProjectPaths() {
            allSessions.append(contentsOf: sessionsForPath(projectURL.path))
        }

        // Deduplicate by file URL
        var seen = Set<URL>()
        return allSessions.filter { session in
            seen.insert(session.fileURL).inserted
        }
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        let fm = FileManager.default
        let projectDirName = projectPath.replacingOccurrences(of: "/", with: "-")
        let projectsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let projectDir = projectsDir.appendingPathComponent(projectDirName)

        guard fm.fileExists(atPath: projectDir.path) else { return [] }

        do {
            let files = try fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "jsonl" }

            return files.compactMap { fileURL in
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                let lastMod = values?.contentModificationDate ?? .distantPast
                return TranscriptSession(
                    provider: .claudeCode,
                    identifier: fileURL.lastPathComponent,
                    fileURL: fileURL,
                    lastActivity: lastMod
                )
            }
        } catch {
            return []
        }
    }
}

struct CodexTranscriptProvider: ConversationTranscriptProvider {
    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        var allSessions: [TranscriptSession] = []

        // Collect sessions from all project paths (working directory, git root, worktrees)
        for projectURL in context.allProjectPaths() {
            allSessions.append(contentsOf: sessionsForPath(projectURL.path))
        }

        // Deduplicate by file URL
        var seen = Set<URL>()
        return allSessions.filter { session in
            seen.insert(session.fileURL).inserted
        }
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        let fm = FileManager.default
        let codexSessionsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")

        guard fm.fileExists(atPath: codexSessionsDir.path) else { return [] }

        // Get git repository URL for this path (if available)
        let gitRepoURL = getGitRepositoryURL(for: projectPath)

        // Find all JSONL files in sessions directory (including subdirectories)
        let jsonlFiles = findJSONLFiles(in: codexSessionsDir)

        // Parse each file looking for session_meta with matching cwd or git repo
        return jsonlFiles.compactMap { fileURL in
            parseCodexSession(fileURL, matchingPath: projectPath, gitRepoURL: gitRepoURL)
        }
    }

    private func findJSONLFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var jsonlFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                jsonlFiles.append(fileURL)
            }
        }
        return jsonlFiles
    }

    private func parseCodexSession(_ fileURL: URL, matchingPath: String, gitRepoURL: String?) -> TranscriptSession? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? fileHandle.close() }

        // Read file line by line looking for session_meta
        guard let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  json["type"] as? String == "session_meta",
                  let payload = json["payload"] as? [String: Any] else {
                continue
            }

            // Check if this session matches our project by cwd or git repo URL
            let sessionCwd = payload["cwd"] as? String
            let sessionGitInfo = payload["git"] as? [String: Any]
            let sessionRepoURL = sessionGitInfo?["repository_url"] as? String

            let isMatch = sessionCwd == matchingPath ||
                          (gitRepoURL != nil && sessionRepoURL == gitRepoURL)

            guard isMatch else { continue }

            // Found a matching session_meta
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let lastMod = values?.contentModificationDate ?? .distantPast

            return TranscriptSession(
                provider: .codexCLI,
                identifier: fileURL.lastPathComponent,
                fileURL: fileURL,
                lastActivity: lastMod
            )
        }

        return nil
    }

    private func getGitRepositoryURL(for path: String) -> String? {
        let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
        let configFile = gitDir.appendingPathComponent("config")

        guard let configData = try? String(contentsOf: configFile, encoding: .utf8) else {
            return nil
        }

        // Parse git config to find remote origin URL
        let lines = configData.components(separatedBy: .newlines)
        var inOriginSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "[remote \"origin\"]" {
                inOriginSection = true
                continue
            }

            if trimmed.hasPrefix("[") && inOriginSection {
                inOriginSection = false
            }

            if inOriginSection && trimmed.hasPrefix("url = ") {
                return String(trimmed.dropFirst("url = ".count))
            }
        }

        return nil
    }
}

struct ActiveConversationResolver: Sendable {
    private let providers: [any ConversationTranscriptProvider]

    init(providers: [any ConversationTranscriptProvider]) {
        self.providers = providers
    }

    func resolveActiveSession(for projectPath: String) -> TranscriptSession? {
        providers
            .flatMap { $0.sessions(for: projectPath) }
            .max(by: { $0.lastActivity < $1.lastActivity })
    }

    func resolveAllSessions(for context: ProjectContext) -> [TranscriptSession] {
        providers
            .flatMap { $0.sessions(for: context) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    func resolveActiveSession(for context: ProjectContext) -> TranscriptSession? {
        resolveAllSessions(for: context).first
    }
}

#endif // DEAD CODE
