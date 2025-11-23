# Code Smell Refactoring Roadmap

**Date:** 2025-11-23
**Purpose:** Phased plan to address discovered anti-patterns
**Total Effort:** ~90 hours over 3 months
**Success Criteria:** Health score >90%, zero P0/P1 issues

---

## Overview

This roadmap addresses 10 major anti-patterns discovered in systematic audit. Work is phased to:
1. Fix critical bugs first (P0)
2. Address fragility and tech debt (P1)
3. Improve architecture and maintainability (P2)
4. Prevent recurrence through guidelines and automation

---

## Phase 1: Critical Bug Fixes (Week 1)

**Goal:** Fix all P0 user-visible bugs
**Effort:** ~3 hours
**Success Criteria:** Zero P0 bugs, all user-facing data correct

### Tasks

#### Task 1.1: Fix Missing display_in_timeline Filters
**Files:** Repositories.swift, TranscriptOrchestrator.swift
**Effort:** 30 minutes
**Details:** See `code-smell-p0-fixes.md` Fix #1-3

**Changes:**
- [ ] Repositories.swift:363 - Add filter to byTranscript()
- [ ] Repositories.swift:373 - Add filter to search()
- [ ] TranscriptOrchestrator.swift:2091 - Add filter to getEntriesAfterCursor() (with cursor)
- [ ] TranscriptOrchestrator.swift:2102 - Add filter to getEntriesAfterCursor() (without cursor)

**Testing:**
```bash
# Manual test: search should not return hidden entries
# Verify in UI that hidden entries don't appear in timeline
```

**Commit message:**
```
fix(db): add display_in_timeline filter to entry queries

Fixes 3 queries that were incorrectly returning hidden entries:
- byTranscript() method
- search() method
- getEntriesAfterCursor() method

Impact: Prevents ~480 unnecessary LLM calls and user confusion
from hidden entries appearing in timeline.

Refs: code-smell-audit-2025-11-23.md Pattern #1
```

---

#### Task 1.2: Fix State Sync After markProjectViewed
**Files:** ProjectSwitcherState.swift, TranscriptOrchestrator.swift
**Effort:** 20 minutes
**Details:** See `code-smell-p0-fixes.md` Fix #5 (recommended)

**Changes:**
- [ ] TranscriptOrchestrator.swift:1770 - Make markProjectViewed return ProjectVisit
- [ ] ProjectSwitcherState.swift:608-619 - Use returned state to update unreadCounts

**Testing:**
```swift
func testUnreadCountsUpdateAfterViewing() async throws {
  let state = ProjectSwitcherState()
  state.unreadCounts[projectId] = 5

  await state.selectProject(projectId)

  XCTAssertEqual(state.unreadCounts[projectId], 0)
}
```

**Commit message:**
```
fix(state): refresh unread counts after viewing project

markProjectViewed now returns fresh ProjectVisit state, which is
immediately used to update @Observable unreadCounts dictionary.

Before: Unread counts stayed at old value until manual refresh
After: Counts update immediately when project is viewed

Refs: code-smell-audit-2025-11-23.md Pattern #2
```

---

#### Task 1.3: Audit All Entry Queries
**Files:** Various
**Effort:** 30 minutes
**Details:** See `code-smell-p0-fixes.md` Fix #6

**Process:**
1. Run: `rg "SELECT.*FROM transcript_entries" --type swift -n`
2. For each query, determine if display_in_timeline filter is needed
3. Add filter OR document exception

**Commit message:**
```
chore(db): audit and document all transcript_entries queries

Systematic review of 27 queries loading transcript_entries:
- 14 user-facing queries: ✅ All have display_in_timeline filter
- 13 internal queries: Documented why filter is skipped

Added comments explaining exceptions (embeddings, stats, admin).

Refs: code-smell-audit-2025-11-23.md Pattern #1
```

---

#### Task 1.4: Add Regression Tests
**Files:** ContextifyTests/
**Effort:** 1 hour
**Details:** Prevent bugs from recurring

**Tests to Add:**
```swift
// RepositoriesTests.swift
func testByTranscriptExcludesHiddenEntries()
func testSearchExcludesHiddenEntries()

// TranscriptOrchestratorTests.swift
func testGetEntriesAfterCursorExcludesHiddenEntries()
func testMarkProjectViewedReturnsUpdatedState()

// ProjectSwitcherStateTests.swift
func testUnreadCountsUpdateAfterViewing()
```

**Commit message:**
```
test(db): add regression tests for display_in_timeline filter

Prevents recurrence of bugs where hidden entries appeared in UI.
All timeline entry queries now have corresponding tests verifying
that display_in_timeline = 0 entries are excluded.

Refs: code-smell-audit-2025-11-23.md
```

---

### Phase 1 Deliverables

- [ ] All P0 bugs fixed
- [ ] Regression tests added
- [ ] User-visible bugs resolved
- [ ] Commits pushed to branch

**Validation:**
```bash
# Run tests
make test

# Manual testing checklist
- [ ] Timeline doesn't show hidden entries
- [ ] Search results don't include hidden entries
- [ ] Unread counts update immediately after viewing project
- [ ] No regressions in existing features
```

---

## Phase 2: Fragility Reduction (Month 1)

**Goal:** Address P1 high-risk fragility issues
**Effort:** ~20 hours
**Success Criteria:** Layer discipline restored, task lifecycle managed, unsafe concurrency fixed

### Tasks

#### Task 2.1: Eliminate Raw SQL in TranscriptOrchestrator
**File:** TranscriptOrchestrator.swift
**Effort:** 6 hours
**Impact:** Reduces duplication, enforces filter consistency

**Approach:**
1. Identify all raw SQL in Orchestrator (7 locations)
2. Check if equivalent Repository method exists
3. If yes: delegate to Repository
4. If no: add method to Repository, then delegate

**Example:**
```swift
// BEFORE (TranscriptOrchestrator.swift:2091)
public func getEntriesAfterCursor(projectId: String, after cursor: EntryCursor?) throws -> [TranscriptEntry] {
  try pool.read { db in
    try TranscriptEntry.fetchAll(db, sql: """
      SELECT * FROM transcript_entries WHERE ...
    """)
  }
}

// AFTER
public func getEntriesAfterCursor(projectId: String, after cursor: EntryCursor?) throws -> [TranscriptEntry] {
  try repository.entriesAfterCursor(projectId: projectId, after: cursor)
}
```

**Locations to Fix:**
- [ ] Line 2091, 2102 - getEntriesAfterCursor (delegate to Repository)
- [ ] Line 326 - Project query (delegate to ProjectRepository)
- [ ] Line 440, 473, 663 - Various queries (evaluate case-by-case)
- [ ] Line 1256, 2051, 2060 - System events (may need new Repository methods)

**Testing:** Verify no behavior change after refactor

**Commit message:**
```
refactor(arch): eliminate raw SQL from Orchestrator layer

TranscriptOrchestrator now delegates all queries to Repository layer.
No more SQL duplication - single source of truth in Repository.

Before: 7 raw SQL queries in Orchestrator
After: All queries delegated to Repository

Refs: code-smell-audit-2025-11-23.md Pattern #5
```

---

#### Task 2.2: Remove GRDB Imports from UI Layer
**Files:** 5 UI files
**Effort:** 4 hours
**Impact:** Restores layer discipline, improves testability

**Files to Fix:**
- [ ] TranscriptMetadataOrchestrator.swift
- [ ] BatchEmbeddingView.swift
- [ ] SemanticSearchView.swift
- [ ] ProjectBadgesContainer.swift
- [ ] EmbeddingDatabaseTestView.swift (lower priority - test UI)

**Process:**
1. Identify all database operations in UI file
2. Move to Orchestrator as async methods
3. Update UI to call Orchestrator instead of DB

**Example:**
```swift
// BEFORE (BatchEmbeddingView.swift)
import GRDB
struct BatchEmbeddingView: View {
  @State var db: DatabasePool

  func loadStats() {
    let count = try! db.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries")
    }
  }
}

// AFTER
struct BatchEmbeddingView: View {
  @State var orchestrator: EmbeddingOrchestrator

  func loadStats() async {
    let count = try await orchestrator.getTotalEntryCount()
  }
}

// Add to EmbeddingOrchestrator
public func getTotalEntryCount() async throws -> Int {
  try await repository.countAllEntries()
}
```

**Commit message:**
```
refactor(arch): remove GRDB imports from UI layer

All database access now goes through Orchestrator layer.
UI files no longer import GRDB or execute queries directly.

Before: 5 UI files with direct database access
After: All use Orchestrator API

Improves testability (can mock Orchestrator without DB).

Refs: code-smell-audit-2025-11-23.md Pattern #4
```

---

#### Task 2.3: Make All Tasks Cancellable
**Files:** ConversationMonitor.swift, ProjectSwitcherState.swift, SettingsView.swift
**Effort:** 6 hours
**Impact:** Prevents resource leaks, race conditions

**Approach:**
1. Find all Task.detached calls (25 total)
2. Store task reference in property
3. Cancel task when context changes
4. Check Task.isCancelled in long loops

**Example:**
```swift
// BEFORE
Task.detached {
  await longOperation()
}

// AFTER
private var backgroundTask: Task<Void, Never>?

func start() {
  backgroundTask?.cancel()  // Cancel previous
  backgroundTask = Task.detached {
    for item in items {
      if Task.isCancelled { break }
      await process(item)
    }
  }
}

func stop() {
  backgroundTask?.cancel()
  backgroundTask = nil
}
```

**Files & Lines:**
- [ ] ConversationMonitor.swift:1594 - Cursor persistence
- [ ] ConversationMonitor.swift:342, 399, 462, 527, 555 - Various tasks
- [ ] ProjectSwitcherState.swift:312, 545, 600, 608 - Project operations
- [ ] SettingsView.swift:296, 347 - Settings operations

**Commit message:**
```
fix(concurrency): make all background tasks cancellable

All Task.detached calls now store task reference and cancel
when context changes (view dismissed, project switched, etc).

Before: 25 fire-and-forget tasks (resource leaks)
After: All tasks tracked and cancelled appropriately

Refs: code-smell-audit-2025-11-23.md Pattern #6
```

---

#### Task 2.4: Fix Unsafe Concurrent Access
**Files:** HUDCore.swift, others
**Effort:** 4 hours
**Impact:** Prevents race conditions, Swift 6 safety

**Process:**
1. Audit all 22 nonisolated(unsafe) usages
2. Verify each is truly safe (immutable singleton)
3. Fix any mutable state with actor isolation
4. Document why each is safe

**Priority Cases:**
- [ ] HUDCore.swift:28 - hasWarnedLegacyDefaults (MUTABLE - needs fix)
- [ ] Others - mostly safe singletons (document)

**Example Fix:**
```swift
// BEFORE (HUDCore.swift:28)
nonisolated(unsafe) private static var hasWarnedLegacyDefaults = false

// AFTER - Use actor for mutable state
actor WarningTracker {
  private var hasWarnedLegacy = false

  func warnOnce() {
    guard !hasWarnedLegacy else { return }
    // Show warning
    hasWarnedLegacy = true
  }
}

private static let warningTracker = WarningTracker()
```

**Commit message:**
```
fix(concurrency): replace unsafe mutable state with actor isolation

Audited all 22 nonisolated(unsafe) usages:
- 21 safe (immutable singletons) - documented
- 1 unsafe (mutable flag) - fixed with actor

Refs: code-smell-audit-2025-11-23.md Pattern #7
```

---

### Phase 2 Deliverables

- [ ] Zero raw SQL in Orchestrator (all delegate to Repository)
- [ ] Zero GRDB imports in UI layer
- [ ] All background tasks cancellable
- [ ] All concurrent access safe (verified or fixed)

**Validation:**
```bash
# Verify no raw SQL in Orchestrator
rg "\.fetchAll\(db, sql:" app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift
# Should return no results

# Verify no GRDB in UI
rg "import GRDB" Contextify/Contextify/*.swift
# Should return no results

# Verify all tasks tracked
rg "Task\.detached" Contextify/Contextify --type swift -A 2
# Each should be stored in a property
```

---

## Phase 3: Architectural Improvements (Quarter 1)

**Goal:** Long-term maintainability, prevent recurrence
**Effort:** ~60 hours
**Success Criteria:** Query builder implemented, god classes split, health score >90%

### Tasks

#### Task 3.1: Implement Query Builder Pattern
**Files:** New TimelineEntryQuery.swift, update Repository
**Effort:** 8 hours
**Impact:** Makes forgetting display_in_timeline filter impossible

**Design:**
```swift
// New file: TimelineEntryQuery.swift
struct TimelineEntryQuery {
  private var filters: [SQLExpression] = [
    Column("display_in_timeline") == 1  // ALWAYS applied
  ]

  func forProject(_ id: String) -> Self { ... }
  func forTranscript(_ id: String) -> Self { ... }
  func afterTimestamp(_ ts: Int) -> Self { ... }
  func matching(_ content: String) -> Self { ... }

  func fetchAll(_ db: Database) throws -> [TranscriptEntry] {
    let combined = filters.joined(operator: .and)
    return try TranscriptEntry.filter(combined).fetchAll(db)
  }
}

// Usage
let entries = try TimelineEntryQuery()
  .forProject(projectId)
  .afterTimestamp(since)
  .fetchAll(db)
```

**Migration:**
1. Create TimelineEntryQuery builder
2. Add tests verifying filter always applied
3. Migrate one Repository method at a time
4. Verify behavior unchanged after each migration

**Commit message:**
```
feat(db): add TimelineEntryQuery builder pattern

Composable query builder that ALWAYS applies display_in_timeline
filter. Makes it impossible to forget this critical business rule.

All timeline entry queries now use builder instead of manual
filter construction.

Refs: code-smell-audit-2025-11-23.md Pattern #1
```

---

#### Task 3.2: Split ConversationMonitor (3189 lines)
**Files:** Extract TimelineState, TimelineLoader, CacheCoordinator
**Effort:** 16 hours
**Impact:** Improved maintainability, clearer responsibilities

**Plan:**
```
ConversationMonitor (3189 lines) →
  - TimelineState.swift (200 lines) - @Observable properties only
  - TimelineLoader.swift (400 lines) - Load entries from DB
  - CacheCoordinator.swift (500 lines) - LLM summary coordination
  - SessionMonitor.swift (300 lines) - File watching
  - RefreshCoordinator.swift (400 lines) - Debouncing, triggers
  - ConversationMonitor.swift (800 lines) - Coordinates above
```

**Approach (Gradual):**
1. **Week 1:** Extract TimelineState (just observable properties)
2. **Week 2:** Extract TimelineLoader (loading logic)
3. **Week 3:** Extract CacheCoordinator (cache management)
4. **Week 4:** Extract SessionMonitor, RefreshCoordinator
5. **Week 5:** Slim down ConversationMonitor to coordinator

**Testing:** Comprehensive tests after each extraction

**Commit series:**
```
refactor(timeline): extract TimelineState from ConversationMonitor
refactor(timeline): extract TimelineLoader from ConversationMonitor
refactor(timeline): extract CacheCoordinator from ConversationMonitor
refactor(timeline): extract SessionMonitor from ConversationMonitor
refactor(timeline): extract RefreshCoordinator from ConversationMonitor
refactor(timeline): slim ConversationMonitor to coordinator role
```

---

#### Task 3.3: Split TranscriptOrchestrator (2134 lines)
**Files:** Extract TranscriptParser, ValidationService, CoordinationOrchestrator
**Effort:** 12 hours
**Impact:** Clearer responsibilities, easier to maintain

**Plan:**
```
TranscriptOrchestrator (2134 lines) →
  - TranscriptParser.swift (300 lines) - Parse JSONL to models
  - ValidationService.swift (200 lines) - Validate entries, transcripts
  - ProjectCoordinator.swift (400 lines) - Project operations
  - EntryCoordinator.swift (400 lines) - Entry operations
  - TranscriptOrchestrator.swift (600 lines) - High-level coordination
```

**Approach:** Similar gradual extraction as ConversationMonitor

---

#### Task 3.4: Standardize Error Handling
**Files:** Various
**Effort:** 6 hours
**Impact:** Consistent UX, predictable patterns

**Strategy:**
- Repository: Always throws
- Orchestrator: Always throws
- ViewModel: Catch and expose error state
- Background: Log and continue

**Process:**
1. Document error handling strategy (done - in guidelines)
2. Audit existing code for violations
3. Fix inconsistencies layer by layer

---

#### Task 3.5: Add Architectural Tests
**Files:** ContextifyTests/ArchitectureTests.swift
**Effort:** 4 hours
**Impact:** Prevents regression of layer violations

**Tests:**
```swift
class ArchitectureTests: XCTestCase {
  func testUILayerDoesNotImportGRDB() {
    let uiFiles = glob("Contextify/Contextify/*.swift")
    for file in uiFiles {
      let content = try! String(contentsOf: file)
      XCTAssertFalse(content.contains("import GRDB"))
    }
  }

  func testOrchestratorDoesNotContainRawSQL() {
    let orch = "app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift"
    let content = try! String(contentsOf: URL(fileURLWithPath: orch))
    let rawSQLCount = content.matches(of: /\.fetchAll\(db, sql:/).count
    XCTAssertEqual(rawSQLCount, 0, "Orchestrator should delegate to Repository")
  }

  func testAllTimelineQueriesHaveFilter() {
    // Parse Swift files, check all timeline queries include display_in_timeline
  }
}
```

---

#### Task 3.6: Update CLAUDE.md with Guidelines
**Files:** CLAUDE.md
**Effort:** 2 hours
**Impact:** Prevents recurrence in future development

**Integration:**
1. Add "SQL Query Guidelines" section
2. Add "State Management Guidelines" section
3. Add "Architecture Guidelines" section
4. Add "Code Review Checklist" section

Use content from `claude-md-guidelines-code-quality.md`

---

#### Task 3.7: Add Pre-commit Hooks
**Files:** .githooks/pre-commit
**Effort:** 4 hours
**Impact:** Catch violations before commit

**Checks:**
- SQL queries missing display_in_timeline filter
- UI files importing GRDB
- Files over 1500 lines
- nonisolated(unsafe) without comment

---

### Phase 3 Deliverables

- [ ] Query builder pattern implemented and in use
- [ ] ConversationMonitor split into 5-6 focused classes
- [ ] TranscriptOrchestrator split into 4-5 focused classes
- [ ] Error handling standardized by layer
- [ ] Architectural tests prevent regressions
- [ ] CLAUDE.md updated with guidelines
- [ ] Pre-commit hooks catch violations

**Validation:**
```bash
# Health metrics
# SQL consistency: 100% (query builder enforces)
# State sync: 100% (pattern established)
# Layer discipline: 100% (architectural tests)
# File size: No files >1500 lines
# Overall health score: >90%
```

---

## Phase 4: Prevention & Monitoring (Ongoing)

**Goal:** Ensure issues don't recur
**Effort:** Ongoing
**Success Criteria:** Zero new P0/P1 issues for 1 month

### Tasks

#### Task 4.1: Enforce Guidelines in Code Review
**Process:** Use checklist from guidelines

**Every PR:**
- [ ] SQL queries have display_in_timeline filter (or documented exception)
- [ ] Database writes refresh state (or return fresh state)
- [ ] Layers respected (UI → State → Orchestrator → Repository → DB)
- [ ] Tasks are cancellable
- [ ] Concurrent access is safe
- [ ] Tests added for new features

---

#### Task 4.2: Monitor Health Metrics
**Frequency:** Weekly
**Dashboard:** Track trends

**Metrics:**
- SQL query consistency (% with required filters)
- State sync discipline (% writes with refresh)
- Layer boundary violations (count)
- Average file size (lines)
- Test coverage (critical paths)

**Alert on:**
- New files >1000 lines
- New layer violations
- Test coverage drops

---

#### Task 4.3: Periodic Audits
**Frequency:** Quarterly
**Process:** Re-run audit methodology

**Check for:**
- New anti-patterns emerging
- Drift from guidelines
- Effectiveness of prevention measures

---

## Success Metrics

### Phase 1 Success (Week 1)
- ✅ Zero P0 bugs remaining
- ✅ All user-facing data correct
- ✅ Regression tests prevent recurrence

### Phase 2 Success (Month 1)
- ✅ Zero raw SQL in Orchestrator
- ✅ Zero GRDB imports in UI
- ✅ All tasks cancellable
- ✅ Unsafe concurrency eliminated

### Phase 3 Success (Quarter 1)
- ✅ Query builder in use (filter enforcement automatic)
- ✅ No files >1500 lines
- ✅ Architectural tests passing
- ✅ Guidelines documented in CLAUDE.md
- ✅ Health score >90%

### Phase 4 Success (Ongoing)
- ✅ Zero new P0/P1 issues for 1 month
- ✅ Code review checklist consistently used
- ✅ Metrics dashboard shows improving trends

---

## Effort Summary

| Phase | Duration | Effort | P0/P1 Fixed |
|-------|----------|--------|-------------|
| Phase 1: Critical Bugs | Week 1 | 3 hours | 3 P0 bugs |
| Phase 2: Fragility | Month 1 | 20 hours | 4 P1 issues |
| Phase 3: Architecture | Quarter 1 | 60 hours | Long-term health |
| Phase 4: Prevention | Ongoing | N/A | Zero new issues |
| **Total** | **3 months** | **~83 hours** | **All issues** |

**Resource allocation:**
- Week 1: 3 hours (critical priority)
- Weeks 2-4: 5 hours/week (20 hours total)
- Months 2-3: 10 hours/week (60 hours total)

---

## Risk Mitigation

### Risk: Refactoring Breaks Features
**Mitigation:**
- Comprehensive tests before refactor
- Gradual extraction (one class at a time)
- Keep tests passing at every step
- Manual QA after each phase

### Risk: New Issues While Fixing Old
**Mitigation:**
- Apply guidelines immediately (don't wait for Phase 3)
- Use code review checklist on all PRs
- Enforce layer discipline from Week 1

### Risk: Effort Exceeds Estimates
**Mitigation:**
- Prioritize P0/P1 (critical first)
- P2 can be deferred if needed
- Gradual refactor allows pausing between phases

---

## Next Actions

**Immediate (Today):**
1. Review this roadmap with team
2. Schedule Week 1 for P0 fixes
3. Assign Phase 1 tasks

**This Week:**
1. Execute Phase 1 (3 hours)
2. Validate fixes with tests
3. Push to branch and create PR

**This Month:**
1. Execute Phase 2 (20 hours, ~5 hours/week)
2. Track progress in this document
3. Update health metrics weekly

**This Quarter:**
1. Execute Phase 3 (60 hours, ~10 hours/week)
2. Document lessons learned
3. Refine prevention guidelines

---

**End of Refactoring Roadmap**

**Status:** Ready for execution
**Next Review:** After Phase 1 complete (reassess timeline, adjust if needed)
