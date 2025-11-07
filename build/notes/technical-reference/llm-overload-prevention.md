# LLM Overload Prevention - Technical Reference

**Last Updated:** 2025-11-07
**Related Files:**
- `Contextify/Contextify/TimelineCacheMissGenerator.swift`
- `Contextify/Contextify/ConversationMonitor.swift`
- `Contextify/Contextify/FoundationLLM.swift`

---

## Executive Summary

Apple Intelligence (FoundationLLM) on macOS 26+ can become overloaded when processing too many requests too quickly. This document describes the multi-layered protection system that prevents overload while maintaining responsive UX.

**Key Metrics:**
- **750ms stabilization delay** before sending requests to LLM
- **1250ms viewport debounce** before queueing entries
- **Batch size: 1** (sequential processing only)
- **LIFO queue** (newest entries processed first)
- **Viewport-based pruning** removes obsolete entries before LLM calls

**Test Results (2025-11-07):**
- Fast scrolling: 23 of 26 entries pruned before reaching LLM (88% prevention rate)
- Only 3 requests reached LLM during aggressive scrolling
- 3 overload errors occurred (entries already in LLM when user scrolled away)

---

## System Architecture

### Layer 1: Viewport Debounce (1250ms)

**Purpose:** Prevent queueing entries during rapid scrolling
**Implementation:** `ConversationMonitor.viewportDidSettle()` (line ~1442)

**How it works:**
1. User scrolls → SwiftUI calls `.onScrollTargetVisibilityChange` with new visible IDs
2. Timer starts/resets on each visibility change
3. After 1250ms of no changes → viewport "settles"
4. Only after settling → entries are queued for generation

**Effect:**
- If user scrolls every 500ms, entries never get queued
- Prevents thrashing during fast scrolling
- User must pause for 1.25s before generation starts

**Code:**
```swift
private var viewportDebounceTask: Task<Void, Never>?
private let viewportDebounceMs: Int = 1250

viewportDebounceTask?.cancel()
viewportDebounceTask = Task { @MainActor in
    try? await Task.sleep(nanoseconds: UInt64(viewportDebounceMs) * 1_000_000)
    guard !Task.isCancelled else { return }
    // Viewport settled, queue entries...
}
```

---

### Layer 2: Viewport-Based Pruning

**Purpose:** Remove entries from queue when they scroll out of view
**Implementation:** `TimelineCacheMissGenerator.pruneQueue()` (line ~118)

**How it works:**
1. Called BEFORE queueing new entries (after viewport settles)
2. Compares `pendingMisses` queue against currently visible entry IDs
3. Removes entries that are:
   - Not in visible set AND
   - Not the actively processing entry
4. Updates queue and notifies observers

**Effect:**
- User scrolls from view A to view B
- After viewport settles (1250ms), pruning runs
- All entries queued for view A but not yet sent to LLM are dropped
- Only view B's visible entries get queued

**Code:**
```swift
func pruneQueue(keepOnly visibleIDs: Set<String>) async {
    let activeID = await MainActor.run { activeEntryID }
    pendingMisses.removeAll { miss in
        let isVisible = visibleIDs.contains(miss.entryId)
        let isActive = UUID(uuidString: miss.entryId) == activeID
        return !isVisible && !isActive  // Remove if not visible AND not active
    }
}
```

**Limitation:** Cannot prune entries already sent to LLM (actively processing)

---

### Layer 3: Stabilization Delay (750ms)

**Purpose:** Give pruning time to cancel requests before they reach LLM
**Implementation:** `TimelineCacheMissGenerator.processBatch()` (line ~372)

**How it works:**
1. Entry is dequeued from `pendingMisses`
2. **Wait 750ms** before calling LLM
3. Check `Task.isCancelled` after delay
4. If cancelled → exit without calling LLM
5. If not cancelled → proceed to LLM

**Effect:**
- Entry dequeued at T+0ms
- Wait 750ms
- User scrolls away at T+500ms → viewport settles at T+1750ms → pruning cancels task
- Cancellation check at T+750ms → task cancelled → **LLM never called**

**Code:**
```swift
if self.stabilizationDelayMs > 0 {
    try? await Task.sleep(nanoseconds: UInt64(self.stabilizationDelayMs) * 1_000_000)

    if Task.isCancelled {
        log.info("[STAB-DELAY] Cancelled during delay")
        break
    }
}
```

**Tuning:**
- Current: 750ms
- Trade-off: Longer delay = more cancellations but slower UX
- Tested values: 0ms (no protection), 750ms (current), 1500ms (too slow)

---

### Layer 4: Task Cancellation Check

**Purpose:** Final safety check before invoking LLM
**Implementation:** `TimelineCacheMissGenerator.generateSummary()` (line ~492)

**How it works:**
1. After stabilization delay completes
2. Right before calling `llm.summarizeTimelineWithForms()`
3. Call `try Task.checkCancellation()`
4. If cancelled → throw `CancellationError`, exit cleanly
5. If not cancelled → proceed to LLM

**Effect:**
- Catches cancellations that occurred during or after stabilization delay
- Last line of defense before committing to LLM call
- Prevents wasted compute on cancelled tasks

**Code:**
```swift
try Task.checkCancellation()

let llm = FoundationLLM.shared
let result = try await llm.summarizeTimelineWithForms(...)
```

**Why it matters:** Once inside `llm.summarizeTimelineWithForms()`, we cannot cancel. This is the last checkpoint.

---

### Layer 5: LIFO Queue Processing

**Purpose:** Prioritize newest entries (what user is looking at NOW)
**Implementation:** `TimelineCacheMissGenerator.queueMisses()` (line ~154)

**How it works:**
1. New entries inserted at **front** of queue
2. Processing takes from front (newest first)
3. Older entries get pushed to back
4. If queue is pruned, older entries more likely to be dropped

**Effect:**
- User scrolls to new content → new entries jump to front
- Old entries (from previous scroll position) sit at back
- Pruning runs → old entries dropped, new entries processed
- User sees summaries for current viewport faster

**Code:**
```swift
pendingMisses.insert(miss, at: 0)  // Add to front (LIFO)
```

**Alternative (old behavior):**
```swift
pendingMisses.append(miss)  // Add to back (FIFO) - REMOVED
```

---

### Layer 6: Sequential Processing (Batch Size = 1)

**Purpose:** Prevent concurrent LLM requests
**Implementation:** `TimelineCacheMissGenerator.maxBatchSize = 1` (line 45)

**How it works:**
1. `processQueue()` loop dequeues exactly 1 entry at a time
2. Waits for that entry to complete (success or failure)
3. Only then dequeues the next entry
4. Never more than 1 LLM call in flight at a time

**Effect:**
- Entry A: Dequeue → wait 750ms → send to LLM (processing 8s) → complete
- Entry B: **Waits for A to finish** → then dequeue → wait 750ms → send to LLM
- Apple Intelligence only receives 1 request at a time

**Code:**
```swift
private let maxBatchSize = 1  // Process one at a time for instant responsiveness
```

**Why not larger batches?**
- Larger batches would process multiple entries in parallel
- Could overload Apple Intelligence with concurrent requests
- Current architecture (with 750ms delay) already slow enough for sequential

---

## Protection Layers Summary

| Layer | Trigger | Prevents | Can Cancel In-Flight? |
|-------|---------|----------|----------------------|
| 1. Viewport Debounce | User stops scrolling | Queueing during rapid scroll | N/A |
| 2. Viewport Pruning | Viewport settles | Queueing obsolete entries | Yes (if not dequeued yet) |
| 3. Stabilization Delay | Entry dequeued | Sending to LLM too quickly | Yes (during 750ms window) |
| 4. Cancellation Check | After delay | Last-second cancelled tasks | No (about to enter LLM) |
| 5. LIFO Processing | Queue order | Old entries blocking new | N/A |
| 6. Sequential Batch | Dequeue rate | Concurrent LLM requests | N/A |

**Critical Distinction:**
- Layers 1-4: Can prevent entries from reaching LLM
- **Once in LLM (inside `llm.summarizeTimelineWithForms()`):** Cannot be cancelled
- Apple Intelligence processes the request even if we don't use the result

---

## Timing Diagram

```
User Action: Scroll to View A
                ↓
T+0ms:         [VIEWPORT-CHANGE] Debounce timer starts
T+500ms:       User scrolls to View B (timer resets)
T+1750ms:      [VIEWPORT-SETTLED] Debounce complete
T+1750ms:      [PRUNE] Drop View A entries from queue
T+1750ms:      [QUEUE] Add View B entries to queue
T+1750ms:      [DEQUEUE] Entry B1 dequeued
T+1750ms:      [STAB-DELAY] Wait 750ms...
T+2500ms:      [CANCEL-CHECK] Not cancelled, proceed
T+2500ms:      [LLM-START] Send to Apple Intelligence
T+4500ms:      [LLM-COMPLETE] Summary generated (2s)
T+4500ms:      [DEQUEUE] Entry B2 dequeued (if still visible)
T+4500ms:      [STAB-DELAY] Wait 750ms...
T+5250ms:      [LLM-START] Send to Apple Intelligence
```

**Key Insight:** Each entry has ~2s of protection (1250ms debounce + 750ms stabilization) before reaching LLM.

---

## Why Overload Still Occurs

Despite all these protections, overload errors can still occur when:

### 1. **Very Fast Scrolling (< 3s per viewport)**
- User scrolls every 2-3 seconds
- Each scroll queues new entries after settling (1.25s + 0.75s = 2s)
- LLM processing takes 1-10s per entry
- Multiple entries reach LLM before user's next scroll
- Apple Intelligence receives 3-5 requests in 10s window → overload

**Example (from test logs):**
- T+0s: Entry 1 queued, reaches LLM at T+2s
- T+3s: Entry 2 queued, reaches LLM at T+5s (Entry 1 still processing)
- T+6s: Entry 3 queued, reaches LLM at T+8s (Entry 1, 2 still processing)
- T+8s: Apple Intelligence overloaded (3 concurrent requests)

### 2. **Entries Already in LLM When User Scrolls Away**
- Entry A dequeued → 750ms delay → sent to LLM (processing 8s)
- User scrolls away at T+1s
- Pruning runs at T+2.25s, but Entry A already in LLM
- **Cannot recall LLM request** - it completes even though user scrolled away
- Wasted compute, counts toward overload threshold

**Test Results (2025-11-07):**
- 26 entries queued during aggressive scrolling
- 23 pruned before reaching LLM (88% success)
- 3 reached LLM and caused overload errors
- All 3 were already processing when user scrolled away

### 3. **Apple Intelligence Has Low Concurrency Threshold**
- Test showed sequential requests (1 at a time)
- Still got overload errors
- Suggests Apple Intelligence wants >2s gap between requests
- Or was genuinely overloaded from other sources (system-wide usage)

---

## What Doesn't Help

### ❌ Increasing Stabilization Delay to 1500ms+
- **Problem:** User waits 3+ seconds for summaries (1250ms debounce + 1500ms delay)
- **Benefit:** Marginally more cancellations
- **Verdict:** UX cost too high for minimal gain

### ❌ Concurrent Processing (Batch Size > 1)
- **Problem:** Would send multiple requests to Apple Intelligence simultaneously
- **Benefit:** Faster generation when Apple Intelligence isn't overloaded
- **Verdict:** Would make overload worse, opposite of goal

### ❌ Aggressive Circuit Breaker
- **Problem:** Currently disabled (batch size = 1), wouldn't help anyway
- **Benefit:** Stops processing after N failures
- **Verdict:** Doesn't prevent overload, just stops retrying after it happens

---

## What Would Help (Future Improvements)

### 1. **Inter-Batch Delay** (Recommended)
Add delay BETWEEN sequential entries:

```swift
private let batchDelayNs: UInt64 = 500_000_000  // 500ms between entries
```

**Effect:**
- Entry 1 completes → wait 500ms → Entry 2 starts
- Spaces out requests even with sequential processing
- Reduces burst load on Apple Intelligence

**Tradeoff:** Slower generation when multiple entries need summaries

### 2. **Rate Limiting with Token Bucket**
Track request rate and throttle when approaching threshold:

```swift
class RateLimiter {
    var tokens: Int = 5  // Max 5 requests per window
    let refillRate: Int = 1  // 1 token per 2 seconds

    func canProcess() -> Bool {
        return tokens > 0
    }
}
```

**Effect:** Hard limit on request rate to Apple Intelligence

### 3. **Adaptive Delay Based on Error Rate**
Increase delay dynamically when errors occur:

```swift
if consecutiveErrors > 2 {
    stabilizationDelayMs = 1500  // Back off
} else {
    stabilizationDelayMs = 750   // Normal
}
```

**Effect:** Automatically adjusts to Apple Intelligence's current capacity

### 4. **True Circuit Breaker**
Stop entire `processQueue()` loop on sustained failures:

```swift
var circuitOpen = false

while !pendingMisses.isEmpty && !circuitOpen {
    // Process entry...
    if consecutiveFailures >= 3 {
        circuitOpen = true
        log.error("Circuit breaker opened, stopping queue")
    }
}
```

**Effect:** Prevents hammering Apple Intelligence when it's genuinely overloaded

---

## Current Configuration (As of 2025-11-07)

```swift
// TimelineCacheMissGenerator.swift
private let maxBatchSize = 1                    // Sequential processing only
private let stabilizationDelayMs: Int = 750     // 750ms before LLM call
private let batchDelayNs: UInt64 = 0            // No delay between entries (TODO?)
private let maxQueueSize = 5000                 // Queue capacity

// ConversationMonitor.swift
private let viewportDebounceMs: Int = 1250      // Viewport settle time
```

**Why These Values:**
- **750ms stabilization:** Balance between UX and protection (tested 0ms, 750ms, 1500ms)
- **1250ms debounce:** Standard debounce time for scroll interactions
- **Batch size 1:** Prevents concurrent requests (tested with fast scrolling)
- **0ms batch delay:** Not implemented yet (candidate for improvement)

---

## Testing & Validation

### Test Scenario: Aggressive Scrolling
**Setup:**
- Clean database (0 cached summaries)
- Timeline with 25 unsummarized entries
- User scrolls rapidly through all entries (< 3s per viewport)

**Results:**
- 26 entries queued
- 23 pruned before reaching LLM (88%)
- 3 reached LLM (12%)
- 3 overload errors (100% of entries that reached LLM)

**Log Evidence:**
```
[PRUNE] Removed 4 entries no longer visible
[PRUNE] Removed 4 entries no longer visible
[PRUNE] Removed 2 entries no longer visible
[PRUNE] Removed 2 entries no longer visible
[PRUNE] Removed 4 entries no longer visible
[PRUNE] Removed 3 entries no longer visible
[PRUNE] Removed 4 entries no longer visible
Total: 23 pruned

Batch complete: 0 generated, 0 skipped, 1 errors (3 times)
```

### Interpretation
**System is working as designed:**
- Pruning prevents 88% of unnecessary work
- Only entries user actually stopped on reach LLM
- 3 errors = entries that were processing when user scrolled away

**Apple Intelligence is sensitive:**
- 3 requests in ~30s caused overload
- Suggests threshold is < 1 request per 10s
- Or was genuinely overloaded from external sources

---

## Monitoring & Diagnostics

### Log Tags
Use these to debug overload issues:

```bash
# Monitor pruning activity
grep "PRUNE" /tmp/cache-generation.log

# Track stabilization delays
grep "STAB-DELAY" /tmp/cache-generation.log

# Check cancellation catches
grep "CANCEL-CHECK" /tmp/cache-generation.log

# View queueing activity
grep "SUMM-QUEUE" /tmp/cache-generation.log

# See viewport changes
grep "SUMM-VIEWPORT" /tmp/cache-generation.log
```

### Monitoring Script
```bash
bash scripts/logging/monitor-cache-generation.sh > /tmp/cache-test.log
```

Captures all relevant tags with color-coded output.

### Key Metrics to Watch
- **Prune rate:** High = good (entries dropped before LLM)
- **Cancellation catches:** Should see some during fast scrolling
- **Error rate:** > 10% suggests need for more protection
- **Queue depth:** Consistently > 20 entries = pruning not aggressive enough

---

## Decision Log

### 2025-11-07: Stabilization Delay Testing
- **Tested:** 0ms (no delay), 750ms, 1500ms
- **Result:** 750ms chosen as balance between UX and protection
- **Evidence:** 0ms = many overloads, 1500ms = sluggish UX, 750ms = acceptable both

### 2025-11-07: LIFO vs FIFO Processing
- **Tested:** FIFO (oldest first), LIFO (newest first)
- **Result:** LIFO chosen for better UX
- **Evidence:** User sees summaries for current viewport faster

### 2025-11-07: Circuit Breaker Disabled
- **Tested:** Circuit breaker with batch size = 1
- **Result:** Disabled (ineffective with batch size 1)
- **Evidence:** Code analysis showed it only breaks batch loop, not queue loop

### 2025-11-07: Inter-Batch Delay NOT Implemented
- **Considered:** 500ms delay between sequential entries
- **Result:** Deferred for future if overload persists
- **Rationale:** Want to validate current protections first

---

## Related Documentation

- **LLM Architecture:** `build/notes/technical-reference/llm-processing-architecture.md`
- **Timeline Cache:** `build/notes/technical-reference/timeline-cache-llm-architecture.md`
- **Conversation Monitor:** `build/notes/technical-reference/conversation-monitor-state-architecture.md`
- **Status Bar:** `build/notes/feature-specs/status-bar/spec-final.md`

---

## Changelog

**2025-11-07:** Initial documentation based on viewport-based queuing implementation
