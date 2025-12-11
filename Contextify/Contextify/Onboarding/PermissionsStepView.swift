//
//  PermissionsStepView.swift
//  Contextify
//
//  Step 2 of the App Store onboarding wizard.
//  Grants access to transcript folders (~/.claude/projects/ and ~/.codex/).
//

import SwiftUI
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Onboarding")

/// Step 2: Transcript folder permissions.
/// User must grant access to at least one transcript source before completing.
///
/// Keyboard flow:
/// - Tab/Shift+Tab cycles through: Claude → Codex → Continue → Claude...
/// - Enter triggers the focused element (Grant Access or Continue)
/// - Focus ring indicates which element will respond to Enter
struct PermissionsStepView: View {
  @ObservedObject var folderAccessController: FolderAccessController
  @Binding var isConfigured: Bool
  /// Which element has keyboard focus (managed by parent)
  @Binding var permissionsFocus: PermissionsFocus
  /// Authorization status for each source (shared with parent for focus target calculation)
  @Binding var authorizations: [SourceID: AuthorizationStatus]
  /// Set by parent when Enter is pressed - triggers Grant Access for the specified source
  @Binding var triggerGrantAccess: SourceID?

  /// Internal storage for full authorization objects (needed for SourceAuthorizationRow)
  @State private var authorizationObjects: [SourceID: SourceAuthorization] = [:]

  private var hasAnyAuthorizations: Bool {
    authorizations.values.contains { $0 == .authorized }
  }

  /// Returns the first source that is not yet authorized
  private var firstUnauthorizedSource: SourceID? {
    for source in SourceID.allCases {
      if authorizations[source] != .authorized {
        return source
      }
    }
    return nil
  }

  var body: some View {
    VStack(spacing: 24) {
      // Explanation
      VStack(spacing: 12) {
        Text("Grant access to transcript folders")
          .font(.headline)

        Text("Contextify reads your Claude Code and Codex CLI transcripts to build searchable timelines. At least one of these tools must be installed.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        Text("Your transcript data stays private on your machine and is never sent to the internet.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 32)

      // Source authorization rows
      VStack(spacing: 12) {
        ForEach(SourceID.allCases, id: \.self) { source in
          SourceAuthorizationRow(
            source: source,
            controller: folderAccessController,
            authorization: authorizationObjects[source],
            // Focus ring shows when this source matches permissionsFocus and isn't authorized
            isDefaultAction: isFocused(source) && authorizations[source] != .authorized,
            triggerAction: triggerGrantAccess == source
          ) { updatedAuth in
            // Update both internal objects and parent's status binding
            authorizationObjects[source] = updatedAuth
            authorizations[source] = updatedAuth.status
            // Update parent's configured state
            isConfigured = hasAnyAuthorizations
            // Advance focus to next unauthorized source, or Continue if all done
            advanceFocusAfterGrant()
            // Clear the trigger
            triggerGrantAccess = nil
          }
        }
      }
      .padding(.horizontal, 32)

      // Centered hint section - fills remaining vertical space
      if !hasAnyAuthorizations {
        Spacer(minLength: 0)
        Text("Grant access to at least one folder to continue")
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      } else {
        Spacer(minLength: 0)
      }
    }
    .padding(.top, 24)
    .task {
      await loadAuthorizations()
      isConfigured = hasAnyAuthorizations
    }
    .onChange(of: triggerGrantAccess) { _, newValue in
      // Clear trigger after it's been processed (handled by row callback)
      if newValue == nil { return }
    }
  }

  // MARK: - Helpers

  /// Check if a source matches the current permissionsFocus
  private func isFocused(_ source: SourceID) -> Bool {
    switch (source, permissionsFocus) {
    case (.claude, .claude): return true
    case (.codex, .codex): return true
    default: return false
    }
  }

  /// After granting access, advance focus to next unauthorized source or Continue
  private func advanceFocusAfterGrant() {
    if let nextSource = firstUnauthorizedSource {
      // Move to next unauthorized source
      switch nextSource {
      case .claude: permissionsFocus = .claude
      case .codex: permissionsFocus = .codex
      }
    } else {
      // All sources authorized, move to Continue
      permissionsFocus = .continueButton
    }
  }

  // MARK: - Actions

  private func loadAuthorizations() async {
    let allAuths = await folderAccessController.allAuthorizations()
    for auth in allAuths {
      authorizationObjects[auth.id] = auth
      authorizations[auth.id] = auth.status
    }
  }
}

#Preview {
  PermissionsStepView(
    folderAccessController: FolderAccessController(),
    isConfigured: .constant(false),
    permissionsFocus: .constant(.claude),
    authorizations: .constant([:]),
    triggerGrantAccess: .constant(nil)
  )
  .frame(width: 520, height: 400)
}
