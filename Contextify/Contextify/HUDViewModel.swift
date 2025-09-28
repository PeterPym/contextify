import Foundation
import Observation
import OSLog
import Dispatch
import Darwin

enum HUDPreferences {
  static let projectRootKey = "dev.contextify.projectRoot"
  static let projectRootBookmarkKey = "dev.contextify.projectRootBookmark"
  static let autoPersistKey = "dev.contextify.autoPersist"

  private static let sharedDefaults: UserDefaults = {
    UserDefaults(suiteName: "dev.contextify") ?? .standard
  }()

  static func getPersistedRoot() -> String? {
    if let groupValue = sharedDefaults.string(forKey: projectRootKey) {
      return groupValue
    }
    if let legacy = UserDefaults.standard.string(forKey: projectRootKey) {
      // migrate legacy value into shared defaults once
      sharedDefaults.set(legacy, forKey: projectRootKey)
      UserDefaults.standard.removeObject(forKey: projectRootKey)
      return legacy
    }
    return nil
  }

  static func setPersistedRoot(_ path: String?) {
    guard let path, !path.isEmpty else {
      clearPersistedRoot()
      return
    }
    storeRootURL(URL(fileURLWithPath: path))
  }

  static func setPersistedRoot(_ url: URL) {
    storeRootURL(url)
  }

  static func clearPersistedRoot() {
    sharedDefaults.removeObject(forKey: projectRootKey)
    sharedDefaults.removeObject(forKey: projectRootBookmarkKey)
    UserDefaults.standard.removeObject(forKey: projectRootBookmarkKey)
  }

  static func shouldAutoPersist() -> Bool {
    if let value = sharedDefaults.object(forKey: autoPersistKey) as? Bool { return value }
    if let legacy = UserDefaults.standard.object(forKey: autoPersistKey) as? Bool {
      sharedDefaults.set(legacy, forKey: autoPersistKey)
      UserDefaults.standard.removeObject(forKey: autoPersistKey)
      return legacy
    }
    return true
  }

  static func setAutoPersist(_ enabled: Bool) {
    sharedDefaults.set(enabled, forKey: autoPersistKey)
  }

  static func resolveBookmark() -> URL? {
    guard let data = sharedDefaults.data(forKey: projectRootBookmarkKey) else { return nil }
    var stale = false
    do {
      let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
      if stale {
        try storeBookmark(for: url)
      }
      return url
    } catch {
      sharedDefaults.removeObject(forKey: projectRootBookmarkKey)
      return nil
    }
  }

  private static func storeRootURL(_ url: URL) {
    let canonical = url.resolvingSymlinksInPath()
    sharedDefaults.set(canonical.path, forKey: projectRootKey)
    try? storeBookmark(for: canonical)
  }

  private static func storeBookmark(for url: URL) throws {
    let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    sharedDefaults.set(data, forKey: projectRootBookmarkKey)
  }
}

struct GitRepositoryResolver {
  struct GitInfoResult: Sendable {
    let root: URL?
    let branch: String?
    let source: String?
    let shouldPersist: Bool
    let alertMessage: String?
    let clearPersisted: Bool
  }

  static func computeGitInfo(
    environment: [String: String],
    persistedPath: String?,
    currentRoot: URL?,
    autoPersist: Bool
  ) -> GitInfoResult {
    if let envPath = environment["CONTEXTIFY_PROJECT_ROOT"], !envPath.isEmpty {
      let base = URL(fileURLWithPath: envPath).resolvingSymlinksInPath()
      guard FileManager.default.isReadableFile(atPath: base.path) else {
        return GitInfoResult(root: nil, branch: nil, source: nil, shouldPersist: false, alertMessage: "CONTEXTIFY_PROJECT_ROOT is not readable:\n\(base.path)", clearPersisted: false)
      }
      if let root = findGitRoot(startingAt: base) {
        let branch = parseHEAD(at: root) ?? runGitBranch(at: root)
        return GitInfoResult(root: root, branch: branch, source: "env", shouldPersist: autoPersist, alertMessage: nil, clearPersisted: false)
      } else {
        return GitInfoResult(root: nil, branch: nil, source: nil, shouldPersist: false, alertMessage: "CONTEXTIFY_PROJECT_ROOT is not a Git repository:\n\(base.path)", clearPersisted: false)
      }
    }

    if let persistedPath, !persistedPath.isEmpty {
      let base = URL(fileURLWithPath: persistedPath).resolvingSymlinksInPath()
      guard FileManager.default.isReadableFile(atPath: base.path) else {
        return GitInfoResult(root: nil, branch: nil, source: nil, shouldPersist: false, alertMessage: "Stored project root is no longer readable:\n\(base.path)", clearPersisted: true)
      }
      if let root = findGitRoot(startingAt: base) {
        let branch = parseHEAD(at: root) ?? runGitBranch(at: root)
        return GitInfoResult(root: root, branch: branch, source: "saved", shouldPersist: false, alertMessage: nil, clearPersisted: false)
      } else {
        return GitInfoResult(root: nil, branch: nil, source: nil, shouldPersist: false, alertMessage: "Stored project root is not a Git repository:\n\(base.path)", clearPersisted: true)
      }
    }

    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    if let root = findGitRoot(startingAt: cwd) {
      let branch = parseHEAD(at: root) ?? runGitBranch(at: root)
      return GitInfoResult(root: root, branch: branch, source: "cwd", shouldPersist: autoPersist, alertMessage: nil, clearPersisted: false)
    }

    if let currentRoot {
      let branch = parseHEAD(at: currentRoot) ?? runGitBranch(at: currentRoot)
      return GitInfoResult(root: currentRoot, branch: branch, source: "existing", shouldPersist: false, alertMessage: nil, clearPersisted: false)
    }

    return GitInfoResult(root: nil, branch: nil, source: nil, shouldPersist: false, alertMessage: nil, clearPersisted: false)
  }

  static func resolveGitDir(for repoRoot: URL) -> URL? {
    let dotGit = repoRoot.appendingPathComponent(".git")
    var isDir: ObjCBool = false
    let fm = FileManager.default
    if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
      if isDir.boolValue {
        return dotGit
      }
      if let contents = try? String(contentsOf: dotGit, encoding: .utf8) {
        let prefix = "gitdir:"
        if let range = contents.range(of: prefix) {
          let raw = contents[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
          let resolvedURL: URL
          if raw.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: raw, isDirectory: true)
          } else {
            resolvedURL = URL(fileURLWithPath: raw, relativeTo: repoRoot)
          }
          let candidate = resolvedURL.standardizedFileURL
          if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            return candidate
          }
        }
      }
    }
    return nil
  }

  static func headPath(for repoRoot: URL) -> String? {
    resolveGitDir(for: repoRoot)?.appendingPathComponent("HEAD").path
  }

  static func parseHEAD(at repoRoot: URL) -> String? {
    guard let headPath = headPath(for: repoRoot) else { return nil }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: headPath)) else { return nil }
    guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { return nil }
    let head = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if head.hasPrefix("ref:") {
      let ref = head.dropFirst(4).trimmingCharacters(in: .whitespaces)
      return String(ref)
    } else if head.count >= 7 {
      return "detached@" + String(head.prefix(7))
    }
    return nil
  }

  static func findGitRoot(startingAt url: URL, maxDepth: Int = 64) -> URL? {
    var current = url.resolvingSymlinksInPath()
    let fm = FileManager.default
    var visited = Set<URL>()
    var depth = 0
    while depth < maxDepth, visited.insert(current).inserted {
      var isDir: ObjCBool = false
      let dotGit = current.appendingPathComponent(".git")
      if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
        if isDir.boolValue {
          let headPath = dotGit.appendingPathComponent("HEAD").path
          if fm.fileExists(atPath: headPath) { return current }
        }
        if let gitdir = resolveGitDir(for: current) {
          let headPath = gitdir.appendingPathComponent("HEAD").path
          if fm.fileExists(atPath: headPath) { return current }
        }
      }
      let parent = current.deletingLastPathComponent()
      if parent.path == current.path { break }
      current = parent
      depth += 1
    }
    return nil
  }

  static func runGitBranch(at dir: URL, timeout: TimeInterval = 2.0) -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["git", "rev-parse", "--abbrev-ref", "HEAD"]
    task.currentDirectoryURL = dir
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:" + (env["PATH"] ?? "")
    task.environment = env

    let stdout = Pipe()
    let stderr = Pipe()
    task.standardOutput = stdout
    task.standardError = stderr
    defer {
      try? stdout.fileHandleForReading.close()
      try? stderr.fileHandleForReading.close()
    }

    let group = DispatchGroup()
    group.enter()
    task.terminationHandler = { _ in group.leave() }

    do {
      try task.run()
    } catch {
      return nil
    }

    if group.wait(timeout: .now() + timeout) == .timedOut {
      task.terminate()
      _ = group.wait(timeout: .now() + 0.5)
      if task.isRunning {
        kill(task.processIdentifier, SIGKILL)
        _ = group.wait(timeout: .now() + 0.5)
      }
      return nil
    }

    guard task.terminationStatus == 0 else { return nil }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    guard var output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else { return nil }
    if output == "HEAD" {
      if let fallback = parseHEAD(at: dir) { output = fallback }
    }
    return output
  }
}

/// HUDViewModel owns UI presentation state on the main actor; Git and filesystem work run off-main.
@Observable
@MainActor
final class HUDViewModel {
  static let shared = HUDViewModel()

  enum UIState: Equatable { case idle, ingesting, success(String), error(String) }
  enum ProjectRootError: Error, Equatable { case notGit(URL), unreadable(URL) }

  private let gitLog = Logger(subsystem: "dev.contextify", category: "Git")
  private let lifecycleLog = Logger(subsystem: "dev.contextify", category: "Lifecycle")
  private let watcherLog = Logger(subsystem: "dev.contextify", category: "Watcher")

  var branch: String = "—"
  var session: String = "Session-001"
  var status: String = "Ready"
  var lastOutputURL: URL? = nil
  var state: UIState = .idle
  var urlText: String = ""
  var alertMessage: String? = nil
  private(set) var projectRootURL: URL? = nil
  private var branchTimer: Timer? = nil
  private var drainTimer: Timer? = nil
  private var pendingDrainAt: Date = .distantPast
  private var headWatcher: DispatchSourceFileSystemObject? = nil
  private var headWatcherMask: DispatchSource.FileSystemEvent? = nil
  private var headFD: CInt = -1
  private var refWatcher: DispatchSourceFileSystemObject? = nil
  private var refFD: CInt = -1
  private var packedWatcher: DispatchSourceFileSystemObject? = nil
  private var packedFD: CInt = -1
  private var updating = false
  private var pendingUpdate = false
  private var pendingEnvironment: [String: String]? = nil
  private var lastPersistedPath: String?
  private var lastPersistedAt: Date = .distantPast
  private let headEventDebounce: TimeInterval = 0.15
  private var lastHeadEventAt: Date = .distantPast
  private var updateGeneration: UInt64 = 0
  private var hasLoggedMissingGit = false
  private var securityScopedURL: URL? = nil
  private var headWatcherArms: Int = 0

  var branchDisplay: String {
    if branch == "—" { return branch }
    return branch.split(separator: "/").last.map(String.init) ?? branch
  }

  var outputsDirectory: URL {
    let base = FileManager.default.homeDirectoryForCurrentUser
    return base.appendingPathComponent("Contextify/outputs", isDirectory: true)
  }

  init() {
    let persistedPath = HUDPreferences.getPersistedRoot()
    let bookmarkURL = HUDPreferences.resolveBookmark()
    if let path = persistedPath, !path.isEmpty {
      let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath()
      #if DEBUG
      lifecycleLog.info("startup persisted root=\(canonical.path, privacy: .public)")
      #else
      lifecycleLog.info("startup persisted root=\(canonical.path, privacy: .private)")
      #endif
      projectRootURL = canonical
      lastPersistedPath = canonical.path
      lastPersistedAt = Date()
      if let bookmark = bookmarkURL {
        updateSecurityScope(for: bookmark, persisted: true)
      } else {
        updateSecurityScope(for: canonical, persisted: true)
      }
      updateGitInfo()
      updateHeadWatcher()
    } else if let bookmark = bookmarkURL {
      let canonical = bookmark.resolvingSymlinksInPath()
      #if DEBUG
      lifecycleLog.info("startup bookmark root=\(canonical.path, privacy: .public)")
      #else
      lifecycleLog.info("startup bookmark root=\(canonical.path, privacy: .private)")
      #endif
      projectRootURL = canonical
      lastPersistedPath = canonical.path
      lastPersistedAt = Date()
      updateSecurityScope(for: bookmark, persisted: true)
      updateGitInfo()
      updateHeadWatcher()
    } else {
      lifecycleLog.info("startup no persisted root")
    }
  }

  @MainActor deinit {
    lifecycleLog.info("HUDViewModel deinit")
    branchTimer?.invalidate()
    branchTimer = nil
    drainTimer?.invalidate()
    drainTimer = nil
    cancelHeadAndRefWatchers()
    #if os(macOS)
    securityScopedURL?.stopAccessingSecurityScopedResource()
    #endif
    securityScopedURL = nil
  }

  func ingestURLString() async {
    let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), !trimmed.isEmpty else {
      state = .error("Enter a valid URL")
      return
    }
    await ingest(.url(url))
  }

  enum IngestItem: Sendable { case file(URL), url(URL) }

  func ingest(_ item: IngestItem) async {
    state = .ingesting
    let branchSnapshot = branch
    let sessionSnapshot = session
    let outputsDir = outputsDirectory

    let result = await Task.detached(priority: .utility) { () -> Result<(URL, String), Error> in
      do {
        let fm = FileManager.default
        try fm.createDirectory(at: outputsDir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let out = outputsDir.appendingPathComponent("\(stamp).md")

        let content: String
        switch item {
        case .file(let src):
          let ingestDir = outputsDir.appendingPathComponent("ingest", isDirectory: true)
          try fm.createDirectory(at: ingestDir, withIntermediateDirectories: true)
          let copyName = "\(stamp)-\(src.lastPathComponent)"
          let dest = ingestDir.appendingPathComponent(copyName)
          if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
          }
          try fm.copyItem(at: src, to: dest)
          let attrs = try fm.attributesOfItem(atPath: dest.path)
          let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
          content = """
          # File Ingest

          - Source: \(src.path)
          - Copied: ingest/\(copyName)
          - Size: \(size) bytes
          - Session: \(sessionSnapshot)
          - Branch: \(branchSnapshot)
          - Saved: \(Date())

          ## Notes
          - Add a summary here.
          """
        case .url(let u):
          content = """
          # URL Ingest

          - URL: \(u.absoluteString)
          - Session: \(sessionSnapshot)
          - Branch: \(branchSnapshot)
          - Saved: \(Date())

          ## Notes
          - Add findings here.
          """
        }

        try content.write(to: out, atomically: true, encoding: .utf8)
        return .success((out, out.lastPathComponent))
      } catch {
        return .failure(error)
      }
    }.value

    switch result {
    case .success(let payload):
      let (out, name) = payload
      state = .success("Saved to outputs: \(name)")
      status = "Last: \(name)"
      lastOutputURL = out
    case .failure(let error):
      state = .error("Failed to save: \(error.localizedDescription)")
    }
  }

  func newSession() {
    session = "Session-\(Int.random(in: 100...999))"
    urlText = ""
    lastOutputURL = nil
    status = "Ready"
  }

  func checkpoint() async {
    let branchSnapshot = branch
    let sessionSnapshot = session
    let outputsDir = outputsDirectory

    let result = await Task.detached(priority: .utility) { () -> Result<(URL, String), Error> in
      do {
        let fm = FileManager.default
        try fm.createDirectory(at: outputsDir, withIntermediateDirectories: true)
        let cpDir = outputsDir.appendingPathComponent("checkpoints", isDirectory: true)
        try fm.createDirectory(at: cpDir, withIntermediateDirectories: true)
        let ts = Int(Date().timeIntervalSince1970)
        let file = cpDir.appendingPathComponent("checkpoint-\(sessionSnapshot)-\(ts).md")
        let body = """
        # Checkpoint
        - Session: \(sessionSnapshot)
        - Branch: \(branchSnapshot)
        - Timestamp: \(Date())
        """
        try body.write(to: file, atomically: true, encoding: .utf8)
        return .success((file, file.lastPathComponent))
      } catch {
        return .failure(error)
      }
    }.value

    switch result {
    case .success(let payload):
      let (file, name) = payload
      status = "Checkpoint at \(Date())"
      lastOutputURL = file
      state = .success("Saved to outputs: \(name)")
    case .failure(let error):
      state = .error("Failed to save checkpoint: \(error.localizedDescription)")
    }
  }

  func prepareOutputsDirectory() async -> URL {
    let dir = outputsDirectory
    _ = await Task.detached(priority: .utility) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }.value
    return dir
  }

  func updateGitInfo(env: [String: String]? = nil) {
    if updating {
      pendingUpdate = true
      if let env { pendingEnvironment = env }
      scheduleDrain()
      return
    }

    updating = true
    updateGeneration &+= 1
    let generation = updateGeneration
    let envToUse = env ?? ProcessInfo.processInfo.environment
    let persistedPath = HUDPreferences.getPersistedRoot()
    let autoPersist = HUDPreferences.shouldAutoPersist()
    let currentRoot = projectRootURL

    Task.detached { [weak self, envToUse, persistedPath, autoPersist, currentRoot, generation] in
      let info = GitRepositoryResolver.computeGitInfo(
        environment: envToUse,
        persistedPath: persistedPath,
        currentRoot: currentRoot,
        autoPersist: autoPersist
      )
      await MainActor.run { [weak self] in
        guard let self else { return }
        defer {
          self.updating = false
          if self.pendingUpdate {
            let nextEnv = self.pendingEnvironment
            self.pendingUpdate = false
            self.pendingEnvironment = nil
            self.updateGitInfo(env: nextEnv)
          }
        }
        guard generation == self.updateGeneration else { return }
        self.applyGitInfo(info)
      }
    }
  }

  private func applyGitInfo(_ info: GitRepositoryResolver.GitInfoResult) {
    alertMessage = info.alertMessage
    if info.clearPersisted {
      HUDPreferences.clearPersistedRoot()
      lastPersistedPath = nil
      lastPersistedAt = .distantPast
      #if os(macOS)
      securityScopedURL?.stopAccessingSecurityScopedResource()
      #endif
      securityScopedURL = nil
      projectRootURL = nil
      branch = "—"
      status = "Select a Git repository"
      stopBranchMonitor()
      cancelHeadAndRefWatchers()
      pendingUpdate = false
      pendingEnvironment = nil
      return
    }

    guard let root = info.root else {
      #if os(macOS)
      securityScopedURL?.stopAccessingSecurityScopedResource()
      #endif
      securityScopedURL = nil
      projectRootURL = nil
      branch = "—"
      status = "Select a Git repository"
      stopBranchMonitor()
      cancelHeadAndRefWatchers()
      pendingUpdate = false
      pendingEnvironment = nil
      return
    }

    adoptDetectedRoot(root, source: info.source, persist: info.shouldPersist)
    if let br = info.branch, !br.isEmpty {
      branch = br
      hasLoggedMissingGit = false
      #if DEBUG
      gitLog.info("branch=\(br, privacy: .public)")
      #else
      gitLog.info("branch=\(br, privacy: .private)")
      #endif
    } else {
      branch = "—"
      if !hasLoggedMissingGit {
        hasLoggedMissingGit = true
        #if DEBUG
        gitLog.error("Unable to resolve git branch for \(root.path, privacy: .public)")
        #else
        gitLog.error("Unable to resolve git branch for \(root.path, privacy: .private)")
        #endif
      }
    }
  }

  private func adoptDetectedRoot(_ root: URL, source: String?, persist: Bool, forcePersist: Bool = false) {
    let canonical = root.resolvingSymlinksInPath()
    let pathChanged = projectRootURL?.path != canonical.path
    if pathChanged {
      #if os(macOS)
      securityScopedURL?.stopAccessingSecurityScopedResource()
      #endif
      securityScopedURL = nil
    }
    projectRootURL = canonical
    status = "Ready"
    alertMessage = nil
    if persist {
      persistRootIfNeeded(canonical, force: forcePersist)
    }
    updateSecurityScope(for: canonical, persisted: persist)
    if let source {
      #if DEBUG
      gitLog.info("adopted root source=\(source, privacy: .public) path=\(canonical.path, privacy: .public)")
      #else
      gitLog.info("adopted root source=\(source, privacy: .public) path=\(canonical.path, privacy: .private)")
      #endif
    } else {
      #if DEBUG
      gitLog.info("adopted root path=\(canonical.path, privacy: .public)")
      #else
      gitLog.info("adopted root path=\(canonical.path, privacy: .private)")
      #endif
    }
    if pathChanged || headWatcher == nil {
      updateHeadWatcher()
    }
  }

  private func persistRootIfNeeded(_ url: URL, force: Bool = false) {
    let canonical = url.resolvingSymlinksInPath()
    let path = canonical.path
    let now = Date()
    guard force || path != lastPersistedPath || now.timeIntervalSince(lastPersistedAt) > 5 else { return }
    HUDPreferences.setPersistedRoot(canonical)
    lastPersistedPath = path
    lastPersistedAt = now
  }

  func setProjectRoot(url: URL) -> Result<URL, ProjectRootError> {
    let canonical = url.resolvingSymlinksInPath()
    guard FileManager.default.isReadableFile(atPath: canonical.path) else {
      alertMessage = "Selected folder is not readable:\n\(canonical.path)"
      status = "Select a Git repository"
      return .failure(.unreadable(canonical))
    }
    guard let repo = GitRepositoryResolver.findGitRoot(startingAt: canonical) else {
      alertMessage = "Selected folder is not a Git repository:\n\(canonical.path)"
      status = "Select a Git repository"
      return .failure(.notGit(canonical))
    }
    adoptDetectedRoot(repo, source: "manual", persist: true, forcePersist: true)
    updateGitInfo()
    return .success(repo)
  }

  func startBranchMonitor(interval: TimeInterval = 2.0) {
    branchTimer?.invalidate()
    branchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      self?.updateGitInfo()
    }
  }

  func stopBranchMonitor() {
    branchTimer?.invalidate()
    branchTimer = nil
  }

  func updateHeadWatcher() {
    cancelHeadAndRefWatchers()

    let base: URL = {
      if let current = projectRootURL { return current }
      if let saved = HUDPreferences.getPersistedRoot() {
        return URL(fileURLWithPath: saved)
      }
      return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()

    guard let root = GitRepositoryResolver.findGitRoot(startingAt: base) else {
      stopBranchMonitor()
      return
    }
    guard let headPath = GitRepositoryResolver.headPath(for: root) else {
      stopBranchMonitor()
      return
    }

    headFD = open(headPath, O_EVTONLY)
    guard headFD >= 0 else {
      watcherLog.error("Failed to open HEAD for watching; falling back to timer")
      startBranchMonitor()
      return
    }

    stopBranchMonitor()
    let eventMask: DispatchSource.FileSystemEvent = [.write, .attrib, .extend, .delete, .rename, .revoke]
    let src = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: headFD,
      eventMask: eventMask,
      queue: .main
    )
    src.setEventHandler { [weak self, weak src] in
      guard let self else { return }
      let events = src?.data ?? []
      self.handleHeadEvent(events: events)
    }
    src.setCancelHandler { [weak self] in
      self?.handleWatcherCancelled()
    }
    headWatcher = src
    headWatcherMask = eventMask
    headWatcherArms += 1
    #if DEBUG
    watcherLog.info("Armed HEAD watcher for \(headPath, privacy: .public)")
    #else
    watcherLog.info("Armed HEAD watcher for \(headPath, privacy: .private)")
    #endif
    src.resume()
    armRefWatchers(for: root)
  }

  private func handleHeadEvent(events: DispatchSource.FileSystemEvent) {
    if let mask = headWatcherMask {
      let critical: DispatchSource.FileSystemEvent = [.delete, .rename, .revoke]
      if mask.intersection(critical) != critical {
        watcherLog.fault("HEAD watcher missing critical events mask=\(mask.rawValue, privacy: .public)")
      }
    }

    let now = Date()
    if now.timeIntervalSince(lastHeadEventAt) > headEventDebounce {
      lastHeadEventAt = now
      updateGitInfo()
    } else {
      lastHeadEventAt = now
      pendingUpdate = true
      scheduleDrain()
    }

    if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
      updateHeadWatcher()
    }
  }

  private func handleWatcherCancelled() {
    closeFD(&headFD)
    headWatcher = nil
    headWatcherMask = nil
    tearDownRefWatchers()
  }

  private func scheduleDrain() {
    let scheduledAt = Date()
    pendingDrainAt = scheduledAt
    drainTimer?.invalidate()
    let timer = Timer(timeInterval: headEventDebounce, repeats: false) { [weak self] _ in
      guard let self, self.pendingDrainAt == scheduledAt else { return }
      self.pendingDrainAt = .distantPast
      if self.pendingUpdate {
        if self.updating {
          self.pendingUpdate = true
        } else {
          self.pendingUpdate = false
          self.updateGitInfo()
        }
      }
    }
    drainTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func updateSecurityScope(for url: URL, persisted: Bool) {
    #if os(macOS)
    securityScopedURL?.stopAccessingSecurityScopedResource()
    securityScopedURL = nil
    if persisted, let bookmark = HUDPreferences.resolveBookmark(), bookmark.startAccessingSecurityScopedResource() {
      securityScopedURL = bookmark
    } else if url.startAccessingSecurityScopedResource() {
      securityScopedURL = url
    } else if persisted {
      HUDPreferences.clearPersistedRoot()
      alertMessage = "Stored project root is no longer accessible."
    }
    #else
    #endif
  }

  private func tearDownRefWatchers() {
    refWatcher?.cancel()
    refWatcher = nil
    closeRefFD()

    packedWatcher?.cancel()
    packedWatcher = nil
    closePackedFD()
  }

  private func refPath(for root: URL) -> String? {
    guard let ref = GitRepositoryResolver.parseHEAD(at: root), ref.hasPrefix("refs/") else { return nil }
    guard let gitDir = GitRepositoryResolver.resolveGitDir(for: root) else { return nil }
    return gitDir.appendingPathComponent(ref).path
  }

  private func armRefWatchers(for root: URL) {
    tearDownRefWatchers()

    if let path = refPath(for: root) {
      refFD = open(path, O_EVTONLY)
      if refFD >= 0 {
        let src = DispatchSource.makeFileSystemObjectSource(
          fileDescriptor: refFD,
          eventMask: [.write, .attrib, .extend, .delete, .rename, .revoke],
          queue: .main
        )
        src.setEventHandler { [weak self] in self?.updateGitInfo() }
        src.setCancelHandler { [weak self] in
          self?.closeRefFD()
        }
        refWatcher = src
        src.resume()
      } else {
        closeRefFD()
      }
    }

    if let gitDir = GitRepositoryResolver.resolveGitDir(for: root) {
      let packed = gitDir.appendingPathComponent("packed-refs").path
      packedFD = open(packed, O_EVTONLY)
      if packedFD >= 0 {
        let src = DispatchSource.makeFileSystemObjectSource(
          fileDescriptor: packedFD,
          eventMask: [.write, .delete, .rename, .revoke],
          queue: .main
        )
        src.setEventHandler { [weak self] in self?.updateGitInfo() }
        src.setCancelHandler { [weak self] in
          self?.closePackedFD()
        }
        packedWatcher = src
        src.resume()
      } else {
        closePackedFD()
      }
    }
  }

  private func closeFD(_ fd: inout CInt) {
    if fd >= 0 {
      close(fd)
      fd = -1
    }
  }

  private func closeRefFD() {
    closeFD(&refFD)
  }

  private func closePackedFD() {
    closeFD(&packedFD)
  }

  private func cancelHeadAndRefWatchers() {
    headWatcher?.cancel()
    headWatcher = nil
    headWatcherMask = nil
    closeFD(&headFD)
    tearDownRefWatchers()
    drainTimer?.invalidate()
    drainTimer = nil
    pendingDrainAt = .distantPast
  }

  #if DEBUG
  var debugIsUpdating: Bool { updating }
  var debugPendingUpdate: Bool { pendingUpdate }
  var debugHeadWatcherMask: DispatchSource.FileSystemEvent? { headWatcherMask }
  var debugHeadWatcherArms: Int { headWatcherArms }
  func debugHandleHeadEvent(_ events: DispatchSource.FileSystemEvent) { handleHeadEvent(events: events) }
  #endif
}
