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
  - first-run onboarding when Contextify is not installed yet

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

### Codex install/enable behavior

#### Install location

- Skills are discovered from `~/.codex/skills/`, where each skill is a directory containing `SKILL.md`.

#### Enable/disable

- Skills are enabled per session using `--enable skills`:
  - Enable: `codex --enable skills`
  - Disable: omit the flag

#### Verify skills are loaded

- In an active Codex session, prompt: `list skills`
- Expect the response to list:
  - skill names and descriptions
  - the filesystem path to `SKILL.md`

#### Reload behavior

- Skills are loaded once per session; changes require starting a new Codex session.

#### Upgrade/removal

- Upgrade: overwrite skill folders:
  - `rsync -a --delete build/skills/codex/ ~/.codex/skills/`
- Removal: delete a skill folder:
  - `rm -rf ~/.codex/skills/<skill-name>`

#### Constraints / gotchas

- Treat skills as an evolving feature; Phase 2 QA captures a “last verified” Codex version and date.
- Do not assume symlink behavior for skills; install as real directories/files.

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

Ship canonical skill content inside the repo as templates:

- `build/skills/codex/contextify-reinject/SKILL.md`
- `build/skills/codex/contextify-query-debug/SKILL.md`
- `build/skills/claude/contextify-reinject/SKILL.md`
- `build/skills/claude/contextify-query-debug/SKILL.md`

Provide a one-liner install instruction:

- `rsync -a --delete build/skills/codex/ ~/.codex/skills/`

### Cross-tool skill deployment

To avoid drift across tools, Phase 2 treats the repo (and the app bundle built from it) as the canonical source of skill content.

Deployment options:

- App-driven installer (preferred): Contextify provides “Install Skills…” with options for:
  - Codex (`~/.codex/skills/`)
- Claude Code plugin install (preferred for Claude Code): guides the user through plugin install/upgrade
- Claude Code personal skills (`~/.claude/skills/`) as a fallback when plugin install is unavailable
- Terminal install (fallback): `rsync` commands documented above.

Rules:

- Install skills as real directories/files (no symlinks).
- Each install flow provides a “Verify” step that is copy/pasteable and has expected output.

---

## Deliverable B: Claude Code skill/instructions (optional)

### Claude Code install/enable behavior

Claude Code supports skills via:

- Plugins (preferred for Phase 2 distribution)
- Personal skills on disk (fallback): `~/.claude/skills/`

#### Install (preferred: plugin)

Package the Contextify skills as a Claude Code plugin so users can install/upgrade via Claude’s plugin UX rather than copying folders manually.

This avoids introducing repo-local skill installs and keeps upgrades deterministic.

#### Install (fallback: personal skills)

- Install by copying the skill directory:
  - `mkdir -p ~/.claude/skills`
  - `rsync -a --delete build/skills/claude/ ~/.claude/skills/`

#### Verify

- Ask Claude Code to perform a reinjection task that should trigger the skill (for example: “Use Contextify to find context for <topic> in this repo and bring back the relevant neighborhood.”).
- Confirm the response uses `contextify-query` and follows the reinjection workflow.

#### Upgrade/removal

- Upgrade:
  - Plugin: use Claude Code’s plugin upgrade flow
  - Fallback: overwrite the skill folders (same rsync commands as install)
- Removal:
  - Plugin: uninstall the plugin
  - Fallback: delete the skill folder from `~/.claude/skills/<skill-name>`

### Claude Code content surface

Define which surface we ship for Claude Code in Phase 2:

- A skill (if supported), or
- A plugin/repo marketplace entry, or
- A drop-in instructions file and where it lives.

Phase 2 success does not require a first-class Claude skill if Codex adoption is the main driver.

---

## Deliverable C: CLI Install / Distribution Story

### Packaging requirement (Phase 2)

Homebrew is deferred. Phase 2 packages `contextify-query` with both distribution channels:

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
  - offers App Store mode: user-driven install into a user-chosen folder (recommend `~/bin`)
  - offers “Repair” when an existing shim/symlink is broken or points elsewhere
  - offers uninstall

### DMG install target selection

Target selection chain:

1) If `/opt/homebrew/bin` exists:
  - if writable: install shim there
  - else: provide a copy/paste `sudo` command to install
2) Else if `/usr/local/bin` exists:
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
  - verify Codex loads skills (`list skills` shows the Contextify skills)
  - verify end-to-end flow works using only skill guidance
  - record “last verified” date + Codex version
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

- Do we target Codex first and treat Claude Code as best-effort, or ship both skills in the same phase?
- Where do we store versioned skills in the repo (`build/skills/...` vs `build/docs/...`)?
- Preferred DMG install target:
  - `/opt/homebrew/bin` vs `/usr/local/bin` vs both?
- Homebrew: deferred (not a Phase 2 deliverable).

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
