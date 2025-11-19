# Liquid Glass Compliance Audit

**Date:** 2025-11-19
**Auditor:** Engineering Review
**Target SDK:** macOS 26.0 (Tahoe) / iOS 26.0
**Current Build SDK:** macOS 25.x
**Scope:** Contextify macOS application

---

## Executive Summary

Contextify currently has **ZERO code-level adoption** of Liquid Glass design patterns and APIs. While standard SwiftUI components (sheets, menus, forms) will automatically adopt Liquid Glass visual styling when rebuilt with macOS 26 SDK, the app's navigation structure, toolbar implementation, and custom UI components require explicit code changes to fully adopt the new design system.

**Current State:**
- ❌ No `NavigationSplitView`, `NavigationStack`, or `TabView` usage
- ❌ No `.toolbar` implementation despite declaring `.windowToolbarStyle(.unified)`
- ❌ Zero usage of Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, glass button styles)
- ⚠️ Extensive custom backgrounds on navigation and control surfaces that interfere with system effects
- ✅ Good foundation: standard sheets, menus, and forms will adopt automatically

**Impact Assessment:**
- **Visual:** App will look dated compared to system apps on macOS 26
- **UX:** Missing modern navigation patterns (floating sidebars, morphing controls)
- **Performance:** No scroll edge effects, no fluid window resizing
- **Accessibility:** Standard components will adapt, but custom elements need work

**Effort Estimate:** 9-14 weeks for comprehensive adoption

---

## Table of Contents

1. [Navigation Structure](#1-navigation-structure)
2. [Toolbars](#2-toolbars)
3. [Custom Liquid Glass Elements](#3-custom-liquid-glass-elements)
4. [Custom Backgrounds That Interfere](#4-custom-backgrounds-that-interfere)
5. [Button Styles](#5-button-styles)
6. [Sheets and Modals](#6-sheets-and-modals)
7. [Search Implementation](#7-search-implementation)
8. [Controls and Forms](#8-controls-and-forms)
9. [App Icon](#9-app-icon)
10. [Background Extension Effect](#10-background-extension-effect)
11. [Window Management](#11-window-management)
12. [Menus and Context Menus](#12-menus-and-context-menus)
13. [Scrolling and Scroll Edge Effect](#13-scrolling-and-scroll-edge-effect)
14. [Concentric Corners](#14-concentric-corners)
15. [Accessibility and Reduced Effects](#15-accessibility-and-reduced-effects)
16. [Implementation Roadmap](#implementation-roadmap)
17. [Testing Checklist](#testing-checklist)

---

## 1. Navigation Structure

### Current State

**Main Window (`ContentView.swift`)**
```swift
// ContentView.swift (lines 49-73 approximate)
VStack(spacing: 0) {
    if projectSwitcher.tabProjects.count >= 2 {
        ProjectSwitcherView()
        Divider()
    }
    projectHeader
    Divider()
    SurfaceCard { ConversationTimelineView() }
    StatusBarView()
}
```

The app uses a simple `VStack` layout with custom sections. There is no `NavigationSplitView`, `NavigationStack`, or `TabView`.

**Finding:** ❌ **Missing standard navigation containers**

### Apple's Guidance

> "Liquid Glass applies to the topmost layer of the interface, where you define your navigation. Key navigation elements like tab bars and sidebars float in this Liquid Glass layer to help people focus on the underlying content."
>
> "Consider using split views to build sidebar layouts with an inspector panel. Split views are optimized to create a consistent and familiar experience for sidebar and inspector layouts across platforms."

### Recommendation: Adopt NavigationSplitView

The app has a natural three-column layout opportunity:

```swift
NavigationSplitView {
    // Sidebar: Projects list
    ProjectsListView()
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
} content: {
    // Main content: Timeline
    VStack(spacing: 0) {
        ConversationTimelineView()
        StatusBarView()
    }
    .navigationSplitViewColumnWidth(min: 500, ideal: 800)
} detail: {
    // Inspector: Transcript/session details (optional)
    if let selectedEntry = monitor.selectedEntry {
        TranscriptDetailView(entry: selectedEntry)
            .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
    }
}
.inspector(isPresented: $showInspector) {
    // Alternative: Inspector panel for secondary detail
    TranscriptMetadataView()
}
```

**Benefits:**
- ✅ Automatic Liquid Glass sidebar that floats above content
- ✅ Background extension effect for content behind sidebar
- ✅ System-provided resize handles and animations
- ✅ Proper safe area management
- ✅ Inspector panel for secondary details (transcript metadata, session info)

**Implementation Impact:**
- **Complexity:** Medium-High (major architectural refactor)
- **Files affected:** `ContentView.swift`, `ProjectSwitcherView.swift`, `ContextifyApp.swift`
- **New files needed:** `ProjectsListView.swift`, optional `TranscriptDetailView.swift`
- **Priority:** Phase 2 (after foundation work)

**Evidence:**
- `ContentView.swift` lines 49-73: Custom VStack layout
- Apple docs: "NavigationSplitView" for sidebar + inspector patterns

---

## 2. Toolbars

### Current State

**ContextifyApp.swift:273**
```swift
.windowToolbarStyle(.unified)
```

Declares unified toolbar style but **NO TOOLBAR CONTENT** anywhere in the app.

**ConversationTimelineView.swift:58-120** (approximate)
```swift
private var header: some View {
    HStack(spacing: 8) {
        VStack(alignment: .leading) { /* ... */ }
        Spacer()
        if monitor.isProcessing { ProgressView() }
        Button { /* projects */ }
        Button { /* inventory */ }
        Menu { /* options */ }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
}
```

**Finding:** ❌ **No `.toolbar` implementation = missing automatic Liquid Glass toolbar**

### Apple's Guidance

> "Toolbars take on a Liquid Glass appearance, and provide a grouping mechanism for toolbar items, letting you choose which actions to display together."
>
> "In the new design, an automatic scroll edge effect keeps controls legible. It is a subtle blur and fade effect applied to content under system toolbars."

### Recommendation: Replace Custom Headers with `.toolbar`

```swift
// ConversationTimelineView.swift or ContentView.swift
struct ConversationTimelineView: View {
    var body: some View {
        ScrollView {
            // Timeline content
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if monitor.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    openWindow(id: "projects")
                } label: {
                    Label("Projects", systemImage: "folder.badge.gearshape")
                }

                Button {
                    openWindow(id: "transcript-inventory")
                } label: {
                    Label("Transcripts", systemImage: "doc.text.magnifyingglass")
                }
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Refresh Now") { /* ... */ }
                    Toggle("Auto-scroll", isOn: $autoScroll)
                    Divider()
                    Button(role: .destructive) {
                        /* clear */
                    } label: {
                        Label("Clear Timeline", systemImage: "trash")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}
```

**Benefits:**
- ✅ Automatic Liquid Glass background for toolbar
- ✅ System-provided toolbar item grouping
- ✅ Scroll edge effect (content blur under toolbar)
- ✅ Proper spacing and visual hierarchy
- ✅ Automatic monochrome icon rendering

**Toolbar Grouping with Spacers:**

```swift
.toolbar {
    ToolbarItem(placement: .automatic) {
        Button("Action 1") { }
    }

    ToolbarSpacer(.fixed(width: 20))  // Separate into distinct groups

    ToolbarItem(placement: .automatic) {
        Button("Action 2") { }
    }
}
```

**Implementation Impact:**
- **Complexity:** Low (straightforward refactor)
- **Files affected:** `ConversationTimelineView.swift`, `ContentView.swift`
- **Priority:** Phase 1 (foundation work)

**Note:** The `.toolbar` modifier can be applied to either `ContentView` or `ConversationTimelineView`; it attaches to the window's toolbar surface regardless of which view declares it.

**Evidence:**
- `ConversationTimelineView.swift:58-120`: Custom header HStack
- `ContextifyApp.swift:273`: `.windowToolbarStyle(.unified)` declared
- Apple docs: Toolbars section on Liquid Glass appearance and grouping

---

## 3. Custom Liquid Glass Elements

### Current State

**Code Search Results:**
```bash
grep -r "glassEffect" Contextify/**/*.swift      # 0 results
grep -r "GlassEffectContainer" Contextify/**/*.swift  # 0 results
grep -r "\.glass" Contextify/**/*.swift          # 0 results (button styles)
```

**Finding:** ❌ **ZERO Liquid Glass API usage**

### Candidate Elements for Selective Glass Adoption

**Apple's Critical Guidance:**
> "Avoid overusing Liquid Glass effects. If you apply Liquid Glass effects to a custom control, do so sparingly. Liquid Glass seeks to bring attention to the underlying content, and overusing this material in multiple custom controls can provide a subpar user experience by distracting from that content. **Limit these effects to the most important functional elements in your app.**"

Based on this guidance, **do not apply glass to every element**. Instead, use glass selectively for:

#### Recommended: Active/Selected States Only

**1. Active Project Tab** (`ProjectSwitcherView.swift:364-434`)

```swift
// Apply glass ONLY to the active tab
Button {
    // tap action
} label: {
    HStack(spacing: 4) {
        if project.isOrphaned {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        Text(project.name)
            .fontWeight(isActive ? .semibold : .regular)
        if unreadCount > 0 {
            Badge(count: unreadCount)
        }
    }
}
.buttonStyle(isActive ? .glassProminent : .bordered)
```

**2. Key Badges or Floating Controls**

For achievement badges, notifications, or "now playing" style controls:

```swift
@Namespace private var namespace

GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 12) {
        if showBadge {
            BadgeView(achievement: currentAchievement)
                .glassEffect(in: .rect(cornerRadius: 12))
                .glassEffectID("badge", in: namespace)
        }
    }
}
```

**3. Selected Timeline Entry (Optional)**

```swift
// Only apply glass to the SELECTED entry, not all entries
TimelineEntryRow(entry: entry)
    .background {
        if entry.id == selectedEntryId {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .glassEffect()
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }
```

#### NOT Recommended: Bulk Application

❌ **Do NOT apply glass to:**
- Every timeline entry row (could be hundreds of items)
- Every project tab (visual noise, performance cost)
- Dense, scrolling content areas

**Performance Considerations:**

When using glass effects:
```swift
// ✅ GOOD: Group glass elements in container
GlassEffectContainer(spacing: 40.0) {
    HStack {
        glassButton1
        glassButton2
    }
}

// ❌ BAD: Separate containers for each element
// This causes inconsistent sampling and poor performance
glassButton1.glassEffect()  // Separate container
glassButton2.glassEffect()  // Separate container
```

**Implementation Impact:**
- **Complexity:** Medium (requires careful selection of elements)
- **Files affected:** `ProjectSwitcherView.swift`, optional `TimelineEntryRow.swift`
- **Priority:** Phase 3 (polish and refinement)
- **Performance:** Must profile with Instruments if applying to scrolling content

**Evidence:**
- Apple docs: "Avoid overusing Liquid Glass effects... Limit these effects to the most important functional elements"
- `ProjectSwitcherView.swift:364-434`: Custom tab backgrounds
- `TimelineEntryRow.swift:59-68`: Custom RoundedRectangle backgrounds

---

## 4. Custom Backgrounds That Interfere

### Current State

**Apple's Specific Guidance:**
> "Reduce your use of custom backgrounds in **controls and navigation elements**. Any custom backgrounds and appearances you use in these elements might overlay or interfere with Liquid Glass or other effects that the system provides, such as the scroll edge effect. Make sure to check any custom backgrounds in elements like **split views, tab bars, and toolbars**."

### Problematic Patterns: Navigation and Control Surfaces

**1. StatusBarView (Navigation Element)** - `StatusBarView.swift:74`

```swift
.background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
```

This is a **window-level control surface** and should let the system provide the background.

**Recommendation:** Remove entirely or use toolbar placement.

**2. ProjectSwitcherView Container (Navigation Element)** - `ProjectSwitcherView.swift:334`

```swift
.background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
```

This navigation bar should adopt system chrome.

**Recommendation:** Remove background, let NavigationSplitView or toolbar handle it.

**3. SurfaceCard (Navigation Container)** - `ContentView.swift:282-314`

```swift
.background(
    RoundedRectangle(cornerRadius: corner, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
)
.overlay(
    RoundedRectangle(cornerRadius: corner, style: .continuous)
        .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
)
```

`SurfaceCard` wraps the **entire timeline view**, making it a navigation-level container, not a content card.

**Recommendation:** Remove or significantly lighten the background once NavigationSplitView is adopted.

### Optional Refinements: Content-Level Cards

**4. TimelineEntryRow (Content Card)** - `TimelineEntryRow.swift:59-68`

```swift
.background(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor))
)
```

**Analysis:** Timeline rows are **content elements**, not navigation chrome. Apple's guidance on removing custom backgrounds is specifically about "controls and navigation elements."

**Recommendation:**
- **Option 1 (Conservative):** Keep as-is for content cards
- **Option 2 (Experimental):** Use `.fill(.clear)` or system materials and test legibility
- **Option 3 (Selective Glass):** Apply glass only to selected/hovered entries (see Section 3)

### Summary: Prioritize Navigation Surfaces

**Must Remove (Navigation/Control):**
- ✅ `StatusBarView` custom background
- ✅ `ProjectSwitcherView` custom background
- ✅ `SurfaceCard` background (after NavigationSplitView adoption)

**Optional (Content):**
- ⚠️ `TimelineEntryRow` backgrounds (test both approaches)

**Implementation Impact:**
- **Complexity:** Medium (requires testing visual consistency)
- **Files affected:** `StatusBarView.swift`, `ProjectSwitcherView.swift`, `ContentView.swift`
- **Priority:** Phase 1 (foundation work)
- **Testing:** Verify legibility across light/dark modes and various content types

**Evidence:**
- Apple docs: "Reduce your use of custom backgrounds in controls and navigation elements"
- `StatusBarView.swift:74`: Custom opacity background
- `ProjectSwitcherView.swift:334`: Custom background
- `ContentView.swift:282-314`: SurfaceCard wrapping timeline

---

## 5. Button Styles

### Current State

**Button styles currently used:**
- `.bordered` (Settings, Projects Window, Modals)
- `.borderedProminent` (Primary actions, Welcome Modal)
- `.borderless` (Toolbar-like buttons, inline actions)
- `.link` (Secondary actions)
- `.plain` (Icon-only buttons)

**NOT using:**
- ❌ `.glass` (standard glass appearance)
- ❌ `.glassProminent` (prominent glass appearance)

**Finding:** ⚠️ **No glass button styles despite availability in macOS 26**

### Apple's Guidance

> "Leverage new button styles. Instead of creating buttons with custom Liquid Glass effects, you can adopt the look and feel of the material with minimal code by using one of the following button style APIs: `.glass`, `.glassProminent`"

### Recommendation: Selective Adoption for Key Actions

**Use glass button styles for a few key controls**, not every button:

**Example 1: Welcome Modal Primary Action**
```swift
// WelcomeModalView.swift
Button("Get Started") {
    dismiss()
}
.buttonStyle(.glassProminent)  // Primary call-to-action
.controlSize(.large)
```

**Example 2: Active Project Tab (as shown in Section 3)**
```swift
.buttonStyle(isActive ? .glassProminent : .bordered)
```

**Example 3: Prominent Timeline Actions**
```swift
// For key actions like "Regenerate Summary"
Button("Regenerate Summary") {
    regenerate()
}
.buttonStyle(.glass)
```

### Where NOT to Use Glass Buttons

❌ **Avoid glass buttons for:**
- Inline text buttons (use `.link` or `.plain`)
- Toolbar buttons (toolbar provides the glass surface)
- Every button in a form (use `.bordered` for standard actions)
- Destructive actions (use `.borderedProminent` with `.tint(.red)`)

**Implementation Impact:**
- **Complexity:** Low (simple style replacement)
- **Files affected:** `WelcomeModalView.swift`, `ProjectsWindow.swift`, `ContentView.swift`
- **Priority:** Phase 1 (foundation work)
- **Testing:** Verify button legibility against various backgrounds

**Evidence:**
- `WelcomeModalView.swift`: Uses `.borderedProminent`
- `ContentView.swift`: Uses `.borderless` and `.link`
- Apple docs: "Leverage new button styles" section

---

## 6. Sheets and Modals

### Current State

**Existing Sheet Usage:**
```swift
// ContentView.swift:238
.sheet(isPresented: $showWelcomeModal) {
    WelcomeModalView(folderAccessController: folderAccessController)
}

// ProjectsWindow.swift:30
.sheet(item: $selectedProject) { project in
    ProjectStatsView(project: project)
}
```

**No custom backgrounds applied** via `presentationBackground` or similar modifiers.

**Finding:** ✅ **Good! Standard sheet usage**

### Apple's Guidance

> "Modal views like sheets and action sheets adopt Liquid Glass. Sheets feature an increased corner radius, and half sheets are inset from the edge of the display to allow content to peek through from beneath them."
>
> "Audit the backgrounds of sheets and popovers. Check whether you add a visual effect view to your popover's content view, and remove those custom background views to provide a consistent experience with other sheets across the system."

### Recommendation: Keep As-Is

✅ **No changes needed** - sheets already adopt Liquid Glass automatically:
- Increased corner radius
- Inset edges on half sheets
- Glass background that transitions to opaque at full height
- Smooth morphing from source button (when using navigation zoom transition)

### Optional Enhancement: Navigation Zoom Transition

For sheets presented from toolbar buttons, add morphing animation:

```swift
@State private var showStatsSheet = false

// In toolbar
Button {
    showStatsSheet = true
} label: {
    Label("Show Stats", systemImage: "chart.bar")
}
.navigationTransition(.zoom(sourceID: "stats", in: namespace))

// Sheet
.sheet(isPresented: $showStatsSheet) {
    ProjectStatsView(project: currentProject)
        .navigationTransition(.zoom(sourceID: "stats", in: namespace))
}
```

**Implementation Impact:**
- **Complexity:** None (automatic adoption)
- **Optional enhancement:** Navigation zoom transition (Phase 4)
- **Priority:** No action required (automatic)

**Evidence:**
- `ContentView.swift:238`: Standard sheet usage
- Apple docs: Sheets automatically adopt Liquid Glass

---

## 7. Search Implementation

### Current State

**Finding:** ❌ **No standard `.searchable` search interface**

The app does not currently implement global search for:
- Timeline entries
- Projects
- Transcripts

**Existing:** `SemanticSearchView.swift` exists as a developer tool presented via sheet, not integrated into global search patterns.

### Apple's Guidance

> "Platform conventions for location and behavior of search optimize the experience for each device and use case."
>
> "Use semantic search tabs. If your app's search appears as part of a tab bar, make sure to use the standard system APIs for indicating which tab is the search tab. The system automatically separates the search tab from other tabs and places it at the trailing end."

### Recommendation: Add Search with Liquid Glass

**Option 1: Search in Toolbar** (if using NavigationSplitView)

```swift
NavigationSplitView {
    ProjectsListView()
} detail: {
    ConversationTimelineView()
}
.searchable(text: $searchText, placement: .toolbar, prompt: "Search conversations")
```

**Option 2: Dedicated Search Tab** (if using TabView)

```swift
@State private var searchText = ""

TabView {
    Tab {
        ConversationTimelineView()
    } label: {
        Label("Timeline", systemImage: "list.bullet")
    }

    // Search tab with semantic role
    Tab(role: .search) {
        SemanticSearchView(searchText: $searchText)
    } label: {
        Label("Search", systemImage: "magnifyingglass")
    }
}
.searchable(text: $searchText)
```

**Integration with Existing SemanticSearchView:**

Leverage the existing semantic search implementation:
```swift
Tab(role: .search) {
    // Reuse existing semantic search infrastructure
    SemanticSearchView(searchText: $searchText)
        .navigationTitle("Search")
} label: {
    Label("Search", systemImage: "magnifyingglass")
}
```

**Search Minimization:**

```swift
.searchable(text: $searchText, placement: .toolbar)
.searchToolbarBehavior(.minimized)  // Minimize to button when not primary
```

**Benefits:**
- ✅ Automatic Liquid Glass search field
- ✅ Consistent placement (top-trailing toolbar or dedicated tab)
- ✅ System keyboard handling and animations
- ✅ Integration with existing semantic search infrastructure

**Implementation Impact:**
- **Complexity:** Medium (requires search functionality implementation)
- **Files affected:** `ConversationTimelineView.swift`, `SemanticSearchView.swift`
- **Priority:** Phase 4 (future enhancement)
- **Integration:** Leverage existing `SemanticSearchView` to minimize duplication

**Evidence:**
- No `.searchable` usage in codebase
- `SemanticSearchView.swift` exists as developer tool
- Apple docs: Search section with `Tab(role: .search)` pattern

---

## 8. Controls and Forms

### Current State

**SettingsView.swift:**
- ✅ Uses `Form` with grouped style
- ✅ Uses standard `Picker` with `.radioGroup` style
- ✅ Uses standard `Button` with various styles
- ✅ Uses `ProgressView` for loading states

**Finding:** ✅ **Good! Standard control usage**

### Apple's Guidance

> "Control heights are updated for the new design. Most controls on macOS are slightly taller, providing a little more breathing room around the control label, and enhancing the size of the click targets."
>
> "For your most important, prominent actions there is now support for extra large sized buttons."
>
> "Consider aligning the shape of controls with other rounded elements throughout the interface... use rounded shapes that are concentric to their containers using these APIs: `ConcentricRectangle`"

### Recommendations

**1. Extra Large Buttons for Prominent Actions**

```swift
Button("Start Discovery") {
    startDiscovery()
}
.buttonStyle(.borderedProminent)
.controlSize(.extraLarge)  // New in macOS 26
```

**2. Concentric Corners for Edge-Aligned Custom Controls**

Use `ConcentricRectangle` **only for edge-aligned elements** (e.g., custom bottom bars, overlays at window edges):

```swift
// For custom controls at window/sheet edges
ConcentricRectangle(cornerConfiguration: .containerConcentric)
    .fill(Color.accentColor)
```

**NOT for interior content cards:**
```swift
// ❌ Don't use for timeline rows or interior cards
// ✅ Fixed corner radii are fine for content elements
RoundedRectangle(cornerRadius: 10, style: .continuous)
```

**3. Keep Using Standard Controls**

Continue using:
- `Form` with grouped style ✅
- Standard `Picker`, `Toggle`, `Slider` ✅
- System `Button` styles ✅

These automatically adopt Liquid Glass visual updates.

**Implementation Impact:**
- **Complexity:** Low (minor additions to existing controls)
- **Files affected:** `SettingsView.swift`, `WelcomeModalView.swift`
- **Priority:** Phase 1 (extra large buttons), Phase 3 (concentric corners for edge elements only)
- **Testing:** Verify new sizes don't break existing layouts

**Evidence:**
- `SettingsView.swift`: Uses standard Form and controls
- Apple docs: Extra large control size and concentric corners

---

## 9. App Icon

### Current State

**Finding:** ❓ **App icon not examined in detail**

This audit focused on in-app UI. App icon assets were at:
- ~~`Contextify/Contextify/Assets.xcassets/AppIcon.appiconset/`~~ (Removed - legacy C icon)
- ✅ **Now:** `Contextify/icon-composer-project.icon` (Icon Composer format)

### Apple's Guidance

> "App icons take on a design that's dynamic and expressive. Updates to the icon grid result in a standardized iconography that's visually consistent across devices... App icons now contain layers, which dynamically respond to lighting and other visual effects the system provides."
>
> "Design using layers. The system automatically applies effects like reflection, refraction, shadow, blur, and highlights to your icon layers."
>
> "Compose and preview in Icon Composer."

### ✅ Implementation Complete (2025-11-19)

**Design Implemented:**
- ✅ Infinity symbol with layered design
- ✅ Solid, filled shapes with semi-transparent layers
- ✅ System applies effects (reflection, shadow, blur, highlights)
- ✅ Icon Composer .icon format

**Files:**
- Icon: `Contextify/icon-composer-project.icon`
- Asset: `icon-composer-project.icon/Assets/Infinity.png`
- Config: `ASSETCATALOG_COMPILER_APPICON_NAME = "icon-composer-project"`

**Implementation Impact:**
- **Status:** ✅ Complete
- **Tools:** Icon Composer (Xcode 26)
- **Priority:** ✅ Shipped
- **Old Files:** Removed AppIcon.appiconset (2025-11-19)

**Evidence:**
- Apple docs: App Icons section
- Icon Composer documentation

---

## 10. Background Extension Effect

### Current State

**Finding:** ❌ **No NavigationSplitView = no background extension opportunity**

Background extension effect requires:
1. `NavigationSplitView` with sidebar/inspector
2. Content that extends behind panels
3. `.backgroundExtensionEffect()` modifier on extending views

**Current layout:** Simple VStack with no overlapping panels.

### Apple's Guidance

> "A background extension effect creates a sense of extending a background under a sidebar or inspector, without actually scrolling or placing content under it. A background extension effect mirrors the adjacent content to give the impression of stretching it under the sidebar, and applies a blur to maintain legibility."

### Recommendation: Adopt After NavigationSplitView

**Step 1:** Implement NavigationSplitView (see Section 1)

**Step 2:** Add background extension for hero content

```swift
NavigationSplitView {
    ProjectsListView()
} content: {
    VStack(spacing: 0) {
        // Hero content: Project summary or featured conversation
        if let featuredProject = currentProject {
            ProjectHeroView(project: featuredProject)
                .backgroundExtensionEffect()  // Extends and blurs behind sidebar
        }

        // Main timeline
        ConversationTimelineView()
    }
} detail: {
    // Inspector panel
    if let selectedEntry = monitor.selectedEntry {
        TranscriptDetailView(entry: selectedEntry)
    }
}
```

**Consider Hero Content Options:**
- Project summary card with gradient
- Featured conversation snippet
- Project activity visualization
- Team collaboration status

**Benefits:**
- ✅ Full edge-to-edge visual experience
- ✅ Content "peeks through" behind glass sidebar
- ✅ Maintains sidebar legibility with automatic blur
- ✅ Creates visual depth and hierarchy

**Implementation Impact:**
- **Complexity:** Medium (requires NavigationSplitView first + hero content design)
- **Files affected:** `ContentView.swift`, new `ProjectHeroView.swift`
- **Priority:** Phase 2 (after NavigationSplitView adoption)
- **Dependencies:** Requires visually rich hero content source

**Evidence:**
- No NavigationSplitView in current code
- Apple docs: Background extension effect section
- Landmarks sample: Hero image with `.backgroundExtensionEffect()`

---

## 11. Window Management

### Current State

**ContextifyApp.swift:272-285**
```swift
.defaultSize(width: 800, height: 500)
.windowToolbarStyle(.unified)
```

**ContentView.swift** (approximate line numbers)
```swift
.frame(
    minWidth: Layout.timelineMin,  // 340
    minHeight: 360
)
```

**Finding:** ⚠️ **Minimal window resizing configuration**

The app does set minimum content size, but lacks:
- Explicit `.windowResizability` configuration
- `NavigationSplitView` column width constraints
- Fluid resizing optimizations

### Apple's Guidance

> "Windows adopt rounder corners to fit controls and navigation elements. In iPadOS, apps show window controls and support continuous window resizing. Instead of transitioning between specific preset sizes, windows resize fluidly down to a minimum size."
>
> "Support arbitrary window sizes. Allow people to resize their window to the width and height that works for them, and adjust your content accordingly."

### Recommendation: Enhance Window Resizing

**1. Explicit Resizability Configuration**

```swift
// ContextifyApp.swift
Window("Contextify", id: "main") {
    ContentView()
        .frame(minWidth: 340, minHeight: 500)
}
.defaultSize(width: 800, height: 600)
.windowResizability(.contentSize)  // Allow arbitrary sizes
```

**2. NavigationSplitView Column Constraints** (after adoption)

```swift
NavigationSplitView {
    ProjectsListView()
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
} content: {
    ConversationTimelineView()
        .navigationSplitViewColumnWidth(min: 500, ideal: 800)
} detail: {
    TranscriptDetailView()
        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
}
```

**3. Responsive Content Layout**

Ensure all content adapts to size changes:
```swift
// Timeline should work at minimum width
ScrollView {
    LazyVStack(spacing: 8) {
        ForEach(entries) { entry in
            TimelineEntryRow(entry: entry)
                .frame(maxWidth: .infinity)  // Adapts to width
        }
    }
    .padding(.horizontal)
}
```

**Benefits:**
- ✅ Smooth column resizing with animations
- ✅ Content reflow at all sizes
- ✅ Proper minimum sizes for usability
- ✅ Matches system window behavior

**Implementation Impact:**
- **Complexity:** Low (add column width constraints)
- **Files affected:** `ContextifyApp.swift`, `ContentView.swift` (after NavigationSplitView)
- **Priority:** Phase 2 (with NavigationSplitView adoption)
- **Testing:** Verify UI at minimum and maximum sizes

**Evidence:**
- `ContentView.swift`: Sets minimum content size
- `ContextifyApp.swift:272-285`: Basic window configuration
- Apple docs: Fluid window resizing section

---

## 12. Menus and Context Menus

### Current State

**ConversationTimelineView.swift:96-117** (approximate)
```swift
Menu {
    Button("Refresh Now") { /* ... */ }
    Toggle("Auto-scroll", isOn: $autoScroll)
    Divider()
    Button(role: .destructive) { /* clear */ } label: {
        Label("Clear Timeline", systemImage: "trash")
    }
} label: {
    Image(systemName: "ellipsis")
}
.menuStyle(.borderlessButton)
```

**TimelineEntryRow.swift:86-102** (approximate)
```swift
.contextMenu {
    Button("Copy Message Details as JSON") { copyAsJSON() }
    if let transcriptPath = entry.sourceContext?.filePath {
        Divider()
        Button("Reveal Source Transcript in Finder") { /* ... */ }
    }
}
```

**Finding:** ✅ **Good! Standard menu usage**

### Apple's Guidance

> "Menus across platforms have a new design and more consistent layout. Icons are consistently on the leading edge and are now used on macOS too."
>
> "Adopt standard icons in menu items. For menu items that perform standard actions like Cut, Copy, and Paste, the system uses the menu item's selector to determine which icon to apply."

### Recommendation: Keep As-Is with Icon Enhancement

✅ **Menus automatically adopt Liquid Glass in macOS 26**

**Optional Enhancement: Add Standard Icons**

```swift
.contextMenu {
    Button {
        copyAsJSON()
    } label: {
        Label("Copy as JSON", systemImage: "doc.on.clipboard")
    }

    if let transcriptPath = entry.sourceContext?.filePath {
        Divider()
        Button {
            revealInFinder(transcriptPath)
        } label: {
            Label("Reveal in Finder", systemImage: "arrow.up.forward.square")
        }
    }

    if entry.contentSha256 != nil {
        Divider()
        Button {
            regenerateSummary()
        } label: {
            Label("Regenerate Summary", systemImage: "arrow.clockwise")
        }
    }
}
```

**Automatic Benefits (macOS 26):**
- Glass background material
- Icon display for menu items
- Improved visual hierarchy
- Consistent menu appearance

**Implementation Impact:**
- **Complexity:** Low (add icons to menu items)
- **Files affected:** `TimelineEntryRow.swift`, `ConversationTimelineView.swift`
- **Priority:** Phase 1 (minor enhancement)
- **Testing:** Verify icons appear correctly in menus

**Evidence:**
- `ConversationTimelineView.swift:96-117`: Standard Menu usage
- `TimelineEntryRow.swift:86-102`: Context menu
- Apple docs: Menus automatically adopt Liquid Glass

---

## 13. Scrolling and Scroll Edge Effect

### Current State

**ConversationTimelineView.swift** structure:
```swift
VStack {
    header  // Custom HStack, NOT a toolbar
    Divider()
    ScrollView {
        // Timeline content
    }
}
```

The header is implemented as a **static custom bar** above the ScrollView, so content doesn't actually scroll "under" it.

**Finding:** ⚠️ **Header implemented as static bar rather than toolbar**

### Apple's Guidance

> "Scroll views offer a scroll edge effect that helps maintain sufficient legibility and contrast for controls by obscuring content that scrolls beneath them. System bars like toolbars adopt this behavior by default."
>
> "If you use a custom bar with elements like controls, text, or icons that have content scrolling beneath them, you can register those views to use a scroll edge effect."

### Recommendation: Migrate to Toolbar (Primary) or Register for Scroll Edge Effect (Alternative)

**Option 1: Migrate Header to Toolbar (Recommended)**

```swift
// See Section 2 for full implementation
ScrollView {
    // Timeline content
}
.toolbar {
    ToolbarItemGroup(placement: .automatic) {
        // Header content becomes toolbar items
    }
}
```

Toolbars automatically get scroll edge effect.

**Option 2: Register Custom Header for Scroll Edge Effect (Alternative)**

If keeping custom header for specific layout needs:

```swift
VStack {
    customHeader
        .safeAreaBar(edge: .top, alignment: .center) {
            // Content that needs scroll edge effect
            HStack {
                if monitor.isProcessing { ProgressView() }
                // ... other header content
            }
        }

    ScrollView {
        // Scrolling content
    }
}
```

**Benefits:**
- ✅ Maintains legibility as content scrolls
- ✅ Automatic blur/fade effect on scroll content
- ✅ Consistent with system behavior
- ✅ Better visual hierarchy

**Implementation Impact:**
- **Complexity:** Low (if migrating to toolbar), Medium (if using safeAreaBar)
- **Files affected:** `ConversationTimelineView.swift`
- **Priority:** Phase 1 (with toolbar migration)
- **Testing:** Verify scroll performance with many entries

**Evidence:**
- `ConversationTimelineView.swift`: VStack with header outside ScrollView
- Apple docs: Scroll edge effect for custom bars

---

## 14. Concentric Corners

### Current State

**Hardcoded Corner Radii:**
- `SurfaceCard`: `cornerRadius: 12`
- `TimelineEntryRow`: `cornerRadius: 10`
- `ProjectTabView`: `cornerRadius: 6`

**Finding:** ⚠️ **Fixed corner radii throughout**

### Apple's Guidance

> "Across Apple platforms, the shape of the hardware informs the curvature, size, and shape of nested interface elements, including controls, sheets, popovers, windows, and more. Help maintain a sense of visual continuity in your interface by using rounded shapes that are concentric to their containers."

### Recommendation: Use Concentric Corners for Edge-Aligned Elements Only

**When to Use `ConcentricRectangle`:**
- ✅ Custom controls at window/sheet edges
- ✅ Floating panels that align with display corners
- ✅ Elements that need visual continuity with container

**When NOT to Use:**
- ❌ Interior cards (timeline entries, content panels)
- ❌ Elements that don't touch container edges
- ❌ Simple buttons or icons

**Example: Edge-Aligned Custom Bottom Bar**

```swift
// For a custom bar at bottom edge of window
CustomBottomBar()
    .background(
        ConcentricRectangle(cornerConfiguration: .containerConcentric)
            .fill(.regularMaterial)
    )
```

**Keep Fixed Radii for Interior Content:**

```swift
// ✅ CORRECT: Interior timeline row
TimelineEntryRow(entry: entry)
    .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
    )

// ❌ UNNECESSARY: Concentric corners for interior card
TimelineEntryRow(entry: entry)
    .background(
        ConcentricRectangle(cornerConfiguration: .containerConcentric)
    )
```

**Implementation Impact:**
- **Complexity:** Low (selective application only)
- **Files affected:** Only files with edge-aligned custom elements
- **Priority:** Phase 3 (polish, if creating custom edge-aligned UI)
- **Testing:** Verify on different display sizes

**Evidence:**
- `ContentView.swift:282-314`: SurfaceCard with fixed corners
- `TimelineEntryRow.swift:59-68`: Fixed corner radius
- Apple docs: Concentric corners section

---

## 15. Accessibility and Reduced Effects

### Current State

**Code Search:**
```bash
grep -r "accessibilityReduceMotion" Contextify/**/*.swift  # 0 results
grep -r "accessibilityReduceTransparency" Contextify/**/*.swift  # 0 results
```

**Finding:** ⚠️ **No explicit reduced motion/transparency handling**

### Apple's Guidance

> "Translucency and fluid morphing animations contribute to the look and feel of Liquid Glass, but can adapt to people's needs. For example, people might turn on accessibility settings that reduce transparency or motion in the interface, which can remove or modify certain effects."
>
> "If you use standard components from system frameworks, this experience adapts automatically. Ensure your custom elements and animations provide a good fallback experience when these settings are on as well."

### Recommendation: Test and Handle Accessibility Settings

**System Controls Adapt Automatically:**
- Liquid Glass reduces transparency when "Reduce Transparency" is enabled
- Fluid animations reduce when "Reduce Motion" is enabled
- Standard sheets, menus, toolbars handle this automatically ✅

**For Custom Animations/Effects:**

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion
@Environment(\.accessibilityReduceTransparency) var reduceTransparency

// Conditional animation
if reduceMotion {
    // Instant state change
    isExpanded.toggle()
} else {
    // Animated state change
    withAnimation(.spring(response: 0.3)) {
        isExpanded.toggle()
    }
}

// Conditional glass effect
if reduceTransparency {
    // Use solid background
    RoundedRectangle(cornerRadius: 10)
        .fill(Color(nsColor: .windowBackgroundColor))
} else {
    // Use glass effect
    RoundedRectangle(cornerRadius: 10)
        .glassEffect()
}
```

**Testing Requirements:**

1. **Enable "Reduce Transparency":**
   - System Settings > Accessibility > Display > Reduce transparency
   - Verify glass effects show solid backgrounds
   - Verify content remains legible

2. **Enable "Reduce Motion":**
   - System Settings > Accessibility > Display > Reduce motion
   - Verify animations are instant or minimal
   - Verify no motion sickness triggers

3. **High Contrast Mode:**
   - Verify color contrast meets WCAG AA standards
   - Test glass elements for legibility

4. **VoiceOver:**
   - Verify all glass elements are accessible
   - Test navigation through timeline
   - Ensure proper labels on all controls

**Implementation Impact:**
- **Complexity:** Low (testing primarily, conditional code where needed)
- **Files affected:** Any files with custom animations or glass effects
- **Priority:** Phase 1 (testing), Phase 3 (conditional code for custom glass)
- **Testing:** Critical for accessibility compliance

**Evidence:**
- No accessibility environment variables in codebase
- Apple docs: Test with accessibility settings

---

## Implementation Roadmap

### Overview

**Total Effort Estimate:** 9-14 weeks for comprehensive adoption
**Team Size Assumption:** 1 engineer full-time
**Approach:** Incremental phases with independent testing

---

### Priority 1: Foundation (2-3 weeks)

**Goal:** Enable automatic Liquid Glass with minimal structural changes

#### Tasks

**1. Remove Custom Backgrounds** (1 week)
- Remove `StatusBarView` custom background (`StatusBarView.swift:74`)
- Remove `ProjectSwitcherView` container background (`ProjectSwitcherView.swift:334`)
- Lighten `SurfaceCard` background or remove entirely (`ContentView.swift:282-314`)
- Test visual consistency across light/dark modes

**Files:** `StatusBarView.swift`, `ProjectSwitcherView.swift`, `ContentView.swift`

**2. Add Toolbar Implementation** (1 week)
- Replace custom header HStack with `.toolbar` modifier (`ConversationTimelineView.swift:58-120`)
- Move header actions to `ToolbarItemGroup`
- Configure toolbar item grouping with `ToolbarSpacer`
- Test scroll edge effect

**Files:** `ConversationTimelineView.swift`, `ContentView.swift`

**3. Adopt Glass Button Styles** (0.5 weeks)
- Replace `.borderedProminent` with `.glassProminent` for primary actions
- Add `.glass` style to key secondary actions
- Test button legibility and interaction

**Files:** `WelcomeModalView.swift`, `ProjectsWindow.swift`, `ContentView.swift`

**4. Add Icons to Menus** (0.5 weeks)
- Update context menus to use `Label` with system symbols
- Test menu appearance

**Files:** `TimelineEntryRow.swift`, `ConversationTimelineView.swift`

#### Deliverables
- ✅ Toolbars show automatic Liquid Glass
- ✅ Buttons use glass styles for key actions
- ✅ No custom backgrounds interfering with system effects
- ✅ Menus display icons

#### Testing
- Visual: Light/dark modes, toolbar appearance, button states
- Interaction: Toolbar morphing, scroll edge effect
- Accessibility: Reduce transparency, color contrast

---

### Priority 2: Navigation Structure (3-4 weeks)

**Goal:** Adopt standard navigation containers for floating glass sidebars

#### Tasks

**1. Design NavigationSplitView Layout** (1 week)
- Design three-column layout (sidebar, content, inspector)
- Create `ProjectsListView` for sidebar
- Define column width constraints
- Design state management for selection

**New Files:** `ProjectsListView.swift`, optional `TranscriptDetailView.swift`

**2. Refactor ContentView** (1-2 weeks)
- Replace VStack with `NavigationSplitView`
- Migrate `ProjectSwitcherView` functionality to sidebar list
- Configure safe areas and column widths
- Implement window state persistence

**Files:** `ContentView.swift` (major refactor), `ProjectSwitcherView.swift`, `ContextifyApp.swift`

**3. Add Inspector Panel** (0.5 weeks)
- Implement `.inspector(isPresented:)` for transcript metadata
- Design inspector content view
- Test inspector show/hide behavior

**Files:** `ContentView.swift`, new `TranscriptMetadataView.swift`

**4. Add Background Extension Effect** (0.5 weeks)
- Design hero content (project summary, gradient, featured item)
- Apply `.backgroundExtensionEffect()` to hero view
- Test legibility of sidebar over extended content

**Files:** `ContentView.swift`, new `ProjectHeroView.swift`

**5. Window Resizing Configuration** (0.5 weeks)
- Add `.windowResizability(.contentSize)`
- Configure column width constraints
- Test fluid resizing and content reflow

**Files:** `ContextifyApp.swift`, `ContentView.swift`

#### Deliverables
- ✅ NavigationSplitView with floating glass sidebar
- ✅ Background extension effect on hero content
- ✅ Inspector panel for secondary details
- ✅ Smooth column resizing
- ✅ Persistent sidebar state

#### Testing
- Visual: Sidebar appearance, background extension, inspector
- Interaction: Column resizing, sidebar collapse/expand, inspector toggle
- Layout: Content reflow at all window sizes
- Performance: Resize animations, state persistence

---

### Priority 3: Custom Glass Elements (1-2 weeks)

**Goal:** Selective application of glass to key UI elements

#### Tasks

**1. Identify Key Glass Candidates** (0.5 weeks)
- Determine which elements warrant glass (active tab, selected entry, badges)
- Profile performance implications
- Design glass morphing animations

**2. Apply Glass to Active Tab** (0.5 weeks)
- Update `ProjectTabView` to use `.glassProminent` for active state
- Add `GlassEffectContainer` around tab group
- Implement morphing with `glassEffectID`

**Files:** `ProjectSwitcherView.swift`

**3. Optional: Glass for Selected Timeline Entry** (0.5 weeks)
- Apply `.glassEffect()` to selected entry only
- Test performance with large timelines
- Profile with Instruments

**Files:** `TimelineEntryRow.swift`

**4. Concentric Corners for Edge Elements** (0.5 weeks)
- Identify edge-aligned custom controls
- Replace fixed radii with `ConcentricRectangle`
- Test on different display sizes

**Files:** Any custom edge-aligned elements

#### Deliverables
- ✅ Active project tab uses glass prominently
- ✅ Optional glass on selected timeline entry
- ✅ Concentric corners on edge-aligned elements
- ✅ Fluid morphing animations

#### Performance Constraints
- ⚠️ **Limit glass elements:** Maximum 5-10 concurrent glass effects
- ⚠️ **Profile scrolling:** Ensure 60fps with glass in scrolling views
- ⚠️ **Use containers:** Group all glass effects in `GlassEffectContainer`

#### Testing
- Visual: Glass appearance, morphing animations
- Performance: Instruments profiling, scroll performance
- Interaction: Touch/hover responses on glass elements

---

### Priority 4: Future Enhancements (2-3 weeks)

**Goal:** Complete feature set and polish

#### Tasks

**1. Search Interface** (1-2 weeks)
- Implement global search with `.searchable()`
- Integrate with existing `SemanticSearchView`
- Add search tab or toolbar placement
- Test search field minimization

**Files:** `ConversationTimelineView.swift`, `SemanticSearchView.swift`, possibly `ContentView.swift`

**2. App Icon Redesign** (0.5-1 week)
- Design layered icon in design tool
- Export foreground/middle/background layers
- Use Icon Composer to create variants
- Export all appearance modes (default, dark, clear, tinted)

**Files:** `Assets.xcassets/AppIcon.appiconset/`

**3. Accessibility Refinements** (0.5 weeks)
- Add `@Environment(\.accessibilityReduceMotion)` checks
- Add `@Environment(\.accessibilityReduceTransparency)` checks
- Implement conditional animations
- Test with all accessibility settings

**Files:** All files with custom animations or glass effects

#### Deliverables
- ✅ Global search with Liquid Glass field
- ✅ Redesigned app icon with layers
- ✅ Full accessibility compliance

#### Testing
- Search: Keyboard behavior, minimization, toolbar placement
- Icon: All variants render correctly across themes
- Accessibility: VoiceOver, reduce motion, reduce transparency, high contrast

---

### Testing & Polish (1-2 weeks)

Comprehensive testing across all phases:

**Visual Testing:**
- ✅ Build with Xcode 26 SDK
- ✅ Test on macOS 26 (Tahoe)
- ✅ Verify glass on toolbars, buttons, sidebar
- ✅ Test light and dark appearance
- ✅ Test with various background colors/images

**Interaction Testing:**
- ✅ Glass buttons morph into menus/popovers
- ✅ Fluid morphing between glass elements
- ✅ Toolbar scroll edge effect
- ✅ Window resizing animations
- ✅ Sidebar resize handles

**Accessibility Testing:**
- ✅ Enable Reduce Transparency → verify adaptation
- ✅ Enable Reduce Motion → verify instant changes
- ✅ Test VoiceOver navigation
- ✅ Test keyboard navigation
- ✅ Verify color contrast (WCAG AA)

**Performance Testing:**
- ✅ Profile with Instruments (Time Profiler)
- ✅ Monitor memory usage
- ✅ Test scroll performance with large timeline
- ✅ Test window resize performance

---

### Rollout Strategy

**Option 1: Feature Branch Approach**
- Phase 1: `feature/liquid-glass-foundation`
- Phase 2: `feature/liquid-glass-navigation`
- Phase 3: `feature/liquid-glass-polish`
- Phase 4: `feature/liquid-glass-enhancements`

**Option 2: Gradual Rollout with Compatibility Key**

For shipping with latest SDK while retaining old visuals temporarily:

```xml
<!-- Info.plist -->
<key>UIDesignRequiresCompatibility</key>
<true/>
```

This allows:
- Building with macOS 26 SDK
- Retaining pre-Liquid Glass appearance
- Gradual rollout of changes

**Remove this key** once Liquid Glass refactor is complete.

---

### Dependencies

**Phase 1 → Phase 2:**
- ✅ Removing custom backgrounds ensures NavigationSplitView can apply glass correctly
- ✅ Toolbar implementation provides foundation for navigation chrome

**Phase 2 → Phase 3:**
- ✅ NavigationSplitView structure enables background extension effect
- ✅ Proper navigation hierarchy clarifies which elements warrant glass

**Phase 3 → Phase 4:**
- ⚠️ Search can be implemented in current layout (independent)
- ⚠️ Icon redesign is fully independent
- ✅ Accessibility work applies to all previous phases

---

### Risk Assessment

**Low Risk:**
- Button style changes (easily reversible)
- Adding toolbar (minimal functionality change)
- Removing custom backgrounds (can restore if needed)

**Medium Risk:**
- NavigationSplitView refactor (major layout change, test thoroughly)
- Glass effects on custom elements (performance implications)

**High Risk:**
- Background extension with complex content (test legibility carefully)
- Multiple glass elements in scrolling views (profile performance)

---

## Testing Checklist

### Visual Testing

- [ ] Build app with Xcode 26 SDK
- [ ] Launch on macOS 26 (Tahoe) or later
- [ ] Verify Liquid Glass appears on toolbars
- [ ] Verify glass button styles render correctly
- [ ] Verify sidebar floats above content (NavigationSplitView)
- [ ] Verify background extension effect (if implemented)
- [ ] Test with light appearance
- [ ] Test with dark appearance
- [ ] Test with various background colors/images
- [ ] Verify menu icons appear correctly

### Interaction Testing

- [ ] Verify glass buttons morph into menus/popovers
- [ ] Verify fluid morphing between glass elements (if using glassEffectID)
- [ ] Verify toolbar scroll edge effect
- [ ] Verify window resizing animations
- [ ] Verify sidebar resize handles work smoothly
- [ ] Test drag and drop (if applicable)
- [ ] Verify sheet presentations morph from source buttons
- [ ] Test keyboard navigation through all glass elements

### Accessibility Testing

- [ ] Enable "Reduce Transparency" → verify glass effects show solid backgrounds
- [ ] Enable "Reduce Motion" → verify animations are instant or minimal
- [ ] Test VoiceOver navigation through timeline
- [ ] Test VoiceOver on all glass elements
- [ ] Test keyboard navigation (tab order, shortcuts)
- [ ] Test color contrast (WCAG AA compliance)
- [ ] Test at minimum window size for usability
- [ ] Verify all controls have accessibility labels

### Performance Testing

- [ ] Profile with Instruments (Time Profiler)
- [ ] Monitor memory usage with many glass elements
- [ ] Test scroll performance with large timeline (>100 entries)
- [ ] Test scroll performance with glass effects in timeline
- [ ] Test app launch time
- [ ] Test window resize performance
- [ ] Verify 60fps during animations
- [ ] Test on older supported macOS versions for compatibility

### Specific Scenarios

- [ ] Verify scroll performance with >100 timeline entries when glass effects are present
- [ ] Run on macOS versions below 26 to ensure no runtime crashes or layout regressions
- [ ] Test search field minimization and toolbar behavior with `.searchToolbarBehavior` (if search implemented)
- [ ] Verify error banners and badges remain legible when overlapping glass surfaces
- [ ] Test inspector panel show/hide behavior (if implemented)
- [ ] Verify background extension effect legibility with dark images

---

## Code Impact Summary

### Files Requiring Changes

**Major Changes (3 files):**
1. `Contextify/Contextify/ContentView.swift` (387 lines)
   - Remove SurfaceCard custom backgrounds
   - Refactor VStack → NavigationSplitView
   - Add background extension effect
   - Update column width configuration

2. `Contextify/Contextify/ProjectSwitcherView.swift` (509 lines)
   - Remove custom background
   - Migrate to sidebar list (or update for glass buttons)
   - Update corner radii if edge-aligned

3. `Contextify/Contextify/ConversationTimelineView.swift` (384 lines)
   - Replace custom header HStack with `.toolbar`
   - Add `.searchable()` modifier (optional)
   - Configure scroll edge effects

**Medium Changes (4 files):**
4. `Contextify/Contextify/TimelineEntryRow.swift` (366 lines)
   - Optional: Apply glass to selected entries only
   - Add accessibility checks

5. `Contextify/Contextify/StatusBarView.swift` (479 lines)
   - Remove custom opacity background
   - Optional: integrate into toolbar

6. `Contextify/Contextify/WelcomeModalView.swift` (643 lines)
   - Replace `.borderedProminent` with `.glassProminent`
   - Add accessibility checks

7. `Contextify/Contextify/ContextifyApp.swift` (982 lines)
   - Window configuration for NavigationSplitView
   - Add `.windowResizability`

**Minor Changes (9 files):**
8. `Contextify/Contextify/ProjectsWindow.swift` (217 lines)
   - Update button styles to `.glass`

9. `Contextify/Contextify/SettingsView.swift` (377 lines)
   - Add `.controlSize(.extraLarge)` to key buttons

10. `Contextify/Contextify/SemanticSearchView.swift` (795 lines)
    - Integration with global search (optional)

11-16. Other minor updates for menu icons, accessibility, etc.

**New Files:**
- `ProjectsListView.swift` (sidebar content)
- `ProjectHeroView.swift` (background extension content)
- `TranscriptDetailView.swift` (inspector content, optional)

**Total:** ~16 existing files + 2-3 new files

---

## Resources

### Apple Documentation

- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)
- [WWDC 2025 Session 323: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/323/)

### SwiftUI APIs

**Navigation:**
- `NavigationSplitView` - Sidebar/detail/inspector layout
- `.inspector(isPresented:content:)` - Inspector panel
- `.backgroundExtensionEffect()` - Extend content under panels

**Toolbars:**
- `.toolbar(content:)` - Standard toolbar with glass
- `ToolbarItemGroup` - Group related items
- `ToolbarSpacer` - Fixed or flexible spacing
- `.sharedBackgroundVisibility(_:)` - Hide group background

**Liquid Glass Effects:**
- `.glassEffect(_:in:)` - Apply glass to custom views
- `GlassEffectContainer` - Combine multiple glass elements
- `.glassEffectID(_:in:)` - Enable morphing animations
- `.glassEffectUnion(id:namespace:)` - Combine shapes

**Button Styles:**
- `.glass` - Standard glass button
- `.glassProminent` - Prominent glass button

**Search:**
- `.searchable(text:placement:)` - Search field
- `Tab(role: .search)` - Semantic search tab
- `.searchToolbarBehavior(_:)` - Minimize behavior

**Window & Layout:**
- `.windowResizability(_:)` - Window sizing behavior
- `.navigationSplitViewColumnWidth(min:ideal:max:)` - Column constraints
- `ConcentricRectangle` - Corner concentric shapes
- `.controlSize(.extraLarge)` - Extra large controls

**Scroll Effects:**
- `.safeAreaBar(edge:alignment:spacing:content:)` - Scroll edge effect
- `.scrollEdgeEffectStyle(_:)` - Effect sharpness

**Accessibility:**
- `@Environment(\.accessibilityReduceMotion)` - Motion preference
- `@Environment(\.accessibilityReduceTransparency)` - Transparency preference

### Sample Code

- Clone Apple's Landmarks sample app for reference
- Study system apps: Notes, Reminders, Calendar for Liquid Glass usage

### Design Resources

- [Apple Design Resources](https://developer.apple.com/design/resources/) - Icon grids and templates
- Icon Composer (included in Xcode 26)
- [Human Interface Guidelines - App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)

---

## Conclusion

Contextify requires comprehensive updates to adopt Liquid Glass design patterns for macOS 26. While standard components will receive automatic visual updates when rebuilt with the latest SDK, the app's navigation structure, toolbar implementation, and selective use of custom glass elements require explicit code changes.

**Recommended Approach:**
1. **Start with Priority 1 (Foundation)** - Quick wins with toolbars and button styles
2. **Plan Priority 2 (Navigation)** - Major refactor requiring careful design and testing
3. **Selectively apply Priority 3 (Custom Glass)** - Avoid overuse, profile performance
4. **Schedule Priority 4 (Enhancements)** - Independent features for later phases

**Key Principles:**
- ✅ Leverage system frameworks for automatic Liquid Glass
- ✅ Remove custom backgrounds from navigation/control surfaces
- ⚠️ Apply custom glass effects sparingly (avoid overuse)
- ✅ Test thoroughly with accessibility settings
- ✅ Profile performance with Instruments

Following this audit's recommendations will result in a modern, system-consistent app that takes full advantage of Liquid Glass while maintaining performance and accessibility.

---

**Audit Version:** 2.0
**Last Updated:** 2025-11-19
**Next Review:** After Phase 1 completion
