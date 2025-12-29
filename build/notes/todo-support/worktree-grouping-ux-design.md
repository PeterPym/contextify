---
todo: WORKTREE
type: design
status: ready
created: 2025-12-28
---

# Git Worktree Support - Comprehensive Design Document

**Date:** 2025-12-28
**Status:** Design Phase
**Priority:** P2 UX Enhancement
**Effort Estimate:** 8-12 hours (initial implementation)

---

## 1. Executive Summary

### Problem Statement

Contextify currently treats git worktrees as completely separate, unrelated projects. While the core infrastructure correctly isolates transcripts by working directory (enabling parallel development workflows), users have no visual indication that multiple projects in the tab bar are actually related worktrees of the same repository.

**Current UX Pain Points:**
1. **No visual relationship** - Worktrees appear as completely unrelated projects in the Projects window
2. **Manual switching required** - Users must manually use ⌘⇧P to switch between worktree projects
3. **Confusing naming** - Projects are shown by their directory names (e.g., "contextify" vs "contextify-worker-bee") with no indication they share git history
4. **No auto-detection** - HUD doesn't automatically switch when user moves to a different worktree in their terminal

### Current State

**What Works:**
- ✅ Worktrees in different directories are tracked as separate projects
- ✅ Transcripts are correctly associated based on CWD (current working directory)
- ✅ Database uniqueness enforced by full path (`root_path` UNIQUE index)
- ✅ Git root detection correctly identifies worktree directories
- ✅ Manual project switching works (⌘⇧P)

**What Doesn't Work:**
- ❌ No visual grouping or color coding for related worktrees
- ❌ No automatic HUD switching when terminal changes worktrees
- ❌ No indication in UI of worktree relationships
- ❌ No integration with CLI worktree tooling (`wt-status.sh`, etc.)

### Proposed Solution

Implement a **multi-phase visual differentiation system** that:

1. **Phase 1 (Core):** Color-code tabs by git root to visually group related worktrees
2. **Phase 2 (Enhanced):** Add worktree indicators (badges, branch names) to tabs
3. **Phase 3 (Advanced):** Implement auto-switching based on terminal activity (optional)
4. **Phase 4 (Integration):** Surface CLI worktree tooling status in UI (optional)

**Primary deliverable:** Hash git root path to consistent color, apply as tab background tint (4-6 hours).

---

## 2. Background

### Why Worktrees Matter for This User

The user actively works with git worktrees for **parallel development workflows**:

```
/Users/rob/code/projects/
├── contextify/              # Main repo (main branch)
├── contextify-worker-bee/   # Worktree (main-wb2 branch)
└── contextify-liquid-glass/ # Worktree (main-wb3 branch)
```

**Use case:** Simultaneously working on:
- Feature development in one worktree
- Bug fixes in another worktree
- Code reviews in a third worktree

**Without stashing or switching branches** - each worktree is a complete, independent working directory sharing the same git history.

### Current Pain Points (From Conversation History)

From December 23-24, 2024 discussions:

> "well i want the fucking session for each worktree to only show up in that worktree"

**User's explicit requirement:** Worktrees should remain isolated (separate projects), BUT the system should visually indicate they're related.

**UX expectations:**
1. Visual grouping so "you can tell at a glance which projects are worktrees of the same repo"
2. Optional auto-switching when terminal activity moves to different worktree
3. Integration with existing CLI worktree tooling (`wt-status.sh`, `wt-sync.sh`)

### Developer Workflow Context

**Common worktree workflow:**
1. Developer creates worktree with sibling directory naming: `projectname-branchname`
2. Each worktree has different active branch (`main-wb2`, `feat/lazy-watchers`, etc.)
3. Developer runs Claude Code/Codex CLI in each worktree's directory
4. Expects Contextify HUD to show ONLY that worktree's transcripts
5. Switches between worktrees frequently during day

**Current behavior:**
- ✅ Step 4 works correctly (isolation by CWD)
- ❌ No visual indication which tabs are related
- ❌ Manual tab switching required when switching worktrees in terminal

---

## 3. Current Implementation

### Architecture Overview

**Project Identity Pipeline:**

```
Transcript JSONL → Extract CWD → Canonicalize Path → Compute Project ID → Database Entry
```

**Key Components:**

1. **`app/Sources/ContextifyCore/ProjectIdentity.swift`** (195 lines)
   - `computeProjectID(provider:path:)` - SHA256 hash of `"<provider>:<path>"`
   - `extractCwdFromJSONLine()` - Parses CWD from transcript JSONL
   - `reverseManglePath()` - Extracts real path from Claude's mangled directory names
   - `canonicalizePath()` - Normalizes paths (removes trailing slash, resolves symlinks)

2. **`Contextify/Contextify/ProjectContext.swift`** (91 lines)
   - `discoverWorktrees()` - Finds all worktrees by reading `.git/worktrees/*/gitdir`
   - `allProjectPaths()` - Returns working dir + git root + all worktrees (for aggregation)
   - **NOTE:** Designed for AGGREGATING transcripts, not currently used in isolation mode

3. **`app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift`**
   - `scanClaudeDirectory()` - Discovers projects from `~/.claude/projects/` hash folders
   - `scanCodexDirectory()` - Discovers projects from `~/.codex/sessions/` by CWD
   - **Critical:** Uses `cwd` field from transcripts as `canonicalRootPath` for database identity

4. **`app/Sources/ContextifyCore/HUDCore.swift`** (GitRepositoryResolver section, lines 511-597)
   - `findGitRoot()` - Walks up from CWD to find `.git` (file or directory)
   - `resolveGitDir()` - Follows `gitdir:` pointer in `.git` file for worktrees
   - Returns worktree directory (NOT main repo) for worktrees

5. **`app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift`**
   - `LightweightProject` struct (lines 673-698)
   - Fields: `id`, `path`, `displayName`, `transcriptCount`, `lastActivity`, `provider`, `cwd`, `transcriptFiles`
   - `canonicalRootPath` property: `PathUtils.canonicalizePath(cwd ?? path.path)`

### How Isolation Works

**For Claude Code provider:**

Claude Code organizes transcripts by encoding the working directory path:

```
~/.claude/projects/
├── -Users-rob-code-projects-contextify/        # Main repo
│   └── session-uuid.jsonl
└── -Users-rob-code-projects-contextify-worker/ # Worktree (different CWD)
    └── session-uuid.jsonl
```

**Critical insight:** Because worktrees have different filesystem paths, their transcripts are stored in SEPARATE directories by Claude Code. This is the foundation that makes worktree support possible.

**Discovery process:**

1. Contextify scans `~/.claude/projects/` directories
2. Decodes directory name to get real path (e.g., `-Users-rob-...` → `/Users/rob/...`)
3. Reads first transcript to extract `cwd` field
4. Creates `LightweightProject` with `cwd` as canonical identity
5. Computes project ID: `SHA256("claude.code:/Users/rob/code/projects/contextify-worker")`
6. Inserts into database with `root_path = "/Users/rob/code/projects/contextify-worker"`

**Database uniqueness:**

```sql
CREATE TABLE projects (
  id TEXT PRIMARY KEY,           -- SHA256(provider:canonicalRootPath)
  name TEXT NOT NULL,
  root_path TEXT NOT NULL,       -- Full canonicalized path
  last_updated INTEGER NOT NULL,
  is_orphaned INTEGER NOT NULL DEFAULT 0,
  orphaned_since INTEGER
);

CREATE UNIQUE INDEX idx_projects_root_path ON projects(root_path);
```

**Result:** Each worktree gets a unique database entry because `root_path` is different.

### Git Root Detection for Worktrees

`GitRepositoryResolver.findGitRoot()` correctly handles worktrees:

```swift
// For worktrees, .git is a file (not a directory)
if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
  if isDir.boolValue {
    // Regular repo: .git is a directory
    return current
  }

  // Worktree: .git is a file with "gitdir: /path/to/main/.git/worktrees/NAME"
  if let gitdir = resolveGitDir(for: current) {
    let headPath = gitdir.appendingPathComponent("HEAD").path
    if fm.fileExists(atPath: headPath) {
      return current  // Returns WORKTREE directory, not main repo
    }
  }
}
```

**Key behavior:** For worktrees, this returns the worktree's own directory (e.g., `/Users/rob/code/projects/contextify-worker`), NOT the main repo directory.

### What Works (Verified)

**Scenario 1: Worktrees in Different Directories** ✅

```
/Users/rob/code/projects/
├── contextify/          # Main repo
└── contextify-worker/   # Worktree checked out to different branch
```

- Each has unique `root_path` in database
- Each gets its own project entry
- Transcripts correctly associated based on CWD

**Scenario 2: Multiple Unrelated Projects with Same Name** ✅

```
/Users/rob/code/projects/contextify/       # Project A
/Users/rob/code/personal/contextify/       # Project B (unrelated)
```

- Different `root_path` values in database
- Both appear as separate projects
- Display names identical but distinguishable by full path

**Scenario 3: Name Collision Edge Case** ✅

- Claude Code stores in SEPARATE directories: `-Users-rob-code-projects-contextify/` vs `-Users-rob-code-projects-contextify-worker-bee/`
- Database uses FULL `root_path` as unique key
- Display names are DIFFERENT ("contextify" vs "contextify-worker-bee")
- No collision occurs

### Known Gaps

**Gap 1: ProjectContext.projectIdentifier Uses Git Root** ❌

**File:** `Contextify/Contextify/ProjectContext.swift:14`

```swift
self.projectIdentifier = (gitRepoRoot ?? workingDirectory).lastPathComponent
```

**Problem:** For worktrees sharing the same git root:
- Main repo: `gitRoot = /Users/rob/code/projects/contextify`, identifier = "contextify"
- Worktree: `gitRoot = /Users/rob/code/projects/contextify` (SAME!), identifier = "contextify"

**Impact:** Mostly cosmetic (database uses `root_path`, not `projectIdentifier`), but confusing for debugging.

**Recommendation:** Remove `projectIdentifier` entirely since `displayName` serves the same purpose.

**Gap 2: allProjectPaths() Returns All Related Paths** ⚠️

**File:** `Contextify/Contextify/ProjectContext.swift:74-89`

```swift
func allProjectPaths() -> [URL] {
  var paths: [URL] = [workingDirectory]
  if let gitRoot = gitRepoRoot, gitRoot != workingDirectory {
    paths.append(gitRoot)
  }
  paths.append(contentsOf: discoverWorktrees())
  return paths  // Includes main + all worktrees
}
```

**Purpose:** Designed for AGGREGATING transcripts across worktrees.

**Problem:** If called when you want ONLY the current worktree's transcripts, you'd get all of them.

**Current Status:** This method exists but doesn't appear to be used in the main project identity pipeline. More of a future API for optional aggregation.

**Recommendation:** Document intent clearly to prevent misuse.

**Gap 3: No Visual Indication of Related Worktrees** ❌

**Current Behavior:**
- Tab bar shows projects by `displayName` (last path component):
  - "contextify"
  - "contextify-worker"
- No visual grouping or color coding

**Desired Behavior:**
- Hash git root path to consistent color
- Apply as tab background tint
- Users can visually see which projects are related worktrees

**Priority:** P2, Effort: 4-6 hours (PRIMARY FOCUS OF THIS DESIGN)

---

## 4. UI/UX Research Findings

### Industry Best Practices

**What Current Tools Do:**

1. **Status Bar Indicators** (IntelliJ, VS Code)
   - Always visible
   - Minimal screen real estate
   - Quick reference
   - **Best for:** Constant context awareness

2. **Dedicated Panel/View** (GitLens, IntelliJ plugins)
   - Table/tree view with metadata
   - Shows all worktrees at once
   - Supports actions (open, switch, delete)
   - **Best for:** Management and navigation

3. **Icon Differentiation** (IntelliJ plugins)
   - Branch vs. commit icons
   - Status indicators (dirty, clean, etc.)
   - **Best for:** Quick visual scanning

4. **Grouping by Repository** (Visual Studio multi-repo support)
   - Logical separation in UI
   - Prevents mixing contexts
   - **Best for:** Multi-worktree workflows

### What's Missing (Opportunities)

1. **Color Coding** ⭐
   - Almost no tools use color for worktrees
   - Proven pattern for tabs/projects (Tabs Studio, JetBrains Rider)
   - **Potential for:** Instant visual recognition

2. **Visual Relationships**
   - No tools show worktree relationships graphically
   - Sibling worktrees from same repo look unrelated
   - **Potential for:** Tree view or connection lines

3. **Contextual Warnings**
   - No visual warnings for wrong-worktree actions
   - **Potential for:** Colored backgrounds, badges

4. **Smart Naming**
   - Tools rely on directory names
   - Could extract semantic information (branch name from path)
   - **Potential for:** Auto-generated labels, tags

### Color Coding Best Practices

**From Refactoring UI:**
- For categorizing similar elements, you may need **up to 10 different accent colors**
- Each color should have **5-10 shades**
- Define a **fixed set of shades up front** rather than generating on-the-fly

**From JetBrains Rider:**
- Color-code tabs via regular expressions
- Force specific colors for specific project types (e.g., "web" vs "DB")
- Groups tabs by project rather than order of opening

**From UXPin Design Systems:**
- **Uniform color usage** across all components
- **Primary colors** for key elements
- **Associate accent colors with primary colors**
- Color evokes emotions (blue = trust/calm, green = growth, yellow = energy)

### Tab Grouping Patterns

**Tabs Studio (Visual Studio):**
- Groups tabs by common name parts, path, project
- Super groups with margins between
- Color coding via regular expressions
- Vertical tab display option

**project-tab-groups (Emacs):**
- Named tab groups per project
- Automatic tab group creation/selection
- Isolated buffers per project
- Strict isolation: one tab group per project
- Automatic switching when changing projects

**Tabs Per Project (IntelliJ):**
- Groups tabs by project
- Perfect for developers working with multiple projects simultaneously

### Key Insights

**What works for similar problems:**
1. **Automatic grouping** based on metadata (project root, git root)
2. **Visual separators** (margins, dividers, color zones)
3. **Consistent color assignment** (same color for related items)
4. **Status indicators** (badges, icons) for additional context
5. **Automatic context switching** when changing focus

**What Contextify should adopt:**
1. **Color coding by git root** (primary differentiator)
2. **Badge or icon** indicating worktree status
3. **Branch name display** in tab (secondary context)
4. **Optional auto-switching** when terminal changes worktrees

---

## 5. Past Discussions Summary

### Core Problem Discovery (December 23, 2024)

**Transcript ID:** `5917FC7F-5641-41C6-935C-C4710B244E3C`

**User's initial complaint:**
> "well i want the fucking session for each worktree to only show up in that worktree"

**Key decision:** User explicitly stated they were **okay with worktrees being treated as separate projects**, but the system was struggling with that model.

**Technical root cause identified:**
> "git worktrees can confuse the discovery pipeline because it discovers projects by looking at transcript metadata (cwd, encoded paths, etc.) and maps them to normalized roots."

**Resolution:** Problem "magically" resolved during testing, but **no explicit code changes were documented**. Unclear if permanent fix was implemented.

### CLI Tooling Development (December 24, 2024)

**Transcript ID:** `F039D744-5C1A-436D-8F26-59080EBB70A1`

**Major effort:** Comprehensive worktree management toolkit developed for `~/code/projects/cli-ai-setup/utils/gitops/`:

**Files created:**
- `wt-status.sh` - Display worktree sync status
- `wt-sync.sh` - Sync individual worktree
- `wt-sync-all.sh` - Sync all worktrees
- `wt-init.sh` - Initialize worktree registry
- `wt-context.sh` - Show current worktree identity

**Branch model:**
- **Canonical branch** - Shared upstream (e.g., `main`)
- **Landing branch** - Per-worktree working branch (e.g., `main-wb1`, `main-wb2`)

**Sync state machine:**
```
UPDATE → SYNC → PUSH → PUBLISH
  ↓       ↓      ↓       ↓
  Pull    Merge  Push    Force-push
  remote  canon  land    canon
          to     to      to
          land   remote  remote
```

**Status display example:**
```
NAME     CANONICAL  LANDING   ACTION
wb1      ↓3         ↑2        sync,push
wb2      -          -         -         ← dirty, no actions
```

**Configuration schema:**
```json
{
  "schemaVersion": "1.1",
  "config": {
    "canonicalBranch": "main",
    "remote": "origin",
    "pushLanding": true
  },
  "worktrees": [
    {
      "name": "wb1",
      "path": "/path/to/worktree1",
      "landingBranch": "main-wb1"
    }
  ]
}
```

**Status:** CLI tooling fully implemented BUT not integrated with Contextify UI.

### UI/UX Considerations

**Auto-switching behavior:**

From conversation (Entry ID: `9c98b300-8e66-bb11-b7cd-f0fab88ffaed`):

> "If you want the HUD to automatically follow whichever worktree you're in (so each worktree's session shows up where you expect), we need to either:
> 1. Update the discovery mapping so transcripts from `/Users/rob/code/projects/contextify` land under that project ID instead of the worker-bee ID, or
> 2. Force the HUD/project switcher to select the project that actually owns the new transcripts (e.g., by watching the latest `project_id` that got entries)."

**Project switcher behavior:**

From conversation (Entry ID: `23d60a17-2e6b-996a-bb65-4cb484d1d653`):

> "Have the HUD switch to whichever project ID just received entries (the project switcher can listen for the ingestion completion and activate the matching ID)."

**Implementation suggestion:** Use the existing `ProjectProviderStore` to:
- Track which project IDs receive new transcript entries
- Automatically switch the HUD's active project when new entries arrive
- Subscribe to `.projectsIngestionComplete` notifications

### What Was NOT Discussed

**Zero or minimal discussion on:**
1. Visual grouping (grouping worktrees under a parent project in the UI)
2. Color coding (using colors to differentiate worktrees)
3. Hierarchical display (tree-style or indented display of worktrees)
4. Worktree badges (visual indicators showing worktree relationships)
5. Inline worktree switching (worktree picker within the HUD)
6. Worktree-aware search (searching across all worktrees of a project)
7. Canonical project concept (surfacing the "main" project vs worktrees)

**Implication:** These are **greenfield design opportunities** with no prior constraints.

---

## 6. Proposed Solution

### Design Principles

1. **Minimal disruption** - Preserve existing isolation behavior, add visual context
2. **Progressive enhancement** - Start simple (color coding), add complexity in phases
3. **Automatic where possible** - Reduce manual configuration
4. **Consistent visual language** - Use color, icons, and spacing consistently
5. **Accessibility-friendly** - Don't rely solely on color (add icons/text)

### Phase 1: Color Coding by Git Root (Core Implementation)

**Priority:** P2
**Effort:** 4-6 hours
**Status:** Ready for implementation

#### Visual Design

**Tab appearance with color coding:**

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ contextify      │  │ other-project   │  │ contextify-work │
│   [subtle blue  │  │   [subtle green │  │   [subtle blue  │
│    tint bg]     │  │    tint bg]     │  │    tint bg]     │
└─────────────────┘  └─────────────────┘  └─────────────────┘
       ↑                     ↑                     ↑
       └─────────────────────┴─────────────────────┘
              Same git root = same color
```

**Color assignment algorithm:**

```swift
func colorForGitRoot(_ gitRoot: URL) -> Color {
  // Hash the git root path to get consistent color index
  let hash = SHA256.hash(data: Data(gitRoot.path.utf8))
  let colorIndex = hash.withUnsafeBytes { bytes in
    Int(bytes[0]) % 10  // Use first byte mod 10 for 10 color palette
  }

  // Return from predefined accent color palette
  return accentColors[colorIndex]
}
```

**Color palette (10 colors from Contextify design system):**

Derived from `build/design/brand/colors.md` semantic and brand colors:

```swift
let accentColors: [Color] = [
  Color(hex: "#4A7BA7"),  // primary (trust, calm)
  Color(hex: "#51A86B"),  // success (growth)
  Color(hex: "#D4A84E"),  // warning (energy, attention)
  Color(hex: "#C74E4E"),  // error (urgency)
  Color(hex: "#7C68A8"),  // accent (creativity)
  Color(hex: "#F9B233"),  // brand-yellow (warmth)
  Color(hex: "#4AC4E0"),  // brand-cyan (clarity)
  Color(hex: "#8B5CF6"),  // brand-purple (depth)
  Color(hex: "#9B8B7E"),  // secondary (neutral)
  Color(hex: "#5A9BAA"),  // teal (derived: bridges primary and brand-cyan)
]
```

**Color derivation notes:**
- First 5: Semantic UI colors (primary, success, warning, error, accent)
- Next 3: Brand gradient colors (yellow, cyan, purple)
- secondary: Neutral taupe for low-contrast needs
- teal: Derived by blending primary (#4A7BA7) and brand-cyan (#4AC4E0)

**Application strategy:**
- Background tint: 10% opacity of accent color
- Border (optional): 50% opacity of accent color on active tab
- Text: No color change (preserve readability)

#### Implementation Plan

**Step 1: Add git root detection to Project model**

**File:** `app/Sources/ContextifyCore/Models/Project.swift` (or wherever Project is defined)

```swift
// Add computed property for git root
extension Project {
  var gitRoot: URL? {
    // Use existing GitRepositoryResolver
    guard let rootURL = URL(string: rootPath) else { return nil }
    return GitRepositoryResolver.findGitRoot(from: rootURL)
  }
}
```

**Step 2: Create color hashing utility**

**New file:** `app/Sources/ContextifyCore/UI/WorktreeColorUtility.swift`

```swift
import Foundation
import SwiftUI
import CryptoKit

public struct WorktreeColorUtility {

  // Contextify design system colors (from build/design/brand/colors.md)
  private static let accentColors: [Color] = [
    Color(hex: "#4A7BA7"),  // primary
    Color(hex: "#51A86B"),  // success
    Color(hex: "#D4A84E"),  // warning
    Color(hex: "#C74E4E"),  // error
    Color(hex: "#7C68A8"),  // accent
    Color(hex: "#F9B233"),  // brand-yellow
    Color(hex: "#4AC4E0"),  // brand-cyan
    Color(hex: "#8B5CF6"),  // brand-purple
    Color(hex: "#9B8B7E"),  // secondary
    Color(hex: "#5A9BAA"),  // teal (derived)
  ]

  /// Computes a consistent color for a git root path
  public static func color(for gitRoot: URL) -> Color {
    let hash = SHA256.hash(data: Data(gitRoot.path.utf8))
    let colorIndex = hash.withUnsafeBytes { bytes in
      Int(bytes[0]) % accentColors.count
    }
    return accentColors[colorIndex]
  }

  /// Returns the tint color (10% opacity) for tab backgrounds
  public static func tintColor(for gitRoot: URL) -> Color {
    color(for: gitRoot).opacity(0.1)
  }

  /// Returns the border color (50% opacity) for active tabs
  public static func borderColor(for gitRoot: URL) -> Color {
    color(for: gitRoot).opacity(0.5)
  }
}

// Helper extension for hex colors
extension Color {
  init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r, g, b: UInt64
    switch hex.count {
    case 6: // RGB
      (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
    default:
      (r, g, b) = (0, 0, 0)
    }
    self.init(
      .sRGB,
      red: Double(r) / 255,
      green: Double(g) / 255,
      blue: Double(b) / 255
    )
  }
}
```

**Step 3: Update tab view with color coding**

**File to modify:** `Contextify/Contextify/ProjectSwitcherView.swift` (or wherever project tabs are rendered)

**Before:**
```swift
struct ProjectTabView: View {
  let project: Project
  let isSelected: Bool

  var body: some View {
    Text(project.displayName)
      .padding()
      .background(isSelected ? Color.blue : Color.clear)
  }
}
```

**After:**
```swift
struct ProjectTabView: View {
  let project: Project
  let isSelected: Bool

  var worktreeTintColor: Color {
    guard let gitRoot = project.gitRoot else { return .clear }
    return WorktreeColorUtility.tintColor(for: gitRoot)
  }

  var worktreeBorderColor: Color {
    guard let gitRoot = project.gitRoot else { return .clear }
    return WorktreeColorUtility.borderColor(for: gitRoot)
  }

  var body: some View {
    Text(project.displayName)
      .padding()
      .background(worktreeTintColor)
      .overlay(
        RoundedRectangle(cornerRadius: 4)
          .stroke(isSelected ? worktreeBorderColor : .clear, lineWidth: 2)
      )
  }
}
```

**Step 4: Testing**

1. Create test worktrees:
   ```bash
   cd /tmp
   git init test-repo
   cd test-repo
   git commit --allow-empty -m "Initial"
   git worktree add ../test-repo-wt1 -b wt1
   git worktree add ../test-repo-wt2 -b wt2
   ```

2. Run Claude Code in each:
   ```bash
   cd /tmp/test-repo && claude code
   cd /tmp/test-repo-wt1 && claude code
   cd /tmp/test-repo-wt2 && claude code
   ```

3. Verify in Contextify:
   - All three projects appear as tabs
   - `test-repo`, `test-repo-wt1`, `test-repo-wt2` have SAME background color
   - Color is consistent across app restarts
   - Different repo tabs have different colors

**Deliverables:**
- [ ] `WorktreeColorUtility.swift` with color hashing logic
- [ ] Updated `ProjectSwitcherView.swift` with color-coded tabs
- [ ] Manual testing checklist completed
- [ ] Screenshots in `/tmp/worktree-phase1-screenshots/`

---

### Phase 2: Enhanced Visual Indicators (Optional Enhancement)

**Priority:** P3
**Effort:** 3-4 hours
**Status:** Optional, post-Phase 1

#### Additional Visual Elements

**Branch name badge:**

```
┌───────────────────────────┐
│ contextify-worker-bee     │
│   feat/lazy-watchers  📝  │  ← Branch name + dirty indicator
│   [subtle blue tint bg]   │
└───────────────────────────┘
```

**Worktree count indicator:**

When multiple worktrees exist for same git root, show count:

```
┌───────────────────────────┐
│ contextify           [3]  │  ← "3" = 3 worktrees total
│   [subtle blue tint bg]   │
└───────────────────────────┘
```

#### Implementation

**Step 1: Detect current branch**

```swift
extension Project {
  var currentBranch: String? {
    guard let gitRoot = gitRoot else { return nil }
    let headPath = gitRoot.appendingPathComponent(".git/HEAD")
    guard let headContent = try? String(contentsOf: headPath) else { return nil }

    // Parse "ref: refs/heads/BRANCH" or return SHA
    if headContent.hasPrefix("ref: ") {
      let ref = headContent.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
      return ref.components(separatedBy: "/").last
    }
    return headContent.prefix(7).description  // Short SHA
  }
}
```

**Step 2: Count related worktrees**

```swift
extension Project {
  var worktreeCount: Int {
    guard let gitRoot = gitRoot else { return 1 }

    // Use ProjectContext.discoverWorktrees() to count
    let context = ProjectContext(workingDirectory: URL(fileURLWithPath: rootPath))
    return 1 + context.discoverWorktrees().count  // 1 for main + worktrees
  }
}
```

**Step 3: Update tab view**

```swift
struct ProjectTabView: View {
  let project: Project
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(project.displayName)
          .font(.body)

        if project.worktreeCount > 1 {
          Text("[\(project.worktreeCount)]")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      if let branch = project.currentBranch {
        Text(branch)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding()
    .background(worktreeTintColor)
    .overlay(
      RoundedRectangle(cornerRadius: 4)
        .stroke(isSelected ? worktreeBorderColor : .clear, lineWidth: 2)
    )
  }
}
```

**Deliverables:**
- [ ] Branch name detection logic
- [ ] Worktree count detection logic
- [ ] Updated tab view with badges
- [ ] Manual testing checklist

---

### Phase 3: Auto-Switching (Advanced, Optional)

**Priority:** P4
**Effort:** 6-8 hours
**Status:** Optional, requires user feedback on desirability

#### Design Question

**Should the HUD automatically switch projects when:**
1. A new transcript is created in a different worktree?
2. The user's terminal changes to a different worktree directory?

**Pros:**
- Seamless workflow (no manual switching)
- Always shows relevant context

**Cons:**
- May be disruptive if user wants to review old transcripts while working in different worktree
- Requires file system monitoring (resource intensive)

**Recommendation:** Implement as **opt-in preference** with three modes:
1. **Manual** (default) - No auto-switching
2. **On new transcript** - Switch when new transcript appears in different worktree
3. **On directory change** - Switch when terminal changes directories (advanced)

#### Implementation Approach

**Mode 2: On New Transcript (Easier)**

Subscribe to `ProjectProviderStore.projectsIngestionComplete` notifications:

```swift
class ProjectSwitcherState: ObservableObject {
  @Published var activeProjectID: String?

  private var autoSwitchEnabled: Bool {
    UserDefaults.standard.bool(forKey: "autoSwitchWorktrees")
  }

  init() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleIngestionComplete),
      name: .projectsIngestionComplete,
      object: nil
    )
  }

  @objc private func handleIngestionComplete(_ notification: Notification) {
    guard autoSwitchEnabled else { return }

    // Get project ID that just received new entries
    guard let projectID = notification.userInfo?["projectID"] as? String else { return }

    // Switch to that project
    DispatchQueue.main.async {
      self.activeProjectID = projectID
    }
  }
}
```

**Mode 3: On Directory Change (Harder)**

Monitor current terminal's working directory using `FSEvents` or polling:

```swift
class TerminalDirectoryMonitor {
  private var timer: Timer?

  func startMonitoring() {
    timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      self?.checkCurrentDirectory()
    }
  }

  private func checkCurrentDirectory() {
    // Get current terminal's CWD (requires querying running processes)
    guard let terminalPID = getActivTerminalPID(),
          let cwd = getCurrentWorkingDirectory(for: terminalPID) else { return }

    // Find project matching this CWD
    if let project = findProject(forPath: cwd) {
      ProjectSwitcherState.shared.activeProjectID = project.id
    }
  }

  private func getActivTerminalPID() -> Int32? {
    // Use NSWorkspace to get frontmost application
    guard let app = NSWorkspace.shared.frontmostApplication,
          app.bundleIdentifier == "com.apple.Terminal" ||
          app.bundleIdentifier == "com.googlecode.iterm2" else { return nil }

    return app.processIdentifier
  }

  private func getCurrentWorkingDirectory(for pid: Int32) -> String? {
    // Use libproc to get process info
    // This is complex - requires C interop
    // See: https://stackoverflow.com/questions/6591613/get-current-working-directory-of-another-process
    return nil  // Placeholder
  }
}
```

**Recommendation:** Start with Mode 2 (on new transcript) as it's simpler and less invasive.

**Deliverables (if implemented):**
- [ ] User preference toggle in Settings
- [ ] Auto-switching logic (Mode 2)
- [ ] Testing with multiple worktrees
- [ ] Documentation in user-facing guide

---

### Phase 4: CLI Tooling Integration (Future)

**Priority:** P5
**Effort:** 8-12 hours
**Status:** Deferred, requires significant UI work

#### Potential Features

1. **Display worktree sync status in HUD**
   - Show sync state next to project name (e.g., "↓3 ↑2" = behind 3, ahead 2)
   - Color-code based on sync health (green = synced, yellow = needs sync, red = diverged)

2. **Trigger worktree operations from UI**
   - "Sync Worktree" button in project context menu
   - Runs `wt-sync.sh` in background
   - Shows progress in HUD

3. **Worktree management panel**
   - Dedicated view showing all worktrees for current git root
   - Create/delete worktrees from UI
   - Switch between worktrees with click

#### Implementation Considerations

**Challenge:** CLI tooling lives in separate repo (`~/code/projects/cli-ai-setup/utils/gitops/`).

**Options:**
1. **Shell out to scripts** - Use `Process` to run `wt-status.sh`, parse output
2. **Duplicate logic in Swift** - Reimplement worktree detection/status in Contextify
3. **Create shared library** - Extract common logic to Swift package, use in both CLI and app

**Recommendation:** Start with Option 1 (shell out) for prototyping, refactor to Option 3 if we commit to deep integration.

**Deliverables (if implemented):**
- [ ] Shell integration for `wt-status.sh`
- [ ] Worktree status display in tab view
- [ ] Context menu with "Sync Worktree" action
- [ ] Progress indicator for sync operations

---

## 7. Implementation Plan

### Phased Rollout

| Phase | Deliverable | Priority | Effort | Dependencies |
|-------|-------------|----------|--------|--------------|
| **Phase 1** | Color-coded tabs by git root | P2 | 4-6h | None |
| **Phase 2** | Branch badges, worktree count | P3 | 3-4h | Phase 1 |
| **Phase 3** | Auto-switching (opt-in) | P4 | 6-8h | Phase 1 |
| **Phase 4** | CLI tooling integration | P5 | 8-12h | Phase 1, external scripts |

**Total effort:** 21-30 hours (all phases), 4-6 hours (Phase 1 only)

### Recommended Approach

**Sprint 1 (Focus on Phase 1):**
1. Implement `WorktreeColorUtility.swift` with color hashing
2. Update `ProjectSwitcherView.swift` with color-coded tabs
3. Manual testing with real worktrees
4. Screenshot documentation

**Sprint 2 (Optional enhancements):**
1. Add branch name detection
2. Add worktree count badge
3. User testing for feedback on usefulness

**Sprint 3+ (Advanced features, if desired):**
1. Implement auto-switching preference
2. Add CLI tooling integration
3. Create dedicated worktree management panel

### Success Criteria

**Phase 1 (Required):**
- [ ] Tabs for worktrees of same git root have visually matching colors
- [ ] Color is consistent across app restarts
- [ ] Color assignment is deterministic (same git root = same color always)
- [ ] Different git roots have different colors (with 10-color palette, 90% likely)
- [ ] Color is subtle enough not to distract (10% opacity background)
- [ ] Zero compiler warnings
- [ ] Manual testing checklist passed

**Phase 2 (Optional):**
- [ ] Branch names display correctly in tabs
- [ ] Worktree count shows when > 1 worktree exists
- [ ] UI remains readable with additional elements

**Phase 3 (Optional):**
- [ ] User preference toggle works
- [ ] Auto-switching activates on new transcript (when enabled)
- [ ] No false positives (switching when not intended)

**Phase 4 (Optional):**
- [ ] Worktree sync status displays accurately
- [ ] CLI operations can be triggered from UI
- [ ] Operations show progress/completion feedback

---

## 8. Test Strategy

### Manual Testing (Phase 1)

**Setup:**
1. Create test repository with 3 worktrees:
   ```bash
   mkdir /tmp/test-worktrees
   cd /tmp/test-worktrees
   git init main-repo
   cd main-repo
   git commit --allow-empty -m "Initial"
   git worktree add ../worktree-1 -b feature-1
   git worktree add ../worktree-2 -b feature-2
   ```

2. Create transcripts in each:
   ```bash
   cd /tmp/test-worktrees/main-repo && claude code
   cd /tmp/test-worktrees/worktree-1 && claude code
   cd /tmp/test-worktrees/worktree-2 && claude code
   ```

3. Create unrelated project:
   ```bash
   cd /tmp
   git init other-project
   cd other-project && claude code
   ```

**Test Cases:**

| Test | Expected Result | Pass/Fail |
|------|-----------------|-----------|
| All 3 worktrees appear as separate tabs | ✅ | |
| All 3 worktrees have SAME background color | ✅ | |
| `other-project` has DIFFERENT background color | ✅ | |
| Quit and relaunch app | Same colors persist | |
| Create new worktree, run Claude Code | New tab has matching color | |
| Select tab | Border color appears (50% opacity) | |
| Switch between tabs | Only active tab has border | |
| Display name shows last path component | "main-repo", "worktree-1", "worktree-2" | |

**Screenshot checklist:**
- [ ] Tab bar with 3 worktrees (same color)
- [ ] Tab bar with mixed projects (different colors)
- [ ] Active tab with border highlight
- [ ] Color palette visualization (all 10 colors)

### Automated Testing (SPM-Compatible)

**Unit Tests:**

**File:** `Tests/ContextifyCoreTests/WorktreeColorUtilityTests.swift`

```swift
import XCTest
@testable import ContextifyCore

final class WorktreeColorUtilityTests: XCTestCase {

  func testConsistentColorForSamePath() {
    let gitRoot = URL(fileURLWithPath: "/tmp/test-repo")
    let color1 = WorktreeColorUtility.color(for: gitRoot)
    let color2 = WorktreeColorUtility.color(for: gitRoot)
    XCTAssertEqual(color1, color2, "Same git root should always return same color")
  }

  func testDifferentColorsForDifferentPaths() {
    let gitRoot1 = URL(fileURLWithPath: "/tmp/repo-1")
    let gitRoot2 = URL(fileURLWithPath: "/tmp/repo-2")
    let color1 = WorktreeColorUtility.color(for: gitRoot1)
    let color2 = WorktreeColorUtility.color(for: gitRoot2)
    // Note: This MIGHT fail if hash collision occurs (low probability)
    XCTAssertNotEqual(color1, color2, "Different git roots should usually return different colors")
  }

  func testTintOpacity() {
    let gitRoot = URL(fileURLWithPath: "/tmp/test-repo")
    let tint = WorktreeColorUtility.tintColor(for: gitRoot)
    // Verify opacity is 0.1 (may need to inspect Color internals)
    // This is tricky to test directly - may require visual inspection
  }

  func testColorPaletteRange() {
    // Test that all possible hash values map to valid color indices
    for i in 0..<100 {
      let gitRoot = URL(fileURLWithPath: "/tmp/repo-\(i)")
      let color = WorktreeColorUtility.color(for: gitRoot)
      XCTAssertNotNil(color, "Color should never be nil")
    }
  }
}
```

**File:** `Tests/ContextifyCoreTests/ProjectWorktreeTests.swift`

```swift
import XCTest
@testable import ContextifyCore

final class ProjectWorktreeTests: XCTestCase {

  func testGitRootDetectionForWorktree() throws {
    // Create temporary worktree structure
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("worktree-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Create .git file (worktree marker)
    let gitFile = tempDir.appendingPathComponent(".git")
    let gitContent = "gitdir: /tmp/main-repo/.git/worktrees/test"
    try gitContent.write(to: gitFile, atomically: true, encoding: .utf8)

    // Test git root detection
    let gitRoot = GitRepositoryResolver.findGitRoot(from: tempDir)
    XCTAssertEqual(gitRoot, tempDir, "Should return worktree directory, not main repo")

    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testProjectIdentityUniqueness() {
    let project1ID = ProjectIdentity.computeProjectID(provider: .claudeCode, path: "/tmp/repo")
    let project2ID = ProjectIdentity.computeProjectID(provider: .claudeCode, path: "/tmp/repo-worktree")
    XCTAssertNotEqual(project1ID, project2ID, "Different paths should have different project IDs")
  }
}
```

### Integration Testing (Fixture-Based)

**File:** `scripts/qa/test-worktree-visual-grouping.sh`

```bash
#!/bin/bash
set -e

# Create test worktrees
TEST_DIR="/tmp/contextify-worktree-test-$(uuidgen)"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

git init main-repo
cd main-repo
git commit --allow-empty -m "Initial commit"

git worktree add ../worktree-1 -b feature-1
git worktree add ../worktree-2 -b feature-2

# Run Claude Code in each to generate transcripts
cd "$TEST_DIR/main-repo"
echo "Test message" | claude code --non-interactive || true

cd "$TEST_DIR/worktree-1"
echo "Test message" | claude code --non-interactive || true

cd "$TEST_DIR/worktree-2"
echo "Test message" | claude code --non-interactive || true

# Launch Contextify (DMG build required)
open -a Contextify

echo "✅ Test worktrees created:"
echo "  - $TEST_DIR/main-repo"
echo "  - $TEST_DIR/worktree-1"
echo "  - $TEST_DIR/worktree-2"
echo ""
echo "📋 Manual verification checklist:"
echo "  [ ] All 3 projects appear in tab bar"
echo "  [ ] All 3 projects have matching background color"
echo "  [ ] Color is visually distinct from other projects"
echo ""
echo "🧹 Cleanup command:"
echo "  rm -rf $TEST_DIR"
echo "  # Also remove from Contextify database via Projects window"
```

### Deferred UI Tests

**Per `build/notes/todo-support/deferred-ui-tests.md`:**

1. **Visual worktree grouping** (requires SwiftUI automation)
   - Verify related worktrees have matching background colors
   - Verify color is consistent across app restarts
   - **Deferred:** SwiftUI color inspection not reliable in tests

2. **Tab interaction** (requires SwiftUI automation)
   - Verify clicking tab switches active project
   - Verify border color changes with selection
   - **Deferred:** Tab interaction testing requires stable harness

**Documentation entry needed:**

```markdown
## Worktree Visual Grouping

**Behavior:** Projects from same git root have matching tab background color (10% opacity tint).

**Reproduction:**
1. Create git worktrees: `git worktree add ../worktree-1 -b feature`
2. Run Claude Code in both: `cd main-repo && claude code`, `cd worktree-1 && claude code`
3. Open Contextify
4. Observe tab bar

**Expected:** Both tabs have matching subtle background color.

**Linked TODO:** TODOS.md #WORKTREE (lines 2059-2066)
```

---

## 9. Open Questions

### Design Decisions Needed from User

1. **Color palette size:**
   - Current proposal: 10 colors
   - Alternative: 20 colors (lower collision probability)
   - Question: Is 10 colors sufficient for your typical workflow?

2. **Auto-switching behavior:**
   - Option A: Never auto-switch (manual only)
   - Option B: Auto-switch on new transcript (opt-in)
   - Option C: Auto-switch on terminal directory change (advanced, opt-in)
   - Question: Which behavior do you prefer?

3. **Branch name display:**
   - Option A: Always show branch name in tab
   - Option B: Only show on hover
   - Option C: Don't show (keeps tabs compact)
   - Question: Is branch name useful in tab, or too cluttered?

4. **Worktree count badge:**
   - Option A: Show count when > 1 worktree exists (e.g., "[3]")
   - Option B: Only show in Projects window, not tabs
   - Option C: Don't show (not useful)
   - Question: Is worktree count helpful in the tab view?

5. **CLI tooling integration priority:**
   - Question: Do you want worktree sync status (`wt-status.sh` output) visible in Contextify UI?
   - Question: Should Contextify be able to trigger `wt-sync.sh` operations?
   - Or: Keep CLI and UI separate, no integration needed?

6. **Phase 1 only vs full implementation:**
   - Option A: Ship Phase 1 (color coding) only, get user feedback
   - Option B: Implement Phases 1-2 together (color + badges)
   - Option C: Implement all phases at once
   - Question: What's the desired scope for initial release?

### Technical Decisions

1. **Color collision handling:**
   - With 10 colors, probability of collision = ~10% if user has 2 repos
   - Do we need a fallback strategy if two unrelated repos get same color?
   - Option: Add manual color override in Settings

2. **`ProjectContext.projectIdentifier` cleanup:**
   - Should we remove this property entirely?
   - Or fix it to use full path instead of git root?
   - Audit required to determine usage

3. **`allProjectPaths()` documentation:**
   - Should we rename this method to make intent clearer? (e.g., `allRelatedWorktreePaths()`)
   - Or just add comprehensive documentation?

4. **Performance considerations:**
   - Git root detection requires filesystem operations
   - Should we cache git root lookups?
   - Invalidation strategy if worktrees are added/removed?

---

## 10. References

### Investigation Documents
- `/Users/rob/code/projects/contextify-worker-bee/build/notes/todo-support/WORKTREE-investigation.md` (354 lines, 2025-11-25)
- `/tmp/worktree-total-recall-findings.md` (this research)
- `/tmp/worktree-web-research.md` (this research)
- `/tmp/worktree-existing-design.md` (this research)

### Implementation Files
- `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/ProjectIdentity.swift` (195 lines)
- `/Users/rob/code/projects/contextify-worker-bee/Contextify/Contextify/ProjectContext.swift` (91 lines)
- `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift`
- `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/HUDCore.swift` (lines 511-597)
- `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift` (lines 673-698)
- `/Users/rob/code/projects/contextify-worker-bee/app/Sources/ContextifyCore/Database/DatabaseSchema.swift` (lines 601-626)

### Tests
- `/Users/rob/code/projects/contextify-worker-bee/Tests/ContextifyCoreTests/ProjectIdentityTests.swift`
- `/Users/rob/code/projects/contextify-worker-bee/Contextify/ContextifyTests/GitDetectionTests.swift`

### TODO Entry
- `/Users/rob/code/projects/contextify-worker-bee/TODOS.md` (lines 2059-2066, "#WORKTREE")

### CLI Tooling (External)
- `~/code/projects/cli-ai-setup/utils/gitops/wt-status.sh`
- `~/code/projects/cli-ai-setup/utils/gitops/wt-sync.sh`
- `~/code/projects/cli-ai-setup/utils/gitops/wt-sync-all.sh`
- `~/code/projects/cli-ai-setup/utils/gitops/wt-init.sh`
- `~/code/projects/cli-ai-setup/utils/gitops/wt-context.sh`
- `~/code/projects/cli-ai-setup/utils/gitops/.worktrees.json` (registry)

### Conversation History
- Transcript ID: `5917FC7F-5641-41C6-935C-C4710B244E3C` (December 23, 2024 - Core problem discovery)
- Transcript ID: `F039D744-5C1A-436D-8F26-59080EBB70A1` (December 24, 2024 - CLI tooling development)
- Entry IDs for specific discussions documented in `/tmp/worktree-total-recall-findings.md`

### Design Resources
- `/Users/rob/code/projects/contextify-worker-bee/build/design/brand/colors.md` (color tokens)
- `/Users/rob/code/projects/contextify-worker-bee/build/docs/design/swiftui-patterns.md` (SwiftUI best practices)

### External Research Sources
- [IntelliJ idea-worktrees Plugin](https://github.com/djessup/idea-worktrees)
- [GitLens VS Code Extension](https://marketplace.visualstudio.com/items?itemName=eamodio.gitlens)
- [Tabs Studio - Tab Grouping](https://tabsstudio.com/documentation/visual_studio_tab_grouping.html)
- [Refactoring UI - Color Palette](https://www.refactoringui.com/previews/building-your-color-palette)

---

## 11. Next Steps

### Immediate Actions (to start Phase 1)

1. **User decision on open questions:**
   - Review "Open Questions" section above
   - Provide answers/preferences for design decisions
   - Approve Phase 1 scope or request modifications

2. **Pre-implementation verification:**
   - Run `swift test` to ensure tests pass
   - Run `bash scripts/xc.sh build` to verify zero warnings
   - Verify `ProjectSwitcherView.swift` location (may be named differently)

3. **Create implementation branch:**
   ```bash
   git checkout -b feat/worktree-visual-grouping
   ```

4. **Implementation sequence:**
   - [ ] Create `WorktreeColorUtility.swift` (1-2 hours)
   - [ ] Update tab view with color coding (2-3 hours)
   - [ ] Manual testing checklist (1 hour)
   - [ ] Screenshot documentation (30 mins)
   - [ ] Unit tests (optional, 1-2 hours)

5. **Pre-merge validation:**
   - [ ] Zero compiler warnings
   - [ ] Manual testing checklist passed
   - [ ] Screenshots captured
   - [ ] TODO entry updated with status

### Success Metrics

**Phase 1 complete when:**
- User can visually distinguish related worktrees by color
- Color assignment is deterministic and persistent
- No disruption to existing workflows
- Documentation updated (screenshot + user guide)

**Long-term success:**
- User reports reduced confusion about worktree relationships
- Faster project switching workflow
- No requests to revert feature (positive reception)

---

## Appendix A: Color Palette Visualization

```
┌──────────────────────────────────────────────────────────────┐
│ Contextify Design System - Worktree Accent Palette           │
├──────────────────────────────────────────────────────────────┤
│ SEMANTIC COLORS                                              │
│ 1. primary      #4A7BA7  ████████  Trust, Calm              │
│ 2. success      #51A86B  ████████  Growth                    │
│ 3. warning      #D4A84E  ████████  Energy, Attention         │
│ 4. error        #C74E4E  ████████  Urgency                   │
│ 5. accent       #7C68A8  ████████  Creativity                │
├──────────────────────────────────────────────────────────────┤
│ BRAND COLORS                                                 │
│ 6. brand-yellow #F9B233  ████████  Warmth                    │
│ 7. brand-cyan   #4AC4E0  ████████  Clarity                   │
│ 8. brand-purple #8B5CF6  ████████  Depth                     │
├──────────────────────────────────────────────────────────────┤
│ EXTENDED                                                     │
│ 9. secondary    #9B8B7E  ████████  Neutral                   │
│ 10. teal        #5A9BAA  ████████  Balance (derived)         │
└──────────────────────────────────────────────────────────────┘

Applied at 10% opacity for tab backgrounds.
Applied at 50% opacity for active tab borders.

Source: build/design/brand/colors.md
```

---

## Appendix B: Example Tab Layouts

### Before (Current State)

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ contextify      │  │ contextify-work │  │ other-project   │
│                 │  │                 │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘

No visual indication of relationships.
```

### After Phase 1 (Color Coding)

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ contextify      │  │ contextify-work │  │ other-project   │
│ [blue tint]     │  │ [blue tint]     │  │ [green tint]    │
└─────────────────┘  └─────────────────┘  └─────────────────┘
       ↑                     ↑                     ↑
       └─────────────────────┘                     │
       Same git root = blue                   Different git root
```

### After Phase 2 (Badges + Branch)

```
┌───────────────────────┐  ┌───────────────────────┐  ┌───────────────────────┐
│ contextify       [2]  │  │ contextify-work  [2]  │  │ other-project         │
│   main                │  │   feat/lazy-watch     │  │   main                │
│ [blue tint]           │  │ [blue tint]           │  │ [green tint]          │
└───────────────────────┘  └───────────────────────┘  └───────────────────────┘
       ↑                           ↑                           ↑
       [2] = 2 worktrees    Same color/count          Different repo
```

---

## Document Metadata

**Prepared by:** Claude Code Agent
**Research Sources:** 3 files (total-recall, web research, existing design)
**Total Lines:** ~1200 (comprehensive spec)
**Ready for Implementation:** Yes (pending user decisions on open questions)
**Estimated Read Time:** 20-25 minutes
**Primary Stakeholder:** Rob (user)
**Next Action:** User review + decision on Phase 1 scope and open questions
