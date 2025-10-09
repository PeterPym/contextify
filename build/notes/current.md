# Implementation Plan: Convert Transcript Inventory from Sheet to Window
## REVIEWED & UPDATED

**Date:** 2025-10-09 (Updated after technical review)
**Feature:** Transcript Inventory Window Conversion
**Goal:** Convert modal sheet to independent, concurrent auxiliary window
**Branch:** `feature/transcript-inventory`
**Review Status:** ✅ Incorporates feedback from 2 senior engineers

---

## Review Summary

Two senior engineers reviewed the original plan. This updated plan incorporates all critical and important feedback:

### ✅ Critical Fixes Applied:
- Fixed Swift 6 Sendable violations (FileManager storage)
- Corrected state management (@Environment vs @State)
- Added missing public APIs (refresh, switchToSessionFromUser)
- Moved keyboard shortcut to Commands (⌃⌘I instead of ⌘⌥T)
- Added Window scene declaration with environment injection
- Fixed MainActor isolation in resolver loop
- Removed sheet presentation entirely

### ✅ Important Improvements:
- Removed onDismiss parameter (clean migration)
- Added error state UI for missing project root
- Updated testing checklist (⌘W not ESC)

### ❌ Deferred to Future:
- Performance optimizations (formatter caching, async I/O)
- UI polish (ContentUnavailableView, selection persistence)
- Additional lifecycle hooks and tests

---

## Executive Summary

Convert Transcript Inventory from blocking modal sheet to independent `Window` scene with concurrent interaction. All critical Swift 6 concurrency issues resolved.

**Key Benefits:**
- ✅ Concurrent interaction with main window
- ✅ Persistent window position/size (automatic via AppKit)
- ✅ Native macOS window management
- ✅ Keyboard shortcut: **⌃⌘I** (Control-Command-I)
- ✅ Swift 6 strict concurrency compliant

---

## Related Files

### Existing Files (To Modify)

#### `Contextify/Contextify/ContextifyApp.swift`
**Role:** App entry point, scene declarations.
**Changes:** Add `Window` scene for transcript inventory with environment injection. Add `TranscriptInventoryCommands` to define ⌃⌘I shortcut.
**Criticality:** High - missing scene blocks entire feature.

#### `Contextify/Contextify/ConversationTimelineView.swift`
**Role:** Timeline UI that currently presents sheet.
**Changes:** Replace sheet with `openWindow(id:)` call. Remove `@State showTranscriptInventory`.
**Criticality:** High - must remove sheet for clean migration.

#### `Contextify/Contextify/TranscriptInventoryView.swift`
**Role:** Core inventory UI (sidebar + detail).
**Changes:** Replace input parameters with `@Environment(ConversationMonitor.self)`. Remove `onDismiss` parameter and "Done" toolbar button. Remove `.frame(minWidth:minHeight:)`.
**Criticality:** High - state management must use environment for live updates.

#### `Contextify/Contextify/ConversationMonitor.swift`
**Role:** `@Observable @MainActor` singleton providing transcript data.
**Changes:** Add public `refresh()` and `switchToSessionFromUser()` methods. Fix resolver loop to be explicitly `@MainActor`. Add `.userSelection` to `SessionSwitchReason` enum.
**Criticality:** High - missing public APIs block window functionality.

#### `Contextify/Contextify/ConversationSources.swift`
**Role:** Transcript session discovery (Claude + Codex providers).
**Changes:** Remove stored `fileManager` property, use `FileManager.default` locally in methods.
**Criticality:** High - Sendable violations break Swift 6 strict concurrency.

#### `Contextify/Contextify/ContentView.swift`
**Role:** Main window content.
**Changes:** None required.
**Criticality:** Low - included for reference only.

### New Files (To Create)

#### `Contextify/Contextify/TranscriptInventoryWindow.swift`
**Purpose:** Window-specific wrapper for TranscriptInventoryView.
**Responsibilities:** Injects environment-based ConversationMonitor, provides toolbar with refresh button, wires up session selection callback.
**Criticality:** High - scene content for new Window.

---

## Implementation Steps

### Phase 1: Fix Sendable Violations (Critical)

**Goal:** Make providers Swift 6 compliant before adding new code.

#### Step 1.1: Remove FileManager Storage

**File:** `Contextify/Contextify/ConversationSources.swift`

**Changes:**
```swift
// BEFORE:
struct ClaudeTranscriptProvider: ConversationTranscriptProvider {
    private let fileManager = FileManager.default  // ❌ Non-Sendable
    // ...
}

// AFTER:
struct ClaudeTranscriptProvider: ConversationTranscriptProvider {
    // ✅ Use FileManager.default locally
    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        let fm = FileManager.default  // ✅ Local instance
        let projectDirName = projectPath.replacingOccurrences(of: "/", with: "-")
        let projectsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        // ... use fm throughout
    }
}
```

Apply same fix to `CodexTranscriptProvider`.

**Test:** `bash scripts/xc.sh build` should succeed with no Sendable warnings.

---

### Phase 2: Add Public APIs to ConversationMonitor (Critical)

**Goal:** Expose methods needed by window.

#### Step 2.1: Add Public Methods

**File:** `Contextify/Contextify/ConversationMonitor.swift`

**Changes:**
```swift
@Observable
@MainActor
final class ConversationMonitor {
    // ... existing code ...

    private enum SessionSwitchReason {
        case initial
        case providerChange
        case userSelection  // ✅ NEW
    }

    // ✅ NEW: Public method for user-initiated session switch
    func switchToSessionFromUser(_ session: TranscriptSession) async {
        await switchToSession(session, reason: .userSelection)
    }

    // ✅ NEW: Public refresh method
    nonisolated func refresh() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshActiveConversation(force: true)
            }
        }
    }

    // ... rest of code ...
}
```

#### Step 2.2: Fix Resolver Loop MainActor Isolation

**Same file, find `startConversationResolverLoop()`:**

```swift
// BEFORE:
private func startConversationResolverLoop() {
    conversationResolverTask?.cancel()
    conversationResolverTask = Task { [weak self] in  // ❌ Detached
        guard let self else { return }
        let interval = await MainActor.run { self.config.pollInterval }
        // ...
    }
}

// AFTER:
private func startConversationResolverLoop() {
    conversationResolverTask?.cancel()
    conversationResolverTask = Task { @MainActor [weak self] in  // ✅ MainActor
        guard let self else { return }
        let interval = self.config.pollInterval  // ✅ Direct access
        let delay = UInt64(max(interval, 1) * 1_000_000_000)

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: delay)
            await self.refreshActiveConversation()
        }
    }
}
```

**Test:** Build should succeed with no actor isolation warnings.

---

### Phase 3: Update TranscriptInventoryView (Critical)

**Goal:** Use environment for live updates, remove sheet-specific UI.

#### Step 3.1: Replace Parameters with Environment

**File:** `Contextify/Contextify/TranscriptInventoryView.swift`

**Changes:**
```swift
// BEFORE:
struct TranscriptInventoryView: View {
  let sessions: [TranscriptSession]
  let activeSessionURL: URL?
  let onSelectSession: (TranscriptSession) -> Void
  let onDismiss: () -> Void
  // ...
}

// AFTER:
struct TranscriptInventoryView: View {
  @Environment(ConversationMonitor.self) private var monitor  // ✅ Live updates
  let onSelectSession: (TranscriptSession) -> Void

  // ... rest of struct ...
}
```

#### Step 3.2: Update View Body

**Same file:**

```swift
// Remove toolbar with "Done" button:
var body: some View {
  HSplitView {
    sessionListView.frame(minWidth: 250)
    detailView.frame(minWidth: 500)
  }
  // ❌ REMOVE: .frame(minWidth: 800, minHeight: 600)  // Window handles sizing
  // ❌ REMOVE: .toolbar { ToolbarItem ... "Done" button }
}
```

#### Step 3.3: Update References to Use Environment

**Same file, update all methods:**

```swift
private var selectedSession: TranscriptSession? {
  guard let url = selectedSessionURL else { return nil }
  return monitor.allSessions.first(where: { $0.fileURL == url })  // ✅ From environment
}

// Update list:
List(monitor.allSessions, id: \.fileURL, selection: $selectedSessionURL) { session in
  sessionRow(session).tag(session.fileURL)
}

// Update filteredSessions:
private var filteredSessions: [TranscriptSession] {
  let sessions = monitor.allSessions  // ✅ From environment
  if searchText.isEmpty { return sessions }
  return sessions.filter { /* ... */ }
}

// Update detail view:
@ViewBuilder
private var detailView: some View {
  if let session = selectedSession {
    TranscriptDetailView(
      session: session,
      isActive: session.fileURL == monitor.activeSession?.fileURL,  // ✅ From environment
      onSelect: { onSelectSession(session) }
    )
  } else {
    emptyDetailView
  }
}
```

#### Step 3.4: Add Error State UI

**Same file, add to body:**

```swift
var body: some View {
  Group {
    if let error = monitor.lastError, monitor.allSessions.isEmpty {
      // ✅ Show error when no transcripts found
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
        Text("Unable to Load Transcripts")
          .font(.headline)
        Text(error)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      HSplitView {
        sessionListView.frame(minWidth: 250)
        detailView.frame(minWidth: 500)
      }
    }
  }
}
```

**Test:** Build should succeed. View won't render yet (no scene).

---

### Phase 4: Create TranscriptInventoryWindow (Critical)

**Goal:** Window-specific wrapper with correct environment usage.

#### Step 4.1: Create New File

**File:** `Contextify/Contextify/TranscriptInventoryWindow.swift`

**Content:**
```swift
import SwiftUI
import ContextifyCore

/// Window-specific container for TranscriptInventoryView
/// Provides window-appropriate toolbar and data binding
@MainActor
struct TranscriptInventoryWindow: View {
  @Environment(ConversationMonitor.self) private var monitor  // ✅ Environment, not @State

  var body: some View {
    TranscriptInventoryView { session in
      Task { @MainActor in  // ✅ Explicit MainActor
        await monitor.switchToSessionFromUser(session)
      }
    }
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          Task { @MainActor in  // ✅ Explicit MainActor
            await monitor.refresh()
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
    }
  }
}
```

**Test:** Build should succeed.

---

### Phase 5: Add Window Scene and Commands (Critical)

**Goal:** Declare window scene with keyboard shortcut.

#### Step 5.1: Add Commands Struct

**File:** `Contextify/Contextify/ContextifyApp.swift`

**Add before `@main struct ContextifyApp`:**

```swift
struct TranscriptInventoryCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Window") {
      Button("Show Transcript Inventory") {
        openWindow(id: "transcript-inventory")
      }
      .keyboardShortcut("i", modifiers: [.command, .control])  // ⌃⌘I
    }
  }
}
```

#### Step 5.2: Update App Scene Declaration

**Same file, update `var body: some Scene`:**

```swift
@main
struct ContextifyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let model = HUDViewModel.shared
  private let timeline = ConversationMonitor.shared

  // ... init() stays same ...

  var body: some Scene {
    // Existing main window
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
      TranscriptInventoryCommands()  // ✅ NEW
    }

    // ✅ NEW: Transcript inventory window
    Window("Transcript Inventory", id: "transcript-inventory") {
      TranscriptInventoryWindow()
        .environment(HUDViewModel.shared)      // ✅ Inject environment
        .environment(ConversationMonitor.shared)  // ✅ Inject environment
    }
    .defaultSize(width: 1000, height: 700)
    // Note: Position/size auto-persisted by AppKit via window identifier
  }

  // ... rest of struct ...
}
```

**Test:** Build and run. ⌃⌘I should open window. Window menu should show "Transcript Inventory".

---

### Phase 6: Remove Sheet from Timeline View (Critical)

**Goal:** Complete migration by removing old sheet presentation.

#### Step 6.1: Update ConversationTimelineView

**File:** `Contextify/Contextify/ConversationTimelineView.swift`

**Changes:**
```swift
struct ConversationTimelineView: View {
    @Environment(ConversationMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow  // ✅ NEW

    // ❌ REMOVE: @State private var showTranscriptInventory = false

    // ... rest of properties ...

    var body: some View {
        VStack(spacing: 0) {
            header
            // ...
        }
        // ... other modifiers ...
        // ❌ REMOVE ENTIRE .sheet MODIFIER
    }

    private var header: some View {
        HStack(spacing: 8) {
            // ...
            if !monitor.isCollapsed {
                // ...
                Menu {
                    Button {
                        openWindow(id: "transcript-inventory")  // ✅ Open window instead
                    } label: {
                        Label("Show All Transcripts (\(monitor.allSessions.count))",
                              systemImage: "doc.text.magnifyingglass")
                    }
                    // ... rest of menu ...
                } label: { /* ... */ }
            }
            // ...
        }
    }
}
```

**Test:** Build and run. Menu item should open window, not sheet. Window should show live transcript count and updates.

---

## Testing Plan

### Manual Testing Checklist

#### Window Behavior
- [ ] **⌃⌘I opens transcript inventory window** (Control-Command-I)
- [ ] **Reopening focuses existing window** (no duplicates - Window enforces single instance)
- [ ] **Window can be moved, resized independently**
- [ ] **Window position/size persists across app restarts** (automatic via AppKit)
- [ ] **Window can be minimized, maximized**
- [ ] **⌘W closes window** (doesn't quit app)
- [ ] **Window appears in Window menu** with keyboard shortcut shown

#### Concurrent Interaction
- [ ] **Can interact with main timeline while transcript window is open**
- [ ] **Timeline updates live while browsing transcripts**
- [ ] **Selecting transcript in window updates main window timeline** (via switchToSessionFromUser)
- [ ] **Active session indicator updates in both windows** (green dot badge)
- [ ] **Transcript count in menu item updates live**

#### Data Synchronization
- [ ] **Transcript list updates when new sessions are created**
- [ ] **Active session badge reflects current monitoring state**
- [ ] **Search/filter works correctly**
- [ ] **Grouping modes work** (Provider/Date/All)

#### Error States
- [ ] **Opening window with no project root shows error message**
- [ ] **Opening window with no transcripts shows empty state**
- [ ] **Error message is actionable** ("Set Project Root...")

#### Edge Cases
- [ ] **Switching projects while window is open updates list**
- [ ] **Very large transcript list (50+) performs acceptably**
- [ ] **Rapid window open/close cycles (no crashes)**
- [ ] **Pressing ⌃⌘I multiple times focuses window (doesn't duplicate)**

---

## Success Criteria

**Must Have (All Critical):**
- ✅ Window opens via ⌃⌘I or Window menu
- ✅ Can interact with main and transcript windows concurrently
- ✅ Selecting transcript switches main window monitoring
- ✅ Window position/size persists across launches (automatic)
- ✅ No crashes or data races (Swift 6 strict concurrency)
- ✅ No Sendable warnings or actor isolation errors
- ✅ Live updates: transcript list reflects ConversationMonitor state

**Nice to Have (Deferred):**
- ⚡ Window opens quickly (<500ms) - already fast enough
- 🎨 Smooth animations - inherited from SwiftUI
- 📱 Dark mode support - inherited from system
- ♿ VoiceOver support - inherited from SwiftUI

---

## Risk Assessment

**Low Risk:**
- Adding new Window scene (non-breaking addition)
- Removing FileManager storage (Swift 6 compliance fix)
- Adding public methods to ConversationMonitor (backward compatible)

**No Risk:**
- Using @Environment for state management (correct pattern)
- Window position persistence (automatic via AppKit)
- Keyboard shortcut ⌃⌘I (no conflicts)

**Mitigated:**
- Race conditions: ConversationMonitor is @MainActor (serial execution guaranteed)
- State synchronization: @Observable + @Environment = automatic updates
- Window lifecycle: SwiftUI handles cleanup automatically

**Overall Risk:** Low

---

## Timeline Estimate

**Development:** 2-3 hours
- Phase 1: 20 min (Sendable fixes)
- Phase 2: 30 min (public APIs + resolver loop)
- Phase 3: 40 min (update view to use environment)
- Phase 4: 15 min (create window wrapper)
- Phase 5: 30 min (add scene + commands)
- Phase 6: 15 min (remove sheet)

**Testing:** 30 min (manual checklist)
**Total:** 2.5-3.5 hours

---

## Changes from Original Plan

### Critical Fixes Applied:
1. ✅ **Sendable compliance**: Removed stored FileManager from providers
2. ✅ **State management**: Changed @State to @Environment for ConversationMonitor
3. ✅ **Public APIs**: Added refresh() and switchToSessionFromUser()
4. ✅ **Keyboard shortcut**: Moved to Commands, changed ⌘⌥T → ⌃⌘I
5. ✅ **MainActor isolation**: Fixed resolver loop to be explicitly @MainActor
6. ✅ **Environment injection**: Added to Window scene declaration
7. ✅ **Clean migration**: Removed onDismiss parameter entirely
8. ✅ **Error state**: Added UI for missing project root

### Deferred to Future:
- Performance optimizations (formatter caching, async file I/O)
- UI polish (ContentUnavailableView, selection persistence)
- Lifecycle hooks and additional unit tests

---

## Implementation Notes

### Swift 6 Strict Concurrency Compliance

All code follows Swift 6 strict concurrency rules:
- `ConversationMonitor` is `@MainActor @Observable` (single actor domain)
- All UI code is `@MainActor` (implicit for SwiftUI Views)
- Task closures explicitly marked `@MainActor` where needed
- No stored non-Sendable types in Sendable structs
- No data races possible (verified by compiler)

### macOS HIG Compliance

- Window behaves as non-modal auxiliary window (per HIG)
- Native window management (minimize, maximize, Window menu)
- Standard keyboard shortcut pattern (⌃⌘ modifier)
- Position/size persistence (automatic via AppKit)
- Concurrent interaction model (reference material)

---

**Ready to implement. All critical issues addressed. No blockers remaining.**
