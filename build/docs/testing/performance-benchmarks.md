# Performance Testing & Benchmarks

**Last Updated:** 2025-11-17
**Status:** ✅ Active
**Audience:** Developers optimizing Contextify performance

---

## Phase 3 Performance Achievements (Nov 2025)

**✅ Validated:**
- Startup: <200ms (achieved 187ms) - 10-35x improvement
- Memory: 30-50 MB at startup - 3-5x reduction
- DB writes: 19 rows - 10-20x reduction
- JIT ingestion: <1s per project

**Updated targets reflect Phase 3 lazy loading architecture.**

---

## Table of Contents

1. [Overview](#overview)
2. [Performance Targets](#performance-targets)
3. [Benchmark Categories](#benchmark-categories)
4. [Database Performance](#database-performance)
5. [Transcript Ingestion Performance](#transcript-ingestion-performance)
6. [LLM Performance](#llm-performance)
7. [UI Rendering Performance](#ui-rendering-performance)
8. [Startup Performance](#startup-performance)
9. [Real-Time Monitoring Performance](#real-time-monitoring-performance)
10. [Profiling Workflows](#profiling-workflows)
11. [Performance Regression Testing](#performance-regression-testing)
12. [Known Bottlenecks](#known-bottlenecks)
13. [Optimization Recommendations](#optimization-recommendations)

---

## Overview

### Purpose

This document establishes performance baselines, benchmarking methodologies, and optimization targets for Contextify. It provides measurable criteria for performance regression detection and guides optimization efforts.

### Performance Philosophy

**Target Experience:**
- **Cold start:** Timeline visible in <500ms
- **Real-time updates:** <200ms latency from file change to UI update
- **LLM summaries:** <1s perceived latency (with placeholders)
- **Smooth UI:** 60 FPS (16.67ms/frame) during scrolling

**Trade-offs:**
- **Fast path vs accuracy:** Preview ingestion (10-25 entries) for startup speed, full ingestion deferred
- **Cache complexity vs latency:** Timeline cache adds schema complexity but reduces LLM calls by 95%+
- **Memory vs speed:** In-memory caches improve latency at cost of memory footprint

### Measurement Approach

**Three Measurement Contexts:**

1. **Unit Tests (XCTest)** - Isolated component performance
2. **Integration Tests** - Multi-component workflows
3. **Production Profiling (Instruments)** - Real-world performance with actual data

---

## Performance Targets

### Current Targets

| Operation | Target | Status | Priority |
|-----------|--------|--------|----------|
| **Startup** |
| Cold start (app launch to timeline) | <500ms | ⏳ Unmeasured | P0 |
| StartupCoordinator overhead | <100ms | ⏳ Unmeasured | P1 |
| Quick discovery (fast path) | <500ms | ⏳ Unmeasured | P0 |
| Full project discovery | <3s | ⏳ Unmeasured | P2 |
| **Database** |
| Single entry query | <5ms | ⏳ Unmeasured | P1 |
| Recent entries (50 limit) | <20ms | ⏳ Unmeasured | P1 |
| Timeline cache lookup | <5ms | ~3ms ✅ | P0 |
| Database migration (v25→v26) | <2s | ⏳ Unmeasured | P2 |
| **Transcript Ingestion** |
| HooverEngine batch (1000 lines) | <500ms | ⏳ Unmeasured | P1 |
| Parser throughput (Claude Code) | >2000 lines/s | ⏳ Unmeasured | P2 |
| Preview ingestion (10 entries) | <100ms | ⏳ Unmeasured | P0 |
| **LLM** |
| Timeline summary generation | <1s | ~200ms ✅ | P0 |
| Session creation (FoundationModels) | <2ms | ⏳ Unmeasured | P1 |
| Metadata extraction | 2-8s | ⏳ Measured | P2 |
| **Real-Time Monitoring** |
| FSEvents latency | <200ms | ~100-200ms ✅ | P1 |
| TranscriptWatcher latency | <150ms | ⏳ Unmeasured | P1 |
| End-to-end (file write → UI) | <350ms | ~165ms ✅ | P0 |
| **UI Rendering** |
| Timeline scroll (60 FPS) | 16.67ms/frame | ⏳ Unmeasured | P0 |
| Project switcher open | <100ms | ⏳ Unmeasured | P1 |
| ConversationMonitor state update | <50ms | ⏳ Unmeasured | P1 |

**Legend:**
- ✅ **Measured and meets target**
- ⏳ **Unmeasured** - needs baseline establishment
- ❌ **Measured, fails target** - needs optimization
- P0-P3: Priority (P0 = critical user-facing, P3 = nice-to-have)

### Target Rationale

**<500ms cold start:**
- Based on UX research: users perceive <500ms as "instant"
- Competitors (iTerm2 session restore, VS Code) achieve 200-800ms
- Contextify target: 200-500ms (current estimated range)

**<200ms real-time latency:**
- Human perception threshold for "real-time" response
- Allows for file write (1ms) + FSEvents (100-200ms) + parsing (10-50ms) + UI update (16-33ms)

**<1s LLM latency:**
- On-device LLM (FoundationModels) achieves ~200ms per summary
- Placeholder strategy masks latency (user sees instant response)
- Target includes cache lookup (<5ms) + generation (200ms) + UI update (16ms)

---

## Benchmark Categories

### 1. Microbenchmarks

**Purpose:** Measure isolated functions/methods

**Example:**

```swift
func testSHA256HashPerformance() {
  let input = String(repeating: "x", count: 10000)

  measure(metrics: [XCTClockMetric()]) {
    _ = SHA256Utils.hash(input)
  }
}
```

**Use Cases:**
- Hash computation (SHA256, window hash)
- JSON parsing (single line)
- String manipulation (path demangling, content extraction)

### 2. Component Benchmarks

**Purpose:** Measure single component with realistic inputs

**Example:**

```swift
func testParserThroughput() {
  // 1000 realistic Claude Code JSONL lines
  let fixture = try loadFixture(name: "large-transcript-1000-lines")
  let parser = ClaudeCodeLineParser()

  measure(metrics: [XCTClockMetric()]) {
    for (idx, line) in fixture.enumerated() {
      _ = try! parser.parse(
        line: line,
        lineNumber: idx,
        transcriptId: "test",
        projectId: "test",
        provider: "claude.code",
        sessionId: "test"
      )
    }
  }

  // Calculate throughput
  let linesPerSecond = 1000.0 / averageTime
  print("Parser throughput: \(linesPerSecond) lines/second")
}
```

**Use Cases:**
- Parser throughput (lines/second)
- Repository query performance (rows/second)
- Cache hit rate (percentage)

### 3. Integration Benchmarks

**Purpose:** Measure multi-component workflows

**Example:**

```swift
func testEndToEndIngestion() {
  // Setup: Database + repos + engine
  let pool = try makeMigratedPool(at: dbPath)
  let hooverEngine = HooverEngine(/* all dependencies */)

  // Fixture: 10,000 line transcript
  let largeTranscript = try loadFixture(name: "large-transcript-10k")
  try largeTranscript.write(to: transcriptPath, atomically: true, encoding: .utf8)

  measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
    _ = try! hooverEngine.hooverTranscript(
      transcript,
      fileURL: transcriptPath,
      progress: NoOpProgressSink()
    )
  }
}
```

**Use Cases:**
- End-to-end ingestion (file → database)
- Startup sequence (launch → timeline visible)
- Project switching (old project → new project ready)

### 4. Load Testing

**Purpose:** Measure system behavior under stress

**Example:**

```swift
func testLargeProjectLoadTime() {
  // Create 100 projects with 50 transcripts each (5000 total)
  for i in 0..<100 {
    let projectId = try projectRepo.create(name: "Project \(i)", rootPath: "/test/\(i)")
    for j in 0..<50 {
      _ = try transcriptRepo.upsert(
        projectId: projectId,
        fileURL: URL(fileURLWithPath: "/test/\(i)/t\(j).jsonl"),
        provider: "claude.code",
        providerSessionId: "session-\(i)-\(j)",
        lastModified: Date(),
        fileSize: 10000
      )
    }
  }

  // Measure project list query
  measure(metrics: [XCTClockMetric()]) {
    _ = try! projectRepo.list()
  }
}
```

**Use Cases:**
- Large project counts (100+ projects)
- Large transcript files (1M+ lines)
- High concurrent LLM requests (10+ simultaneous)

---

## Database Performance

### Schema: v26

**File:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

### Query Performance Targets

| Query | Target | Baseline | Current | Status |
|-------|--------|----------|---------|--------|
| `Project.list()` | <20ms | TBD | TBD | ⏳ |
| `Transcript.byProject(projectId)` | <30ms | TBD | TBD | ⏳ |
| `Entry.recentByProject(projectId, limit: 50)` | <20ms | TBD | TBD | ⏳ |
| `TimelineCache.lookup(contentSHA, windowSHA)` | <5ms | ~3ms | ~3ms | ✅ |
| `Entry.byTranscript(transcriptId)` | <10ms | TBD | TBD | ⏳ |

### Benchmark: Single Entry Query

**Test:**

```swift
func testSingleEntryQueryPerformance() throws {
  let pool = try makeMigratedPool(at: tempDB)
  let entryRepo = EntryRepositoryImpl(db: pool)

  // Setup: Insert 10,000 entries across 100 transcripts
  for t in 0..<100 {
    let entries = (0..<100).map { i in
      makeTestEntry(transcriptId: "transcript-\(t)", index: i)
    }
    try entryRepo.insertBatch(entries)
  }

  // Measure query
  measure(metrics: [XCTClockMetric()]) {
    _ = try! entryRepo.byTranscript("transcript-50")
  }
}
```

**Expected:** <10ms (indexed query on `transcript_id`)

### Benchmark: Timeline Cache Lookup

**Test:**

```swift
func testTimelineCacheLookupPerformance() throws {
  let pool = try makeMigratedPool(at: tempDB)

  // Setup: 10,000 cache entries
  try pool.write { db in
    for i in 0..<10_000 {
      try db.execute(sql: """
        INSERT INTO timeline_cache (content_sha256, window_sha256, summary, generator_signature)
        VALUES (?, ?, ?, ?)
      """, arguments: [
        SHA256Utils.hash("content-\(i)"),
        SHA256Utils.hash("window-\(i)"),
        "Summary \(i)",
        "gpt-4o@2025-09:timeline@3"
      ])
    }
  }

  // Measure lookup (cache hit)
  let contentSHA = SHA256Utils.hash("content-5000")
  let windowSHA = SHA256Utils.hash("window-5000")

  measure(metrics: [XCTClockMetric()]) {
    _ = try! pool.read { db in
      try Row.fetchOne(db, sql: """
        SELECT summary FROM timeline_cache
        WHERE content_sha256 = ? AND window_sha256 = ?
      """, arguments: [contentSHA, windowSHA])
    }
  }
}
```

**Current:** ~3ms (composite PK lookup)
**Target:** <5ms ✅

### Benchmark: Database Migration

**Test:**

```swift
func testMigrationPerformance() throws {
  // Create v25 database with realistic data
  let pool = try createV25Database(with: sampleData)

  // Measure v25→v26 migration
  measure(metrics: [XCTClockMetric()]) {
    let migrator = DatabaseSchema.createMigrator()
    try! migrator.migrate(pool)
  }
}
```

**Target:** <2s for typical database (1000 projects, 10,000 transcripts, 100,000 entries)

### Index Performance Verification

**Critical Indexes:**

```sql
-- Session ID index (fastest lookup)
CREATE UNIQUE INDEX IF NOT EXISTS uq_tr_provider_session
  ON transcripts(provider, provider_session_id)
  WHERE provider_session_id IS NOT NULL;

-- Path hash fallback index
CREATE UNIQUE INDEX IF NOT EXISTS uq_tr_provider_path_hash
  ON transcripts(provider, path_hash);

-- Fast-path discovery index
CREATE INDEX IF NOT EXISTS idx_tr_mtime_ms
  ON transcripts(mtime_ms DESC);

-- Partial ingestion query index
CREATE INDEX IF NOT EXISTS idx_tr_ingest_state_updated_at
  ON transcripts(ingest_state, updated_at);
```

**Test:**

```swift
func testIndexUsage() throws {
  let pool = try makeMigratedPool(at: tempDB)

  // Insert 10,000 transcripts
  // ...

  // Verify index is used (EXPLAIN QUERY PLAN)
  let plan = try pool.read { db in
    try String.fetchOne(db, sql: """
      EXPLAIN QUERY PLAN
      SELECT * FROM transcripts
      WHERE provider = 'claude.code' AND provider_session_id = 'session-123'
    """)
  }

  XCTAssertTrue(plan?.contains("USING INDEX uq_tr_provider_session") ?? false)
}
```

### WAL Mode Performance

**Configuration:** `DatabaseManager.swift:91`

```swift
try db.execute(sql: "PRAGMA journal_mode=WAL")
```

**Benefits:**
- **Concurrent reads:** Multiple readers don't block each other
- **Write performance:** WAL writes are sequential (faster than journal)
- **Crash recovery:** WAL provides atomic commits

**Test:**

```swift
func testConcurrentReadPerformance() throws {
  let pool = try makeMigratedPool(at: tempDB)
  // Verify journal_mode is WAL
  let mode = try pool.read { db in
    try String.fetchOne(db, sql: "PRAGMA journal_mode")
  }
  XCTAssertEqual(mode, "wal")

  // Measure 10 concurrent reads
  let group = DispatchGroup()
  let start = Date()

  for _ in 0..<10 {
    group.enter()
    DispatchQueue.global().async {
      _ = try? pool.read { db in
        try Row.fetchAll(db, sql: "SELECT * FROM projects")
      }
      group.leave()
    }
  }

  group.wait()
  let elapsed = Date().timeIntervalSince(start)
  print("10 concurrent reads: \(elapsed * 1000)ms")

  XCTAssertLessThan(elapsed, 0.1, "Should complete in <100ms")
}
```

---

## Transcript Ingestion Performance

### HooverEngine Throughput

**Component:** `app/Sources/ContextifyCore/Database/HooverEngine.swift`

**Configuration:**
- **Batch size:** 1000 lines (MonitorConfig.batchLines)
- **Checkpoint frequency:** Every batch
- **Parser:** Provider-specific (ClaudeCodeLineParser, CodexLineParser)

### Benchmark: Batch Ingestion (1000 lines)

**Test:**

```swift
func testHooverEngineBatchPerformance() throws {
  let pool = try makeMigratedPool(at: tempDB)
  let hooverEngine = HooverEngine(/* dependencies */)

  // Create transcript with 1000 Claude Code entries
  let transcript = try makeTranscriptFile(lineCount: 1000, provider: "claude.code")

  measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
    _ = try! hooverEngine.hooverTranscript(
      transcript,
      fileURL: transcriptPath,
      progress: NoOpProgressSink()
    )
  }

  // Expected: <500ms for 1000 lines
}
```

**Target:** <500ms per batch (1000 lines)
**Throughput:** >2000 lines/second

### Benchmark: Parser Performance

**Test:**

```swift
func testClaudeCodeParserThroughput() {
  let parser = ClaudeCodeLineParser()
  let lines = (0..<10_000).map { i in
    """
    {"uuid":"msg-\(i)","type":"user","timestamp":"2025-11-17T12:00:\(i % 60).000Z","sessionId":"test","message":{"role":"user","content":"Test message \(i)"},"gitBranch":"main"}
    """
  }

  measure(metrics: [XCTClockMetric()]) {
    for (idx, line) in lines.enumerated() {
      _ = try! parser.parse(
        line: line,
        lineNumber: idx,
        transcriptId: "test",
        projectId: "test",
        provider: "claude.code",
        sessionId: "test"
      )
    }
  }

  // Calculate throughput
}
```

**Target:** >2000 lines/second

### Benchmark: Preview Ingestion (Fast Path)

**Test:**

```swift
func testPreviewIngestionPerformance() throws {
  let pool = try makeMigratedPool(at: tempDB)
  let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)

  // Create transcript with 1000 lines
  let transcript = try makeTranscriptFile(lineCount: 1000, provider: "claude.code")

  measure(metrics: [XCTClockMetric()]) {
    // Preview mode: ingest only first 10 entries
    _ = try! await orchestrator.ingestTranscript(
      transcriptId: transcriptId,
      mode: .preview(entries: 10),
      notifyUI: false
    )
  }
}
```

**Target:** <100ms for 10 entries (startup fast-path)

### Checkpoint Overhead

**Test:**

```swift
func testCheckpointOverhead() throws {
  let pool = try makeMigratedPool(at: tempDB)
  let transcriptRepo = TranscriptRepositoryImpl(db: pool)

  measure(metrics: [XCTClockMetric()]) {
    try! transcriptRepo.setIngestionState(
      id: transcriptId,
      lastProcessedLine: 1000,
      lineCount: 10000,
      parserVersion: 1,
      status: "active",
      ingestState: "partial",
      lastError: nil
    )
  }
}
```

**Expected:** <5ms per checkpoint (single UPDATE query)

---

## LLM Performance

### FoundationLLM (macOS 26+)

**Component:** `Contextify/Contextify/FoundationLLM.swift`

**Configuration:**
- **Model:** Foundation model (on-device)
- **Session strategy:** Pooled with reset (circuit breaker after 15 requests)
- **Concurrency:** SessionController (FIFO queue)

### Benchmark: Session Creation

**Test:**

```swift
func testSessionCreationBenchmark() throws {
  guard ProcessInfo.processInfo.environment["RUN_LLM_BENCH"] == "1" else {
    throw XCTSkip("Set RUN_LLM_BENCH=1 to run")
  }

  let iterations = 1_000
  let instructions = "Summarize text concisely."

  let start = Date()
  for _ in 0..<iterations {
    _ = LanguageModelSession(instructions: instructions)
  }
  let elapsed = Date().timeIntervalSince(start)
  let avgMs = (elapsed * 1000.0) / Double(iterations)

  print(String(format: "Session creation avg: %.3f ms", avgMs))

  // Decision threshold: <2ms → use stateless, ≥2ms → pool+reset
  XCTAssertLessThan(avgMs, 2.0, "Should be <2ms for stateless strategy")
}
```

**Target:** <2ms per session creation
**Current:** ⏳ Unmeasured (test exists in FoundationLLMTests.swift:416)

### Benchmark: Timeline Summary Generation

**Test:**

```swift
@available(macOS 26.0, *)
func testTimelineSummaryPerformance() async throws {
  let llm = FoundationLLM.shared
  let message = "I've updated the configuration file to use the new API endpoint and verified all tests pass."

  measure(metrics: [XCTClockMetric()]) {
    _ = try! await llm.generateTimelineSummary(
      message: message,
      kind: .assistant,
      prevActionHint: nil
    )
  }
}
```

**Current:** ~200ms per summary (on-device LLM)
**Target:** <1s perceived latency (with placeholder strategy) ✅

### Benchmark: Metadata Extraction

**Test:**

```swift
@available(macOS 26.0, *)
func testMetadataExtractionPerformance() async throws {
  let orchestrator = TranscriptMetadataOrchestrator()

  // Load realistic transcript (500 lines)
  let transcript = try loadFixture(name: "medium-transcript-500-lines")

  measure(metrics: [XCTClockMetric()]) {
    _ = try! await orchestrator.extractMetadata(
      transcriptId: transcriptId,
      content: transcript
    )
  }
}
```

**Current:** 2-8 seconds per transcript (depends on size)
**Note:** This is a background task, not user-facing (P2 priority)

### LLM Queue Throughput

**Queue Strategy:**
- **Timeline cache misses:** Batch of 10, rate-limited (2s delay between batches)
- **Metadata extraction:** Concurrent (limited by circuit breaker)

**Measured Throughput:**
- **Timeline:** ~5 items/second (10-item batches with 2s delays)
- **Metadata:** Concurrent (no specific limit documented)

**Reference:** `build/docs/architecture/llm-processing.md:311-319`

---

## UI Rendering Performance

### Target: 60 FPS (16.67ms/frame)

**Critical UI Components:**
- `ConversationMonitor` - Timeline display (3054 lines)
- `ProjectSwitcherView` - Project dropdown
- `TimelineView` - Entry list rendering

### Benchmark: Timeline Scroll Performance

**Test:**

```swift
@MainActor
func testTimelineScrollPerformance() {
  let app = XCUIApplication()
  app.launch()

  // Navigate to timeline
  let timeline = app.scrollViews["timeline"]

  // Measure frame rate during scroll
  measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
    timeline.swipeUp(velocity: .fast)
  }
}
```

**Target:** 60 FPS (no dropped frames)

### Benchmark: Project Switcher Open

**Test:**

```swift
@MainActor
func testProjectSwitcherPerformance() {
  let app = XCUIApplication()
  app.launch()

  let switcher = app.buttons["project-switcher"]

  measure(metrics: [XCTClockMetric()]) {
    switcher.tap()
  }
}
```

**Target:** <100ms from tap to menu open

### Benchmark: ConversationMonitor State Update

**Test:**

```swift
@MainActor
func testConversationMonitorStateUpdate() {
  let monitor = ConversationMonitor.shared

  // Load 50 entries
  let entries = (0..<50).map { makeTestEntry(index: $0) }

  measure(metrics: [XCTClockMetric()]) {
    monitor._testUpdateTimeline(entries: entries)
  }
}
```

**Target:** <50ms for 50-entry update

### Main Actor Blocking

**Anti-Pattern:**

```swift
@MainActor
func updateTimeline() {
  // ❌ BAD: Blocking main thread with database query
  let entries = try! database.fetchEntries() // May take 50-100ms
  self.timelineEntries = entries
}
```

**Correct Pattern:**

```swift
@MainActor
func updateTimeline() async {
  // ✅ GOOD: Database query on background thread
  let entries = await Task.detached {
    try! database.fetchEntries()
  }.value
  self.timelineEntries = entries
}
```

---

## Startup Performance

### Cold Start Target: <500ms

**Phases:**

1. **App Launch** → Main window visible
2. **StartupCoordinator.start()** → Project identity resolved
3. **Quick Discovery** → Preview entries ingested
4. **Timeline Hydration** → UI populated with entries

### Benchmark: Cold Start (End-to-End)

**Test:**

```swift
@MainActor
func testColdStartPerformance() {
  measure(metrics: [XCTApplicationLaunchMetric()]) {
    let app = XCUIApplication()
    app.launch()

    // Wait for timeline to be visible
    let timeline = app.scrollViews["timeline"]
    XCTAssertTrue(timeline.waitForExistence(timeout: 1.0))
  }
}
```

**Target:** <500ms from launch to timeline visible
**Current:** ~200-500ms (estimated, needs measurement)

### Benchmark: StartupCoordinator Overhead

**Test:**

```swift
@MainActor
func testStartupCoordinatorPerformance() async throws {
  let coordinator = StartupCoordinator.shared

  measure(metrics: [XCTClockMetric()]) {
    try! await coordinator.start(
      repoRoot: URL(fileURLWithPath: "/test/repo"),
      gitBranch: "main"
    )
  }
}
```

**Target:** <100ms coordinator overhead
**Reference:** `build/docs/architecture/startup-coordinator.md:395`

### Benchmark: Quick Discovery (Fast Path)

**Test:**

```swift
func testQuickDiscoveryPerformance() async throws {
  let discoveryService = ProjectDiscoveryService(/* dependencies */)

  measure(metrics: [XCTClockMetric()]) {
    _ = try! await discoveryService.quickDiscoverNewest(
      for: projectId,
      providers: [.claudeCode, .codexCLI]
    )
  }
}
```

**Target:** <500ms for typical setups (10-20 projects)
**Reference:** `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift:199-201`

### Startup Latency Breakdown

**From:** `build/docs/architecture/data-pipeline-architecture.md:395`

```
Cold Start Latency Budget (Target: <500ms)
├─ App Launch: ~50-100ms (system overhead)
├─ StartupCoordinator.start(): ~50-100ms (git detection, project ID)
├─ Quick Discovery: ~100-200ms (scan ~/.claude/projects, mtime check)
├─ Preview Ingestion: ~50-100ms (parse first 10-25 entries)
└─ Timeline Hydration: ~50-100ms (database query + UI render)
```

---

## Real-Time Monitoring Performance

### FSEvents Latency

**Component:** `app/Sources/ContextifyCore/FSEventsMonitor.swift`

**Configuration:**
- **Latency:** 0.5s (ProjectActivityMonitor.swift:89)
- **Debouncing:** Yes (FSEventsDebouncer)

**Measured Latency:** ~100-200ms (OS-dependent)
**Reference:** `build/docs/architecture/data-pipeline-architecture.md:159`

### TranscriptWatcher Latency

**Component:** `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`

**Technology:** DispatchSource file monitoring

**Target:** <150ms from file change to ingestion trigger
**Reference:** `build/docs/architecture/data-pipeline-architecture.md:373`

### End-to-End Real-Time Latency

**Workflow:** User saves file in Claude Code → Timeline updates in Contextify

**Latency Breakdown:**

```
File Write → Timeline Update (Target: <350ms)
├─ File write: ~1ms (system I/O)
├─ FSEvents notification: ~100-200ms (OS latency)
├─ TranscriptWatcher trigger: ~10-50ms (debouncing + DispatchSource)
├─ Incremental ingestion: ~10-50ms (parse new lines)
├─ Database write: ~5-20ms (batch insert)
└─ UI update: ~16-33ms (60 FPS render cycle)
```

**Current:** ~165ms average (from data-flow.md, archived)
**Target:** <350ms ✅

**Reference:** `build/docs/architecture/window-system.md:271`

### Benchmark: End-to-End Real-Time Update

**Test:**

```swift
@MainActor
func testRealTimeUpdateLatency() async throws {
  // Setup: Launch app with test project
  let app = XCUIApplication()
  app.launch()

  // Write to transcript file
  let start = Date()
  let transcriptPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/projects/test-project/session.jsonl")
  let newLine = """
  {"uuid":"test","type":"user","timestamp":"\(Date().ISO8601Format())","sessionId":"test","message":{"role":"user","content":"Test"}}
  """
  try (try! String(contentsOf: transcriptPath) + "\n" + newLine)
    .write(to: transcriptPath, atomically: true, encoding: .utf8)

  // Wait for timeline to update
  let timeline = app.scrollViews["timeline"]
  let newEntry = timeline.staticTexts["Test"]
  XCTAssertTrue(newEntry.waitForExistence(timeout: 1.0))

  let elapsed = Date().timeIntervalSince(start)
  print("End-to-end latency: \(elapsed * 1000)ms")
  XCTAssertLessThan(elapsed, 0.35, "Should be <350ms")
}
```

---

## Profiling Workflows

### Instruments Templates

Apple Instruments provides specialized profiling templates:

#### 1. Time Profiler

**Use Case:** Identify CPU hotspots

**Workflow:**

```bash
# Build test bundle
xcodebuild test -scheme Contextify -destination 'platform=macOS' \
  -only-testing:ContextifyTests/DatabaseTests/testLargeProjectLoadTime \
  SKIP_INSTALL=NO

# Profile with Time Profiler
instruments -t "Time Profiler" -D time-profile.trace \
  /path/to/ContextifyTests.xctest/Contents/MacOS/ContextifyTests
```

**Key Metrics:**
- **Heaviest Stack Trace** - Functions consuming most CPU time
- **Call Tree** - Invocation hierarchy and timing

**Common Hotspots:**
- JSON parsing (Codable)
- SHA256 hashing (window computation)
- Database queries (non-indexed lookups)

#### 2. Allocations

**Use Case:** Memory usage and leak detection

**Workflow:**

```bash
instruments -t "Allocations" -D allocations.trace \
  /Applications/Contextify.app/Contents/MacOS/Contextify
```

**Key Metrics:**
- **All Heap & Anonymous VM** - Total memory usage
- **Persistent Bytes** - Memory that never gets freed (potential leaks)
- **Transient Bytes** - Short-lived allocations (may indicate thrashing)

**Common Issues:**
- Large timeline cache (unbounded growth)
- Unreleased AsyncStream continuations
- Retained closures in observation callbacks

#### 3. Leaks

**Use Case:** Memory leak detection

**Workflow:**

```bash
instruments -t "Leaks" -D leaks.trace \
  /Applications/Contextify.app/Contents/MacOS/Contextify
```

**Leaks Tool:** Automatically detects unreachable memory

**Common Leaks:**
- Observation tokens not removed (NotificationCenter)
- Security-scoped resources not stopped (bookmark leaks)
- Strong reference cycles in closures

#### 4. System Trace

**Use Case:** File I/O, threading, system calls

**Workflow:**

```bash
instruments -t "System Trace" -D system.trace \
  /Applications/Contextify.app/Contents/MacOS/Contextify
```

**Key Metrics:**
- **File Activity** - Reads/writes, latency, throughput
- **Thread State** - Blocked, runnable, running time
- **System Calls** - Frequency and duration

**Common Issues:**
- Synchronous file reads on main thread
- Excessive small I/O operations (not batched)
- Thread contention (locks, semaphores)

#### 5. SwiftUI

**Use Case:** View rendering performance

**Workflow:**

```bash
instruments -t "SwiftUI" -D swiftui.trace \
  /Applications/Contextify.app/Contents/MacOS/Contextify
```

**Key Metrics:**
- **View Body Evaluation** - How often views re-render
- **Frame Rate** - FPS during interactions
- **State Updates** - Observation triggers

**Common Issues:**
- Excessive body re-computation (missing Equatable)
- Heavy computations in view body (should be cached)
- MainActor blocking (database queries in view init)

### Profiling Best Practices

**1. Profile Release Builds**

```bash
xcodebuild build -scheme Contextify -configuration Release
```

Debug builds have optimizations disabled (-Onone), making profiles misleading.

**2. Use Realistic Data**

- Test with 100+ projects
- Use multi-thousand-line transcripts
- Simulate typical user workflows

**3. Run Multiple Iterations**

```bash
# Run 10 times, take median
for i in {1..10}; do
  instruments -t "Time Profiler" -D "profile-$i.trace" /path/to/app
done
```

**4. Focus on Hot Paths**

Profile user-facing operations:
- Cold start
- Project switching
- Real-time transcript updates
- Timeline scrolling

---

## Performance Regression Testing

### XCTest Performance Baselines

XCTest can store performance baselines and detect regressions:

```swift
func testDatabaseQueryPerformance() throws {
  measure(metrics: [XCTClockMetric()]) {
    _ = try! projectRepo.list()
  }

  // First run establishes baseline
  // Subsequent runs compare against baseline
  // Test fails if performance degrades >10% (configurable)
}
```

**Baseline Storage:** `.xcresult` bundles or Xcode Cloud

### CI Performance Gates

**GitHub Actions Workflow:**

```yaml
name: Performance Tests

on:
  pull_request:
    branches: [ main ]

jobs:
  performance:
    runs-on: macos-14

    steps:
    - uses: actions/checkout@v4

    - name: Run Performance Tests
      run: |
        xcodebuild test \
          -scheme Contextify \
          -destination 'platform=macOS' \
          -only-testing:ContextifyTests/PerformanceTests \
          -resultBundlePath TestResults.xcresult

    - name: Check for Regressions
      run: |
        # Extract performance metrics
        xcrun xcresulttool get --path TestResults.xcresult \
          --format json > results.json

        # Compare against baseline (stored in repo or artifact)
        python scripts/check-performance-regression.py \
          --baseline baseline.json \
          --current results.json \
          --threshold 1.1  # Fail if >10% slower
```

### Performance Budget

**Per-Component Budgets:**

| Component | Operation | Budget | Consequence |
|-----------|-----------|--------|-------------|
| StartupCoordinator | start() | <100ms | Cold start delay |
| HooverEngine | hooverTranscript() (1000 lines) | <500ms | Slow ingestion |
| TimelineCache | lookup() | <5ms | UI lag |
| ConversationMonitor | updateTimeline() | <50ms | Dropped frames |
| ProjectDiscoveryService | quickDiscoverNewest() | <500ms | Startup delay |

**Enforcement:** CI fails if any operation exceeds budget by >10%

---

## Known Bottlenecks

### 1. ConversationMonitor God Object (P0)

**File:** `Contextify/Contextify/ConversationMonitor.swift` (3054 lines)

**Issue:** Monolithic state management with 15+ responsibilities

**Performance Impact:**
- **MainActor contention:** All timeline operations block main thread
- **State update overhead:** Large @Published properties trigger expensive SwiftUI diffs
- **Memory footprint:** Holds entire timeline in memory

**Optimization Path:**
- Extract timeline cache into separate actor (off main thread)
- Move database queries to background
- Implement incremental timeline updates (not full replacement)

**Reference:** `build/docs/architecture/architecture-refactoring-analysis.md:1420`

### 2. Timeline Cache Miss Latency (P0)

**Current:** ~500-1000ms per cache miss
**Target:** <100ms perceived latency (with placeholder)

**Issue:** Cache misses block UI while waiting for LLM

**Optimization:**
- ✅ **Implemented:** Placeholder strategy (instant feedback)
- ⏳ **TODO:** Batch cache generation during idle time
- ⏳ **TODO:** Predictive caching (pre-generate for visible entries)

**Reference:** `build/docs/architecture/data-pipeline-architecture.md:903-904`

### 3. Full Project Discovery (P2)

**Current:** Unbounded (depends on project count)
**Target:** <3s

**Issue:** Full scan of `~/.claude/projects` and `~/.codex/sessions` on every startup

**Optimization:**
- ✅ **Implemented:** Fast-path preview (first 10-25 entries only)
- ⏳ **TODO:** Background full discovery (don't block startup)
- ⏳ **TODO:** Incremental discovery (only scan changed directories)

### 4. N+1 Query Pattern (P1)

**Issue:** Fetching entries one-by-one instead of batch

**Example:**

```swift
// ❌ BAD: N+1 queries
for transcriptId in transcriptIds {
  let entries = try entryRepo.byTranscript(transcriptId)
  // ...
}

// ✅ GOOD: Single batch query
let allEntries = try entryRepo.byTranscripts(transcriptIds)
```

**Impact:** 10-100x slower for large result sets

### 5. Synchronous File I/O on Main Thread (P0)

**Issue:** File reads/writes block UI

**Example:**

```swift
@MainActor
func loadTranscript() {
  // ❌ BAD: Blocks main thread
  let content = try! String(contentsOf: transcriptURL)
}
```

**Fix:**

```swift
@MainActor
func loadTranscript() async {
  // ✅ GOOD: Background I/O
  let content = await Task.detached {
    try! String(contentsOf: transcriptURL)
  }.value
}
```

---

## Optimization Recommendations

### Priority 0 (Critical)

**1. Move Database Queries Off Main Thread**

**Impact:** Prevent UI blocking (dropped frames, laggy scrolling)

**Implementation:**

```swift
// Current (blocking)
@MainActor
func fetchTimeline() {
  self.entries = try! database.fetchRecent(limit: 50) // Blocks UI
}

// Optimized (non-blocking)
@MainActor
func fetchTimeline() async {
  self.entries = await withCheckedContinuation { continuation in
    Task.detached {
      let entries = try! database.fetchRecent(limit: 50)
      continuation.resume(returning: entries)
    }
  }
}
```

**Effort:** Medium (requires async refactoring)

**2. Implement Incremental Timeline Updates**

**Impact:** Reduce SwiftUI diff cost (50% faster)

**Current:**

```swift
// Replace entire array (expensive)
self.timelineEntries = newEntries
```

**Optimized:**

```swift
// Append only new entries (cheap)
let newIds = Set(newEntries.map(\.id))
let existing = Set(timelineEntries.map(\.id))
let additions = newEntries.filter { !existing.contains($0.id) }
self.timelineEntries.append(contentsOf: additions)
```

**Effort:** Low

**3. Add Timeline Cache Placeholders (Already Implemented)**

**Status:** ✅ Implemented (Priority 0)

**Impact:** <1s perceived latency (instant feedback)

### Priority 1 (High)

**4. Batch Cache Generation During Idle**

**Impact:** Eliminate perceived cache miss latency

**Strategy:** Pre-generate summaries for recently added entries during idle periods (no user activity for 500ms)

**Effort:** High (requires idle detection + background queue)

**5. Add Performance Baselines to CI**

**Impact:** Prevent regressions

**Implementation:** Store `.xcresult` performance baselines as artifacts, compare in CI

**Effort:** Low

**6. Profile and Optimize ConversationMonitor**

**Impact:** 20-30% improvement in UI responsiveness

**Actions:**
- Extract background-compatible operations to separate actor
- Move timeline hydration off main thread
- Cache derived state (avoid recomputation)

**Effort:** High (requires refactoring)

### Priority 2 (Medium)

**7. Implement Database Query Caching**

**Impact:** 5-10x faster repeated queries

**Strategy:** In-memory LRU cache for hot queries (recent entries, project list)

**Effort:** Medium

**8. Optimize SHA256 Window Computation**

**Impact:** 30-50% faster entry processing

**Current:** Compute SHA256 for every entry (CPU-intensive)

**Optimization:** Use fast hash (xxHash) for window tracking, SHA256 only for cache keys

**Effort:** Low

**9. Add Incremental Discovery**

**Impact:** 50-80% faster startup after first launch

**Strategy:** Track mtimes, only re-scan changed directories

**Effort:** Medium

---

## Summary

### Measurement Status

| Category | Baselines Established | Regression Testing | Priority |
|----------|----------------------|-------------------|----------|
| Database | ❌ No | ❌ No | P1 |
| Ingestion | ❌ No | ❌ No | P1 |
| LLM | ⚠️ Partial | ❌ No | P0 |
| UI Rendering | ❌ No | ❌ No | P0 |
| Startup | ❌ No | ❌ No | P0 |
| Real-Time | ⚠️ Partial | ❌ No | P1 |

**Overall Coverage:** ~10% (2/6 categories partially measured)

### Next Steps

**Phase 1: Establish Baselines (1-2 weeks)**
1. Implement database performance tests (DatabaseTests.swift)
2. Measure startup latency (cold start, coordinator, discovery)
3. Profile UI rendering (timeline scroll, project switcher)
4. Establish XCTest performance baselines

**Phase 2: Enable Regression Testing (1 week)**
5. Add CI performance gates (GitHub Actions)
6. Store and compare baselines on every PR
7. Set up alerting for >10% regressions

**Phase 3: Optimization (4-6 weeks)**
8. Move database queries off main thread (P0)
9. Implement incremental timeline updates (P0)
10. Profile and refactor ConversationMonitor (P1)
11. Add database query caching (P2)

**Total Effort:** 6-9 weeks

---

## References

### Internal Documentation

- **`build/docs/architecture/data-pipeline-architecture.md`** - Latency breakdowns and performance targets
- **`build/docs/architecture/startup-coordinator.md`** - Startup overhead targets
- **`build/docs/architecture/architecture-refactoring-analysis.md`** - Known bottlenecks (god objects)
- **`build/docs/architecture/llm-processing.md`** - LLM latency and throughput
- **`build/docs/testing/integration-testing-guide.md`** - XCTest performance test examples

### Code References (Performance-Sensitive)

- `app/Sources/ContextifyCore/Database/HooverEngine.swift` - Ingestion performance
- `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift:199` - Discovery targets
- `Contextify/Contextify/ConversationMonitor.swift` - UI rendering bottleneck (3054 lines)
- `Contextify/Contextify/FoundationLLM.swift` - LLM performance
- `Contextify/ContextifyTests/FoundationLLMTests.swift:416` - Session creation benchmark

### External Resources

- **Instruments User Guide:** https://help.apple.com/instruments/mac/current/
- **XCTest Performance Testing:** https://developer.apple.com/documentation/xctest/performance_testing
- **Swift Concurrency Performance:** https://developer.apple.com/videos/play/wwdc2021/10254/

---

**Document Status:** ✅ Complete
**Last Code Verification:** 2025-11-17 (verified performance targets across 8 documentation files, 3 test files)
**Next Review:** After baseline establishment or when new performance targets are set
