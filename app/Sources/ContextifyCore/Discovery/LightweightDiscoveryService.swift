import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "LightweightDiscovery")

/// Fast filesystem scanner that returns project metadata WITHOUT reading file contents or writing to DB
/// Goal: <200ms for typical setup (19 projects, 663 transcripts)
public actor LightweightDiscoveryService {

  public init() {}

  /// Scans filesystem for project metadata. NO DB SIDE EFFECTS.
  /// Returns projects sorted by last activity (newest first)
  public func discoverProjectsLightweight() async -> [LightweightProject] {
    log.info("[DISC-LIGHT] Starting lightweight scan...")
    let start = Date()

    async let claudeProjects = scanClaudeProjects()
    async let codexProjects = scanCodexSessions()

    var all = await claudeProjects + codexProjects
    all.sort { $0.lastActivity > $1.lastActivity }

    let duration = Date().timeIntervalSince(start)
    log.info("[DISC-LIGHT] Scan complete in \(String(format: "%.3f", duration), privacy: .public)s. Found \(all.count, privacy: .public) projects.")

    return all
  }

  // MARK: - Claude Projects (~/.claude/projects/HASH/*.jsonl)

  private func scanClaudeProjects() -> [LightweightProject] {
    let root = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/projects")

    guard let dirs = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      log.debug("[DISC-LIGHT] No Claude projects directory found")
      return []
    }

    return dirs.compactMap { dir -> LightweightProject? in
      // Optimization: Use directory mtime as proxy for activity
      // This avoids opening/reading individual files (saves syscalls)
      let mtime = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast

      // Quick count via stat (fast - just counts directory entries)
      let count = (try? FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".jsonl") }.count) ?? 0

      // Claude folder names are hashed paths - use as stable ID
      return LightweightProject(
        id: dir.lastPathComponent,
        path: dir,
        transcriptCount: count,
        lastActivity: mtime,
        provider: "claude.code"
      )
    }
  }

  // MARK: - Codex Sessions (~/.codex/sessions/YYYY/MM/DD/*.jsonl)

  private func scanCodexSessions() async -> [LightweightProject] {
    let root = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/sessions")

    // Aggregate by CWD (current working directory)
    var projects: [String: (count: Int, maxDate: Date, path: URL)] = [:]

    // Helper to peek first line for CWD
    // This is the ONLY file read we do - just first 256 bytes for header
    func getCWD(url: URL) -> String? {
      guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
      defer { try? handle.close() }

      // Read just 256 bytes for header (fast)
      guard let data = try? handle.read(upToCount: 256),
            let str = String(data: data, encoding: .utf8),
            let firstLine = str.components(separatedBy: .newlines).first,
            let lineData = firstLine.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
            let cwd = json["cwd"] as? String else {
        return nil
      }

      return cwd
    }

    // Use FileManager.enumerator to walk tree efficiently
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      log.debug("[DISC-LIGHT] No Codex sessions directory found")
      return []
    }

    // Gather .jsonl files (synchronous - enumerator is not async-friendly)
    var files: [URL] = []
    while let fileURL = enumerator.nextObject() as? URL {
      if fileURL.pathExtension == "jsonl" {
        files.append(fileURL)
      }
    }

    log.debug("[DISC-LIGHT] Found \(files.count, privacy: .public) Codex transcripts")

    // Parallel process headers to extract CWD
    // This is the only place we read file contents (first line only)
    await withTaskGroup(of: (String, Date)?.self) { group in
      for url in files {
        group.addTask {
          guard let cwd = getCWD(url: url) else { return nil }
          let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
          return (cwd, date)
        }
      }

      for await result in group {
        if let (cwd, date) = result {
          // Aggregate by CWD
          if var p = projects[cwd] {
            p.count += 1
            p.maxDate = max(p.maxDate, date)
            projects[cwd] = p
          } else {
            projects[cwd] = (1, date, URL(fileURLWithPath: cwd))
          }
        }
      }
    }

    // Convert to LightweightProject array
    return projects.map { cwd, data in
      // Generate stable ID from path (base64 encoding)
      let id = cwd.data(using: .utf8)!.base64EncodedString()
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "+", with: "-")

      return LightweightProject(
        id: id,
        path: data.path,
        transcriptCount: data.count,
        lastActivity: data.maxDate,
        provider: "codex.cli"
      )
    }
  }
}
