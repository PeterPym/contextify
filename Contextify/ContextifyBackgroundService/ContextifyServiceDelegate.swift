import Foundation

/// NSXPCListener delegate that vends the ContextifyBackgroundService.
class ContextifyServiceDelegate: NSObject, NSXPCListenerDelegate {
  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: ContextifyXPCProtocol.self)
    newConnection.exportedObject = ContextifyBackgroundService()
    newConnection.resume()
    return true
  }
}
