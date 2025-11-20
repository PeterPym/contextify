# Console Log Error Investigation Report
**Date:** 2025-11-20
**Log File:** `/private/tmp/console.app-01.log`
**Timespan:** 08:47:49 to 08:51:11 (3.5 minutes)
**Total Lines:** 4,272

## Executive Summary

Three distinct error categories were identified in the log, with **watcher failures being the most critical**. Analysis reveals that watchers were never started during this session, leading to missing real-time updates for at least 2 transcripts. The root cause appears to be a gap in the watcher initialization sequence.

---

## Error Type 1: TRANSCRIPT-WATCHER Failures (CRITICAL)

### Frequency
- **3 occurrences** over 3.5 minutes
- **2 unique transcripts** affected

### Affected Transcripts
1. `F6B193ED-8726-4277-8C9F-4FB174A29A74`  
   - Project: banagale-com
   - File: `agent-6d49e3b0.jsonl`
   - Error time: 08:48:20

2. `47e507f6-84d2-41c9-b21b-1a048a7990ba`  
   - Project: contextify
   - File: `47e507f6-84d2-41c9-b21b-1a048a7990ba.jsonl`
   - Error times: 08:48:52, 08:50:25 (repeated)

### Root Cause Analysis

**Detection Mechanism:**
- Health check runs every 30 seconds (`ConversationMonitor.swift:3069`)
- Calls `TimelineDiagnostics.captureSnapshot()` to check watcher state
- Detection code: `TimelineDiagnostics.swift:330-336`

```swift
// Issue detection
if !isWatching && fileExists {
    issues.append(.init(
        severity: .critical,
        category: .watcherMissing,
        message: "[TRANSCRIPT-WATCHER] Watcher not running for transcript \(transcript.id) ...",
        recommendation: "Possible causes: race condition during startup, permission issue, or watcher start failure."
    ))
}
```

**Critical Finding: Watchers Never Started**

Evidence from log analysis:
- ❌ **Zero** `WATCHER-WATCH-START` logs (expected: at least 2)
- ❌ **Zero** `WATCHER-WATCH-DONE` logs
- ❌ **Zero** `WATCHER-WATCH-SKIP` logs  
- ❌ **Zero** `FSEVENTS-HEARTBEAT` logs (should emit every 60s showing watcher count)
- ❌ **Zero** `FSEVENTS-WATCH-STOP` logs
- ✅ **Files exist** on disk (confirmed by health check)

**What This Means:**
The watcher lifecycle logs prove that watchers were **never initialized** during this session, rather than being started and then failing. The file descriptors were never opened, FSEvents dispatch sources were never created, and the heartbeat was never started.

**Where Watchers Should Have Been Started:**

1. **During Project Discovery** (`ProjectDiscoveryService`)
   - After hoovering transcripts
   - Calls `orchestrator.startWatchingTranscript()`

2. **During Session Activation** (`ConversationMonitor`)
   - When active session changes
   - Should verify watcher is running via `setActiveSession()`

3. **During Health Check Recovery** (`ConversationMonitor:3126-3136`)
   - When watcher failure is detected
   - Should call `orchestrator.ensureProjectWatcher()`
   - **BUG:** No `[WATCHER-RECOVERY]` logs were emitted
   - **This suggests recovery was never executed or failed silently**

### Why Recovery Didn't Run

Analysis of recovery flow:
```swift
// ConversationMonitor.swift:3106-3122
for issue in snapshot.issues where issue.severity == .critical {
    await MainActor.run { [weak self] in
        self?.log.warning("🏥 Critical issue detected: \(issue.message, privacy: .public)")
    }

    // Auto-recovery for specific issues
    if issue.category == .watcherMissing {
        await attemptWatcherRecovery(
            projectId: projectId,
            orchestrator: orchestrator,
            targetTranscriptId: snapshot.watcherState.transcriptId
        )
    }
}
```

The critical issue log **was** emitted (we see it in the log), but `[WATCHER-RECOVERY]` log was **not** emitted.

**Possible Causes:**
1. **Recovery threw exception before logging** (line 3128-3131)
2. **`orchestrator.ensureProjectWatcher()` failed silently**
3. **Recovery was skipped** due to project switch guard (line 3100-3104)
4. **Task was cancelled** before reaching recovery code

**Most Likely: Exception During ensureProjectWatcher()**

The recovery method has a try-catch:
```swift
private func attemptWatcherRecovery(...) async {
    do {
        let summary = try orchestrator.ensureProjectWatcher(...)
        log.info("[WATCHER-RECOVERY] ...") // NEVER REACHED
    } catch {
        log.error("Watcher recovery failed: \(error.localizedDescription)")
    }
}
```

**No error log was emitted either**, which suggests:
- The `catch` block was never reached
- The error was thrown in a non-throwing context
- The task was cancelled mid-execution

### Codex Watcher Specifics

The user noted: "codex watchers seem to be breaking after a while with the app for unknown reasons."

**Key Observation:** Both failed transcripts are **Claude Code** sessions (`.jsonl` in `~/.claude/projects/`), NOT Codex sessions.

However, the pattern suggests a **systemic watcher initialization problem** that would affect all providers:
- If watchers aren't started during discovery, Codex sessions would also be affected
- The absence of heartbeat logs confirms **no watchers are active** for any provider
- This explains user-reported Codex issues: watchers start initially but fail to restart after certain events

**Hypothesis: Watcher Recovery Deadlock or Actor Isolation Issue**

Given Swift 6 strict concurrency and the `await MainActor.run` calls in recovery flow:
- Health check runs on background task
- Switches to MainActor to log critical issue
- Attempts watcher recovery (which may need MainActor or watcherQueue access)
- **Potential deadlock** or actor reentrancy issue

### Impact

**User-Facing:**
- Transcripts don't update in real-time
- User must manually refresh or restart app to see new content
- **Severe UX degradation** for active development sessions

**System:**
- Health check detects problem every 30 seconds
- Recovery is attempted but fails silently
- Error logs accumulate in console
- No automatic resolution without app restart

### Recommended Fixes

**Priority 1: Investigate Recovery Failure**
1. Add detailed logging to `ensureProjectWatcher()` entry point
2. Log every step of watcher recovery flow
3. Wrap recovery call in do-catch with explicit error logging
4. Check for actor isolation issues (Swift 6 strict concurrency)
5. Add timeout detection for recovery operations

**Priority 2: Improve Watcher Initialization**
1. Add `WATCHER-INIT-START` log at beginning of `watch()` call
2. Log file descriptor open result (success/failure with errno)
3. Log FSEvents dispatch source creation
4. Verify heartbeat starts (should see first `[FSEVENTS-HEARTBEAT]` log)
5. Add initialization health check after discovery completes

**Priority 3: Add Recovery Fallback**
1. If `ensureProjectWatcher()` fails, schedule retry with exponential backoff
2. After 3 failures, prompt user with actionable error + "Restart Monitoring" button
3. Add diagnostics API endpoint to manually trigger watcher recovery

**Testing:**
1. Add integration test that kills watchers mid-session and verifies recovery
2. Test watcher initialization during project discovery
3. Test watcher startup in sandboxed builds (security-scoped bookmarks)
4. Load test with 50+ watchers to verify file descriptor limits

---

## Error Type 2: FAST-PATH-RESET (WARNING, not ERROR)

### Frequency
- **27 occurrences** over 3.5 minutes
- Affects **3 projects** (same projects repeatedly)

### Affected Projects
1. `-Users-rob-code-personal-finance` (forced=2)
2. `-Users-rob-code-projects-cli-ai-setup-templates-commands` (forced=2)  
3. `-Users-rob-code-personal-job-hunt-2025-interviews` (forced=1)

### What This Error Means

**Source:** `FastPathIngestionCoordinator.swift:190`

```swift
if entryCount == 0 {
    do {
        let forcedIds = try orchestrator.forceResetIngestState(projectId: projectId, limit: forcedPreviewCount)
        if !forcedIds.isEmpty {
            log.warning("[FAST-PATH-RESET] project=\(projectId, privacy: .public) forced=\(forcedIds.count, privacy: .public)")
        }
    } catch {
        log.error("[FAST-PATH-RESET] Failed to reset ingest state ...")
    }
}
```

**Trigger Condition:**
- All transcripts for a project are marked `ingest_state = "complete"`
- BUT entry count for project is **0** in database
- System forces reset of ingest state for up to N transcripts to re-process them

**Root Cause:**
This is a **data inconsistency recovery mechanism**, not an error:
- Database migration issue (entries lost but ingest state not reset)
- Discovery ran but ingestion failed
- Database cleared but transcript metadata not reset
- First-time project discovery with no prior entries

### Why This Is Logged at ERROR Level

**Analysis:** This is **miscategorized**. Should be `.warning` or `.info`.

**Evidence:**
- The code already uses `log.warning()` (line 190)
- But Console.app interprets it as `error` level
- This is a **normal recovery path**, not a failure

**Impact:**
- Misleading error logs (inflates error count)
- Makes it harder to spot actual problems
- Creates false impression of system instability

### Recommended Fix

**Immediate:**
- Verify OSLog configuration: `Logger(subsystem: "dev.contextify", category: "FastPath")`
- Check if `.warning` is being mapped to `error` level by OSLog

**Medium-term:**
- Add context to message: `[FAST-PATH-RESET-RECOVERY] Resetting ingest state for project with 0 entries (forced=N transcripts)`
- Add `.debug` log showing why reset was triggered
- Track reset frequency in diagnostics (if same project resets >5x in 5 minutes, that's a real bug)

---

## Error Type 3: SUMM-VIEWPORT-FALLBACK (INFO, not ERROR)

### Frequency
- **11 occurrences** over 3.5 minutes
- Distributed across timeline interactions

### Sample Logs
```
error 08:47:50.516953  [SUMM-VIEWPORT-FALLBACK] Triggering fallback snapshot (4 IDs, reason=programmatic-scroll)
error 08:48:16.764795  [SUMM-VIEWPORT-FALLBACK] Triggering fallback snapshot (2 IDs, reason=programmatic-scroll)
error 08:48:25.851654  [SUMM-VIEWPORT-FALLBACK] Triggering fallback snapshot (4 IDs, reason=programmatic-scroll)
```

### What This Means

**Context:** LLM summary viewport tracking system
- Timeline uses viewport visibility to trigger LLM summaries for visible entries
- When viewport tracking fails or is uncertain, system falls back to snapshot-based detection
- Ensures summaries are generated even if viewport events are missed

**Trigger Reason:** `programmatic-scroll`
- Timeline is being scrolled programmatically (not user interaction)
- Viewport tracking may be temporarily unavailable
- System takes snapshot of visible entries as fallback

### Root Cause

**This is NOT an error** - it's a **fallback path in the happy flow**.

**Design Intent:**
- Primary: Viewport onAppear/onDisappear events
- Fallback: Periodic snapshot when events are unreliable
- Programmatic scroll is a known case where events may be delayed/missed

**Why Logged at ERROR Level:**
- Similar to FAST-PATH-RESET, this is miscategorized
- Should be `.debug` or `.info` level
- Only ERROR if fallback itself fails

### Impact

**Functional:**
- ✅ Summaries are still generated correctly
- ✅ No user-visible impact
- Fallback mechanism is working as designed

**Logging:**
- Inflates error count
- Makes logs harder to read
- Obscures actual problems (like watcher failures)

### Recommended Fix

**Immediate:**
- Change log level from `.error` to `.debug`
- Only log at `.warning` if fallback snapshot also fails

**Medium-term:**
- Add metrics: track fallback frequency vs. normal viewport path
- If fallback is used >80% of the time, investigate viewport event reliability
- Add timeout detection: if viewport events don't fire within 500ms of scroll, use fallback

---

## Cross-Cutting Observations

### Logging Hygiene Issues

**Problem:** Too many INFO/DEBUG operations logged at ERROR level

**Impact:**
- Hard to distinguish real errors from normal operations
- Error count is misleading (41 "errors" vs. 3 real issues)
- Diagnostic signal-to-noise ratio is poor

**Recommendation:**
1. **Audit all log.error() calls** - ensure they represent actual failures
2. **Reserve .error for unrecoverable failures** requiring user action
3. **Use .warning for recoverable issues** (like forced resets)
4. **Use .info for normal fallback paths** (like viewport snapshots)
5. **Use .debug for verbose diagnostics** (like watcher lifecycle)

### Missing Diagnostic Logs

**Watcher Lifecycle:**
- No logs for watcher startup, despite 2 active transcripts
- No heartbeat logs (should emit every 60s)
- No logs for watcher file descriptor open/close
- Makes it impossible to debug watcher initialization failures

**Recommendation:**
Add comprehensive watcher lifecycle logging:
- `[WATCHER-INIT-START] transcript=X file=Y`
- `[WATCHER-FD-OPEN] fd=42 path=Y`
- `[WATCHER-SOURCE-CREATE] transcript=X`
- `[WATCHER-SOURCE-RESUME] transcript=X`
- `[WATCHER-ARMED] transcript=X ✅`
- `[FSEVENTS-HEARTBEAT] watching=N` (every 60s)

### Swift 6 Concurrency Considerations

**Observation:** Multiple `await MainActor.run` calls in health check flow

**Potential Issue:**
- Health check runs on background task
- Switches to MainActor for logging
- Switches back to background for orchestrator calls
- Watcher uses `DispatchQueue` (pre-Swift 6 concurrency)
- **Possible deadlock or actor reentrancy issue**

**Recommendation:**
1. Audit all actor boundaries in health check → recovery flow
2. Verify `ensureProjectWatcher()` doesn't await MainActor while holding watcherQueue lock
3. Add timeout monitoring for recovery operations (should complete in <1s)
4. Consider Swift 6 actor-based watcher instead of DispatchQueue

---

## Priority Action Items

### P0 (Critical - User Impact)

1. **Investigate watcher recovery silence**
   - Why no `[WATCHER-RECOVERY]` or error logs?
   - Add verbose logging to recovery flow
   - Test recovery in clean environment
   - Estimated effort: 2-3 hours

2. **Fix watcher initialization gap**
   - Verify watchers are started after discovery
   - Add health check immediately after project switch
   - Ensure active session changes trigger watcher verification
   - Estimated effort: 3-4 hours

### P1 (Important - Logging Quality)

3. **Reclassify log levels**
   - FAST-PATH-RESET: error → warning
   - SUMM-VIEWPORT-FALLBACK: error → debug/info
   - Audit all `.error()` calls
   - Estimated effort: 2 hours

4. **Add watcher lifecycle logging**
   - File descriptor open/close
   - FSEvents source creation/cancellation
   - Heartbeat initialization
   - Estimated effort: 2 hours

### P2 (Nice to Have - Diagnostics)

5. **Add recovery retry mechanism**
   - Exponential backoff for failed recovery
   - User-facing "Restart Monitoring" button
   - Diagnostics API manual recovery endpoint
   - Estimated effort: 4-6 hours

6. **Integration tests for watcher recovery**
   - Kill watchers mid-session
   - Verify auto-recovery
   - Test sandboxed builds
   - Load test with 50+ watchers
   - Estimated effort: 6-8 hours

---

## Conclusion

The most critical issue is **watcher initialization failure**, not watcher crashes after running. The evidence shows watchers were never started during this session, and the auto-recovery mechanism fails silently. This explains the user-reported issue: "codex watchers seem to be breaking after a while" - they likely never restart after project switches or discovery re-runs.

**The other two "errors" are not actually errors** - they are normal operational logs miscategorized at ERROR level, creating noise that obscures the real problem.

**Next Steps:**
1. Reproduce watcher initialization failure in clean environment
2. Add verbose logging to capture failure point
3. Fix recovery silence (determine why no logs are emitted)
4. Implement retry mechanism for robust recovery
5. Reclassify log levels to improve signal-to-noise

---

**Report Generated:** 2025-11-20
**Analyzed by:** Claude Code Investigation
**Log Duration:** 3.5 minutes (08:47:49 to 08:51:11)
**Total Issues:** 3 (1 critical, 2 miscategorized)
