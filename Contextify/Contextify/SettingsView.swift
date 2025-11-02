import SwiftUI
import OSLog
import ContextifyCore
import UniformTypeIdentifiers
import AppKit

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
          HStack {
            Text("Current Location:")
              .font(.subheadline)
            Spacer()
            Button(action: { openDatabaseFolder() }) {
              Label("Reveal in Finder", systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
          }

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
            VStack(alignment: .leading, spacing: 8) {
              Text("Selecting a new location will move your database from its current location.")
                .font(.caption)
                .foregroundStyle(.secondary)

              Button(action: { showingFilePicker = true }) {
                Label("Choose Custom Location...", systemImage: "folder")
              }
              .buttonStyle(.bordered)
              .disabled(isMigrating)
            }
            .padding(.top, 4)
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

        #if DEBUG
        Divider()
          .padding(.vertical, 8)

        Button("Backup (Dev)") {
          backupDatabase()
        }
        .buttonStyle(.bordered)
        #endif
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
      do {
        if let conflict = try DatabaseManager.shared.checkForAccessConflicts() {
          switch conflict {
          case .recentConflict(let machine, let timeSince):
            let minutes = Int(timeSince / 60)
            conflictWarning = "Heads-up: \(machine) used this database ~\(minutes)m ago. If two Macs write at once (e.g., via Dropbox), data loss can occur."
          case .multiMachine(let machines):
            conflictWarning = "Info: This database has been accessed from: \(machines.joined(separator: ", "))"
          }
        } else {
          conflictWarning = nil
        }
      } catch {
        log.error("Failed to check access conflicts: \(error.localizedDescription)")
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

      var didStartScope = false
      if Sandbox.isSandboxed {
        guard url.startAccessingSecurityScopedResource() else {
          migrationError = "Failed to access selected folder"
          return
        }
        didStartScope = true
      }

      // Run the heavy migration work off the main thread
      Task.detached(priority: .userInitiated) {
        defer {
          if didStartScope {
            url.stopAccessingSecurityScopedResource()
          }
        }
        await migrateDatabase(to: url)
        await MainActor.run {
          loadCurrentLocation()
        }
      }

    case .failure(let error):
      log.error("File picker error: \(error)")
      migrationError = "Failed to select folder: \(error.localizedDescription)"
    }
  }

  private func migrateDatabase(to targetDirectory: URL) async {
    await MainActor.run {
      isMigrating = true
      migrationError = nil
    }

    do {
      try await DatabaseMigration.migrateDatabase(to: targetDirectory, deleteSource: false)
      await MainActor.run {
        loadCurrentLocation()
      }
      log.info("Database migrated successfully to: \(targetDirectory.path)")
    } catch {
      log.error("Migration failed: \(error)")
      await MainActor.run {
        migrationError = error.localizedDescription
      }
    }

    await MainActor.run {
      isMigrating = false
    }
  }

  private func resetToDefaultLocation() {
    guard HUDPreferences.getCustomDatabaseLocation() != nil else { return }

    // Run the heavy migration work off the main thread
    Task.detached(priority: .userInitiated) {
      await MainActor.run {
        isMigrating = true
        migrationError = nil
      }

      do {
        let defaultDir = try FileManager.default
          .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
          .appendingPathComponent("Contextify")

        // Migrate FIRST, then clear preference on success
        try await DatabaseMigration.migrateDatabase(to: defaultDir, deleteSource: false)
        HUDPreferences.clearCustomDatabaseLocation()
        await MainActor.run {
          loadCurrentLocation()
          log.info("Database reset to default location")
        }
      } catch {
        await MainActor.run {
          migrationError = error.localizedDescription
          log.error("Reset to default failed: \(error)")
        }
      }

      await MainActor.run {
        isMigrating = false
      }
    }
  }

}

#Preview {
  SettingsView()
}
