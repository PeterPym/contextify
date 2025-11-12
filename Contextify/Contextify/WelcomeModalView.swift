//
//  WelcomeModalView.swift
//  Contextify
//
//  Created on 2025-11-08.
//  Welcome modal for first-time users with live discovery progress
//

import SwiftUI
import ContextifyCore
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "WelcomeModal")

/// Welcome modal shown on first launch with no project configured
///
/// Shows discovery progress and automatically selects most recent project when complete.
struct WelcomeModalView: View {
    @Environment(ProjectsViewModel.self) private var projectsVM
    @Environment(\.dismiss) private var dismiss

    // Folder access for App Store builds (injected from app level)
    @ObservedObject var folderAccessController: FolderAccessController
    @State private var authorizations: [SourceID: SourceAuthorization] = [:]
    @State private var showPermissionsStep = false

    // Track retry attempts to prevent infinite loops
    @State private var retryCount = 0
    private let maxRetries = 3

    var body: some View {
        VStack(spacing: 24) {
            // Header
            header

            // Status content (changes based on discovery state)
            Group {
                if showPermissionsStep {
                    // Show permissions step until user explicitly dismisses it
                    // (Don't auto-hide when first authorization is granted)
                    permissionsContent
                } else if projectsVM.isDiscovering || projectsVM.isIngesting {
                    discoveringContent
                } else if !projectsVM.projects.isEmpty {
                    completedContent
                } else if let errorMessage = projectsVM.errorMessage {
                    errorContent(message: errorMessage)
                } else {
                    noProjectsContent
                }
            }

            // Action button
            actionButton
        }
        .padding(32)
        .frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            // Check if we need to show permissions on App Store builds
            await loadAuthorizations()
            if needsPermissions {
                showPermissionsStep = true
                log.info("[WMODAL-PERMISSIONS] Showing permissions step (App Store build, no authorizations)")
            }
        }
        .onAppear {
            log.info("[WMODAL-LIFECYCLE] Modal appeared, isDiscovering=\(projectsVM.isDiscovering), hasProgress=\(projectsVM.discoveryProgress != nil)")
        }
        .onDisappear {
            log.info("[WMODAL-LIFECYCLE] Modal disappeared")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)

            Text("Welcome to Contextify")
                .font(.title)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Discovery States

    private var discoveringContent: some View {
        VStack(spacing: 20) {
            if let progress = projectsVM.discoveryProgress {
                let _ = log.info("[WMODAL-BARS] Showing progress bars: \(progress.projectsCompleted, privacy: .public)/\(progress.projectsTotal, privacy: .public) projects")
                // Project-level progress
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(progress.currentProject ?? "Processing...")
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(progress.projectsCompleted)/\(progress.projectsTotal) projects")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Horizontal progress bar (Mail.app style)
                    ProgressView(value: Double(progress.projectsCompleted), total: Double(progress.projectsTotal))
                        .progressViewStyle(.linear)
                        .tint(.blue)

                    // Transcript-level progress (if available)
                    if progress.transcriptsTotal > 0 {
                        HStack {
                            Text(progress.currentTranscript ?? "Loading transcripts...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(progress.transcriptsCompleted)/\(progress.transcriptsTotal) files")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        ProgressView(value: Double(progress.transcriptsCompleted), total: Double(progress.transcriptsTotal))
                            .progressViewStyle(.linear)
                            .tint(.green)
                            .scaleEffect(x: 1.0, y: 0.6)
                    }

                    // Status message
                    Text(progress.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            } else {
                let _ = log.info("[WMODAL-SPINNER] Showing spinner (discoveryProgress is nil)")
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("Scanning for Claude Code and Codex projects...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private var completedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            if let progress = projectsVM.discoveryProgress {
                Text(progress.message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            } else {
                Text("Found \(projectsVM.projects.count) \(projectsVM.projects.count == 1 ? "project" : "projects")")
                    .font(.headline)
            }

            Text("All set! Your conversations are ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Discovery Error")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Show retry count if user has tried before
            if retryCount > 0 {
                Text("Attempt \(retryCount + 1) of \(maxRetries)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                // Only show retry if under max attempts
                if retryCount < maxRetries {
                    Button("Retry") {
                        retryCount += 1
                        Task {
                            await projectsVM.discoverProjects()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Always show skip option as escape hatch
                Button("Skip for Now") {
                    log.info("User skipped discovery after \(retryCount) retries")
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            // Contact support option after max retries
            if retryCount >= maxRetries {
                Button("Contact Support") {
                    SystemInfo.openSupportEmail()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
                .font(.footnote)
            }
        }
        .padding(.vertical, 16)
    }

    private var noProjectsContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("No projects found")
                .font(.headline)

            Text("Contextify monitors Claude Code and Codex CLI conversations. Start a coding session with either tool, and your project will appear here automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Permissions

    private var permissionsContent: some View {
        VStack(spacing: 20) {
            Text("Grant Folder Access")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                Text("Contextify reads your Claude Code or Codex transcripts to build searchable timelines. At least one of these tools must be installed first.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("This takes about 4 clicks. We'll automatically open the correct folders—you just need to click \"Grant Access\" in each dialog.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your transcript data stays private on your machine and is never sent to the internet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Source authorization rows
            VStack(spacing: 12) {
                ForEach(SourceID.allCases, id: \.self) { source in
                    SourceAuthorizationRow(
                        source: source,
                        controller: folderAccessController,
                        authorization: authorizations[source]
                    ) { updatedAuth in
                        authorizations[source] = updatedAuth
                    }
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Helper Computed Properties

    private var needsPermissions: Bool {
        // Check if we're in a sandboxed build
        #if APPSTORE
        let isSandboxed = true
        #else
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        #endif

        // Show permissions step on first launch (no authorizations exist yet)
        // Once shown, showPermissionsStep controls visibility until user dismisses
        if !isSandboxed {
            return false
        }

        // If permissions step is already visible, keep it visible
        if showPermissionsStep {
            return true
        }

        // Otherwise, show it if no authorizations exist
        return !hasAnyAuthorizations
    }

    private var hasAnyAuthorizations: Bool {
        authorizations.values.contains { $0.status == .authorized }
    }

    private func loadAuthorizations() async {
        let allAuths = await folderAccessController.allAuthorizations()
        for auth in allAuths {
            authorizations[auth.id] = auth
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if showPermissionsStep && needsPermissions {
                // Permissions step buttons
                HStack(spacing: 12) {
                    Button("Skip for now") {
                        log.info("User skipped permissions step")
                        showPermissionsStep = false
                    }
                    .buttonStyle(.plain)

                    Button("Continue") {
                        log.info("User granted permissions, continuing to discovery")
                        showPermissionsStep = false
                        Task {
                            await projectsVM.discoverProjects()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasAnyAuthorizations)
                    .keyboardShortcut(.defaultAction)
                }
            } else if !projectsVM.projects.isEmpty && !projectsVM.isDiscovering && !projectsVM.isIngesting {
                Button("Get Started") {
                    log.info("User clicked Get Started - closing welcome modal")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if !projectsVM.isDiscovering && !projectsVM.isIngesting {
                Button("Close") {
                    log.info("User closed welcome modal (no projects)")
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            // No button during discovery/ingestion - modal auto-closes when complete
        }
    }
}

// MARK: - Source Authorization Row

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
                let auths = try await controller.requestAccess(for: [source])
                if let auth = auths.first {
                    onAuthorizationChanged(auth)
                    log.info("[PERMISSIONS] Granted access for \(source.rawValue)")
                }
            } catch FolderAccessError.userCancelled {
                log.info("[PERMISSIONS] User cancelled access for \(source.rawValue)")
            } catch {
                log.error("[PERMISSIONS] Failed to grant access for \(source.rawValue): \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
            isRequesting = false
        }
    }
}

// MARK: - Previews

#Preview("Discovering") {
    WelcomeModalView(folderAccessController: FolderAccessController())
        .environment(mockProjectsVM(state: .discovering, projectCount: 0))
        .frame(width: 500, height: 400)
}

#Preview("Ingesting") {
    WelcomeModalView(folderAccessController: FolderAccessController())
        .environment(mockProjectsVM(state: .ingesting, projectCount: 5, currentProject: "my-awesome-project", currentIndex: 3))
        .frame(width: 500, height: 400)
}

#Preview("Complete") {
    WelcomeModalView(folderAccessController: FolderAccessController())
        .environment(mockProjectsVM(state: .complete, projectCount: 5))
        .frame(width: 500, height: 400)
}

#Preview("No Projects") {
    WelcomeModalView(folderAccessController: FolderAccessController())
        .environment(mockProjectsVM(state: .complete, projectCount: 0))
        .frame(width: 500, height: 400)
}

#Preview("Error") {
    WelcomeModalView(folderAccessController: FolderAccessController())
        .environment(mockProjectsVM(state: .error, projectCount: 0, errorMessage: "Failed to access ~/.claude/projects directory"))
        .frame(width: 500, height: 400)
}

// MARK: - Mock Data for Previews

private enum MockState {
    case discovering
    case ingesting
    case complete
    case error
}

@MainActor
private func mockProjectsVM(
    state: MockState,
    projectCount: Int,
    currentProject: String? = nil,
    currentIndex: Int = 0,
    errorMessage: String? = nil
) -> ProjectsViewModel {
    // Note: This is a simplified mock for previews only
    // Since ProjectDiscoveryService is an actor and cannot be subclassed,
    // we use the real service with real dependencies
    let orchestrator = try! TranscriptOrchestrator(dbManager: .shared)
    let discoveryService = ProjectDiscoveryService(
        db: try! DatabaseManager.shared.pool,
        orchestrator: orchestrator
    )
    let vm = ProjectsViewModel(
        discoveryService: discoveryService,
        hudModel: HUDViewModel.shared
    )

    // Note: Mock state cannot be easily injected due to private(set) properties
    // Previews will show the actual discovery state from the database
    // For testing, consider adding a test-specific initializer or dependency injection

    return vm
}
