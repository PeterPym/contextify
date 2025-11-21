# P0 #P1-DISCOVERY Fix - Welcome Modal 11s Hang

**Date:** 2025-11-18
**Priority:** P0 (Blocking Release)
**Issue:** #P1-DISCOVERY in build/notes/TODOS.md
**Branch:** `feature/p0-project-discovery-fix`

## Problem Statement

Welcome modal showed "1/19 projects" for **11+ seconds** during first launch, appearing frozen to users. This created a broken onboarding experience.

### Timing Breakdown (Before Fix)

```
00:29:16.348: ProjectsViewModel.discoverProjects() completes (131ms) ✅
00:29:18.285: Ingestion completes (1.937s) ✅
00:29:18.285-29.966: **11.7 SECOND GAP** ⚠️ <-- THE PROBLEM
00:29:29.966: ProjectActivityMonitor.start() finally runs
00:29:30.443: ProjectActivityMonitor discovery completes (477ms)
```

**Total welcome modal time:** 14+ seconds (unacceptable)

## Root Cause Analysis

Three compounding issues:

### Issue 1: Missing Notification (Primary Cause)
`ProjectsViewModel.discoverProjects()` never posted `.projectsDiscoveryComplete` notification after completing.

**Impact:** ProjectSwitcherState waited for notification that never came → fell back to 5-second timeout

### Issue 2: Fallback Timeout Delay
`ProjectSwitcherState.scheduleMonitorStart()` waited 5 seconds for fallback timeout before starting ProjectActivityMonitor.

**Code:**
```swift
monitorFallbackTask = Task { [weak self] in
  try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 second delay!
  await self.startGlobalMonitoringIfNeeded(reason: "fallback-timeout")
}
```

### Issue 3: Duplicate Discovery
After timeout, `ProjectActivityMonitor.startGlobalMonitoring()` ran its own `discoverAllProjects()` even though ProjectsViewModel had already discovered and ingested everything.

**Impact:** Wasted additional ~500ms rescanning filesystem

**Total delay:** 5s timeout + ~6.7s unknown + 0.5s duplicate discovery = **12.2s hang**

## Solution

### Part 1: Post Missing Notification

**File:** `Contextify/Contextify/ProjectsViewModel.swift:150-172`

Added notification post after discovery completes:

```swift
// POST .projectsDiscoveryComplete notification to unblock ProjectSwitcherState
// This was previously missing, causing a 5-second timeout delay before
// ProjectActivityMonitor could start. See P0 #P1-DISCOVERY for details.
await MainActor.run {
  NotificationCenter.default.post(name: .projectsDiscoveryComplete, object: nil)
}
logger.info("[DISCOVERY-NOTIFICATION] Posted .projectsDiscoveryComplete notification")
```

**Impact:** Eliminates 5-second timeout delay

### Part 2: Skip Duplicate Discovery

**File:** `app/Sources/ContextifyCore/ProjectActivityMonitor.swift:74-83`

Added check to skip discovery if projects already exist:

```swift
// Check if projects were already discovered and ingested by ProjectsViewModel
// If so, skip the expensive discoverAllProjects() call (P0 #P1-DISCOVERY optimization)
let projectCount = (try? orchestrator.listProjects().count) ?? 0
if projectCount > 0 {
  log.info("[INIT-SKIP-DISCOVERY] Projects already ingested (count: \(projectCount, privacy: .public)) - skipping duplicate discovery")
} else {
  log.info("[INIT-FULL-DISCOVERY] No projects in database - running full discovery")
  try await discoverAllProjects()
}
```

**Impact:** Eliminates ~500ms duplicate filesystem scan

### Part 3: Comprehensive Logging

Added logging to verify fix works:

**ProjectsViewModel.swift:**
- `[DISCOVERY-START]` - Discovery begins
- `[DISCOVERY-COMPLETE]` - Discovery completes with duration
- `[DISCOVERY-NOTIFICATION]` - Notification posted

**ProjectSwitcherState.swift:**
- `[SWITCHER-MONITOR] Waiting for .projectsDiscoveryComplete notification...`
- `[SWITCHER-MONITOR] ✅ Received .projectsDiscoveryComplete notification`
- `[SWITCHER-MONITOR] ⚠️ Fallback timeout triggered` (should NOT appear)

**ProjectActivityMonitor.swift:**
- `[INIT] ProjectActivityMonitor: starting global monitoring`
- `[INIT-SKIP-DISCOVERY] Projects already ingested` (optimization working)
- `[INIT-COMPLETE] ProjectActivityMonitor startup complete in XXms`

## Expected Results

### Before Fix
- Welcome modal time: **14+ seconds**
- Fallback timeout: **Triggered (bad)**
- Duplicate discovery: **Yes (wasted work)**
- User experience: **Broken (appears frozen)**

### After Fix
- Welcome modal time: **<3 seconds** (82% improvement)
- Fallback timeout: **Not triggered** (notification path works)
- Duplicate discovery: **No** (optimization working)
- User experience: **Responsive** (smooth progress)

### Target Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Discovery → Monitor Start | 11.7s | <200ms | 98% |
| Total Welcome Modal Time | 14s | <3s | 79% |
| Duplicate Discovery | Yes | No | 100% |

## Testing

### Automated Validation

Created `scripts/logging/validate-discovery-fix.sh` to verify:
1. ✅ Discovery completes successfully
2. ✅ `.projectsDiscoveryComplete` notification posted
3. ✅ Notification received by ProjectSwitcherState
4. ✅ Gap between post and receive <200ms
5. ✅ ProjectActivityMonitor started
6. ✅ Monitor skipped duplicate discovery
7. ✅ No fallback timeout triggered
8. ✅ Total time <3000ms

**Usage:**
```bash
bash scripts/logging/validate-discovery-fix.sh /path/to/log.log
```

### Manual Test Plan

See `build/docs/testing/p0-discovery-fix-test-plan.md` for complete test scenarios:
- Test 1: Clean database first launch (primary)
- Test 2: Existing database startup
- Test 3: Discovery failure handling
- Test 4: Rapid restart race condition

## Files Changed

```
Contextify/Contextify/ProjectsViewModel.swift
  - Added notification post after discovery (lines 150-172)
  - Added timing logs

app/Sources/ContextifyCore/ProjectActivityMonitor.swift
  - Added duplicate discovery skip (lines 74-83)
  - Added completion timing log (lines 120-122)

Contextify/Contextify/ProjectSwitcherState.swift
  - Added notification wait logging (line 730)
  - Added notification received logging (line 733)
  - Added fallback timeout warning (line 743)

scripts/logging/validate-discovery-fix.sh (NEW)
  - Automated validation script

build/docs/testing/p0-discovery-fix-test-plan.md (NEW)
  - Comprehensive test plan
```

## Risk Assessment

**Risk Level:** Low

**Reasoning:**
1. No architectural changes
2. Only added missing notification (should have been there all along)
3. Skip optimization is safe (checks database before running)
4. Extensive logging for verification
5. Fallback path still exists if notification fails

**Rollback:** Simple revert of 3 files

## Next Steps

1. Test with clean database (first launch scenario)
2. Run validation script
3. Verify metrics meet targets
4. Update TODOS.md to mark #P1-DISCOVERY as complete
5. Commit changes
6. Update release notes

## References

- Original investigation: `build/docs/archive/investigations/2025-11-17-discoverallprojects-fastpath.md`
- TODO entry: `build/notes/TODOS.md` line 218 (#P1-DISCOVERY)
- Log evidence: `/private/tmp/transcript-queue-monitor-20251118-002852.log`
