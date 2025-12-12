---
todo_id: P2-SEARCH-FOLLOWON
title: Conversation Search Follow-on Improvements
type: spec
date: 2025-11-26
status: active
description: Performance and UX improvements for conversation search feature
---

# P2-SEARCH-FOLLOWON: Conversation Search Follow-on Improvements

## Overview

Follow-on improvements identified during conversation search feature development (branch `feat/conversation-search`). These are not blockers but would improve performance and UX.

## Items

### 1. Context Load Performance (Priority: High within P2)

**Problem:**
Context load can take 2-3 seconds in some cases, even though the FTS query is fast (~25ms). The delay occurs because:
- `DeepSearchViewModel` is `@MainActor`
- Database calls await on main actor, but main actor is busy with UI re-renders
- 50-result list re-render blocks main actor between await points

**Evidence from logs:**
```
[DEEPSEARCH-TIMING] FTS query took 0.023s
[DEEPSEARCH-TIMING] Context load took 2.026s  # Should be <100ms
```

**Solution:**
Move database work off main actor using `Task.detached` or explicit actor hop:

```swift
// Current (waits for main actor between steps)
func loadContext(for entryId: String) async {
  let entries = try await searchService.getContext(...)
  contextEntries = entries  // Back on main (waits if busy)
  let counts = try await searchService.getContextCounts(...)
  earlierCount = counts.earlierCount  // Back on main again
}

// Fixed (batch off-main work)
func loadContext(for entryId: String) async {
  let (entries, counts) = await Task.detached {
    let e = try await searchService.getContext(...)
    let c = try await searchService.getContextCounts(...)
    return (e, c)
  }.value

  // Single hop back to main
  contextEntries = entries
  earlierCount = counts.earlierCount
  laterCount = counts.laterCount
}
```

**Scope:** Only affects `DeepSearchViewModel` and `QuickSearchViewModel`. Does not require changes to other parts of app.

**Files:**
- `Contextify/Contextify/DeepSearchViewModel.swift`
- `Contextify/Contextify/QuickSearchViewModel.swift`

**Effort:** 1-2 hours

---

### 2. QuickSearch Row Selection Highlighting (Priority: Low)

**Problem:**
`SearchHitRow` has `isSelected` parameter but QuickSearch always passes `false`. Selection highlighting could improve keyboard navigation UX.

**Current:**
```swift
SearchHitRow(hit: hit, isSelected: false)
```

**Proposed:**
```swift
SearchHitRow(hit: hit, isSelected: hit.id == viewModel.selectedHitId)
```

**Note:** Deferred for v1 because QuickSearch is a transient dropdown - clicking immediately opens Deep Search, so selection highlighting adds visual noise without benefit. Relevant for future keyboard navigation feature.

**Files:**
- `Contextify/Contextify/QuickSearchView.swift`

**Effort:** 15 minutes (once keyboard navigation is added)

---

### 3. ViewModel Test Infrastructure (Priority: Medium)

**Problem:**
ViewModels in Xcode app target cannot be tested from SPM test suite. Bug fix for "stale selection when query changes" was committed without regression test.

**Current state:**
- `Tests/ContextifyCoreTests/` - SPM tests (79 tests, all pass)
- `Contextify/ContextifyTests/` - Legacy Xcode tests (read-only per AGENTS.md)
- ViewModels in `Contextify/Contextify/` - not testable from either

**Options:**
1. Move ViewModel logic to ContextifyCore (may violate layering)
2. Extract pure functions for testable logic
3. Set up separate test target for app ViewModels
4. Accept manual testing for ViewModel state logic

**Files:**
- `Contextify/Contextify/DeepSearchViewModel.swift`
- `Contextify/Contextify/QuickSearchViewModel.swift`

**Effort:** 2-4 hours depending on approach

---

## Related Work (Completed)

These items from external review have been addressed:

- [x] P2.1: Refactor polling loop to async `searchAndWait()`
- [x] P2.2: Validate selection against new results after search
- [x] P2.4: Add `max(0, ...)` guards for negative limit/offset
- [x] P1.1: Add explicit `@MainActor` to Task closures
- [x] Fix: Clear results only when query text actually changes
- [x] Fix: Full-width "No Results" state (not split view)
- [x] Fix: Prevent stale scroll attempts during rapid selection

## Acceptance Criteria

- [ ] Context load consistently < 200ms (not 2-3s)
- [ ] No scroll errors in logs during rapid clicking
- [ ] Clean separation between main-actor UI work and off-main database work
