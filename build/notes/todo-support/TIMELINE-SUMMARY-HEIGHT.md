---
todo_id: P3-TIMELINE-SUMMARY-HEIGHT
title: Timeline Row Height Regression Coverage
type: plan
date: 2025-11-24
status: active
description: Capture the current height-control behavior for timeline summary rows and add regression tests so we can detect layout regressions if the geometry reader logic changes.
---

## Goal
Document how the current log/capping logic works (max height per entry, 2-line limit for pending summaries, and the 28pt headroom) and define a regression test that: 
1. Renders a timeline entry with a tall summary,
2. Forces a shorter replacement (e.g., simulated summary update),
3. Verifies `summaryFrameMinHeight` is still >= previous height minus the 28pt delta, and
4. Confirms `[SUMMARY-HEIGHT]` logs appear when a drop occurs.

## Adjacent UI regression need: viewport-triggered summary queueing
When switching to a project (e.g., `webviewer`) the UI shows visible entries with the hourglass before any scroll occurs, but the logger indicates queueing only fires after the fallback timer (500-600ms) or a user scroll (`[SUMM-VIEWPORT-FALLBACK]`, `[SUMM-DEBOUNCE]`). That means the viewport path is gated on scroll activity and prunes/queues the same entries repeatedly, so some visible entries never finish summarizing.

### Validation hints
- Logs to watch: `SUMM-LOAD-DEFER`, `SUMM-VIEWPORT-FALLBACK`, `SUMM-PRUNE-*`, `SUMM-QUEUE-*` around timestamps 11:03:11+ show the queue depth going from 0 → 17 and prune removing visible entries before summaries finish.
- DB queries confirming the symptom:
  * `SELECT entry_id FROM transcript_entries WHERE project_id = '-Users-rob-code-projects-webviewer' AND created_at BETWEEN ...;` (populate start/end from loged timestamps) to list the entries being shown.
  * `SELECT entry_id FROM timeline_cache WHERE entry_id IN (...)` to verify only some entries have cached summaries.
  * `SELECT entry_id, is_queued FROM transcript_entries WHERE entry_id IN (...)` to verify they are not queued and still unsummarized.

### Deferred UI test idea
1. Launch app with `webviewer` project snapshot.
2. Capture logs for `[SUMM-QUEUE]`/`[SUMM-PRUNE]` without performing any manual scrolls.
3. Assert the viewport callback triggers queueing (and pruning) within the initial fallback period rather than waiting for `isUserScrollActive`.
4. Optionally check the DB (`timeline_cache`, `transcript_entries`) afterward to ensure all visible entries have `selected_form` entries once queueing executes.

This test ensures future changes don’t re-introduce the UI stall where visible entries never queue unless the user scrolls. Keep the helper scripts/log commands referenced in this doc for future automation.

## Approach
1. Use the existing `TimelineEntryRow` view in a lightweight XCTest or SwiftUI preview harness.
2. Inject a fake entry + summary text; capture geometry via `SummaryTextHeightKey` observers.
3. Swap in a shorter summary and confirm the observed height delta matches the allowed cap.
4. Spy on OSLog (or use a test logger) to ensure `log.info("[SUMMARY-HEIGHT]")` fires when we drop below the prior max.

## Validation
- Covered by unit/SwiftUI test in `Contextify/ContextifyTests` or `Tests/ContextifyCoreTests`, depending on feasibility.
- Document the test matrix (long summary first, shorter second, delta <= 28pt, log emitted).
- Place any helper fixtures/resources here or in `build/notes/todo-support/` if more context is needed.
