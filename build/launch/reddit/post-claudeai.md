# r/ClaudeAI Post Draft

**Flair:** Built with Claude (or Self-Promotion)

---

## Title Options

1. `I built a searchable history for Claude Code (your transcripts delete after 30 days)`
2. `Built a macOS app to keep my Claude Code conversations forever - Contextify`
3. `Your Claude Code history auto-deletes after 30 days. I built something to fix that.`

**Recommended:** Option 3 (problem-focused, hooks attention)

---

## Post Body

Your Claude Code history auto-deletes after 30 days. I built something to fix that.

I've been using Claude Code heavily since June, and I kept running into the same problem: conversations I needed to reference were gone. Decisions, rationale, failed approaches, context that took hours to build - all deleted.

So I built **Contextify** - a native macOS app that monitors your Claude Code sessions in real-time and keeps everything in a searchable local database.

### What it does

- **Real-time monitoring** of Claude Code (and Codex CLI) conversations
- **Full-text search** across all your sessions
- **LLM summaries** generated locally via Apple Intelligence (no API keys, no cloud)
- **Project-centric organization** with automatic discovery

### Demo

[3-minute video demo](https://www.youtube.com/watch?v=FvrvRGp4C9M)

### Screenshots

[Include 1-2 screenshots showing timeline and search]

### Technical details

- SwiftUI (macOS 26 SDK)
- GRDB/SQLite for local storage
- Apple FoundationModels for on-device LLM
- FSEvents for real-time file monitoring
- Parses JSONL transcripts from `~/.claude/projects/`

No server component. No telemetry. Your conversations stay on your machine.

### Pricing

**Free.** Available on the [App Store](https://apps.apple.com/us/app/contextify/id6753190666) and as a [direct DMG download](https://contextify.sh).

### Why I built this

Before Claude Code, I used ChatGPT's web interface with [FileKitty](https://filekitty.app) (which hit the HN front page) for context curation. One thing I relied on was the sidebar to search old conversations.

When I moved to Claude Code, I discovered there's no searchable history, and conversations auto-delete after 30 days. Then I started splitting work between Claude Code and Codex when I'd hit rate limits, making the fragmentation worse.

Contextify started as a script to parse these files. Then I added a UI. Then summaries. Then search. Now it's become my second monitor while coding.

### Questions for you

1. Do you keep your Claude Code conversation history? Do you ever go back to it?
2. Would you want Claude Code to be able to search its own past sessions? (The "memory" problem)
3. What other features would be useful?

---

**Links:**
- Website: https://contextify.sh
- App Store: https://apps.apple.com/us/app/contextify/id6753190666
- GitHub (issues): https://github.com/PeterPym/contextify
- Demo video: https://www.youtube.com/watch?v=FvrvRGp4C9M

---

## Notes for posting

- Use "Built with Claude" flair if available, otherwise "Self-Promotion"
- Include screenshots inline (upload to Reddit)
- Be ready to respond to comments for first few hours
- If asked about open source: "Core app is not open source yet. Considering it based on traction."
