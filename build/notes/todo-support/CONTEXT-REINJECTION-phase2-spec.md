---
todo_id: CONTEXT-REINJECTION
title: Context reinjection Phase 2 - Skills + CLI install/distribution
type: spec
date: 2025-12-13
status: active
description: Define Phase 2 for context reinjection: ship skills that teach Codex/Claude Code how to use contextify-query, plus a reliable CLI install/distribution story (DMG/App Store constraints).
---

# Phase 2: Skills + `contextify-query` Install/Distribution

Phase 1 establishes a stable, read-only query surface (`contextify-query`) with deterministic results and machine-friendly JSON.

Phase 2 focuses on adoption: external agents reliably use that surface without bespoke prompting or fragile setup.

## Goals

- Make Codex (and optionally Claude Code) reliably perform: search → anchor entry id → bounded context window → reinject.
- Provide a low-friction way for tools/humans to invoke `contextify-query`:
  - DMG: “it’s on PATH” is achievable.
  - App Store: provide a best-effort, user-consented flow that doesn’t fight sandbox constraints.
- Encode best practices in skills:
  - scoping (project vs global)
  - time filtering (`--days`)
  - budgeting (caps, truncation awareness)
  - error handling using structured error `details`

## Non-goals

- MCP server transport.
- Writing to the Contextify database.
- A full “Copy with Context” UI flow in Contextify (can be Phase 3+).

---

## Deliverable A: Codex Skill(s)

### Target mechanism

Codex CLI discovers skills under:

- `~/.codex/skills/**/SKILL.md`

Each skill is a directory containing `SKILL.md` with YAML frontmatter:

- `name` (<= 100 chars)
- `description` (<= 500 chars)

Codex injects only name/description/path at startup; the body is read when needed.

### Skill set

#### Skill 1: `contextify-reinject`

Purpose: Teach the canonical reinjection loop.

Required behaviors:

- Start with `contextify-query status --json` when DB availability is uncertain.
- Prefer `--project .` when the user’s request is clearly about the current repo.
- Prefer `--days N` for “recent” queries.
- Use `search` to find candidate anchors.
- Use `context <uuid>` to pull a bounded neighborhood.
- Respect truncation:
  - if `contentTruncated` is true in search, treat snippet as partial
  - if entries return `contentTruncated/contentFullSize`, don’t assume full fidelity
- Budget:
  - default to `--before 10 --after 20`
  - only widen windows when needed
  - never exceed `--max-window` cap

Error handling contract:

- `dbNotFound`: tell user how to provide `--db-path` / open app once.
- `dbProjectNotFound`: consult `details.suggestions` and pick likely match or ask user.
- `featureUnavailable`: explain missing capability (FTS/summaries).
- `entryNotFound`: treat anchor as stale; re-search.

Reinjection formatting guidance:

- Emit a compact “Contextify Reinjection” block with:
  - anchor id
  - before/after entries with timestamps/kinds
  - clear note when content is truncated

#### Skill 2: `contextify-query-debug`

Purpose: Teach diagnosis of discovery, schema, and “why did this fail” cases.

- `status` first.
- `projects` for discovery.
- Known failure patterns:
  - invalid DB path (not a database)
  - missing FTS table
  - missing summaries table
  - project resolution ambiguity

### Where these skills live

Ship canonical skill content inside the repo as templates:

- `build/skills/codex/contextify-reinject/SKILL.md`
- `build/skills/codex/contextify-query-debug/SKILL.md`

Provide a one-liner install instruction:

- `rsync -a build/skills/codex/ ~/.codex/skills/`

---

## Deliverable B: Claude Code skill/instructions (optional)

Claude’s skills mechanism differs from Codex; if we don’t have a reliable “installable skill” channel, ship a short “Contextify query usage” instruction file that users can drop into their Claude Code environment.

Phase 2 success does not require a first-class Claude skill if Codex adoption is the main driver.

---

## Deliverable C: CLI Install / Distribution Story

### DMG channel (preferred)

Goal: `contextify-query` is invokable as `contextify-query` from a typical shell.

Options:

1) Symlink into a PATH directory (preferred UX)
- Target: `/opt/homebrew/bin/contextify-query` if present else `/usr/local/bin/contextify-query`.
- Source: a bundled binary inside `Contextify.app` (stable path).
- Requires user consent; may require admin privileges.

2) User-writable install fallback
- Install to `~/bin/contextify-query`.
- Show a clear instruction to add `~/bin` to PATH.

Implementation notes:

- Provide an in-app “Install CLI…” UI (DMG only) that:
  - detects likely PATH dir
  - attempts install
  - on failure, prints copy/paste `sudo ln -sf ...` command
  - also offers uninstall

### App Store channel

Constraints: sandbox and review make “install into /usr/local/bin” impractical.

Supported approaches:

- Bundle the CLI in the app.
- Offer a user-driven install to a user-writable location (commonly `~/bin`) with explicit instruction.
- Provide a fallback: use absolute path to the bundled CLI.

Phase 2 can ship without perfect PATH ergonomics for App Store builds; prioritize clarity and a reliable fallback.

---

## QA / Validation

- Maintain a scripted runner for manual QA:
  - `build/notes/todo-support/CONTEXT-REINJECTION-qa-runner.sh`
- Add a Phase 2 skill QA doc:
  - verify Codex loads skills (skill appears in “list skills”)
  - verify end-to-end flow works using only skill guidance
- Add a DMG install QA checklist:
  - install
  - PATH presence
  - uninstall
  - upgrades (existing symlink)

---

## Open questions (Phase 2)

- Do we target Codex first and treat Claude Code as best-effort, or ship both skills in the same phase?
- Where do we store versioned skills in the repo (`build/skills/...` vs `build/docs/...`)?
- Preferred DMG install target:
  - `/opt/homebrew/bin` vs `/usr/local/bin` vs both?
- Do we ship a Homebrew formula/cask for the CLI (separate from the app)?
