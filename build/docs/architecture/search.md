# Search Architecture

Technical reference for Contextify's search system.

**Status:** Phase 1 (FTS5) shipped
**Last Updated:** 2025-12-10

---

## Overview

Contextify provides full-text search across conversation history via two surfaces:

- **Quick Search** - Project-scoped, inline in HUD (⌘F)
- **Deep Search** - Cross-project, dedicated window (⌘⇧F)

Both use SQLite FTS5 for lexical search. Future phases add embeddings and semantic search.

---

## Architecture

### Current Implementation (Phase 1)

<!-- TODO: Document actual implementation details -->
<!-- TODO: Add file:line references to key components -->

**Indexing:**
- SQLite FTS5 virtual table on transcript entries
- Indexes user messages and assistant responses
- <!-- TODO: Which columns? content_text? raw JSON? -->

**Query Flow:**
1. User enters search query
2. FTS5 MATCH query against indexed content
3. Results ranked by BM25 relevance
4. Context window (±N messages) fetched for preview
5. Results displayed with highlighting

**Key Components:**

| Component | File | Purpose |
|-----------|------|---------|
| Quick Search View | `Contextify/Contextify/QuickSearchView.swift` | Project-scoped search UI |
| Quick Search ViewModel | `Contextify/Contextify/QuickSearchViewModel.swift` | Search logic, state |
| Deep Search View | `Contextify/Contextify/DeepSearchView.swift` | Cross-project search UI |
| Deep Search ViewModel | `Contextify/Contextify/DeepSearchViewModel.swift` | Multi-project queries |
| Semantic Search View | `Contextify/Contextify/SemanticSearchView.swift` | <!-- TODO: What is this? --> |
| FTS Index | <!-- TODO: Schema location --> | FTS5 virtual table |

### Database Schema

<!-- TODO: Document FTS5 table schema -->
<!-- TODO: Document which migration added search -->

```sql
-- TODO: Add actual schema
CREATE VIRTUAL TABLE transcript_entries_fts USING fts5(
    -- columns here
);
```

---

## Search Surfaces

### Quick Search (HUD)

<!-- TODO: Document activation, behavior, keyboard shortcuts -->

- **Scope:** Current project only
- **Activation:** ⌘F (or click search field)
- **Results:** Inline list replacing timeline content
- **Actions per result:**
  - Copy excerpt
  - Copy for AI (formatted for re-injection)
  - Open in timeline (jump to entry)

### Deep Search (Search Center)

<!-- TODO: Document window behavior, project filtering -->

- **Scope:** All projects (with optional filter)
- **Activation:** ⌘⇧F (or ⌘Enter from Quick Search)
- **Results:** Paginated list with project attribution
- **Features:**
  - Project filter sidebar/dropdown
  - Expanded context preview
  - Cross-project result aggregation

---

## Phased Roadmap

### Phase 1: FTS5 + Context Excerpts (SHIPPED)

- SQLite FTS5 lexical search
- Project-scoped Quick Search
- Cross-project Deep Search
- Context preview (±N messages)
- Copy actions

### Phase 2: Embeddings + Hybrid Ranking (FUTURE)

- Per-entry embeddings table (`transcript_entry_embeddings`)
- Background embedding worker
- Hybrid ranking: BM25 + cosine similarity
- "Summarize this excerpt" action

### Phase 3: Segments & Conversation Cards (FUTURE)

- Transcript segmentation (episodes/topics)
- Segment-level embeddings
- Hierarchical retrieval (segment → message)
- Card-based Deep Search results

---

## Performance Considerations

<!-- TODO: Document indexing performance -->
<!-- TODO: Document query performance characteristics -->
<!-- TODO: Document any caching -->

- FTS5 is highly optimized for full-text queries
- Index updates happen during transcript ingestion
- Large result sets are paginated
- <!-- TODO: Any debouncing on search input? -->

---

## Related Documentation

- **Original Spec:** `build/notes/todo-support/P1-CONVO-SEARCH-spec.md`
- **Implementation Notes:** `build/notes/todo-support/P1-CONVO-SEARCH-implementation.md`
- **Search UX Followup:** `build/notes/todo-support/P2-SEARCH-UX-spec.md`
- **Search Followon Features:** `build/notes/todo-support/P2-SEARCH-FOLLOWON-spec.md`
- **User-facing Help:** `build/docs/design/help-documentation.md` (Search section)

---

## TODOs

- [ ] Fill in actual schema details
- [ ] Add file:line references for key functions
- [ ] Document keyboard shortcuts and their bindings
- [ ] Document search result model structure
- [ ] Document context window sizing
- [ ] Add performance benchmarks
