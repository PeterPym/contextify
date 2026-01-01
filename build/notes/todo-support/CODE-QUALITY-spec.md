---
todo_id: P1-CODE-QUALITY
title: Code Quality Improvements (Post-Audit)
type: spec
date: 2025-11-23
status: active
description: Implementation plan for code quality improvements based on Nov 2025 audit
---

# Code Quality Improvements Specification

**Based on:** Consolidated code smell analysis (Nov 2025)
**Status:** P0 bugs fixed (commit ad190448), prevention work remains
**Effort:** 29 hours total (vs original 83h estimate)

---

## Context

Three parallel investigations (audit-code-smells, sql-duplication, observable-state-sync) identified issues in the codebase. After principal engineer review and re-audit:

- ✅ **P0 bugs FIXED** (commit `ad190448` - display_in_timeline filters)
- ⚠️ **Prevention work needed** (tests, patterns, guidelines)
- 📊 **Health score:** 75% current → 90%+ target

**Key insight:** Focus on PREVENTION (tests, patterns) not heavy refactoring.

---

## Phase 1B: Regression Tests (2h)

**Goal:** Prevent recurrence of fixed filter bugs

### Tasks

1. **Test byTranscript() filter** (30 min)
   ```swift
   func testByTranscriptExcludesHiddenEntries() throws {
     // Given: mix of visible and hidden entries
     try createEntry(transcriptId: "test", displayInTimeline: 1)
     try createEntry(transcriptId: "test", displayInTimeline: 0)

     // When
     let entries = try repository.byTranscript("test")

     // Then
     XCTAssertTrue(entries.allSatisfy { $0.displayInTimeline == 1 })
   }
   ```

2. **Test search() filter** (30 min)
   - Similar pattern for search method
   - Verify hidden entries excluded from search results

3. **Test getEntriesAfterCursor() filter** (1h)
   - Test both branches (with cursor, without cursor)
   - Verify incremental updates exclude hidden entries

**Location:** `ContextifyTests/RepositoriesTests.swift`

**Success criteria:** Tests fail if filters are removed

---

## Phase 2: Verify & Fix Remaining Issues (15h)

### 2.1 Verification Audit (2h)

**Run automated checks against current main:**

```bash
# SQL duplication check
rg "getEntriesAfterCursor" --type swift app/Sources/ContextifyCore/Database/

# Layer violations check
rg "import GRDB" --type swift Contextify/Contextify/

# Detached tasks check
rg "Task\.detached" --type swift Contextify/Contextify/ app/Sources/ContextifyCore/

# Unsafe concurrency check
rg "nonisolated\(unsafe\)" --type swift
```

**Output:** List of verified issues still present

### 2.2 Fix Verified Issues (13h, contingent on audit)

**If SQL duplication confirmed (6h):**
- Orchestrator should delegate to Repository
- Remove duplicate getEntriesAfterCursor implementation
- Use Repository.entriesAfterCursor() instead

**If layer violations found (4h):**
- Remove GRDB imports from UI files
- Move queries to Orchestrator layer
- Update UI to call Orchestrator methods

**If detached tasks confirmed (3h):**
- Store task references in properties
- Cancel on deinit or context change
- Focus on high-traffic paths (ConversationMonitor, ProjectSwitcherState)

**Defer:** Unsafe concurrency audit (most are safe singletons)

---

## Phase 3: Prevention (12h)

### 3.1 Architectural Tests with SwiftSyntax (4h)

**Goal:** Enforce layer boundaries (UI → Orchestrator → Repository → DB)

**Implementation:**

```swift
import XCTest
import SwiftSyntax
import SwiftParser

class ArchitecturalTests: XCTestCase {
  func testUILayerDoesNotImportGRDB() throws {
    let uiFiles = try FileManager.default
      .contentsOfDirectory(at: uiDirectory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "swift" }

    for file in uiFiles {
      let source = try String(contentsOf: file)
      let tree = Parser.parse(source: source)

      let visitor = ImportVisitor()
      visitor.walk(tree)

      let grdbImports = visitor.imports.filter { $0.contains("GRDB") }

      XCTAssertTrue(
        grdbImports.isEmpty,
        """
        \(file.lastPathComponent) should not import GRDB directly.
        Use TranscriptOrchestrator instead.
        Found: \(grdbImports.joined(separator: ", "))
        """
      )
    }
  }
}

class ImportVisitor: SyntaxVisitor {
  var imports: [String] = []

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    imports.append(node.path.description)
    return .visitChildren
  }
}
```

**Location:** New test target or `ContextifyTests/ArchitecturalTests.swift`

**Integration:** Add to pre-commit hook

**Success criteria:** Test catches violations before they reach main

---

### 3.2 State Sync Observability (2h)

**Goal:** Validate hybrid state sync pattern working as intended

**Implementation:**

```swift
// In methods that write to DB
func markProjectViewed(projectId: String, timestamp: String) throws {
  logger.debug("DB WRITE: markProjectViewed(projectId: \(projectId, privacy: .public))")

  try dbManager.pool.write { db in
    try projectVisitsRepository.markViewed(db: db, projectId: projectId, timestamp: timestamp)
  }

  // Log if no state refresh follows
  logger.debug("DB WRITE COMPLETE: markProjectViewed - no immediate refresh (optimistic pattern)")
}

// In methods that refresh state
func refreshUnreadCounts(for projectIds: [String]) async {
  logger.debug("STATE REFRESH: refreshUnreadCounts(count: \(projectIds.count))")
  // ... existing code ...
  logger.debug("STATE REFRESH COMPLETE: \(projectIds.count) projects updated")
}
```

**Validation:** Review logs to confirm pattern adherence

**Success criteria:** Clear log trail showing writes + refreshes (or lack thereof by design)

---

### 3.3 Query Builder Pilot (3h)

**Goal:** Evaluate extension method approach for preventing filter bugs

**Implementation:**

```swift
extension TranscriptEntry {
  /// Returns a query that filters to visible timeline entries only
  static func visible() -> QueryInterfaceRequest<TranscriptEntry> {
    filter(Column("display_in_timeline") == 1)
  }

  /// Returns visible entries for a specific project
  static func forProject(_ id: String) -> QueryInterfaceRequest<TranscriptEntry> {
    visible().filter(Column("project_id") == id)
  }

  /// Returns visible entries for a specific transcript
  static func forTranscript(_ id: String) -> QueryInterfaceRequest<TranscriptEntry> {
    visible().filter(Column("transcript_id") == id)
  }
}

// Usage example (migrate 3-5 callsites)
let entries = try TranscriptEntry.forProject(projectId).fetchAll(db)
```

**Pilot callsites:**
1. `Repositories.swift` - `recentByProject()` (line ~358)
2. `Repositories.swift` - `recentFeed()` (line ~401, may need custom approach for joins)
3. `ConversationMonitor.swift` - timeline loading

**Evaluation criteria:**
- Is it more readable than manual filters?
- Does it reduce cognitive load?
- Should we migrate all 27 callsites or keep current approach?

**Deliverable:** Short note (200 words) recommending full migration or status quo

---

### 3.4 Document Patterns in CLAUDE.md (1h)

**Add to CLAUDE.md:**

#### SQL Query Patterns

**Rule:** All timeline entry queries MUST filter `display_in_timeline = 1`

**Exceptions:** Embedding generation, stats, admin tools (document why)

**Enforcement:**
```bash
# Before committing entry queries
rg "SELECT.*FROM transcript_entries" --type swift | grep -v "display_in_timeline"
# Should return only documented exceptions
```

#### State Sync Pattern - Hybrid Model

**User-initiated, visible changes:**
- Optimistic UI update (immediate feedback)
- Background DB write
- Reconciliation on next natural refresh point

**Background/invisible changes:**
- DB is source of truth
- UI refreshes on next relevant view load

**Rule:** Missing refresh is a bug ONLY when there's no optimistic update AND no natural reconciliation.

**Example (correct):**
```swift
// Optimistic update
unreadCounts[projectId] = 0  // Immediate

// Background write
Task.detached {
  try orchestrator.markProjectViewed(projectId: projectId, timestamp: now)
  // No explicit refresh needed - optimistic update already applied
}
```

#### Layer Discipline

**Rule:** UI → ViewModel → Orchestrator → Repository → Database

**Never skip layers.** UI files must not import GRDB.

**Enforcement:** Architectural tests (see ArchitecturalTests.swift)

---

### 3.5 Testability Improvements (2h)

**Goal:** Make ConversationMonitor easier to test without heavy refactoring

**Approach:**

```swift
// Extract protocol for time dependency
protocol TimeProvider {
  func now() -> Date
}

struct SystemTimeProvider: TimeProvider {
  func now() -> Date { Date() }
}

// In ConversationMonitor
@Observable
class ConversationMonitor {
  let timeProvider: TimeProvider

  init(orchestrator: TranscriptOrchestrator,
       timeProvider: TimeProvider = SystemTimeProvider()) {
    self.timeProvider = timeProvider
    // ...
  }
}

// In tests
class MockTimeProvider: TimeProvider {
  var currentTime = Date()
  func now() -> Date { currentTime }
}
```

**Focus areas:**
- Time dependencies (for timeline ordering tests)
- Database dependencies (for testing without real DB)
- File system dependencies (for testing monitoring)

**Success criteria:** Can test key timeline operations in isolation

---

## Deferred Items

### God Class Refactoring (40-60h)
**Why deferred:** Medium priority, realistic effort is 3-4x original estimate

**Alternative:** Testability improvements (above)

**Condition to revisit:** If dependency diagram shows clean boundaries

### Reactive State Management
**Why deferred:** Too risky for pre-production

**Alternative:** Hybrid pattern working well

**Condition to revisit:** If state sync bugs persist after observability

---

## Success Metrics

**Current (after commit ad190448):**
- SQL query consistency: 100%
- State sync discipline: 75%
- Layer discipline: 88%
- Health score: 75%

**Target (after this work):**
- SQL query consistency: 100% (maintained with tests)
- State sync discipline: 90%
- Layer discipline: 100%
- Health score: >90%

**Gap:** 15% improvement needed, 29 hours effort

---

## Timeline

**Week 1 (5h):**
- Regression tests (2h)
- Verification audit (2h)
- Document state sync pattern (1h)

**Month 1 (15h total):**
- Fix verified issues (13h, contingent)
- Architectural tests (4h)
- State sync observability (2h)

**Quarter 1 (29h total):**
- Query builder pilot (3h)
- Update CLAUDE.md (1h)
- Testability improvements (2h)
- Additional tests as needed (4h)

---

## References

**Source Analysis:**
- `build/notes/research/code-smells/CONSOLIDATED-CODE-SMELL-ANALYSIS.md`
- `build/notes/research/code-smells/sql-duplication-audit.md`
- `build/notes/research/code-smells/observable-state-sync-audit.md`

**Review:**
- Principal engineer review v2 (completed 2025-11-23)
- Owner Q&A answered (hybrid model, SwiftSyntax preference)

**Related Commits:**
- `ad190448` - Fixed display_in_timeline filters (P0 bugs)
- `283be03` - Added tokens to bridging lexicon (validation)

**Related TODOs:**
- Existing `#P1-QUERY-CENTRALIZE` in TODOS.md (aligns with this work)

---

**Status:** Ready to implement - start with Phase 1B regression tests
