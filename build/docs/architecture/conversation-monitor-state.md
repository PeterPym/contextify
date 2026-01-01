# ConversationMonitor State Management Architecture

**Status:** Production
**Concurrency:** @MainActor (UI layer)
**Pattern:** Observable + Suffix-Based Visible State
**File:** `Contextify/Contextify/ConversationMonitor.swift`

---

## System Overview

ConversationMonitor is the UI-facing singleton that manages timeline state, session switching, and real-time updates. It coordinates SQL backend queries, LLM cache generation, and SwiftUI observation.

**Key Responsibilities:**
- Maintain single source of truth (TimelineState)
- Provide visible entries (suffix-limited, all sessions in one stream)
- Coordinate background tasks (file watching, health monitoring)
- Handle incremental updates via TimelineDataLoader
- Debounce rapid file changes

---

## Architecture

```
┌───────────────────────────────────────────────────────┐
│          ConversationMonitor (@MainActor)             │
│              Singleton, @Observable                   │
├───────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────┐ │
│  │          TimelineState (nested class)            │ │
│  │  - entries: [TimelineEntry]                      │ │
│  │  - revision: UInt64                              │ │
│  │  - _indexByCacheKey: [CacheKey: Int] (cached)   │ │
│  │  - _byID: [UUID: TimelineEntry] (cached)        │ │
│  └─────────────────────────────────────────────────┘ │
│                                                        │
│  ┌─────────────────────────────────────────────────┐ │
│  │      visibleEntries (suffix-limited)             │ │
│  │  - Returns last N entries (visibleEntryLimit=25) │ │
│  │  - All sessions shown in one stream (no filter)  │ │
│  └─────────────────────────────────────────────────┘ │
│                                                        │
│  ┌─────────────────────────────────────────────────┐ │
│  │         Background Tasks (structured)            │ │
│  │  - File watcher (debounced updates)              │ │
│  │  - Health monitoring (via coordinator)           │ │
│  │  - Cache miss generator (LLM summaries)          │ │
│  └─────────────────────────────────────────────────┘ │
│                                                        │
│  ┌─────────────────────────────────────────────────┐ │
│  │         Extracted Coordinators                   │ │
│  │  - ViewportTrackingCoordinator (viewport state)  │ │
│  │  - TimelineCacheCoordinator (cache misses)       │ │
│  │  - HealthMonitoringCoordinator (health checks)   │ │
│  │  - TimelineDataLoader (DB queries, cursor)       │ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────┬────────────────────────────────────┘
                   │
         ┌─────────┴─────────┐
         ↓                   ↓
┌──────────────────┐   ┌──────────────────┐
│ Orchestrator     │   │ Notifications    │
│ (nonisolated)    │   │ - Cache updated  │
│ - SQL queries    │   │ - Project changed│
│ - Cache lookups  │   │ - Primer ready   │
└──────────────────┘   └──────────────────┘
```

---

## TimelineState Design

### Single Source of Truth

TimelineState is a nested `@Observable` class that owns the entries array and provides O(1) lookups:

```swift
@MainActor
@Observable
final class TimelineState {
    var entries: [TimelineEntry] = []
    private(set) var revision: UInt64 = 0

    // Cached index maps (rebuilt on mutation)
    @ObservationIgnored private var _indexByCacheKey: [CacheKey: Int] = [:]
    @ObservationIgnored private var _byID: [UUID: TimelineEntry] = [:]

    var indexByCacheKey: [CacheKey: Int] { _indexByCacheKey }

    func lookup(_ id: UUID) -> TimelineEntry? { _byID[id] }

    func replace(with entries: [TimelineEntry]) {
        self.entries = entries
        revision &+= 1
        rebuildCacheIndex()
    }

    func append(_ e: TimelineEntry) {
        entries.append(e)
        revision &+= 1
        // Incremental index update (no full rebuild)
        if let key = e.cacheKey { _indexByCacheKey[key] = entries.count - 1 }
        _byID[e.id] = e
    }

    func update(at index: Int, to newValue: TimelineEntry) {
        // Atomic cache index update: remove old key, add new
        entries[index] = newValue
        revision &+= 1
        // Update index maps incrementally
    }
}
```

**Design Rationale:**
- **Cached index maps:** `_indexByCacheKey` and `_byID` enable O(1) lookup
- **Incremental updates:** `append()` updates indexes without full rebuild
- **Revision tracking:** Every mutation increments revision for SwiftUI reactivity
- **Observable:** SwiftUI re-renders when entries/revision changes

---

## visibleEntries (Suffix-Limited Display)

The timeline no longer filters by session. All sessions appear as one continuous chronological stream, limited to the most recent N entries for performance:

```swift
@Observable
@MainActor
final class ConversationMonitor {
    private let state = TimelineState()
    private let visibleEntryLimit = 25  // Tuneable (MonitorConfig.maxEntries)

    var entries: [TimelineEntry] { state.entries }

    var visibleEntries: [TimelineEntry] {
        // Force SwiftUI observation by reading revision counters
        _ = entriesRevision
        _ = stateRevision

        let n = max(visibleEntryLimit, 1)
        return state.entries.count > n
            ? Array(state.entries.suffix(n))
            : state.entries
    }
}
```

**Design Notes:**
- **No session filtering:** Timeline shows all sessions in one view
- **Suffix-based limiting:** Only last 25 entries shown for performance
- **Revision tracking:** Both `entriesRevision` and `stateRevision` force SwiftUI updates
- **Configurable limit:** Controlled by `MonitorConfig.maxEntries` (default 25)

---

## Startup & Monitoring Lifecycle

### startMonitoring() Flow

The startup flow in `ConversationMonitor#startMonitoring` handles project initialization:

```swift
@MainActor
func startMonitoring(projectId: String) {
    // Guard: Skip if already monitoring this project
    if (isMonitoring && currentProjectId == projectId) ||
       (currentProjectId == projectId && isInitializing) {
        return
    }

    isInitializing = true
    currentProjectId = projectId  // Set synchronously to prevent UI races

    Task { [weak self] in
        // 1. Reuse or create orchestrator
        // 2. Verify project exists in database (non-fatal if not yet)
        // 3. Shutdown old cache generator with chained handoff
        // 4. Create new generator in background (non-blocking)
        // 5. Initialize diagnostics service
        // 6. Spawn background task group:
        //    - watchForDebouncedTranscriptUpdates()
        //    - healthMonitor.startMonitoring()
        // 7. Load initial feed via loadFeedFromSQL()
        // 8. Setup cache update notifications
        // 9. Set isMonitoring = true, isInitializing = false

        NotificationCenter.default.post(name: .conversationMonitoringDidStart, object: nil)
    }
}
```

**Key Design Points:**
- **Duplicate call prevention:** Guards on `isMonitoring` and `isInitializing`
- **Chained generator shutdown:** Old generator awaits previous shutdown before cleanup
- **Non-blocking generator init:** New generator created in background Task
- **No discovery loop:** Transcript discovery handled by ProjectActivityMonitor via FSEvents

---

## Real-Time Updates

### Incremental Update Strategy

Incremental updates use `TimelineDataLoader` (an actor) for cursor management and deduplication:

```swift
// EntryCursor struct for keyset pagination
@ObservationIgnored private var lastSeenCursor: EntryCursor?

@MainActor
private func processIncrementalUpdate() async {
    // Single-flight guard
    if updateInFlight { updateDirty = true; return }
    updateInFlight = true
    defer { updateInFlight = false }

    repeat {
        updateDirty = false

        guard let projectId = currentProjectId,
              let loader = dataLoader else { return }

        // Delegate to TimelineDataLoader for cursor/dedup
        let result = try await loader.processIncremental(projectId: projectId)

        guard !result.newEntries.isEmpty else { break }

        // Convert to TimelineEntry with cache lookup
        for entry in result.newEntries {
            let cache = lookupCache(for: entry)
            appendEntry(toTimelineEntry(entry, cached: cache, ...))
        }

        // Queue cache misses via coordinator
        let misses = cacheCoordinator.createMissesForUpdate(...)
        await cacheMissGenerator?.queueMisses(misses)

        // Maintain order and bounds
        sortEntriesChronologically()
        trimEntries()  // Trims to MonitorConfig.maxEntries (25)

        // Sync cursor from loader
        lastSeenCursor = await loader.lastSeenCursor

    } while updateDirty && updateDrainItersRemaining > 0
}
```

**EntryCursor:** Uses struct with `(timestamp, createdAt, id)` for stable keyset pagination.

**TimelineDataLoader:** Actor that owns cursor persistence and `seenEntryIDs` set.

**Drain Loop:** Max 8 iterations to prevent main thread starvation.

---

## Session Switching

### User-Initiated Switch

Session switching in `switchToSessionFromUser` loads entries for a specific transcript:

```swift
@MainActor
func switchToSessionFromUser(_ session: TranscriptSession) async {
    // Find transcript across all projects
    let transcript = findTranscript(for: session)

    // Switch project if needed
    if currentProjectId != transcript.projectId {
        await ProjectSwitcherState.shared.switchToProject(transcript.projectId)
    }

    // Load entries for this transcript
    let entries = orchestrator.getEntries(forTranscript: transcript.id, ...)

    // Batch cache lookup + map to timeline entries
    setEntries(transcriptTimelineEntries)
    sortEntriesChronologically()

    // Update follow state via policy engine
    await pinAndSwitch(session)

    currentSessionId = session.identifier
}
```

**Note:** Session switching loads a specific transcript's entries but the timeline still shows all sessions in the main view. The `currentSessionId` is used for inventory UI selection, not timeline filtering.

---

## Background Task Coordination

### Structured Concurrency

Background tasks are managed via a single parent Task with structured concurrency:

```swift
self.backgroundTasks = Task { [weak self] in
    await withTaskGroup(of: Void.self) { group in
        // Task 1: Debounced transcript updates
        group.addTask { await self?.watchForDebouncedTranscriptUpdates() }

        // Task 2: Health monitoring with auto-recovery
        group.addTask { await self?.healthMonitor.startMonitoring(...) }
    }
}

func stopMonitoring() {
    backgroundTasks?.cancel()
    backgroundTasks = nil
    Task { await healthMonitor.stopMonitoring() }
}
```

**Note:** Discovery loop was removed. Transcript discovery is now handled by `ProjectActivityMonitor` via FSEvents.

### File Watcher (Debounced)

```swift
private func watchForDebouncedTranscriptUpdates() async {
    for await note in NotificationCenter.default.notifications(named: "TranscriptUpdated") {
        if Task.isCancelled { break }

        await MainActor.run {
            // Only process if notification is for current project
            if note.projectId == currentProjectId || note.projectId == nil {
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
                    await processIncrementalUpdate()
                }
            }
        }
    }
}
```

**Debouncing:** Multiple rapid file writes coalesce to single update after 150ms.

**Multi-project aware:** Filters notifications to current project only.

---

## Cache Update Notifications

### Flow

Cache updates are batched and debounced to prevent UI flood:

```swift
private func setupCacheUpdateNotifications() {
    cacheUpdateObserver = NotificationCenter.default.addObserver(
        forName: .timelineCacheUpdated,
        object: nil,
        queue: .main
    ) { [weak self] note in
        let keys = (note.userInfo?["keys"] as? [CacheKey]) ?? []

        Task { @MainActor in
            // Accumulate keys
            self?.pendingCacheKeys.formUnion(keys)

            // Debounce: 100ms
            self?.cacheDebounceTask?.cancel()
            self?.cacheDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let keysToRefresh = Array(self?.pendingCacheKeys ?? [])
                self?.pendingCacheKeys.removeAll()
                await self?.refreshCachedEntries(keys: keysToRefresh)
            }
        }
    }
}

private func refreshCachedEntries(keys: [CacheKey]) async {
    // Batch fetch caches with signature verification
    let cacheMap = try orchestrator.getCachedTimelineManyWithSignature(
        keys: keys,
        generatorSignature: generatorSignature()
    )

    // Update entries in-place using O(1) index lookup
    for key in keys {
        if let index = state.indexByCacheKey[key],
           let cache = cacheMap[key] {
            let old = entries[index]
            updateEntry(at: index, with: old.copyWith(summary: cache.presentForm, ...))
        }
    }
}
```

**Batching:** Keys accumulated in `pendingCacheKeys` set, processed after 100ms debounce.

**Efficiency:** Batch cache lookup via `getCachedTimelineManyWithSignature`, O(1) entry lookup via `indexByCacheKey`.

---

## Observable Patterns

### SwiftUI Integration

```swift
// ContentView.swift
@Environment(ConversationMonitor.self) private var monitor

var body: some View {
    List(monitor.visibleEntries, id: \.id) { entry in
        TimelineEntryRow(entry: entry)
    }
}
```

**Observation mechanics:**
- SwiftUI tracks access to `monitor.visibleEntries`
- `visibleEntries` reads `entriesRevision` and `stateRevision` to force observation
- When revision increments, SwiftUI re-renders

**Performance:** Only visible rows re-render (SwiftUI diffing).

---

## Error Handling

### Graceful Degradation

Feed loading uses explicit phase tracking for error handling:

```swift
enum Phase: String {
    case cold      // Not yet loaded
    case loading   // SQL fetch in progress
    case loaded    // Feed loaded successfully
    case failed    // Load failed
}

private func loadFeedFromSQL() async -> Task<Void, Never>? {
    guard phase != .loading else {
        pendingRefreshAfterLoad = true  // Coalesce requests
        return nil
    }

    phase = .loading

    feedHydrationTask = Task {
        do {
            let result = try await dataLoader.loadFeed(projectId: projectId, ...)
            // ... apply entries ...
            phase = .loaded
        } catch {
            lastError = "Failed to load timeline: \(error.localizedDescription)"
            phase = .failed
        }
    }

    return feedHydrationTask
}
```

**Phase tracking:** UI can show loading/error states based on `phase` property.

**Re-entrancy guard:** Duplicate load requests are coalesced via `pendingRefreshAfterLoad`.

---

## Performance Characteristics

| Operation | Latency | Notes |
|-----------|---------|-------|
| Full reload | ~20-35ms | 25 entries + cache from SQL |
| Incremental update | ~10ms | New entries via keyset cursor |
| visibleEntries | <1ms | Suffix slice of array |
| Cache update (batch) | ~3ms | O(1) lookup + batch SQL query |

**Optimization:** Revision-based observation, batch cache lookups, debounced notifications.

---

## Memory Management

### Limits

```swift
// Max entries in memory (configured via MonitorConfig)
state.trim(to: config.maxEntries)  // Default: 25

// seenEntryIDs pruning (managed by TimelineDataLoader)
await loader.pruneSeenIDsIfNeeded(currentEntryIDs: ..., maxEntries: config.maxEntries)

// Cleanup on project switch
seenEntryIDs.removeAll(keepingCapacity: false)
```

**Trade-off:** Small entry limit (25) keeps memory low. TimelineDataLoader manages deduplication set pruning.

---

## Testing

**Manual Testing:**
- Modify transcript file externally, verify debounced update
- Delete cache table, verify regeneration with in-place update
- Switch projects, verify timeline clears and reloads

**Integration Tests:**
- Full lifecycle: start, load feed, incremental update, stop
- Cache update: verify batch in-place mutation
- Project switching: verify cleanup and reload

---

## Cross-References

- **SQL Backend:** `build/docs/architecture/sql-backend.md`
- **Cache + LLM:** `build/docs/components/timeline-cache.md`
- **LLM Processing:** `build/docs/architecture/llm-processing.md`
- **Implementation:** `Contextify/Contextify/ConversationMonitor.swift`
- **Models:** `Contextify/Contextify/TimelineModels.swift`
- **Viewport Tracking:** `Contextify/Contextify/ViewportTrackingCoordinator.swift`
- **Data Loader:** `Contextify/Contextify/TimelineDataLoader.swift`
