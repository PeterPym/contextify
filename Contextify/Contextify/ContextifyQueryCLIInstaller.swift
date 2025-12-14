import AppKit
import Combine
import ContextifyCore
import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "QueryCLIInstall")

@MainActor
final class ContextifyQueryCLIInstaller: ObservableObject {
  private static let dmgInstallDirOverrideKey = "Contextify.QueryCLI.DMGInstallDirOverride"

  enum InstallError: LocalizedError {
    case bundledShimMissing(URL)
    case installDirectoryMissing(URL)
    case collision(existing: URL)
    case permissionDenied(target: URL, sudoCommand: String?)
    case bookmarkMissing
    case bookmarkResolutionFailed
    case securityScopeDenied(URL)
    case uninstallNotSafe(URL)

    var errorDescription: String? {
      switch self {
      case .bundledShimMissing(let url):
        return "Bundled shim is missing: \(url.path)"
      case .installDirectoryMissing(let url):
        return "Install directory does not exist: \(url.path)"
      case .collision(let existing):
        return "Refusing to overwrite existing file: \(existing.path)"
      case .permissionDenied(let target, let sudoCommand):
        if sudoCommand != nil {
          return "Permission denied writing to \(target.path). Use the provided sudo command."
        }
        return "Permission denied writing to \(target.path)."
      case .bookmarkMissing:
        return "No saved install location. Choose a folder first."
      case .bookmarkResolutionFailed:
        return "Failed to resolve saved install folder permission. Choose the folder again."
      case .securityScopeDenied(let url):
        return "Access denied for selected folder: \(url.path)"
      case .uninstallNotSafe(let url):
        return "Refusing to remove file that does not look like a Contextify-installed shim: \(url.path)"
      }
    }
  }

  struct Status: Equatable {
    var bundledCLIURL: URL
    var bundledShimURL: URL
    var installedOnPATH: URL?
    var installedIsOurShim: Bool
    var sandboxedInstallDirectory: URL?
  }

  @Published private(set) var status: Status
  @Published var lastError: String?
  @Published var lastSudoCommand: String?
  @Published var lastSuccess: String?

  private let bookmarkStore = CLIFolderBookmarkStore()

  init() {
    let bundledCLIURL = Self.bundledCLIURL()
    let bundledShimURL = Self.bundledShimURL()
    self.status = Status(
      bundledCLIURL: bundledCLIURL,
      bundledShimURL: bundledShimURL,
      installedOnPATH: nil,
      installedIsOurShim: false,
      sandboxedInstallDirectory: nil
    )
    refreshStatus()
  }

  func refreshStatus() {
    lastError = nil
    lastSudoCommand = nil
    lastSuccess = nil

    var sandboxedInstallDirectory: URL?
    if Sandbox.isSandboxed, let stored = try? bookmarkStore.resolveFolderURL() {
      sandboxedInstallDirectory = stored
    }

    let pathHit = Self.findInstalledShim(named: "contextify-query", sandboxedInstallDirectory: sandboxedInstallDirectory)
    let installedIsOurShim = pathHit.map { ContextifyQueryShimMarker.fileLooksLikeOurShim(at: $0) } ?? false

    status = Status(
      bundledCLIURL: Self.bundledCLIURL(),
      bundledShimURL: Self.bundledShimURL(),
      installedOnPATH: pathHit,
      installedIsOurShim: installedIsOurShim,
      sandboxedInstallDirectory: sandboxedInstallDirectory
    )

    if let pathHit {
      log.info("[QUERYCLI-STATUS] onPath=1 isOurShim=\(installedIsOurShim) path=\(pathHit.path, privacy: .public)")
    } else {
      log.info("[QUERYCLI-STATUS] onPath=0")
    }
  }

  func installRecommendedDMG() {
    do {
      let dir = try Self.recommendedInstallDirectoryForDMG()
      log.info("[QUERYCLI-INSTALL-DIR] mode=dmg dir=\(dir.path, privacy: .public)")
      try installShim(toDirectory: dir, allowSudoSnippet: true)
    } catch {
      log.error("[QUERYCLI-INSTALL-ERROR] \(error.localizedDescription, privacy: .public)")
      lastError = error.localizedDescription
    }
    refreshStatus()
  }

  func chooseFolderAndInstallSandboxed() {
    do {
      let folder = try Self.promptForInstallFolder()
      log.info("[QUERYCLI-INSTALL-DIR] mode=appstore dir=\(folder.path, privacy: .public)")
      try bookmarkStore.saveFolderURL(folder)
      try withSecurityScopedAccess(folder) { scoped in
        try installShim(toDirectory: scoped, allowSudoSnippet: false)
      }
      refreshStatus()
    } catch {
      log.error("[QUERYCLI-INSTALL-ERROR] \(error.localizedDescription, privacy: .public)")
      lastError = error.localizedDescription
      refreshStatus()
    }
  }

  func repairUsingSavedSandboxedFolder() {
    do {
      guard let folder = try? bookmarkStore.resolveFolderURL() else {
        throw InstallError.bookmarkMissing
      }
      log.info("[QUERYCLI-INSTALL-DIR] mode=appstore dir=\(folder.path, privacy: .public) action=repair")
      try withSecurityScopedAccess(folder) { scoped in
        try installShim(toDirectory: scoped, allowSudoSnippet: false)
      }
      refreshStatus()
    } catch {
      log.error("[QUERYCLI-INSTALL-ERROR] \(error.localizedDescription, privacy: .public)")
      lastError = error.localizedDescription
      refreshStatus()
    }
  }

  func uninstallFromInstalledPATH() {
    do {
      guard let installed = status.installedOnPATH else { return }
      try uninstallShim(at: installed)
      refreshStatus()
    } catch {
      log.error("[QUERYCLI-UNINSTALL-ERROR] \(error.localizedDescription, privacy: .public)")
      lastError = error.localizedDescription
      refreshStatus()
    }
  }

  private func uninstallShim(at url: URL) throws {
    guard ContextifyQueryShimMarker.fileLooksLikeOurShim(at: url) else {
      throw InstallError.uninstallNotSafe(url)
    }
    try FileManager.default.removeItem(at: url)
    lastSuccess = "Removed \(url.path)"
    log.info("[QUERYCLI-UNINSTALL-DONE] path=\(url.path, privacy: .public)")
  }

  private func installShim(toDirectory directory: URL, allowSudoSnippet: Bool) throws {
    let shimSource = status.bundledShimURL
    guard FileManager.default.fileExists(atPath: shimSource.path) else {
      throw InstallError.bundledShimMissing(shimSource)
    }

    let destination = directory.appendingPathComponent("contextify-query")
    do {
      try Self.safeInstall(from: shimSource, to: destination)
      lastSuccess = "Installed to \(destination.path)"
      lastSudoCommand = nil
      lastError = nil
      log.info("[QUERYCLI-INSTALL-DONE] path=\(destination.path, privacy: .public)")
    } catch {
      if allowSudoSnippet, Self.isPermissionDenied(error) {
        lastSudoCommand = Self.makeSudoInstallCommand(from: shimSource, to: destination)
        log.warning("[QUERYCLI-INSTALL-SUDO-REQUIRED] path=\(destination.path, privacy: .public)")
        throw InstallError.permissionDenied(target: destination, sudoCommand: lastSudoCommand)
      }
      if case InstallError.collision(let existing) = error {
        log.error("[QUERYCLI-INSTALL-COLLISION] path=\(existing.path, privacy: .public)")
      } else {
        log.error("[QUERYCLI-INSTALL-ERROR] \(error.localizedDescription, privacy: .public)")
      }
      throw error
    }
  }

  private static func safeInstall(from source: URL, to destination: URL) throws {
    let fileManager = FileManager.default
    let destinationDir = destination.deletingLastPathComponent()
    if !fileManager.fileExists(atPath: destinationDir.path) {
      try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
    }

    if fileManager.fileExists(atPath: destination.path) {
      let isSymlink = (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
      let isOurShim = ContextifyQueryShimMarker.fileLooksLikeOurShim(at: destination)
      guard isSymlink || isOurShim else {
        throw InstallError.collision(existing: destination)
      }
    }

    let tmp = destinationDir.appendingPathComponent(".contextify-query.install.\(ProcessInfo.processInfo.processIdentifier)")
    if fileManager.fileExists(atPath: tmp.path) {
      try? fileManager.removeItem(at: tmp)
    }

    try fileManager.copyItem(at: source, to: tmp)
    try Self.ensureExecutable(tmp)

    if fileManager.fileExists(atPath: destination.path) {
      _ = try? fileManager.replaceItemAt(destination, withItemAt: tmp)
    } else {
      try fileManager.moveItem(at: tmp, to: destination)
    }
  }

  private static func ensureExecutable(_ url: URL) throws {
    url.withUnsafeFileSystemRepresentation { fsRep in
      guard let fsRep else { return }
      chmod(fsRep, 0o755)
    }
  }

  private static func makeSudoInstallCommand(from source: URL, to destination: URL) -> String {
    let src = source.path.replacingOccurrences(of: "\"", with: "\\\"")
    let dst = destination.path.replacingOccurrences(of: "\"", with: "\\\"")
    return "sudo install -m 0755 \"\(src)\" \"\(dst)\""
  }

  private static func isPermissionDenied(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSPOSIXErrorDomain, nsError.code == EACCES { return true }
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError { return true }
    return false
  }

  private static func bundledCLIURL() -> URL {
    Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/contextify-query")
  }

  private static func bundledShimURL() -> URL {
    Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/contextify-query/shim/contextify-query-shim")
  }

  private static func expandedPath(_ raw: String) -> String {
    (raw as NSString).expandingTildeInPath
  }

  private static func dmgInstallDirectoryOverrideURL(createIfMissing: Bool) throws -> URL? {
    guard let raw = ContextifyDefaults.shared.string(forKey: dmgInstallDirOverrideKey) else { return nil }
    let expanded = expandedPath(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !expanded.isEmpty else { return nil }

    let url = URL(fileURLWithPath: expanded)
    if createIfMissing, !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    return url
  }

  private static func recommendedInstallDirectoryForDMG() throws -> URL {
    let fm = FileManager.default
    if let override = try dmgInstallDirectoryOverrideURL(createIfMissing: true) {
      return override
    }
    let optHomebrew = URL(fileURLWithPath: "/opt/homebrew/bin")
    if fm.fileExists(atPath: optHomebrew.path) { return optHomebrew }
    let usrLocal = URL(fileURLWithPath: "/usr/local/bin")
    if fm.fileExists(atPath: usrLocal.path) { return usrLocal }

    let home = fm.homeDirectoryForCurrentUser
    let bin = home.appendingPathComponent("bin")
    if !fm.fileExists(atPath: bin.path) {
      try fm.createDirectory(at: bin, withIntermediateDirectories: true)
    }
    return bin
  }

  private static func findInstalledShim(named name: String, sandboxedInstallDirectory: URL?) -> URL? {
    var candidates: [URL] = []

    if let override = try? dmgInstallDirectoryOverrideURL(createIfMissing: false) {
      candidates.append(override.appendingPathComponent(name))
    }

    if let sandboxedInstallDirectory {
      candidates.append(sandboxedInstallDirectory.appendingPathComponent(name))
    }

    for candidate in candidates {
      if FileManager.default.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }

    if let onPath = findExecutableOnPATH(named: name) {
      return onPath
    }

    candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin").appendingPathComponent(name))
    candidates.append(URL(fileURLWithPath: "/usr/local/bin").appendingPathComponent(name))
    candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin/\(name)"))

    for candidate in candidates {
      if FileManager.default.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }
    return nil
  }

  private static func promptForInstallFolder() throws -> URL {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    panel.message = "Choose a folder to install the Contextify CLI shim into (recommended: ~/bin)."
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin")

    let response = panel.runModal()
    guard response == .OK, let url = panel.url else { throw InstallError.bookmarkMissing }
    return url
  }

  private static func findExecutableOnPATH(named name: String) -> URL? {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for dir in path.split(separator: ":") {
      let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
      if FileManager.default.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }
    return nil
  }

  private func withSecurityScopedAccess<T>(_ url: URL, operation: (URL) throws -> T) throws -> T {
    var isStale = false
    guard let bookmarkData = try? bookmarkStore.readBookmarkData() else {
      throw InstallError.bookmarkMissing
    }

    guard let resolved = try? URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else {
      throw InstallError.bookmarkResolutionFailed
    }

    guard resolved.startAccessingSecurityScopedResource() else {
      throw InstallError.securityScopeDenied(resolved)
    }

    defer { resolved.stopAccessingSecurityScopedResource() }

    if isStale {
      try? bookmarkStore.saveFolderURL(resolved)
    }

    return try operation(resolved)
  }
}

@MainActor
private final class CLIFolderBookmarkStore {
  private let key = "Contextify.QueryCLI.InstallFolderBookmark"

  func saveFolderURL(_ url: URL) throws {
    let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    UserDefaults.standard.set(data, forKey: key)
  }

  func readBookmarkData() throws -> Data {
    guard let data = UserDefaults.standard.data(forKey: key) else {
      throw ContextifyQueryCLIInstaller.InstallError.bookmarkMissing
    }
    return data
  }

  func resolveFolderURL() throws -> URL {
    var isStale = false
    let data = try readBookmarkData()
    guard let url = try? URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else {
      throw ContextifyQueryCLIInstaller.InstallError.bookmarkResolutionFailed
    }
    if isStale {
      try? saveFolderURL(url)
    }
    return url
  }
}
