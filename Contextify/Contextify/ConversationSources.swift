import Foundation

struct TranscriptSession: Hashable, Sendable {
    let provider: TimelineSourceContext.Provider
    let identifier: String
    let fileURL: URL
    let lastActivity: Date
}

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
    private let fileManager = FileManager.default

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
        let projectDirName = projectPath.replacingOccurrences(of: "/", with: "-")
        let projectsDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let projectDir = projectsDir.appendingPathComponent(projectDirName)

        guard fileManager.fileExists(atPath: projectDir.path) else { return [] }

        do {
            let files = try fileManager.contentsOfDirectory(
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
    private let fileManager = FileManager.default

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
        let codexSessionsDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")

        guard fileManager.fileExists(atPath: codexSessionsDir.path) else { return [] }

        // Find all JSONL files in sessions directory (including subdirectories)
        let jsonlFiles = findJSONLFiles(in: codexSessionsDir)

        // Parse each file looking for session_meta with matching cwd
        return jsonlFiles.compactMap { fileURL in
            parseCodexSession(fileURL, matchingPath: projectPath)
        }
    }

    private func findJSONLFiles(in directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
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

    private func parseCodexSession(_ fileURL: URL, matchingPath: String) -> TranscriptSession? {
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
                  let payload = json["payload"] as? [String: Any],
                  let cwd = payload["cwd"] as? String,
                  cwd == matchingPath else {
                continue
            }

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
