# Bug: Status Bar Shows "Processing 0 items"

**Status:** Active
**Priority:** P2 (Cosmetic race condition)
**Reported:** 2025-10-28
**Component:** TimelineCacheMissGenerator, StatusBarView

## Problem Statement

Status bar displays "Processing 0 items (~3s)" with a spinner, then shows "1 Error" after processing completes. This is confusing because:
1. User sees "0 items" being processed (nonsensical)
2. Implies work is being done when queue is empty
3. Creates perception that the app is stuck/broken

## Current Behavior

**Observed Sequence:**
```
1. App opens
2. Status bar: "Processing 0 items (~3s)" [spinner]
3. After ~3s: "1 Error"
4. After clean + rebuild: "Processing 0 items" → "Up to date"
```

**Why it happens:**
Clean build → fresh state → same race condition but different outcome

## Root Cause: Race Condition

### Code Flow
```swift
// TimelineCacheMissGenerator.swift:148-207
private func processQueue() async {
    while !pendingMisses.isEmpty {
        if Task.isCancelled { break }
        isProcessing = true              // ← Set INSIDE loop
        notifyQueueChanged()

        // Process batch...
        // Remove items from pendingMisses

        // [RACE WINDOW HERE]
        // Stats read: isProcessing=true, pendingMisses.count=0 ← BUG!
    }

    isProcessing = false                 // ← Set AFTER loop exits
    notifyQueueChanged()
}
```

### The Race Window

**Thread 1 (Processing):**
```
1. Process last item in batch
2. Remove from pendingMisses → count=0
3. Check while condition: isEmpty=true
4. [PAUSE - about to exit loop]
```

**Thread 2 (Stats Observer):**
```
5. makeQueueStats() called
6. Read isProcessing=true (still set from line 150)
7. Read pendingMisses.count=0 (already cleared)
8. Return QueueStats(pending=0, isProcessing=true) ← INCONSISTENT!
```

**Thread 1 (continues):**
```
9. Exit loop
10. Set isProcessing=false (line 203)
11. Notify stats changed again
```

### Why StatusBarView Shows This State

```swift
// StatusBarView.swift:174
} else if let viewModel, viewModel.isProcessing {
    // Processing state - shows even with queueDepth=0!
    Text("Processing \(viewModel.queueDepth) items")
    Text("(~\(viewModel.estimatedSecondsRemaining)s)")
}
```

**Condition check order:**
1. ✅ Has errors? → Show errors (line 159)
2. ✅ Is processing? → Show "Processing N items" (line 174)  ← Triggers with N=0
3. ✅ Has pending? → Show "N pending" (line 199)
4. ✅ Else → Show "Up to date" (line 206)

## Related Issues

### Issue 1: Incorrect `currentBatchSize`
```swift
// Line 472
currentBatchSize: isProcessing ? maxBatchSize : 0,
```

Assumes full batch when `isProcessing=true`, but final batch may be smaller.

### Issue 2: ETA Calculated from Empty Queue
```swift
// Line 454-460
let fullBatchesRemaining = max(0, pendingMisses.count / maxBatchSize)
let partialBatchETA = Double(inFlightCount) * avgSecondsPerItem
```

When `pendingMisses.count=0` but `inFlightCount>0`, ETA is non-zero → Shows "(~3s)"

### Issue 3: `inFlightCount` Not Cleared
`inFlightCount` tracks items currently being processed, but may not be cleared atomically with `pendingMisses`.

## Proposed Solutions

### Option A: Guard Against Inconsistent State (Simple Fix)

Update StatusBarView to check for nonsensical state:

```swift
// StatusBarView.swift:174
} else if let viewModel, viewModel.isProcessing && viewModel.queueDepth > 0 {
    // Only show "Processing" if there's actually items to process
    Text("Processing \(viewModel.queueDepth) items")
}
```

**Pros:** Quick fix, handles race condition gracefully
**Cons:** Doesn't fix root cause, may flicker between states

### Option B: Atomic State Updates (Proper Fix)

Ensure `isProcessing` and `pendingMisses` are read/written atomically:

```swift
// TimelineCacheMissGenerator.swift
private func makeQueueStats() -> QueueStats {
    // Calculate everything based on actual work state
    let pending = pendingMisses.count
    let inFlight = inFlightCount
    let actuallyProcessing = (pending > 0 || inFlight > 0) && isProcessing

    return QueueStats(
        pending: pending,
        isProcessing: actuallyProcessing,  // ← Consistent check
        currentBatchSize: inFlight,        // ← Use actual in-flight count
        ...
    )
}
```

**Pros:** Fixes root cause, accurate state
**Cons:** More complex, requires careful testing

### Option C: Debounce Stats Updates

Add delay before reading stats to let processing settle:

```swift
private func notifyQueueChanged() {
    Task {
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms debounce
        for await continuation in statsContinuations.values {
            continuation.yield(makeQueueStats())
        }
    }
}
```

**Pros:** Smooths over race window
**Cons:** Adds latency, doesn't fix root issue

## Recommended Solution

**Hybrid: Option A + Option B (partial)**

1. **Immediate:** Add guard in StatusBarView (Option A)
   - Prevents showing "Processing 0 items"
   - User sees "Up to date" instead during race window

2. **Follow-up:** Fix `currentBatchSize` to use `inFlightCount` (Option B partial)
   - More accurate ETA calculations
   - Better reflects actual work being done

## Implementation

### Fix 1: Guard in StatusBarView
```swift
} else if let viewModel, viewModel.isProcessing && viewModel.queueDepth > 0 {
    // Processing state (only show if items exist)
    HStack(spacing: 6) {
        ProgressView()
        Text("Processing \(viewModel.queueDepth) items")
    }
```

### Fix 2: Use `inFlightCount` for batch size
```swift
return QueueStats(
    pending: pendingMisses.count,
    isProcessing: isProcessing,
    currentBatchSize: inFlightCount,  // ← Actual count, not assumed maxBatchSize
    estimatedSecondsRemaining: estimatedSeconds,
    recentErrorCount: errorCount,
    topErrorReason: topError
)
```

## Testing Plan

### Reproduce Bug
1. Start app with transcript containing 1-5 new entries
2. Observe status bar during processing
3. Should see "Processing 0 items" near end of queue

### Verify Fix
1. Apply StatusBarView guard
2. Rebuild and restart
3. Process small queue (1-5 items)
4. Should NOT see "Processing 0 items" - should skip directly to "Up to date"

### Edge Cases
- Empty queue from start → Should show "Up to date"
- Single item → Process → Should show "Processing 1 item" then "Up to date"
- Large queue → Process → Should never show "Processing 0"

## Related Files

- `Contextify/Contextify/TimelineCacheMissGenerator.swift` (state management)
- `Contextify/Contextify/StatusBarView.swift` (display logic)
- `Contextify/Contextify/StatusBarViewModel.swift` (stats aggregation)

## User Impact

**Current:** Confusing UI state that makes app appear broken
**After Fix A:** Smooth transition, never shows nonsensical "0 items"
**After Fix B:** More accurate ETAs and processing indicators
