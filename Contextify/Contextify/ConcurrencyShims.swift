import Foundation

#if os(macOS)
import AppKit
#endif

#if swift(<6.0)
// Avoid adding @unchecked Sendable to SDK types.
// If you ever need to move an NSItemProvider across actors,
// wrap it in this box instead of retrofitting the SDK type.
public struct ItemProviderBox: @unchecked Sendable {
  public let value: NSItemProvider
  public init(_ value: NSItemProvider) { self.value = value }
}
#endif
