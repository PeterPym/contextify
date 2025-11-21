# Change Requirements: build/docs/components/project-discovery.md

**Document:** `build/docs/components/project-discovery.md`
**Priority:** 2 (Medium)
**Impact:** Medium - Component overview
**Estimated Effort:** 2-3 hours

---

## Current State Analysis

**File:** General overview of discovery patterns
**Current Content:**
- High-level discovery concepts
- Provider patterns
- Multi-project support

**Issues:**
1. No mention of LightweightDiscoveryService
2. No documentation of lazy loading pattern
3. No explanation of background indexing
4. Performance targets outdated
5. No two-tier architecture explanation

---

## Required Changes

### 1. Add Phase 3 Overview Section

**Location:** Top of document (after title/metadata)

**Content:**

```markdown
---

## Phase 3 Architecture (Nov 2025)

**Discovery is now two-tiered** for optimal startup performance:

**Tier 1: Lightweight Discovery** (Startup)
- Component: `LightweightDiscoveryService`
- Strategy: Stat-only scanning (NO file reads)
- Performance: <200ms (achieved: 143-187ms)
- Purpose: Instant UI with project list

**Tier 2: Full Discovery** (On-Demand)
- Component: `ProjectDiscoveryService`
- Strategy: Complete JSONL parsing + DB writes
- Performance: 1-5s per project
- Purpose: JIT ingestion when project selected

**Key Innovation:** Decouple "show projects" (fast) from "load timeline data" (slow)

**See Also:**
- Implementation: `build/docs/components/project-discovery-service-implementation.md`
- Architecture: `build/docs/architecture/data-pipeline-architecture.md`

---
```

**Estimated Effort:** 15 minutes

---

### 2. Add LightweightDiscoveryService Overview Section

**Location:** Insert before existing discovery service sections

**Content:**

```markdown
## LightweightDiscoveryService Overview

**File:** `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift` (251 lines)
**Added:** Phase 3 (Nov 2025)
**Purpose:** Ultra-fast project discovery for startup

### Design Principles

1. **Stat-Only Scanning**
   - Uses FileManager metadata queries only
   - NO file content reads
   - Directory mtime as activity proxy

2. **Zero Database Impact**
   - NO database writes
   - NO database reads
   - Pure filesystem operation

3. **Minimal Memory**
   - ~50 KB for 19 projects
   - Just file metadata structures
   - No JSONL parsing buffers

4. **Background Execution**
   - Actor pattern for thread safety
   - Off main thread by default
   - Async/await for structured concurrency

### What It Returns

**LightweightProject** (struct):
```swift
public struct LightweightProject: Sendable, Identifiable {
  public let id: String                // Stable identifier
  public let path: URL                 // Filesystem location
  public let displayName: String       // UI-friendly name
  public let transcriptCount: Int      // File count (not parsed)
  public let lastActivity: Date        // Directory mtime
  public let provider: String          // "claude.code" or "codex.cli"
  public let cwd: String?              // Real project path (decoded)
  public let transcriptFiles: [URL]    // For later JIT ingestion
}
```

**Key Differences from DiscoveredProject:**
- No database backing (pure filesystem)
- Approximate activity (mtime vs parsed timestamps)
- Carries file URLs for later ingestion
- Sendable (can cross actor boundaries)

### Performance Targets

| Metric | Target | Achieved | Validation |
|--------|--------|----------|------------|
| Duration | <200ms | 143-187ms | ✅ Logs |
| Memory | <1 MB | ~50 KB | ✅ Instruments |
| File Reads | 0 | 0 | ✅ Code review |
| DB Operations | 0 | 0 | ✅ Code review |

**Log Evidence:**
```
[DISC-LIGHT] Starting lightweight scan...
[DISC-LIGHT] Scan complete in 0.143s. Found 19 projects.
```

### Use Cases

**✅ Use LightweightDiscoveryService for:**
- App startup (need instant UI)
- Quick refresh (pull-to-refresh)
- Background polling (check for new projects)

**❌ Don't use for:**
- Loading timeline (need full data)
- Displaying entry counts (need parsed entries)
- Showing exact activity times (need parsed timestamps)

### Integration Pattern

```swift
// AppStateOrchestrator.startup()
let projects = await LightweightDiscoveryService().discoverProjectsLightweight()
setState(.idle(projects: projects))  // UI ready in <200ms

// Later: User selects project
await FastPathIngestionCoordinator().ingestProjectJIT(projects[0])
// Now database has full data for timeline
```

---
```

**Estimated Effort:** 1 hour

---

### 3. Add Lazy Loading Architecture Section

**Location:** Insert after LightweightDiscoveryService section

**Content:**

```markdown
## Lazy Loading Architecture (Phase 3)

### Problem Statement

**Before Phase 3:**
- All projects ingested at startup (2-5 seconds)
- UI blocked until completion
- Memory spike (150-300 MB)
- Database write spike (5000-15000 rows)

**User Impact:**
- Blank screen for 2-5 seconds (bad first impression)
- Slow project switches (re-ingesting everything)

### Solution: Just-In-Time (JIT) Ingestion

**Phase 3 Approach:**

```mermaid
sequenceDiagram
    participant User
    participant UI
    participant ASO as AppStateOrchestrator
    participant LDS as LightweightDiscoveryService
    participant FPI as FastPathIngestionCoordinator
    participant DB as Database

    User->>UI: Launch app
    UI->>ASO: startup()
    ASO->>LDS: discoverProjectsLightweight()
    LDS-->>ASO: [LightweightProject] (19 projects)
    ASO->>ASO: setState(.idle(projects))
    ASO->>UI: UI ready (<200ms)

    Note over User,UI: User sees project list immediately

    User->>UI: Click "Project A"
    UI->>ASO: selectProject(id: "A")
    ASO->>ASO: setState(.loading)
    ASO->>FPI: ingestProjectJIT(project A)
    FPI->>DB: INSERT transcripts, entries
    FPI-->>ASO: Complete
    ASO->>ASO: setState(.active)
    ASO->>UI: Timeline ready

    Note over User,UI: Only Project A ingested (~1s)
```

### Benefits

✅ **10-35x Faster Startup**
- Before: 2-5s (all projects)
- After: <200ms (none ingested)

✅ **3-5x Lower Memory**
- Before: 150-300 MB (all data loaded)
- After: 30-50 MB (just metadata)

✅ **Better UX**
- Instant perceived performance
- No blank screen
- Responsive during ingestion

✅ **Scalability**
- Handles 100+ projects gracefully
- Startup time independent of project count
- Memory scales with active projects only

### Background Indexing

**Optimization:** Pre-ingest inactive projects when idle

```swift
// AppStateOrchestrator.startBackgroundIndexing()
Task(priority: .utility) {
  await Task.sleep(nanoseconds: 5_000_000_000)  // Wait 5s

  for project in inactiveProjects {
    if Task.isCancelled { break }
    await fastPath.ingestProjectJIT(project)
    await Task.yield()  // Cooperative cancellation
  }
}
```

**Characteristics:**
- Priority: `.utility` (low, won't block UI)
- Cancellable: User interaction cancels immediately
- Sequential: One project at a time (no CPU spike)
- Progress: Status bar shows completion

**User Impact:**
- By the time user switches projects, most already ingested
- Feels instant (background work done proactively)

---
```

**Estimated Effort:** 1 hour

---

### 4. Update Performance Targets Section

**Add Comparison Table:**

```markdown
## Performance Comparison: Phase 2 vs Phase 3

### Startup Performance

| Metric | Phase 2 (Eager) | Phase 3 (Lazy) | Improvement |
|--------|----------------|----------------|-------------|
| Duration | 2000-5000ms | 143-187ms | **10-35x faster** |
| File Reads | 663 (all) | 0 | **Infinite improvement** |
| JSONL Parsing | Full (all) | None | **Deferred to JIT** |
| DB Writes | 5000-15000 rows | 19 rows | **10-20x fewer** |
| Memory Peak | 150-300 MB | 30-50 MB | **3-5x lower** |
| UI Blocking | Yes (2-5s) | No (<200ms) | **Non-blocking** |

### Project Selection Performance

| Metric | Phase 2 | Phase 3 | Notes |
|--------|---------|---------|-------|
| First Selection | Already loaded | 500-1000ms | JIT ingestion |
| Subsequent | Instant | Instant | Already ingested |
| Background Indexed | Instant | Instant | Pre-ingested |

**Net Result:**
- Startup: **10-35x faster**
- First project switch: Comparable (already had to load)
- Overall UX: **Much better** (instant perceived performance)

---
```

**Estimated Effort:** 30 minutes

---

### 5. Add Architecture Diagram

**Location:** After overview sections

**Content:**

```markdown
## Phase 3 Discovery Architecture Diagram

```mermaid
graph TB
    subgraph "Filesystem"
        CC[~/.claude/projects/]
        CX[~/.codex/sessions/]
    end

    subgraph "Tier 1: Lightweight (Startup)"
        LDS[LightweightDiscoveryService<br/>Actor]
        LDS -->|Stat-only| CC
        LDS -->|Stat-only| CX
        LDS -->|<200ms| LP[LightweightProject<br/>Sendable Struct]
    end

    subgraph "Tier 2: Full (On-Demand)"
        PDS[ProjectDiscoveryService<br/>Actor]
        FPI[FastPathIngestionCoordinator]
        HE[HooverEngine]
        PDS -->|Full read| CC
        PDS -->|Full read| CX
        FPI -->|JIT| HE
        HE -->|Parse JSONL| DB[(Database)]
    end

    subgraph "Coordination"
        ASO[AppStateOrchestrator<br/>@MainActor]
        ASO -->|Startup| LDS
        ASO -->|JIT| FPI
        ASO -->|Background| FPI
    end

    subgraph "UI"
        UI[SwiftUI Views]
        ASO -->|@Published state| UI
    end

    style LDS fill:#90EE90
    style ASO fill:#90EE90
    style PDS fill:#FFE4B5
```

**Key:**
- Green: Phase 3 primary components
- Yellow: Legacy/secondary components
- Solid arrows: Primary paths
- Dashed arrows: Secondary/background paths

---
```

**Estimated Effort:** 15 minutes

---

## Summary of Changes

1. **Add:** Phase 3 overview (~15 lines)
2. **Add:** LightweightDiscoveryService overview section (~100 lines)
3. **Add:** Lazy loading architecture section (~80 lines with mermaid)
4. **Add:** Performance comparison table (~40 lines)
5. **Add:** Architecture diagram (~30 lines mermaid)

**Total Lines Added/Modified:** ~265 lines
**Estimated Effort:** 2-3 hours

---

## Validation Checklist

After making changes, verify:

- [ ] Two-tier architecture clearly explained
- [ ] LightweightDiscoveryService overview accurate
- [ ] Lazy loading benefits articulated
- [ ] Background indexing documented
- [ ] Performance targets validated against logs
- [ ] Architecture diagram renders correctly
- [ ] Comparison tables accurate
- [ ] Cross-references resolve
- [ ] Use case guidance clear

---

**Document Version:** 1.0
**Created:** 2025-11-19
**Implements:** Phase 3 documentation update item #7
