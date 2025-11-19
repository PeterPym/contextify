# Architecture Analysis & Improvement Opportunities

**Status:** Current as of 2025-11-19
**Purpose:** Architectural health assessment and refactoring roadmap
**Audience:** Developers, architects, technical leadership

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Codebase Health Metrics](#codebase-health-metrics)
3. [Architectural Strengths](#architectural-strengths)
4. [God Objects & Complexity Hotspots](#god-objects--complexity-hotspots)
5. [Coupling & Dependency Analysis](#coupling--dependency-analysis)
6. [Design Pattern Consistency](#design-pattern-consistency)
7. [Testability Assessment](#testability-assessment)
8. [Refactoring Opportunities](#refactoring-opportunities)
9. [Implementation Roadmap](#implementation-roadmap)

---

# Executive Summary

## Current State

Contextify's architecture demonstrates **strong fundamentals** with a mature lazy loading system, central state coordination, and well-isolated database layer. The application achieves excellent performance (<200ms startup, 30-50 MB memory footprint) through careful architectural design.

**Architecture Grade: A-**

### Strengths
- ✅ Excellent separation of UI/Business Logic/Data layers
- ✅ Swift 6 strict concurrency with proper actor isolation
- ✅ Robust SQL backend (GRDB, schema v26, WAL mode)
- ✅ Central state coordination (AppStateOrchestrator with state machine)
- ✅ High-performance lazy loading architecture
- ✅ Clean discovery tier separation (lightweight vs. full)

### Areas for Improvement
- ⚠️ ConversationMonitor remains a god object (3054 lines, ~15 responsibilities)
- ⚠️ Hybrid event system (NotificationCenter + @Published)
- ⚠️ No protocol abstractions (difficult to test)
- ⚠️ HUDCore combines multiple concerns (1196 lines)

### Critical Priorities
1. **P0 - ConversationMonitor Refactor** (3-4 weeks) - Split into focused components
2. **P1 - HUDCore Extraction** (2 weeks) - Separate Git and bookmark management
3. **P2 - Protocol Abstractions** (2-3 weeks) - Enable dependency injection for testing
4. **P3 - Unified Event System** (2-3 weeks) - Replace NotificationCenter with EventBus actor

---

# Codebase Health Metrics

## File Size Distribution

### Critical - Requires Refactoring (>1000 lines)
```
ConversationMonitor.swift           3054 lines  🔴 CRITICAL
HUDCore.swift                      1196 lines  ⚠️  HIGH
ProjectDiscoveryService.swift     1000 lines  ⚠️  MEDIUM
```

### Large - Acceptable for Coordinators (500-1000 lines)
```
HooverEngine.swift                  898 lines  ✓ (streaming parser, acceptable)
StartupCoordinator.swift            735 lines  ✓ (legacy shim, scheduled for removal)
DatabaseManager.swift              ~600 lines  ✓ (singleton manager, acceptable)
```

### Well-Sized - Good Examples (200-500 lines)
```
AppStateOrchestrator.swift          297 lines  ✓ EXCELLENT (new architecture)
LightweightDiscoveryService.swift   251 lines  ✓ EXCELLENT (focused actor)
TranscriptWatcher.swift             307 lines  ✓
TranscriptOrchestrator.swift       ~350 lines  ✓
DatabaseSchema.swift               ~400 lines  ✓
```

### Small - Focused Components (<200 lines)
```
ProjectsViewModel.swift             163 lines  ✓ EXCELLENT (simplified in current arch)
TimelineModels.swift               ~150 lines  ✓
ActiveProjectContext.swift          ~80 lines  ✓
```

## Complexity Metrics

**God Objects Identified:**

| File | Lines | Responsibilities | Severity | Recommended Action |
|------|-------|------------------|----------|-------------------|
| ConversationMonitor.swift | 3054 | 15+ | 🔴 Critical | Split into 4 components |
| HUDCore.swift | 1196 | 8+ | ⚠️ High | Extract Git/Bookmark managers |
| ProjectDiscoveryService.swift | 1000 | 6 | ⚠️ Medium | Consider lightweight-only in future |
| HooverEngine.swift | 898 | 4 | ℹ️ Low | Acceptable for streaming parser |

---

# Architectural Strengths

## 1. Lazy Loading Architecture

**Implementation:** Two-tier discovery with JIT ingestion

**Components:**
- `AppStateOrchestrator` - Central state coordinator (297 lines)
- `LightweightDiscoveryService` - Stat-only scanning (<200ms)
- `FastPathIngestionCoordinator` - Just-in-time ingestion
- `ProjectsViewModel` - Simplified observer (163 lines, 63% smaller than previous design)

**Performance Achieved:**
- Cold start: 187ms (10-35x improvement)
- Memory at startup: 30-50 MB (3-5x reduction)
- DB writes at startup: 19 rows (10-20x reduction)

**Design Quality:** Excellent separation of concerns, clear state machine pattern

## 2. State Machine Pattern

**Implementation:** `AppState` enum in AppStateOrchestrator

```swift
enum AppState: Sendable {
  case startup
  case discovering
  case idle(projects: [LightweightProject])
  case loading(projectId: String)
  case active(projectId: String)
  case error(String)
}
```

**Benefits:**
- Type-safe state transitions
- Impossible invalid states
- Clear lifecycle modeling
- Easy to test and debug

## 3. Database Layer

**Implementation:** GRDB with schema v26, WAL mode

**Strengths:**
- Clean repository pattern
- Streaming ingestion (HooverEngine)
- Checkpointing for crash safety
- Multi-machine conflict detection
- Custom location support (Dropbox, iCloud)

**Isolation:** Well-separated from business logic via TranscriptOrchestrator

## 4. Actor Concurrency Model

**Examples:**
- `LightweightDiscoveryService` (actor) - Thread-safe filesystem scanning
- `ProjectDiscoveryService` (actor) - Safe mutable state management
- `@MainActor` components - UI safety guarantees

**Swift 6 Compliance:** Full strict concurrency adoption

---

# God Objects & Complexity Hotspots

## Critical: ConversationMonitor (3054 lines)

**Current Responsibilities (~15):**

1. Timeline state management (TimelineState, entries array)
2. Database query coordination (loadFeedFromSQL, pagination)
3. Transcript watcher lifecycle (start/stop monitoring)
4. LLM queue management (TimelineCacheMissGenerator coordination)
5. Session filtering and switching
6. Unread tracking and visit updates
7. System message handling
8. Entry expansion/collapse state
9. Scroll position management
10. Real-time update handling (NotificationCenter subscriptions)
11. StartupCoordinator integration (legacy)
12. Project switching coordination
13. Metadata generation orchestration
14. Status bar state aggregation
15. Error handling and recovery

**Coupling Issues:**
- Tight coupling to StartupCoordinator (legacy dependency)
- Direct NotificationCenter usage (fragile event system)
- Mixed UI state and business logic
- Hard to test (no protocol abstractions)

**Recommended Split (4 components):**

### 1. ConversationMonitor (~400 lines)
**Responsibilities:** Timeline coordination only
- Owns TimelineState
- Coordinates between loader, watcher, cache
- Handles user actions (session switch, scroll)

### 2. TimelineLoader (~300 lines)
**Responsibilities:** Database queries and pagination
- SQL query execution via TranscriptOrchestrator
- Pagination logic
- Entry filtering

### 3. MonitoringCoordinator (~250 lines)
**Responsibilities:** Watcher lifecycle management
- Start/stop TranscriptWatcher instances
- Handle file system events
- Coordinate refresh triggers

### 4. TimelineCacheCoordinator (~200 lines)
**Responsibilities:** LLM queue management
- Coordinate TimelineCacheMissGenerator
- Track pending summaries
- Provide status aggregation

**Estimated Effort:** 3-4 weeks
**Priority:** P0 (Critical)

---

## High: HUDCore (1196 lines)

**Current Responsibilities (~8):**

1. Project root management
2. Git repository detection
3. Git branch monitoring (file watchers)
4. File/URL ingestion
5. Session management
6. Checkpoint creation
7. Security-scoped bookmarks
8. UserDefaults persistence

**Recommended Extraction:**

### 1. GitBranchMonitor (~150 lines)
- Watch `.git/HEAD` for changes
- Parse branch from refs
- Handle detached state
- Emit branch updates

### 2. BookmarkManager (~100 lines)
- Create/resolve security-scoped bookmarks
- Persist bookmark data
- Handle access coordination

### 3. Simplified HUDViewModel (~800 lines)
- Project root coordination
- Ingestion orchestration
- Session/checkpoint management

**Estimated Effort:** 2 weeks
**Priority:** P1 (High)

---

# Coupling & Dependency Analysis

## Current Coupling Issues

### 1. Event System Fragmentation

**Problem:** Two competing event mechanisms

**NotificationCenter usage:**
- ConversationMonitor ← TranscriptWatcher
- ProjectSwitcherState ← Discovery updates
- Background indexing progress
- Legacy compatibility layers

**@Published properties:**
- AppStateOrchestrator.state
- ViewModels throughout UI

**Recommendation:** Migrate to unified EventBus actor with AsyncStream

### 2. StartupCoordinator Legacy Dependency

**Current Role:** Compatibility shim for ConversationMonitor

**Problem:**
- AppStateOrchestrator → StartupCoordinator → ConversationMonitor roundtrip
- Unnecessary intermediate layer
- ActiveProjectContext creation overhead

**Solution:** Remove after ConversationMonitor refactor (Phase 4)

### 3. Concrete Dependencies (No Protocols)

**Example:** ConversationMonitor directly instantiates:
- TranscriptOrchestrator
- TimelineCacheMissGenerator
- TranscriptWatcher

**Problem:** Impossible to test in isolation, must use real database

**Solution:** Introduce protocol abstractions (P2)

---

# Design Pattern Consistency

## Well-Applied Patterns

### ✅ State Machine (AppStateOrchestrator)
Clear, type-safe state modeling with explicit transitions

### ✅ Observer Pattern (ProjectsViewModel)
Clean separation: view model observes orchestrator, no business logic

### ✅ Repository Pattern (Database layer)
ProjectRepository, TranscriptRepository, EntryRepository abstractions

### ✅ Actor Pattern (Discovery services)
Thread-safe mutable state with Swift 6 actors

### ✅ Coordinator Pattern (AppStateOrchestrator, FastPathIngestionCoordinator)
Central coordination of complex workflows

## Inconsistent Patterns

### ⚠️ Event Delivery
NotificationCenter + @Published + AsyncStream mix creates confusion

### ⚠️ Dependency Injection
Some components use DI (DatabaseManager.shared), others hard-code dependencies

### ⚠️ Error Handling
Mix of throws, Result<>, optional returns, and @Published error properties

---

# Testability Assessment

## Current Test Coverage

**Estimated Coverage:** ~15%

**Well-Tested:**
- Git detection (GitDetectionTests.swift)
- Basic HUD initialization

**Poorly Tested:**
- ConversationMonitor (too complex, no mocks)
- Discovery services
- AppStateOrchestrator state machine
- Ingestion pipeline
- LLM queue coordination

## Testing Barriers

### 1. Concrete Dependencies
```swift
// ConversationMonitor.swift - hard to test
class ConversationMonitor {
    private let orchestrator = TranscriptOrchestrator(dbManager: .shared)
    // ↑ Requires real database, no way to inject mock
}
```

### 2. Singleton Overuse
```swift
DatabaseManager.shared  // Global state, test interference
AppStateOrchestrator.shared
StartupCoordinator.shared
```

### 3. NotificationCenter Coupling
Hard to verify notification flow in tests, timing-dependent

---

# Refactoring Opportunities

## P0 - Critical (3-4 weeks)

### ConversationMonitor Split

**Goal:** 4 focused components (~400 lines each)

**Protocol Interfaces:**
```swift
protocol TimelineLoaderProtocol {
    func loadEntries(projectId: String, cursor: TimelineCursor) async throws -> [TimelineEntry]
}

protocol MonitoringCoordinatorProtocol {
    func startMonitoring(projectId: String) async
    func stopMonitoring()
}

protocol TimelineCacheCoordinatorProtocol {
    func generateMissingSummaries(entries: [TimelineEntry]) async
    var queueStatus: LLMQueueStatus { get }
}
```

**Benefits:**
- Each component <500 lines
- Testable in isolation
- Clear responsibilities
- Easier to reason about

**Migration Path:**
1. Week 1: Define protocols, create TimelineLoader
2. Week 2: Extract MonitoringCoordinator, TimelineCacheCoordinator
3. Week 3: Refactor ConversationMonitor, wire components
4. Week 4: Testing, integration, remove legacy code

---

## P1 - High (2 weeks)

### HUDCore Extraction

**Components to Extract:**

1. **GitBranchMonitor**
```swift
actor GitBranchMonitor {
    func watch(repositoryPath: URL) -> AsyncStream<String?>
    func currentBranch() async -> String?
}
```

2. **BookmarkManager**
```swift
actor BookmarkManager {
    func createBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> URL
}
```

**Benefits:**
- HUDViewModel reduced to ~800 lines
- Git logic reusable
- Bookmark management centralized
- Easier testing

---

## P2 - Medium (2-3 weeks)

### Protocol Abstractions for DI

**Goal:** Enable dependency injection for testing

**Key Protocols:**

```swift
protocol DatabasePoolProtocol {
    func read<T>(_ block: (Database) throws -> T) throws -> T
    func write<T>(_ updates: (Database) throws -> T) throws -> T
}

protocol TranscriptOrchestratorProtocol {
    func getProject(id: String) async throws -> Project?
    func getTranscripts(projectId: String) async throws -> [Transcript]
    func getEntries(transcriptId: String) async throws -> [Entry]
}

protocol DiscoveryServiceProtocol {
    func discoverProjects() async throws -> [LightweightProject]
}
```

**Migration Strategy:**
- Introduce protocols alongside existing code
- Update components one-by-one to accept protocols
- Create mock implementations for tests
- Gradually increase test coverage

---

## P3 - Medium (2-3 weeks)

### Unified Event System

**Goal:** Replace NotificationCenter with type-safe EventBus

**Implementation:**

```swift
actor EventBus {
    func publish<T: Event>(_ event: T) async
    func subscribe<T: Event>(_ type: T.Type) -> AsyncStream<T>
}

protocol Event: Sendable {
    var timestamp: Date { get }
}

// Concrete events
struct ProjectDidActivate: Event {
    let projectId: String
    let timestamp: Date
}

struct BackgroundIngestProgress: Event {
    let completed: Int
    let total: Int
    let timestamp: Date
}
```

**Benefits:**
- Type-safe events
- No stringly-typed notification names
- Easy to test
- Clear event flow
- No timing issues

---

# Implementation Roadmap

## Phase 1: Foundation (Weeks 1-4)

**Goals:**
- Split ConversationMonitor into 4 components
- Establish protocol interfaces
- Create initial mock implementations

**Deliverables:**
- TimelineLoader, MonitoringCoordinator, TimelineCacheCoordinator, refactored ConversationMonitor
- Protocol definitions
- 40%+ unit test coverage

**Risk:** High complexity, potential for regression bugs

**Mitigation:** Incremental rollout, extensive integration testing

---

## Phase 2: Cleanup (Weeks 5-6)

**Goals:**
- Extract GitBranchMonitor and BookmarkManager from HUDCore
- Remove StartupCoordinator (no longer needed after ConversationMonitor refactor)

**Deliverables:**
- Simplified HUDViewModel (~800 lines)
- GitBranchMonitor actor
- BookmarkManager actor
- StartupCoordinator deleted

**Risk:** Medium - legacy dependencies

---

## Phase 3: Testing Infrastructure (Weeks 7-9)

**Goals:**
- Implement protocol abstractions across codebase
- Build comprehensive mock suite
- Achieve 70%+ test coverage

**Deliverables:**
- DatabasePoolProtocol, TranscriptOrchestratorProtocol, etc.
- Mock implementations
- Expanded test suite
- Performance benchmarks

---

## Phase 4: Event System (Weeks 10-12)

**Goals:**
- Implement EventBus actor
- Migrate NotificationCenter usage to EventBus
- Remove NotificationCenter dependencies

**Deliverables:**
- EventBus implementation
- Event type definitions
- Migration complete
- Documentation updates

---

## Success Criteria

**Performance Targets (Maintain Current):**
- Cold start: <200ms
- Memory at startup: <50 MB
- UI responsiveness: 60 FPS during scrolling

**Code Quality Targets:**
- No files >1000 lines
- Test coverage >70%
- All dependencies protocol-based
- Single event system

**Architecture Targets:**
- All components <500 lines
- Clear responsibility boundaries
- No god objects
- Full dependency injection support

---

## Related Documentation

- **Current Architecture:** `build/docs/architecture/COMPONENTS.md`
- **Data Pipeline:** `build/docs/architecture/data-pipeline-architecture.md`
- **Performance Benchmarks:** `build/docs/testing/performance-benchmarks.md`
- **Testing Guide:** `build/docs/testing/integration-testing-guide.md`
