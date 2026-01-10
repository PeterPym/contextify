# User Feedback Log

Track notable user feedback, feature requests, and interactions.

---

## u/quinncom (quinn@strangecode.com)

**Source:** Reddit r/MacApps, email
**First Contact:** 2025-12-10

### 2025-12-10: Reddit comment

**Context:** Launch post on r/MacApps

**Feedback:**
- Interested in Contextify but can't use macOS 26 (Tahoe)
- "I would be fine without summarization. My main use case would be to search for previous coding sessions by keyword, tag, or directory path."

**Impact:** Validated demand for #LEGACY-MACOS (pre-Tahoe support with graceful degradation)

### 2025-12-11: Email follow-up

**Request:**
1. Way to be notified of releases (mailing list or GitHub)
2. Interested in macOS Sequoia support

**Response:**
- Pointed to GitHub releases: `github.com/PeterPym/contextify` → Watch → Releases only
- Confirmed pre-Tahoe support is on TODO list ("lite mode" approach)
- Mentioned newsletter is planned but not yet available

---

## Noah Zoschke (noah@housecat.com)

**Source:** HN, then Email
**HN Username:** nzoschke
**First Contact:** 2025-12-15 (HN), 2025-12-26 (email)

### 2025-12-15: HN thread - Team/hosted version request

**Thread:** https://news.ycombinator.com/item?id=46266705 (Ask HN: What Are You Working On?)

**Feedback:**
- "For my small software shop I'd like a team version of this"
- Wants: collect prompts/chats from all devs, store in cloud, summarize into feed/digest
- "A central service. Hosted, secure, frontier model is fine."
- But also: "maybe it starts local with an app like yours anyway. I do a lot of solo hacking I don't want to share with the team too. Then there is some sort of way to push up subsets of data."

**Impact:** First explicit request for hosted/SaaS team version. Suggests hybrid model: local-first with selective cloud sync.

### 2025-12-26: Email follow-up - Sequoia support, schema questions

**Context:** Got Contextify running from DMG on Sequoia, had questions about workflow

**Feedback:**
- Asked about backup frequency for comprehensive history
- Interested in schema stability for building extensions
- Asked about multi-machine setup with iCloud Drive
- Curious about Total Recall CLI

**Response:**
- Explained transcript ingestion catches up on launch (no need to run continuously)
- Recommended backing up source transcript files (`~/.claude/projects/`, `~/.codex/sessions/`)
- Schema at v28, still evolving; recommended Total Recall CLI as stable interface
- Confirmed multi-machine works with shared network location (avoid concurrent access)
- Asked about team workflows and Total Recall experience

**Impact:** Validates interest in:
1. Building on top of Contextify (extension ecosystem)
2. Multi-machine/team use cases
3. Total Recall CLI as stable API surface

---

## Template

```markdown
## [Username/Name]

**Source:** [Reddit/HN/Email/Twitter]
**First Contact:** YYYY-MM-DD

### YYYY-MM-DD: [Brief description]

**Feedback:**
- Point 1
- Point 2

**Impact:** [How this influenced roadmap/decisions]
```
