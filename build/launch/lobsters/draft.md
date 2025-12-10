# Lobsters Post Draft

**Title:** Contextify - Searchable history for Claude Code and Codex CLI

**URL:** https://contextify.sh

**Tags:** `show`, `macos`, `ai`

---

## Description (for comments)

I built Contextify because I kept losing track of my Claude Code sessions.

Claude Code auto-deletes conversations after 30 days, and there's no way to search across sessions. When I started splitting work between Claude Code and Codex CLI (to work around rate limits), the fragmentation got worse.

**What it does:**

- Monitors `~/.claude/projects/` and `~/.codex/sessions/` for JSONL transcripts
- Builds a unified, searchable timeline across both tools
- Generates one-line summaries for each message using Apple Intelligence (on-device, no API keys)
- Organizes by project with automatic discovery

**Technical details:**

- Native SwiftUI (not Electron)
- GRDB/SQLite for storage
- Apple FoundationModels for on-device LLM
- FSEvents for real-time file monitoring
- Requires macOS 26 (Tahoe) for the summary feature

**Why native macOS?**

I wanted something that feels like a system utility. Instant launch, minimal memory footprint, native window management. The Tahoe requirement comes from Apple Intelligence - on-device summarization without API keys or cloud calls.

**What I learned building it:**

- Found and fixed transcript corruption bugs that were causing "resume session" 400 errors in Claude Code (Anthropic patched this a few weeks later)
- Lazy summarization (only process messages you scroll to) keeps battery usage reasonable
- SwiftUI's ScrollViewReader needs to call scrollTo twice for reliable scrolling (undocumented quirk)

**Source:** Not open source yet, but transcript format documentation is available. Considering based on interest.

**Free:** Available on the App Store and as a direct DMG.

Happy to answer questions about the architecture, transcript parsing, or SwiftUI/macOS development.

---

# Planning Notes

## Lobsters vs HN differences

- More technical audience, appreciates implementation details
- Tags instead of "Show HN" prefix
- Smaller community, less noise
- Generally more appreciative of native Mac apps
- Less tolerant of marketing-speak

## Key angles to emphasize

1. **Native Mac app** - Lobsters audience appreciates this
2. **Technical details** - The corruption bug story, lazy summarization, SwiftUI quirks
3. **On-device LLM** - Privacy angle, no API keys
4. **Practical problem** - Losing conversation history is relatable

## Potential questions to prepare for

- "Why not just grep the JSONL files?" → UX layer: search, summaries, timeline, project organization
- "Open source plans?" → Considering based on interest, transcript formats documented
- "Linux support?" → macOS only due to Apple Intelligence dependency
- "Why Tahoe only?" → Apple Intelligence requirement; could add lite mode for older macOS
- "Performance?" → Native SwiftUI, lazy loading, minimal memory

## Tags selection

- `show` - Required for Show posts
- `macos` - Primary platform
- `ai` - Relevant category

Alternative tags if limited:
- `programming` - Generic fallback
- `swift` - If technical audience

## Don't mention

- Pricing strategy (it's free, no need to discuss)
- Roadmap (focus on what ships today)
- Competitors (let them bring it up)
