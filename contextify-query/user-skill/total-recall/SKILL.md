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

Before your first search, compute the skill and CLI fingerprints:

```bash
shasum -a 256 ~/.claude/skills/total-recall/SKILL.md | cut -c1-8
contextify --version
```

Use these in response headers: `skill:<hash> cli:<version>` (e.g., `skill:e07ddcfc cli:1.3.2`).

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

The Contextify search backend uses FTS5 with **porter stemming**. The porter algorithm automatically matches morphological variants of English words.

- `deploy` matches "deploy", "deploys", "deployed", "deploying", "deployment", "deployments"
- `run` matches "run", "running", "runs", "runner" (but NOT irregular forms like "ran")
- Searches are case-insensitive
- The prefix operator `*` matches token prefixes: `run*` matches any token starting with "run"
- Quoted phrases match exact sequences with stemming: `"memory leak"` requires both stems adjacent in order
- **Quoted phrases still apply stemming** to each word within the phrase, but enforce adjacency

**Stemming limitations:** The query builder quotes tokens with special characters (dots, colons) to enforce exact matching for those tokens. Irregular verb forms (e.g., "ran" from "run") are NOT matched by stemming -- use explicit OR for those.

**Tokenization and special characters:** Hyphens, underscores, and most punctuation act as token separators. For example, `CT-97` is tokenized as two separate tokens `CT` and `97`. To match hyphenated or snake_case identifiers, search for `CT AND 97` or try the quoted form `"CT 97"`. File paths and punctuation-heavy identifiers may need simplified forms.

## Query construction

Before searching, analyze the user's request and build an effective query.

### Priority rule: entities first

Preserve rare names and identifiers exactly. Only expand common verbs and concepts.

- **Proper nouns, people, companies, products**: use as-is or in quoted phrases (`"Perch Innovations"`, `"Fulton House"`)
- **Task IDs, version numbers**: quote them (`"ct 389"`, `"v1.5.0"`)
- **Hyphenated project names**: quote without hyphens (`"contextify cloud"`, `"cli ai setup"`)
- **Common verbs**: porter stemming handles regular forms automatically; only add explicit OR for irregular forms (`run OR ran`)

Start your search with the 2-3 most distinctive terms from the question. If the question mentions a specific name, number, or identifier, that should be your primary search term, not a generic concept.

### Step 1: Classify intent

Determine the query type to set your strategy and starting `--days` window:

| Intent | Signals | Time window | Strategy |
|--------|---------|-------------|----------|
| **Counting** | "how many", "count", "every time", "frequency" | `--days 365` | Use `--count-only`. Add `--term-counts` for OR queries. |
| **Lookup** | "what did we decide", "find the discussion", "when did we" | `--days 365` | Balanced. Use quoted phrases for precision. Default `--limit 10`. |
| **Exploratory** | "what have we talked about", "find anything about" | `--days 365` | Start broad, refine iteratively. Use `--limit 20`. |
| **Negative proof** | "have we ever", "did we discuss", "was there any" | `--days 365` | Broad scope. Run 2-3 materially different query variations before declaring absence. |
| **Debugging** | "when did this break", "what changed", "recent error" | `--days 30` | Narrow, recent. Use `--project .` for current repo focus. |
| **Time-scoped** | "last N hours", "today", "yesterday", "this morning", "this week", "last week", "past hour" | See below | Detect the time reference and use `--hours` or `--days` accordingly. |

**Time-scoped intent:** When the user's request includes an explicit time reference, override the default window:

| User phrasing | Flag to use |
|---------------|-------------|
| "in the last N hours", "past N hours" | `--hours N` |
| "today", "this morning", "this afternoon" | `--hours 24` |
| "yesterday" | `--days 2` |
| "this week", "past few days" | `--days 7` |
| "last week" | `--days 14` |
| "last month", "past few weeks" | `--days 30` |

Use `--hours` for sub-day precision (e.g., "last 6 hours") and `--days` for multi-day windows. Do not default to `--days 365` when the user specifies a narrower time frame.

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

Porter stemming automatically matches regular inflections: `deploy` finds "deployed", "deploying", "deployment". You do NOT need explicit OR for regular verb/noun forms.

**Still expand with OR for:**
- **Irregular verbs:** `run OR ran`, `break OR broke OR broken`
- **Synonyms and related terms:** `error OR failure OR bug`, `hat OR cap OR headwear`
- **Alternative phrasings:** `"pricing model" OR "pricing plan" OR "subscription"`, `rename OR rebrand OR retitle`

**Use prefix `*` when:**
- The stem is short or ambiguous: `config*` catches "config", "configure", "configuration"
- You want broad recall: `patcher*` catches "patcher", "patching", "patchers"

**Build multi-concept queries** by combining expanded terms with AND:
```
(deploy OR release) AND (fail OR error OR broke)
```

**Always try 2-3 query formulations** for non-trivial searches. A single query rarely covers all relevant phrasing. Vary your terms, try alternative angles, and broaden before concluding no results exist.

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

**Quick recipe:** Classify intent, pick 2-3 distinctive terms + OR synonyms (stemming handles inflections, you handle synonyms), choose limit (or `--count-only`), search, try 2-3 query variations, paginate if `hasMore`, answer with citations.

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
    "newestEntryTimestamp": 1769380895,
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

**Data freshness check:** Compare `newestEntryTimestamp` (Unix epoch) to the current time. If the newest entry is more than 1 hour old, warn the user before searching:

> **Note:** Contextify data may be stale (last indexed entry is from [time ago]). Results may be incomplete. Ensure the Contextify app is running to resume ingestion.

Still proceed with the search, but frame results as potentially incomplete. If searching for very recent conversations (e.g., "last hour", "today") and data is stale, the warning is especially important.

2) Construct query and search:

Build your query following the "Query construction" section above, then search:

```bash
contextify search "<expanded-query>" --days 365 --limit <N> --snippet-tokens 100
```

For repo-scoped debugging, add `--project .` and use `--days 30` instead.

When the request relates to specific code, subsystems, or files you can identify from your project knowledge, pass those files as anchors to boost results from conversations near commits touching those files:

```bash
contextify search "<expanded-query>" --days 365 --limit <N> --snippet-tokens 100 --anchor-files "<file1>,<file2>"
```

Determine the relevant files from your understanding of the codebase, not from the user's query text. For example, if the user asks "what did we decide about the database migration?", you know that relates to `DatabaseSchema.swift`, so pass `--anchor-files DatabaseSchema.swift`. If the user asks about the startup flow, you know that relates to `StartupCoordinator.swift`.

For queries where you cannot identify specific relevant files but the query contains literal filenames or symbols, fall back to `--anchor-git` which extracts cues from the query text automatically:

```bash
contextify search "<expanded-query>" --days 365 --limit <N> --snippet-tokens 100 --anchor-git
```

Git anchoring is additive, not exclusive:
- if the CLI reports it found git anchors, use that ranking signal
- if it reports no strong commit signal, continue with normal broad search
- do not stop exploring just because the git path was attempted

Set `--limit` based on intent: 10 for lookup, 20 for exploratory. For counting, use `--count-only --json` (counting requires JSON for structured `totalCount`).

**Search query syntax (FTS5):** Use `OR`, `AND`, `NOT` operators, quoted phrases for exact sequences, and `*` for prefix matching. Use parentheses when mixing AND/OR to control grouping; do not rely on default operator precedence.

**Text output format:** The default (non-JSON) output is designed to be read directly:

```
847 results across my-project, other-project
Showing 10 of 847

1. [assistant] my-project · Mar 29, 2026 14:06  entry:e897a104
   The database schema was migrated in phase 3 to support multi-device sync...

2. [user] my-project · Mar 28, 2026 09:15  entry:5f981600
   What did we decide about the migration strategy?...

Drill down:
  contextify context <entry-id> --before 5 --after 15    # surrounding conversation
  contextify entry <entry-id>                             # full entry text
  Add --offset 10 to see the next page
```

Each result shows: numbered position, entry kind, project name, human-readable date, and the 8-character entry ID prefix (usable with `context` and `entry` commands). The summary line shows total count and projects. The drill-down hints show how to fetch more detail.

Example -- user asks "how many times have I mentioned deploying":
```bash
contextify search "deploy" --project . --days 365 --count-only --term-counts --json
```

Porter stemming matches all regular forms automatically. Use `--json` here because counting queries need the structured `totalCount` and `termCounts` fields.

Example -- user asks "what did we decide about the database schema":
```bash
contextify search "\"database schema\" OR \"schema migration\" OR \"schema change\"" --project . --days 90 --limit 10
```

Example -- user asks "what did we discuss in the last 6 hours about testing":
```bash
contextify search "test OR testing OR \"test suite\"" --project . --hours 6 --limit 10
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
    "totalCount": 847,
    "databaseSummary": {
      "entryCount": 586093,
      "projectCount": 46,
      "deviceCount": 2
    }
  },
  "schemaVersion": 1,
  "type": "search"
}
```

**Important:** `data` is a flat array of results. Each result's `id` is the UUID you pass to the `context` and `entry` commands. Both full UUIDs and 8+ character prefixes are accepted (the CLI resolves prefixes like git resolves short SHAs). If a prefix is ambiguous (matches multiple entries), the CLI returns an `entryAmbiguousId` error with candidates.

`projectId` is an opaque string (format varies). `score` is an internal ranking value; treat it as opaque. Results are already returned in best-first order; do not re-sort. If `contentTruncated` is `true`, always fetch full content via `context` (preferred) or `entry`.

**Metadata fields:** `returned`, `limit`, `offset`, `hasMore`, and `totalCount` are always present. Other fields:
- `databaseSummary`: always present, contains `entryCount`, `projectCount`, `deviceCount` for the full database (not filtered by search scope)
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
contextify context "<entry-id>" --before 5 --after 15
```

The text output shows the surrounding conversation in chronological order with entry IDs and dates. Use the 8-character entry ID prefix from search results. For structured access, add `--json`.

4) If a snippet is too short and you need the full entry:

```bash
contextify entry "<entry-id>"
```

Returns the full untruncated entry text. Use the 8-character entry ID prefix from search results.

5) Validate results before answering:

Before formatting your response, check:

- **Total count:** The text output header shows "N results across projects" and "Showing X of Y". If more exist, paginate with `--offset`:
  ```bash
  contextify search "<expanded-query>" --project . --limit 20 --offset 20
  ```
- **Result volume sanity check:** If a counting query returns fewer results than expected, re-examine your query. Did you miss an irregular form (e.g., "ran" for "run")? A synonym? Porter stemming handles regular inflections but not irregular verbs or synonyms.
- **For counting queries:** Use `--count-only --json` and report `totalCount` from metadata. List which search terms were used so the user can judge completeness.

If results seem incomplete, run additional searches with expanded terms before answering.

6) Format response:

Use the template matching the query type. Adapt the structure to the number of results, but keep the header, citation format, and summary sections.

### Lookup / exploratory template

```
> **Contextify Total Recall**
> _Searched <totalCount> entries across <project(s)> | <time range, e.g. "last 90 days" or "all time">_

[1-2 sentence summary: what was found, when, and the bottom line.]

> "[Quoted excerpt from the most relevant result. Keep it concise but include the key fact, decision, or detail.]"
>
> -- <project name>, <date in "Mon DD, YYYY" format> `entry:<first-8-chars-of-uuid>`

> "[Second excerpt if needed for a different facet or time period.]"
>
> -- <project name>, <date> `entry:<first-8-chars-of-uuid>`

**Summary:** [What was decided or what the current status is, synthesized from the evidence above. Distinguish "discussed and planned" from "implemented and merged" when relevant. If the answer is uncertain or incomplete, say so.]

## Evidence

- `entry:<first-8-of-uuid>` <project>, <date>: "<exact quoted span from the entry content>"
- `entry:<first-8-of-uuid>` <project>, <date>: "<exact quoted span from the entry content>"

`skill:<hash> cli:<version>`
```

### Counting template

```
> **Contextify Total Recall**
> _Searched <scope> | <time range>_

**<totalCount>** entries match across <project(s)>.

| Term | Matches |
|------|---------|
| deploy | 312 |
| deployed | 201 |
| ... | ... |

**Search terms:** `<the OR-expanded query as sent to the CLI>`

## Evidence

- `entry:<first-8-of-uuid>` <project>, <date>: "<exact quoted span from the entry content>"

`skill:<hash> cli:<version>`
```

### Negative result template

After completing the zero-result protocol (section below), if still no results:

```
> **Contextify Total Recall**
> _No results found._

Searched <N> entries across <scope> over <time range>.

**Queries tried:**
1. `<first query>`
2. `<second query>`
3. `<broadened query>`

[Brief note on what this means, e.g. "This topic does not appear in your indexed conversation history."]

`skill:<hash> cli:<version>`
```

### Formatting rules

- **Header is mandatory.** Every response starts with the `Contextify Total Recall` header line and search scope line.
- **Quote, don't paraphrase.** Use `> "..."` blockquotes for source excerpts. Trim for brevity but preserve the key fact.
- **Cite every excerpt.** Each blockquote gets a `-- project, date entry:<uuid-prefix>` attribution line.
- **One summary, at the end.** Synthesize across all cited results. Do not repeat what the quotes already say.
- **Timestamps as dates.** Convert Unix timestamps to "Mon DD, YYYY" (or "Mon DD, YYYY HH:MM" when time matters). Never show raw Unix timestamps to the user.
- **Multiple results.** Show 2-4 quoted excerpts for the most relevant hits. For exploratory queries with many results, briefly list additional hits by date and project after the key quotes.
- **Evidence section is mandatory** (except for negative results). Every response that found results must end with a `## Evidence` section. This section helps both humans verify the answer's sources and automated tooling validate search accuracy. Rules:
  - List 1-5 entries that directly support the answer
  - Each line: `- \`entry:<first-8-chars-of-uuid>\` <project>, <date>: "<exact quoted span>"`
  - The entry ID must be the first 8 characters of the entry UUID from search/context results
  - The quoted span must be an EXACT substring of the entry's content (copy-paste, not paraphrased)
  - The quoted span should be the most relevant 1-2 sentences from the entry
  - For negative results (no matches found), omit the Evidence section

**Response fidelity rules:**

- **Quote distinctive terms verbatim.** When results contain technical identifiers (env vars like `SENTRY_ENVIRONMENT`, config values, error codes), exact job titles ("Quality Engineering Lead"), product names, or distinctive phrasing, reproduce them exactly from the source material rather than paraphrasing.
- **Name every individual mentioned.** When a question asks about decisions, stakeholders, or participants, name ALL individuals found in relevant results with their specific roles or requests, not just the first or most prominent one.
- **Verify implementation status.** When asked whether work was done or implemented, search for merge/commit evidence (commit hashes, PR numbers, "merged to main"), not just discussion. Clearly distinguish between "discussed and planned" vs "implemented and merged." If you find only discussion without merge evidence, say so.
- **Include technical details.** When results contain specific values (version numbers, config settings, measurements, URLs), include them in your response. These details are often what the user actually needs.
- **Fetch context for key results.** When a search snippet seems relevant but is truncated, always use `contextify context` to get the full surrounding conversation. Important details (names, status, outcomes) are often in adjacent entries, not the snippet itself.
- **Use source language.** When the source material uses distinctive or colorful terms (e.g., "bootleg hats" instead of "novelty hats"), use the source's wording in your response. This preserves the user's original framing.

## NEVER pipe CLI output through external tools

**CRITICAL:** Do not pipe `contextify` output through `python3`, `jq`, `awk`, `sed`, `grep`, or any other tool. This is the single most common cause of errors shown to users. The text output is designed to be read directly. If you need structured data for counting, use `--json` and read the JSON directly from the Bash output. You are capable of reading JSON natively without external parsers.

**Never use `2>&1` with contextify.** The CLI writes informational messages to stderr. Using `2>&1` merges these into stdout and corrupts the output.

**When `--json` is used:** Successful responses return `{"data": ..., "schemaVersion": 1, "type": "..."}`. Errors return `{"type": "error", "code": "...", "message": "..."}`. Read the JSON directly.

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
| `dbProjectNotFound` | Check `details.suggestions` for fuzzy name matches (typo correction). Offer alternatives: "Did you mean: X?" |
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
- Simplify: reduce to the 1-2 most distinctive terms (porter stemming already covers regular inflections)
- Add irregular verb forms if applicable: `run OR ran`
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
2. **Check irregular forms and synonyms:** Porter stemming covers regular inflections but not irregular verbs ("ran", "broke") or synonyms. Add those manually if relevant.
3. **Widen time range:** Results clustered in recent days may indicate older matches outside `--days` window.

For counting queries, use `--count-only` to get the authoritative `totalCount`. If counts seem low, check for irregular verb forms or synonyms that stemming does not cover.

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
| `--kinds <csv>` | search, context | Filter by entry kind: `user`, `assistant`, `summary`, `system`. Comma-separated. Example: `--kinds user,assistant` |
| `--exclude-tags <csv>` | search | Exclude transcripts that have any of the specified tags. Comma-separated tag names. Example: `--exclude-tags archived,noise` |
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
