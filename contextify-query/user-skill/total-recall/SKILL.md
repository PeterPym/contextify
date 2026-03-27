---
name: total-recall
description: Contextify Total Recall - Search past conversations and decisions with your AI. https://contextify.sh
---

# Contextify Total Recall

Search your conversation history to find past decisions, solutions, and discussions.

## IMPORTANT: Command Format

**The CLI command is `contextify` (one word, no hyphen).**

- Correct: `contextify search "my query"`
- Correct: `contextify status --json`
- **WRONG:** `contextify query search` (no `query` subcommand)

The legacy name `contextify-query` still works (backwards-compatible symlink) but `contextify` is the canonical command.

Always use the exact commands shown in this skill file. Do not improvise command formats.

## Output Format

Begin your response with:

> **Contextify Total Recall**

Then provide the search results with citations.

## Trigger phrases

- "use total recall to..."
- "search our conversation history"
- "find where we discussed..."
- "what did we decide about..."
- "look back in past sessions"
- "remember when we talked about..."

## Preconditions

This skill requires the Contextify app and CLI.
It works with Claude Code and Codex CLI.

1) Check CLI availability:

```bash
command -v contextify
```

2) If `contextify` is missing:

**Error response:**
> Contextify CLI not found.
>
> **DMG users:** Open Contextify -> Settings -> CLI -> "Install/Repair CLI"
>
> **App Store users:** Run `brew install PeterPym/contextify/contextify-query` (installs as `contextify`)
>
> For help: https://contextify.sh/help

## Data model

Contextify organizes conversations into three levels:

- **Project:** A codebase or working directory (e.g., `~/code/my-app`). Maps 1:1 with a git repo or folder.
- **Transcript:** A single conversation session within a project. Each time you start a new Claude Code or Codex session, a new transcript is created.
- **Entry:** One message within a transcript. Each user prompt, assistant response, or system message is an entry with a `kind` (user/assistant/system), `content`, and `timestamp`.

Search results return entries. Use `transcriptId` to see the full conversation, `projectId` to scope by codebase.

## FTS5 search behavior

The Contextify search backend currently uses FTS5 with **exact token matching** and no stemming.

- `"run"` matches only the exact token "run", NOT "running", "runs", or "ran"
- `"deploy"` does NOT match "deployment" or "deployed"
- Searches are case-insensitive
- The prefix operator `*` matches token prefixes: `run*` matches "run", "running", "runs", "runner"
- Quoted phrases match exact sequences: `"memory leak"` requires both words adjacent in order

**Tokenization and special characters:** Hyphens, underscores, and most punctuation act as token separators. For example, `CT-97` is tokenized as two separate tokens `CT` and `97`. To match hyphenated or snake_case identifiers, search for `CT AND 97` or try the quoted form `"CT 97"`. File paths and punctuation-heavy identifiers may need simplified forms.

Because there is no stemming, you must explicitly include morphological variants in your queries. See "Query construction" below.

## Query construction

Before searching, analyze the user's request and build an effective query.

### Priority rule: entities first

Preserve rare names and identifiers exactly. Only expand common verbs and concepts.

- **Proper nouns, people, companies, products**: use as-is or in quoted phrases (`"Perch Innovations"`, `"Fulton House"`)
- **Task IDs, version numbers**: quote them (`"ct 389"`, `"v1.5.0"`)
- **Hyphenated project names**: quote without hyphens (`"contextify cloud"`, `"cli ai setup"`)
- **Common verbs**: expand with prefix matching (`deploy*`, `migrat*`)

Start your search with the 2-3 most distinctive terms from the question. If the question mentions a specific name, number, or identifier, that should be your primary search term, not a generic concept.

### Step 1: Classify intent

Determine the query type to set your strategy and starting `--days` window:

| Intent | Signals | Starting `--days` | Strategy |
|--------|---------|-------------------|----------|
| **Counting** | "how many", "count", "every time", "frequency" | 365 | Use `--count-only`. Add `--term-counts` for OR queries. |
| **Lookup** | "what did we decide", "find the discussion", "when did we" | 365 | Balanced. Use quoted phrases for precision. Default `--limit 10`. |
| **Exploratory** | "what have we talked about", "find anything about" | 365 | Start broad, refine iteratively. Use `--limit 20`. |
| **Negative proof** | "have we ever", "did we discuss", "was there any" | 365 | Broad scope. Run 2-3 materially different query variations before declaring absence. |
| **Debugging** | "when did this break", "what changed", "recent error" | 30 | Narrow, recent. Use `--project .` for current repo focus. |

**Counting note:** Counts refer to matched entries (messages), not individual word occurrences within those entries. Use `--count-only` to get `totalCount` without fetching result bodies. For OR queries, add `--term-counts` to get per-term breakdowns. Apply `--days` and `--project` filters as needed.

### Step 1.5: Check for special characters

Before building the query, scan each search term for characters that FTS5 treats as token separators. The CLI auto-handles common cases (F-02), but verify your query terms are clean:

| Character | Example | Rewrite to |
|-----------|---------|------------|
| Hyphen `-` | `cli-ai-setup` | `"cli ai setup"` (quoted phrase without hyphens) |
| Hyphen `-` in task ID | `ct-361`, `bl-42` | `"ct 361"` (quoted phrase) |
| Underscore `_` | `UNREAD_COUNT` | `"UNREAD COUNT"` (quoted phrase without underscores) |
| Dot `.` | `v1.5.0` | `"v1.5.0"` (quote the whole term) |

**When to apply:** Always scan your query terms before Step 2. If any term contains hyphens, underscores, or dots, rewrite it using the table above. Note the reformulation in your response so the user knows what was searched.

**The CLI now auto-rewrites bare hyphenated tokens** (e.g., `review-loop` becomes `"review loop"`), but this only works for simple queries without FTS5 operators. When you construct complex queries with OR/AND, you must handle special characters yourself.

### Step 2: Expand query terms

For each key term, generate morphological variants and join with OR:

**Verb example:** "deploy"
```
deploy OR deploys OR deployed OR deploying OR deployment OR deployments
```

**Shortcut -- prefix matching:** When variants share a common prefix, use `*`:
```
deploy*
```
This matches deploy, deploys, deployed, deploying, deployment, deployments.

**When to use explicit OR vs prefix `*`:**
- Prefix `*` is simpler and catches variants you might not think of
- Explicit OR is better when the stem is ambiguous (e.g., `run*` also matches "rune", "rung")
- Explicit OR is required for irregular forms (e.g., "ran" is not matched by `run*`)
- For counting queries, start with explicit OR plus any irregular forms, then use a prefix query as a recall backstop if counts look low

**Compound queries:** Combine expanded terms with AND when the user's query has multiple concepts:
```
(deploy* OR release*) AND (fail* OR error* OR broke*)
```

### Step 3: Consider synonyms and related terms

For conceptual searches (not word-counting), add synonyms:
```
"memory leak" OR "out of memory" OR OOM OR "memory pressure"
```

Do NOT add synonyms for literal word searches ("how many times did I say X").

### Step 4: Adjust parameters to intent

- **Counting queries:** Use `--count-only` (and `--term-counts` for OR queries). No `--limit` or pagination needed.
- **Lookup queries:** `--limit 10` is fine for finding an anchor.
- **Exploratory queries:** `--limit 20`, then refine.

**Quick recipe:** Classify intent, build expanded query, choose limit (or `--count-only`), search, paginate if `hasMore`, answer with citations.

## Canonical loop

1) Confirm database availability:

```bash
contextify status --json
```

Returns:
```json
{
  "data": {
    "databasePath": "/Users/.../contextify.db",
    "entryCount": 315465,
    "projectCount": 46,
    "transcriptCount": 3285,
    "ftsEnabled": true,
    "summariesEnabled": true
  },
  "schemaVersion": 1,
  "type": "status"
}
```

Real output may include additional fields (e.g., `appSchemaVersion`). Ignore unknown keys.

If database not found, respond:
> Contextify database not found.
>
> Please open Contextify once to initialize the database.
>
> Download: https://contextify.sh/download

2) Construct query and search:

Build your query following the "Query construction" section above, then search:

```bash
contextify search "<expanded-query>" --days 365 --limit <N> --snippet-tokens 100 --json
```

For repo-scoped debugging, add `--project .` and use `--days 30` instead.

When the request references files, commands, skills, symbols, versions, or a narrow implementation detail, prefer git-anchored search first:

```bash
contextify search "<expanded-query>" --days 365 --limit <N> --snippet-tokens 100 --anchor-git --json
```

Git anchoring is additive, not exclusive:
- if the CLI reports it found git anchors, use that ranking signal
- if it reports no strong commit signal, continue with normal broad search
- do not stop exploring just because the git path was attempted

Set `--limit` based on intent: 10 for lookup, 20 for exploratory. For counting, use `--count-only` instead (no `--limit` needed).

**Search query syntax (FTS5):** Use `OR`, `AND`, `NOT` operators, quoted phrases for exact sequences, and `*` for prefix matching. Use parentheses when mixing AND/OR to control grouping; do not rely on default operator precedence.

Example -- user asks "how many times have I mentioned deploying":
```bash
contextify search "deploy OR deploys OR deployed OR deploying OR deployment" --project . --days 365 --count-only --term-counts --json
```

Example -- user asks "what did we decide about the database schema":
```bash
contextify search "\"database schema\" OR \"schema migration\" OR \"schema change\"" --project . --days 90 --limit 10 --json
```

Returns:
```json
{
  "data": [
    {
      "id": "e897a104-...",
      "contentSnippet": "...matched text with context...",
      "contentTruncated": true,
      "kind": "assistant",
      "score": -12.34,
      "timestamp": 1769380895,
      "projectName": "my-project",
      "projectId": "AB12CD34-...",
      "transcriptId": "5F9816DE-...",
      "provider": "claude.code"
    }
  ],
  "metadata": {
    "returned": 10,
    "limit": 10,
    "offset": 0,
    "hasMore": true,
    "totalCount": 847
  },
  "schemaVersion": 1,
  "type": "search"
}
```

**Important:** `data` is a flat array of results. Each result's `id` is the UUID you pass to the `context` command. `projectId` is an opaque string (format varies). `score` is an internal ranking value; treat it as opaque. Results are already returned in best-first order; do not re-sort. If `contentTruncated` is `true`, always fetch full content via `context` (preferred) or `entry`.

**Metadata fields:** `returned`, `limit`, `offset`, `hasMore`, and `totalCount` are always present. Optional fields appear conditionally:
- `termCounts`: per-term match counts (when `--term-counts` used with an OR query)
- `worktreeExpansion`: worktree group details (when worktree expansion is active, see "Worktree expansion" below)
- `sourceCounts`: per-project result counts (when worktreeExpansion is present)

**Count-only example** (for counting queries):
```bash
contextify search "deploy OR deploys OR deployed OR deploying OR deployment" --project . --days 365 --count-only --term-counts --json
```

Returns:
```json
{
  "data": [],
  "metadata": {
    "totalCount": 847,
    "termCounts": {
      "deploy": 312,
      "deployed": 201,
      "deploying": 98,
      "deployment": 187,
      "deploys": 49
    }
  },
  "schemaVersion": 1,
  "type": "search"
}
```

With `--count-only`, `data` is always an empty array. Only `totalCount` (and optionally `termCounts`) appear in metadata. No pagination is needed.

If `--project .` returns a `dbProjectNotFound` error, retry without `--project` (omit it entirely) to search all projects. If you need a specific project, run `contextify projects --json` which returns a `data` array of objects with `name` and `rootPath` fields, then pass `--project <name>`.

Anchor selection guidance:

- Prefer older transcripts unless the user asked about the current chat session.
- If `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` is set, down-rank hits from that transcript unless the user explicitly wants current session results.

3) Decide whether to fetch context or use the snippet:

**Use the snippet directly** if it already contains the specific answer: a name, number, date, decision, or quote. With `--snippet-tokens 100`, snippets often contain enough detail.

**Fetch context** when: the snippet is truncated and you need the full text, the answer depends on surrounding discussion or rationale, or pronouns/references need resolution.

```bash
contextify context "<entry-uuid>" --before 10 --after 20 --json
```

Returns:
```json
{
  "data": {
    "before": [
      { "id": "...", "kind": "user", "content": "...", "timestamp": 1769380791,
        "createdAt": 1769380791, "provider": "claude.code" }
    ],
    "anchor": {
      "id": "e897a104-...", "kind": "assistant", "content": "full text here...",
      "timestamp": 1769380895, "createdAt": 1769380895,
      "transcriptId": "...", "projectId": "...", "provider": "claude.code"
    },
    "after": [
      { "id": "...", "kind": "user", "content": "...", "timestamp": 1769380900,
        "createdAt": 1769380900, "provider": "claude.code" }
    ],
    "meta": {
      "transcriptEntryCount": 75,
      "hasMoreBefore": true,
      "hasMoreAfter": false
    }
  },
  "schemaVersion": 1,
  "type": "context"
}
```

**Important:** `data` is an object with `before` (array), `anchor` (object), and `after` (array). The `before` array is in chronological order. Read the entries directly from the JSON; do not pipe through `jq` or write parsers.

4) If a snippet is too short and you need the full entry:

```bash
contextify entry "<entry-uuid>" --json
```

Returns:
```json
{
  "data": {
    "entry": {
      "id": "...", "kind": "assistant", "content": "full untruncated text...",
      "timestamp": 1769380895, "createdAt": 1769380895,
      "transcriptId": "...", "projectId": "...", "provider": "claude.code"
    },
    "projectName": "my-project"
  },
  "schemaVersion": 1,
  "type": "entry"
}
```

5) Validate results before answering:

Before formatting your response, check:

- **`hasMore` flag:** If `true`, you have not retrieved all matches. For lookup/exploratory queries needing more results, paginate with `--offset`:
  ```bash
  contextify search "<expanded-query>" --project . --limit 20 --offset 20 --json
  ```
  Increment `--offset` by `--limit` each page until `hasMore` is `false`.
- **`totalCount` field:** Always present in search metadata. Use this to know the total number of matches without paginating. For counting queries, use `--count-only` instead of paginating.
- **(Counting intent only) Variant coverage:** If `--term-counts` shows uneven distribution, consider whether you missed a variant. If you searched `deploy*` and a follow-up search for "redeployment" returns additional hits, your prefix did not capture it.
- **Result volume sanity check:** If a counting query returns fewer results than expected, re-examine your query. Did you miss an irregular form? A synonym?
- **For counting queries:** Report `totalCount` from metadata (or per-term counts from `termCounts`), and list which search terms were used so the user can judge completeness.

If results seem incomplete, run additional searches with expanded terms before answering.

6) Format response:

> **Contextify Total Recall**
>
> **Found:** [brief summary of what was found]
>
> **From:** [date/time and project context]
>
> [Key excerpts with citations]
>
> **Entry ID:** `<uuid>` (for reference)

For counting queries, also include:
> **Search terms used:** [list the OR-expanded terms]
> **Matched entries:** [totalCount from metadata] entries
> **Per-term breakdown:** [if --term-counts was used, show each term's count]

## Working with the JSON output

**Successful responses** return `{"data": ..., "schemaVersion": 1, "type": "..."}`. **Errors** return `{"type": "error", "code": "...", "message": "...", "details": ...}`. Read the JSON output directly. You do not need to pipe it through `python3`, `jq`, or any other tool. You are capable of reading and interpreting JSON natively.

- **search**: `data` is an **array** of result objects; pagination info in `metadata`
- **context**: `data` is an **object** with `before`, `anchor`, `after`; pagination info in `meta` (note: name differs from search)
- **entry**: `data` is an **object** with `entry` and `projectName`
- **status**: `data` is an **object** with database stats

Common entry fields: `id` (UUID), `kind` (user/assistant/system), `content`, `timestamp` (Unix), `projectId`, `transcriptId`, `provider` (claude.code/codex).

## Error handling

Error responses have `"type": "error"` and a `code` field:
```json
{
  "code": "dbNotFound",
  "details": null,
  "message": "Database not found at expected location",
  "type": "error"
}
```

`details` may be `null` or an object with additional context (e.g., `details.suggestions` for `dbProjectNotFound`).

Branch on `code`:

| `code` | Response |
|-------|----------|
| `dbNotFound` | "Contextify database not found. Open Contextify to initialize. https://contextify.sh/download" If the user has a custom database location (Dropbox, iCloud Drive), use `--db-path <path>` or `--db-dir <dir>`. |
| `dbProjectNotFound` | Check `details.suggestions`, offer alternatives |
| `featureUnavailable` | Explain limitation clearly, do not imply workarounds |
| `entryNotFound` | Re-search for a new anchor |
| `cliNotFound` | "Contextify CLI not found. See https://contextify.sh/help for installation." |

## Zero-result protocol (mandatory)

This protocol is **mandatory** before declaring "not found." Skipping steps is a skill violation.

When search returns 0 results, follow this escalation path in order. Stop as soon as you get results:

**Step 1: Widen the time window.**
- If `--days` was < 90, retry with `--days 90`
- If `--days` was < 365, retry with `--days 365`
- If already at 365 or no `--days` was set, proceed to Step 2

**Step 2: Broaden query terms.**
- Try prefix matching: `deploy*` instead of `deploy`
- Simplify: reduce to the 1-2 most distinctive terms
- Check for special characters (Step 1.5) that may need quoting

**Step 3: Broaden project scope.**
- If using `--project .`, retry without `--project` (search all projects)
- Skip this step for clearly repo-scoped debugging queries

**Step 4: Try alternative terms.**
- Use synonyms or related phrasings
- For hyphenated identifiers, try both the quoted phrase form and the individual tokens

**Step 5: Only now declare "not found."**
Report what you searched: "Searched [N] days across [scope] with queries: [list]. No results found."

### Partial or suspicious results

If results are returned but may be incomplete:
1. **Check `totalCount` and `hasMore`:** `totalCount` tells you the full count. If you need more result bodies, raise `--limit` or paginate with `--offset`.
2. **Check variant coverage:** Did you search all morphological forms? Add missing variants and re-search.
3. **Cross-check with prefix query:** Run a `term*` prefix search and compare the count to your explicit-variant search. A large discrepancy suggests missed variants.
4. **Widen time range:** Results clustered in recent days may indicate older matches outside `--days` window.

For counting queries, use `--count-only` to get the authoritative `totalCount`. If counts seem low, verify your query covers all morphological variants.

## Advanced flags

These flags provide fine-grained control over search and output behavior.

### Counting and aggregation

| Flag | Subcommand | Description |
|------|-----------|-------------|
| `--count-only` | search | Returns only `totalCount` in metadata with an empty `data` array. No result bodies fetched. Use for counting queries instead of paginating. |
| `--term-counts` | search | Adds per-term match counts (`termCounts` object) for OR queries. Opt-in. Silently omitted if the query is not an OR query or has more than 10 unique terms. Works with or without `--count-only`. |

### Filtering

| Flag | Subcommand | Description |
|------|-----------|-------------|
| `--kinds <csv>` | search, context | Filter by entry kind: `user`, `assistant`, `system`. Comma-separated. Example: `--kinds user,assistant` |
| `--since <ts\|iso>` | global | Time range start (inclusive). Accepts Unix timestamp, ISO 8601, or `YYYY-MM-DD`. Cannot combine with `--days`. |
| `--until <ts\|iso>` | global | Time range end (inclusive). Same formats as `--since`. Cannot combine with `--days`. `--since` must be <= `--until`. |
| `--include-hidden` | global | Include non-timeline entries (system messages, hidden entries). By default only `display_in_timeline=1` entries are returned. |
| `--transcript-id <id>` | global | Scope queries to a specific transcript by ID. Narrows search/activity results to a single conversation. |

### Content control

| Flag | Subcommand | Description |
|------|-----------|-------------|
| `--full-content` | activity, entry, context | Disable the default 2KB content truncation. Has no effect on search (search returns snippets). |
| `--no-content` | activity, entry, context | Returns `null` for content (metadata only). No effect on search. |
| `--snippet-tokens <n>` | search | Control search snippet length in tokens. Default 10, max 100. Longer snippets reduce the need to call `context` for each hit. |

### Context window

| Flag | Subcommand | Description |
|------|-----------|-------------|
| `--before <n>` | context | Entries before anchor (default 10). |
| `--after <n>` | context | Entries after anchor (default 20). |
| `--max-window <n>` | context | Cap `--before` + `--after` total. Default 200, hard max 2000. Errors if exceeded. |

### Scope and database

| Flag | Subcommand | Description |
|------|-----------|-------------|
| `--project-id <id>` | global | Scope queries to a project by UUID. Bypasses worktree expansion entirely. Use when you have a known project ID. |
| `--db-path <path>` | global | Full path to `contextify.db`. Use when the database is in a custom location (Dropbox, iCloud Drive). |
| `--db-dir <dir>` | global | Directory containing `contextify.db`. Appends the filename automatically. |

### Worktree scope

| Flag | Subcommand | Description |
|------|-----------|-------------|
| `--this-worktree` | search, activity | Suppress worktree group expansion. Search only the current worktree's project. |
| `--exclude <csv>` | search, activity | Exclude specific worktrees from expansion by display name or directory name. Comma-separated. |

## Worktree expansion

When `--project .` is used inside a git worktree, Contextify auto-detects sibling worktrees and expands the search across all of them. This means a search in one worktree also returns results from conversations in sibling worktrees of the same repository.

**How it works:**
1. Contextify runs `git worktree list` to discover sibling worktrees
2. Each worktree is looked up in the database by path
3. The search runs across all matched project IDs
4. Results include a `worktreeExpansion` metadata object explaining what happened

**Example metadata with worktree expansion:**
```json
{
  "metadata": {
    "returned": 10,
    "limit": 10,
    "offset": 0,
    "hasMore": true,
    "totalCount": 234,
    "worktreeExpansion": {
      "enabled": true,
      "worktrees": ["main", "wb1", "wb2"],
      "excluded": [],
      "unresolved": []
    },
    "sourceCounts": {
      "AB12CD34-...": 150,
      "EF56GH78-...": 84
    }
  }
}
```

- `worktreeExpansion.worktrees`: display names of all included worktrees
- `worktreeExpansion.excluded`: names that were excluded (via `--exclude`)
- `worktreeExpansion.unresolved`: names not found in the database
- `sourceCounts`: maps each project ID to its result count

**Controlling expansion:**
- `--this-worktree` suppresses expansion entirely (search only the current worktree)
- `--exclude wb1,wb2` removes specific worktrees from expansion
- Worktrees marked `archived: true` in `.worktrees.json` are excluded automatically
- Using `--project-id` instead of `--project` bypasses expansion entirely

## Additional subcommands

Beyond `search`, `context`, `entry`, `status`, and `projects`, the CLI provides:

| Subcommand | Description |
|-----------|-------------|
| `activity` | Recent timeline entries. Supports `--project`, `--days`, `--limit`, worktree expansion. |
| `transcripts` | List transcripts for a project. Requires `--project` or `--project-id`. |
| `stats` | Project statistics (transcript count, entry count, last activity). |
| `summaries` | LLM-generated transcript summaries. Requires summaries capability (check `status`). |
| `doctor` | Check CLI installation health. Exit codes: 0=healthy, 1=degraded, 2=broken. |
| `feedback` | Record or manage CLI feedback items. Subcommands: `list`, `show`, `export`, `dismiss`, `archive`, `clear`. |

## Delegating to researcher agent

**Claude Code only:** For complex multi-query searches, delegate to `contextify-researcher` agent:

```
Use the contextify-researcher agent to thoroughly search for [topic]
```

The researcher agent will perform multiple searches and synthesize results.

**Codex CLI:** Agent delegation is not available. Instead, run multiple searches manually and synthesize results yourself.
