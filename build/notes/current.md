# SYSTEM PROMPT FOR AI REVIEW

You are a senior iOS/macOS engineer reviewing a production-ready implementation plan for converting a modal sheet presentation to an independent window in a Swift 6 macOS application using SwiftUI.

## Your Task

Carefully review the implementation plan below for:

1. **Swift 6 Strict Concurrency Compliance**
   - Verify all `@Observable`, `@MainActor`, and `Sendable` annotations are correct
   - Check for potential data races in window-to-window communication
   - Ensure environment object passing is thread-safe

2. **SwiftUI Scene API Correctness**
   - Validate Window scene configuration
   - Check `@Environment(\.openWindow)` and `@Environment(\.dismissWindow)` usage
   - Verify window ID strings are consistent

3. **State Management Architecture**
   - Assess shared state strategy between main and auxiliary windows
   - Validate use of `@AppStorage`, `@StateObject`, or observable objects
   - Check for potential state synchronization issues

4. **macOS HIG Compliance**
   - Verify window behaves as non-modal auxiliary window
   - Check toolbar placement and controls
   - Validate keyboard shortcuts don't conflict with system

5. **Code Organization & Modularity**
   - Assess file structure and separation of concerns
   - Check for code reuse vs. duplication
   - Validate naming conventions

6. **Testing Considerations**
   - Identify potential edge cases
   - Note any areas needing unit/integration tests
   - Flag any hard-to-test code patterns

7. **Backward Compatibility & Migration**
   - Check if existing functionality is preserved
   - Validate that no features are lost in conversion
   - Ensure graceful handling of window lifecycle

8. **Performance & Resource Management**
   - Check for memory leaks in window management
   - Validate proper cleanup on window dismissal
   - Assess impact of concurrent window operation

## Review Output Format

Provide feedback in this structure:
- **Critical Issues** (blocks production): Problems that must be fixed
- **Warnings** (should fix): Issues that should be addressed but aren't blocking
- **Suggestions** (nice to have): Improvements that would enhance the implementation
- **Approvals**: Aspects that are well-designed and production-ready

Be thorough but concise. Flag specific file paths and line ranges where issues exist.

---

# Implementation Plan: Convert Transcript Inventory from Sheet to Window

**Date:** 2025-10-09
**Feature:** Transcript Inventory Window Conversion
**Goal:** Convert modal sheet presentation to independent, concurrent auxiliary window
**Branch:** `feature/transcript-inventory`

---

## Executive Summary

Convert the Transcript Inventory from a blocking modal sheet (`.sheet(isPresented:)`) to an independent macOS `Window` scene that allows concurrent interaction with the main timeline window. This improves UX by allowing users to browse transcripts while monitoring live timeline updates, treating the inventory as reference material rather than a blocking task.

**Key Benefits:**
- ✅ Concurrent interaction with main window
- ✅ Persistent window position/size across sessions
- ✅ Native macOS window management (minimize, maximize, Window menu)
- ✅ Keyboard shortcut support (⌘⌥T)
- ✅ Better UX for reference material

---

## Related Files

### Existing Files (To Modify)

#### `Contextify/Contextify/ContextifyApp.swift`
**Current Role:** App entry point with single `WindowGroup` scene for main window.
**Changes Needed:** Add new `Window` scene for transcript inventory, configure keyboard shortcut and default sizing.
**Relationship:** Defines all app scenes; must declare the new auxiliary window scene.

#### `Contextify/Contextify/ConversationTimelineView.swift`
**Current Role:** Presents TranscriptInventoryView as a modal sheet via `.sheet(isPresented:)`.
**Changes Needed:** Replace sheet presentation with window opening via `@Environment(\.openWindow)`, add menu item to open window.
**Relationship:** Currently owns the sheet presentation logic; will delegate to window management.

#### `Contextify/Contextify/TranscriptInventoryView.swift`
**Current Role:** The view containing sidebar + detail layout for transcript browsing.
**Changes Needed:** Remove "Done" button, remove `onDismiss` callback, adjust toolbar for window context, remove sheet-specific sizing.
**Relationship:** Core UI that will be embedded in new window scene; needs to adapt from modal to window context.

#### `Contextify/Contextify/ConversationMonitor.swift`
**Current Role:** `@Observable` `@MainActor` singleton providing transcript session data and active session tracking.
**Changes Needed:** Potentially expose additional state or callbacks for window coordination; ensure thread-safe access from multiple windows.
**Relationship:** Shared data source between main and auxiliary windows; must support concurrent access.

#### `Contextify/Contextify/ConversationSources.swift`
**Current Role:** Defines `TranscriptSession` model and provider protocols for discovering transcripts.
**Changes Needed:** No changes expected, already `Sendable`.
**Relationship:** Data model layer; window changes don't affect transcript discovery logic.

#### `Contextify/Contextify/ContentView.swift`
**Current Role:** Main window content view.
**Changes Needed:** Minimal or none; may need to pass window environment for opening transcript window.
**Relationship:** Main window UI; indirectly affected if menu items are added at app level.

### New Files (To Create)

#### `Contextify/Contextify/TranscriptInventoryWindow.swift`
**Purpose:** Window-specific wrapper view that embeds `TranscriptInventoryView` with window-appropriate configuration.
**Responsibilities:** Manages window-specific toolbar, provides data binding from `ConversationMonitor`, handles window lifecycle callbacks.
**Relationship:** Scene content for the new `Window("Transcript Inventory")` scene; adapts existing view for window context.

#### `Contextify/Contextify/WindowCoordinator.swift` (Optional)
**Purpose:** Centralized coordinator for managing window state and inter-window communication.
**Responsibilities:** Tracks open windows, provides shared state access, handles window focus events.
**Relationship:** Optional abstraction if window management becomes complex; may be deferred to future if simple `@Environment` suffices.

---

## Implementation Steps

### Phase 1: Add Window Scene (Non-Breaking)

**Goal:** Add new window scene without removing sheet, allowing parallel testing.

#### Step 1.1: Create TranscriptInventoryWindow.swift

Create new file: `Contextify/Contextify/TranscriptInventoryWindow.swift`

```swift
import SwiftUI
import ContextifyCore

/// Window-specific container for TranscriptInventoryView
/// Provides window-appropriate toolbar and data binding
@MainActor
struct TranscriptInventoryWindow: View {
  @Environment(\.dismissWindow) private var dismissWindow
  @State private var monitor = ConversationMonitor.shared

  var body: some View {
    TranscriptInventoryView(
      sessions: monitor.allSessions,
      activeSessionURL: monitor.activeSession?.fileURL,
      onSelectSession: { session in
        // Switch active session in main window
        // TODO: Implement session switching
      },
      onDismiss: {
        // No-op: window has native close button
        // Keep for backward compatibility during transition
      }
    )
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          Task {
            // Trigger session refresh
            await monitor.refreshActiveConversation(force: true)
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
    }
  }
}
```

**Rationale:** Separates window concerns from view logic; allows TranscriptInventoryView to remain reusable.

#### Step 1.2: Add Window Scene to ContextifyApp.swift

Modify: `Contextify/Contextify/ContextifyApp.swift`

Find the `App` body and add new `Window` scene:

```swift
@main
struct ContextifyApp: App {
  var body: some Scene {
    // Existing main window (keep as-is)
    WindowGroup("Contextify", id: "main") {
      ContentView()
    }
    .commands {
      CommandGroup(after: .windowArrangement) {
        Button("Show Transcript Inventory") {
          // Will be implemented via openWindow
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
      }
    }

    // NEW: Transcript inventory window
    Window("Transcript Inventory", id: "transcript-inventory") {
      TranscriptInventoryWindow()
    }
    .keyboardShortcut("t", modifiers: [.command, .option])
    .defaultSize(width: 1000, height: 700)
    .defaultPosition(.center)
  }
}
```

**Key Decisions:**
- Use `Window` (not `WindowGroup`) for single-instance auxiliary window
- Set keyboard shortcut at scene level for global availability
- Provide sensible defaults for size and position

#### Step 1.3: Test Window Opening

Build and test:
```bash
bash scripts/xc.sh build
```

Verify:
- Window → Show Transcript Inventory menu item appears
- ⌘⌥T opens transcript inventory window
- Window can be moved, resized, minimized independently
- Main window remains interactive while transcript window is open

**Expected Issues:**
- ConversationMonitor may not expose `refreshActiveConversation` - will need to add
- Session switching callback not yet implemented

---

### Phase 2: Adapt TranscriptInventoryView for Window Context

**Goal:** Remove sheet-specific UI elements and adapt for window presentation.

#### Step 2.1: Remove Sheet-Specific UI

Modify: `Contextify/Contextify/TranscriptInventoryView.swift`

Changes:
1. Remove "Done" toolbar button (window has native close button)
2. Remove `.frame(minWidth:minHeight:)` on root (window scene handles sizing)
3. Make `onDismiss` optional (window doesn't need dismissal callback)

```swift
// BEFORE: Sheet-specific toolbar
.toolbar {
  ToolbarItem(placement: .cancellationAction) {
    Button("Done") {
      onDismiss()
    }
    .keyboardShortcut(.cancelAction)
  }
}

// AFTER: Remove (window has native close button)
// Keep toolbar for other controls if needed
```

```swift
// BEFORE: Sheet-specific sizing
.frame(minWidth: 800, minHeight: 600)

// AFTER: Remove (Window scene handles sizing)
```

#### Step 2.2: Update View Initialization

Make `onDismiss` optional:

```swift
struct TranscriptInventoryView: View {
  let sessions: [TranscriptSession]
  let activeSessionURL: URL?
  let onSelectSession: (TranscriptSession) -> Void
  let onDismiss: (() -> Void)? // Made optional

  // Remove ESC key handling (window handles this natively)
}
```

**Backward Compatibility:** Keep `onDismiss` parameter for now to avoid breaking sheet presentation during transition.

---

### Phase 3: Replace Sheet with Window Opening

**Goal:** Update main window to open auxiliary window instead of presenting sheet.

#### Step 3.1: Update ConversationTimelineView

Modify: `Contextify/Contextify/ConversationTimelineView.swift`

Replace sheet presentation with window opening:

```swift
// BEFORE: Sheet presentation
@State private var showTranscriptInventory = false

// In view body:
.sheet(isPresented: $showTranscriptInventory) {
  TranscriptInventoryView(
    sessions: monitor.allSessions,
    activeSessionURL: monitor.activeSession?.fileURL,
    onSelectSession: { session in
      // ...
    },
    onDismiss: {
      showTranscriptInventory = false
    }
  )
}

// AFTER: Window opening
@Environment(\.openWindow) private var openWindow

// In menu or button action:
Button("Show All Transcripts") {
  openWindow(id: "transcript-inventory")
}
.keyboardShortcut("t", modifiers: [.command, .option])
```

**State Changes:**
- Remove `@State private var showTranscriptInventory`
- Add `@Environment(\.openWindow) private var openWindow`
- Update menu item action to call `openWindow(id:)`

#### Step 3.2: Update Menu Integration

Ensure menu item properly opens window:

```swift
// In Timeline menu section
Menu("Timeline") {
  // ... existing items ...

  Divider()

  Button("Show All Transcripts") {
    openWindow(id: "transcript-inventory")
  }
  .keyboardShortcut("t", modifiers: [.command, .option])
}
```

**Testing:**
- Verify menu item opens window (not sheet)
- Verify keyboard shortcut works from main window
- Verify reopening focuses existing window (doesn't create duplicate)

---

### Phase 4: Implement Inter-Window Communication

**Goal:** Enable session switching from transcript window to affect main window.

#### Step 4.1: Expose Session Switching in ConversationMonitor

Modify: `Contextify/Contextify/ConversationMonitor.swift`

Add public method for external session switching:

```swift
@Observable
@MainActor
final class ConversationMonitor {
  // ... existing code ...

  /// Switch to a specific session for monitoring
  /// Called from transcript inventory window
  func switchToSession(_ session: TranscriptSession) async {
    await switchToSession(session, reason: .userSelection)
  }

  // Make existing switchToSession accessible
  private enum SessionSwitchReason {
    case initial
    case providerChange
    case userSelection // NEW
  }

  private func switchToSession(_ session: TranscriptSession, reason: SessionSwitchReason) async {
    // ... existing implementation ...
  }
}
```

#### Step 4.2: Wire Up Session Selection

Update: `Contextify/Contextify/TranscriptInventoryWindow.swift`

```swift
TranscriptInventoryView(
  sessions: monitor.allSessions,
  activeSessionURL: monitor.activeSession?.fileURL,
  onSelectSession: { session in
    Task {
      await monitor.switchToSession(session)
    }
  },
  onDismiss: nil // Window doesn't need dismissal
)
```

**Data Flow:**
1. User clicks "Select for Monitoring" in transcript window
2. TranscriptInventoryView calls `onSelectSession(session)`
3. TranscriptInventoryWindow forwards to `monitor.switchToSession()`
4. ConversationMonitor updates `activeSession` (via `@Observable`)
5. Main window timeline updates automatically via observation

---

### Phase 5: Polish & Cleanup

**Goal:** Remove sheet remnants, add polish, test thoroughly.

#### Step 5.1: Remove Sheet Presentation Code

Once window is stable:
- Remove `showTranscriptInventory` state from all files
- Remove `.sheet()` modifier entirely
- Clean up any sheet-specific callbacks

#### Step 5.2: Add Window-Specific Polish

Enhancements:
1. **Window title updates:** Reflect project name or active session count
2. **Toolbar items:** Add refresh, grouping mode picker
3. **Status bar:** Show last refresh time
4. **Empty state:** Better messaging when no transcripts found

#### Step 5.3: Update Help/Documentation

Update: `CLAUDE.md` and user-facing docs
- Document ⌘⌥T shortcut
- Note that transcript inventory is now a window (not modal)
- Update any screenshots if needed

---

## Testing Plan

### Manual Testing Checklist

#### Window Behavior
- [ ] ⌘⌥T opens transcript inventory window
- [ ] Reopening focuses existing window (no duplicates)
- [ ] Window can be moved, resized independently
- [ ] Window position/size persists across app restarts
- [ ] Window can be minimized, maximized
- [ ] Closing window doesn't quit app
- [ ] ESC key closes window (native macOS behavior)

#### Concurrent Interaction
- [ ] Can interact with main timeline while transcript window is open
- [ ] Timeline updates live while browsing transcripts
- [ ] Selecting transcript in window updates main window timeline
- [ ] Active session indicator updates in both windows

#### Data Synchronization
- [ ] Transcript list updates when new sessions are created
- [ ] Active session badge reflects current monitoring state
- [ ] Search/filter works correctly
- [ ] Grouping modes work correctly

#### Edge Cases
- [ ] Opening window with no project root set (graceful error)
- [ ] Opening window with no transcripts found (empty state)
- [ ] Switching projects while window is open (updates list)
- [ ] Very large transcript list (performance)
- [ ] Rapid window open/close cycles (no crashes)

### Unit Testing (Future)

Key areas needing tests:
- `ConversationMonitor.switchToSession()` logic
- Transcript session discovery with multiple providers
- Window state persistence (if custom logic added)

---

## Migration Strategy

### Phased Rollout

**Phase 1 (This PR):** Add window scene alongside sheet (non-breaking)
- Both sheet and window coexist
- Window accessible via ⌘⌥T or menu
- Sheet still works from existing menu item

**Phase 2 (Follow-up PR):** Make window the default
- Update menu items to open window by default
- Keep sheet as fallback for testing

**Phase 3 (Future PR):** Remove sheet entirely
- Clean up sheet presentation code
- Remove `onDismiss` parameter from TranscriptInventoryView

### Backward Compatibility

- TranscriptInventoryView remains reusable (could still be used in sheet if needed)
- No breaking changes to ConversationMonitor API
- No changes to transcript discovery logic

---

## Potential Issues & Mitigations

### Issue 1: State Synchronization Between Windows

**Problem:** Main window and transcript window might show inconsistent state.

**Mitigation:**
- Use `@Observable` ConversationMonitor as single source of truth
- Both windows observe same shared instance
- Swift 6 strict concurrency ensures thread safety

### Issue 2: Window Lifecycle Management

**Problem:** Window might not properly clean up resources on close.

**Mitigation:**
- SwiftUI handles window lifecycle automatically
- No manual cleanup needed for `Window` scenes
- Monitor uses `deinit` for cleanup if needed (singleton, so unlikely)

### Issue 3: Performance with Large Transcript Lists

**Problem:** 50+ transcripts might slow down window rendering.

**Mitigation:**
- Use `List` with lazy loading (already implemented)
- Pagination or virtual scrolling if needed (future)
- File I/O on background thread (already using async/await)

### Issue 4: Keyboard Shortcut Conflicts

**Problem:** ⌘⌥T might conflict with other apps or system shortcuts.

**Mitigation:**
- Checked common macOS shortcuts - no conflicts found
- User can remap via System Settings → Keyboard → Shortcuts
- Provide alternative menu access

---

## Success Criteria

**Must Have:**
- ✅ Window opens via ⌘⌥T or menu
- ✅ Can interact with main and transcript windows concurrently
- ✅ Selecting transcript switches main window monitoring
- ✅ Window position/size persists across launches
- ✅ No crashes or data races (Swift 6 strict concurrency)

**Nice to Have:**
- ⚡ Window opens quickly (<500ms)
- 🎨 Smooth animations and transitions
- 📱 Respects system appearance (light/dark mode)
- ♿ VoiceOver support (inherited from SwiftUI)

---

## Risk Assessment

**Low Risk:**
- Adding new Window scene (non-breaking addition)
- Adapting existing view for window context (minor UI changes)

**Medium Risk:**
- Inter-window communication (needs thorough testing)
- State synchronization (mitigated by @Observable)

**High Risk:**
- None identified

**Overall Risk:** Low-Medium

---

## Timeline Estimate

**Development:** 4-6 hours
- Phase 1: 1-2 hours (add window scene)
- Phase 2: 1 hour (adapt view)
- Phase 3: 1 hour (replace sheet)
- Phase 4: 1 hour (inter-window communication)
- Phase 5: 30 min (polish)

**Testing:** 1-2 hours
**Total:** 5-8 hours

---

## Open Questions

1. **Should we keep sheet as fallback option?**
   - Leaning no - window is strictly better
   - Could keep for accessibility if needed

2. **Should we add "Open in New Window" for individual transcripts?**
   - Future enhancement
   - Would allow side-by-side transcript comparison

3. **Should window restore last-viewed transcript on reopen?**
   - Yes via AppStorage (future enhancement)
   - Low priority for MVP

---

## Appendix: File Contents

The following sections contain the current state of all related files for reference during implementation.


---

## File: Contextify/Contextify/ContextifyApp.swift

```swift
import SwiftUI
import AppKit
import ContextifyCore

@main
struct ContextifyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let model = HUDViewModel.shared
  private let timeline = ConversationMonitor.shared

  init() {
    // Check for existing instance
    if isAnotherInstanceRunning() {
      // In development, kill the old instance and proceed
      #if DEBUG
      if let existing = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == Bundle.main.bundleIdentifier &&
        $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
      }) {
        existing.terminate()
        // Give it a moment to shut down
        Thread.sleep(forTimeInterval: 0.5)
      }
      #else
      // In production, show alert and quit
      showSingleInstanceAlert()
      NSApplication.shared.terminate(nil)
      #endif
    }
  }

  var body: some Scene {
    Window("Contextify", id: "main") {
      ContentView()
        .environment(model)
        .environment(timeline)
        .background(WindowAccessor())
    }
    .defaultSize(width: 940, height: 360)
    .commands {
      CommandGroup(replacing: .newItem) { }
      ProjectRootCommands()
    }
  }

  private func isAnotherInstanceRunning() -> Bool {
    let runningApps = NSWorkspace.shared.runningApplications
    let contextifyApps = runningApps.filter { app in
      app.bundleIdentifier == Bundle.main.bundleIdentifier &&
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
    return !contextifyApps.isEmpty
  }

  private func showSingleInstanceAlert() {
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.messageText = "Contextify is Already Running"
      alert.informativeText = "Only one instance of Contextify can run at a time. The existing instance will be brought to the front."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "OK")
      alert.runModal()

      // Activate the existing instance
      if let existing = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == Bundle.main.bundleIdentifier &&
        $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
      }) {
        existing.activate()
      }
    }
  }
}

struct ProjectRootCommands: Commands {
  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Set Project Root…") { pickProjectRoot() }
    }
  }

  private func pickProjectRoot() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    if panel.runModal() == .OK, let url = panel.urls.first {
      _ = HUDViewModel.shared.setProjectRoot(url: url)
    }
  }
}
```

---

## File: Contextify/Contextify/ConversationTimelineView.swift

```swift
import SwiftUI

struct ConversationTimelineView: View {
    @Environment(ConversationMonitor.self) private var monitor

    @State private var showTranscriptInventory = false

    private let collapsedWidth: CGFloat = 52
    private let expandedWidth: CGFloat = 320
    private let scrollAnchorID = "timeline-scroll-anchor"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if monitor.isCollapsed {
                collapsedContent
            } else {
                timelineContent
            }
        }
        .frame(width: monitor.isCollapsed ? collapsedWidth : expandedWidth)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: monitor.isCollapsed)
        .overlay(alignment: .bottomTrailing) {
            if monitor.lastError != nil {
                Button {
                    TimelineIntegration.shared.requestManualRefresh(trigger: .manualHotkey)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .padding(8)
                .help("Timeline fetch failed. Retry now.")
            }
        }
        .sheet(isPresented: $showTranscriptInventory) {
            TranscriptInventoryView(
                sessions: monitor.allSessions,
                activeSessionURL: monitor.activeSession?.fileURL,
                onSelectSession: { session in
                    showTranscriptInventory = false
                    // TODO: Add method to ConversationMonitor to switch to specific session
                },
                onDismiss: {
                    showTranscriptInventory = false
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if monitor.isCollapsed {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversation Log")
                        .font(.headline)
                    if let last = monitor.lastUpdate {
                        Text("Updated \(last, format: .dateTime.hour().minute().second())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if monitor.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
                Menu {
                    Button {
                        showTranscriptInventory = true
                    } label: {
                        Label("Show All Transcripts (\(monitor.allSessions.count))", systemImage: "doc.text.magnifyingglass")
                    }
                    Divider()
                    Button("Refresh Now") {
                        TimelineIntegration.shared.requestManualRefresh(trigger: .manualHotkey)
                    }
                    Toggle("Auto-scroll", isOn: Binding(
                        get: { monitor.autoScroll },
                        set: { monitor.autoScroll = $0 }
                    ))
                    Divider()
                    Button(role: .destructive) {
                        monitor.clearEntries()
                    } label: {
                        Label("Clear Timeline", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Button(action: { monitor.toggleCollapsed() }) {
                Image(systemName: monitor.isCollapsed ? "arrow.left.square" : "arrow.right.square")
            }
            .buttonStyle(.plain)
            .help(monitor.isCollapsed ? "Expand timeline" : "Collapse timeline")
        }
        .padding(.horizontal, monitor.isCollapsed ? 12 : 16)
        .padding(.vertical, 12)
    }

    private var collapsedContent: some View {
        VStack {
            Spacer()
            if monitor.isProcessing {
                ProgressView()
            } else {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var timelineContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = monitor.lastError {
                        errorBanner(error)
                    }

                    if monitor.entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(monitor.entries) { entry in
                            TimelineEntryRow(entry: entry)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .id(entry.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(scrollAnchorID)
                    }
                }
                .padding(16)
            }
            .onChange(of: monitor.entries.map { $0.id }) { _, ids in
                guard monitor.autoScroll, !ids.isEmpty else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(scrollAnchorID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("No Activity Yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Use Claude Code in iTerm2 to populate the timeline.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.caption)
            Spacer()
            Button("Retry") {
                TimelineIntegration.shared.requestManualRefresh(trigger: .manualHotkey)
            }
            .buttonStyle(.link)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(0.15))
        )
    }

}
```

---

## File: Contextify/Contextify/TranscriptInventoryView.swift

```swift
import SwiftUI
import ContextifyCore

/// Displays all discovered transcripts for the current project, including worktrees.
/// Uses HSplitView for macOS-native sidebar + detail layout.
struct TranscriptInventoryView: View {
  let sessions: [TranscriptSession]
  let activeSessionURL: URL?
  let onSelectSession: (TranscriptSession) -> Void
  let onDismiss: () -> Void

  @State private var selectedSessionURL: URL?
  @State private var searchText = ""
  @State private var groupingMode: GroupingMode = .provider

  enum GroupingMode: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case date = "Date"
    case flat = "All"

    var id: String { rawValue }
  }

  var body: some View {
    HSplitView {
      // Session list
      sessionListView
        .frame(minWidth: 250)

      // Detail view
      detailView
        .frame(minWidth: 500)
    }
    .frame(minWidth: 800, minHeight: 600)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Done") {
          onDismiss()
        }
        .keyboardShortcut(.cancelAction)
      }
    }
  }

  private var selectedSession: TranscriptSession? {
    guard let url = selectedSessionURL else { return nil }
    return sessions.first(where: { $0.fileURL == url })
  }

  @ViewBuilder
  private var sessionListView: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Transcript Inventory")
          .font(.headline)
        Spacer()
        Button {
          refreshSessions()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
      }
      .padding()

      // Toolbar with grouping
      HStack {
        Picker("Group by", selection: $groupingMode) {
          ForEach(GroupingMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)

        Spacer()

        Text("\(filteredSessions.count) transcripts")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal)
      .padding(.bottom, 8)

      Divider()

      // Session list with URL-based selection
      List(sessions, id: \.fileURL, selection: $selectedSessionURL) { session in
        sessionRow(session)
          .tag(session.fileURL)
      }
      .listStyle(.sidebar)
      .searchable(text: $searchText, prompt: "Search transcripts")
      .onChange(of: sessions) { _, newSessions in
        // Clear selection if selected session no longer exists
        if let selectedURL = selectedSessionURL,
           !newSessions.contains(where: { $0.fileURL == selectedURL }) {
          selectedSessionURL = nil
        }
      }
    }
  }

  @ViewBuilder
  private var detailView: some View {
    if let session = selectedSession {
      TranscriptDetailView(
        session: session,
        isActive: session.fileURL == activeSessionURL,
        onSelect: {
          onSelectSession(session)
        }
      )
    } else {
      emptyDetailView
    }
  }

  private var emptyDetailView: some View {
    VStack(spacing: 12) {
      Image(systemName: "doc.text")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("No Transcript Selected")
        .font(.headline)
      Text("Select a transcript from the sidebar to view details")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Session Row

  @ViewBuilder
  private func sessionRow(_ session: TranscriptSession) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: providerIcon(session.provider))
          .foregroundStyle(providerColor(session.provider))
          .frame(width: 16)

        Text(session.identifier)
          .font(.callout)
          .lineLimit(1)

        if session.fileURL == activeSessionURL {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(.green)
        }
      }

      HStack(spacing: 4) {
        Label(providerName(session.provider), systemImage: providerIcon(session.provider))
          .font(.caption)
          .foregroundStyle(.secondary)
          .labelStyle(.titleOnly)

        Text("•")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(relativeTime(session.lastActivity))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  // MARK: - Helpers

  private var filteredSessions: [TranscriptSession] {
    if searchText.isEmpty {
      return sessions
    }
    return sessions.filter { session in
      session.identifier.localizedCaseInsensitiveContains(searchText)
        || session.fileURL.path.localizedCaseInsensitiveContains(searchText)
    }
  }

  private func providerName(_ provider: TimelineSourceContext.Provider) -> String {
    switch provider {
    case .claudeCode: return "Claude Code"
    case .codexCLI: return "Codex CLI"
    case .other: return "Other"
    }
  }

  private func providerIcon(_ provider: TimelineSourceContext.Provider) -> String {
    switch provider {
    case .claudeCode: return "terminal.fill"
    case .codexCLI: return "chevron.left.forwardslash.chevron.right"
    case .other: return "doc.text"
    }
  }

  private func providerColor(_ provider: TimelineSourceContext.Provider) -> Color {
    switch provider {
    case .claudeCode: return .orange
    case .codexCLI: return .blue
    case .other: return .gray
    }
  }

  private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func refreshSessions() {
    // Trigger refresh in parent
    // This will be wired up when integrated
  }
}

/// Detail view for a selected transcript session
struct TranscriptDetailView: View {
  let session: TranscriptSession
  let isActive: Bool
  let onSelect: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header with status badge
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(session.identifier)
              .font(.title2)
              .fontWeight(.semibold)

            Text(providerName)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          Spacer()

          if isActive {
            Label("Active", systemImage: "circle.fill")
              .font(.caption)
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
              .background(Color.green)
              .clipShape(Capsule())
          }
        }

        Divider()

        // Metadata
        VStack(alignment: .leading, spacing: 12) {
          metadataRow(label: "Last Modified", value: formattedDate(session.lastActivity))
          metadataRow(label: "File Path", value: session.fileURL.path)
          metadataRow(label: "File Name", value: session.fileURL.lastPathComponent)
          metadataRow(label: "Provider", value: providerName)

          if let fileSize = fileSize() {
            metadataRow(label: "File Size", value: fileSize)
          }

          if let lineCount = lineCount() {
            metadataRow(label: "Lines", value: "\(lineCount)")
          }
        }

        Divider()

        // Actions
        VStack(spacing: 8) {
          if !isActive {
            Button {
              onSelect()
            } label: {
              Label("Select for Monitoring", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          }

          Button {
            NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
          } label: {
            Label("Reveal in Finder", systemImage: "folder")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSWorkspace.shared.open(session.fileURL)
          } label: {
            Label("Open in Default Editor", systemImage: "doc.text")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.fileURL.path, forType: .string)
          } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
      }
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func metadataRow(label: String, value: String) -> some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(width: 100, alignment: .leading)

      Text(value)
        .font(.subheadline)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var providerName: String {
    switch session.provider {
    case .claudeCode: return "Claude Code"
    case .codexCLI: return "Codex CLI"
    case .other: return "Other"
    }
  }

  private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func fileSize() -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: session.fileURL.path),
          let size = attrs[.size] as? Int64 else {
      return nil
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private func lineCount() -> Int? {
    guard let content = try? String(contentsOf: session.fileURL, encoding: .utf8) else {
      return nil
    }
    return content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
  }
}

// MARK: - Previews

#if DEBUG
struct TranscriptInventoryView_Previews: PreviewProvider {
  static var previews: some View {
    TranscriptInventoryView(
      sessions: [
        TranscriptSession(
          provider: .claudeCode,
          identifier: "conversation-1.jsonl",
          fileURL: URL(fileURLWithPath: "/Users/rob/.claude/projects/contextify/conversation-1.jsonl"),
          lastActivity: Date()
        ),
        TranscriptSession(
          provider: .claudeCode,
          identifier: "conversation-2.jsonl",
          fileURL: URL(fileURLWithPath: "/Users/rob/.claude/projects/contextify/conversation-2.jsonl"),
          lastActivity: Date().addingTimeInterval(-3600)
        ),
        TranscriptSession(
          provider: .codexCLI,
          identifier: "session-123.jsonl",
          fileURL: URL(fileURLWithPath: "/Users/rob/.codex/sessions/session-123.jsonl"),
          lastActivity: Date().addingTimeInterval(-86400)
        )
      ],
      activeSessionURL: URL(fileURLWithPath: "/Users/rob/.claude/projects/contextify/conversation-1.jsonl"),
      onSelectSession: { _ in },
      onDismiss: { }
    )
  }
}
#endif
```

---

## File: Contextify/Contextify/ConversationMonitor.swift

```swift
import Foundation
import Observation
import OSLog
import ContextifyCore

@Observable
@MainActor
final class ConversationMonitor {
    static let shared = ConversationMonitor()

    private let log = Logger(subsystem: "dev.contextify", category: "Timeline")
    private let config = MonitorConfig()
    private let conversationResolver = ActiveConversationResolver(providers: [
        ClaudeTranscriptProvider(),
        CodexTranscriptProvider()
    ])
    private let affirmativeLexicon: Set<String> = [
        "yes", "y", "ok", "okay", "sure", "👍", "yep", "yup", "sounds", "good", "go", "ahead",
        "proceed", "do", "it", "please", "sgtm", "roger", "affirmative", "yeah", "yah", "make", "so"
    ]
    private let negativeLexicon: Set<String> = [
        "no", "nope", "nah", "not", "now", "yet", "hold", "off", "stop", "don't", "do", "cancel", "abort"
    ]
    private let actionHintCues: [String] = [
        "would you like me to", "shall i", "i can ", "i will ",
        "proceed", "change it to", "ensure ", "run ", "fix ", "update ", "refactor ", "implement "
    ]

    private(set) var entries: [TimelineEntry] = []
    private(set) var isCollapsed = false
    private(set) var isMonitoring = false
    private(set) var isProcessing = false
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?
    var autoScroll = true

    @ObservationIgnored private var fileWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var conversationFileDescriptor: CInt = -1
    @ObservationIgnored private var lastProcessedLine: Int = 0
    @ObservationIgnored private var currentLineNumber: Int = 0
    @ObservationIgnored private var seenMessageUUIDs: Set<String> = []
    @ObservationIgnored private var didEmitSessionStart = false
    @ObservationIgnored private var currentConversationFile: URL?
    @ObservationIgnored private(set) var activeSession: TranscriptSession?
    @ObservationIgnored private var conversationResolverTask: Task<Void, Never>?
    @ObservationIgnored private(set) var allSessions: [TranscriptSession] = []

    private init() {}

    func startMonitoring() {
        guard fileWatcher == nil else { return }
        log.info("Starting conversation timeline monitoring via project conversation files")
        log.info("HUDViewModel projectRootURL: \(String(describing: HUDViewModel.shared.projectRootURL?.path), privacy: .public)")
        isMonitoring = true

        // Find and watch the current project's conversation file
        Task { [weak self] in
            await self?.refreshActiveConversation(force: true)
        }
        startConversationResolverLoop()
    }

    func stopMonitoring() {
        tearDownFileWatcher()
        isMonitoring = false
        currentConversationFile = nil
        activeSession = nil
        conversationResolverTask?.cancel()
        conversationResolverTask = nil
    }

    func toggleCollapsed() {
        isCollapsed.toggle()
    }

    func clearEntries() {
        entries.removeAll()
        lastProcessedLine = 0
        seenMessageUUIDs.removeAll()
        didEmitSessionStart = false
        ensureSessionStartEntry()
    }

    func requestImmediateRefresh(trigger: TimelineRefreshTrigger) {
        Task {
            await processConversationFile()
        }
    }

    // MARK: - File Discovery & Watching

    private func refreshActiveConversation(force: Bool = false) async {
        guard let projectURL = HUDViewModel.shared.projectRootURL else {
            if activeSession != nil {
                log.info("No project root set; tearing down watcher")
                tearDownFileWatcher()
            }
            activeSession = nil
            currentConversationFile = nil
            allSessions = []
            lastError = "No project root set"
            log.error("Timeline: No project root URL available from HUDViewModel")
            return
        }

        log.info("Timeline: Resolving conversations for project: \(projectURL.path, privacy: .public)")

        // Use ProjectContext for worktree-aware session discovery
        guard let context = ProjectContext.current() else {
            log.error("Timeline: Failed to create ProjectContext")
            lastError = "Failed to create project context"
            return
        }

        let sessions = conversationResolver.resolveAllSessions(for: context)
        allSessions = sessions

        log.info("Timeline: Found \(sessions.count) total sessions for project (including worktrees)")

        guard let session = sessions.first else {
            if activeSession != nil {
                log.info("No active conversation sessions found; tearing down watcher")
                tearDownFileWatcher()
            }
            activeSession = nil
            currentConversationFile = nil
            lastError = "No conversation file found for this project"
            log.error("Timeline: No sessions found for project")
            return
        }

        log.info("Timeline: Active session at \(session.fileURL.path, privacy: .public)")

        if !force, let current = activeSession, current.fileURL == session.fileURL {
            activeSession = session
            return
        }

        await switchToSession(session, reason: force ? .initial : .providerChange)
    }

    private enum SessionSwitchReason {
        case initial
        case providerChange
    }

    private func switchToSession(_ session: TranscriptSession, reason: SessionSwitchReason) async {
        tearDownFileWatcher()

        activeSession = session
        currentConversationFile = session.fileURL
        lastProcessedLine = 0
        seenMessageUUIDs.removeAll()
        lastError = nil

        configureFileWatcher(for: session.fileURL)

        if reason == .initial {
            ensureSessionStartEntry()
        } else if reason == .providerChange {
            emitProviderSwitchEntry(for: session)
        }

        await processConversationFile()
    }

    private func configureFileWatcher(for fileURL: URL) {
        let path = fileURL.path
        conversationFileDescriptor = open(path, O_EVTONLY)
        guard conversationFileDescriptor >= 0 else {
            log.error("Failed to open conversation file for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: conversationFileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                await self?.processConversationFile()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.conversationFileDescriptor >= 0 {
                close(self.conversationFileDescriptor)
                self.conversationFileDescriptor = -1
            }
        }

        source.resume()
        fileWatcher = source
        log.info("Watching transcript: \(fileURL.lastPathComponent, privacy: .public)")
    }

    private func tearDownFileWatcher() {
        if let watcher = fileWatcher {
            watcher.cancel()
            fileWatcher = nil
        } else if conversationFileDescriptor >= 0 {
            close(conversationFileDescriptor)
        }

        conversationFileDescriptor = -1
    }

    private func emitProviderSwitchEntry(for session: TranscriptSession) {
        let providerName: String
        switch session.provider {
        case .claudeCode: providerName = "Claude Code"
        case .codexCLI: providerName = "Codex CLI"
        case .other: providerName = "AI Source"
        }

        let summary = "Switched to \(providerName) conversation"
        let detail = """
        Timeline switched to \(providerName) conversation

        Monitoring: \(session.fileURL.lastPathComponent)
        Path: \(session.fileURL.path)
        """
        let context = TimelineSourceContext(
            provider: session.provider,
            identifier: session.identifier,
            filePath: session.fileURL.path
        )

        let entry = TimelineEntry(
            kind: .system,
            timestamp: Date(),
            summary: summary,
            detail: detail,
            sourceContent: detail,
            sourceContext: context,
            sourceIdentifier: "provider-switch-\(session.identifier)"
        )

        entries.append(entry)
        if entries.count > config.maxEntries {
            entries = Array(entries.suffix(config.maxEntries))
        }
    }

    private func startConversationResolverLoop() {
        conversationResolverTask?.cancel()
        conversationResolverTask = Task { [weak self] in
            guard let self else { return }
            let interval = await MainActor.run { self.config.pollInterval }
            let delay = UInt64(max(interval, 1) * 1_000_000_000)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delay)
                await self.refreshActiveConversation()
            }
        }
    }

    private func makeSourceContext(identifier: String, line: Int? = nil) -> TimelineSourceContext {
        let provider = activeSession?.provider ?? .other
        let filePath = activeSession?.fileURL.path
        return TimelineSourceContext(provider: provider, identifier: identifier, filePath: filePath, line: line)
    }

    // MARK: - Processing

    private func processConversationFile() async {
        guard isMonitoring else {
            log.error("🔴 processConversationFile: not monitoring")
            return
        }
        guard !isProcessing else {
            log.error("🔴 processConversationFile: already processing")
            return
        }
        guard let fileURL = currentConversationFile else {
            log.error("🔴 processConversationFile: no conversation file")
            return
        }

        log.info("🟢 processConversationFile: starting, file=\(fileURL.lastPathComponent, privacy: .public)")

        isProcessing = true
        defer {
            isProcessing = false
            lastUpdate = Date()
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

            log.info("🟢 processConversationFile: read \(lines.count) lines, lastProcessedLine=\(self.lastProcessedLine)")

            // Only process new lines since last check
            guard lines.count > lastProcessedLine else {
                log.info("🟡 processConversationFile: no new lines to process")
                return
            }

            let newLines: ArraySlice<String>
            let shouldBackfillLimitedEntries: Bool
            if lastProcessedLine == 0 {
                // Initial load: Check if timeline is effectively empty (only system messages)
                let hasNonSystemMessages = entries.contains { $0.kind != .system }

                if !hasNonSystemMessages {
                    // Timeline is empty, backfill last 5 displayable entries
                    newLines = lines[...]
                    shouldBackfillLimitedEntries = true
                    log.info("🟢 processConversationFile: Initial load (empty timeline), will backfill last 5 displayable entries from \(lines.count) total lines")
                } else {
                    // Timeline already has content, don't backfill old messages
                    newLines = []
                    shouldBackfillLimitedEntries = false
                    log.info("🟢 processConversationFile: Initial load (existing timeline), skipping backfill")
                }
                lastProcessedLine = lines.count
            } else {
                // Incremental update: process all new lines
                newLines = lines[lastProcessedLine...]
                shouldBackfillLimitedEntries = false
                lastProcessedLine = lines.count
                log.info("🟢 processConversationFile: Incremental update, processing \(newLines.count) new lines")
            }

            var processedCount = 0
            var skippedCount = 0
            let entriesBeforeProcessing = entries.count

            for (index, line) in newLines.reversed().enumerated() {
                // Calculate actual line number in file
                let lineNumber = shouldBackfillLimitedEntries
                    ? lastProcessedLine - newLines.count + index + 1
                    : lastProcessedLine - newLines.count + index + 1

                // If backfilling with limit, stop once we have 5 new displayable entries
                if shouldBackfillLimitedEntries {
                    let newDisplayableEntries = entries.count - entriesBeforeProcessing
                    if newDisplayableEntries >= 20 {
                        log.info("🟢 processConversationFile: Reached displayable entries limit, (newDisplayableEntries) stopping backfill")
                        break
                    }
                }

                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    skippedCount += 1
                    continue
                }

                currentLineNumber = lineNumber
                await processConversationEntry(json)
                processedCount += 1
            }

            // Reverse entries if we were backfilling (since we processed in reverse)
            if shouldBackfillLimitedEntries, entries.count > entriesBeforeProcessing {
                let backfilledEntries = entries[entriesBeforeProcessing...]
                entries.removeLast(backfilledEntries.count)
                entries.append(contentsOf: backfilledEntries.reversed())
            }

            log.info("🟢 processConversationFile: processed \(processedCount) entries, skipped \(skippedCount), total timeline entries now: \(self.entries.count)")

            lastError = nil
        } catch {
            lastError = "Failed to read conversation: \(error.localizedDescription)"
            log.error("🔴 processConversationFile: Failed to process conversation file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func processConversationEntry(_ json: [String: Any]) async {
        guard let uuid = json["uuid"] as? String else {
            log.error("🔴 processConversationEntry: no uuid")
            return
        }
        guard !seenMessageUUIDs.contains(uuid) else {
            log.info("🟡 processConversationEntry: already seen uuid=\(uuid, privacy: .public)")
            return
        }
        seenMessageUUIDs.insert(uuid)

        if (json["isSidechain"] as? Bool) == true {
            log.info("🟡 processConversationEntry: skipping sidechain message")
            return
        }

        guard let type = json["type"] as? String else {
            log.error("🔴 processConversationEntry: no type for uuid=\(uuid, privacy: .public)")
            return
        }
        guard let timestampStr = json["timestamp"] as? String else {
            log.error("🔴 processConversationEntry: no timestamp for uuid=\(uuid, privacy: .public)")
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let timestamp = formatter.date(from: timestampStr) else {
            log.error("🔴 processConversationEntry: invalid timestamp '\(timestampStr, privacy: .public)' for uuid=\(uuid, privacy: .public)")
            return
        }

        log.info("🟢 processConversationEntry: type=\(type, privacy: .public), uuid=\(uuid, privacy: .public)")

        switch type {
        case "user":
            await processUserMessage(json, timestamp: timestamp, uuid: uuid)
        case "assistant":
            await processAssistantMessage(json, timestamp: timestamp, uuid: uuid)
        default:
            log.info("🟡 processConversationEntry: skipping unknown type=\(type, privacy: .public)")
            break
        }
    }

    private func processUserMessage(_ json: [String: Any], timestamp: Date, uuid: String) async {
        log.info("🟢 processUserMessage: uuid=\(uuid, privacy: .public)")

        guard let message = json["message"] as? [String: Any] else {
            log.error("🔴 processUserMessage: no message dict for uuid=\(uuid, privacy: .public)")
            return
        }

        let toolUseStdout = (json["toolUseResult"] as? [String: Any])?["stdout"] as? String
        let fallbackToolText = (toolUseStdout?.isEmpty == false) ? toolUseStdout : nil

        if let contentBlocks = message["content"] as? [[String: Any]] {
            let blockTypes = contentBlocks.compactMap { $0["type"] as? String }
            if !blockTypes.isEmpty, blockTypes.allSatisfy({ $0 == "tool_result" }) {
                log.info("🟡 processUserMessage: skipping assistant tool_result relay for uuid=\(uuid, privacy: .public)")
                return
            }
        }

        let text: String
        if let directContent = message["content"] as? String {
            text = directContent
        } else if let contentBlocks = message["content"] as? [[String: Any]] {
            let blockText = contentBlocks.compactMap { block -> String? in
                guard let blockType = block["type"] as? String else { return nil }

                switch blockType {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty { return text }
                    if let text = block["content"] as? String, !text.isEmpty { return text }
                    return nil
                case "tool_result":
                    if let text = block["content"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                default:
                    return nil
                }
            }.first

            if let blockText {
                text = blockText
            } else if let stdout = fallbackToolText {
                // Prefer inline block content when available; fall back to tool output if the array omits it.
                text = stdout
            } else {
                let contentType = type(of: message["content"] as Any)
                log.error("🔴 processUserMessage: no usable content in array for uuid=\(uuid, privacy: .public), content type=\(String(describing: contentType))")
                return
            }
        } else if let stringArray = message["content"] as? [String],
                  let first = stringArray.first(where: { !$0.isEmpty }) {
            text = first
        } else if let stdout = fallbackToolText {
            // Prefer inline block content when available; fall back to tool output if the array omits it.
            text = stdout
        } else {
            let contentType = type(of: message["content"] as Any)
            log.error("🔴 processUserMessage: content not a string for uuid=\(uuid, privacy: .public), content type=\(String(describing: contentType))")
            return
        }

        let isMeta = json["isMeta"] as? Bool ?? false
        log.info("🟢 processUserMessage: text length=\(text.count), isMeta=\(isMeta)")

        // Skip meta messages and command wrappers
        guard !text.isEmpty,
              !(json["isMeta"] as? Bool ?? false),
              !text.contains("<command-name>"),
              !text.contains("<local-command-stdout>") else {
            log.info("🟡 processUserMessage: skipping (empty/meta/command) for uuid=\(uuid, privacy: .public)")
            return
        }

        log.info("🟢 processUserMessage: creating timeline entry for uuid=\(uuid, privacy: .public)")

        let actionHint = shouldUseActionHint(for: text) ? latestAssistantActionHint() : nil
        let summaryResult: FoundationLLM.TimelineSummaryResult
        do {
            summaryResult = try await FoundationLLM.shared.summarizeTimeline(kind: .user, text: text, actionHint: actionHint)
        } catch {
            log.error("🔴 processUserMessage: summarization failed after retries, skipping entry: \(error.localizedDescription, privacy: .public)")
            return
        }
        let detail = text.count > config.previewCharacterLimit
            ? String(text.prefix(config.previewCharacterLimit - 1)) + "…"
            : text

        let entry = TimelineEntry(
            kind: .user,
            timestamp: timestamp,
            summary: summaryResult.summary,
            detail: detail,
            sourceContent: text,
            sourceContext: makeSourceContext(identifier: uuid, line: currentLineNumber),
            sourceIdentifier: "msg-\(uuid)",
            isCompletion: false
        )

        entries.append(entry)

        if entries.count > config.maxEntries {
            entries = Array(entries.suffix(config.maxEntries))
        }

        log.info("✅ processUserMessage: Added user entry, summary=\(summaryResult.summary, privacy: .private), total entries=\(self.entries.count)")
    }

    private func processAssistantMessage(_ json: [String: Any], timestamp: Date, uuid: String) async {
        log.info("🟢 processAssistantMessage: uuid=\(uuid, privacy: .public)")

        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            log.error("🔴 processAssistantMessage: no message or content array for uuid=\(uuid, privacy: .public)")
            return
        }

        log.info("🟢 processAssistantMessage: content blocks count=\(content.count)")

        // Process each content block (skip tool invokes, only surface text)
        for (index, block) in content.enumerated() {
            guard let blockType = block["type"] as? String else {
                log.error("🔴 processAssistantMessage: no type in block \(index) for uuid=\(uuid, privacy: .public)")
                continue
            }

            log.info("🟢 processAssistantMessage: block \(index) type=\(blockType, privacy: .public)")

            switch blockType {
            case "text":
                if let text = block["text"] as? String {
                    await addAssistantTextEntry(text: text, timestamp: timestamp, uuid: uuid)
                } else {
                    log.error("🔴 processAssistantMessage: text block has no text field")
                }
            case "tool_use":
                log.info("🟡 processAssistantMessage: skipping tool_use block for uuid=\(uuid, privacy: .public)")
            default:
                log.info("🟡 processAssistantMessage: skipping unknown block type=\(blockType, privacy: .public)")
                break
            }
        }
    }

    private func addAssistantTextEntry(text: String, timestamp: Date, uuid: String) async {
        log.info("🟢 addAssistantTextEntry: text length=\(text.count), uuid=\(uuid, privacy: .public)")

        let summaryResult: FoundationLLM.TimelineSummaryResult
        do {
            summaryResult = try await FoundationLLM.shared.summarizeTimeline(kind: .assistant, text: text)
        } catch {
            log.error("🔴 addAssistantTextEntry: summarization failed after retries, skipping entry: \(error.localizedDescription, privacy: .public)")
            return
        }
        let detail = text.count > config.previewCharacterLimit
            ? String(text.prefix(config.previewCharacterLimit - 1)) + "…"
            : text

        let entry = TimelineEntry(
            kind: .assistant,
            timestamp: timestamp,
            summary: summaryResult.summary,
            detail: detail,
            sourceContent: text,
            sourceContext: makeSourceContext(identifier: uuid, line: currentLineNumber),
            sourceIdentifier: "msg-\(uuid)-text",
            isCompletion: summaryResult.isCompletion
        )

        entries.append(entry)
        log.info("✅ addAssistantTextEntry: Added assistant text entry, summary=\(summaryResult.summary, privacy: .private), completion=\(summaryResult.isCompletion), uuid=\(uuid, privacy: .public), total entries=\(self.entries.count)")
    }

    private func latestAssistantActionHint() -> String? {
        guard let lastAssistant = entries.reversed().first(where: { $0.kind == .assistant }) else {
            return nil
        }
        let raw = lastAssistant.sourceContent?.isEmpty == false
            ? lastAssistant.sourceContent
            : lastAssistant.detail
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return distilledActionHint(from: raw)
    }

    private func distilledActionHint(from text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let candidate = lines.first { line in
            let lower = line.lowercased()
            return actionHintCues.contains { lower.contains($0) }
        } ?? lines.first

        guard var hint = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty else {
            return nil
        }

        hint = hint.replacingOccurrences(
            of: "^(yes|no|ok|okay|sure|please)[\\s,:-]*",
            with: "",
            options: .regularExpression
        )
        hint = hint.replacingOccurrences(
            of: "[?.!…]+$",
            with: "",
            options: .regularExpression
        )

        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }

    private func shouldUseActionHint(for text: String) -> Bool {
        let normalized = normalizeForActionHint(text)
        guard !normalized.isEmpty else { return false }
        let tokens = normalized.split(separator: " ")
        guard tokens.count <= 3 else { return false }
        let allAffirmative = tokens.allSatisfy { affirmativeLexicon.contains(String($0)) }
        let allNegative = tokens.allSatisfy { negativeLexicon.contains(String($0)) }
        return allAffirmative || allNegative
    }

    private func normalizeForActionHint(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuation = CharacterSet.punctuationCharacters.union(CharacterSet(charactersIn: "…“”\"'"))
        normalized = normalized.trimmingCharacters(in: punctuation)
        normalized = normalized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return normalized.lowercased()
    }

    private func ensureSessionStartEntry() {
        guard !didEmitSessionStart else { return }
        didEmitSessionStart = true
        let summary = "Timeline monitoring started"
        let detail: String
        if let fileURL = currentConversationFile {
            detail = """
            Timeline monitoring started

            Monitoring: \(fileURL.lastPathComponent)
            Path: \(fileURL.path)
            """
        } else {
            detail = "Timeline monitoring started (no conversation file found yet)"
        }
        let entry = TimelineEntry(
            kind: .system,
            summary: summary,
            detail: detail,
            sourceContent: detail,
            sourceContext: makeSourceContext(identifier: "system-start"),
            sourceIdentifier: "system-start"
        )
        entries.append(entry)
    }
}

#if DEBUG
extension ConversationMonitor {
    func _testShouldUseActionHint(_ text: String) -> Bool {
        shouldUseActionHint(for: text)
    }

    func _testDistilledActionHint(from text: String) -> String? {
        distilledActionHint(from: text)
    }
}
#endif
```

---

## File: Contextify/Contextify/ConversationSources.swift

```swift
import Foundation

struct TranscriptSession: Hashable, Sendable {
    let provider: TimelineSourceContext.Provider
    let identifier: String
    let fileURL: URL
    let lastActivity: Date
}

protocol ConversationTranscriptProvider: Sendable {
    func sessions(for projectPath: String) -> [TranscriptSession]
    func sessions(for context: ProjectContext) -> [TranscriptSession]
}

extension ConversationTranscriptProvider {
    // Default implementation for backward compatibility
    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        return sessions(for: context.workingDirectory.path)
    }
}

struct ClaudeTranscriptProvider: ConversationTranscriptProvider {
    private let fileManager = FileManager.default

    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        var allSessions: [TranscriptSession] = []

        // Collect sessions from all project paths (working directory, git root, worktrees)
        for projectURL in context.allProjectPaths() {
            allSessions.append(contentsOf: sessionsForPath(projectURL.path))
        }

        // Deduplicate by file URL
        var seen = Set<URL>()
        return allSessions.filter { session in
            seen.insert(session.fileURL).inserted
        }
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        let projectDirName = projectPath.replacingOccurrences(of: "/", with: "-")
        let projectsDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let projectDir = projectsDir.appendingPathComponent(projectDirName)

        guard fileManager.fileExists(atPath: projectDir.path) else { return [] }

        do {
            let files = try fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "jsonl" }

            return files.compactMap { fileURL in
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                let lastMod = values?.contentModificationDate ?? .distantPast
                return TranscriptSession(
                    provider: .claudeCode,
                    identifier: fileURL.lastPathComponent,
                    fileURL: fileURL,
                    lastActivity: lastMod
                )
            }
        } catch {
            return []
        }
    }
}

struct CodexTranscriptProvider: ConversationTranscriptProvider {
    private let fileManager = FileManager.default

    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        var allSessions: [TranscriptSession] = []

        // Collect sessions from all project paths (working directory, git root, worktrees)
        for projectURL in context.allProjectPaths() {
            allSessions.append(contentsOf: sessionsForPath(projectURL.path))
        }

        // Deduplicate by file URL
        var seen = Set<URL>()
        return allSessions.filter { session in
            seen.insert(session.fileURL).inserted
        }
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        let codexSessionsDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")

        guard fileManager.fileExists(atPath: codexSessionsDir.path) else { return [] }

        // Get git repository URL for this path (if available)
        let gitRepoURL = getGitRepositoryURL(for: projectPath)

        // Find all JSONL files in sessions directory (including subdirectories)
        let jsonlFiles = findJSONLFiles(in: codexSessionsDir)

        // Parse each file looking for session_meta with matching cwd or git repo
        return jsonlFiles.compactMap { fileURL in
            parseCodexSession(fileURL, matchingPath: projectPath, gitRepoURL: gitRepoURL)
        }
    }

    private func findJSONLFiles(in directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var jsonlFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                jsonlFiles.append(fileURL)
            }
        }
        return jsonlFiles
    }

    private func parseCodexSession(_ fileURL: URL, matchingPath: String, gitRepoURL: String?) -> TranscriptSession? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? fileHandle.close() }

        // Read file line by line looking for session_meta
        guard let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  json["type"] as? String == "session_meta",
                  let payload = json["payload"] as? [String: Any] else {
                continue
            }

            // Check if this session matches our project by cwd or git repo URL
            let sessionCwd = payload["cwd"] as? String
            let sessionGitInfo = payload["git"] as? [String: Any]
            let sessionRepoURL = sessionGitInfo?["repository_url"] as? String

            let isMatch = sessionCwd == matchingPath ||
                          (gitRepoURL != nil && sessionRepoURL == gitRepoURL)

            guard isMatch else { continue }

            // Found a matching session_meta
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let lastMod = values?.contentModificationDate ?? .distantPast

            return TranscriptSession(
                provider: .codexCLI,
                identifier: fileURL.lastPathComponent,
                fileURL: fileURL,
                lastActivity: lastMod
            )
        }

        return nil
    }

    private func getGitRepositoryURL(for path: String) -> String? {
        let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
        let configFile = gitDir.appendingPathComponent("config")

        guard let configData = try? String(contentsOf: configFile, encoding: .utf8) else {
            return nil
        }

        // Parse git config to find remote origin URL
        let lines = configData.components(separatedBy: .newlines)
        var inOriginSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "[remote \"origin\"]" {
                inOriginSection = true
                continue
            }

            if trimmed.hasPrefix("[") && inOriginSection {
                inOriginSection = false
            }

            if inOriginSection && trimmed.hasPrefix("url = ") {
                return String(trimmed.dropFirst("url = ".count))
            }
        }

        return nil
    }
}

struct ActiveConversationResolver: Sendable {
    private let providers: [any ConversationTranscriptProvider]

    init(providers: [any ConversationTranscriptProvider]) {
        self.providers = providers
    }

    func resolveActiveSession(for projectPath: String) -> TranscriptSession? {
        providers
            .flatMap { $0.sessions(for: projectPath) }
            .max(by: { $0.lastActivity < $1.lastActivity })
    }

    func resolveAllSessions(for context: ProjectContext) -> [TranscriptSession] {
        providers
            .flatMap { $0.sessions(for: context) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    func resolveActiveSession(for context: ProjectContext) -> TranscriptSession? {
        resolveAllSessions(for: context).first
    }
}
```

---

## File: Contextify/Contextify/ContentView.swift

```swift
//
//  ContentView.swift
//  Contextify
//
//  Created by Rob Banagale on 9/13/25.
//

import SwiftUI
import AppKit
import OSLog

import ContextifyCore
private let uiLog = Logger(subsystem: "dev.contextify", category: "UI")

struct ContentView: View {
    @Environment(HUDViewModel.self) private var model
    @Environment(ConversationMonitor.self) private var timeline
    @State private var showToast = false
    @State private var toastText = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                // REMOVED UI (2025-10-02): Contextify file/URL ingestion features
                // Previously here:
                // - urlEntry: TextField + "Ingest" button for URL ingestion
                // - IngestDropZone: Drag-and-drop zone for files
                // - controls: "New Session", "Checkpoint", "Reveal Outputs" buttons
                // - Session label (e.g., "Session-001")
                // - Status display / Last output URL
                //
                // These features created timestamped Markdown artifacts in ~/Contextify/outputs
                // For restoration, see git history or build/notes/archive/2025-10-02-compose-panel.md
                composeSection
            }
            .frame(minWidth: 640)
            .padding(16)

            ConversationTimelineView()
        }
        .background(WindowTitleWriter(title: "Contextify"))
        .overlay(alignment: .top) { toast }
        .onAppear {
            model.updateGitInfo()
            Task { await refreshSession() }
            TimelineIntegration.shared.startMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextifyShowToast)) { notification in
            guard let payload = notification.userInfo?[ToastPayloadKey.message] as? String else { return }
            presentToast(payload)
        }
        .alert("Project Root", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: model.state) { _, newState in
            if case .success(let msg) = newState {
                toastText = msg
                withAnimation { showToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showToast = false }
                }
            }
        }
        .frame(minWidth: 940, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if model.projectRootURL != nil {
                Label(model.projectDisplayName, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Label(model.branchDisplay, systemImage: "arrow.branch")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            } else {
                Button("Set Project Root…") {
                    let ok = pickProjectRoot()
                    uiLog.info("Set Project Root result=\(ok, privacy: .public)")
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("set-project-root")
            }
            Spacer()
        }
    }

    private var composeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Session header
            HStack {
                Text("Send to:")
                    .foregroundStyle(.secondary)
                if let sessionName = model.targetSessionName {
                    Text("✳ \(sessionName)")
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("iTerm2 (not running)")
                        .foregroundStyle(.tertiary)
                }
                Button(action: { Task { await refreshSession() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh iTerm2 session")
                Spacer()
            }
            .font(.subheadline)

            // Text area
            FocusableTextView(text: Binding(
                get: { model.composeText },
                set: { model.composeText = $0 }
            ))
            .frame(minHeight: 120)

            // Send button
            HStack {
                Spacer()
                Button("Send") {
                    Task { await sendToTerminal() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.composeText.isEmpty)
            }
        }
    }

    private var toast: some View {
        Group {
            if showToast {
                Text(toastText)
                    .padding(10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

#Preview { ContentView().environment(HUDViewModel()) }

private extension ContentView {
    @discardableResult
    func pickProjectRoot() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.urls.first {
            let result = model.setProjectRoot(url: url)
            switch result {
            case .success(let root):
                #if DEBUG
                uiLog.info("Set Project Root path=\(root.path, privacy: .public)")
                #else
                uiLog.info("Set Project Root path=\(root.path, privacy: .private)")
                #endif
                return true
            case .failure(let error):
                uiLog.error("Failed to set project root: \(String(describing: error), privacy: .public)")
                return false
            }
        }
        return false
    }

    func refreshSession() async {
        model.targetSessionName = await ITerm2Bridge.getCurrentSessionName()
    }

    func sendToTerminal() async {
        let textToSend = model.composeText
        let currentLine = await TerminalContentReader.shared.captureCurrentLineFast()

        if let currentLine, !currentLine.isEmpty {
            TerminalTextHistory.shared.push(currentLine)
        }

        let result = await ITerm2Bridge.send(text: textToSend, newline: false, mode: .replace(existingLine: currentLine))
        switch result {
        case .success:
            model.lastCapturedTerminalText = textToSend
            model.composeText = ""
            presentToast("Sent to iTerm2 (Cmd+Z to undo)")
            TimelineIntegration.shared.requestManualRefresh(trigger: .hudSend)
        case .failure(let error):
            presentToast("Failed: \(error.localizedDescription)")
        }
    }

    func presentToast(_ message: String) {
        toastText = message
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showToast = false }
        }
    }
}
```

---

**End of Implementation Plan with File Contents**
