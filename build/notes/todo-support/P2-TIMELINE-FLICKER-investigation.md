# Timeline Flicker During DMG Startup

**Status:** Unresolved
**Priority:** P2
**Severity:** Medium (UX issue, DMG builds only)
**Date:** 2025-11-15

## Problem

DMG builds show massive timeline flicker during startup with clean database. Timeline re-renders identical entries multiple times (visible UI flicker). App Store builds appear fine.

**User observation:** "Conversation log updates even though newest message is still newest and 25 total entries don't change."

## Evidence

From log `/private/tmp/transcript-queue-monitor-20251115-225901.log`:

```
22:59:27.832 - setEntries 25 (first load)
22:59:28.351 - setEntries 25 (DUPLICATE - 519ms later, same data)
```

Multiple `[TIMELINE-LOAD]` calls during startup:
- 22:59:27.118 - Load 1 (db=0, current=0)
- 22:59:27.134 - Load 2 (db=0, current=0)
- 22:59:27.136 - Load 3 (db=0, current=0)
- 22:59:27.137 - Load 4 (db=0, current=0)

## Things Tried

### Attempt 1: P1 Entry Count Check (commit 68637df)
**Fix:** Compare DB entry count vs current displayed count, skip if unchanged.

**Code:**
```swift
let dbEntryCount = (try? orchestrator.getEntryCount(forProject: projectId)) ?? 0
let currentCount = state.entries.count

if dbEntryCount == currentCount && currentCount > 0 {
    return nil  // Skip refresh
}
```

**Result:** Failed - compares total DB (267) vs paginated display (25), never matches.

**Removed in:** commit 284bd4c

### Attempt 2: Remove Broken P1 Check (commit 284bd4c)
**Fix:** Remove the broken comparison entirely, rely on existing 500ms debounce.

**Result:** Failed - flicker still present.

## Current Debounce Mechanism

`ConversationMonitor.swift:1640-1666` has 500ms debounce on hoovering progress:

```swift
progressDebounceTask = Task { @MainActor [weak self] in
    let minInterval: TimeInterval = 0.5
    // Wait if last refresh was < 500ms ago
    try? await Task.sleep(...)
    await self.loadFeedFromSQL()?.value
}
```

This should prevent rapid refreshes but doesn't eliminate startup flicker.

## Why DMG vs App Store Difference

**DMG builds:** All 16 projects hoover concurrently (6 workers), rapid event burst.

**App Store builds:** Permission delays space events naturally.

Both have the issue, but DMG makes it highly visible.

## Root Cause Unknown

Multiple rapid `loadFeedFromSQL()` calls during startup (4 calls in 19ms).

Source unclear - code doesn't log call sites. Could be:
- Project switches during discovery
- Context updates
- Ingestion complete notifications
- Progress notifications bleeding through

## Next Steps

1. **Add call site logging** to `loadFeedFromSQL()` to track who's calling it
2. **Investigate startup sequence** - why 4 loads in 19ms?
3. **Consider debouncing loadFeedFromSQL()** itself (not just progress handler)
4. **Check if tab selection triggers refreshes** during discovery

## References

See full analysis: `/tmp/timeline-flicker-final-analysis.md`

---

# Appendix: Final Analysis (Two-Pass Review)

# Timeline Flicker - Final Root Cause Analysis

## Pass 1: Actual Control Flow (Evidence-Based)

### Timeline Reconstruction from Log

**22:59:27.118-137:** FOUR rapid loadFeedFromSQL() calls (19ms)
- All show `db=0, current=0` (before hoovering)
- P1 check: 0 == 0 AND 0 > 0 → FALSE (currentCount not > 0)
- All proceed to refresh

**22:59:27.824:** Hoovering progress (5/5) → debounce task created
- Task says "Waiting 492ms" before refresh
- Will execute at 27.824 + 0.492 = **28.316 seconds**

**22:59:27.832:** First debounced refresh completes
- setEntries 25
- P1 check would have been: db=267, current=6
- 267 ≠ 6 → Proceed

**22:59:28.351:** DUPLICATE refresh (**CULPRIT**)
- setEntries 25 (same as 27.832)
- P1 check: db=267, current=25
- 267 ≠ 25 → Proceed (WRONG!)
- This is 27ms AFTER expected debounce (28.324)

### Root Cause: P1 Check is Broken

The check at line 1269:
```swift
if dbEntryCount == currentCount && currentCount > 0
```

**Always fails** because:
- `dbEntryCount` = total entries in DB (267)
- `currentCount` = displayed paginated entries (25)
- Timeline uses `LIMIT 25` so these will NEVER match when DB has >25 entries

### Why App Store Works, DMG Doesn't

Not actually different! Both have the same bug.

Difference is **visibility**:
- App Store: Permission delays space out events → less noticeable
- DMG: All events rapid-fire → flicker is obvious

### What Triggers the 28.351 Duplicate?

Looking at the timeline, it's 519ms after first refresh (27.832).
The debounce was set to wait 492ms from 27.824.

**Hypothesis:** Another progress notification arrived AFTER first batch completed, creating a second debounce task.

Evidence from log line at 27.832:
```
[TIMELINE-REFRESH-PROGRESS] Waiting 492ms before refresh (last refresh 7ms ago)
```

"last refresh 7ms ago" = there was a refresh at 27.825ish.

Then at 28.351 (519ms later), another debounce completes.

## Pass 2: Colleague Review

### Issue: The Analysis Above is Still Wrong

The duplicate at 28.351 shows `[TIMELINE-LOAD] primer start` which is logged at the BEGINNING of `loadFeedFromSQL()` (line 1263).

But the debounce handler calls `loadFeedFromSQL()` at line 1664, which should also trigger that log.

Let me check: Does the log show what triggered this specific call?

**NO** - The code doesn't log who called `loadFeedFromSQL()`.

### Add Call Site Logging (Recommended)

Instead of guessing, add this to `loadFeedFromSQL()` line 1263:

```swift
log.info("[TIMELINE-LOAD] primer start; projectId=\(projectId), caller=\(Thread.callStackSymbols[1])")
```

This would show WHO called it.

### But We Don't Need To

The fix is obvious: **Remove the broken P1 check entirely.**

It compares wrong values (total DB vs paginated display) and will NEVER work correctly for timelines with >25 entries.

The debounce at line 1640-1666 already prevents rapid refreshes (500ms minimum).

The P1 check adds zero value and causes bugs.

---

## Recommended Solution: Remove P1 Check

### Implementation

**File:** `ConversationMonitor.swift:1265-1278`

**DELETE lines 1265-1278:**
```swift
// P1 Fix: Skip refresh if entry count hasn't changed (eliminates duplicate refreshes)
let dbEntryCount = (try? orchestrator.getEntryCount(forProject: projectId)) ?? 0
let currentCount = state.entries.count

if dbEntryCount == currentCount && currentCount > 0 {
    log.debug("[TIMELINE-REFRESH-SKIP] Entry count unchanged: \(currentCount, privacy: .public)")
    // Update state to ensure UI is correct even though we're skipping
    phase = .loaded
    isProcessing = false
    return nil
}

// Log refresh reason for debugging
log.info("[TIMELINE-REFRESH-REASON] Refreshing: db=\(dbEntryCount, privacy: .public), current=\(currentCount, privacy: .public)")
```

**KEEP only:**
```swift
// Set loading phase (tracked by UI)
phase = .loading
```

### Why This Works

1. **Debounce already handles rapid refreshes** (500ms minimum at line 1648)
2. **P1 check is fundamentally flawed** (compares total vs paginated)
3. **Removing broken code can't make things worse**

### Expected Result

- Debounce prevents refreshes closer than 500ms
- No false skips from broken comparison
- Timeline refreshes when data actually changes
- Flicker eliminated

---

## Testing Plan

1. Remove P1 check
2. Build DMG
3. Clean DB test
4. Count `setEntries` logs - should see 1-2, not 3+
5. Verify no flicker

## Estimated Time

- Remove code: 2 minutes
- Test: 5 minutes
- Total: 7 minutes

---

## Why Your Question Was Important

You asked: "Why DMG but not App Store?"

My initial analysis was wrong (project ID capture).

Real answer: **Both have the bug**. DMG just makes it visible because events are rapid-fire.

The bug is the P1 check comparing apples (total DB) to oranges (paginated display).

Remove the check = fix both builds.
