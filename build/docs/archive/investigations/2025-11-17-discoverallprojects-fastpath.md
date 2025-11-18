# Investigation: `discoverAllProjects` Full-Scan Optimization (P1 Support)

**Date:** 2025-11-17  
**Owner:** feat/dmg-build-hang-investigation  
**Related Priority:** `#P1-DISCOVERY` (build/notes/TODOS.md)  
**Source Logs:**  
- DMG build: `/private/tmp/transcript-queue-monitor-20251117-193137-dmg-build.log`  
- App Store build (baseline): `/private/tmp/transcript-queue-monitor-20251117-192937-app-store-build.log`

---

## Problem Statement

`discoverAllProjects()` still performs a synchronous, blocking walk of the entire Codex transcript tree (`~/.codex/sessions/YYYY/MM/DD/**/*.jsonl`) during phase 3 of startup. On DMG builds this happens while the welcome modal is visible, so the UI appears frozen for 60 s+ whenever Codex contains more than a handful of sessions. App Store builds avoid the stall because the sandboxed path exits early, so the hang only affects development builds—which is exactly where we need rapid iteration.

Quick discovery (phase 2) is now fast (<100 ms) thanks to streaming the first `session_meta` line and short-circuiting per-project scans, but the full scan still:

1. Enumerates every file and directory under `.codex/sessions` before emitting progress.
2. Re-reads up to 64 KB from each transcript to recover `payload.cwd`.
3. Competes with the ongoing Claude hoover (hundreds of transcripts) for disk I/O.
4. Blocks the main actor from completing onboarding tasks until the 60 s traversal finishes.

This doc captures the open work needed to elevate the full scan to the same standard as the quick path.

---

## Control Flow Review

1. `ProjectSwitcherState.start()` kicks off `ProjectActivityMonitor.startGlobalMonitoring()` (Contextify/Contextify/ProjectSwitcherState.swift:33-152).
2. On DMG builds, `ProjectActivityMonitor` calls `ProjectDiscoveryService.discoverAllProjects()` immediately (app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift:232-496). App Store builds skip out via `#if APPSTORE_BUILD`.
3. Inside `discoverAllProjects()`:
   - Claude pass completes quickly by scanning `~/.claude/projects`.
   - Codex pass walks `.codex/sessions` by enumerating every year/month/day, collecting all `.jsonl` files, then reopening each file to parse a `cwd` so it can be grouped by repo.
4. Only after the scan finishes do we emit `[DISC-SCAN-ROOT-DONE]` and allow the welcome modal to advance.

The DMG log linked above shows Codex discovery running for **66 s** (`[DISC-SCAN-ROOT] … -> [DISC-SCAN-ROOT-DONE]`), while the App Store log contains no such entries because the sandbox never starts the scan.

---

## Findings

- Codex storage is global, so we cannot infer the owning project from the directory structure alone; we must read some metadata. Currently we re-open each transcript and parse 64 KB of JSON for every run.
- The enumerator dumps the entire tree into memory before any work is done, so users see no log progress for the first minute.
- `discoverAllProjects()` runs on the main actor during onboarding, so the UI is unresponsive until the Codex traversal finishes.
- Because Claude ingestion is also in-flight, the disks spend a significant amount of time thrashing between hoover writes (`~/.claude/projects/...`) and Codex reads (`~/.codex/sessions/...`).

---

## Proposed Improvements (P1 Scope)

The following items compose the `#P1-DISCOVERY` work:

1. **Stage the Codex scan in the background.** Kick off the Codex portion after Claude quick discovery finishes, but run it on a detached task with progress notifications so the welcome modal/UI can continue while discovery completes. Abort or defer if the user selects a project before the scan is done.
2. **Read lightweight metadata instead of transcript bodies.** Codex creates a sibling `session.json` next to each `rollout-*.jsonl` that includes `project_root`/`cwd`. Reading that file (a few hundred bytes) is dramatically cheaper than reopening the entire transcript. Add fallbacks when the metadata is missing.
3. **Newest-first traversal with early exit.** Start from the newest YYYY/MM/DD directories and walk backward until every known project has a freshest Codex timestamp or a 5 s budget expires. Persist the last successful day stamp so subsequent launches only need to scan new folders.
4. **Incremental resumption.** Cache per-project Codex mtimes (similar to the quick discovery baseline) so future runs only inspect directories newer than the cached time.
5. **Progress & telemetry logging.** Emit `[DISC-CODEX-PROGRESS processed=X, projects=Y, elapsed=Z]` every N transcripts so the welcome modal and log stream show forward motion. Include cancellation reasons (budget exceeded, user switched project, etc.).

Implementing these steps should drop the phase 3 Codex scan from 60 s to sub-second in the common case and stop blocking the UI during onboarding.

---

## Validation Strategy

1. Instrument new logs at INFO level so `log stream --predicate 'subsystem == "dev.contextify"'` shows:
   - Start/budget information
   - Periodic progress updates
   - Early exits (budget, cancellation, errors)
2. Compare DMG vs App Store startup again using `scripts/xc.sh dr` / `bash scripts/xc.sh --dist=appstore Debug cleanrun`.
3. Capture a before/after log slice and attach it to the TODO entry once the P1 work lands.

---

## Appendix: Quick Discovery Recap

The fast path (`quickDiscoverNewest()`) already:
- Streams the first `session_meta` line instead of sampling 64 KB chunks.
- Scans directories newest-first with a strict 5 s budget.
- Short-circuits after the newest transcript per project.

These improvements removed the 66 s hang from phase 2. The open work now is to apply the same principles to the full `discoverAllProjects()` scan so DMG startup remains smooth even after onboarding completes.
