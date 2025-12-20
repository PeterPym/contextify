---
todo_id: CONTEXT-REINJECTION
title: Contextify query report aggregations (follow-on)
type: reference
date: 2025-12-14
status: active
description: Follow-on scope for adding read-only aggregation reports to contextify-query to improve reinjection workflows and enable demo-quality outputs.
---

# Contextify query report aggregations

This document captures follow-on aggregation/report ideas for `contextify-query`. Reports aim to improve reinjection workflows by making it easier for an agent to choose good query scopes and anchors.

## Goals

- Provide small, deterministic, read-only “reports” that:
  - guide time-window selection (`--days`, `--since/--until`)
  - surface high-signal anchors (decision points, revisited topics)
  - enable compelling demos (ASCII charts, compact summaries) without ad-hoc SQL
- Keep schemas stable and machine-friendly (`--json`).

## Non-goals

- “Mood” or sentiment scoring (too unreliable/noisy in v1).
- Heavy NLP/topic modeling (defer unless a clear need emerges).
- Any DB writes.

## Proposed CLI shape

Introduce a new command family:

- `contextify-query report <report-name> [options]`

Shared options:

- `--project-id <id>` / `--project <path|.|current>`
- `--since <ts|iso>` / `--until <ts|iso>` / `--days <n>`
- `--kinds <csv>` (optional)
- `--providers <csv>` (optional; e.g. `claude.code,codex.cli`)
- `--limit <n>` (where applicable)
- `--json`

Report outputs should be:

- deterministic ordering
- bounded (hard caps on bucket count and anchor lists)
- explicit about truncation (if any)

## Report candidates (v1 set)

### 1) `activity-by-hour`

Purpose: choose time windows and demonstrate “when work happens”.

Output:
- 24 buckets (0–23), counts
- optional `anchors[]` (up to 3 entry ids per bucket) when `--include-anchors`

### 2) `activity-by-weekday`

Purpose: same as hour, but day-of-week cadence.

Output:
- 7 buckets (Mon–Sun), counts

### 3) `decision-points`

Purpose: find anchors where decisions/specs happened.

Heuristic:
- match common decision markers (`decide`, `should`, `spec`, `plan`, `ship`, `blocker`)
- optionally restrict to `kind=user` for intent

Output:
- list of entries with `id`, `timestamp`, `contentSnippet`, and a `reason` label

### 4) `revisited-topics`

Purpose: identify churn to guide “pull more context” behavior.

Heuristic:
- lightweight tokenization + stopword removal
- track repeated keywords across a time range

Output:
- top N topics with counts and up to 3 anchor entry ids each

## Data needed to make reports genuinely helpful

Reports get better when they incorporate how tools actually construct queries. The fastest way to learn is to record lightweight “query planning telemetry” during dogfooding.

Candidate telemetry sources:

- Claude Code plugin hooks:
  - capture `session_id` + `transcript_path` at SessionStart
  - capture `contextify-query` Bash invocations (args + exit + timing) on tool use hooks
- Contextify-side telemetry:
  - structured logs for “skill invoked search/context”, including `--days`, `--project` usage
- CLI feedback inbox:
  - allow attaching “trace snippets” to `contextify-query feedback`

Telemetry design constraints:

- local-only storage by default (App Support)
- bounded retention (size cap + archive)
- avoid capturing raw content unless explicitly enabled
