# App UI Design Documentation

Design decisions, UX patterns, and visual design specifications **for the macOS app**.

> **Note:** For brand identity, website, and marketing design, see [`build/design/`](../../design/README.md).

## Purpose

This directory contains design documentation for:
- In-app color scheme and typography
- UX patterns and interactions
- SwiftUI design patterns
- Accessibility considerations

## Documents

### [Color Scheme](color-scheme.md)
**Topics:** Color palette and usage guidelines
- Semantic color definitions
- Timeline entry colors by intent
- Dark mode support
- Implementation references (TimelineEntryRow.swift:192-206)

### [Provider Iconography](providers.md)
**Topics:** AI provider visual identity
- Claude Code and Codex CLI logomarks
- Asset locations and colors
- Light mode shadow requirement for Codex
- Reference implementation (TimelineEntryRow.swift:112-124)

### [Help System](help-tooltip-ux-system.md)
**Topics:** Help tooltip UX system design
- Tooltip patterns and hierarchy
- Contextual help placement
- SwiftUI 6 implementation details
- Phases 1-4 implementation status (complete)

### [Help Documentation](help-documentation.md)
**Topics:** Help content and documentation structure
- User-facing help text
- Tooltip content guidelines
- Documentation organization

### [Help Tooltip Research Findings](help-tooltip-research-findings.md)
**Topics:** Research and analysis for help system design
- User testing insights
- Best practices from other apps
- Design rationale

### [Help Tooltip SwiftUI 6 Update](help-tooltip-swiftui6-update.md)
**Topics:** SwiftUI 6 migration for help system
- API changes and updates
- Implementation improvements
- Compatibility considerations

---

## Relationship to Other Docs

- **Architecture/** - Technical implementation of design decisions
- **Components/** - Components implementing these design patterns
- **Guides/** - How to maintain design consistency

---

## Updating These Docs

**When to update:**
- After design decisions that affect UX patterns
- When color scheme or typography changes
- After major UI refactoring that changes design approach

**What to include:**
- Design rationale and decision context
- Visual specifications (colors, spacing, typography)
- Code references for implementation
- Examples and screenshots where helpful

**What NOT to include:**
- Design explorations or mockups → `build/design/research/`
- Brand identity documentation → `build/design/brand/`
- Website design → `build/design/website/`
- Marketing/social assets → `build/design/marketing/`
- User feedback or feature requests → GitHub issues or TODOS.md

---

## Design Principles

1. **Minimal and focused** - Show only what's needed, when it's needed
2. **Consistent patterns** - Reuse established SwiftUI patterns
3. **Accessible** - Follow macOS HIG and accessibility guidelines
4. **Data-driven** - Design reflects data structure and flow
