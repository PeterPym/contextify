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

**Source:** Email
**First Contact:** 2025-12-26

### 2025-12-26: Initial email - Sequoia support, schema questions

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
