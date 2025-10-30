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
  @State private var dropTargetId: String?

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(state.allProjects) { project in
            ProjectTabView(
              project: project,
              isActive: project.id == state.activeProjectId,
              unreadCount: state.unreadCounts[project.id] ?? 0,
              isDragging: draggingProject?.id == project.id,
              isDropTarget: dropTargetId == project.id
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
              dropTargetId: $dropTargetId,
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
  let isDragging: Bool
  let isDropTarget: Bool
  @Environment(ProjectSwitcherState.self) private var state

  var body: some View {
    HStack(spacing: 4) {
      // Orphaned indicator
      if project.isOrphaned {
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
    .background(
      Group {
        if isDropTarget {
          Color.accentColor.opacity(0.3)  // Highlight drop target
        } else if isActive {
          Color.accentColor.opacity(0.2)
        } else {
          Color.clear
        }
      }
    )
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(
          isDropTarget ? Color.accentColor : (isActive ? Color.accentColor : Color.secondary.opacity(0.3)),
          lineWidth: isDropTarget ? 2 : 1
        )
    )
    .opacity(isDragging ? 0.5 : 1.0)  // Reduce opacity while dragging
    .animation(.easeInOut(duration: 0.2), value: isDropTarget)
    .animation(.easeInOut(duration: 0.15), value: isDragging)
    .contextMenu {
      Button("Hide from Tabs") {
        Task {
          await state.hideProject(project.id)
        }
      }

      if project.isOrphaned {
        Divider()
        Text("Directory Missing: \(project.rootPath)")
          .font(.caption)
          .foregroundStyle(.secondary)
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
  @Binding var dropTargetId: String?
  let onReorder: ([String]) -> Void

  func dropEntered(info: DropInfo) {
    guard let draggingProject = draggingProject,
          draggingProject.id != project.id else {
      return
    }

    // Show drop target indicator (UI only, no DB write)
    dropTargetId = project.id
  }

  func dropExited(info: DropInfo) {
    if dropTargetId == project.id {
      dropTargetId = nil
    }
  }

  func performDrop(info: DropInfo) -> Bool {
    dropTargetId = nil

    // Persist final order exactly once on drop
    guard let draggingProject = draggingProject else {
      self.draggingProject = nil
      return false
    }

    var updatedProjects = allProjects
    guard let fromIndex = updatedProjects.firstIndex(where: { $0.id == draggingProject.id }),
          let toIndex = updatedProjects.firstIndex(where: { $0.id == project.id }) else {
      self.draggingProject = nil
      return false
    }

    // Calculate final order
    updatedProjects.move(fromOffsets: IndexSet(integer: fromIndex),
                        toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)

    // Persist atomically
    let orderedIds = updatedProjects.map { $0.id }
    onReorder(orderedIds)

    self.draggingProject = nil
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
