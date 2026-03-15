import AppKit
import SwiftUI
import ContextifyCore
import OSLog

/// Owns the NSStatusItem for Contextify's menu bar presence. Replaces SwiftUI
/// MenuBarExtra with an imperative NSStatusItem + NSPopover so the lifecycle
/// can be managed explicitly (create/remove on preference change, clean up on
/// termination).
///
/// The popover hosts StatusItemPopoverContent via NSHostingController.
@MainActor
final class StatusItemController: NSObject {
  static let shared = StatusItemController()

  private let log = Logger(subsystem: "dev.contextify", category: "StatusItem")

  private var statusItem: NSStatusItem?
  private var popover: NSPopover?
  private var outsideClickMonitor: Any?
  private var preferencesObserver: Any?

  /// Tracks the presentation model to update the icon reactively.
  private var iconUpdateTask: Task<Void, Never>?

  // MARK: - Appearance Observation (ct-462)

  /// KVO token for NSApp.effectiveAppearance.
  /// IMPORTANT: Observe NSApp, NOT per-button effectiveAppearance. Setting
  /// button.image triggers effectiveAppearance KVO on the button itself, which
  /// causes an infinite redraw loop (observe -> set image -> KVO fires -> observe ...).
  private var appearanceObservation: NSKeyValueObservation?

  /// Last observed appearance name, used to de-duplicate KVO callbacks
  /// that fire without an actual appearance change.
  private var lastObservedAppearanceName: NSAppearance.Name?

  /// Debounce timer for appearance changes. Multiple displays can fire
  /// appearance-change KVO simultaneously; coalesce into one re-render.
  private var appearanceDebounceTimer: Timer?

  /// Cache of last-assigned image data per button, keyed by ObjectIdentifier.
  /// Compared via tiffRepresentation to avoid redundant button.image assignments
  /// that would trigger unnecessary KVO and potential redraw churn.
  private var lastImageData: [ObjectIdentifier: Data] = [:]

  private override init() {
    super.init()
  }

  // MARK: - Public API

  /// Call once at app launch. Evaluates the current preference and creates
  /// or skips the status item accordingly, then observes future changes.
  func start() {
    log.notice("[STATUS-ITEM] Starting StatusItemController")

    let menuBarEnabled = HUDPreferences.isMenuBarExtraEnabled()
    let utilityMode = HUDPreferences.isBackgroundUtilityModeEnabled()
    let resolved = AppPresentationPreferences.resolvedMenuBarExtraEnabled(
      menuBarExtraEnabled: menuBarEnabled,
      backgroundUtilityModeEnabled: utilityMode
    )
    log.notice("[STATUS-ITEM] Prefs at start: menuBarEnabled=\(menuBarEnabled, privacy: .public), utilityMode=\(utilityMode, privacy: .public), resolved=\(resolved, privacy: .public)")

    applyCurrentPreference()
    observePreferenceChanges()
  }

  /// Tear down the status item and all observation. Called from
  /// AppDelegate.applicationWillTerminate.
  func tearDown() {
    log.info("[STATUS-ITEM] Tearing down StatusItemController")
    stopObservingPreferences()
    removeStatusItem()
  }

  // MARK: - Preference Observation

  private func observePreferenceChanges() {
    // Observe UserDefaults changes with object: nil because
    // ContextifyDefaults.shared and HUDPreferences.sharedDefaults may be
    // different Swift instances of the same suite, and the notification is
    // posted on the instance that was written to.
    preferencesObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.applyCurrentPreference()
      }
    }
  }

  private func stopObservingPreferences() {
    if let observer = preferencesObserver {
      NotificationCenter.default.removeObserver(observer)
      preferencesObserver = nil
    }
  }

  private func applyCurrentPreference() {
    let shouldShow = AppPresentationPreferences.resolvedMenuBarExtraEnabled(
      menuBarExtraEnabled: HUDPreferences.isMenuBarExtraEnabled(),
      backgroundUtilityModeEnabled: HUDPreferences.isBackgroundUtilityModeEnabled()
    )

    if shouldShow {
      createStatusItemIfNeeded()
    } else {
      removeStatusItem()
    }
  }

  // MARK: - Status Item Lifecycle

  private func createStatusItemIfNeeded() {
    guard statusItem == nil else { return }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = item.button {
      // Use the Contextify infinity logomark from the asset catalog.
      // The imageset has template-rendering-intent: template, so macOS
      // handles light/dark tinting automatically.
      let image = NSImage(named: "menubar-icon")
      image?.isTemplate = true
      button.image = image
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    self.statusItem = item
    log.notice("[STATUS-ITEM] Created NSStatusItem, button=\(item.button != nil, privacy: .public)")

    // Start updating the icon based on app state
    startIconUpdates()
    startObservingAppearance()
  }

  private func removeStatusItem() {
    dismissPopover()

    iconUpdateTask?.cancel()
    iconUpdateTask = nil

    stopObservingAppearance()

    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
      log.info("[STATUS-ITEM] Removed NSStatusItem")
    }
  }

  // MARK: - Icon Updates

  /// Periodically derive the icon from MenuBarStatusDeriver and update the button.
  private func startIconUpdates() {
    iconUpdateTask?.cancel()
    iconUpdateTask = Task { @MainActor [weak self] in
      guard let self else { return }

      // Start the activity model so background ingest messages flow
      MenuBarActivityModel.shared.start()

      // Poll every 2 seconds. A future iteration could use Combine/Observation
      // for more efficient push-based updates.
      while !Task.isCancelled {
        self.updateIcon()
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  private func updateIcon() {
    guard let button = statusItem?.button else { return }

    let cloudSync = CloudSyncManager.shared
    let presentation = MenuBarStatusDeriver.derivePresentation(
      syncState: cloudSync.syncState,
      cloudOffline: cloudSync.cloudOffline,
      cloudStatus: cloudSync.cloudStatus,
      cloudStatusError: cloudSync.cloudStatusError,
      backgroundIngestMessage: MenuBarActivityModel.shared.backgroundIngestMessage
    )

    // Keep the branded logomark as the icon; update only the tooltip
    // to reflect current state. The icon stays constant (Contextify infinity
    // mark) rather than swapping symbols per state - status detail lives
    // in the popover and tooltip.
    button.toolTip = presentation.statusText
  }

  // MARK: - Image Caching (ct-462)

  /// Assigns an image to a status bar button only if it differs from the
  /// previously assigned image. Compares tiffRepresentation data to avoid
  /// redundant assignments that trigger KVO on the button, which can cause
  /// unnecessary redraws or feed into an infinite loop if the button's
  /// effectiveAppearance is being observed (see appearance observation note).
  private func setButtonImage(_ button: NSStatusBarButton, image: NSImage) {
    let buttonId = ObjectIdentifier(button)
    guard let newData = image.tiffRepresentation else {
      button.image = image
      return
    }
    if lastImageData[buttonId] == newData { return }
    lastImageData[buttonId] = newData
    button.image = image
  }

  // MARK: - Appearance Observation (ct-462)

  /// Begin observing NSApp.effectiveAppearance for light/dark mode changes.
  /// IMPORTANT: We observe NSApp, NOT the per-button effectiveAppearance.
  /// Setting button.image triggers effectiveAppearance KVO on the button,
  /// which would create an infinite redraw loop if we observed that property.
  private func startObservingAppearance() {
    lastObservedAppearanceName = NSApp.effectiveAppearance.name

    appearanceObservation = NSApp.observe(
      \.effectiveAppearance,
      options: [.new]
    ) { [weak self] _, change in
      // Extract the appearance name before crossing isolation boundaries.
      // NSKeyValueObservedChange is not Sendable, so we must read it here.
      let newName = change.newValue?.name
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard newName != self.lastObservedAppearanceName else { return }
        self.lastObservedAppearanceName = newName
        // Clear image cache so re-rendered images are compared fresh
        // against the new appearance variant.
        self.lastImageData.removeAll()
        self.scheduleAppearanceUpdate()
      }
    }
    log.debug("[STATUS-ITEM] Started observing NSApp.effectiveAppearance")
  }

  private func stopObservingAppearance() {
    appearanceObservation?.invalidate()
    appearanceObservation = nil
    appearanceDebounceTimer?.invalidate()
    appearanceDebounceTimer = nil
    lastObservedAppearanceName = nil
    lastImageData.removeAll()
  }

  /// Coalesce rapid appearance-change notifications (e.g., from multiple
  /// displays switching simultaneously) into a single re-render pass.
  private func scheduleAppearanceUpdate() {
    appearanceDebounceTimer?.invalidate()
    appearanceDebounceTimer = Timer.scheduledTimer(
      withTimeInterval: 0.15,
      repeats: false
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.updateIcon()
      }
    }
  }

  // MARK: - Popover

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    togglePopover()
  }

  private func togglePopover() {
    if let popover, popover.isShown {
      dismissPopover()
    } else {
      showPopover()
    }
  }

  private func showPopover() {
    guard let button = statusItem?.button else { return }

    let popover = makePopover()
    self.popover = popover

    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    startMonitoringOutsideClicks()
    log.debug("[STATUS-ITEM] Popover shown")
  }

  /// Dismiss the popover. Called internally and from the popover content view
  /// (e.g., before opening a window from a popover button).
  func dismissPopover() {
    stopMonitoringOutsideClicks()
    popover?.performClose(nil)
    popover = nil
    log.debug("[STATUS-ITEM] Popover dismissed")
  }

  private func makePopover() -> NSPopover {
    let popover = NSPopover()
    popover.contentSize = NSSize(width: 280, height: 320)
    popover.behavior = .semitransient
    popover.animates = true
    popover.delegate = self

    let hostingController = NSHostingController(
      rootView: StatusItemPopoverContent()
    )
    popover.contentViewController = hostingController
    return popover
  }

  // MARK: - Outside Click Monitoring

  private func startMonitoringOutsideClicks() {
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        if let popover = self?.popover, popover.isShown {
          self?.dismissPopover()
        }
      }
    }
  }

  private func stopMonitoringOutsideClicks() {
    if let monitor = outsideClickMonitor {
      NSEvent.removeMonitor(monitor)
      outsideClickMonitor = nil
    }
  }
}

// MARK: - NSPopoverDelegate

extension StatusItemController: NSPopoverDelegate {
  func popoverDidClose(_ notification: Notification) {
    stopMonitoringOutsideClicks()
    popover = nil
  }
}

// MARK: - Popover Content View

/// SwiftUI content for the status item popover. Wraps the existing menu bar
/// content in a proper popover layout. This replaces the SwiftUI MenuBarExtra
/// menu style with a richer popover presentation.
///
/// NOTE: Environment values like @Environment(\.openWindow) are available
/// because the hosting controller participates in the SwiftUI scene graph
/// when embedded via NSHostingController within the App's process.
private struct StatusItemPopoverContent: View {
  @State private var cloudSyncManager = CloudSyncManager.shared
  @State private var activityModel = MenuBarActivityModel.shared
  /// Tracks main window visibility. Updated by window notifications so the
  /// Show/Hide button label stays correct while the popover is open.
  @State private var mainWindowVisible = false
  @AppStorage(HUDPreferences.backgroundUtilityModeEnabledKey, store: ContextifyDefaults.shared)
  private var backgroundUtilityModeEnabled = false

  private var presentation: MenuBarPresentation {
    MenuBarStatusDeriver.derivePresentation(
      syncState: cloudSyncManager.syncState,
      cloudOffline: cloudSyncManager.cloudOffline,
      cloudStatus: cloudSyncManager.cloudStatus,
      cloudStatusError: cloudSyncManager.cloudStatusError,
      backgroundIngestMessage: activityModel.backgroundIngestMessage
    )
  }

  private var isCloudConfigured: Bool {
    cloudSyncManager.syncState != .disabled
      || cloudSyncManager.cloudStatus != nil
      || !(cloudSyncManager.cloudStatusError?.isEmpty ?? true)
  }

  private var mainWindowButtonLabel: String {
    mainWindowVisible ? "Hide Contextify" : "Show Contextify"
  }

  /// Promote activation policy and activate the app before presenting a window.
  private func activateForWindow() {
    AppPresentationController.shared.promoteForWindowPresentation()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func dismissPopover() {
    StatusItemController.shared.dismissPopover()
  }

  private func openSettings() {
    dismissPopover()
    activateForWindow()
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Text("Contextify")
          .font(.headline)
        Spacer()
        Image(systemName: presentation.iconSystemName)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)
      .padding(.bottom, 4)

      // Status section
      VStack(alignment: .leading, spacing: 2) {
        Text(presentation.statusText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("menubar-popover-status")

        if presentation.localActivityText != "No background work" {
          Text(presentation.localActivityText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text(presentation.cloudText)
          .font(.caption)
          .foregroundStyle(.secondary)

        if let lastSyncDate = cloudSyncManager.lastSyncDate {
          Text("Last sync \(RelativeDateTimeFormatter().localizedString(for: lastSyncDate, relativeTo: .now))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 8)

      Divider()

      // Actions
      VStack(spacing: 2) {
        PopoverButton(label: mainWindowButtonLabel) {
          dismissPopover()
          if AppPresentationController.shared.isMainWindowVisible {
            AppPresentationController.shared.hideMainWindow()
          } else {
            AppPresentationController.shared.showMainWindow {
              openWindowByID("main")
            }
          }
        }
        .accessibilityIdentifier("menubar-popover-toggle-main")
        .accessibilityLabel(mainWindowButtonLabel)

        PopoverButton(label: "Projects") {
          dismissPopover()
          activateForWindow()
          // Use NSApp to open the window by sending the appropriate action
          openWindowByID("projects")
        }
        .accessibilityIdentifier("menubar-popover-projects")
        .accessibilityLabel("Open Projects window")

        PopoverButton(label: "Transcripts") {
          dismissPopover()
          activateForWindow()
          openWindowByID("transcript-inventory")
        }
        .accessibilityIdentifier("menubar-popover-transcripts")
        .accessibilityLabel("Open Transcripts window")

        if isCloudConfigured {
          PopoverButton(label: "Sync Now") {
            cloudSyncManager.triggerSync()
            Task { await cloudSyncManager.refreshStatusFromServer() }
          }
          .accessibilityIdentifier("menubar-popover-sync")
          .accessibilityLabel("Run cloud sync now")
        }

        PopoverButton(label: "Settings") {
          openSettings()
        }
        .accessibilityIdentifier("menubar-popover-settings")
        .accessibilityLabel("Open Settings")
      }
      .padding(.vertical, 4)

      Divider()

      // Mode indicator
      Text(backgroundUtilityModeEnabled ? "Background utility mode on" : "Background utility mode off")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityIdentifier("menubar-popover-mode-indicator")

      Divider()

      // Quit
      PopoverButton(label: "Quit Contextify") {
        NSApp.terminate(nil)
      }
      .accessibilityIdentifier("menubar-popover-quit")
      .accessibilityLabel("Quit Contextify")
      .padding(.bottom, 4)
    }
    .frame(width: 260)
    .accessibilityIdentifier("menubar-popover-content")
    .onAppear {
      mainWindowVisible = MainWindowTracker.shared.window?.isVisible == true
    }
    .task {
      activityModel.start()
      if isCloudConfigured {
        await cloudSyncManager.refreshStatusFromServer()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
      if let window = note.object as? NSWindow, window === MainWindowTracker.shared.window {
        mainWindowVisible = true
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
      if let window = note.object as? NSWindow, window === MainWindowTracker.shared.window {
        mainWindowVisible = false
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { note in
      if let window = note.object as? NSWindow, window === MainWindowTracker.shared.window {
        mainWindowVisible = false
      }
    }
  }

  /// Open a SwiftUI Window by its identifier using NotificationCenter.
  /// Since we are outside the SwiftUI scene graph, @Environment(\.openWindow)
  /// is not available. Instead we post a notification that ContextifyApp
  /// observes to call openWindow on our behalf.
  private func openWindowByID(_ id: String) {
    NotificationCenter.default.post(
      name: .statusItemOpenWindow,
      object: nil,
      userInfo: ["windowID": id]
    )
  }
}

/// A simple button styled for popover use (full-width, hover highlight).
private struct PopoverButton: View {
  let label: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack {
        Text(label)
        Spacer()
      }
      .contentShape(Rectangle())
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
      .cornerRadius(4)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
    .padding(.horizontal, 4)
  }
}

// MARK: - Notification Name

extension Notification.Name {
  /// Posted by StatusItemPopoverContent to request ContextifyApp open a
  /// window by its SwiftUI scene id. userInfo contains ["windowID": String].
  static let statusItemOpenWindow = Notification.Name("dev.contextify.statusItemOpenWindow")
}

// MARK: - Window Bridge

/// Invisible view embedded in the main Window scene. Provides access to
/// @Environment(\.openWindow) for the status item popover, which lives outside
/// the SwiftUI scene graph and cannot access environment values directly.
/// The popover posts a .statusItemOpenWindow notification; this view receives
/// it and calls openWindow(id:) on behalf of the popover.
struct StatusItemWindowBridge: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .allowsHitTesting(false)
      .onReceive(NotificationCenter.default.publisher(for: .statusItemOpenWindow)) { note in
        guard let windowID = note.userInfo?["windowID"] as? String else { return }
        openWindow(id: windowID)
      }
  }
}
