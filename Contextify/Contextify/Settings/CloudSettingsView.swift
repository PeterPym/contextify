import SwiftUI
import Combine
import ContextifyCore
import OSLog
import AppKit

private let log = Logger(subsystem: "dev.contextify", category: "CloudSettings")

private enum ConnectionSheetMode {
  case connect
  case manage

  var title: String {
    switch self {
    case .connect:
      return "Connect to Cloud"
    case .manage:
      return "Manage Cloud Connection"
    }
  }

  var confirmLabel: String {
    switch self {
    case .connect:
      return "Connect"
    case .manage:
      return "Save Changes"
    }
  }
}

struct CloudSettingsView: View {
  @State private var syncManager = CloudSyncManager.shared

  @State private var apiKey: String = ""
  @State private var deviceName: String = ""
  @State private var draftApiKey: String = ""
  @State private var draftDeviceName: String = ""

  // MARK: - UI State

  @State private var isConfigured: Bool = false
  @State private var showConnectionSheet: Bool = false
  @State private var connectionSheetMode: ConnectionSheetMode = .connect
  @State private var showDisconnectConfirmation: Bool = false
  @State private var saveMessage: String?
  @State private var connectionSheetError: String?
  @State private var isSavingConnection: Bool = false
  @State private var now: Date = .now
  @State private var wasOffline: Bool = false
  @State private var showReconnectBanner: Bool = false
  @State private var reconnectBannerTask: Task<Void, Never>?

  private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    Form {
      serverConfigurationSection

      if isConfigured {
        syncStatusSection
        controlsSection
      }
    }
    .padding()
    .onAppear {
      loadConfiguration()
      wasOffline = syncManager.cloudOffline
      Task {
        await syncManager.refreshStatusFromServer()
        await syncManager.refreshAccountProfileFromServer()
      }
    }
    .onReceive(clockTimer) { tick in
      now = tick

      let isOfflineNow = syncManager.cloudOffline
      if wasOffline && !isOfflineNow {
        reconnectBannerTask?.cancel()
        showReconnectBanner = true
        reconnectBannerTask = Task {
          try? await Task.sleep(for: .seconds(8))
          await MainActor.run { showReconnectBanner = false }
        }
      }
      wasOffline = isOfflineNow
    }
    .sheet(isPresented: $showConnectionSheet) {
      CloudConnectionSheet(
        mode: connectionSheetMode,
        apiKey: $draftApiKey,
        deviceName: $draftDeviceName,
        isSaving: isSavingConnection,
        errorMessage: connectionSheetError,
        onSave: saveConfiguration,
        onDisconnect: isConfigured ? { showDisconnectConfirmation = true } : nil
      )
    }
    .alert("Disconnect Cloud Sync?", isPresented: $showDisconnectConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Disconnect", role: .destructive) {
        disconnect()
      }
    } message: {
      Text("This will remove your cloud sync configuration. Your local data will not be affected.")
    }
    // No .onDisappear cleanup - sync lives at app level
  }

  // MARK: - Cloud Connection Section

  @ViewBuilder
  private var serverConfigurationSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        Text("Cloud Connection")
          .font(.headline)

        Text(CloudConfig.defaultServerURL)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)

        if isConfigured {
          configuredConnectionSummary
        } else {
          unconfiguredConnectionSummary
        }

        if let message = saveMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(message.contains("Error") ? .red : .green)
        }
      }
    }
  }

  @ViewBuilder
  private var unconfiguredConnectionSummary: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("This Mac is not connected to Contextify Cloud yet.")
        .font(.subheadline)

      Text("Connect with an API key in a modal so the main settings view stays focused on account state instead of raw credential editing.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Button("Connect to Cloud") {
        connectionSheetMode = .connect
        connectionSheetError = nil
        draftApiKey = ""
        draftDeviceName = Host.current().localizedName ?? deviceName
        showConnectionSheet = true
      }
      .buttonStyle(.borderedProminent)
      .tint(Color.accentColor)
    }
  }

  @ViewBuilder
  private var configuredConnectionSummary: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let profile = syncManager.cloudAccountProfile {
        summaryFactRow(label: "Signed in as", value: profile.email)
        summaryFactRow(label: "Workspace", value: profile.tenantName)
      } else if let error = syncManager.cloudAccountError {
        Text("Account details unavailable: \(error)")
          .font(.caption)
          .foregroundStyle(.orange)
      } else {
        Text("Resolving account details...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      summaryFactRow(label: "Device name", value: deviceName)

      Button("Manage Cloud Connection") {
        connectionSheetMode = .manage
        connectionSheetError = nil
        draftApiKey = apiKey
        draftDeviceName = deviceName
        showConnectionSheet = true
      }
      .buttonStyle(.bordered)
    }
  }

  // MARK: - Sync Status Section

  @ViewBuilder
  private var syncStatusSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        Divider()

        Text("Sync Status")
          .font(.headline)

        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 10) {
            syncStatusBadge
            Text(stateHeadlineText)
              .font(.subheadline.weight(.medium))
          }

          if showReconnectBanner {
            Text(reconnectBannerText)
              .font(.caption)
              .foregroundStyle(.green)
              .padding(6)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.green.opacity(0.1))
              .cornerRadius(4)
          }

          if let summary = connectionSummaryText {
            Text(summary)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let session = activePushSession, showsBulkCatchUpProgress {
            activeSessionProgressCard(session: session)
          } else if showsClientSideBulkCatchUpProgress {
            clientSideProgressCard
          }

          if let message = statusErrorMessage {
            VStack(alignment: .leading, spacing: 4) {
              Text("Latest error")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
              Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .cornerRadius(6)
          }

          if let lastSync = syncManager.lastSyncDate {
            syncFactRow(label: "Last sync", value: relativeTimeString(from: lastSync))
          }

          if let pushResult = syncManager.lastPushResult {
            syncFactRow(
              label: "Last upload",
              value: "\(formatCount(pushResult.entriesPushed)) uploaded, \(formatCount(pushResult.duplicatesSkipped)) already on server"
            )
          }
        }
      }
    }
  }

  @ViewBuilder
  private func activeSessionProgressCard(session: CloudActivePushSessionStatus) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Catch-up sync in progress")
        .font(.subheadline.weight(.medium))

      // Prefer client-side progress (always available during push) over server-side
      let totalBatches = syncManager.pushEstimatedTotalBatches
      let batchesDone = syncManager.pushBatchesCompleted
      if totalBatches > 0 {
        ProgressView(value: Double(batchesDone), total: Double(totalBatches))
          .progressViewStyle(.linear)

        let totalEntries = syncManager.pushTotalEntries
        let entriesDone = batchesDone * 500  // approximate
        Text("\(formatCount(min(entriesDone, totalEntries))) / \(formatCount(totalEntries)) entries (\(formatPercent(resolved: batchesDone, total: totalBatches)))")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else if let total = session.entriesTotal, total > 0 {
        // Fallback to server-side session data
        let resolved = min(max(session.entriesResolved ?? 0, 0), total)
        ProgressView(value: Double(resolved), total: Double(total))
          .progressViewStyle(.linear)

        Text("\(formatCount(resolved)) / \(formatCount(total)) entries (\(formatPercent(resolved: resolved, total: total)))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // ETA: prefer client-side, then smoothed server-side, then raw server-side
      let clientEta = syncManager.pushEstimatedSecondsRemaining
      let displayEta = clientEta ?? syncManager.cloudSmoothedEtaSeconds ?? session.etaSeconds

      if let eta = displayEta, eta > 0 {
        Text("About \(etaString(seconds: eta)) remaining")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let attention = session.needsAttentionCount, attention > 0 {
        Text("\(formatCount(attention)) entries need attention")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08))
    .cornerRadius(6)
  }

  /// Progress card shown when client is actively pushing but server session data isn't available yet.
  @ViewBuilder
  private var clientSideProgressCard: some View {
    let totalBatches = syncManager.pushEstimatedTotalBatches
    let batchesDone = syncManager.pushBatchesCompleted
    let totalEntries = syncManager.pushTotalEntries

    VStack(alignment: .leading, spacing: 8) {
      Text("Catch-up sync in progress")
        .font(.subheadline.weight(.medium))

      ProgressView(value: Double(batchesDone), total: Double(totalBatches))
        .progressViewStyle(.linear)

      let entriesDone = batchesDone * 500
      Text("\(formatCount(min(entriesDone, totalEntries))) / \(formatCount(totalEntries)) entries (\(formatPercent(resolved: batchesDone, total: totalBatches)))")
        .font(.caption)
        .foregroundStyle(.secondary)

      if let eta = syncManager.pushEstimatedSecondsRemaining, eta > 0 {
        Text("About \(etaString(seconds: eta)) remaining")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08))
    .cornerRadius(6)
  }

  // MARK: - Controls Section

  @ViewBuilder
  private var controlsSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        Divider()

        Text("Controls")
          .font(.headline)

        HStack(spacing: 12) {
          Button(primaryActionLabel) {
            syncManager.triggerSync()
            Task { await syncManager.refreshStatusFromServer() }
          }
          .buttonStyle(.bordered)
          .disabled(syncManager.syncState == .syncing)

          if syncManager.syncState == .syncing {
            ProgressView()
              .controlSize(.small)
          }

          Button("View Activity") {
            openCloudSyncPage()
          }
          .buttonStyle(.bordered)
        }

        Toggle("Auto-sync every 5 minutes", isOn: Binding(
          get: { syncManager.autoSyncEnabled },
          set: { syncManager.setAutoSync(enabled: $0) }
        ))
      }
    }
  }

  // MARK: - Status Mapping

  private enum SyncDisplayState {
    case healthy
    case syncing
    case offline
    case needsAttention
    case error
    case disabled
  }

  private var activePushSession: CloudActivePushSessionStatus? {
    syncManager.cloudStatus?.activePushSession
  }

  private var displayState: SyncDisplayState {
    if syncManager.syncState == .disabled { return .disabled }
    if syncManager.cloudOffline { return .offline }

    if let session = activePushSession {
      let phase = session.phase.lowercased()
      let completion = session.completionState?.lowercased()
      let attention = session.needsAttentionCount ?? 0

      if phase == "stalled" { return .needsAttention }
      if completion == "blocked" || completion == "completed_with_issues" || attention > 0 {
        return .needsAttention
      }
      if syncManager.syncState == .syncing || completion == "in_progress" {
        return .syncing
      }
    }

    if syncManager.syncState == .syncing { return .syncing }
    if case .error = syncManager.syncState { return .error }
    return .healthy
  }

  @ViewBuilder
  private var syncStatusBadge: some View {
    switch displayState {
    case .healthy:
      statusBadge(text: "Healthy", systemImage: "checkmark.circle.fill", tint: .green)
    case .syncing:
      statusBadge(text: "Syncing", systemImage: "arrow.triangle.2.circlepath", tint: .blue)
    case .offline:
      statusBadge(text: "Offline", systemImage: "wifi.slash", tint: .orange)
    case .needsAttention:
      statusBadge(text: "Attention needed", systemImage: "exclamationmark.triangle.fill", tint: .orange)
    case .error:
      statusBadge(text: "Error", systemImage: "exclamationmark.octagon.fill", tint: .red)
    case .disabled:
      statusBadge(text: "Disabled", systemImage: "minus.circle.fill", tint: .secondary)
    }
  }

  private var stateHeadlineText: String {
    switch displayState {
    case .healthy:
      return "Day-to-day sync is caught up."
    case .syncing:
      if showsBulkCatchUpProgress,
         let session = activePushSession,
         let total = session.entriesTotal,
         let resolved = session.entriesResolved,
         total > 0 {
        return "Uploading catch-up batch (\(formatPercent(resolved: min(max(resolved, 0), total), total: total)))."
      }
      return "Uploading recent changes."
    case .offline:
      return "Cloud sync is offline."
    case .needsAttention:
      return "Cloud sync needs attention."
    case .error:
      return "The latest sync attempt failed."
    case .disabled:
      return "Cloud sync is disabled."
    }
  }

  private var connectionSummaryText: String? {
    switch displayState {
    case .healthy:
      return nil
    case .syncing:
      if showsBulkCatchUpProgress {
        return "This is a bounded catch-up upload, so progress and ETA are shown."
      }
      return nil
    case .offline:
      return "Changes are saved locally and queued for upload. Upload resumes automatically when connection returns."
    case .needsAttention:
      if let session = activePushSession, session.phase.lowercased() == "stalled" {
        return "No recent catch-up progress checkpoint. Retry resumes from the last safe point."
      }
      return "Upload progress is safe, but some entries need review before the session is fully healthy."
    case .error:
      return "The error details below come from the latest local or server sync failure."
    case .disabled:
      return "Connect this Mac to Contextify Cloud to enable sync."
    }
  }

  private var statusErrorMessage: String? {
    if case .error(let message) = syncManager.syncState {
      return message
    }
    return syncManager.cloudStatusError
  }

  private var primaryActionLabel: String {
    switch displayState {
    case .offline, .error, .needsAttention:
      return "Retry Now"
    default:
      return "Sync Now"
    }
  }

  private var reconnectBannerText: String {
    if let session = activePushSession, let pending = pendingEntriesCount(session: session), pending > 0 {
      return "Back online. Uploading \(formatCount(pending)) pending entries..."
    }
    return "Back online. Resuming cloud upload..."
  }

  private var showsBulkCatchUpProgress: Bool {
    if let session = activePushSession,
       (syncManager.cloudStatus?.pendingBatches ?? 0) > 0 {
      let completion = session.completionState?.lowercased()
      return completion == "in_progress" && (session.entriesTotal ?? 0) > 0
    }
    return false
  }

  private var showsClientSideBulkCatchUpProgress: Bool {
    activePushSession == nil
      && syncManager.syncState == .syncing
      && syncManager.pushEstimatedTotalBatches > 1
      && syncManager.pushTotalEntries > 0
  }

  private func pendingEntriesCount(session: CloudActivePushSessionStatus) -> Int? {
    guard let total = session.entriesTotal else { return nil }
    let resolved = session.entriesResolved ?? 0
    return max(0, total - resolved)
  }

  // MARK: - Actions

  private func loadConfiguration() {
    if let config = syncManager.loadConfig() {
      apiKey = config.apiKey
      deviceName = config.deviceName
      draftApiKey = config.apiKey
      draftDeviceName = config.deviceName
      isConfigured = true
      if syncManager.syncState == .idle || syncManager.syncState == .disabled {
        syncManager.configure(config: config)
      }
      Task { await syncManager.refreshAccountProfileFromServer() }
      log.info("[CLOUD-SETTINGS] Configuration loaded from disk")
    } else {
      deviceName = Host.current().localizedName ?? ""
      draftDeviceName = deviceName
      isConfigured = false
      log.debug("[CLOUD-SETTINGS] No configuration found")
    }
  }

  @MainActor
  private func saveConfiguration() {
    connectionSheetError = nil
    let trimmedApiKey = draftApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedDeviceName = draftDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let mode = connectionSheetMode

    guard !trimmedApiKey.isEmpty else {
      connectionSheetError = "The API key is required."
      return
    }

    isSavingConnection = true

    Task { [trimmedApiKey, trimmedDeviceName, mode] in
      defer {
        Task {
          await MainActor.run {
            isSavingConnection = false
          }
        }
      }

      do {
        _ = try await syncManager.validateConnection(
          serverURL: CloudConfig.defaultServerURL,
          apiKey: trimmedApiKey
        )
      } catch {
        await MainActor.run {
          connectionSheetError = userFriendlyConnectionMessage(for: error)
        }
        return
      }

      await MainActor.run {
        persistConfiguration(
          apiKey: trimmedApiKey,
          deviceName: trimmedDeviceName,
          mode: mode
        )
      }
    }
  }

  @MainActor
  private func persistConfiguration(
    apiKey: String,
    deviceName: String,
    mode: ConnectionSheetMode
  ) {
    self.apiKey = apiKey
    self.deviceName = deviceName
    draftApiKey = apiKey
    draftDeviceName = deviceName

    // TODO(self-hosted): Replace CloudConfig.defaultServerURL with serverURL state var.
    let config = CloudConfig(
      serverURL: CloudConfig.defaultServerURL,
      apiKey: self.apiKey,
      deviceId: MachineID.current(),
      deviceName: self.deviceName,
      enabled: true,
      lastPullSequence: 0,
      lastPushTimestamp: nil,
      lastPushEntryId: nil,
      lastPushSessionId: nil,
      lastPushBatchSeq: nil
    )

    var finalConfig = config
    if let existing = syncManager.loadConfig() {
      finalConfig = CloudConfig(
        serverURL: CloudConfig.defaultServerURL,
        apiKey: self.apiKey,
        deviceId: MachineID.current(),
        deviceName: self.deviceName,
        enabled: true,
        lastPullSequence: existing.lastPullSequence,
        lastPushTimestamp: existing.lastPushTimestamp,
        lastPushEntryId: existing.lastPushEntryId,
        lastPushSessionId: existing.lastPushSessionId,
        lastPushBatchSeq: existing.lastPushBatchSeq
      )
    }

    syncManager.saveConfig(finalConfig)
    syncManager.configure(config: finalConfig)
    if finalConfig.enabled {
      syncManager.startAppLevelAutoSync()
      syncManager.triggerSync()
      Task {
        await syncManager.refreshStatusFromServer()
        await syncManager.refreshAccountProfileFromServer()
      }
    }
    isConfigured = true
    let expectedMessage = mode == .connect ? "Connected" : "Connection updated"
    saveMessage = expectedMessage
    showConnectionSheet = false
    log.info("[CLOUD-SETTINGS] Configuration saved")

    Task {
      try? await Task.sleep(for: .seconds(2))
      await MainActor.run {
        if saveMessage == expectedMessage {
          saveMessage = nil
        }
      }
    }
  }

  private func disconnect() {
    syncManager.resetForDisconnect()

    let configFile = CloudConfig.configFile
    do {
      if FileManager.default.fileExists(atPath: configFile.path) {
        try FileManager.default.removeItem(at: configFile)
      }
    } catch {
      log.error("[CLOUD-SETTINGS] Failed to remove config file: \(error.localizedDescription, privacy: .public)")
    }

    apiKey = ""
    deviceName = Host.current().localizedName ?? ""
    draftApiKey = ""
    draftDeviceName = deviceName
    isConfigured = false
    saveMessage = nil
    connectionSheetError = nil

    log.info("[CLOUD-SETTINGS] Disconnected from cloud sync")
  }

  private func openCloudSyncPage() {
    guard let url = URL(string: "\(CloudConfig.defaultServerURL)/cloud/sync") else {
      log.error("[CLOUD-SETTINGS] Failed to build cloud sync page URL")
      return
    }
    NSWorkspace.shared.open(url)
  }

  // MARK: - Helpers

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
  }()

  private func relativeTimeString(from date: Date) -> String {
    if date > now {
      return "just now"
    }
    return Self.relativeDateFormatter.localizedString(for: date, relativeTo: now)
  }

  private func etaString(seconds: Int) -> String {
    if seconds < 60 { return "under a minute" }
    let minutes = Int(round(Double(seconds) / 60.0))
    if minutes < 60 { return "~\(minutes) min" }
    let hours = minutes / 60
    let rem = minutes % 60
    if rem == 0 { return "~\(hours) hr" }
    return "~\(hours) hr \(rem) min"
  }

  private func formatCount(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  private func formatPercent(resolved: Int, total: Int) -> String {
    guard total > 0 else { return "0%" }
    let fraction = Double(resolved) / Double(total)
    return "\(Int((fraction * 100.0).rounded()))%"
  }

  private func userFriendlyConnectionMessage(for error: Error) -> String {
    switch error {
    case let cloudError as CloudSyncError:
      switch cloudError {
      case .unauthorized:
        return "The API key was rejected. Check the key and try again."
      default:
        return cloudError.localizedDescription
      }
    default:
      return error.localizedDescription
    }
  }

  @ViewBuilder
  private func statusBadge(text: String, systemImage: String, tint: Color) -> some View {
    Label(text, systemImage: systemImage)
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .foregroundStyle(tint)
      .background(tint.opacity(0.12))
      .clipShape(Capsule())
  }

  @ViewBuilder
  private func syncFactRow(label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text("\(label):")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func summaryFactRow(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.subheadline)
    }
  }
}

private struct CloudConnectionSheet: View {
  let mode: ConnectionSheetMode
  @Binding var apiKey: String
  @Binding var deviceName: String
  let isSaving: Bool
  let errorMessage: String?
  let onSave: () -> Void
  let onDisconnect: (() -> Void)?

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(mode.title)
        .font(.title3.weight(.semibold))

      Text("The API key is edited here instead of on the main settings surface, so accidental changes are less likely.")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 8) {
        Text("API Key")
          .font(.subheadline)
        SecureField("ctx_...", text: $apiKey)
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
          .disabled(isSaving)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Device Name")
          .font(.subheadline)
        TextField("My Mac", text: $deviceName)
          .textFieldStyle(.roundedBorder)
          .disabled(isSaving)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .disabled(isSaving)

        if let onDisconnect {
          Button("Disconnect") {
            dismiss()
            onDisconnect()
          }
          .foregroundStyle(.red)
          .disabled(isSaving)
        }

        Spacer()

        Button(mode.confirmLabel) {
          onSave()
        }
        .buttonStyle(.borderedProminent)
        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

        if isSaving {
          ProgressView()
            .controlSize(.small)
        }
      }
    }
    .padding(20)
    .frame(width: 440)
    .interactiveDismissDisabled(isSaving)
  }
}

#Preview {
  CloudSettingsView()
    .frame(width: 520)
}
