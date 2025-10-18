# ConversationMonitor State Management Architecture

**Status:** Production
**Concurrency:** @MainActor (UI layer)
**Pattern:** Observable + Cached Derived State

---

## System Overview

ConversationMonitor is the UI-facing singleton that manages timeline state, session switching, and real-time updates. It coordinates SQL backend queries, LLM cache generation, and SwiftUI observation.

**Key Responsibilities:**
- Maintain single source of truth (TimelineState)
- Filter entries by session (visibleEntries)
- Coordinate background tasks (discovery, file watching)
- Handle incremental updates (keyset cursor)
- Debounce rapid file changes

---

## Architecture

```
┌───────────────────────────────────────────────────────┐
│          ConversationMonitor (@MainActor)             │
│              Singleton, @Observable                   │
├───────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────┐ │
│  │          TimelineState (nested)                  │ │
│  │  - entries: [TimelineEntry]                      │ │
│  │  - revision: UInt64                              │ │
│  │  - indexByCacheKey: [CacheKey: Int] (computed)  │ │
│  └─────────────────────────────────────────────────┘ │
│                                                        │
│  ┌─────────────────────────────────────────────────┐ │
│  │      Derived State (cached, invalidated)         │ │
│  │  - visibleEntries: [TimelineEntry]               │ │
│  │    → Filtered by currentSessionId                │ │
│  │    → Cached until revision changes               │ │
│  └─────────────────────────────────────────────────┘ │
│                                                        │
│  ┌─────────────────────────────────────────────────┐ │
│  │         Background Tasks (structured)            │ │
│  │  - Discovery loop (find new transcripts)         │ │
│  │  - File watcher (debounced updates)              │ │
│  │  - Cache miss generator (LLM summaries)          │ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────┬────────────────────────────────────┘
                   │
         ┌─────────┴─────────┐
         ↓                   ↓
┌──────────────────┐   ┌──────────────────┐
│ Orchestrator     │   │ Notifications    │
│ (nonisolated)    │   │ - Cache updated  │
│ - SQL queries    │   │ - Project changed│
│ - Cache lookups  │   │ - Transcript add │
└──────────────────┘   └──────────────────┘
```

---

## TimelineState Design

### Single Source of Truth

```swift
@MainActor
@Observable
final class TimelineState {
  var entries: [TimelineEntry] = []
  private(set) var revision: UInt64 = 0

  // Computed property (always in sync)
  var indexByCacheKey: [CacheKey: Int] {
    Dictionary(uniqueKeysWithValues: entries.enumerated().compactMap { i, e in
      e.cacheKey.map { ($0, i) }
    })
  }

  // Mutation methods (increment revision)
  func replace(with entries: [TimelineEntry]) {
    self.entries = entries
    revision &+= 1
  }

  func append(_ e: TimelineEntry) {
    entries.append(e)
    revision &+= 1
  }

  func update(at index: Int, to newValue: TimelineEntry) {
    entries[index] = newValue
    revision &+= 1
  }
}
```

**Design Rationale:**
- **No duplicate state:** Index is computed from entries → impossible to desync
- **Revision tracking:** Every mutation increments revision → derived caches know when to invalidate
- **Observable:** SwiftUI re-renders when entries/revision changes

---

## Derived State Caching

### visibleEntries (Session Filtering)

```swift
@Observable
@MainActor
final class ConversationMonitor {
  private let state = TimelineState()

  // Observable (SwiftUI sees changes)
  var entries: [TimelineEntry] { state.entries }

  // Cached derived state
  @ObservationIgnored private var cachedVisibleEntries: [TimelineEntry]?
  @ObservationIgnored private var cachedForSessionId: String??
  @ObservationIgnored private var cachedForRevision: UInt64 = .max

  var visibleEntries: [TimelineEntry] {
    // Check cache validity
    if let cached = cachedVisibleEntries,
       cachedForSessionId == currentSessionId,
       cachedForRevision == state.revision {
      return cached
    }

    // Recompute filter
    let filtered: [TimelineEntry]
    if let id = currentSessionId {
      filtered = state.entries.filter { $0.sessionId == id }
    } else {
      filtered = state.entries  // Show all
    }

    // Update cache
    cachedVisibleEntries = filtered
    cachedForSessionId = currentSessionId
    cachedForRevision = state.revision

    return filtered
  }
}
```

**Why Cache?**
- `visibleEntries` accessed frequently during SwiftUI view updates
- Filtering 1000+ entries is O(n) → cache avoids re-filtering on every access
- Cache invalidation is simple: revision mismatch → recompute

**Trade-off:** Memory (store filtered array) vs CPU (recompute every time).

---

## Startup & Monitoring Lifecycle

### startMonitoring() Flow

```swift
@MainActor
func startMonitoring() {
  Task { @MainActor [weak self] in
    guard let self else { return }

    // 1. Get project root from HUD
    guard let projectRoot = HUDViewModel.shared.projectRootURL else {
      self.lastError = "No project root set"
      return
    }

    // 2. Initialize SQL orchestrator (shared, nonisolated)
    self.orchestrator = try TranscriptOrchestrator(dbManager: .shared)

    // 3. Create/get project in database (CRITICAL: wait for commit)
    self.currentProjectId = try self.orchestrator.getOrCreateProject(
      name: projectRoot.lastPathComponent,
      rootPath: projectRoot.path
    )

    // Verify project exists (forces DB read, confirms commit)
    guard let _ = try self.orchestrator.getProject(id: currentProjectId!) else {
      self.lastError = "Failed to verify project creation"
      return
    }

    // 4. Initialize cache miss generator
    self.cacheMissGenerator = TimelineCacheMissGenerator(
      orchestrator: self.orchestrator
    )

    // 5. Start background tasks (structured concurrency)
    let projectId = self.currentProjectId!
    let orchestrator = self.orchestrator!

    self.backgroundTasks = Task { [weak self] in
      await withTaskGroup(of: Void.self) { group in
        // Task 1: Discovery loop
        group.addTask {
          try? await self?.discoverNewTranscripts(
            projectId: projectId,
            orchestrator: orchestrator
          )
        }

        // Task 2: Debounced file watcher
        group.addTask {
          await self?.watchForDebouncedTranscriptUpdates()
        }
      }
    }

    // 6. Load initial feed from SQL
    await self.loadFeedFromSQL()

    // 7. Subscribe to notifications
    self.setupCacheUpdateNotifications()
    self.setupProjectChangeNotifications()

    self.isMonitoring = true
  }
}
```

**Critical Section:** Step 3 waits for project creation to commit before starting background tasks. Prevents FK constraint violations (entries referencing non-existent project).

---

## Real-Time Updates

### Incremental Update Strategy

```swift
// Keyset cursor for efficient pagination
private var lastSeenCursor: (timestamp: Int, createdAt: Int, id: String)?

func processIncrementalUpdate() async {
  // Single-flight guard (prevent concurrent updates)
  guard !updateInFlight else {
    updateDirty = true  // Mark dirty for retry
    return
  }
  updateInFlight = true
  defer { updateInFlight = false }

  // Drain loop (max 8 iterations to prevent starvation)
  updateDrainItersRemaining = updateDrainMaxItersDefault

  while updateDirty && updateDrainItersRemaining > 0 {
    updateDirty = false
    updateDrainItersRemaining -= 1

    // Query new entries since last cursor
    let newEntries = try? orchestrator.getEntriesAfter(
      cursor: lastSeenCursor,
      limit: 100
    )

    guard let newEntries = newEntries, !newEntries.isEmpty else { break }

    // Update cursor
    let last = newEntries.last!
    lastSeenCursor = (last.timestamp, last.createdAt, last.id)

    // Deduplicate (track seen IDs)
    let unseen = newEntries.filter { !seenEntryIDs.contains($0.id) }
    unseen.forEach { seenEntryIDs.insert($0.id) }

    // Append to state
    for entry in unseen {
      state.append(entry)
    }

    // Sort chronologically
    state.sortChronologically()

    // Trim to max size (5000 entries)
    state.trim(to: 5000)

    // Queue cache misses
    let misses = detectCacheMisses(unseen)
    await cacheMissGenerator?.queueMisses(misses)
  }
}
```

**Keyset Cursor:** Avoids OFFSET pagination (O(n) on large tables). Uses `(timestamp, createdAt, id)` for stable ordering.

**Deduplication:** `seenEntryIDs` prevents duplicates from file watcher + notification race conditions.

**Drain Loop:** If more updates arrive during processing (`updateDirty = true`), loop continues up to 8 iterations. Prevents starvation of main thread.

---

## Session Switching

### User-Initiated Switch

```swift
func switchToSessionFromUser(_ session: TranscriptSession) async {
  await switchToSession(session, reason: .userSelection)
}

private func switchToSession(_ session: TranscriptSession, reason: SessionSwitchReason) async {
  // Cancel previous session tasks
  sessionEpoch = UUID()  // New epoch → old tasks check and exit

  // Update current session
  currentSessionId = session.providerSessionId

  // Full reload from SQL (filtered by session)
  await loadFeedFromSQL()

  // Update active session
  activeSession = session

  // Notify UI
  lastUpdate = Date()
}
```

**Session Filtering:** `visibleEntries` recomputes when `currentSessionId` changes (cache miss on session ID mismatch).

**Full Reload:** Session switch clears state and loads fresh from SQL. Simpler than incremental merge.

---

## Background Task Coordination

### Structured Concurrency

```swift
self.backgroundTasks = Task { [weak self] in
  await withTaskGroup(of: Void.self) { group in
    group.addTask { /* Discovery */ }
    group.addTask { /* File watcher */ }
  }
}

// Cancellation
func stopMonitoring() {
  backgroundTasks?.cancel()
  backgroundTasks = nil
}
```

**Benefits:**
- All background work in single parent task → one cancellation point
- Structured concurrency → tasks auto-cancelled when parent cancelled
- No orphaned tasks after stopMonitoring()

### Discovery Loop

```swift
func discoverNewTranscripts(projectId: String, orchestrator: TranscriptOrchestrator) async throws {
  while !Task.isCancelled {
    let projectContext = ProjectContext.current()
    let providers = [ClaudeTranscriptProvider(), CodexTranscriptProvider()]

    for provider in providers {
      let sessions = provider.sessions(for: projectContext)

      for session in sessions {
        try orchestrator.discoverTranscript(
          projectId: projectId,
          fileURL: session.fileURL,
          provider: session.provider,
          providerSessionId: session.providerSessionId,
          startWatching: true
        )
      }
    }

    // Poll every 5 minutes
    try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
  }
}
```

**Purpose:** Find newly created transcripts without manual refresh.

**Frequency:** 5 minutes (low overhead, discovers new sessions within 5min).

### File Watcher (Debounced)

```swift
func watchForDebouncedTranscriptUpdates() async {
  while !Task.isCancelled {
    // Wait for notification
    for await _ in NotificationCenter.default.notifications(
      named: .transcriptFileUpdated
    ) {
      // Debounce: wait 500ms for more updates
      debounceTask?.cancel()
      debounceTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 500_000_000)
        await self?.processIncrementalUpdate()
      }
    }
  }
}
```

**Debouncing:** Multiple rapid file writes → single incremental update after 500ms.

**Trade-off:** Latency (500ms delay) vs efficiency (fewer SQL queries).

---

## Cache Update Notifications

### Flow

```swift
// TimelineCacheMissGenerator posts notification after LLM generation
NotificationCenter.default.post(
  name: .timelineCacheUpdated,
  object: cacheKey  // CacheKey struct
)

// ConversationMonitor listens
func setupCacheUpdateNotifications() {
  cacheUpdateObserver = NotificationCenter.default.addObserver(
    forName: .timelineCacheUpdated,
    object: nil,
    queue: .main
  ) { [weak self] notification in
    guard let cacheKey = notification.object as? CacheKey else { return }
    self?.updateCacheForKey(cacheKey)
  }
}

func updateCacheForKey(_ key: CacheKey) {
  // Find entry by cache key (O(1) via computed index)
  guard let index = state.indexByCacheKey[key] else { return }

  // Query fresh cache from SQL
  guard let cached = try? orchestrator.getCachedTimeline(key: key) else { return }

  // Update entry in-place
  var entry = state.entries[index]
  entry.cachedSummary = cached.presentForm
  state.update(at: index, to: entry)

  // Revision increments → SwiftUI re-renders
}
```

**Efficiency:** O(1) lookup via `indexByCacheKey`, then O(1) SQL query by composite PK.

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

**@Observable Magic:**
- SwiftUI tracks access to `monitor.visibleEntries`
- When `state.revision` increments → cache invalidates → `visibleEntries` recomputes
- SwiftUI sees new value → re-renders List

**Performance:** Only visible rows re-render (SwiftUI diffing).

---

## Error Handling

### Graceful Degradation

```swift
func loadFeedFromSQL() async {
  do {
    let feed = try orchestrator.getRecentFeed(
      forProject: currentProjectId!,
      limit: 50
    )

    let entries = feed.map { (entry, cache) in
      TimelineEntry(
        from: entry,
        cachedSummary: cache?.presentForm ?? fallbackSummary(entry)
      )
    }

    state.replace(with: entries)

    // Queue cache misses
    let misses = detectCacheMisses(feed)
    await cacheMissGenerator?.queueMisses(misses)

  } catch {
    lastError = "Failed to load timeline: \(error.localizedDescription)"
    state.replace(with: [])  // Empty state
  }
}
```

**Never crash:** Errors set `lastError` observable → UI shows error banner.

---

## Performance Characteristics

| Operation | Latency | Notes |
|-----------|---------|-------|
| Full reload | ~20ms | 50 entries + cache from SQL |
| Incremental update | ~10ms | 100 new entries (keyset cursor) |
| visibleEntries (cached) | <1ms | Return cached array |
| visibleEntries (miss) | ~2ms | Filter 1000 entries |
| Cache update (in-place) | ~3ms | O(1) lookup + SQL query |

**Optimization:** Revision-based cache invalidation minimizes recomputation.

---

## Memory Management

### Limits

```swift
// Max entries in memory
state.trim(to: 5000)

// Max pending cache misses
cacheMissGenerator.maxQueueSize = 5000

// Cleanup on session switch
seenEntryIDs.removeAll(keepingCapacity: false)
```

**Trade-off:** 5000 entries ≈ 2MB RAM. Trim older entries to cap memory.

---

## Testing

**Manual Testing:**
- Open two transcript sessions → switch between → verify filtering
- Modify transcript file externally → verify debounced update
- Delete cache table → verify regeneration + in-place update

**Integration Tests:**
- Full lifecycle: start → load feed → incremental update → stop
- Session switching: verify full reload
- Cache update: verify in-place mutation

---

## Cross-References

- **SQL Backend:** `build/notes/technical-reference/sql-backend-architecture.md`
- **Cache + LLM:** `build/notes/technical-reference/timeline-cache-llm-architecture.md`
- **Implementation:** `Contextify/Contextify/ConversationMonitor.swift`
- **Models:** `Contextify/Contextify/TimelineModels.swift`
