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

3) Entry ids are UUID strings

```bash
contextify-query search "test" --limit 1 --json
```

Expected: the first result’s `id` is a UUID string (no `e_` prefix).

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

In Claude Code:

```text
/plugin marketplace add PeterPym/contextify
/plugin install query@contextify
```

Expected:

- Claude Code prompts to install.
- After restart, `claude --debug` shows the plugin is loaded.

Local development validation (repo marketplace):

```bash
claude plugin marketplace add ./
claude plugin install query@contextify
```

Note: `claude plugin marketplace add .` is rejected; use `./`.

Verification (on-disk):

- Marketplace config: `~/.claude/plugins/known_marketplaces.json` contains `contextify`.
- Installed plugin record: `~/.claude/plugins/installed_plugins_v2.json` contains `query@contextify`.
- Plugin cache path exists:
  - `~/.claude/plugins/cache/contextify/query/<version>/`
- Skills exist in cache:
  - `~/.claude/plugins/cache/contextify/query/<version>/skills/contextify-reinject/SKILL.md`
  - `~/.claude/plugins/cache/contextify/query/<version>/skills/contextify-query-debug/SKILL.md`

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

## E) macOS 15 (Sequoia) VM QA gate

Run this on a macOS 15 VM to validate “Lite Mode” compatibility assumptions.

1) Install and launch Contextify (DMG build).

Expected:

- App launches successfully on macOS 15.
- UI does not assume summaries exist.

2) Verify “Install/Repair CLI…” flow is usable.

Expected:

- The install UI is present and functional.
- If installing to a user-writable folder (`~/bin`), it succeeds without requiring privileged writes.
- The installed shim runs: `contextify-query status --json` works (after the CLI is on PATH or invoked via full path).

3) Verify Claude Code plugin onboarding UI (or instructions) is accessible.

Expected:

- The UI/instructions can be used without any Apple Intelligence features.
- Copy/paste commands are visible and correct.
