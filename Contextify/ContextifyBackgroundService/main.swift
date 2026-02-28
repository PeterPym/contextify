import Foundation

let delegate = ContextifyServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
