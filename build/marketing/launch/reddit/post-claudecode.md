# r/ClaudeCode Post

**Status:** Posted 2025-12-10 ~11:15am PT
**URL:** https://www.reddit.com/r/ClaudeCode/comments/1pjbriy/what_i_found_parsing_1700_claude_code_transcripts/
**Flair:** Showcase

---

## Title (as posted)

`What I found parsing 1,700 Claude Code transcripts (queue system, corruption bugs, and a free app)`

---

## Images Used

1. Onboarding screenshot (Dropbox location picker) - "Store your database in Dropbox or iCloud for backup"
2. `build/assets/website/feature-search-cropped.webp` - "Search across all your sessions"
3. `build/assets/promotional/v1.0.2/contextify-screenshot-queued-message-claude-code-light.png` - "Queue indicator in the timeline"

---

## Post Body (as posted)

Hey r/ClaudeCode.

I built a macOS app called [Contextify](https://contextify.sh) that monitors Claude Code sessions and keeps everything in a searchable local database. But the more interesting part might be what I learned while parsing 1,700+ transcripts.

**The Queue System**

Claude Code has a message queuing system that's pretty slick. If you send a message while it's already working, it queues it and incorporates it into its ongoing work. It might interrupt itself or wait - it makes the call.

The queue operations show up in the transcript as metadata records (`enqueue`, `dequeue`, `remove`, `popAll`). I built this into the parser and UI so you can see when messages are queued vs processed.

**Transcript Corruption from Teleport**

During the Claude Code Web promo a few weeks ago, I found corruption patterns causing 400 errors when resuming sessions from the web interface. The "teleport" feature was creating orphaned `tool_result` blocks the API couldn't handle.

I wrote a repair script that fixed ~99% of cases. Was going to ship it with the app, but Anthropic fixed it in 2.0.47 before I was ready to release. Oh well!

**Apple Intelligence Quirks**

FoundationModels (Apple's on-device LLM) is sequential-only - one request at a time. So I made summarization viewport-aware: it processes what you're looking at first.

Also discovered it refuses to summarize messages with expletives. Late night coding sessions can get salty. Rather than retry forever, I "tombstone" those failures - the entry shows original text with an (i) icon explaining why.

The app is free: [download the dmg or via the App Store](https://contextify.sh/download/). Here's the [demo video](https://www.youtube.com/watch?v=FvrvRGp4C9M) if you want to see it in action.

Happy to answer questions about the transcript format or the queue system. Also curious if anyone with more than 2k transcripts would stress test it.

---

## Notes

- Technical discovery angle, app secondary
- Bold text for sections, no formal headings
- Links at end
