import Foundation

/// XPC service implementation that tests security-scoped bookmark resolution.
///
/// Receives raw bookmark Data from the main app, resolves it as a
/// security-scoped URL, and tries to list directory contents.
class ContextifyBackgroundService: NSObject, ContextifyXPCProtocol {
  func ping(withReply reply: @escaping (Bool) -> Void) {
    NSLog("[XPC-SERVICE] ping received, replying true")
    reply(true)
  }

  func testBookmarkAccess(
    _ bookmarkData: Data,
    withReply reply: @escaping (Bool, String) -> Void
  ) {
    NSLog("[XPC-SERVICE] testBookmarkAccess called with %d bytes of bookmark data", bookmarkData.count)
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      NSLog("[XPC-SERVICE] Resolved bookmark to: %@ (stale=%d)", url.path, isStale ? 1 : 0)

      guard url.startAccessingSecurityScopedResource() else {
        let msg = "startAccessingSecurityScopedResource() returned false for \(url.path)"
        NSLog("[XPC-SERVICE] %@", msg)
        reply(false, msg)
        return
      }
      defer { url.stopAccessingSecurityScopedResource() }

      let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
      let preview = contents.prefix(5).joined(separator: ", ")
      let msg = "Listed \(contents.count) items in \(url.path). First 5: \(preview)"
      NSLog("[XPC-SERVICE] SUCCESS: %@", msg)
      reply(true, msg)
    } catch {
      let msg = "Failed to resolve bookmark: \(error)"
      NSLog("[XPC-SERVICE] %@", msg)
      reply(false, msg)
    }
  }
}
