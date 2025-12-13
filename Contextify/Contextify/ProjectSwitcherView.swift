import SwiftUI
import OSLog
import AppKit
import UniformTypeIdentifiers
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "ProjectSwitcherUI")

// MARK: - ScrollView-compatible Button Style (macOS 15 workaround)
// SwiftUI's horizontal ScrollView blocks onTapGesture on macOS 15 (Sequoia).
// Using Button with a custom ButtonStyle works because button styles don't
// interfere with ScrollView gesture handling.
// See: https://danielsaidi.com/blog/2022/11/16/using-complex-gestures-in-a-scroll-view

private struct ScrollViewButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1.0)
  }
}

// MARK: - Tab frame measurement

private struct TabPositionPreferenceKey: PreferenceKey {
  static var defaultValue: [String: CGRect] = [:]
  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

private extension View {
  /// Tracks the view's frame in the "projectsContainer" coordinate space under a given id.
  func trackTabFrame(id: String) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear
          .preference(
            key: TabPositionPreferenceKey.self,
            value: [id: proxy.frame(in: .named("projectsContainer"))]
          )
      }
    )
  }
}

private extension CGRect {
  var midX: CGFloat { (minX + maxX) * 0.5 }
}

// MARK: - Container drop delegate

private struct ProjectTabsDropDelegate: DropDelegate {
  let projects: [ProjectInfo]
  let tabFrames: [String: CGRect]
  @Binding var draggingProject: ProjectInfo?
  @Binding var insertionIndex: Int?
  let activeProjectId: String?
  let onReorder: ([String]) -> Void
  let onActivate: (String) -> Void
  let onDragActivate: () -> Void  // Called before auto-activating via drag-drop

  // Hysteresis and stickiness to avoid boundary jitter
  private let hysteresis: CGFloat = 8.0
  private let stickyDistance: CGFloat = 20.0  // Must move this far to change slots

  // 0...N "slots" determined by tab boundaries (left/right halves)
  // Returns nil if cursor is in a gap between tabs (non-responsive)
  private func proposedInsertionIndex(for locationX: CGFloat) -> Int? {
    // Require complete measurement for stable behavior
    guard tabFrames.count == projects.count else { return nil }
    let frames = projects.compactMap { tabFrames[$0.id] }
    guard frames.count == projects.count, !frames.isEmpty else { return nil }

    // Find which tab the cursor is over based on left/right halves
    for (i, frame) in frames.enumerated() {
      let tabCenter = frame.midX

      // Left half of tab → insert before (index i)
      if locationX >= frame.minX - hysteresis && locationX < tabCenter {
        return i
      }

      // Right half of tab → insert after (index i+1)
      if locationX >= tabCenter && locationX <= frame.maxX + hysteresis {
        return i + 1
      }
    }

    // Before first tab (with hysteresis)
    if locationX < frames.first!.minX - hysteresis {
      return 0
    }

    // After last tab (with hysteresis)
    if locationX > frames.last!.maxX + hysteresis {
      return frames.count
    }

    // Cursor is in gap between tabs → non-responsive
    return nil
  }

  private func isValidMove(from fromIndex: Int, to toIndex: Int) -> Bool {
    // No-op when dropping immediately before self or immediately after self
    toIndex != fromIndex && toIndex != (fromIndex + 1)
  }

  func validateDrop(info: DropInfo) -> Bool { draggingProject != nil }

  func dropEntered(info: DropInfo) {
    // No-op: we drive all updates from dropUpdated for stability.
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard let dragging = draggingProject,
          let fromIndex = projects.firstIndex(where: { $0.id == dragging.id }) else {
      insertionIndex = nil
      return .init(operation: .move)
    }

    let x = info.location.x
    let proposed = proposedInsertionIndex(for: x)

    // If cursor is in gap (nil), keep current slot (non-responsive)
    guard let proposed = proposed else {
      return .init(operation: .move)
    }

    if isValidMove(from: fromIndex, to: proposed) {
      // Apply stickiness: only change if significantly different from current
      if let current = insertionIndex {
        // Calculate distance from current slot position
        let frames = projects.compactMap { tabFrames[$0.id] }
        guard frames.count == projects.count, !frames.isEmpty else {
          insertionIndex = proposed
          return .init(operation: .move)
        }

        let currentSlotX: CGFloat
        if current == 0 {
          currentSlotX = frames.first!.minX
        } else if current >= frames.count {
          currentSlotX = frames.last!.maxX
        } else {
          // Between tabs: use gap center
          currentSlotX = (frames[current - 1].maxX + frames[current].minX) / 2
        }

        // Only change slot if we've moved far enough
        if abs(x - currentSlotX) > stickyDistance {
          insertionIndex = proposed
        }
      } else {
        // First time setting slot - no stickiness needed
        insertionIndex = proposed
      }
    } else {
      // Invalid move - clear insertion index
      if insertionIndex != nil { insertionIndex = nil }
    }
    return .init(operation: .move)
  }

  func dropExited(info: DropInfo) {
    // Clear drag state when cursor exits the drop zone entirely
    // This prevents ghost entries when dragging outside the window
    draggingProject = nil
    insertionIndex = nil
  }

  func performDrop(info: DropInfo) -> Bool {
    guard let dragging = draggingProject,
          let fromIndex = projects.firstIndex(where: { $0.id == dragging.id }) else {
      // Clear immediately on early exit
      draggingProject = nil
      insertionIndex = nil
      return false
    }

    // If insertionIndex is nil (e.g., very fast drop or dropped in gap), compute a final slot once.
    let finalSlot: Int? = {
      if let ii = insertionIndex { return ii }
      return proposedInsertionIndex(for: info.location.x)
    }()

    // If dropped in gap, reject the drop
    guard let finalSlot = finalSlot else {
      // Clear immediately on rejection
      draggingProject = nil
      insertionIndex = nil
      return false
    }

    guard finalSlot != fromIndex && finalSlot != fromIndex + 1 else {
      // Clear immediately on no-op
      draggingProject = nil
      insertionIndex = nil
      return false
    }

    var updated = projects
    updated.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: finalSlot)
    onReorder(updated.map(\.id))

    // Auto-activate reordered project if it's not already active
    if dragging.id != activeProjectId {
      onDragActivate()  // Signal that next activation is from drag-drop
      onActivate(dragging.id)
    }

    // Delay clearing placeholder until after animation completes
    // This prevents the jarring collapse before the real tab appears
    // Matches spring animation (response: 0.3, dampingFraction: 0.7) ≈ 0.3s
    // Token-checked to avoid clearing a subsequent drag that starts within 300ms
    let scheduledId = dragging.id
    let scheduledIndex = insertionIndex
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      if draggingProject?.id == scheduledId && insertionIndex == scheduledIndex {
        draggingProject = nil
        insertionIndex = nil
      }
    }

    return true
  }
}

/// SwiftUI component for project navigation bar
/// Shows project tabs with unread badges and active state
struct ProjectSwitcherView: View {
  @Environment(ProjectSwitcherState.self) private var state

  var body: some View {
    // FULL: With spacer fix, test full feature set
    let _ = log.info("[FULL-WITH-SPACER] Full features with 1pt spacer fix")
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(state.tabProjects) { project in
            ProjectTabView(
              project: project,
              isActive: project.id == state.activeProjectId,
              unreadCount: state.unreadCounts[project.id] ?? 0
            )
            .id(project.id)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
      .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
      .onChange(of: state.activeProjectId) { oldValue, newValue in
        if let newValue {
          withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            proxy.scrollTo(newValue, anchor: .center)
          }
        }
      }
    }
  }
}

/// Simple project tab - minimal label matching inline version
struct ProjectTabViewSimple: View {
  let project: ProjectInfo
  let isActive: Bool
  @Environment(ProjectSwitcherState.self) private var state

  var body: some View {
    Button {
      Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")
        .info("[BUTTON-TAP] CLICKED: \(project.name, privacy: .public)")
      Task { await state.switchToProject(project.id) }
    } label: {
      Text(project.name)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
    .buttonStyle(ScrollViewButtonStyle())
  }
}

/// Individual project tab component - complex label
struct ProjectTabView: View {
  let project: ProjectInfo
  let isActive: Bool
  let unreadCount: Int
  @Environment(ProjectSwitcherState.self) private var state

  private let log = Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")

  var body: some View {
    // Using Button with custom ButtonStyle to work inside ScrollView on macOS 15
    // See: https://danielsaidi.com/blog/2022/11/16/using-complex-gestures-in-a-scroll-view
    Button {
      log.info("[BUTTON-TAP] CLICKED via Button: \(project.name)")
      guard state.activeProjectId != project.id else {
        log.debug("ProjectTab: already active, skipping switch")
        return
      }
      Task {
        await state.switchToProject(project.id)
      }
    } label: {
      HStack(spacing: 4) {
        if project.isOrphaned {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
        }
        Text(project.name)
          .font(.subheadline)
          .fontWeight(isActive ? .semibold : .regular)
          .lineLimit(1)
        if unreadCount > 0 {
          Text(unreadCount > 99 ? "(99+)" : "(\(unreadCount))")
            .font(.caption)
            .foregroundStyle(Color.contextifyBlue)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .frame(minHeight: 44)
      .contentShape(Rectangle())  // Expand hit area to full frame
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isActive ? Color.contextifyBlue.opacity(0.2) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(isActive ? Color.contextifyBlue : Color.secondary.opacity(0.3), lineWidth: 1)
      )
    }
    .buttonStyle(ScrollViewButtonStyle())
  }
}

// MARK: - Gap View

/// Fixed-width spacer for pairwise gap control in drag-and-drop
/// Allows collapsing gaps only around dragged tab without affecting global spacing
private struct Gap: View {
  let width: CGFloat

  var body: some View {
    Color.clear
      .frame(width: width, height: 1)
      .allowsHitTesting(false)
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
    .background(Color.contextifyBlue.opacity(0.1))
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(
          style: StrokeStyle(lineWidth: 2, dash: [6, 4])
        )
        .foregroundStyle(Color.contextifyBlue)
    )
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
