# Smart Lazy Watchers v2: Architecture & Operational Guide

**Status:** Active (WatcherBudgetCoordinator)
**Last Updated:** 2025-12-28
**Target Audience:** Developers maintaining transcript monitoring

This document describes the Smart Lazy Watchers v2 architecture: a budgeted plan → diff → apply system that keeps file descriptors bounded while preserving immediate activity signals.

---

## Overview

Smart Lazy Watchers v2 uses a **three-tier budget model**:

- **HOT**: active project (up to 20 transcripts watched)
- **WARM**: up to 2 most recently activated projects (up to 10 transcripts each)
- **COLD**: all remaining projects (0 watchers; FSEvents-only activity signals)

**Global limit:** 150 watchers maximum across all tiers. If budget is exceeded, warm projects are reduced first.

When FD exhaustion is detected, v2 enters **degraded mode** and drops to **hot-only** until restart.

---

## Core Components

- **WatcherBudgetCoordinator** (`app/Sources/ContextifyCore/Coordination/WatcherBudgetCoordinator.swift`)
  - Single authority for watcher lifecycle.
  - Maintains LRU activation order (max 3 projects).
  - Computes plan → diff → apply with deterministic ordering.

- **ProjectActivityMonitor** (`app/Sources/ContextifyCore/ProjectActivityMonitor.swift`)
  - FSEvents listener for all transcript roots.
  - Emits activity signals for cold/unwatched transcripts.
  - Optional tail scan for unread approximation.

- **TranscriptOrchestrator** (`app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`)
  - Starts/stops watchers, persists baselines, approximations, and activity timestamps.
  - Performs activation catch-up rehoover (foreground + background).

- **TranscriptTailScanner** (`app/Sources/ContextifyCore/Transcripts/TranscriptTailScanner.swift`)
  - Bounded tail scan (64KB, 50ms) with confidence scoring.

---

## Budgeted Plan → Diff → Apply

### Tier assignment

LRU is updated **only on user activation**. Activity-triggered promotion recomputes are debounced (300ms).

- `LRU[0]` → HOT
- `LRU[1]`, `LRU[2]` → WARM
- everything else → COLD

### Transcript selection

Per project, transcripts are ranked by:

1. `last_modified` (desc)
2. `last_activity_detected_at` (desc)
3. `transcript_id` (lexicographic)

Targets:

- HOT: top 20
- WARM: top 10
- COLD: none

### Apply ordering

- **Stop first** (evictions, demotions, intra-tier drops)
- **Start next** (HOT first, then WARM in LRU order)

**Residency gating:** Newly started watchers have a 20-second residency window to prevent thrashing. Degraded mode bypasses residency gating to shed warm watchers immediately.

---

## Activation Flow

```
User activates project
→ WatcherBudgetCoordinator.activateProject(projectId)
→ Update LRU + tiers
→ Compute plan → diff → apply
→ Foreground catch-up: rehoover pending HOT transcripts
→ Background catch-up: rehoover remaining pending transcripts
```

Activation ordering uses generation tokens to prevent stale activations from winning.

---

## Cold Activity Signals

When a cold/unwatched transcript changes:

1. Set `transcripts.last_activity_detected_at`
2. Set `projects.last_activity_detected_at`
3. Set `pending_rehoover = 1`
4. Emit `ProjectEvent.projectActivityDetected` (debounced 200ms per project)
5. Optional tail scan for `~N` unread approximation

UI shows:

- accurate unread count → number
- medium/high approximation → `~N`
- activity signal only → dot

---

## Baselines + Approximation

Baselines are updated only after successful full ingestion:

- `known_last_entry_ts`
- `known_file_size`

Tail scan runs only if baseline exists and rate-limited (1s per transcript). Low confidence returns no approximation.

---

## Schema

Migration v32 added baseline + activity + approximation fields (current schema is v33):

- `transcripts.known_last_entry_ts`
- `transcripts.known_file_size`
- `transcripts.unread_approx_count`
- `transcripts.unread_approx_confidence`
- `transcripts.unread_approx_updated_at`
- `transcripts.last_activity_detected_at`
- `projects.last_activity_detected_at`

---

## Operational Notes

- Watcher count should remain well under FD limits (typically ≤ 40 in steady state).
- Degraded mode is a safety fallback (hot-only) on FD exhaustion.
- `deactivateAll()` stops all watchers via an orchestrator-level “stop all” hammer.

For operational commands and log filters, see `build/docs/operations/MONITORING.md`.
