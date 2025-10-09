# macOS Window Types in SwiftUI (2025 HIG)

**Date:** 2025-10-09
**Context:** Evaluating window presentation options for Transcript Inventory feature

---

## Overview

This document provides a comprehensive overview of different window presentation types in macOS SwiftUI, aligned with Apple's Human Interface Guidelines (2025). Each presentation type has distinct characteristics, use cases, and user experience implications.

---

## 1. Sheet

```swift
.sheet(isPresented: $showSheet) { ContentView() }
```

### Characteristics
- **Modal presentation** - blocks interaction with parent window
- Slides down from top of parent window
- Has standard sheet appearance with rounded corners
- Automatically dismissed with ESC key
- Cannot be moved or resized independently
- Parent window is dimmed/disabled while sheet is visible

### Best For
Temporary, focused tasks that require completion before returning to main workflow:
- Settings and preferences
- Simple forms requiring user input
- Quick selections or confirmations
- Focused data entry

### HIG Guidance
Use for workflows that should complete before continuing main task. The modal nature signals to users that they should finish the current task before returning to their primary workflow.

### Example Use Cases
- "Save As" dialogs
- Export options configuration
- Simple property inspectors
- Focused editing flows

---

## 2. Full Screen Cover

```swift
.fullScreenCover(isPresented: $showCover) { ContentView() }
```

### Characteristics
- Takes over entire screen
- Completely hides parent window
- More immersive than sheet
- Cannot see parent content
- Modal presentation

### Best For
Immersive experiences requiring full attention:
- Onboarding flows
- Document editing that needs full focus
- Media viewing/editing
- Game-like interfaces

### HIG Guidance
Use sparingly; users prefer working with visible context. Full screen covers remove all spatial context and should only be used when the experience truly benefits from using the entire screen.

### Example Use Cases
- First-run onboarding
- Photo/video editing
- Presentation mode
- Authentication flows

---

## 3. Popover

```swift
.popover(isPresented: $showPopover) { ContentView() }
```

### Characteristics
- Anchored to a specific UI element
- Arrow pointing to anchor point
- Lightweight, dismissible by clicking outside
- Cannot be moved or resized by user
- Automatically positioned to stay on-screen
- Non-modal by default

### Best For
Contextual information and quick actions:
- Inspector panels
- Color pickers
- Quick action menus
- Contextual help
- Auxiliary controls

### HIG Guidance
Use for non-critical, contextual content that supplements the main interface. Popovers should feel lightweight and easily dismissible. Content should be directly related to the element that triggered the popover.

### Example Use Cases
- Text formatting options
- Color/font selection
- Calendar date picker
- Quick file info
- Emoji picker

---

## 4. Window (Recommended for Auxiliary Features)

```swift
// Method 1: WindowGroup (for document-style windows)
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup("Main") { MainView() }
        WindowGroup("Transcripts", id: "transcripts") {
            TranscriptInventoryView()
        }
    }
}

// Method 2: Window (for auxiliary/utility windows)
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup("Main") { MainView() }
        Window("Transcript Inventory", id: "transcript-inventory") {
            TranscriptInventoryView()
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
        .defaultSize(width: 1000, height: 700)
    }
}
```

### Characteristics
- **Independent, concurrent interaction** - can interact with parent and child simultaneously
- Fully movable and resizable (respects minWidth/minHeight)
- Can be minimized, maximized, closed, reopened
- Has own toolbar and title bar
- Appears in Window menu automatically
- Can set keyboard shortcuts to open/focus
- Persists position and size across sessions (automatic state restoration)
- Non-modal by default

### Best For
Auxiliary functionality that complements main workflow:
- **Inspector panels** (your transcript inventory!)
- Tool palettes
- Secondary content users want visible alongside main window
- Reference material
- Debug/diagnostic tools
- Preference windows
- "Utility" windows

### HIG Guidance
- Use for **non-modal, auxiliary functionality**
- Allow users to **work in both windows concurrently**
- Respect system window management behaviors
- Provide keyboard shortcuts for common actions
- Support standard window operations (minimize, maximize, close)
- Let the system handle window stacking, positioning, and restoration

### Example Use Cases
- Xcode Inspector panes
- Preview app sidebar
- Mail message viewer
- Finder info window
- Safari Web Inspector
- **Contextify Transcript Inventory** ✅

### Window vs WindowGroup

**WindowGroup:**
- Can open multiple instances (e.g., multiple document windows)
- Each instance has independent state
- Good for document-based apps
- Example: TextEdit documents, Xcode projects

**Window:**
- Single instance only (reopening focuses existing window)
- Shared state across app
- Good for auxiliary/utility windows
- Example: Preferences, Inspector panels, tool palettes

---

## 5. MenuBarExtra (Menu Bar Item)

```swift
@main
struct MyApp: App {
    var body: some Scene {
        MenuBarExtra("My App", systemImage: "star") {
            MenuView()
        }
    }
}
```

### Characteristics
- Lives in system menu bar
- Can show menu or popover on click
- Always accessible
- Minimal screen real estate
- Can be shown/hidden by user

### Best For
Background apps and always-available functionality:
- Status monitors
- Quick access tools
- Background services
- System utilities

### HIG Guidance
- Keep icon simple and recognizable
- Provide clear menu options
- Consider user's menu bar space (can be crowded)
- Allow user to quit from menu bar

### Example Use Cases
- Calendar/time display
- Network status monitors
- Media playback controls
- Background sync tools
- System utilities (Dropbox, 1Password, etc.)

---

## Modern HIG Principles (2025)

### Modality Should Be Rare
Only use modal presentations (sheets, full screen covers) when you **must** block workflow to:
- Prevent data loss
- Require critical user input
- Complete a focused task before proceeding

### Respect User's Window Management
- Let macOS handle window positioning, sizing, and stacking
- Don't force window positions or sizes
- Support automatic state restoration
- Honor user's space preferences

### Support Concurrent Workflows
- macOS users expect to work in multiple windows simultaneously
- Provide auxiliary windows instead of modals when content is reference material
- Allow drag-and-drop between windows
- Support split view and Stage Manager

### Provide Discoverability
- Window menu integration makes features discoverable
- Keyboard shortcuts improve efficiency
- Standard behaviors reduce learning curve
- Consistent with system conventions

---

## Decision Matrix: Choosing the Right Presentation Type

| Requirement | Sheet | Popover | Window | Full Screen |
|-------------|-------|---------|--------|-------------|
| Must block parent interaction | ✅ | ❌ | ❌ | ✅ |
| Concurrent interaction needed | ❌ | ✅ | ✅ | ❌ |
| Contextual to specific element | ❌ | ✅ | ❌ | ❌ |
| Needs independent window management | ❌ | ❌ | ✅ | ❌ |
| Quick, lightweight interaction | ❌ | ✅ | ❌ | ❌ |
| Reference material | ❌ | ⚠️ | ✅ | ❌ |
| Auxiliary tool/inspector | ❌ | ⚠️ | ✅ | ❌ |
| Focused, immersive experience | ⚠️ | ❌ | ❌ | ✅ |
| Appears in Window menu | ❌ | ❌ | ✅ | ❌ |
| Persistent across sessions | ❌ | ❌ | ✅ | ❌ |
| User can resize/move | ❌ | ❌ | ✅ | ❌ |

✅ = Ideal
⚠️ = Possible but not recommended
❌ = Not supported or inappropriate

---

## Case Study: Contextify Transcript Inventory

### Current Implementation
- **Type:** Sheet (`.sheet(isPresented:)`)
- **Behavior:** Modal presentation, blocks main window interaction
- **Dismissal:** "Done" button or ESC key

### Problems with Sheet Approach
1. ❌ Cannot browse transcripts while watching live timeline updates
2. ❌ Modal blocking interrupts workflow
3. ❌ Cannot compare transcript inventory with main window content
4. ❌ Window state doesn't persist across sessions
5. ❌ Feels cramped for complex, information-rich interface

### Recommendation: Convert to Window
**Why Window is Better:**
1. ✅ **Concurrent interaction** - Users can browse transcripts while watching live timeline
2. ✅ **Reference material** - Transcript inventory is reference content, not a blocking task
3. ✅ **Persistent** - Window persists position/size across sessions
4. ✅ **Full functionality** - Can have complex toolbar, search, multi-pane layout
5. ✅ **Native macOS behavior** - Appears in Window menu, supports standard management
6. ✅ **Better for comparison** - Users can compare transcripts side-by-side with timeline

### Implementation Pattern

```swift
// In ContextifyApp.swift
@main
struct ContextifyApp: App {
    var body: some Scene {
        // Main window
        WindowGroup("Contextify", id: "main") {
            ContentView()
        }

        // Transcript inventory as separate window
        Window("Transcript Inventory", id: "transcript-inventory") {
            TranscriptInventoryWindowView()
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
        .defaultSize(width: 1000, height: 700)
        .defaultPosition(.center)
    }
}
```

### UI Changes for Window Conversion
1. **Remove "Done" button** - Windows have native close button
2. **Enhance toolbar** - Use native window toolbar with full controls
3. **Remove `onDismiss` callback** - Use `@Environment(\.openWindow)` for control
4. **Add menu items** - Window → Show Transcript Inventory
5. **State management** - Use shared observable object between windows
6. **Keyboard shortcuts** - ⌘⌥T to open/focus window

---

## References

- [Apple Human Interface Guidelines - macOS Windows](https://developer.apple.com/design/human-interface-guidelines/windows)
- [SwiftUI Scene API Documentation](https://developer.apple.com/documentation/swiftui/scene)
- [Managing Windows in SwiftUI](https://developer.apple.com/documentation/swiftui/managing-windows-in-swiftui)
- WWDC 2023: "What's new in SwiftUI" (Window management improvements)
- WWDC 2024: "Design for macOS" (Modern window patterns)

---

## Conclusion

Modern macOS app design favors **non-modal, concurrent workflows**. The `Window` scene type is ideal for auxiliary features like inspectors, tool palettes, and reference material that users need alongside their main workflow. Reserve modal presentations (sheets, full screen covers) for truly blocking operations.

For Contextify's Transcript Inventory, converting from a sheet to a window would significantly improve the user experience by allowing concurrent interaction with both the live timeline and the transcript browser.
