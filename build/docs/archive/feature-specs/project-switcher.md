# Project Switcher Navigation Bar

**Status:** Proposed → Ready for Phase 0 (Post-Ultrathink + Colleague Review)
**Priority:** High
**Readiness:** 4.0/5 (ready to start Phase 0)
**Related:** Multi-project support, transcript monitoring, user experience
**Last Updated:** 2025-10-27 (Simplified for pre-production hard cutover)

Add a navigation bar above the main window that displays all discovered projects with active transcripts and allows quick switching between them with unread indicators.

## Executive Summary

* **Vision**: Transform Contextify from **single-project monitoring** to **multi-project dashboard** with event-driven discovery, unread badges, and instant switching.
* **Core Architecture**: FSEvents-based discovery → **ProjectActivityMonitor** (actor, single watcher owner) → DB-derived unread counts (immutable timestamps) → SwiftUI navigation bar with overflow/keyboard shortcuts.
* **Top Risks**: (1) Duplicate/unstable project identity (reverse path-mangling), (2) watcher lifecycle leaks, (3) unread correctness & clock skew, (4) N× watcher scaling, (5) schema migration safety.
* **Discovery Model**: **FSEvents-first** on `~/.claude/projects/` and `~/.codex/sessions/` with targeted rescan on change; 30s polling **fallback only** (not primary).
* **Database Schema**: New **project_visits** table `(project_id, last_viewed_at, last_selected_at, pinned)` with proper FKs and indices; unread = `entries.created_at > last_viewed_at`.
* **Concurrency Pattern**: Single owners per domain—**ProjectActivityMonitor** (actor) for watchers, **ProjectRepository** via **DatabaseActor**—to funnel mutations and eliminate cross-actor races.
* **UX Requirements**: Overflow to "More…" popover when >6 projects; badges cap at **99+**; **Cmd+1…9** shortcuts; full VoiceOver labels and 44pt hit targets.
* **Integration**: Status Bar remains health/AI surface; switcher controls **project selection** and **timeline refresh**; guard against double refresh and branch header flicker.
* **Privacy**: Display names by default, full paths only in tooltips; one-time **consent dialog** for global scan; log redaction enabled by default.
* **Must-Fix Before Build**: Identity spec, watcher dedupe/keys, DB migration script, unread SQL + indices, accessibility acceptance criteria, privacy consent UX.

## Current Behavior (Single-Project Mode)

1. User sets project root → ConversationMonitor starts watchers for that project only
2. File changes → ad-hoc notifications → TranscriptOrchestrator updates DB/metadata
3. HUD/Main UI refresh for current project only
4. **Limitations**:
   - No visibility into other projects with active transcripts
   - When switching projects, all watchers for previous project are stopped
   - Users must manually switch project root to see activity elsewhere
   - No unread indicators or "what changed while I was away"
   - No multi-tasking across concurrent work streams

## Proposed Functionality

### Multi-Project Navigation Bar

Transform Contextify from a single-project monitor into a multi-project dashboard with persistent monitoring across all discovered projects.

#### 1. Project Discovery (FSEvents-First)

- **FSEvents monitoring**: Register **FSEvents** on transcript roots (`~/.claude/projects/` and `~/.codex/sessions/`)
- **Targeted rescan**: On FSEvents change notification, perform targeted directory scan (not full tree walk)
- **Fallback polling**: 30s polling **only** when FSEvents unavailable or erroring (with telemetry alert)
- **Path reverse-mangling**: Parse directory names back to absolute project paths using **stable reverse-mangle spec** (see Project Identity section)
- **Database registration**: Create/upsert projects with stable `project_id` = `SHA256(<provider>:<normalizedAbsolutePath>)`
- **Collision handling**: Same project path across multiple roots → prefer newest `entries.created_at`; log warning
- **ASSUMPTION**: App is not sandboxed; has direct FS access to transcript roots

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
│  contextify  │  website  │  api-server (3)  │  cli-tools  │  [Project Switcher]
└────────────────────────────────────────────────────────┘
├────────────────────────────────────────────────────────┤
│ Project: /Users/rob/code/projects/contextify          │  [Current Header]
│ Branch: main                                           │
├────────────────────────────────────────────────────────┤
│ [Timeline entries...]                                  │  [Main Content]
├────────────────────────────────────────────────────────┤
│ [●] Apple Intelligence  |  Processing 12 items (~6s)  │  [Status Bar Footer]
└────────────────────────────────────────────────────────┘
```

- Active project has filled background
- Unread badges show as `(3)` next to project name
- Compact horizontal layout
- **Placement**: Above existing header, does not conflict with status bar footer

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

#### 1. ProjectActivityMonitor (Actor - Single Watcher Owner)

**Purpose**: Actor that owns all watcher lifecycle. **Single source of truth** for which projects are being watched.

**Location**: `app/Sources/ContextifyCore/ProjectActivityMonitor.swift`

**Actor Guarantees**:
- **Idempotent watcher start**: Calling `startWatcher(projectId)` twice returns same handle
- **No double-starts**: Internal `Dictionary<ProjectID, WatchHandle>` ensures exactly one watcher per project
- **Cancellation safety**: All AsyncSequence watchers properly cancel on stop/rediscovery
- **Serial mutations**: All watcher lifecycle operations serialized through actor

**Responsibilities**:
- Monitor FSEvents on `~/.claude/projects/` and `~/.codex/sessions/` (with fallback polling)
- Parse directory names via **reverse-mangle spec** to extract absolute project paths
- Create/upsert projects in database with stable `project_id`
- Discover transcripts for all projects
- Maintain persistent watchers for all projects (keyed by `project_id`)
- Emit `AsyncSequence<ProjectEvent>` for UI consumption
- Handle collision detection and logging

**API**:
```swift
public actor ProjectActivityMonitor {
  public init(orchestrator: TranscriptOrchestrator, discovery: ProjectDiscovery)

  // Start global monitoring (FSEvents + fallback polling)
  public func startGlobalMonitoring() async throws

  // Stop all monitoring and watchers (cancels all AsyncSequence tasks)
  public func stopAll()

  // Idempotent watcher start (returns existing handle if already started)
  public func ensureWatcher(projectId: String) async throws -> WatchHandle

  // Stop watcher for specific project (removes from active set)
  public func stopWatcher(projectId: String) async

  // Event stream for UI (debounced per-project)
  public nonisolated func observeProjectEvents() -> AsyncStream<ProjectEvent>
}

public struct ProjectEvent: Sendable {
  let projectId: String
  let kind: EventKind  // .discovered, .transcriptUpdated, .removed
  let timestamp: Date
}
```

**Key Pattern**: UI never starts watchers directly. All watcher control goes through this actor.

#### 2. Database Schema: project_visits Table

**Purpose**: Track user visits and enable **DB-derived unread counts** (no mutable counters).

**Schema**:
```sql
CREATE TABLE project_visits (
  project_id TEXT NOT NULL PRIMARY KEY,
  last_viewed_at TEXT,      -- ISO8601Z UTC (NULL = never viewed, all entries unread)
  last_selected_at TEXT,    -- ISO8601Z UTC (last time user switched to this project)
  pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0,1)),
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

-- Critical indices for unread calculation
CREATE INDEX idx_entries_project_created_at ON entries(project_id, created_at);
CREATE INDEX idx_project_visits_last_viewed_at ON project_visits(project_id, last_viewed_at);
```

**Unread Calculation (Purely DB-Derived)**:
```sql
-- Count unread for one project
SELECT COUNT(*) FROM entries e
LEFT JOIN project_visits v ON v.project_id = e.project_id
WHERE e.project_id = ?
  AND (v.last_viewed_at IS NULL OR e.created_at > v.last_viewed_at);

-- Batch unread counts for all projects
SELECT p.id,
       COALESCE((
         SELECT COUNT(*) FROM entries e
         WHERE e.project_id = p.id
           AND (v.last_viewed_at IS NULL OR e.created_at > v.last_viewed_at)
       ), 0) AS unread
FROM projects p
LEFT JOIN project_visits v ON v.project_id = p.id;
```

**Operations**:
- `markViewed(projectId, timestamp)`: Set `last_viewed_at = <timestamp>` (UTC ISO8601Z)
- `markSelected(projectId)`: Set `last_selected_at = now()` (for "last used" sorting)
- `togglePin(projectId)`: Toggle `pinned` flag (pinned projects always visible)
- `getUnreadCounts()`: Execute batch query above (index-only plan via `idx_entries_project_created_at`)

**Key Properties**:
- **Crash-safe**: Unread is always computed from immutable `entries.created_at`
- **Clock-skew resistant**: Uses UTC timestamps; never compares `now()` to `created_at`
- **NULL semantics**: `last_viewed_at = NULL` means "never viewed" → all entries unread
- **No mutable counters**: No `unread_count` column to lose/corrupt

**Migration Strategy (Pre-Production Hard Cutover)**:
```sql
-- Migration v8: Simple hard cutover (no complex rollback)
migrator.registerMigration("v8-project-visits") { db in
  // Create table + indices
  try db.execute(sql: """
    CREATE TABLE project_visits (
      project_id TEXT NOT NULL PRIMARY KEY,
      last_viewed_at TEXT,
      last_selected_at TEXT,
      pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0,1)),
      FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
    );
    CREATE INDEX idx_entries_project_created_at ON entries(project_id, created_at);
    CREATE INDEX idx_project_visits_last_viewed_at ON project_visits(project_id, last_viewed_at);
  """)

  // Optional: backfill current project only (others default to NULL = all unread)
  if let currentProjectId = getCurrentProjectId() {
    try db.execute(sql: """
      INSERT INTO project_visits (project_id, last_viewed_at)
      SELECT ?, MIN(created_at) FROM entries WHERE project_id = ?
    """, arguments: [currentProjectId, currentProjectId])
  }
}
```

**Rollback Plan (Pre-Production)**:
- Delete `~/Library/Application Support/Contextify/transcripts.db`
- Restart app (fresh DB with all migrations)
- Feature flag: `FeatureFlags.multiProjectSwitcher` disables UI if issues arise (data remains)

#### 3. ProjectSwitcherState

**Purpose**: Observable state for project switcher UI.

**Location**: `Contextify/Contextify/ProjectSwitcherState.swift`

**Responsibilities**:
- Query all projects with transcripts from database
- Subscribe to `TranscriptUpdated` notifications
- Maintain unread counts per project
- Provide project switching API

**Architecture Pattern**: Follow StatusBarViewModel pattern (see `StatusBarViewModel.swift` for reference):
- Event-driven with AsyncStream for real-time updates
- Proper lifecycle management (start/stop)
- @Observable for SwiftUI integration
- Protocol-based providers for testability

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

  // Lifecycle state
  private var projectObservationTask: Task<Void, Never>?
  private var isStarted: Bool = false

  struct ProjectInfo: Identifiable, Sendable {
    let id: String  // project_id
    let name: String  // display name
    let rootPath: String
    let transcriptCount: Int
  }

  init(orchestrator: TranscriptOrchestrator, activityMonitor: ProjectActivityMonitor) {
    self.orchestrator = orchestrator
    self.activityMonitor = activityMonitor
  }

  // MARK: - Lifecycle (called by View)

  func start() {
    guard !isStarted else { return }
    isStarted = true

    // Initial load
    Task { await refreshProjects() }

    // Start event stream observation
    projectObservationTask = Task { @MainActor [weak self] in
      await self?.observeProjectUpdates()
    }
  }

  func stop() {
    projectObservationTask?.cancel()
    projectObservationTask = nil
    isStarted = false
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

  private func observeProjectUpdates() async {
    // Listen for TranscriptUpdated notifications via AsyncStream
    // If projectId != activeProjectId, increment unread count
    // Pattern: Similar to StatusBarViewModel's queue observation
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

**Add ProjectSwitcherView above header** (status bar is already in footer):
```swift
var body: some View {
  VStack(spacing: 0) {
    // NEW: Project switcher (top navigation)
    if projectSwitcherState.allProjects.count > 1 {
      ProjectSwitcherView()
        .environment(projectSwitcherState)
    }

    // Existing content
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        header
        Divider()
        composeSection
      }
      .frame(minWidth: 640)
      .padding(16)

      ConversationTimelineView()
    }

    // EXISTING: Status bar footer (from feature/status-bar merge)
    StatusBarView()
  }
}
```

**Note**: Status bar is already implemented and occupies the bottom footer. Project switcher will be top navigation, no UI conflicts.

## Project Identity & Reverse Path-Mangling

### Stable Identity Specification

**Project Identity** = tuple `(<provider: "claude.code"|"codex.cli">, <normalizedAbsolutePath: String>)`

**project_id** = `SHA256("\(provider):\(normalizedAbsolutePath)")` (stable hash)

### Reverse Path-Mangling Algorithm

**Claude Code Format**: `~/.claude/projects/<mangled-name>/`
- Mangling: URL-encodes special chars, replaces `/` with `__`
- Example: `/Users/rob/my-app` → `Users__rob__my-app` or `Users%2Frob%2Fmy-app`

**Codex CLI Format**: `~/.codex/sessions/<hash>/` (no path info in directory name)
- Must read session metadata file for project path

**Reverse-Mangle Spec**:
```swift
func reverseManglePath(provider: String, directory: URL) throws -> String {
  switch provider {
  case "claude.code":
    // Unescape URL encoding, replace __ with /
    let name = directory.lastPathComponent
    let unescaped = name.removingPercentEncoding ?? name
    let unmangled = unescaped.replacingOccurrences(of: "__", with: "/")

    // Normalize: resolve symlinks, remove trailing slash
    return try PathNormalizer.canonicalize("/" + unmangled)

  case "codex.cli":
    // Read .codex/session.json for project_root field
    let metaPath = directory.appendingPathComponent("session.json")
    let meta = try JSONDecoder().decode(CodexSessionMeta.self, from: Data(contentsOf: metaPath))
    return try PathNormalizer.canonicalize(meta.project_root)

  default:
    throw ProjectIdentityError.unknownProvider(provider)
  }
}
```

### Collision Handling

**Same path across multiple roots**:
```
~/.claude/projects/Users__rob__my-app/
~/.codex/sessions/ABC123/  (points to /Users/rob/my-app)
```

**Resolution**:
1. Compute `project_id` for both → **same hash**
2. Query DB: find existing project with that ID
3. If exists: **prefer newest `entries.created_at`** (most recent activity wins)
4. Log warning: `"Duplicate project found: <path> in <provider1> and <provider2>"`
5. UI: Show badge "(duplicate)" in tooltip

**Symlink Handling**:
- Always resolve via `realpath()` before hashing
- `/Users/rob/link-to-app` and `/Users/rob/my-app` → **same project** if symlinked

## Privacy & Consent

### Display & Logging

**Default Behavior**:
- **UI**: Display project **display name** (last path component: "my-app")
- **Tooltips**: Show full absolute path only on hover/focus
- **Logs**: Redact paths by default; log project_id hash only

**Verbose Mode** (opt-in):
- Preference: "Show full paths in logs" (default: OFF)
- When enabled: full paths logged for debugging

### Global Scan Consent

**First Run Dialog**:
```
┌─────────────────────────────────────────────────┐
│  Enable Multi-Project Monitoring?               │
│                                                  │
│  Contextify can monitor all projects with       │
│  Claude Code or Codex CLI transcripts.          │
│                                                  │
│  This requires scanning:                        │
│  • ~/.claude/projects/                          │
│  • ~/.codex/sessions/                           │
│                                                  │
│  Project paths are stored locally only.         │
│  No data is shared externally.                  │
│                                                  │
│  [Disable]  [Enable Multi-Project Mode]         │
└─────────────────────────────────────────────────┘
```

**Preference Key**: `dev.contextify.multiProjectMode.enabled` (default: `false`)

**Opt-Out Path**:
- User can disable multi-project mode in Preferences
- On disable: stop all watchers, hide switcher UI
- Data retained (project_visits table) for re-enable

## Accessibility Contract

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Cmd+1…9** | Select project by index (1=first visible, 9=ninth) |
| **Ctrl+Tab** | Cycle to next project |
| **Ctrl+Shift+Tab** | Cycle to previous project |
| **Cmd+Shift+P** | Open "More…" popover (when overflow) |

### VoiceOver Support

**Project Tab Label**:
```swift
.accessibilityLabel("Project \(name), \(unread) unread")
.accessibilityHint("Activate to switch to this project")
.accessibilityAddTraits(.isButton)
```

**Badge Label**:
```swift
.accessibilityLabel("\(unread) unread entries")
.accessibilityValue("\(unread)")
```

**More Popover**:
```swift
.accessibilityLabel("Show more projects")
.accessibilityHint("\(hiddenCount) projects not visible")
```

### Hit Targets

- **Minimum**: 44×44pt for all interactive elements
- **Pills**: Expand vertically to 44pt minimum
- **Focus Ring**: 2pt ring with `Color.accentColor`

### Color Accessibility

- **Unread badges**: Use text + icon (not color-only)
- **Active state**: Border + background (not background-only)
- **High Contrast**: Respect system `accessibilityDisplayShouldIncreaseContrast`

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| **Path reverse-mangle collisions** | Med | High | Stable spec + tie-break by newest activity; log & surface conflict UI |
| **Double-started watchers** | Med | High | Single owner actor + idempotent map keyed by projectId |
| **Unread miscount due to clock skew** | Low | High | Use entry.created_at (UTC), not `now()`; deterministic clock in tests |
| **N× scaling overhead** | Med | Med | Debounce, concurrency caps, lazy watchers for inactive projects |
| **Migration failure** | Low | High | Transactional migration + backup; on fail, disable feature |
| **FSEvents unavailability** | Low | Med | Fallback polling with backoff; telemetry alert |
| **UI jank on large unread** | Med | Med | Indexed queries; batch fetch; never block MainActor |
| **Privacy leakage (paths)** | Low | High | Default redaction; consent dialog; logging levels |
| **Startup race (DB vs watchers)** | Med | Med | Strict startup order; await DB ready before discovery |
| **Duplicate notifications** | Med | Low | Per-watcher sequence numbers; de-dup gate |

## Validation Matrix

### Unit Tests (DB & Logic)

**Unread Correctness**:
```swift
func testUnreadForNeverVisited_isAllEntries() async throws {
  // Given: project with 10 entries, last_viewed_at = NULL
  let projectId = "test-project"
  await createEntries(count: 10, projectId: projectId)

  // When: query unread
  let unread = try await repo.getUnreadCount(projectId: projectId)

  // Then: unread = 10 (all entries)
  XCTAssertEqual(unread, 10)
}

func testUnreadIndexPlan_isIndexOnly() throws {
  // Given: unread query
  let query = """
    SELECT COUNT(*) FROM entries e
    LEFT JOIN project_visits v ON v.project_id = e.project_id
    WHERE e.project_id = ? AND (v.last_viewed_at IS NULL OR e.created_at > v.last_viewed_at)
  """

  // When: EXPLAIN QUERY PLAN
  let plan = try db.read { try Row.fetchAll($0, sql: "EXPLAIN QUERY PLAN \(query)", arguments: [projectId]) }

  // Then: uses idx_entries_project_created_at (index-only scan)
  XCTAssertTrue(plan.contains { $0["detail"].contains("idx_entries_project_created_at") })
}

func testMarkViewed_updatesTimestamp() async throws {
  // Given: project with entries, last_viewed_at = NULL
  let projectId = "test-project"
  let firstEntry = await createEntry(projectId: projectId, timestamp: "2025-10-27T00:00:00Z")

  // When: mark viewed
  try await repo.markViewed(projectId: projectId, timestamp: firstEntry.created_at)

  // Then: last_viewed_at updated, unread = 0
  let visit = try await repo.getVisit(projectId: projectId)
  XCTAssertEqual(visit.last_viewed_at, firstEntry.created_at)
  XCTAssertEqual(try await repo.getUnreadCount(projectId: projectId), 0)
}

func testClockSkew() async throws {
  // Given: entry at 2025-10-27T00:00:00Z, last_viewed_at at 2025-10-26T23:59:59Z
  let projectId = "test-project"
  await createEntry(projectId: projectId, timestamp: "2025-10-27T00:00:00Z")
  try await repo.markViewed(projectId: projectId, timestamp: "2025-10-26T23:59:59Z")

  // When: query unread
  let unread = try await repo.getUnreadCount(projectId: projectId)

  // Then: unread = 1 (created_at > last_viewed_at)
  XCTAssertEqual(unread, 1)
}
```

**Identity & Path**:
```swift
func testReverseMangle_claudeCode() throws {
  let input = URL(fileURLWithPath: "~/.claude/projects/Users__rob__my-app")
  let expected = "/Users/rob/my-app"

  let result = try reverseManglePath(provider: "claude.code", directory: input)
  XCTAssertEqual(result, expected)
}

func testReverseMangle_collision() throws {
  // Same project path across multiple roots
  let claude = try reverseManglePath(provider: "claude.code", directory: URL(fileURLWithPath: "~/.claude/projects/Users__rob__my-app"))
  let codex = try reverseManglePath(provider: "codex.cli", directory: URL(fileURLWithPath: "~/.codex/sessions/ABC123"))

  // Both resolve to same absolute path
  XCTAssertEqual(claude, codex)

  // Same project_id hash
  let id1 = ProjectIdentity.hash(provider: "claude.code", path: claude)
  let id2 = ProjectIdentity.hash(provider: "codex.cli", path: codex)
  XCTAssertEqual(id1, id2)
}
```

### Actor/Concurrency Tests

**Watcher Lifecycle**:
```swift
func testIdempotentWatcherStart() async throws {
  let monitor = ProjectActivityMonitor(orchestrator: orchestrator, discovery: discovery)
  let projectId = "test-project"

  // When: start watcher twice
  let handle1 = try await monitor.ensureWatcher(projectId: projectId)
  let handle2 = try await monitor.ensureWatcher(projectId: projectId)

  // Then: same handle, watcher count = 1
  XCTAssertEqual(handle1.id, handle2.id)
  XCTAssertEqual(await monitor.activeWatcherCount, 1)
}

func testRapidSwitchCancellation() async throws {
  let monitor = ProjectActivityMonitor(orchestrator: orchestrator, discovery: discovery)

  // When: switch 20× rapidly
  for i in 1...20 {
    try await monitor.ensureWatcher(projectId: "project-\(i)")
  }

  // Then: no leaked tasks after 60s
  try await Task.sleep(nanoseconds: 60_000_000_000)
  let leaks = await monitor.debugGetPendingTasks()
  XCTAssertEqual(leaks.count, 0)
}
```

### Integration Tests

**End-to-End Flow**:
```swift
func testEndToEnd_unreadBadgeUpdate() async throws {
  // Given: 3 projects with synthetic file events
  let projects = ["p1", "p2", "p3"]
  for projectId in projects {
    try await createProject(id: projectId)
  }

  // When: emit file events for p1
  for _ in 1...5 {
    await emitFileEvent(projectId: "p1")
  }

  // Then: unread badge updates within 300ms
  try await waitForCondition(timeout: 0.3) {
    let unread = try await repo.getUnreadCount(projectId: "p1")
    return unread == 5
  }
}

func testFSEventsFailure_fallbackPolling() async throws {
  // Given: FSEvents unavailable (simulated)
  discovery.fsEventsEnabled = false

  // When: start monitoring
  try await monitor.startGlobalMonitoring()

  // Then: fallback polling engaged, telemetry flag set
  try await waitForCondition(timeout: 5.0) {
    await monitor.isFallbackPollingActive
  }
  XCTAssertTrue(await telemetry.flags.contains("fsevents_unavailable"))
}
```

### Performance Tests

**Idle CPU & Burst**:
```swift
func testIdleCPU() async throws {
  // Given: monitoring 10 projects
  try await monitor.startGlobalMonitoring()

  // When: measure CPU over 60s
  let cpuUsage = await measureCPU(duration: 60.0)

  // Then: ≤2% CPU
  XCTAssertLessThanOrEqual(cpuUsage.average, 0.02)
}

func testBurstEvents() async throws {
  // Given: 200 file events across 10 projects
  let events = (1...200).map { FileEvent(projectId: "p\($0 % 10)", timestamp: Date()) }

  // When: emit all events
  let start = Date()
  for event in events {
    await monitor.emit(event)
  }

  // Wait for processing
  try await waitForCondition(timeout: 5.0) {
    await monitor.pendingEvents.isEmpty
  }
  let duration = Date().timeIntervalSince(start)

  // Then: processes in ≤2s, ≤10 DB transactions
  XCTAssertLessThanOrEqual(duration, 2.0)
  XCTAssertLessThanOrEqual(await orchestrator.transactionCount, 10)
}
```

## Gap List (Must-Fix Before Build)

1. **Reverse path-mangling spec**: Complete algorithm with examples for both Claude Code and Codex CLI formats; test fixtures with edge cases.
2. **Watcher provider API**: Define `ProjectWatcherProvider` protocol with lifecycle, error surface, backoff strategy.
3. **ProjectVisitsRepository**: CRUD operations, pinning, atomic view updates, index verification.
4. **Migration ID/order**: Determine next migration version, rollback plan, backfill SQL script.
5. **Discovery dedupe rules**: Policy for same project across multiple roots; symlink resolution.
6. **Consent UX copy**: Final dialog text, preference key, opt-out flow.
7. **Accessibility acceptance criteria**: Complete keyboard map, VoiceOver labels, hit target measurements.
8. **Performance budget**: Max CPU % during idle (≤2%), max FS ops/sec (target: <10).
9. **Startup selection policy**: Last selected vs. most active in last N hours; tie-breaking.
10. **Error handling surface**: Toast vs. HUD vs. silent logs for watcher failures; user-facing messages.

## Implementation Phases (Revised Post-Ultrathink)

### Phase 0: Decisions & Schema (~2-3 days)

**Goal**: Lock down all foundational decisions; schema PR merged.

**Tasks**:
1. **Finalize identity spec**: Write reverse-mangle algorithm with test fixtures (Claude Code + Codex CLI examples)
2. **Design `project_visits` migration**: Determine next migration version (v8?), write SQL, backfill script
3. **Consent toggle**: Implement preference key `dev.contextify.multiProjectMode.enabled`, first-run dialog UI
4. **Watcher provider API**: Define `ProjectWatcherProvider` protocol with lifecycle, error surface
5. **Index verification**: Add `idx_entries_project_created_at`, verify EXPLAIN QUERY PLAN uses index
6. **Feature flag**: Add `FeatureFlags.multiProjectSwitcher` to guard all new code

**Exit Criteria**:
- [ ] Migration PR reviewed & merged
- [ ] Identity tests pass (reverse-mangle for both providers)
- [ ] EXPLAIN shows index-only scan for unread query
- [ ] Consent dialog implemented

**Rollback**: Drop `project_visits` table; feature flag disabled.

### Phase 1: Discovery & Watch Manager (~3-4 days)

**Goal**: Stable watcher list with no duplicates; FSEvents working.

**Tasks**:
1. **FSEvents integration**: Implement `FSEventsMonitor` wrapper with fallback polling
2. **ProjectActivityMonitor (actor)**: Idempotent `ensureWatcher()`, `Dictionary<ProjectID, WatchHandle>`
3. **Discovery loop**: Targeted rescan on FSEvents change (not full tree walk)
4. **Path normalization**: Integrate `PathNormalizer.canonicalize()` with symlink resolution
5. **Collision detection**: Log warnings when same path found across roots
6. **Telemetry**: Add flag for `fsevents_unavailable` fallback

**Exit Criteria**:
- [ ] FSEvents emits change notifications (verified with test harness)
- [ ] ProjectActivityMonitor passes idempotency tests (double-start → same handle)
- [ ] No watcher leaks after 20× rapid project switch
- [ ] Fallback polling engages when FSEvents disabled

**Rollback**: Disable multi-project mode; revert to single-project watcher.

### Phase 2: Unread Pipeline (~2-3 days)

**Goal**: Green unread tests; index-only query plan.

**Tasks**:
1. **ProjectVisitsRepository**: Implement CRUD operations (`markViewed`, `markSelected`, `togglePin`, `getUnreadCounts`)
2. **Unread SQL**: Implement batch query with LEFT JOIN; verify index usage
3. **Deterministic clock**: Add `Clock` protocol for testing; inject into repositories
4. **Backfill logic**: Write migration v8 with optional current project backfill (hard cutover)
5. **Edge case tests**: NULL last_viewed_at, clock skew, large unread counts (>1000)
6. **TranscriptOrchestrator integration**: Wire up `markViewed()` calls with **GRDB transaction wrapper**
7. **Transaction boundaries**: Wrap concurrent unread updates in `db.write { }` blocks

**Exit Criteria**:
- [ ] All unread tests pass (including `testUnreadForNeverVisited_isAllEntries`)
- [ ] EXPLAIN QUERY PLAN confirms index-only scan
- [ ] Backfill migration tested with rollback
- [ ] Performance: unread query <50ms for 10k entries

**Rollback**: Hide badges; keep switcher shell (UI only shows project names).

### Phase 3: UI Switcher (~2-3 days)

**Goal**: Accessibility, overflow, keyboard shortcuts working.

**Tasks**:
1. **ProjectSwitcherView**: SwiftUI navigation bar with pills, overflow "More…" popover
2. **Keyboard shortcuts**: Implement Cmd+1…9, Ctrl+Tab, Cmd+Shift+P
3. **VoiceOver labels**: Full accessibility labels with unread counts
4. **Hit targets**: Verify 44×44pt minimum; add focus rings
5. **Overflow logic**: Show up to 6 pills, rest in popover with search
6. **Badge rendering**: Cap at "99+", hide when zero
7. **SwiftUI previews**: All states (empty, single project, overflow, high unread)

**Exit Criteria**:
- [ ] VoiceOver announces "Project X, N unread" on focus
- [ ] Cmd+1 selects first project (no double-refresh)
- [ ] Overflow popover shows when >6 projects
- [ ] All hit targets measured ≥44pt

**Rollback**: Behind feature flag; keep menu-only project switch.

### Phase 4: Performance & Reliability (~2 days)

**Goal**: ≤2% CPU idle; no leaks over 2h.

**Tasks**:
1. **Debounce**: Add per-project debounce (150-300ms) with `TaskGroup`
2. **Concurrency caps**: Limit parallel parsers (4-8 concurrent projects)
3. **Lazy watchers** (optional): Inactive projects only watch metadata, full watcher on selection
4. **Telemetry**: Add CPU/memory profiling; log watcher count, pending events
5. **Stress testing**: 20 projects with synthetic file events; measure CPU, memory, DB transactions
6. **Leak detection**: Run for 2h with periodic project switching; verify no task/watcher leaks

**Exit Criteria**:
- [ ] Idle CPU ≤2% over 60s
- [ ] 200 file events across 10 projects process in ≤2s
- [ ] ≤10 DB transactions during burst
- [ ] No leaks after 2h (Instruments confirms)

**Rollback**: Reduce active watchers for inactive projects (lazy mode).

### Phase 5: Integration & Polish (~2 days)

**Goal**: No double refresh; status bar health OK; timeline/branch header smooth.

**Tasks**:
1. **Single selection source**: Ensure `ProjectSwitcherState` is single source of truth for active project
2. **Timeline refresh guard**: Debounce selection changes; **cancel in-flight timeline loads** via `debounceTask?.cancel()` pattern
3. **Cancellation on switch**: Apply existing ConversationMonitor cancellation pattern to project switching
4. **Branch header prefetch**: Load git branch info before switching to avoid flicker
5. **Status bar coordination**: Verify status bar continues showing LLM health (no interference)
6. **Startup order**: Strict sequence: DB open → migration → discovery → initial unread → UI mount
7. **Error handling**: Toast for watcher failures; HUD message for migration errors; silent logs for retries
8. **Integration tests**: End-to-end flow with synthetic projects; verify no double timeline refresh

**Exit Criteria**:
- [ ] Switching projects refreshes timeline exactly once
- [ ] Branch header updates without flicker
- [ ] Status bar health indicator unaffected
- [ ] Startup completes without race conditions

**Rollback**: Disable timeline auto-refresh on switch.

### Phase 6: Final QA & Documentation (~1 day)

**Goal**: Production-ready; all acceptance criteria met.

**Tasks**:
1. **Edge case testing**: No projects (hide switcher), single project, >20 projects
2. **Animation polish**: Subtle badge count changes, smooth pill selection transitions
3. **Loading states**: Show spinner during project switch (if >500ms)
4. **Documentation**: Update CLAUDE.md with multi-project mode; add troubleshooting section
5. **QA checklist**: Run full validation matrix; verify all acceptance criteria
6. **Performance verification**: Re-run idle CPU, burst events, leak detection
7. **Accessibility audit**: Full VoiceOver session; keyboard-only navigation

**Exit Criteria**:
- [ ] All validation matrix tests pass
- [ ] Documentation complete
- [ ] QA sign-off on all edge cases
- [ ] Accessibility audit complete

**Deliverable**: Production-ready feature; merge to main.

---

**Total Estimated Time**: ~14-18 days (3-4 weeks)

**Must-Complete Before Any Phase**: Phase 0 (Decisions & Schema)

**Rollback Strategy**: Each phase has independent rollback plan; feature flag guards all phases.

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

## Readiness Assessment

**Score: 4.0 / 5** - Clear architecture with manageable risks; ready to proceed with Phase 0.

### Strengths
- ✅ Event-driven architecture (FSEvents + AsyncStream) eliminates polling races
- ✅ Actor-based concurrency pattern (ProjectActivityMonitor) prevents watcher leaks and race conditions
- ✅ DB-derived unread (immutable timestamps) is crash-safe and clock-skew resistant
- ✅ Comprehensive risk register with mitigations for all high-impact risks
- ✅ Phased rollout plan with independent rollback per phase
- ✅ Reference implementations from status bar (observable ViewModels, lifecycle patterns)
- ✅ Transaction boundaries defined (GRDB write blocks)
- ✅ Cancellation pattern defined (reuse ConversationMonitor pattern)
- ✅ Simplified migration for pre-production (hard cutover, no complex rollback)

### Must-Fix Before Build (Checklist)

- [ ] **Reverse path-mangle spec** with examples for both Claude Code and Codex CLI formats + collision policy *(Phase 0)*
- [ ] **FSEvents-first** `ProjectWatcherProvider` API and `ProjectActivityMonitor` actor implementation *(Phase 0-1)*
- [ ] **GRDB migration v8** for `project_visits` + indices (hard cutover, simple backfill) *(Phase 0)*
- [ ] **Unread query & indices** proven with EXPLAIN and deterministic clock tests *(Phase 2)*
- [ ] **Transaction boundaries** via GRDB write blocks for concurrent updates *(Phase 2)*
- [ ] **Cancellation pattern** for timeline refresh on rapid switching *(Phase 5)*
- [ ] **Accessibility + keyboard contract** (Cmd+1…9, labels, focus, hit targets) documented *(Phase 3)*
- [ ] **Startup order** & feature flag + **privacy consent** toggle and log redaction default *(Phase 0)*

### Ready to Start
- ✅ **Phase 0 (Decisions & Schema)** can begin immediately - all critical architectural decisions made
- **Phase 1 (Discovery & Watch Manager)** blocked until Phase 0 complete
- All subsequent phases depend on Phase 0 + 1

### Recent Improvements (Post-Colleague Review)
- ✅ Simplified migration to hard cutover (pre-production appropriate)
- ✅ Added explicit transaction boundaries (Phase 2)
- ✅ Added cancellation pattern for rapid switching (Phase 5)
- ✅ Confirmed all major race conditions already mitigated (actor model, idempotent watchers)
- ✅ Confirmed clock-skew resistance (immutable timestamps, no `now()` comparisons)

### Key Assumptions Requiring Validation
1. **App is not sandboxed** (has direct FS access to transcript roots) - Probe: Test FSEvents on roots
2. **GRDB/SQLCipher** present with `entries.created_at` as immutable timestamp - Probe: Verify schema
3. **Status Bar does not auto-select projects** - Probe: Grep for selection side effects

## Related Work

- See `build/notes/technical-reference/sql-backend-architecture.md` for database design
- See `build/notes/technical-reference/conversation-monitor-state-architecture.md` for state management
- See `build/notes/feature-specs/status-bar/spec-final.md` for reference UI component pattern (observable ViewModels, lifecycle)
- See `build/notes/technical-reference/llm-processing-architecture.md` for multi-provider aggregation pattern (similar to multi-project monitoring)
