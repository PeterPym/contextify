---
todo_id: P2-TAB-REORDER-UX
title: Project Tab Bar Reordering UX Improvements
type: investigation
date: 2025-11-25
status: active
description: Fix drag-drop precision issues and add keyboard shortcuts for tab reordering
---

# Project Tab Bar Reordering UX Investigation

## Issues Identified

### Issue 1: Vertical Drag Sensitivity

**Problem:** When dragging a tab, even a small vertical movement causes the tab to "drop" unexpectedly. Users must exercise excessive precision to keep the drag within a narrow horizontal band.

**Root Cause Analysis:**

Looking at `ProjectSwitcherView.swift:151-156`:

```swift
func dropExited(info: DropInfo) {
  // Clear drag state when cursor exits the drop zone entirely
  // This prevents ghost entries when dragging outside the window
  draggingProject = nil
  insertionIndex = nil
}
```

The `dropExited` callback fires when the cursor leaves the drop zone's bounds. The drop zone is likely constrained to the tab bar's vertical height, so vertical cursor drift triggers exit.

**Historical Context:**
The comment mentions "prevents ghost entries when dragging outside the window" - this was likely a fix for tabs disappearing entirely when dragged outside and released. The fix may have been overly aggressive.

**Proposed Solutions:**

**Option A: Expanded Vertical Hit Zone (Recommended)**
- Wrap the drop zone in a larger invisible rectangle
- Allow significant vertical drift (e.g., +/- 100px) before triggering `dropExited`
- Keeps horizontal precision for slot detection

```swift
// Pseudocode
.contentShape(Rectangle())
.frame(height: tabBarHeight + 200)  // Extra vertical tolerance
```

**Option B: Ignore Vertical Movement in dropExited**
- Only cancel drag if cursor exits horizontally (left/right of tab bar)
- Vertical exit just maintains current state

```swift
func dropExited(info: DropInfo) {
  // Only cancel if exited horizontally, not vertically
  let x = info.location.x
  if x < minX - tolerance || x > maxX + tolerance {
    draggingProject = nil
    insertionIndex = nil
  }
  // Vertical exit: keep current state, don't cancel
}
```

**Option C: Delayed Cancel on Exit**
- When `dropExited` fires, start a short timer (200ms)
- If cursor re-enters before timer fires, cancel the timer
- Only actually cancel if timer completes

**Option D: Reimplementation**
- If current approach is fundamentally flawed, consider:
  - SwiftUI's native `.draggable()` / `.dropDestination()` (macOS 13+)
  - Custom gesture-based approach with `DragGesture`
  - AppKit `NSCollectionView` with drag-drop

### Issue 2: Missing Keyboard Shortcuts for Tab Reordering

**Problem:** No keyboard shortcuts exist to move the currently selected tab left or right.

**Requested Shortcut:** `Shift-Command-Option-[` and `Shift-Command-Option-]`

**Behavior Requirements:**
- Move active tab one position left (`[`) or right (`]`)
- **No wrap-around:** If tab is already at the end, do nothing (don't move to opposite end)
- Should work regardless of focus state
- Should trigger same reorder logic as drag-drop

**Implementation Approach:**

1. **Add keyboard shortcuts to ContentView or ProjectSwitcherView:**

```swift
.keyboardShortcut("[", modifiers: [.shift, .command, .option])
.keyboardShortcut("]", modifiers: [.shift, .command, .option])
```

2. **Create reorder action in ProjectSwitcherState:**

```swift
func moveActiveTab(direction: TabMoveDirection) {
  guard let activeId = activeProjectId,
        let currentIndex = projects.firstIndex(where: { $0.id == activeId }) else {
    return
  }

  let newIndex: Int
  switch direction {
  case .left:
    guard currentIndex > 0 else { return }  // No wrap-around
    newIndex = currentIndex - 1
  case .right:
    guard currentIndex < projects.count - 1 else { return }  // No wrap-around
    newIndex = currentIndex + 1
  }

  var updated = projects
  updated.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: newIndex + (direction == .right ? 1 : 0))
  // Persist new order...
}

enum TabMoveDirection {
  case left, right
}
```

3. **Wire up in view:**

```swift
Button("Move Tab Left") {
  state.moveActiveTab(direction: .left)
}
.keyboardShortcut("[", modifiers: [.shift, .command, .option])
.opacity(0)  // Hidden button, keyboard only

Button("Move Tab Right") {
  state.moveActiveTab(direction: .right)
}
.keyboardShortcut("]", modifiers: [.shift, .command, .option])
.opacity(0)
```

## Current Implementation Analysis

**Files:**
- `Contextify/Contextify/ProjectSwitcherView.swift` - Drop delegate, tab rendering
- `Contextify/Contextify/ProjectSwitcherState.swift` - State management, persistence

**Key Components:**
- `ProjectTabsDropDelegate` - Handles all drag-drop logic
- `proposedInsertionIndex(for:)` - Calculates slot based on X position only
- `dropExited(info:)` - Cancels drag on exit (the problematic function)
- `performDrop(info:)` - Executes the reorder

**Existing Safeguards:**
- Hysteresis (8px) for boundary jitter
- Stickiness (20px) to avoid accidental slot changes
- Gap detection (non-responsive in gaps between tabs)

## Best Practices Research

**macOS Tab Bar Patterns:**
- Safari: Allows significant vertical drift, only cancels on horizontal exit
- Chrome: Similar generous vertical tolerance
- Finder: Uses NSCollectionView with built-in drag tolerance

**SwiftUI Drag-Drop:**
- `.dropDestination()` (macOS 13+) has configurable tolerance
- Custom `DragGesture` allows full control over bounds
- `DropDelegate` (current) requires manual tolerance management

## Testing Strategy

**SPM-Compatible Tests:**
- Unit test: `moveActiveTab(direction:)` logic with edge cases
- Unit test: Tab order persistence after keyboard reorder
- Unit test: No-wrap-around behavior at boundaries

**Deferred SwiftUI Tests:**
- UI test: Drag with vertical drift maintains drag state
- UI test: Keyboard shortcuts trigger reorder
- UI test: Visual feedback during keyboard reorder

## Files to Modify

1. `Contextify/Contextify/ProjectSwitcherView.swift`
   - Fix `dropExited` vertical sensitivity
   - Add keyboard shortcut buttons

2. `Contextify/Contextify/ProjectSwitcherState.swift`
   - Add `moveActiveTab(direction:)` method

3. `Tests/ContextifyCoreTests/TabReorderTests.swift` (new)
   - Unit tests for reorder logic

## References

- `Contextify/Contextify/ProjectSwitcherView.swift:39-210` - Current drag-drop implementation
- `Contextify/Contextify/ProjectSwitcherState.swift` - State management
- Apple HIG: https://developer.apple.com/design/human-interface-guidelines/drag-and-drop
