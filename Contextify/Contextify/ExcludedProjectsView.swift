import SwiftUI
import ContextifyCore

/// View for managing excluded projects
struct ExcludedProjectsView: View {
  @Environment(ProjectsViewModel.self) private var viewModel
  @Environment(\.dismiss) private var dismiss

  @State private var excludedPaths: Set<String> = []
  @State private var isLoading = true

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Excluded Projects")
          .font(.title2.bold())

        Spacer()

        Button("Done") {
          dismiss()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding()

      Divider()

      // Content
      if isLoading {
        VStack {
          Spacer()
          ProgressView()
          Text("Loading excluded projects...")
            .foregroundStyle(.secondary)
          Spacer()
        }
      } else if excludedPaths.isEmpty {
        VStack(spacing: 16) {
          Spacer()

          Image(systemName: "checkmark.circle")
            .font(.system(size: 64))
            .foregroundStyle(.green)

          VStack(spacing: 8) {
            Text("No Excluded Projects")
              .font(.title3.bold())

            Text("Projects you hide will appear here")
              .font(.body)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(excludedPaths).sorted(), id: \.self) { path in
              ExcludedProjectRow(
                path: path,
                onRestore: {
                  restoreProject(path)
                }
              )
            }
          }
          .padding()
        }
      }
    }
    .frame(width: 600, height: 500)
    .task {
      await loadExcludedProjects()
    }
  }

  private func loadExcludedProjects() async {
    excludedPaths = await viewModel.getExcludedProjects()
    isLoading = false
  }

  private func restoreProject(_ path: String) {
    Task {
      await viewModel.discoveryService.includeProject(path)
      excludedPaths.remove(path)

      // Refresh main projects list
      viewModel.refresh()
    }
  }
}

struct ExcludedProjectRow: View {
  let path: String
  let onRestore: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "folder.fill.badge.minus")
        .foregroundStyle(.secondary)
        .imageScale(.large)

      VStack(alignment: .leading, spacing: 4) {
        Text(URL(fileURLWithPath: path).lastPathComponent)
          .font(.headline)

        Text(path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      Button("Restore") {
        onRestore()
      }
      .buttonStyle(.bordered)
    }
    .padding()
    .background(Color.secondary.opacity(0.05))
    .cornerRadius(8)
  }
}

#Preview {
  VStack {
    Text("Excluded Projects Preview")
  }
  .frame(width: 600, height: 500)
}
