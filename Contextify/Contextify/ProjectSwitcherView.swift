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
  @State private var draggingProject: ProjectInfo?
  @State private var insertionIndex: Int?
  @State private var tabPositions: [String: CGRect] = [:]
  @State private var skipNextAutoScroll = false

  private let baseSpacing: CGFloat = 8

  /// Compute starting flat index for a group
  private func flatIndexForGroup(at groupIndex: Int) -> Int {
    var index = 0
    for i in 0..<groupIndex {
      index += state.tabGroups[i].projects.count
    }
    return index
  }

  var body: some View {
    let _ = log.debug("[TABBAR-BODY] body recomputed, groups=\(state.tabGroups.count, privacy: .public), tabs=\(state.tabProjects.count, privacy: .public)")
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {  // No global spacing - use explicit Gap/GroupSeparator views
          ForEach(Array(state.tabGroups.enumerated()), id: \.element.id) { groupIndex, group in
            let globalFlatIndex = flatIndexForGroup(at: groupIndex)

            // Group separator before this group (except first)
            if groupIndex > 0 {
              GroupSeparator()
            }

            TabGroupView(
              group: group,
              isAnyTabActive: group.projects.contains { $0.id == state.activeProjectId },
              activeProjectId: state.activeProjectId,
              unreadIndicators: state.unreadIndicators,
              draggingProject: draggingProject,
              insertionIndex: insertionIndex,
              globalFlatIndex: globalFlatIndex,
              baseSpacing: baseSpacing,
              onDragStart: { project in
                self.draggingProject = project
                return NSItemProvider(object: project.id as NSString)
              }
            )
          }

          // Insertion indicator after last tab (at end of last group)
          if let insertionIndex,
             insertionIndex == state.tabProjects.count,
             let draggingProject {
            Gap(width: baseSpacing)
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
        .coordinateSpace(name: "projectsContainer")
        .onPreferenceChange(TabPositionPreferenceKey.self) { v in
          tabPositions = v
        }
        // Container-level drop delegate (wide, stable)
        // Uses flat tabProjects for drop index calculation
        .onDrop(
          of: [.text],
          delegate: ProjectTabsDropDelegate(
            projects: state.tabProjects,
            tabFrames: tabPositions,
            draggingProject: $draggingProject,
            insertionIndex: $insertionIndex,
            activeProjectId: state.activeProjectId,
            onReorder: { orderedIds in
              Task { await state.reorderProjects(orderedIds) }
            },
            onActivate: { projectId in
              Task { await state.switchToProject(projectId) }
            },
            onDragActivate: {
              skipNextAutoScroll = true
            }
          )
        )
      }
      .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
      .onChange(of: state.activeProjectId) { oldValue, newValue in
        log.info("[UIOPT-TABS-UPDATE] Active project changed from \(oldValue ?? "nil", privacy: .public) to \(newValue ?? "nil", privacy: .public)")

        // Auto-scroll to active project when it changes (especially for keyboard nav)
        // Skip if activation was triggered by drag-drop (user can already see the tab)
        if let newValue, !skipNextAutoScroll {
          withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            proxy.scrollTo(newValue, anchor: .center)
          }
        }

        // Reset flag for next activation
        if skipNextAutoScroll {
          skipNextAutoScroll = false
        }
      }
    }
  }
}

/// Individual project tab component
/// Uses Button+ButtonStyle for clicks (macOS 15 workaround) with onDrag for reordering.
struct ProjectTabView: View {
  let project: ProjectInfo
  let isActive: Bool
  let indicator: UnreadIndicatorResult?
  let isDragging: Bool
  var onDragStart: () -> NSItemProvider
  @Environment(ProjectSwitcherState.self) private var state

  private let log = Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")

  /// Background color for the tab.
  /// Uses worktree color tint only for grouped tabs (v33), solo tabs use default.
  private var tabBackgroundColor: Color {
    // Only use worktree colors for grouped tabs
    if project.groupId != nil, let gitRoot = project.gitRoot {
      return WorktreeColorUtility.tintColor(for: gitRoot)
    }
    // Default for solo tabs and non-git projects
    return isActive ? Color.contextifyBlue.opacity(0.2) : Color.clear
  }

  /// Border color for the tab.
  /// Uses worktree color when active only for grouped tabs (v33).
  private var tabBorderColor: Color {
    // Only use worktree colors for grouped tabs
    if isActive, project.groupId != nil, let gitRoot = project.gitRoot {
      return WorktreeColorUtility.borderColor(for: gitRoot)
    }
    return isActive ? Color.contextifyBlue : Color.secondary.opacity(0.3)
  }

  private var accessibilityUnreadLabel: String {
    guard let indicator else { return "no unread" }
    if indicator.accurateUnread > 0 {
      return "\(indicator.accurateUnread) unread"
    }
    if let approx = indicator.approxDelta, approx > 0 {
      return "~\(approx) unread"
    }
    if indicator.hasActivitySignal {
      return "new activity"
    }
    return "no unread"
  }

  var body: some View {
    // Using Button with custom ButtonStyle to work inside ScrollView on macOS 15
    // onDrag is attached to the Button for reordering support
    Button {
      log.info("[BUTTON-TAP] CLICKED: \(project.name, privacy: .public)")
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
            .help("Project directory is missing")
        }

        Text(project.name)
          .font(.subheadline)
          .fontWeight(isActive ? .semibold : .regular)
          .lineLimit(1)

        if let indicator {
          if indicator.accurateUnread > 0 {
            Text(indicator.accurateUnread > 99 ? "(99+)" : "(\(indicator.accurateUnread))")
              .font(.caption)
              .foregroundStyle(Color.contextifyBlue)
          } else if let approx = indicator.approxDelta, approx > 0 {
            Text("~\(approx)")
              .font(.caption)
              .foregroundStyle(Color.contextifyBlue)
          } else if indicator.hasActivitySignal {
            Circle()
              .fill(Color.contextifyBlue)
              .frame(width: 6, height: 6)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .frame(minHeight: 44)
      .contentShape(Rectangle())  // Expand hit area to full frame
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(tabBackgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(tabBorderColor, lineWidth: 1)
      )
    }
    .buttonStyle(ScrollViewButtonStyle())
    .opacity(isDragging ? 0.0 : 1.0)
    .animation(.easeInOut(duration: 0.15), value: isDragging)
    .onDrag(onDragStart)
    .contextMenu {
      // Move Left/Right for reordering (works on all macOS versions)
      let projectIndex = state.tabProjects.firstIndex(where: { $0.id == project.id })
      let canMoveLeft = projectIndex.map { $0 > 0 } ?? false
      let canMoveRight = projectIndex.map { $0 < state.tabProjects.count - 1 } ?? false

      Button("Move Left") {
        guard let idx = projectIndex, idx > 0 else { return }
        var newOrder = state.tabProjects.map(\.id)
        newOrder.swapAt(idx, idx - 1)
        Task { await state.reorderProjects(newOrder) }
      }
      .disabled(!canMoveLeft)

      Button("Move Right") {
        guard let idx = projectIndex, idx < state.tabProjects.count - 1 else { return }
        var newOrder = state.tabProjects.map(\.id)
        newOrder.swapAt(idx, idx + 1)
        Task { await state.reorderProjects(newOrder) }
      }
      .disabled(!canMoveRight)

      Divider()

      Button("Hide this Project") {
        Task {
          await state.hideProject(project.id)
        }
      }

      if state.hasHiddenProjects {
        Button("Restore Hidden Projects") {
          Task {
            await state.restoreAllHiddenProjects()
          }
        }
      }

      if project.isOrphaned {
        Divider()
        Text("Directory Missing: \(project.rootPath)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityLabel("Project \(project.name), \(accessibilityUnreadLabel)")
    .accessibilityHint("Activate to switch to this project")
    .accessibilityAddTraits(.isButton)
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

// MARK: - Group Separator

/// Visual separator between tab groups
/// Provides wider spacing than intra-group gaps for visual distinction
private struct GroupSeparator: View {
  static let width: CGFloat = 12

  var body: some View {
    Color.clear
      .frame(width: Self.width, height: 1)
      .allowsHitTesting(false)
  }
}

// MARK: - Tab Group View

/// Container for a group of related project tabs
/// - Solo tabs (synthetic groups) render without background
/// - Multi-tab groups get subtle background container
private struct TabGroupView: View {
  let group: TabGroupInfo
  let isAnyTabActive: Bool
  let activeProjectId: String?
  let unreadIndicators: [String: UnreadIndicatorResult]
  let draggingProject: ProjectInfo?
  let insertionIndex: Int?
  let globalFlatIndex: Int  // Starting index in flat tab list
  let baseSpacing: CGFloat
  let onDragStart: (ProjectInfo) -> NSItemProvider

  private let intraGroupSpacing: CGFloat = 4  // Tighter spacing within groups

  /// Background color for multi-tab groups (subtle tint from git root)
  private var groupBackgroundColor: Color {
    // Only show background for actual multi-tab groups (not solo)
    guard !group.isSoloTab, group.projects.count > 1 else {
      return .clear
    }
    // Use group color at low opacity for subtle grouping
    return group.color.opacity(0.08)
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(group.projects.enumerated()), id: \.element.id) { localIndex, project in
        let flatIndex = globalFlatIndex + localIndex

        // Insertion indicator before this tab (if applicable)
        if insertionIndex == flatIndex, let dragging = draggingProject {
          if localIndex > 0 || globalFlatIndex > 0 {
            Gap(width: baseSpacing)
          }
          InsertionIndicator(draggingProject: dragging)
            .transition(.asymmetric(
              insertion: .scale(scale: 0.5).combined(with: .opacity),
              removal: .scale(scale: 0.5).combined(with: .opacity)
            ))
          Gap(width: baseSpacing)
        }

        ProjectTabView(
          project: project,
          isActive: project.id == activeProjectId,
          indicator: unreadIndicators[project.id],
          isDragging: draggingProject?.id == project.id,
          onDragStart: { onDragStart(project) }
        )
        .id(project.id)
        .trackTabFrame(id: project.id)
        .frame(
          width: draggingProject?.id == project.id ? 0 : nil,
          height: draggingProject?.id == project.id ? 0 : nil
        )
        .clipped()

        // Intra-group gap (between tabs within same group)
        if localIndex < group.projects.count - 1 {
          let nextFlatIndex = flatIndex + 1
          let skipGap = insertionIndex == nextFlatIndex
          if !skipGap {
            Gap(width: draggingProject?.id == group.projects[localIndex + 1].id ? 0 : intraGroupSpacing)
          }
        }
      }
    }
    .padding(.horizontal, group.isSoloTab ? 0 : 4)
    .padding(.vertical, group.isSoloTab ? 0 : 2)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(groupBackgroundColor)
    )
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
  return ProjectSwitcherView()
    .environment(state)
    .frame(width: 600, height: 50)
}

#Preview("Multiple Projects") {
  let state = ProjectSwitcherState.shared
  return ProjectSwitcherView()
    .environment(state)
    .frame(width: 600, height: 50)
}
