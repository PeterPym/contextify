---
todo_id: TIMELINE-HANG
title: Timeline View Hang During Heavy Updates
type: investigation
date: 2025-12-24
status: reference
description: Analysis of 1.06s hang in TimelineEntryRow during decoration testing
---

# Timeline View Hang Investigation

## Summary

A 1.06 second hang was observed during agent decoration feature testing. Investigation determined this is **likely unrelated** to the decoration changes and represents normal SwiftUI behavior during heavy updates.

## Incident Details

- **Date:** 2025-12-24 18:13:29
- **Duration:** 1.06 seconds
- **Context:** Testing agent spawn decoration badges
- **Trigger:** Unknown - occurred ~1.5 minutes after test activity

## Crash Report Snippets

### Header
```
Event:            hang
Duration:         1.06s
Steps:            11 (100ms sampling interval)

Command:          Contextify
Version:          1.0.7 (18)
Architecture:     arm64
```

### Heaviest Stack (Main Thread)
```
11  TimelineEntryRow.body.getter (TimelineEntryRow.swift:104)
 7  DynamicBody.updateValue()
 7  ViewBodyAccessor.updateBody(of:changed:)
 4  protocol witness for View.body.getter in conformance TimelineEntryRow
 2  TimelineEntryRow.body.getter + 3288 (<compiler-generated>)
```

### Key Stack Frames
```
AttributedString.Guts.characterwiseIsEqual(_:in:to:in:) + 5504
LazyStack<>.place(subviews:context:cache:in:) + 2404
ForEachState.forEachItem(from:style:do:) + 1788
_platform_memmove + 452
```

### Process State
```
Footprint:        84.20 MB
Time Since Fork:  58860s (~16 hours)
Num threads:      4
CPU Time:         1.000s (3.4G cycles, 12.3G instructions)
```

## Analysis

### Location
The hang occurred in `TimelineEntryRow.body.getter` at line 104, which is the `.contextMenu` modifier.

### Contributing Factors

1. **AttributedString Comparison**: `formatWithBackticks()` creates AttributedStrings that SwiftUI compares on each render. For long text (like agent output), this comparison is expensive.

2. **Lazy Stack Layout**: `LazyStack<>.place` and `ForEachState.forEachItem` indicate the timeline's lazy list was computing layout for multiple entries.

3. **Memory Operations**: Deep stack shows `_platform_memmove` and `tuple_destroy` - memory manipulation during view updates.

### Why NOT Decoration-Related

1. **@ObservationIgnored**: Decoration lookups (`spawnedAgentsLookup`, `contextifyEntryIds`) are marked `@ObservationIgnored` and won't trigger SwiftUI cascade updates.

2. **TimelineEntryRow Equatable**: The row implements custom equality that only compares `entry` and `isExpanded` - unchanged entries won't re-render.

3. **Timing**: The hang occurred 1.5 minutes after the last logged activity, suggesting it wasn't directly triggered by our test.

### Possible Contributing Scenario

When decoration data changes via `refreshDecorationData()`, entries created by `toTimelineEntry()` get new `spawnedAgentType`/`isContextifyCall` values. This makes those entries != previous, triggering:
- Row re-renders
- `formatWithBackticks()` AttributedString recreation
- SwiftUI string comparison overhead

However, this is expected behavior and 1.06s is borderline - may just be normal heavy UI work.

## Recommendation

**Priority: P3 (Low/Deferred)**

1. **Monitor**: Watch for recurrence during normal usage
2. **If recurs frequently**, consider:
   - Memoizing `formatWithBackticks()` results (cache AttributedString by content hash)
   - Using `EquatableView` wrapper for TimelineEntryRow
   - Profiling with Instruments to identify specific hot spots
3. **Not blocking**: Proceed with feature work; this is not a critical issue

## Related Files

- `Contextify/Contextify/TimelineEntryRow.swift` - View where hang occurred
- `Contextify/Contextify/ConversationMonitor.swift` - Decoration data management
- `/tmp/agent-decoration-issues.md` - Full issue tracking document

## Log Context

Last activity before hang (18:11:49):
```
[CACHE-UPSERT] Successfully saved summary for entry=c7908c5b
[SUMM-GENERATOR-DONE] entry=c7908c5b status=success elapsed_ms=1977
```

No logs between 18:11:49 and hang at 18:13:29.
