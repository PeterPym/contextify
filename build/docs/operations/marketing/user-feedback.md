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
