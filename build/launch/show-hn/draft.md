# Show HN: Contextify – Your Claude Code history deletes after 30 days. This keeps it forever.

I built Contextify because I kept losing track of my Claude Code sessions.

Before Claude Code, I used ChatGPT's web interface with FileKitty (which hit the HN front page) for context curation. One thing I relied on was the sidebar to search old conversations.

When I moved to Claude Code, I discovered there's no searchable history, and conversations auto-delete after 30 days. Then I started splitting work between Claude Code and Codex when I'd hit rate limits, making the fragmentation worse.

## What it does

Contextify is a native macOS HUD - a private, searchable timeline of your AI coding sessions:

- **Unified timeline** of Claude Code and Codex CLI conversations
- **Searchable history** across all your projects and sessions
- **LLM summaries** generated locally via Apple Intelligence (no API keys, no cloud)
- **Project-centric organization** with automatic discovery

Your conversations, your control. Think of it as an ambient flow monitor for your agentic AI coding sessions.

## What's shipping today

✅ Real-time session monitoring (Claude Code + Codex CLI)
✅ Full-text search across all conversations
✅ LLM-powered message summaries (Apple Intelligence)
✅ Multi-project discovery and indexing
✅ Timeline visualization with expand/collapse
✅ 100% local - your data never leaves your Mac

## What's NOT in v1

- No transcript export/conversion between CLIs
- No mobile companion
- macOS 26 (Tahoe) required for summaries

## Why native macOS? Why Tahoe-only?

I wanted something that feels like a system utility, not another Electron app. SwiftUI means instant launch, minimal memory, native window management.

**The Tahoe requirement** is because of Apple Intelligence - the on-device LLM that generates summaries. No API keys, no cloud calls, runs entirely on your Mac. If you're on an older macOS and want a summary-less mode, let me know.

## Pricing

**Free.** Available on the App Store and as a direct DMG download.

I'm a solo developer. If this gets traction, I might add a paid tier for advanced features. But the core monitoring and search is free.

## Technical details

- SwiftUI (macOS 26 SDK)
- GRDB/SQLite for local storage
- Apple FoundationModels for on-device LLM
- FSEvents for real-time file monitoring
- Parses JSONL transcripts from `~/.claude/projects/` and `~/.codex/sessions/`
- Lazy summarization (only processes messages you scroll to - doesn't burn battery)
- Tool call history retained for audit trails (how did the AI get to that solution?)
- Database can live on Dropbox/network folder for backup

No server component. No telemetry. Your conversations stay on your machine.

## Why I built this

I've been using Claude Code heavily since June. The conversations are valuable - decisions, rationale, failed approaches, context that took hours to build. But Claude Code auto-deletes them after 30 days, and there's no way to search across sessions.

Contextify started as a script to parse these files. Then I added a UI. Then summaries. Then search. Now it's become my second monitor while coding.

## Roadmap

- **1.1**: Semantic search (embeddings)
- **Future**: MCP server to let Claude Code query its own history ("What did we try last week?")
- **Future**: Cross-CLI transcript conversion (resume Claude Code sessions in Codex)

## Links

- **Demo video:** https://www.youtube.com/watch?v=FvrvRGp4C9M
- **Download:** https://contextify.sh
- **App Store:** https://apps.apple.com/us/app/contextify/id6753190666
- **GitHub (issues):** https://github.com/PeterPym/contextify

## Questions for HN

1. Do you keep your AI conversation history? Do you ever go back to it?

2. Would you want Claude Code to be able to search its own past sessions? (The "memory" problem)

3. What other AI coding tools should I support? (Cursor, Aider, Windsurf?)

---

Solo indie project, built in Swift over ~3 months. Happy to answer questions about the architecture, transcript parsing, or anything else.

---

# Planning Notes (not part of post)

## Alternative Titles

- Show HN: Contextify - Searchable history for Claude Code and Codex
- Show HN: Contextify - A timeline HUD for CLI coding agents
- Show HN: Contextify - Stop losing your Claude Code conversation history

## Be Ready For Questions About

- Privacy - everything local, no telemetry
- What LLM is used - Apple Intelligence (FoundationModels framework)
- Open source plans - not yet, considering based on traction
- Linux/Windows support - macOS only due to Apple Intelligence dependency
- Why Tahoe only - Apple Intelligence requirement; lite mode possible for older macOS
- Cursor/Aider support - planned based on demand

## Potential Objections & Responses

**"Why macOS only?"**
> Native performance, Apple Intelligence integration. Windows/Linux would require different LLM approach.

**"Why Tahoe only?"**
> Apple Intelligence requires macOS 26. Working on backwards compatibility with lite mode.

**"What about Cursor/Aider/other tools?"**
> Claude Code and Codex CLI first because that's what I use. More tools planned based on demand.

**"Is this open source?"**
> Core app is not open source yet. Considering it based on traction. Transcript formats are documented.

**"How is this different from just reading the JSONL files?"**
> You could read them manually, but: unified timeline across tools, AI summaries, search, project organization. It's the UX layer.

**"What about privacy?"**
> Everything local. No data leaves your Mac. LLM runs on-device via Apple Intelligence.

## Video Demo (Optional)

If recording a demo, show:
1. Start a Claude Code session in any project
2. Contextify auto-detects it, shows the conversation timeline
3. Each message gets a one-line summary
4. Switch projects in the sidebar
5. Search across all conversations

Script available at: `build/launch/show-hn/video-script-v2.md`
