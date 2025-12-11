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
import UniformTypeIdentifiers
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
  @Binding var selectedPath: String?
  @Binding var selectedFolderName: String?

  /// Trigger from parent to open folder picker (e.g., when Enter is pressed)
  @Binding var openPickerTrigger: Bool

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
    VStack(spacing: 16) {
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

      // Tip text
      Text("Tip: You can also pick a folder in Dropbox, iCloud Drive, or another location that provides automatic backup.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
    }
    .padding(.top, 12)
    .onChange(of: openPickerTrigger) { _, triggered in
      if triggered {
        openPickerTrigger = false  // Reset trigger
        openFolderPicker()
      }
    }
  }

  // MARK: - Folder Card

  /// Returns the appropriate folder icon:
  /// - If Dropbox folder is selected, shows custom Dropbox folder icon (system icon doesn't work reliably)
  /// - If another folder is selected, shows that folder's actual icon (respects custom icons)
  /// - Otherwise, shows the generic system folder icon
  private var folderIcon: some View {
    let image: Image

    if let path = selectedPath, isDropboxPath(path) {
      // Use custom Dropbox folder icon - system icon doesn't show correctly on recent macOS
      image = Image("dropbox-folder")
    } else if let path = selectedPath {
      image = Image(nsImage: NSWorkspace.shared.icon(forFile: path))
    } else {
      image = Image(nsImage: NSWorkspace.shared.icon(for: .folder))
    }

    return image
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: 40, height: 40)
  }

  /// Detects if a path is inside Dropbox storage
  private func isDropboxPath(_ path: String) -> Bool {
    // Modern macOS CloudStorage location
    if path.contains("/Library/CloudStorage/Dropbox") {
      return true
    }
    // Legacy Dropbox location
    if path.contains("/Dropbox/") || path.hasSuffix("/Dropbox") {
      return true
    }
    return false
  }

  private var folderCard: some View {
    Button(action: { openFolderPicker() }) {
      HStack(spacing: 16) {
        // Folder icon - uses real macOS system icon
        folderIcon

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
            .foregroundStyle(Color.contextifyGreen)
        }
      }
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 10)
          // When not configured: highlighted as call-to-action (Enter will trigger)
          // When configured: subtle selected state (Next button is now CTA)
          .fill(isConfigured ? Color(nsColor: .controlBackgroundColor) : Color.contextifyBlue.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          // Border: prominent when not configured (CTA), subtle when configured
          .stroke(
            isConfigured ? Color.secondary.opacity(0.3) : Color.contextifyBlue,
            lineWidth: isConfigured ? 1 : 2
          )
      )
      .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    .buttonStyle(.plain)
    .disabled(isSelecting)
    .accessibilityIdentifier("onboarding-folder-card")
    // Note: Enter key is handled by parent's KeyboardHandler, no shortcut needed here
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
  DatabaseLocationStepView(
    isConfigured: .constant(false),
    selectedPath: .constant(nil),
    selectedFolderName: .constant(nil),
    openPickerTrigger: .constant(false)
  )
  .frame(width: 520, height: 400)
}

#Preview("Configured") {
  DatabaseLocationStepView(
    isConfigured: .constant(true),
    selectedPath: .constant("/Users/demo/Documents/Contextify"),
    selectedFolderName: .constant("Contextify"),
    openPickerTrigger: .constant(false)
  )
  .frame(width: 520, height: 400)
}
