import Foundation

/// XPC protocol for background service communication.
///
/// This is a PoC protocol to test whether security-scoped bookmarks
/// created in the parent app can be resolved and used in an XPC service.
@objc protocol ContextifyXPCProtocol {
  func ping(withReply reply: @escaping (Bool) -> Void)
  func testBookmarkAccess(_ bookmarkData: Data, withReply reply: @escaping (Bool, String) -> Void)
}
