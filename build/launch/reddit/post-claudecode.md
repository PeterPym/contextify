# r/ClaudeCode Post

**Status:** Draft
**Flair:** Showcase (or Discussion)

---

## Title

`I parsed 1,700 Claude Code transcripts and learned some things (+ free macOS app)`

### Alternates
- `Built a transcript viewer for Claude Code - here's what I learned about the queue system`
- `Free macOS app: searchable Claude Code history (and things I learned parsing 1,700 transcripts)`

---

## Post Body

Hey r/ClaudeCode.

I built a macOS app called Contextify that monitors Claude Code sessions and keeps everything in a searchable local database. But the more interesting part might be what I learned while parsing 1,700+ transcripts.

### The App (quick version)

- Real-time monitoring of Claude Code conversations
- Full-text search across all your past sessions
- LLM summaries via Apple Intelligence (on-device)
- Free: [contextify.sh](https://contextify.sh) / [App Store](https://apps.apple.com/us/app/contextify/id6753190666)

[Screenshot: Main window with conversation timeline]

### Stuff I Learned

**The Queue System**

Claude Code has a message queuing system that's pretty slick. If you send a message while it's already working, it queues it and incorporates it into its ongoing work. It might interrupt itself or wait - it makes the call.

The queue operations show up in the transcript as metadata records (`enqueue`, `dequeue`, `remove`, `popAll`). I built this into the parser and UI so you can see when messages are queued vs processed.

**Transcript Corruption from Teleport**

During the Claude Code Web promo a few weeks ago, I found corruption patterns causing 400 errors when resuming sessions from the web interface. The "teleport" feature was creating orphaned `tool_result` blocks the API couldn't handle.

I wrote a repair script that fixed ~99% of cases. Was going to ship it with the app, but Anthropic fixed it in 2.0.47 before I was ready to release. Oh well!

**Apple Intelligence Quirks**

FoundationModels (Apple's on-device LLM) is sequential-only - one request at a time. So I made summarization viewport-aware: it processes what you're looking at first.

Also discovered it refuses to summarize messages with expletives. Late night coding sessions can get salty. Rather than retry forever, I "tombstone" those failures - the entry shows original text with an (i) icon explaining why.

---

Happy to answer questions about the transcript format, the queue system, or anything else. Also curious if anyone with more than 1,700 transcripts wants to stress test the app.

**Links:**
- [Website](https://contextify.sh)
- [Demo video](https://www.youtube.com/watch?v=FvrvRGp4C9M) (3 min)
- [GitHub (issues)](https://github.com/PeterPym/contextify/issues)

---

## Images

1. `website/assets/img/contextify-screenshot-dark.png` - Main timeline
2. `build/assets/screenshots/contextify-screenshot-queued-message-claude-code-dark.png` - Queue indicator (very relevant for this sub)

---

## Writing Style Notes

For r/claudecode:
- Lead with technical discovery, app is secondary
- Queue system details will resonate with power users
- These users know their transcripts delete - don't belabor it
- "Stuff I Learned" format works well
- Ask for stress testers (engagement hook)
