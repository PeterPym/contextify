# Removal Plan: Deprecated "Exclude" Functionality

## Summary
Remove deprecated UserDefaults-based "exclude" functionality in favor of database-backed "hide" feature.

## Functional Difference
- **Exclude (DEPRECATED):** Prevents project discovery at filesystem scan level (UserDefaults storage)
- **Hide (CURRENT):** Hides projects from tab bar only, still tracks in database (SQL storage)

The "hide" functionality is superior because:
- Database-backed (persistent, queryable)
- More granular (hides from tabs but still tracks data)
- Better UX (bulk restore option in context menu)

---

## Files to DELETE Entirely

### 1. ExcludedProjectsView.swift
**Path:** `Contextify/Contextify/ExcludedProjectsView.swift`
**Reason:** Modal UI for managing excluded projects
**Lines:** 1-136 (entire file)

### 2. ProjectExclusionManager.swift
**Path:** `app/Sources/ContextifyCore/Projects/ProjectExclusionManager.swift`
**Reason:** UserDefaults-based exclusion storage
**Lines:** Entire file

---

## Code to REMOVE from Existing Files

### 3. ProjectsWindow.swift
**Path:** `Contextify/Contextify/ProjectsWindow.swift`

**Remove: State variable**
```swift
@State private var showingExcluded = false
```
**Location:** Near other @State declarations

**Remove: "Show Excluded" button**
```swift
Button("Show Excluded") {
  showingExcluded = true
}
.buttonStyle(.bordered)
```
**Location:** Line ~87-90 (in toolbar HStack)

**Remove: Sheet modifier**
```swift
.sheet(isPresented: $showingExcluded) {
  ExcludedProjectsView()
    .environment(viewModel)
}
```
**Location:** Line ~31-34 (in view body)

### 4. ProjectRowView.swift
**Path:** `Contextify/Contextify/ProjectRowView.swift`

**Remove: onExclude callback**
```swift
let onExclude: () -> Void
```
**Location:** Line ~9 (in struct properties)

**Remove: "Hide from List" menu item**
```swift
Button("Hide from List", action: onExclude)
```
**Location:** Line ~113 (in context menu)

### 5. ProjectsViewModel.swift
**Path:** `Contextify/Contextify/ProjectsViewModel.swift`

**Remove: excludeProject method**
```swift
/// Excludes a project from the list
func excludeProject(_ project: DiscoveredProject) {
  logger.info("Excluding project: \(project.name)")

  Task {
    await discoveryService.excludeProject(project.path.path)

    // Refresh list to remove excluded project
    let currentPath = hudModel.projectRootURL?.path
    await discoverProjects(currentPath: currentPath)
    discoverProjectsInFlight = false
  }
}
```
**Location:** Lines ~174-187

**Remove: getExcludedProjects method**
```swift
/// Gets all excluded projects
func getExcludedProjects() async -> Set<String> {
  await discoveryService.getExcludedProjects()
}
```
**Location:** Lines ~189-192

### 6. ProjectDiscoveryService.swift
**Path:** `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift`

**Remove: exclusionManager property**
```swift
private let exclusionManager: ProjectExclusionManager
```
**Location:** In property declarations

**Remove: exclusionManager initialization**
```swift
exclusionManager = ProjectExclusionManager()
```
**Location:** In init()

**Remove: Exclusion filtering logic**
```swift
// 2. Filter out excluded projects
let excluded = await exclusionManager.getExcludedProjects()
let filteredProjects = claudeProjects.filter { !excluded.contains($0.path) }

if claudeProjects.count > filteredProjects.count {
  logger.debug("Filtered out \(claudeProjects.count - filteredProjects.count) excluded projects")
}
```
**Location:** Lines ~39-45 (in discoverProjects method)
**Replace with:** `let filteredProjects = claudeProjects`

**Remove: Exclusion management methods**
```swift
// MARK: - Exclusion Management

/// Excludes a project from future discovery
public func excludeProject(_ projectPath: String) async {
  await exclusionManager.excludeProject(projectPath)
  logger.info("Excluded project: \(projectPath)")
}

/// Includes a previously excluded project
public func includeProject(_ projectPath: String) async {
  await exclusionManager.includeProject(projectPath)
  logger.info("Included project: \(projectPath)")
}

/// Gets all excluded project paths
public func getExcludedProjects() async -> Set<String> {
  await exclusionManager.getExcludedProjects()
}
```
**Location:** Lines ~376-393

---

## Callsite Updates

### ProjectsWindow.swift
**Before:**
```swift
ProjectRowView(
  project: project,
  onSetAsCurrent: { ... },
  onRevealInFinder: { ... },
  onExclude: { viewModel.excludeProject(project) },
  onShowStats: { ... }
)
```

**After:**
```swift
ProjectRowView(
  project: project,
  onSetAsCurrent: { ... },
  onRevealInFinder: { ... },
  onShowStats: { ... }
)
```

---

## Testing After Removal

1. **Build verification:**
   ```bash
   bash scripts/xc.sh build
   ```

2. **Functional tests:**
   - Open Projects window
   - Verify no "Show Excluded" button in toolbar
   - Verify no "Hide from List" menu item in project row context menu
   - Verify "Hide this Project" still works in main window tab bar
   - Verify "Restore Hidden Projects" still works

3. **Database migration:**
   - No schema changes needed (hidden column remains for active feature)
   - UserDefaults cleanup: Optional - could add migration to clear old excluded projects key

---

## Optional: UserDefaults Cleanup Migration

If desired, add one-time cleanup in app startup:

```swift
// In ContextifyApp.swift or appropriate init location
private func cleanupLegacyExclusions() {
  // Remove deprecated UserDefaults key
  UserDefaults.standard.removeObject(forKey: "dev.contextify.excluded_projects")
}
```

---

## Summary of Changes

**Files to delete:** 2
- `ExcludedProjectsView.swift`
- `ProjectExclusionManager.swift`

**Files to modify:** 4
- `ProjectsWindow.swift` (remove button, sheet, state)
- `ProjectRowView.swift` (remove callback, menu item)
- `ProjectsViewModel.swift` (remove 2 methods)
- `ProjectDiscoveryService.swift` (remove property, methods, filtering logic)

**Total lines removed:** ~200-250 lines
**Functionality preserved:** "Hide" feature in database remains fully functional
