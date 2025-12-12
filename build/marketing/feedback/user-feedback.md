# User Feedback

Collected feedback from users, testers, and reviewers.

---

## Nick Asch - 2025-12-08

**Context:** Pre-launch review of website (contextify.sh)

**Feedback:**
> The last two screenshots are the same I think. Design looks great though on mobile.
> Clear value props. Working with codex and CC is a big one. And local-only AI is the other important part to me.

**Key Takeaways:**
- Duplicate screenshot issue (fixed)
- Design works well on mobile
- **Value props that resonate:**
  1. Works with both Claude Code and Codex
  2. Local-only AI (privacy)

**Action Taken:**
- Fixed duplicate screenshot (Apple Intelligence section now has distinct macOS Tahoe image)
- Updated hero copy to emphasize "private, searchable"
- Added "Your conversations, your control" to privacy section

---

## u/quinncom (Reddit r/MacApps) - 2025-12-10

**Context:** Reply to Contextify launch post

**Feedback:**
> I would love to try this - but it looks like it requires macOS 26? I'm gonna try to stay on macOS Sequoia as long as possible to avoid the liquid ass. :(

> I would be fine without summarization. My main use case would be to search for previous coding sessions by keyword, tag, or directory path.

> Provide an advanced settings option where the user can enter a custom chat completions API URL that points to either a local LLM or a commercial LLM if they decide to use one.

> Another feature that would be important to me - if it doesn't already do this - would be to filter by tag or directory path. I'm a freelancer who works with many different clients, so being able to filter sessions by a client or project name using tags, or just the project's directory path, would be really helpful to narrow down which sessions I'm looking for.

**Key Takeaways:**
- **macOS 15 holdouts exist** - Users avoiding Tahoe ("liquid glass")
- **Search is the core value** - Would use without summaries
- **Freelancer use case** - Multiple clients, needs filtering by client/project
- **Feature requests:**
  1. macOS 15 support without summarization ("lite mode")
  2. Custom LLM API endpoint for summarization
  3. Tags for organizing sessions

**What Already Exists:**
- Directory path filtering (each project tab = directory path)
- Full-text search (within current project)

**Potential Roadmap Items:**
- #LEGACY-MACOS (P2) - Already planned, validates priority bump
- Custom LLM API - New, could be part of #LEGACY-MACOS
- Tags - New feature request, not currently planned

**Reply (posted 2025-12-10):**

> Hey, this is really helpful feedback - thanks for being specific about your use case.
>
> Good news on both fronts:
>
> Directory path filtering - This is exactly how it works now. Each project tab corresponds to a directory path (derived from where you ran Claude Code/Codex). As a freelancer with multiple clients, you'd see each client project as a separate tab.
>
> Search by keyword - Yes, this is already built! Full-text search across your conversation history, within a single project at a time. I have plans to support cross-project search but haven't built it yet.
>
> For macOS 15 support without summarization: this is definitely something I want to do. A "lite mode" (timeline + search, no summaries) would let people start building their searchable history now, then get summaries automatically when they upgrade. I'll bump this up in priority based on your feedback.
>
> The custom LLM API idea is interesting. Have you installed a local llm in the past? I'm wondering if this is something to build all the tooling around like "click here to download the model" i.e. Draw Something or try to fit into a popular existing local LLM install method.
>
> Tags are a new idea I hadn't considered. Could you tell me more about how you'd use them? Would these be manually applied, or auto-generated from something (client name in path, etc.)?

**Status:** Awaiting response on LLM and tags questions

---

## Tom (ifun.de comment) - 2025-12-11

**Context:** Comment on German article about Contextify
**URL:** https://www.ifun.de/fuer-codex-und-claude-code-mac-werkzeuge-zur-lokalen-verwaltung-271052/#comment-997832

**Feedback:**
> Contextify braucht leider macos 26

*(Translation: "Contextify unfortunately requires macOS 26")*

**Key Takeaways:**
- Same concern as u/quinncom - macOS 26 requirement is a barrier
- German-speaking user base exists
- Validates #LEGACY-MACOS priority

**Status:** Pending response - point to Reddit discussion about planned macOS 15 "lite mode" support

---

## Reddit r/ClaudeCode comment - 2025-12-12

**Context:** Reply to older post about Claude Code transcripts (not a Contextify launch post)
**URL:** https://www.reddit.com/r/ClaudeCode/comments/1pjbriy/comment/ntg0mlz/

**Feedback:**
> That's fascinating.
>
> I've been seeing those queue messages and never understood them. Could you explain a little more please? How does it make the call whether to interrupt or not? Is there a separate LLM call to haiku or something with the question "should I interrupt"?
>
> Did you understand where the "summary" items fit in? Sometimes I see a single jsonl file containing summaries for a a load of other sessionIds, sometimes I see a sessions.jsonl containing its own summary, sometimes I see several summary for a single sessionId, sometimes I see none.

**Key Takeaways:**
- **Queue mechanism interest** - Users see queue messages but don't understand them
- **Summary records confusion** - Multiple patterns observed:
  1. Single file with summaries for multiple sessionIds
  2. Session file containing its own summary
  3. Multiple summaries for single sessionId
  4. No summaries at all
- Shows interest in understanding Claude Code internals

**Technical Notes on Summaries (verified):**
- `type: "summary"` records contain `summary` (string) and `leafUuid` fields
- ~16% of transcript files (165/1035) contain summary records
- ~97% appear in the first 10 lines of files, though some appear later
- When multiple summaries exist in one file, each has a different `leafUuid`
- Summary records do NOT have a `sessionId` field

**Reply (posted 2025-12-12):**

> Hey there, the queuing is a big deal--very big differentiator from codex and I don't think it is discussed much.
>
> I am not sure how it makes the call on whether to interrupt but your speculation on some prompting around it seems on target.
>
> I do know that once the message has been processed it is popped from the queue (at least as defined in the transcripts)
>
> This does not necessarily mean that the AI is going to act on the item immediately. In fact, it may complete what its working on and only mention the request. I believe it is possible for the queued item to fall completely through the cracks, though it seems uncommon these days.
>
> I've not looked closely at at summaries, can you tell me more about the single file containing summaries for other sessionIds? is that in ~/.claude/projects/?

**Status:** Posted, awaiting response about the "summaries for other sessionIds" pattern
