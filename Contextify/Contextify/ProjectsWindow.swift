import SwiftUI
import ContextifyCore

/// Dedicated window for browsing and managing discovered projects
struct ProjectsWindow: View {
  @Environment(ProjectsViewModel.self) private var viewModel
  @State private var selectedProject: DiscoveredProject?
  @State private var searchText = ""  // P2-PROJECTS-SEARCH: Search functionality

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
    .frame(minWidth: 800, idealWidth: 800, maxWidth: .infinity, minHeight: 600, idealHeight: 600, maxHeight: .infinity)
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
          Text("\(viewModel.projects.count) projects")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          if let lastScan = viewModel.lastScanTime {
            Text("Updated \(lastScan, format: .dateTime.hour().minute().second())")
              .font(.caption2)
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

      Button("Refresh Projects") {
        viewModel.refresh()
      }
      .buttonStyle(.bordered)
      .disabled(viewModel.isDiscovering)
    }
  }

  // MARK: - States

  private var projectsList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        ForEach(filteredProjects) { project in
          ProjectRowView(
            project: project,
            onSetAsCurrent: {
              viewModel.setAsCurrent(project)
            },
            onRevealInFinder: {
              viewModel.revealInFinder(project)
            },
            onShowStats: {
              selectedProject = project
            }
          )
        }
      }
      .padding()
    }
    .searchable(text: $searchText, prompt: "Search")
  }

  private var emptyState: some View {
    VStack(spacing: 20) {
      Image(systemName: "folder.fill.badge.questionmark")
        .font(.system(size: 64))
        .foregroundStyle(.secondary)

      VStack(spacing: 8) {
        Text("No Projects Found")
          .font(.title2.bold())

        Text("No projects found.")
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
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var loadingState: some View {
    VStack(spacing: 20) {
      ProgressView()
        .controlSize(.large)

      VStack(spacing: 8) {
        Text("Discovering Projects...")
          .font(.title2.bold())

        Text("Scanning for projects...")
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
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func errorState(message: String) -> some View {
    VStack(spacing: 20) {
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
    .frame(maxHeight: .infinity, alignment: .top)
  }

  // MARK: - Helpers

  /// Filtered projects based on search text (P2-PROJECTS-SEARCH)
  private var filteredProjects: [DiscoveredProject] {
    if searchText.isEmpty {
      return viewModel.projects
    }
    return viewModel.projects.filter { project in
      project.name.localizedCaseInsensitiveContains(searchText) ||
      project.path.path.localizedCaseInsensitiveContains(searchText)
    }
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
