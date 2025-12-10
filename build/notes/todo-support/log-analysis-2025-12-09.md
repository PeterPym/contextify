---
todo_id: P0-LOG-ISSUES
title: Log Analysis - Dec 2025
type: investigation
date: 2025-12-09
status: active
description: Deep analysis of 37MB logs identifying 5 issues with root causes
---

# Contextify Deep Log Analysis Report

**Analysis Date:** 2025-12-09
**Log Period:** Dec 8-9, 2025 (~36 hours)
**Total Log Files:** 22 files
**Total Log Size:** 37MB

---

## Executive Summary

Analysis of 37MB of logs from 22 sessions over 36 hours reveals several distinct issues, ranked by severity and actionability:

| Priority | Issue | Occurrences | Impact | Root Cause Status |
|----------|-------|-------------|--------|-------------------|
| **P0** | Transcript validation failures (summary-only files) | 108 failures / 20 unique files | Transcripts not ingested | **ROOT CAUSE FOUND** |
| **P1** | Codex watcher recovery infinite loop | 96+ recovery errors | CPU/battery waste, log noise | **ROOT CAUSE FOUND** |
| **P2** | Timeline high refresh rate | 20+ occurrences | Performance degradation | **ROOT CAUSE FOUND** |
| **P3** | getCWD failures for Codex transcripts | 3000+ failures | Log noise, Codex not indexed | Known limitation |
| **P4** | Apple Intelligence cancellation errors | 45 occurrences | Benign (self-healing works) | Expected behavior |

---

## Issue #1: Transcript Validation Failures (P0)

### Symptom
```
❌ Transcript validation failed: <private> - 1 error(s)
[TRANS-DISC-PREFLIGHT-FAIL] b9990b98-f054-4453-80f0-a478a3810604.jsonl
```

**Occurrences:** 108 failures across 20 unique transcript files
**Most affected:** `b9990b98-f054-4453-80f0-a478a3810604.jsonl` (20 failures)

### Root Cause Analysis

**Location:** `app/Sources/ContextifyCore/Database/TranscriptValidator.swift:219-222`

The validator requires these fields for Claude Code transcripts:
```swift
hasRequiredFields = json["uuid"] != nil
                 && json["timestamp"] != nil
                 && json["type"] != nil
```

**The failing transcripts start with summary lines that lack `uuid` and `timestamp`:**

```json
{"type":"summary","summary":"Debugging App Store Permissions...","leafUuid":"3e70afb7..."}
```

**This is valid Claude Code format** - summary lines at the top of transcripts are normal. The validator's structural check reads only the first 4 lines (`linesToCheck: 4`), and if all 4 are summary lines, validation fails.

### Evidence

Checked multiple failing transcripts:
- `b9990b98-f054-4453-80f0-a478a3810604.jsonl` - First 5 lines are all `type=summary`
- `d0575562-3394-4a23-be9e-337ad94a9cd5.jsonl` - First line is `type=summary`
- `71f3c2d6-86fd-41ab-8e0d-f087bfd8fa1a.jsonl` - First line is `type=summary`

### Fix Required

The validator should either:
1. Skip summary lines and look for the first non-summary entry
2. Accept `type=summary` with `leafUuid` as a valid entry type
3. Increase `linesToCheck` to find a valid entry past the summary lines

### Affected Files
- `app/Sources/ContextifyCore/Database/TranscriptValidator.swift:162-251` (validateStructure method)

---

## Issue #2: Codex Watcher Recovery Infinite Loop (P1)

### Symptom
```
🏥 Critical issue detected: [TRANSCRIPT-WATCHER] Watcher not running for transcript 71FD6695...
[RECOVERY-TRIGGER] Recovering ALL watchers for project=L1VzZXJzL3JvYi9jb2RlL3Byb2plY3RzL2NvbnRleHRpZnk=
[WATCHER-RECOVERY-ERROR] Recovery failed: Access to security-scoped resource denied: /Users/rob/Library/Containers/sh.contextify.Contextify/Data/.codex/sessions
```

**Occurrences:**
- 43 recovery attempts for transcript `71FD6695-0796-45D4-8F2E-9551452C8D53`
- 96+ total watcher recovery errors
- Errors occur every ~30 seconds in a loop

### Root Cause Analysis

The watcher recovery logic attempts to recover watchers for **ALL** providers when detecting a missing watcher. When the app has:
1. Claude Code permission (granted)
2. Codex permission (NOT granted or stale bookmark)

The recovery:
1. Detects a Codex transcript in the timeline (from database)
2. Triggers recovery for ALL watchers
3. Fails because Codex security scope is denied
4. Repeats on next health check (~30s)

**The base64 project ID decodes to:** `/Users/rob/code/projects/contextify`

**Key insight:** The Codex transcript `rollout-2025-10-24T17-33-49...` exists in `~/.codex/sessions/` but the app doesn't have a valid security-scoped bookmark for that directory. The recovery loop is trying to watch a file it can't access.

### Evidence

From logs at 14:10-14:19:
```
14:10:46 [PERMISSIONS] ✅ Granted access for codex
14:11:37 [WATCHER-RECOVERY-ERROR] Recovery failed...denied: .codex/sessions
14:12:08 [WATCHER-RECOVERY-ERROR] Recovery failed...denied: .codex/sessions
14:12:40 [WATCHER-RECOVERY-ERROR] Recovery failed...denied: .codex/sessions
```

The errors continue at ~30s intervals despite the permission being "granted" - suggesting the bookmark became stale or the path resolution is wrong.

### Fix Required

1. Check security scope availability before attempting watcher recovery
2. Don't trigger recovery for providers without valid security scope
3. Add exponential backoff for recovery failures to prevent tight loops
4. Log the specific provider that failed, not just the project

### Affected Files
- `Contextify/Contextify/ConversationMonitor.swift` (recovery trigger logic)
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift:1982` (recovery implementation)
- `app/Sources/ContextifyCore/Sandbox/TranscriptAccessProvider.swift` (security scope management)

---

## Issue #3: Timeline High Refresh Rate (P2)

### Symptom
```
[TIMELINE-REFRESH-RATE] High refresh rate: 10 refreshes in 5s (triggers: setupHooveringProgressNotifications, startMonitoring, onProjectOrSessionChange...)
```

**Occurrences:** 20+ events, with refresh rates up to 10/5s

### Root Cause Analysis

**Location:** `Contextify/Contextify/ConversationMonitor.swift:1374-1386`

Multiple notification handlers are triggering `loadFeedFromSQL()`:
1. `setupHooveringProgressNotifications` - Hoover progress notifications
2. `startMonitoring` - Called when project changes
3. `onProjectOrSessionChange` - Project/session change handler
4. `handleQueueOperationsProcessed` - LLM queue completion

**The problem:** These handlers fire independently and each triggers a timeline refresh. During startup or project switch, multiple notifications fire near-simultaneously.

### Evidence

The mangled Swift method names show the call sites:
```
$s10Contextify19ConversationMonitorC35setupHooveringProgressNotifications33...
$s10Contextify19ConversationMonitorC15startMonitoring9projectId...
$s10Contextify19ConversationMonitorC24onProjectOrSessionChange33...
```

### Fix Required

1. Coalesce multiple refresh requests with debouncing
2. Add a "refresh pending" flag to skip redundant loads
3. Consider batching notifications during startup

### Affected Files
- `Contextify/Contextify/ConversationMonitor.swift:1388-1410` (loadFeedFromSQL)
- Notification setup methods in ConversationMonitor

---

## Issue #4: getCWD Failures for Codex Transcripts (P3)

### Symptom
```
[DISC-LIGHT] getCWD failed for Codex transcript: rollout-2025-11-03T09-49-46-019a4ad6...
```

**Occurrences:** 3000+ failures across 91 unique Codex transcripts

### Root Cause

All Codex "rollout" transcripts have a different structure. The `getCWD` function expects Claude Code format:
- Claude Code: First line contains conversation data with `cwd` field
- Codex rollout: First line is `session_meta` with `payload.cwd`

The discovery code doesn't handle the Codex nested structure.

### Evidence

Codex rollout format:
```json
{"timestamp":"...","type":"session_meta","payload":{"id":"...","cwd":"/Users/rob/code/projects/contextify",...}}
```

The `cwd` is nested inside `payload`, not at the top level.

### Fix Required

Update `getCWD` extraction to handle Codex format:
```swift
// Try Claude Code format first
if let cwd = json["cwd"] as? String { return cwd }
// Try Codex format (nested in payload)
if let payload = json["payload"] as? [String: Any],
   let cwd = payload["cwd"] as? String { return cwd }
```

### Affected Files
- `app/Sources/ContextifyCore/Discovery/LightweightDiscovery.swift` (getCWD implementation)
- `app/Sources/ContextifyCore/Coordination/ProjectIdentity.swift` (extractCwdFromTranscript)

---

## Issue #5: Apple Intelligence Cancellation Errors (P4 - Benign)

### Symptom
```
❌ Apple Intelligence BECAME UNAVAILABLE - Health check cancelled
⚠️ Apple Intelligence RECOVERED - Now available
```

**Occurrences:** 45 cancellations, 44 recoveries

### Analysis

These are **expected** during project switches and app lifecycle events. The health check task is cancelled when a new check starts, causing a transient "unavailable" state that self-heals.

The logging correctly identifies this:
```
Error type: CancellationError (parent task cancelled, likely app lifecycle event)
This is NOT a real Apple Intelligence failure - treating as transient
```

### Recommendation

No code changes needed. Consider reducing log level to `.debug` for cancellation errors since the code already handles them correctly.

---

## Additional Observations

### Transcript Files Consistently Failing Validation

| File | Location | First Line Type |
|------|----------|-----------------|
| `b9990b98-f054-4453-80f0-a478a3810604.jsonl` | contextify | `type=summary` |
| `d0575562-3394-4a23-be9e-337ad94a9cd5.jsonl` | contextify | `type=summary` |
| `71f3c2d6-86fd-41ab-8e0d-f087bfd8fa1a.jsonl` | -Users-rob | `type=summary` |
| `6994b5e7-8e4c-4b90-9999-a92b9487e946.jsonl` | finance | (file exists but empty first line?) |
| `1ee30814-ac8a-4101-962d-69721218bb9d.jsonl` | -Users-rob | `type=summary` |

### Security-Scoped Resource Paths

The logs show two problematic paths:
1. `/Users/rob/Library/Containers/sh.contextify.Contextify/Data/.codex/sessions` - Container path, not real Codex path
2. `/Users/rob/Library/Containers/sh.contextify.Contextify/Data/.claude/projects` - Container path, not real Claude path

**Hypothesis:** The app is resolving paths relative to its container instead of the user's home directory when bookmarks are missing or stale.

---

## Priority Action Items

### Immediate (P0/P1)

1. **Fix transcript validation** to handle summary-prefixed transcripts
   - File: `app/Sources/ContextifyCore/Database/TranscriptValidator.swift`
   - Change: Skip `type=summary` lines in structural validation

2. **Fix watcher recovery loop**
   - File: `Contextify/Contextify/ConversationMonitor.swift`
   - Change: Check security scope before triggering recovery, add backoff

### Short-term (P2/P3)

3. **Debounce timeline refreshes**
   - File: `Contextify/Contextify/ConversationMonitor.swift`
   - Change: Coalesce refresh requests within 100ms window

4. **Fix Codex getCWD extraction**
   - File: `app/Sources/ContextifyCore/Discovery/LightweightDiscovery.swift`
   - Change: Handle nested `payload.cwd` format

---

## Log Files Analyzed

| File | Size | Date | Session Type |
|------|------|------|--------------|
| `transcript-queue-monitor-20251208-111748.log` | 3.9M | Dec 8 11:29 | Extended session |
| `transcript-queue-monitor-20251208-221026.log` | 1.1M | Dec 8 22:13 | Evening session |
| `transcript-queue-monitor-20251209-091550.log` | 608K | Dec 9 09:18 | Morning startup |
| `transcript-queue-monitor-20251209-103915.log` | 5.1M | Dec 9 10:41 | Largest session |
| `transcript-queue-monitor-20251209-140725.log` | 4.1M | Dec 9 14:19 | Afternoon session |
| `transcript-queue-monitor-20251209-153432.log` | 1.8M | Dec 9 15:39 | Latest session |
| (+ 16 more files) | | | |

---

## Appendix: Error Frequency Summary

```
108 ❌ Transcript validation failed: <private> - 1 error(s)
 96 [WATCHER-RECOVERY-ERROR] Recovery failed...Access to security-scoped resource denied
 91 [RECOVERY-TRIGGER] Recovering ALL watchers...triggered by: 71FD6695...
 70 ⚠️ Transcript validation warnings: <private> - 1 warning(s)
 54 🏥 Critical issue detected: Timeline restart guard triggered
 45 ❌ Apple Intelligence BECAME UNAVAILABLE
 44 ⚠️ Apple Intelligence RECOVERED
 33 [DISC-LIGHT] getCWD failed for Codex transcript (per unique file)
 20 [TIMELINE-REFRESH-RATE] High refresh rate
 17 ProjectSwitcher: start() called while started
```
