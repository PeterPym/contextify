import Foundation
import Observation

@Observable
final class HUDViewModel {
    enum UIState { case idle, ingesting, success(String), error(String) }

    var branch: String = "main"
    var session: String = "Session-001"
    var status: String = "Ready"
    var state: UIState = .idle
    var urlText: String = ""

    // Destination for outputs; for development keep outside repo by default.
    var outputsDirectory: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Contextify/outputs", isDirectory: true)
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
                content = "Ingested file: \(src.lastPathComponent)\nSaved: \(Date())\n"
            case .url(let u):
                content = "Ingested URL: \(u.absoluteString)\nSaved: \(Date())\n"
            }
            try content.write(to: out, atomically: true, encoding: .utf8)
            state = .success("Saved to outputs: \(out.lastPathComponent)")
            status = "Last: \(out.lastPathComponent)"
        } catch {
            state = .error("Failed to save: \(error.localizedDescription)")
        }
    }

    @MainActor
    func newSession() { session = "Session-\(Int.random(in: 100...999))" }

    @MainActor
    func checkpoint() { status = "Checkpoint at \(Date())" }
}

