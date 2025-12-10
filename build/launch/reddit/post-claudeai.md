# r/ClaudeAI Post

**Flair:** Built with Claude (or Self-Promotion)

---

## Title

`I built a searchable history for Claude Code so you can find out how many times you've been "absolutely right"`

### Alternates (if needed)
- `Your Claude Code history auto-deletes after 30 days. I built something to fix that.`
- `PSA: Your Claude Code transcripts delete after 30 days. Here's a free app to keep them.`

---

## Post Body

Hey everyone.

I'm a software engineer and longtime redditor, sharing a new project today called Contextify.

I'm structuring this post to hopefully be valuable to you regardless of if you want to try my app: what it does, links to check it out, and things I learned.

### What it does

- Real-time monitoring of Claude Code and Codex conversations
- Full-text search across all your past sessions
- Privacy-first bias performs all LLM summaries locally via Apple Intelligence
- Project-centric organization with automatic discovery

### Download Links and Things

- [Contextify Website](https://contextify.sh)
- Download the app from [macOS App Store](https://apps.apple.com/us/app/contextify/id6753190666) or [.dmg](https://github.com/PeterPym/contextify/releases/latest)
- [File a bug report or request a feature](https://github.com/PeterPym/contextify/issues)
- Check out screenshots and a demo video

[Screenshot: Search window showing some of the times I've been "absolutely right."]

[Screenshot: Main window, showing the conversation timeline with the corresponding terminal window next to it.]

Video demo is on [youtube here](https://www.youtube.com/watch?v=FvrvRGp4C9M). Note this one is formatted for desktop viewing, may be hard to see on mobile.

### Stuff I've Learned

**Claude Code Web Free Tokens Promo Transcript Corruption Issue**

During the big Claude Code Web promo a few weeks ago, I found corruption patterns that were causing 400 errors when trying to resume sessions from the web interface.

I found that the "teleport" feature (resume CLI session from web) was creating orphaned tool_result blocks that the API couldn't handle.

I wrote a repair script that fixed about 99% of cases - it removes orphaned messages or fixes stop_reason mismatches. I thought, "Hey I'll include this with the app. People can spend their credits easier!"

But I wasn't ready to release before the credits expired and Anthropic fixed it in 2.0.47 with "Improved error messages and validation for claude --teleport". Oh well!

**CC's Queue System**

Claude Code has an awesome queuing system that I studied while building the parser.

Codex doesn't have this. On Codex, if you send a message while it's working, it basically waits until its fully completed the prior request.

On CC, if you send a message while it's already working on something, it will queue it and incorporate it into its ongoing work. It might interrupt itself or it might wait, it makes a call on its own and its very slick.

I wanted Contextify to be able to reflect these Queued messages appropriately and I was able to build this into the parser and UI by following the transcript metadata records (enqueue, dequeue, remove, popAll).

The app clears this status once Claude has included it in its thinking (regardless of whether it says that it has, cause sometimes it doesn't!)

**Apple Intelligence Quirks**

Foundation Models (Apple's on-device LLM framework) is sequential-only. One request in flight at a time, period. So, I made summarization viewport-aware - it processes what you're actually looking at first, not some random order.

Also discovered it refuses to summarize messages containing expletives. I stayed up late a lot of nights working on this and sometimes things could get salty with CC.

Rather than retry summarizing these kinds of messages, I "tombstone" those failures in the cache. The entry just shows original text with an (i) icon you can click to see why it wasn't summarized.

I also learned a lot about grounding LLM outputs to avoid hallucinated intent along the way. There are many, many cases to handle to make a short summary accurately reflect the intent of messages. I have covered a lot but have a batch of funky summaries still to build logic for.

---

Okay that's all for now. I'd be happy to answer questions or hear other people's experiences dealing with the above.

I'm also curious if someone with more transcripts than me can try the app. I have about 1700 transcripts between CC and Codex at the moment. I'd like to know how well the app loads in first 3 mins and then ongoing use.

---

## Writing Style Notes

This post uses an authentic, conversational tone:
- No marketing hype or superlatives
- Technical details that are genuinely interesting
- Self-deprecating humor (the "Oh well!" moment)
- Honest about limitations (funky summaries still to fix)
- Asks for help rather than just promoting

Use this style for all future posts.
