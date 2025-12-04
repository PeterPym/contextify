//
//  DatabaseLocationStepView.swift
//  Contextify
//
//  Step 1 of the App Store onboarding wizard.
//  Allows user to select where to store their database.
//
//  IMPORTANT: Sandboxed apps MUST use NSOpenPanel to get security-scoped
//  access to folders outside the container. There is no way to programmatically
//  access ~/Documents without user consent via the open panel.
//

import SwiftUI
import AppKit
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Onboarding")

/// Step 1: Database location selection.
/// User must choose a location before proceeding to step 2.
///
/// For sandboxed App Store builds, we MUST use NSOpenPanel to:
/// 1. Get user consent for folder access
/// 2. Obtain security-scoped bookmark for persistent access
struct DatabaseLocationStepView: View {
  @Binding var isConfigured: Bool

  @State private var selectedPath: String?
  @State private var isSelecting = false
  @State private var errorMessage: String?

  /// Suggested path for display only - actual access requires NSOpenPanel
  private var suggestedDisplayPath: String {
    let username = NSUserName()
    return "/Users/\(username)/Documents/Contextify"
  }

  /// URL to pre-navigate the open panel to Documents folder
  private var documentsURL: URL {
    // Try to get real Documents folder, not sandbox container
    let username = NSUserName()
    return URL(fileURLWithPath: "/Users/\(username)/Documents")
  }

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
              Text("Recommended: Documents Folder")
                .font(.subheadline)
                .fontWeight(.medium)
            }

            Text(suggestedDisplayPath)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)

            Button("Select Documents Folder...") {
              openFolderPicker(startingAt: documentsURL)
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

        Button("Choose Different Location...") {
          openFolderPicker(startingAt: nil)
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

      if isConfigured, let path = selectedPath {
        VStack(spacing: 4) {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text("Location configured")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Text(path)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
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

  /// Opens NSOpenPanel for folder selection.
  /// This is REQUIRED for sandboxed apps to get security-scoped access.
  private func openFolderPicker(startingAt directoryURL: URL?) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Select"
    panel.message = "Choose where to store your Contextify database.\nA 'Contextify' subfolder will be created automatically."

    // Pre-navigate to suggested location if provided
    if let dir = directoryURL {
      panel.directoryURL = dir
    }

    guard panel.runModal() == .OK, let selectedURL = panel.url else {
      log.info("[ONBOARD-DB] User cancelled folder selection")
      return
    }

    log.info("[ONBOARD-DB] User selected: \(selectedURL.path)")
    isSelecting = true
    errorMessage = nil

    do {
      // The panel grants temporary security-scoped access - use it now
      guard selectedURL.startAccessingSecurityScopedResource() else {
        throw NSError(domain: "Contextify", code: 1, userInfo: [
          NSLocalizedDescriptionKey: "Could not access the selected folder. Please try again."
        ])
      }
      defer { selectedURL.stopAccessingSecurityScopedResource() }

      // Determine final path - append Contextify subfolder if needed
      var finalURL = selectedURL
      if selectedURL.lastPathComponent.lowercased() != "contextify" {
        finalURL = selectedURL.appendingPathComponent("Contextify")
      }

      // Create directory if needed (we have access from the panel)
      let fm = FileManager.default
      if !fm.fileExists(atPath: finalURL.path) {
        try fm.createDirectory(at: finalURL, withIntermediateDirectories: true)
        log.info("[ONBOARD-DB] Created directory: \(finalURL.path)")
      }

      // Create security-scoped bookmark for persistent access
      // This is what allows the app to access this folder after restart
      try createAndStoreBookmark(for: finalURL)

      selectedPath = finalURL.path
      isConfigured = true
      log.info("[ONBOARD-DB] Configured database location: \(finalURL.path)")

    } catch {
      errorMessage = error.localizedDescription
      log.error("[ONBOARD-DB] Failed to configure location: \(error.localizedDescription)")
    }

    isSelecting = false
  }

  /// Creates a security-scoped bookmark and stores it in preferences.
  private func createAndStoreBookmark(for url: URL) throws {
    // Create bookmark with security scope for persistent access
    let bookmarkData = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    // Store both the path and bookmark in preferences
    HUDPreferences.setCustomDatabaseLocation(url, bookmarkData: bookmarkData)
    log.info("[ONBOARD-DB] Created security-scoped bookmark for: \(url.path)")
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
