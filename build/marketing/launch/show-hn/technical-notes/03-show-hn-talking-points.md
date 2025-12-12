# Show HN: Technical Talking Points

Terse, HN-appropriate additions to the Show HN post. Based on successful post patterns (personal story + technical depth, no hype).

---

## Recommended Additions to Draft

### For the "Technical details" Section

Add one or more of these bullets. They're concrete, invite discussion, and demonstrate real engineering work:

**Transcript corruption (best story):**
> During the Claude Code API credits giveaway, I discovered corruption patterns in transcripts that caused 400 errors when resuming sessions. Wrote a repair script that fixed 99% of cases. A few weeks later, Anthropic's release notes mentioned making transcript parsing "robust." Small world.

**Queue system:**
> Claude Code has an undocumented queuing system. If you send a message while it's working, it queues it and can even change direction mid-task. I reverse-engineered this to show "queued" status in the timeline. Codex doesn't have this.

**Lazy loading:**
> With 1000+ transcripts, naive loading locked the UI. Rewrote ingestion as stat-only discovery + JIT parsing. Cold start went from seconds to 187ms.

**Tombstoning:**
> Apple Intelligence refuses to summarize messages with expletives. Rather than retry forever, I "tombstone" failures in the cache. Learned a lot about grounding LLM summarization to avoid hallucinated intent.

---

### For Comment Responses (Not Main Post)

These are good for replies when someone asks "tell me more about X":

**On transcript formats:**
> Claude Code and Codex both use JSONL but the similarity ends there. Claude Code has 10+ record types including queue operations, tool results inline, and git branch on every message. Codex has 4 types and stores git info only at session start. I documented both formats extensively while building the parsers.

**On the corruption bug:**
> The "teleport" feature (resume CLI session from web) was creating orphaned tool_result blocks. The API would return "unexpected tool_use_id found in tool_result blocks." My repair script removes the orphaned messages or fixes stop_reason mismatches. Found 35 corruption issues in one session alone (1.8% of records).

**On performance:**
> The architecture has three layers: LightweightDiscoveryService (stat-only, no file reads), FastPathIngestionCoordinator (JIT per-project), and HooverEngine (streaming 1000 lines/batch). Never blocks the main thread. Could probably handle 10k transcripts.

**On Apple Intelligence limitations:**
> FoundationModels is sequential-only. One request in flight at a time. So summarization is viewport-aware, processes what you're looking at first. If content exceeds 4096 tokens or triggers guardrails, it gets tombstoned so we don't retry forever.

---

## Tone Calibration (from HN Research)

**What works on HN:**
- First-person, understated ("I discovered..." not "I invented...")
- Concrete numbers (187ms, 99% recovery, 1000+ transcripts)
- Acknowledge limitations honestly
- Technical specifics without jargon
- "Small world" / serendipity stories

**What to avoid:**
- Superlatives ("incredible", "amazing", "revolutionary")
- Marketing speak ("seamless", "powerful", "cutting-edge")
- Defending against imagined criticism
- Over-explaining obvious things

---

## Best Single Addition

If you add only one thing to the draft, add the **transcript corruption story**. It:

1. Shows real engineering depth (found bug before vendor)
2. Has a satisfying arc (problem -> solution -> vendor fix)
3. Demonstrates domain expertise (parsing thousands of transcripts)
4. Is genuinely interesting to developers
5. Invites follow-up questions

Suggested placement in draft, in "Technical details" section:

```markdown
## Technical details

- SwiftUI (macOS 26 SDK)
- GRDB/SQLite for local storage
- Apple FoundationModels for on-device LLM
- FSEvents for real-time file monitoring
- Parses JSONL transcripts from `~/.claude/projects/` and `~/.codex/sessions/`
- **Found and fixed transcript corruption bugs that caused "resume session" 400 errors. Anthropic's release notes acknowledged the fix a few weeks later.**
```

Or as a separate paragraph after "Why I built this":

> While parsing thousands of transcripts, I found corruption patterns that caused 400 errors when resuming sessions from the web. Wrote a repair script. A few weeks later, Anthropic mentioned making transcript parsing "robust" in their release notes.

---

## Optional: New "Questions for HN"

Replace or supplement the existing questions with more technical ones:

> 1. Has anyone else hit the transcript corruption issue? I can share the repair script.
> 2. Would transcript format documentation be useful? I've reverse-engineered both Claude Code and Codex formats.
> 3. What's your strategy for on-device LLM rate limiting? Apple Intelligence is sequential-only.

---

## Additional Points from Second Recording

### App Store Distribution

**For the main post (brief):**
> Available on the App Store for those with enterprise IT policies that require it. The sandboxing was painful but worth it for accessibility.

**For comment responses:**
> App Store builds require security-scoped bookmarks and an onboarding wizard to request permissions for ~/.claude/ access. Painful to implement, but some corporate environments require App Store distribution. DMG is simpler if you don't have that restriction.

### Future CLI Support

**For the main post:**
> Currently supports Claude Code and Codex CLI. Will add Gemini CLI once it supports local transcripts (open issue). Happy to add others based on demand.

**For comment responses:**
> Gemini CLI doesn't write local transcripts yet. There are GitHub issues requesting it. The parser architecture is pluggable, so adding new CLIs is straightforward once they write structured transcripts.

### Orchestrator Vision (Use Sparingly)

This is future/speculative, so keep it brief. Only mention if someone asks about roadmap:

> Right now it's read-only: view and search your history. Longer term, I see potential for it to act as an orchestrator layer. Cross-CLI context sharing, maybe an MCP server so Claude Code can query its own history ("What did we try last week?"). But that's future work.

### GitHub Issues

**For the main post footer:**
> Bug reports and feature requests: github.com/PeterPym/contextify

**For comment responses:**
> Using a public repo for releases and issues, similar to how Anthropic handles Claude Code. Happy to look at feature requests there.

---

## Updated Summary: What to Add

### Must-add (high value, low word count):
1. **Transcript corruption story** - one sentence in Technical details
2. **GitHub issues link** - already in draft, good

### Consider adding:
3. **App Store mention** - shows commitment to accessibility
4. **Gemini/future CLIs** - shows extensibility, invites requests

### Save for comments:
5. **Queue system details** - too niche for main post
6. **Tombstoning** - interesting but requires explanation
7. **Orchestrator vision** - speculative, save for "what's next" questions

---

## Final Recommended Edit to Draft

In the "Technical details" section, change:

```markdown
- Parses JSONL transcripts from `~/.claude/projects/` and `~/.codex/sessions/`
```

To:

```markdown
- Parses JSONL transcripts from `~/.claude/projects/` and `~/.codex/sessions/`
- Found and fixed transcript corruption bugs that caused "resume session" 400 errors (Anthropic patched this a few weeks later)
```

And in "What other AI coding tools should I support?":

```markdown
3. What other AI coding tools should I support? (Cursor, Aider, Windsurf, Gemini CLI once it has local transcripts?)
```

These are small, factual additions that invite discussion without being salesy.

---

## Development Story (Third Recording)

### The rm -rf Story

**High risk, high reward for HN engagement.** This story will get attention but could derail the thread into AI safety debates.

**If you include it (probably NOT in main post, save for comments):**

> About a third of the way through development, Claude Code rm -rf'd my home directory when I asked it to clean up a build folder. Lost 1.5 days of work. Still run with --dangerously-skip-permissions. The fresh macOS install actually made my M2 faster.

**Why it works on HN:**
- Self-deprecating, honest
- Timely (recent Reddit posts about same issue)
- Shows real stakes / skin in the game
- The "still do it anyway" is very HN contrarian

**Why to avoid in main post:**
- Could completely derail discussion
- Invites pile-on about AI safety
- Distracts from the actual product

**Best use:** Save for when someone asks "how did you build this?" or "any war stories?"

### Python Dev Building macOS App

**For the main post (brief, in "Solo indie project" line):**

> Solo indie project, built in Swift over ~3 months. First macOS app (background in Python/iOS). Happy to answer questions.

**For comment responses:**

> I'm primarily a Python developer. This is my first macOS release. Built most of it without Xcode open, using command-line builds and Claude Code. Only used Xcode for Instruments when profiling the lazy loading.

### No-Xcode Workflow

**For comment responses only (too controversial for main post):**

> Built most of this without Xcode running. Command-line builds via xcodebuild wrapper script, Claude Code for development. Only opened Xcode for Instruments profiling. Controversial, I know, but it worked.

---

## Updated Summary: What to Add

### Must-add (high value, low word count):
1. **Transcript corruption story** - one sentence in Technical details
2. **GitHub issues link** - already in draft, good

### Consider adding:
3. **App Store mention** - shows commitment to accessibility
4. **Gemini/future CLIs** - shows extensibility, invites requests
5. **"First macOS app"** - adds personal story angle

### Save for comments:
6. **Queue system details** - too niche for main post
7. **Tombstoning** - interesting but requires explanation
8. **Orchestrator vision** - speculative, save for "what's next" questions
9. **rm -rf story** - very engaging but could derail, save for war stories question
10. **No-Xcode workflow** - controversial, save for "how did you build this?" question

---

## Final Recommendation

**In main post**, keep it focused on the product. The development stories (rm -rf, no-Xcode, Python background) are great engagement bait but belong in comments where they won't derail the initial impression.

**Suggested addition to closing line:**

Before:
> Solo indie project, built in Swift over ~3 months. Happy to answer questions about the architecture, transcript parsing, or anything else.

After:
> Solo indie project, built in Swift over ~3 months (first macOS app, coming from Python/iOS). Happy to answer questions about the architecture, transcript parsing, or anything else.

This plants the seed for "how did you build this?" questions without front-loading the war stories.
