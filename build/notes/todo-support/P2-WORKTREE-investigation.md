---
todo_id: P2-WORKTREE
title: Git Worktree Support Investigation
type: investigation
date: 2025-11-25
status: active
description: Analysis of git worktree support in Contextify - what works, gaps, and proposed fixes
discovered_during: P3-LOGOMARK debugging
---

# Git Worktree Support Analysis

**Status:** PARTIAL SUPPORT (works in some scenarios, gaps in others)

## Executive Summary

Contextify has **partial** git worktree support. The current implementation correctly:
1. Detects worktrees via `.git` file with `gitdir:` pointer
2. Creates separate projects for different CWD paths
3. Associates transcripts based on the working directory where Claude Code/Codex was launched

**However**, there are gaps that cause issues in some worktree scenarios.

## How Worktrees Currently Work

### Claude Code Transcript Storage

Claude Code organizes transcripts by encoding the working directory path:

```
~/.claude/projects/
+-- -Users-rob-code-projects-contextify/        # Main repo
|   +-- session-uuid.jsonl
+-- -Users-rob-code-projects-contextify-worker/ # Worktree (different CWD)
    +-- session-uuid.jsonl
```

The path encoding replaces `/` with `-`, so:
- `/Users/rob/code/projects/contextify` becomes `-Users-rob-code-projects-contextify`
- `/Users/rob/code/projects/contextify-worker` becomes `-Users-rob-code-projects-contextify-worker`

**Key insight:** Because worktrees have different filesystem paths, their transcripts are stored in SEPARATE directories by Claude Code. This is the foundation that makes worktree support possible.

### Contextify's Project Discovery

`LightweightDiscoveryService.scanClaudeDirectory()` discovers projects by:
1. Scanning `~/.claude/projects/` subdirectories
2. For each directory, extracting the `cwd` field from transcript JSONL files
3. Using the decoded CWD as the canonical `root_path`

```swift
// From LightweightDiscoveryService.swift:84-97
let hashFolder = dir.lastPathComponent
let realPath = resolveClaudeProjectPath(hashFolder: hashFolder, directory: dir, transcripts: files)
let displayName = realPath.map { URL(fileURLWithPath: $0).lastPathComponent }
  ?? fallbackDisplayName(for: hashFolder)

return LightweightProject(
  id: hashFolder,
  path: dir,
  displayName: displayName,
  cwd: realPath,  // The actual filesystem path
  ...
)
```

### Database Uniqueness

Projects are uniquely identified by `root_path` in the database:

```sql
-- From DatabaseSchema.swift:615
CREATE UNIQUE INDEX idx_projects_root_path ON projects(root_path)
```

This means:
- `/Users/rob/code/projects/contextify` = Project A
- `/Users/rob/code/projects/contextify-worker` = Project B (SEPARATE)

## What Works

### Scenario 1: Worktrees in Different Directories (WORKS)

```
/Users/rob/code/projects/
+-- contextify/          # Main repo
+-- contextify-worker/   # Worktree checked out to different branch
```

- Each has a unique `root_path`
- Each gets its own project entry
- Transcripts are correctly associated
- **Result: WORKS CORRECTLY**

### Scenario 2: Multiple Unrelated Projects with Same Name (WORKS)

```
/Users/rob/code/projects/contextify/       # Project A
/Users/rob/code/personal/contextify/       # Project B (unrelated)
```

- Different `root_path` values
- Both appear as separate projects (both named "contextify" but distinguishable)
- **Result: WORKS CORRECTLY**

## What Doesn't Work (Gaps)

### Gap 1: ProjectContext.projectIdentifier Uses Git Root

`ProjectContext.swift:14` computes a shared identifier from the git root:

```swift
self.projectIdentifier = (gitRepoRoot ?? workingDirectory).lastPathComponent
```

For worktrees sharing the same git root:
- Main repo: gitRoot = `/Users/rob/code/projects/contextify`, identifier = "contextify"
- Worktree: gitRoot = `/Users/rob/code/projects/contextify` (SAME!), identifier = "contextify"

**Impact:** The `projectIdentifier` is used for display but NOT for database queries. The database uses `root_path` (the full CWD path), which is correct. This is mostly cosmetic but confusing.

### Gap 2: allProjectPaths() Returns All Related Paths

`ProjectContext.swift:74-89` returns paths from the git root perspective:

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

**Impact:** This is designed for AGGREGATING transcripts across worktrees, not for isolating them. If called when you want ONLY the current worktree's transcripts, you'd get all of them.

### Gap 3: No Visual Indication of Related Worktrees

The tab bar shows projects by their `displayName` (last path component):
- contextify
- contextify-worker

There's no visual grouping or color coding to indicate these are related worktrees from the same repository.

### Gap 4: Git Root Detection May Return Main Repo

`GitRepositoryResolver.findGitRoot()` walks up from the CWD and returns the first directory containing `.git`:

```swift
// From HUDCore.swift:363-387
public static func findGitRoot(startingAt url: URL, maxDepth: Int = 64) -> URL? {
  var current = url.resolvingSymlinksInPath()
  while depth < maxDepth, visited.insert(current).inserted {
    let dotGit = current.appendingPathComponent(".git")
    if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
      if isDir.boolValue { /* regular repo */ }
      if let gitdir = resolveGitDir(for: current) {
        let headPath = gitdir.appendingPathComponent("HEAD").path
        if fm.fileExists(atPath: headPath) { return current }  // Returns worktree dir
      }
    }
    // ... walk up
  }
}
```

For worktrees, this correctly returns the WORKTREE directory (where `.git` is a file pointing to the main repo's worktrees directory). This is correct behavior.

**However:** Some code paths may assume the git root IS the main repo, not a worktree. This needs verification in specific flows.

## Root Name Collision Concern

Analysis of "contextify and contextify-worker-bee" collision concern:

### Scenario: Similar Project Names

```
/Users/rob/code/projects/contextify/           # Main repo
/Users/rob/code/projects/contextify-worker-bee/ # Worktree OR unrelated project
```

**No collision occurs because:**
1. Claude Code stores in SEPARATE directories:
   - `-Users-rob-code-projects-contextify/`
   - `-Users-rob-code-projects-contextify-worker-bee/`
2. Database uses FULL `root_path` as unique key
3. Display names are DIFFERENT ("contextify" vs "contextify-worker-bee")

**Edge case to watch:** If a project name contains hyphens that could confuse the path decoding:
- `/Users/rob/code/my-project-name/` encoded as `-Users-rob-code-my-project-name`
- When decoded, the `-` between path segments vs `-` in the name must be distinguished

`LightweightDiscoveryService.findRealPath()` handles this by trying progressive combinations:

```swift
// From LightweightDiscoveryService.swift:230-252
nonisolated private func findRealPath(hashFolder: String) -> String? {
  let components = base.components(separatedBy: "-")
  for mergeCount in 0..<components.count {
    // Try progressively merging components with hyphens
    let testPath = testComponents.joined(separator: "/")
    if FileManager.default.fileExists(atPath: testPath) {
      return testPath
    }
  }
}
```

This works but is O(n) in the number of path segments.

## Code Changes Needed for Full Worktree Support

### 1. Visual Grouping in Tab Bar (P2 Enhancement)

**File:** `Contextify/Contextify/ProjectSwitcherView.swift` (or wherever tab bar is rendered)

**Change:** Add background color or grouping indicator for projects sharing the same git root.

**Approach:**
```swift
// Pseudocode
struct ProjectTabView: View {
  let project: Project
  let gitRoot: URL?  // Computed from project.rootPath

  var groupColor: Color {
    // Hash the git root path to a consistent color
    gitRoot.map { colorForGitRoot($0) } ?? .clear
  }

  var body: some View {
    TabButton(project.displayName)
      .background(groupColor.opacity(0.1))
  }
}
```

**Complexity:** LOW - UI change only, no backend changes needed.

### 2. Fix projectIdentifier to Use Full Path (P3 Cleanup)

**File:** `Contextify/Contextify/ProjectContext.swift:14`

**Current:**
```swift
self.projectIdentifier = (gitRepoRoot ?? workingDirectory).lastPathComponent
```

**Change to:**
```swift
self.projectIdentifier = workingDirectory.path  // Use full path for uniqueness
```

**Or remove projectIdentifier entirely** since it's only used for display and `displayName` already serves that purpose.

**Impact:** Need to audit all usages of `projectIdentifier` to ensure nothing breaks.

### 3. Clarify allProjectPaths() Intent (P3 Documentation)

**File:** `Contextify/Contextify/ProjectContext.swift:74`

**Current behavior:** Returns all paths (main + worktrees) - correct for aggregation
**Expected behavior:** Should be clear when to use this vs. `workingDirectory` alone

**Change:** Add documentation clarifying when to aggregate vs. isolate:

```swift
/// Returns all project paths that should be checked for transcripts.
/// Use this when you want to find ALL transcripts across the main repo and all worktrees.
/// Use `workingDirectory` alone when you want ONLY the current worktree's transcripts.
func allProjectPaths() -> [URL] { ... }
```

### 4. Ensure Transcript-to-Project Association is Strict (P1 Verification)

**Verify these flows use the EXACT CWD, not git root:**

1. `LightweightDiscoveryService.scanClaudeDirectory()` - VERIFIED: Uses `cwd` from transcript
2. `TranscriptOrchestrator.discoverTranscript()` - VERIFY: Uses `projectId` parameter
3. `HooverEngine.hooverTranscript()` - VERIFY: Uses `transcript.projectId`

**Test case needed:**
1. Create two worktrees: `/tmp/repo-main` and `/tmp/repo-worker`
2. Run Claude Code in each
3. Verify transcripts appear in separate projects in Contextify
4. Verify timeline shows ONLY the correct worktree's messages

## Testing Strategy

### SPM-Compatible Tests (Can implement now)

These tests can run in the Swift Package Manager test suite:

1. **Unit test: Path encoding/decoding with hyphens**
   - Test `findRealPath()` with paths containing hyphens
   - Verify `/Users/rob/code/my-project-name/` decodes correctly
   - File: `Tests/ContextifyCoreTests/DiscoveryTests.swift`

2. **Unit test: Project uniqueness by root_path**
   - Test that two projects with same display name but different paths are distinct
   - Mock database operations
   - File: `Tests/ContextifyCoreTests/ProjectRepositoryTests.swift`

3. **Unit test: Git root detection for worktrees**
   - Test `GitRepositoryResolver.findGitRoot()` with worktree `.git` file
   - Test `resolveGitDir()` follows `gitdir:` pointer correctly
   - File: `Tests/ContextifyCoreTests/GitRepositoryResolverTests.swift`

4. **Integration test: Transcript-project association**
   - Create mock transcripts with different CWDs
   - Verify they're associated with correct projects
   - File: `Tests/ContextifyCoreTests/TranscriptAssociationTests.swift`

### Deferred SwiftUI Tests (UI harness limitations)

Per `build/notes/todo-support/deferred-ui-tests.md`, these require stable SwiftUI automation:

1. **Visual worktree grouping**
   - Verify related worktrees have matching background colors
   - Verify color is consistent across app restarts
   - Deferred: Requires tab bar rendering verification

2. **Tab bar display with multiple worktrees**
   - Verify all worktrees appear as separate tabs
   - Verify switching between worktrees works correctly
   - Deferred: Requires tab interaction testing

## Summary

| Aspect | Status | Notes |
|--------|--------|-------|
| Transcript storage isolation | **WORKS** | Claude Code uses separate dirs per CWD |
| Database project uniqueness | **WORKS** | `root_path` is unique indexed |
| Project discovery | **WORKS** | Extracts CWD from transcripts |
| Transcript-project association | **NEEDS VERIFICATION** | Should use CWD, not git root |
| Visual worktree grouping | **NOT IMPLEMENTED** | P2 enhancement |
| projectIdentifier consistency | **CONFUSING** | Uses git root, may collide |

**Overall Assessment:** The core infrastructure supports worktrees. The main gaps are:
1. Verification that all code paths use CWD (not git root) for association
2. Visual UX for indicating related worktrees
3. Cleanup of confusing `projectIdentifier` property

## References

- `Contextify/Contextify/ProjectContext.swift` - Worktree discovery logic
- `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift` - Project discovery
- `app/Sources/ContextifyCore/HUDCore.swift:215-387` - GitRepositoryResolver
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift:601-626` - Project table schema
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` - Transcript ingestion
- `build/docs/specifications/transcript-formats.md` - Transcript storage structure
