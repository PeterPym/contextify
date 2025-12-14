---
todo_id: CONTEXT-REINJECTION
title: Context reinjection Phase 2 - Skills + CLI install/distribution
type: spec
date: 2025-12-13
status: active
description: Define Phase 2 for context reinjection: ship Claude Code plugin skills that use contextify-query, plus a reliable CLI install/distribution story (DMG/App Store constraints).
---

# Phase 2: Claude Code Skills + `contextify-query` Install/Distribution

Phase 1 establishes a stable, read-only query surface (`contextify-query`) with deterministic results and machine-friendly JSON.

Phase 2 focuses on adoption: external agents reliably use that surface without bespoke prompting or fragile setup.

## Goals

- Make Claude Code reliably perform: search → anchor entry id → bounded context window → reinject.
- Provide a low-friction way for tools/humans to invoke `contextify-query`:
  - DMG: “it’s on PATH” is achievable.
  - App Store: provide a best-effort, user-consented flow that doesn’t fight sandbox constraints.
- Encode best practices in skills:
  - scoping (project vs global)
  - time filtering (`--days`)
  - budgeting (caps, truncation awareness)
  - error handling using structured error `details`
  - first-run onboarding when Contextify is not installed yet
- Preserve macOS 15 “Lite Mode” compatibility (no Apple Intelligence requirement for any Phase 2 deliverable).

## Non-goals

- MCP server transport.
- Writing to the Contextify database.
- A full “Copy with Context” UI flow in Contextify (can be Phase 3+).

---

## Phase 1 contract dependencies

Phase 2 assumes the Phase 1 `contextify-query` contract is implemented as specified in `build/notes/todo-support/CONTEXT-REINJECTION-spec.md`.

Minimum required CLI behaviors (skills depend on these):

- Read-only DB access (no writes) and stable JSON output via `--json`.
- Entry ids are UUID strings (no `e_` prefix).
- Commands:
  - `status --json`
  - `search <query> --json`
  - `context <entry-id> --json`
- Flags used by skills:
  - scoping: `--project .` (project resolution by path)
  - time: `--days N`
  - result size: `--limit N`
  - neighborhood size: `--before N --after N --max-window N`
- Errors:
  - `featureUnavailable` for missing FTS/search capability (no silent fallback).
  - `dbNotFound`, `dbProjectNotFound`, `entryNotFound` surfaced as structured errors (skills should treat `details.*` as optional).

## Legacy macOS (15) compatibility

Contextify currently targets macOS 26, but Phase 2 is written to stay compatible with the “Lite Mode” approach in `build/notes/todo-support/LEGACY-MACOS-spec.md`.

Requirements:

- Phase 2 must not introduce new dependencies on Apple Intelligence / `FoundationModels`.
- “Install/Repair CLI…” and any plugin/skills onboarding UI must work in Lite Mode (no summaries, no LLM queue).
- Any code paths that touch macOS 26-only APIs remain isolated behind `#available(macOS 26, *)` and have safe fallbacks.

## Deliverable A: Claude Code skill (plugin-first)

### Target mechanism

Claude Code supports skills via:

- Plugins (preferred for Phase 2 distribution)
- Personal skills on disk (fallback): `~/.claude/skills/`

Phase 2 targets Claude Code first because plugin-based distribution provides deterministic install/upgrade UX. Codex skills are a follow-on once Codex skill support is stable and documented.

### Claude Code plugin packaging/release story (pinned down)

Phase 2 ships a Claude Code plugin from this repository via a plugin marketplace.

Decisions:

- Marketplace repo (public-facing): `PeterPym/contextify`
- Marketplace id (marketplace.json.name): `contextify`
- Plugin id (target): `query`
- Plugin source path (within this repo): `./contextify-query/claude-plugin`

Development note:

- It is acceptable to validate the marketplace mechanics using a private development repo first, but the published installation instructions and marketplace source target `PeterPym/contextify`.
- If Claude Code requires the plugin id to match `plugin.json.name`, use `contextify-query@contextify` instead of `query@contextify`.

Plugin layout (Claude Code requirement):

- `contextify-query/claude-plugin/.claude-plugin/plugin.json`
- `contextify-query/claude-plugin/skills/contextify-reinject/SKILL.md`
- `contextify-query/claude-plugin/skills/contextify-query-debug/SKILL.md`
- `contextify-query/claude-plugin/hooks/hooks.json`
- `contextify-query/claude-plugin/scripts/session_start.py`

Marketplace manifest:

- `.claude-plugin/marketplace.json` at repo root with an entry for `contextify` pointing at `./contextify-query/claude-plugin`.

Versioning:

- `plugin.json.version` matches the Contextify app version (semver).
- Skills assume a minimum `contextify-query` CLI contract version and provide remediation (“update Contextify”) when flags/subcommands are missing.

Install/upgrade/uninstall (user steps):

1) Add the marketplace:
  - `/plugin marketplace add PeterPym/contextify`
2) Install:
  - `/plugin install query@contextify`
  - restart Claude Code after install
3) Upgrade:
  - re-run `/plugin install query@contextify` (then restart)
4) Uninstall:
  - `/plugin uninstall query@contextify`

If the plugin is installed before Contextify:

- Skills guide the user to install Contextify, then run Contextify → “Install/Repair CLI…”, then retry.

Session metadata capture:

- The plugin registers a `SessionStart` hook that persists:
  - `CONTEXTIFY_CLAUDE_SESSION_ID`
  - `CONTEXTIFY_CLAUDE_TRANSCRIPT_PATH`
  - `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID`
- Skills use `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` to avoid selecting search hits from the active transcript when better historical matches exist.

Local development validation:

- `claude plugin marketplace add ./`
- `claude plugin install query@contextify`

Observed on-disk behavior (Claude Code 2.0.65):

- Marketplaces persisted at `~/.claude/plugins/known_marketplaces.json`
- Installed plugins persisted at `~/.claude/plugins/installed_plugins_v2.json`
- Installed plugin cache copied to:
  - `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`

### Skill set

#### Skill 1: `contextify-reinject`

Purpose: Teach the canonical reinjection loop.

Required behaviors:

- If `contextify-query` is not found, guide the user through installing Contextify first (if needed), then installing/repairing the CLI, then retry.
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

Canonical skill source lives alongside the CLI contract surface:

- `contextify-query/skills/claude/**/SKILL.md`
- `contextify-query/skills/codex/**/SKILL.md` (Phase 2.1)

Build-time packaging copies these into the app bundle for shipping (DMG + App Store).

### Install

Preferred: package skills as a Claude Code plugin and distribute via Claude’s plugin install UX.

Fallback (for local development and early adopters):

- `mkdir -p ~/.claude/skills`
- `rsync -a --delete contextify-query/skills/claude/ ~/.claude/skills/`

### Cross-tool skill deployment

To avoid drift across tools, Phase 2 treats the repo (and the app bundle built from it) as the canonical source of skill content.

Deployment options:

- Claude Code plugin install (preferred): guides the user through plugin install/upgrade.
- Claude Code personal skills (`~/.claude/skills/`) as a fallback when plugin install is unavailable.
- Terminal install (fallback): `rsync` commands documented above.

Rules:

- Install skills as real directories/files (no symlinks).
- Each install flow provides a “Verify” step that is copy/pasteable and has expected output.

## Deliverable C: CLI Install / Distribution Story

### Packaging requirement (Phase 2)

Homebrew is deferred as a packaging channel for the CLI (no formula/cask).

Phase 2 still packages `contextify-query` with both distribution channels:

- DMG (Contextify)
- App Store (Contextify App Store)

This section defines how external tools get a stable, usable invocation path for the packaged CLI.

### Core approach: PATH entrypoint + repair flow

The preferred design is to bundle the `contextify-query` binary inside the app bundle and install a lightweight entrypoint on the user’s PATH.

This implies a clear behavior: the entrypoint must be repairable when the app moves/renames or the user changes PATH locations. The app provides an explicit “Install/Repair CLI…” action.

#### Preferred entrypoint: shim (recommended)

Install a small shim executable (or script) named `contextify-query` onto `PATH`. The shim locates the Contextify app bundle and then execs the bundled `contextify-query` binary.

Advantages:

- If the app moves, the shim can emit a clear remediation message (instead of “No such file or directory” from a broken symlink).
- The shim can support both DMG and App Store distribution with the same behavior.

#### Alternate entrypoint: symlink (simple)

A symlink to the bundled binary is simpler but produces a hard failure when the app moves. It is acceptable as a Phase 2 fallback, but the shim is preferred.

### DMG channel (preferred)

Goal: `contextify-query` is invokable as `contextify-query` from a typical shell.

Options:

1) Install shim into a PATH directory (preferred UX)
- Target: `/opt/homebrew/bin/contextify-query` if present else `/usr/local/bin/contextify-query`.
- Source: a shim that locates the app and runs the bundled binary.
- Requires user consent; may require admin privileges.

2) User-writable install fallback
- Install to `~/bin/contextify-query`.
- Show a clear instruction to add `~/bin` to PATH.

Implementation notes:

- Provide an in-app “Install/Repair CLI…” UI that:
  - detects likely PATH dir
  - offers DMG mode: install into `/opt/homebrew/bin` or `/usr/local/bin` with an authorization prompt or copy/paste `sudo` command fallback
  - offers App Store mode: user-driven install into a user-chosen folder (recommend `~/bin`) with a persisted security-scoped bookmark
  - offers “Repair” when an existing shim/symlink is broken or points elsewhere
  - offers uninstall

### DMG install target selection

Target selection chain:

1) If `/opt/homebrew/bin` exists (common on Homebrew systems):
  - if writable: install shim there
  - else: provide a copy/paste `sudo` command to install
2) Else if `/usr/local/bin` exists (common on non-Homebrew systems):
  - if writable: install shim there
  - else: provide a copy/paste `sudo` command to install
3) Else fallback to `~/bin`:
  - create `~/bin` if missing
  - provide a copy/paste PATH export line for common shells

Upgrade behavior:

- Replace only if the existing `contextify-query` is:
  - a shim installed by Contextify (marker embedded), or
  - a symlink pointing to a Contextify bundle path
- Otherwise, refuse and explain how to uninstall/rename the existing file.

Uninstall behavior:

- Remove only if it is recognized as Contextify’s shim/symlink target.

### App Store channel

Constraints: sandbox and review make “install into /usr/local/bin” impractical.

Supported approaches:

- Bundle the CLI in the app.
- Offer a user-driven install to a user-writable location (commonly `~/bin`) with explicit instruction.
- Provide a fallback: invoke a known shim path (if installed) or call the bundled binary via app-driven UI.

Phase 2 can ship without perfect PATH ergonomics for App Store builds; prioritize clarity and a reliable fallback.

#### App Store “Install/Repair CLI…” UX (pinned down)

This flow is user-driven and sandbox-safe:

1) Present a folder picker (recommend `~/bin`).
2) Persist a security-scoped bookmark for the chosen folder (same pattern as transcript folder bookmarks; see `build/docs/operations/app-store/sandbox-implementation-plan.md`).
3) Write `contextify-query` shim into that folder.
4) Show:
  - the installed path (e.g. `~/bin/contextify-query`)
  - the detected shell(s)
  - a copy/pasteable PATH line if `~/bin` is not already on PATH

Repair behavior:

- If the shim exists but fails to invoke the bundled CLI, re-write it (and keep the existing install location).
- If the bookmark is stale or missing, re-prompt for a folder.

Uninstall behavior:

- Remove the shim only if it matches the Contextify shim marker.
- Offer “Forget install location” (clears the bookmark).

### When `contextify-query` is not on PATH

Skills use this strategy:

1) Attempt: `contextify-query ...`
2) If unavailable, instruct the user to:
  - open Contextify and run “Install/Repair CLI…”, or
  - run the shim from a known location (recommended `~/bin/contextify-query`) if they installed it there

Skills do not hardcode `/Applications/Contextify.app/...` paths.

---

## QA / Validation

- Maintain a scripted runner for manual QA:
  - `build/notes/todo-support/CONTEXT-REINJECTION-qa-runner.sh`
- Use a Phase 2 adoption checklist:
  - `build/notes/todo-support/CONTEXT-REINJECTION-phase2-qa-checklist.md`
- Add a Phase 2 skills QA checklist:
  - verify Claude Code plugin install/upgrade works
  - verify end-to-end flow works using only skill guidance
  - record “last verified” date + Claude Code version
- Add a CLI install QA checklist:
  - install (DMG)
  - PATH presence
  - uninstall
  - upgrades (existing shim/symlink)
  - App Store user-driven install flow (folder picker)

## Skill versioning / compatibility

Skills avoid assuming flags that may not exist in older CLI versions.

Guidelines:

- Start flows with `contextify-query status --json` when capability is uncertain.
- On missing flags or subcommands:
  - instruct the user to update Contextify, or
  - fall back to a simpler query pattern.
- Keep the skills and CLI shipped from the same app release to avoid drift.

---

## Open questions (Phase 2)

- Claude Code plugin packaging details:
  - plugin identifier/name
  - install/upgrade commands or UI steps (as verified)
  - whether we publish to a marketplace vs provide a local install workflow

## Follow-on: Codex skills (Phase 2.1)

Codex skills are a follow-on once Codex skills support is stable and documented.

## Follow-on: Report aggregations (Phase 2.2)

Read-only `contextify-query report ...` aggregations are tracked as a follow-on to support query planning and demo-quality outputs:

- `build/notes/todo-support/CONTEXT-REINJECTION-report-aggregations.md`

---

## References

- Phase 1 spec: `build/notes/todo-support/CONTEXT-REINJECTION-spec.md`
- Phase 1 QA runner: `build/notes/todo-support/CONTEXT-REINJECTION-qa-runner.sh`
- Skills adoption research: `build/notes/todo-support/CONTEXT-REINJECTION-phase2-skills-research.md`
- Claude Code install reference: `build/notes/todo-support/CONTEXT-REINJECTION-claude-code-skills-installation.md`
- Phase 2 QA checklist: `build/notes/todo-support/CONTEXT-REINJECTION-phase2-qa-checklist.md`
- Local skills reference docs:
  - `build/notes/todo-support/CONTEXT-REINJECTION-agent-skills-overview-reference.md`
  - `build/notes/todo-support/CONTEXT-REINJECTION-agent-skills-developer-guide-reference.md`
  - `build/notes/todo-support/CONTEXT-REINJECTION-agent-skills-api-quickstart-reference.md`
  - `build/notes/todo-support/CONTEXT-REINJECTION-skill-authoring-best-practices-reference.md`
  - `build/notes/todo-support/CONTEXT-REINJECTION-claude-code-plugins-reference.md`
- Anthropic official skills docs: https://support.claude.com/en/articles/12512180-using-skills-in-claude
- Codex official skills doc: https://github.com/openai/codex/blob/main/docs/skills.md
- OpenAI skills overview (Simon Willison): https://simonwillison.net/2025/Dec/12/openai-skills/
