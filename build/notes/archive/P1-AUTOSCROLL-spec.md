# Timeline Auto-Scroll Fix: Implementation Specification (v2)

**Status:** Ready for implementation
**Priority:** P1
**Estimated Effort:** 2-4 hours
**Files:** `ConversationTimelineView.swift`, `ConversationMonitor.swift`

---

## Problem Summary

The conversation timeline auto-scroll is unreliable:
- Flickers on first load (double scroll triggers)
- Stops working after 25 items (count-based trigger saturates)
- Viewport summary queueing delayed by stuck scroll gating

---

## Root Causes (Validated)

### 1. Double Programmatic Scroll on First Paint

Two overlapping scroll triggers fire when entries first appear:

1. **Immediate nil-animated jump** in `onAppear` (`ConversationTimelineView.swift:196-210`)
2. **Debounced animated scroll** 150ms later via `onChange(of: visibleEntries.count)` (`ConversationTimelineView.swift:218-234`)

Both call `monitor.beginProgrammaticScroll()`, causing duplicate gating and visual flicker.

### 2. Count-Based Trigger Stalls at 25-Item Cap

```swift
.onChange(of: monitor.visibleEntries.count) { ... }
```

Once `entries.count >= 25`, `visibleEntries.count` is always 25 (capped). New entries change *which* 25 items appear, not the count. Result: `.onChange` never fires again, auto-scroll permanently stops.

### 3. Scroll Gating Stuck After Nil-Animated Jump

The nil-animated `scrollTo` may not emit a `ScrollPhase` transition, leaving `doingProgrammaticScroll = true` indefinitely. This delays viewport-based summary queueing until the 500ms fallback fires.

### 4. Pending Scroll Task Not Cancelled on Teardown

`scrollTask` is never cancelled in `onDisappear`. If the view tears down during the 150ms debounce window, a stale scroll may fire against a dead view.

---

## Solution Design

### Core Pattern: Sticky Bottom via `scrollPosition(id:anchor:)`

Replace the dual-trigger approach with a single scroll path using SwiftUI's `scrollPosition` binding:

```swift
@State private var scrollPositionId: UUID?
@State private var isAtBottom = true
@State private var didRunInitialScroll = false

ScrollView {
    LazyVStack {
        ForEach(monitor.visibleEntries, id: \.id) { entry in
            TimelineEntryRow(...)
                .id(entry.id)
        }
    }
    .scrollTargetLayout()
}
.scrollPosition(id: $scrollPositionId, anchor: .bottom)
.onChange(of: scrollPositionId) { _, new in
    // Detect when user scrolls away from bottom
    let last = monitor.visibleEntries.last?.id
    isAtBottom = (last != nil && new == last)
}
```

### Single Scroll Helper

Consolidate all programmatic scrolling into one function:

```swift
private func scrollToBottomIfNeeded() {
    guard monitor.autoScroll,
          let lastId = monitor.visibleEntries.last?.id
    else { return }

    monitor.beginProgrammaticScroll()
    withAnimation(.easeOut(duration: 0.3)) {
        scrollPositionId = lastId
    }
}
```

### Trigger Points

**Initial load** (once per view lifecycle):
```swift
.onAppear {
    if !didRunInitialScroll {
        didRunInitialScroll = true
        scrollToBottomIfNeeded()
    }
}
```

**Incremental updates** (keyed to revision, not count):
```swift
.onChange(of: monitor.entriesRevision) { _, _ in
    if monitor.entries.isEmpty {
        // Reset state on project switch
        didRunInitialScroll = false
        isAtBottom = true
    } else if isAtBottom {
        scrollToBottomIfNeeded()
    }
}
```

### "Sticky Until User Scrolls Up" Behavior

- **While `isAtBottom == true`**: Auto-scroll on new entries
- **When user scrolls up**: `isAtBottom` becomes `false`, auto-scroll pauses
- **"Jump to Latest" button**: Sets `scrollPositionId = lastId`, resumes auto-scroll

**Important:** Keep `monitor.autoScroll` as the global preference. Use view-local `isAtBottom` for transient pause state. Don't conflate them.

### Gating Timeout (ConversationMonitor)

Add a 1-second timeout to clear stuck gating:

```swift
@ObservationIgnored private var scrollGateTimeoutTask: Task<Void, Never>?

@MainActor
func beginProgrammaticScroll() {
    doingProgrammaticScroll = true
    pendingInitialVisibleIDs = nil

    scrollGateTimeoutTask?.cancel()
    scrollGateTimeoutTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(1))
        await MainActor.run {
            guard let self, self.doingProgrammaticScroll else { return }
            self.doingProgrammaticScroll = false
            log.warning("[SUMM-SCROLL] Clearing programmatic scroll gate after timeout")
        }
    }
}
```

---

## Implementation Checklist

### ConversationTimelineView.swift

- [ ] Remove `@State private var scrollTask: Task<Void, Never>?`
- [ ] Add `@State private var scrollPositionId: UUID?`
- [ ] Add `@State private var isAtBottom = true`
- [ ] Add `@State private var didRunInitialScroll = false`
- [ ] Replace `ScrollViewReader { proxy in ... }` with `.scrollPosition(id:anchor:)`
- [ ] Create `scrollToBottomIfNeeded()` helper
- [ ] Simplify `.onAppear` to single initial scroll (with flag)
- [ ] Change `.onChange` trigger from `visibleEntries.count` to `entriesRevision`
- [ ] Add `.onChange(of: scrollPositionId)` for `isAtBottom` detection
- [ ] Remove the 150ms debounce task (rely on SwiftUI throttling for v1)
- [ ] Keep existing viewport tracking modifiers (`onScrollTargetVisibilityChange`, `onScrollPhaseChange`)
- [ ] Add "Jump to Latest" button when `!isAtBottom` (optional for v1)

### ConversationMonitor.swift

- [ ] Add `scrollGateTimeoutTask: Task<Void, Never>?` property
- [ ] Update `beginProgrammaticScroll()` with 1-second timeout
- [ ] Ensure `handleScrollPhaseChange(.idle)` cancels the timeout task

### Auto-Scroll Toggle Cleanup

- [ ] Decide on retaining the UI toggle: if no hard “never auto-scroll” mode is needed, remove the timeline menu toggle and rely on stickiness + “Jump to Latest.” If kept, treat it as a global kill switch that disables programmatic scrolling regardless of stickiness state.

---

## Edge Cases & Mitigations

| Edge Case | Risk | Mitigation |
|-----------|------|------------|
| Initial load misses scroll | `entriesRevision` bumped before view exists | Use `didRunInitialScroll` flag in `onAppear` |
| User scrolled up, confused by pause | May think feature is broken | Show "Jump to Latest" button |
| Project switch leaves stale state | `isAtBottom` wrong for new project | Reset flags when `entries.isEmpty` |
| ScrollPhase never fires | Gating stuck indefinitely | 1-second timeout clears gate |
| Heavy ingestion causes jitter | Many rapid scrolls | SwiftUI throttles internally; add debounce in v2 if needed |

---

## Testing Plan

1. **First load**: Launch app, verify timeline scrolls to bottom automatically
2. **New entries**: Add entries, verify auto-scroll continues past 25 items
3. **User scroll up**: Scroll up manually, verify auto-scroll pauses
4. **Jump to latest**: Click button, verify scroll resumes and sticks
5. **Project switch**: Switch projects, verify new project auto-scrolls correctly
6. **Toggle off**: Disable auto-scroll in menu, verify no auto-scrolling occurs
7. **Rapid ingestion**: Process many entries quickly, verify no flicker/jitter

---

## Decision Log

| Decision | Rationale |
|----------|-----------|
| Use `scrollPosition(id:)` over `ScrollViewReader` | Modern API, two-way binding, avoids DispatchQueue gymnastics |
| Key trigger on `entriesRevision` not `count` | Count saturates at 25; revision increments on every change |
| Single helper for all scroll paths | Eliminates duplicate gating, easier to reason about |
| Remove 150ms debounce for v1 | Complexity vs. benefit; SwiftUI throttles internally |
| Keep `autoScroll` separate from `isAtBottom` | Preference vs. transient state; don't conflate |
| Add gating timeout | Belt-and-suspenders against stuck gates |

---

## References

- SwiftUI `scrollPosition(id:anchor:)`: macOS 14+ / iOS 17+
- Existing viewport tracking: `ConversationMonitor.swift:2023-2079`
- Current scroll implementation: `ConversationTimelineView.swift:176-235`
