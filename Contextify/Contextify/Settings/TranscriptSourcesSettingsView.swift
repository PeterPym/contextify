import SwiftUI
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "Settings")

/// Settings view for managing transcript source folder authorizations.
/// Accessible via Settings → Transcript Sources... menu item.
struct TranscriptSourcesSettingsView: View {
    @ObservedObject var folderAccessController: FolderAccessController
    @State private var authorizations: [SourceID: SourceAuthorization] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Transcript Sources")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Manage folder access for Claude Code and Codex transcripts.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 500)
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
