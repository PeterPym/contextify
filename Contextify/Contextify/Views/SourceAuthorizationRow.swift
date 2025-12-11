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
  /// When true, shows focus ring to indicate this button will respond to Enter
  var isDefaultAction: Bool = false
  /// When true, triggers the Grant Access action (set by parent via Enter key)
  var triggerAction: Bool = false
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
        .accessibilityIdentifier("relink-\(source.rawValue)")
      } else if authorization?.status == .authorized {
        Button {} label: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityIdentifier("authorized-\(source.rawValue)")
      } else {
        grantAccessButton
      }
    }
  }

  /// Grant Access button with conditional styling based on focus state.
  /// Always uses .bordered style (secondary) - only Continue should be .borderedProminent.
  /// Focus is indicated with a subtle blue ring overlay.
  /// Note: No keyboard shortcut - Enter is handled manually by parent to avoid system blue override.
  @ViewBuilder
  private var grantAccessButton: some View {
    Button("Grant Access...") { requestAccess() }
      .buttonStyle(.bordered)
      .disabled(isRequesting)
      .modifier(FocusRingIndicator(isActive: isDefaultAction && !isRequesting))
      .accessibilityIdentifier("grant-access-\(source.rawValue)")
      .accessibilityLabel("Grant Access \(source.displayName)")
      .onChange(of: triggerAction) { _, shouldTrigger in
        if shouldTrigger && !isRequesting {
          requestAccess()
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

          // Trigger access provider reconfiguration and discovery refresh.
          // This notification is handled by ContextifyApp which calls reconfigureAccessProvider()
          // and then triggers discovery to pick up projects from the newly-authorized source.
          log.info("[PERMISSIONS] 📣 Posting permissionAuthorizationDidChange notification")
          NotificationCenter.default.post(name: .permissionAuthorizationDidChange, object: source)
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

// MARK: - Focus Ring Indicator

/// Shows a focus indicator matching the folder card pattern from DatabaseLocationStepView:
/// - Blue border (2pt) + subtle blue background when focused
/// - No additional styling when unfocused (uses standard .bordered appearance)
///
/// This provides visual feedback that Enter will trigger this button,
/// without competing with the primary .borderedProminent Continue button.
private struct FocusRingIndicator: ViewModifier {
  let isActive: Bool

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isActive ? Color.contextifyBlue.opacity(0.08) : Color.clear)
          .padding(-4)  // Extend behind button
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(isActive ? Color.contextifyBlue : Color.clear, lineWidth: 2)
          .padding(-4)  // Extend ring outside button bounds
      )
      .animation(.easeInOut(duration: 0.15), value: isActive)
  }
}
