# Project Switcher Navigation Bar

**Status:** Proposed
**Priority:** High
**Related:** Multi-project support, transcript monitoring, user experience

Add a navigation bar above the main window that displays all discovered projects with active transcripts and allows quick switching between them with unread indicators.

## Current Behavior

- Contextify monitors a single project at a time (set via "Set Project Root" button or environment variable)
- When switching projects, all watchers for the previous project are stopped
- No visibility into other projects that have active transcripts
- Users must manually switch project root to see activity in other repositories
- No indication when transcripts receive updates in non-active projects

## Proposed Functionality

### Multi-Project Navigation Bar

Transform Contextify from a single-project monitor into a multi-project dashboard with persistent monitoring across all discovered projects.

#### 1. Project Discovery

- **Global scan**: Discover all projects with transcripts in `~/.claude/projects/` and `~/.codex/sessions/`
- **Automatic detection**: Parse directory names back to project paths (reverse Claude Code's path mangling)
- **Database registration**: Create/upsert projects in database for each discovered project
- **Continuous monitoring**: Run discovery loop periodically (every 30s) to detect new projects

#### 2. Navigation Bar Display

- **Placement**: Horizontal bar above existing project root/branch header
- **Project tabs**: Show project name (derived from path, e.g., "contextify", "my-app")
- **Active indicator**: Highlight currently active project
- **Unread badges**: Show count of new entries in non-active projects
- **Overflow handling**: Horizontal scroll or "More..." menu for >6 projects

#### 3. Unread Tracking

- **Visit timestamps**: Track `last_viewed_at` per project in database
- **Unread calculation**: Count entries with `timestamp > last_viewed_at`
- **Real-time updates**: Increment unread count when `TranscriptUpdated` notification arrives for non-active project
- **Reset on switch**: Clear unread count when user switches to that project

#### 4. Project Switching

- **Click to switch**: Tap project tab to switch active project
- **Preserves watchers**: Keep all project watchers running (don't stop previous project)
- **Timeline refresh**: Load timeline entries for newly selected project
- **Branch info update**: Show git branch for newly selected project

## UI Design

### Option A: Segmented Control Style (Recommended)

```
┌────────────────────────────────────────────────────────┐
│  contextify  │  website  │  api-server (3)  │  cli-tools  │
└────────────────────────────────────────────────────────┘
├────────────────────────────────────────────────────────┤
│ Project: /Users/rob/code/projects/contextify          │
│ Branch: main                                           │
├────────────────────────────────────────────────────────┤
│ [Timeline entries...]                                  │
```

- Active project has filled background
- Unread badges show as `(3)` next to project name
- Compact horizontal layout

### Option B: Chip/Pill Style

```
┌────────────────────────────────────────────────────────┐
│  [contextify]  [website]  [api-server ●3]  [cli-tools]  │
└────────────────────────────────────────────────────────┘
```

- Rounded chips with borders
- Badge as red dot with count
- More visual weight, better for accessibility

### Option C: Minimal Text List

```
┌────────────────────────────────────────────────────────┐
│ contextify  •  website  •  api-server (3)  •  cli-tools  │
└────────────────────────────────────────────────────────┘
```

- Text-only with separators
- Least visual weight
- May be harder to see active state

### Unread Badge Styling

- **Color**: System accent color (blue) or attention color (orange/red)
- **Position**: Trailing the project name `"api-server (3)"`
- **Alternative**: Small circular badge superimposed on top-right of tab
- **Animation**: Subtle pulse when count increases
- **Max count**: Show "99+" for counts over 99

## Technical Architecture

### System Transformation: Single → Multi-Project

#### Current Architecture (Single Project)

```
ConversationMonitor.startMonitoring()
  ↓
discoverNewTranscripts(projectId: current)
  ↓
Scans .claude/projects/{CURRENT-project-only}/
  ↓
Starts watchers for current project's transcripts
  ↓
TranscriptUpdated notification (projectId)
  ↓
Filters: only process if projectId == currentProjectId
```

**Problem**: Discovery and watching are scoped to one project. Switching projects tears down watchers.

#### New Architecture (Multi-Project)

```
ProjectActivityMonitor.startGlobalMonitoring()
  ↓
discoverAllProjects()
  ├─ Scans ALL directories in .claude/projects/
  ├─ Parses directory names → project paths
  └─ Creates/upserts projects in database
  ↓
For each project:
  ├─ discoverTranscripts(projectId)
  └─ Start watchers for all transcripts
  ↓
TranscriptUpdated notification (projectId)
  ↓
Branch 1: if projectId == currentProjectId
  └─ Refresh timeline (existing behavior)
Branch 2: if projectId != currentProjectId
  └─ Increment project_visits.unread_count
```

**Key changes**:
1. Discovery scans all projects, not just current
2. Watchers persist across project switches
3. Notifications are processed for all projects (not filtered out)

### Component Specifications

#### 1. ProjectActivityMonitor

**Purpose**: Global coordinator for multi-project discovery and watching.

**Location**: `app/Sources/ContextifyCore/ProjectActivityMonitor.swift`

**Responsibilities**:
- Scan all project directories in `~/.claude/projects/` and `~/.codex/sessions/`
- Parse directory names to extract project paths
- Create/upsert projects in database
- Discover transcripts for all projects
- Maintain persistent watchers for all projects (don't tear down on switch)
- Periodic refresh (every 30s) to detect new projects

**API**:
```swift
public final class ProjectActivityMonitor {
  public init(orchestrator: TranscriptOrchestrator)

  // Start global monitoring (all projects)
  public func startGlobalMonitoring() async throws

  // Stop all monitoring and watchers
  public func stopAll()

  // Get list of all discovered projects
  public func getAllProjects() throws -> [Project]

  // Get unread counts for all projects
  public func getUnreadCounts() throws -> [String: Int]
}
```

#### 2. Database Schema: project_visits Table

**Purpose**: Track user visits and unread counts per project.

**Schema**:
```sql
CREATE TABLE project_visits (
  project_id TEXT PRIMARY KEY NOT NULL,
  last_viewed_at INTEGER NOT NULL,  -- Unix timestamp
  unread_count INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

CREATE INDEX idx_project_visits_last_viewed ON project_visits(last_viewed_at);
```

**Operations**:
- `updateLastViewed(projectId)`: Set `last_viewed_at = now()`, reset `unread_count = 0`
- `incrementUnreadCount(projectId)`: Increment `unread_count += 1`
- `getUnreadCounts()`: Return map of `projectId → unread_count` for all projects
- `calculateUnreadCount(projectId)`: Query entries with `timestamp > last_viewed_at`

#### 3. ProjectSwitcherState

**Purpose**: Observable state for project switcher UI.

**Location**: `Contextify/Contextify/ProjectSwitcherState.swift`

**Responsibilities**:
- Query all projects with transcripts from database
- Subscribe to `TranscriptUpdated` notifications
- Maintain unread counts per project
- Provide project switching API

**Implementation**:
```swift
@MainActor
@Observable
final class ProjectSwitcherState {
  private let orchestrator: TranscriptOrchestrator
  private let activityMonitor: ProjectActivityMonitor

  // All discovered projects
  private(set) var allProjects: [ProjectInfo] = []

  // Currently active project ID
  private(set) var activeProjectId: String?

  // Unread counts per project
  private(set) var unreadCounts: [String: Int] = [:]

  struct ProjectInfo: Identifiable, Sendable {
    let id: String  // project_id
    let name: String  // display name
    let rootPath: String
    let transcriptCount: Int
  }

  init(orchestrator: TranscriptOrchestrator, activityMonitor: ProjectActivityMonitor) {
    self.orchestrator = orchestrator
    self.activityMonitor = activityMonitor

    // Subscribe to transcript updates
    setupNotificationObservers()

    // Initial load
    Task { await refreshProjects() }
  }

  func refreshProjects() async {
    // Query all projects from database
    // Query unread counts
    // Update allProjects and unreadCounts
  }

  func switchToProject(_ projectId: String) async {
    // Update activeProjectId
    // Reset unread count for this project
    // Notify HUDViewModel to update project root
    // Trigger timeline refresh in ConversationMonitor
  }

  private func setupNotificationObservers() {
    // Listen for TranscriptUpdated notifications
    // If projectId != activeProjectId, increment unread count
  }
}
```

#### 4. ProjectSwitcherView

**Purpose**: SwiftUI component for project navigation bar.

**Location**: `Contextify/Contextify/ProjectSwitcherView.swift`

**Implementation**:
```swift
struct ProjectSwitcherView: View {
  @Environment(ProjectSwitcherState.self) private var state

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(state.allProjects) { project in
          ProjectTabView(
            project: project,
            isActive: project.id == state.activeProjectId,
            unreadCount: state.unreadCounts[project.id] ?? 0
          )
          .onTapGesture {
            Task {
              await state.switchToProject(project.id)
            }
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .background(.background.secondary)
  }
}

struct ProjectTabView: View {
  let project: ProjectSwitcherState.ProjectInfo
  let isActive: Bool
  let unreadCount: Int

  var body: some View {
    HStack(spacing: 4) {
      Text(project.name)
        .font(.subheadline)
        .fontWeight(isActive ? .semibold : .regular)

      if unreadCount > 0 {
        Text("(\(unreadCount))")
          .font(.caption)
          .foregroundStyle(.blue)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
    )
  }
}
```

### Integration Points

#### 1. ConversationMonitor Changes

**Current**: Filters `TranscriptUpdated` notifications to only process current project.

**Change**: Remove filter, branch on `projectId`:
```swift
private func watchForDebouncedTranscriptUpdates() async {
  for await note in center.notifications(named: name) {
    let pid = note.userInfo?["projectId"] as? String

    await MainActor.run { [weak self] in
      guard let self else { return }

      if pid == self.currentProjectId {
        // Existing behavior: refresh timeline
        self.debounceTask?.cancel()
        self.debounceTask = Task {
          try? await Task.sleep(nanoseconds: 150_000_000)
          await self.processIncrementalUpdate()
        }
      } else if let projectId = pid {
        // NEW: increment unread count for other project
        Task {
          try? await ProjectSwitcherState.shared.incrementUnreadCount(projectId: projectId)
        }
      }
    }
  }
}
```

#### 2. HUDViewModel Integration

**Add method**:
```swift
@MainActor
func switchToProject(_ projectPath: String) {
  // Update project root URL
  self.projectRootURL = URL(fileURLWithPath: projectPath)

  // Post notification (ConversationMonitor listens to this)
  NotificationCenter.default.post(
    name: NSNotification.Name("ProjectRootChanged"),
    object: projectPath
  )

  // Refresh git info
  Task { await updateGitInfo() }
}
```

#### 3. ContentView Integration

**Add ProjectSwitcherView above header**:
```swift
var body: some View {
  VStack(spacing: 0) {
    // NEW: Project switcher
    if projectSwitcherState.allProjects.count > 1 {
      ProjectSwitcherView()
        .environment(projectSwitcherState)
    }

    // Existing content
    header
    ConversationTimelineView()
    StatusBarView()
  }
}
```

## Implementation Phases

### Phase 1: Database Foundation (~1 day)

**Goal**: Add project visit tracking to database.

**Tasks**:
1. Add `project_visits` table to `DatabaseSchema.swift`
2. Create migration (v8 or next available)
3. Add `ProjectVisitsRepository` protocol and implementation
4. Add methods: `updateLastViewed()`, `incrementUnreadCount()`, `getUnreadCounts()`
5. Unit tests for repository

**Deliverable**: Database can track visits and unread counts.

### Phase 2: Global Discovery (~2 days)

**Goal**: Discover all projects across all transcript providers.

**Tasks**:
1. Create `ProjectActivityMonitor` class
2. Implement `discoverAllProjects()` to scan `~/.claude/projects/` and `~/.codex/sessions/`
3. Parse directory names back to project paths (reverse mangling)
4. Upsert projects into database
5. Discover transcripts for all projects
6. Start watchers for all transcripts (reuse existing `TranscriptWatcher`)
7. Periodic refresh loop (every 30s)
8. Integration tests with fixture directories

**Deliverable**: All projects are discovered and watched, regardless of active project.

### Phase 3: State Management (~1 day)

**Goal**: Observable state for UI binding.

**Tasks**:
1. Create `ProjectSwitcherState` class
2. Query all projects and unread counts from database
3. Subscribe to `TranscriptUpdated` notifications
4. Implement unread count increment logic
5. Add `switchToProject()` method
6. Unit tests with mock orchestrator and notifications

**Deliverable**: Observable state that tracks projects and unread counts.

### Phase 4: UI Implementation (~1 day)

**Goal**: Build project switcher UI component.

**Tasks**:
1. Create `ProjectSwitcherView` SwiftUI component
2. Create `ProjectTabView` for individual tabs
3. Implement unread badge rendering
4. Add active state styling
5. Handle tap gestures to switch projects
6. SwiftUI previews with mock data

**Deliverable**: Functional UI component that displays projects and badges.

### Phase 5: Integration (~1 day)

**Goal**: Wire everything together.

**Tasks**:
1. Modify `ConversationMonitor.watchForDebouncedTranscriptUpdates()` to handle non-active projects
2. Add `HUDViewModel.switchToProject()` method
3. Initialize `ProjectActivityMonitor` in app startup
4. Initialize `ProjectSwitcherState` and inject into SwiftUI environment
5. Add `ProjectSwitcherView` to `ContentView`
6. Integration tests: switch projects, verify timeline updates, verify unread counts

**Deliverable**: Fully functional multi-project switching.

### Phase 6: Polish & Testing (~1 day)

**Goal**: Edge cases, animations, comprehensive tests.

**Tasks**:
1. Handle no projects (hide switcher)
2. Handle single project (hide switcher or show grayed out)
3. Handle many projects (horizontal scroll or overflow menu)
4. Add subtle animations for unread count changes
5. Add loading states during project switch
6. Comprehensive test suite: unit, integration, UI tests
7. Performance testing with 10+ projects

**Deliverable**: Production-ready feature with full test coverage.

## Database Queries

### Unread Count Calculation

```sql
-- Get unread count for a specific project
SELECT COUNT(*)
FROM entries e
JOIN transcripts t ON e.transcript_id = t.id
JOIN project_visits pv ON t.project_id = pv.project_id
WHERE t.project_id = ?
  AND e.timestamp > pv.last_viewed_at;

-- Get unread counts for all projects
SELECT
  t.project_id,
  COUNT(*) as unread_count
FROM entries e
JOIN transcripts t ON e.transcript_id = t.id
JOIN project_visits pv ON t.project_id = pv.project_id
WHERE e.timestamp > pv.last_viewed_at
GROUP BY t.project_id;
```

### All Projects with Transcripts

```sql
SELECT
  p.id,
  p.name,
  p.root_path,
  COUNT(DISTINCT t.id) as transcript_count
FROM projects p
JOIN transcripts t ON p.id = t.project_id
GROUP BY p.id
ORDER BY p.name;
```

## Edge Cases & Error Handling

### Empty States

- **No projects found**: Hide project switcher, show onboarding message
- **Single project**: Option to hide switcher (controlled by preference)
- **Project has no transcripts**: Don't show in switcher (filter in query)

### Project Path Ambiguity

- **Multiple projects with same name**: Show disambiguating path segments
  - Example: "contextify (/Users/rob/...)" vs "contextify (/Users/rob/work/...)"
- **Very long project names**: Truncate with ellipsis "my-very-long-pr..."

### Unread Count Edge Cases

- **Never visited project**: Show all entries as unread
- **Project visited before entries existed**: `last_viewed_at` older than oldest entry, no unread
- **Very large unread count**: Show "99+" to avoid layout issues
- **Negative unread count** (bug): Clamp to 0

### Performance Considerations

- **Many projects (>20)**: Consider pagination or "show more" dropdown
- **High-frequency updates**: Debounce unread count updates (same 150ms as timeline)
- **Large transcripts**: Unread count query should use indexed timestamp column

### Concurrency & Race Conditions

- **Rapid project switching**: Cancel in-flight timeline loads from previous project
- **Simultaneous updates**: Use database transactions for visit timestamp updates
- **Watcher lifecycle**: Ensure watchers aren't double-started on re-discovery

## User Benefits

- **Multi-tasking**: Monitor multiple projects simultaneously without manual switching
- **Awareness**: See when other projects receive activity via unread badges
- **Efficiency**: Quick switching between projects without "Set Project Root" dialog
- **Context preservation**: Timeline state preserved per project (no loss of scroll position)

## Future Enhancements

### Phase 7+ (Future)

- **Project favorites/pinning**: Pin frequently used projects to top of list
- **Project search/filter**: Search projects by name when list is large
- **Keyboard shortcuts**: Cmd+1, Cmd+2, etc. to switch to project by index
- **Project colors**: User-assignable colors for visual distinction
- **Project grouping**: Group related projects (e.g., by organization or workspace)
- **Unread timestamp**: Show "Last updated 5m ago" tooltip on badge hover
- **Desktop notifications**: Optional system notification when non-active project receives updates
- **Project context menu**: Right-click project tab for options (Reveal in Finder, Open in Terminal, etc.)

## Testing Strategy

### Unit Tests

- `ProjectActivityMonitor`: Discovery logic, path parsing, project upsert
- `ProjectSwitcherState`: Unread count calculation, notification handling
- `ProjectVisitsRepository`: Database operations, SQL correctness

### Integration Tests

- End-to-end: Discover projects → Start watchers → Receive updates → Increment unread → Switch projects → Reset unread
- Concurrent updates: Multiple transcripts updating simultaneously
- Database integrity: Foreign key constraints, cascading deletes

### UI Tests

- Project switching workflow
- Unread badge rendering
- Active state styling
- Overflow handling (many projects)

### Performance Tests

- Discovery speed with 20+ projects
- Timeline refresh speed when switching
- Unread count query performance with large entry counts

## Related Work

- See `build/notes/technical-reference/sql-backend-architecture.md` for database design
- See `build/notes/technical-reference/conversation-monitor-state-architecture.md` for state management
- See `build/notes/feature-specs/status-bar-spec.md` for related UI component pattern
