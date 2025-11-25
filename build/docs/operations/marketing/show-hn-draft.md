# Show HN: Contextify – Native macOS app for tracking Claude Code and Codex CLI sessions

**Video demo:** [2-minute walkthrough] (TODO: record)

I built Contextify because I kept losing track of what happened in long Claude Code sessions. After 200+ messages, I'd forget what we decided, what we tried, what failed. Starting a new session meant re-explaining everything.

## What it does

Contextify is a native macOS HUD that monitors your AI coding sessions in real-time:

- **Unified timeline** of Claude Code and Codex CLI conversations
- **AI-generated summaries** of each message (via Apple Intelligence)
- **Project-centric organization** with automatic git branch tracking
- **Cross-session history** searchable in a local SQLite database

Think of it as Activity Monitor for your AI pair programming sessions.

## Demo (screenshots in comments)

1. Start a Claude Code session in any project
2. Contextify auto-detects it, shows the conversation timeline
3. Each message gets a one-line summary ("Debugging unread count issue", "Refactoring ProjectSwitcher")
4. Switch projects in the sidebar, see all your sessions organized by repo
5. Search across all conversations (coming in next update)

## What's shipping today

✅ Real-time session monitoring (Claude Code + Codex CLI)
✅ LLM-powered message summaries
✅ Multi-project discovery and indexing
✅ Timeline visualization with timestamps
✅ Git branch display per session
✅ Local-only data (nothing leaves your Mac)

## What's NOT in v1

- No conversation search yet (FTS coming in 1.1)
- No transcript export/conversion
- No mobile app
- macOS 26 (Tahoe) required for summaries

## Why native macOS? Why Tahoe-only?

I wanted something that feels like a system utility, not another Electron app. SwiftUI means instant launch, minimal memory, native window management.

**The Tahoe (macOS 26) requirement** is because of Apple Intelligence - the on-device LLM that generates summaries. No API keys, no data sent anywhere, runs entirely on your Mac.

That said, the core functionality (monitoring, indexing, timeline) doesn't need Apple Intelligence. I'm planning to add support for older macOS versions with either:
- Ollama/local model integration
- Summary-less "lite" mode (still useful for timeline + search)

**If you're on an older macOS:** The roadmap includes backwards compatibility. If you want to start collecting your transcript history now so it's ready when you upgrade, let me know - I can prioritize this.

## Pricing

**Free** on the App Store. Also available as a direct DMG download.

I'm a solo developer. If this gets traction, I'll add a paid tier for advanced features (search, analytics, maybe team sync). But the core monitoring is free.

## Technical details

- SwiftUI (macOS 26 SDK, min deployment macOS 26)
- GRDB/SQLite for local storage
- Apple FoundationModels for on-device LLM
- FSEvents for real-time file monitoring
- Parses JSONL transcripts from `~/.claude/projects/` and `~/.codex/sessions/`

No server component. Your conversations stay on your machine.

## Why I built this

I've been using Claude Code heavily for the past few months. The conversations are valuable - they contain decisions, rationale, failed approaches, context that took hours to build. But they're trapped in append-only JSONL files that are painful to search or review.

Contextify started as a script to parse these files. Then I added a UI. Then summaries. Now it's become my second monitor while coding.

## Roadmap (if people want it)

- **1.1**: Full-text search across all conversations
- **1.2**: Semantic search (embeddings)
- **Future**: MCP server to let Claude Code query its own history ("What did we try last time?")

## Links

- App Store: [link]
- Direct download (DMG): https://contextify.sh
- GitHub: https://github.com/banagale/contextify (not open source yet, but considering it)

## Questions for HN

1. Do you keep your AI conversation history? Do you ever go back to it?

2. Would you want Claude Code to be able to search its own past sessions? (The "memory" problem)

3. What other AI coding tools should I support? (Cursor, Aider, Windsurf?)

---

Solo indie project, built in Swift over the past 3 months. Happy to answer questions about the architecture, the transcript formats, or anything else.
