import AppKit
import OSLog
import SwiftUI

@MainActor
final class ComposeWindowController: NSWindowController, NSWindowDelegate {
  static let shared = ComposeWindowController()
  private static let frameDefaultsKey = "ComposePanelFrame"

  private let log = Logger(subsystem: "dev.contextify", category: "ComposeWC")
  private var hostingView: NSHostingView<ComposeSheet>?
  private var latestTmpFilePath: String?
  private var latestSendOnSubmit: Bool = true

  private init() {
    let panel = ComposeWindowController.makePanel()
    super.init(window: panel)
    window?.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present(
    initialText: String,
    title: String = "Compose",
    tmpFilePath: String? = nil,
    sendToITermOnSubmit: Bool = true
  ) {
    latestTmpFilePath = tmpFilePath
    latestSendOnSubmit = sendToITermOnSubmit

    var startText = initialText
    if startText.isEmpty,
       let path = tmpFilePath,
       FileManager.default.fileExists(atPath: path),
       let contents = try? String(contentsOfFile: path, encoding: .utf8) {
      startText = contents
    }
    let rootView = ComposeSheet(initialText: startText) { [weak self] text, delivery in
      guard let self else { return }
      Task { @MainActor in
        await self.handleSubmit(text: text, delivery: delivery)
      }
    } onCancel: { [weak self] in
      self?.dismiss()
    }

    if hostingView == nil {
      let host = NSHostingView(rootView: rootView)
      window?.contentView = host
      hostingView = host
    } else {
      hostingView?.rootView = rootView
    }

    window?.title = title.isEmpty ? "Compose" : title

    guard let panel = window as? NSPanel else { return }
    if let frameString = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) {
      panel.setFrame(NSRectFromString(frameString), display: false)
    } else if !panel.isVisible {
      panel.center()
    }

    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
      NotificationCenter.default.post(name: .contextifyFocusEditor, object: nil)
    }
  }

  func dismiss() {
    persistFrame()
    window?.orderOut(nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    dismiss()
    return false
  }

  func windowDidMove(_ notification: Notification) {
    persistFrame()
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    persistFrame()
  }

  private func handleSubmit(text: String, delivery: ComposeSheet.Delivery) async {
    if let path = latestTmpFilePath, !path.isEmpty {
      do {
        try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        log.info("Wrote \(text.count, privacy: .public) chars to tmpfile")
        _ = try? foregroundITerm2()
      } catch {
        log.error("Failed to write tmpfile: \(error.localizedDescription, privacy: .public)")
      }
    } else if latestSendOnSubmit {
      await deliverToITerm(text: text, delivery: delivery)
    }

    dismiss()
  }

  private func deliverToITerm(text: String, delivery: ComposeSheet.Delivery) async {
    let newline = (delivery == .keystrokes)
    let result = await ITerm2Bridge.send(text: text, newline: newline)
    switch result {
    case .success:
      log.info("Sent \(text.count, privacy: .public) chars to iTerm2 (newline=\(newline, privacy: .public))")
    case .failure(let error):
      log.error("Failed to send to iTerm2: \(error.localizedDescription, privacy: .public)")
    }
  }

  private static func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
      styleMask: [.titled, .closable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.collectionBehavior.insert(.moveToActiveSpace)
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.titlebarAppearsTransparent = true
    panel.toolbarStyle = .unified
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    return panel
  }

  private func foregroundITerm2() throws -> Bool {
    let bundleID = "com.googlecode.iterm2"
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
      return app.activate(options: [.activateAllWindows])
    }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
        let didActivate = app?.activate(options: [.activateAllWindows]) ?? false
        self.log.info("openApplication activate=\(didActivate, privacy: .public)")
      }
      return false
    }
    return false
  }

  private func persistFrame() {
    guard let frame = window?.frame else { return }
    UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameDefaultsKey)
  }
}
