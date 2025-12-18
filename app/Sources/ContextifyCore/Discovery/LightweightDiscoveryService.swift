import Foundation
import OSLog
import CryptoKit

private let log = Logger(subsystem: "dev.contextify", category: "LightweightDiscovery")

/// Fast filesystem scanner that returns project metadata WITHOUT reading file contents or writing to DB
/// Goal: <200ms for typical setup (19 projects, 663 transcripts)
public actor LightweightDiscoveryService {

  private var accessProvider: TranscriptAccessProvider?

  public init(accessProvider: TranscriptAccessProvider? = nil) {
    self.accessProvider = accessProvider
  }

  /// Configure the access provider (allows late binding for App Store builds)
  public func configure(accessProvider: TranscriptAccessProvider) {
    log.info("[DISC-LIGHT] ▶ Configuring access provider (late binding)")
    self.accessProvider = accessProvider
    log.info("[DISC-LIGHT] ✅ Access provider configured")
  }

  /// Scans filesystem for project metadata. NO DB SIDE EFFECTS.
  /// Returns projects sorted by last activity (newest first), merged by canonical path.
  public func discoverProjectsLightweight() async -> [LightweightProject] {
    log.info("[DISC-LIGHT] Starting lightweight scan...")
    let start = Date()

    // Log provider state for debugging permission issues
    if let provider = accessProvider {
      let hasClaude = (try? provider.withAccess(for: TranscriptProviderID.claude) { _ in true }) ?? false
      let hasCodex = (try? provider.withAccess(for: TranscriptProviderID.codex) { _ in true }) ?? false
      log.info("[DISC-LIGHT] Provider state: claude=\(hasClaude ? "✓" : "✗"), codex=\(hasCodex ? "✓" : "✗")")
    } else {
      log.info("[DISC-LIGHT] Provider state: nil (DMG build, direct filesystem access)")
    }

    async let claudeProjectsTask = scanClaudeProjects()
    async let codexProjectsTask = scanCodexSessions()

    let claudeProjects = await claudeProjectsTask
    var codexProjects = await codexProjectsTask

    // Remap Codex project paths to Claude roots using longest-prefix matching
    // This recovers orphaned sessions from nested project structures
    codexProjects = remapCodexToClaudeRoots(
      claudeProjects: claudeProjects,
      codexProjects: codexProjects
    )

    let rawProjects = claudeProjects + codexProjects

    // Count transcript files per provider for startup diagnostics
    let claudeTranscriptCount = claudeProjects.reduce(0) { $0 + $1.transcriptCount }
    let codexTranscriptCount = codexProjects.reduce(0) { $0 + $1.transcriptCount }
    log.info("[DISC-LIGHT] Filesystem transcripts: Claude=\(claudeTranscriptCount, privacy: .public), Codex=\(codexTranscriptCount, privacy: .public)")
    log.debug("[DISC-LIGHT] Raw discoveries: \(rawProjects.count, privacy: .public) (Claude: \(claudeProjects.count, privacy: .public), Codex: \(codexProjects.count, privacy: .public))")

    // Merge projects with same canonical path (e.g., Claude + Codex for same directory)
    let merged = mergeByCanonicalPath(rawProjects)

    var all = merged
    all.sort { $0.lastActivity > $1.lastActivity }

    let duration = Date().timeIntervalSince(start)
    log.info("[DISC-LIGHT] Scan complete in \(String(format: "%.3f", duration), privacy: .public)s. Found \(all.count, privacy: .public) projects (merged from \(rawProjects.count, privacy: .public) discoveries).")

    return all
  }

  /// Merge projects that point to the same canonical path.
  /// This handles multi-provider scenarios (Claude + Codex for same project).
  /// Internal visibility for testing.
  nonisolated func mergeByCanonicalPath(_ projects: [LightweightProject]) -> [LightweightProject] {
    var merged: [String: LightweightProject] = [:]

    for project in projects {
      let key = project.canonicalRootPath

      if let existing = merged[key] {
        // Merge: combine transcripts, keep most recent activity, mark as multi-provider
        // Dedupe by standardized file path to avoid counting same file twice
        let combinedFiles = existing.transcriptFiles + project.transcriptFiles
        let deduped = Array(
          Dictionary(grouping: combinedFiles) { $0.standardizedFileURL.path }
            .compactMapValues { $0.first }
            .values
        ).sorted { $0.path < $1.path }  // Sort for deterministic ordering

        let providers = Set([existing.provider, project.provider])
        let providerStr = providers.count > 1 ? "multi" : existing.provider

        merged[key] = LightweightProject(
          id: existing.id,  // Keep first ID for consistency
          path: existing.path,
          displayName: existing.displayName,
          transcriptCount: deduped.count,
          lastActivity: max(existing.lastActivity, project.lastActivity),
          provider: providerStr,
          cwd: existing.cwd ?? project.cwd,
          transcriptFiles: deduped
        )
        log.debug("[DISC-LIGHT-MERGE] Merged \(project.displayName, privacy: .public) (\(project.provider, privacy: .public)) into existing (\(existing.provider, privacy: .public)), deduped \(combinedFiles.count, privacy: .public) -> \(deduped.count, privacy: .public) files")
      } else {
        merged[key] = project
      }
    }

    return Array(merged.values)
  }

  /// Remap Codex project paths to Claude roots using longest-prefix matching.
  /// This recovers orphaned sessions from nested project structures (Issue #1).
  ///
  /// Example: Codex sessions with cwd `/repo/subdir` get assigned to Claude project root `/repo`.
  ///
  /// - Parameters:
  ///   - claudeProjects: Projects discovered from ~/.claude/projects
  ///   - codexProjects: Projects discovered from ~/.codex/sessions
  /// - Returns: Updated Codex projects with paths remapped to Claude roots
  nonisolated func remapCodexToClaudeRoots(
    claudeProjects: [LightweightProject],
    codexProjects: [LightweightProject]
  ) -> [LightweightProject] {
    guard !codexProjects.isEmpty else { return codexProjects }
    guard !claudeProjects.isEmpty else {
      log.info("[CODEX-REMAP] No Claude projects found - keeping \(codexProjects.count, privacy: .public) Codex-only projects")
      return codexProjects
    }

    // Extract known Claude project roots (canonicalized, deduped, sorted by length descending)
    // Sorting by length descending allows early-break on first match (longest prefix wins)
    let knownRoots = Array(Set(claudeProjects.map { $0.canonicalRootPath }))
      .sorted { $0.count > $1.count }

    // Instrumentation counters
    var exactMatches = 0
    var prefixMatches = 0
    var codexOnlyMatches = 0

    var remapped: [LightweightProject] = []

    for project in codexProjects {
      guard let cwd = project.cwd else {
        log.debug("[CODEX-REMAP] Skipping project without cwd: \(project.displayName, privacy: .public)")
        remapped.append(project)
        continue
      }

      // Canonicalize CWD to match canonicalRootPath normalization
      let cwdNorm = PathUtils.canonicalizePath(cwd)

      // Find longest matching prefix from knownRoots (sorted by length desc, so first match wins)
      // Boundary-aware: cwd == root OR cwd starts with root + "/"
      var assignedRoot: String? = nil
      for root in knownRoots {
        if cwdNorm == root || cwdNorm.hasPrefix(root + "/") {
          assignedRoot = root
          break  // First match is longest (sorted by length desc)
        }
      }

      if let assignedRoot = assignedRoot {
        // Remap project to Claude root
        let isExact = (cwdNorm == assignedRoot)
        if isExact {
          exactMatches += 1
        } else {
          prefixMatches += 1
        }

        // Create new project with updated path
        let remappedProject = LightweightProject(
          id: project.id,
          path: URL(fileURLWithPath: assignedRoot),
          displayName: project.displayName,
          transcriptCount: project.transcriptCount,
          lastActivity: project.lastActivity,
          provider: project.provider,
          cwd: cwd,  // Keep original CWD for reference
          transcriptFiles: project.transcriptFiles
        )
        remapped.append(remappedProject)

        log.debug("[CODEX-REMAP] Remapped \(cwdNorm, privacy: .private) -> \(assignedRoot, privacy: .private) (\(isExact ? "exact" : "prefix", privacy: .public))")
      } else {
        // No prefix match - keep as Codex-only project
        codexOnlyMatches += 1
        remapped.append(project)

        // Sanitize path for logging (SHA256 first 12 hex chars)
        let hash = SHA256.hash(data: Data(cwdNorm.utf8))
        let sanitized = hash.prefix(6).map { String(format: "%02x", $0) }.joined()
        log.info("[CODEX-REMAP] Codex-only project: \(sanitized, privacy: .public) (no Claude root match)")
      }
    }

    log.info("[CODEX-REMAP] Match breakdown: exact=\(exactMatches, privacy: .public) prefix=\(prefixMatches, privacy: .public) codex-only=\(codexOnlyMatches, privacy: .public) total=\(codexProjects.count, privacy: .public)")

    return remapped
  }

  // MARK: - Claude Projects (~/.claude/projects/HASH/*.jsonl)

  private func scanClaudeProjects() -> [LightweightProject] {
    // Use access provider if available (App Store builds), otherwise fallback to direct access (DMG builds)
    if let provider = accessProvider {
      do {
        return try provider.withAccess(for: TranscriptProviderID.claude) { root in
          log.debug("[DISC-LIGHT] Claude root URL from provider: \(root.path, privacy: .public)")
          return scanClaudeDirectory(at: root)
        }
      } catch {
        log.debug("[DISC-LIGHT] No Claude access authorized: \(error.localizedDescription, privacy: .public)")
        return []
      }
    } else {
      // No access provider - this is expected for DMG builds but a BUG for sandbox builds
      if Sandbox.isSandboxed {
        log.error("[DISC-LIGHT] BUG: no access provider in sandbox; this path should be unreachable. Discovery will use container path and find 0 projects.")
      }

      let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
      log.debug("[DISC-LIGHT] Claude root (no access provider - fallback): \(root.path, privacy: .public)")
      return scanClaudeDirectory(at: root)
    }
  }

  nonisolated private func scanClaudeDirectory(at root: URL) -> [LightweightProject] {
    log.debug("[DISC-LIGHT] scanClaudeDirectory called with root: \(root.path, privacy: .public)")

    let dirs: [URL]
    do {
      dirs = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
      log.info("[DISC-LIGHT] Found \(dirs.count, privacy: .public) entries in Claude directory")
    } catch {
      log.error("[DISC-LIGHT] Failed to enumerate Claude directory at \(root.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return []
    }

    guard !dirs.isEmpty else {
      log.debug("[DISC-LIGHT] Claude directory is empty: \(root.path, privacy: .public)")
      return []
    }

    return dirs.map { dir -> LightweightProject in
      // Optimization: Use directory mtime as proxy for activity
      // This avoids opening/reading individual files (saves syscalls)
      let mtime = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast

      // Scan for .jsonl files (need full URLs for JIT ingestion)
      let files = (try? FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ))?.filter { $0.pathExtension == "jsonl" } ?? []

      let hashFolder = dir.lastPathComponent

      let realPath = resolveClaudeProjectPath(hashFolder: hashFolder, directory: dir, transcripts: files)
      let displayName = realPath.map { URL(fileURLWithPath: $0).lastPathComponent }
        ?? fallbackDisplayName(for: hashFolder)

      return LightweightProject(
        id: hashFolder,  // Keep hash as ID for consistency
        path: dir,  // Keep original hash folder path for filesystem ops
        displayName: displayName,  // Friendly name for UI (validated)
        transcriptCount: files.count,
        lastActivity: mtime,
        provider: "claude.code",
        cwd: realPath,  // Store decoded real path (may not exist if orphaned)
        transcriptFiles: files  // Store file URLs for JIT ingestion
      )
    }
  }

  // MARK: - Codex Sessions (~/.codex/sessions/YYYY/MM/DD/*.jsonl)

  private func scanCodexSessions() async -> [LightweightProject] {
    // Get root URL - either from access provider (App Store) or direct (DMG)
    let root: URL

    if let provider = accessProvider {
      // For sandboxed builds, verify we have access and get the root URL
      do {
        root = try provider.withAccess(for: TranscriptProviderID.codex) { url in
          return url
        }
      } catch {
        log.debug("[DISC-LIGHT] No Codex access authorized: \(error.localizedDescription, privacy: .public)")
        return []
      }
    } else {
      // DMG build: direct filesystem access
      root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")
    }

    // Security-scoped access is already established by the bookmark resolution in ContextifyApp
    // We can now safely do async scanning
    return await scanCodexDirectory(at: root)
  }

  private func scanCodexDirectory(at root: URL) async -> [LightweightProject] {
    // Aggregate by CWD (current working directory)
    // Store file URLs per project (not just count)
    var projects: [String: (files: [URL], maxDate: Date, path: URL)] = [:]

    // Helper to peek first few lines for CWD
    // Uses shared helper that supports both Claude Code and Codex formats
    // Scans up to 5 lines to find CWD (session_meta may not be first line)
    func getCWD(url: URL) -> String? {
      guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
      defer { try? handle.close() }

      // Read 64KB to capture first line (Codex session_meta can be 30KB+ with large AGENTS.md)
      guard let data = try? handle.read(upToCount: 65536),
            let str = String(data: data, encoding: .utf8) else {
        return nil
      }

      // Scan first 5 non-empty lines for CWD
      let lines = str.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .prefix(5)

      for line in lines {
        if let cwd = ProjectIdentity.extractCwdFromJSONLine(line) {
          return cwd
        }
      }

      return nil
    }

    // Use FileManager.enumerator to walk tree efficiently
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      log.debug("[DISC-LIGHT] No Codex sessions directory found at \(root.path, privacy: .public)")
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

    // Track CWD extraction failures for aggregate reporting
    var cwdFailureCount = 0
    var cwdFailureFiles: [URL] = []

    // Parallel process headers to extract CWD, but cap concurrency to avoid FD pressure.
    let batchSize = 64
    var index = 0

    while index < files.count {
      let end = min(index + batchSize, files.count)
      let slice = files[index..<end]

      await withTaskGroup(of: (String?, Date, URL).self) { group in
        for url in slice {
          group.addTask {
            let cwd = getCWD(url: url)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return (cwd, date, url)
          }
        }

        for await (cwd, date, url) in group {
          if let cwd = cwd {
            // Aggregate by CWD - collect file URLs
            if var p = projects[cwd] {
              p.files.append(url)  // Accumulate file list
              p.maxDate = max(p.maxDate, date)
              projects[cwd] = p
            } else {
              projects[cwd] = ([url], date, URL(fileURLWithPath: cwd))
            }
          } else {
            // CWD extraction failed - track for fallback bucket
            cwdFailureCount += 1
            cwdFailureFiles.append(url)
            log.debug("[DISC-LIGHT] getCWD failed for Codex transcript: \(url.lastPathComponent, privacy: .private)")
          }
        }
      }

      index = end
    }

    // Log aggregate failure count at info level (not just per-file debug)
    if cwdFailureCount > 0 {
      log.info("[DISC-LIGHT] CWD extraction failed for \(cwdFailureCount, privacy: .public) Codex transcripts")
    }

    log.info("[DISC-LIGHT] Codex scan produced \(projects.count, privacy: .public) projects from \(files.count, privacy: .public) transcripts (failures: \(cwdFailureCount, privacy: .public))")

    // Convert to LightweightProject array
    var result = projects.map { cwd, data in
      // Generate stable ID from path (base64 encoding)
      let id = cwd.data(using: .utf8)!.base64EncodedString()
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "+", with: "-")

      return LightweightProject(
        id: id,
        path: data.path,
        displayName: URL(fileURLWithPath: cwd).lastPathComponent,  // Derive name from CWD
        transcriptCount: data.files.count,
        lastActivity: data.maxDate,
        provider: "codex.cli",
        cwd: cwd,
        transcriptFiles: data.files  // Pass file URLs for JIT ingestion
      )
    }

    // Create fallback bucket for transcripts with CWD extraction failures
    // These are still ingested so they remain searchable and inspectable
    if !cwdFailureFiles.isEmpty {
      let maxDate = cwdFailureFiles.compactMap {
        (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      }.max() ?? Date.distantPast

      // Root-specific ID to avoid collisions across multiple Codex roots/profiles
      let rootHash = SHA256.hash(data: Data(root.path.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
      let unknownId = "codex-unknown-cwd-\(rootHash)"

      let unknownProject = LightweightProject(
        id: unknownId,
        path: root,
        displayName: "Unknown Codex Sessions",
        transcriptCount: cwdFailureFiles.count,
        lastActivity: maxDate,
        provider: "codex.cli",
        cwd: nil,  // No CWD - these couldn't be extracted
        transcriptFiles: cwdFailureFiles
      )
      result.append(unknownProject)
      log.info("[DISC-LIGHT] Created fallback bucket for \(cwdFailureFiles.count, privacy: .public) Codex transcripts with CWD extraction failures")
    }

    return result
  }

  // MARK: - Helper Functions

  /// Intelligently decode Claude hash folder to real filesystem path
  /// Handles hyphenated folder names by trying progressive combinations
  nonisolated private func findRealPath(hashFolder: String) -> String? {
    guard hashFolder.hasPrefix("-") else { return nil }

    let base = "/" + hashFolder.dropFirst()
    let components = base.components(separatedBy: "-")

    for mergeCount in 0..<components.count {
      var testComponents = components

      if mergeCount > 0 {
        let mergeStart = max(0, testComponents.count - mergeCount - 1)
        let merged = testComponents[mergeStart...].joined(separator: "-")
        testComponents = Array(testComponents[..<mergeStart]) + [merged]
      }

      let testPath = testComponents.joined(separator: "/")
      if FileManager.default.fileExists(atPath: testPath) {
        log.debug("[DISC-LIGHT] Found real path via validation: \(testPath) (mergeCount: \(mergeCount))")
        return testPath
      }
    }

    return nil
  }

  /// Attempt to resolve the actual project path using transcript metadata, even for orphaned projects.
  nonisolated private func resolveClaudeProjectPath(hashFolder: String, directory: URL, transcripts: [URL]) -> String? {
    guard hashFolder.hasPrefix("-") else { return nil }

    if let path = try? ProjectIdentity.reverseManglePath(provider: "claude.code", directory: directory) {
      return path
    }

    if let transcriptPath = inferPathFromTranscripts(transcripts) {
      return transcriptPath
    }

    return findRealPath(hashFolder: hashFolder)
  }

  nonisolated private func inferPathFromTranscripts(_ transcripts: [URL]) -> String? {
    guard !transcripts.isEmpty else { return nil }

    let sorted = transcripts.sorted { lhs, rhs in
      let lhsSize = (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      let rhsSize = (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      return lhsSize > rhsSize
    }

    for file in sorted {
      if let cwd = try? ProjectIdentity.extractCwdFromTranscriptForOrphaned(file),
         !cwd.isEmpty {
        return PathUtils.canonicalizePath(cwd)
      }
    }

    return nil
  }

  nonisolated private func fallbackDisplayName(for hashFolder: String) -> String {
    guard hashFolder.hasPrefix("-") else {
      return "Claude (\(String(hashFolder.prefix(8))))"
    }

    let simpleDecoded = "/" + hashFolder.dropFirst().replacingOccurrences(of: "-", with: "/")
    let last = URL(fileURLWithPath: simpleDecoded).lastPathComponent
    return last.isEmpty ? hashFolder : last
  }
}
