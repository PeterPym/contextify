import SwiftUI
import OSLog
import ContextifyCore
import UniformTypeIdentifiers
import AppKit

private let log = Logger(subsystem: "dev.contextify", category: "Settings")

// MARK: - Main Settings View (Tabbed)

struct SettingsView: View {
  @ObservedObject var folderAccessController: FolderAccessController

  private static let selectedTabOverrideKey = "Contextify.Settings.SelectedTabOverride"
  private static let selectedTabKey = "Contextify.Settings.SelectedTab"

  @State private var selectedTab: String = "database"

  private var overriddenSelectedTab: String? {
    ContextifyDefaults.shared.string(forKey: Self.selectedTabOverrideKey)
  }

  var body: some View {
    if Sandbox.isSandboxed {
      // App Store build: show both Database and Permissions tabs
      TabView(selection: $selectedTab) {
        DatabaseSettingsTab()
          .tabItem {
            Label("Database", systemImage: "cylinder")
          }
          .tag("database")

        PermissionsSettingsTab(folderAccessController: folderAccessController)
          .tabItem {
            Label("Permissions", systemImage: "folder.badge.plus")
          }
          .tag("permissions")

        CLISkillsSettingsTab()
          .tabItem {
            Label("CLI", systemImage: "terminal")
          }
          .tag("cli")
      }
      .onAppear {
        selectedTab = ContextifyDefaults.shared.string(forKey: Self.selectedTabKey) ?? "database"
        if let overriddenSelectedTab {
          selectedTab = overriddenSelectedTab
        }
      }
      .onChange(of: selectedTab) { _, newValue in
        ContextifyDefaults.shared.set(newValue, forKey: Self.selectedTabKey)
      }
      .frame(width: 450, height: 520)
    } else {
      // DMG build: Database + CLI (no permissions needed)
      TabView(selection: $selectedTab) {
        DatabaseSettingsTab()
          .tabItem {
            Label("Database", systemImage: "cylinder")
          }
          .tag("database")

        CLISkillsSettingsTab()
          .tabItem {
            Label("CLI", systemImage: "terminal")
          }
          .tag("cli")
      }
      .onAppear {
        selectedTab = ContextifyDefaults.shared.string(forKey: Self.selectedTabKey) ?? "database"
        if let overriddenSelectedTab {
          selectedTab = overriddenSelectedTab
        }
      }
      .onChange(of: selectedTab) { _, newValue in
        ContextifyDefaults.shared.set(newValue, forKey: Self.selectedTabKey)
      }
      .frame(width: 520, height: 520)
    }
  }
}

// MARK: - Database Settings Tab

struct DatabaseSettingsTab: View {
  @State private var currentLocation: String = ""
  @State private var isCustomLocation: Bool = false
  @State private var isMigrating: Bool = false
  @State private var migrationError: String?
  @State private var migrationSuccess: String?
  @State private var showingFilePicker: Bool = false
  @State private var conflictWarning: String?
  @State private var showLocationInfo: Bool = false
  @State private var pendingRestart: Bool = false  // App Store: restart required after reset

  private let devMode = DeveloperMode.shared

  private var isDropboxLocation: Bool {
    let normalized = currentLocation.lowercased()
    return normalized.contains("/cloudstorage/dropbox") || normalized.contains("/dropbox/")
  }

  var body: some View {
    Form {
      Section {
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

        if isDropboxLocation {
          DropboxBadge()
            .padding(.top, 4)
        }

        Divider()
          .padding(.vertical, 8)

        // Location selection
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 6) {
            Text("Storage Location:")
              .font(.subheadline)

            InfoButton(isPresented: $showLocationInfo)
              .popover(isPresented: $showLocationInfo) {
                InfoPopoverContent(
                  title: "Custom Database Location",
                  message: locationExplanation
                )
              }
          }

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

        // Success display
        if let success = migrationSuccess {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
              Text("Migration complete")
                .font(.caption)
                .fontWeight(.semibold)
              Text(success)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.green.opacity(0.1))
          .cornerRadius(4)
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

        // Restart required (App Store builds after reset)
        if pendingRestart {
          HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill")
              .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
              Text("Restart Required")
                .font(.caption)
                .fontWeight(.semibold)
              Text("Database location has been reset. Please restart Contextify to choose a new location.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.orange.opacity(0.1))
          .cornerRadius(4)
          .padding(.top, 8)
        }

        if devMode.isEnabled {
          Divider()
            .padding(.vertical, 8)

          Button("Backup (Dev)") {
            backupDatabase()
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding()
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
      migrationSuccess = nil  // Clear success message when toggling
      if !newValue {
        resetToDefaultLocation()
      }
    }
  }

  // MARK: - Help Content

  private var locationExplanation: String {
    """
    Contextify stores all project data, transcripts, and timeline entries in a single database file.

    Default Location:
    • Stored in ~/Library/Application Support/Contextify/
    • Isolated to this Mac
    • Best for single-machine use

    Custom Location (Advanced):
    • Choose any folder: Dropbox, iCloud Drive, external drive, etc
    • When you change your database location, the old file is kept as backup. Delete it manually when you're ready.

    When using Dropbox, iCloud or other cloud sync:
    • You can keep a single database synced and use it as a centralized backup
    • You should NOT run the app simultaneously on multiple machines
    • Contextify will try to warn you if it detects access conflicts, heed this warning.
    """
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
    // Capture old path before migration
    let oldPath = (try? DatabaseManager.shared.databasePath().deletingLastPathComponent().path) ?? "previous location"

    await MainActor.run {
      isMigrating = true
      migrationError = nil
      migrationSuccess = nil
    }

    do {
      try await DatabaseMigration.migrateDatabase(to: targetDirectory, deleteSource: false)
      await MainActor.run {
        loadCurrentLocation()
        migrationSuccess = "Old database kept as backup at:\n\(oldPath)\n\nYou can manually delete it after verifying sync is working."
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

    // App Store builds: clear state and require restart
    // Hot-swapping database location while running is complex and error-prone.
    // Simpler approach: clear state and let next launch show the onboarding wizard.
    #if APPSTORE_BUILD
    log.info("[DB-RESET] App Store build - clearing onboarding state, restart required")
    HUDPreferences.clearAppStoreOnboardingState()
    pendingRestart = true
    #else
    // DMG builds: run the heavy migration work off the main thread
    Task.detached(priority: .userInitiated) {
      // Capture old path before migration
      let oldPath = (try? DatabaseManager.shared.databasePath().deletingLastPathComponent().path) ?? "previous location"

      await MainActor.run {
        isMigrating = true
        migrationError = nil
        migrationSuccess = nil
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
          migrationSuccess = "Old database kept as backup at:\n\(oldPath)\n\nYou can manually delete it after verifying sync is working."
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
    #endif
  }

}

// MARK: - Permissions Settings Tab

struct PermissionsSettingsTab: View {
  @ObservedObject var folderAccessController: FolderAccessController
  @State private var authorizations: [SourceID: SourceAuthorization] = [:]

  var body: some View {
    VStack(spacing: 24) {
      VStack(spacing: 8) {
        Text("Transcript Sources")
          .font(.headline)

        Text("Grant access to folders containing Claude Code and Codex transcripts.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.top, 8)

      VStack(spacing: 12) {
        ForEach(SourceID.allCases, id: \.self) { source in
          SourceAuthorizationRow(
            source: source,
            controller: folderAccessController,
            authorization: authorizations[source]
          ) { updatedAuth in
            authorizations[source] = updatedAuth
            log.info("[SETTINGS] Updated authorization for \(source.rawValue)")
          }
        }
      }

      Spacer()
    }
    .padding()
    .task {
      await loadAuthorizations()
    }
  }

  private func loadAuthorizations() async {
    let allAuths = await folderAccessController.allAuthorizations()
    for auth in allAuths {
      authorizations[auth.id] = auth
    }
  }
}

private struct DropboxBadge: View {
  var body: some View {
    HStack(spacing: 8) {
      Image("dropbox-mark")
        .resizable()
        .interpolation(.high)
        .renderingMode(.original)
        .aspectRatio(contentMode: .fit)
        .frame(width: 48, height: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text("Stored in Dropbox")
          .font(.caption)
          .fontWeight(.semibold)
        Text("Tip: avoid opening this database on multiple Macs at once to prevent sync conflicts.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor))
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
    )
  }
}

#Preview {
  SettingsView(folderAccessController: FolderAccessController())
}

#Preview("Database Tab") {
  DatabaseSettingsTab()
}
