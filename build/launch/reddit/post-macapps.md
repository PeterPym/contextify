# r/MacApps Post Draft

**Flair:** Self-Promotion (check subreddit for exact flair options)

---

## Title Options

1. `Contextify - Free macOS app that backs up and searches your Claude Code / Codex sessions`
2. `I built a native macOS HUD to monitor AI coding sessions (Claude Code + Codex)`
3. `Free app: Searchable history for Claude Code and Codex CLI (your transcripts delete after 30 days)`

**Recommended:** Option 1 (clear, mentions free, describes function)

---

## Post Body

Hi r/MacApps!

I built **Contextify**, a free native macOS app that monitors your AI coding sessions (Claude Code and Codex CLI) and keeps everything in a searchable local database.

### The problem

If you use Claude Code or OpenAI's Codex CLI, your conversation transcripts auto-delete after 30 days. There's no searchable history, and if you switch between tools, your context is fragmented across multiple locations.

### What Contextify does

- **Real-time monitoring** - watches your Claude Code and Codex sessions as they happen
- **Searchable history** - full-text search across all conversations, forever
- **AI summaries** - each message gets a one-line summary via Apple Intelligence (100% on-device, no API)
- **Project organization** - automatically discovers and groups sessions by project

### Screenshots

[Include 2-3 screenshots: timeline view, search results, project switcher]

### Demo video

[3-minute walkthrough](https://www.youtube.com/watch?v=FvrvRGp4C9M)

### Why native macOS?

I wanted something that feels like a system utility, not another Electron app:
- SwiftUI for instant launch and minimal memory
- Native window management (HUD-style floating window)
- Apple Intelligence integration for on-device LLM summaries
- No server component, no telemetry

### Requirements

- macOS 26 (Tahoe) for Apple Intelligence summaries
- Works without summaries on older macOS (if there's demand for a lite mode)

### Pricing

**Free.** Both App Store and direct DMG download.

I'm a solo developer. If this gets traction, I might add a paid tier for advanced features, but the core monitoring and search is free.

### Links

- **Download:** https://contextify.sh
- **App Store:** https://apps.apple.com/us/app/contextify/id6753190666
- **GitHub (issues):** https://github.com/PeterPym/contextify

Happy to answer any questions about the app or the technical implementation!

---

## Notes for posting

- r/MacApps appreciates:
  - Native apps (not Electron)
  - Free or reasonably priced
  - Privacy-focused
  - Technical details about implementation
- Be prepared for questions about:
  - Why not open source?
  - Why Tahoe only?
  - Comparisons to similar tools
- Engage with ALL comments, even critical ones
- Based on research: critical feedback early can lead to positive momentum if you respond well
