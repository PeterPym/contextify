import SwiftUI
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "CloudSettings")

struct CloudSettingsView: View {
  @State private var syncManager = CloudSyncManager()

  // MARK: - Form Fields

  @State private var serverURL: String = ""
  @State private var apiKey: String = ""
  @State private var deviceName: String = ""

  // MARK: - UI State

  @State private var isConfigured: Bool = false
  @State private var autoSyncEnabled: Bool = false
  @State private var oneShotSyncTask: Task<Void, Never>?
  @State private var autoSyncTask: Task<Void, Never>?
  @State private var showDisconnectConfirmation: Bool = false
  @State private var saveMessage: String?

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
    }
    .onDisappear {
      oneShotSyncTask?.cancel()
      stopAutoSync()
      autoSyncEnabled = false
    }
  }

  // MARK: - Server Configuration Section

  @ViewBuilder
  private var serverConfigurationSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        Text("Server Configuration")
          .font(.headline)

        VStack(alignment: .leading, spacing: 8) {
          Text("Cloud URL")
            .font(.subheadline)
          TextField("https://cloud.contextify.sh", text: $serverURL)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("API Key")
            .font(.subheadline)
          SecureField("ctx_...", text: $apiKey)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Device Name")
            .font(.subheadline)
          TextField("My Mac", text: $deviceName)
            .textFieldStyle(.roundedBorder)
        }

        HStack {
          Button("Save") {
            saveConfiguration()
          }
          .buttonStyle(.borderedProminent)
          .tint(Color.accentColor)
          .disabled(serverURL.isEmpty || apiKey.isEmpty)

          if let message = saveMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(message.contains("Error") ? .red : .green)
          }
        }
        .padding(.top, 4)
      }
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
          // Current state
          HStack(spacing: 8) {
            stateIndicator
            Text(stateDescription)
              .font(.body)
          }

          // Error message
          if case .error(let message) = syncManager.syncState {
            Text(message)
              .font(.caption)
              .foregroundStyle(.red)
              .padding(6)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.red.opacity(0.1))
              .cornerRadius(4)
          }

          // Last sync time
          if let lastSync = syncManager.lastSyncDate {
            HStack(spacing: 4) {
              Text("Last sync:")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(relativeTimeString(from: lastSync))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          // Entries synced
          if let pushResult = syncManager.lastPushResult {
            HStack(spacing: 4) {
              Text("Last push:")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text("\(pushResult.entriesPushed) pushed, \(pushResult.duplicatesSkipped) skipped")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          if let pullResult = syncManager.lastPullResult {
            HStack(spacing: 4) {
              Text("Last pull:")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text("\(pullResult.entriesImported) imported, \(pullResult.entriesSkipped) skipped")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
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
          Button("Sync Now") {
            startOneShotSync()
          }
          .buttonStyle(.bordered)
          .disabled(syncManager.syncState == .syncing)

          if syncManager.syncState == .syncing {
            ProgressView()
              .controlSize(.small)
          }
        }

        Toggle("Auto-sync every 5 minutes", isOn: $autoSyncEnabled)
          .onChange(of: autoSyncEnabled) { _, newValue in
            if newValue {
              startAutoSync()
            } else {
              stopAutoSync()
            }
          }

        Button("Disconnect") {
          showDisconnectConfirmation = true
        }
        .buttonStyle(.bordered)
        .foregroundStyle(.red)
        .alert("Disconnect Cloud Sync?", isPresented: $showDisconnectConfirmation) {
          Button("Cancel", role: .cancel) {}
          Button("Disconnect", role: .destructive) {
            disconnect()
          }
        } message: {
          Text("This will remove your cloud sync configuration. Your local data will not be affected.")
        }
      }
    }
  }

  // MARK: - State Indicator

  @ViewBuilder
  private var stateIndicator: some View {
    switch syncManager.syncState {
    case .idle:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .syncing:
      ProgressView()
        .controlSize(.small)
    case .error:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    case .disabled:
      Image(systemName: "minus.circle.fill")
        .foregroundStyle(.secondary)
    }
  }

  private var stateDescription: String {
    switch syncManager.syncState {
    case .idle:
      return "Connected"
    case .syncing:
      return "Syncing..."
    case .error:
      return "Error"
    case .disabled:
      return "Disabled"
    }
  }

  // MARK: - Actions

  private func loadConfiguration() {
    if let config = syncManager.loadConfig() {
      serverURL = config.serverURL
      apiKey = config.apiKey
      deviceName = config.deviceName
      isConfigured = true
      syncManager.configure(config: config)
      log.info("[CLOUD-SETTINGS] Configuration loaded from disk")
    } else {
      // Pre-fill device name with hostname
      deviceName = Host.current().localizedName ?? ""
      isConfigured = false
      log.debug("[CLOUD-SETTINGS] No configuration found")
    }
  }

  private func saveConfiguration() {
    let config = CloudConfig(
      serverURL: serverURL,
      apiKey: apiKey,
      deviceId: MachineID.current(),
      deviceName: deviceName,
      enabled: true,
      lastPullSequence: 0
    )

    // Preserve lastPullSequence if updating an existing config
    var finalConfig = config
    if let existing = syncManager.loadConfig() {
      finalConfig = CloudConfig(
        serverURL: serverURL,
        apiKey: apiKey,
        deviceId: MachineID.current(),
        deviceName: deviceName,
        enabled: true,
        lastPullSequence: existing.lastPullSequence
      )
    }

    syncManager.saveConfig(finalConfig)
    syncManager.configure(config: finalConfig)
    isConfigured = true
    saveMessage = "Saved"
    log.info("[CLOUD-SETTINGS] Configuration saved")

    // Clear the save message after a brief delay
    Task {
      try? await Task.sleep(for: .seconds(2))
      await MainActor.run {
        if saveMessage == "Saved" {
          saveMessage = nil
        }
      }
    }
  }

  private func startOneShotSync() {
    guard isConfigured else { return }

    let manager = syncManager
    oneShotSyncTask = Task.detached(priority: .userInitiated) {
      do {
        let dbURL = try DatabaseManager.shared.databasePath()
        let queryService = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
        await manager.sync(using: queryService)
      } catch {
        await manager.setErrorForUI("Failed to open local database for sync.")
      }
    }
  }

  private func startAutoSync() {
    stopAutoSync()
    log.info("[CLOUD-SETTINGS] Starting auto-sync (every 5 minutes)")

    let manager = syncManager
    autoSyncTask = Task.detached(priority: .background) {
      while !Task.isCancelled {
        do {
          let dbURL = try DatabaseManager.shared.databasePath()
          let queryService = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
          await manager.sync(using: queryService)
        } catch {
          await manager.setErrorForUI("Auto-sync failed to open local database.")
        }
        try? await Task.sleep(for: .seconds(300))
      }
    }
  }

  private func stopAutoSync() {
    autoSyncTask?.cancel()
    autoSyncTask = nil
  }

  private func disconnect() {
    oneShotSyncTask?.cancel()
    stopAutoSync()

    // Remove the config file
    let configFile = CloudConfig.configFile
    do {
      if FileManager.default.fileExists(atPath: configFile.path) {
        try FileManager.default.removeItem(at: configFile)
      }
    } catch {
      log.error("[CLOUD-SETTINGS] Failed to remove config file: \(error.localizedDescription, privacy: .public)")
    }

    // Reset UI state
    serverURL = ""
    apiKey = ""
    deviceName = Host.current().localizedName ?? ""
    isConfigured = false
    autoSyncEnabled = false
    saveMessage = nil

    // Reset manager state
    syncManager = CloudSyncManager()

    log.info("[CLOUD-SETTINGS] Disconnected from cloud sync")
  }

  // MARK: - Helpers

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
  }()

  private func relativeTimeString(from date: Date) -> String {
    Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
  }
}

#Preview {
  CloudSettingsView()
    .frame(width: 520)
}
