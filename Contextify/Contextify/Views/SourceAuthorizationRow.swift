//
//  SourceAuthorizationRow.swift
//  Contextify
//
//  Extracted from WelcomeModalView.swift for reuse in onboarding wizard.
//  Displays a single transcript source (Claude/Codex) with authorization status and action button.
//

import SwiftUI
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Permissions")

/// Row displaying authorization status for a transcript source (Claude Code or Codex CLI).
/// Used by WelcomeModalView, PermissionsStepView, and PermissionsSettingsTab.
struct SourceAuthorizationRow: View {
  let source: SourceID
  @ObservedObject var controller: FolderAccessController
  let authorization: SourceAuthorization?
  let onAuthorizationChanged: (SourceAuthorization) -> Void

  @State private var isRequesting = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        // Source name
        Text(source.displayName)
          .font(.headline)

        Spacer()

        // Status chip
        statusChip

        // Action button
        actionButton
      }

      // Error message (if any)
      if let errorMessage = errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundColor(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding()
    .background(Color(nsColor: .controlBackgroundColor))
    .cornerRadius(8)
  }

  private var statusChip: some View {
    let status = authorization?.status ?? .notAuthorized
    let (text, color) = statusDisplay(for: status)

    return Text(text)
      .font(.caption)
      .fontWeight(.medium)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(color.opacity(0.2))
      .foregroundColor(color)
      .cornerRadius(4)
  }

  private var actionButton: some View {
    Group {
      if authorization?.status == .broken {
        Button("Re-link...") {
          requestAccess()
        }
        .buttonStyle(.bordered)
        .disabled(isRequesting)
      } else if authorization?.status == .authorized {
        Button {} label: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
        }
        .buttonStyle(.plain)
        .disabled(true)
      } else {
        Button("Grant Access...") {
          requestAccess()
        }
        .buttonStyle(.bordered)
        .disabled(isRequesting)
      }
    }
  }

  private func statusDisplay(for status: AuthorizationStatus) -> (String, Color) {
    switch status {
    case .authorized: return ("Authorized", .green)
    case .notAuthorized: return ("Awaiting access", .secondary)
    case .broken: return ("Broken", .orange)
    }
  }

  private func requestAccess() {
    isRequesting = true
    errorMessage = nil

    Task { @MainActor in
      do {
        log.info("[PERMISSIONS] ▶ Requesting access for \(source.rawValue, privacy: .public)...")
        let auths = try await controller.requestAccess(for: [source])
        if let auth = auths.first {
          onAuthorizationChanged(auth)
          log.info("[PERMISSIONS] ✅ Granted access for \(source.rawValue, privacy: .public)")
          log.warning("[PERMISSIONS] ⚠️ NOTE: Access granted but reconfigureAccessProvider() NOT called from Settings flow")
          log.warning("[PERMISSIONS] ⚠️ Discovery will NOT pick up this permission until app restart or manual reconfigure")
        }
      } catch FolderAccessError.userCancelled {
        log.info("[PERMISSIONS] User cancelled access for \(source.rawValue, privacy: .public)")
      } catch {
        log.error("[PERMISSIONS] ❌ Failed to grant access for \(source.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription
      }
      isRequesting = false
    }
  }
}
