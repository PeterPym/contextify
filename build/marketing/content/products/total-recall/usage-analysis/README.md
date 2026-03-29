# Total Recall Usage Analysis

Deep analysis of every `/total-recall` invocation across all Claude Code sessions. Source data for case studies, product improvement, and marketing content.

## How This Was Generated

### Source prompt

The analysis was driven by a structured prompt written in a prior session:
`/tmp/total-recall-usage-analysis-prompt.md` (session `5e562095-6100-4ee7-80cf-2646fe2752ab`, 2026-03-26, branch `main-wb3`)

A copy of the prompt is preserved below for reproducibility.

### Dataset

| Metric | Count |
|--------|-------|
| Skill tool_use invocations (`Skill` + `"total-recall"`) | 54 |
| User-initiated /total-recall commands | ~51 |
| contextify-researcher agent delegations | 367 mentions / 170 files |
| Unique main sessions with direct invocations | 29 |
| Projects spanned | ~10 |

### Extraction method

5 parallel research agents each processed a batch of session JSONL files:

| Batch | Files | Scope |
|-------|-------|-------|
| 1 | 6 | Consulting + personal administration |
| 2 | 6 | Personal misc + task management tool |
| 3 | 4 | CLI tooling project |
| 4 | 6 | macOS developer tool (worktrees 1-2, first half) |
| 5 | 6 | macOS developer tool (worktrees 2-4, second half) |

Each agent:
1. Used `grep -n "total-recall" <file>` to find invocation line numbers in the raw JSONL
2. Read +/- 80 lines around each invocation for context
3. Extracted trigger, query, results, delivery, aftermath, and classification
4. Wrote structured JSON to `raw/tr-analysis-batch-N.json`

### Execution context

- Session: `7167f5f7-2eb0-47d9-92b7-3cd37532bdf5`
- Date: 2026-03-26
- Branch: `ct-390-v3-polish` (contextify-wb4)
- Model: Claude Opus 4.6

### Known limitations

- Agents grepped raw JSONL files rather than querying the Contextify database first. The database could have provided faster initial discovery, with JSONL used only for tool_use metadata extraction.
- Subagent files (`/subagents/agent-*.jsonl`) were checked but coverage may be incomplete for deeply nested delegations.
- Privacy: case study descriptions use generic project names, not specific client or project details.

## Directory Structure

```
usage-analysis/
  README.md                     # This file
  raw/                          # Raw extraction data (one JSON per batch)
    tr-analysis-batch-1.json
    tr-analysis-batch-2.json
    tr-analysis-batch-3.json
    tr-analysis-batch-4.json
    tr-analysis-batch-5.json
  case-studies.md               # Synthesized case study library (Phase 3)
  product-improvements.md       # Friction points and improvement ideas (Phase 4)
  marketing-cases.md            # Top cases formatted for marketing (Phase 4)
```

## Key Findings (from completed batches)

### Batch 1 (consulting + personal admin): 6 invocations
- All user-initiated; TR used as escalation after local search (grep, glob, bloon) fails
- Context retrieval (`contextify context`) needed in 5/6 cases, snippets rarely sufficient
- "Multiple Contextify installs detected" warning in every invocation (UX issue)

### Batch 3 (CLI tooling): 5 invocations, 2 successful
- Query construction anti-patterns: narrow `--days` windows, no retries, no synonym expansion
- 3/5 failed silently and fell back to git/filesystem tools
- Cross-project noise: unrelated projects returned in results

### Batch 5 (macOS dev tool, wb2-4): 5 invocations, all successful
- Common session-opener pattern: start new session by re-orienting with Total Recall
- FTS5 hyphen tokenization: `review-loop` returns nothing, must use `"review loop"`
- Clearest negative-proof example: confirming a review loop was never performed elsewhere

## Source Prompt (preserved for reproducibility)

The full prompt that generated this analysis follows. It was originally written to
`/tmp/total-recall-usage-analysis-prompt.md` in session `5e562095`.

---

### Objective

Analyze every past invocation of the `/total-recall` skill across all Claude Code sessions to build a library of case studies. The output should identify patterns in how the tool is used, what value it delivers, and where it falls short, informing both product improvement and marketing.

### Phase 1: Extract Invocation Records

For each of the 29 session files, read the JSONL and extract every total-recall invocation. An invocation is identified by an `assistant` record containing:
```json
{
  "type": "tool_use",
  "name": "Skill",
  "input": { "skill": "total-recall", "args": "..." }
}
```

For each invocation, extract:

1. **Invocation metadata** - session file path, session ID, project, timestamp, main vs subagent
2. **The trigger** - what prompted this? User-initiated or AI-initiated? Underlying need?
3. **The query** - raw args, search commands constructed, parameters used
4. **The results** - success/fail, count, pagination, context drilldown
5. **The delivery** - how findings were presented
6. **The aftermath** - user response, direction change, follow-up searches

### Phase 2: Classify and Enrich

Taxonomy of use cases:

| Category | Description |
|----------|-------------|
| Decision Recall | "What did we decide about X?" |
| Implementation Reference | "How did we implement X?" |
| Cross-Session Continuity | Picking up where a previous session left off |
| Knowledge Search | "What do we know about X?" |
| Counting/Audit | "How many times did we X?" |
| Debugging History | "When did this break?" |
| Cross-Project Search | Finding info from a different project |
| Self-Referential | Using Total Recall to improve Total Recall |
| Proof Gathering | Finding evidence/citations for a claim |
| Session Handoff | Loading context for a new session/worktree |
| Negative Proof | Confirming something was never discussed |
| Incident Forensics | Tracing events across sessions |

Enrichment: value delivered (high/medium/low/none), tool friction, would-have-been-lost, surprise factor.

### Phase 3: Synthesize Case Study Library

Write to case-studies.md with executive summary, per-category cases, cross-cutting analysis (value delivery, friction points, marketing insights, product improvements).

### Phase 4: Derivative Outputs

- product-improvements.md - prioritized improvements from friction analysis
- marketing-cases.md - top 10 cases formatted for marketing
- use-case-taxonomy.md - refined taxonomy with frequency data

### Session Files Analyzed

```
# Consulting (1 file)
5dd20285-778a-44c3-a50c-38f9ae7c7d92.jsonl

# Personal Administration (5 files)
76e3d276, 35fdba7b, b23057f0, e283b278, fba286a1

# Personal Misc (4 files)
1c360b52, 804be59a, a56c55f8, ac151dab

# Task Management Tool (2 files)
5298c35f, fd66f959

# CLI Tooling (4 files)
c9913bbd, 4e81aeb6, 6192fe6b, 9a14f6f5

# macOS Developer Tool (13 files across 4 worktrees)
26117307, c73815d2, d9f10e0c, 106858ec, 4d0fa098, 66459b5c,
bc9c89d7, f04fe221, fb9a8259, 2ee40fe6, 48df0d86, 92747822
```
