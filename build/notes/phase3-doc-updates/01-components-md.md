# Change Requirements: build/docs/architecture/COMPONENTS.md

**Document:** `build/docs/architecture/COMPONENTS.md`
**Priority:** 1 (Critical)
**Impact:** High - Primary architecture reference document
**Estimated Effort:** 4-6 hours

---

## Current State Analysis

**File:** 304 lines
**Last Updated:** Schema v26 references, Nov 2025
**Current Content:**
- Database Layer (lines 12-80)
- LLM Processing & Timeline Integration (lines 83-126)
- Core Components / Project Context (lines 129-148)
- Startup Coordination (lines 151-206)
- UI Layer (lines 209-236)
- Supporting Components (lines 239-248)
- Transcript Parsing & Metadata (lines 251-280)
- Transcript Corruption (lines 283-304)

**Issues:**
1. No mention of AppStateOrchestrator (central coordinator introduced in Phase 3)
2. No mention of LightweightDiscoveryService (stat-only scanning)
3. StartupCoordinator section (lines 151-206) describes it as "single source of truth" - now legacy compatibility shim
4. ProjectsViewModel not documented (simplified observer pattern in Phase 3)
5. No documentation of lazy loading architecture
6. No documentation of background indexing
7. No documentation of AppState enum (state machine pattern)
8. Performance metrics outdated

---

## Required Changes

### 1. Add New Section: "Application State Coordination (Phase 3 Lazy Loading)"

**Location:** Insert after line 148 (before "Startup Coordination")

**Content:**

```markdown
## Application State Coordination (Phase 3 Lazy Loading)

**As of 2025-11-18:** Phase 3 introduces lazy loading architecture with central state coordination.

**AppStateOrchestrator** (`app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift`):
- Central coordinator for all app state transitions
- Replaces fragmented responsibilities of StartupCoordinator, ProjectActivityMonitor, and ProjectsViewModel ingestion logic
- Implements state machine pattern via AppState enum
- Manages lazy loading: JIT (Just-In-Time) ingestion on project selection
- Coordinates background indexing of inactive projects

**AppState** (enum in AppStateOrchestrator.swift):
- `startup` - Initial app launch
- `discovering` - Lightweight filesystem scan in progress
- `idle(projects: [LightweightProject])` - UI ready with project list
- `loading(projectId: String)` - JIT ingestion in progress for selected project
- `active(projectId: String)` - Project fully loaded and timeline ready
- `error(String)` - Error state with user-facing message

**LightweightDiscoveryService** (`app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift`):
- Fast filesystem scanner for project metadata (NO file content reads, NO DB writes)
- Stat-only scanning: uses file modification times as activity proxy
- Goal: <200ms for typical setup (19 projects, 663 transcripts)
- Returns `LightweightProject` structs sorted by last activity
- Actor-based for thread safety

**LightweightProject** (struct in AppStateOrchestrator.swift):
- Sendable, lightweight project metadata (no database required)
- Contains: id, path, displayName, transcriptCount, lastActivity, provider, cwd, transcriptFiles
- Used for initial UI display before full ingestion
- Converted to DiscoveredProject by ProjectsViewModel for UI compatibility

**FastPathIngestionCoordinator** (`app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`):
- JIT ingestion coordinator for selected projects
- Batched ingestion with progress tracking
- Resume pending completions on app restart
- Called by AppStateOrchestrator.selectProject()

**ProjectsViewModel** (`Contextify/Contextify/ProjectsViewModel.swift`):
- Simplified "dumb" observer view model (Phase 3 refactor: -278 lines, 63% reduction)
- Observes AppStateOrchestrator state transitions
- Converts state to UI-compatible models (LightweightProject → DiscoveredProject)
- Delegates all actions to AppStateOrchestrator (no direct discovery or ingestion)

### Key Principles (Phase 3)

- **AppStateOrchestrator** is the central coordinator - all state flows through it
- **Startup is lightweight** - stat-only scan, NO ingestion (target: <200ms)
- **Ingestion is lazy (JIT)** - projects ingested only when user selects them
- **Background indexing** - inactive projects pre-ingested at low priority
- **State machine pattern** - explicit state transitions with type safety

### Performance Metrics (Phase 3)

- **Cold start:** <200ms (achieved: 187ms) - 10-35x faster than Phase 2
- **Memory at startup:** 30-50 MB - 3-5x lower than Phase 2 (150-300 MB)
- **DB writes at startup:** 19 rows (projects metadata only) - 10-20x fewer than Phase 2 (5000-15000 rows)
- **JIT ingestion:** <1s per project (typical)
- **Background indexing:** Low priority (Task.priority.utility), cancellable

### Architecture Flow

```
1. App Launch → AppStateOrchestrator.startup()
   - LightweightDiscoveryService.discoverProjectsLightweight() [<200ms]
   - Update projects table metadata ONLY (no transcripts/entries)
   - setState(.idle(projects)) → UI ready

2. User Selects Project → AppStateOrchestrator.selectProject(id:)
   - Cancel background work
   - setState(.loading(projectId))
   - FastPathIngestionCoordinator.ingestProjectJIT(project) [<1s]
   - StartupCoordinator.handleExternalProjectSwitch() [legacy compatibility]
   - setState(.active(projectId))
   - Post .projectDidActivate notification

3. Background (idle) → AppStateOrchestrator.startBackgroundIndexing()
   - Wait 5s after user activity
   - Ingest inactive projects one at a time (low priority)
   - Check Task.isCancelled between projects
   - Post .backgroundIngestProgress notifications
```

### Documentation

- **Architecture overview:** `build/docs/architecture/data-pipeline-architecture.md`
- **Phase 3 comparison:** `build/notes/phase3-refactor-comparison-analysis.md`
- **Implementation guide:** `build/docs/components/project-discovery-service-implementation.md`

---
```

**Estimated Effort:** 2 hours

---

### 2. Update "Startup Coordination" Section (lines 151-206)

**Current:** Describes StartupCoordinator as "single source of truth"

**Changes:**

```markdown
## Startup Coordination (Legacy - Phase 3)

**IMPORTANT (Phase 3):** StartupCoordinator is now a **legacy compatibility shim**. AppStateOrchestrator is the central coordinator for project state.

**StartupCoordinator** (`app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`):
- Legacy coordinator for backward compatibility with ConversationMonitor and other pre-Phase 3 components
- Receives notifications from AppStateOrchestrator via handleExternalProjectSwitch()
- Publishes ActiveProjectContext updates for legacy subscribers
- Will be refactored/removed in Phase 4 when ConversationMonitor is split

**ActiveProjectContext** (`app/Sources/ContextifyCore/Models/ActiveProjectContext.swift`):
- Immutable value type representing active project identity
- Contains stable project ID (primary key), filesystem path (metadata), display name, git branch, and security-scoped bookmark

### Phase 3 Role Change

**Before Phase 3:** StartupCoordinator was primary project identity coordinator
**After Phase 3:** AppStateOrchestrator owns state, StartupCoordinator notifies legacy components

### Integration Pattern (Phase 3)

```swift
// New components: Subscribe to AppStateOrchestrator
for await _ in NotificationCenter.default.notifications(named: .appStateDidChange) {
    await updateFromOrchestrator()
}

// Legacy components: Still use StartupCoordinator
for await context in StartupCoordinator.shared.updates {
    self.activeProjectId = context.id
}
```

### Key Principles (Legacy Pattern - Will Change in Phase 4)

- `ActiveProjectContext.id` is the **stable primary identity** - use for all database queries
- `ActiveProjectContext.path` is **metadata only** - do not use for lookups
- New code should use AppStateOrchestrator directly (not StartupCoordinator)

### Documentation

- **Architecture:** `build/docs/architecture/startup-coordinator.md`
- **Implementation:** `build/docs/components/startup-coordinator-implementation.md`
- **Phase 4 refactoring plan:** `build/docs/architecture/architecture-refactoring-analysis.md`

**⚠️ Note:** This section documents legacy behavior. For new development, see "Application State Coordination" above.
```

**Estimated Effort:** 1 hour

---

### 3. Add Performance Metrics Summary

**Location:** Insert after Table of Contents (before "Database Layer" section)

**Content:**

```markdown
---

## Performance Summary (Phase 3 - Nov 2025)

**Startup Performance:**
- **Cold start:** <200ms (target) | 187ms (achieved) - 10-35x faster than Phase 2
- **UI ready:** Immediate after lightweight scan (no ingestion blocking)
- **First project selection:** <1s (JIT ingestion)

**Memory Footprint:**
- **At startup:** 30-50 MB (Phase 3) vs 150-300 MB (Phase 2) - 3-5x reduction
- **After first project load:** 60-100 MB

**Database Operations:**
- **At startup:** 19 row updates (projects metadata only)
- **Phase 2 baseline:** 5000-15000 rows (all projects/transcripts/entries) - 10-20x reduction

**Lazy Loading:**
- **Discovery:** Stat-only filesystem scan (no JSONL parsing)
- **Ingestion:** On-demand (JIT) when user selects project
- **Background:** Low-priority pre-ingestion of inactive projects

---
```

**Estimated Effort:** 30 minutes

---

### 4. Update LLM Processing Section (lines 83-126)

**Current:** Describes ConversationMonitor as main component (accurate but incomplete)

**Add Note:**

```markdown
**ConversationMonitor** (`Contextify/Contextify/ConversationMonitor.swift`):
- Main `@Observable` `@MainActor` component for timeline display
- Manages TimelineState, visible entries, and session filtering
- Integrates with SQL backend via TranscriptOrchestrator
- **⚠️ Phase 4:** Will be refactored into 4 focused components (see architecture-refactoring-analysis.md)
  - ConversationMonitor (400 lines) - Timeline coordination only
  - TimelineLoader (300 lines) - Database queries & pagination
  - MonitoringCoordinator (250 lines) - Watcher lifecycle
  - TimelineCacheCoordinator (200 lines) - LLM queue management
```

**Estimated Effort:** 15 minutes

---

### 5. Update UI Layer Section (lines 209-236)

**Add ProjectsViewModel:**

```markdown
**ProjectsViewModel** (`Contextify/Contextify/ProjectsViewModel.swift`):
- Simplified observer view model for Projects window (Phase 3 refactor: 163 lines, down from 441)
- Observes AppStateOrchestrator state transitions
- Converts LightweightProject → DiscoveredProject for UI display
- Delegates all actions (project selection, refresh) to AppStateOrchestrator
```

**Estimated Effort:** 15 minutes

---

### 6. Add Cross-References Section

**Location:** End of document (after "Transcript Corruption")

**Content:**

```markdown
---

## Phase 3 Architecture Documentation

**Phase 3 Lazy Loading** (implemented Nov 2025):
- **Comparison with recommendations:** `build/notes/phase3-refactor-comparison-analysis.md`
- **Documentation update tracker:** `build/notes/phase3-documentation-update-master-list.md`
- **Data pipeline updates:** `build/docs/architecture/data-pipeline-architecture.md`

**Key Phase 3 Components:**
- AppStateOrchestrator - Central state coordinator
- LightweightDiscoveryService - Stat-only scanning (<200ms)
- ProjectsViewModel - Simplified observer pattern
- FastPathIngestionCoordinator - JIT ingestion

**Performance Achievements:**
- ✅ Startup: 10-35x faster (<200ms)
- ✅ Memory: 3-5x lower (30-50 MB)
- ✅ DB writes: 10-20x fewer (19 rows)

**Phase 4 Planned Work:**
- ConversationMonitor refactor (3000+ lines → 4 components)
- Protocol abstractions for testability
- Unified event system (replace NotificationCenter)
- StartupCoordinator refactor/removal
```

**Estimated Effort:** 15 minutes

---

## Summary of Changes

1. **Add:** New section "Application State Coordination (Phase 3 Lazy Loading)" (~100 lines)
2. **Update:** "Startup Coordination" section - mark as legacy, explain role change (~50 lines modified)
3. **Add:** Performance metrics summary at top of document (~15 lines)
4. **Update:** ConversationMonitor - add Phase 4 refactoring note (~5 lines)
5. **Add:** ProjectsViewModel to UI Layer section (~5 lines)
6. **Add:** Phase 3 cross-references section (~20 lines)

**Total Lines Added/Modified:** ~195 lines
**Estimated Effort:** 4-6 hours

---

## Validation Checklist

After making changes, verify:

- [ ] AppStateOrchestrator documented with state machine pattern
- [ ] LightweightDiscoveryService documented with performance targets
- [ ] StartupCoordinator marked as legacy with Phase 4 deprecation note
- [ ] Performance metrics updated (startup, memory, DB writes)
- [ ] ProjectsViewModel documented as observer pattern
- [ ] Cross-references to Phase 3 documentation added
- [ ] No broken internal links
- [ ] Code examples use correct file paths and line numbers
- [ ] Architecture flow diagram accurate

---

**Document Version:** 1.0
**Created:** 2025-11-19
**Implements:** Phase 3 documentation update item #1
