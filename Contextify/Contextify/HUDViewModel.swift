import Foundation
import Observation

@Observable
final class HUDViewModel {
    static let shared = HUDViewModel()
    enum UIState: Equatable { case idle, ingesting, success(String), error(String) }

    var branch: String = "Not a git repo"
    var session: String = "Session-001"
    var status: String = "Ready"
    var lastOutputURL: URL? = nil
    var state: UIState = .idle
    var urlText: String = ""
    private(set) var projectRootURL: URL? = nil
    private var branchTimer: Timer? = nil
    private static let sharedDefaults: UserDefaults = {
        // Use a shared suite to persist across bundle changes
        UserDefaults(suiteName: "dev.contextify") ?? .standard
    }()

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
        if let url = projectRootURL {
            let root = findGitRoot(startingAt: url) ?? url
            if let br = runGitBranch(at: root) { self.branch = br } else { self.branch = "Not a git repo" }
        } else if let root = ProcessInfo.processInfo.environment["CONTEXTIFY_PROJECT_ROOT"], !root.isEmpty {
            let url = URL(fileURLWithPath: root)
            let rootURL = findGitRoot(startingAt: url) ?? url
            if let br = runGitBranch(at: rootURL) { self.branch = br } else { self.branch = "Not a git repo" }
        } else {
            // Try current working directory
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let root = findGitRoot(startingAt: cwd) ?? cwd
            if let br = runGitBranch(at: root) { self.branch = br } else { self.branch = "Not a git repo" }
        }
    }

    private func runGitBranch(at dir: URL) -> String? {
        // Prefer fast local parse to avoid spawning git frequently
        if let br = parseHEAD(at: dir) { return br }
        // Fall back to git CLI if parsing fails
        if let br = gitCLIAbbrevRef(at: dir) { return br }
        return nil
    }

    private func gitCLIAbbrevRef(at dir: URL) -> String? {
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
        // Locate .git directory (can be directory or a file pointing to gitdir)
        let dotGit = dir.appendingPathComponent(".git", isDirectory: false)
        var gitDirURL: URL? = nil
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
            if isDir.boolValue {
                gitDirURL = dotGit
            } else {
                // .git is a file: read 'gitdir: <path>'
                if let s = try? String(contentsOf: dotGit, encoding: .utf8),
                   let range = s.range(of: "gitdir:") {
                    let path = s[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if path.isEmpty == false {
                        gitDirURL = URL(fileURLWithPath: path)
                    }
                }
            }
        }
        guard let gitDir = gitDirURL else { return nil }
        let headURL = gitDir.appendingPathComponent("HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if head.hasPrefix("ref:") {
            // format: ref: refs/heads/<branch>
            let ref = head.replacingOccurrences(of: "ref:", with: "").trimmingCharacters(in: .whitespaces)
            if let last = ref.split(separator: "/").last { return String(last) }
            return ref
        } else if head.count >= 7 {
            // Detached HEAD with SHA
            return "detached@" + String(head.prefix(7))
        }
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

    // MARK: - Project Root persistence
    @MainActor
    func setProjectRoot(url: URL) {
        projectRootURL = url
        // Persist in both shared suite and standard to be resilient across builds
        Self.sharedDefaults.set(url.path, forKey: Self.defaultsProjectRootKey)
        UserDefaults.standard.set(url.path, forKey: Self.defaultsProjectRootKey)
        updateGitInfo()
        startBranchMonitor()
    }

    private static let defaultsProjectRootKey = "dev.contextify.projectRoot"

    // MARK: - Auto branch monitoring
    @MainActor
    func startBranchMonitor(interval: TimeInterval = 1.0) {
        branchTimer?.invalidate()
        branchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateGitInfo()
        }
    }

    @MainActor
    func stopBranchMonitor() {
        branchTimer?.invalidate()
        branchTimer = nil
    }
}
