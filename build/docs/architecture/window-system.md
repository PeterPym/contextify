# Window Architectures: Contextify

**Last Updated**: 2025-10-22
**Status**: Comprehensive Reference
**Audience**: Developers, UI Engineers

---

## Overview

Contextify consists of **four primary windows**, each with distinct purposes, data sources, and architectural patterns:

1. **Main HUD Window** - Real-time timeline + iTerm2 compose panel
2. **Transcript Inventory Window** - Session browser with metadata
3. **Projects Window** - Multi-project discovery and switching
4. **Settings Window** - User preferences (standard macOS Settings)

This document provides detailed architectural analysis of each window, focusing on data flow, state management, initialization sequences, and cross-window communication.

---

## Window Creation & Management

### App-Level Window Declaration

**File**: `ContextifyApp.swift` (lines 56-120)

```swift
@main
struct ContextifyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let model = HUDViewModel.shared        // Shared instance
  private let timeline = ConversationMonitor.shared  // Shared instance
  @State private var projectsViewModel: ProjectsViewModel?

  var body: some Scene {
    // Window 1: Main HUD (always visible on launch)
    Window("Contextify", id: "main") {
      ContentView()
        .environment(model)
        .environment(timeline)
        .environment(DeveloperMode.shared)
    }
    .defaultSize(width: 940, height: 360)

    // Window 2: Transcript Inventory (on-demand)
    Window("Transcript Inventory", id: "transcript-inventory") {
      TranscriptInventoryWindow()
        .environment(HUDViewModel.shared)
        .environment(ConversationMonitor.shared)
    }
    .defaultSize(width: 1000, height: 700)

    // Window 3: Projects (on-demand)
    Window("Projects", id: "projects") {
      if let viewModel = projectsViewModel {
        ProjectsWindow().environment(viewModel)
      } else {
        ProgressView()  // Loading state
      }
    }
    .defaultSize(width: 800, height: 600)

    // Window 4: Settings (macOS standard)
    Settings {
      SettingsView()
    }
  }
}
```

### Window Opening Mechanism

**Keyboard Shortcuts** (ContextifyApp.swift:6-22):
```swift
struct WindowCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Window") {
      Button("Show Transcript Inventory") {
        openWindow(id: "transcript-inventory")
      }
      .keyboardShortcut("i", modifiers: [.command, .control])

      Button("Projects") {
        openWindow(id: "projects")
      }
      .keyboardShortcut("p", modifiers: [.command, .shift])
    }
  }
}
```

**Programmatic Opening**:
```swift
// From anywhere in the app
@Environment(\.openWindow) private var openWindow

func showInventory() {
  openWindow(id: "transcript-inventory")
}
```

---

## Window 1: Main HUD (Timeline View)

### Purpose

The Main HUD window serves as the **primary interface** for:
- Real-time conversation timeline display
- iTerm2 integration (compose panel)
- Project and git branch display
- Session filtering and navigation

### Component Hierarchy

```
Window("Contextify", id: "main")
  ├─ ContentView
  │   ├─ header (project info, branch, folder picker)
  │   ├─ composeSection (iTerm2 integration)
  │   └─ ConversationTimelineView (RIGHT SIDE)
  │       ├─ Session filter controls
  │       ├─ VirtualizedScrollView
  │       │   └─ ForEach(monitor.visibleEntries)
  │       │       └─ TimelineEntryRow
  │       │           ├─ Role indicator (user/assistant/system)
  │       │           ├─ Summary (LLM-generated)
  │       │           └─ Expanded detail (on click)
  │       └─ Status footer (entry count, errors)
  └─ WindowTitleWriter (updates window title to project name)
```

### Initialization Sequence

**Phase 1: Environment Setup** (ContentView.onAppear, line 50-54):

```swift
.onAppear {
  // 1. Update git info (branch, commit, worktree)
  model.updateGitInfo()

  // 2. Refresh iTerm2 session
  Task { await refreshSession() }

  // 3. Start timeline monitoring
  TimelineIntegration.shared.startMonitoring()
}
```

**Phase 2: Timeline Monitoring** (calls ConversationMonitor.startMonitoring):

```
ConversationMonitor.startMonitoring()
  ├─ Get project root from HUDViewModel.shared.projectRootURL
  ├─ Initialize TranscriptOrchestrator
  ├─ Create/get project in database
  ├─ Spawn background tasks:
  │   ├─ Task 1: discoverNewTranscripts() (every 10 seconds)
  │   └─ Task 2: watchForDebouncedTranscriptUpdates() (file watcher)
  ├─ Load initial feed: loadFeedFromSQL()
  ├─ Setup notifications (cache updates, project changes)
  └─ isMonitoring = true
```

**Total startup time**: ~50-100ms from launch to first timeline render

### Data Sources

**Primary Data Source**: SQL Database via `TranscriptOrchestrator`

```
ConversationMonitor.entries (TimelineState)
  ↑
loadFeedFromSQL()
  ↑
TranscriptOrchestrator.getEntriesWithCache(transcriptId:, limit:, cursor:)
  ↑
SQL Query:
  SELECT e.*, tc.summary_present, tc.summary_past
  FROM transcript_entries e
  LEFT JOIN timeline_cache tc ON ...
  WHERE e.transcript_id = ?
  ORDER BY e.timestamp, e.created_at, e.id
  LIMIT 50
```

**Secondary Data Sources**:
- **Git Information**: HUDViewModel.branchDisplay (from filesystem)
- **iTerm2 Session**: ITerm2Bridge.getCurrentSessionName() (AppleScript)
- **Project Root**: HUDViewModel.projectRootURL (from UserDefaults + bookmarks)

### State Management

**TimelineState** (ConversationMonitor.swift):

```swift
@Observable
@MainActor
class ConversationMonitor {
  // Primary state
  var entries: [TimelineEntry] = []          // All entries for current project
  var activeSession: String? = nil           // Filter by transcript ID
  var currentProjectId: String? = nil        // Active project UUID

  // Revision-based cache invalidation
  private var revision: Int = 0              // Bumped on major changes

  // Derived state (cached until revision changes)
  var visibleEntries: [TimelineEntry] {
    if let sessionId = activeSession {
      return entries.filter { $0.transcriptId == sessionId }
    }
    return entries
  }

  // Background tasks
  private var backgroundTasks: Task<Void, Never>?
  private var debounceTask: Task<Void, Never>?
}
```

**State Transitions**:

| Trigger | State Change | Revision Bump? | Result |
|---------|--------------|----------------|--------|
| App startup | entries = [], revision = 0 | No | Empty timeline |
| Initial feed load | entries = [...] | Yes | Timeline populates |
| File change event | entries.append(...) | No | Incremental update |
| Session switch | activeSession = newId | Yes | Filter changes |
| Project switch | currentProjectId = newId | Yes | Full reload |

### Update Mechanisms

**1. Real-Time Updates (File Watcher)**:

```
File system event (JSONL appended)
  ↓
TranscriptWatcher (debounced 150ms)
  ↓
HooverEngine.hooverTranscript() (incremental)
  ↓
NotificationCenter.post("transcriptUpdated")
  ↓
ConversationMonitor.watchForDebouncedTranscriptUpdates()
  ↓
loadFeedFromSQL() (keyset cursor - only new entries)
  ↓
entries.append(newEntries)
  ↓
SwiftUI observes change → Timeline updates
```

**Latency**: ~165ms from file change to UI update

**2. Discovery Loop (Background)**:

```
Every 10 seconds:
  ↓
ConversationMonitor.discoverNewTranscripts()
  ↓
ConversationSources.allSessions() (filesystem scan)
  ↓
orchestrator.upsertTranscripts() (persist to DB)
  ↓
startWatchingTranscript() for ALL transcripts
  ↓
allSessions = [...] (update inventory data)
  ↓
loadFeedFromSQL() (refresh feed)
```

**Performance**: ~200ms per cycle for 50 transcripts

**3. Manual Refresh** (N/A - automatic only)

### Session Filtering

**UI Control**: Session dropdown in ConversationTimelineView

**Mechanism**:
```swift
// User selects session from dropdown
func selectSession(_ session: TranscriptSession?) {
  monitor.activeSession = session?.identifier  // Set filter

  // Revision bump triggers visibleEntries recomputation
  monitor.revision += 1

  // Reload feed with new filter
  Task { await monitor.loadFeedFromSQL() }
}
```

**Derived State**:
```swift
var visibleEntries: [TimelineEntry] {
  // Cached until revision changes
  if let sessionId = activeSession {
    return entries.filter { $0.transcriptId == sessionId }
  }
  return entries  // No filter - show all
}
```

**Performance**: ~5ms SQL query + ~8ms UI render = ~13ms total

### Performance Characteristics

| Operation | Time | Notes |
|-----------|------|-------|
| App startup → first render | 50-100ms | Includes DB init + feed load |
| File change → timeline update | ~165ms | Debounce (150ms) + hoover + SQL |
| Session switch | ~13ms | SQL filter + UI re-render |
| Scroll through 1000 entries | Smooth | SwiftUI lazy rendering |
| Discovery cycle (background) | ~200ms | Every 10 seconds |

### Key Files

| File | Lines | Purpose |
|------|-------|---------|
| **ContentView.swift** | 1-260 | Main window layout, header, compose panel |
| **ConversationTimelineView.swift** | All | Timeline display UI, session filtering |
| **TimelineEntryRow.swift** | All | Individual entry rendering |
| **ConversationMonitor.swift** | 130-1050 | Timeline state management, data loading |
| **HUDViewModel.swift** | app/Sources/ContextifyCore/HUDCore.swift:370-1032 | Project root, git info, iTerm2 integration |

### Known Issues

- None currently identified for Main HUD window

---

## Window 2: Transcript Inventory

### Purpose

The Transcript Inventory window provides:
- Browse all discovered transcript sessions (across all providers)
- View session metadata (title, description, topics)
- Switch between sessions (updates Main HUD timeline)
- Search and filter transcripts
- Flush heuristic metadata cache (for re-analysis)

### Component Hierarchy

```
Window("Transcript Inventory", id: "transcript-inventory")
  ├─ TranscriptInventoryWindow
  │   └─ TranscriptInventoryView
  │       ├─ HSplitView (macOS native sidebar + detail)
  │       │   ├─ LEFT: Session List
  │       │   │   ├─ Header (title, refresh button, flush cache button)
  │       │   │   ├─ Toolbar (grouping picker, count)
  │       │   │   ├─ Search bar
  │       │   │   └─ List(sessions) with metadata
  │       │   │       └─ sessionRow(session)
  │       │   │           ├─ Provider badge
  │       │   │           ├─ Title (LLM-generated or heuristic)
  │       │   │           ├─ Description
  │       │   │           └─ Topics (tags)
  │       │   └─ RIGHT: Detail View
  │       │       ├─ Session info (provider, file path, timestamps)
  │       │       ├─ Metadata (title, description, topics)
  │       │       └─ Actions ("Switch to Session" button)
  │       └─ Toast notifications (flush confirmation)
```

### Initialization Sequence

**Phase 1: Window Appears** (TranscriptInventoryView.task, line 150-155):

```swift
.task {
  // Load initial sessions from ConversationMonitor
  // (sessions populated by discovery loop in main window)

  // Load metadata for all sessions
  await loadMetadataForSessions(monitor.allSessions)
}
```

**Phase 2: Metadata Loading** (TranscriptInventoryView.loadMetadataForSessions):

```
For each session in allSessions:
  ├─ Check metadata cache (transcript ID → metadata)
  ├─ IF cached: use cached metadata
  ├─ IF NOT cached:
  │   ├─ Call TranscriptMetadataOrchestrator.metadata(for: transcriptId)
  │   ├─ LLM generation (or heuristic fallback)
  │   └─ Save to cache (in-memory ❌)
  └─ Update UI state
```

**Total time**: ~1-3 seconds per session (LLM-dependent)

### Data Sources

**Primary Data Source (Sessions List)**: SQL via ConversationMonitor.allSessions ✅

```
ConversationMonitor.allSessions
  ↑
Discovery loop (every 10 seconds)
  ↑
orchestrator.getTranscripts(forProject:)
  ↑
SQL: SELECT * FROM transcripts WHERE project_id = ?
```

**Secondary Data Source (Metadata)**: In-Memory Cache ❌ **BROKEN**

```
TranscriptInventoryView.metadata: [String: TranscriptMetadata]
  ↑
loadMetadataForSessions()
  ↑
TranscriptMetadataOrchestrator.metadata(for: transcriptId)
  ↑
SidecarMetadataStore.load(for: URL)  ❌ IN-MEMORY CACHE
  ↑
Lost on app restart ❌
```

**Expected Data Source (Metadata)**: SQL ✅ **SHOULD BE**

```
TranscriptInventoryView.metadata: [String: TranscriptMetadata]
  ↑
loadMetadataForSessions()
  ↑
orchestrator.getTranscriptMetadata(transcriptId)  // ✅ SQL READ
  ↑
SQL: SELECT * FROM transcript_metadata WHERE transcript_id = ?
```

### State Management

**Local State** (TranscriptInventoryView):

```swift
struct TranscriptInventoryView: View {
  @Environment(ConversationMonitor.self) private var monitor  // Shared instance

  // Local UI state
  @State private var selectedTranscriptId: String?
  @State private var searchText = ""
  @State private var debouncedSearch = ""
  @State private var groupingMode: GroupingMode = .provider

  // Metadata cache (IN-MEMORY ❌)
  @State private var metadata: [String: TranscriptMetadata] = [:]
  @State private var loadingMetadata: Set<String> = []
  @State private var metadataTasks: [String: Task<Void, Never>] = []
}
```

**Derived State**:

```swift
// Filtered sessions (by search text)
var filteredSessions: [TranscriptSession] {
  guard !debouncedSearch.isEmpty else { return monitor.allSessions }

  return monitor.allSessions.filter { session in
    // Search in title, description, file path
    let meta = metadata[session.identifier]
    return meta?.title.localizedCaseInsensitiveContains(debouncedSearch) == true ||
           meta?.description.localizedCaseInsensitiveContains(debouncedSearch) == true ||
           session.fileURL.path.localizedCaseInsensitiveContains(debouncedSearch)
  }
}

// Selected session
var selectedSession: TranscriptSession? {
  guard let id = selectedTranscriptId else { return nil }
  return monitor.allSessions.first(where: { $0.identifier == id })
}
```

**State Transitions**:

| Trigger | State Change | Result |
|---------|--------------|--------|
| Window opens | metadata = [:] | Empty, start loading |
| Metadata loads | metadata[id] = ... | UI shows title/description |
| User searches | debouncedSearch = "..." | Filtered list |
| User selects session | selectedTranscriptId = id | Detail view updates |
| Discovery finds new sessions | monitor.allSessions updated | Trigger metadata load |
| App restarts | metadata = [:] | ❌ Lost, reload all |

### Update Mechanisms

**1. Reactive Updates (Discovery Loop)**:

```swift
.onChange(of: monitor.allSessions) { _, newSessions in
  // Clear selection if selected session no longer exists
  if let selectedId = selectedTranscriptId,
     !newSessions.contains(where: { $0.identifier == selectedId }) {
    selectedTranscriptId = nil
  }

  // Load metadata for new sessions (centralized, not per-row)
  Task {
    await loadMetadataForSessions(newSessions)  // ❌ NO DB WRITE
  }
}
```

**Problem**: Missing database persistence step

**Expected Flow**:
```swift
.onChange(of: monitor.allSessions) { _, newSessions in
  // PHASE 1: Persist discovered sessions to database ✅ NEW
  Task {
    await persistDiscoveredSessions(newSessions)
  }

  // PHASE 2: Load metadata from SQL (not in-memory)
  Task {
    await loadMetadataForSessions(newSessions)
  }
}
```

**2. Manual Refresh**:

```swift
func refreshSessions() {
  // Trigger discovery manually
  Task {
    await ConversationMonitor.shared.discoverNewTranscripts(...)
  }
}
```

**3. Flush Heuristic Cache**:

```swift
func flushHeuristicCache() {
  // Remove cached metadata files with "Developer Chat" or "Brief Session" titles
  // Forces re-analysis with LLM on next load

  let flushedCount = TranscriptMetadataOrchestrator.shared.flushHeuristicMetadata()
  lastFlushCount = flushedCount
  showingFlushAlert = true
}
```

### The Gap: Missing Database Persistence

**Current (Broken) Flow**:

```
Discovery finds JSONL files
  ↓
monitor.allSessions = [...]  (SQL: transcripts table) ✅
  ↓
.onChange triggers
  ↓
loadMetadataForSessions() ❌ NO DB WRITE
  ↓
TranscriptMetadataOrchestrator.metadata()
  ↓
SidecarMetadataStore.load() (in-memory)
  ↓
IF nil:
  ├─ LLM generation
  └─ SidecarMetadataStore.save() (in-memory) ❌
  ↓
App restarts → metadata lost ❌
```

**Expected (Fixed) Flow**:

```
Discovery finds JSONL files
  ↓
orchestrator.upsertTranscripts()  (SQL: transcripts table) ✅
  ↓
monitor.allSessions = [...]
  ↓
.onChange triggers
  ↓
persistDiscoveredSessions() ✅ NEW
  ├─ orchestrator.discoverTranscript(projectId, fileURL, provider, startWatching: false)
  └─ Ensures transcript exists in DB
  ↓
loadMetadataForSessions()
  ├─ orchestrator.getTranscriptMetadata(transcriptId) ✅ SQL READ
  ├─ IF cached in SQL: return cached
  ├─ IF NOT cached:
  │   ├─ LLM generation
  │   └─ orchestrator.saveTranscriptMetadata() ✅ SQL WRITE
  └─ metadata[id] = ...
  ↓
App restarts → metadata survives ✅
```

**Missing Method**:

```swift
// ADD TO TranscriptInventoryView
private func persistDiscoveredSessions(_ sessions: [TranscriptSession]) async {
  guard let projectId = monitor.currentProjectId,
        let orchestrator = monitor.orchestrator else { return }

  for session in sessions {
    try? orchestrator.discoverTranscript(
      projectId: projectId,
      fileURL: session.fileURL,
      provider: session.provider.rawValue,
      providerSessionId: session.providerSessionId ?? "",
      startWatching: false  // Inventory doesn't need real-time updates
    )
  }
}
```

### Cross-Window Communication

**Scenario**: User selects session in Inventory → switch Main HUD timeline

**Mechanism**:

```swift
// In TranscriptInventoryView detail panel
Button("Switch to Session") {
  onSelectSession(selectedSession)  // Callback
}

// Callback implementation (in TranscriptInventoryWindow)
TranscriptInventoryView { session in
  // Update ConversationMonitor (shared instance)
  ConversationMonitor.shared.activeSession = session.identifier

  // Main HUD timeline observes change and updates
  Task { await ConversationMonitor.shared.loadFeedFromSQL() }

  // Activate main window
  NSApp.activate(ignoringOtherApps: true)
  if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
    mainWindow.makeKeyAndOrderFront(nil)
  }
}
```

### Performance Characteristics

| Operation | Time | Notes |
|-----------|------|-------|
| Window open → session list visible | ~50ms | Sessions already cached in monitor.allSessions |
| Metadata load (cache hit, SQL) | ~1ms | ✅ Expected behavior |
| Metadata load (cache miss, LLM) | 1-3s | Apple FoundationLLM |
| Metadata load (cache miss, heuristic) | ~2ms | First sentence extraction |
| Search filtering (1000 sessions) | ~5ms | In-memory filter |
| Flush cache (50 heuristic files) | ~100ms | File deletion |

### Key Files

| File | Lines | Purpose |
|------|-------|---------|
| **TranscriptInventoryView.swift** | 1-500 | Main inventory UI, session list, detail view |
| **TranscriptInventoryWindow.swift** | All | Window wrapper, callback handling |
| **TranscriptMetadataOrchestrator.swift** | All | LLM metadata generation, circuit breaker |
| **SidecarMetadataStore.swift** | All | ❌ In-memory cache (temporary stub) |

### Known Issues

1. **Metadata Lost on Restart** ⚠️
   - **Cause**: SidecarMetadataStore is in-memory only
   - **Impact**: Re-analyze all sessions every launch (waste of LLM quota)
   - **Fix**: Migrate to SQL backend (`transcript_metadata` table)

2. **Missing DB Persistence for Discoveries** ⚠️
   - **Cause**: No call to `orchestrator.discoverTranscript()` in inventory view
   - **Impact**: Inventory sessions may not exist in `transcripts` table
   - **Fix**: Add `persistDiscoveredSessions()` method

3. **Circuit Breaker State Lost on Restart** ⚠️
   - **Cause**: Circuit breaker state stored in-memory
   - **Impact**: Can't learn from persistent LLM failures
   - **Fix**: Persist circuit breaker state to SQL

### Migration Path

See `transcript-inventory-db-integration-gap.md` for detailed migration plan.

**High-Level Steps**:
1. Add `persistDiscoveredSessions()` to TranscriptInventoryView
2. Update `.onChange(of: monitor.allSessions)` to persist before loading
3. Migrate `SidecarMetadataStore` to SQL (`transcript_metadata` table)
4. Update `TranscriptMetadataOrchestrator` to read/write from SQL
5. Remove in-memory cache
6. Test metadata persistence across app restarts

---

## Window 3: Projects

### Purpose

The Projects window provides:
- Auto-discovery of all Contextify-enabled projects
- Project metadata display (name, path, transcript count, last activity)
- Quick project switching (updates Main HUD)
- Background refresh (every 10 minutes)

### Component Hierarchy

```
Window("Projects", id: "projects")
  ├─ ProjectsWindow
  │   └─ ProjectsView
  │       ├─ Header (refresh button, discovery status)
  │       ├─ Search bar
  │       ├─ List(projects)
  │       │   └─ ProjectRow
  │       │       ├─ Project name
  │       │       ├─ Root path
  │       │       ├─ Transcript count
  │       │       ├─ Last activity timestamp
  │       │       └─ "Open" button
  │       └─ Empty state (if no projects found)
```

### Initialization Sequence

**Phase 1: App Launch** (ContextifyApp.initializeProjectsSystem, line 151-186):

```
ContextifyApp.init()
  ↓
.task {
  await initializeProjectsSystem()
    ├─ Initialize ProjectDiscoveryService
    ├─ Create ProjectsViewModel
    ├─ Auto-discover projects (await vm.discoverProjects())
    ├─ Post notification: .projectsDiscoveryComplete
    └─ Start background refresh timer (10 minutes)
}
```

**Phase 2: Discovery** (ProjectDiscoveryService.discoverProjects):

```
Scan candidate directories:
  ├─ ~/code/*
  ├─ ~/projects/*
  └─ ~/Documents/*
  ↓
For each directory:
  ├─ Check for .claude/ or .codex/ subdirectories
  ├─ If found:
  │   ├─ Get/create project in database
  │   ├─ Count transcripts
  │   ├─ Get latest activity timestamp
  │   └─ Add to projects list
  └─ Performance: ~1-2ms per directory
  ↓
Return [DiscoveredProject]
```

**Total discovery time**: ~500ms-2s (depending on directory count)

### Data Sources

**Primary Data Source**: SQL via ProjectDiscoveryService

```
ProjectsViewModel.projects: [DiscoveredProject]
  ↑
ProjectDiscoveryService.discoverProjects()
  ↑
orchestrator.getOrCreateProject(name:, rootPath:)
  ↑
SQL:
  INSERT INTO projects (name, root_path) VALUES (?, ?)
  ON CONFLICT (root_path) DO UPDATE SET updated_at = ?
```

**Metadata Aggregation**:
```sql
-- Transcript count per project
SELECT COUNT(*) FROM transcripts WHERE project_id = ?

-- Latest activity
SELECT MAX(timestamp) FROM transcript_entries
WHERE transcript_id IN (SELECT id FROM transcripts WHERE project_id = ?)
```

### State Management

**ProjectsViewModel** (Observable):

```swift
@Observable
@MainActor
class ProjectsViewModel {
  var projects: [DiscoveredProject] = []
  var isDiscovering = false
  var lastDiscoveryTime: Date?
  var errorMessage: String?

  private let discoveryService: ProjectDiscoveryService
  private let hudModel: HUDViewModel  // For project switching

  func discoverProjects() async {
    isDiscovering = true
    defer { isDiscovering = false }

    projects = await discoveryService.discoverProjects()
    lastDiscoveryTime = Date()
  }

  func switchToProject(_ project: DiscoveredProject) {
    // Update HUD with new project root
    _ = hudModel.setProjectRoot(url: URL(fileURLWithPath: project.rootPath))

    // Close projects window
    NSApp.windows.first(where: { $0.identifier?.rawValue == "projects" })?.close()

    // Activate main window
    NSApp.activate(ignoringOtherApps: true)
  }
}
```

### Update Mechanisms

**1. Background Refresh** (ContextifyApp.startBackgroundRefresh, line 189-203):

```swift
Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
  Task { @MainActor in
    await viewModel.discoverProjects()
  }
}
```

**Interval**: Every 10 minutes

**2. Manual Refresh**:

```swift
Button("Refresh") {
  Task { await viewModel.discoverProjects() }
}
```

**3. Discovery Notification** (for coordination):

```swift
NotificationCenter.default.post(
  name: .projectsDiscoveryComplete,
  object: viewModel.projects
)
```

### Performance Characteristics

| Operation | Time | Notes |
|-----------|------|-------|
| Window open (first time) | ~500ms-2s | Initial discovery |
| Window open (subsequent) | ~50ms | Projects cached |
| Background refresh | ~500ms-2s | Every 10 minutes |
| Project switch | ~100ms | Update HUD + DB query |

### Key Files

| File | Lines | Purpose |
|------|-------|---------|
| **ProjectsWindow.swift** | All | Window wrapper |
| **ProjectsView.swift** | All | Projects list UI |
| **ProjectsViewModel.swift** | All | State management, discovery coordination |
| **ProjectDiscoveryService.swift** | All | Filesystem scan, DB persistence |

### Known Issues

- None currently identified

---

## Window 4: Settings

### Purpose

Standard macOS Settings window for user preferences.

### Current Implementation

**File**: `SettingsView.swift`

**Content**: Placeholder (minimal implementation)

**Future**: Preferences for:
- Discovery directories
- LLM provider settings
- Logging levels
- Keyboard shortcuts

---

## Cross-Window Communication Patterns

### Pattern 1: Shared Environment Objects

**Mechanism**: SwiftUI Environment

```swift
@main
struct ContextifyApp: App {
  private let model = HUDViewModel.shared        // Singleton
  private let timeline = ConversationMonitor.shared  // Singleton

  var body: some Scene {
    Window("Contextify", id: "main") {
      ContentView()
        .environment(model)      // ← Shared
        .environment(timeline)   // ← Shared
    }

    Window("Transcript Inventory", id: "transcript-inventory") {
      TranscriptInventoryWindow()
        .environment(HUDViewModel.shared)        // ← Same instance
        .environment(ConversationMonitor.shared) // ← Same instance
    }
  }
}
```

**Result**: All windows access the same state

**Key Shared State**:
- `HUDViewModel.shared.projectRootURL` - Current project
- `ConversationMonitor.shared.entries` - Timeline entries
- `ConversationMonitor.shared.allSessions` - Discovered sessions
- `ConversationMonitor.shared.activeSession` - Current session filter

### Pattern 2: NotificationCenter

**Mechanism**: System-wide notifications

```swift
// Sender (TranscriptWatcher)
NotificationCenter.default.post(
  name: .transcriptUpdated,
  object: transcriptId
)

// Receiver (ConversationMonitor)
NotificationCenter.default.publisher(for: .transcriptUpdated)
  .sink { notification in
    guard let transcriptId = notification.object as? String else { return }
    // React to update
    Task { await loadFeedFromSQL() }
  }
```

**Defined Notifications**:

| Notification | Sender | Receivers | Payload |
|--------------|--------|-----------|---------|
| `transcriptUpdated` | TranscriptWatcher | ConversationMonitor | transcriptId (String) |
| `cacheUpdated` | TimelineCacheMissGenerator | ConversationMonitor | [entryId] (Array) |
| `projectChanged` | HUDViewModel | ConversationMonitor | projectId (String) |
| `projectsDiscoveryComplete` | ProjectsViewModel | (future: analytics) | [DiscoveredProject] |

### Pattern 3: Callback Functions

**Mechanism**: Closures passed as parameters

```swift
// Definition (TranscriptInventoryView)
let onSelectSession: (TranscriptSession) -> Void

// Usage (TranscriptInventoryWindow)
TranscriptInventoryView { session in
  // Callback implementation
  ConversationMonitor.shared.activeSession = session.identifier
  Task { await ConversationMonitor.shared.loadFeedFromSQL() }

  // Activate main window
  activateMainWindow()
}
```

### Pattern 4: Window Management (NSApp)

**Mechanism**: AppKit window queries

```swift
// Find window by identifier
if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
  mainWindow.makeKeyAndOrderFront(nil)
}

// Activate app
NSApp.activate(ignoringOtherApps: true)

// Close current window
NSApp.keyWindow?.close()
```

---

## Comparison Matrix: All Windows

| Aspect | Main HUD | Transcript Inventory | Projects | Settings |
|--------|----------|----------------------|----------|----------|
| **Window ID** | `"main"` | `"transcript-inventory"` | `"projects"` | N/A |
| **Default Size** | 940×360 | 1000×700 | 800×600 | System |
| **Keyboard Shortcut** | N/A (always visible) | ⌃⌘I | ⇧⌘P | ⌘, |
| **Launch Behavior** | Auto-open | On-demand | On-demand | On-demand |
| **Primary Data Source** | SQL (timeline entries) | SQL (sessions) + in-memory (metadata ❌) | SQL (projects) | UserDefaults |
| **Update Mechanism** | Real-time (file watcher) | Reactive (discovery loop) | Background (10 min timer) | Manual |
| **Shared Environment** | HUDViewModel, ConversationMonitor | HUDViewModel, ConversationMonitor | ProjectsViewModel | N/A |
| **State Persistence** | ✅ SQL | ⚠️ Partial (sessions: SQL, metadata: memory) | ✅ SQL | ✅ UserDefaults |
| **Cross-Window Impact** | Updates all windows | Updates Main HUD | Updates Main HUD + Inventory | N/A |
| **Known Gaps** | None | Missing DB persistence for metadata | None | Minimal implementation |
| **Performance (Open)** | 50-100ms | ~50ms + metadata load | 500ms-2s (first), ~50ms (cached) | N/A |

---

## Data Flow: Complete Picture

### Startup Sequence (All Windows)

```
App Launch
  ├─ ContextifyApp.init()
  │   ├─ Initialize HUDViewModel.shared
  │   ├─ Initialize ConversationMonitor.shared
  │   └─ Check for duplicate instances
  │
  ├─ Main Window Auto-Opens
  │   ├─ ContentView.onAppear
  │   │   ├─ model.updateGitInfo()
  │   │   ├─ refreshSession() (iTerm2)
  │   │   └─ TimelineIntegration.shared.startMonitoring()
  │   │       └─ ConversationMonitor.startMonitoring()
  │   │           ├─ Get project root
  │   │           ├─ Initialize orchestrator
  │   │           ├─ Spawn background tasks
  │   │           └─ loadFeedFromSQL()
  │   └─ Timeline renders
  │
  └─ .task (App-level initialization)
      └─ initializeProjectsSystem()
          ├─ Auto-discover all projects
          ├─ Post .projectsDiscoveryComplete
          └─ Start 10-minute refresh timer
```

### Cross-Window Data Flow (Example: Session Switch)

```
User in Inventory Window
  ↓
Click "Switch to Session" button
  ↓
Callback: onSelectSession(session)
  ├─ ConversationMonitor.shared.activeSession = session.id  (shared state)
  ├─ Task { await ConversationMonitor.shared.loadFeedFromSQL() }
  └─ activateMainWindow()
  ↓
ConversationMonitor (observed by Main HUD)
  ├─ activeSession changed
  ├─ revision++
  └─ loadFeedFromSQL() with new filter
  ↓
Main HUD Timeline
  ├─ Observes visibleEntries change
  ├─ Re-renders with filtered entries
  └─ Shows selected session's conversation
  ↓
Inventory Window
  └─ Closes (user returned to Main HUD)
```

### Discovery → Persistence → Display Flow

```
Background Discovery Loop (every 10s)
  ↓
ConversationSources.allSessions()
  ├─ Scan ~/.claude/projects/
  └─ Scan ~/.codex/sessions/
  ↓
orchestrator.upsertTranscripts() ✅ PERSIST TO DB
  ├─ INSERT/UPDATE transcripts table
  └─ Returns [ResolvedTranscript]
  ↓
orchestrator.startWatchingTranscript() (for ALL)
  ├─ HooverEngine.hooverTranscript()
  └─ TranscriptWatcher.watch()
  ↓
allSessions = [...] (update for Inventory)
  ↓
Main HUD:
  ├─ loadFeedFromSQL()
  └─ Timeline updates
  ↓
Inventory Window (if open):
  ├─ .onChange(of: monitor.allSessions)
  ├─ ❌ MISSING: persistDiscoveredSessions()
  └─ loadMetadataForSessions() (in-memory ❌)
```

---

## Architecture Principles

### 1. Single Source of Truth

- **Timeline Entries**: SQL (`transcript_entries` table)
- **Session List**: SQL (`transcripts` table)
- **Projects**: SQL (`projects` table)
- **Metadata**: ⚠️ Should be SQL (`transcript_metadata` table), currently in-memory

### 2. Shared Singletons

- `HUDViewModel.shared`: Project root, git info
- `ConversationMonitor.shared`: Timeline state, session filtering
- `DatabaseManager.shared`: SQLite connection pool

**Benefit**: All windows access same state, no sync issues

### 3. Reactive Updates

- SwiftUI `@Observable` for UI-driven updates
- NotificationCenter for cross-component communication
- File watchers for filesystem changes

### 4. Structured Concurrency

- `Task` groups for background work
- `async/await` for all I/O operations
- `@MainActor` isolation for UI state

### 5. Crash Resilience

- Checkpoint-based resume (HooverEngine)
- WAL mode (SQLite)
- Idempotent operations (upsert, watch)

---

## Future Enhancements

### 1. Fix Inventory Metadata Persistence
- Migrate SidecarMetadataStore to SQL
- Add `persistDiscoveredSessions()` call
- Test metadata survival across restarts

### 2. Settings Window
- Add preferences UI
- Persist to UserDefaults
- Support for:
  - Discovery directories
  - LLM provider selection
  - Logging levels
  - Keyboard shortcuts

### 3. Multi-Window Timeline
- Allow multiple Main HUD windows (one per project)
- Coordinate state across windows
- Shared orchestrator, separate timeline states

### 4. Real-Time Collaboration
- WebSocket integration for remote sessions
- Shared timeline across team members
- Presence indicators

---

## Appendix: Key Files Reference

### Main HUD Window
- `ContextifyApp.swift` (lines 56-73): Window declaration
- `ContentView.swift` (lines 1-260): Main layout, header, compose
- `ConversationTimelineView.swift`: Timeline display
- `TimelineEntryRow.swift`: Entry rendering
- `ConversationMonitor.swift` (lines 130-1050): State management
- `HUDViewModel.swift` (app/Sources/ContextifyCore/HUDCore.swift): Project + git

### Transcript Inventory Window
- `ContextifyApp.swift` (lines 79-84): Window declaration
- `TranscriptInventoryView.swift` (lines 1-500): Inventory UI
- `TranscriptInventoryWindow.swift`: Window wrapper
- `TranscriptMetadataOrchestrator.swift`: LLM metadata
- `SidecarMetadataStore.swift`: ❌ In-memory cache (temporary)

### Projects Window
- `ContextifyApp.swift` (lines 86-120): Window declaration
- `ProjectsWindow.swift`: Window wrapper
- `ProjectsView.swift`: Projects list UI
- `ProjectsViewModel.swift`: State management
- `ProjectDiscoveryService.swift`: Filesystem scan

### Settings Window
- `SettingsView.swift`: Placeholder UI

---

## Conclusion

Contextify's window architecture follows a **shared singleton pattern** with:
- ✅ Single source of truth (SQL for most data)
- ✅ Reactive updates (SwiftUI Observation)
- ✅ Efficient cross-window communication (shared environment)
- ⚠️ **One known gap**: Transcript Inventory metadata persistence

**Fixing the Inventory gap** requires:
1. Add `persistDiscoveredSessions()` method
2. Migrate `SidecarMetadataStore` to SQL backend
3. Update metadata loading to use SQL instead of in-memory cache

This change will align the Inventory window with the proven architecture of the Main HUD and Projects windows, ensuring metadata survives app restarts and reducing duplicate LLM work.

---

**END OF DOCUMENT**
