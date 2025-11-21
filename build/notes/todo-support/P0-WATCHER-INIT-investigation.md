---
todo_id: P0-WATCHER-INIT
title: Watcher initialization recovery investigation
type: investigation
date: 2025-11-20
status: reference
description: Logs, root causes, and remediation steps for the watcher initialization gap that stopped real-time transcripts after project switches.
---

## Problem
Watchers were never initialized during several lifecycle events (project switches, discovery re-runs, health check recovery), so transcripts stopped streaming updates and users had to restart the app to see new entries.

## Evidence
- Health check audits show the failure pattern but no recovery logs ever emitted.
- There were zero watcher lifecycle logs (`WATCHER-WATCH-START`, `WATCHER-WATCH-DONE`, `FSEVENTS-HEARTBEAT`).
- Two active transcripts (banagale-com, contextify) were never watched despite files existing on disk.
- Recovery attempts logged by the health check were silent: no `[WATCHER-RECOVERY]` success or `[WATCHER-RECOVERY-ERROR]`, suggesting the task was failing before the logging point.

## Root Causes
1. **Silent recovery failure (primary):** `ConversationMonitor.attemptWatcherRecovery()` calls `orchestrator.ensureProjectWatcher()` without visibility into thrown exceptions or cancellation, so the recovery work completes silently and never restarts watchers.
2. **Initialization gap:** The watcher lifecycle was never triggered during project discovery, session activation, or health check recovery, leaving transcripts unobserved after context switches.
3. **Actor isolation and logging discrepancies:** Health checks run on background tasks while watcher initialization involves a pre-Swift 6 `DispatchQueue`, creating a risk of deadlocks when control crosses actor boundaries and preventing completion logs from ever appearing.

## Recovery Plan
### Phase 1 – Diagnose (1 hour)
1. Add verbose health check/recovery logging in `ConversationMonitor.attemptWatcherRecovery()` (start/call/success/error tags).
2. Instrument `TranscriptOrchestrator.ensureProjectWatcher()` with logs for each transcript check, watcher start, and completion counts.
3. Verify `TranscriptWatcher.watch()` emits start/FD-open/source/heartbeat logs (including `[WATCHER-FD-OPEN]` and `[FSEVENTS-HEARTBEAT-START]`) to see why watchers never advance.

### Phase 2 – Fix (1-2 hours)
- Apply the insights from Phase 1 to add timeout monitoring, actor-safe scheduling, and explicit retries/backoff in `attemptWatcherRecovery()`.
- Guarantee `TranscriptWatcher.watch()` is idempotent and resilient to repeated calls, ensuring any path needing a watcher can request it safely.
- Address the identified actor isolation/deadlock path by confining UI-facing logging to the `MainActor` and offloading watcher coordination to a dedicated queue or structured concurrency task.

### Phase 3 – Verify (1 hour)
1. Reproduce the watcher failure pattern in a clean environment (project switch, discovery rerun).
2. Confirm recovery logs appear and complete successfully; `[FSEVENTS-HEARTBEAT]` should emit every 60 seconds.
3. Verify project switches and app resumes restart watchers automatically and bring timeline updates within two seconds for both Claude Code and Codex sessions.

## Acceptance Criteria
- Real-time watcher lifecycle logs appear during normal operation.
- `[WATCHER-RECOVERY]` emits success or failure for every attempted recovery.
- Heartbeat logs fire every 60 seconds for active watchers.
- Watchers restart after project switches and survive app resume/background transitions.
- Timeline updates happen continuously without manual refresh.
- No more `[TRANSCRIPT-WATCHER]` critical issue logs in production portions of the log stream.

## Testing
1. Monitor the console log while switching projects to ensure recovery logs and heartbeats appear.
2. Modify an active transcript file and verify the timeline updates within two seconds.
3. Run scenarios with both Claude Code and Codex sessions to confirm consistent watcher coverage.
4. Trigger app resume/background flows to ensure watchers survive lifecycle transitions.

## Related Issues
- User report: “codex watchers seem to be breaking after a while.” Investigation revealed the issue is a failure to restart watchers rather than a crash.
