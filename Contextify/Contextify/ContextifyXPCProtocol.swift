import Foundation

/// XPC protocol for background service communication.
///
/// This file is duplicated in both the main app and XPC service targets.
/// Both targets need compile-time access to this protocol definition.
///
/// This is a PoC protocol to test whether security-scoped bookmarks
/// created in the parent app can be resolved and used in an XPC service.
///
/// XPC callbacks execute on arbitrary threads, so methods are nonisolated
/// to opt out of default MainActor isolation.
@objc protocol ContextifyXPCProtocol {
  nonisolated func ping(withReply reply: @escaping (Bool) -> Void)
  nonisolated func testBookmarkAccess(_ bookmarkData: Data, withReply reply: @escaping (Bool, String) -> Void)
}
