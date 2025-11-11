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

    // Track retry attempts to prevent infinite loops
    @State private var retryCount = 0
    private let maxRetries = 3

    var body: some View {
        VStack(spacing: 24) {
            // Header
            header

            // Status content (changes based on discovery state)
            Group {
                if projectsVM.isDiscovering || projectsVM.isIngesting {
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

            Text("Discovering your projects...")
                .font(.body)
                .foregroundStyle(.secondary)
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

            Text("You're all set! Your conversations are ready to explore.")
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

            Text("Contextify looks for Claude Code and Codex CLI sessions in your home directory. You can add a project manually using File → Open Project.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if projectsVM.isDiscovering || projectsVM.isIngesting {
                Button("Continue in Background") {
                    log.info("User dismissed welcome modal during discovery/ingestion")
                    dismiss()
                }
                .buttonStyle(.bordered)
            } else if !projectsVM.projects.isEmpty {
                Button("Get Started") {
                    log.info("User clicked Get Started - closing welcome modal")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Dismiss") {
                    log.info("User dismissed welcome modal (no projects)")
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Previews

#Preview("Discovering") {
    WelcomeModalView()
        .environment(mockProjectsVM(state: .discovering, projectCount: 0))
        .frame(width: 500, height: 400)
}

#Preview("Ingesting") {
    WelcomeModalView()
        .environment(mockProjectsVM(state: .ingesting, projectCount: 5, currentProject: "my-awesome-project", currentIndex: 3))
        .frame(width: 500, height: 400)
}

#Preview("Complete") {
    WelcomeModalView()
        .environment(mockProjectsVM(state: .complete, projectCount: 5))
        .frame(width: 500, height: 400)
}

#Preview("No Projects") {
    WelcomeModalView()
        .environment(mockProjectsVM(state: .complete, projectCount: 0))
        .frame(width: 500, height: 400)
}

#Preview("Error") {
    WelcomeModalView()
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
