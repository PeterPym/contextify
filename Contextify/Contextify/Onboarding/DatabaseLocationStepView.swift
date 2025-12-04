//
//  DatabaseLocationStepView.swift
//  Contextify
//
//  Step 1 of the App Store onboarding wizard.
//  Allows user to select where to store their database.
//

import SwiftUI
import AppKit
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Onboarding")

/// Step 1: Database location selection.
/// User must choose a location before proceeding to step 2.
struct DatabaseLocationStepView: View {
  @Binding var isConfigured: Bool

  @State private var selectedPath: String?
  @State private var isSelecting = false
  @State private var errorMessage: String?

  private let suggestedPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent("Documents/Contextify").path
  }()

  var body: some View {
    VStack(spacing: 24) {
      // Explanation
      VStack(spacing: 12) {
        Text("Where should Contextify store your data?")
          .font(.headline)

        Text("Your conversation history and project data will be stored in a folder you can access. This ensures your data isn't hidden in a system folder.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 32)

      // Suggested location
      VStack(spacing: 12) {
        GroupBox {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
              Text("Suggested Location")
                .font(.subheadline)
                .fontWeight(.medium)
            }

            Text(suggestedPath)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)

            Button("Use This Location") {
              selectSuggestedLocation()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSelecting)
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        Text("or")
          .font(.caption)
          .foregroundStyle(.tertiary)

        Button("Choose Different Folder...") {
          openFolderPicker()
        }
        .buttonStyle(.bordered)
        .disabled(isSelecting)
      }
      .padding(.horizontal, 32)

      // Status
      if isSelecting {
        HStack {
          ProgressView()
            .controlSize(.small)
          Text("Setting up folder...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .padding(.horizontal, 32)
      }

      if isConfigured {
        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Database location configured")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
      }

      Spacer()

      // Tip
      Text("Tip: You can also choose Dropbox, iCloud Drive, or an external drive for automatic backup.")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }
    .padding(.top, 24)
  }

  // MARK: - Actions

  private func selectSuggestedLocation() {
    isSelecting = true
    errorMessage = nil

    Task { @MainActor in
      do {
        try await configureLocation(URL(fileURLWithPath: suggestedPath))
        isConfigured = true
        log.info("[ONBOARD-DB] Using suggested location: \(suggestedPath)")
      } catch {
        errorMessage = error.localizedDescription
        log.error("[ONBOARD-DB] Failed to configure suggested location: \(error.localizedDescription)")
      }
      isSelecting = false
    }
  }

  private func openFolderPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Select"
    panel.message = "Choose where to store your Contextify database. A 'Contextify' subfolder will be created if needed."

    // Start at Documents
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")

    guard panel.runModal() == .OK, let selectedURL = panel.url else {
      return
    }

    isSelecting = true
    errorMessage = nil

    Task { @MainActor in
      do {
        // Auto-append Contextify subfolder if not already named Contextify
        var finalURL = selectedURL
        if selectedURL.lastPathComponent.lowercased() != "contextify" {
          finalURL = selectedURL.appendingPathComponent("Contextify")
        }

        try await configureLocation(finalURL)
        isConfigured = true
        log.info("[ONBOARD-DB] Using custom location: \(finalURL.path)")
      } catch {
        errorMessage = error.localizedDescription
        log.error("[ONBOARD-DB] Failed to configure custom location: \(error.localizedDescription)")
      }
      isSelecting = false
    }
  }

  private func configureLocation(_ url: URL) async throws {
    let fm = FileManager.default

    // Create directory if needed
    if !fm.fileExists(atPath: url.path) {
      try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // Create security-scoped bookmark
    HUDPreferences.setCustomDatabaseLocation(url)

    // Mark onboarding step as complete (bookmark created)
    selectedPath = url.path
  }
}

#Preview {
  DatabaseLocationStepView(isConfigured: .constant(false))
    .frame(width: 520, height: 400)
}

#Preview("Configured") {
  DatabaseLocationStepView(isConfigured: .constant(true))
    .frame(width: 520, height: 400)
}
