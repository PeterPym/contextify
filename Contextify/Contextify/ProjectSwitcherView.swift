import SwiftUI
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "ProjectSwitcherUI")

/// SwiftUI component for project navigation bar
/// Shows project tabs with unread badges and active state
struct ProjectSwitcherView: View {
  @Environment(ProjectSwitcherState.self) private var state

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(state.allProjects) { project in
          ProjectTabView(
            project: project,
            isActive: project.id == state.activeProjectId,
            unreadCount: state.unreadCounts[project.id] ?? 0
          )
          .onTapGesture {
            Task {
              await state.switchToProject(project.id)
            }
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    .task {
      state.start()
    }
    .onDisappear {
      state.stop()
    }
  }
}

/// Individual project tab component
struct ProjectTabView: View {
  let project: ProjectInfo
  let isActive: Bool
  let unreadCount: Int

  var body: some View {
    HStack(spacing: 4) {
      Text(project.name)
        .font(.subheadline)
        .fontWeight(isActive ? .semibold : .regular)
        .lineLimit(1)

      if unreadCount > 0 {
        Text(unreadCount > 99 ? "(99+)" : "(\(unreadCount))")
          .font(.caption)
          .foregroundStyle(.blue)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
    )
    .accessibilityLabel("Project \(project.name), \(unreadCount) unread")
    .accessibilityHint("Activate to switch to this project")
    .accessibilityAddTraits(.isButton)
  }
}

// MARK: - Previews

#Preview("Empty") {
  ProjectSwitcherView()
    .environment(ProjectSwitcherState.shared)
    .frame(width: 600, height: 50)
}

#Preview("Single Project") {
  let state = ProjectSwitcherState.shared
  // TODO: Mock state for preview
  return ProjectSwitcherView()
    .environment(state)
    .frame(width: 600, height: 50)
}

#Preview("Multiple Projects") {
  let state = ProjectSwitcherState.shared
  // TODO: Mock state for preview
  return ProjectSwitcherView()
    .environment(state)
    .frame(width: 600, height: 50)
}
