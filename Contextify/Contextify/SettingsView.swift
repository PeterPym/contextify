import SwiftUI
import OSLog
import ContextifyCore
import UniformTypeIdentifiers

private let log = Logger(subsystem: "dev.contextify", category: "Settings")

struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem {
          Label("General", systemImage: "gearshape")
        }

      DatabaseSettingsView()
        .tabItem {
          Label("Database", systemImage: "cylinder")
        }
    }
    .frame(width: 550, height: 450)
  }
}

struct GeneralSettingsView: View {
  @AppStorage("outputsDirectory") private var outputsDirectory = "~/Contextify/outputs"

  var body: some View {
    Form {
      Section {
        Text("General Settings")
          .font(.headline)

        Divider()

        LabeledContent("Outputs Directory:") {
          Text(outputsDirectory)
            .foregroundStyle(.secondary)
            .font(.caption)
        }

        Text("Configure application preferences and behavior")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 8)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

struct DatabaseSettingsView: View {
  @State private var currentLocation: String = ""
  @State private var isCustomLocation: Bool = false
  @State private var isMigrating: Bool = false
  @State private var migrationError: String?
  @State private var showingFilePicker: Bool = false
  @State private var conflictWarning: String?

  var body: some View {
    Form {
      Section {
        Text("Database Settings")
          .font(.headline)

        Divider()

        // Conflict warning (if present)
        if let warning = conflictWarning {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text(warning)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.orange.opacity(0.1))
          .cornerRadius(4)

          Divider()
            .padding(.vertical, 4)
        }

        // Current location display
        VStack(alignment: .leading, spacing: 8) {
          Text("Current Location:")
            .font(.subheadline)

          Text(currentLocation)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
        }
        .padding(.top, 4)

        Divider()
          .padding(.vertical, 8)

        // Location selection
        VStack(alignment: .leading, spacing: 12) {
          Text("Storage Location:")
            .font(.subheadline)

          Picker("", selection: $isCustomLocation) {
            Text("Default Location").tag(false)
            Text("Custom Location").tag(true)
          }
          .pickerStyle(.radioGroup)
          .disabled(isMigrating)

          if isCustomLocation {
            // Quick presets
            VStack(alignment: .leading, spacing: 8) {
              Text("Quick Presets:")
                .font(.caption)
                .foregroundStyle(.secondary)

              HStack(spacing: 8) {
                if let dropboxPath = getDropboxPath() {
                  Button(action: { migrateToPreset(dropboxPath, name: "Dropbox") }) {
                    Label("Dropbox", systemImage: "cloud")
                  }
                  .buttonStyle(.bordered)
                  .disabled(isMigrating)
                }

                if let iCloudPath = getICloudPath() {
                  Button(action: { migrateToPreset(iCloudPath, name: "iCloud Drive") }) {
                    Label("iCloud Drive", systemImage: "icloud")
                  }
                  .buttonStyle(.bordered)
                  .disabled(isMigrating)
                }
              }
            }

            Divider()
              .padding(.vertical, 4)

            Button(action: { showingFilePicker = true }) {
              Label("Choose Custom Location...", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(isMigrating)
          }
        }

        // Migration status
        if isMigrating {
          HStack {
            ProgressView()
              .controlSize(.small)
            Text("Migrating database...")
              .foregroundStyle(.secondary)
          }
          .padding(.top, 8)
        }

        // Error display
        if let error = migrationError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .cornerRadius(4)
            .padding(.top, 8)
        }

        Divider()
          .padding(.vertical, 8)

        // Quick actions
        HStack(spacing: 8) {
          Button("Open Folder") {
            openDatabaseFolder()
          }
          .buttonStyle(.bordered)

          Button("Backup") {
            backupDatabase()
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .fileImporter(
      isPresented: $showingFilePicker,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      handleFileSelection(result)
    }
    .onAppear {
      loadCurrentLocation()
    }
    .onChange(of: isCustomLocation) { _, newValue in
      if !newValue {
        resetToDefaultLocation()
      }
    }
  }

  // MARK: - Actions

  private func loadCurrentLocation() {
    do {
      let path = try DatabaseManager.shared.databasePath()
      currentLocation = path.deletingLastPathComponent().path
      isCustomLocation = HUDPreferences.getCustomDatabaseLocation() != nil

      // Check for multi-machine conflicts
      if let conflict = try? DatabaseManager.shared.checkForAccessConflicts() {
        switch conflict {
        case .recentConflict(let machine, let timeSince):
          let minutes = Int(timeSince / 60)
          conflictWarning = "Warning: \(machine) accessed this database \(minutes) minute\(minutes == 1 ? "" : "s") ago. Concurrent access may cause sync issues."
        case .multiMachine(let machines):
          conflictWarning = "Info: This database has been accessed from: \(machines.joined(separator: ", "))"
        }
      } else {
        conflictWarning = nil
      }
    } catch {
      log.error("Failed to load database location: \(error)")
      currentLocation = "Unknown"
    }
  }

  private func openDatabaseFolder() {
    do {
      let path = try DatabaseManager.shared.databasePath()
      NSWorkspace.shared.open(path.deletingLastPathComponent())
    } catch {
      log.error("Failed to open database folder: \(error)")
    }
  }

  private func backupDatabase() {
    // Note: This launches the backup script in the project directory
    // For now, this is a placeholder - full backup integration TBD
    do {
      let scriptPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("code/projects/contextify/scripts/db_manager.sh")

      if FileManager.default.fileExists(atPath: scriptPath.path) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath.path, "backup"]
        try task.run()
        log.info("Backup script launched")
      } else {
        log.warning("Backup script not found at: \(scriptPath.path)")
      }
    } catch {
      log.error("Backup failed: \(error)")
      migrationError = "Backup failed: \(error.localizedDescription)"
    }
  }

  private func handleFileSelection(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }

      // Start accessing security-scoped resource
      guard url.startAccessingSecurityScopedResource() else {
        migrationError = "Failed to access selected folder"
        return
      }

      // Migrate with resource access, then stop when done
      Task {
        defer { url.stopAccessingSecurityScopedResource() }
        await migrateDatabase(to: url)
      }

    case .failure(let error):
      log.error("File picker error: \(error)")
      migrationError = "Failed to select folder: \(error.localizedDescription)"
    }
  }

  private func migrateDatabase(to targetDirectory: URL) async {
    isMigrating = true
    migrationError = nil

    do {
      try await DatabaseMigration.migrateDatabase(to: targetDirectory, deleteSource: false)
      loadCurrentLocation()
      log.info("Database migrated successfully to: \(targetDirectory.path)")
    } catch {
      log.error("Migration failed: \(error)")
      migrationError = error.localizedDescription
    }

    isMigrating = false
  }

  private func resetToDefaultLocation() {
    guard HUDPreferences.getCustomDatabaseLocation() != nil else { return }

    Task {
      isMigrating = true
      migrationError = nil

      do {
        let defaultDir = try FileManager.default
          .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
          .appendingPathComponent("Contextify")

        // Migrate FIRST, then clear preference on success
        try await DatabaseMigration.migrateDatabase(to: defaultDir, deleteSource: false)
        HUDPreferences.clearCustomDatabaseLocation()
        loadCurrentLocation()
        log.info("Database reset to default location")
      } catch {
        log.error("Reset to default failed: \(error)")
        migrationError = error.localizedDescription
      }

      isMigrating = false
    }
  }

  // MARK: - Preset Locations

  private func getDropboxPath() -> URL? {
    let candidates = [
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Dropbox"),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Dropbox (Personal)"),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Dropbox (Work)")
    ]

    for path in candidates {
      if FileManager.default.fileExists(atPath: path.path) {
        return path.appendingPathComponent("Apps/Contextify")
      }
    }
    return nil
  }

  private func getICloudPath() -> URL? {
    // Try to get iCloud Drive path
    if let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
      return iCloudURL.appendingPathComponent("Documents/Contextify")
    }

    // Fallback: try direct path
    let directPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Contextify")

    if FileManager.default.fileExists(atPath: directPath.path) {
      return directPath
    }

    return directPath  // Return even if it doesn't exist - we'll create it during migration
  }

  private func migrateToPreset(_ url: URL, name: String) {
    Task {
      await migrateDatabase(to: url)
      if migrationError == nil {
        log.info("Migrated to \(name): \(url.path)")
      }
    }
  }
}

#Preview {
  SettingsView()
}
