import SwiftUI
import Observation
import ContextifyCore

@MainActor
@Observable
final class MenuBarActivityModel {
  static let shared = MenuBarActivityModel()

  private(set) var backgroundIngestMessage: String?
  @ObservationIgnored private var backgroundObservationTask: Task<Void, Never>?

  private init() {}

  func start() {
    guard backgroundObservationTask == nil else { return }

    backgroundObservationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let stream = NotificationCenter.default.notifications(named: .backgroundIngestProgress)
      for await note in stream {
        guard
          let total = note.userInfo?["total"] as? Int,
          let remaining = note.userInfo?["remaining"] as? Int
        else { continue }

        if total <= 0 || remaining <= 0 {
          self.backgroundIngestMessage = nil
          continue
        }

        let completed = total - remaining
        let current = completed + 1
        self.backgroundIngestMessage = "Indexing \(current)/\(total) projects..."
      }
    }
  }
}

struct ContextifyMenuBarExtraLabel: View {
  @State private var cloudSyncManager = CloudSyncManager.shared
  @State private var activityModel = MenuBarActivityModel.shared

  private var presentation: MenuBarPresentation {
    MenuBarStatusDeriver.derivePresentation(
      syncState: cloudSyncManager.syncState,
      cloudOffline: cloudSyncManager.cloudOffline,
      cloudStatus: cloudSyncManager.cloudStatus,
      cloudStatusError: cloudSyncManager.cloudStatusError,
      backgroundIngestMessage: activityModel.backgroundIngestMessage
    )
  }

  var body: some View {
    Label {
      Text("Ctx")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
    } icon: {
      Image(systemName: presentation.iconSystemName)
        .symbolRenderingMode(.hierarchical)
    }
    .help(presentation.statusText)
    .accessibilityLabel("Contextify: \(presentation.statusText)")
    .task {
      activityModel.start()
    }
  }
}

struct ContextifyMenuBarExtraContent: View {
  @Environment(\.openWindow) private var openWindow

  @State private var cloudSyncManager = CloudSyncManager.shared
  @State private var activityModel = MenuBarActivityModel.shared
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
    AppPresentationController.shared.isMainWindowVisible ? "Hide Contextify" : "Show Contextify"
  }

  /// Promote activation policy and activate the app before presenting a window.
  /// In utility mode this switches from .accessory to .regular so the Dock icon
  /// and Command-Tab entry appear while windows are visible.
  private func activateForWindow() {
    AppPresentationController.shared.promoteForWindowPresentation()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func openSettings() {
    activateForWindow()
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }

  var body: some View {
    Text("Contextify")
    Text(presentation.statusText)

    if presentation.localActivityText != "No background work" {
      Text(presentation.localActivityText)
    }

    Text(presentation.cloudText)

    if let lastSyncDate = cloudSyncManager.lastSyncDate {
      Text("Last sync \(RelativeDateTimeFormatter().localizedString(for: lastSyncDate, relativeTo: .now))")
    }

    Divider()

    Button(mainWindowButtonLabel) {
      AppPresentationController.shared.toggleMainWindow {
        openWindow(id: "main")
      }
    }
    .accessibilityLabel(mainWindowButtonLabel)

    Button("Projects") {
      activateForWindow()
      openWindow(id: "projects")
    }
    .accessibilityLabel("Open Projects window")

    Button("Transcripts") {
      activateForWindow()
      openWindow(id: "transcript-inventory")
    }
    .accessibilityLabel("Open Transcripts window")

    if isCloudConfigured {
      Button("Sync Now") {
        cloudSyncManager.triggerSync()
        Task { await cloudSyncManager.refreshStatusFromServer() }
      }
      .accessibilityLabel("Run cloud sync now")
    }

    Button("Settings") {
      openSettings()
    }
    .accessibilityLabel("Open Settings")

    Divider()

    Text(backgroundUtilityModeEnabled ? "Background utility mode on" : "Background utility mode off")

    Divider()

    Button("Quit Contextify") {
      NSApp.terminate(nil)
    }
    .accessibilityLabel("Quit Contextify")
    .task {
      activityModel.start()
      if isCloudConfigured {
        await cloudSyncManager.refreshStatusFromServer()
      }
    }
  }
}
