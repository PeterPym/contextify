---
todo_id: CONTEXT-REINJECTION
title: Phase 2 QA checklist - skills + CLI install
type: guide
date: 2025-12-14
status: active
description: Manual QA checklist for Phase 2 adoption work: skills loading/verification and deterministic contextify-query invocation across DMG and App Store constraints.
---

# Phase 2 QA checklist: skills + CLI install

Record for each QA run:

- Date:
- Contextify version/build:
- Codex version:
- Claude Code version:

## A) CLI availability

1) `contextify-query` resolves on PATH

```bash
command -v contextify-query
```

Expected: prints a single path ending in `contextify-query`.

2) CLI responds

```bash
contextify-query status --json
```

Expected: exit code `0` and JSON output.

## A0) First-run onboarding (Contextify not installed yet)

If the skills are installed before Contextify is installed:

- Trigger `contextify-reinject`.
- Confirm the guidance:
  - explains Contextify must be installed first (because it ingests transcripts and builds the DB)
  - then instructs the user to run Contextify → “Install/Repair CLI…”
  - then retries the `contextify-query` command sequence

## B) Codex skills

Phase 2 does not ship Codex skills. This section is a Phase 2.1 follow-on once Codex skills are stable and documented.

1) Install skills

```bash
rsync -a --delete contextify-query/skills/codex/ ~/.codex/skills/
```

Expected: `~/.codex/skills/contextify-reinject/SKILL.md` exists and `~/.codex/skills/contextify-query-debug/SKILL.md` exists.

2) Start Codex with skills enabled

```bash
codex --enable skills
```

Expected: Codex starts normally.

3) Verify skills are loaded

Prompt inside the Codex session:

```text
list skills
```

Expected: output lists `contextify-reinject` and `contextify-query-debug` and includes the SKILL.md paths under `~/.codex/skills/`.

4) Reload behavior

- Edit one SKILL.md (change a visible line).
- In the existing session, ask again: `list skills`.
- Start a new session and ask again.

Expected: new content is visible only in the new session.

5) End-to-end reinjection

Prompt:

```text
Find prior context in Contextify about "<topic>", using contextify-query, then reinject the relevant neighborhood for this repo.
```

Expected: agent runs `contextify-query search ...` then `contextify-query context <uuid> ...` and returns a compact reinjection block.

## C) Claude Code skills (best-effort)

1) Install (preferred: plugin)

- Install/enable via Claude Code’s plugin UI/commands (record exact steps used and the plugin identifier).

2) Install (fallback: personal skills)

```bash
rsync -a --delete contextify-query/skills/claude/ ~/.claude/skills/
```

Expected: `~/.claude/skills/contextify-reinject/SKILL.md` exists.

3) Trigger behavior

Ask Claude Code a reinjection task that should obviously use the skill.

Expected: response uses `contextify-query` and follows the reinjection loop.

## D) Not-on-PATH behavior

In a clean shell where `contextify-query` is not on PATH (or after temporarily adjusting PATH), validate that skills guidance is still actionable:

- Skills do not hardcode `/Applications/Contextify.app/...` paths.
- Skills instruct the user to run Contextify → “Install/Repair CLI…” or to invoke the shim from a known location (recommended `~/bin/contextify-query`) if installed there.
