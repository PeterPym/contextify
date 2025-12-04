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
struct PermissionsStepView: View {
  @ObservedObject var folderAccessController: FolderAccessController
  @Binding var isConfigured: Bool

  @State private var authorizations: [SourceID: SourceAuthorization] = [:]

  private var hasAnyAuthorizations: Bool {
    authorizations.values.contains { $0.status == .authorized }
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
            authorization: authorizations[source]
          ) { updatedAuth in
            authorizations[source] = updatedAuth
            // Update parent's configured state
            isConfigured = hasAnyAuthorizations
          }
        }
      }
      .padding(.horizontal, 32)

      // Hint when no authorizations yet
      if !hasAnyAuthorizations {
        Text("Grant access to at least one folder to continue")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.top, 8)
      }
    }
    .padding(.top, 24)
    .task {
      await loadAuthorizations()
      isConfigured = hasAnyAuthorizations
    }
  }

  // MARK: - Actions

  private func loadAuthorizations() async {
    let allAuths = await folderAccessController.allAuthorizations()
    for auth in allAuths {
      authorizations[auth.id] = auth
    }
  }
}

#Preview {
  PermissionsStepView(
    folderAccessController: FolderAccessController(),
    isConfigured: .constant(false)
  )
  .frame(width: 520, height: 400)
}
