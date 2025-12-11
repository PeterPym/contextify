# Contextify Design System

Central home for all design documentation and decisions.

## Directory Structure

```
build/design/
├── README.md           # This file
├── brand/              # Brand identity (universal)
│   ├── colors.md       # Canonical color tokens
│   ├── logomark/       # Infinity symbol, exports, history
│   └── providers/      # Third-party AI provider identity
│       ├── claude-code/
│       └── codex-cli/
├── application/        # macOS app design
│   └── icon/           # App icon (Icon Composer)
├── website/            # contextify.sh design
│   └── specimens/      # Color exploration
├── marketing/          # Social media, press kit
└── research/           # Competitive analysis, explorations
    ├── competitive/
    └── inspiration/
```

## Quick Links

| Area | Location | Status |
|------|----------|--------|
| **Color System** | `brand/colors.md` | Done - full inventory with dark mode |
| **Design Comparator** | `website/specimens/website-comparator.html` | Active - Lens A (website) / Lens B (specimens) |
| **Logomark** | `brand/logomark/` | Done - source + exports |
| **Providers** | `brand/providers/` | Done - icons + presentation rules |
| **App Icon** | `application/icon/` | Done - symlink to Icon Composer |
| **Marketing** | `marketing/` | Scaffold |
| **Research** | `research/` | Ready for use |

## Related Locations

| Location | Purpose |
|----------|---------|
| `build/docs/design/` | App UI patterns (SwiftUI, components) |
| `build/assets/` | Unified asset hub (symlinks + promotional, video, DMG assets) |
| `website/` | Deployed website files |
| `Contextify/icon-composer-project.icon/` | Active Icon Composer project (Xcode) |

## Color Token System

Canonical source: `brand/colors.md`

### Overview

| Category | Description |
|----------|-------------|
| **Semantic** | 7 purpose-driven colors (primary, secondary, success, warning, error, info, accent) |
| **Neutrals** | Tailwind Slate scale (11 steps: slate-50 to slate-950) |
| **Derived** | Text, background, border, link tokens mapped from neutrals |
| **Brand** | Logomark gradient colors (yellow, cyan, purple) |
| **Provider** | Third-party AI provider colors (Claude, Codex) |
| **Dark Mode** | Systematic derivation (inversion, lifting) documented |

### Semantic Colors

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `primary` | #4A7BA7 | #6A9BC7 | Actions, links |
| `secondary` | #9B8B7E | #B5A89D | Assistant content |
| `success` | #51A86B | #6BC885 | Completion states |
| `warning` | #D4A84E | #E4B85E | Warnings |
| `error` | #C74E4E | #D76E6E | Errors |
| `info` | #4A7BA7 | #6A9BC7 | Informational |
| `accent` | #7C68A8 | #9C88C8 | Metadata |

### Brand Colors

| Token | Hex | Source |
|-------|-----|--------|
| `brand-yellow` | #F9B233 | Logomark left |
| `brand-cyan` | #4AC4E0 | Logomark center |
| `brand-purple` | #8B5CF6 | Logomark right |

### Provider Colors

| Token | Hex | Provider |
|-------|-----|----------|
| `provider-claude` | #D97757 | Claude Code (Anthropic coral) |
| `provider-codex` | #FFFFFF | Codex CLI (needs shadow) |

**Naming:** CSS uses kebab-case (`--contextify-primary`), Swift uses camelCase (`contextifyPrimary`).

**Full details:** See `brand/colors.md` for neutral scale, derived tokens, dark mode derivation rules, and implementation examples.

## Brand Voice (Stub)

- **Audience:** Developers, Hacker News readers
- **Tone:** Authentic but chill, technically competent
- **Anti-pattern:** No hype, no marketing-speak

See `brand/voice-tone.md` for full guidelines (TODO).
