---
title: Background Indexing Progress UX Research
type: investigation
date: 2025-12-09
related_todo: P4-FIRST-RUN-INDEXING
---

# Indexing Progress UX - Revised Investigation

**Date:** 2025-12-09
**Log analyzed:** `/private/tmp/transcript-queue-monitor-20251209-103915.log`

## Key Observations from Log Analysis

### 1. Background Indexing Is Highly Volatile

In ~1 minute of activity (10:39:42 to 10:40:59):
- **16 background indexing starts**
- **12 immediate cancellations**
- Only **4** actually ran to completion

Most cycles look like this:
```
10:40:34.892 Starting background indexing...
10:40:34.892 Indexing cancelled
10:40:34.892 Background indexing complete
```

**Why?** Every project switch or re-ingestion triggers `startBackgroundIndexing()`, which first cancels any existing background task:
```swift
backgroundTask?.cancel()
backgroundTask = Task(priority: .utility) { ...
```

Since there's a 5-second sleep before actual work begins, frequent project switches cancel background indexing before it starts.

### 2. When Indexing Does Run, It's Fast

A successful full run (35 projects):
```
10:39:57.310 Starting background indexing...
10:40:05.783 Background indexing complete
```

**Duration:** ~8.5 seconds for 35 projects (~240ms per project average)

Individual project timing varies wildly:
- `contextify` (1193 transcripts): 6+ seconds (heavy)
- `banagale-com` (15 transcripts): 0.036s
- Most small projects: <50ms each

### 3. The Progress Display Shows "Stuttering" Because...

The rapid per-project notifications (~240ms average) combined with:
1. SwiftUI batching (coalesces rapid state changes)
2. Projects that process in <50ms never get rendered
3. Large projects (contextify) appear to "pause" while small ones flash by

**User sees:** "Indexing 1/35... [pause on big project] ...Indexing 18/35... [gone]"

### 4. First-Run vs Incremental: No Special Handling

There's no distinction between "cold start" (empty DB) and "warm start" (mostly indexed). The same `startBackgroundIndexing()` runs either way.

**First run concerns:**
- On App Store version, if user switches projects before background indexing completes, conversations may appear empty
- The `entryCount == 0` check in `FastPathIngestionCoordinator.swift:233` tries to force-reset transcripts that show no entries, but this is reactive, not proactive

## Revised Recommendations

### Don't Slow Down the Progress Display

You're right - if indexing is fast (8s total), artificially slowing display would be distracting. The real issues are:

1. **Frequent cancellation** - most indexing cycles never run
2. **No completion feedback** - just disappears
3. **First-run reliability** - empty conversations in App Store version

### Recommendation A: Suppress Progress for Fast Cycles

Only show progress if indexing will take meaningful time:

```swift
private func handleBackgroundProgress(total: Int, remaining: Int) {
    guard total > 0 else {
        backgroundIngestMessage = nil
        return
    }

    // Don't show progress for small batches (fast indexing)
    // User won't benefit from seeing "Indexing 3/3 projects..."
    let significantThreshold = 10
    guard total >= significantThreshold else {
        backgroundIngestMessage = nil
        return
    }

    if remaining <= 0 {
        // Brief completion feedback
        backgroundIngestMessage = "Indexed \(total) projects ✓"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if self.backgroundIngestMessage?.starts(with: "Indexed") == true {
                self.backgroundIngestMessage = nil
            }
        }
        return
    }

    let currentlyProcessing = total - remaining + 1
    backgroundIngestMessage = "Indexing \(currentlyProcessing)/\(total) projects…"
}
```

### Recommendation B: Debounce Background Indexing Start

Reduce cancellation churn by waiting for activity to settle:

```swift
private var backgroundDebounceTask: Task<Void, Never>?

private func startBackgroundIndexing() {
    backgroundDebounceTask?.cancel()

    // Wait for user activity to settle before starting
    backgroundDebounceTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second debounce
        guard !Task.isCancelled else { return }
        self.actuallyStartBackgroundIndexing()
    }
}
```

### Recommendation C: First-Run Detection and Priority

For App Store builds with empty DB, prioritize completing initial indexing:

```swift
private func startBackgroundIndexing() {
    let isFirstRun = checkIsFirstRun() // e.g., total entry count == 0

    if isFirstRun {
        // Higher priority, shorter delay, don't cancel on project switch
        log.info("[ORCH-BACKGROUND] First-run indexing - priority elevated")
        // ... different behavior
    }
}
```

### Recommendation D: Track "Initial Indexing Complete" State

Add a persistent flag that tracks whether first-run indexing has completed:

```swift
// In DatabaseManager or similar
var hasCompletedInitialIndexing: Bool {
    get { UserDefaults.standard.bool(forKey: "hasCompletedInitialIndexing") }
    set { UserDefaults.standard.set(newValue, forKey: "hasCompletedInitialIndexing") }
}
```

This allows:
- Showing a different UI during first run ("Setting up..." vs "Indexing...")
- Warning users if they search before initial indexing completes
- Not cancelling initial indexing on project switch

## The Real Problem: App Store First-Run

The DMG build doesn't have this issue because:
1. Direct filesystem access means instant parsing
2. No sandbox permission dance
3. User likely has existing data from previous sessions

The App Store build:
1. Requires onboarding wizard for permissions
2. Starts with empty DB
3. Background indexing gets cancelled repeatedly as user explores
4. Result: conversations appear empty until background indexing eventually completes

**Priority fix:** Don't cancel initial indexing on project switch. Let it run to completion at least once.

## Summary

| Issue | Severity | Recommendation |
|-------|----------|----------------|
| Progress display stuttering | Low | Suppress for small batches (<10 projects) |
| No completion feedback | Low | Show "Indexed X projects ✓" briefly |
| Frequent cancellation | Medium | Debounce background indexing start |
| First-run empty conversations | **High** | Don't cancel initial indexing on project switch |
| No first-run tracking | Medium | Add `hasCompletedInitialIndexing` flag |

## Files Involved

- `AppStateOrchestrator.swift:544-597` - Background indexing logic
- `StatusBarViewModel.swift:179-191` - Progress display handler
- `FastPathIngestionCoordinator.swift:232-248` - Entry count check / force reset
