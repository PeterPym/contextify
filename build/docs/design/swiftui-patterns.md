# SwiftUI Architecture Patterns

**Last Updated:** 2025-11-26
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

**Reference:** `build/docs/architecture/architecture-refactoring-analysis.md` (ConversationMonitor god object, 3054 lines)

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
  // 3054 lines with 15+ responsibilities
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
- `ConversationMonitor.swift` (3054 lines)
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
- `Contextify/Contextify/DeepSearchView.swift:209-219` - Double scrollTo with delays for context pane

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
- `Contextify/Contextify/ContentView.swift` - Main window with HUDSearchField
- `Contextify/Contextify/DeepSearchView.swift` - Deep Search window
- `Contextify/Contextify/SemanticSearchView.swift` - Semantic Search window

**Pattern B (.searchable):**
- `Contextify/Contextify/TranscriptInventoryView.swift` - Transcript inventory
- `Contextify/Contextify/ProjectsWindow.swift` - Projects browser

### Why This Is Required

SwiftUI's `.searchable()` modifier and custom TextFields do NOT respond to Cmd+F by default. This is a macOS platform quirk that users expect but Apple does not provide automatically. The hidden button pattern intercepts the keyboard shortcut and programmatically focuses the search field.

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
**Last Code Verification:** 2025-11-26 (verified against 27 SwiftUI files, 6 @Observable classes, 16 views)
**Next Review:** After SwiftUI architecture changes or Swift 6 migration tasks
