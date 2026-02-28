import Foundation
import ContextifyCore
import OSLog

/// Proof-of-concept: tests whether security-scoped bookmarks created in the
/// parent app can be resolved and used by an embedded XPC service.
///
/// Call `XPCBookmarkPoC.run()` from any debug context (e.g., AppDelegate).
/// Results are logged via OSLog with category "XPC-POC".
enum XPCBookmarkPoC {

  /// Run the XPC bookmark proof-of-concept test.
  /// Loads raw bookmark data from BookmarkStore and sends it to the XPC service.
  nonisolated static func run() {
    #if APPSTORE_BUILD
    Task.detached {
      await _run()
    }
    #else
    let log = Logger(subsystem: "dev.contextify", category: "XPC-POC")
    log.info("[XPC-POC] Skipped: only runs in App Store builds (sandboxed)")
    #endif
  }

  #if APPSTORE_BUILD
  nonisolated private static func _run() async {
    let log = Logger(subsystem: "dev.contextify", category: "XPC-POC")
    log.info("[XPC-POC] Starting XPC bookmark PoC test")

    // 1. Connect to XPC service
    let connection = NSXPCConnection(
      serviceName: "sh.contextify.ContextifyBackgroundService"
    )
    connection.remoteObjectInterface = NSXPCInterface(
      with: ContextifyXPCProtocol.self
    )
    connection.resume()

    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
      let errLog = Logger(subsystem: "dev.contextify", category: "XPC-POC")
      errLog.error("[XPC-POC] Connection error: \(error, privacy: .public)")
    }

    guard let service = proxy as? ContextifyXPCProtocol else {
      log.error("[XPC-POC] Failed to get remote object proxy")
      return
    }

    // 2. Ping the service
    service.ping { success in
      let cbLog = Logger(subsystem: "dev.contextify", category: "XPC-POC")
      cbLog.info("[XPC-POC] ping reply: \(success)")
    }

    // 3. Load bookmark data from BookmarkStore
    let store = BookmarkStore()
    let auth = await store.authorization(for: .claude)

    guard let bookmarkData = auth?.bookmarkData else {
      log.warning("[XPC-POC] No claude bookmark data available. Grant access in Settings first.")
      return
    }

    let statusString = auth?.status.rawValue ?? "nil"
    log.info("[XPC-POC] Loaded claude bookmark data: \(bookmarkData.count) bytes, status=\(statusString, privacy: .public)")

    // 4. Send bookmark data to XPC service
    service.testBookmarkAccess(bookmarkData) { success, message in
      let cbLog = Logger(subsystem: "dev.contextify", category: "XPC-POC")
      if success {
        cbLog.info("[XPC-POC] testBookmarkAccess SUCCESS: \(message, privacy: .public)")
      } else {
        cbLog.error("[XPC-POC] testBookmarkAccess FAILED: \(message, privacy: .public)")
      }
    }
  }
  #endif
}
