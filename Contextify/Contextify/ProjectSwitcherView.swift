import SwiftUI
import OSLog
import AppKit
import UniformTypeIdentifiers
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "ProjectSwitcherUI")

/// SwiftUI component for project navigation bar
/// Shows project tabs with unread badges and active state
struct ProjectSwitcherView: View {
  @Environment(ProjectSwitcherState.self) private var state
  @State private var draggingProject: ProjectInfo?

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(state.allProjects) { project in
            ProjectTabView(
              project: project,
              isActive: project.id == state.activeProjectId,
              unreadCount: state.unreadCounts[project.id] ?? 0
            )
            .id(project.id)  // Set ID for ScrollViewReader
            .onTapGesture {
              log.info("ProjectTab: user tapped project tab: \(project.name) id=\(project.id)")
              Task {
                await state.switchToProject(project.id)
              }
            }
            .onDrag {
              self.draggingProject = project
              return NSItemProvider(object: project.id as NSString)
            }
            .onDrop(of: [.text], delegate: ProjectDropDelegate(
              project: project,
              allProjects: state.allProjects,
              draggingProject: $draggingProject,
              onReorder: { orderedIds in
                Task {
                  await state.reorderProjects(orderedIds)
                }
              }
            ))
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
      .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
      .onChange(of: state.activeProjectId) { oldValue, newValue in
        // Auto-scroll to active project when it changes (especially for keyboard nav)
        if let newValue {
          withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            proxy.scrollTo(newValue, anchor: .center)
          }
        }
      }
      .task {
        // Verify we're using the correct singleton instance (not a separate @Environment copy)
        let stateId = ObjectIdentifier(state)
        let sharedId = ObjectIdentifier(ProjectSwitcherState.shared)
        if stateId != sharedId {
          let stateIdStr = "\(stateId)"
          let sharedIdStr = "\(sharedId)"
          log.fault("⚠️ ProjectSwitcherView is using wrong ProjectSwitcherState instance! state=\(stateIdStr) != shared=\(sharedIdStr)")
          assertionFailure("ProjectSwitcherView must use ProjectSwitcherState.shared - verify .environment() injection")
        } else {
          log.debug("✅ ProjectSwitcherView verified using correct singleton instance")
        }
      }
    }
  }

}

/// Individual project tab component
struct ProjectTabView: View {
  let project: ProjectInfo
  let isActive: Bool
  let unreadCount: Int
  @Environment(ProjectSwitcherState.self) private var state
  @State private var isOrphaned: Bool = false

  var body: some View {
    HStack(spacing: 4) {
      // Orphaned indicator
      if isOrphaned {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.caption2)
          .foregroundStyle(.orange)
          .help("Project directory is missing")
      }

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
    .frame(minHeight: 44)  // Accessibility: Minimum touch target height
    .contentShape(Rectangle())  // Expand tap area to full frame
    .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
    )
    .contextMenu {
      Button("Hide from Tabs") {
        Task {
          await state.hideProject(project.id)
        }
      }

      if isOrphaned {
        Divider()
        Text("Directory Missing: \(project.rootPath)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .task {
      // Check if project is orphaned
      if let details = await state.getProjectDetails(project.id) {
        isOrphaned = details.isOrphaned
      }
    }
    .accessibilityLabel("Project \(project.name), \(unreadCount) unread")
    .accessibilityHint("Activate to switch to this project")
    .accessibilityAddTraits(.isButton)
  }
}

// MARK: - Drag and Drop

/// Drop delegate for project tab reordering
struct ProjectDropDelegate: DropDelegate {
  let project: ProjectInfo
  let allProjects: [ProjectInfo]
  @Binding var draggingProject: ProjectInfo?
  let onReorder: ([String]) -> Void

  func dropEntered(info: DropInfo) {
    guard let draggingProject = draggingProject,
          draggingProject.id != project.id else {
      return
    }

    // Calculate new order
    var updatedProjects = allProjects
    guard let fromIndex = updatedProjects.firstIndex(where: { $0.id == draggingProject.id }),
          let toIndex = updatedProjects.firstIndex(where: { $0.id == project.id }) else {
      return
    }

    // Move the project
    updatedProjects.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)

    // Trigger reorder callback with new order
    let orderedIds = updatedProjects.map { $0.id }
    onReorder(orderedIds)
  }

  func performDrop(info: DropInfo) -> Bool {
    draggingProject = nil
    return true
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
