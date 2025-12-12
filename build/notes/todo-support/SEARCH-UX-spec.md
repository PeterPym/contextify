---
todo_id: P2-SEARCH-UX
title: Deep Search Window Enhancements
type: spec
date: 2025-11-26
status: active
description: Feature specification for search window UI improvements including sorting, multi-select, and sticky date header
---

# Deep Search Window Enhancements

## Overview

Enhance the Deep Search window with improved sorting controls, multi-select capability in the context pane, and a sticky date header for navigation context.

## Features

### 1. Sort Control (2-3 hours)

**Location:** Search results pane header (left side)

**UI:** Segmented control with three options:
- **Date** - Sort by message timestamp
- **Relevance** - Sort by BM25 score (current default)
- **Both** - Primary: relevance, secondary: date

**Behavior:**
- Click same option twice to toggle ascending/descending
- Visual indicator for current sort direction (arrow or similar)
- Persist preference per session (not across app restarts)

**Implementation:**
- Add `sortMode` enum to `DeepSearchViewModel`
- Add `sortAscending` boolean
- Modify search query ORDER BY based on selection
- Update `ConversationSearchService.search()` to accept sort parameters

### 2. Context Pane Multi-Select (2-3 hours)

**Location:** Context pane (right side)

**Selection Behavior:**
- **Click:** Single message selection (clears previous selection)
- **Shift+Click:** Select range from last selection to clicked message
- **Cmd+Click:** Toggle individual message in/out of selection (additive)

**Visual Indication:**
- Selected messages get distinct background color or checkbox
- Selection count shown in header ("3 selected")

**Actions:**
- **Cmd+C:** Copy all selected messages to clipboard (formatted)
- Future: Export selected, feed to CLI (#P2-CONTEXT-REINJECTION)

**Implementation:**
- Add `selectedEntryIds: Set<String>` to `DeepSearchViewModel`
- Track `lastSelectedId` for shift+click range selection
- Modify `ContextEntryRow` to show selection state
- Add keyboard handler for Cmd+C

### 3. Sticky Date Header (1-2 hours)

**Location:** Top of context pane, overlays content

**Behavior:**
- Frozen row showing date of topmost visible message(s)
- Updates dynamically as user scrolls
- When messages from new day scroll into view, header updates
- Subtle visual treatment (semi-transparent background, smaller text)

**Implementation:**
- Use SwiftUI `GeometryReader` or preference keys to track visible entries
- Compute date from topmost visible entry's timestamp
- Overlay sticky header using `ZStack` with alignment

## Files to Modify

- `Contextify/Contextify/DeepSearchView.swift`
  - Sort control UI
  - Multi-select click handlers
  - Sticky date header overlay

- `Contextify/Contextify/DeepSearchViewModel.swift`
  - `sortMode`, `sortAscending` state
  - `selectedEntryIds` set
  - Selection logic (range, toggle)
  - Copy selected to clipboard

- `app/Sources/ContextifyCore/Search/ConversationSearchService.swift`
  - Accept sort parameters in `search()` method
  - Build ORDER BY clause dynamically

## Related TODOs

- **#P2-CONTEXT-REINJECTION** - Uses multi-select for export/CLI injection
- **#P1-CONTEXT-EXPORT** - Copy/export functionality

## Acceptance Criteria

- [ ] Sort control switches between Date/Relevance/Both
- [ ] Double-click on sort option toggles asc/desc
- [ ] Multi-select works with click, shift+click, cmd+click
- [ ] Cmd+C copies all selected messages
- [ ] Sticky date header shows current scroll position date
- [ ] Date header updates smoothly while scrolling
