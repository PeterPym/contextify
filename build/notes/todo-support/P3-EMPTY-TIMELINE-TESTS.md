---
title: P3-EMPTY-TIMELINE-TESTS
todo: build/notes/TODOS.md#P3-EMPTY-TIMELINE-TESTS
status: pending
priority: P3
---

## Objective
Document and later implement regression coverage for the empty-project timeline experience so we can prevent the spinner from creeping back in after the `ConversationMonitor` fix.

## Scope
- Capture the expected state combinations for `ConversationMonitor.phase`, `isAwaitingPrimer`, and the UI branch selection when there are zero timeline entries.
- Decide whether the guard is best implemented via a SwiftUI snapshot/UI test (exercising `ConversationTimelineView`) or a targeted unit test that instantiates `ConversationMonitor`, manipulates its state, and validates `phase`/`visibleEntries`.
- Identify any infrastructure gaps (mock orchestrator, VS prefer testing with actual database).

## Notes / Placeholders
- `ConversationMonitor.loadFeedFromSQL` should exit early with `phase == .loaded` when the entry count is zero.
- `ConversationTimelineView` currently toggles between the spinner and empty-state based on `phase` and `isAwaitingPrimer`.
- This note will grow with specific scenarios, test data setup steps, and references to future automation scripts.

