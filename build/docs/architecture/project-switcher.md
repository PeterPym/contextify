# Project Switcher - Multi-Project Architecture

**Status:** Shipped
**Components:** ProjectSwitcherView.swift (563 lines), ProjectSwitcherState.swift (682 lines)
**Related:** StartupCoordinator, ProjectActivityMonitor, ConversationMonitor

The Project Switcher transforms Contextify from single-project monitoring to multi-project dashboard with real-time unread badges, drag-drop reordering, and keyboard navigation.

---

## Overview

**Single-Project Mode (Legacy):**
- User manually sets project root
- Timeline shows only that project's transcripts
- No visibility into other projects with active sessions

**Multi-Project Mode (Current):**
- All projects with transcripts automatically discovered
- Tab-based navigation bar shows all projects
- Unread badges show activity per project
- Keyboard shortcuts for quick switching
- Drag-drop tab reordering
- Persistent user-defined order

---

## Architecture

### Component Responsibilities

**ProjectSwitcherState** (`@Observable` `@MainActor` singleton)
- Owns list of all discovered projects (`ProjectInfo[]`)
- Tracks active project ID (synced with `StartupCoordinator`)
- Computes unread counts per project
- Handles project switching logic
- Manages drag-drop reorder persistence
- Coordinates with `ProjectActivityMonitor` for file watching

**ProjectSwitcherView** (SwiftUI)
- Renders tab bar with project tabs
- Handles drag-drop interactions (with hysteresis/stickiness)
- Shows unread badges (capped at 99+)
- Overflow to "More..." popover when >6 tabs
- Integrates with keyboard shortcuts

**StartupCoordinator**
- Single source of truth for active project context
- Publishes `ActiveProjectContext` updates via `AsyncStream`
- Ensures project exists in DB before monitoring starts

**ProjectActivityMonitor**
- FSEvents-based file watching for transcript changes
- Emits `ProjectEvent` stream (discovered, updated, reordered)
- Manages global directory monitoring (`~/.claude/projects`, `~/.codex/sessions`)

---

## Data Flow

### Startup Sequence

```
App Launch
    ↓
StartupCoordinator.start()
    ↓
ProjectSwitcherState.start()
    ├─ Subscribe to coordinator updates
    ├─ Wait for coordinator.ready()
    ├─ Refresh projects from DB
    ├─ Refresh unread counts
    └─ Start global monitoring (if consent given)
    ↓
Listen to ProjectActivityMonitor events
    ↓
Update UI on project changes
```

### Project Switch Flow

```
User clicks tab / presses Cmd+Shift+P / keyboard shortcut
    ↓
switchToProject(id) called
    ├─ Deduplicate (skip if already switching to this ID)
    ├─ Cancel previous switch task
    ├─ IMMEDIATE UI UPDATE (activeProjectId = id)
    └─ Spawn detached task:
        ├─ Look up project in DB (off main thread)
        ├─ Call StartupCoordinator.switchProject(to: path)
        └─ Coordinator broadcasts update to all subscribers
    ↓
handleContextUpdate() receives new context
    ├─ Update activeProjectId (confirmation)
    ├─ Clear unread count for active project
    └─ Refresh project list
    ↓
ConversationMonitor receives same update
    └─ Timeline refreshes with new project's entries
```

**Key Design Choice:** Immediate UI update + background DB lookup prevents blocking on database during LLM generation or heavy I/O.

---

## Unread Badge System

### Schema (v8)

**Table: `project_visits`**
```sql
CREATE TABLE project_visits (
  project_id TEXT PRIMARY KEY,
  last_viewed_at INTEGER NOT NULL  -- epoch timestamp
);
```

### Unread Calculation

**Algorithm:**
```sql
SELECT COUNT(*)
FROM transcript_entries e
WHERE e.project_id = ?
  AND e.created_at > COALESCE(
    (SELECT last_viewed_at FROM project_visits WHERE project_id = ?),
    0
  )
```

**Update Timing:**
- On project switch: `last_viewed_at` set to current epoch
- Unread count cleared immediately in memory (UI update)
- Database updated asynchronously

**Coalescing:**
- Multiple unread events within 150ms batched together
- Prevents UI thrashing during rapid transcript writes
- `Set<String>` accumulates pending project IDs
- Task debouncing with 150ms delay

---

## Drag-Drop Tab Reordering

### UI Behavior

**Drag Source:**
- Long-press any project tab
- Tab lifts with scale effect
- Other tabs shift to show insertion point

**Drop Target:**
- Blue insertion indicator between tabs
- Snap to nearest valid slot
- Invalid drops rejected (e.g., dropping on self)

**Stickiness:**
- Hysteresis: 8pt dead zone to avoid boundary jitter
- Sticky distance: 20pt - must move this far to change slots
- Prevents accidental reorders during minor mouse movements

### Persistence (v19)

**Schema Addition:**
```sql
ALTER TABLE projects ADD COLUMN display_order INTEGER;
CREATE INDEX idx_projects_display_order ON projects(display_order);
```

**Reorder Algorithm:**
1. User drops tab at new position
2. UI immediately updates `allProjects` array
3. Background task assigns `display_order` values (0, 1, 2, ...)
4. Database write with UPDATE statements
5. Emit `.reordered` event to refresh other windows

**Sort Priority:**
1. Projects with `display_order` (user-defined order)
2. Projects without `display_order` (fallback to `created_at`)

---

## Keyboard Shortcuts

| Shortcut | Action | Wrapping |
|----------|--------|----------|
| `Cmd+Shift+P` | Open Projects window | - |
| `Cmd+Shift+[` | Previous project | Yes (wraps to end) |
| `Cmd+Shift+]` | Next project | Yes (wraps to start) |
| `Cmd+1` ... `Cmd+9` | Jump to project 1-9 | No |

**Implementation:**
- Shortcuts defined in `WindowCommands` (ContextifyApp.swift)
- Call `cycleToPreviousProject()` / `cycleToNextProject()`
- Wrapping: modulo arithmetic for circular navigation

---

## Project Discovery

### Consent Model

**First Launch:**
- App shows consent dialog: "Allow global project discovery?"
- User grants or denies
- Preference stored in `ConsentManager`

**If Denied:**
- Only current project shown in switcher
- Manual project addition via file picker

**If Granted:**
- `ProjectActivityMonitor.startGlobalMonitoring()` called
- FSEvents watch on:
  - `~/.claude/projects/`
  - `~/.codex/sessions/`
- New transcript files trigger project discovery

### Discovery Algorithm

**Event Source:** FSEvents on global directories

**On New Transcript:**
1. Parse project path from transcript file location
2. Check if project exists in DB
3. If not: call `TranscriptOrchestrator.getOrCreateProject()`
4. Emit `.discovered` event
5. ProjectSwitcherState refreshes project list

---

## Event-Driven Architecture

### ProjectEvent Types

```swift
enum ProjectEventKind {
  case discovered   // New project found
  case updated      // Transcript added/modified
  case reordered    // User reordered tabs
}

struct ProjectEvent {
  let projectId: String
  let kind: ProjectEventKind
}
```

### Event Flow

```
ProjectActivityMonitor (file watcher)
    ↓ emits ProjectEvent
ProjectSwitcherState.handle(event)
    ↓
switch event.kind:
  case .discovered → refreshProjects()
  case .updated    → scheduleUnreadRefresh(projectId)
  case .reordered  → refreshProjects()
```

**Coalescing:**
- `.updated` events batched (150ms window)
- Multiple updates to same project deduplicated
- Single unread count query for all pending projects

---

## Multi-Window Coordination

### Projects Window

**Purpose:** Full project list with search, hide/show, stats

**Location:**
```swift
// ContextifyApp.swift
Window("projects", id: "projects") {
  ProjectsWindow()
}
```

**Coordination:**
- Shares `ProjectSwitcherState.shared` singleton
- Changes in Projects window update switcher tabs
- Changes in switcher tabs update Projects window
- Both observe same `ProjectActivityMonitor` events

**Data Binding:**
```swift
@Environment(ProjectSwitcherState.self) private var switcherState
```

---

## Orphaned Project Handling (v17)

### Problem

User moves/deletes project directory, but DB still has transcripts.

### Detection

**Schema Addition (v17):**
```sql
ALTER TABLE projects ADD COLUMN is_orphaned INTEGER DEFAULT 0;
```

**Check:**
```swift
let isOrphaned = project.isOrphaned
  || !FileManager.default.fileExists(atPath: project.rootPath)
```

**UI Treatment:**
- Orphaned tabs shown with gray text
- Tooltip: "Project directory not found: [path]"
- Still selectable (shows empty timeline)
- User can hide via Projects window

---

## Performance Optimizations

### Immediate UI Feedback (CXT-14)

**Problem:** Database lookups blocked UI during project switch

**Solution:**
```swift
// Set activeProjectId IMMEDIATELY for instant visual feedback
activeProjectId = projectId

// Spawn detached task for DB lookup (off main thread)
Task.detached(priority: .userInitiated) {
  guard let project = try orchestrator.getProject(id: projectId) else { ... }
  await coordinator.switchProject(to: URL(fileURLWithPath: project.rootPath))
}
```

**Result:** <10ms tab highlight vs 100ms+ blocking DB read

### Deduplication (CXT-13)

**Problem:** Rapid clicks caused concurrent switch tasks, race conditions

**Solution:**
```swift
if switchInProgress == projectId {
  log.debug("Switch already in progress, skipping duplicate")
  return
}
switchInProgress = projectId
defer { switchInProgress = nil }
```

### Unread Coalescing

**Problem:** 50 transcript writes → 50 unread queries (UI thrashing)

**Solution:**
```swift
pendingUnread.insert(projectId)  // Accumulate IDs
coalesceTask?.cancel()
coalesceTask = Task {
  try await Task.sleep(for: .milliseconds(150))
  await refreshUnreadCounts()  // Single query for all pending
  pendingUnread.removeAll()
}
```

---

## Integration Points

### With ConversationMonitor

**Shared Dependency:** Both subscribe to `StartupCoordinator.updates()`

**Race Prevention (CXT-13):**
- Old: ProjectSwitcher → calls HUDViewModel → NotificationCenter → ConversationMonitor (timing-dependent)
- New: ProjectSwitcher → StartupCoordinator → both receive update simultaneously via typed streams

**Result:** Timeline always in sync with active tab

### With StatusBarViewModel

**Shared Resource:** Both observe `ProjectActivityMonitor` events

**Ownership:**
- `ProjectSwitcherState` creates monitor during startup
- `StatusBarViewModel` receives reference via environment
- Single watcher instance prevents duplicate FSEvents

### With HUDViewModel

**Legacy Coupling:**
- HUD still owns project root path for git branch display
- Switcher reads from HUDViewModel on startup
- Migration path: move git monitoring to per-project state

---

## UI/UX Details

### Tab Overflow

**Trigger:** >6 visible projects

**Behavior:**
- First 5 projects shown as tabs
- 6th tab becomes "More..." button
- Click opens popover with full scrollable list
- Popover shows names, paths, unread counts

### Badge Styling

**Colors:**
- Unread count: White text on red badge
- Capped at "99+" for large values

**Positioning:**
- Top-right corner of tab
- Outside tab bounds (overlaps content area)

**Accessibility:**
- VoiceOver reads: "Project name, 5 unread entries"
- Badge included in tab hit target (44pt minimum)

---

## Testing

### Unit Tests (ProjectSwitcherState)

**Initialization:**
```swift
let orchestrator = TestOrchestrator()
let state = ProjectSwitcherState(orchestrator: orchestrator)
await state.start()
XCTAssertEqual(state.allProjects.count, 0)
```

**Switch:**
```swift
await state.switchToProject(projectId)
XCTAssertEqual(state.activeProjectId, projectId)
```

**Unread:**
```swift
// Add entry to DB
await orchestrator.addEntry(projectId: "project-1", ...)
await state.refreshUnreadCounts()
XCTAssertEqual(state.unreadCounts["project-1"], 1)
```

### Manual Testing

**Drag-Drop:**
1. Open Contextify with 3+ projects
2. Long-press a project tab
3. Drag left/right - insertion indicator should appear
4. Drop - tab should move, order persisted
5. Quit & relaunch - order should be preserved

**Keyboard:**
1. Press `Cmd+Shift+]` - should cycle forward
2. Press `Cmd+Shift+[` - should cycle backward
3. At last project, `]` wraps to first
4. At first project, `[` wraps to last

**Unread:**
1. Switch to Project A
2. In iTerm2, run Claude Code in Project B
3. Badge should appear on Project B tab
4. Switch to Project B - badge clears

---

## Known Limitations

1. **Transcript count:** Always shows 0 (TODO: query actual count)
2. **Git branch:** Not shown in tabs (only in HUD header for active project)
3. **Network drives:** FSEvents may not fire for network-mounted project directories
4. **Sandbox:** Global monitoring requires user consent (privacy)
5. **Memory:** No virtualization - all project names loaded (fine for <100 projects)

---

## Future Enhancements

**Out of Scope (Current Release):**
- Per-project git branch badges
- Pin/favorite projects (always show first)
- Grouping by workspace/organization
- Custom project icons/colors
- Search/filter in tab bar
- Keyboard shortcut customization

**Potential Improvements:**
- Lazy-load project stats (only for visible tabs)
- Virtual scrolling for >100 projects
- Transcript count in badge (separate from unread)

---

## Related Documentation

- `build/docs/architecture/startup-coordinator.md` - Project identity pipeline
- `build/docs/components/project-discovery.md` - Discovery algorithm details
- `build/docs/architecture/conversation-monitor-state.md` - Timeline integration
- `build/docs/archive/feature-specs/project-switcher.md` - Original design spec (49KB)

---

## Debugging

### Enable Project Switcher Logs

**Console Filter:**
```
subsystem:dev.contextify category:ProjectSwitcher
```

**Key Log Messages:**
```
✅ ProjectSwitcher: starting
🔀 ProjectSwitcher: Switching to project: [id]
📊 Unread counts updated: project-1=5, project-2=0
[UIOPT-SWITCH-START] switchToProject() called
[UIOPT-SWITCH-UI] activeProjectId updated immediately
```

### Performance Profiling

**Instruments Trace Points:**
- `os_signpost(.begin, "ProjectSwitch", "%{public}s", projectId)`
- `os_signpost(.end, "ProjectSwitch")`

**Typical Timings:**
- Tab click → UI update: <10ms
- DB lookup: 50-100ms (background)
- Unread query (1 project): ~5ms
- Unread query (10 projects): ~20ms
