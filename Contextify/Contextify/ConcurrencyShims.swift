import Foundation

#if swift(>=6.0)
// Allow capturing NSItemProvider in @Sendable closures when used safely on main thread.
extension NSItemProvider: @unchecked Sendable {}
#endif

