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
| **Color Tokens** | `brand/colors.md` | Done - semantic, brand, provider |
| **Logomark** | `brand/logomark/` | Done - source + exports |
| **Providers** | `brand/providers/` | Done - icons + presentation rules |
| **App Icon** | `application/icon/` | Done - symlink to Icon Composer |
| **Website** | `website/` | Active - color exploration |
| **Marketing** | `marketing/` | Scaffold |
| **Research** | `research/` | Ready for use |

## Related Locations

| Location | Purpose |
|----------|---------|
| `build/docs/design/` | App UI patterns (SwiftUI, components) |
| `build/assets/` | Legacy assets (DMG background) |
| `website/` | Deployed website files |
| `Contextify/icon-composer-project.icon/` | Active Icon Composer project (Xcode) |

## Color Token System

All colors are defined in `brand/colors.md` with unified naming:

### Semantic Colors (`contextify-*`)

| Token | Hex | Usage |
|-------|-----|-------|
| `contextify-primary` | #4A7BA7 | User actions, links |
| `contextify-secondary` | #9B8B7E | Assistant content |
| `contextify-success` | #51A86B | Completion states |
| `contextify-warning` | #D4A84E | Warnings |
| `contextify-error` | #C74E4E | Errors |
| `contextify-accent` | #7C68A8 | Metadata |

### Brand Colors (`contextify-brand-*`)

| Token | Hex | Source |
|-------|-----|--------|
| `contextify-brand-yellow` | #F9B233 | Logomark left |
| `contextify-brand-cyan` | #4AC4E0 | Logomark center |
| `contextify-brand-purple` | #8B5CF6 | Logomark right |

### Provider Colors (`provider-*`)

| Token | Hex | Provider |
|-------|-----|----------|
| `provider-claude` | #F97316 | Claude Code |
| `provider-codex` | #FFFFFF | Codex CLI (needs shadow) |

**Naming:** CSS uses kebab-case (`--contextify-primary`), Swift uses camelCase (`contextifyPrimary`).

## Brand Voice (Stub)

- **Audience:** Developers, Hacker News readers
- **Tone:** Authentic but chill, technically competent
- **Anti-pattern:** No hype, no marketing-speak

See `brand/voice-tone.md` for full guidelines (TODO).
