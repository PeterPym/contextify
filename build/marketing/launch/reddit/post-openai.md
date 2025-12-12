# r/OpenAI Post Draft (Codex CLI angle)

**Flair:** Check subreddit for appropriate flair

---

## Title Options

1. `Built a macOS app to keep your Codex CLI history forever (also works with Claude Code)`
2. `If you use Codex CLI: your sessions delete after 30 days. I built something to fix that.`
3. `Contextify - Searchable history for Codex CLI and Claude Code sessions`

**Recommended:** Option 2 (problem-focused, Codex-first)

---

## Post Body

If you use **Codex CLI**, you might have noticed your session transcripts auto-delete after a while. There's no built-in way to search old conversations or keep a permanent history.

I built **Contextify** to solve this.

### What it does

Contextify is a native macOS app that:

- **Monitors Codex CLI sessions** in real-time (also supports Claude Code)
- **Keeps everything forever** in a local SQLite database
- **Full-text search** across all your sessions
- **AI-generated summaries** for each message (via Apple Intelligence, 100% on-device)

If you switch between Codex and Claude Code depending on rate limits or task type, Contextify gives you a unified timeline across both tools.

### Demo

[3-minute video](https://www.youtube.com/watch?v=FvrvRGp4C9M)

### How it works

- Watches `~/.codex/sessions/` for new transcripts
- Parses the JSONL format in real-time
- Stores everything locally (no cloud, no telemetry)
- Apple Intelligence generates summaries on-device

### Pricing

**Free.** Available on the App Store and as a direct download.

### Links

- Website: https://contextify.sh
- App Store: https://apps.apple.com/us/app/contextify/id6753190666

### Questions

1. Do you use Codex CLI regularly? How do you manage your session history?
2. Do you also use Claude Code, or stick to one tool?
3. What features would be most useful for your workflow?

---

## Notes for posting

- r/OpenAI is large and diverse - posts can get buried
- Lead with Codex angle since that's the OpenAI connection
- Mention Claude Code support as bonus (unified history)
- Be prepared for questions about why not Windows/Linux
- This post might get less traction than r/ClaudeAI since Codex CLI is newer/smaller user base
