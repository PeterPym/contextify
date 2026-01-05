# Performance Audit Plan for Contextify

**Created:** 2026-01-02
**Branch:** `feature/performance-audit-2026-01`
**Status:** Planning

---

## Executive Summary

Contextify is a macOS SwiftUI HUD that monitors Claude Code/Codex CLI conversation transcripts with real-time LLM-powered summaries. Following the successful fix of P0 bugs related to UI lag during ingest (file watcher events on main thread, stuck loading spinner), this document presents a comprehensive, proactive performance optimization plan.

**Primary Goal:** The initial ingest experience must never feel sluggish or slow down the machine.

**Secondary Goal:** If we cannot perform both UI responsiveness and background work simultaneously, we must pause tasks and communicate clearly (status bar, settings tab showing indexing state/progress/ETA).

**Strategic Value:** The Linux engine is shipping soon. Optimizations to shared code (ContextifyCore) benefit both macOS and Linux platforms, providing 2-3x impact.

---

## Architecture Overview

### Shared vs Mac-Only Code

The codebase is structured with explicit platform separation:

**Shared Core (ContextifyCore) - Benefits Both Platforms:**

| Component | File | Performance Role |
|-----------|------|------------------|
| HooverEngine | `Database/HooverEngine.swift` | Streaming JSONL parser, batch processing |
| TranscriptParsers | `Database/TranscriptParsers.swift` | Line-by-line parsing, metadata extraction |
| DatabaseSchema | `Database/DatabaseSchema.swift` | Schema v33, indexes |
| Repositories | `Database/Repositories.swift` | DB access patterns |
| PathNormalizer | `Database/PathNormalizer.swift` | Path canonicalization |
| LightweightDiscoveryService | `Discovery/LightweightDiscoveryService.swift` | Stat-only scanning |
| ProjectIdentity | `ProjectIdentity.swift` | Project resolution caching |

**Linux-Only (ContextifyIngestionCore):**
- Platform abstractions (CrossPlatformLogger, CrossPlatformCrypto, PlatformSandbox)
- ContextifyIngestionCLI executable

**Mac-Only (UI Layer):**

| Component | File | Performance Role |
|-----------|------|------------------|
| ConversationMonitor | `Contextify/Contextify/ConversationMonitor.swift` | Timeline state, UI coordination |
| TimelineCacheMissGenerator | `Contextify/Contextify/TimelineCacheMissGenerator.swift` | LLM queue |
| TranscriptWatcher | `Database/TranscriptWatcher.swift` | File monitoring (DispatchSource) |
| FastPathIngestionCoordinator | `Projects/FastPathIngestionCoordinator.swift` | Preview/completion orchestration |
| AppStateOrchestrator | `Orchestration/AppStateOrchestrator.swift` | App lifecycle state machine |

### Performance-Critical Code Paths

1. **Startup Path** (<200ms target, achieved 187ms)
   - LightweightDiscoveryService.discoverProjectsLightweight() - stat-only scan
   - TranscriptOrchestrator.updateProjectsMetadataOnly() - 19 row updates

2. **JIT Ingest Path** (on project selection, <1s target)
   - FastPathIngestionCoordinator.ingestProjectJIT()
   - HooverEngine.hooverTranscript() - streaming 1000-line batches
   - TranscriptWatcher.watch() - file monitoring setup

3. **Real-time Updates Path** (<350ms total latency)
   - TranscriptWatcher event -> debounce (150ms) -> HooverEngine -> DB -> UI

4. **LLM Summarization Path** (background, ~200ms/item)
   - TimelineCacheMissGenerator queue -> FoundationLLM -> timeline_cache

---

## Performance Dimensions

### 1. UI Responsiveness (Main Thread Blocking)
- **Status:** P0 fix applied - watcher events moved to background queue
- **Remaining risks:** Heavy SwiftUI view updates, large timeline re-renders
- **Metrics:** Main thread gaps >100ms, window control responsiveness

### 2. Ingest Throughput (transcripts/second)
- **Current:** ~1000 lines/batch, streaming design
- **Bottlenecks:** Per-entry project resolution (P0 fix added caching)
- **Metrics:** Lines/second, entries/second, batch commit time

### 3. Memory Usage During Bulk Ingest
- **Current:** O(batch_size) ~1MB for 1000 entries
- **Risks:** Large transcripts (10k+ entries), many concurrent projects
- **Metrics:** Peak memory during first-run, memory per transcript

### 4. Database Write Efficiency
- **Current:** 1000-line batch commits, WAL mode
- **Bottlenecks:** SQLITE_BUSY under concurrent load
- **Metrics:** Commit latency, lock contention frequency

### 5. LLM Queue Processing
- **Current:** Sequential (FoundationLLM limitation), LIFO priority
- **Bottlenecks:** Single-threaded, viewport-aware pruning overhead
- **Metrics:** Queue depth, items/second, cache hit rate

### 6. File Watcher Efficiency
- **Current:** DispatchSource per-file, 150ms debounce
- **Risks:** FD exhaustion with many watchers (tiered budget exists)
- **Metrics:** Active watcher count, FD usage, event coalescing rate

### 7. Project Switching Speed
- **Current:** <100-200ms (ConversationMonitor state reset)
- **Bottlenecks:** Phase state management, watcher teardown/setup
- **Metrics:** Switch latency, timeline hydration time

### 8. Search/Query Performance
- **Current:** FTS5 indexes for summaries, covering indexes for feeds
- **Bottlenecks:** Large result sets, complex queries
- **Metrics:** Query latency by type, index hit rates

### 9. Startup Time
- **Current:** <200ms (lightweight scan, no ingestion)
- **Risks:** DB pool initialization, migration checks
- **Metrics:** Cold start to UI ready, hot start time

---

## Phased Optimization Plan

### Phase 1: Measurement and Baselines (1-2 days)

**Goal:** Establish repeatable benchmarks and baseline metrics.

**Tasks:**

1. **Create Benchmark Fixtures**
   - Synthetic transcripts: 100 lines, 1000 lines, 10000 lines, 50000 lines
   - Multiple project configurations: 5, 20, 50, 100 projects
   - Store in `scripts/performance/fixtures/`

2. **Implement Performance Test Harness**
   - Script: `scripts/performance/run-perf-suite.sh`
   - Measures: startup, JIT ingest, bulk ingest, project switch, search
   - Output: JSON metrics for tracking over time

3. **Baseline Current Performance**
   - Run harness on main branch
   - Document baseline in `build/docs/performance/baseline-2026-01.md`
   - Key metrics: startup time, ingest rate, memory peak, query latencies

4. **Add Instruments Templates**
   - Create Time Profiler template for ingest path
   - Create Memory Allocations template for bulk operations
   - Document usage in `build/docs/performance/profiling-guide.md`

**Linux Engine Impact:** Harness should be portable; ingest benchmarks apply directly.

---

### Phase 2: Quick Wins - High Impact, Low Effort (3-5 days)

**Goal:** Immediate performance improvements with minimal code changes.

**Tasks:**

1. **Database Index Audit** (Shared)
   - Review existing indexes against actual query patterns
   - Add composite index for `(transcript_id, timestamp)` if missing
   - Validate covering index usage for feed queries
   - File: `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

2. **HooverEngine Project Resolution Cache Expansion** (Shared)
   - Current: Per-transcript cache, fetches all projects on first miss
   - Improvement: Pre-warm cache during FastPath initialization
   - Reduce cold-path DB queries
   - File: `app/Sources/ContextifyCore/Database/HooverEngine.swift:286-622`

3. **Batch Size Tuning** (Shared)
   - Current: 1000 lines/batch, 1000 lines/checkpoint
   - Experiment: 500, 2000, 5000 batch sizes
   - Measure commit latency vs memory tradeoff
   - Configuration: `MonitorConfig` in HooverEngine.swift

4. **TranscriptWatcher Debounce Tuning** (Mac)
   - Current: 150ms debounce
   - Experiment: 100ms, 200ms, 300ms
   - Balance responsiveness vs event coalescing
   - File: `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift:29`

5. **Enable WAL Checkpointing** (Shared)
   - Add explicit WAL checkpoint after bulk ingest
   - Prevent WAL file growth during heavy operations
   - File: `app/Sources/ContextifyCore/Database/DatabaseManager.swift`

6. **LLM Queue Prefetch** (Mac)
   - Prefetch summaries for entries just outside viewport
   - Reduce visible stutter on scroll
   - File: `Contextify/Contextify/TimelineCacheMissGenerator.swift`

**Linux Engine Impact:** Items 1-5 directly improve Linux CLI performance.

---

### Phase 3: Architectural Improvements (1-2 weeks)

**Goal:** Structural changes for better concurrency and throughput.

**Tasks:**

1. **Pipeline Parallelization** (Shared)
   - Current: Sequential parsing -> DB write
   - Improvement: Overlap parsing batch N with DB write batch N-1
   - Use Swift async/await with task groups
   - File: `app/Sources/ContextifyCore/Database/HooverEngine.swift`

2. **Streaming Timeline Load** (Mac)
   - Current: Wait for all 50 entries before render
   - Improvement: Render batches of 10 as they load
   - Use AsyncStream for progressive UI updates
   - Files: `ConversationMonitor.swift`, `TimelineDataLoader.swift`

3. **Concurrent Discovery** (Shared)
   - Current: Claude and Codex scanned sequentially
   - Improvement: Parallel discovery with withTaskGroup
   - File: `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift`

4. **Incremental Discovery** (Shared)
   - Current: Full scan on every refresh
   - Improvement: FSEvents-based incremental updates
   - Only scan changed directories
   - Files: `LightweightDiscoveryService.swift`, `ProjectActivityMonitor.swift`

5. **DatabaseWriteQueue Optimization** (Shared)
   - Current: Retry with backoff on SQLITE_BUSY
   - Improvement: Batch coalescing, write queuing
   - Reduce lock contention during concurrent operations
   - File: `app/Sources/ContextifyCore/Database/DatabaseWriteQueue.swift`

6. **FastPath Worker Pool Tuning** (Mac/Shared)
   - Current: 4 concurrent workers
   - Experiment: Dynamic pool sizing based on system load
   - Consider CPU core count and available memory
   - File: `app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift:18`

**Linux Engine Impact:** Items 1, 3, 4, 5 directly apply. Item 6 principles apply.

---

### Phase 4: Low-Level Optimizations (1-2 weeks)

**Goal:** Fine-grained performance tuning.

**Tasks:**

1. **JSONL Parser Optimization** (Shared)
   - Profile current JSON decoding overhead
   - Consider lazy decoding for large content blocks
   - Optimize hot paths in TranscriptParsers
   - File: `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

2. **Content Hash Optimization** (Shared)
   - Current: SHA256 for every entry
   - Improvement: Incremental hashing, cache intermediate results
   - File: `app/Sources/ContextifyCore/Database/KeyGeneration.swift`

3. **Memory Pool for Entries** (Shared)
   - Pre-allocate EntryInsert arrays for batch processing
   - Reduce allocation churn during bulk ingest
   - File: `app/Sources/ContextifyCore/Database/HooverEngine.swift`

4. **SQL Query Optimization** (Shared)
   - EXPLAIN QUERY PLAN for all hot-path queries
   - Optimize feed queries, session queries, search queries
   - Add/adjust indexes based on findings
   - Files: `Repositories.swift`, `TranscriptOrchestrator.swift`

5. **String Handling Optimization** (Shared)
   - Audit String allocations in parsing hot path
   - Use Substring where possible
   - Avoid unnecessary UTF-8 conversions
   - Files: `TranscriptParsers.swift`, `HooverEngine.swift`

6. **LLM Response Caching** (Mac)
   - Improve cache hit detection speed
   - Consider in-memory LRU cache for frequent lookups
   - File: `TranscriptOrchestrator.swift` (getCachedTimeline)

**Linux Engine Impact:** Items 1-5 directly improve Linux CLI performance.

---

### Phase 5: User Communication Improvements (3-5 days)

**Goal:** Clear feedback when background work affects performance.

**Tasks:**

1. **Status Bar Enhancements** (Mac)
   - Show indexing progress during first-run ingest
   - Display queue depth and ETA for LLM processing
   - Indicate when system is busy vs idle
   - Files: `StatusBarView.swift`, `StatusBarViewModel.swift`

2. **Settings Tab - Indexing Status** (Mac)
   - New panel showing per-project ingest state
   - Display: total transcripts, indexed, pending, errors
   - ETA for completion
   - Allow pause/resume of background indexing
   - Files: New UI components in `Contextify/Contextify/Settings/`

3. **Progress Notifications** (Mac)
   - System notification when bulk ingest completes
   - Option to disable (for power users)
   - File: New notification helper

4. **Throttle Detection** (Mac)
   - Detect when system is under load (thermal, memory pressure)
   - Auto-pause non-critical background work
   - Surface status to user
   - File: New system monitoring component

5. **Ingest Progress Protocol** (Shared)
   - Enhance IngestProgressSink for richer reporting
   - Add: estimated time remaining, throughput metrics
   - File: `app/Sources/ContextifyCore/Database/IngestProgress.swift`

**Linux Engine Impact:** Item 5 benefits CLI progress reporting.

---

## Key Files Reference

### Architecture Documentation

| File | Description |
|------|-------------|
| `build/docs/architecture/ingestion-workflow.md` | Complete ingest pipeline flow |
| `build/docs/architecture/data-pipeline-architecture.md` | System overview, 5 detail levels |
| `build/docs/architecture/llm-processing.md` | LLM queue architecture |
| `build/docs/architecture/conversation-monitor-state.md` | Timeline state management |
| `build/docs/components/timeline-cache.md` | LLM caching strategy |

### Investigation Documents (from P0 fix session)

| File | Description |
|------|-------------|
| `/tmp/ingest-ui-lag-complete-investigation-2026-01-01.md` | Root cause analysis of P0 bugs |
| `/tmp/ingestion-log-analysis.md` | Log analysis showing race condition |
| `/tmp/p0-ingest-fix-implementation-plan.md` | Implementation details for fixes |
| `/tmp/p0-ingest-fix-validation-results.md` | Before/after comparison |
| `/tmp/review-loop-p0-ingest-fix/` | All review loop artifacts |

### Core Implementation Files

| File | Description | Linux? |
|------|-------------|--------|
| `app/Sources/ContextifyCore/Database/HooverEngine.swift` | Streaming parser, batch processing | Yes |
| `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift` | File monitoring, debouncing | No |
| `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` | JSONL parsing | Yes |
| `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` | High-level DB coordination | Yes |
| `app/Sources/ContextifyCore/Database/DatabaseManager.swift` | Connection pool, WAL | Yes |
| `app/Sources/ContextifyCore/Database/DatabaseWriteQueue.swift` | Write serialization | Yes |
| `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift` | Stat-only scanning | Yes |
| `app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift` | Preview/completion | No |
| `Contextify/Contextify/ConversationMonitor.swift` | Timeline UI state | No |
| `Contextify/Contextify/TimelineCacheMissGenerator.swift` | LLM queue | No |

---

## Starter Prompt for Fresh Session

Use this prompt to kick off the performance optimization work in a fresh Claude Code session:

---

```
I'm starting a performance optimization effort for Contextify based on the audit plan.

## Context

Contextify is a macOS SwiftUI app that monitors Claude Code/Codex CLI transcripts. We just fixed P0 bugs related to UI lag during ingest. Now we want a proactive, holistic performance optimization.

**Primary Goal:** Initial ingest experience must never feel sluggish.
**Secondary Goal:** If we can't do both UI + background work, pause and communicate clearly.
**Strategic:** Linux engine is shipping soon - optimizations to shared code benefit both platforms.

## Read First

1. Read the full audit plan: `/tmp/performance-audit-plan-2026-01.md`
2. Read the P0 investigation: `/tmp/ingest-ui-lag-complete-investigation-2026-01-01.md`
3. Read architecture docs:
   - `build/docs/architecture/ingestion-workflow.md`
   - `build/docs/architecture/data-pipeline-architecture.md`
   - `build/docs/architecture/llm-processing.md`

## Key Architecture

**Shared code (ContextifyCore)** - benefits Mac + Linux:
- `app/Sources/ContextifyCore/Database/HooverEngine.swift` - Streaming parser
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` - JSONL parsing
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` - DB coordination
- `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift` - Stat-only scan

**Mac-only (UI):**
- `Contextify/Contextify/ConversationMonitor.swift` - Timeline state
- `Contextify/Contextify/TimelineCacheMissGenerator.swift` - LLM queue
- `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift` - File monitoring

## Which Phase Are We On?

[USER: Specify which phase you want to work on]

- Phase 1: Measurement & Baselines (create benchmark suite)
- Phase 2: Quick Wins (index audit, cache tuning, debounce tuning)
- Phase 3: Architectural Improvements (parallelization, streaming)
- Phase 4: Low-Level Optimizations (parser, hashing, memory)
- Phase 5: User Communication (status bar, settings, progress)

## Ground Rules

1. **Run tests before any commit:** `swift test`
2. **Zero warnings:** `bash scripts/xc.sh build`
3. **Measure before/after:** Use benchmark suite or manual timing
4. **Document Linux impact:** Note if optimization affects shared code
5. **Atomic commits:** One logical change per commit
```

---

## Success Criteria

By the end of this effort:

1. **Measurable:** Benchmark suite exists with baseline measurements
2. **UI responsive:** No main thread gaps >100ms during any operation
3. **User informed:** Clear feedback during background work
4. **Linux benefits:** Shared code optimizations benefit both platforms
5. **Documented:** All optimizations documented with before/after metrics
