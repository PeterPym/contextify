import XCTest
import Foundation
@testable import ContextifyCore

func clearPersistedRoot() {
  HUDPreferences.clearPersistedRoot()
}

func locateRepoRoot(startingAt url: URL? = nil) -> URL? {
  let fm = FileManager.default
  var current = (url ?? URL(fileURLWithPath: fm.currentDirectoryPath)).resolvingSymlinksInPath()
  var visited = Set<URL>()
  for _ in 0..<64 {
    guard visited.insert(current).inserted else { break }
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: current.appendingPathComponent(".git").path, isDirectory: &isDir), isDir.boolValue {
      return current
    }
    let parent = current.deletingLastPathComponent()
    if parent.path == current.path { break }
    current = parent
  }
  return nil
}


#if os(macOS)
@MainActor private var scopedResources: [URL] = []

@discardableResult
@MainActor
func allowSecurityScopedAccess(to url: URL, file: StaticString = #file, line: UInt = #line) -> URL {
  do {
    let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    var stale = false
    let scoped = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
    if !scoped.startAccessingSecurityScopedResource() {
      XCTFail("Failed to start security scope for \(url.path)", file: file, line: line)
    }
    scopedResources.append(scoped)
    return scoped
  } catch {
    XCTFail("Unable to create security scope for \(url.path): \(error)", file: file, line: line)
    return url
  }
}

@MainActor
func resetSecurityScopedAccess() {
  for resource in scopedResources {
    resource.stopAccessingSecurityScopedResource()
  }
  scopedResources.removeAll()
}
#endif

@discardableResult
func waitForCondition(
  _ reason: String,
  timeout: TimeInterval = 2.0,
  poll: TimeInterval = 0.05,
  file: StaticString = #file, line: UInt = #line,
  condition: @escaping () -> Bool
) async throws -> Bool {
  let start = Date()
  while Date().timeIntervalSince(start) < timeout {
    if condition() { return true }
    try await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
  }
  XCTFail("Timeout: \(reason)", file: file, line: line)
  return false
}
