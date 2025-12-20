---
title: Contextify CLI Improvement Opportunities
created: 2025-12-20
related_todo: "P1 - Contextify CLI improvements"
status: active
---

# Contextify Query Regex Failure Analysis

## What I Tried

```bash
contextify-query search "thank you|thanks|nice|perfect|great|awesome|good job|well done|excellent|brilliant|exactly" --days 365 --limit 500 --json
```

## What I Was Trying To Do

Search for multiple praise-related terms in a single query using regex OR syntax (pipe operator) to efficiently find all instances where the user expressed positive sentiment toward Claude or Codex.

## Why I Tried It That Way

1. **Pattern from Grep tool**: The Grep tool documentation explicitly states "Supports full regex syntax (e.g., 'log.*Error', 'function\s+\w+')" and contextify-query felt like similar infrastructure.

2. **Common convention**: Most search tools that support regex use `|` as the OR operator. This is standard PCRE/ripgrep behavior.

3. **Efficiency**: Running 10+ separate queries for each praise term, then deduplicating, seemed wasteful when regex OR should handle it in one pass.

4. **No documentation consulted**: The skill prompt I received (`contextify-reinject`) showed example usage like `contextify-query search "<query>"` but did not specify what query syntax is supported. I assumed regex without verifying.

## Why I Thought It Would Succeed

I made an untested assumption. The skill documentation showed:
```bash
contextify-query search "<query>" --project . --days 30 --limit 10 --json
```

The `<query>` placeholder gave no indication of supported syntax. I extrapolated from:
- My knowledge of ripgrep (which powers the Grep tool)
- The fact that contextify uses SQLite FTS (full-text search) under the hood
- General expectation that search tools support regex

I did NOT:
- Run a simple test query first to verify behavior
- Check if there's a `--help` flag on contextify-query
- Search for documentation on the query syntax
- Consider that SQLite FTS5 has its own query syntax (MATCH expressions) which differs from regex

## Whether The Output Was Useful When It Failed

**No. The output was actively harmful.**

The command returned:
```json
{
  "data": [],
  "schemaVersion": 1,
  "type": "search"
}
```

This is a **silent failure**. Zero results with no error message. Problems:

1. **Ambiguous**: Does this mean "no matches found" or "query syntax invalid"? I cannot tell.

2. **No validation feedback**: The tool accepted a malformed query without complaint.

3. **Wasted downstream work**: I proceeded to run the Python analysis script on empty data, producing a meaningless report with zeros.

4. **Debugging blind spot**: I had to infer the failure from the output rather than being told explicitly what went wrong.

A better failure mode would be:
```json
{
  "error": "queryParseError",
  "message": "Pipe character '|' not supported in search queries. Use multiple searches or FTS5 OR syntax.",
  "schemaVersion": 1,
  "type": "error"
}
```

## What I Plan To Do Next

Run individual searches for each term and combine results:

```bash
# Praise terms
contextify-query search "thank you" --days 365 --limit 200 --json > /tmp/praise_thanks.json
contextify-query search "thanks" --days 365 --limit 200 --json > /tmp/praise_thanks2.json
contextify-query search "nice work" --days 365 --limit 200 --json > /tmp/praise_nice.json
contextify-query search "perfect" --days 365 --limit 200 --json > /tmp/praise_perfect.json
contextify-query search "great" --days 365 --limit 200 --json > /tmp/praise_great.json
# ... etc

# Then combine and dedupe in Python by entry ID
```

## Is This A Reasonable Alternative?

**Partially.** It will work, but has drawbacks:

- **Inefficient**: 20+ queries instead of 2
- **Rate limiting risk**: If contextify-query has any rate limiting
- **Latency**: Sequential queries take longer
- **Maintenance burden**: Adding new terms requires adding new queries

However, it's the only reliable path forward given the tool's current behavior.

## How I Would Prefer The Command To Work

### Option 1: Support OR syntax
```bash
contextify-query search "thanks OR nice OR perfect OR great" --days 365
```
SQLite FTS5 actually supports this natively, so this might already work.

### Option 2: Multi-term flag
```bash
contextify-query search --terms "thanks,nice,perfect,great" --days 365
```

### Option 3: Regex flag
```bash
contextify-query search --regex "thank|nice|perfect|great" --days 365
```

### Option 4: Better error messages
At minimum, if the query syntax is invalid, tell me:
```
Error: Unknown operator '|' in query.
Hint: Use FTS5 syntax like "term1 OR term2" or run separate queries.
```

## Lessons Learned

1. **Test assumptions before scaling**: Should have run `contextify-query search "thanks"` first to verify basic functionality.

2. **Silent failures are dangerous**: Tools should fail loudly with actionable errors.

3. **Read the actual docs**: I should have run `contextify-query --help` or searched for documentation before assuming regex support.

4. **FTS != regex**: SQLite Full-Text Search has its own query language. Assuming ripgrep-style regex was incorrect.

## Next Steps

1. Try FTS5 OR syntax: `contextify-query search "thanks OR nice OR great"`
2. If that fails, fall back to individual queries
3. Consider filing an issue/TODO to improve contextify-query error messages

---

## Additional Issue: --kinds Flag Not Working

### Observed Behavior

The `--kinds user` flag does not filter results as expected:

```bash
contextify-query search "thanks" --days 365 --limit 5 --kinds user --json | jq '.data[].kind'
# Returns: "assistant", "assistant", "assistant", ...
```

Despite requesting `--kinds user`, assistant messages are returned.

### Workaround

Filter in jq after the fact:

```bash
contextify-query search "thanks" --days 365 --json | jq '[.data[] | select(.kind == "user")]'
```

### Suggested Fix

The `--kinds` flag should filter results before returning them. If this is a known limitation, the help text should clarify that `--kinds` is advisory or not yet implemented.

---

## Issue: Skill Invocation Discoverability

### Context

When a user says "use contextify to look through our convo history", the agent should recognize this as intent to use the `query:contextify-reinject` or `query:contextify-query-debug` skills.

### Observed Behavior

The agent did not immediately recognize the user's intent to leverage Contextify's conversation search capabilities. The phrasing "use contextify" should trigger skill invocation awareness.

### Suggested Improvements

1. **Skill description clarity**: The skill description should emphasize that Contextify is for searching/querying past conversation history across sessions.

2. **Trigger phrases**: Document common user phrasings that should invoke the skill:
   - "use contextify to..."
   - "search our conversation history"
   - "find where we discussed..."
   - "look through past sessions for..."

3. **Proactive suggestion**: When users ask about past conversations or "what did we discuss", the agent should proactively suggest using Contextify.

