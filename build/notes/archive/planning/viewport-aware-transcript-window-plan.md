# Viewport-Aware Transcript Window - Implementation Plan

**Date:** 2025-11-09
**Status:** Planning
**Branch:** TBD (new branch after terminology fixes merged)

---

## Executive Summary

Implement true viewport-aware metadata generation for TranscriptInventoryView to match the proven behavior of ConversationTimelineView. This prevents Apple Intelligence overload and provides responsive UX when browsing large session lists.

**Current State:** Transcript window uses hardcoded first-10 loading with per-row `.onAppear` triggers and concurrency limits. This is NOT viewport-aware - it's a band-aid fix.

**Target State:** Transcript window uses aggregate visibility tracking, debounced viewport handling, and active queue pruning to only generate metadata for visible sessions.

---

## Problem Statement

### What Works (ConversationTimelineView)

The conversation log has proven viewport-aware architecture:

1. **Aggregate visibility tracking** - `.onScrollTargetVisibilityChange` provides all visible IDs in one callback
2. **Debounced viewport handling** - 1250ms settle time before acting on visibility changes
3. **Active queue pruning** - `pruneQueue(keepOnly: visibleIDs)` removes invisible entries from pending work
4. **Stabilization delay** - 750ms window before LLM call allows pruning to cancel stale work
5. **LIFO priority** - Newest entries (current viewport) processed first
6. **88% prevention rate** - During fast scrolling, 23 of 26 queued entries dropped before reaching LLM

### What's Broken (TranscriptInventoryView)

Commit 94d29d4 attempted "viewport-aware loading" but only implemented:

1. **Hardcoded first-10 load** - `Array(filteredSessions.prefix(10))` (line 240)
2. **Per-row .onAppear triggers** - Each row loads independently when visible (line 448)
3. **Concurrency limit** - Max 3 concurrent metadata requests (line 996)

**Missing:**
- No aggregate visibility tracking
- No debouncing
- No pruning when sessions scroll out of view
- No stabilization delay
- No cancellation of in-flight work

**Result:** Opening inventory with 490 transcripts can still overwhelm Apple Intelligence because work is spawned immediately when rows appear, with no mechanism to cancel when they scroll away.

---

## Goals

1. **Match conversation log behavior** - Transcript window should have identical viewport-aware protection
2. **Prevent Apple Intelligence overload** - 88%+ prevention rate like timeline queue
3. **Responsive UX** - Generate metadata for what user is looking at NOW
4. **No destabilization** - Conversation log remains untouched during this work

---

## Multi-Session Concurrency Clarification

**IMPORTANT:** Timeline and Transcript queues CAN run concurrently!

**How it works:**
- `FoundationLLM` maintains up to 16 separate `SessionController` instances
- Each session can process ONE request at a time
- **Different sessions process concurrently**

**Our architecture:**
1. **Timeline Session** - Sequential processing (one entry at a time)
   - Session key: Based on entry kind/provider
   - LIFO queue with viewport-aware pruning

2. **Transcript Session** - Sequential processing (one transcript at a time)
   - Session key: Based on transcript metadata schema
   - To be refactored: Queue-based with viewport-aware pruning

**Both sessions run in parallel** (one timeline entry + one transcript at same time), but each queue is sequential internally.

**Why sequential per queue?**
- Enables viewport-aware pruning (can't prune mid-flight requests)
- Simpler error handling and attribution
- LIFO priority control

**NOT doing:** Multiple sessions per queue (would lose pruning ability)

---

## Technical Approach

### Option A: Refactor TranscriptMetadataOrchestrator to Queue-Based

**Current architecture:** Concurrent task-per-transcript (spawns Task for each session)

**Target architecture:** Queue-based with pruning like TimelineCacheMissGenerator

**Changes required:**
1. Replace concurrent task spawning with managed queue
2. Add `pruneQueue(keepOnly: visibleIDs)` method
3. Implement LIFO priority (newest sessions first)
4. Add stabilization delay (750ms) before LLM call
5. Track active sessions for pruning protection

**Pros:**
- Enables true viewport-aware pruning
- Matches proven timeline queue architecture
- Can cancel work when sessions scroll away

**Cons:**
- Large refactor of TranscriptMetadataOrchestrator
- Need to preserve circuit breaker behavior
- More complex migration

### Option B: Implement Abstract LLM Queue

**Approach:** Build generic queue infrastructure that both queues use

**From Phase 0 design** (`build/docs/architecture/abstract-llm-queue-design.md`):
- Protocol-oriented architecture (LLMWorkProcessor)
- Configuration-based (processing mode, priority strategy)
- Supports sequential processing (only mode that works with FoundationLLM)
- Pluggable pruning predicates

**Implementation sequence:**
1. Implement abstract `LLMWorkQueue<Item, Result>` actor
2. Migrate TranscriptMetadataOrchestrator to use it
3. Validate with transcript window
4. Later: migrate TimelineCacheMissGenerator (optional)

**Pros:**
- Avoids code duplication
- Foundation for future LLM queues
- Enforces consistent patterns

**Cons:**
- More upfront work
- Higher complexity
- Need to get abstraction right on first try

---

## Recommended Approach

**Hybrid:** Start with Option A, extract commonality later

**Reasoning:**
1. **Lower risk** - Duplicate proven patterns from timeline queue
2. **Faster validation** - Get transcript window working first
3. **Learn from two implementations** - Discover true common patterns
4. **Avoid premature abstraction** - Don't abstract until we have two working examples

**Sequence:**
1. Refactor TranscriptMetadataOrchestrator to queue-based (this PR)
2. Add viewport tracking to TranscriptInventoryView (this PR)
3. Validate behavior matches timeline queue (this PR)
4. Extract common patterns to abstract queue (future PR, optional)
5. Migrate timeline queue to abstraction (future PR, optional)

---

## Implementation Plan

### Phase 1: Add Viewport Tracking to TranscriptInventoryView

**File:** `Contextify/Contextify/TranscriptInventoryView.swift`

**Changes:**

1. Add viewport state tracking:
```swift
@State private var lastVisibleSessionIDs: Set<String> = []
@State private var debounceTask: Task<Void, Never>?
```

2. Wrap session list in ScrollView with visibility tracking:
```swift
ScrollView {
    LazyVStack {
        ForEach(filteredSessions) { session in
            sessionRow(for: session)
                .id(session.identifier)
        }
    }
    .scrollTargetLayout()
    .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.55) { ids in
        handleVisibleSessionsChanged(ids)
    }
}
```

3. Implement debounced viewport handler:
```swift
private func handleVisibleSessionsChanged(_ ids: [String]) {
    lastVisibleSessionIDs = Set(ids)

    // Debounce 1250ms like ConversationMonitor
    debounceTask?.cancel()
    debounceTask = Task {
        try? await Task.sleep(nanoseconds: 1_250_000_000)
        guard !Task.isCancelled else { return }

        // Prune FIRST, then load
        await pruneMetadataQueue(keepOnly: lastVisibleSessionIDs)
        await loadMetadataForVisibleSessions()
    }
}
```

4. Remove hardcoded first-10 load and per-row .onAppear triggers

### Phase 2: Refactor TranscriptMetadataOrchestrator

**File:** `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`

**Changes:**

1. Replace concurrent task tracking with managed queue:
```swift
actor TranscriptMetadataOrchestrator {
    // Replace:
    // private var activeTasks: [String: Task<TranscriptMetadata, Error>] = [:]

    // With:
    private var pendingWork: [MetadataWorkItem] = []  // LIFO queue
    private var pendingKeys: Set<String> = []  // Deduplication
    private var processingTask: Task<Void, Never>?
    private var activeTranscriptID: String?  // Protect from pruning

    struct MetadataWorkItem: Sendable {
        let transcriptId: String
        let session: TranscriptSession
        let orchestrator: TranscriptOrchestrator
    }
}
```

2. Add queueing method (replaces direct task spawn):
```swift
func queueMetadata(for sessions: [TranscriptSession]) async {
    let items = sessions.map { session in
        MetadataWorkItem(
            transcriptId: session.identifier,
            session: session,
            orchestrator: self.orchestrator
        )
    }

    // Add to front (LIFO: newest first)
    for item in items {
        if !pendingKeys.contains(item.transcriptId) {
            pendingWork.insert(item, at: 0)
            pendingKeys.insert(item.transcriptId)
        }
    }

    notifyQueueChanged()
    await ensureProcessing()
}
```

3. Add pruning method:
```swift
func pruneQueue(keepOnly visibleIDs: Set<String>) async {
    let beforeCount = pendingWork.count

    pendingWork.removeAll { item in
        let isVisible = visibleIDs.contains(item.transcriptId)
        let isActive = item.transcriptId == activeTranscriptID
        return !isVisible && !isActive
    }

    // Update deduplication set
    pendingKeys = Set(pendingWork.map { $0.transcriptId })

    let pruned = beforeCount - pendingWork.count
    if pruned > 0 {
        log.info("Pruned \(pruned) invisible sessions (kept \(pendingWork.count))")
        notifyQueueChanged()
    }
}
```

4. Add processing loop (sequential, with stabilization delay):
```swift
private func processQueue() async {
    while !pendingWork.isEmpty {
        guard !Task.isCancelled else { break }

        // Dequeue next item (front = newest)
        let item = pendingWork.removeFirst()
        pendingKeys.remove(item.transcriptId)
        activeTranscriptID = item.transcriptId

        // Stabilization delay (750ms) - allows pruning to catch scroll-aways
        try? await Task.sleep(nanoseconds: 750_000_000)
        guard !Task.isCancelled else { break }

        // Process metadata generation
        do {
            let metadata = try await generateMetadata(for: item.session)
            // Cache to SQL, notify observers...
        } catch {
            // Error handling with circuit breaker...
        }

        activeTranscriptID = nil
    }

    processingTask = nil
}
```

5. Preserve circuit breaker integration

### Phase 3: Integration and Testing

1. Update TranscriptInventoryView to call new queue methods:
```swift
private func loadMetadataForVisibleSessions() async {
    let visibleSessions = filteredSessions.filter {
        lastVisibleSessionIDs.contains($0.identifier)
    }
    await TranscriptMetadataOrchestrator.shared.queueMetadata(for: visibleSessions)
}

private func pruneMetadataQueue(keepOnly visibleIDs: Set<String>) async {
    await TranscriptMetadataOrchestrator.shared.pruneQueue(keepOnly: visibleIDs)
}
```

2. Remove concurrency limit logic (no longer needed with sequential processing)

3. Test with large session lists (490+ transcripts)

4. Verify pruning behavior with fast scrolling

5. Confirm status bar integration still works

---

## Success Criteria

- [ ] Opening inventory with 490 transcripts does NOT overwhelm Apple Intelligence
- [ ] Fast scrolling triggers pruning (log evidence of entries removed)
- [ ] Only visible sessions get metadata generated
- [ ] Metadata appears for sessions user stops on (after 1.25s settle)
- [ ] Status bar accurately reflects queue depth and processing state
- [ ] Error handling works (circuit breaker, retry, fallback)
- [ ] Conversation log remains stable (no regressions)
- [ ] Pruning prevention rate ≥80% (like timeline queue)

---

## Testing Plan

### Automated Test Harness

Similar to `scripts/logging/monitor-automated-test.sh`:

```bash
#!/bin/bash
# Test viewport-aware metadata generation

echo "Test: Fast scroll through 50 sessions"
echo "Expected: ≥40 sessions pruned before reaching LLM"

# Clear logs
rm /tmp/metadata-viewport-test.log

# Start app with clean state
# Monitor logs for:
# - [META-QUEUE] entries added
# - [META-PRUNE] entries removed
# - [META-LLM] entries sent to LLM

# Fast scroll through inventory (simulate with automation)

# Analyze results
QUEUED=$(grep -c "META-QUEUE" /tmp/metadata-viewport-test.log)
PRUNED=$(grep -c "META-PRUNE" /tmp/metadata-viewport-test.log)
LLMCALLS=$(grep -c "META-LLM" /tmp/metadata-viewport-test.log)

PREVENTION_RATE=$((100 * PRUNED / QUEUED))

if [ $PREVENTION_RATE -ge 80 ]; then
    echo "✅ PASS: Prevention rate $PREVENTION_RATE% (≥80%)"
else
    echo "❌ FAIL: Prevention rate $PREVENTION_RATE% (<80%)"
fi
```

### Manual Testing

1. **Large inventory:** Open inventory with 490+ transcripts, verify no overload
2. **Fast scrolling:** Scroll rapidly, verify only stopped-on sessions get metadata
3. **Session switching:** Switch between sessions, verify pruning works
4. **Error handling:** Disconnect network, verify circuit breaker activates
5. **Status bar:** Verify accurate counts and no race conditions

---

## Risks and Mitigations

### Risk: Breaking TranscriptMetadataOrchestrator

**Mitigation:**
- Comprehensive testing before merge
- Preserve existing API surface (ensureMetadata still works)
- Keep circuit breaker behavior identical
- Feature flag to switch between old/new queue?

### Risk: Performance Regression

**Mitigation:**
- Profile metadata generation before/after
- Measure queue latency and throughput
- Compare with timeline queue performance
- Monitor status bar update frequency

### Risk: Race Conditions

**Mitigation:**
- Actor isolation prevents data races
- Careful task cancellation handling
- Test with fast user interactions
- Validate cleanup on view disappear

---

## Future Work

### Abstract Queue (Optional)

After both queues work with viewport-aware pruning:

1. Extract common patterns to `LLMWorkQueue<Item, Result>`
2. Migrate transcript queue to use abstraction
3. Validate no behavior changes
4. Consider migrating timeline queue (lower priority)

**Benefits:**
- Eliminates ~300 lines of duplicated code
- Consistent queue behavior
- Easier to add new LLM features

**When to do it:** After this PR is merged and validated in production

---

## Related Documentation

- **Conversation log implementation:** `Contextify/Contextify/ConversationTimelineView.swift`
- **Timeline queue:** `Contextify/Contextify/TimelineCacheMissGenerator.swift`
- **Current metadata orchestrator:** `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`
- **LLM overload prevention:** `build/notes/technical-reference/llm-overload-prevention.md`
- **Abstract queue design:** `build/docs/architecture/abstract-llm-queue-design.md` (Phase 0)
- **Terminology fixes:** This branch (terminology corrections to LIFO/sequential)

---

## Terminology Corrections Applied

This plan uses corrected terminology throughout:

- **NOT "FIFO"** - Queue is LIFO (newest first)
- **NOT "batched"** - Processing is sequential (one at a time)
- **NOT "concurrent"** - FoundationLLM only supports sequential processing per session
- **"Viewport-aware pruning"** - Accurate term for removing invisible entries
- **"Sequential processing"** - Reflects FoundationLLM's `isResponding` limitation

See commit XXX for full terminology audit and corrections.
