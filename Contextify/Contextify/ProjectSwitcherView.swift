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

// MARK: - Conditional drag modifier (P1: avoid empty drag sessions)
// Only applies .onDrag for solo tabs; grouped tabs get no drag at all,
// preventing any drag cursor/ghost from appearing.

private struct ConditionalDragModifier: ViewModifier {
  let enabled: Bool
  let onDragStart: () -> NSItemProvider

  func body(content: Content) -> some View {
    if enabled {
      content.onDrag(onDragStart)
    } else {
      content
    }
  }
}

private extension View {
  func conditionalDrag(enabled: Bool, onDragStart: @escaping () -> NSItemProvider) -> some View {
    modifier(ConditionalDragModifier(enabled: enabled, onDragStart: onDragStart))
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

  /// Compute gap width between groups.
  /// Uses baseSpacing between solo groups to preserve Phase 2 visuals.
  /// Uses wider GroupSeparator width when either side is a real multi-tab group.
  private func gapWidthBetweenGroups(left: TabGroupInfo?, right: TabGroupInfo) -> CGFloat {
    guard let left = left else { return 0 }
    // If both groups are solo, use baseSpacing (preserves prior layout)
    if left.isSoloTab && right.isSoloTab {
      return baseSpacing
    }
    // Otherwise use wider separator for visual distinction
    return GroupSeparator.width
  }

  var body: some View {
    // DEBUG invariant: tabProjects count must match sum of group project counts
    #if DEBUG
    let _ = {
      let expectedCount = state.tabGroups.reduce(0) { $0 + $1.projects.count }
      assert(state.tabProjects.count == expectedCount,
             "tabProjects count (\(state.tabProjects.count)) != tabGroups sum (\(expectedCount))")
    }()
    #endif

    let _ = log.debug("[TABBAR-BODY] body recomputed, groups=\(state.tabGroups.count, privacy: .public), tabs=\(state.tabProjects.count, privacy: .public)")
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {  // No global spacing - use explicit Gap/GroupSeparator views
          ForEach(Array(state.tabGroups.enumerated()), id: \.element.id) { groupIndex, group in
            let globalFlatIndex = flatIndexForGroup(at: groupIndex)
            let prevGroup = groupIndex > 0 ? state.tabGroups[groupIndex - 1] : nil

            // Inter-group gap (before this group, except first)
            if groupIndex > 0 {
              Gap(width: gapWidthBetweenGroups(left: prevGroup, right: group))
            }

            // Boundary insertion indicator (insert before first tab of this group)
            if let idx = insertionIndex, idx == globalFlatIndex, let dragging = draggingProject {
              if globalFlatIndex > 0 {
                Gap(width: baseSpacing)
              }
              InsertionIndicator(draggingProject: dragging)
                .transition(.asymmetric(
                  insertion: .scale(scale: 0.5).combined(with: .opacity),
                  removal: .scale(scale: 0.5).combined(with: .opacity)
                ))
              Gap(width: baseSpacing)
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
      .onChange(of: state.scrollToProjectId) { _, targetId in
        guard let targetId else { return }
        log.info("[SCROLL-EXECUTE] Scrolling to project: \(targetId, privacy: .public)")

        // P1.2 fix: Capture requestedId to avoid clearing a newer request
        let requestedId = targetId

        // Double-call pattern for reliable scroll (documented quirk in swiftui-patterns.md)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            proxy.scrollTo(requestedId, anchor: .center)
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            proxy.scrollTo(requestedId, anchor: .center)
          }
          // P1.2 fix: Only clear if this is still the active request
          if state.scrollToProjectId == requestedId {
            state.clearScrollRequest()
          }
        }
      }
    }
  }
}

/// Popover for renaming a tab group
/// P1.1 fix: Reset state in onAppear to avoid stale text across opens
struct GroupRenamePopover: View {
  let initialName: String
  let onRename: (String?) -> Void
  let onCancel: () -> Void

  @State private var name: String = ""
  @FocusState private var isNameFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Group Name")
        .font(.headline)

      TextField("Unnamed Group", text: $name)
        .textFieldStyle(.roundedBorder)
        .focused($isNameFocused)
        .onSubmit { commitRename() }

      HStack {
        Button("Cancel", role: .cancel) {
          // Clear focus before dismissing to prevent focus from jumping to search field
          // G6 fix: Use async dispatch to allow focus state to settle before popover dismisses
          isNameFocused = false
          DispatchQueue.main.async {
            onCancel()
          }
        }
          .keyboardShortcut(.escape, modifiers: [])

        Spacer()

        // P2.1 fix: Use .defaultAction instead of .return to avoid double-submit with .onSubmit
        Button("Rename") { commitRename() }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding()
    .frame(width: 280)
    .onAppear {
      // P1.1 fix: Always reset to initialName on appear (not in init)
      name = initialName
      isNameFocused = true
    }
  }

  private func commitRename() {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    // Clear focus before dismissing to prevent focus from jumping to search field
    isNameFocused = false
    onRename(trimmed.isEmpty ? nil : trimmed)
  }
}

/// Popover for selecting a custom group color
struct GroupColorPickerPopover: View {
  let initialColor: Color
  let onApply: (Color) -> Void
  let onCancel: () -> Void

  @State private var selectedColor: Color = .blue

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Custom Color")
        .font(.headline)

      ColorPicker("", selection: $selectedColor, supportsOpacity: false)
        .labelsHidden()
        .frame(height: 80)

      HStack {
        Button("Cancel", role: .cancel) {
          onCancel()
        }
        .keyboardShortcut(.escape, modifiers: [])

        Spacer()

        Button("Apply") {
          onApply(selectedColor)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
    .frame(width: 200)
    .onAppear {
      selectedColor = initialColor
    }
  }
}

// MARK: - Color to Hex Extension

private extension Color {
  /// Convert a SwiftUI Color to a hex string (e.g., "#4A7BA7")
  func toHexString() -> String {
    // Convert to NSColor first to get RGB components
    guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else {
      return "#000000"
    }

    let r = Int(nsColor.redComponent * 255)
    let g = Int(nsColor.greenComponent * 255)
    let b = Int(nsColor.blueComponent * 255)

    return String(format: "#%02X%02X%02X", r, g, b)
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

  @State private var showRenamePopover = false
  @State private var renameText = ""

  // Color picker state
  @State private var showColorPicker = false
  @State private var customColor = Color.blue

  private let log = Logger(subsystem: "dev.contextify", category: "ProjectSwitcher")

  /// The group this tab belongs to (if any)
  private var tabGroup: TabGroupInfo? {
    guard let groupId = project.groupId else { return nil }
    return state.tabGroups.first { $0.id == groupId }
  }

  /// Display name for the group (used in tooltip and context menu header)
  private var groupDisplayName: String? {
    guard let group = tabGroup, !group.isSoloTab else { return nil }
    let trimmed = group.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed?.isEmpty ?? true) ? "Unnamed Group" : trimmed
  }

  /// Background color for the tab.
  /// Uses group color (which respects colorHex override) for grouped tabs, default for solo.
  private var tabBackgroundColor: Color {
    // Use group's computed color (respects colorHex override > gitRoot hash)
    if let group = tabGroup, !group.isSoloTab {
      return group.color.opacity(0.15)
    }
    // Default for solo tabs and non-git projects
    return isActive ? Color.contextifyBlue.opacity(0.2) : Color.clear
  }

  /// Border color for the tab.
  /// Uses group color when active for grouped tabs.
  private var tabBorderColor: Color {
    // Use group's computed color (respects colorHex override)
    if isActive, let group = tabGroup, !group.isSoloTab {
      return group.color
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
    // Simple tooltip showing group name for grouped tabs
    .help(groupDisplayName ?? "")
    .opacity(isDragging ? 0.0 : 1.0)
    .animation(.easeInOut(duration: 0.15), value: isDragging)
    // B1-B7 fix: Only apply drag for solo tabs. Grouped tabs use context menu movement
    // (Move Group Left/Right). This prevents drag cursor/ghost for grouped tabs entirely.
    .conditionalDrag(enabled: project.groupId == nil, onDragStart: onDragStart)
    .contextMenu {
      // Group name header (non-selectable) for grouped tabs
      if let groupName = groupDisplayName {
        Text("Group: \(groupName)")
          .font(.caption)
          .foregroundStyle(.secondary)
        Divider()
      }

      // Movement - context-aware based on grouping
      let projectIndex = state.tabProjects.firstIndex(where: { $0.id == project.id })
      let isGrouped = project.groupId != nil

      if isGrouped, let groupId = project.groupId {
        // Grouped tab: move within group (P0.1 fix: use explicit IDs)
        let group = state.tabGroups.first { $0.id == groupId }
        let localIndex = group?.projects.firstIndex { $0.id == project.id }
        let canMoveLeftInGroup = localIndex.map { $0 > 0 } ?? false
        let canMoveRightInGroup = localIndex.map { $0 < (group?.projects.count ?? 1) - 1 } ?? false

        Button {
          Task { await state.moveTabLeftInGroup(projectId: project.id) }
        } label: {
          HStack {
            Text("Move Left in Group")
            Spacer()
            Text("\u{2318}\u{21E7}\u{2325}[")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
        }
        .disabled(!canMoveLeftInGroup)

        Button {
          Task { await state.moveTabRightInGroup(projectId: project.id) }
        } label: {
          HStack {
            Text("Move Right in Group")
            Spacer()
            Text("\u{2318}\u{21E7}\u{2325}]")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
        }
        .disabled(!canMoveRightInGroup)

        Divider()

        // Group movement (P0.1 fix: use explicit group ID)
        let groupIndex = state.tabGroups.firstIndex { $0.id == groupId }
        let canMoveGroupLeft = groupIndex.map { $0 > 0 } ?? false
        let canMoveGroupRight = groupIndex.map { $0 < state.tabGroups.count - 1 } ?? false

        Button {
          Task { await state.moveGroupLeft(groupId: groupId) }
        } label: {
          HStack {
            Text("Move Group Left")
            Spacer()
            Text("\u{2318}\u{21E7}\u{2303}[")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
        }
        .disabled(!canMoveGroupLeft)

        Button {
          Task { await state.moveGroupRight(groupId: groupId) }
        } label: {
          HStack {
            Text("Move Group Right")
            Spacer()
            Text("\u{2318}\u{21E7}\u{2303}]")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
        }
        .disabled(!canMoveGroupRight)

        Divider()

        Button("Rename Group...") {
          if let group = state.tabGroups.first(where: { $0.id == project.groupId }) {
            renameText = group.name ?? ""
          }
          showRenamePopover = true
        }

        Menu("Change Group Color...") {
          // Automatic option - reset to auto-computed color
          Button {
            Task { await state.setGroupColor(groupId: groupId, hexColor: nil) }
          } label: {
            Label("Automatic", systemImage: "wand.and.stars")
          }

          Divider()

          // Palette colors
          ForEach(WorktreeColorUtility.namedPalette) { namedColor in
            Button {
              Task { await state.setGroupColor(groupId: groupId, hexColor: namedColor.id) }
            } label: {
              HStack {
                Circle()
                  .fill(namedColor.color)
                  .frame(width: 12, height: 12)
                Text(namedColor.name)
              }
            }
          }

          Divider()

          // Custom color option
          Button("Custom...") {
            // Initialize with current group color
            if let group = state.tabGroups.first(where: { $0.id == groupId }) {
              customColor = group.color
            }
            showColorPicker = true
          }
        }
      } else {
        // Solo tab: global movement
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
      }

      Divider()

      // Manual grouping options
      if !isGrouped {
        // Solo tab options
        Button("Create New Group") {
          Task { _ = await state.createGroupWithProject(project.id) }
        }

        let availableGroups = state.getAvailableGroupsForProject(project.id)
        if !availableGroups.isEmpty {
          Menu("Add to Group...") {
            ForEach(availableGroups) { group in
              Button(group.name ?? "Unnamed Group") {
                Task { await state.addToGroup(projectId: project.id, groupId: group.id) }
              }
            }
          }
        }
      } else if state.isInManualGroup(project) {
        // Manual group tab options
        Button("Remove from Group") {
          Task { await state.removeFromGroup(projectId: project.id) }
        }
      }

      Divider()

      // Hide options
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

      // Worktree grouping options (Phase 4) - only for worktree scenarios
      if let gitRoot = project.gitRoot {
        Divider()

        // Show "Ungroup Worktree" only for worktree groups (P0.3 fix)
        // Not shown for manual groups or solo tabs
        if state.isInWorktreeGroup(project) {
          Button("Ungroup Worktree") {
            Task {
              await state.ungroupWorktree(gitRoot)
            }
          }
        }

        // Show "Regroup Worktree" if project was ungrouped
        if !isGrouped && state.isWorktreeUngrouped(gitRoot) {
          Button("Regroup Worktree") {
            Task {
              await state.regroupWorktree(gitRoot)
            }
          }
        }
      }

      // Orphan info
      if project.isOrphaned {
        Divider()
        Text("Directory Missing: \(project.rootPath)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .popover(isPresented: $showRenamePopover) {
      // P3.2 fix: Only render popover if groupId exists (defensive)
      if let groupId = project.groupId {
        GroupRenamePopover(
          initialName: renameText,
          onRename: { newName in
            Task { await state.renameGroup(groupId: groupId, name: newName) }
            showRenamePopover = false
          },
          onCancel: { showRenamePopover = false }
        )
      }
    }
    .popover(isPresented: $showColorPicker) {
      if let groupId = project.groupId {
        GroupColorPickerPopover(
          initialColor: customColor,
          onApply: { color in
            let hexColor = color.toHexString()
            Task { await state.setGroupColor(groupId: groupId, hexColor: hexColor) }
            showColorPicker = false
          },
          onCancel: { showColorPicker = false }
        )
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

        // Intra-group insertion indicator (between tabs within this group)
        // Note: Boundary indicators (localIndex == 0) are handled at the group level
        if localIndex > 0, insertionIndex == flatIndex, let dragging = draggingProject {
          Gap(width: baseSpacing)
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
