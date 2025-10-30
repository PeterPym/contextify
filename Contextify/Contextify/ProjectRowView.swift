import SwiftUI
import ContextifyCore

/// Individual project row in the Projects window
struct ProjectRowView: View {
  let project: DiscoveredProject
  let onSetAsCurrent: () -> Void
  let onRevealInFinder: () -> Void
  let onExclude: () -> Void
  let onShowStats: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header: icon + name + current badge + error indicator
      HStack(spacing: 8) {
        Image(systemName: project.isCurrent ? "folder.fill" : "folder")
          .foregroundStyle(project.isCurrent ? .blue : .secondary)
          .imageScale(.large)

        Text(project.name)
          .font(.headline)

        if project.isCurrent {
          Text("CURRENT")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue)
            .cornerRadius(3)
        }

        if project.ingestionError != nil {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .imageScale(.small)
            .help("Ingestion error: \(project.ingestionError ?? "")")
        }

        Spacer()
      }

      // Path
      Text(project.path.path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)

      // Provider badges
      HStack(spacing: 8) {
        ForEach(Array(project.providers.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { provider in
          HStack(spacing: 4) {
            Image(provider.iconImage)
              .renderingMode(.template)
              .foregroundStyle(providerColor(provider))
              .imageScale(.small)
            Text(provider.displayName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.secondary.opacity(0.1))
          .cornerRadius(4)
        }
      }

      // Stats
      HStack(spacing: 12) {
        Label("\(project.transcriptCount) transcripts", systemImage: "doc.text")
          .font(.caption)
          .foregroundStyle(.secondary)

        if let lastActivity = project.lastActivity {
          Text("•")
            .foregroundStyle(.tertiary)
          Text("Last activity: \(lastActivity, style: .relative)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      // Actions
      HStack(spacing: 12) {
        Button(action: onSetAsCurrent) {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle")
              .imageScale(.small)
            Text("Set as Current")
          }
        }
        .buttonStyle(.bordered)
        .disabled(project.isCurrent)

        Button(action: onRevealInFinder) {
          HStack(spacing: 4) {
            Image(systemName: "folder")
              .imageScale(.small)
            Text("Reveal in Finder")
          }
        }
        .buttonStyle(.bordered)

        Spacer()

        Menu {
          Button("View Statistics", action: onShowStats)
          Divider()
          Button("Hide from List", action: onExclude)
        } label: {
          Image(systemName: "ellipsis.circle")
            .imageScale(.large)
        }
        .menuStyle(.borderlessButton)
        .help("More actions")
      }
    }
    .padding()
    .background(Color.secondary.opacity(project.isCurrent ? 0.08 : 0.03))
    .cornerRadius(8)
  }

  private func providerColor(_ provider: DiscoveredProject.Provider) -> Color {
    switch provider {
    case .claudeCode: return .orange
    case .codex: return .white
    }
  }
}

#Preview {
  ProjectRowView(
    project: DiscoveredProject(
      id: "/Users/rob/code/projects/contextify",
      name: "contextify",
      path: URL(fileURLWithPath: "/Users/rob/code/projects/contextify"),
      providers: [.claudeCode, .codex],
      transcriptCount: 24,
      entryCount: 1247,
      lastActivity: Date().addingTimeInterval(-300),
      isCurrent: true
    ),
    onSetAsCurrent: {},
    onRevealInFinder: {},
    onExclude: {},
    onShowStats: {}
  )
  .padding()
}
