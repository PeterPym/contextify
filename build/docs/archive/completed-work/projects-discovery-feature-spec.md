# Feature Spec: Global Projects Discovery & Management

**Created:** 2025-10-22
**Status:** Design Phase
**Priority:** High (blocks multi-project RAG usage)
**Complexity:** Medium-High (backend + UI + integration)

---

## Executive Summary

**Problem:** Currently, Contextify only discovers and ingests transcripts for the **current project root**. Users with multiple projects must manually switch project roots to make their transcripts searchable. This creates a poor multi-project workflow and limits RAG search usefulness.

**Solution:** Implement **global auto-discovery** that finds all Claude Code and Codex CLI projects on the user's machine at startup, ingests all transcripts into the database, and provides a **Projects Window** for browsing and switching between projects.

**User Value:**
- ✅ All projects searchable immediately (no manual switching)
- ✅ Visual overview of all projects and their transcripts
- ✅ Easy project switching (like "Open Recent" but smarter)
- ✅ Cross-project search actually useful (finds content from all projects)

**Technical Scope:**
- Backend: ProjectDiscoveryService, auto-ingestion, path mapping
- UI: Dedicated Projects Window (Window > Projects)
- Integration: Menu items, keyboard shortcuts, current project tracking
- Database: Query existing schema (no schema changes needed)

---

## User Stories

### Primary Stories

**US-1: Auto-Discovery at Startup**
```
As a user with multiple projects,
When I launch Contextify,
Then the app should automatically discover all my Claude Code and Codex projects,
And ingest their transcripts into the database,
So that I can search across all my projects immediately.
```

**US-2: Projects Window**
```
As a user managing multiple projects,
When I open Window > Projects,
Then I should see a list of all discovered projects,
With their names, paths, transcript counts, and last activity,
So that I can understand what projects are being tracked.
```

**US-3: Switch Current Project**
```
As a user working on a specific project,
When I select a project in the Projects Window and click "Set as Current",
Then that project should become the active project root,
And the HUD should update to show that project's context,
So that project-scoped features work correctly.
```

**US-4: Manual Refresh**
```
As a user who just started a new project,
When I click "Refresh Projects" in the Projects Window,
Then the app should re-scan for new projects,
And ingest any newly discovered transcripts,
So that I don't have to restart the app.
```

### Secondary Stories

**US-5: Visual Project Status**
```
As a user browsing my projects,
When I look at the Projects Window,
Then I should clearly see which project is "current",
And which providers each project uses (Claude Code, Codex, or both),
So that I understand the state of my project tracking.
```

**US-6: Reveal in Finder**
```
As a user who wants to navigate to a project,
When I right-click a project in the Projects Window,
Then I should be able to "Reveal in Finder",
So that I can quickly access the project directory.
```

---

## UI Design

### Projects Window

**Window Properties:**
- Title: "Projects"
- Size: 800×600 (default), resizable
- Position: Centered on first open, persists after that
- Menu Path: `Window > Projects` (or `File > Projects`)
- Keyboard Shortcut: `⌘⇧P`
- Can be opened/closed without affecting app state

**Layout Mockup:**
```
┌─ Projects ────────────────────────────────────────────────────┐
│ ┌─ Discovery Status ──────────────────────────────────────┐  │
│ │ ✅ Discovered 12 projects with 147 transcripts          │  │
│ │ Last scan: 2 minutes ago        [Refresh Projects]      │  │
│ └─────────────────────────────────────────────────────────┘  │
│                                                                │
│ ┌─ Projects List ─────────────────────────────────────────┐  │
│ │                                                          │  │
│ │ ┌──────────────────────────────────────────────────┐    │  │
│ │ │ 📁 contextify                         [CURRENT]  │    │  │
│ │ │ /Users/rob/code/projects/contextify              │    │  │
│ │ │ 🔵 Claude Code  🟡 Codex CLI                    │    │  │
│ │ │ 24 transcripts • Last activity: 5 minutes ago    │    │  │
│ │ │ [Set as Current] [Reveal in Finder]              │    │  │
│ │ ├──────────────────────────────────────────────────┤    │  │
│ │ │ 📁 job-search                                    │    │  │
│ │ │ /Users/rob/projects/job-search                   │    │  │
│ │ │ 🔵 Claude Code                                   │    │  │
│ │ │ 18 transcripts • Last activity: 2 days ago       │    │  │
│ │ │ [Set as Current] [Reveal in Finder]              │    │  │
│ │ ├──────────────────────────────────────────────────┤    │  │
│ │ │ 📁 personal-website                              │    │  │
│ │ │ /Users/rob/sites/personal-website                │    │  │
│ │ │ 🔵 Claude Code                                   │    │  │
│ │ │ 8 transcripts • Last activity: 1 week ago        │    │  │
│ │ │ [Set as Current] [Reveal in Finder]              │    │  │
│ │ └──────────────────────────────────────────────────┘    │  │
│ │                                                          │  │
│ └──────────────────────────────────────────────────────────┘  │
│                                                                │
│ [Add Project Manually...]                              [Close]│
└────────────────────────────────────────────────────────────────┘
```

**Project Row Components:**
- **Icon:** 📁 (folder) or 📂 (open folder if current)
- **Name:** Derived from last path component or git repo name
- **Path:** Full filesystem path (truncated with ellipsis if too long)
- **Provider Badges:**
  - 🔵 "Claude Code" (if has ~/.claude/projects/<project>/)
  - 🟡 "Codex CLI" (if has <project>/.codex/sessions/)
  - Both if project uses both tools
- **Stats:** "{N} transcripts • Last activity: {relative time}"
- **Current Indicator:** [CURRENT] badge if this is the active project
- **Actions:**
  - "Set as Current" button (disabled if already current)
  - "Reveal in Finder" button
  - Right-click context menu: Reveal, Refresh, Remove

**Discovery Status Bar:**
- Shows count of discovered projects
- Shows total transcript count across all projects
- Shows last scan time
- "Refresh Projects" button to manually trigger discovery
- Progress indicator during discovery (spinner + "Discovering projects...")

**Empty State:**
```
┌─ Projects ──────────────────────────────┐
│                                          │
│         📂                               │
│    No Projects Found                     │
│                                          │
│  We couldn't find any Claude Code or    │
│  Codex CLI projects on your machine.    │
│                                          │
│  Projects are discovered from:          │
│  • ~/.claude/projects/*                 │
│  • <project>/.codex/sessions/           │
│                                          │
│  [Add Project Manually...]               │
│                                          │
└──────────────────────────────────────────┘
```

**Loading State:**
```
┌─ Projects ──────────────────────────────┐
│                                          │
│         ⏳                               │
│    Discovering Projects...               │
│                                          │
│  Scanning for Claude Code and Codex     │
│  projects across your machine...         │
│                                          │
│  Found 8 projects so far...              │
│                                          │
└──────────────────────────────────────────┘
```

### Menu Integration

**Window Menu:**
```
Window
  Bring All to Front
  ──────────────────
  Transcript Inventory    ⌘1
  Projects                ⌘⇧P  ← NEW
  ──────────────────
  [Open windows list]
```

**File Menu (alternative):**
```
File
  New Session             ⌘N
  ──────────────────
  Projects...             ⌘⇧P  ← NEW
  Set Project Root...     ⌘⇧O
  ──────────────────
  Close                   ⌘W
```

### Status Bar Update

**Current approach:** Project name shown in header
**Enhancement:** Add provider indicators
```
Before: "contextify"
After:  "contextify (🔵 Claude Code, 🟡 Codex)"
```

---

## Backend Architecture

### 1. ProjectDiscoveryService

**New file:** `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift`

```swift
public struct DiscoveredProject: Sendable, Identifiable {
  public let id: String               // Project path (unique identifier)
  public let name: String              // Display name
  public let path: URL                 // Filesystem path
  public let providers: Set<Provider>  // .claudeCode, .codex, or both
  public let transcriptCount: Int      // Count from database
  public let lastActivity: Date?       // Most recent transcript timestamp
  public let isCurrent: Bool           // Is this the active project?

  public enum Provider: String, Sendable {
    case claudeCode = "claude.code"
    case codex = "codex"
  }
}

public actor ProjectDiscoveryService {
  private let db: DatabasePool
  private let orchestrator: TranscriptOrchestrator

  /// Discovers all Claude Code and Codex projects
  /// - Returns: Array of discovered projects with metadata
  public func discoverAllProjects() async throws -> [DiscoveredProject]

  /// Discovers Claude Code projects from ~/.claude/projects/
  /// - Returns: Array of project paths found
  private func discoverClaudeCodeProjects() async throws -> [URL]

  /// Checks if a project has Codex transcripts at <path>/.codex/sessions/
  /// - Parameter projectPath: The project root path
  /// - Returns: True if Codex transcripts exist
  private func hasCodexTranscripts(at projectPath: URL) -> Bool

  /// Ingests all transcripts for all discovered projects
  /// - Parameter projects: Array of project paths to ingest
  /// - Parameter progressHandler: Callback for progress updates
  public func ingestAllProjects(
    projects: [URL],
    progressHandler: ((String, Int, Int) -> Void)?
  ) async throws

  /// Gets metadata for a single project from database
  /// - Parameter projectId: The project path
  /// - Returns: Project metadata (transcript count, last activity)
  private func getProjectMetadata(projectId: String) async throws -> ProjectMetadata
}
```

**Discovery Algorithm:**

```swift
func discoverAllProjects() async throws -> [DiscoveredProject] {
  var discovered: [DiscoveredProject] = []

  // 1. Scan ~/.claude/projects/* for Claude Code projects
  let claudeProjects = try await discoverClaudeCodeProjects()

  // 2. For each Claude project, check if it also has Codex transcripts
  for projectPath in claudeProjects {
    var providers: Set<Provider> = [.claudeCode]

    if hasCodexTranscripts(at: projectPath) {
      providers.insert(.codex)
    }

    // 3. Get metadata from database (if already ingested)
    let metadata = try await getProjectMetadata(projectId: projectPath.path)

    // 4. Determine display name
    let name = deriveProjectName(from: projectPath)

    discovered.append(DiscoveredProject(
      id: projectPath.path,
      name: name,
      path: projectPath,
      providers: providers,
      transcriptCount: metadata.transcriptCount,
      lastActivity: metadata.lastActivity,
      isCurrent: projectPath.path == currentProjectRoot?.path
    ))
  }

  // 5. Sort by last activity (most recent first)
  return discovered.sorted {
    ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
  }
}

private func discoverClaudeCodeProjects() async throws -> [URL] {
  let claudeProjectsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/projects")

  guard FileManager.default.fileExists(atPath: claudeProjectsDir.path) else {
    return []
  }

  let subdirs = try FileManager.default.contentsOfDirectory(
    at: claudeProjectsDir,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
  )

  // Convert directory names back to paths
  // -Users-rob-code-projects-foo → /Users/rob/code/projects/foo
  return subdirs.compactMap { dir in
    let dirName = dir.lastPathComponent
    let originalPath = dirName.replacingOccurrences(of: "-", with: "/")

    // Validate the path exists
    let url = URL(fileURLWithPath: originalPath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }

    return url
  }
}

private func hasCodexTranscripts(at projectPath: URL) -> Bool {
  let codexDir = projectPath.appendingPathComponent(".codex/sessions")

  guard FileManager.default.fileExists(atPath: codexDir.path) else {
    return false
  }

  // Check if there are any .jsonl files
  let files = try? FileManager.default.contentsOfDirectory(
    at: codexDir,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
  ).filter { $0.pathExtension == "jsonl" }

  return !(files?.isEmpty ?? true)
}

private func deriveProjectName(from path: URL) -> String {
  // Option 1: Use git repo name if available
  let gitConfigPath = path.appendingPathComponent(".git/config")
  if FileManager.default.fileExists(atPath: gitConfigPath.path) {
    // Parse git config for repo name... (complex, skip for MVP)
  }

  // Option 2: Use last path component
  return path.lastPathComponent
}
```

### 2. Auto-Discovery Flow

**When:**
- App launch (after database initialization)
- Background timer (every 10 minutes)
- Manual refresh (user clicks "Refresh Projects")

**Where:** New method in `AppDelegate` or `ContextifyApp`

```swift
@MainActor
func performGlobalDiscovery() async {
  let discoveryService = ProjectDiscoveryService(
    db: try! DatabaseManager.shared.pool,
    orchestrator: TranscriptOrchestrator.shared
  )

  // 1. Discover all projects
  let projects = try await discoveryService.discoverAllProjects()

  // 2. Ingest transcripts for each project
  try await discoveryService.ingestAllProjects(
    projects: projects.map { $0.path }
  ) { projectName, current, total in
    // Update UI progress
    print("Ingesting \(projectName): \(current)/\(total)")
  }

  // 3. Notify ProjectsWindow to refresh
  NotificationCenter.default.post(
    name: .projectsDiscoveryComplete,
    object: projects
  )
}
```

**Progress Tracking:**

```swift
struct DiscoveryProgress {
  let phase: Phase
  let currentProject: String?
  let projectsCompleted: Int
  let projectsTotal: Int
  let message: String

  enum Phase {
    case scanning      // Finding projects
    case ingesting     // Loading transcripts
    case complete
  }
}
```

### 3. Ingestion Changes

**Current:** `ConversationMonitor.discoverAndIngestTranscriptsForCurrentProject()`
- Only ingests for current project root

**New:** `ProjectDiscoveryService.ingestAllProjects()`
- Ingests for all discovered projects
- Handles multiple projects in sequence (or parallel?)
- Deduplication via existing `orchestrator.upsertTranscripts()`

**Key Considerations:**

1. **Parallel vs Sequential Ingestion:**
   - **Sequential:** Safer, easier to track progress, less memory
   - **Parallel:** Faster, but could overload system
   - **Recommendation:** Sequential for MVP, parallel as optimization

2. **Resume After Interruption:**
   - Track which projects have been ingested
   - Skip projects that are already up-to-date
   - Check: `orchestrator.getTranscripts(forProject: projectId).count > 0`

3. **Error Handling:**
   - If one project fails, continue with others
   - Log errors per-project
   - Show failed projects in UI with error message

### 4. Database Queries

**No schema changes needed!** Use existing tables.

**Query 1: Get all projects**
```sql
SELECT DISTINCT project_id, COUNT(*) as transcript_count
FROM transcripts
GROUP BY project_id
ORDER BY MAX(last_processed_at) DESC;
```

**Query 2: Get project transcript count**
```sql
SELECT COUNT(*) FROM transcripts WHERE project_id = ?;
```

**Query 3: Get project last activity**
```sql
SELECT MAX(timestamp) FROM transcript_entries WHERE project_id = ?;
```

**Swift Wrapper:**
```swift
struct ProjectStats {
  let projectId: String
  let transcriptCount: Int
  let lastActivity: Date?
}

func getProjectStats() async throws -> [ProjectStats] {
  try await db.read { db in
    let sql = """
      SELECT
        t.project_id,
        COUNT(t.id) as transcript_count,
        MAX(e.timestamp) as last_activity
      FROM transcripts t
      LEFT JOIN transcript_entries e ON t.id = e.transcript_id
      GROUP BY t.project_id
      ORDER BY last_activity DESC
      """

    let rows = try Row.fetchAll(db, sql: sql)

    return rows.compactMap { row in
      guard let projectId: String = row["project_id"],
            let count: Int = row["transcript_count"] else {
        return nil
      }

      let timestamp: Int? = row["last_activity"]
      let lastActivity = timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }

      return ProjectStats(
        projectId: projectId,
        transcriptCount: count,
        lastActivity: lastActivity
      )
    }
  }
}
```

---

## Implementation Plan

### Phase 1: Backend Discovery (Week 1)

**Files to Create:**
- `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift`
- `app/Sources/ContextifyCore/Projects/ProjectModels.swift`

**Tasks:**
1. ✅ Create `DiscoveredProject` model
2. ✅ Implement `discoverClaudeCodeProjects()`
3. ✅ Implement `hasCodexTranscripts()`
4. ✅ Implement `deriveProjectName()`
5. ✅ Implement `getProjectMetadata()` database query
6. ✅ Implement `discoverAllProjects()` orchestration
7. ✅ Implement `ingestAllProjects()` with progress tracking
8. ✅ Add unit tests for path mapping
9. ✅ Add integration test for discovery

**Acceptance Criteria:**
- Can discover all Claude Code projects on machine
- Can detect which projects also have Codex transcripts
- Can ingest transcripts for all projects without errors
- Progress callback provides accurate updates

### Phase 2: UI - Projects Window (Week 1-2)

**Files to Create:**
- `Contextify/Contextify/ProjectsWindow.swift`
- `Contextify/Contextify/ProjectsViewModel.swift`
- `Contextify/Contextify/ProjectRowView.swift`

**Tasks:**
1. ✅ Create `ProjectsWindow` SwiftUI view
2. ✅ Create `ProjectsViewModel` with ObservableObject
3. ✅ Implement project list display
4. ✅ Implement "Set as Current" action
5. ✅ Implement "Reveal in Finder" action
6. ✅ Implement "Refresh Projects" action
7. ✅ Add provider badges (Claude Code, Codex)
8. ✅ Add current project indicator
9. ✅ Add empty state
10. ✅ Add loading state with progress
11. ✅ Add error handling UI

**Acceptance Criteria:**
- Projects window opens via menu
- Shows all discovered projects with correct metadata
- Can set any project as current
- Can reveal project in Finder
- Refresh updates the list
- Current project is clearly indicated

### Phase 3: Integration (Week 2)

**Files to Modify:**
- `Contextify/Contextify/ContextifyApp.swift` (add auto-discovery)
- `Contextify/Contextify/ContentView.swift` (menu items)
- `app/Sources/ContextifyCore/HUDCore.swift` (project switching)

**Tasks:**
1. ✅ Add auto-discovery call at app launch
2. ✅ Add menu item: Window > Projects (⌘⇧P)
3. ✅ Wire up "Set as Current" to HUDViewModel
4. ✅ Add background refresh timer (10 minutes)
5. ✅ Update HUD header to show provider badges
6. ✅ Add notification for discovery complete
7. ✅ Persist window position
8. ✅ Handle window lifecycle (can open/close)

**Acceptance Criteria:**
- Auto-discovery runs on launch
- Projects window accessible via menu
- Setting current project updates HUD
- Background refresh works
- Window position persists across launches

### Phase 4: Polish & Testing (Week 2)

**Tasks:**
1. ✅ Add logging for discovery events
2. ✅ Add analytics/telemetry (project count, discovery time)
3. ✅ Performance testing (100+ projects)
4. ✅ Error case testing (permissions, missing dirs)
5. ✅ Edge case testing (renamed projects, symlinks)
6. ✅ UI polish (animations, icons, spacing)
7. ✅ Accessibility (VoiceOver, keyboard navigation)
8. ✅ Documentation (user guide, inline help)

**Acceptance Criteria:**
- Discovery completes in <5 seconds for typical user (10-20 projects)
- Handles 100+ projects gracefully
- Clear error messages for failures
- Smooth animations and transitions
- Full keyboard navigation support

---

## Edge Cases & Error Handling

### 1. Path Mapping Ambiguity

**Problem:** Multiple paths could map to same directory name
```
/Users/rob/projects/foo → -Users-rob-projects-foo
/opt/projects/foo       → -opt-projects-foo
```
**Solution:** Use full path as `project_id`, directory name just for discovery

**Problem:** Special characters in path
```
/Users/rob/my-project (old) → -Users-rob-my-project (old)
```
**Solution:** Handle this in reverse mapping, validate paths exist

### 2. Moved/Renamed Projects

**Scenario:** User renames `/Users/rob/old-name` to `/Users/rob/new-name`

**Current State:**
- Database has entries with `project_id = "/Users/rob/old-name"`
- Claude Code directory: `-Users-rob-old-name` (stale)

**Behavior:**
- Discovery finds new path: `/Users/rob/new-name`
- Old project appears as "orphaned" (transcripts in DB but no files on disk)
- New project appears as new (files on disk but not in DB yet)

**Solution Options:**
- **Option A:** Show both, let user merge manually
- **Option B:** Detect orphaned projects, offer to update project_id
- **Option C:** Keep old project_id, show warning about missing files
- **Recommendation:** Option A for MVP (safe), Option B for future

### 3. Permission Errors

**Scenario:** Can't read `~/.claude/projects/` (unlikely but possible)

**Handling:**
```swift
do {
  let projects = try await discoveryService.discoverAllProjects()
} catch {
  logger.error("Discovery failed: \(error)")
  // Show in UI: "Could not discover projects. Check permissions."
}
```

### 4. Malformed Directory Names

**Scenario:** Directory name doesn't follow expected pattern

**Example:** User manually created `~/.claude/projects/foo` (no dashes)

**Handling:**
- Skip directories that don't map to valid paths
- Log warning
- Don't crash

### 5. Very Large Projects

**Scenario:** Project with 1,000+ transcript files

**Handling:**
- Show progress during ingestion
- Allow cancellation
- Don't freeze UI
- Consider batching (ingest 100 at a time)

### 6. Codex-Only Projects

**Scenario:** Project uses Codex but not Claude Code

**Current Plan:** Won't be discovered (no entry in ~/.claude/projects/)

**Future:** Add "Add Project Manually" button
- User selects project root via file chooser
- App checks for `.codex/sessions/`
- Adds to tracked projects list

### 7. Network/Remote Projects

**Scenario:** Project on network drive or remote filesystem

**Handling:**
- Should work (uses FileManager)
- May be slow
- Don't block UI during discovery

---

## Testing Plan

### Unit Tests

**ProjectDiscoveryServiceTests:**
- ✅ `testDiscoverClaudeCodeProjects()` - Finds all projects
- ✅ `testPathMapping()` - Correctly reverses directory name to path
- ✅ `testHasCodexTranscripts()` - Detects Codex directories
- ✅ `testDeriveProjectName()` - Extracts sensible name
- ✅ `testEmptyDiscovery()` - Handles no projects gracefully
- ✅ `testMalformedDirectoryNames()` - Skips invalid directories

**ProjectMetadataTests:**
- ✅ `testGetProjectStats()` - Queries database correctly
- ✅ `testProjectStatsWithNoEntries()` - Handles empty projects
- ✅ `testLastActivityCalculation()` - Finds most recent timestamp

### Integration Tests

**DiscoveryIntegrationTests:**
- ✅ `testFullDiscoveryFlow()` - End-to-end discovery + ingestion
- ✅ `testIngestAllProjects()` - Ingests multiple projects correctly
- ✅ `testProgressTracking()` - Progress callbacks fire correctly
- ✅ `testErrorRecovery()` - Continues after project fails

### UI Tests

**ProjectsWindowTests:**
- ✅ `testWindowOpensViaMenu()` - ⌘⇧P opens window
- ✅ `testProjectListDisplays()` - Shows all projects
- ✅ `testSetAsCurrentAction()` - Switches active project
- ✅ `testRevealInFinder()` - Opens Finder to project
- ✅ `testRefreshAction()` - Triggers re-discovery
- ✅ `testCurrentProjectIndicator()` - Highlights current project

### Manual Testing Scenarios

1. **Fresh Install:**
   - Install app on machine with 3 projects
   - Launch app
   - Verify all projects discovered and ingested
   - Open Projects window, verify all 3 shown

2. **Add New Project:**
   - Create new Claude Code project
   - Click "Refresh Projects"
   - Verify new project appears

3. **Switch Projects:**
   - Open Projects window
   - Click "Set as Current" on different project
   - Verify HUD updates to show new project
   - Verify project-scoped search uses new project

4. **Cross-Project Search:**
   - Search with "Search across projects" checked
   - Verify results from multiple projects
   - Verify each result shows correct project

5. **Error Handling:**
   - Deny permissions to ~/.claude/projects/
   - Launch app
   - Verify graceful error message

---

## Performance Considerations

### Discovery Performance

**Measurement Points:**
- Time to scan `~/.claude/projects/`
- Time to check each project for Codex
- Time to query database for stats
- Total discovery time

**Expected Performance:**
```
10 projects:   ~500ms
50 projects:   ~2s
100 projects:  ~5s
```

**Optimization Strategies:**
1. **Parallel scanning** - Check multiple projects concurrently
2. **Caching** - Cache discovered projects, only re-check on refresh
3. **Incremental discovery** - Show results as they're found
4. **Database index** - Index `project_id` column for faster queries

### Ingestion Performance

**Current:** ~8-10 seconds for 100 entries (1 project)

**Scaled:** 10 projects × 100 entries = 80-100 seconds

**Too slow!** Need optimization:
1. **Parallel ingestion** - Ingest multiple projects at once
2. **Skip up-to-date projects** - Don't re-ingest if no new files
3. **Incremental updates** - Only process new/modified files
4. **Background processing** - Don't block UI

**Target Performance:**
- Initial discovery + ingestion: <30 seconds (10 projects)
- Refresh (no changes): <2 seconds
- Background refresh: No user-visible impact

### Memory Considerations

**Current:** ~15-20 MB per project (embeddings + entries)

**Scaled:** 10 projects = 150-200 MB

**Acceptable** for modern Macs, but should:
- Not load all projects into memory at once
- Only load current project's data for timeline
- Lazy-load project metadata on demand

---

## Future Enhancements (Post-MVP)

### 1. Project Favorites

**Feature:** Pin favorite projects to top of list

**UI:** Star icon next to project name
```
⭐ contextify
   my-important-project
   rarely-used-project
```

**Implementation:**
- Store favorites in UserDefaults
- Sort: favorites first, then by last activity

### 2. Project Groups/Tags

**Feature:** Organize projects by tags (work, personal, client-X)

**UI:**
```
┌─ Projects ──────────────┐
│ Filter: [All ▼]         │
│   All                   │
│   Work (8)              │
│   Personal (4)          │
│   Client-Acme (2)       │
└─────────────────────────┘
```

**Implementation:**
- Add `project_tags` table (many-to-many)
- Filter projects list by selected tag

### 3. Exclude Projects

**Feature:** Hide specific projects from discovery

**UI:** Right-click > "Stop Tracking This Project"

**Implementation:**
- Store excluded paths in UserDefaults
- Skip during discovery
- Offer "Show Excluded Projects" to restore

### 4. Multi-Project Search Weights

**Feature:** Boost results from certain projects

**Example:** When searching, prioritize "work" projects over "archived"

**UI:** Slider in Projects window: "Search priority" (low/normal/high)

**Implementation:**
- Store weights per project
- Multiply similarity scores during search
- Sort final results by weighted score

### 5. Project Statistics Dashboard

**Feature:** Show detailed analytics per project

**UI:**
```
┌─ contextify Details ────────────────┐
│ 24 transcripts                      │
│ 1,247 entries                       │
│ 842 searchable (with embeddings)    │
│                                     │
│ Activity Over Time:                 │
│ [Activity graph]                    │
│                                     │
│ Top Topics:                         │
│ • RAG implementation (124 entries)  │
│ • Database migration (89 entries)   │
│ • UI design (67 entries)            │
└─────────────────────────────────────┘
```

### 6. Cross-Project Pattern Detection

**Feature:** Find similar conversations across projects

**Example:** "You solved this auth issue 3 months ago in project X"

**Implementation:**
- Semantic search across all projects
- Cluster similar entries
- Suggest related conversations when viewing a result

### 7. Project Health Indicators

**Feature:** Show if project transcripts are up-to-date

**UI:**
```
📁 contextify                      ✅ Healthy
   All transcripts indexed
   Last sync: 2 minutes ago

📁 old-project                     ⚠️ Stale
   3 new transcripts not indexed
   Last sync: 3 weeks ago
```

### 8. Bulk Actions

**Feature:** Perform actions on multiple projects

**UI:** Multi-select projects, then:
- "Refresh Selected"
- "Tag Selected as..."
- "Export Selected..."

### 9. Import/Export Project Configuration

**Feature:** Share project discovery settings across machines

**Format:** JSON file with:
```json
{
  "favorites": ["/Users/rob/code/projects/foo"],
  "excluded": ["/Users/rob/old/archived-project"],
  "tags": {
    "work": ["/Users/rob/work/client-a", "/Users/rob/work/client-b"],
    "personal": ["/Users/rob/personal/blog"]
  }
}
```

### 10. Manual Project Addition (Codex-only support)

**Feature:** Add projects that only use Codex

**UI:** "Add Project Manually..." button opens file chooser

**Validation:**
- Check if path contains `.codex/sessions/`
- Warn if no transcripts found
- Add to tracked projects

---

## Open Questions

### Q1: Project Identity

**Question:** What should be the unique identifier for a project?

**Options:**
- **A:** Filesystem path (current approach)
- **B:** Git repository URL (if git repo)
- **C:** User-assigned unique ID

**Recommendation:** A (path) for MVP
- **Pros:** Simple, maps directly to database `project_id`
- **Cons:** Breaks if project moves
- **Future:** Add git URL as secondary identifier

### Q2: Current Project Behavior

**Question:** When user sets a project as "current", what should happen?

**Options:**
- **A:** Only update `HUDViewModel.projectRootURL`, nothing else
- **B:** Also update working directory (like `cd` to project)
- **C:** Also switch terminal/editor to project directory

**Recommendation:** A (minimal) for MVP
- **Pros:** Simple, predictable, doesn't interfere with user workflow
- **Cons:** Less integrated
- **Future:** Add option B/C as preferences

### Q3: Ingestion Timing

**Question:** When should we ingest transcripts for newly discovered projects?

**Options:**
- **A:** Immediately on discovery (blocks until complete)
- **B:** Asynchronously after discovery (background task)
- **C:** Lazy (only when user accesses project)

**Recommendation:** B (async) for MVP
- **Pros:** Doesn't block UI, feels responsive
- **Cons:** Search might miss recent content until ingestion complete
- **Solution:** Show "Ingesting..." indicator in Projects window

### Q4: Background Refresh Frequency

**Question:** How often should we auto-refresh project discovery?

**Options:**
- **A:** Never (only on launch + manual refresh)
- **B:** Every 5 minutes
- **C:** Every 10 minutes
- **D:** Configurable by user

**Recommendation:** C (10 minutes) for MVP
- **Pros:** Balances freshness with performance
- **Cons:** Might miss new projects for up to 10 minutes
- **Future:** Add preference (D)

### Q5: Error Recovery

**Question:** If discovery fails for one project, what should we do?

**Options:**
- **A:** Skip and continue with other projects
- **B:** Abort entire discovery
- **C:** Retry failed project N times

**Recommendation:** A (skip) for MVP
- **Pros:** Resilient, doesn't block other projects
- **Cons:** User might not notice failure
- **Solution:** Show error indicator in Projects window per-project

---

## Dependencies

### Code Dependencies

**New imports needed:**
- None (uses existing frameworks)

**Existing dependencies:**
- GRDB (database queries)
- SwiftUI (Projects window)
- TranscriptOrchestrator (ingestion)

### System Requirements

**Filesystem access:**
- Read: `~/.claude/projects/*`
- Read: `<project>/.codex/sessions/*`
- No new permissions needed (already have file system access)

**macOS version:**
- Same as current minimum (macOS 14+)

---

## Risks & Mitigations

### Risk 1: Performance Degradation

**Risk:** Discovery + ingestion takes too long, blocks app launch

**Likelihood:** Medium
**Impact:** High (bad UX)

**Mitigation:**
- Run discovery asynchronously (don't block launch)
- Show progress indicator
- Allow user to cancel
- Cache results, only re-scan on refresh

### Risk 2: Path Mapping Failures

**Risk:** Can't reliably convert directory names back to paths

**Likelihood:** Low (but possible for edge cases)
**Impact:** Medium (some projects not discovered)

**Mitigation:**
- Log unmapped directories
- Validate paths exist before using
- Offer manual project addition as fallback

### Risk 3: Database Bloat

**Risk:** Ingesting all projects creates huge database

**Likelihood:** Low (even 100 projects = ~1GB)
**Impact:** Low (storage is cheap)

**Mitigation:**
- Monitor database size
- Add "Clean Up" option to remove old/unused projects
- Warn if database >5GB

### Risk 4: User Confusion

**Risk:** Users don't understand difference between "discovered" and "current" project

**Likelihood:** Medium
**Impact:** Medium (support burden)

**Mitigation:**
- Clear UI labels and indicators
- Help text / tooltips
- Documentation

---

## Success Metrics

### Quantitative

- **Discovery Time:** <5s for 20 projects (P90)
- **Ingestion Time:** <30s for 10 projects (initial), <2s (refresh with no changes)
- **UI Responsiveness:** <100ms to open Projects window
- **Search Accuracy:** Cross-project search finds relevant results from all projects
- **Adoption:** >80% of users with multiple projects use Projects window

### Qualitative

- **User Feedback:** Positive comments about ease of switching projects
- **Bug Reports:** <5 bugs related to project discovery in first month
- **Support Tickets:** <10% of tickets related to project management

---

## Documentation Requirements

### User-Facing

1. **Help Article:** "Managing Multiple Projects"
   - How to open Projects window
   - What "Set as Current" does
   - How to refresh projects
   - How to reveal in Finder

2. **Tooltip Text:**
   - "Set as Current": "Makes this the active project for project-scoped searches"
   - "Refresh Projects": "Scans for new or changed projects"
   - Provider badges: "Claude Code" / "Codex CLI"

3. **Empty State Text:**
   - What projects are discovered from
   - How to add projects manually (future)

### Developer-Facing

1. **Architecture Doc:** `build/notes/technical-reference/project-discovery-architecture.md`
   - Discovery algorithm
   - Path mapping logic
   - Database queries
   - UI integration points

2. **Code Comments:**
   - Document path mapping reversibility assumptions
   - Document discovery algorithm
   - Document ingestion flow

---

## Rollout Plan

### Phase 1: Internal Testing (Week 1)

- Implement backend discovery
- Manual testing with dev's projects
- Fix critical bugs
- Performance profiling

### Phase 2: Beta Testing (Week 2)

- Implement UI
- Ship to beta testers (3-5 users)
- Collect feedback
- Iterate on UX

### Phase 3: Production Release (Week 3)

- Polish based on feedback
- Write documentation
- Ship to all users
- Monitor crash reports and feedback

### Phase 4: Iteration (Week 4+)

- Implement Future Enhancements based on user requests
- Add telemetry for usage patterns
- Optimize performance if needed

---

## Alternatives Considered

### Alternative 1: No Auto-Discovery

**Approach:** Keep current behavior, add manual project management only

**Pros:**
- Simpler implementation
- No performance concerns
- User has full control

**Cons:**
- Poor UX for multi-project users
- Doesn't solve the core problem

**Decision:** ❌ Rejected - Auto-discovery is the main value prop

### Alternative 2: In-App Project Picker (No Window)

**Approach:** Dropdown in main HUD to select project

**Pros:**
- Simpler UI
- Always visible

**Cons:**
- Clutters main HUD
- Hard to show metadata (transcript count, etc.)
- Doesn't scale to many projects

**Decision:** ❌ Rejected - Dedicated window provides better UX

### Alternative 3: Transcript Inventory Integration

**Approach:** Add project grouping to existing Transcript Inventory

**Pros:**
- Reuses existing UI
- One place for all transcript/project management

**Cons:**
- Conflates two concepts (projects vs sessions)
- UI becomes too complex
- Hard to show project-level actions

**Decision:** ❌ Rejected - Separate concerns = better UX

---

## Appendix A: Path Mapping Examples

```
Claude Code Directory          → Original Path
────────────────────────────────────────────────────────────
-Users-rob-code-projects-foo   → /Users/rob/code/projects/foo
-Users-rob-work-client-a       → /Users/rob/work/client-a
-opt-projects-website          → /opt/projects/website
-home-ubuntu-app               → /home/ubuntu/app

Edge Cases:
────────────────────────────────────────────────────────────
foo                            → ??? (no path, skip)
-foo-bar-baz                   → /foo/bar/baz (valid)
-Users-rob-my-project (old)    → /Users/rob/my-project (old) (valid, spaces ok)
```

**Algorithm:**
```swift
func reversePathMapping(_ dirName: String) -> URL? {
  // Replace dashes with slashes
  let path = dirName.replacingOccurrences(of: "-", with: "/")

  // Validate it's an absolute path (starts with /)
  guard path.hasPrefix("/") else {
    return nil
  }

  let url = URL(fileURLWithPath: path)

  // Validate the path exists on disk
  guard FileManager.default.fileExists(atPath: url.path) else {
    return nil
  }

  return url
}
```

---

## Appendix B: Database Schema Reference

**No changes needed** - use existing schema.

**Relevant tables:**
```sql
CREATE TABLE transcripts (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,  -- This is the project path!
  file_path TEXT NOT NULL,
  provider TEXT,
  session_id TEXT,
  last_processed_entry_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE transcript_entries (
  id TEXT PRIMARY KEY,
  transcript_id TEXT NOT NULL,
  project_id TEXT NOT NULL,  -- Denormalized for fast queries
  -- ... other fields
);

-- Useful indexes (already exist):
CREATE INDEX idx_transcripts_project ON transcripts(project_id);
CREATE INDEX idx_entries_project ON transcript_entries(project_id);
```

**Queries needed:**
```sql
-- Get all distinct projects
SELECT DISTINCT project_id FROM transcripts;

-- Get project transcript count
SELECT COUNT(*) FROM transcripts WHERE project_id = ?;

-- Get project entry count
SELECT COUNT(*) FROM transcript_entries WHERE project_id = ?;

-- Get project last activity
SELECT MAX(timestamp) FROM transcript_entries WHERE project_id = ?;

-- Get project stats (combined)
SELECT
  t.project_id,
  COUNT(DISTINCT t.id) as transcript_count,
  COUNT(e.id) as entry_count,
  MAX(e.timestamp) as last_activity
FROM transcripts t
LEFT JOIN transcript_entries e ON t.id = e.transcript_id
WHERE t.project_id = ?
GROUP BY t.project_id;
```

---

**End of Feature Spec**

Total Estimated Effort: **2-3 weeks** (1 engineer)
- Week 1: Backend discovery + basic UI
- Week 2: Integration + testing + polish
- Week 3: Beta testing + iteration + documentation

**Status:** Ready for implementation pending approval
