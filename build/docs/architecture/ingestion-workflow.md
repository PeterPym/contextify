# Ingestion Workflow (DMG + App Store)

This document describes how transcript files on disk become searchable timeline entries in the database, including FastPath preview/backfill behavior and sandbox differences.

## Glossary

- **Provider**: A transcript source such as `claude.code` or `codex.cli`.
- **Lightweight project**: A filesystem-discovered project used for UI listing (`LightweightDiscoveryService`).
- **DB project**: A row in `projects`, identified by `ActiveProjectContext.id` (UUID).
- **Transcript row**: A row in `transcripts` representing a file, keyed by `transcript.id`.
- **Hoover**: Streaming parser+ingestor (`HooverEngine.hooverTranscript`) that writes `transcript_entries` and updates checkpoints.
- **Preview ingestion**: Bounded ingest intended to make the UI usable quickly (`IngestionMode.preview(entries:)`).
- **Completion ingestion**: Full ingest to EOF (`IngestionMode.complete`).
- **Watcher**: File-change monitor (`TranscriptWatcher`) that triggers incremental re-hoover when a transcript changes.

## Build Variants: The Operational Differences

### DMG build (unsandboxed)

- Direct filesystem access (no security-scoped bookmarks).
- `TranscriptAccessProvider` is typically `nil`.
- Startup initializes the DB components immediately (`AppStateOrchestrator.initializeDatabaseComponents()`).
- Background discovery is disabled in `AppStateOrchestrator.startup()`; discovery relies on the normal non-sandbox runtime environment.

### App Store build (sandboxed)

- Transcript file access is gated by security-scoped bookmarks.
- All file I/O under transcript roots runs inside `TranscriptAccessProvider.withAccess(for:) { root in ... }`.
- `AppStateOrchestrator` defers DB initialization until onboarding completes.
- Background discovery starts after `startup()`:
  - Claude: `SandboxedDirectoryWatcher`
  - Codex: polling timer (nested folder structure)

Constraints for sandbox builds:
- File reads must complete synchronously inside the `withAccess` closure; do not offload file reads to tasks that outlive the scope.

---

# System Overview

## Disk → DB → UI pipeline (ASCII)

```
┌───────────────────────────────────────────────────────────────────────┐
│ UI Layer                                                              │
│ SwiftUI Views → ViewModels → AppStateOrchestrator                      │
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 1) Lightweight Discovery (fast, no DB writes)                          │
│    LightweightDiscoveryService.discoverProjectsLightweight()            │
│    Output: [LightweightProject] (id/root/transcript file URLs)          │
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 2) Metadata sync (projects table only)                                 │
│    TranscriptOrchestrator.updateProjectsMetadataOnly(projects)          │
│    TranscriptOrchestrator.seedDisplayOrderFromDiscoveryIfUnset(projects)│
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 3) Project selection (auto-select most recent, or user selection)      │
│    AppStateOrchestrator.selectProject(id:)                              │
│      → FastPathIngestionCoordinator.ingestProjectJIT(lightweightProject)│
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 4) FastPath ingestion (UI-first preview + bounded completion backfill) │
│    FastPathIngestionCoordinator.runFastPath(projectIds, activeProject)  │
│      - Active project: preview subset + watchers                         │
│      - All remaining: completion queue (no watchers)                     │
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 5) Core ingestion                                                      │
│    TranscriptOrchestrator.ingestTranscript(transcriptId, mode, ...)     │
│      → discoverTranscript(...) → doDiscoverTranscript()                 │
│          - preflight validation + cache                                 │
│          - transcript upsert                                            │
│          - hoover (parse + write entries + checkpoint)                  │
│          - optional watcher start (startWatching)                       │
└───────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│ 6) Real-time updates                                                   │
│    TranscriptWatcher watches active files and triggers incremental      │
│    re-hoover on changes.                                                │
└───────────────────────────────────────────────────────────────────────┘

Notification channel:
- TranscriptOrchestrator posts Notification("TranscriptUpdated") with projectId to drive UI refresh.
```

---

# Stage-by-stage behavior

## Stage A — Startup, onboarding, discovery

### DMG startup

```
AppStateOrchestrator.init()
  ├─ initializeDatabaseComponents()
  │    ├─ TranscriptOrchestrator(dbManager:)
  │    └─ FastPathIngestionCoordinator(orchestrator:)
  └─ startup()
       ├─ discoverProjectsLightweight()
       ├─ updateProjectsMetadataOnly()
       ├─ state = .idle(projects)
       └─ auto-select most recent → selectProject(id:)
```

### App Store startup

```
AppStateOrchestrator.init()
  ├─ (onboarding incomplete) orchestrator/fastPath are nil
  └─ onboarding flow creates/configures TranscriptAccessProvider
       ▼
configureAccessProvider(provider)
       ▼
completeOnboardingInitialization()
  ├─ initializeDatabaseComponents()
  └─ (async) fastPath.resumePendingCompletions()
       ▼
startup()
  ├─ discoverProjectsLightweight()
  ├─ updateProjectsMetadataOnly()
  ├─ state = .idle(projects)
  ├─ auto-select most recent → selectProject(id:)
  └─ start background discovery (App Store only)
       - SandboxedDirectoryWatcher (Claude)
       - Codex poll timer
```

## Stage B — Project selection and JIT ingest

Project selection starts from a lightweight project ID, but ingestion and queries use the DB project UUID.

```
FastPathIngestionCoordinator.ingestProjectJIT(lightweightProject)
  ├─ TranscriptOrchestrator.getOrCreateProject(name, rootPath) → dbProjectId
  ├─ (primer) TranscriptOrchestrator.registerPrimer(projectId, target)
  ├─ TranscriptOrchestrator.upsertTranscripts(projectId, discoveredFiles)
  └─ runFastPath(projectIds:[dbProjectId], activeProjectId: dbProjectId)
```

## Stage C — FastPath preview vs completion

FastPath optimizes for “UI usable fast” without unbounded background work.

### Active project preview

- FastPath selects a prioritized subset of transcripts for preview ingestion.
- Preview ingestion calls:
  - `TranscriptOrchestrator.ingestTranscript(mode: .preview(entries: ...), startWatching: true)`
- Preview starts watchers only for that active subset.
- A “notify once per project” token gates UI notifications to one successful preview completion.

### Completion backfill (all remaining transcripts)

- FastPath enqueues all remaining transcripts immediately into a completion queue.
- Completion runs in a bounded worker pool:
  - `TranscriptOrchestrator.ingestTranscript(mode: .complete, startWatching: false)`
- Cancellation handling:
  - Workers check pause/shutdown before dequeue.
  - `CancellationError` requeues at the front to avoid dropping work.

## Stage D — Core ingestion (locks → discovery → hoover → watchers)

```
TranscriptOrchestrator.ingestTranscript(transcriptId, mode, notifyUI, startWatching)
  ├─ acquireIngestionLock(transcriptId)
  ├─ file exists?
  │    - if missing: status=unavailable, ingest_state=complete, last_error
  ├─ discoverTranscript(projectId, fileURL, provider, sessionId, startWatching, ingestLimit)
  │    └─ discoverTranscriptInternal(...)
  │         ├─ (App Store) accessProvider.withAccess(for: provider) { ... }
  │         └─ doDiscoverTranscript(...)
  │              - preflight validate + cache
  │              - transcriptRepo.upsert(...)
  │              - hooverEngine.hooverTranscript(..., limit: ingestLimit)
  │              - if startWatching: TranscriptWatcher.watch(...)
  ├─ releaseIngestionLock(transcriptId)
  └─ if notifyUI: post Notification("TranscriptUpdated", projectId)
```

## Stage E — Startup resumption of partials

At DB initialization, FastPath resumes completion work based on persisted transcript state:

```
FastPathIngestionCoordinator.resumePendingCompletions()
  ├─ TranscriptOrchestrator.getPartialTranscripts()
  │    SELECT transcripts WHERE ingest_state='partial' AND status='active'
  └─ enqueueCompletion(transcriptId) for each
```

Permanent failure behavior:
- Permanent/non-retryable completion failures mark the transcript as terminally unavailable:
  - `status='unavailable'` and `ingest_state='complete'`
- This prevents repeated re-enqueueing across app restarts.

---

# Decision Knobs

These are the policy decisions this pipeline exposes.

## 1) Pause/resume semantics

Current behavior in FastPath:
- `pauseBackfill()` pauses workers and stops scanning additional projects.
- `runFastPath()` auto-resumes paused backfill when invoked again.

Alternative behavior:
- Pause is sticky until an explicit `resumeBackfill()` call.

## 2) Permanent failure policy

Current behavior:
- Common permanent failures (file missing / permission denied) persist as `status='unavailable'` and are removed from the “partial resumption” set.

Alternative behavior:
- Cooldown-based retries (persist retry-after timestamps).
- Retry on content change only (suppress retries until mtime changes).

## 3) Watcher scope

Current behavior:
- Watchers are created only for the active project’s preview subset.

Alternative behavior:
- Background watchers (bounded by an LRU or per-project cap) to keep inactive projects live without FD pressure.

---

# Key Code Anchors

- `app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift`
- `app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`
- `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`
- `app/Sources/ContextifyCore/Database/HooverEngine.swift`
