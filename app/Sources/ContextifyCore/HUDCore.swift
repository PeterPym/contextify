import Foundation
import Observation
import OSLog
import Dispatch
import Darwin

#if os(macOS)
import AppKit
#endif

// MARK: - HUDPreferences

public enum HUDPreferences {
  public static let projectRootKey = "dev.contextify.projectRoot"
  public static let projectRootBookmarkKey = "dev.contextify.projectRootBookmark"
  public static let autoPersistKey = "dev.contextify.autoPersist"

  // Database location
  public static let customDatabaseLocationKey = "dev.contextify.customDatabaseLocation"
  public static let customDatabaseBookmarkKey = "dev.contextify.customDatabaseBookmark"

  // App Store onboarding
  public static let appStoreOnboardingCompletedKey = "dev.contextify.appStoreOnboardingCompleted"

  nonisolated(unsafe) private static let sharedDefaults: UserDefaults = {
    if let suite = UserDefaults(suiteName: "dev.contextify"), probeDefaultsWriteability(suite) {
      return suite
    }
    return .standard
  }()

  // Actor to safely track warning state (prevents race conditions)
  private actor WarningTracker {
    private var hasWarned = false

    func shouldWarn() -> Bool {
      if hasWarned {
        return false
      }
      hasWarned = true
      return true
    }
  }

  private static let warningTracker = WarningTracker()

  public static func getPersistedRoot() -> String? {
    warnIfLegacyDefaultsPresent()
    return sharedDefaults.string(forKey: projectRootKey)
  }

  public static func setPersistedRoot(_ path: String?) {
    guard let path, !path.isEmpty else {
      clearPersistedRoot()
      return
    }
    storeRootURL(URL(fileURLWithPath: path))
  }

  public static func setPersistedRoot(_ url: URL) {
    storeRootURL(url)
  }

  public static func clearPersistedRoot() {
    sharedDefaults.removeObject(forKey: projectRootKey)
    sharedDefaults.removeObject(forKey: projectRootBookmarkKey)
  }

  public static func shouldAutoPersist() -> Bool {
    warnIfLegacyDefaultsPresent()
    if let value = sharedDefaults.object(forKey: autoPersistKey) as? Bool { return value }
    return true
  }

  public static func setAutoPersist(_ enabled: Bool) {
    sharedDefaults.set(enabled, forKey: autoPersistKey)
  }

  // MARK: - Database Location

  public static func getCustomDatabaseLocation() -> String? {
    warnIfLegacyDefaultsPresent()
    return sharedDefaults.string(forKey: customDatabaseLocationKey)
  }

  public static func setCustomDatabaseLocation(_ path: String?) {
    guard let path, !path.isEmpty else {
      clearCustomDatabaseLocation()
      return
    }
    storeDatabaseURL(URL(fileURLWithPath: path))
  }

  public static func setCustomDatabaseLocation(_ url: URL) {
    storeDatabaseURL(url)
  }

  public static func clearCustomDatabaseLocation() {
    sharedDefaults.removeObject(forKey: customDatabaseLocationKey)
    sharedDefaults.removeObject(forKey: customDatabaseBookmarkKey)
  }

  public static func resolveDatabaseBookmark() -> URL? {
    guard let data = sharedDefaults.data(forKey: customDatabaseBookmarkKey) else { return nil }
    return resolveBookmarkData(data, pathKey: customDatabaseLocationKey, bookmarkKey: customDatabaseBookmarkKey)
  }

  // MARK: - App Store Onboarding

  /// Returns true if the user has completed the App Store onboarding wizard.
  ///
  /// **App Store builds:** Requires BOTH the completion flag AND a resolvable database bookmark.
  /// This ensures we don't proceed with DB access if the user's chosen folder was deleted.
  ///
  /// **DMG builds:** Always returns true at compile-time (onboarding not required).
  public static func hasCompletedAppStoreOnboarding() -> Bool {
    #if APPSTORE_BUILD
    // 1) Flag must be set
    guard sharedDefaults.bool(forKey: appStoreOnboardingCompletedKey) else { return false }

    // 2) Bookmark must resolve
    guard let url = resolveDatabaseBookmark() else { return false }

    // 3) Resolved URL must exist and be a directory
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      return false
    }

    return true
    #else
    // DMG builds never gate on onboarding
    return true
    #endif
  }

  #if DEBUG
  /// Testing helper that evaluates App Store onboarding completeness using
  /// App Store semantics even in non-App Store builds.
  public static func hasCompletedAppStoreOnboardingForTesting() -> Bool {
    guard sharedDefaults.bool(forKey: appStoreOnboardingCompletedKey) else { return false }
    guard let url = resolveDatabaseBookmark() else { return false }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      return false
    }
    return true
  }
  #endif

  /// Sets the App Store onboarding completion state.
  public static func setAppStoreOnboardingCompleted(_ completed: Bool) {
    sharedDefaults.set(completed, forKey: appStoreOnboardingCompletedKey)
  }

  /// Clears both the onboarding completion flag AND the database bookmark.
  /// Used when user resets database location in Settings or when bookmark becomes stale.
  public static func clearAppStoreOnboardingState() {
    sharedDefaults.removeObject(forKey: appStoreOnboardingCompletedKey)
    sharedDefaults.removeObject(forKey: customDatabaseBookmarkKey)
    sharedDefaults.removeObject(forKey: customDatabaseLocationKey)
  }

  private static func storeDatabaseURL(_ url: URL) {
    let canonical = url.resolvingSymlinksInPath()
    sharedDefaults.set(canonical.path, forKey: customDatabaseLocationKey)
    try? storeBookmark(for: canonical, key: customDatabaseBookmarkKey)
  }

  // MARK: - Bookmark Resolution

  public static func resolveBookmark() -> URL? {
    guard let data = sharedDefaults.data(forKey: projectRootBookmarkKey) else { return nil }
    return resolveBookmarkData(data, pathKey: projectRootKey, bookmarkKey: projectRootBookmarkKey)
  }

  private static func resolveBookmarkData(_ data: Data, pathKey: String, bookmarkKey: String) -> URL? {
    let primary: URL.BookmarkResolutionOptions = Sandbox.isSandboxed ? [.withSecurityScope] : []
    for options in [primary, []] {
      var stale = false
      do {
        let url = try URL(
          resolvingBookmarkData: data,
          options: options,
          relativeTo: nil,
          bookmarkDataIsStale: &stale
        )
        if stale {
          // Re-store the bookmark to update it
          let canonical = url.resolvingSymlinksInPath()

          // For project root, use centralized helper (enforces sandbox filtering)
          if pathKey == projectRootKey {
            if !setProjectRootIfAllowed(canonical) {
              return nil  // Blocked - sandbox container path
            }
          } else {
            // Other bookmarks (e.g., database location) - store directly
            sharedDefaults.set(canonical.path, forKey: pathKey)
            try? storeBookmark(for: canonical, key: bookmarkKey)
          }
        }
        return url
      } catch {
        continue
      }
    }
    sharedDefaults.removeObject(forKey: bookmarkKey)
    if let path = sharedDefaults.string(forKey: pathKey) {
      var isDir: ObjCBool = false
      if !(FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue) {
        sharedDefaults.removeObject(forKey: pathKey)
      }
    }
    return nil
  }

  // MARK: - Centralized Project Root Write Helper

  /// Single enforcement point for all project root writes.
  /// Ensures sandbox container paths are never persisted.
  /// - Parameter url: The URL to persist (will be canonicalized)
  /// - Returns: true if the path was stored, false if blocked
  @discardableResult
  private static func setProjectRootIfAllowed(_ url: URL) -> Bool {
    let canonical = url.resolvingSymlinksInPath()
    let path = canonical.path

    // Never store sandbox container paths - they cause "invalid root" modal on next launch
    if SandboxPathFilter.isSandboxContainerPath(path) {
      // Clean up any existing poisoned prefs
      sharedDefaults.removeObject(forKey: projectRootKey)
      sharedDefaults.removeObject(forKey: projectRootBookmarkKey)
      return false
    }

    sharedDefaults.set(path, forKey: projectRootKey)
    try? storeBookmark(for: canonical, key: projectRootBookmarkKey)
    return true
  }

  private static func storeRootURL(_ url: URL) {
    setProjectRootIfAllowed(url)
  }

  private static func storeBookmark(for url: URL, key: String) throws {
    #if os(macOS)
    let options: URL.BookmarkCreationOptions = Sandbox.isSandboxed ? [.withSecurityScope] : []
    let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    sharedDefaults.set(data, forKey: key)
    #endif
  }

  @discardableResult
  private static func probeDefaultsWriteability(_ defaults: UserDefaults) -> Bool {
    let probeKey = "dev.contextify.defaults.probe"
    defaults.set(true, forKey: probeKey)
    if defaults.bool(forKey: probeKey) != true {
      defaults.removeObject(forKey: probeKey)
      return false
    }
    defaults.removeObject(forKey: probeKey)
    return true
  }

  private static func warnIfLegacyDefaultsPresent() {
    // Check for legacy defaults asynchronously (warning doesn't block main operation)
    Task {
      guard await warningTracker.shouldWarn() else { return }
      let legacyDefaults = UserDefaults.standard
      let legacyKeys = [projectRootKey, projectRootBookmarkKey, autoPersistKey]
        .filter { legacyDefaults.object(forKey: $0) != nil }
      guard !legacyKeys.isEmpty else { return }
      // Warning would be logged here (currently just sets flag)
    }
  }
}

// MARK: - Sandbox

public enum Sandbox {
  #if DEBUG
  /// Override for unit tests to simulate sandboxed/unsandboxed environment.
  /// Only available in DEBUG builds.
  nonisolated(unsafe) public static var isSandboxedOverrideForTests: Bool?
  #endif

  /// Returns true when running in a sandboxed environment.
  /// Uses runtime detection because compile-time flags (#if APPSTORE_BUILD)
  /// don't propagate to Swift package code.
  public static var isSandboxed: Bool {
    #if DEBUG
    if let override = isSandboxedOverrideForTests {
      return override
    }
    #endif
    return isRuntimeSandboxed
  }

  /// Runtime check via environment variables set by macOS for sandboxed apps.
  public static var isRuntimeSandboxed: Bool {
    #if os(macOS)
    if getenv("APP_SANDBOX_CONTAINER_ID") != nil { return true }
    if ProcessInfo.processInfo.environment["__XPC_SANDBOXED"] == "1" { return true }
    #endif
    return false
  }
}

// MARK: - GitRepositoryResolver

public struct GitRepositoryResolver {
  private static let processLog = Logger(subsystem: "dev.contextify", category: "GitProcess")

  public struct GitInfoResult: Sendable {
    public let root: URL?
    public let branch: String?
    public let source: String?
    public let shouldPersist: Bool
    public let alertMessage: String?
    public let clearPersisted: Bool
  }

  public static func computeGitInfo(
    environment: [String: String],
    persistedPath: String?,
    currentRoot: URL?,
    autoPersist: Bool
  ) -> GitInfoResult {
    var alerts: [String] = []
    var candidateRoot: URL? = nil
    var candidateSource: String? = nil
    var candidatePersist = false
    var clearPersisted = false
    var sawEnvOverride = false

    if let envPath = environment["CONTEXTIFY_PROJECT_ROOT"], !envPath.isEmpty {
      sawEnvOverride = true
      let base = URL(fileURLWithPath: envPath).resolvingSymlinksInPath()
      var envIsDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: base.path, isDirectory: &envIsDir), envIsDir.boolValue,
         let root = findGitRoot(startingAt: base) {
        candidateRoot = root
        candidateSource = "env"
        candidatePersist = autoPersist
      } else {
        alerts.append("CONTEXTIFY_PROJECT_ROOT invalid/unreadable:\n\(base.path)")
      }
    }

    if candidateRoot == nil, let persistedPath, !persistedPath.isEmpty {
      let base = URL(fileURLWithPath: persistedPath).resolvingSymlinksInPath()
      var savedIsDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: base.path, isDirectory: &savedIsDir), savedIsDir.boolValue,
         let root = findGitRoot(startingAt: base) {
        candidateRoot = root
        candidateSource = "saved"
        candidatePersist = false
      } else {
        clearPersisted = true
        alerts.append("Stored project root is invalid or unreadable (saved path):\n\(base.path)")
      }
    }

    if candidateRoot == nil, !sawEnvOverride {
      let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      if let cwdRoot = findGitRoot(startingAt: cwd) {
        candidateRoot = cwdRoot
        candidateSource = "cwd"
        candidatePersist = autoPersist
      }
    }

    if candidateRoot == nil, let currentRoot {
      candidateRoot = currentRoot
      candidateSource = "existing"
      candidatePersist = false
    }

    let branch = candidateRoot.flatMap { root in
      if Sandbox.isSandboxed {
        return parseHEAD(at: root)
      }
      return parseHEAD(at: root) ?? runGitBranch(at: root)
    }
    let alertMessage = alerts.isEmpty ? nil : alerts.joined(separator: "\n")
    return GitInfoResult(
      root: candidateRoot,
      branch: branch,
      source: candidateSource,
      shouldPersist: candidatePersist,
      alertMessage: alertMessage,
      clearPersisted: clearPersisted
    )
  }

  public static func resolveGitDir(for repoRoot: URL) -> URL? {
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

  public static func headPath(for repoRoot: URL) -> String? {
    resolveGitDir(for: repoRoot)?.appendingPathComponent("HEAD").path
  }

  public static func parseHEAD(at repoRoot: URL) -> String? {
    let fm = FileManager.default
    let gitDirectory: URL
    if let resolved = resolveGitDir(for: repoRoot) {
      gitDirectory = resolved
    } else {
      let candidate = repoRoot.appendingPathComponent(".git", isDirectory: true)
      var isDir: ObjCBool = false
      guard fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue else { return nil }
      gitDirectory = candidate
    }

    let headURL = gitDirectory.appendingPathComponent("HEAD")
    guard let line = try? String(contentsOf: headURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !line.isEmpty else { return nil }

    if line.hasPrefix("ref:") {
      let ref = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
      return String(ref)
    }

    if line.count >= 7 {
      let prefix = line.prefix(7)
      let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
      let isHex = prefix.unicodeScalars.allSatisfy { hexSet.contains($0) }
      if isHex { return "detached@" + String(prefix) }
    }
    return nil
  }

  public static func findGitRoot(startingAt url: URL, maxDepth: Int = 64) -> URL? {
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

  public static func runGitBranch(at dir: URL, timeout: TimeInterval = 2.0) -> String? {
    if Sandbox.isSandboxed {
      return parseHEAD(at: dir)
    }
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
      return parseHEAD(at: dir)
    }

    if task.terminationStatus != 0 {
      return parseHEAD(at: dir)
    }

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    guard var output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else { return nil }
    if output == "HEAD" {
      return parseHEAD(at: dir)
    }
    return output
  }
}

// MARK: - HUDViewModel (@Observable, @MainActor)

@Observable
@MainActor
public final class HUDViewModel {
  public static let shared = HUDViewModel()

  public enum ProjectRootError: Error, Equatable { case notGit(URL), unreadable(URL) }

  private let gitLog = Logger(subsystem: "dev.contextify", category: "Git")
  private let lifecycleLog = Logger(subsystem: "dev.contextify", category: "Lifecycle")
  private let watcherLog = Logger(subsystem: "dev.contextify", category: "Watcher")

  public var branch: String = "—"

  public var projectDisplayName: String {
    projectRootURL?.lastPathComponent ?? "Unknown Project"
  }
  public var alertMessage: String? = nil
  public private(set) var projectRootURL: URL? = nil

  // Track last posted path to avoid duplicate notifications (nit #2)
  private var lastPostedPath: String?

  private var branchTimer: Timer? = nil
  private let coalesceQueue = DispatchQueue(label: "dev.contextify.git-coalesce")
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
  private let headEventMask: DispatchSource.FileSystemEvent = [.write, .attrib, .extend, .delete, .rename, .revoke]
  private let criticalHeadEvents: DispatchSource.FileSystemEvent = [.delete, .rename, .revoke]
  private var lastHeadEventAt: Date = .distantPast
  private var updateGeneration: UInt64 = 0
  private var hasLoggedMissingGit = false
  private var securityScopedURL: URL? = nil
  private var headWatcherArms: Int = 0
  private var coordinatorSubscription: Task<Void, Never>? = nil

  public var branchDisplay: String {
    if branch.isEmpty || branch == "—" { return "—" }
    if branch.hasPrefix("refs/heads/") { return String(branch.dropFirst("refs/heads/".count)) }
    if branch.hasPrefix("refs/") { return branch.split(separator: "/").last.map(String.init) ?? branch }
    return branch
  }

  public init() {
    // Defer all file I/O to async startup() to avoid blocking main thread
  }

  /// Async startup to restore persisted project root without blocking main thread
  public func startup() async {
    // Run file I/O on background thread
    let (bookmarkURL, persistedPath) = await Task.detached {
      return (HUDPreferences.resolveBookmark(), HUDPreferences.getPersistedRoot())
    }.value

    // Back on main actor to update state
    var discoveredRoot: URL?

    if let bookmark = bookmarkURL {
      let canonical = await Task.detached {
        bookmark.resolvingSymlinksInPath()
      }.value
      if SandboxPathFilter.isSandboxContainerPath(canonical.path) {
        lifecycleLog.warning("[HUD-SANDBOX-FILTER] Ignoring sandbox container bookmark at \(canonical.path, privacy: .public)")
      } else {
        projectRootURL = canonical
        lastPersistedPath = canonical.path
        lastPersistedAt = Date()
        persistRootIfNeeded(canonical, force: true)
        updateSecurityScope(for: bookmark, persisted: true)
        updateGitInfo()
        updateHeadWatcher()
        discoveredRoot = canonical
      }
    } else if let path = persistedPath, !path.isEmpty {
      let (canonical, scoped) = await Task.detached {
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let scoped = HUDPreferences.resolveBookmark() ?? canonical
        return (canonical, scoped)
      }.value
      if SandboxPathFilter.isSandboxContainerPath(canonical.path) {
        lifecycleLog.warning("[HUD-SANDBOX-FILTER] Ignoring sandbox persisted root at \(canonical.path, privacy: .public)")
      } else {
        projectRootURL = canonical
        lastPersistedPath = canonical.path
        lastPersistedAt = Date()
        persistRootIfNeeded(canonical, force: true)
        updateSecurityScope(for: scoped, persisted: true)
        updateGitInfo()
        updateHeadWatcher()
        discoveredRoot = canonical
      }
    }

    // Notify observers synchronously on MainActor; startup is @MainActor-isolated
    if let root = discoveredRoot {
      postProjectRootDidChange(root, source: "startup")
    }

    // CXT-13: Subscribe to coordinator updates to keep git info in sync
    coordinatorSubscription = Task { @MainActor [weak self] in
      guard let self else { return }
      for await context in StartupCoordinator.shared.updates() {
        await self.handleCoordinatorUpdate(context)
      }
    }
  }

  /// Handle project context update from StartupCoordinator (CXT-13)
  @MainActor
  private func handleCoordinatorUpdate(_ context: ActiveProjectContext) async {
    lifecycleLog.debug("📍 HUDViewModel: Received coordinator update: \(context.displayName) (path: \(context.path, privacy: .public))")

    // Update project root URL and branch from coordinator context
    let url = URL(fileURLWithPath: context.path)
    projectRootURL = url
    branch = context.branch ?? "—"

    // Restore security-scoped access to project root. Without this, sandboxed builds
    // cannot monitor .git/HEAD (branch display breaks) or access other project files.
    // The bookmark grants persistent filesystem access across app launches and project switches.
    // Even though git monitoring is disabled in App Store builds, the restored scope is still
    // required for Finder reveals, transcript ingestion, and any other scoped I/O.
    if let bookmark = context.bookmark {
      do {
        var isStale = false
        let scopedURL = try URL(
          resolvingBookmarkData: bookmark,
          options: .withSecurityScope,
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
        updateSecurityScope(for: scopedURL, persisted: true)

        if isStale {
          watcherLog.warning("Security-scoped bookmark is stale for \(context.displayName)")
        }
      } catch {
        watcherLog.error("Failed to resolve security-scoped bookmark: \(error.localizedDescription)")
      }
    }

    // Update file watchers for new project
    updateHeadWatcher()

    lifecycleLog.info("✅ HUDViewModel: Updated to project: \(context.displayName) (branch: \(self.branch))")
  }

  deinit {
    MainActor.assumeIsolated {
      branchTimer?.invalidate()
      branchTimer = nil
      coordinatorSubscription?.cancel()
      coordinatorSubscription = nil
      cancelHeadAndRefWatchers()
      #if os(macOS)
      securityScopedURL?.stopAccessingSecurityScopedResource()
      #endif
      securityScopedURL = nil
    }
  }

  // MARK: - Project Switching (Multi-Project Mode)

  /// Canonicalize URL path (resolve symlinks, standardize)
  /// - Parameter url: URL to canonicalize
  /// - Returns: Canonical absolute path
  private func canonicalPath(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
  }

  /// Post project root change notification with both URL and String types
  /// - Parameters:
  ///   - url: Project root URL
  ///   - source: Source of the change (for diagnostics)
  ///   - nonce: Optional nonce for self-suppression in notification observers
  @MainActor
  private func postProjectRootDidChange(_ url: URL, source: String, nonce: String? = nil) {
    // Canonicalize path to avoid symlink flutter (nit #1)
    let path = canonicalPath(url)

    // Emitter-side deduplication to reduce notification noise (nit #2)
    if lastPostedPath == path {
      lifecycleLog.debug("🔇 HUDViewModel: Skipping duplicate post src=\(source) path=\(path)")
      return
    }
    lastPostedPath = path

    #if DEBUG
    // Ensure URL and path are present (nit #7)
    assert(!path.isEmpty, "postProjectRootDidChange: path is empty")
    assert(path.hasPrefix("/"), "postProjectRootDidChange: path is not absolute")
    #endif

    lifecycleLog.info("📢 HUDViewModel: .projectRootDidChange src=\(source) path=\(path) nonce=\(nonce ?? "nil")")
    var userInfo: [String: Any] = [
      ProjectRootDidChangeKeys.url: URL(fileURLWithPath: path),  // Use canonical path
      ProjectRootDidChangeKeys.path: path,
      ProjectRootDidChangeKeys.source: source
    ]
    if let nonce = nonce {
      userInfo[ProjectRootDidChangeKeys.nonce] = nonce
    }
    NotificationCenter.default.post(
      name: .projectRootDidChange,
      object: path,  // Keep String for backward compatibility
      userInfo: userInfo
    )
  }

  /// Switch to a different project (fire-and-forget).
  ///
  /// **Eventually Consistent:** This method notifies the coordinator asynchronously.
  /// For deterministic flows, use `switchToProjectAsync(_:nonce:)` instead.
  ///
  /// - Parameters:
  ///   - projectPath: Absolute path to the new project root
  ///   - nonce: Optional nonce for self-suppression in notification observers
  @MainActor
  public func switchToProject(_ projectPath: String, nonce: String? = nil) {
    Task {
      await switchToProjectAsync(projectPath, nonce: nonce)
    }
  }

  /// Awaitable variant of switchToProject for deterministic callers (CXT-2).
  ///
  /// This method updates HUD state and **awaits** the coordinator switch before returning.
  /// Ensures `StartupCoordinator.current` reflects the new project ID/path immediately.
  ///
  /// - Parameters:
  ///   - projectPath: Absolute path to the new project root
  ///   - nonce: Optional nonce for self-suppression in notification observers
  /// - Note: Preferred for keyboard shortcuts, onboarding, and other deterministic flows
  @MainActor
  public func switchToProjectAsync(_ projectPath: String, nonce: String? = nil) async {
    // Update project root URL immediately (optimistic update for UI responsiveness)
    let url = URL(fileURLWithPath: projectPath)
    let resolved = url.resolvingSymlinksInPath()
    self.projectRootURL = resolved

    // Clear any previous alerts
    self.alertMessage = nil

    // Post notification immediately so UI updates (with nonce if provided)
    postProjectRootDidChange(resolved, source: "switchToProject", nonce: nonce)

    // Detect git info async to avoid blocking UI (6+ fileExists() calls)
    await Task.detached(priority: .userInitiated) {
      // Do heavy file I/O off main thread
      let gitRoot = GitRepositoryResolver.findGitRoot(startingAt: resolved)
      let env = ProcessInfo.processInfo.environment

      await MainActor.run { [weak self] in
        guard let self else { return }
        // Update UI with git results
        if let gitRoot = gitRoot {
          let info = GitRepositoryResolver.computeGitInfo(
            environment: env,
            persistedPath: resolved.path,
            currentRoot: resolved,
            autoPersist: false
          )
          self.branch = info.branch ?? "—"
          self.projectRootURL = gitRoot
          self.persistRootIfNeeded(gitRoot, force: true)
        } else {
          // No git - keep the resolved path
          self.branch = "—"
          self.persistRootIfNeeded(resolved, force: true)
        }

        // Update watcher for new git location (or clear if no git)
        self.updateHeadWatcher()
      }
    }.value

    // Notify coordinator with the final path (git root if present)
    // IMPORTANT: Do NOT await - this would block the main thread during project switch
    // The coordinator will handle database operations on background thread and publish updates
    // NOTE: Using Task.detached because project switching is a background coordination task
    // that should complete independently. UI updates come via StartupCoordinator.updates publisher.
    let finalPath = (self.projectRootURL ?? resolved).path
    Task.detached(priority: .userInitiated) {
      let logger = Logger(subsystem: "dev.contextify", category: "Lifecycle")
      do {
        try await StartupCoordinator.shared.switchProject(to: finalPath)
        logger.info("✅ Coordinator switch complete: \(finalPath)")
      } catch {
        logger.error("❌ Coordinator switch failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  public func updateGitInfo(env: [String: String]? = nil) {
    // Defensive guard: git operations disabled in sandboxed builds
    guard !Sandbox.isSandboxed else { return }

    if updating {
      pendingUpdate = true
      if let env { pendingEnvironment = env }
      scheduleDrain()
      return
    }

    updating = true
    updateGeneration &+= 1
    let generation = updateGeneration
    let envToUse: [String: String]
    if let env {
      envToUse = env
    } else if let stored = pendingEnvironment {
      envToUse = stored
      pendingEnvironment = nil
    } else {
      envToUse = ProcessInfo.processInfo.environment
    }
    let persistedPath = HUDPreferences.getPersistedRoot()
    let autoPersist = HUDPreferences.shouldAutoPersist()
    let currentRoot = projectRootURL

    Task(priority: .utility) { [weak self, envToUse, persistedPath, autoPersist, currentRoot, generation] in
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
    if let message = info.alertMessage {
      alertMessage = message
    }
    if info.clearPersisted {
      HUDPreferences.clearPersistedRoot()
      lastPersistedPath = nil
      lastPersistedAt = .distantPast
      #if os(macOS)
      securityScopedURL?.stopAccessingSecurityScopedResource()
      #endif
      securityScopedURL = nil
      if info.root == nil {
        projectRootURL = nil
      }
    }

    guard let root = info.root else {
      branch = "—"
      stopBranchMonitor()
      cancelHeadAndRefWatchers()
      pendingUpdate = false
      pendingEnvironment = nil
      #if os(macOS)
      securityScopedURL?.stopAccessingSecurityScopedResource()
      #endif
      securityScopedURL = nil
      projectRootURL = nil
      return
    }

    adoptDetectedRoot(root, source: info.source, persist: info.shouldPersist)
    if let br = info.branch, !br.isEmpty {
      branch = br
      hasLoggedMissingGit = false
    } else {
      branch = "—"
      if !hasLoggedMissingGit {
        hasLoggedMissingGit = true
      }
    }
  }

  private func adoptDetectedRoot(
    _ root: URL,
    source: String?,
    persist: Bool,
    forcePersist: Bool = false,
    scopedURL: URL? = nil
  ) {
    let canonical = root.resolvingSymlinksInPath()
    let pathChanged = projectRootURL?.path != canonical.path
    if pathChanged {
      #if os(macOS)
      securityScopedURL?.stopAccessingSecurityScopedResource()
      #endif
      securityScopedURL = nil
    }
    projectRootURL = canonical
    if persist {
      persistRootIfNeeded(canonical, force: forcePersist)
    }
    let scoped = scopedURL ?? (persist ? (HUDPreferences.resolveBookmark() ?? canonical) : canonical)
    updateSecurityScope(for: scoped, persisted: persist)
    if pathChanged || headWatcher == nil {
      updateHeadWatcher()
    }
  }

  private func persistRootIfNeeded(_ url: URL, force: Bool = false) {
    let canonical = url.resolvingSymlinksInPath()
    let path = canonical.path

    // Never persist sandbox container paths - they trigger "invalid root" modal on next launch
    if SandboxPathFilter.isSandboxContainerPath(path) {
      lifecycleLog.debug("[HUD-PERSIST-SKIP] Skipping sandbox container path: \(path, privacy: .public)")
      return
    }

    let now = Date()
    guard force || path != lastPersistedPath || now.timeIntervalSince(lastPersistedAt) > 5 else { return }
    HUDPreferences.setPersistedRoot(canonical)
    lastPersistedPath = path
    lastPersistedAt = now

    #if os(macOS)
    if Sandbox.isSandboxed, let scoped = HUDPreferences.resolveBookmark() {
      updateSecurityScope(for: scoped, persisted: true)
    }
    #endif
  }

  /// Set project root (supports both Git and non-Git projects)
  /// - Parameter url: The project directory URL
  /// - Returns: Result with the resolved project root URL
  /// - Note: Git repositories use the .git root; non-Git projects use the provided path
  ///
  /// **Eventually Consistent:** This method notifies the coordinator asynchronously (fire-and-forget).
  /// For deterministic flows, use `setProjectRootAsync(url:)` instead.
  @MainActor
  public func setProjectRoot(url: URL) -> Result<URL, ProjectRootError> {
    let canonical = url.resolvingSymlinksInPath()
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDir), isDir.boolValue else {
      alertMessage = "Selected folder is not readable:\n\(canonical.path)"
      return .failure(.unreadable(canonical))
    }

    // Try to find Git root (optional - not required)
    let finalRoot: URL
    if let repo = GitRepositoryResolver.findGitRoot(startingAt: canonical) {
      // Has Git - use repository root
      finalRoot = repo
      adoptDetectedRoot(repo, source: "manual", persist: true, forcePersist: true, scopedURL: url)
    } else {
      // No Git - use provided path as-is
      finalRoot = canonical
      projectRootURL = canonical
      branch = "—"
      persistRootIfNeeded(canonical, force: true)
    }

    updateGitInfo()

    // Notify coordinator of user-initiated project switch (fire-and-forget)
    Task {
      do {
        try await StartupCoordinator.shared.switchProject(to: finalRoot.path)
        lifecycleLog.info("✅ Coordinator notified of project switch to: \(finalRoot.path)")
      } catch {
        lifecycleLog.error("❌ Failed to notify coordinator: \(error.localizedDescription)")
      }
    }

    // Notify observers that project root has changed (legacy support)
    postProjectRootDidChange(finalRoot, source: "setProjectRoot")

    return .success(finalRoot)
  }

  /// Awaitable variant of setProjectRoot for deterministic callers.
  ///
  /// This method validates and updates HUD state synchronously, then **awaits** the coordinator
  /// switch before returning. This ensures that `StartupCoordinator.current` matches the chosen
  /// path/id immediately after this call completes.
  ///
  /// - Parameter url: The project directory URL
  /// - Returns: Result with the resolved project root URL
  /// - Note: Preferred for onboarding flows and other cases requiring deterministic ordering
  @MainActor
  public func setProjectRootAsync(url: URL) async -> Result<URL, ProjectRootError> {
    // First call sync variant to validate and update HUD state + post legacy notification
    let result = setProjectRoot(url: url)

    // Then await coordinator switch for deterministic ordering
    if case .success(let finalRoot) = result {
      do {
        try await StartupCoordinator.shared.switchProject(to: finalRoot.path)
        lifecycleLog.info("✅ Coordinator switch complete: \(finalRoot.path)")
      } catch {
        lifecycleLog.error("❌ Coordinator switch failed: \(error.localizedDescription)")
      }
    }

    return result
  }

  // MARK: - Compose Methods

  private func startBranchMonitor(interval: TimeInterval = 2.0) {
    branchTimer?.invalidate()
    branchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      self?.updateGitInfo()
    }
  }

  private func stopBranchMonitor() {
    branchTimer?.invalidate()
    branchTimer = nil
  }

  public func updateHeadWatcher() {
    // Always cancel existing watchers first (cleanup before early returns)
    cancelHeadAndRefWatchers()

    #if os(macOS)
    // Git monitoring disabled in sandboxed builds (requires per-project folder access)
    // Sandboxed builds would need user to grant access to each project root via NSOpenPanel,
    // which is too complex for initial App Store release. See TODOS.md for future enhancement.
    guard !Sandbox.isSandboxed else {
      watcherLog.info("Git monitoring disabled (App Store build)")
      return
    }
    #endif

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
    let src = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: headFD,
      eventMask: headEventMask,
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
    headWatcherMask = headEventMask
    headWatcherArms += 1
    src.resume()
    armRefWatchers(for: root)
  }

  private func handleHeadEvent(events: DispatchSource.FileSystemEvent) {
    if let mask = headWatcherMask,
       mask.intersection(criticalHeadEvents) != criticalHeadEvents {
      watcherLog.fault("HEAD watcher missing critical events; switching to timer monitor")
      cancelHeadAndRefWatchers()
      startBranchMonitor()
      return
    }

    let now = Date()
    // Note: This handler is never called in sandboxed builds (watcher not created)
    if now.timeIntervalSince(lastHeadEventAt) > headEventDebounce {
      lastHeadEventAt = now
      updateGitInfo()
    } else {
      lastHeadEventAt = now
      pendingUpdate = true
      scheduleDrain()
    }

    if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
      Task { [weak self] in
        try await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run {
          self?.updateHeadWatcher()
        }
      }
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
    coalesceQueue.asyncAfter(deadline: .now() + headEventDebounce) { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        guard self.pendingDrainAt == scheduledAt else { return }
        self.pendingDrainAt = .distantPast
        if self.updating {
          self.pendingUpdate = true
          return
        }
        guard self.pendingUpdate else { return }
        self.pendingUpdate = false
        let nextEnv = self.pendingEnvironment
        self.pendingEnvironment = nil
        self.updateGitInfo(env: nextEnv)
      }
    }
  }

  private func updateSecurityScope(for url: URL, persisted: Bool) {
    #if os(macOS)
    securityScopedURL?.stopAccessingSecurityScopedResource()
    securityScopedURL = nil
    if !Sandbox.isSandboxed {
      if FileManager.default.isReadableFile(atPath: url.path) {
        return
      } else if persisted {
        HUDPreferences.clearPersistedRoot()
        alertMessage = "Stored project root can’t be accessed."
      }
      return
    }
    if url.startAccessingSecurityScopedResource() {
      securityScopedURL = url
    } else if persisted {
      var isDir: ObjCBool = false
      let readableDir = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
      if !readableDir {
        HUDPreferences.clearPersistedRoot()
        alertMessage = "Stored project root can’t be accessed with current permissions."
      }
    }
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
    guard let gitDir = GitRepositoryResolver.resolveGitDir(for: root) else { return nil }
    let headURL = gitDir.appendingPathComponent("HEAD")
    guard let line = try? String(contentsOf: headURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines),
      line.hasPrefix("ref:") else { return nil }
    let ref = line.split(separator: " ").last.map(String.init) ?? ""
    guard ref.hasPrefix("refs/") else { return nil }
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
    pendingDrainAt = .distantPast
  }

  #if DEBUG
  public var debugIsUpdating: Bool { updating }
  public var debugPendingUpdate: Bool { pendingUpdate }
  public var debugHeadWatcherMask: DispatchSource.FileSystemEvent? { headWatcherMask }
  public var debugHeadWatcherArms: Int { headWatcherArms }
  public var debugRefWatcherActive: Bool { refFD >= 0 }
  public var debugPackedWatcherActive: Bool { packedFD >= 0 }
  public var debugSecurityScopedURL: URL? { securityScopedURL }
  public func debugHandleHeadEvent(_ events: DispatchSource.FileSystemEvent) { handleHeadEvent(events: events) }
  #endif
}
