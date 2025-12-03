# Brand Identity

Universal brand elements used across app, website, and marketing.

## Directory Structure

```
brand/
├── README.md           # This file
├── colors.md           # Canonical color tokens (semantic, brand, provider)
├── logomark/           # Infinity symbol - primary visual identifier
│   ├── README.md
│   ├── HISTORY.md
│   ├── source/         # High-res master, SVG (TODO)
│   └── exports/        # Pre-rendered sizes (16-512px)
├── providers/          # Third-party AI provider identity
│   ├── README.md       # Presentation rules
│   ├── claude-code/    # Anthropic Claude Code
│   └── codex-cli/      # OpenAI Codex CLI
├── wordmark.md         # "Contextify" typography (TODO)
├── typography.md       # Font choices (TODO)
└── voice-tone.md       # Writing style (TODO)
```

## Colors

Canonical color token definitions. See `colors.md` for:
- Semantic colors (`contextify-primary`, `contextify-success`, etc.)
- Brand colors (`contextify-brand-yellow`, etc.)
- Provider colors (`provider-claude`, `provider-codex`)
- CSS and Swift implementations

## Logomark

The infinity symbol with circular arrows. See `logomark/README.md` for:
- Source files and exports
- Version history
- Regeneration commands

## Providers

Third-party AI provider visual identity. See `providers/README.md` for:
- Claude Code (Anthropic) - orange asterisk
- Codex CLI (OpenAI) - white brackets (requires shadow on light bg)
- Icon exports and presentation rules

## Status

| File | Purpose | Status |
|------|---------|--------|
| `colors.md` | Unified color tokens | **Done** |
| `logomark/` | Infinity symbol specs, exports | **Done** |
| `providers/` | AI provider identity, icons | **Done** |
| `wordmark.md` | "Contextify" typography, lockups | TODO |
| `typography.md` | Font choices, hierarchy | TODO |
| `voice-tone.md` | Writing style, messaging guidelines | TODO |

## Voice/Tone Stub

Until full documentation:
- **Audience:** Developers, Hacker News readers
- **Tone:** Authentic but chill, technically competent
- **Avoid:** Hype, buzzwords, empty marketing language
- **Examples:**
  - ✅ "Contextify watches your AI coding sessions and builds a searchable timeline"
  - ❌ "Revolutionary AI-powered productivity enhancement solution"
