# Code Quality & Anti-Pattern Prevention Guidelines

**Purpose:** Prevent recurrence of code smells discovered in 2025-11-23 audit
**Audience:** Claude Code, human developers, code reviewers
**Status:** Draft for CLAUDE.md integration

---

## Overview

This document contains comprehensive guidelines to prevent the 10 major anti-patterns discovered during systematic codebase audit. Each guideline includes:
- **Rule:** What to do/avoid
- **Why:** Consequences of violation
- **How:** Concrete implementation patterns
- **Enforcement:** How to verify compliance

---

## 1. SQL Query Patterns - Timeline Entry Queries

### Rule: ALWAYS Apply display_in_timeline Filter

Every query loading `transcript_entries` for **user-facing display** MUST include:
```sql
WHERE display_in_timeline = 1
```

### Why

- **Hidden entries are for internal use only** (embeddings, analysis, debugging)
- Showing hidden entries in UI confuses users
- Generates unnecessary LLM summaries (wasted resources ~480 calls)
- Business rule applied inconsistently (52% of queries had filter, 48% didn't)

### When Filter Is Required

✅ **MUST apply filter:**
- Timeline display
- Search results
- Entry feeds
- Recent entries
- Any user-facing list

❌ **Skip filter ONLY for:**
- Embedding generation (needs all content)
- Statistics/analytics (counting ALL entries)
- Database maintenance operations
- Admin/debug tools (explicitly showing hidden)

### How to Implement

**Pattern 1: Query Builder (Preferred)**
```swift
// ✅ CORRECT - filter always applied
let entries = try TranscriptEntry
  .filter(Column("project_id") == projectId)
  .filter(Column("display_in_timeline") == 1)  // ← REQUIRED
  .order(Column("timestamp").desc)
  .fetchAll(db)
```

**Pattern 2: Raw SQL (Use Sparingly)**
```swift
// ✅ CORRECT - filter in WHERE clause
let entries = try TranscriptEntry.fetchAll(db, sql: """
  SELECT * FROM transcript_entries
  WHERE project_id = :pid
    AND display_in_timeline = 1
  ORDER BY timestamp DESC
""", arguments: ["pid": projectId])
```

**Pattern 3: Document Exceptions**
```swift
// ❌ Intentionally querying ALL entries (including hidden) for embedding generation
// This is CORRECT for this use case - we need hidden entries for vector search
let entries = try TranscriptEntry.fetchAll(db, sql: """
  SELECT id, content FROM transcript_entries
  WHERE length(content) >= :minLength
""", arguments: ["minLength": 100])
```

### Enforcement

**Pre-commit Check:**
```bash
# Find queries potentially missing filter
rg "SELECT.*FROM transcript_entries" --type swift | grep -v "display_in_timeline"

# Review each result:
# - Is it user-facing? → Add filter
# - Is it internal? → Add comment explaining why filter is skipped
```

**Code Review Checklist:**
- [ ] Every new entry query has display_in_timeline filter OR documented exception
- [ ] Existing queries not modified to remove filter
- [ ] Test verifies hidden entries are excluded

**Automated Test Pattern:**
```swift
func testTimelineExcludesHiddenEntries() throws {
  // Given: mix of visible and hidden entries
  try createEntry(projectId: "test", displayInTimeline: 1)
  try createEntry(projectId: "test", displayInTimeline: 0) // hidden

  // When: loading timeline
  let entries = try repository.recentEntries(projectId: "test")

  // Then: only visible entries returned
  XCTAssertTrue(entries.allSatisfy { $0.displayInTimeline == 1 })
}
```

---

## 2. State Management - Observable State Sync

### Rule: Database Writes MUST Refresh Observable State

When you write to the database from code that manages `@Observable` state, you MUST refresh the state immediately in the same operation.

### Why

**Without sync:**
- UI shows stale data (user just clicked "mark as read" but count doesn't change)
- Requires manual refresh (bad UX)
- Easy to break during refactoring (no compiler error)
- Temporal coupling (works if you happen to refresh later, breaks if you don't)

**Discovered bugs:**
- Unread counts stayed at old value after viewing project
- Project list didn't reflect hidden state after hiding
- Required page reload to see changes

### Pattern 1: Refresh in Same Method (Simple)

```swift
// ✅ CORRECT - write then refresh
func hideProject(_ projectId: String) async {
  do {
    // 1. Write to database
    try orchestrator.setProjectHidden(projectId: projectId, hidden: true)

    // 2. Refresh state immediately
    await refreshProjects()

  } catch {
    log.error("Failed to hide project: \(error)")
  }
}
```

### Pattern 2: Return Fresh State (Better)

```swift
// Orchestrator layer
public func markProjectViewed(projectId: String, timestamp: String) throws -> ProjectVisit {
  try dbManager.pool.write { db in
    try projectVisitsRepository.markViewed(db: db, projectId: projectId, timestamp: timestamp)

    // Return fresh state in same transaction
    return try projectVisitsRepository.getVisit(projectId: projectId)!
  }
}

// State layer
func selectProject(_ projectId: String) async {
  let visit = try orchestrator.markProjectViewed(projectId: projectId, timestamp: now)
  self.unreadCounts[projectId] = visit.unreadCount  // Use returned state
}
```

### Pattern 3: Reactive (Best for Complex Cases)

```swift
// Use AsyncStream or Combine to observe database changes
// State automatically updates when database changes
class ProjectState: Observable {
  @ObservationIgnored
  private var dbObserver: Task<Void, Never>?

  init(orchestrator: TranscriptOrchestrator) {
    dbObserver = Task {
      for await projects in orchestrator.observeProjects() {
        await MainActor.run {
          self.allProjects = projects
        }
      }
    }
  }
}
```

### When NOT to Refresh

**Don't refresh if:**
- State is purely in-memory (no database backing)
- Operating on different data (write to project A, state tracks project B)
- Background operation (user can't see the result anyway)

**DO document why:**
```swift
// NOTE: Not refreshing state here because this runs in background
// and user-facing state is refreshed on next project switch
Task.detached {
  try orchestrator.cleanupOrphanedProjects()
  // No refresh - this is background maintenance
}
```

### Testing Pattern

```swift
func testStateRefreshesAfterDatabaseWrite() async throws {
  // Given: initial state
  let state = ProjectSwitcherState()
  state.unreadCounts[projectId] = 5

  // When: database write operation
  await state.markProjectViewed(projectId)

  // Then: state MUST reflect database change
  XCTAssertEqual(state.unreadCounts[projectId], 0,
    "State must refresh after database write")
}
```

### Enforcement

**Code Review Checklist:**
- [ ] Database write followed by state refresh (or documented exception)
- [ ] State refresh in same method (not caller's responsibility)
- [ ] Tests verify state changes after database writes
- [ ] No temporal coupling (order-dependent correctness)

**Common Violations:**
```swift
// ❌ BAD - write without refresh
func markAsRead(id: String) {
  try orchestrator.markRead(id)
  // BUG: self.unreadCount still has old value
}

// ❌ BAD - refresh is caller's responsibility
func markAsRead(id: String) {
  try orchestrator.markRead(id)
  // Caller must remember to call refreshState() - fragile!
}

// ✅ GOOD - write and refresh together
func markAsRead(id: String) async {
  try orchestrator.markRead(id)
  await refreshState()  // Always refreshes
}
```

---

## 3. Architecture - Layer Discipline

### Rule: Respect Layer Boundaries

```
UI Layer → State Layer → Orchestrator → Repository → Database
```

**Each layer has clear responsibilities:**
- **UI:** Display, user interaction, navigation
- **State:** @Observable properties, derived state, UI logic
- **Orchestrator:** Business logic, coordination, validation
- **Repository:** Data access, queries, persistence
- **Database:** Storage, migrations, schema

### Layer Violations to Avoid

#### Violation 1: UI Importing GRDB

```swift
// ❌ BAD - UI layer directly importing database
import GRDB
struct MyView: View {
  @State var db: DatabasePool

  var body: some View {
    .task {
      let entries = try! db.read { db in
        try TranscriptEntry.fetchAll(db)
      }
    }
  }
}
```

**Fix:** Use Orchestrator
```swift
// ✅ GOOD - UI calls Orchestrator
struct MyView: View {
  @State var orchestrator: TranscriptOrchestrator

  var body: some View {
    .task {
      let entries = try await orchestrator.getEntries()
    }
  }
}
```

#### Violation 2: Orchestrator with Raw SQL (Bypassing Repository)

```swift
// ❌ BAD - Orchestrator reimplementing Repository query
public func getRecentEntries(projectId: String) throws -> [TranscriptEntry] {
  try pool.read { db in
    try TranscriptEntry.fetchAll(db, sql: """
      SELECT * FROM transcript_entries WHERE project_id = ?
    """, arguments: [projectId])
  }
}
```

**Fix:** Delegate to Repository
```swift
// ✅ GOOD - Orchestrator delegates to Repository
public func getRecentEntries(projectId: String) throws -> [TranscriptEntry] {
  try repository.recentEntries(projectId: projectId, limit: 50)
}
```

#### Violation 3: Business Logic in UI

```swift
// ❌ BAD - validation in UI layer
struct ProjectNameField: View {
  @State var name: String

  func save() {
    if name.count < 3 {
      showError("Name too short")
      return
    }
    if name.contains("/") {
      showError("Invalid character")
      return
    }
    orchestrator.saveProject(name: name)
  }
}
```

**Fix:** Move validation to Orchestrator
```swift
// Orchestrator
public func saveProject(name: String) throws {
  guard name.count >= 3 else {
    throw ValidationError.nameTooShort
  }
  guard !name.contains("/") else {
    throw ValidationError.invalidCharacters
  }
  try repository.save(name: name)
}

// UI
struct ProjectNameField: View {
  func save() async {
    do {
      try await orchestrator.saveProject(name: name)
    } catch {
      showError(error.localizedDescription)
    }
  }
}
```

### When to Break Rules

**Raw SQL in Orchestrator is OK when:**
- Complex transaction spanning multiple repositories
- Performance-critical path needing custom optimization
- Migration or one-time data transformation

**Document exceptions:**
```swift
// NOTE: Using raw SQL here instead of Repository because:
// 1. Joins across 3 tables (no single repository owns all)
// 2. Performance-critical (hot path in timeline refresh)
// 3. Complex transaction with rollback logic
public func complexOperation() throws {
  try pool.write { db in
    // ... raw SQL ...
  }
}
```

### Enforcement

**Architectural Tests:**
```swift
func testUILayerDoesNotImportGRDB() {
  let uiFiles = /* glob Contextify/Contextify/*.swift */
  for file in uiFiles {
    let content = try String(contentsOf: file)
    XCTAssertFalse(content.contains("import GRDB"),
      "\(file) should not import GRDB directly")
  }
}
```

**Code Review Checklist:**
- [ ] No `import GRDB` in UI layer files
- [ ] Orchestrator methods delegate to Repository (not raw SQL)
- [ ] Business logic in Orchestrator, not UI
- [ ] Each layer only talks to adjacent layer (no skip levels)

---

## 4. Concurrency - Task Management

### Rule: Track and Cancel Background Tasks

**Every `Task.detached` or long-running `Task` MUST be:**
1. Stored in a property (so it can be cancelled)
2. Cancelled when context changes (view disappears, project switches)

### Why

**Without cancellation:**
- Wasted CPU/memory (task runs after result no longer needed)
- Race conditions (task completes with stale data)
- Resource leaks (database connections held)
- Confusing state updates (user switched projects, old task updates UI)

### Pattern: Store and Cancel

```swift
class ConversationMonitor: Observable {
  private var refreshTask: Task<Void, Never>?

  func startRefresh() {
    // Cancel previous task if still running
    refreshTask?.cancel()

    // Start new task
    refreshTask = Task {
      await loadEntries()
    }
  }

  func stop() {
    refreshTask?.cancel()
    refreshTask = nil
  }
}
```

### Pattern: Task Group for Multiple Concurrent Tasks

```swift
func loadMultipleProjects(ids: [String]) async {
  await withTaskGroup(of: Project?.self) { group in
    for id in ids {
      group.addTask {
        try? await self.loadProject(id)
      }
    }

    for await project in group {
      if let p = project {
        self.projects.append(p)
      }
    }
  }
  // All tasks automatically cancelled if parent task cancelled
}
```

### Pattern: Cancellable Stream Processing

```swift
class Monitor: Observable {
  private var streamTask: Task<Void, Never>?

  func startMonitoring() {
    streamTask = Task {
      for await event in eventStream {
        // Check for cancellation in long-running loops
        if Task.isCancelled { break }

        await processEvent(event)
      }
    }
  }

  func stopMonitoring() {
    streamTask?.cancel()
    streamTask = nil
  }
}
```

### When Task.detached Is OK

**Use Task.detached ONLY when:**
- Task is truly independent of current context
- Task should outlive current view/object
- Task is fire-and-forget (result not needed)

**Document why:**
```swift
// NOTE: Using Task.detached because this background cleanup
// should complete even if the view is dismissed
Task.detached(priority: .background) {
  await cleanupTempFiles()
}
```

### Enforcement

**Code Review Checklist:**
- [ ] Every Task.detached is documented (why detached?)
- [ ] Long-running Tasks are stored and cancellable
- [ ] Tasks are cancelled in cleanup methods (stop, deinit, onDisappear)
- [ ] Task.isCancelled checked in long loops

**Pattern to Avoid:**
```swift
// ❌ BAD - fire and forget, no way to cancel
Task.detached {
  await longOperation()
}

// ✅ GOOD - stored and cancellable
private var operationTask: Task<Void, Never>?

func start() {
  operationTask = Task.detached {
    await longOperation()
  }
}

func stop() {
  operationTask?.cancel()
}
```

---

## 5. Concurrency - Actor Isolation Safety

### Rule: Avoid nonisolated(unsafe) Unless Truly Immutable

Properties marked `nonisolated(unsafe)` bypass Swift 6 concurrency safety. Use ONLY for:
- Immutable singletons (initialized once, never changed)
- Thread-safe system objects (locks, semaphores)

### When It's Safe

```swift
// ✅ SAFE - immutable after initialization
nonisolated(unsafe) private static let formatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "yyyy-MM-dd"
  return f
}()

// ✅ SAFE - thread-safe system object
nonisolated(unsafe) private let lock = NSLock()
```

### When It's UNSAFE

```swift
// ❌ UNSAFE - mutable flag without synchronization
nonisolated(unsafe) private static var hasWarned = false

func warnOnce() {
  if !hasWarned {  // RACE CONDITION
    print("Warning")
    hasWarned = true
  }
}
```

### Fix: Use Actor Isolation

```swift
// ✅ SAFE - actor protects mutable state
actor WarningTracker {
  private var hasWarned = false

  func warnOnce() {
    if !hasWarned {
      print("Warning")
      hasWarned = true
    }
  }
}
```

### Audit Existing Code

**Found 22 `nonisolated(unsafe)` usages - most are safe singletons, but MUST verify:**
```bash
rg "nonisolated\(unsafe\)" --type swift -A 3
```

For each:
- ✅ Immutable singleton → OK
- ⚠️ Mutable → Needs actor protection
- ⚠️ Unclear → Add comment explaining thread safety

### Enforcement

**Code Review Checklist:**
- [ ] Every nonisolated(unsafe) has comment explaining why it's safe
- [ ] Mutable state uses actor isolation instead
- [ ] Immutable singletons documented as such

---

## 6. Error Handling - Consistency by Layer

### Rule: Standardize Error Handling by Layer

**Different layers use different strategies:**
- **Repository:** Always `throws` (data layer failures)
- **Orchestrator:** Always `throws` (business logic errors)
- **State/ViewModel:** Catch and expose as `@State var errorMessage: String?`
- **Background tasks:** Log and continue (or retry)

### Repository Layer

```swift
// ✅ ALWAYS throws
protocol ProjectRepository {
  func get(id: String) throws -> Project
  func save(_ project: Project) throws
}
```

### Orchestrator Layer

```swift
// ✅ ALWAYS throws
public class TranscriptOrchestrator {
  public func getProject(id: String) throws -> Project {
    try repository.get(id: id)
  }
}
```

### State/ViewModel Layer

```swift
// ✅ Catch and expose to UI
@Observable
class ProjectState {
  var errorMessage: String?

  func loadProject(id: String) async {
    do {
      let project = try await orchestrator.getProject(id: id)
      self.currentProject = project
      self.errorMessage = nil
    } catch {
      self.errorMessage = "Failed to load project: \(error.localizedDescription)"
    }
  }
}
```

### Background Task Layer

```swift
// ✅ Log and continue (or retry)
Task.detached {
  do {
    try await backgroundOperation()
  } catch {
    logger.error("Background operation failed: \(error)")
    // Continue - user doesn't need to know
  }
}
```

### When to Use Result<T, Error>

**Use Result only when:**
- Caller needs to distinguish success/failure without exceptions
- Building async operation pipeline
- Compatibility with APIs expecting Result

**Most of our code should use `throws`** (simpler, more idiomatic)

### Enforcement

**Code Review Checklist:**
- [ ] Repository methods throw (don't silently fail)
- [ ] Orchestrator methods throw (propagate errors)
- [ ] ViewModels catch and set error state
- [ ] Background tasks log errors (don't crash)

---

## 7. Code Organization - Single Responsibility

### Rule: Files Over 1000 Lines Should Be Split

**When a file grows large:**
1. Identify distinct responsibilities
2. Extract into focused classes/files
3. Keep original as coordinator if needed

### Warning Signs

- File over 1000 lines
- Multiple unrelated methods
- Hard to name the class ("Manager", "Coordinator", "Helper")
- Long scroll to find methods

### Refactoring Strategy

**DON'T:** Big-bang refactor (risky, breaks things)

**DO:** Gradual extraction during feature work
1. Extract one responsibility at a time
2. Keep tests passing at each step
3. Refactor when touching code anyway

### Example: ConversationMonitor.swift (3189 lines)

**Current responsibilities:**
- Timeline state (@Observable properties)
- Entry loading (from database)
- Cache management (LLM summaries)
- Session monitoring (file watching)
- Refresh coordination (debouncing, triggering)

**Potential split:**
```swift
// TimelineState.swift - 200 lines
@Observable
class TimelineState {
  var entries: [TimelineEntry]
  var isLoading: Bool
  // Just state, no logic
}

// TimelineLoader.swift - 300 lines
class TimelineLoader {
  func loadEntries(projectId: String) async -> [TimelineEntry]
  // Just loading logic
}

// CacheCoordinator.swift - 400 lines
class CacheCoordinator {
  func generateMissingSummaries() async
  // Just cache management
}

// ConversationMonitor.swift - 500 lines (slimmed down)
@Observable
class ConversationMonitor {
  private let state: TimelineState
  private let loader: TimelineLoader
  private let cache: CacheCoordinator

  // Coordinates the above
}
```

### When NOT to Split

**Keep together if:**
- Responsibilities are tightly coupled (can't test separately)
- Splitting creates more complexity (too much wiring)
- File is large but focused (1000 lines of related code)

### Enforcement

**Build warning for files >1500 lines** (optional):
```bash
# Pre-commit hook
for file in $(git diff --name-only --cached '*.swift'); do
  lines=$(wc -l < "$file")
  if [ $lines -gt 1500 ]; then
    echo "Warning: $file has $lines lines (consider splitting)"
  fi
done
```

---

## 8. Testing - Critical Path Coverage

### Rule: Every Critical Path MUST Have Tests

**Critical paths:**
- User authentication/authorization
- Data persistence (saves, deletes)
- Business rule enforcement (filters, validation)
- State transitions (UI state changes)

### Test Pattern: Verify Business Rules

```swift
// Test that display_in_timeline filter is applied
func testTimelineOnlyShowsVisibleEntries() throws {
  // Given
  try createEntry(projectId: "test", displayInTimeline: 1)
  try createEntry(projectId: "test", displayInTimeline: 0)

  // When
  let entries = try repository.recentEntries(projectId: "test")

  // Then
  XCTAssertEqual(entries.count, 1)
  XCTAssertTrue(entries.allSatisfy { $0.displayInTimeline == 1 })
}
```

### Test Pattern: Verify State Sync

```swift
// Test that state refreshes after database write
func testStateRefreshesAfterWrite() async throws {
  // Given
  let state = ProjectState()
  state.unreadCounts[projectId] = 5

  // When
  await state.markAsViewed(projectId)

  // Then
  XCTAssertEqual(state.unreadCounts[projectId], 0,
    "State must reflect database change")
}
```

### Test Pattern: Verify Layer Boundaries

```swift
// Architectural test
func testUILayerDoesNotAccessDatabase() throws {
  let uiFiles = glob("Contextify/Contextify/*.swift")
  for file in uiFiles {
    let content = try String(contentsOf: file)
    XCTAssertFalse(content.contains("import GRDB"))
  }
}
```

### What NOT to Test

**Skip testing:**
- Generated code (Xcode templates, SwiftGen)
- Third-party libraries
- Simple getters/setters with no logic
- UI layout details (snapshot tests are better)

### Test Coverage Goals

- **Critical paths:** 100% (business rules, data persistence)
- **Core features:** 80% (main user workflows)
- **Utilities:** 60% (helpers, extensions)
- **UI:** 40% (focus on logic, not layout)

---

## 9. Documentation - Code Comments

### Rule: Comment WHY, Not WHAT

**Good comments explain:**
- Why this approach was chosen
- Why alternative approaches don't work
- Non-obvious constraints or requirements
- Business context

**Bad comments explain:**
- What the code does (code is self-documenting)
- Restating method name
- Obsolete information

### Examples

```swift
// ❌ BAD - comments what code obviously does
// Loop through all projects
for project in projects {
  // Set the name
  project.name = newName
}

// ✅ GOOD - explains why
// We update all projects (not just active) because the name comes from
// the git remote, which is shared across all worktrees of the same repo.
for project in projects {
  project.name = newName
}

// ❌ BAD - restates function name
/// Marks the project as viewed
func markProjectViewed() { ... }

// ✅ GOOD - explains contract and side effects
/// Marks the project as viewed, resetting unread count to 0.
/// Returns fresh state immediately (no separate refresh needed).
func markProjectViewed() -> ProjectVisit { ... }

// ✅ GOOD - explains exception to normal pattern
// NOTE: Intentionally using raw SQL here instead of Repository because
// this complex join spans 3 tables with custom optimization.
let results = try db.read { db in
  try Row.fetchAll(db, sql: complexJoinSQL)
}
```

### When to Add Comments

**ALWAYS comment:**
- Violations of normal patterns (raw SQL in Orchestrator, nonisolated(unsafe))
- Business rules that aren't obvious from code
- Workarounds for system limitations
- Performance-critical code with non-obvious optimization

**NEVER comment:**
- Implementation details that code shows clearly
- Redundant information
- Outdated information (update or delete)

---

## 10. Code Review - Comprehensive Checklist

### SQL Queries
- [ ] All timeline entry queries include `display_in_timeline = 1` filter
- [ ] OR documented exception explaining why filter is skipped
- [ ] Orchestrator delegates to Repository (not raw SQL)
- [ ] OR documented why raw SQL is needed

### State Management
- [ ] Database writes followed by state refresh
- [ ] OR method returns fresh state (no separate refresh)
- [ ] No temporal coupling (order-dependent correctness)
- [ ] Tests verify state changes after database writes

### Architecture
- [ ] UI layer doesn't import GRDB
- [ ] Each layer respects boundaries (no skip levels)
- [ ] Business logic in Orchestrator, not UI
- [ ] Data access in Repository, not Orchestrator

### Concurrency
- [ ] Long-running Tasks are stored and cancellable
- [ ] Task.detached documented (why detached?)
- [ ] Task.isCancelled checked in long loops
- [ ] nonisolated(unsafe) documented (why safe?)

### Error Handling
- [ ] Repository methods throw (don't return nil on error)
- [ ] Orchestrator methods throw (propagate errors)
- [ ] ViewModels catch and set error state
- [ ] Background tasks log errors appropriately

### Code Organization
- [ ] New files under 500 lines (focused)
- [ ] Single responsibility (clear purpose)
- [ ] No god classes added

### Testing
- [ ] Critical paths have tests
- [ ] Business rules verified in tests
- [ ] State sync verified in tests
- [ ] No regressions (existing tests still pass)

### Documentation
- [ ] Comments explain WHY, not WHAT
- [ ] Pattern violations documented
- [ ] Non-obvious constraints explained

---

## Enforcement Tools

### Pre-commit Checks

```bash
#!/bin/bash
# .githooks/pre-commit

echo "Checking for common anti-patterns..."

# Check 1: SQL queries potentially missing display_in_timeline filter
echo "Checking SQL queries..."
missing_filter=$(rg "SELECT.*FROM transcript_entries" --type swift Contextify/Contextify | grep -v "display_in_timeline" || true)
if [ -n "$missing_filter" ]; then
  echo "⚠️  Warning: Found timeline entry queries possibly missing display_in_timeline filter"
  echo "$missing_filter"
  echo "Verify these queries either:"
  echo "  1. Include 'display_in_timeline = 1' filter"
  echo "  2. Have comment explaining why filter is skipped"
fi

# Check 2: UI layer importing GRDB
echo "Checking layer boundaries..."
ui_grdb=$(rg "import GRDB" --type swift Contextify/Contextify/*.swift 2>/dev/null || true)
if [ -n "$ui_grdb" ]; then
  echo "❌ Error: UI layer should not import GRDB directly"
  echo "$ui_grdb"
  exit 1
fi

# Check 3: Large files
echo "Checking file sizes..."
large_files=$(find Contextify app/Sources -name "*.swift" -exec sh -c '
  lines=$(wc -l < "$1")
  if [ $lines -gt 1500 ]; then
    echo "$1: $lines lines (consider splitting)"
  fi
' _ {} \;)
if [ -n "$large_files" ]; then
  echo "⚠️  Warning: Large files detected:"
  echo "$large_files"
fi

echo "✅ Pre-commit checks complete"
```

### CI Checks (GitHub Actions)

```yaml
# .github/workflows/code-quality.yml
name: Code Quality Checks

on: [pull_request]

jobs:
  anti-pattern-detection:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Check for SQL anti-patterns
        run: |
          # Check for timeline queries missing filter
          ./scripts/check-sql-patterns.sh
      - name: Check layer boundaries
        run: |
          # Check UI doesn't import GRDB
          ./scripts/check-layer-boundaries.sh
```

---

## Integration with CLAUDE.md

**Recommendation:** Add these sections to CLAUDE.md:

1. **"SQL Query Guidelines"** section (from Section 1)
2. **"State Management Guidelines"** section (from Section 2)
3. **"Architecture Guidelines"** section (from Section 3)
4. **"Code Review Checklist"** section (from Section 10)

Keep this document as reference for detailed rationale and examples.

---

**End of Guidelines Document**

**Status:** Ready for review and integration into CLAUDE.md
