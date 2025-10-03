import AppKit

final class MainWindowTracker {
  static let shared = MainWindowTracker()
  private init() {}
  weak var window: NSWindow?
}
