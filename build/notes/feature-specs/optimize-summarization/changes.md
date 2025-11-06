# Summarization Optimization - Branch Changes

## Overview

This branch temporarily disables LLM summarization during project switches to measure performance impact and identify bottlenecks in the project switching flow.

## Changes Made

### 1. Monitoring Script Created

**Location:** `/tmp/test-summarization-flow.sh`

**Purpose:** Monitor and capture logs related to summarization flow from project selection through to LLM queue operations.

**Log Tags:**
- `[SUMM-TAP]` - User taps project tab
- `[SUMM-SWITCH]` - ProjectSwitcherState initiates switch
- `[SUMM-COORD]` - StartupCoordinator processes switch
- `[SUMM-MONITOR]` - ConversationMonitor handles context update
- `[SUMM-LOAD]` - Timeline feed loading
- `[SUMM-MISSES]` - Cache misses detected
- `[SUMM-QUEUE]` - LLM queue operations (not used in this branch)
- `[SUMM-SKIP]` - Summarization skipped (new feature flag)

**Usage:**
```bash
/tmp/test-summarization-flow.sh
# Switch projects in the app
# Press Ctrl+C to stop
# Logs saved to /tmp/summarization-flow-YYYYMMDD-HHMMSS.log
```

### 2. Logging Added to Trace Summarization Flow

**Files Modified:**

#### ProjectSwitcherView.swift (Line 271)
- Added: `[SUMM-TAP]` log when user taps project tab

#### ProjectSwitcherState.swift (Lines 340, 378)
- Added: `[SUMM-SWITCH]` log when initiating switch
- Added: `[SUMM-SWITCH]` log before calling coordinator

#### StartupCoordinator.swift (Lines 242, 283, 286)
- Added: `[SUMM-COORD]` log on entry to switchProject()
- Added: `[SUMM-COORD]` log before publishing context
- Added: `[SUMM-COORD]` log after publishing context

#### ConversationMonitor.swift (Lines 656, 683, 964, 975, 1006, 1011)
- Added: `[SUMM-MONITOR]` log when receiving context update
- Added: `[SUMM-MONITOR]` log before calling startMonitoring()
- Added: `[SUMM-LOAD]` log when loading feed from SQL
- Added: `[SUMM-LOAD]` log after feed loaded with entry count
- Added: `[SUMM-MISSES]` log with cache miss count
- Added: `[SUMM-SKIP]` warning when summarization is skipped

### 3. Summarization Disabled

**Location:** `ConversationMonitor.swift:1010-1017`

**Change:**
```swift
// BEFORE:
if !misses.isEmpty, let generator = cacheMissGenerator {
    Task {
        await generator.queueMisses(misses)
    }
}

// AFTER:
if !misses.isEmpty, let generator = cacheMissGenerator {
    log.info("[SUMM-SKIP] ⚠️ Summarization disabled - skipping queueMisses() call for \(misses.count) entries")
    // DISABLED: Task {
    // DISABLED:     await generator.queueMisses(misses)
    // DISABLED: }
} else if misses.isEmpty {
    log.info("[SUMM-MISSES] No cache misses - all entries have summaries")
}
```

**Impact:**
- Timeline loads entries from database
- Cache misses are detected and counted
- LLM queue is NOT triggered (no summarization happens)
- Timeline displays entries without present/past form summaries

## Testing Methodology

### Step 1: Baseline with Summarization Disabled

1. Build and run app with this branch:
   ```bash
   make build
   ```

2. Start monitoring script:
   ```bash
   /tmp/test-summarization-flow.sh
   ```

3. Switch between projects with large conversation histories

4. Observe:
   - Project switch timing from `[SWITCH-START]` to `[SWITCH-END]`
   - Feed loading time from `[SUMM-LOAD]` logs
   - Number of cache misses detected
   - No LLM processing delays

5. Save logs and note performance metrics

### Step 2: Re-enable Summarization (Future)

1. Uncomment the `generator.queueMisses(misses)` call in ConversationMonitor.swift:1012-1014

2. Remove `[SUMM-SKIP]` log and restore original behavior

3. Repeat testing to compare performance with/without summarization

## Expected Observations

**With Summarization Disabled:**
- Faster project switches (no LLM queue blocking)
- Timeline entries show raw content (no summaries)
- No database writes to timeline_cache table
- Reduced CPU/memory usage during switches

**Flow Trace Example:**
```
[SUMM-TAP] User tapped project: contextify id=ABC123
[SUMM-SWITCH] ProjectSwitcherState initiating switch to: ABC123
[SUMM-SWITCH] Calling StartupCoordinator.switchProject(to: /path/to/project)
[SUMM-COORD] StartupCoordinator.switchProject() called for: /path/to/project
[SUMM-COORD] Publishing ActiveProjectContext (id: XYZ789, path: /path/to/project)
[SUMM-COORD] ActiveProjectContext published, subscribers should receive update
[SUMM-MONITOR] ConversationMonitor received context update for: contextify (id: XYZ789)
[SUMM-MONITOR] Calling startMonitoring(projectId: XYZ789)
[SUMM-LOAD] Loading feed from SQL for project: XYZ789
[SUMM-LOAD] Feed loaded: 247 entries from database
[SUMM-MISSES] Detected 183 cache misses
[SUMM-SKIP] ⚠️ Summarization disabled - skipping queueMisses() call for 183 entries
```

## Files Modified

1. `/tmp/test-summarization-flow.sh` (new)
2. `Contextify/Contextify/ProjectSwitcherView.swift`
3. `Contextify/Contextify/ProjectSwitcherState.swift`
4. `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`
5. `Contextify/Contextify/ConversationMonitor.swift`

## Rollback Instructions

To restore summarization:

```swift
// In ConversationMonitor.swift:1008-1017, replace with:
// Queue cache misses for background generation
if !misses.isEmpty, let generator = cacheMissGenerator {
    Task {
        await generator.queueMisses(misses)
    }
}
```

And remove all `[SUMM-*]` logging if desired (though keeping trace logging is useful for debugging).

## Related Documentation

- **Summarization flow trace:** See terminal output from exploration agent above
- **LLM architecture:** `build/notes/technical-reference/llm-processing-architecture.md`
- **Timeline cache:** `build/notes/technical-reference/timeline-cache-llm-architecture.md`
- **Startup coordinator:** `build/notes/technical-reference/startup-coordinator-architecture.md`
