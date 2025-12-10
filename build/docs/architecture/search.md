# Search Architecture

Technical reference for Contextify's search system.

**Status:** Phase 1 (FTS5) shipped
**Last Updated:** 2025-12-10
**Migration:** v28

---

## Overview

Contextify provides full-text search across conversation history via two surfaces:

- **Quick Search** - Project-scoped, inline in HUD (Enter in search field)
- **Deep Search** - Cross-project, dedicated window (⌘Enter from search field)

Both use SQLite FTS5 for lexical search. Future phases add embeddings and semantic search.

**Design Principle:** Contextify's data is append-only transcripts, not mutable code. Embeddings don't go stale, and the "vector index" is just another SQLite table. This makes hybrid search simpler than in tools like Claude Code.

---

## Architecture

### Database Schema (Migration v28)

FTS5 virtual table synced via triggers:

```sql
CREATE VIRTUAL TABLE transcript_entries_fts USING fts5(
    content,
    entry_id UNINDEXED,
    project_id UNINDEXED,
    role UNINDEXED,
    created_at UNINDEXED,
    tokenize = 'unicode61 remove_diacritics 2 separators _'
);
```

**Key details:**
- `separators _` allows `UNREAD_COUNT_UPDATED` to match `unread`, `count`, `updated`
- Only indexes `role IN ('user', 'assistant')` with `display_in_timeline = 1`
- Synced via `AFTER INSERT/UPDATE/DELETE` triggers on `transcript_entries`
- Case-insensitive, diacritic-insensitive (é ≈ e)
- No stemming in Phase 1 (`summary` ≠ `summaries`)

### Search Service

```swift
// app/Sources/ContextifyCore/Search/SearchService.swift

public enum SearchScope: Sendable {
    case project(String)           // Quick Search
    case allProjects               // Deep Search default
    case projects([String])        // Deep Search filtered
}

public struct SearchRequest: Sendable {
    public let query: String
    public let scope: SearchScope
    public let limit: Int          // Capped at 50 per page
    public let offset: Int         // Capped at 5000 max
}

public struct SearchHit: Sendable, Identifiable {
    public let id: String          // entry_id
    public let projectId: String
    public let projectName: String
    public let role: String
    public let content: String
    public let createdAt: Date
    public let rank: Double        // BM25 score
    public let snippet: String     // Highlighted snippet
}
```

### Query Flow

1. User enters search query
2. Query sanitized and converted to FTS5 MATCH syntax
3. FTS5 query with BM25 ranking
4. Results joined with `transcript_entries` for full data
5. Context window fetched for preview (±10 before, up to 19 after)
6. Results displayed with term highlighting

**Key Components:**

| Component | File | Purpose |
|-----------|------|---------|
| Search Service | `app/Sources/ContextifyCore/Search/SearchService.swift` | FTS queries, result models |
| Quick Search View | `Contextify/Contextify/QuickSearchView.swift` | Project-scoped search UI |
| Quick Search ViewModel | `Contextify/Contextify/QuickSearchViewModel.swift` | Search state, actions |
| Deep Search View | `Contextify/Contextify/DeepSearchView.swift` | Cross-project search UI |
| Deep Search ViewModel | `Contextify/Contextify/DeepSearchViewModel.swift` | Multi-project queries |
| FTS Migration | `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` | v28 migration |

---

## Search Surfaces

### Quick Search (HUD)

- **Activation:** Enter in HUD search field (with non-empty query)
- **Scope:** Current project only
- **Results:** Up to 50 hits, inline list replacing timeline content
- **Layout:** Split view - result list (left), context preview (right)

**Mode Bar:**
> Search results for "<query>"
> Project: **Contextify** · 37 matches · **Exit Search** · Deep Search… ⌘⏎

**Actions per result:**
- **Open in Timeline** - Jump to entry, highlight flash
- **Copy Excerpt** - Formatted text with metadata
- **Copy for AI** - Structured block for pasting into new session

**Dismissing:** Exit Search button, Esc, or clear search field

### Deep Search (Search Center)

- **Activation:** ⌘Enter from HUD search field
- **Scope:** All projects (default), with project filter dropdown
- **Results:** Paginated (50 per page), up to 5000 total
- **Layout:** Split view with project attribution per result

**Actions:**
- **Open in HUD** - Switch HUD to result's project, scroll to entry
- **Copy Excerpt / Copy for AI** - Same as Quick Search

---

## Query Syntax

**Supported (Phase 1):**
- Keywords: `foo bar` → messages containing both (AND)
- Phrases: `"unread counts"` → exact phrase match

**Not supported (Phase 1):**
- Named operators (`project:`, `before:`, `after:`)
- These are planned for Deep Search in future phases

---

## Context Excerpts

When displaying a search result, surrounding context is fetched:

```sql
SELECT * FROM transcript_entries
WHERE project_id = :projectId
  AND seq BETWEEN :hitSeq - 10 AND :hitSeq + 19
ORDER BY seq;
```

- Default: ~10 messages before, up to 19 after
- Hard cap: ~30 messages or ~8-10k chars
- Truncation markers shown if more messages exist

### Copy Formats

**Copy Excerpt:**
```
CONTEXTIFY EXCERPT
Project: <project name>
Time range: <start> – <end>
Shown messages: i–j of N

… earlier messages omitted …
[User, 14:21]: ...
[Assistant, 14:23]: ...
… later messages omitted …
```

**Copy for AI:**
```
CONTEXTIFY CONTEXT EXCERPT
Project: <project name>
Time range: <start> – <end>

[User, 14:21]: ...
[Assistant, 14:23]: ...
```

---

## Phased Roadmap

### Phase 1: FTS5 + Context Excerpts (SHIPPED)

- SQLite FTS5 lexical search with BM25 ranking
- Quick Search (project-scoped) and Deep Search (cross-project)
- Context preview with copy actions
- 50 results per page, 5000 max pagination depth

### Phase 2: Embeddings + Hybrid Ranking (FUTURE)

- Per-entry embeddings table (`transcript_entry_embeddings`)
- Background embedding worker using Apple text-embedding model
- Hybrid ranking: `0.4 * BM25 + 0.6 * cosine_similarity`
- "Summarize this excerpt" action (on-device LLM)

### Phase 3: Segments & Conversation Cards (FUTURE)

- `transcript_segments` table with time spans and summaries
- Segment-level embeddings for hierarchical retrieval
- Deep Search becomes card-based (Conversation Cards)
- Project summary table for All Projects view

---

## Performance

- **Pagination caps:** 50 per page, 5000 max offset (prevents runaway queries)
- **FTS5:** Highly optimized for full-text queries
- **Index sync:** Triggers ensure FTS stays in sync with base table
- **Backfill:** Initial migration indexes all existing entries, logged to `system_events`

---

## Historical Context

The search design was informed by HN feedback on chat search UIs (Nov 2025, Onyx launch thread). Key insight: **chat UIs treat history as an afterthought** - users generate valuable context that disappears into unsearchable sidebars. Contextify's value prop is being the search/discovery layer that chat UIs neglect.

---

## Related Documentation

**Archived (Phase 1 shipped):**
- `build/docs/archive/completed-work/convo-search/` - Spec, implementation, addendum

**Active (future phases):**
- `build/notes/todo-support/P2-SEARCH-UX-spec.md` - UX followup items
- `build/notes/todo-support/P2-SEARCH-FOLLOWON-spec.md` - Phase 2/3 features

**User-facing:**
- `build/docs/design/help-documentation.md` (Search section)
