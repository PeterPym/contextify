import SwiftUI
import OSLog
import AppKit

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
    // Keyboard shortcuts: Cmd+Shift+[ and Cmd+Shift+]
    .background(KeyboardShortcutHandler(
      onPrevious: cycleToPreviousProject,
      onNext: cycleToNextProject
    ))
  }

  private func cycleToPreviousProject() {
    guard !state.allProjects.isEmpty else { return }

    if let currentId = state.activeProjectId,
       let currentIndex = state.allProjects.firstIndex(where: { $0.id == currentId }) {
      // Move to previous, wrapping around to end
      let previousIndex = currentIndex > 0 ? currentIndex - 1 : state.allProjects.count - 1
      let previousProject = state.allProjects[previousIndex]

      Task {
        await state.switchToProject(previousProject.id)
      }
    } else if let first = state.allProjects.first {
      // No active project, select first
      Task {
        await state.switchToProject(first.id)
      }
    }
  }

  private func cycleToNextProject() {
    guard !state.allProjects.isEmpty else { return }

    if let currentId = state.activeProjectId,
       let currentIndex = state.allProjects.firstIndex(where: { $0.id == currentId }) {
      // Move to next, wrapping around to start
      let nextIndex = currentIndex < state.allProjects.count - 1 ? currentIndex + 1 : 0
      let nextProject = state.allProjects[nextIndex]

      Task {
        await state.switchToProject(nextProject.id)
      }
    } else if let first = state.allProjects.first {
      // No active project, select first
      Task {
        await state.switchToProject(first.id)
      }
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

// MARK: - Keyboard Shortcut Handler

/// Invisible view that handles keyboard shortcuts for project cycling
private struct KeyboardShortcutHandler: NSViewRepresentable {
  let onPrevious: () -> Void
  let onNext: () -> Void

  func makeNSView(context: Context) -> KeyboardShortcutView {
    let view = KeyboardShortcutView()
    view.onPrevious = onPrevious
    view.onNext = onNext
    return view
  }

  func updateNSView(_ nsView: KeyboardShortcutView, context: Context) {
    nsView.onPrevious = onPrevious
    nsView.onNext = onNext
  }

  class KeyboardShortcutView: NSView {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
      // Cmd+Shift+[ = 0x21 ([)
      // Cmd+Shift+] = 0x1E (])
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifiers == [.command, .shift] {
        if event.charactersIgnoringModifiers == "[" {
          onPrevious?()
          return
        } else if event.charactersIgnoringModifiers == "]" {
          onNext?()
          return
        }
      }

      super.keyDown(with: event)
    }
  }
}
