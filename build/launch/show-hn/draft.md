# Show HN: Contextify - Draft Post

Work in progress.

---

## Title Options

- Show HN: Contextify - Searchable history for Claude Code and Codex
- Show HN: Contextify - A timeline HUD for CLI coding agents
- Show HN: Contextify - Stop losing your Claude Code conversation history

---

## Post Body (Draft)

[Video link goes here after intro paragraph, not as opener]

**Draft 1:**

I built Contextify because I kept losing track of my Claude Code sessions.

Before Claude Code, I used ChatGPT's web interface with a tool I built called FileKitty (which hit the HN front page) for context curation. One thing I relied on was the sidebar to search old conversations.

When I moved to Claude Code, I discovered there's no searchable history, and conversations auto-delete after 30 days by default. Then I started splitting work between Claude Code and Codex when I'd hit rate limits, making the fragmentation worse.

Contextify solves this. It's a native macOS HUD that:

- Watches Claude Code and Codex sessions in real-time
- Generates LLM summaries of conversation chunks
- Stores everything in a local, searchable database
- Shows a timeline so you can skim what happened

[2-min demo video]

It's built with Swift/SwiftUI, runs locally, and your data never leaves your machine. Free to download.

Repo: [if open source, or "Closed source for now"]
Download: contextify.sh

Happy to answer questions about the implementation, the LLM summarization approach, or anything else.

---

## Notes

- HN appreciates technical details - mention Swift/SwiftUI, local LLM summarization
- Link to FileKitty for credibility/context
- Keep it concise - the video does the heavy lifting
- Be ready for questions about: privacy, what LLM is used, open source plans, Linux/Windows support
