//
//  DatabaseLocationStepView.swift
//  Contextify
//
//  Step 1 of the App Store onboarding wizard.
//  Allows user to select where to store their database via a single clickable card.
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
/// User must click the card and select a folder before proceeding to step 2.
///
/// For sandboxed App Store builds, we MUST use NSOpenPanel to:
/// 1. Get user consent for folder access
/// 2. Obtain security-scoped bookmark for persistent access
struct DatabaseLocationStepView: View {
  @Binding var isConfigured: Bool

  @State private var selectedPath: String?
  @State private var selectedFolderName: String?
  @State private var isSelecting = false
  @State private var errorMessage: String?

  /// Suggested path for display only - actual access requires NSOpenPanel
  private var suggestedDisplayPath: String {
    let username = NSUserName()
    return "/Users/\(username)/Documents/Contextify"
  }

  /// Display folder name (either selected or suggested)
  private var displayFolderName: String {
    selectedFolderName ?? "Contextify"
  }

  /// Display path (either selected or suggested)
  private var displayPath: String {
    selectedPath ?? suggestedDisplayPath
  }

  /// URL to pre-navigate the open panel to Documents folder
  private var documentsURL: URL {
    let username = NSUserName()
    return URL(fileURLWithPath: "/Users/\(username)/Documents")
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
        .frame(height: 8)

      // Main heading and description
      VStack(spacing: 12) {
        Text("Choose where Contextify saves your data")
          .font(.headline)
          .multilineTextAlignment(.center)

        Text("Contextify stores your conversation history and project data in a folder you control so it's easy to find and back up.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 40)

      // Folder selection card
      folderCard
        .padding(.horizontal, 40)

      // Error message
      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .padding(.horizontal, 40)
      }

      Spacer()

      // Tip text
      Text("Tip: You can also pick a folder in Dropbox, iCloud Drive, or another location that provides automatic backup.")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
    }
  }

  // MARK: - Folder Card

  private var folderCard: some View {
    Button(action: { openFolderPicker() }) {
      HStack(spacing: 16) {
        // Folder icon
        Image(systemName: "folder.fill")
          .font(.system(size: 32))
          .foregroundStyle(.blue)
          .frame(width: 40, height: 40)

        // Folder name and path
        VStack(alignment: .leading, spacing: 4) {
          Text(displayFolderName)
            .font(.body)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)

          Text(displayPath)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer()

        // Checkmark badge (only when configured)
        if isConfigured {
          Image(systemName: "checkmark.circle.fill")
            .font(.title2)
            .foregroundStyle(.green)
        }
      }
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(isConfigured ? Color.accentColor.opacity(0.05) : Color(nsColor: .controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(isConfigured ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isConfigured ? 2 : 1)
      )
      .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    .buttonStyle(.plain)
    .disabled(isSelecting)
  }

  // MARK: - Actions

  /// Opens NSOpenPanel for folder selection.
  /// This is REQUIRED for sandboxed apps to get security-scoped access.
  private func openFolderPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Select"
    panel.message = "Choose where to store your Contextify database.\nA 'Contextify' subfolder will be created if needed."

    // Pre-navigate to Documents folder
    panel.directoryURL = documentsURL

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
      try createAndStoreBookmark(for: finalURL)

      // Update UI state
      selectedPath = finalURL.path
      selectedFolderName = finalURL.lastPathComponent
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
