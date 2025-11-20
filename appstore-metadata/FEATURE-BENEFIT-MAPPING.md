# Feature-to-Benefit Mapping for Contextify

## Core Value Proposition

**Feature**: Centralized database for ALL AI coding conversations (Claude Code + Codex)

**Benefits**:
1. **Never lose valuable solutions** - Every conversation permanently archived, searchable forever
2. **Build a personal knowledge base** - Accumulate insights and solutions over weeks/months
3. **Search across ALL projects** - Find that solution from 3 months ago, even if it was in a different project
4. **One source of truth** - No more hunting through terminal scrollback or trying to remember which project had that conversation
5. **Backup and sync** - Database can live in Dropbox/iCloud Drive for automatic backup and multi-machine access

**User Story**: "I remember solving this authentication bug 2 months ago in a different project, but can't remember the details. Let me search Contextify... found it in 5 seconds."

---

## Feature 1: Unified Claude Code + Codex Support

**Feature**: Monitors BOTH ~/.claude/projects/ AND ~/.codex/sessions/ simultaneously

**Benefits**:
1. **Unified timeline** - See all conversations chronologically regardless of which tool you used
2. **Tool-agnostic workflow** - Switch between Claude Code and Codex without losing context
3. **Compare approaches** - See how different tools solved the same problem in past sessions
4. **Future-proof** - As new AI coding tools emerge, Contextify can adapt (not locked into one tool)
5. **Team collaboration** - Some team members use Claude Code, others Codex - everyone's conversations visible

**User Story**: "Started debugging in Claude Code this morning, switched to Codex after lunch. Contextify shows me the entire day's work in one timeline, not fragmented across two tools."

---

## Feature 2: Real-time Conversation Monitoring

**Feature**: Watches transcript files and updates timeline as conversation progresses

**Benefits**:
1. **Live status updates** - See at a glance what the AI is currently doing ("Implementing authentication", "Running tests")
2. **No manual refresh** - Timeline updates automatically, you never miss an update
3. **Catch errors early** - See if the AI went down a wrong path before it completes
4. **Parallel context** - Monitor AI session in Contextify while coding in your editor
5. **Async awareness** - Know what's happening even if you step away from terminal

**User Story**: "I asked Claude to refactor 5 files. Instead of watching terminal scroll, I glance at Contextify's timeline to see progress. 'Refactoring auth.ts... Complete. Refactoring user.ts... In progress.'"

---

## Feature 3: AI-Powered Timeline Summaries

**Feature**: LLM generates intelligent summaries of conversation segments

**Benefits**:
1. **Instant comprehension** - Understand a 2-hour conversation in 30 seconds
2. **Quick navigation** - "Where did we implement error handling?" - find it instantly via summary
3. **Reduce cognitive load** - Don't re-read entire conversations to remember what happened
4. **Handoff documentation** - Show team members what you accomplished without exporting transcripts
5. **Decision tracking** - Summaries highlight key decisions made during development

**User Story**: "After a 3-hour pairing session with Claude Code, I need to remember what we decided about the database schema. Contextify's summary shows: 'Decided to use UUID primary keys, implemented soft deletes, added created_at/updated_at timestamps.'"

---

## Feature 4: Project-Centric Organization

**Feature**: Automatically detects and organizes conversations by project

**Benefits**:
1. **Zero configuration** - No manual setup, Contextify discovers projects automatically
2. **Instant project context** - Switch projects, see that project's conversation history immediately
3. **Isolation** - Work conversations don't pollute personal project history
4. **Git integration** - Knows which branch each conversation happened on
5. **Multi-repo workflows** - Work on 10 projects, Contextify keeps them all organized

**User Story**: "I work on 8 client projects. Contextify auto-detects each one. When client X calls with a question about their project, I switch to that project in Contextify and see exactly what we discussed 2 weeks ago."

---

## Feature 5: Transcripts (Session Browser)

**Feature**: Browse ALL past conversations across all projects

**Benefits**:
1. **Historical access** - Review any past session, even from months ago
2. **Session metadata** - See duration, message count, provider (Claude/Codex) at a glance
3. **Cross-project search** (future) - "I solved CORS issues somewhere... which project was it?"
4. **Audit trail** - Know exactly when you worked on what
5. **Learning resource** - Review how you approached similar problems in the past

**User Story**: "My coworker asks 'How did you implement that caching layer?' I open Transcripts, filter by 'caching', find the session from 6 weeks ago, and share the approach."

---

## Feature 6: Drag & Drop File/URL Ingestion

**Feature**: Drop files or URLs into Contextify to create timestamped Markdown artifacts

**Benefits**:
1. **Instant context capture** - Save important files/links without leaving your workflow
2. **Timestamped history** - Know when you saved each resource
3. **No manual organization** - Files automatically associated with current project/session
4. **URL metadata extraction** - Contextify pulls title/description from URLs automatically
5. **Markdown output** - Artifacts saved as readable Markdown, not proprietary format

**User Story**: "Found a critical Stack Overflow answer during debugging. Drag URL into Contextify. 3 months later, revisiting the same bug, the solution is right there in the project's artifact history."

---

## Feature 7: Timeline Caching (Performance)

**Feature**: Caches timeline summaries to avoid re-generating on every startup

**Benefits**:
1. **Instant startup** - Open Contextify, see timeline immediately (not "Generating...")
2. **Reduced API costs** - 1-2 LLM calls instead of 20-50 on startup
3. **Offline capability** - View cached timelines even without internet/API access
4. **Battery life** - Less CPU usage from constant LLM calls
5. **Snappy UX** - Switch between projects with zero lag

**User Story**: "Before timeline caching: Open Contextify, wait 30 seconds while it generates summaries. After: Open Contextify, timeline appears instantly. Startup feels 10x faster."

---

## Feature 8: Git Branch Awareness

**Feature**: Automatically detects git repository and current branch for each conversation

**Benefits**:
1. **Context preservation** - Know which branch you were on during each conversation
2. **Debugging aid** - "This bug was introduced on feature/auth branch, let me see what we did there"
3. **Worktree support** - Works even with complex git worktree setups
4. **Branch switching** - See conversation history change as you switch branches
5. **Code review prep** - Review AI conversations alongside code changes before PR

**User Story**: "PR reviewer asks 'Why did you implement it this way?' I show them the Contextify conversation from that feature branch where Claude and I discussed the tradeoffs."

---

## Feature 9: Custom Database Locations

**Feature**: Store database in default location, Dropbox, iCloud Drive, or custom path

**Benefits**:
1. **Multi-machine sync** - Work on MacBook and iMac, same conversation history everywhere
2. **Backup peace of mind** - Database in Dropbox = automatic backup
3. **Storage control** - Put database on external drive if needed
4. **Privacy control** - Keep database local if you don't want cloud sync
5. **Team sharing** (advanced) - Share database via network drive for team visibility

**User Story**: "I store my Contextify database in iCloud Drive. Work on a bug at the office on my iMac, continue at home on my MacBook - full conversation history available on both machines automatically."

---

## Feature 10: Sandboxed Security Model

**Feature**: Security-scoped bookmarks for safe file access in App Store builds

**Benefits**:
1. **App Store distribution** - Can distribute via Mac App Store (more trust/visibility)
2. **System security** - macOS sandbox prevents unauthorized file access
3. **User control** - You explicitly grant access to transcript directories
4. **Revocable permissions** - Can revoke access anytime via System Settings
5. **Future compliance** - Ready for stricter macOS security requirements

**User Story**: "I don't trust random developer tools with full disk access. Contextify uses sandboxing - I grant access ONLY to ~/.claude and ~/.codex directories, nothing else."

---

## Missing Features / Future Enhancements (NOT in v1.0)

These should NOT be in App Store description yet:

1. **Full-text search** - Database exists but search UI not yet built
2. **User-created checkpoints** - Infrastructure exists but not exposed in UI
3. **Export to various formats** - Markdown artifacts yes, but not PDF/HTML/etc
4. **RAG/semantic search** - Mentioned in plans but not implemented
5. **Multi-user collaboration** - Database is single-user currently
6. **Integrations** - No Slack/Discord/Notion integrations yet

---

## Revised App Store Messaging Focus

**Primary Benefits to Emphasize:**

1. **Never lose context** (centralized archive)
2. **Unified Claude + Codex support** (tool-agnostic)
3. **Instant comprehension** (AI summaries)
4. **Zero configuration** (automatic project detection)
5. **Always available** (persistent timeline, offline caching)

**Secondary Benefits:**

6. **Multi-machine sync** (custom database locations)
7. **Privacy-first** (local storage, optional cloud sync)
8. **Performance** (timeline caching)
9. **Git integration** (branch awareness)
10. **Artifact capture** (drag & drop ingestion)

---

## Recommended Description Structure

1. **Hook**: Never lose track of AI coding conversations across projects and tools
2. **Primary Benefit**: Centralized searchable archive of ALL your Claude Code and Codex sessions
3. **Unified Support**: Works with both tools simultaneously, unified timeline
4. **AI Intelligence**: Intelligent summaries help you comprehend hours of conversation in seconds
5. **Zero Config**: Automatically detects projects, git branches, conversation sessions
6. **Always Available**: Timeline caching means instant startup, works offline
7. **Your Control**: Data stays on your Mac, optional sync via iCloud/Dropbox
8. **Features**: Real-time monitoring, file ingestion, session browser, git integration

---

## Key Phrases to Include

- "Never lose valuable solutions from past AI conversations"
- "Unified view of Claude Code and Codex sessions"
- "Search across all projects, not just your current one"
- "Build a personal knowledge base of AI insights over time"
- "See exactly what you discussed weeks or months ago"
- "Multi-machine sync via iCloud Drive or Dropbox"
- "Works with both Claude Code and Codex simultaneously"
- "Automatic project detection - zero configuration required"
