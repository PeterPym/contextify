import SwiftUI
import ContextifyCore

/// Dedicated window for browsing and managing discovered projects
struct ProjectsWindow: View {
  @Environment(ProjectsViewModel.self) private var viewModel
  @State private var showingExcluded = false
  @State private var selectedProject: DiscoveredProject?

  var body: some View {
    VStack(spacing: 0) {
      // Discovery status bar
      discoveryStatusBar
        .padding()
        .background(Color.secondary.opacity(0.05))

      Divider()

      // Main content
      if viewModel.isDiscovering && viewModel.projects.isEmpty {
        loadingState
      } else if let error = viewModel.errorMessage {
        errorState(message: error)
      } else if viewModel.projects.isEmpty {
        emptyState
      } else {
        projectsList
      }
    }
    .frame(width: 800, height: 600)
    .task {
      // Auto-discover on window open
      await viewModel.discoverProjects()
    }
    .sheet(isPresented: $showingExcluded) {
      ExcludedProjectsView()
        .environment(viewModel)
    }
    .sheet(item: $selectedProject) { project in
      ProjectStatsView(project: project)
    }
  }

  // MARK: - Discovery Status Bar

  private var discoveryStatusBar: some View {
    HStack {
      if viewModel.isDiscovering {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(viewModel.isIngesting ? "Ingesting transcripts..." : "Discovering projects...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } else {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text("Discovered \(viewModel.projects.count) projects")
              .font(.subheadline)
              .fontWeight(.medium)
          }

          if let lastScan = viewModel.lastScanTime {
            Text("Last scan: \(lastScan, style: .relative)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      Spacer()

      if let progress = viewModel.discoveryProgress, viewModel.isIngesting {
        HStack(spacing: 8) {
          if let project = progress.currentProject {
            Text(project)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Text("\(progress.projectsCompleted)/\(progress.projectsTotal)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 8) {
        Button("Show Excluded") {
          showingExcluded = true
        }
        .buttonStyle(.bordered)

        Button("Refresh Projects") {
          viewModel.refresh()
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isDiscovering)
      }
    }
  }

  // MARK: - States

  private var projectsList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        ForEach(viewModel.projects) { project in
          ProjectRowView(
            project: project,
            onSetAsCurrent: {
              viewModel.setAsCurrent(project)
            },
            onRevealInFinder: {
              viewModel.revealInFinder(project)
            },
            onExclude: {
              viewModel.excludeProject(project)
            },
            onShowStats: {
              selectedProject = project
            }
          )
        }
      }
      .padding()
    }
  }

  private var emptyState: some View {
    VStack(spacing: 20) {
      Spacer()

      Image(systemName: "folder.fill.badge.questionmark")
        .font(.system(size: 64))
        .foregroundStyle(.secondary)

      VStack(spacing: 8) {
        Text("No Projects Found")
          .font(.title2.bold())

        Text("We couldn't find any Claude Code or Codex CLI projects on your machine.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Projects are discovered from:")
          .font(.caption.bold())
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 4) {
          Label("~/.claude/projects/*", systemImage: "folder")
            .font(.caption)
            .foregroundStyle(.secondary)

          Label("<project>/.codex/sessions/", systemImage: "folder")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding()
      .background(Color.secondary.opacity(0.05))
      .cornerRadius(8)

      Spacer()
    }
    .padding()
  }

  private var loadingState: some View {
    VStack(spacing: 20) {
      Spacer()

      ProgressView()
        .controlSize(.large)

      VStack(spacing: 8) {
        Text("Discovering Projects...")
          .font(.title2.bold())

        Text("Scanning for Claude Code and Codex projects across your machine...")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      if !viewModel.projects.isEmpty {
        Text("Found \(viewModel.projects.count) projects so far...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding()
  }

  private func errorState(message: String) -> some View {
    VStack(spacing: 20) {
      Spacer()

      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 64))
        .foregroundStyle(.orange)

      VStack(spacing: 8) {
        Text("Discovery Error")
          .font(.title2.bold())

        Text(message)
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Button("Try Again") {
        viewModel.refresh()
      }
      .buttonStyle(.borderedProminent)

      Spacer()
    }
    .padding()
  }
}

#Preview {
  VStack {
    Text("Projects Window Preview")
    Text("(Requires database initialization)")
      .foregroundStyle(.secondary)
  }
  .frame(width: 800, height: 600)
}
