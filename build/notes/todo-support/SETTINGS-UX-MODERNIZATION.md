---
todo_id: SETTINGS-UX-MODERNIZATION
title: Settings window UX modernization
type: plan
date: 2025-12-14
status: active
description: Plan to modernize the Settings window navigation and pane layout to better match macOS conventions and improve perceived quality.
---

# Settings window UX modernization

## Context

Contextify’s Settings window currently uses a tab-style pane switcher and some panes present content in a way that can feel cramped or “mobile/web-like” (weak margins, uneven alignment, and insufficient grouping). This affects perceived quality even when the functionality is correct.

This TODO tracks a focused modernization pass to improve navigation and layout without changing underlying behavior.

## Goals

- Adopt a macOS-idiomatic Settings navigation pattern and keep it stable.
- Ensure each pane has consistent margins, padding, and visual hierarchy.
- Align controls (toggles, pickers, action buttons) to a consistent grid so controls don’t “float” based on label length.
- Ensure primary actions and critical information are visible without scrolling at the default window size.

## HIG references (local snapshots)

- `build/docs/design/references/apple-hig/README.md`
- `build/docs/design/references/apple-hig/2025-12-15/settings.md`
- `build/docs/design/references/apple-hig/2025-12-15/windows.md`
- `build/docs/design/references/apple-hig/2025-12-15/toolbars.md`
- `build/docs/design/references/apple-hig/2025-12-15/sidebars.md`
- `build/docs/design/references/apple-hig/2025-12-15/buttons.md`
- `build/docs/design/references/apple-hig/2025-12-15/labels.md`
- `build/docs/design/references/apple-hig/2025-12-15/text-views.md`
- `build/docs/design/references/apple-hig/2025-12-15/writing.md`

## Design decisions to pin down

1) Navigation model
- Option A: Toolbar-style settings panes (icon buttons across top)
- Option B: Sidebar-based settings window (Ventura-era System Settings style)

Phase 2 immediate work may keep the current pattern for stability; this TODO decides and executes the modernization explicitly.

2) Pane sizing strategy
- Per-pane sizing to fit content (preferred for settings)
- Scroll-first layout with stable window size

3) Layout primitives
- Prefer consistent grids (`LabeledContent`, `Grid`) for label/control alignment.
- Use `GroupBox` or similar for grouping when it improves scanability.

## Implementation sketch (high level)

- Audit existing panes for spacing and alignment consistency.
- Pick navigation model and implement in `SettingsView`.
- Refactor each pane to use consistent margins and control alignment.
- Add or update E2E tests that rely on Settings navigation (avoid window counting; prefer log tags).

## Risks / constraints

- SwiftUI accessibility identifiers can be unreliable; E2E tests should remain logs-first.
- Settings navigation changes may require updating QA scripts that switch panes.

