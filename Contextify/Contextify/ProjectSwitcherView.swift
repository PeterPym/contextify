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
  @State private var insertionIndex: Int?  // Track where insertion indicator should appear

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Array(state.allProjects.enumerated()), id: \.element.id) { index, project in
            HStack(spacing: 0) {
              // Insertion indicator (appears before project when this is the drop target)
              if insertionIndex == index, let draggingProject {
                InsertionIndicator(draggingProject: draggingProject)
                  .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .scale(scale: 0.5).combined(with: .opacity)
                  ))
              }

              ProjectTabView(
                project: project,
                isActive: project.id == state.activeProjectId,
                unreadCount: state.unreadCounts[project.id] ?? 0,
                isDragging: draggingProject?.id == project.id
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
                projectIndex: index,
                allProjects: state.allProjects,
                draggingProject: $draggingProject,
                insertionIndex: $insertionIndex,
                onReorder: { orderedIds in
                  Task {
                    await state.reorderProjects(orderedIds)
                  }
                }
              ))
            }
          }

          // Insertion indicator at the end (for dropping after last item)
          if let insertionIndex, insertionIndex == state.allProjects.count, let draggingProject {
            InsertionIndicator(draggingProject: draggingProject)
              .transition(.asymmetric(
                insertion: .scale(scale: 0.5).combined(with: .opacity),
                removal: .scale(scale: 0.5).combined(with: .opacity)
              ))
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: insertionIndex)
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
    .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(
          isActive ? Color.accentColor : Color.secondary.opacity(0.3),
          lineWidth: 1
        )
    )
    .opacity(isDragging ? 0.5 : 1.0)  // Reduce opacity while dragging
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

// MARK: - Insertion Indicator

/// Visual indicator showing where dragged item will be inserted
/// Full-sized tab placeholder matching the dimensions of the dragged tab
struct InsertionIndicator: View {
  let draggingProject: ProjectInfo

  var body: some View {
    HStack(spacing: 4) {
      // Match the structure of ProjectTabView but render as ghost placeholder
      if draggingProject.isOrphaned {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.caption2)
          .foregroundStyle(.orange.opacity(0.5))
      }

      Text(draggingProject.name)
        .font(.subheadline)
        .lineLimit(1)
        .foregroundStyle(.secondary.opacity(0.5))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .frame(minHeight: 44)
    .background(Color.accentColor.opacity(0.1))
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(
          style: StrokeStyle(lineWidth: 2, dash: [6, 4])
        )
        .foregroundStyle(Color.accentColor)
    )
  }
}

// MARK: - Drag and Drop

/// Drop delegate for project tab reordering with insertion indicator
struct ProjectDropDelegate: DropDelegate {
  let project: ProjectInfo
  let projectIndex: Int
  let allProjects: [ProjectInfo]
  @Binding var draggingProject: ProjectInfo?
  @Binding var insertionIndex: Int?
  let onReorder: ([String]) -> Void

  func dropEntered(info: DropInfo) {
    guard let draggingProject = draggingProject,
          draggingProject.id != project.id else {
      return
    }

    // Calculate insertion point based on drag position
    guard let fromIndex = allProjects.firstIndex(where: { $0.id == draggingProject.id }) else {
      return
    }

    // Determine if we're inserting before or after this project based on position
    let toIndex: Int
    if fromIndex < projectIndex {
      // Dragging forward: insert before target
      toIndex = projectIndex
    } else {
      // Dragging backward: insert after target (before next)
      toIndex = projectIndex + 1
    }

    // Only show insertion indicator if this would actually change position
    // Invalid positions: immediately before (toIndex == fromIndex) or after (toIndex == fromIndex + 1) itself
    guard toIndex != fromIndex && toIndex != fromIndex + 1 else {
      insertionIndex = nil
      return
    }

    // Show insertion indicator (UI only, no DB write)
    insertionIndex = toIndex
  }

  func dropExited(info: DropInfo) {
    insertionIndex = nil
  }

  func performDrop(info: DropInfo) -> Bool {
    insertionIndex = nil

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

    // Calculate final order based on drop position
    let finalIndex: Int
    if fromIndex < toIndex {
      // Moving forward: insert before target
      finalIndex = toIndex
    } else {
      // Moving backward: insert after target
      finalIndex = toIndex + 1
    }

    updatedProjects.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: finalIndex)

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
