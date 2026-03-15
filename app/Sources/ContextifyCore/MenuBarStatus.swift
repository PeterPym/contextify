import Foundation

public enum MenuBarDisplayState: String, Sendable, Equatable {
  case idle
  case localActivity
  case cloudSyncing
  case cloudOffline
  case cloudNeedsAttention
}

public struct MenuBarPresentation: Sendable, Equatable {
  public let displayState: MenuBarDisplayState
  public let iconSystemName: String
  public let statusText: String
  public let localActivityText: String
  public let cloudText: String

  public init(
    displayState: MenuBarDisplayState,
    iconSystemName: String,
    statusText: String,
    localActivityText: String,
    cloudText: String
  ) {
    self.displayState = displayState
    self.iconSystemName = iconSystemName
    self.statusText = statusText
    self.localActivityText = localActivityText
    self.cloudText = cloudText
  }
}

public enum AppPresentationPreferences {
  public static func resolvedMenuBarExtraEnabled(
    menuBarExtraEnabled: Bool,
    backgroundUtilityModeEnabled: Bool
  ) -> Bool {
    backgroundUtilityModeEnabled || menuBarExtraEnabled
  }

  public static func shouldStartWithoutMainWindow(
    quietLaunch: Bool,
    backgroundUtilityModeEnabled: Bool
  ) -> Bool {
    quietLaunch || backgroundUtilityModeEnabled
  }
}

public enum MenuBarStatusDeriver {
  public static func derivePresentation(
    syncState: SyncState,
    cloudOffline: Bool,
    cloudStatus: CloudSyncStatus?,
    cloudStatusError: String?,
    backgroundIngestMessage: String?
  ) -> MenuBarPresentation {
    let localActivityText = normalizedLocalActivityText(backgroundIngestMessage)
    let cloudText = normalizedCloudText(
      syncState: syncState,
      cloudOffline: cloudOffline,
      cloudStatus: cloudStatus,
      cloudStatusError: cloudStatusError
    )

    let displayState: MenuBarDisplayState
    if needsCloudAttention(syncState: syncState, cloudStatus: cloudStatus, cloudStatusError: cloudStatusError) {
      displayState = .cloudNeedsAttention
    } else if cloudOffline {
      displayState = .cloudOffline
    } else if isCloudSyncing(syncState: syncState, cloudStatus: cloudStatus) {
      displayState = .cloudSyncing
    } else if normalizedLocalActivityText(backgroundIngestMessage) != "No background work" {
      displayState = .localActivity
    } else {
      displayState = .idle
    }

    return MenuBarPresentation(
      displayState: displayState,
      iconSystemName: iconSystemName(for: displayState),
      statusText: statusText(for: displayState),
      localActivityText: localActivityText,
      cloudText: cloudText
    )
  }

  private static func iconSystemName(for state: MenuBarDisplayState) -> String {
    switch state {
    case .idle:
      return "checkmark.circle"
    case .localActivity:
      return "arrow.triangle.2.circlepath.circle"
    case .cloudSyncing:
      return "cloud.fill"
    case .cloudOffline:
      return "wifi.slash"
    case .cloudNeedsAttention:
      return "exclamationmark.circle"
    }
  }

  private static func statusText(for state: MenuBarDisplayState) -> String {
    switch state {
    case .idle:
      return "Up to date"
    case .localActivity:
      return "Background work active"
    case .cloudSyncing:
      return "Cloud syncing"
    case .cloudOffline:
      return "Cloud offline"
    case .cloudNeedsAttention:
      return "Cloud needs attention"
    }
  }

  private static func normalizedLocalActivityText(_ backgroundIngestMessage: String?) -> String {
    guard let backgroundIngestMessage,
          !backgroundIngestMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return "No background work"
    }
    return backgroundIngestMessage
  }

  private static func normalizedCloudText(
    syncState: SyncState,
    cloudOffline: Bool,
    cloudStatus: CloudSyncStatus?,
    cloudStatusError: String?
  ) -> String {
    let configured = isCloudConfigured(syncState: syncState, cloudStatus: cloudStatus, cloudStatusError: cloudStatusError)
    guard configured else {
      return "Cloud sync off"
    }

    if needsCloudAttention(syncState: syncState, cloudStatus: cloudStatus, cloudStatusError: cloudStatusError) {
      return "Cloud needs attention"
    }

    if cloudOffline {
      return "Cloud sync is offline"
    }

    if isCloudSyncing(syncState: syncState, cloudStatus: cloudStatus) {
      if let session = cloudStatus?.activePushSession,
         let total = session.entriesTotal, total > 0 {
        let resolved = min(max(session.entriesResolved ?? 0, 0), total)
        return "Cloud syncing \(resolved)/\(total) entries"
      }
      return "Cloud syncing"
    }

    if let lastSync = cloudStatus?.lastSync, !lastSync.isEmpty {
      return "Cloud synced recently"
    }

    return "Cloud connected"
  }

  private static func isCloudConfigured(
    syncState: SyncState,
    cloudStatus: CloudSyncStatus?,
    cloudStatusError: String?
  ) -> Bool {
    syncState != .disabled || cloudStatus != nil || !(cloudStatusError?.isEmpty ?? true)
  }

  private static func isCloudSyncing(
    syncState: SyncState,
    cloudStatus: CloudSyncStatus?
  ) -> Bool {
    if syncState == .syncing {
      return true
    }

    guard let session = cloudStatus?.activePushSession else {
      return false
    }

    let phase = session.phase.lowercased()
    let completion = session.completionState?.lowercased()
    return completion == "in_progress" || phase == "syncing" || phase == "initial_upload"
  }

  private static func needsCloudAttention(
    syncState: SyncState,
    cloudStatus: CloudSyncStatus?,
    cloudStatusError: String?
  ) -> Bool {
    if case .error = syncState {
      return true
    }

    if let cloudStatusError, !cloudStatusError.isEmpty {
      return true
    }

    guard let session = cloudStatus?.activePushSession else {
      return false
    }

    let phase = session.phase.lowercased()
    let completion = session.completionState?.lowercased()
    let attention = session.needsAttentionCount ?? 0

    return phase == "stalled"
      || completion == "blocked"
      || completion == "completed_with_issues"
      || attention > 0
  }
}
