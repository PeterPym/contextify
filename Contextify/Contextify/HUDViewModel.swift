import Foundation
import Observation
import OSLog

@Observable
final class HUDViewModel {
    static let shared = HUDViewModel()
    enum UIState: Equatable { case idle, ingesting, success(String), error(String) }

    var branch: String = "—"
    var session: String = "Session-001"
    var status: String = "Ready"
    var lastOutputURL: URL? = nil
    var state: UIState = .idle
    var urlText: String = ""
    var alertMessage: String? = nil
    private static let defaultsProjectRootKey = "dev.contextify.projectRoot"

    // Destination for outputs; for development keep outside repo by default.
    var outputsDirectory: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Contextify/outputs", isDirectory: true)
    }

    init() {
        // Load persisted project root if available (shared suite first, then standard fallback)
        let persisted = Self.sharedDefaults.string(forKey: Self.defaultsProjectRootKey)
            ?? UserDefaults.standard.string(forKey: Self.defaultsProjectRootKey)
        if let path = persisted, !path.isEmpty {
            projectRootURL = URL(fileURLWithPath: path)
            Task { @MainActor in
                self.updateGitInfo()
                self.startBranchMonitor()
            }
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
        let logger = Logger(subsystem: "dev.contextify", category: "Git")
        if let saved = UserDefaults.standard.string(forKey: Self.defaultsProjectRootKey), !saved.isEmpty {
            let base = URL(fileURLWithPath: saved)
            logger.info("updateGitInfo: saved=\(saved, privacy: .public)")
            guard let root = findGitRoot(startingAt: base) else {
                alertMessage = "Configured project root is not a Git repository:\n\(saved)"
                logger.error("Saved path had no git: \(saved, privacy: .public)")
                UserDefaults.standard.removeObject(forKey: Self.defaultsProjectRootKey)
                branch = "—"
                status = "Select a Git repository"
                return
            }
            if let br = runGitBranch(at: root) { self.branch = br; logger.info("branch=\(br, privacy: .public)") }
            return
        }
        if let root = ProcessInfo.processInfo.environment["CONTEXTIFY_PROJECT_ROOT"], !root.isEmpty {
            let base = URL(fileURLWithPath: root)
            logger.info("env CONTEXTIFY_PROJECT_ROOT=\(root, privacy: .public)")
            guard let repo = findGitRoot(startingAt: base) else { logger.error("env path not a git repo"); return }
            if let br = runGitBranch(at: repo) { self.branch = br; logger.info("branch=\(br, privacy: .public)") }
            return
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let repo = findGitRoot(startingAt: cwd), let br = runGitBranch(at: repo) {
            self.branch = br
            logger.info("cwd repo branch=\(br, privacy: .public)")
        } else {
            logger.info("No repo found from CWD")
        }
    }

    // remove: old void variant of setProjectRoot (replaced by Bool version below)

    private func runGitBranch(at dir: URL) -> String? {
        if let br = parseHEAD(at: dir) { return br }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "rev-parse", "--abbrev-ref", "HEAD"]
        task.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        // Ensure PATH includes common locations
        env["PATH"] = "/usr/bin:/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        let err = Pipe()
        task.standardError = err
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseHEAD(at dir: URL) -> String? {
        guard let root = findGitRoot(startingAt: dir) else { return nil }
        let headURL = root.appendingPathComponent(".git/HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if head.hasPrefix("ref:") {
            let ref = head.replacingOccurrences(of: "ref:", with: "").trimmingCharacters(in: .whitespaces)
            if let last = ref.split(separator: "/").last { return String(last) }
            return ref
        } else if head.count >= 7 { return "detached@" + String(head.prefix(7)) }
        return nil
    }

    private func findGitRoot(startingAt url: URL) -> URL? {
        var current = url
        let fm = FileManager.default
        while true {
            var isDir: ObjCBool = false
            let dotGit = current.appendingPathComponent(".git")
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) { return current }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    @MainActor
    @discardableResult
    func setProjectRoot(url: URL) -> Bool {
        guard let repo = findGitRoot(startingAt: url) else {
            alertMessage = "Selected folder is not a Git repository:\n\(url.path)"
            status = "Select a Git repository"
            return false
        }
        UserDefaults.standard.set(repo.path, forKey: Self.defaultsProjectRootKey)
        status = "Ready"
        updateGitInfo()
        return true
    }
}
