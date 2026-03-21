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

  var summaryText: String {
    switch self {
    case .connect:
      return "Enter your Contextify Cloud API key to connect this Mac."
    case .manage:
      return "Update the API key or device name for this Mac's cloud connection."
    }
  }

  var linkLabel: String {
    switch self {
    case .connect:
      return "Get API Key"
    case .manage:
      return "Manage API Keys"
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
  @State private var localConversationCount: Int = 0
  @State private var localProjectCount: Int = 0
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
    .formStyle(.grouped)
    .onAppear {
      loadConfiguration()
      wasOffline = syncManager.cloudOffline
      loadLocalStats()
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
        originalAPIKey: connectionSheetMode == .manage ? apiKey : "",
        originalDeviceName: connectionSheetMode == .manage ? deviceName : (Host.current().localizedName ?? deviceName),
        isSaving: isSavingConnection,
        errorMessage: connectionSheetError,
        onSave: saveConfiguration,
        onDisconnect: isConfigured ? { showDisconnectConfirmation = true } : nil
      )
    }
    .onChange(of: draftApiKey) { _, _ in
      if connectionSheetError != nil {
        connectionSheetError = nil
      }
    }
    .onChange(of: draftDeviceName) { _, _ in
      if connectionSheetError != nil {
        connectionSheetError = nil
      }
    }
    .alert("Disconnect Cloud Sync?", isPresented: $showDisconnectConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Disconnect", role: .destructive) {
        disconnect()
      }
    } message: {
      Text("This removes this Mac's cloud sync configuration. Local data stays on this Mac, and cloud data is not deleted.")
    }
    // No .onDisappear cleanup - sync lives at app level
  }

  // MARK: - Cloud Connection Section

  @ViewBuilder
  private var serverConfigurationSection: some View {
    Section("Connection") {
      VStack(alignment: .leading, spacing: 12) {
        if isConfigured {
          configuredConnectionSummary
        } else {
          unconfiguredConnectionSummary
        }

        if let message = saveMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(message.contains("Error") ? .red : .green)
            .accessibilityIdentifier("cloud-save-message")
        }
      }
    }
  }

  @ViewBuilder
  private var unconfiguredConnectionSummary: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("This Mac is not connected to Contextify Cloud yet.")
        .font(.subheadline)
        .accessibilityIdentifier("cloud-connection-empty-state")

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
      .accessibilityIdentifier("cloud-connect-button")
      .accessibilityHint("Opens the cloud connection sheet")
    }
  }

  @ViewBuilder
  private var configuredConnectionSummary: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let profile = syncManager.cloudAccountProfile {
        HStack(alignment: .top, spacing: 18) {
          compactSummaryFact(label: "Signed in as", value: profile.email)
          compactSummaryFact(label: "Workspace", value: profile.tenantName)
          compactSummaryFact(label: "Device name", value: deviceName)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("cloud-connection-summary-row")
      } else if let error = syncManager.cloudAccountError {
        Text("Account details unavailable: \(error)")
          .font(.caption)
          .foregroundStyle(.orange)
          .accessibilityIdentifier("cloud-account-error")

        compactSummaryFact(label: "Device name", value: deviceName)
      } else {
        Text("Resolving account details...")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("cloud-account-loading")

        compactSummaryFact(label: "Device name", value: deviceName)
      }

      Button("Manage Cloud Connection") {
        connectionSheetMode = .manage
        connectionSheetError = nil
        draftApiKey = apiKey
        draftDeviceName = deviceName
        showConnectionSheet = true
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("cloud-manage-button")
      .accessibilityHint("Opens the cloud connection sheet")
    }
  }

  // MARK: - Sync Status Section

  @ViewBuilder
  private var syncStatusSection: some View {
    Section("Status") {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 10) {
            syncStatusBadge
            Text(stateHeadlineText)
              .font(.subheadline.weight(.medium))
              .accessibilityIdentifier("cloud-sync-status-headline")
          }

          if showReconnectBanner {
            Text(reconnectBannerText)
              .font(.caption)
              .foregroundStyle(.green)
              .padding(6)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.green.opacity(0.1))
              .cornerRadius(4)
              .accessibilityIdentifier("cloud-reconnect-banner")
          }

          if let summary = connectionSummaryText {
            Text(summary)
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("cloud-sync-status-summary")
          }

          if let session = visibleActivePushSession, showsBulkCatchUpProgress {
            activeSessionProgressCard(session: session)
          } else if showsClientSideBulkCatchUpProgress {
            clientSideProgressCard
          }

          if let message = statusErrorMessage {
            VStack(alignment: .leading, spacing: 4) {
              Text("Latest error")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityIdentifier("cloud-sync-error-heading")
              Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("cloud-sync-error-message")

              if let reportURL = syncManager.syncErrorReportURL {
                Button {
                  NSWorkspace.shared.open(reportURL)
                } label: {
                  Label("Report Issue", systemImage: "envelope")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Report this sync error to support via email")
              }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .cornerRadius(6)
          }

          if let lastSync = syncManager.lastSyncDate {
            syncFactRow(label: "Last sync", value: relativeTimeString(from: lastSync))
          }

          if let uploadSummary = lastUploadSummary {
            syncFactRow(
              label: "Last upload",
              value: uploadSummary
            )
          }
        }

        if let status = syncManager.cloudStatus {
          Divider()

          HStack(spacing: 0) {
            cloudStatItem(
              value: formatCount(status.entriesSynced),
              label: "Cloud entries"
            )
            Spacer()
            cloudStatItem(
              value: formatCount(localProjectCount),
              label: "Projects"
            )
            Spacer()
            cloudStatItem(
              value: formatCount(localConversationCount),
              label: "Conversations"
            )
            Spacer()
            cloudStatItem(
              value: "\(status.devices.count)",
              label: status.devices.count == 1 ? "Device" : "Devices"
            )
          }
        }
      }
    }
  }

  private func cloudStatItem(value: String, label: String) -> some View {
    VStack(spacing: 2) {
      Text(value)
        .font(.title3.weight(.semibold).monospacedDigit())
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
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
    Section("Controls") {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
          Button {
            syncManager.triggerSync()
            Task { await syncManager.refreshStatusFromServer() }
          } label: {
            Label(primaryActionLabel, systemImage: "arrow.triangle.2.circlepath")
          }
          .buttonStyle(.bordered)
          .disabled(syncManager.syncState == .syncing)
          .accessibilityIdentifier("cloud-sync-now-button")

          Button {
            openCloudSyncPage()
          } label: {
            Label("View Activity", systemImage: "globe")
          }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("cloud-view-activity-button")
          .accessibilityHint("Opens the cloud sync activity page in your browser")
        }

        Toggle("Auto-sync every 5 minutes", isOn: Binding(
          get: { syncManager.autoSyncEnabled },
          set: { syncManager.setAutoSync(enabled: $0) }
        ))
        .accessibilityIdentifier("cloud-auto-sync-toggle")
      }
    }
  }

  // MARK: - Status Mapping

  private enum SyncDisplayState {
    case healthy
    case syncing
    case waitingForIngest
    case deferred
    case offline
    case needsAttention
    case error
    case disabled
  }

  private var activePushSession: CloudActivePushSessionStatus? {
    syncManager.cloudStatus?.activePushSession
  }

  /// Returns the server's active push session only when it belongs to this
  /// client's current connection. Returns nil for orphaned sessions so all
  /// UI derivation treats them as nonexistent.
  private var visibleActivePushSession: CloudActivePushSessionStatus? {
    guard let session = activePushSession, !syncManager.isActiveSessionOrphaned else {
      return nil
    }
    return session
  }

  private var lastUploadSummary: String? {
    guard let pushResult = syncManager.lastPushResult else { return nil }
    guard pushResult.entriesPushed > 0 else { return nil }
    let noun = pushResult.entriesPushed == 1 ? "entry" : "entries"
    return "\(formatCount(pushResult.entriesPushed)) new \(noun) uploaded"
  }

  private var displayState: SyncDisplayState {
    if syncManager.syncState == .disabled { return .disabled }
    if syncManager.cloudOffline { return .offline }

    // Only use server-side session state when the session belongs to this
    // client's current connection. After disconnect/reconnect the server may
    // still report a stalled session from the old connection which is no
    // longer actionable.
    if let session = visibleActivePushSession {
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
    if syncManager.syncState == .waitingForIngest { return .waitingForIngest }
    if syncManager.syncState == .deferred { return .deferred }
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
    case .waitingForIngest:
      statusBadge(text: "Waiting", systemImage: "hourglass", tint: .secondary)
    case .deferred:
      statusBadge(text: "Deferred", systemImage: "clock.arrow.circlepath", tint: .secondary)
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
      return "Cloud up to date."
    case .syncing:
      if showsBulkCatchUpProgress,
         let session = visibleActivePushSession,
         let total = session.entriesTotal,
         let resolved = session.entriesResolved,
         total > 0 {
        return "Uploading catch-up batch (\(formatPercent(resolved: min(max(resolved, 0), total), total: total)))."
      }
      return "Uploading recent changes."
    case .waitingForIngest:
      return "Waiting for transcript ingestion to complete before syncing."
    case .deferred:
      return "Sync paused while transcript ingestion is active."
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
    case .waitingForIngest:
      return "Sync will begin automatically as soon as ingestion finishes."
    case .deferred:
      return "Sync will retry on the next scheduled cycle, or you can sync manually."
    case .offline:
      return "Changes are saved locally and queued for upload. Upload resumes automatically when connection returns."
    case .needsAttention:
      if let session = visibleActivePushSession, session.phase.lowercased() == "stalled" {
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
    if let session = visibleActivePushSession, let pending = pendingEntriesCount(session: session), pending > 0 {
      return "Back online. Uploading \(formatCount(pending)) pending entries..."
    }
    return "Back online. Resuming cloud upload..."
  }

  private var showsBulkCatchUpProgress: Bool {
    if let session = visibleActivePushSession,
       (syncManager.cloudStatus?.pendingBatches ?? 0) > 0 {
      let completion = session.completionState?.lowercased()
      return completion == "in_progress" && (session.entriesTotal ?? 0) > 0
    }
    return false
  }

  private var showsClientSideBulkCatchUpProgress: Bool {
    visibleActivePushSession == nil
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

  private func loadLocalStats() {
    do {
      let dbURL = try DatabaseManager.shared.databasePath()
      let service = try ContextifyQueryService(databaseURL: dbURL, readOnly: true)
      let dbCounts = try service.counts()
      localConversationCount = dbCounts.transcriptCount
      localProjectCount = dbCounts.projectCount
    } catch {
      localConversationCount = 0
    }
  }

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

    guard CloudConnectionSheet.isStructurallyValidAPIKey(trimmedApiKey) else {
      connectionSheetError = "API keys must match the format ctx_<16 hex>_<24 hex>."
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

      let profile: CloudAccountProfile
      do {
        profile = try await syncManager.validateConnection(
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
          mode: mode,
          validatedProfile: profile
        )
      }
    }
  }

  @MainActor
  private func persistConfiguration(
    apiKey: String,
    deviceName: String,
    mode: ConnectionSheetMode,
    validatedProfile: CloudAccountProfile
  ) {
    self.apiKey = apiKey
    self.deviceName = deviceName
    draftApiKey = apiKey
    draftDeviceName = deviceName
    let existing = syncManager.loadConfig()
    let finalConfig = CloudConfig.mergedForConnectionUpdate(
      existing: existing,
      serverURL: CloudConfig.defaultServerURL,
      apiKey: self.apiKey,
      deviceId: MachineID.current(),
      deviceName: self.deviceName
    )
    if let existing, existing.apiKey != apiKey {
      log.info("[CLOUD-SETTINGS] API key changed; resetting cloud sync cursors")
    }

    syncManager.saveConfig(finalConfig)
    syncManager.configure(config: finalConfig)
    syncManager.setValidatedAccountProfile(validatedProfile)
    if finalConfig.enabled {
      syncManager.startAppLevelAutoSync()
      syncManager.triggerSync()
      Task {
        await syncManager.refreshStatusFromServer()
      }
    }
    Task { await syncManager.refreshAccountProfileFromServer() }
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
        return "The API key was rejected and was not saved. Check the key and try again."
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
      .accessibilityIdentifier("cloud-sync-status-badge")
      .accessibilityLabel("Sync status")
      .accessibilityValue(text)
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
  private func compactSummaryFact(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.subheadline)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
    .accessibilityValue(value)
    .accessibilityIdentifier("cloud-summary-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
  }
}

private struct CloudConnectionSheet: View {
  private enum FocusField: Hashable {
    case apiKey
    case deviceName
  }

  let mode: ConnectionSheetMode
  @Binding var apiKey: String
  @Binding var deviceName: String
  let originalAPIKey: String
  let originalDeviceName: String
  let isSaving: Bool
  let errorMessage: String?
  let onSave: () -> Void
  let onDisconnect: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var showDisconnectInfo: Bool = false
  @FocusState private var focusedField: FocusField?

  private var trimmedAPIKey: String {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedDeviceName: String {
    deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var hasMeaningfulChanges: Bool {
    trimmedAPIKey != originalAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
      || trimmedDeviceName != originalDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var apiKeyFormatError: String? {
    guard !trimmedAPIKey.isEmpty else { return nil }
    guard Self.isStructurallyValidAPIKey(trimmedAPIKey) else {
      return "Invalid API key format. Use a valid Contextify Cloud API key."
    }
    return nil
  }

  private var canConfirm: Bool {
    !trimmedAPIKey.isEmpty && apiKeyFormatError == nil && !isSaving && hasMeaningfulChanges
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(mode.title)
        .font(.title3.weight(.semibold))
        .accessibilityIdentifier("cloud-connection-sheet-title")

      Text(mode.summaryText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("cloud-connection-sheet-summary")

      if let settingsURL = URL(string: "\(CloudConfig.defaultServerURL)/cloud/settings") {
        Link(mode.linkLabel, destination: settingsURL)
          .buttonStyle(.link)
          .font(.caption)
          .modifier(PointingHandCursorModifier())
          .accessibilityIdentifier("cloud-connection-api-key-link")
          .accessibilityHint("Opens the Contextify Cloud settings page in your browser")
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("API Key")
          .font(.subheadline)
        TextField("ctx_...", text: $apiKey)
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
#if os(macOS)
          .autocorrectionDisabled(true)
#endif
          .disabled(isSaving)
          .focused($focusedField, equals: .apiKey)
          .accessibilityIdentifier("cloud-connection-api-key")
          .accessibilityLabel("API Key")
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Device Name")
          .font(.subheadline)
        TextField("My Mac", text: $deviceName)
          .textFieldStyle(.roundedBorder)
          .disabled(isSaving)
          .focused($focusedField, equals: .deviceName)
          .accessibilityIdentifier("cloud-connection-device-name")
          .accessibilityLabel("Device Name")
      }

      if let message = errorMessage ?? apiKeyFormatError {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("cloud-connection-error")
      }

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .disabled(isSaving)
        .accessibilityIdentifier("cloud-connection-cancel")
        .accessibilityHint("Closes the cloud connection sheet without saving")

        if let onDisconnect {
          HStack(spacing: 6) {
            Button("Disconnect") {
              dismiss()
              onDisconnect()
            }
            .foregroundStyle(.red)
            .disabled(isSaving)
            .accessibilityIdentifier("cloud-connection-disconnect")
            .accessibilityHint("Disconnects this Mac from cloud sync")

            Button {
              showDisconnectInfo.toggle()
            } label: {
              Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isSaving)
            .popover(isPresented: $showDisconnectInfo, arrowEdge: .bottom) {
              VStack(alignment: .leading, spacing: 8) {
                Text("Disconnect stops cloud sync on this Mac.")
                  .font(.headline)
                Text("Your local data stays on this Mac.")
                Text("Your cloud data is not deleted.")
                Text("You can reconnect later with the same or a different API key.")
              }
              .font(.caption)
              .padding(12)
              .frame(width: 280, alignment: .leading)
              .accessibilityIdentifier("cloud-connection-disconnect-popover")
            }
            .accessibilityIdentifier("cloud-connection-disconnect-info")
            .accessibilityLabel("Explain disconnect")
            .accessibilityHint("Shows what disconnect does and does not remove")
          }
        }

        Spacer()

        if canConfirm {
          Button(mode.confirmLabel) {
            onSave()
          }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .focusable()
          .accessibilityIdentifier("cloud-connection-confirm")
          .accessibilityHint("Validates and saves the cloud connection")
        } else {
          Button(mode.confirmLabel) {}
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityIdentifier("cloud-connection-confirm")
            .accessibilityHint("Validates and saves the cloud connection")
        }

        if isSaving {
          ProgressView()
            .controlSize(.small)
            .accessibilityIdentifier("cloud-connection-saving")
        }
      }
    }
    .padding(20)
    .frame(width: 440)
    .interactiveDismissDisabled(isSaving)
    .onChange(of: errorMessage) { _, newValue in
      guard newValue != nil else { return }
      focusAndSelectAPIKey()
    }
  }

  @MainActor
  private func focusAndSelectAPIKey() {
    focusedField = .apiKey
    DispatchQueue.main.async {
      (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
    }
  }

  static func isStructurallyValidAPIKey(_ key: String) -> Bool {
    let parts = key.split(separator: "_", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == "ctx" else { return false }
    guard parts[1].count == 16, parts[2].count == 24 else { return false }
    return parts[1].allSatisfy(\.isHexDigit) && parts[2].allSatisfy(\.isHexDigit)
  }
}

private struct PointingHandCursorModifier: ViewModifier {
  @State private var cursorPushed = false

  func body(content: Content) -> some View {
    content.onHover { hovering in
      if hovering, !cursorPushed {
        NSCursor.pointingHand.push()
        cursorPushed = true
      } else if !hovering, cursorPushed {
        NSCursor.pop()
        cursorPushed = false
      }
    }
  }
}

#Preview {
  CloudSettingsView()
    .frame(width: 520)
}
