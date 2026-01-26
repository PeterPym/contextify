---
name: total-recall
description: Contextify Total Recall - Search past conversations and decisions with your AI. https://contextify.sh
---

# Contextify Total Recall

Search your conversation history to find past decisions, solutions, and discussions.

## IMPORTANT: Command Format

**The CLI command is `contextify-query` (hyphenated, one word).**

- Correct: `contextify-query search "my query"`
- Correct: `contextify-query status --json`
- **WRONG:** `contextify query` (this is Linux-only and will fail on macOS)
- **WRONG:** `contextify search` (this is Linux-only and will fail on macOS)

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
command -v contextify-query
```

2) If `contextify-query` is missing:

**Error response:**
> Contextify CLI not found.
>
> **DMG users:** Open Contextify -> Settings -> CLI -> "Install/Repair CLI"
>
> **App Store users:** Run `brew install PeterPym/contextify/contextify-query`
>
> For help: https://contextify.sh/help

## FTS5 search behavior

The search backend uses SQLite FTS5 with **exact token matching**. There is no stemming.

- `"run"` matches only the exact token "run", NOT "running", "runs", or "ran"
- `"deploy"` does NOT match "deployment" or "deployed"
- Searches are case-insensitive
- The prefix operator `*` matches token prefixes: `run*` matches "run", "running", "runs", "runner"
- Quoted phrases match exact sequences: `"memory leak"` requires both words adjacent in order

Because there is no stemming, you must explicitly include morphological variants in your queries. See "Query construction" below.

## Query construction

Before searching, analyze the user's request and build an effective query.

### Step 1: Classify intent

Determine the query type to set your strategy:

| Intent | Signals | Strategy |
|--------|---------|----------|
| **Counting** | "how many", "count", "every time", "frequency" | Maximize recall. Expand all variants. Use `--limit 200` or higher. |
| **Lookup** | "what did we decide", "find the discussion", "when did we" | Balanced. Use quoted phrases for precision. Default `--limit 10`. |
| **Exploratory** | "what have we talked about", "find anything about" | Start broad, refine iteratively. Use `--limit 20`. |

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
- For counting queries, prefer explicit OR with all known variants for precision

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

- **Counting queries:** `--limit 200` minimum. If `hasMore` is true, paginate with `--offset`.
- **Lookup queries:** `--limit 10` is fine for finding an anchor.
- **Exploratory queries:** `--limit 20`, then refine.

## Canonical loop

1) Confirm database availability:

```bash
contextify-query status --json
```

If database not found, respond:
> Contextify database not found.
>
> Please open Contextify once to initialize the database.
>
> Download: https://contextify.sh/download

2) Construct query and search:

Build your query following the "Query construction" section above, then search:

```bash
contextify-query search "<expanded-query>" --project . --days 30 --limit <N> --json
```

Set `--limit` based on intent: 200+ for counting, 10 for lookup, 20 for exploratory.

**Search query syntax (FTS5):** Use `OR`, `AND`, `NOT` operators, quoted phrases for exact sequences, and `*` for prefix matching.

Example -- user asks "how many times have I mentioned deploying":
```bash
contextify-query search "deploy OR deploys OR deployed OR deploying OR deployment" --project . --days 365 --limit 200 --json
```

Example -- user asks "what did we decide about the database schema":
```bash
contextify-query search "\"database schema\" OR \"schema migration\" OR \"schema change\"" --project . --days 90 --limit 10 --json
```

Anchor selection guidance:

- If asking about earlier context (not "in this chat"), prefer anchors NOT from the active transcript.
- If `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` is set, treat hits from that transcript as lower priority unless user explicitly wants current session.
- If transcript ID missing and multiple hits exist, avoid auto-selecting anchors from last 30 minutes.

3) Retrieve context around the anchor:

```bash
contextify-query context "<entry-uuid>" --before 10 --after 20 --project . --json
```

4) Validate results before answering:

Before formatting your response, check:

- **`hasMore` flag:** If `true`, you have not retrieved all matches. For counting queries, paginate with `--offset` until `hasMore` is `false`.
- **Variant coverage:** Scan returned snippets for word forms you did not search for. If you searched `deploy*` and see "redeployment" in results, verify your query also captures that.
- **Result volume sanity check:** If a counting query returns fewer results than expected, re-examine your query. Did you miss an irregular form? A synonym?
- **For counting queries:** Report the total count, note whether `hasMore` was encountered, and list which search terms were used so the user can judge completeness.

If results seem incomplete, run additional searches with expanded terms before answering.

5) Format response:

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
> **Total matches:** [count] across [N] conversations
> **Complete:** [Yes/No -- based on whether hasMore was false on final page]

## Error handling

| Error | Response |
|-------|----------|
| `dbNotFound` | "Contextify database not found. Open Contextify to initialize. https://contextify.sh/download" |
| `dbProjectNotFound` | Check `details.suggestions`, offer alternatives |
| `featureUnavailable` | Explain limitation clearly, do not imply workarounds |
| `entryNotFound` | Re-search for a new anchor |
| `cliNotFound` | "Contextify CLI not found. See https://contextify.sh/help for installation." |

## Expanding search

### Zero results

If search returns 0 results:
1. Widen `--days` (try 90, then 365)
2. If not clearly about current repo, retry without `--project .`
3. Try prefix matching (`deploy*` instead of `deploy`)
4. Use `contextify-query projects --json` to discover other projects
5. Ask user to clarify what they're looking for

### Partial or suspicious results

If results are returned but may be incomplete:
1. **Check `hasMore`:** If true, raise `--limit` or paginate with `--offset`
2. **Check variant coverage:** Did you search all morphological forms? Add missing variants and re-search.
3. **Cross-check with prefix query:** Run a `term*` prefix search and compare the count to your explicit-variant search. A large discrepancy suggests missed variants.
4. **Widen time range:** Results clustered in recent days may indicate older matches outside `--days` window.

For counting queries, always verify you have captured all results before reporting a number.

## Delegating to researcher agent

**Claude Code only:** For complex multi-query searches, delegate to `contextify-researcher` agent:

```
Use the contextify-researcher agent to thoroughly search for [topic]
```

The researcher agent will perform multiple searches and synthesize results.

**Codex CLI:** Agent delegation is not available. Instead, run multiple searches manually and synthesize results yourself.
