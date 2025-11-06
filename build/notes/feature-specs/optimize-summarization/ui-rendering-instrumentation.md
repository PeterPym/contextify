# UI Rendering & Thread Instrumentation Plan

## Goal
Isolate UI lag during project switching by instrumenting SwiftUI rendering and main thread operations.

## Current Status
- Database/business logic operations are fast (1-3ms)
- Gap between operations shows 60-130ms total
- No 8+ second lag captured in current logs
- Need to instrument UI layer to find blocking operations

## Areas to Instrument

### 1. SwiftUI View Body Evaluation

**Problem:** SwiftUI `body` re-evaluation can block the main thread if expensive.

**Solution:** Add timing to key views using `.task` and `.onChange` modifiers.

**Files to modify:**
- `ConversationTimelineView.swift` - Timeline rendering
- `TimelineEntryRow.swift` - Individual row rendering
- `ProjectSwitcherView.swift` - Project tab rendering
- `ContentView.swift` - Main container

**Approach:**
```swift
import OSLog
private let log = Logger(subsystem: "dev.contextify", category: "UIRender")

var body: some View {
    let _ = log.info("[UIOPT-RENDER-START] ConversationTimelineView.body evaluated")

    return VStack {
        // ... existing content
    }
    .task(id: monitor.entries.count) {
        // Log when entries change triggers re-render
        log.info("[UIOPT-RENDER-ENTRIES] Timeline re-rendering with \(monitor.entries.count, privacy: .public) entries")
    }
    .onChange(of: monitor.currentProjectId) { oldId, newId in
        log.info("[UIOPT-RENDER-PROJECT] Timeline switching from \(oldId ?? "nil", privacy: .public) to \(newId ?? "nil", privacy: .public)")
    }
}
```

### 2. Main Actor Queue Delays

**Problem:** Tasks waiting in main actor queue can cause lag.

**Solution:** Log when tasks enter/exit main actor execution.

**Approach:**
```swift
// In ConversationMonitor.swift
@MainActor
func setEntries(_ entries: [TimelineEntry]) {
    let start = Date()
    log.info("[UIOPT-MAINACTOR-START] setEntries() executing on main actor")

    self.state.entries = entries

    let elapsed = Date().timeIntervalSince(start)
    log.info("[UIOPT-MAINACTOR-DONE] setEntries() completed in \(String(format: "%.0f", elapsed * 1000), privacy: .public)ms")
}
```

### 3. List/ForEach Rendering

**Problem:** Large lists can cause rendering lag.

**Solution:** Measure list creation time.

**In ConversationTimelineView.swift:**
```swift
private var timelineContent: some View {
    let start = Date()
    let _ = log.info("[UIOPT-LIST-START] Building list with \(monitor.visibleEntries.count, privacy: .public) visible entries")

    return ScrollView {
        LazyVStack(spacing: 8) {
            ForEach(monitor.visibleEntries) { entry in
                TimelineEntryRow(entry: entry)
            }
        }
    }
    .task {
        let elapsed = Date().timeIntervalSince(start)
        log.info("[UIOPT-LIST-DONE] List rendered in \(String(format: "%.0f", elapsed * 1000), privacy: .public)ms")
    }
}
```

### 4. Window/View Lifecycle Events

**Problem:** View appearance/disappearance can block during transitions.

**Solution:** Log lifecycle events.

```swift
var body: some View {
    content
        .onAppear {
            log.info("[UIOPT-LIFECYCLE] ConversationTimelineView appeared")
        }
        .onDisappear {
            log.info("[UIOPT-LIFECYCLE] ConversationTimelineView disappeared")
        }
}
```

### 5. Project Tab Updates

**Problem:** Project tabs might re-render slowly when activeProjectId changes.

**In ProjectSwitcherView.swift:**
```swift
// In the project tab ForEach:
.onChange(of: state.activeProjectId) { oldId, newId in
    log.info("[UIOPT-TABS-UPDATE] Active project changed from \(oldId ?? "nil", privacy: .public) to \(newId ?? "nil", privacy: .public)")
}
```

### 6. Detect Main Thread Blocking

**Problem:** Long-running synchronous work on main thread.

**Solution:** Use Instruments or add signposts for time profiling.

**Approach A - Signposts (native profiling):**
```swift
import os.signpost

let log = OSLog(subsystem: "dev.contextify", category: "Performance")
let signpostID = OSSignpostID(log: log)

os_signpost(.begin, log: log, name: "Project Switch", signpostID: signpostID)
// ... operation ...
os_signpost(.end, log: log, name: "Project Switch", signpostID: signpostID)
```

**Approach B - Detect stalls:**
```swift
// Add to ConversationMonitor
@MainActor
private func detectMainThreadStall() {
    Task { @MainActor in
        var lastCheck = Date()
        while !Task.isCancelled {
            let now = Date()
            let gap = now.timeIntervalSince(lastCheck)

            if gap > 0.1 { // 100ms gap = potential stall
                log.warning("[UIOPT-STALL] Main thread stalled for \(String(format: "%.0f", gap * 1000), privacy: .public)ms")
            }

            lastCheck = now
            try? await Task.sleep(for: .milliseconds(16)) // ~60fps check
        }
    }
}
```

## Implementation Priority

### Phase 1: High-Impact Instrumentation (do first)
1. ✅ Add `[UIOPT-RENDER-ENTRIES]` to ConversationTimelineView when entries change
2. ✅ Add `[UIOPT-MAINACTOR-*]` timing to `setEntries()`
3. ✅ Add `[UIOPT-TABS-UPDATE]` to ProjectSwitcherView activeProjectId change
4. ✅ Add `[UIOPT-LIST-*]` timing to timeline list rendering

### Phase 2: Lifecycle & State Changes
5. Add `.onChange` for key state properties (currentProjectId, entries.count)
6. Add view lifecycle logging (onAppear/onDisappear)
7. Log window focus/activation events

### Phase 3: Advanced Profiling
8. Add main thread stall detection
9. Use Instruments signposts for deep profiling
10. Measure individual row render times (if needed)

## Expected Insights

After instrumentation, logs will show:

**Fast scenario (no lag):**
```
[UIOPT-INPUT] Keyboard shortcut
[UIOPT-TABS-UPDATE] Active project changed
[UIOPT-MONITOR-START] Starting
[UIOPT-RENDER-PROJECT] Timeline switching projects
[UIOPT-SQL-QUERY] Query completed: 50 entries in 2ms
[UIOPT-MAINACTOR-START] setEntries() executing
[UIOPT-MAINACTOR-DONE] setEntries() completed in 1ms
[UIOPT-RENDER-ENTRIES] Timeline re-rendering with 50 entries
[UIOPT-LIST-START] Building list with 50 entries
[UIOPT-LIST-DONE] List rendered in 5ms
[UIOPT-MONITOR-READY] Ready
```

**Slow scenario (8s lag - hypothetical):**
```
[UIOPT-INPUT] Keyboard shortcut
[UIOPT-TABS-UPDATE] Active project changed
... 8 second gap here ...
[UIOPT-MONITOR-START] Starting  ← Would show delay before monitor starts
```

OR

```
[UIOPT-SQL-QUERY] Query completed
[UIOPT-MAINACTOR-START] setEntries() executing
... 8 second gap here ...
[UIOPT-MAINACTOR-DONE] setEntries() completed in 8000ms  ← Main actor blocked!
```

OR

```
[UIOPT-RENDER-ENTRIES] Timeline re-rendering
[UIOPT-LIST-START] Building list
... 8 second gap here ...
[UIOPT-LIST-DONE] List rendered in 8000ms  ← SwiftUI rendering blocked!
```

## Alternative: Use Instruments

For one-time deep analysis:
1. Build Release configuration with Debug symbols
2. Profile with Instruments > Time Profiler
3. Record during slow project switch
4. Examine call tree to find blocking operations

**Advantages:**
- Shows exact stack traces
- CPU time per function
- Thread activity timeline

**Disadvantages:**
- Can't capture in production
- Requires manual profiling session
- Harder to isolate specific scenarios

## Testing Methodology

1. Apply Phase 1 instrumentation
2. Rebuild app
3. Run new monitoring script (captures `[UIOPT-RENDER-*]`, `[UIOPT-MAINACTOR-*]`, `[UIOPT-TABS-*]`, `[UIOPT-LIST-*]`)
4. Switch projects rapidly
5. Try to reproduce 8+ second lag
6. Analyze logs to find which phase takes 8+ seconds

## New Monitoring Script Tags

Add to `scripts/logging/monitor-ui-performance.sh`:
- `[UIOPT-RENDER-*]` - SwiftUI body evaluation
- `[UIOPT-MAINACTOR-*]` - Main actor execution timing
- `[UIOPT-TABS-*]` - Project tab updates
- `[UIOPT-LIST-*]` - List rendering
- `[UIOPT-LIFECYCLE]` - View appear/disappear
- `[UIOPT-STALL]` - Main thread stall detection (>100ms gaps)

## Files to Modify

1. `ConversationTimelineView.swift` - List rendering, lifecycle
2. `TimelineEntryRow.swift` - Row rendering (if needed)
3. `ProjectSwitcherView.swift` - Tab update timing
4. `ConversationMonitor.swift` - Main actor timing for setEntries
5. `ContentView.swift` - Window lifecycle (if needed)
6. `scripts/logging/monitor-ui-performance.sh` - Add new tags to grep pattern
