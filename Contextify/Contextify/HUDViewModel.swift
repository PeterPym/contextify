import Foundation
import Observation

@Observable
final class HUDViewModel {
    enum UIState: Equatable { case idle, ingesting, success(String), error(String) }

    var branch: String = "Not a git repo"
    var session: String = "Session-001"
    var status: String = "Ready"
    var lastOutputURL: URL? = nil
    var state: UIState = .idle
    var urlText: String = ""
    private(set) var projectRootURL: URL? = nil

    // Destination for outputs; for development keep outside repo by default.
    var outputsDirectory: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Contextify/outputs", isDirectory: true)
    }

    init() {
        // Load persisted project root if available
        if let path = UserDefaults.standard.string(forKey: Self.defaultsProjectRootKey), !path.isEmpty {
            projectRootURL = URL(fileURLWithPath: path)
        }
    }

    @MainActor
    func ensureOutputsDir() {
        let fm = FileManager.default
        try? fm.createDirectory(at: outputsDirectory, withIntermediateDirectories: true)
    }

    @MainActor
    func ingestURLString() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            state = .error("Enter a valid URL")
            return
        }
        await ingest(.url(url))
    }

    enum IngestItem { case file(URL), url(URL) }

    @MainActor
    func ingest(_ item: IngestItem) async {
        ensureOutputsDir()
        state = .ingesting
        do {
            let stamp = Int(Date().timeIntervalSince1970)
            let out = outputsDirectory.appendingPathComponent("\(stamp).md")
            let content: String
            switch item {
            case .file(let src):
                // Phase 2: copy file to outputs/ingest and emit simple summary
                let ingestDir = outputsDirectory.appendingPathComponent("ingest", isDirectory: true)
                try? FileManager.default.createDirectory(at: ingestDir, withIntermediateDirectories: true)
                let copyName = "\(stamp)-\(src.lastPathComponent)"
                let dest = ingestDir.appendingPathComponent(copyName)
                _ = try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: src, to: dest)
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                content = """
                # File Ingest
                
                - Source: \(src.path)
                - Copied: ingest/\(copyName)
                - Size: \(size) bytes
                - Session: \(session)
                - Branch: \(branch)
                - Saved: \(Date())
                
                ## Notes
                - Add a summary here.
                """
            case .url(let u):
                content = """
                # URL Ingest
                
                - URL: \(u.absoluteString)
                - Session: \(session)
                - Branch: \(branch)
                - Saved: \(Date())
                
                ## Notes
                - Add findings here.
                """
            }
            try content.write(to: out, atomically: true, encoding: .utf8)
            state = .success("Saved to outputs: \(out.lastPathComponent)")
            status = "Last: \(out.lastPathComponent)"
            lastOutputURL = out
        } catch {
            state = .error("Failed to save: \(error.localizedDescription)")
        }
    }

    @MainActor
    func newSession() {
        session = "Session-\(Int.random(in: 100...999))"
        urlText = ""
        lastOutputURL = nil
        status = "Ready"
    }

    @MainActor
    func checkpoint() {
        ensureOutputsDir()
        let ts = Int(Date().timeIntervalSince1970)
        let cpDir = outputsDirectory.appendingPathComponent("checkpoints", isDirectory: true)
        try? FileManager.default.createDirectory(at: cpDir, withIntermediateDirectories: true)
        let file = cpDir.appendingPathComponent("checkpoint-\(session)-\(ts).md")
        let body = """
        # Checkpoint
        - Session: \(session)
        - Branch: \(branch)
        - Timestamp: \(Date())
        """
        try? body.write(to: file, atomically: true, encoding: .utf8)
        status = "Checkpoint at \(Date())"
        lastOutputURL = file
    }

    // MARK: - Git discovery (read-only)
    @MainActor
    func updateGitInfo() {
        if let url = projectRootURL {
            if let br = runGitBranch(at: url) { self.branch = br } else { self.branch = "Not a git repo" }
        } else if let root = ProcessInfo.processInfo.environment["CONTEXTIFY_PROJECT_ROOT"], !root.isEmpty {
            if let br = runGitBranch(at: URL(fileURLWithPath: root)) { self.branch = br } else { self.branch = "Not a git repo" }
        } else {
            // Try current working directory
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if let br = runGitBranch(at: cwd) { self.branch = br } else { self.branch = "Not a git repo" }
        }
    }

    private func runGitBranch(at dir: URL) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "rev-parse", "--abbrev-ref", "HEAD"]
        task.currentDirectoryURL = dir
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Project Root persistence
    @MainActor
    func setProjectRoot(url: URL) {
        projectRootURL = url
        UserDefaults.standard.set(url.path, forKey: Self.defaultsProjectRootKey)
        updateGitInfo()
    }

    private static let defaultsProjectRootKey = "dev.contextify.projectRoot"
}
