# ConversationMonitor State Management Architecture

**Status:** Production (with known initialization issues - see Phase 2/3 refactor)
**Concurrency:** @MainActor (UI layer)
**Pattern:** Observable + Cached Derived State
**Known Issues:** Duplicate initialization paths, race conditions during startup

---

## ⚠️ Known Initialization Issues (Phase 2/3 Refactor Needed)

**Date Discovered:** 2025-11-07
**Status:** Phase 1 tactical fix applied, architectural refactor pending

### Problem Summary

ConversationMonitor has evolved **two overlapping initialization paths** that cause duplicate work and race conditions:

1. **Legacy Path** (`startMonitoring()` lines 355-542):
   - Initializes orchestrator, diagnostics, background tasks
   - Calls `loadFeedFromSQL()` at line 509

2. **Coordinator Path** (`onProjectOrSessionChange()` lines 602-695):
   - Loads policy, sessions, cursor, events
   - Calls `loadFeedFromSQL()` at line 644

### Root Causes Identified

#### Issue 1: didSet Observer Cascade (FIXED in Phase 1)
- `startMonitoring()` sets `currentProjectId` inside async Task
- Triggers `didSet` observer → calls `onProjectOrSessionChange()`
- Both paths call `loadFeedFromSQL()` → duplicate database queries

**Fix Applied:** `isInitializing` flag (line 360) blocks `onProjectOrSessionChange()` during `startMonitoring()`

#### Issue 2: Double startMonitoring() Calls (ATTEMPTED FIX FAILED)
- **ContentView.task** (ContentView.swift:85) calls `startMonitoring()` on initial startup
- **Coordinator subscription** (ConversationMonitor.swift:293) receives same initial context
- Both receive same project ID → call `startMonitoring()` twice

**Attempted Fix:** Synchronously set `isMonitoring`/`currentProjectId` before async Task
**Result:** CRASH - violated Swift actor isolation (these are `@MainActor` properties)
**Lesson:** Cannot set `@MainActor` properties synchronously from `@MainActor` context before async Task spawns

#### Issue 3: Actor Isolation Violation
```swift
@MainActor
func startMonitoring(projectId: String) {
    isMonitoring = true        // This is @MainActor
    currentProjectId = projectId  // This is @MainActor

    Task { [weak self] in      // Task NOT isolated to MainActor
        // Properties set above but Task can spawn before didSet completes
        // External observers see torn state
    }
}
```

**Problem:** Properties are set on MainActor, but the Task is NOT MainActor-isolated (CXT-13: removed to prevent UI blocking). This creates a race window where:
- Properties appear set to guards checking them
- But async Task spawns and may access them before isolation completes
- External calls to `onProjectOrSessionChange()` see inconsistent state

### Implications of Double startMonitoring() Calls

**Impact on Application Behavior:**

1. **Database Queries Duplicated**
   - `loadFeedFromSQL()` runs twice for same project
   - ~50ms penalty per duplicate (100ms total wasted)
   - Not catastrophic but inefficient

2. **Background Tasks May Spawn Twice**
   - Discovery loops, file watchers, health monitoring
   - Second call hits `isMonitoring=true` guard and skips (line 354)
   - **BUT** there's a race window before guard activates

3. **Generator Shutdown/Creation Churn**
   - First call shuts down old generator, creates new one
   - Second call (if it passes guard) repeats shutdown
   - Can cause generator to be in inconsistent state during transition

4. **Notification Spam**
   - `conversationMonitoringDidStart` notification fired twice
   - Subscribers may react twice to same event
   - Could cause UI flashing or double-loading

5. **Resource Leaks (Potential)**
   - If second call spawns Task before first completes
   - Both Tasks create orchestrators, diagnostics servers
   - Second one replaces first, but first's cleanup may not finish
   - Diagnostic HTTP server might bind to port twice (should fail gracefully)

6. **User-Visible Issues**
   - Timeline may flash/reload unnecessarily
   - Status bar shows "Starting..." twice
   - Slightly slower startup (~100ms penalty)

**Why It's Bad:**
- **Not immediately breaking** but wastes resources
- **Creates unpredictable timing** - race conditions
- **Makes debugging harder** - which call succeeded?
- **Violates single responsibility** - two systems trying to initialize same thing

**Why It Hasn't Been Caught:**
- Guard at line 354 catches most duplicate calls
- Race window is small (~10ms)
- Database queries are idempotent
- Background tasks handle restart gracefully

### Current Workarounds & Limitations

**What Works:**
- ✅ Single project startup (first call usually succeeds)
- ✅ `isInitializing` flag prevents didSet cascade
- ✅ App doesn't crash on startup
- ✅ Guard at line 354 blocks most duplicates

**What's Broken:**
- ❌ Duplicate `startMonitoring()` calls still happen (logged at TIMELINE-START)
- ❌ Small race window exists before guard activates
- ❌ `onProjectOrSessionChange()` can be called from external sources (project discovery) with torn state
- ❌ Resource waste and unpredictable timing

### Architectural Debt

The code has **six boolean flags** managing state transitions, creating a complex implicit state machine:

```swift
isMonitoring: Bool              // Actively monitoring project
isInitializing: Bool            // Inside startMonitoring() Task
isSwitchingProjects: Bool       // Suppress health monitoring
isReadyForUpdates: Bool         // Gate incremental updates
sessionsLoaded: Bool            // Gate policy reconciliation
isCacheGeneratorActive: Bool    // Generator ready
```

**Problems:**
1. **Implicit dependencies:** `isMonitoring=false` required before `loadFeed` succeeds
2. **No formal invariants:** Can have `isMonitoring=true` but `currentProjectId=nil`
3. **didSet side effects:** Setting one property triggers cascades
4. **Race conditions:** Flags checked off MainActor, set on MainActor
5. **2,634 line file:** God Object anti-pattern

### Recommended Fix Approach (Phase 2/3)

**Phase 2: Split Project vs Session Changes** (4-8 hours)
```swift
// Remove didSet observers entirely
private var currentProjectId: String?  // No didSet
private var currentSessionId: String?  // No didSet

// Explicit methods instead
func onProjectChange() {
    // Full reset: policy, sessions, cursor, feed, events
    Task {
        await loadPolicyForCurrentProject()
        await loadAllSessionsFromDatabase()
        await reconcilePolicy()
        await loadCursor()
        await loadFeedFromSQL()
        await replayEvents()
        isReadyForUpdates = true
    }
}

func onSessionChange() {
    // Minimal reset: just reload feed for new session
    Task {
        await loadFeedFromSQL()
    }
}
```

**Benefits:**
- No implicit cascades via didSet
- Clear separation of concerns
- Easier to test (call methods directly)
- Predictable execution order

**Phase 3: Extract Initialization Module** (2-3 days)
```swift
actor ConversationMonitorBootstrap {
    func initialize(projectId: String) async throws -> MonitoringSession {
        // All initialization logic here
        // Returns immutable session descriptor
    }
}

@MainActor @Observable
class ConversationMonitor {
    private var session: MonitoringSession?

    func startMonitoring(projectId: String) async {
        guard session?.projectId != projectId else { return }

        do {
            let newSession = try await bootstrap.initialize(projectId: projectId)
            self.session = newSession
            // Setup complete, start background tasks
        } catch {
            // Handle error
        }
    }
}
```

**Benefits:**
- Single initialization path (no legacy/coordinator split)
- Actor isolation prevents concurrent initialization
- Formal state machine (MonitoringSession type)
- Testable in isolation
- Foundation for multi-window support

**Alternative: Remove ContentView's Direct Call**
```swift
// ContentView.swift line 85 - DELETE THIS:
await TimelineIntegration.shared.startMonitoring(projectId: context.id)

// Let ONLY the coordinator subscription handle initialization
// This is the quickest fix but doesn't solve architectural issues
```

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
    // Check cache validity (revision + session ID)
    if let cached = cachedVisibleEntries,
       cachedForSessionId == currentSessionId,
       cachedForRevision == state.revision {
      return cached
    }

    // Recompute filter from state.entries
    let filtered = currentSessionId.map { id in
      state.entries.filter { $0.sessionId == id }
    } ?? state.entries  // nil → show all

    // Update cache keys: sessionId + state.revision
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
  defer {
    updateInFlight = false
    updateDrainItersRemaining = updateDrainMaxItersDefault  // Reset countdown for next call
  }

  // Drain loop (max 8 iterations to prevent starvation)
  updateDrainItersRemaining = updateDrainMaxItersDefault

  while updateDirty && updateDrainItersRemaining > 0 {
    updateDirty = false
    updateDrainItersRemaining -= 1  // Countdown each iteration

    // Query new entries since last cursor
    let newEntries = try? orchestrator.getEntriesAfter(
      cursor: lastSeenCursor,
      limit: 100
    )

    guard let newEntries = newEntries, !newEntries.isEmpty else { break }

    // Update cursor (stable max on composite key)
    if let latest = newEntries.max(by: { a, b in
      if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
      if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
      return a.id < b.id
    }) {
      lastSeenCursor = (timestamp: latest.timestamp, createdAt: latest.createdAt, id: latest.id)
    }

    // Deduplicate (track seen database entry IDs - String, not UUID)
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

**Frequency:** 5 minutes (hardcoded). No UI to configure yet; future plan: 1/5/15 min intervals or manual trigger only.

### File Watcher (Debounced)

```swift
func watchForDebouncedTranscriptUpdates() async {
  while !Task.isCancelled {
    // Wait for notification
    for await _ in NotificationCenter.default.notifications(
      named: .transcriptFileUpdated
    ) {
      // Debounce: wait 150ms for more updates
      debounceTask?.cancel()
      debounceTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms (matches MonitorConfig.fileWatcherDebounce)
        await self?.processIncrementalUpdate()
      }
    }
  }
}
```

**Debouncing:** Multiple rapid file writes → single incremental update after 150ms.

**macOS < 26.0 Note:** LLM work is skipped with fallback summaries (no errors).

**Trade-off:** Latency (150ms delay) vs efficiency (fewer SQL queries).

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

  // Query fresh cache from SQL (single fetch by composite key)
  guard let cached = try? orchestrator.getCachedTimeline(key: key) else { return }

  // Update entry in-place
  var entry = state.entries[index]
  entry.cachedSummary = cached.presentForm
  state.update(at: index, to: entry)

  // Revision increments → SwiftUI re-renders
}
```

**Efficiency:** O(1) lookup via `indexByCacheKey` (computed from entries), then single SQL fetch by composite PK `(content_sha256, window_sha256)`.

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

- **SQL Backend:** `build/docs/architecture/sql-backend.md`
- **Cache + LLM:** `build/docs/components/timeline-cache.md`
- **Implementation:** `Contextify/Contextify/ConversationMonitor.swift`
- **Models:** `Contextify/Contextify/TimelineModels.swift`
