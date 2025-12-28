# Monitoring Operations

This document describes operational checks for transcript monitoring, watcher counts, and lazy watcher rollout diagnostics.

**Architecture Reference:** For detailed design, diagrams, and promotion mechanisms, see [lazy-watchers-architecture.md](../architecture/lazy-watchers-architecture.md).

## Watcher Counts

**Goal:** Multi-project tiered budget system manages watchers across HOT/WARM/COLD projects.

### Tiered Budget Model

- **HOT tier:** 20 most recent transcripts (actively selected project)
- **WARM tier:** 10 transcripts per warm project (up to 2 recently activated projects)
- **COLD tier:** No watchers, FSEvents detection only (all other projects)
- **LRU management:** Tracks 3 most recently activated projects

```bash
PID=$(ps aux | grep Contextify | grep -v grep | awk '{print $2}' | head -1)
lsof -p $PID | wc -l
```

**Expected:** FD count stays below 500 in typical configurations. Steady-state watchers are typically ≤ 40 unless large transcript sets are active.

## Watcher Budget Logs

Filter for lazy watcher events:

```bash
log show --predicate 'subsystem == "dev.contextify" AND category == "WatcherBudget"' --info --last 5m
```

Common markers:
- `[TIER-ASSIGNMENT] project=<id> tier=<hot|warm|cold> lru_index=<n>`
- `[PLAN-COMPUTED] total_target=<n> hot_target=<n> warm_target=<n> budget=<n> degraded=<0|1>`
- `[WATCHER-START] transcript=<id> project=<id> tier=<hot|warm>`
- `[WATCHER-STOP] transcript=<id> project=<id> reason=<eviction|plan>`
- `[DEGRADED-MODE] enabled=1 reason=fd_exhaustion`

## Activity Signals

FSEvents should hoover inactive transcripts without starting per-file watchers.

```bash
log show --predicate 'subsystem == "dev.contextify" AND category == "ActivitySignal"' --info --last 5m
```

Common markers:
- `[ACTIVITY-DETECTED] project=<id> transcript=<id> watched=<0|1>`
- `[PROJECT-SIGNAL-EMIT] project=<id> kind=projectActivityDetected`

## Unread Approximation

```bash
log show --predicate 'subsystem == "dev.contextify" AND category == "UnreadApprox"' --info --last 5m
```

Common markers:
- `[APPROX-TAIL-SCAN] transcript=<id> scanned_bytes=<n> lines=<n> errors=<n> new_entries=<n> confidence=<high|medium|low> timeout=<0|1>`
- `[APPROX-STORED] transcript=<id> count=<n> confidence=<high|medium>`

## Failure Signals

Search for FD exhaustion or watcher failures:

```bash
log show --predicate 'subsystem == "dev.contextify"' --info --last 1h | grep WATCHER-FD-OPEN-FAILED
```
