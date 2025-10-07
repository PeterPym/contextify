import Foundation

struct TranscriptSession: Hashable, Sendable {
    let provider: TimelineSourceContext.Provider
    let identifier: String
    let fileURL: URL
    let lastActivity: Date
}

protocol ConversationTranscriptProvider: Sendable {
    func sessions(for projectPath: String) -> [TranscriptSession]
}

struct ClaudeTranscriptProvider: ConversationTranscriptProvider {
    private let fileManager = FileManager.default

    func sessions(for projectPath: String) -> [TranscriptSession] {
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
}
