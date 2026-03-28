import AppKit
import CoreServices
import Foundation

private enum ExitCode: Int32 {
  case success = 0
  case usage = 64
  case notInstalled = 69
  case execFailed = 126
  case notFound = 127
}

private let bundleIdentifier = "sh.contextify.Contextify"
private let bundledCLIRelativePath = "Contents/MacOS/contextify-query"
private let appStoreReceiptRelativePath = "Contents/_MASReceipt/receipt"
private let marker = "dev.contextify.contextify-query-shim.v1"
private let appPathOverrideEnv = "CONTEXTIFY_QUERY_APP_PATH"

private struct Candidate {
  let url: URL
  let isAppStore: Bool
  let hasBundledCLI: Bool
  let bundleVersion: String?
  let shortVersion: String?

  var path: String { url.path }
}

private func isAppStoreBundle(_ appURL: URL) -> Bool {
  FileManager.default.fileExists(atPath: appURL.appendingPathComponent(appStoreReceiptRelativePath).path)
}

private func readInfoPlistVersions(_ appURL: URL) -> (bundleVersion: String?, shortVersion: String?) {
  guard let bundle = Bundle(url: appURL) else { return (nil, nil) }
  let bundleVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
  let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  return (bundleVersion, shortVersion)
}

private func numericishVersionKey(_ value: String?) -> [Int] {
  guard let value else { return [] }
  let parts = value.split(separator: ".").map { Int($0) ?? 0 }
  return parts
}

private func compareVersion(_ lhs: Candidate, _ rhs: Candidate) -> ComparisonResult {
  let lhsKey = numericishVersionKey(lhs.bundleVersion)
  let rhsKey = numericishVersionKey(rhs.bundleVersion)
  if lhsKey != rhsKey {
    return lhsKey.lexicographicallyPrecedes(rhsKey) ? .orderedAscending : .orderedDescending
  }

  let lhsShort = numericishVersionKey(lhs.shortVersion)
  let rhsShort = numericishVersionKey(rhs.shortVersion)
  if lhsShort != rhsShort {
    return lhsShort.lexicographicallyPrecedes(rhsShort) ? .orderedAscending : .orderedDescending
  }

  return .orderedSame
}

private func getRunningContextifyPath() -> String? {
  let ws = NSWorkspace.shared
  for app in ws.runningApplications where app.bundleIdentifier == bundleIdentifier {
    return app.bundleURL?.standardizedFileURL.path
  }
  return nil
}

private func selectBestCandidate(_ candidates: [Candidate]) -> Candidate? {
  guard !candidates.isEmpty else { return nil }

  // Prefer the currently running instance if it's a valid candidate
  if let runningPath = getRunningContextifyPath(),
     let running = candidates.first(where: { $0.path == runningPath }) {
    return running
  }

  let sorted = candidates.sorted { a, b in
    if a.hasBundledCLI != b.hasBundledCLI { return a.hasBundledCLI && !b.hasBundledCLI }
    if a.isAppStore != b.isAppStore { return a.isAppStore && !b.isAppStore }
    let versionOrder = compareVersion(a, b)
    if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
    return a.path < b.path
  }

  return sorted.first
}

private func discoverCandidates() -> [Candidate] {
  var urls: [URL] = []

  if let cfURLs = LSCopyApplicationURLsForBundleIdentifier(bundleIdentifier as CFString, nil)?.takeRetainedValue() as? [URL] {
    urls.append(contentsOf: cfURLs)
  } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
    urls.append(url)
  }

  let fallback = URL(fileURLWithPath: "/Applications/Contextify.app")
  if FileManager.default.fileExists(atPath: fallback.path) {
    urls.append(fallback)
  }

  var unique: [String: URL] = [:]
  for url in urls {
    unique[url.standardizedFileURL.path] = url.standardizedFileURL
  }

  return unique.values.compactMap { url in
    let versions = readInfoPlistVersions(url)
    let cliPath = url.appendingPathComponent(bundledCLIRelativePath).path
    let hasCLI = FileManager.default.isExecutableFile(atPath: cliPath)

    // Skip candidates without a valid CLI to avoid selection issues
    guard hasCLI else { return nil }

    return Candidate(
      url: url,
      isAppStore: isAppStoreBundle(url),
      hasBundledCLI: hasCLI,
      bundleVersion: versions.bundleVersion,
      shortVersion: versions.shortVersion
    )
  }
}

private func execBundledCLI(appURL: URL, argv: [String]) -> Never {
  let cliURL = appURL.appendingPathComponent(bundledCLIRelativePath)
  let path = cliURL.path

  guard FileManager.default.isExecutableFile(atPath: path) else {
    fputs("Contextify is installed at \"\(appURL.path)\", but the bundled CLI is missing or not executable at \"\(path)\".\n", stderr)
    exit(ExitCode.execFailed.rawValue)
  }

  var cStrings: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
  cStrings.append(nil)
  defer { cStrings.forEach { if let p = $0 { free(p) } } }

  execv(path, cStrings)
  perror("execv")
  exit(ExitCode.execFailed.rawValue)
}

private func printUsage() {
  print("contextify-query shim (\(marker))")
  print("Usage: contextify-query [args...]")
  print("This shim locates Contextify (\(bundleIdentifier)) and execs its bundled contextify-query CLI.")
}

private func run() -> Never {
  let argv = CommandLine.arguments
  if argv.count >= 2, argv[1] == "--shim-help" || argv[1] == "--shim-version" {
    printUsage()
    exit(ExitCode.success.rawValue)
  }

  if let overridden = ProcessInfo.processInfo.environment[appPathOverrideEnv], !overridden.isEmpty {
    let url = URL(fileURLWithPath: overridden).standardizedFileURL
    let cliURL = url.appendingPathComponent(bundledCLIRelativePath)
    if FileManager.default.isExecutableFile(atPath: cliURL.path) {
      execBundledCLI(appURL: url, argv: argv)
    }
    fputs("Contextify override \(appPathOverrideEnv)=\"\(overridden)\" did not contain an executable bundled CLI at \"\(cliURL.path)\".\n", stderr)
    exit(ExitCode.execFailed.rawValue)
  }

  let candidates = discoverCandidates()
  guard let selected = selectBestCandidate(candidates) else {
    fputs("Contextify is not installed (bundle id \(bundleIdentifier)). Install Contextify, then run Contextify → “Install/Repair CLI…”.\n", stderr)
    exit(ExitCode.notFound.rawValue)
  }

  if candidates.count > 1,
     isatty(STDERR_FILENO) != 0,
     ProcessInfo.processInfo.environment["CONTEXTIFY_NO_INSTALL_WARNING"] != "1",
     ProcessInfo.processInfo.environment["CONTEXTIFY_NO_DEPRECATIONS"] != "1" {
    let others = candidates.filter { $0.path != selected.path }.sorted { $0.path < $1.path }.map(\.path).joined(separator: "\n- ")
    fputs("Multiple Contextify installs detected; using:\n- \(selected.path)\nOther candidates:\n- \(others)\n", stderr)
  }

  execBundledCLI(appURL: selected.url, argv: argv)
}

run()
