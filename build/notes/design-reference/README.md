# Design Reference Documentation

Design guidelines, patterns, and specifications for the Contextify application.

## Purpose

This directory contains **design-facing documentation** that complements the technical reference docs. While `technical-reference/` focuses on implementation details (architecture, APIs, data flow), `design-reference/` documents the **visual language, UX patterns, and design decisions** that shape the user experience.

## Documentation Index

### Visual Design
- **[color-scheme.md](color-scheme.md)** - Application color palette with usage guidelines

### Planned Documentation
- **typography.md** - Font choices, sizes, weights, hierarchy
- **iconography.md** - Icon usage patterns, SF Symbols guidelines
- **spacing.md** - Layout grid, padding, margins, visual rhythm
- **component-patterns.md** - Reusable UI component specifications
- **interaction-patterns.md** - Animations, transitions, gestures
- **accessibility.md** - WCAG compliance, keyboard navigation, VoiceOver support

## Cross-References

Design decisions often have technical implications. Cross-reference with:
- `technical-reference/` - Implementation architecture
- `archive/` - Historical design evolution and rationale
- `implementation-plans/` - Planned feature designs

## Design Philosophy

**Native macOS Experience:** Build on system conventions, HIG guidelines, and platform expectations

**Information Density:** Surface relevant context without overwhelming; progressive disclosure where appropriate

**Professional Clarity:** Muted, purposeful colors; clear visual hierarchy; minimize decoration

**Provider Neutrality:** Support Claude Code, Codex CLI, and future providers without visual bias

**Accessibility First:** WCAG AA minimum; keyboard navigation; proper contrast ratios

## Contributing

When adding UI features:
1. Document color choices in `color-scheme.md`
2. Add component patterns to `component-patterns.md` (when created)
3. Note accessibility considerations
4. Cross-reference technical implementation docs
