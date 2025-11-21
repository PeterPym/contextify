# MonitoringCoordinator Design Spec v3

**Status:** Implementation-ready (pending final review)
**Priority:** P2 (post-launch optimization)
**Prerequisites:** ConversationMonitor 4-way split (P0 from architecture-refactoring-analysis.md)

---

## Problem Statement

Current implementation creates a DispatchSource file watcher for every transcript across all projects. With 672+ transcripts in a single project, this consumes 1600+ file descriptors and scales poorly.

**Evidence (2025-11-20):**
- Contextify project: 672 transcript files
- Total FDs in use: 1607
- Each watcher = 1 open file descriptor + DispatchSource overhead

**Root cause:** The "lazy watchers for inactive projects" mitigation identified in project-switcher.md was never implemented.

---

## Goals

1. Reduce file descriptor usage by 90%+ for typical usage
2. Maintain <200ms latency for active project updates
3. Keep unread badge accuracy for inactive projects while app is running (typically <1s via FSEvents; offline changes corrected on activation)
4. No user-visible behavior change
5. Incremental rollout via feature flag

---

## Design: Two-Tier Monitoring

### Tier 1: Active Project (Real-Time)

**Mechanism:** DispatchSource per-file watchers (current implementation)

**Scope:** Only transcripts belonging to the currently selected project

**Latency:** ~150ms (debounce + hoover + UI)

**Justification:** FSEvents has 0.5s coalesce latency; DispatchSource provides sub-millisecond response needed for "live typing" feel. Two-tier complexity is justified by UX requirements.

### Tier 2: Inactive Projects (FSEvents-Driven)

**Mechanism:** FSEvents directory monitoring only (no periodic polling)

**Rationale:** FSEvents on `~/.claude/projects/` and `~/.codex/sessions/` is reliable. Periodic stat() polling adds I/O overhead and complexity for marginal gain.

**Flow:**
1. FSEvents detects file modification
2. `MonitoringCoordinator` checks if project is active
3. If inactive: mark transcript dirty in DB, update unread badge
4. If active: see FSEvents Behavior Matrix below

---

## FSEvents Behavior Matrix

| Project Status | Transcript Status | Action |
|----------------|-------------------|--------|
| **Active** | New (not in DB) | `discoverTranscript(startWatching: true)` - creates entry, initial hoover, starts watcher |
| **Active** | Existing (in DB, watcher running) | **No-op** - rely on DispatchSource watcher to handle the write |
| **Inactive** | New (not in DB) | `discoverTranscript(startWatching: false)` - creates entry, marks dirty |
| **Inactive** | Existing (in DB) | `markTranscriptDirty(transcriptId, mtime)` - no watcher, no hoover |

**Implementation:**
```swift
// In ProjectActivityMonitor.handleFileSystemChange
func handleFileSystemChange(_ change: FSEvent) async {
  let (projectId, transcriptId) = try resolveTranscript(forPath: change.path)
  let isActive = await monitoringCoordinator.isActiveProject(projectId)
  let existsInDB = try orchestrator.transcriptExists(transcriptId)

  if isActive {
    if !existsInDB {
      // New transcript for active project - discover and watch
      try await orchestrator.discoverTranscript(..., startWatching: true)
    }
    // Existing transcript - DispatchSource watcher handles it (no-op here)
  } else {
    if !existsInDB {
      // New transcript for inactive project - discover but don't watch
      try await orchestrator.discoverTranscript(..., startWatching: false)
    }
    // Mark dirty regardless (new or existing)
    await monitoringCoordinator.markTranscriptDirty(transcriptId, mtime: mtime)
  }
}
```

**Double-Ingestion Prevention:** For existing transcripts in active projects, FSEvents handler returns early. The DispatchSource watcher's debounce handles deduplication for rapid writes.

---

## Offline Changes Detection

**Problem:** Without periodic polling, changes made while app is closed would be missed - `pending_rehoover` remains 0, `last_known_mtime` is stale.

**Solution:** `rehooverDirtyTranscripts` performs on-demand mtime verification on activation:

```swift
// TranscriptOrchestrator.rehooverDirtyTranscripts
func rehooverDirtyTranscripts(projectId: String) async throws -> Int {
  let transcripts = try getTranscripts(forProject: projectId)
  var rehooveredCount = 0

  for transcript in transcripts {
    let fileURL = URL(fileURLWithPath: transcript.filePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

    // Get filesystem mtime
    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let fsMtime = attrs[.modificationDate] as? Date ?? .distantPast

    // Rehoover if: pending flag set OR filesystem is newer than last known
    let needsRehoover = transcript.pendingRehoover ||
                        fsMtime > (transcript.lastKnownMtime ?? .distantPast)

    if needsRehoover {
      _ = try hooverEngine.hooverTranscript(transcript, fileURL: fileURL, progress: NoOpProgressSink())
      try updateTranscriptMtime(transcriptId: transcript.id, mtime: fsMtime)
      try clearPendingRehoover(transcriptId: transcript.id)
      rehooveredCount += 1
    }
  }

  return rehooveredCount
}
```

**Key points:**
- stat() work happens only on **activation of that project**, not globally
- Catches both: FSEvents-detected changes (pending flag) AND offline changes (mtime comparison)
- This is "on-demand verification on activation", not "polling"

---

## Blocking Issue Resolutions (from v1/v2 reviews)

### B1: Health Check Conflict

**Resolution:** Health check ONLY runs for active project:
```swift
// ConversationMonitor.performHealthCheck
guard let activeId = monitoringCoordinator.activeProjectId else { return }
guard projectId == activeId else {
  // Inactive project - watchers intentionally absent
  return
}
```

### B2: FSEvents startWatching Conflict

**Resolution:** See FSEvents Behavior Matrix above. `startWatching` is conditional based on active status AND transcript existence.

### B3: Dirty Transcript Persistence

**Schema (Migration v27):**
```sql
ALTER TABLE transcripts ADD COLUMN pending_rehoover INTEGER DEFAULT 0;
ALTER TABLE transcripts ADD COLUMN last_known_mtime INTEGER;
```

**APIs:**
```swift
func markTranscriptDirty(id: String, mtime: Date) throws
func rehooverDirtyTranscripts(projectId: String) async throws -> Int
func clearPendingRehoover(transcriptId: String) throws
func updateTranscriptMtime(transcriptId: String, mtime: Date) throws
```

### B4: Lifecycle & Ownership

**Owner:** `ConversationMonitor` owns singleton `MonitoringCoordinator`

```swift
actor MonitoringCoordinator {
  private let transcriptWatcher: TranscriptWatcher
  private let orchestrator: TranscriptOrchestrator

  // Single source of truth
  private(set) var activeProjectId: String?

  // Hysteresis: delayed teardown tasks
  private var pendingTeardowns: [String: Task<Void, Never>] = [:]

  func stop() {
    pendingTeardowns.values.forEach { $0.cancel() }
    pendingTeardowns.removeAll()
    activeProjectId = nil
  }
}
```

### B5: Active Project Identity

**Single source of truth:** `MonitoringCoordinator.activeProjectId`

All components query this:
- UI project switch → `MonitoringCoordinator.activateProject(id)`
- FSEvents handler → `MonitoringCoordinator.isActiveProject(projectId)`
- Health check → only runs for `activeProjectId`

---

## Project Switching Flow

**With hysteresis to prevent thrashing:**

```
User switches Project A → Project B:

1. activateProject(B) called
2. Rehoover dirty transcripts for B (includes offline mtime check)
3. Schedule teardown for A in 5 seconds (cancellable)
4. Start watchers for B immediately
5. Set activeProjectId = B

If user switches back to A within 5 seconds:
- Cancel pending teardown for A
- A's watchers still running (no thrash)
- Schedule teardown for B instead
```

---

## stopAllForProject Location

**Decision:** Place in `TranscriptOrchestrator`, not `TranscriptWatcher`

Rationale: `TranscriptWatcher` operates on transcript IDs only; adding project awareness would require DB lookups from inside `watcherQueue`, risking contention.

```swift
// TranscriptOrchestrator
func stopAllWatchers(forProjectId id: String) throws {
  let transcripts = try getTranscripts(forProject: id)
  for t in transcripts {
    watcher.stopWatching(transcriptId: t.id)
  }
}
```

---

## Sandbox Behavior (APPSTORE_BUILD)

FSEvents is disabled for sandbox builds (`#if !APPSTORE_BUILD`).

For sandbox:
- Keep current eager watcher behavior (all transcripts watched)
- Sandbox builds have fewer transcripts (bounded by security-scoped bookmarks)
- Lazy optimization is DMG-only initially

Future consideration: polling via `TranscriptAccessProvider` if FD pressure appears in sandbox.

---

## Files to Modify

| File | Change |
|------|--------|
| `ConversationMonitor.swift` | Extract watcher logic; owns MonitoringCoordinator |
| `ProjectActivityMonitor.swift` | FSEvents behavior matrix; query MonitoringCoordinator |
| `TranscriptWatcher.swift` | No changes needed |
| `TranscriptOrchestrator.swift` | Add dirty transcript APIs; add `stopAllWatchers(forProjectId:)`; migration v27 |
| `DatabaseSchema.swift` | Add `pending_rehoover`, `last_known_mtime` columns |
| `MonitorConfig.swift` | Add `lazyWatchersEnabled` feature flag |

---

## Feature Flag & Rollout

```swift
// MonitorConfig.swift
static var lazyWatchersEnabled: Bool {
  #if APPSTORE_BUILD
  return false  // Disabled for sandbox initially
  #else
  return UserDefaults.standard.bool(forKey: "lazyWatchersEnabled")
  #endif
}
```

**Rollout phases:**
1. Internal testing with flag enabled
2. Opt-in for power users
3. Default on for DMG builds
4. Evaluate for sandbox builds

---

## Observability & Metrics

**Logging:**
- `[LAZY-WATCHER] activeProjectId=X watcherCount=N`
- `[LAZY-WATCHER] Marked transcript dirty: id=X project=Y`
- `[LAZY-WATCHER] Rehoovered N dirty transcripts on activation (M via mtime check)`
- `[LAZY-WATCHER] Teardown scheduled for project=X delay=5s`
- `[LAZY-WATCHER] Teardown cancelled for project=X (reactivated)`
- `[LAZY-WATCHER] FSEvents: active+new → discover+watch`
- `[LAZY-WATCHER] FSEvents: active+existing → no-op (watcher handles)`
- `[LAZY-WATCHER] FSEvents: inactive → mark dirty`

**Heartbeat:**
- `[FSEVENTS-HEARTBEAT] watching=N active_project_watchers=M inactive_dirty=K`

**Success metrics:**
- FD count before/after (via `lsof -p [pid] | wc -l`)
- Watcher count per project
- Dirty transcript queue depth

---

## Resource Impact

**Before (current):**
- 20 projects, ~800 total transcripts
- 800 file descriptors
- 800 DispatchSource objects

**After (with lazy watchers):**
- Active project: ~50 watchers (typical)
- Inactive: 0 watchers, 0 FDs
- **90%+ reduction in file descriptors**

---

## Testing Strategy

### Unit Tests
- `MonitoringCoordinator` state transitions (active/inactive)
- Dirty transcript marking and clearing
- Hysteresis timer cancellation
- `rehooverDirtyTranscripts` catches both pending flag AND stale mtime

### Integration Tests
- Project switch starts/stops correct watchers
- FSEvents on inactive project marks dirty (no watcher started)
- FSEvents on active project with existing transcript is no-op
- FSEvents on active project with new transcript discovers and watches
- Activation rehovers dirty transcripts (including offline changes)
- Health check only repairs active project

### Performance Tests
- Measure FD count before/after with 600+ transcripts
- Rapid project switching (10 switches in 5 seconds) - no FD explosion
- Assert: `activeWatcherCount == 0` for inactive project after hysteresis

### Regression Tests
- Active project latency unchanged (<200ms)
- Offline changes detected on activation
- No missed `TranscriptUpdated` notifications during project switch

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Missed updates during project switch | Rehoover dirty transcripts on activation (includes mtime check) |
| Offline changes missed | `rehooverDirtyTranscripts` compares filesystem mtime |
| Health check fights lazy policy | Scope health check to active project only |
| FSEvents defeats lazy via startWatching | Behavior matrix: conditional based on active + exists |
| Double ingestion for active projects | FSEvents no-ops for existing transcripts; watcher handles |
| Rapid switching thrash | 5-second hysteresis before teardown |
| Complexity increase | Feature flag allows rollback |

---

## Alternative Approaches Considered

### 1. FSEvents-Only (Unified)
- Drop DispatchSource entirely; rely on FSEvents for everything
- **Rejected:** FSEvents 0.5s latency doesn't meet <200ms goal for active project

### 2. LRU Cap Per Project
- Keep per-file watchers but only for K most recent transcripts
- **Deferred:** More complex; current proposal sufficient for initial optimization

---

## Prior Art & References

- `build/docs/archive/feature-specs/project-switcher.md` - "N x scaling overhead" risk
- `build/docs/architecture/architecture-refactoring-analysis.md` - MonitoringCoordinator extraction
- `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift` - Current implementation
- `app/Sources/ContextifyCore/ProjectActivityMonitor.swift` - FSEvents infrastructure

---

## Changelog

**v3 (2025-11-20):** Addressed final review feedback
- Added FSEvents Behavior Matrix (B6) - new vs existing, active vs inactive
- Added offline changes detection via mtime comparison in `rehooverDirtyTranscripts` (B7)
- Moved `stopAllForProject` to TranscriptOrchestrator (N1)
- Updated goal wording for badge accuracy (N2)
- Added detailed logging for FSEvents paths

**v2 (2025-11-20):** Incorporated initial colleague reviews
- Added health check conflict resolution (B1)
- Added FSEvents conditional startWatching (B2)
- Added dirty transcript DB schema and APIs (B3)
- Added lifecycle/ownership section (B4)
- Added single source of truth for active project (B5)
- Replaced periodic polling with FSEvents-only for inactive
- Added hysteresis for project switching
- Added feature flag and rollout plan
- Added observability metrics
- Added sandbox behavior section

**v1 (2025-11-20):** Initial draft
