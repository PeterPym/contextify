# Change Requirements: build/docs/testing/integration-testing-guide.md

**Document:** `build/docs/testing/integration-testing-guide.md`
**Priority:** 4 (Testing)
**Impact:** Medium - Test strategy document (969 lines)
**Estimated Effort:** 4-5 hours

---

## Current State Analysis

**File:** 969 lines comprehensive testing guide
**Current Content:**
- Database integration tests
- Transcript ingestion tests
- LLM integration tests
- UI tests
- Fixture management
- CI/CD integration

**Issues:**
1. No AppStateOrchestrator testing section
2. No lazy loading integration tests
3. No state machine transition tests
4. No JIT ingestion test patterns
5. No background indexing tests
6. No cache coherency tests

---

## Required Changes

### 1. Add "AppStateOrchestrator Testing" Section

**Location:** Insert before UI tests section

**Content:**

```markdown
## AppStateOrchestrator Testing (Phase 3)

### Test Goals

1. **State Machine Correctness** - All valid transitions work, invalid transitions prevented
2. **Performance** - Startup <200ms, JIT <1s
3. **Cancellation** - Background work cancels gracefully
4. **Error Handling** - Failures transition to error state with user message
5. **Cache Coherency** - Project lookup cache stays synchronized

### Test Infrastructure

**Setup:**
```swift
@MainActor
class AppStateOrchestratorTests: XCTestCase {
  var orchestrator: AppStateOrchestrator!
  var mockDiscovery: MockLightweightDiscoveryService!
  var mockIngestion: MockFastPathIngestionCoordinator!
  var tempDB: URL!

  override func setUp() async throws {
    // Create temp database
    tempDB = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("db")

    // Initialize with mocks (requires DI - Phase 4)
    // For now: Test with real services + temp DB
    orchestrator = AppStateOrchestrator.shared

    // Clear state
    await orchestrator.reset()  // Add this method for testing
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDB)
  }
}
```

**Note:** Full DI (dependency injection) will be added in Phase 4. Current tests use real services with temporary database.

---

### State Machine Transition Tests

**Test 1: Startup Flow**
```swift
@MainActor
func testStartupFlow() async throws {
  // Given: Fresh app state
  XCTAssertEqual(orchestrator.state, .startup)

  // When: Call startup
  await orchestrator.startup()

  // Then: Should transition through discovering → idle
  await Task.yield()  // Let async work complete

  guard case .idle(let projects) = orchestrator.state else {
    XCTFail("Expected idle state, got: \(orchestrator.state)")
    return
  }

  XCTAssertFalse(projects.isEmpty, "Should discover projects")
}
```

**Test 2: Project Selection (JIT)**
```swift
@MainActor
func testProjectSelectionJIT() async throws {
  // Given: Idle state with projects
  await orchestrator.startup()
  await Task.yield()

  guard case .idle(let projects) = orchestrator.state,
        let firstProject = projects.first else {
    XCTFail("No projects available")
    return
  }

  // When: Select project
  await orchestrator.selectProject(id: firstProject.id)

  // Then: Should transition loading → active
  await Task.yield()

  guard case .active(let projectId) = orchestrator.state else {
    XCTFail("Expected active state, got: \(orchestrator.state)")
    return
  }

  XCTAssertEqual(projectId, firstProject.id)
}
```

**Test 3: Invalid Transition Prevention**
```swift
@MainActor
func testInvalidTransitionPrevention() async throws {
  // Given: Startup state
  XCTAssertEqual(orchestrator.state, .startup)

  // When: Try to select project before discovery
  // NOTE: This is a design test - selectProject should handle gracefully

  // Create fake project ID
  let fakeId = "nonexistent"

  await orchestrator.selectProject(id: fakeId)
  await Task.yield()

  // Then: Should transition to error state (not crash)
  guard case .error = orchestrator.state else {
    XCTFail("Expected error state for invalid transition")
    return
  }
}
```

**Test 4: Error State Transition**
```swift
@MainActor
func testErrorStateOnFailure() async throws {
  // Given: Idle state
  await orchestrator.startup()

  // When: Select project that will fail ingestion
  // (Requires mock or corrupted test fixture)
  let corruptProjectId = "corrupt-project"

  await orchestrator.selectProject(id: corruptProjectId)
  await Task.yield()

  // Then: Should be in error state
  guard case .error(let message) = orchestrator.state else {
    XCTFail("Expected error state")
    return
  }

  XCTAssertFalse(message.isEmpty, "Error message should not be empty")
}
```

---

### Performance Tests

**Test 5: Startup Performance**
```swift
@MainActor
func testStartupPerformance() async throws {
  measure(metrics: [XCTClockMetric()]) {
    Task { @MainActor in
      await orchestrator.startup()
    }
  }

  // Assert: <200ms
  // (XCTest baseline will track regressions)
}
```

**Test 6: JIT Ingestion Performance**
```swift
@MainActor
func testJITIngestionPerformance() async throws {
  // Given: Idle state with projects
  await orchestrator.startup()

  guard case .idle(let projects) = orchestrator.state,
        let firstProject = projects.first else {
    XCTFail("No projects")
    return
  }

  // When: Measure project selection
  let start = Date()
  await orchestrator.selectProject(id: firstProject.id)
  let duration = Date().timeIntervalSince(start)

  // Then: Should be <1s for typical project
  XCTAssertLessThan(duration, 1.0, "JIT ingestion too slow: \(duration)s")
}
```

---

### Cancellation Tests

**Test 7: Background Work Cancellation**
```swift
@MainActor
func testBackgroundWorkCancellation() async throws {
  // Given: Background indexing running
  await orchestrator.startup()
  // Background indexing starts automatically after idle

  // When: User selects project (should cancel background)
  guard case .idle(let projects) = orchestrator.state,
        let project = projects.first else {
    XCTFail("No projects")
    return
  }

  await orchestrator.selectProject(id: project.id)

  // Then: Background work should be cancelled
  // (Verify via logs or internal state inspection)

  // Note: Requires access to backgroundTask for assertion
  // Phase 4: Add testable API for this
}
```

---

### Cache Coherency Tests

**Test 8: Project Lookup Cache**
```swift
@MainActor
func testProjectLookupCache() async throws {
  // Given: Projects discovered and cached
  await orchestrator.startup()

  guard case .idle(let projects) = orchestrator.state,
        let firstProject = projects.first else {
    XCTFail("No projects")
    return
  }

  // When: Select project by ID (cache hit)
  await orchestrator.selectProject(id: firstProject.id)

  // Then: Should resolve from cache (fast)
  // (Verify via logs showing cache hit, not DB lookup)
}
```

**Test 9: Cache Miss Fallback**
```swift
@MainActor
func testCacheMissFallback() async throws {
  // Given: Project exists in DB but not in cache
  // (Simulate by inserting project directly to DB)

  let testProjectId = "cache-miss-test"
  // Insert to DB...

  // When: Select project not in cache
  await orchestrator.selectProject(id: testProjectId)

  // Then: Should fall back to DB and succeed
  guard case .active(let projectId) = orchestrator.state else {
    XCTFail("Expected active state")
    return
  }

  XCTAssertEqual(projectId, testProjectId)
}
```

---
```

**Estimated Effort:** 2.5 hours

---

### 2. Add "Lazy Loading Integration Tests" Section

**Location:** After AppStateOrchestrator section

**Content:**

```markdown
## Lazy Loading Integration Tests (Phase 3)

### Test Goals

1. **Startup Lightweight** - No ingestion at startup
2. **JIT Ingestion** - Only selected project ingested
3. **Background Indexing** - Inactive projects ingested in background
4. **Memory Efficiency** - Startup memory 3-5x lower than eager loading

### Database State Tests

**Test 1: Startup Does Not Ingest**
```swift
func testStartupDoesNotIngest() async throws {
  // Given: Fresh database
  let db = try DatabaseManager(path: tempDB)
  let transcriptCount = try db.read { db in
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts")
  }

  // When: App starts
  await orchestrator.startup()
  await Task.yield()

  // Then: No transcripts ingested (only project metadata)
  let newCount = try db.read { db in
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts")
  }

  XCTAssertEqual(transcriptCount, newCount,
    "Startup should not ingest transcripts")

  // Verify project metadata updated
  let projectCount = try db.read { db in
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects")
  }
  XCTAssertGreaterThan(projectCount, 0,
    "Projects metadata should be updated")
}
```

**Test 2: JIT Ingests Only Selected Project**
```swift
func testJITIngestsOnlySelectedProject() async throws {
  // Given: Multiple projects, none ingested
  await orchestrator.startup()

  guard case .idle(let projects) = orchestrator.state,
        projects.count >= 2 else {
    XCTFail("Need at least 2 projects")
    return
  }

  let selectedProject = projects[0]
  let otherProject = projects[1]

  // When: Select first project
  await orchestrator.selectProject(id: selectedProject.id)
  await Task.yield()

  // Then: Only first project ingested
  let db = try DatabaseManager(path: tempDB)

  let selectedTranscripts = try db.read { db in
    try Int.fetchOne(db, sql:
      "SELECT COUNT(*) FROM transcripts WHERE project_id = ?",
      arguments: [selectedProject.id]
    )
  }
  XCTAssertGreaterThan(selectedTranscripts, 0,
    "Selected project should have transcripts")

  let otherTranscripts = try db.read { db in
    try Int.fetchOne(db, sql:
      "SELECT COUNT(*) FROM transcripts WHERE project_id = ?",
      arguments: [otherProject.id]
    )
  }
  XCTAssertEqual(otherTranscripts, 0,
    "Other project should NOT have transcripts yet")
}
```

---

### Memory Efficiency Tests

**Test 3: Startup Memory Footprint**
```swift
func testStartupMemoryFootprint() async throws {
  // Measure memory before startup
  let memoryBefore = getMemoryUsage()

  // When: App starts
  await orchestrator.startup()
  await Task.yield()

  // Then: Memory increase should be minimal (<50 MB)
  let memoryAfter = getMemoryUsage()
  let increase = memoryAfter - memoryBefore

  XCTAssertLessThan(increase, 50_000_000,  // 50 MB
    "Startup memory increase too high: \(increase / 1_000_000) MB")
}

private func getMemoryUsage() -> UInt64 {
  var info = mach_task_basic_info()
  var count = mach_msg_type_number_t(
    MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
  )

  let result = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO),
        $0, &count)
    }
  }

  return result == KERN_SUCCESS ? info.resident_size : 0
}
```

---

### Background Indexing Tests

**Test 4: Background Indexing After Idle**
```swift
func testBackgroundIndexingAfterIdle() async throws {
  // Given: Idle state with multiple projects
  await orchestrator.startup()

  guard case .idle(let projects) = orchestrator.state,
        projects.count > 1 else {
    XCTFail("Need multiple projects")
    return
  }

  // When: Wait for background indexing to start (5s delay)
  try await Task.sleep(nanoseconds: 6_000_000_000)  // 6 seconds

  // Then: Background indexing should have started
  // (Check logs or internal state)

  // Verify some projects ingested in background
  let db = try DatabaseManager(path: tempDB)
  let ingestedCount = try db.read { db in
    try Int.fetchOne(db, sql:
      "SELECT COUNT(DISTINCT project_id) FROM transcripts"
    )
  }

  XCTAssertGreaterThan(ingestedCount, 1,
    "Background indexing should have ingested projects")
}
```

---
```

**Estimated Effort:** 1.5 hours

---

### 3. Add Mock Implementations Section

**Location:** After test patterns

**Content:**

```markdown
## Mock Implementations (Phase 4 - Planned)

**Note:** Full mocking requires DI (Phase 4). These are proposed patterns.

### MockLightweightDiscoveryService

```swift
actor MockLightweightDiscoveryService {
  var mockProjects: [LightweightProject] = []
  var scanDelay: TimeInterval = 0.1  // Simulated delay

  func discoverProjectsLightweight() async -> [LightweightProject] {
    try? await Task.sleep(nanoseconds: UInt64(scanDelay * 1_000_000_000))
    return mockProjects
  }

  // Test helper
  func addMockProject(id: String, name: String) {
    mockProjects.append(LightweightProject(
      id: id,
      path: URL(fileURLWithPath: "/mock/\(name)"),
      displayName: name,
      transcriptCount: 5,
      lastActivity: Date(),
      provider: "mock",
      cwd: "/mock/\(name)",
      transcriptFiles: []
    ))
  }
}
```

### MockFastPathIngestionCoordinator

```swift
actor MockFastPathIngestionCoordinator {
  var shouldFail = false
  var ingestionDelay: TimeInterval = 0.5

  func ingestProjectJIT(_ project: LightweightProject) async throws -> String {
    try await Task.sleep(nanoseconds: UInt64(ingestionDelay * 1_000_000_000))

    if shouldFail {
      throw IngestionError.mockFailure
    }

    return project.id
  }

  func cancel() async {
    // Mock cancellation
  }
}

enum IngestionError: Error {
  case mockFailure
}
```

### Usage in Tests (Phase 4)

```swift
@MainActor
func testWithMocks() async throws {
  let mockDiscovery = MockLightweightDiscoveryService()
  mockDiscovery.addMockProject(id: "test1", name: "Test Project 1")
  mockDiscovery.addMockProject(id: "test2", name: "Test Project 2")

  let mockIngestion = MockFastPathIngestionCoordinator()

  // Inject mocks (requires DI refactor)
  let orchestrator = AppStateOrchestrator(
    discovery: mockDiscovery,
    ingestion: mockIngestion
  )

  // Test with controlled environment
  await orchestrator.startup()
  // ...
}
```

---
```

**Estimated Effort:** 30 minutes

---

### 4. Add Test Fixtures Section

**Location:** End of document

**Content:**

```markdown
## Test Fixtures for Phase 3

### Lightweight Project Fixtures

**File:** `ContextifyTests/Fixtures/LightweightProjects.swift`

```swift
struct LightweightProjectFixtures {
  static let typical = LightweightProject(
    id: "test-project-1",
    path: URL(fileURLWithPath: "/tmp/test-project-1"),
    displayName: "Test Project 1",
    transcriptCount: 5,
    lastActivity: Date(),
    provider: "claude.code",
    cwd: "/Users/test/repos/project-1",
    transcriptFiles: [
      URL(fileURLWithPath: "/tmp/test-project-1/transcript1.jsonl"),
      URL(fileURLWithPath: "/tmp/test-project-1/transcript2.jsonl")
    ]
  )

  static let empty = LightweightProject(
    id: "test-project-empty",
    path: URL(fileURLWithPath: "/tmp/test-project-empty"),
    displayName: "Empty Project",
    transcriptCount: 0,
    lastActivity: Date().addingTimeInterval(-86400),
    provider: "claude.code",
    cwd: nil,
    transcriptFiles: []
  )

  static let large = LightweightProject(
    id: "test-project-large",
    path: URL(fileURLWithPath: "/tmp/test-project-large"),
    displayName: "Large Project",
    transcriptCount: 100,
    lastActivity: Date(),
    provider: "codex.cli",
    cwd: "/Users/test/repos/large-project",
    transcriptFiles: (0..<100).map { i in
      URL(fileURLWithPath: "/tmp/test-project-large/transcript\(i).jsonl")
    }
  )
}
```

### AppState Fixtures

```swift
extension AppState {
  static var fixtureIdle: AppState {
    .idle(projects: [
      LightweightProjectFixtures.typical,
      LightweightProjectFixtures.empty
    ])
  }

  static var fixtureLoading: AppState {
    .loading(projectId: "test-project-1")
  }

  static var fixtureActive: AppState {
    .active(projectId: "test-project-1")
  }

  static var fixtureError: AppState {
    .error("Test error message")
  }
}
```

---
```

**Estimated Effort:** 30 minutes

---

## Summary of Changes

1. **Add:** AppStateOrchestrator testing section (~250 lines)
2. **Add:** Lazy loading integration tests (~150 lines)
3. **Add:** Mock implementations section (~80 lines)
4. **Add:** Test fixtures section (~80 lines)

**Total Lines Added:** ~560 lines
**New Document Size:** ~1530 lines (up from 969)
**Estimated Effort:** 4-5 hours

---

## Validation Checklist

After making changes, verify:

- [ ] Test code compiles (Swift syntax correct)
- [ ] Test patterns follow XCTest conventions
- [ ] Mock implementations realistic
- [ ] Fixtures cover typical scenarios
- [ ] Performance assertions reasonable
- [ ] State machine tests cover all transitions
- [ ] Cancellation tests accurate
- [ ] Cross-references resolve

---

**Document Version:** 1.0
**Created:** 2025-11-19
**Implements:** Phase 3 documentation update item #11
