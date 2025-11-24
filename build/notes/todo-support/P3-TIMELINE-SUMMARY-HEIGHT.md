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

## Approach
1. Use the existing `TimelineEntryRow` view in a lightweight XCTest or SwiftUI preview harness.
2. Inject a fake entry + summary text; capture geometry via `SummaryTextHeightKey` observers.
3. Swap in a shorter summary and confirm the observed height delta matches the allowed cap.
4. Spy on OSLog (or use a test logger) to ensure `log.info("[SUMMARY-HEIGHT]")` fires when we drop below the prior max.

## Validation
- Covered by unit/SwiftUI test in `Contextify/ContextifyTests` or `Tests/ContextifyCoreTests`, depending on feasibility.
- Document the test matrix (long summary first, shorter second, delta <= 28pt, log emitted).
- Place any helper fixtures/resources here or in `build/notes/todo-support/` if more context is needed.
