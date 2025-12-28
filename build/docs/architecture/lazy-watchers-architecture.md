# Lazy Watchers Implementation: Architecture & Operational Guide

**Status:** Complete (committed to feat/lazy-watchers, integrated with monitoring stack)
**Last Updated:** 2025-12-27
**Target Audience:** Developers maintaining the monitoring architecture

This document explains how file watchers have evolved with the lazy watchers feature, covering architecture changes, promotion mechanisms, and operational patterns.

---

## OLD ARCHITECTURE: All Watchers All The Time

### Overview

Prior to lazy watchers, Contextify maintained DispatchSource file watchers for **every transcript in every project**:

```
Startup → Discover all projects → Hoover all transcripts → Start watchers for all → Monitor all
           =====================================================================================================
           Result: ~3,600 watchers, exhausting file descriptors (errno=24 EMFILE)
```

### Resource Impact

- **~1,676 Claude transcripts** + **202 Codex** + **~1,800 agent sidechains** = **~3,678 open file descriptors**
- Each watcher: 1 FD + DispatchSource overhead
- macOS default ulimit: 256-1024 FDs per process
- **Result:** 1,638 agent files failed to get watchers (55% data loss)

### Architecture Diagram (OLD)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         STARTUP (EAGER WATCHERS)                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ProjectActivityMonitor.startGlobalMonitoring()                         │
│  ├─ ensureProjectWatcher(projectId) for ALL projects                    │
│  └─ discoverTranscripts(startWatching: true) for ALL transcripts        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │ Project A │   │ Project B │   │ Project C │  ... (20+ projects)
            │ 50 files  │   │ 120 files │   │ 80 files  │
            │ 50 FDs    │   │ 120 FDs   │   │ 80 FDs    │
            └───────────┘   └───────────┘   └───────────┘
                    │               │               │
                    ▼               ▼               ▼
            ┌─────────────────────────────────────────────────────────────┐
            │           TranscriptWatcher.watch() for EVERY file          │
            │           open(fileURL.path, O_EVTONLY) × 3,678             │
            │                                                             │
            │           → errno=24 (EMFILE) after ~1,500 files ←          │
            │           → 1,638 agent files FAIL to get watchers          │
            └─────────────────────────────────────────────────────────────┘
```

---

## NEW ARCHITECTURE: Two-Tier Monitoring

### Overview

Lazy watchers implement a **two-tier strategy**: active project gets real-time per-file monitoring, inactive projects rely on FSEvents-driven detection with on-demand rehoovering.

### Architecture Diagram (NEW)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      STARTUP (LAZY WATCHERS)                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ProjectActivityMonitor + MonitoringCoordinator                         │
│  ├─ FSEvents stream monitors ALL directories (0 FDs, 500ms latency)     │
│  ├─ MonitoringCoordinator tracks activeProjectId                        │
│  └─ Only active project gets per-file watchers                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
                    ▼                               ▼
    ┌───────────────────────────┐   ┌───────────────────────────────────┐
    │     ACTIVE PROJECT        │   │      INACTIVE PROJECTS            │
    │    (User's current view)  │   │    (Everything else)              │
    ├───────────────────────────┤   ├───────────────────────────────────┤
    │                           │   │                                   │
    │  ┌─────────────────────┐  │   │  ┌─────────────────────────────┐  │
    │  │ MonitoringCoordinator│  │   │  │ FSEvents-only monitoring    │  │
    │  │ orchestrates lifecycle│  │   │  │ (no per-file watchers)     │  │
    │  └─────────────────────┘  │   │  └─────────────────────────────┘  │
    │           │               │   │              │                    │
    │           ▼               │   │              ▼                    │
    │  ┌─────────────────────┐  │   │  ┌─────────────────────────────┐  │
    │  │ TranscriptWatcher    │  │   │  │ pending_rehoover flag       │  │
    │  │ DispatchSource × N   │  │   │  │ set in database             │  │
    │  │ (N = transcripts)    │  │   │  │ (deferred ingestion)        │  │
    │  └─────────────────────┘  │   │  └─────────────────────────────┘  │
    │           │               │   │              │                    │
    │           ▼               │   │              ▼                    │
    │  ┌─────────────────────┐  │   │  ┌─────────────────────────────┐  │
    │  │ <150ms latency      │  │   │  │ Hoover on next activation   │  │
    │  │ Real-time updates   │  │   │  │ via mtime comparison        │  │
    │  └─────────────────────┘  │   │  └─────────────────────────────┘  │
    │                           │   │                                   │
    │  FDs used: ~50-100        │   │  FDs used: 0                      │
    └───────────────────────────┘   └───────────────────────────────────┘

                        TOTAL FDs: <100 (down from ~3,600)
```

---

## PROJECT SWITCH FLOW

When user switches from Project A to Project B:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  USER ACTION: Click on Project B in sidebar                             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Step 1: MonitoringCoordinator.activateProject("B")                     │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ • Start watchers for Project B immediately                       │    │
│  │ • Set activeProjectId = "B"                                      │    │
│  │ • Set watchersReadyProjectId = "B"                               │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Step 2: Schedule teardown for Project A (5-second hysteresis)          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   t=0s                    t=5s                                          │
│    │                       │                                            │
│    ├───────────────────────┤                                            │
│    │   CANCELLABLE WINDOW  │                                            │
│    │                       │                                            │
│    │  If user switches     │  If 5s passes:                             │
│    │  back to A:           │  executeTeardown(A)                        │
│    │  • Cancel teardown    │  • stopAllWatchers(A)                      │
│    │  • A keeps watchers   │  • A has 0 FDs now                         │
│    │                       │                                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Step 3: Background - rehooverDirtyTranscripts("B")                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  For each transcript in Project B:                                      │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Check 1: pending_rehoover flag set?                             │    │
│  │           (FSEvents detected change while B was inactive)        │    │
│  │                                                                  │    │
│  │  Check 2: filesystem mtime > cached mtimeMs?                     │    │
│  │           (Offline changes while app was closed)                 │    │
│  │                                                                  │    │
│  │  If EITHER true → Hoover transcript, update mtimeMs, clear flag  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  RESULT:                                                                │
│  • Project B: Full real-time monitoring (<150ms latency)                │
│  • Project A: Will catch up on next activation                          │
│  • FD count: Only B's transcripts consuming FDs                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## PROMOTION MECHANISM: How Old Conversations Get Noticed

### The Problem

When a user switches away from a project, watchers are torn down to save FDs. If someone resumes an old conversation hours later, how do we detect it?

### Three-Tier Detection System

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    TIER 1: FSEvents (Online Changes)                    │
│                    ─────────────────────────────────                    │
│                                                                         │
│  While app is running, FSEvents monitors ALL directories               │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  File changes on disk (inactive project)                          │   │
│  │            │                                                      │   │
│  │            ▼                                                      │   │
│  │  FSEvents detects change (500ms latency)                          │   │
│  │            │                                                      │   │
│  │            ▼                                                      │   │
│  │  ProjectActivityMonitor.handleFileSystemChange()                  │   │
│  │            │                                                      │   │
│  │            ▼                                                      │   │
│  │  Is this the active project? ──NO──▶ markPendingRehoover()        │   │
│  │            │                         (set flag in DB)             │   │
│  │           YES                              │                      │   │
│  │            │                               ▼                      │   │
│  │            ▼                        Badge updates                 │   │
│  │  DispatchSource handles it          ("2 new" appears)             │   │
│  │  (already watching)                                               │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                 TIER 2: Mtime Comparison (Project Activation)           │
│                 ─────────────────────────────────────────────           │
│                                                                         │
│  When user switches to a project, we check for missed changes          │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  User clicks Project X                                            │   │
│  │            │                                                      │   │
│  │            ▼                                                      │   │
│  │  MonitoringCoordinator.activateProject("X")                       │   │
│  │            │                                                      │   │
│  │            ├──────────────────────────────────────────────────┐   │   │
│  │            │                                                  │   │   │
│  │            ▼                                                  ▼   │   │
│  │  Start per-file watchers              rehooverDirtyTranscripts()  │   │
│  │  for Project X                                │                   │   │
│  │                                               ▼                   │   │
│  │                              ┌────────────────────────────────┐   │   │
│  │                              │  For each transcript:          │   │   │
│  │                              │                                │   │   │
│  │                              │  filesystem_mtime = stat(file) │   │   │
│  │                              │  cached_mtime = transcript.    │   │   │
│  │                              │                 mtimeMs        │   │   │
│  │                              │                                │   │   │
│  │                              │  if pending_rehoover = 1       │   │   │
│  │                              │     OR filesystem > cached:    │   │   │
│  │                              │                                │   │   │
│  │                              │     → HOOVER transcript        │   │   │
│  │                              │     → Update mtimeMs           │   │   │
│  │                              │     → Clear pending flag       │   │   │
│  │                              └────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                 TIER 3: Offline Change Detection                        │
│                 ────────────────────────────────                        │
│                                                                         │
│  Catches changes made while app was closed                             │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                                                                   │   │
│  │  APP CLOSED ────────────────────────────────────────▶ APP OPENS   │   │
│  │       │                                                   │       │   │
│  │       ▼                                                   ▼       │   │
│  │  Claude Code writes                              User activates   │   │
│  │  to transcript                                   that project     │   │
│  │       │                                                   │       │   │
│  │       ▼                                                   ▼       │   │
│  │  File mtime updated                        rehooverDirtyTranscripts│   │
│  │  (no FSEvents fired -                              │              │   │
│  │   app wasn't running)                              ▼              │   │
│  │                                          filesystem > cached?     │   │
│  │                                                   │               │   │
│  │                                                  YES              │   │
│  │                                                   │               │   │
│  │                                                   ▼               │   │
│  │                                          HOOVER new content       │   │
│  │                                                                   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  Key insight: pending_rehoover flag wasn't set (app was closed),       │
│  but mtime comparison catches the change anyway.                        │
└─────────────────────────────────────────────────────────────────────────┘
```

### Database Schema for Promotion

```
┌─────────────────────────────────────────────────────────────────────────┐
│  transcripts table (Migration v31)                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────┬────────────────────────────────────────────────┐ │
│  │ Column            │ Purpose                                        │ │
│  ├───────────────────┼────────────────────────────────────────────────┤ │
│  │ pending_rehoover  │ Flag set by FSEvents for inactive projects    │ │
│  │ (INTEGER, 0/1)    │ Indicates "needs catch-up on activation"      │ │
│  ├───────────────────┼────────────────────────────────────────────────┤ │
│  │ mtimeMs           │ Last known file modification time (ms)        │ │
│  │ (INTEGER)         │ Compared against filesystem on activation     │ │
│  └───────────────────┴────────────────────────────────────────────────┘ │
│                                                                         │
│  State transitions:                                                     │
│                                                                         │
│  ┌─────────────┐    FSEvents fires     ┌─────────────────────┐         │
│  │ Clean       │ ────────────────────▶ │ pending_rehoover=1  │         │
│  │ rehoover=0  │    (inactive proj)    │ mtimeMs unchanged   │         │
│  └─────────────┘                       └─────────────────────┘         │
│        ▲                                         │                      │
│        │                                         │                      │
│        │         User activates project          │                      │
│        │         rehooverDirtyTranscripts()      │                      │
│        │                    │                    │                      │
│        └────────────────────┴────────────────────┘                      │
│              Hoover, update mtimeMs, clear flag                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## HYSTERESIS: Why 5 Seconds?

```
┌─────────────────────────────────────────────────────────────────────────┐
│  WITHOUT HYSTERESIS - Rapid switching causes watcher churn              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  User clicks: A → B → A (within 100ms)                                  │
│                                                                         │
│  t=0ms     t=50ms      t=100ms                                          │
│    │         │            │                                             │
│    ▼         ▼            ▼                                             │
│  Stop A   Start B      Stop B                                           │
│  watchers watchers     watchers                                         │
│           Stop A       Start A                                          │
│           watchers     watchers                                         │
│                                                                         │
│  = 4 filesystem operations, FD churn, potential race conditions         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  WITH 5-SECOND HYSTERESIS - Teardowns are deferred and cancellable      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  User clicks: A → B → A (within 100ms)                                  │
│                                                                         │
│  t=0ms              t=50ms              t=100ms                         │
│    │                  │                    │                            │
│    ▼                  ▼                    ▼                            │
│  Activate B        (B already         Activate A                        │
│  Schedule A        active)            CANCEL scheduled                  │
│  teardown                             teardown for A                    │
│  in 5s                                (A's watchers still               │
│    │                                   running!)                        │
│    │                                                                    │
│    │                                                                    │
│    ▼                                                                    │
│  5 seconds pass with no activity?                                       │
│  THEN execute teardown                                                  │
│                                                                         │
│  Result: A's watchers never stopped! Zero thrashing.                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## FSEvents vs DispatchSource: Decision Matrix

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        MONITORING MECHANISMS                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────┐   │
│  │      DispatchSource         │  │         FSEvents                │   │
│  │     (Active Project)        │  │        (All Projects)           │   │
│  ├─────────────────────────────┤  ├─────────────────────────────────┤   │
│  │ • One FD per file           │  │ • Zero FD cost                  │   │
│  │ • ~100-150ms latency        │  │ • ~500ms latency (coalescing)   │   │
│  │ • Per-file granularity      │  │ • Directory-level monitoring    │   │
│  │ • Immediate write detection │  │ • Catches all changes           │   │
│  │ • Only while app running    │  │ • Only while app running        │   │
│  └─────────────────────────────┘  └─────────────────────────────────┘   │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                         DECISION MATRIX                                 │
├───────────────────────┬───────────────────┬─────────────────────────────┤
│ Scenario              │ Mechanism         │ Why                         │
├───────────────────────┼───────────────────┼─────────────────────────────┤
│ Active project,       │ DispatchSource    │ Need <200ms for responsive  │
│ live editing          │                   │ real-time updates           │
├───────────────────────┼───────────────────┼─────────────────────────────┤
│ Inactive project,     │ FSEvents          │ Mark dirty, defer ingestion │
│ file changes          │                   │ to save FDs                 │
├───────────────────────┼───────────────────┼─────────────────────────────┤
│ Offline changes       │ mtime comparison  │ FSEvents didn't fire;       │
│ (app was closed)      │ on activation     │ mtime catches the gap       │
├───────────────────────┼───────────────────┼─────────────────────────────┤
│ New transcript        │ FSEvents          │ Triggers discovery flow     │
│ appears               │                   │ regardless of project state │
└───────────────────────┴───────────────────┴─────────────────────────────┘
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## RESOURCE COMPARISON

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          BEFORE LAZY WATCHERS                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  User with typical usage:                                               │
│  • 20 projects                                                          │
│  • ~1,676 Claude transcripts                                            │
│  • ~202 Codex transcripts                                               │
│  • ~1,800 agent sidechains                                              │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  File descriptors:  ~3,678 (one per watcher)                    │    │
│  │  macOS limit:       ~1,000 (typical)                            │    │
│  │  Result:            errno=24 EMFILE for 1,638 files             │    │
│  │  Data loss:         55% of agent sidechains not monitored       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                          AFTER LAZY WATCHERS                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Same user, viewing one project with ~50 transcripts:                   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Active project FDs:    ~50 (only what user is viewing)         │    │
│  │  Inactive projects:     0 FDs (FSEvents-driven only)            │    │
│  │  Total FDs:             <100                                    │    │
│  │  Result:                No errno=24, all files can be watched   │    │
│  │  Improvement:           93% reduction in FD usage               │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│        ████████████████████████████████████████  3,678 FDs (before)     │
│        ███                                       ~100 FDs (after)       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## KEY COMPONENTS SUMMARY

```
┌─────────────────────────────────────────────────────────────────────────┐
│  MonitoringCoordinator (NEW)                                            │
│  app/Sources/ContextifyCore/Coordination/MonitoringCoordinator.swift    │
├─────────────────────────────────────────────────────────────────────────┤
│  • Central state machine for watcher lifecycle                          │
│  • Tracks activeProjectId and watchersReadyProjectId                    │
│  • Manages 5-second hysteresis for teardowns                            │
│  • Coordinates with ProjectActivityMonitor and TranscriptOrchestrator   │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  ProjectActivityMonitor (ENHANCED)                                      │
│  app/Sources/ContextifyCore/Monitoring/ProjectActivityMonitor.swift     │
├─────────────────────────────────────────────────────────────────────────┤
│  • FSEvents stream for global directory monitoring                      │
│  • Now queries MonitoringCoordinator.isActiveProjectWithWatchers()      │
│  • Routes events: active → let watcher handle, inactive → mark dirty    │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  TranscriptOrchestrator (EXTENDED)                                      │
│  app/Sources/ContextifyCore/Transcripts/TranscriptOrchestrator.swift    │
├─────────────────────────────────────────────────────────────────────────┤
│  • markPendingRehoover() - flag transcript for catch-up                 │
│  • rehooverDirtyTranscripts() - catch up on project activation          │
│  • stopAllWatchers(forProjectId:) - teardown on project deactivation    │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  TranscriptWatcher (UNCHANGED)                                          │
│  app/Sources/ContextifyCore/Transcripts/TranscriptWatcher.swift         │
├─────────────────────────────────────────────────────────────────────────┤
│  • Still manages per-file DispatchSource watchers                       │
│  • Now only created for active project's transcripts                    │
│  • Same API: watch(), stopWatching(), stopAll()                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## LOGGING TAGS FOR DIAGNOSTICS

```bash
# All lazy watcher activity
log show --predicate 'subsystem == "dev.contextify" AND message CONTAINS "LAZY-WATCHER"' --info --last 1h

# FSEvents routing decisions
log show --predicate 'subsystem == "dev.contextify" AND message CONTAINS "FSEVENTS"' --info --last 1h

# Watcher lifecycle
log show --predicate 'subsystem == "dev.contextify" AND message CONTAINS "WATCHER"' --info --last 1h
```

---

## SUMMARY

Lazy watchers transform Contextify from "monitor everything always" to "monitor what the user is looking at now, defer the rest":

| Aspect | Before | After |
|--------|--------|-------|
| Active project | Per-file watchers | Per-file watchers (same) |
| Inactive projects | Per-file watchers (wasteful) | FSEvents + deferred hoovering |
| FD usage | ~3,678 | <100 |
| Offline changes | Missed until manual refresh | Caught via mtime comparison |
| Latency (active) | <150ms | <150ms (same) |
| Latency (inactive→active) | N/A | ~500ms catch-up on switch |

**The promotion mechanism ensures old conversations always catch up when resumed:**
1. **Online changes** → FSEvents sets `pending_rehoover` flag → hoovered on activation
2. **Offline changes** → mtime comparison catches them → hoovered on activation
3. **Result** → User always sees current state when they switch to any project
