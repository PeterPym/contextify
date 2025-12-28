---
todo_id: INDEXING-UI-BLOCKING
title: Background Indexing Blocking Main Thread During Project Switch
type: investigation
date: 2025-12-28
status: active
description: Evidence from logs showing 16.5 second indexing operation blocking main thread (1651769) during project switching, causing UI delays
---

# Background Indexing Blocking Main Thread

## Summary

Log analysis reveals that background indexing operations are running on the main thread (1651769), causing UI blocking during project switches. A notable example shows a 16.5 second indexing operation (10:41:52.272 to 10:42:08.784) that blocks UI responsiveness.

## Evidence from Logs

**Source:** `/tmp/transcript-queue-monitor-20251228-104137.log`

### Timeline of UI Blocking Event

```
2025-12-28 10:41:52.271 I  Contextify[6462:1651769] [dev.contextify:ProjectSwitcher] [UIOPT-SWITCH-UI] activeProjectId updated immediately for instant feedback (elapsed: 0ms)
2025-12-28 10:41:52.272 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Starting background indexing...
2025-12-28 10:41:52.322 I  Contextify[6462:1654195] [dev.contextify:FastPathIngestion] [JIT-INGEST] Populating DB with 907 transcript records...
```

**Key observation:** Background indexing starts on main thread 1651769 immediately after project switch.

### Long-Running Indexing Operation

The indexing operation processes 907 transcript records and takes 16.5 seconds:

```
2025-12-28 10:41:52.272 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Starting background indexing...
[... 907 transcript updates ...]
2025-12-28 10:42:08.784 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Indexing cancelled
2025-12-28 10:42:08.784 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Background indexing complete
```

**Duration:** 16,512ms (16.5 seconds)
**Thread:** 1651769 (main thread)
**Records processed:** 907 transcripts

### Cascading Indexing Calls

After the long indexing operation completes, multiple rapid indexing calls occur on the main thread:

```
2025-12-28 10:42:14.653 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Starting background indexing...
2025-12-28 10:42:14.653 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Indexing cancelled
2025-12-28 10:42:14.653 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Background indexing complete
2025-12-28 10:42:14.653 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Starting background indexing...
2025-12-28 10:42:14.653 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Indexing cancelled
2025-12-28 10:42:14.653 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Background indexing complete
2025-12-28 10:42:14.654 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Starting background indexing...
2025-12-28 10:42:14.654 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Indexing cancelled
2025-12-28 10:42:14.654 I  Contextify[6462:1651769] [dev.contextify:AppOrchestrator] [ORCH-BACKGROUND] Background indexing complete
```

Multiple start/cancel/complete cycles in rapid succession suggest coordination issues.

## Impact

1. **UI Responsiveness:** 16.5 second blocking operation prevents UI updates during project switching
2. **User Experience:** Delays in project switching make the app feel unresponsive
3. **Main Thread Saturation:** Indexing work should be on background threads, not main thread

## Root Cause Analysis

The `[ORCH-BACKGROUND]` prefix suggests this should be background work, but the thread ID (1651769) indicates it's running on the main thread. This is likely due to:

1. Missing `@MainActor` isolation or incorrect async context
2. Synchronous database operations on main thread
3. Lack of proper Task.detached usage for truly independent background work

## Recommended Fix

1. Verify `AppOrchestrator` indexing methods are not marked `@MainActor`
2. Ensure indexing work is dispatched to background threads via `Task.detached(priority: .utility)`
3. Consider debouncing/coalescing indexing calls to prevent rapid start/cancel cycles
4. Add thread logging to verify background operations are not on main thread

## Related Code

Primary suspect: `AppOrchestrator` background indexing implementation
- Search for: `[ORCH-BACKGROUND]` logging calls
- Check: Thread context where indexing is invoked
- Review: Task creation patterns and actor isolation
