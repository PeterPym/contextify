# SwiftUI Architecture Patterns

**Last Updated:** 2026-01-03
**Status:** ✅ Active
**Audience:** Developers working on Contextify's SwiftUI views

---

## Table of Contents

1. [Overview](#overview)
2. [State Management Patterns](#state-management-patterns)
3. [Observable vs StateObject vs State](#observable-vs-stateobject-vs-state)
4. [View Composition](#view-composition)
5. [Environment Injection](#environment-injection)
6. [MainActor Usage](#mainactor-usage)
7. [Observation Patterns](#observation-patterns)
8. [View Lifecycle](#view-lifecycle)
9. [Performance Optimization](#performance-optimization)
10. [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
11. [Migration from StateObject to Observable](#migration-from-stateobject-to-observable)
12. [Platform Quirks and Workarounds](#platform-quirks-and-workarounds)
13. [macOS 15 (Sequoia) Quirks](#macos-15-sequoia-quirks)
14. [Search Field Conventions](#search-field-conventions)
15. [Custom Keyboard Navigation (Tab/Shift+Tab/Enter)](#custom-keyboard-navigation-tabshift-tabenter)

---

## Overview

### Purpose

This document codifies the SwiftUI architecture patterns used in Contextify, helping developers maintain consistency and understand when to use each state management approach.

### Design Philosophy

**Core Principles:**
1. **@Observable for shared state** - Use Swift's new Observation framework for app-wide state
2. **@Environment for dependency injection** - Pass state down the view hierarchy
3. **@State for local state** - Keep view-specific state private to the view
4. **@MainActor for UI code** - All views and view models run on main thread
5. **Single source of truth** - Each piece of state has one owner

### Framework Version

- **Swift:** 6.0 (strict concurrency)
- **SwiftUI:** macOS 14+ (Sonoma)
- **Observation:** Available (iOS 17+, macOS 14+)

---

## State Management Patterns

### Pattern Summary

| Pattern | Use Case | Ownership | Lifecycle |
|---------|----------|-----------|-----------|
| `@Observable` class | Shared app state | Singleton or environment | App lifetime |
| `@State` | Local view state | View | View lifetime |
| `@Environment` | Dependency injection | Parent provides | Inherited |
| `@StateObject` (legacy) | Owned view model | View | View lifetime |
| Actor | Background processing | Service/coordinator | App lifetime |

### Architecture Diagram

```
ContextifyApp (root)
├─ @Environment(HUDViewModel.self)         [Singleton, @Observable, @MainActor]
├─ @Environment(ConversationMonitor.self)  [Singleton, @Observable, @MainActor]
├─ @Environment(ProjectSwitcherState.self) [Singleton, @Observable, @MainActor]
├─ @Environment(ProjectsViewModel.self)    [Created on demand, @Observable, @MainActor]
└─ @Environment(DeveloperMode.self)        [Singleton, @Observable, @MainActor]
    │
    └─ ContentView
        ├─ @Environment (inherits all above)
        ├─ @State private var showToast: Bool             [Local state]
        ├─ @State private var toastText: String           [Local state]
        └─ @State private var activeSheet: ActiveSheet?   [Local state]
            │
            ├─ ProjectSwitcherView
            │   └─ Uses @Environment(ProjectSwitcherState.self)
            │
            ├─ ConversationTimelineView
            │   └─ Uses @Environment(ConversationMonitor.self)
            │
            └─ StatusBarView
                └─ Uses @Environment(StatusBarViewModel.self)
```

---

## Observable vs StateObject vs State

### When to Use @Observable

**Use @Observable for:**
- ✅ Shared state accessed by multiple views
- ✅ App-wide singletons (ConversationMonitor, HUDViewModel)
- ✅ Complex business logic with multiple @Published properties
- ✅ State that needs to be injected via @Environment

**Example:**

```swift
@MainActor
@Observable
public final class ProjectSwitcherState {
  // Shared instance
  public static let shared = ProjectSwitcherState()

  // Observable properties (no @Published needed)
  private(set) var allProjects: [ProjectInfo] = []
  private(set) var tabProjects: [ProjectInfo] = []
  private(set) var activeProjectId: String?
  private(set) var unreadCounts: [String: Int] = [:]

  // Tasks excluded from observation (@ObservationIgnored)
  @ObservationIgnored private var projectObservationTask: Task<Void, Never>?
  @ObservationIgnored private var ingestionCompleteTask: Task<Void, Never>?

  private init() {
    // Lazy initialization
  }

  public func start(orchestrator: TranscriptOrchestrator) {
    self.orchestrator = orchestrator
    startObservingProjects()
  }
}
```

**File:** `Contextify/Contextify/ProjectSwitcherState.swift:29-31`

**Key Features:**
- `@Observable` macro automatically tracks property changes
- No `@Published` needed (Observation framework handles it)
- Use `@ObservationIgnored` for properties that shouldn't trigger updates
- `private(set)` for read-only public access

### When to Use @State

**Use @State for:**
- ✅ View-local state (toggles, text fields, selection)
- ✅ Temporary UI state (active sheet, hover state)
- ✅ State that doesn't need to be shared
- ✅ Simple value types (Bool, String, Int, enum)

**Example:**

```swift
struct ContentView: View {
  @Environment(HUDViewModel.self) private var model
  @Environment(ConversationMonitor.self) private var timeline

  // Local view state
  @State private var showToast = false
  @State private var toastText = ""
  @State private var toastDismissTask: Task<Void, Never>?
  @State private var activeSheet: ActiveSheet?

  var body: some View {
    ZStack {
      // ... main content
    }
    .overlay(alignment: .top) { toast }
    .sheet(item: $activeSheet) { sheet in
      // Present sheet based on activeSheet
    }
  }

  private func showTemporaryToast(_ message: String, duration: TimeInterval = 2.0) {
    toastDismissTask?.cancel()
    toastText = message
    showToast = true

    toastDismissTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(duration))
      showToast = false
    }
  }
}
```

**File:** `Contextify/Contextify/ContentView.swift:41-44`

**Key Features:**
- `@State` creates a source of truth owned by the view
- `private` access control keeps state encapsulated
- SwiftUI automatically updates view when @State changes
- Can pass bindings (`$showToast`) to child views

### When to Use @StateObject (Legacy)

**DO NOT USE @StateObject in new code.**

Contextify has migrated to `@Observable`. `@StateObject` was the pre-iOS 17 pattern and is now considered legacy.

**Migration Note:**
```swift
// ❌ OLD (pre-iOS 17)
@StateObject private var viewModel = MyViewModel()

// ✅ NEW (iOS 17+)
@State private var viewModel = MyViewModel()
// OR inject via @Environment for shared state
```

**Reference:** See [Migration from StateObject to Observable](#migration-from-stateobject-to-observable)

### When to Use @Environment

**Use @Environment for:**
- ✅ Dependency injection down the view hierarchy
- ✅ Accessing shared @Observable state
- ✅ Avoiding prop drilling (passing props through many layers)
- ✅ SwiftUI environment values (\.colorScheme, \.openWindow, etc.)

**Example:**

```swift
struct ContentView: View {
  // Inject shared state via @Environment
  @Environment(HUDViewModel.self) private var model
  @Environment(ConversationMonitor.self) private var timeline
  @Environment(DeveloperMode.self) private var devMode
  @Environment(ProjectSwitcherState.self) private var projectSwitcher
  @Environment(ProjectsViewModel.self) private var projectsVM

  var body: some View {
    VStack {
      // Child views automatically inherit @Environment values
      ProjectSwitcherView()
      ConversationTimelineView()
      StatusBarView()
    }
  }
}
```

**File:** `Contextify/Contextify/ContentView.swift:33-40`

**Providing @Environment values:**

```swift
@main
struct ContextifyApp: App {
  // Create singletons
  @State private var hudViewModel = HUDViewModel()
  private let conversationMonitor = ConversationMonitor.shared
  private let projectSwitcher = ProjectSwitcherState.shared
  @State private var projectsViewModel: ProjectsViewModel?

  var body: some Scene {
    WindowGroup {
      if let projectsViewModel {
        ContentView()
          .environment(hudViewModel)
          .environment(conversationMonitor)
          .environment(projectSwitcher)
          .environment(projectsViewModel)
          .environment(DeveloperMode.shared)
      } else {
        WelcomeModalView(onDismiss: handleWelcomeModalDismiss)
      }
    }
  }
}
```

**File:** `Contextify/Contextify/ContextifyApp.swift` (pattern)

---

## View Composition

### View Decomposition Strategy

**Rule:** Keep views small (<300 lines). Extract subviews for:
1. Reusable components
2. Complex layouts
3. Conditional rendering
4. Performance optimization (reduce body re-evaluation)

### Computed Properties for Subviews

**Pattern:**

```swift
struct ContentView: View {
  @Environment(ProjectSwitcherState.self) private var projectSwitcher

  var body: some View {
    VStack(spacing: 0) {
      if projectSwitcher.tabProjects.count >= 2 {
        ProjectSwitcherView()
        Divider()
      }

      projectHeader
      Divider()

      ConversationTimelineView()
      StatusBarView()
    }
  }

  // Extract complex layouts into computed properties
  @ViewBuilder
  private var projectHeader: some View {
    HStack {
      Text(projectSwitcher.activeProjectId ?? "No Project")
        .font(.headline)
      Spacer()
    }
    .padding()
  }
}
```

**Benefits:**
- Keeps `body` readable
- Isolates complex logic
- Makes intent clear with descriptive names

### Standalone Subviews

**Pattern:**

```swift
// Reusable component extracted to separate file
struct ProjectRowView: View {
  let project: ProjectInfo
  let isActive: Bool
  let unreadCount: Int

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(project.name)
          .font(.headline)
        Text(project.rootPath)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      if unreadCount > 0 {
        Badge(count: unreadCount)
      }
    }
    .padding(.horizontal)
    .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
  }
}
```

**File:** `Contextify/Contextify/ProjectRowView.swift` (example pattern)

**When to Extract:**
- Component used in multiple places
- Component >100 lines
- Component has distinct responsibility
- Component needs isolated state

### ViewBuilder Pattern

**Use @ViewBuilder for:**
- Conditional view construction
- View factories
- Computed view properties

**Example:**

```swift
@ViewBuilder
private var discoveryOverlay: some View {
  if StartupCoordinator.shared.current == nil, projectsVM.isDiscovering {
    ZStack {
      Color.black.opacity(0.5)
        .edgesIgnoringSafeArea(.all)

      VStack(spacing: 16) {
        ProgressView()
          .scaleEffect(1.5)
        Text("Discovering projects...")
          .font(.headline)
      }
      .padding()
      .background(Color(.windowBackgroundColor))
      .cornerRadius(12)
    }
  }
}
```

**File:** `Contextify/Contextify/ContentView.swift:77-81` (pattern)

---

## Environment Injection

### Singleton Pattern

**Pattern for app-wide state:**

```swift
@MainActor
@Observable
public final class ConversationMonitor {
  // Shared singleton
  public static let shared = ConversationMonitor()

  // Private init prevents external instantiation
  private init() {
    // Initialize state
  }
}

// Usage in app root:
@main
struct ContextifyApp: App {
  private let conversationMonitor = ConversationMonitor.shared

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(conversationMonitor)
    }
  }
}

// Usage in views:
struct MyView: View {
  @Environment(ConversationMonitor.self) private var timeline

  var body: some View {
    Text("Entries: \(timeline.entries.count)")
  }
}
```

**Files:**
- `Contextify/Contextify/ConversationMonitor.swift:140-141`
- `Contextify/Contextify/ProjectSwitcherState.swift:29-31`

### On-Demand Creation Pattern

**Pattern for contextual state:**

```swift
@main
struct ContextifyApp: App {
  // Created on demand after project discovery
  @State private var projectsViewModel: ProjectsViewModel?

  var body: some Scene {
    WindowGroup {
      if let projectsViewModel {
        ContentView()
          .environment(projectsViewModel)
      } else {
        WelcomeModalView(onDismiss: handleWelcomeModalDismiss)
      }
    }
  }

  private func handleWelcomeModalDismiss(result: WelcomeResult) {
    switch result {
    case .projectSelected(let projectId):
      // Create ProjectsViewModel now that we have a project
      self.projectsViewModel = ProjectsViewModel()
    case .cancelled:
      NSApplication.shared.terminate(nil)
    }
  }
}
```

**Pattern:** Conditional environment provision based on app state.

### Environment Access Patterns

**Safe Access (non-optional):**

```swift
@Environment(HUDViewModel.self) private var model

// Safe: guaranteed to exist by parent
var body: some View {
  Text(model.currentProject)
}
```

**Conditional Access (optional):**

```swift
@Environment(ProjectsViewModel.self) private var projectsVM?

var body: some View {
  if let projectsVM {
    Text("Projects: \(projectsVM.projects.count)")
  } else {
    Text("No projects loaded")
  }
}
```

**Rule:** Only use optional @Environment if the value may not be provided.

---

## MainActor Usage

### All UI Code on MainActor

**Rule:** All SwiftUI views and view models MUST be @MainActor.

**Why:**
- SwiftUI views can only be updated on the main thread
- Prevents data races in UI state
- Enforced by Swift 6 strict concurrency

**Pattern:**

```swift
@MainActor
@Observable
public final class StatusBarViewModel {
  private(set) var connectionStatus: String = "Disconnected"
  private(set) var lastUpdate: Date?

  public func updateStatus(_ status: String) {
    // Already on main thread, safe to update UI state
    self.connectionStatus = status
    self.lastUpdate = Date()
  }
}
```

**File:** `Contextify/Contextify/StatusBarViewModel.swift:13-14`

### Background Work from UI Code

**Pattern for offloading work:**

```swift
@MainActor
struct ContentView: View {
  @State private var entries: [Entry] = []

  var body: some View {
    List(entries) { entry in
      Text(entry.content)
    }
    .task {
      // Background work
      let result = await Task.detached {
        // Off main thread
        try! database.fetchEntries()
      }.value

      // Back on main thread
      self.entries = result
    }
  }
}
```

**Pattern:**
1. Use `Task.detached` for CPU-intensive or blocking I/O
2. Capture @MainActor properties in non-isolated closure
3. Await result and update UI on main thread

### MainActor Isolation Warnings

**Common Warning:**

```
Main actor-isolated property 'entries' can not be mutated from a non-isolated context
```

**Fix:**

```swift
// ❌ BAD: Trying to update @MainActor property from background
Task.detached {
  let entries = try! database.fetchEntries()
  self.entries = entries  // ERROR: not on main thread
}

// ✅ GOOD: Explicitly switch to main thread
Task.detached {
  let entries = try! database.fetchEntries()
  await MainActor.run {
    self.entries = entries
  }
}

// ✅ BETTER: Use .task modifier (automatically MainActor)
.task {
  let entries = await Task.detached {
    try! database.fetchEntries()
  }.value
  self.entries = entries  // Safe: .task is @MainActor
}
```

---

## Observation Patterns

### @ObservationIgnored

**Use @ObservationIgnored for:**
- Task handles (don't trigger updates)
- Cached computed values (avoid infinite loops)
- Internal implementation details

**Example:**

```swift
@MainActor
@Observable
public final class ProjectSwitcherState {
  // Observed properties
  private(set) var allProjects: [ProjectInfo] = []
  private(set) var activeProjectId: String?

  // NOT observed (tasks, caches, internal state)
  @ObservationIgnored private var projectObservationTask: Task<Void, Never>?
  @ObservationIgnored private var ingestionCompleteTask: Task<Void, Never>?
  @ObservationIgnored private var isStarted: Bool = false
  @ObservationIgnored private var switchInProgress: String?
}
```

**File:** `Contextify/Contextify/ProjectSwitcherState.swift:55-73`

**Rule:** Mark all `Task` properties with `@ObservationIgnored` to prevent observation overhead.

### Private(set) for Read-Only State

**Pattern:**

```swift
@MainActor
@Observable
public final class ProjectSwitcherState {
  // Public read-only, private write
  private(set) var allProjects: [ProjectInfo] = []
  private(set) var tabProjects: [ProjectInfo] = []

  // Public mutating method
  public func refreshProjects() async {
    let projects = await orchestrator.listProjects()
    self.allProjects = projects  // Private write
  }
}
```

**Benefits:**
- Encapsulation (state can only be modified internally)
- Clear API (read-only from outside)
- Prevents accidental mutations

### Observation Performance

**Heavy Observation Cost:**

When an @Observable property changes, ALL views that reference that object re-evaluate their body (even if they don't access the changed property).

**Optimization:**

```swift
// ❌ BAD: Observes entire ConversationMonitor
@Environment(ConversationMonitor.self) private var timeline

var body: some View {
  Text("Count: \(timeline.entries.count)")
  // Re-renders when ANY timeline property changes (isLoading, error, etc.)
}

// ✅ BETTER: Extract only needed data
@Environment(ConversationMonitor.self) private var timeline

var body: some View {
  let entryCount = timeline.entries.count
  return Text("Count: \(entryCount)")
  // Still observes all changes, but minimizes body complexity
}

// ✅ BEST: Split into smaller @Observable objects
@Environment(TimelineCounter.self) private var counter

var body: some View {
  Text("Count: \(counter.count)")
  // Only re-renders when counter.count changes
}
```

**Recommendation:** Split large @Observable objects (like ConversationMonitor) into focused, single-responsibility objects.

**Reference:** `build/docs/architecture/architecture-refactoring-analysis.md` (ConversationMonitor god object, ~2900 lines, partially refactored)

---

## View Lifecycle

### Initialization

**Pattern:**

```swift
struct MyView: View {
  @Environment(HUDViewModel.self) private var model
  @State private var isLoaded = false

  var body: some View {
    VStack {
      if isLoaded {
        ContentView()
      } else {
        ProgressView()
      }
    }
    .task {
      // Async initialization
      await model.load()
      isLoaded = true
    }
  }
}
```

**Rules:**
- Use `.task` for async initialization (auto-cancels on view disappear)
- Use `.onAppear` for synchronous setup (called every time view appears)
- Never do heavy work in `init()` (blocks view construction)

### Cleanup

**Pattern:**

```swift
struct MyView: View {
  @Environment(MonitorService.self) private var monitor
  @State private var observationTask: Task<Void, Never>?

  var body: some View {
    Text("Monitoring...")
      .task {
        // Start monitoring
        observationTask = Task {
          for await event in monitor.events() {
            handleEvent(event)
          }
        }
      }
      .onDisappear {
        // Clean up
        observationTask?.cancel()
        observationTask = nil
      }
  }
}
```

**Rules:**
- `.task` auto-cancels when view disappears (preferred)
- Use `.onDisappear` for manual cleanup if needed
- Cancel all async work to prevent memory leaks

### Task Lifecycle

**Pattern:**

```swift
struct ContentView: View {
  var body: some View {
    Text("Hello")
      .task(id: projectId) {
        // Re-runs when projectId changes
        await loadProject(projectId)
      }
  }
}
```

**Rule:** Use `task(id:)` to re-run task when a value changes.

---

## Performance Optimization

### Avoid Expensive Computations in Body

**❌ BAD:**

```swift
var body: some View {
  let sortedProjects = projects.sorted { $0.name < $1.name }  // Expensive!
  return List(sortedProjects) { project in
    Text(project.name)
  }
}
```

**✅ GOOD:**

```swift
@MainActor
@Observable
class ViewModel {
  var projects: [Project] = []

  // Cached computed property
  var sortedProjects: [Project] {
    projects.sorted { $0.name < $1.name }
  }
}

struct MyView: View {
  @Environment(ViewModel.self) private var viewModel

  var body: some View {
    List(viewModel.sortedProjects) { project in
      Text(project.name)
    }
  }
}
```

**Rule:** Pre-compute expensive values in view model, not in view body.

### Equatable for Value Types

**Pattern:**

```swift
struct ProjectInfo: Identifiable, Sendable, Hashable {
  public let id: String
  public let name: String
  public let rootPath: String
  public let transcriptCount: Int

  // Automatic Equatable from Hashable
  // SwiftUI can diff efficiently
}
```

**File:** `Contextify/Contextify/ProjectSwitcherState.swift:9-14`

**Rule:** Make data models `Equatable` or `Hashable` so SwiftUI can minimize re-renders.

### View Identity

**Pattern:**

```swift
List(projects) { project in
  ProjectRowView(project: project)
    .id(project.id)  // Stable identity
}
```

**Rule:** Use stable `.id()` for list items to prevent unnecessary re-renders.

### Lazy Loading

**Pattern:**

```swift
ScrollView {
  LazyVStack {
    ForEach(entries) { entry in
      EntryRow(entry: entry)
    }
  }
}
```

**Rule:** Use `LazyVStack`/`LazyHStack` for large lists (only renders visible items).

---

## Anti-Patterns to Avoid

### 1. Blocking Main Thread

**❌ ANTI-PATTERN:**

```swift
@MainActor
func loadData() {
  // Blocks UI for entire duration
  let data = try! String(contentsOf: fileURL)
  self.content = data
}
```

**✅ CORRECT:**

```swift
@MainActor
func loadData() async {
  let data = await Task.detached {
    try! String(contentsOf: fileURL)
  }.value
  self.content = data
}
```

### 2. Mutating State During View Update

**❌ ANTI-PATTERN:**

```swift
var body: some View {
  let _ = {
    // NEVER mutate state in body!
    self.count += 1
  }()
  return Text("Count: \(count)")
}
```

**✅ CORRECT:**

```swift
var body: some View {
  Text("Count: \(count)")
    .onAppear {
      count += 1
    }
}
```

### 3. Unnecessary @ObservationIgnored

**❌ ANTI-PATTERN:**

```swift
@Observable
class ViewModel {
  // This defeats the purpose of @Observable!
  @ObservationIgnored var projects: [Project] = []
}
```

**✅ CORRECT:**

```swift
@Observable
class ViewModel {
  // Let Observation track this
  var projects: [Project] = []
}
```

### 4. God Objects

**❌ ANTI-PATTERN:**

```swift
@Observable
class ConversationMonitor {
  // ~2900 lines with 10+ responsibilities (Phase 1–3 extractions complete)
  var entries: [Entry]
  var isLoading: Bool
  var error: String?
  var cache: TimelineCache
  var llmQueue: LLMQueue
  // ... 10 more properties
}
```

**✅ CORRECT:**

```swift
// Split into focused objects
@Observable
class TimelineState {
  var entries: [Entry]
  var isLoading: Bool
}

@Observable
class TimelineCache {
  var cachedSummaries: [String: String]
}

// etc.
```

**Reference:** `build/docs/architecture/architecture-refactoring-analysis.md:880` (ConversationMonitor refactoring)

### 5. Overusing @State

**❌ ANTI-PATTERN:**

```swift
struct ParentView: View {
  @State private var projects: [Project] = []

  var body: some View {
    ChildView(projects: $projects)  // Prop drilling
  }
}

struct ChildView: View {
  @Binding var projects: [Project]

  var body: some View {
    GrandchildView(projects: $projects)  // More prop drilling
  }
}
```

**✅ CORRECT:**

```swift
@Observable
class ProjectStore {
  var projects: [Project] = []
}

struct ParentView: View {
  @Environment(ProjectStore.self) private var store

  var body: some View {
    ChildView()  // No props
  }
}

struct ChildView: View {
  @Environment(ProjectStore.self) private var store

  var body: some View {
    GrandchildView()  // No props
  }
}
```

### 6. Side Effects in Getters or Body

**❌ ANTI-PATTERN:**

```swift
var body: some View {
  let content = markdownContent  // Computed property with side effect
  return Markdown(content)
}

private var markdownContent: MarkdownContent {
  let content = MarkdownContent(entry.detail)
  // NEVER mutate state in a getter!
  DispatchQueue.main.async {
    self.cachedContent = content
  }
  return content
}
```

**✅ CORRECT:**

```swift
@State private var cachedContent: MarkdownContent?

var body: some View {
  if let content = cachedContent {
    Markdown(content)
  }
}
.onAppear { updateCacheIfNeeded() }
.onChange(of: entry.detail) { _, _ in
  invalidateCache()
  updateCacheIfNeeded()
}

private func updateCacheIfNeeded() {
  if cachedContent == nil {
    cachedContent = MarkdownContent(entry.detail)
  }
}

private func invalidateCache() {
  cachedContent = nil
}
```

**Why:** Getters (including `body`) should be pure - no state mutation, no side effects. Use explicit `onChange` handlers for cache management.

**Implementation Reference:**
- `Contextify/Contextify/TimelineEntryRow.swift:87-99` - Correct caching pattern with onChange

### 7. Forgetting View Reuse with @State

**❌ ANTI-PATTERN:**

```swift
struct ItemRow: View {
  let item: Item
  @State private var cachedData: ProcessedData?

  var body: some View {
    // cachedData may contain stale data from a DIFFERENT item
    // if SwiftUI reuses this view instance
    Text(cachedData?.text ?? "")
  }
  .onAppear { loadData() }
  .onChange(of: item.content) { _, _ in
    // Only invalidates when content changes, not when item identity changes!
    cachedData = nil
  }
}
```

**✅ CORRECT:**

```swift
struct ItemRow: View {
  let item: Item
  @State private var cachedData: ProcessedData?

  var body: some View {
    Text(cachedData?.text ?? "")
  }
  .onAppear { loadData() }
  .onChange(of: item.content) { _, _ in
    cachedData = nil
    loadData()
  }
  .onChange(of: item.id) { _, _ in
    // Handle view reuse - SwiftUI may reuse this view for a different item
    cachedData = nil
    loadData()
  }
}
```

**Why:** In `ForEach`, SwiftUI may reuse view instances for different items. `@State` persists with the view instance, not the item. Always invalidate cached state when item identity changes.

**Implementation Reference:**
- `Contextify/Contextify/TimelineEntryRow.swift:188-192` - onChange(of: entry.id) for view reuse safety

### 8. Relying Only on onChange for Initial State

**❌ ANTI-PATTERN:**

```swift
@State private var cache: ParsedContent?

var body: some View {
  if let cache {
    ContentView(cache)
  }
}
.onChange(of: isExpanded) { _, newValue in
  // PROBLEM: If isExpanded starts as true, onChange never fires!
  if newValue {
    cache = parseContent()
  }
}
```

**✅ CORRECT:**

```swift
@State private var cache: ParsedContent?

var body: some View {
  if let cache {
    ContentView(cache)
  }
}
.onAppear {
  // Handle case where isExpanded is already true on first render
  updateCacheIfNeeded()
}
.onChange(of: isExpanded) { _, newValue in
  if newValue {
    updateCacheIfNeeded()
  } else {
    cache = nil
  }
}

private func updateCacheIfNeeded() {
  if isExpanded && cache == nil {
    cache = parseContent()
  }
}
```

**Why:** `onChange` only fires on *changes* after the view appears. If a value is already set when the view appears (e.g., restored state, parent-driven), `onChange` never fires. Use `onAppear` to handle the initial state.

**Implementation Reference:**
- `Contextify/Contextify/TimelineEntryRow.swift:156-173` - Combined onAppear + onChange pattern

---

## Migration from StateObject to Observable

### Before (iOS 16, macOS 13)

```swift
class OldViewModel: ObservableObject {
  @Published var count: Int = 0

  func increment() {
    count += 1
  }
}

struct OldView: View {
  @StateObject private var viewModel = OldViewModel()

  var body: some View {
    Text("Count: \(viewModel.count)")
      .onTapGesture {
        viewModel.increment()
      }
  }
}
```

### After (iOS 17+, macOS 14+)

```swift
@MainActor
@Observable
class NewViewModel {
  var count: Int = 0  // No @Published needed

  func increment() {
    count += 1
  }
}

struct NewView: View {
  @State private var viewModel = NewViewModel()

  var body: some View {
    Text("Count: \(viewModel.count)")
      .onTapGesture {
        viewModel.increment()
      }
  }
}
```

### Migration Checklist

- [ ] Replace `ObservableObject` with `@Observable`
- [ ] Remove all `@Published` wrappers
- [ ] Replace `@StateObject` with `@State` or `@Environment`
- [ ] Add `@MainActor` to all view models
- [ ] Mark non-observed properties with `@ObservationIgnored`
- [ ] Test that UI updates correctly

### Performance Benefits

**Observation Framework Improvements:**
- **Precise tracking:** Only re-renders when accessed properties change (not all published properties)
- **Reduced overhead:** No Combine subscriptions
- **Better debugging:** Compiler errors for concurrency violations

---

## Summary

### Pattern Decision Tree

```
Does the state need to be shared across multiple views?
├─ YES → Use @Observable class + @Environment
│   ├─ Is it app-wide? → Singleton pattern
│   └─ Is it contextual? → On-demand creation
│
└─ NO → Use @State
    ├─ Simple value type? → @State private var
    └─ Complex object? → @State private var (still @State in iOS 17+)

Do you need to observe external state?
└─ Use @Environment(ObservableObject.self)

Do you need a binding?
└─ Pass $stateVariable or use @Binding
```

### Quick Reference

| Question | Answer |
|----------|--------|
| How to share state? | `@Observable` + `@Environment` |
| How to store local state? | `@State private var` |
| How to pass bindings? | `$stateVariable` |
| How to prevent observation? | `@ObservationIgnored` |
| How to ensure main thread? | `@MainActor` on class |
| How to do background work? | `Task.detached { }` |
| How to clean up tasks? | `.task { }` (auto-cancels) |

### File Count by Pattern

**@Observable Classes:** 6
- `ConversationMonitor.swift` (~2900 lines)
- `ProjectSwitcherState.swift`
- `StatusBarViewModel.swift`
- `ProjectsViewModel.swift`
- `DeveloperMode.swift`
- `HUDViewModel.swift`

**Views:** 16 (ProjectSwitcherView, ContentView, ConversationTimelineView, etc.)

**ViewModels:** 2 (ProjectsViewModel, StatusBarViewModel)

---

## Platform Quirks and Workarounds

### ScrollViewReader scrollTo Unreliable on First Call

**Problem:** `ScrollViewReader.scrollTo(_:anchor:)` often scrolls to the wrong position on the first call due to SwiftUI's lazy loading miscalculating offsets before the full layout is complete.

**Symptoms:**
- List scrolls to wrong item
- Scroll appears to do nothing
- Works correctly on second manual scroll

**Workaround:** Call `scrollTo` twice with a delay between calls:

```swift
ScrollViewReader { proxy in
  List {
    ForEach(items) { item in
      ItemRow(item: item)
        .id(item.id)
    }
  }
  .onChange(of: selectedItemId) { _, newId in
    guard let id = newId else { return }
    // Call twice - first call triggers layout calculation,
    // second call scrolls to correct position
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      proxy.scrollTo(id, anchor: .center)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      proxy.scrollTo(id, anchor: .center)
    }
  }
}
```

**References:**
- [Stack Overflow: scrollTo not working reliably](https://stackoverflow.com/a/77042664)
- [Hacking with Swift Forums: ScrollViewReader issues](https://www.hackingwithswift.com/forums/swiftui/scrollviewreader-and-scrollto-isssues-possible-bug/23128)

**Implementation Example:**
- `Contextify/Contextify/DeepSearchView.swift:192-200` - Double scrollTo with delays for context pane

**Note:** This affects macOS Lists more than iOS. The new scroll APIs from WWDC 2023+ (`scrollPosition`, `scrollTargetLayout`) do NOT support `List`, only `ScrollView`.

---

### List vs ScrollView for Scroll Control

**Problem:** Apple's newer scroll control APIs (WWDC 2023+) don't support `List`.

**Implication:** `ScrollViewReader` remains the only scroll control API that works with `List`.

**When to use ScrollView + LazyVStack instead of List:**
- Need precise scroll control
- Need new scroll APIs (`scrollPosition`, `scrollTargetLayout`)
- Don't need List's built-in selection, swipe actions, or styling

**When to stick with List:**
- Need selection behavior
- Need swipe actions
- Need sidebar styling
- Can live with `ScrollViewReader` workarounds

---

### Animation Can Interfere with scrollTo

**Problem:** Wrapping `scrollTo` in `withAnimation` can cause the scroll to fail or animate incorrectly.

**Workaround:** Try without animation first:

```swift
// May fail:
withAnimation {
  proxy.scrollTo(id, anchor: .center)
}

// More reliable:
proxy.scrollTo(id, anchor: .center)
```

---

### onChange with Prepended Items Triggers Unwanted Scroll

**Problem:** When using `.onChange(of: list.first?.id)` to detect list changes and scroll to a target item, prepending items (e.g., "Load 5 earlier") changes the first item's ID, triggering an unwanted scroll back to the target.

**Symptoms:**
- User clicks "Load more previous"
- Earlier entries load correctly
- View unexpectedly scrolls back to the highlighted/target item
- "Load more later" works fine (appending doesn't change first ID)

**Workaround:** Add a flag to distinguish between "new selection" (should scroll) and "load more" (preserve position):

```swift
// ViewModel
@Observable
class ContextViewModel {
  var entries: [Entry] = []
  var shouldScrollToTarget: Bool = false  // Control flag

  func loadContext(for targetId: String) async {
    shouldScrollToTarget = true  // New selection → scroll
    entries = await fetchEntries(around: targetId)
  }

  func loadMoreEarlier() {
    shouldScrollToTarget = false  // Load more → preserve position
    Task { entries = await fetchMoreEarlier() }
  }
}

// View
.onChange(of: viewModel.entries.first?.id) { _, _ in
  guard viewModel.shouldScrollToTarget else { return }  // Check flag
  proxy.scrollTo(targetId, anchor: .center)
}
```

**Implementation Example:**
- `Contextify/Contextify/DeepSearchViewModel.swift:32` - `shouldScrollToHit` flag
- `Contextify/Contextify/DeepSearchView.swift:188` - Guard check before scrolling

---

### onChange Does NOT Fire on Initial Value

**Problem:** SwiftUI's `.onChange(of:)` modifier only fires when a value **changes after** the view appears, not when the value is set initially. If a view appears with a pre-populated value, `onChange` never triggers.

**Symptoms:**
- `.onChange(of: someArray.first?.id)` doesn't fire when the array is already populated on view appear
- Scroll-to-item logic in `onChange` doesn't work on initial window open
- Works fine when clicking to change selection (because the value actually changes)

**Workaround:** Use `.onAppear` in addition to `.onChange` to handle the initial state:

```swift
ScrollViewReader { proxy in
  List { /* ... */ }
    .onAppear {
      // Handle initial value that onChange won't catch
      scrollToTargetIfNeeded(proxy: proxy)
    }
    .onChange(of: viewModel.entries.first?.id) { _, _ in
      // Handle subsequent changes
      scrollToTargetIfNeeded(proxy: proxy)
    }
}

private func scrollToTargetIfNeeded(proxy: ScrollViewProxy) {
  guard viewModel.shouldScroll else { return }
  guard !viewModel.entries.isEmpty else { return }
  // ... scroll logic
}
```

**Key insight:** Extract scroll logic to a helper function to avoid duplication between `onAppear` and `onChange`.

**Implementation Example:**
- `Contextify/Contextify/DeepSearchView.swift:164-172` - Combined `onAppear` + `onChange` pattern
- `Contextify/Contextify/DeepSearchView.swift:186-203` - `scrollToHitIfNeeded` helper function

---

## macOS 15 (Sequoia) Quirks

macOS 15 introduces several SwiftUI regressions, particularly around horizontal ScrollViews and gestures. These quirks do NOT exist on macOS 26 (Tahoe).

### Horizontal ScrollView Blocks onTapGesture

**Problem:** Inside a horizontal `ScrollView`, `onTapGesture` is completely blocked on macOS 15. Taps are intercepted by the ScrollView's gesture handling and never reach the tap handler.

**Symptoms:**
- Buttons using `onTapGesture` don't respond to clicks
- `simultaneousGesture`, `highPriorityGesture` don't help
- `NSClickGestureRecognizer` doesn't help
- Works fine in vertical ScrollViews and on macOS 26

**Workaround:** Use `Button` with a custom `ButtonStyle` instead of `onTapGesture`:

```swift
// ❌ BAD: Doesn't work on macOS 15
Text("Tab")
  .onTapGesture { handleTap() }

// ✅ GOOD: Works on all macOS versions
private struct ScrollViewButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.7 : 1.0)
  }
}

Button { handleTap() } label: {
  Text("Tab")
    .contentShape(Rectangle())  // Expand hit area to full frame
}
.buttonStyle(ScrollViewButtonStyle())
```

**Why this works:** Button styles use a different gesture handling mechanism that doesn't conflict with ScrollView's pan gesture recognition.

**Additional fix:** Add a 1pt invisible spacer above the ScrollView to fix hit-testing layout calculation:

```swift
VStack(spacing: 0) {
  // Workaround: 1pt spacer fixes macOS 15 hit-testing in horizontal ScrollView
  Color.clear.frame(height: 1)

  ScrollView(.horizontal) {
    // Content with Button+ButtonStyle
  }
}
```

**Implementation Reference:**
- `Contextify/Contextify/ProjectSwitcherView.swift:15-20` - ScrollViewButtonStyle
- `Contextify/Contextify/ContentView.swift` - 1pt spacer workaround

---

### .onDrag() Doesn't Work in Horizontal ScrollView

**Problem:** The `.onDrag()` modifier fails to initiate drag operations inside horizontal ScrollViews on macOS 15. The drag preview never appears and the drag never starts.

**Symptoms:**
- Long-press/drag gesture is captured by ScrollView
- No drag preview appears
- Works fine on macOS 26

**Failed alternatives:**
- `.draggable()` modifier - Also doesn't work on macOS 15 (and breaks macOS 26)
- `NSItemProvider` variations - Same result

**Workaround:** Provide alternative reordering via context menu:

```swift
.contextMenu {
  Button("Move Left") {
    guard let idx = items.firstIndex(of: item), idx > 0 else { return }
    var newOrder = items.map(\.id)
    newOrder.swapAt(idx, idx - 1)
    reorder(newOrder)
  }
  .disabled(isFirstItem)

  Button("Move Right") {
    guard let idx = items.firstIndex(of: item), idx < items.count - 1 else { return }
    var newOrder = items.map(\.id)
    newOrder.swapAt(idx, idx + 1)
    reorder(newOrder)
  }
  .disabled(isLastItem)
}
```

**Note:** Keep `.onDrag()` for macOS 26 users where it works correctly. The context menu provides a universal fallback.

**Implementation Reference:**
- `Contextify/Contextify/ProjectSwitcherView.swift:431-475` - Context menu with Move Left/Right
- `Contextify/Contextify/ContextifyApp.swift:52-76` - Keyboard shortcuts (⌘⇧⌥[ / ⌘⇧⌥])

---

### .textSelection(.enabled) Causes Popover Sizing Issues

**Problem:** Adding `.textSelection(.enabled)` to text in a popover causes incorrect sizing on macOS 15. The popover may be too small, clip content, or show incorrect layout.

**Symptoms:**
- Popover content is clipped
- Height calculation is wrong
- Works fine on macOS 26

**Workaround:** Gate `.textSelection()` on macOS 26+:

```swift
@ViewBuilder
private var bodyContent: some View {
  if #available(macOS 26, *) {
    Text(message)
      .textSelection(.enabled)
  } else {
    Text(message)
    // No textSelection on macOS 15
  }
}
```

**Implementation Reference:**
- `Contextify/Contextify/InfoPopoverContent.swift:116-128` - Gated textSelection

---

### .presentationSizing(.fitted) Not Available

**Problem:** The `.presentationSizing(.fitted)` modifier was introduced in macOS 26 and is not available on macOS 15.

**Workaround:** Use a conditional modifier:

```swift
private struct PresentationSizingModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      content.presentationSizing(.fitted)
    } else {
      content  // Rely on frame constraints
    }
  }
}

// Usage
.modifier(PresentationSizingModifier())
```

**Alternative:** Use explicit `.frame()` and `.fixedSize()` that work on both versions:

```swift
.frame(width: 320, alignment: .leading)
.fixedSize(horizontal: false, vertical: true)
```

**Implementation Reference:**
- `Contextify/Contextify/InfoPopoverContent.swift:13-22` - PresentationSizingModifier

---

### Summary: macOS 15 ScrollView Workarounds

| Issue | Workaround |
|-------|------------|
| `onTapGesture` blocked | Use `Button` + custom `ButtonStyle` |
| Hit-testing broken | Add 1pt `Color.clear` spacer above ScrollView |
| `.onDrag()` fails | Keep for macOS 26, add context menu fallback |
| `.draggable()` fails | Don't use - breaks both macOS versions |
| `.textSelection()` sizing | Gate with `#available(macOS 26, *)` |
| `.presentationSizing()` unavailable | Use conditional modifier |

**Testing Recommendation:** Test horizontal ScrollView interactions on BOTH macOS 15 and 26 VMs when making changes to tab bars, carousels, or similar horizontal scrolling UI.

---

## Search Field Conventions

### Cmd+F Support Requirement

All windows with search functionality MUST support Cmd+F to focus the search field. SwiftUI does NOT provide this automatically - manual implementation required for ALL search types.

### Pattern A: Custom TextField

Use when you have a custom search TextField (not using `.searchable()`):

```swift
struct SomeView: View {
  @FocusState private var searchFieldFocused: Bool

  var body: some View {
    VStack {
      TextField("Search...", text: $query)
        .focused($searchFieldFocused)
      // ... other content
    }
    // Cmd+F to focus search field
    .background {
      Button("") { searchFieldFocused = true }
        .keyboardShortcut("f", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
    }
  }
}
```

### Pattern B: .searchable() Modifier

Use when using SwiftUI's built-in `.searchable()` modifier:

```swift
struct SomeView: View {
  @State private var searchText = ""
  @State private var isSearchFieldPresented = false

  var body: some View {
    List { /* ... */ }
      .searchable(text: $searchText, isPresented: $isSearchFieldPresented, prompt: "Search")
      // Cmd+F to focus search field
      .background {
        Button("") { isSearchFieldPresented = true }
          .keyboardShortcut("f", modifiers: .command)
          .frame(width: 0, height: 0)
          .opacity(0)
      }
  }
}
```

### Implementation References

**Pattern A (Custom TextField):**
- `Contextify/Contextify/SemanticSearchView.swift` - Semantic Search window

**Pattern B (.searchable):**
- `Contextify/Contextify/ContentView.swift:111` - Main window search
- `Contextify/Contextify/DeepSearchView.swift:39` - Deep Search window
- `Contextify/Contextify/TranscriptInventoryView.swift:232` - Transcript inventory
- `Contextify/Contextify/ProjectsWindow.swift:116` - Projects browser

### Why This Is Required

SwiftUI's `.searchable()` modifier and custom TextFields do NOT respond to Cmd+F by default. This is a macOS platform quirk that users expect but Apple does not provide automatically. The hidden button pattern intercepts the keyboard shortcut and programmatically focuses the search field.

---

### Swift Package Targets Don't See Xcode Build Flags

**Problem:** Conditional compilation flags defined in Xcode project build settings (like `APPSTORE_BUILD`) are NOT visible to Swift Package code. SPM compiles packages independently of Xcode's build configuration.

**Symptoms:**
- `#if APPSTORE_BUILD` always evaluates to `false` in package code
- Behavior that should differ between DMG and App Store builds doesn't
- Runtime checks work, compile-time checks don't

**Example of the bug:**

```swift
// In ContextifyCore package (HUDCore.swift)
public enum Sandbox {
    public static var isSandboxed: Bool {
        #if APPSTORE_BUILD  // ❌ NEVER TRUE - package doesn't see this flag
        return true
        #else
        return false  // ← Always returns this
        #endif
    }
}

// In app target (WelcomeModalView.swift)
if !Sandbox.isSandboxed {  // Always false!
    return false  // Permissions step always skipped
}
```

**Why this happens:**
1. Xcode build settings only apply to targets in the Xcode project
2. Swift packages are compiled by SPM, which has its own build system
3. SPM doesn't receive `-D APPSTORE_BUILD` from Xcode
4. The flag is undefined in package compilation, so `#if` evaluates to `false`

**Solutions (in order of preference):**

1. **Use runtime detection** (recommended):
```swift
public static var isRuntimeSandboxed: Bool {
    #if os(macOS)
    if getenv("APP_SANDBOX_CONTAINER_ID") != nil { return true }
    if ProcessInfo.processInfo.environment["__XPC_SANDBOXED"] == "1" { return true }
    #endif
    return false
}
```

2. **Inject configuration from app target** at initialization:
```swift
// In package
public enum AppConfig {
    public static var isAppStore: Bool = false  // Default
}

// In app target's @main
AppConfig.isAppStore = true  // Set before any package code runs
```

3. **Move flag-dependent code to app target** (not always practical)

**What NOT to do:**
- ❌ Assume Xcode build settings propagate to SPM packages
- ❌ Use `#if` for distribution-specific behavior in package code
- ❌ Rely on `Sandbox.isSandboxed` from package code in App Store builds

**Implementation references:**
- `app/Sources/ContextifyCore/HUDCore.swift:212-218` - `isRuntimeSandboxed` implementation
- `Contextify/Contextify/WelcomeModalView.swift:373` - Uses `isRuntimeSandboxed`

**Related bug:** This caused two P0 bugs blocking App Store submission - see `/tmp/sandbox-container-path-bug-postmortem.md`

**External references:**
- [Stack Overflow: Custom build configurations in Swift Package Manager](https://stackoverflow.com/questions/60603181/xcode-custom-build-configurations-in-swift-package-manager)
- [Swift Forums: Swift package manager and custom build configurations](https://forums.swift.org/t/swift-package-manager-and-custom-build-configurations/29181)
- [Swift Evolution SE-0238: Package Manager Build Settings](https://github.com/apple/swift-evolution/blob/master/proposals/0238-package-manager-build-settings.md)

---

### .borderedProminent Disabled State Not Visible (macOS 26)

**Problem:** On macOS 26, `.borderedProminent` buttons with `.disabled(true)` do NOT visually dim or gray out. The button remains fully colored (using the accent color or custom `.tint()`), making it impossible to tell the button is disabled.

**Symptoms:**
- Button looks fully clickable (solid blue/tinted fill)
- Button is actually disabled (doesn't respond to clicks)
- Users can't tell they need to complete an action before proceeding

**What doesn't work:**
```swift
// ❌ Button stays fully blue even when disabled
Button("Next") { action() }
  .buttonStyle(.borderedProminent)
  .tint(Color.contextifyBlue)
  .disabled(!isReady)

// ❌ tint(nil) falls back to accent color, not "no tint"
Button("Next") { action() }
  .buttonStyle(.borderedProminent)
  .tint(isReady ? Color.contextifyBlue : nil)
  .disabled(!isReady)

// ❌ Conditional gray tint still shows as prominent/clickable
Button("Next") { action() }
  .buttonStyle(.borderedProminent)
  .tint(isReady ? Color.contextifyBlue : Color.gray)
  .disabled(!isReady)
```

**Workaround:** Use different button styles for enabled vs disabled states:

```swift
// ✅ Enabled: borderedProminent (filled, vibrant)
// ✅ Disabled: bordered (outline only, visually recedes)
if isReady {
  Button("Next") { action() }
    .buttonStyle(.borderedProminent)
    .tint(Color.contextifyBlue)
} else {
  Button("Next") {}
    .buttonStyle(.bordered)
    .disabled(true)
}
```

**Why this works:**
- `.borderedProminent` = filled button (calls to action)
- `.bordered` = outline-only button (secondary action appearance)
- The visual difference is unambiguous regardless of SwiftUI's disabled state rendering

**Implementation Example:**
- `Contextify/Contextify/Onboarding/AppStoreOnboardingView.swift:119-143` - Next/Continue buttons

**Note:** This may be a macOS 26-specific bug. The workaround is safe for all versions since it doesn't rely on the built-in disabled appearance working correctly.

---

## Custom Keyboard Navigation (Tab/Shift+Tab/Enter)

### Problem: SwiftUI Keyboard Shortcut Limitations

SwiftUI's built-in keyboard handling has several issues on macOS:

1. **`.keyboardShortcut(.defaultAction)` forces system blue** - When a button has this modifier, macOS renders it with system accent color (blue), overriding any custom `.tint()` color. This makes it impossible to maintain brand colors.

2. **`.onKeyPress(.tab)` unreliable** - Tab key events are often consumed by system focus navigation before SwiftUI's handler receives them.

3. **No Tab cycling control** - SwiftUI provides no way to define custom Tab order or cycle between specific elements.

### Solution: NSEvent Local Monitor

Use `NSEvent.addLocalMonitorForEvents` to intercept keyboard events at the app level before SwiftUI processes them. This gives full control over Tab, Shift+Tab, and Enter handling.

**Implementation Pattern:**

```swift
// NSViewRepresentable wrapper for keyboard monitoring
private struct KeyboardHandler: NSViewRepresentable {
  let isEnabled: Bool
  let onTab: () -> Void
  let onShiftTab: () -> Void
  let onEnter: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = KeyboardView()
    view.onTab = onTab
    view.onShiftTab = onShiftTab
    view.onEnter = onEnter
    view.isEnabled = isEnabled
    view.setupMonitorIfNeeded()  // Set up immediately
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    guard let view = nsView as? KeyboardView else { return }
    view.onTab = onTab
    view.onShiftTab = onShiftTab
    view.onEnter = onEnter
    view.isEnabled = isEnabled
  }

  @MainActor
  class KeyboardView: NSView {
    var onTab: (() -> Void)?
    var onShiftTab: (() -> Void)?
    var onEnter: (() -> Void)?
    var isEnabled = false
    private var monitor: Any?

    func setupMonitorIfNeeded() {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self, self.isEnabled else { return event }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Tab key (keyCode 48)
        if event.keyCode == 48 {
          if flags == .shift {
            self.onShiftTab?()
            return nil  // Consume event
          } else if flags.isEmpty {
            self.onTab?()
            return nil
          }
        }

        // Enter/Return key (keyCode 36)
        if event.keyCode == 36 && flags.isEmpty {
          self.onEnter?()
          return nil
        }

        return event  // Let other events pass through
      }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil { setupMonitorIfNeeded() }
    }

    override func removeFromSuperview() {
      if let monitor = monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
      super.removeFromSuperview()
    }
  }
}
```

**Usage in View:**

```swift
struct WizardView: View {
  @State private var focusedElement: FocusableElement = .firstButton

  var body: some View {
    VStack {
      // ... buttons with focus rings
    }
    .background(KeyboardHandler(
      isEnabled: true,
      onTab: { focusNext() },
      onShiftTab: { focusPrevious() },
      onEnter: { handleEnter() }
    ))
  }

  private func focusNext() {
    let targets = availableFocusTargets
    if let idx = targets.firstIndex(of: focusedElement) {
      focusedElement = targets[(idx + 1) % targets.count]
    }
  }
}
```

**Implementation Reference:**
- `Contextify/Contextify/Onboarding/AppStoreOnboardingView.swift:274-355` - Full KeyboardHandler implementation

---

### Focus Ring Styling for Enter-Ready Buttons

When using manual Enter handling (no `.keyboardShortcut(.defaultAction)`), buttons need a visual indicator showing which one will respond to Enter.

**Pattern: Focus Ring Overlay**

```swift
private struct FocusRingStyle: ViewModifier {
  let isActive: Bool

  func body(content: Content) -> some View {
    content
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(isActive ? Color.contextifyBlue : Color.clear, lineWidth: 2)
          .padding(-4)  // Extend outside button bounds
      )
      .animation(.easeInOut(duration: 0.15), value: isActive)
  }
}
```

**Usage:**

```swift
Button("Grant Access...") { requestAccess() }
  .buttonStyle(.bordered)  // Secondary style (not .borderedProminent)
  .modifier(FocusRingStyle(isActive: isFocused))
```

**Visual Hierarchy:**
- **`.borderedProminent`** - Primary action (filled background, reserved for "Continue"/"Submit")
- **`.bordered` + focus ring** - Secondary action with keyboard focus
- **`.bordered`** - Secondary action without focus

This avoids the "two prominent buttons" problem where multiple buttons compete visually.

**Implementation References:**
- `Contextify/Contextify/Onboarding/AppStoreOnboardingView.swift:369-385` - FocusRingStyle modifier
- `Contextify/Contextify/Views/SourceAuthorizationRow.swift:152-177` - FocusRingIndicator with background tint

---

### Quirk: Enter Key Dismisses NSOpenPanel Immediately

**Problem:** When Enter triggers an NSOpenPanel via state binding, the Enter key event is still "in flight" when the panel appears. This causes the panel to immediately dismiss (as if the user pressed Enter on the panel's default button).

**Symptoms:**
- Logs show "User cancelled folder selection" immediately after trigger
- Panel appears to flash or not appear at all
- Works fine when clicking the button with mouse

**Workaround:** Use `DispatchQueue.main.async` to delay the trigger until the Enter event is fully consumed:

```swift
private func handleEnter() {
  if !isConfigured {
    // ❌ BAD: Panel dismisses immediately
    openFolderPickerTrigger = true

    // ✅ GOOD: Async delay lets Enter event complete first
    DispatchQueue.main.async {
      self.openFolderPickerTrigger = true
    }
  }
}
```

**Why this works:** The async dispatch puts the trigger on the next run loop iteration, after the NSEvent handler has fully processed and returned. The Enter key event is then complete before the modal panel appears.

**Implementation Reference:**
- `Contextify/Contextify/Onboarding/AppStoreOnboardingView.swift:104-115` - handleEnterStep1 with async delay

---

### Quirk: .keyboardShortcut(.defaultAction) Overrides Button Styling

**Problem:** When a button has `.keyboardShortcut(.defaultAction)`, macOS forces system default button rendering (solid blue fill) regardless of:
- `.buttonStyle(.bordered)`
- Custom `.tint()` color
- Any other styling modifiers

**What doesn't work:**
```swift
// ❌ Button renders as system blue, not contextifyBlue
Button("Next") { }
  .buttonStyle(.bordered)  // Ignored!
  .tint(Color.contextifyBlue)  // Ignored!
  .keyboardShortcut(.defaultAction)
```

**Solution:** Handle Enter key manually via NSEvent monitor instead of using `.keyboardShortcut(.defaultAction)`. This gives full control over button styling.

```swift
// ✅ Button renders correctly, Enter handled manually
Button("Next") { }
  .buttonStyle(.bordered)
  .modifier(FocusRingStyle(isActive: isEnterTarget))
// Enter key handled by KeyboardHandler in parent view
```

**Trade-off:** More code, but complete control over visual appearance.

**Implementation Reference:**
- `Contextify/Contextify/Onboarding/AppStoreOnboardingView.swift` - Full manual keyboard handling
- `Contextify/Contextify/Views/SourceAuthorizationRow.swift:96-113` - Grant Access button without keyboard shortcut

---

## References

### Internal Documentation

- **`build/docs/architecture/architecture-refactoring-analysis.md`** - ConversationMonitor god object refactoring
- **`build/docs/architecture/conversation-monitor-state.md`** - Timeline state management
- **`build/docs/architecture/project-switcher.md`** - Project switcher architecture

### Code Examples (Verified)

- `Contextify/Contextify/ProjectSwitcherState.swift:29-31` - @Observable singleton
- `Contextify/Contextify/ContentView.swift:33-44` - @Environment + @State
- `Contextify/Contextify/StatusBarViewModel.swift:13-14` - @MainActor + @Observable
- `Contextify/Contextify/ConversationMonitor.swift:140-141` - @Observable @MainActor

### External Resources

- **Observation Framework:** https://developer.apple.com/documentation/observation
- **SwiftUI State Management:** https://developer.apple.com/documentation/swiftui/state-and-data-flow
- **Swift Concurrency:** https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/

---

**Document Status:** ✅ Complete
**Last Code Verification:** 2026-01-03 (added anti-patterns 6-8 from MarkdownUI caching implementation)
**Next Review:** After SwiftUI architecture changes or Swift 6 migration tasks
