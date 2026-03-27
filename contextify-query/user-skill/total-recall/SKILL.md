---
name: total-recall
description: Use this skill when the user wants to search prior conversations, recover earlier decisions, verify what was discussed before, or find where a topic was discussed. https://contextify.sh
---

# Contextify Total Recall

Search conversation history to find past decisions, solutions, and discussions.

**Command:** `contextify` (one word, no hyphen). Legacy `contextify-query` still works.

## Do this by default

1. Check database: `contextify status --json`
2. Build an **entity-first** query (see below)
3. Search:
   ```bash
   contextify search "<query>" --days 365 --limit 10 --snippet-tokens 100 --json
   ```
   For repo-scoped debugging only, add `--project .` and use `--days 30`.
4. If the snippet already contains the answer (names, numbers, dates), cite it and stop.
5. If the snippet is truncated or you need surrounding discussion, fetch context for the top 1-2 hits:
   ```bash
   contextify context "<entry-id>" --before 5 --after 15 --json
   ```
6. If 0 results, follow the zero-result protocol (below).
7. Format response with citations.

## Output format

Begin with:
> **Contextify Total Recall**

Then provide findings with specific details, names, numbers, and entry IDs.

## Trigger phrases

- "use total recall to..."
- "search our conversation history"
- "find where we discussed..."
- "what did we decide about..."
- "look back in past sessions"

## Preconditions

Check CLI: `command -v contextify`

If missing:
> Contextify CLI not found.
> **DMG users:** Open Contextify -> Settings -> CLI -> "Install/Repair CLI"
> **App Store users:** Run `brew install PeterPym/contextify/contextify-query`
> https://contextify.sh/help

## Query construction

### 1. Preserve rare entities first

The most important rule: **keep rare names and noun phrases exactly as they appear.** Only expand common verbs and concepts after that.

- Proper nouns, product names, people: use as-is or quoted
- Task IDs, version numbers: quote them (`"ct 389"`, `"v1.5.0"`)
- Common verbs: expand with prefix matching (`deploy*`)

**Examples:**

```bash
# Named entity + topic
contextify search "\"Perch Innovations\" AND Delaware AND \"franchise tax\"" --days 365 --limit 10 --snippet-tokens 100 --json

# Product with stack terms
contextify search "\"contextify cloud\" AND (fastapi OR postgres* OR backend)" --days 365 --limit 10 --snippet-tokens 100 --json

# Task ID + keywords
contextify search "\"ct 389\" AND (release OR launch OR plan)" --days 365 --limit 10 --snippet-tokens 100 --json

# Person + topic
contextify search "\"Justin George\" AND (license OR pricing)" --days 365 --limit 10 --snippet-tokens 100 --json

# Simple distinctive terms
contextify search "\"paperbark maple\"" --days 365 --limit 10 --snippet-tokens 100 --json
```

### 2. Handle special characters

FTS5 treats hyphens, underscores, and dots as token separators. The CLI auto-handles simple cases, but in complex queries you must rewrite manually:

| Input | Rewrite to | Why |
|-------|-----------|-----|
| `cli-ai-setup` | `"cli ai setup"` | Hyphens split tokens |
| `ct-361` | `"ct 361"` | Task ID |
| `UNREAD_COUNT` | `"UNREAD COUNT"` | Underscores split tokens |
| `v1.5.0` | `"v1.5.0"` | Quote dotted terms |

### 3. Expand common terms only

For verbs and common nouns, use prefix matching:
```
deploy*          # matches deploy, deployed, deployment, etc.
(fail* OR error* OR broke*)
```

Do NOT expand proper nouns or named entities. Do NOT add synonyms for literal word searches.

### 4. Choose parameters by intent

| Intent | `--days` | `--project` | `--limit` | Notes |
|--------|----------|-------------|-----------|-------|
| Lookup | 365 | omit | 10 | Most common case |
| Exploratory | 365 | omit | 20 | Start broad |
| Debugging | 30 | `--project .` | 10 | Recent, repo-scoped |
| Counting | 365 | as needed | use `--count-only` | Add `--term-counts` for OR queries |
| Negative proof | 365 | omit | 10 | Run 2-3 variations |

**Default to `--days 365` and no `--project` flag.** Only add `--project .` for clearly repo-scoped debugging.

## Zero-result protocol

When search returns 0 results:

**Retry 1:** Widen scope. Remove `--project` if set. Use `--days 365`. Simplify to the 1-2 rarest terms.

**Retry 2:** Try alternative phrasing. Use prefix matching (`term*`), try related terms, or decompose multi-word queries.

**Then stop** and report: "Searched [days] days across [scope] with queries: [list]. No results found."

## When to fetch context vs use snippets

- **Use the snippet** if it already contains the specific answer (a name, number, date, decision, or quote).
- **Fetch context** only when: the snippet is truncated and you need the full text, the answer depends on the surrounding discussion, or you need to understand why a decision was made.
- Context costs a turn. With `--snippet-tokens 100`, snippets often suffice.

## Data model

- **Project:** A codebase directory (maps 1:1 with a git repo)
- **Transcript:** One conversation session within a project
- **Entry:** One message (user/assistant/system) with `id`, `kind`, `content`, `timestamp`

Search returns entries. Use `id` for context lookups. `projectId` is opaque.

## JSON output format

All responses: `{"data": ..., "schemaVersion": 1, "type": "..."}`.
Errors: `{"type": "error", "code": "...", "message": "..."}`.

Read JSON directly. Do not pipe through `jq` or `python3`.

- **search**: `data` is an array. Pagination in `metadata` (`totalCount`, `hasMore`, `offset`).
- **context**: `data` is an object with `before`, `anchor`, `after`. Pagination in `meta`.
- **entry**: `data` is an object with `entry` and `projectName`.
- **status**: `data` is an object with database stats.

## Error handling

| `code` | Response |
|--------|----------|
| `dbNotFound` | "Database not found. Open Contextify to initialize." |
| `dbProjectNotFound` | Check `details.suggestions`, offer alternatives |
| `featureUnavailable` | Explain limitation clearly |
| `entryNotFound` | Re-search for a new anchor |

## Delegating to researcher agent

**Claude Code only:** For complex multi-query searches, delegate to `contextify-researcher`:
```
Use the contextify-researcher agent to thoroughly search for [topic]
```

**Codex CLI:** Run multiple searches manually.

---

## Reference: Advanced flags

### Counting
| Flag | Description |
|------|-------------|
| `--count-only` | Returns only `totalCount`, empty `data` array |
| `--term-counts` | Per-term match counts for OR queries |

### Filtering
| Flag | Description |
|------|-------------|
| `--kinds <csv>` | Filter by entry kind: `user`, `assistant`, `system` |
| `--since <ts>` | Time range start. Cannot combine with `--days`. |
| `--until <ts>` | Time range end. |
| `--include-hidden` | Include non-timeline entries |
| `--transcript-id <id>` | Scope to a specific transcript |

### Content
| Flag | Description |
|------|-------------|
| `--full-content` | Disable 2KB truncation (context/entry only) |
| `--no-content` | Metadata only |
| `--snippet-tokens <n>` | Snippet length (default 50, max 100) |

### Context window
| Flag | Description |
|------|-------------|
| `--before <n>` | Entries before anchor (default 10) |
| `--after <n>` | Entries after anchor (default 20) |

### Scope
| Flag | Description |
|------|-------------|
| `--project <name-or-path>` | Scope by project name, path, or `.` for cwd |
| `--project-id <id>` | Scope by UUID (bypasses worktree expansion) |
| `--db-path <path>` | Custom database location |

## Reference: Worktree expansion

When `--project .` is used in a git worktree, search auto-expands across sibling worktrees. Control with:
- `--this-worktree` to suppress expansion
- `--exclude wb1,wb2` to exclude specific worktrees
- `--project-id` to bypass expansion entirely

## Reference: Additional subcommands

| Subcommand | Description |
|-----------|-------------|
| `activity` | Recent timeline entries |
| `transcripts` | List transcripts for a project |
| `stats` | Project statistics |
| `summaries` | LLM-generated transcript summaries |
| `doctor` | CLI installation health check |
| `projects` | List all known projects with names and paths |
