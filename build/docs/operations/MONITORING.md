# Monitoring Operations

This document describes operational checks for transcript monitoring, watcher counts, and lazy watcher rollout diagnostics.

## Watcher Counts

**Goal:** Only the active project uses per-file watchers. Inactive projects rely on FSEvents updates.

```bash
PID=$(ps aux | grep Contextify | grep -v grep | awk '{print $2}' | head -1)
lsof -p $PID | wc -l
```

**Expected:** FD count stays below 500 in typical configurations.

## Lazy Watcher Logs

Filter for lazy watcher events:

```bash
log show --predicate 'subsystem == "dev.contextify"' --info --last 5m | grep LAZY-WATCHER
```

Common markers:
- `[LAZY-WATCHER] activeProjectId=... watcherCount=...`
- `[LAZY-WATCHER] Teardown scheduled project=...`
- `[LAZY-WATCHER] Teardown executed project=...`

## FSEvents Routing

FSEvents should hoover inactive transcripts without starting per-file watchers.

```bash
log show --predicate 'subsystem == "dev.contextify" AND category == "ProjectActivity"' --info --last 5m | grep FSEVENTS
```

## Failure Signals

Search for FD exhaustion or watcher failures:

```bash
log show --predicate 'subsystem == "dev.contextify"' --info --last 1h | grep WATCHER-FD-OPEN-FAILED
```
