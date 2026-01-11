---
todo_id: CONTEXT-REINJECTION
title: Phase 2 QA checklist - skills + CLI install
type: guide
date: 2025-12-14
status: active
description: Manual QA checklist for Phase 2 adoption work: skills loading/verification and deterministic contextify-query invocation across DMG and App Store constraints.
---

# Phase 2 QA checklist: skills + CLI install

Canonical interactive runner:

- `build/notes/todo-support/CONTEXT-REINJECTION-phase2-qa-runner.sh`

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

## A1) Bundled CLI sanity (DMG/App Store artifact)

Run these checks against the built `Contextify.app` to catch nested-binary signing/executability issues early.

1) Direct execution from the app bundle

```bash
"<Contextify.app>/Contents/MacOS/contextify-query" status --json
```

Expected: exit code `0` and JSON output.

2) Nested signing validity

```bash
codesign --verify --deep --strict "<Contextify.app>"
```

Expected: exit code `0`.

3) Architecture sanity

```bash
file "<Contextify.app>/Contents/MacOS/contextify-query"
```

Expected: output includes the expected architecture(s).

4) Gatekeeper-style assessment (best-effort; environment-dependent)

```bash
spctl --assess --type execute "<Contextify.app>/Contents/MacOS/contextify-query"
```

Expected: exit code `0` (if available/meaningful in the environment); treat failures as a diagnostic, not an automatic Phase 2 failure.

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
- Installed plugin record: `~/.claude/plugins/installed_plugins.json` contains `query@contextify`.
- Plugin cache path exists:
  - `~/.claude/plugins/cache/contextify/query/<version>/`
- Skills exist in cache:
  - `~/.claude/plugins/cache/contextify/query/<version>/skills/contextify-reinject/SKILL.md`
  - `~/.claude/plugins/cache/contextify/query/<version>/skills/contextify-query-debug/SKILL.md`
- Session metadata env vars (interactive session):
  - Run a prompt that triggers a Bash tool call, then ask for:
    - `echo "$CONTEXTIFY_CLAUDE_TRANSCRIPT_ID"`
  - Expected: best-effort.
    - If non-empty: value matches the active `.jsonl` filename (without `.jsonl`).
    - If empty: skills still behave correctly (they do not require the env vars).

### C0) Marketplace name collision (dev vs public)

Because the marketplace id is `contextify` for both local dev (`./`) and the public repo (`PeterPym/contextify`), Claude Code only keeps one installed at a time.

When switching sources, remove and re-add:

```text
/plugin marketplace remove contextify
/plugin marketplace add <desired source>
```

Expected: the marketplace source changes without installing duplicate `contextify` entries.

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

## F) App Store distribution manual QA (best-effort)

These checks validate the App Store constraints described in the Phase 2 spec. Some portions are intentionally not automated yet (tracked as follow-ons).

1) Build App Store distribution

```bash
bash scripts/xc.sh --dist=appstore Debug build
```

Expected: build succeeds with 0 warnings.

2) Bundle integrity (App Store)

Use the same checks as A1 (pointing at the App Store build’s `Contextify.app`), plus:

- The app bundle includes `contextify-query` and `contextify-query-shim` at the expected locations.
- The Claude plugin assets are present under `Contents/Resources/contextify-query/claude-plugin/`.

3) Settings → CLI tab install flow (App Store)

Manual:

- Launch Contextify App Store build.
- Open Settings → CLI tab.
- Use the “Install/Repair …” action.
- Pick a user-writable directory (recommend `~/bin`) if prompted.

Expected:

- The app requests access only as required (folder picker).
- After install, `command -v contextify-query` resolves to a path under the chosen directory.
- Re-opening Settings shows an installed state and offers repair/uninstall actions.

4) Repair flow (App Store; manual until QA-14 exists)

Manual:

- Quit the app.
- Delete the installed shim from the chosen directory.
- Relaunch the app and use “Repair” in the CLI tab.

Expected: shim is restored in the same directory without requiring the user to re-pick a folder.

Note: Automated coverage for this is tracked as `#QA-14-APPSTORE-CLI-REPAIR`.

5) Standalone execution behavior (App Store)

Manual:

```bash
"<Contextify.app>/Contents/MacOS/contextify-query" status --json
```

Expected: either:

- works and returns JSON (preferred), or
- fails with a documented, stable error envelope/exit code if sandbox constraints prevent standalone execution.

Note: current observed behavior is a crash in some environments; investigation is tracked as `#CONTEXTIFY-QUERY-APPSTORE-CLI`.

## G) Automated QA scripts (recommended)

Run the scripts below after the build checks above. These are designed to be readable and safe to run locally.

- Run all scripted QA tests: `bash scripts/qa/run-all-tests.sh`
- DMG UI-driven CLI install E2E: `bash scripts/qa/tests/QA-13-cli-install-dmg.sh`
- Bundle integrity (DMG + App Store): `bash scripts/qa/tests/QA-15-query-bundle-integrity.sh`

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
