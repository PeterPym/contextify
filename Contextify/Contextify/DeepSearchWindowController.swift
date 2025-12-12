import AppKit
import SwiftUI
import OSLog
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "DeepSearchWindow")

/// Singleton controller for the Deep Search window
@MainActor
final class DeepSearchWindowController {
  static let shared = DeepSearchWindowController()

  private var window: NSWindow?
  var viewModel: DeepSearchViewModel?

  private init() {}

  /// Show the Deep Search window with the given parameters
  func showWindow(
    projectId: String,
    projectName: String,
    query: String,
    selectedHitId: String?,
    searchResult: ConversationSearchResult?
  ) {
    // Create or reuse window
    if window == nil {
      createWindow()
    }

    guard let window = window else { return }

    // Create new view model with parameters
    let vm = DeepSearchViewModel(
      projectId: projectId,
      projectName: projectName,
      initialQuery: query,
      selectedHitId: selectedHitId,
      initialResult: searchResult
    )
    self.viewModel = vm

    // Update window content
    let contentView = DeepSearchView()
      .environment(vm)

    window.contentView = NSHostingView(rootView: contentView)
    window.title = "Search: \(projectName)"

    // Show and bring to front
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    log.info("[DEEPSEARCH-INIT] Deep Search window opened for project: \(projectName, privacy: .public)")
  }

  /// Close the Deep Search window
  func closeWindow() {
    window?.close()
  }

  private func createWindow() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )

    window.minSize = NSSize(width: 700, height: 500)
    window.center()
    window.setFrameAutosaveName("DeepSearchWindow")
    window.isReleasedWhenClosed = false

    // Set up window delegate to handle close
    window.delegate = WindowDelegate.shared

    self.window = window
  }
}

// MARK: - Window Delegate

private class WindowDelegate: NSObject, NSWindowDelegate {
  static let shared = WindowDelegate()

  func windowWillClose(_ notification: Notification) {
    // Clean up view model when window closes
    Task { @MainActor in
      DeepSearchWindowController.shared.viewModel = nil
    }
  }
}
