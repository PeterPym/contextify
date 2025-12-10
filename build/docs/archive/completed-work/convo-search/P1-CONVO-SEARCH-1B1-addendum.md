---
todo_id: P1-CONVO-SEARCH
title: Phase 1B1 Addendum - Deep Search Window (Single Project)
type: implementation
date: 2025-11-25
status: ready
parent: P1-CONVO-SEARCH-implementation.md
description: Revised Phase 1B1 introducing Deep Search Window with split-view layout for single-project search, deferring cross-project features to 1B2.
---

# Phase 1B1 Addendum: Deep Search Window (Single Project)

## Context

Phase 1A implemented Quick Search in the HUD with a split-view layout (results + context). User feedback: the split-view requires too much horizontal space for the HUD's compact design.

## Revised Approach

1. **HUD Quick Search** - Simplified to results-only (compact vertical list)
2. **Deep Search Window** - New non-modal NSWindow with full split-view experience

## Phase 1B1 Scope

### What's IN
- Deep Search Window (non-modal NSWindow)
- Search field in window toolbar (top right)
- HSplitView: Results list | Context pane
- Open triggers: Cmd+Enter from HUD search, OR click result in HUD Quick Search
- Auto-scroll both panes to selected result on open
- Highlighted search hit in context using Contextify Yellow (#D4A84E) at 15% opacity
- Current project scope only
- Continue searching within the window

### What's DEFERRED to 1B2
- Cross-project search
- Pagination with 5000 cap
- Project filter dropdown

## UX Flow

1. User types query in HUD search field
2. Press **Enter** → Results appear in compact list (HUD stays compact)
3. Press **Cmd+Enter** OR click a result → Deep Search Window opens
4. Window shows:
   - Left: Results list, scrolled to & highlighting the selected result
   - Right: Context pane, scrolled to matched message (near center), highlighted
5. User can continue searching via the window's search field
6. Press **Esc** in HUD → exits search mode, returns to timeline

## Color Scheme Compliance

Per `build/docs/design/color-scheme.md`:

| Element | Color | Usage |
|---------|-------|-------|
| User messages | Contextify Blue (#4A7BA7) | Icon/accent |
| Assistant messages | Contextify Taupe (#9B8B7E) | Icon/accent |
| **Search hit highlight** | Contextify Yellow (#D4A84E) at 15% opacity | Background for matched message in context |
| Selected result | System selection color | Standard list selection |

The yellow highlight provides clear visual distinction without competing with message role colors.

## Implementation Details

### Files to Modify

| File | Change |
|------|--------|
| `QuickSearchView.swift` | Remove HSplitView, simplify to results-only list |
| `QuickSearchViewModel.swift` | Add method to open Deep Search Window |

### Files to Create

| File | Purpose |
|------|---------|
| `DeepSearchWindow.swift` | NSWindow wrapper for Deep Search |
| `DeepSearchView.swift` | SwiftUI content with HSplitView layout |
| `DeepSearchViewModel.swift` | State management, reuses ConversationSearchService |

### Window Specifications

```swift
// DeepSearchWindow.swift
- Style: .titled, .closable, .resizable, .miniaturizable
- Min size: 700 x 500
- Default size: 900 x 600
- Title: "Search: {project_name}"
- Non-modal (user can interact with HUD while open)
```

### Context Highlight Implementation

```swift
// In context entry row
.background(
  RoundedRectangle(cornerRadius: 6)
    .fill(isHighlighted ? Color.contextifyYellow.opacity(0.15) : Color.clear)
)
```

### Opening from HUD

```swift
// In QuickSearchViewModel or ContentView
func openDeepSearch(selectedHitId: String? = nil) {
    DeepSearchWindowController.shared.showWindow(
        projectId: currentProjectId,
        projectName: projectName,
        query: query,
        selectedHitId: selectedHitId
    )
}
```

## Testing Checklist

- [ ] Cmd+Enter from empty search field opens window with empty state
- [ ] Cmd+Enter with query opens window with results
- [ ] Click result in HUD opens window scrolled to that result
- [ ] Context pane scrolls to and highlights matched message
- [ ] Search field in window works, replaces results
- [ ] Window is non-modal (can click back to HUD)
- [ ] Esc in HUD exits search mode
- [ ] Yellow highlight visible in both light/dark modes

## Estimate

2-3 hours (reduced from original 1B scope by deferring cross-project features)
