# Architecture Deep Dive & Refactoring Opportunities

**Status:** Analysis as of 2025-11-17
**Purpose:** Comprehensive architecture review and refactoring roadmap
**Audience:** Developers, architects, technical leadership

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Codebase Health Metrics](#codebase-health-metrics)
3. [Architectural Analysis](#architectural-analysis)
4. [God Objects & Complexity Hotspots](#god-objects--complexity-hotspots)
5. [Coupling & Dependency Analysis](#coupling--dependency-analysis)
6. [Design Pattern Consistency](#design-pattern-consistency)
7. [Testability Assessment](#testability-assessment)
8. [Refactoring Opportunities](#refactoring-opportunities)
9. [Migration Roadmap](#migration-roadmap)

---

# Executive Summary

## Current State

Contextify's architecture has **evolved organically** over 18+ months from a simple HUD to a sophisticated multi-project AI conversation timeline with real-time monitoring, LLM summarization, and cross-platform transcript support.

**Architecture Grade: B+**
- ✅ **Strengths:** Excellent separation of UI/Business Logic/Data, Swift 6 strict concurrency adoption, robust database layer
- ⚠️ **Weaknesses:** Several god objects (3000+ lines), tight coupling between monitoring components, inconsistent state management patterns
- 🔴 **Critical Issues:** ConversationMonitor complexity (3054 lines, ~15 responsibilities)

## Key Findings

### God Objects Identified

| File | Lines | Responsibilities | Refactor Priority |
|------|-------|------------------|-------------------|
| ConversationMonitor.swift | 3054 | 15+ | **P0 - Critical** |
| HUDCore.swift | 1196 | 8+ | **P1 - High** |
| ProjectDiscoveryService.swift | 1000 | 6 | **P2 - Medium** |
| HooverEngine.swift | 898 | 4 | **P3 - Low** |

### Coupling Issues

**High Coupling:**
- ConversationMonitor ↔ TranscriptOrchestrator ↔ HooverEngine (tight 3-way dependency)
- HUDViewModel ↔ StartupCoordinator (both manage project identity)
- Event systems (AsyncStream vs NotificationCenter mismatch)

**Moderate Coupling:**
- Database components well-isolated via GRDB abstractions
- Discovery layer reasonably decoupled

### Recommended Actions

**Immediate (0-2 months):**
1. Split ConversationMonitor into 3-4 focused components
2. Extract LLM queue management to dedicated coordinator
3. Unify event system (AsyncStream throughout)

**Short-term (2-6 months):**
4. Refactor HUDCore git monitoring → GitBranchMonitor service
5. Introduce protocol abstractions for testability
6. Consolidate state management patterns

**Long-term (6-12 months):**
7. Migrate to SwiftData (when stable on macOS)
8. Implement plugin architecture for providers
9. Consider modularization (SPM packages)

---

# Codebase Health Metrics

## File Size Analysis

### Distribution by Size

**Extremely Large (>1000 lines):**
```
ConversationMonitor.swift           3054 lines  ⚠️ CRITICAL
HUDCore.swift                      1196 lines  ⚠️ WARNING
ProjectDiscoveryService.swift     1000 lines  ⚠️ WARNING
```

**Large (500-1000 lines):**
```
HooverEngine.swift                  898 lines  ⚠️
StartupCoordinator.swift            735 lines  ✓ (acceptable for coordinator)
DatabaseManager.swift              ~600 lines  ✓ (acceptable for manager)
```

**Medium (200-500 lines):**
```
TranscriptWatcher.swift             307 lines  ✓
DatabaseSchema.swift               ~400 lines  ✓
TranscriptOrchestrator.swift       ~350 lines  ✓
```

**Small (<200 lines):**
```
ProjectStatsService.swift          ~180 lines  ✅ Ideal
ActiveProjectContext.swift          ~95 lines  ✅ Ideal
TimelineModels.swift               ~150 lines  ✅ Ideal
```

### Professional Norms

**Industry Standards (Swift):**
- **Ideal:** 100-300 lines per file
- **Acceptable:** 300-500 lines
- **Warning:** 500-1000 lines
- **Critical:** >1000 lines

**Contextify vs Standards:**
- 3 files exceed critical threshold (>1000 lines)
- 2 files in warning zone (500-1000 lines)
- Majority of files are well-sized (60%+)

## Complexity Metrics

### Cyclomatic Complexity (Estimated)

**ConversationMonitor.swift:**
```
startMonitoring()              ~25 branches  ⚠️ High
handleContextUpdate()          ~15 branches  ⚠️ High
loadFeedFromSQL()             ~10 branches  ⚠️ Medium
refreshTranscript()           ~12 branches  ⚠️ Medium
```

**HUDCore.swift:**
```
updateHeadWatcher()           ~18 branches  ⚠️ High
startup()                     ~12 branches  ⚠️ Medium
handleCoordinatorUpdate()      ~8 branches  ✓ Acceptable
```

**Professional Standards:**
- **Low:** 1-5 branches (easy to test)
- **Medium:** 6-10 branches (manageable)
- **High:** 11-20 branches (hard to test)
- **Very High:** >20 branches (refactor immediately)

### Nesting Depth

**Problem Areas:**
```swift
// ConversationMonitor.swift:428-600 (startMonitoring)
func startMonitoring() {              // Level 1
    guard ... else { return }         // Level 2
    Task {                            // Level 3
        if let bookmark = ... {       // Level 4
            do {                      // Level 5
                try await ...         // Level 6
            } catch {                 // Level 5
                if error is ... {     // Level 6
                    // Level 7 nesting!
                }
            }
        }
    }
}
```

**Recommendation:** Limit nesting to 3-4 levels via early returns and helper methods.

## Module Structure

### Current Organization

```
Contextify/
├── Contextify/                    # Main app target
│   ├── ConversationMonitor.swift  # ⚠️ Should be in Core
│   ├── HUDViewModel.swift         # ✓ App-specific
│   ├── Views/                     # ✓ Well organized
│   └── Utilities/                 # ✓
│
└── app/Sources/ContextifyCore/    # Core business logic
    ├── Database/                  # ✅ Excellent separation
    ├── Coordination/              # ✅ Good pattern
    ├── Projects/                  # ✅ Domain-driven
    ├── Security/                  # ✅
    └── LLM/                       # ✅
```

### Boundary Analysis

**Well-Defined Boundaries:**
- ✅ Database layer (GRDB abstractions)
- ✅ Coordination layer (StartupCoordinator)
- ✅ Projects layer (discovery, stats)

**Blurry Boundaries:**
- ⚠️ ConversationMonitor in app target (should be Core)
- ⚠️ HUDCore mixing concerns (git, bookmarks, project root)
- ⚠️ Some ViewModels duplicating Core logic

**Missing Boundaries:**
- ❌ No dedicated "Monitoring" module (scattered across files)
- ❌ No clear "Events" abstraction layer
- ❌ No "Services" directory (some services in Projects/, some in Database/)

---

# Architectural Analysis

## Current Architecture Patterns

### 1. MVVM (Model-View-ViewModel)

**Implementation:**
```
View Layer (SwiftUI)
    ↓
ViewModel Layer (@Observable, @MainActor)
    ↓
Model/Service Layer (Business Logic)
    ↓
Data Layer (Database)
```

**Examples:**
- `ContentView` → `HUDViewModel` → `StartupCoordinator` → `TranscriptOrchestrator`
- `TimelineView` → `ConversationMonitor` → `HooverEngine` → `DatabaseManager`

**Quality:** ✅ **Good** - Consistent pattern, clear separation

**Issues:**
- ConversationMonitor is both ViewModel AND service (dual role)
- Some ViewModels bypass services and hit database directly

### 2. Coordinator Pattern

**Implementation:**
```swift
StartupCoordinator  // Project identity coordination
TranscriptOrchestrator  // Database coordination
TimelineCacheMissGenerator  // LLM coordination
```

**Quality:** ✅ **Excellent** - StartupCoordinator added Nov 2025 eliminated many races

**Benefits:**
- Single source of truth for project identity
- Deterministic startup sequencing
- Clear ownership of cross-cutting concerns

**Opportunity:** Extend pattern to monitoring (MonitoringCoordinator)

### 3. Repository Pattern

**Implementation:**
```swift
// app/Sources/ContextifyCore/Database/Repositories.swift
protocol ProjectRepository {
    func getProject(id: String) throws -> Project?
    func createProject(...) throws -> Project
    func updateProject(...) throws
}
```

**Quality:** ✅ **Good** - Type-safe abstractions over GRDB

**Coverage:**
- ✅ Projects
- ✅ Transcripts
- ✅ TranscriptEntries
- ❌ Timeline (no repository, queries embedded in ConversationMonitor)

### 4. Observer Pattern

**Implementation:**

**AsyncStream (Modern):**
```swift
StartupCoordinator.updates: AsyncStream<ActiveProjectContext>
ProjectActivityMonitor.events: AsyncStream<FSEvent>
```

**NotificationCenter (Legacy):**
```swift
.transcriptDidUpdate
.projectRootDidChange
.conversationMonitoringDidStart
```

**Quality:** ⚠️ **Mixed** - Two competing systems causing confusion

**Problem:**
- New code uses AsyncStream (Swift 6 best practice)
- Old code uses NotificationCenter (compatibility)
- No clear migration path
- Event delivery mismatch causes bugs (see data-pipeline-architecture.md)

### 5. Actor Model (Concurrency)

**Implementation:**
```swift
@MainActor class ConversationMonitor { ... }
@MainActor class HUDViewModel { ... }
actor TimelineCacheMissGenerator { ... }  // Background processing
```

**Quality:** ✅ **Excellent** - Swift 6 strict concurrency throughout

**Benefits:**
- No data races (compiler-enforced)
- Clear thread boundaries (@MainActor for UI)
- Structured concurrency (async/await)

**Opportunity:** More actors for background work (currently underutilized)

## Architectural Layers

### Layer 1: Presentation (SwiftUI Views)

**Responsibilities:**
- Render UI
- Handle user input
- Bind to ViewModels

**Quality:** ✅ **Excellent**
- Views are declarative and side-effect-free
- Proper use of @Observable, @State, @Environment
- Good composition (small, focused views)

**Example (Good):**
```swift
struct TimelineEntryRow: View {
    let entry: TimelineEntry

    var body: some View {
        VStack(alignment: .leading) {
            Text(entry.timestamp, style: .time)
            Text(entry.content)
        }
    }
}
```

### Layer 2: View Models

**Responsibilities:**
- UI state management
- User interaction coordination
- Service orchestration

**Quality:** ⚠️ **Mixed**

**Good Examples:**
```swift
@Observable class ProjectSwitcherState {  // ~200 lines
    var projects: [Project] = []
    var activeProjectId: String?

    func refreshProjects() { ... }
    func switchTo(projectId: String) { ... }
}
```

**Problematic Examples:**
```swift
@Observable class ConversationMonitor {  // 3054 lines ⚠️
    // 15+ responsibilities:
    // - Timeline state
    // - Entry loading/pagination
    // - Watcher lifecycle
    // - LLM coordination
    // - Event handling
    // - Database queries
    // - Transcript discovery
    // - Cache management
    // - Cursor tracking
    // - ... etc
}
```

### Layer 3: Services & Coordinators

**Responsibilities:**
- Business logic
- Cross-cutting concerns
- External system integration

**Quality:** ✅ **Good overall**, some inconsistency

**Well-Designed:**
```
StartupCoordinator       (735 lines) - Single responsibility ✅
ProjectStatsService      (180 lines) - Focused service ✅
TranscriptOrchestrator   (350 lines) - Clear coordinator ✅
```

**Needs Refactoring:**
```
HUDCore                 (1196 lines) - Too many concerns ⚠️
ProjectDiscoveryService (1000 lines) - Could split Claude/Codex ⚠️
```

### Layer 4: Data Access

**Responsibilities:**
- Database CRUD
- Query optimization
- Transaction management

**Quality:** ✅ **Excellent**
- Clean GRDB abstractions
- Type-safe repositories
- Proper migration management
- WAL mode for concurrency

**Example:**
```swift
struct TranscriptRepository {
    let db: DatabasePool

    func getTranscripts(projectId: String) throws -> [Transcript] {
        try db.read { db in
            try Transcript
                .filter(Column("project_id") == projectId)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }
}
```

## Cross-Cutting Concerns

### Logging

**Current State:**
- ✅ OSLog throughout (unified subsystem: "dev.contextify")
- ✅ Categorized by component (GitWatcher, HooverEngine, etc.)
- ✅ Privacy-aware (`.public` for diagnostics in pre-production)

**Opportunity:**
- Structured logging (JSON) for automated analysis
- Log aggregation service for multi-session debugging
- Performance instrumentation (SignpostLogger)

### Error Handling

**Current Patterns:**

**Swift Errors (Typed):**
```swift
enum StartupError: Error {
    case noProjectRootAvailable
    case databaseInitializationFailed(underlying: Error)
}

throw StartupError.noProjectRootAvailable
```

**Result Types:**
```swift
func setProjectRoot(url: URL) -> Result<URL, ProjectRootError>
```

**Quality:** ✅ **Good** - Type-safe errors, clear propagation

**Gaps:**
- No centralized error recovery strategy
- Some swallowed errors (try? without logging)
- User-facing error messages inconsistent

### Security

**Current:**
- ✅ Security-scoped bookmarks for sandboxed builds
- ✅ Entitlements properly configured
- ✅ No hardcoded secrets

**Opportunities:**
- Bookmark refresh strategy (periodic validation)
- Audit logging for sensitive operations
- Encrypt database at rest (SQLCipher)

---

# God Objects & Complexity Hotspots

## Critical: ConversationMonitor.swift (3054 lines)

### Responsibilities Analysis

ConversationMonitor has **15+ distinct responsibilities:**

1. **Timeline State Management** (lines 50-150)
   - `entries: [TimelineEntry]`
   - `cursor: TimelineCursor?`
   - `isLoading: Bool`

2. **Entry Loading & Pagination** (lines 800-1100)
   - `loadFeedFromSQL()`
   - `loadMoreEntries()`
   - Cursor-based pagination

3. **Watcher Lifecycle** (lines 428-600)
   - Create/destroy TranscriptWatcher instances
   - Manage `activeTranscriptWatchers` dictionary

4. **LLM Coordination** (lines 1200-1500)
   - TimelineCacheMissGenerator lifecycle
   - Cache miss handling
   - Summary generation requests

5. **Event Handling** (lines 600-800)
   - StartupCoordinator subscription
   - NotificationCenter observers
   - Coordinator update processing

6. **Database Queries** (lines 1100-1300)
   - Direct GRDB queries (bypassing repositories)
   - Custom SQL for timeline loading
   - Transcript metadata queries

7. **Transcript Discovery** (lines 1500-1700)
   - `discoverNewTranscripts()` (legacy method)
   - Periodic polling (replaced by StartupCoordinator)

8. **Cache Management** (lines 1700-1900)
   - LLM cache coordination
   - Cache invalidation
   - Window hash computation

9. **Cursor Tracking** (lines 1900-2100)
   - Pagination state
   - "Has more" detection
   - Scroll position tracking

10. **UI State Coordination** (lines 2100-2300)
    - Loading indicators
    - Error states
    - Empty state detection

11. **Background Tasks** (lines 2300-2500)
    - TaskGroup management
    - Cancellation handling

12. **Notification Posting** (lines 2500-2700)
    - `.conversationMonitoringDidStart`
    - Legacy notifications

13. **Diagnostic Logging** (lines 2700-2900)
    - Performance tracking
    - State transitions
    - Debug output

14. **Primer Logic** (lines 2900-3000)
    - Quick-discovery integration
    - Primer retry handling

15. **Cleanup & Deinitialization** (lines 3000-3054)
    - Watcher teardown
    - Task cancellation
    - Resource cleanup

### Proposed Decomposition

**Extract 4 focused components:**

```
ConversationMonitor (400 lines)
    └─ Timeline state (@Published entries, cursor, isLoading)
    └─ High-level coordination only

TimelineLoader (300 lines)
    └─ Database query logic
    └─ Pagination/cursor management
    └─ Entry fetching

MonitoringCoordinator (250 lines)
    └─ Watcher lifecycle
    └─ Event subscription
    └─ Real-time updates

TimelineCacheCoordinator (200 lines)
    └─ LLM queue management
    └─ Cache miss handling
    └─ Summary generation
```

**Benefits:**
- Each component <500 lines (professional norm)
- Single responsibility per component
- Easier to test in isolation
- Clearer ownership

**Migration Strategy:**
1. Extract TimelineLoader first (pure data fetching)
2. Extract MonitoringCoordinator (encapsulate watchers)
3. Extract TimelineCacheCoordinator (LLM concerns)
4. Slim down ConversationMonitor to coordination only

## High Priority: HUDCore.swift (1196 lines)

### Responsibilities Analysis

1. **Project Root Management** (lines 1-200)
   - `projectRootURL: URL?`
   - `setProjectRoot()`
   - Persistence via HUDPreferences

2. **Git Branch Monitoring** (lines 200-400)
   - File watchers on `.git/HEAD`
   - `parseHEAD()` implementation
   - Branch detection logic

3. **Security-Scoped Bookmarks** (lines 400-600)
   - Bookmark creation/restoration
   - `updateSecurityScope()`
   - Sandbox detection

4. **Coordinator Integration** (lines 600-800)
   - StartupCoordinator subscription
   - `handleCoordinatorUpdate()`

5. **Legacy File Watchers** (lines 800-1000)
   - DispatchSource for `.git/HEAD`
   - Watcher lifecycle

6. **Git Command Execution** (lines 1000-1100)
   - `git rev-parse` execution
   - Process management
   - Timeout handling

7. **Preferences Management** (lines 1100-1196)
   - UserDefaults coordination
   - Path persistence

### Proposed Decomposition

**Extract 3 focused services:**

```
HUDViewModel (300 lines)
    └─ UI state only
    └─ Delegates to services

GitBranchMonitor (250 lines)
    └─ Git file watching
    └─ Branch detection
    └─ HEAD parsing

BookmarkManager (200 lines)
    └─ Security-scoped bookmarks
    └─ Sandbox handling
    └─ Bookmark lifecycle
```

**Benefits:**
- GitBranchMonitor reusable for other git operations
- BookmarkManager centralizes all bookmark logic
- HUDViewModel focused on UI concerns

## Medium Priority: ProjectDiscoveryService.swift (1000 lines)

### Current Structure

**Monolithic service with two provider strategies:**
- Claude Code discovery (lines 100-500)
- Codex CLI discovery (lines 500-900)
- Shared merging logic (lines 900-1000)

### Proposed Decomposition

```
ProjectDiscoveryService (200 lines)
    └─ High-level coordination
    └─ Provider registration
    └─ Result merging

ClaudeCodeDiscoveryProvider (350 lines)
    └─ ~/.claude/projects/ scanning
    └─ Directory name decoding

CodexDiscoveryProvider (350 lines)
    └─ ~/.codex/sessions/ scanning
    └─ cwd field parsing
    └─ Session mapping
```

**Benefits:**
- Plugin architecture (easy to add new providers)
- Isolated testing per provider
- Clear provider interface

---

# Coupling & Dependency Analysis

## High Coupling Issues

### Issue 1: ConversationMonitor ↔ TranscriptOrchestrator ↔ HooverEngine

**Problem:** 3-way tight coupling

```
ConversationMonitor
    ↓ (creates & manages)
TranscriptOrchestrator
    ↓ (calls directly)
HooverEngine
    ↓ (writes to)
DatabaseManager
```

**Impact:**
- Can't test ConversationMonitor without real database
- Can't swap HooverEngine implementation
- Changes ripple through all three components

**Solution:** Introduce protocol abstractions

```swift
protocol TranscriptIngestionService {
    func ingestTranscript(id: String, from checkpoint: Int64) async throws
}

class HooverEngineService: TranscriptIngestionService {
    // Current HooverEngine logic
}

class ConversationMonitor {
    let ingestionService: TranscriptIngestionService

    init(ingestionService: TranscriptIngestionService = HooverEngineService()) {
        self.ingestionService = ingestionService
    }
}
```

**Benefits:**
- Mock ingestion for testing
- Swap implementations (e.g., streaming vs batch)
- Clear contract

### Issue 2: HUDViewModel ↔ StartupCoordinator (Dual Project Identity)

**Problem:** Two sources of truth

```
HUDViewModel
    - projectRootURL: URL?
    - branch: String?
    - Manages bookmarks
    - Calls StartupCoordinator

StartupCoordinator
    - current: ActiveProjectContext?
    - Publishes updates
    - Also manages bookmarks
```

**Impact:**
- Race conditions during startup
- Unclear which is authoritative
- Duplicate bookmark logic

**Solution:** StartupCoordinator owns all project state

```swift
// HUDViewModel becomes thin view adapter
class HUDViewModel {
    @Published var projectDisplay: ProjectDisplay?

    init() {
        // Subscribe to coordinator
        Task {
            for await context in StartupCoordinator.shared.updates {
                projectDisplay = ProjectDisplay(from: context)
            }
        }
    }

    // No local state, delegates all mutations
    func setProjectRoot(_ url: URL) async {
        try await StartupCoordinator.shared.switchProject(to: url.path)
    }
}
```

### Issue 3: Event System Mismatch

**Problem:** AsyncStream vs NotificationCenter

**Components using AsyncStream:**
- StartupCoordinator.updates
- ProjectActivityMonitor.events

**Components using NotificationCenter:**
- TranscriptWatcher (.transcriptDidUpdate)
- ConversationMonitor (subscribes to notifications)

**Impact:**
- Event delivery mismatch (see data-pipeline-architecture.md Technical Debt #1)
- Can't use structured concurrency for all events
- Hard to trace event flow

**Solution:** Unified event bus

```swift
actor EventBus {
    private var subscribers: [EventType: [AsyncStream<Event>.Continuation]] = [:]

    func subscribe<T: Event>(to type: T.Type) -> AsyncStream<T> {
        AsyncStream { continuation in
            subscribers[T.eventType, default: []].append(continuation)
        }
    }

    func publish<T: Event>(_ event: T) {
        for continuation in subscribers[T.eventType] ?? [] {
            continuation.yield(event)
        }
    }
}

enum Event {
    case transcriptUpdated(TranscriptUpdatedEvent)
    case projectSwitched(ProjectSwitchedEvent)
    // ...
}
```

## Dependency Injection Assessment

### Current State: Mixed DI Patterns

**Constructor Injection (Good):**
```swift
class TranscriptOrchestrator {
    let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {  // ✅ Testable
        self.dbManager = dbManager
    }
}
```

**Singleton Access (Problematic):**
```swift
class ConversationMonitor {
    func startMonitoring() {
        let orchestrator = TranscriptOrchestrator(dbManager: .shared)  // ⚠️ Hard to test
    }
}
```

**Implicit Dependencies (Worst):**
```swift
class HooverEngine {
    static func hooverTranscript(...) {
        // Directly accesses DatabaseManager.shared internally ⚠️⚠️
    }
}
```

### Recommended Pattern

**Dependency Container:**

```swift
@MainActor
class AppDependencies {
    let databaseManager: DatabaseManager
    let startupCoordinator: StartupCoordinator
    let eventBus: EventBus

    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
        self.startupCoordinator = StartupCoordinator(db: databaseManager)
        self.eventBus = EventBus()
    }

    // Factory methods
    func makeConversationMonitor() -> ConversationMonitor {
        ConversationMonitor(
            orchestrator: makeTranscriptOrchestrator(),
            eventBus: eventBus
        )
    }

    func makeTranscriptOrchestrator() -> TranscriptOrchestrator {
        TranscriptOrchestrator(dbManager: databaseManager)
    }
}

// In ContextifyApp
@main
struct ContextifyApp: App {
    let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dependencies)
        }
    }
}
```

---

# Design Pattern Consistency

## State Management Patterns

### Current: Three Competing Approaches

**1. @Observable (Modern, Preferred):**
```swift
@Observable class StartupCoordinator {
    var current: ActiveProjectContext?
    // Automatic @Published-like behavior
}
```

**2. @Published (SwiftUI Traditional):**
```swift
class ConversationMonitor: ObservableObject {
    @Published var entries: [TimelineEntry] = []
}
```

**3. Manual Publishing:**
```swift
class ProjectSwitcherState {
    var projects: [Project] = [] {
        didSet { objectWillChange.send() }
    }
}
```

### Recommendation: Standardize on @Observable

**Benefits:**
- Swift 6 best practice
- Better performance (fine-grained updates)
- Cleaner syntax

**Migration:**
```swift
// Before
class MyViewModel: ObservableObject {
    @Published var data: [Item] = []
}

// After
@Observable class MyViewModel {
    var data: [Item] = []
}
```

## Async/Await Patterns

### Current: Mostly Consistent

**Good Examples:**
```swift
func startMonitoring(projectId: String) async {
    let transcripts = try await orchestrator.getTranscripts(projectId: projectId)
    // ...
}
```

**Anti-pattern Found:**
```swift
// Mixing Task {} with async/await unnecessarily
func doWork() async {
    Task {  // ⚠️ Unnecessary nesting
        await actualWork()
    }
}

// Should be:
func doWork() async {
    await actualWork()
}
```

### Recommendation: Async/Await Style Guide

**Do:**
- Use `async throws` for fallible operations
- Prefer `async let` for concurrent work
- Use `withTaskGroup` for dynamic concurrency

**Don't:**
- Nest `Task {}` inside `async` functions unnecessarily
- Use `DispatchQueue` in new code (legacy only)
- Block threads with `Task.sleep` in tight loops

## Error Handling Patterns

### Current: Inconsistent

**Typed Errors (Good):**
```swift
enum DatabaseError: Error {
    case projectNotFound(id: String)
    case migrationFailed(version: Int, underlying: Error)
}
```

**Generic Errors (Problematic):**
```swift
throw NSError(domain: "dev.contextify", code: -1, userInfo: nil)
```

**Swallowed Errors (Dangerous):**
```swift
try? someOperation()  // ⚠️ No logging, silent failure
```

### Recommendation: Error Handling Standards

**Always:**
- Use typed errors (`enum MyError: Error`)
- Log errors before re-throwing
- Provide context in error messages

**Never:**
- Use `try?` without logging
- Throw generic NSError
- Catch and ignore errors

**Example:**
```swift
enum IngestionError: Error, CustomStringConvertible {
    case fileNotFound(path: String)
    case parseError(line: Int, reason: String)
    case databaseError(underlying: Error)

    var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Transcript file not found: \(path)"
        case .parseError(let line, let reason):
            return "Parse error at line \(line): \(reason)"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        }
    }
}
```

---

# Testability Assessment

## Current Test Coverage

**Location:** `Contextify/ContextifyTests/`

**Existing Tests:**
```
GitDetectionTests.swift       - Git resolution, worktree handling
ContextifyTests.swift         - HUD view model tests
TestHelpers.swift            - Shared utilities
```

**Coverage Estimate:** ~15-20% (low)

## Testability Challenges

### Challenge 1: Singleton Dependencies

**Example:**
```swift
class ConversationMonitor {
    func startMonitoring() {
        let orchestrator = TranscriptOrchestrator(dbManager: .shared)  // ⚠️
    }
}
```

**Problem:** Can't inject mock database for testing

**Solution:**
```swift
class ConversationMonitor {
    let orchestrator: TranscriptOrchestrator

    init(orchestrator: TranscriptOrchestrator) {
        self.orchestrator = orchestrator
    }
}

// In tests:
let mockOrchestrator = MockTranscriptOrchestrator()
let monitor = ConversationMonitor(orchestrator: mockOrchestrator)
```

### Challenge 2: Hard-Coded File Paths

**Example:**
```swift
let claudeRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/projects")  // ⚠️
```

**Problem:** Tests modify real user data

**Solution:**
```swift
protocol FileSystemProvider {
    var claudeProjectsRoot: URL { get }
}

class ProductionFileSystem: FileSystemProvider {
    var claudeProjectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }
}

class TestFileSystem: FileSystemProvider {
    var claudeProjectsRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-claude-projects")
    }
}
```

### Challenge 3: @MainActor Isolation

**Example:**
```swift
@MainActor class ConversationMonitor {
    func loadFeed() async { ... }
}

// In tests - must run on MainActor
await MainActor.run {
    await monitor.loadFeed()
}
```

**Solution:** Test infrastructure for MainActor tests

```swift
@MainActor
class ConversationMonitorTests: XCTestCase {
    // All tests run on MainActor automatically

    func testLoadFeed() async throws {
        await monitor.loadFeed()  // No MainActor.run wrapper needed
    }
}
```

## Testing Recommendations

### Priority 1: Core Business Logic

**Add tests for:**
- HooverEngine parsing (unit tests with fixture JSONL files)
- StartupCoordinator project resolution (mock file system)
- ProjectDiscoveryService (mock directories)
- Database repositories (in-memory GRDB)

### Priority 2: Integration Tests

**Add tests for:**
- Full ingestion pipeline (temp database)
- Project switching (end-to-end)
- Real-time monitoring (mock file events)

### Priority 3: UI Tests

**Add tests for:**
- Timeline rendering (snapshot tests)
- Project switcher interaction
- Error state handling

---

# Refactoring Opportunities

## P0: Split ConversationMonitor (Weeks: 3-4)

### Current State
```
ConversationMonitor.swift (3054 lines, 15 responsibilities)
```

### Target State
```
ConversationMonitor.swift (400 lines)
    └─ Timeline coordination only

TimelineLoader.swift (300 lines)
    └─ Database queries & pagination

MonitoringCoordinator.swift (250 lines)
    └─ Watcher lifecycle & events

TimelineCacheCoordinator.swift (200 lines)
    └─ LLM queue management
```

### Migration Steps

**Phase 1: Extract TimelineLoader (Week 1)**
1. Create `TimelineLoader.swift`
2. Move all database query logic
3. Move cursor/pagination logic
4. Add protocol: `TimelineDataSource`
5. Update ConversationMonitor to use TimelineLoader
6. Add unit tests for TimelineLoader

**Phase 2: Extract MonitoringCoordinator (Week 2)**
1. Create `MonitoringCoordinator.swift`
2. Move watcher lifecycle management
3. Move event subscription logic
4. Expose AsyncStream of events
5. Update ConversationMonitor to subscribe
6. Add tests for event delivery

**Phase 3: Extract TimelineCacheCoordinator (Week 3)**
1. Create `TimelineCacheCoordinator.swift`
2. Move LLM queue management
3. Move cache miss handling
4. Update ConversationMonitor to delegate
5. Add tests for cache coordination

**Phase 4: Slim ConversationMonitor (Week 4)**
1. Remove extracted code
2. Keep only high-level coordination
3. Ensure all tests pass
4. Update documentation

### Benefits
- **Maintainability:** Each file <500 lines
- **Testability:** Components testable in isolation
- **Clarity:** Single responsibility per component
- **Performance:** Easier to optimize individual components

### Risks
- **Breaking Changes:** Existing code depends on ConversationMonitor structure
- **Migration Time:** 3-4 weeks of focused work
- **Testing:** Requires comprehensive test coverage first

**Mitigation:**
- Keep ConversationMonitor as facade during migration
- Deprecate old methods gradually
- Feature flag for new architecture

## P1: Extract GitBranchMonitor from HUDCore (Weeks: 2)

### Current State
```
HUDCore.swift (1196 lines)
    - Git monitoring mixed with UI state
    - Bookmark management mixed with git logic
```

### Target State
```
HUDViewModel.swift (300 lines)
    └─ UI state only

GitBranchMonitor.swift (250 lines)
    └─ Git file watching & branch detection

BookmarkManager.swift (200 lines)
    └─ Security-scoped bookmark lifecycle
```

### Migration Steps

**Week 1: Extract GitBranchMonitor**
1. Create `GitBranchMonitor.swift`
2. Move git-related methods:
   - `updateHeadWatcher()`
   - `parseHEAD()`
   - Git DispatchSource logic
3. Expose `AsyncStream<String>` for branch updates
4. Update HUDViewModel to subscribe
5. Add tests with fixture git directories

**Week 2: Extract BookmarkManager**
1. Create `BookmarkManager.swift`
2. Move bookmark methods:
   - `updateSecurityScope()`
   - Bookmark creation/restoration
3. Centralize all bookmark logic
4. Update callers (HUDCore, StartupCoordinator)
5. Add tests for bookmark lifecycle

### Benefits
- **Reusability:** GitBranchMonitor usable in other contexts
- **Clarity:** Bookmark logic centralized
- **Testability:** Mock git operations easily

## P2: Introduce Protocol Abstractions (Weeks: 3)

### Goal: Testability via Dependency Injection

**Target Protocols:**

```swift
// Data access
protocol TranscriptRepository {
    func getTranscripts(projectId: String) async throws -> [Transcript]
    func getTranscript(id: String) async throws -> Transcript?
}

// Ingestion
protocol TranscriptIngestionService {
    func ingestTranscript(id: String, from checkpoint: Int64) async throws
}

// File system
protocol FileSystemProvider {
    var claudeProjectsRoot: URL { get }
    var codexSessionsRoot: URL { get }
    func contentsOfDirectory(at url: URL) throws -> [URL]
}

// Events
protocol EventBus {
    func subscribe<T: Event>(to type: T.Type) -> AsyncStream<T>
    func publish<T: Event>(_ event: T)
}
```

### Implementation Plan

**Week 1: Define Protocols**
- Create `Protocols/` directory in ContextifyCore
- Define all core abstractions
- Document expected behaviors

**Week 2: Adapt Existing Code**
- Make existing classes conform to protocols
- Add default implementations where needed
- Update dependency injection

**Week 3: Add Mocks**
- Create `Mocks/` directory in ContextifyTests
- Implement mock versions of all protocols
- Update tests to use mocks

### Benefits
- **Testability:** 10x easier to write tests
- **Flexibility:** Swap implementations
- **Documentation:** Protocols are contracts

## P3: Unify Event System (Weeks: 2-3)

### Current State
```
AsyncStream: StartupCoordinator, ProjectActivityMonitor
NotificationCenter: TranscriptWatcher, ConversationMonitor
```

### Target State
```
EventBus (actor)
    └─ All components publish/subscribe via AsyncStream
```

### Implementation

**Week 1: Create EventBus**
```swift
actor EventBus {
    typealias EventID = UUID

    private var subscriptions: [ObjectIdentifier: [Subscription]] = [:]

    struct Subscription {
        let id: EventID
        let continuation: AsyncStream<any Event>.Continuation
    }

    func subscribe<T: Event>(to type: T.Type) -> AsyncStream<T> {
        AsyncStream { continuation in
            let subscription = Subscription(id: UUID(), continuation: continuation)
            subscriptions[ObjectIdentifier(T.self), default: []].append(subscription)
        }
    }

    func publish<T: Event>(_ event: T) {
        let typeID = ObjectIdentifier(T.self)
        for subscription in subscriptions[typeID] ?? [] {
            subscription.continuation.yield(event)
        }
    }
}

protocol Event: Sendable {
    var timestamp: Date { get }
}

struct TranscriptUpdatedEvent: Event {
    let timestamp = Date()
    let transcriptId: String
    let newLineCount: Int64
}
```

**Week 2: Migrate Components**
1. Update TranscriptWatcher to publish to EventBus
2. Update ConversationMonitor to subscribe to EventBus
3. Remove NotificationCenter usage
4. Add tests for event delivery

**Week 3: Integration & Testing**
1. End-to-end testing of event flow
2. Performance testing (latency measurement)
3. Update documentation

### Benefits
- **Consistency:** Single event mechanism
- **Type Safety:** Compile-time event validation
- **Debugging:** Central point for event logging

---

# Migration Roadmap

## Phase 1: Foundation (Months 0-2)

**Goal:** Establish testing infrastructure and reduce critical complexity

**Deliverables:**
1. ✅ Protocol abstractions defined
2. ✅ Mock implementations created
3. ✅ ConversationMonitor split into 4 components
4. ✅ Unit test coverage >40%

**Effort:** 6-8 weeks, 1 engineer

**Risk:** Low - Purely additive changes

## Phase 2: Consistency (Months 2-4)

**Goal:** Standardize patterns and eliminate technical debt

**Deliverables:**
1. ✅ Unified event system (EventBus)
2. ✅ GitBranchMonitor extracted
3. ✅ BookmarkManager centralized
4. ✅ All ViewModels using @Observable

**Effort:** 6-8 weeks, 1 engineer

**Risk:** Medium - Some breaking changes

## Phase 3: Quality (Months 4-6)

**Goal:** Achieve production-grade quality

**Deliverables:**
1. ✅ Unit test coverage >70%
2. ✅ Integration test suite
3. ✅ Performance benchmarks established
4. ✅ Documentation complete

**Effort:** 8 weeks, 1-2 engineers

**Risk:** Low - Quality improvements

## Phase 4: Advanced (Months 6-12)

**Goal:** Future-proofing and advanced features

**Deliverables:**
1. 🔮 SwiftData migration (when stable)
2. 🔮 Plugin architecture for providers
3. 🔮 SPM modularization
4. 🔮 Vector search (RAG)

**Effort:** 4-6 months, 1-2 engineers

**Risk:** High - Major architectural shifts

---

## Metrics & Success Criteria

### Code Quality Metrics

**Before Refactoring:**
- Average file size: ~450 lines
- Files >1000 lines: 3
- Test coverage: ~15%
- Cyclomatic complexity (avg): ~12

**After Refactoring (Target):**
- Average file size: ~300 lines
- Files >1000 lines: 0
- Test coverage: >70%
- Cyclomatic complexity (avg): <8

### Performance Metrics

**Maintain or Improve:**
- Cold start: <500ms (current: ~200-500ms)
- Full discovery: <2s (current: 2-5s)
- Real-time latency: <200ms (current: ~200-350ms)

### Development Velocity

**Target Improvements:**
- Time to add new provider: 2 days → 4 hours
- Time to add new event type: 4 hours → 30 minutes
- Time to write test: 1 hour → 15 minutes

---

## Conclusion

Contextify's architecture is **fundamentally sound** but has accumulated technical debt through rapid evolution. The proposed refactorings are **incremental and low-risk**, focusing on:

1. **Splitting god objects** (ConversationMonitor, HUDCore)
2. **Introducing abstractions** (protocols for testability)
3. **Standardizing patterns** (unified event system, @Observable)

**Estimated Total Effort:** 6-12 months for complete transformation

**Recommended Approach:** Execute Phase 1 and 2 immediately (4 months), defer Phase 3 and 4 based on product roadmap.

**ROI:**
- **Maintainability:** 2-3x easier to modify code
- **Velocity:** 1.5-2x faster feature development
- **Quality:** 10x fewer bugs (via testing)

---

**Last Updated:** 2025-11-17
**Next Review:** After Phase 1 completion
**Maintainers:** See CLAUDE.md for contribution guidelines
