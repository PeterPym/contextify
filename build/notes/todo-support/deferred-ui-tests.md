---
title: Deferred UI Tests Registry
type: plan
date: 2025-11-24
status: active
description: Catalog of UI behavior we can’t yet cover with SPM tests; each entry records context, verification steps, and supporting artifacts (logs, DB queries).
---

## 1. Timeline summary queueing needs a viewport test

**Problem:** After switching to `webviewer` (see `/private/tmp/transcript-queue-monitor-20251124-110308.log`), the visible entries (IDs `f9d9b1c7`, `a796c993`, `d6b8470e`, etc.) remain in “hourglass” state even though the viewport never scrolls. Queueing only runs once the fallback timer fires (`[SUMM-VIEWPORT-FALLBACK]` around `11:03:11`, `[SUMM-QUEUE-NEEDS-SUMMARY-COUNT] = 17`), and then pruning immediately removes entries that are no longer in `lastVisibleIDs`. This leaves the topmost messages unsummarized.

**Verification steps:**
1. Launch the app, switch to the `webviewer` project with `Contextify`.
2. Capture logs with `scripts/logging/monitor-viewport-queueing.sh` (or similar) while *not* manually scrolling.
3. Look for these log patterns within ~1s of the switch:
   - `[SUMM-LOAD-DEFER] Deferring queueing to viewport tracking`
   - `[SUMM-VIEWPORT-FALLBACK] ... firing in 500ms`
   - `[SUMM-PRUNE-*]` showing queue depth and removed items
   - `[SUMM-QUEUE-*]` showing visible IDs being re-queued (should execute even without `isUserScrollActive`)
4. Confirm the fallback path fires only once (not repeatedly) and that queueing runs even without a scroll event.

**Supporting DB queries:**
- List visible entries and re-check their summary/cache state:
  ```sql
  SELECT id, content, window_sha256 FROM transcript_entries
  WHERE project_id = '-Users-rob-code-projects-webviewer'
    AND timestamp BETWEEN strftime('%s','2025-11-01T06:48:00Z') AND strftime('%s','2025-11-01T06:50:30Z');
  ```
- Determine which entries still lack cached summaries:
  ```sql
  SELECT entry_id FROM timeline_cache WHERE entry_id IN (<visible IDs>);
  ```
- Check queue flags:
  ```sql
  SELECT entry_id, is_queued FROM transcript_entries WHERE entry_id IN (<visible IDs>);
  ```

**Goal:** Build an automated UI test (or instrumentation) that ensures the viewport-triggered queue path executes without requiring user scrolls and that entries in the initial viewport reach the LLM queue without being pruned away first. Recording the log/DB queries above will help validate this behavior before converting to a fully automated regression test.

## 2. Empty-project spinner avoidance needs UI coverage

**Problem:** We added logic so `ConversationMonitor` skips `.loading` when a project has zero entries, but the UI test harness can't currently reproduce the spinner branch to verify the empty state renders immediately. SwiftUI automation is fragile (TableView/timeline flicker, placeholder states), so there isn’t a reliable `swift test` that exercises the spinner vs empty-state branch.

**Verification hints:**
1. Manually switch to a project known to have no entries (e.g., a fresh repo) and confirm the HUD shows “No Activity Yet” instantly instead of the spinner.
2. Capture logs (`[TIMELINE-LOAD]`, `[TIMELINE-HYDRATE-SKIP]`, and `[TIMELINE-LOAD] primer complete` showing phase transitions) to prove the monitor reported zero entries.
3. Use SQL to confirm the project has no `timeline_entries` but does exist (e.g., `SELECT COUNT(*) FROM transcript_entries WHERE project_id = '<id>'` returns 0).

**Goal:** Add the empty-state UI test once the SwiftUI automation stabilizes (or move this check into a lightweight expectation harness) so we can guard the spinner-free behavior. Keep this entry in the deferred doc until the automated test is written.
