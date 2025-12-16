---
todo_id: PROJECT-SWITCH-TIMELINE-PREVIEW-PREFETCH
title: Project Switch Timeline Preview Prefetch
type: spec
date: 2025-12-14
status: active
description: Prefetch a small, cancelable preview subset for likely-next projects so project switching avoids long empty timeline windows without creating watchers.
---

# Project Switch Timeline Preview Prefetch

## Problem Statement

When a user switches from the active project to another project that has transcripts on disk, the timeline can appear empty for a long time. Today, FastPath preview ingestion is limited to the active project and inactive projects are typically completion-only. On fresh databases, this means inactive projects can remain `ingest_state='partial'` with 0 entries until completion backfill eventually runs.

This is a UX failure mode because “empty timeline” visually reads as “no data exists”, when the real state is “not ingested yet”.

## Goals

- Project switching shows non-empty, displayable timeline content quickly when transcripts exist.
- Prefetch does not create watchers for non-active projects (avoid FD growth and watcher recovery loops).
- Prefetch work is bounded and cancelable; it does not contend with the active project’s ingestion.
- Prefetch does not add meaningful startup latency; it runs after the UI is already usable.

## Non-Goals

- Making every project fully ingested before the user interacts.
- Starting watchers for all projects.
- Adding a periodic “keep trying forever” loop (handled by separate resilience work if needed).

## Proposed Solution

Introduce a “non-active project preview prefetch” stage that runs after startup/project list becomes visible and/or after the active project reaches an initial usable state.

### Key behaviors

1. **Select a bounded prefetch set**
   - Candidate selection order (proposed):
     - most recently viewed projects (persisted),
     - then most recently active (discovery activity ordering),
     - then projects with unread/attention signals (if available),
     - cap to `K` projects per run (e.g., 3–8).

2. **Ingest a lightweight preview subset per project**
   - For each selected project:
     - pick a small set of transcripts (similar to FastPath prioritization),
     - ingest with `IngestionMode.preview(entries: previewLimit)` and `startWatching: false`,
     - stop once at least `M` displayable entries exist for the project or once `T` seconds elapse.

3. **Scheduling and cancellation**
   - Prefetch tasks run at `.background`/`.utility` priority and are cancelable.
   - On project switch:
     - active project preview continues,
     - non-active prefetch pauses/cancels and re-schedules after the switch settles.

4. **UI state: “loading” vs “empty”**
   - UI distinguishes truly empty vs “not ingested yet”:
     - show a lightweight loading state while preview prefetch is pending for that project,
     - avoid showing a blank timeline with no indicator when transcripts exist but entries do not.

## Architecture & Components

### Where this likely lives

- Scheduling: `app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift`
  - Add a post-startup/background prefetch stage that uses the DB project IDs.
- Ingestion API: `app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`
  - Add a method that previews a bounded subset for a project with `startWatching: false`.
- Ingestion core: `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`
  - Existing `ingestTranscript(... startWatching:)` supports the needed split.

### Watcher safety rule (hard constraint)

Non-active prefetch must not call watcher start paths:
- use `startWatching: false` on all prefetch preview ingests,
- do not call `startWatchingTranscript(...)` for prefetch.

## Test Requirements

### Unit tests

- Prefetch selection ordering: given projects with known recency/activity, verify chosen set is bounded and stable.
- Watcher safety: prefetch preview does not increase `orchestrator.watcherCount`.
- Cancellation semantics: switching projects cancels/deprioritizes prefetch tasks and active project work remains prioritized.

### E2E tests

- Update or add a QA test that switches between two projects where one is initially not ingested and asserts:
  - timeline shows a loading state immediately,
  - non-empty content appears within a bounded time window,
  - watcher count remains bounded (if surfaced in logs/diagnostics).

## Rollout Considerations

- Feature flag (optional): guard prefetch with a config value for tuning (`K`, `M`, time budget).
- Performance monitoring: log prefetch duration and outcomes (entries created per project).

## Open Questions

- What is the authoritative “recently viewed” signal: DB table, UserDefaults, or an existing project visits repo?
- What is the best trigger point:
  - after `.idle(projects)` is set,
  - after active project reaches `primerTargetEntries`,
  - or after a short idle debounce?
- Should prefetch run only for projects the user has previously opened, or also for newly discovered projects?
