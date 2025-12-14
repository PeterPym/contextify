---
todo_id: CONTEXT-REINJECTION
title: Context reinjection Phase 2 implementation plan
type: plan
date: 2025-12-14
status: active
description: Medium-level implementation plan and expected commit series for CONTEXT-REINJECTION Phase 2 (Claude Code plugin skills + CLI install/distribution).
---

# Context reinjection Phase 2 - Implementation Plan

Implements `build/notes/todo-support/CONTEXT-REINJECTION-phase2-spec.md` as a sequence of small, reviewable commits with tests and zero warnings.

## Constraints

- Keep `contextify-query` a semi-independent deliverable that ships inside the app bundle.
- Prefer Claude Code plugin-based skill distribution; Codex skills are Phase 2.1.
- Preserve Phase 1 CLI contract (`build/notes/todo-support/CONTEXT-REINJECTION-spec.md`).
- Do not introduce new dependencies on Apple Intelligence / `FoundationModels` (Lite Mode compatible).
- Atomic commits only; run `swift test` and keep `bash scripts/xc.sh build` warning-free.

## Expected commit series

This is the intended commit shape; it can deviate if implementation realities demand it.

### 1) Canonicalize skill sources under `contextify-query/`

Completed on this branch:

- Canonical skills live at:
  - `contextify-query/skills/claude/contextify-reinject/SKILL.md`
  - `contextify-query/skills/claude/contextify-query-debug/SKILL.md`
- Codex templates live at:
  - `contextify-query/skills/codex/contextify-reinject/SKILL.md` (Phase 2.1)
  - `contextify-query/skills/codex/contextify-query-debug/SKILL.md` (Phase 2.1)

### 2) Add Claude Code plugin + marketplace files (repo-hosted)

Completed on this branch (derisked with Claude Code 2.0.65):

- Marketplace manifest at repo root:
  - `.claude-plugin/marketplace.json` with `name: "contextify"`
  - plugin entry `name: "query"` → `source: "./contextify-query/claude-plugin"`
- Plugin root at `contextify-query/claude-plugin/`:
  - `.claude-plugin/plugin.json` with `name: "query"`
  - `skills/` populated with the two skills

Install forms:

- Public-facing (future): `/plugin marketplace add PeterPym/contextify` then `/plugin install query@contextify`
- Local dev validation: `claude plugin marketplace add ./` then `claude plugin install query@contextify`

#### Marketplace name collision (dev vs public)

The marketplace id is `contextify` for both local dev (`./`) and the public marketplace repo (`PeterPym/contextify`). Claude Code keys marketplaces by name, so you cannot have both installed at once without replacement.

Dev workflow:

- Use `claude plugin marketplace remove contextify` before switching between local (`./`) and public (`PeterPym/contextify`).
- Re-add the desired marketplace source, then re-run `claude plugin install query@contextify`.

#### Session metadata capture (best-effort)

This branch implements a `SessionStart` hook that attempts to persist:

- `CONTEXTIFY_CLAUDE_SESSION_ID`
- `CONTEXTIFY_CLAUDE_TRANSCRIPT_PATH`
- `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID`

However, treat this as best-effort only:

- Skills must behave correctly when these env vars are missing.
- Phase 2 acceptance does not depend on session metadata capture being present (it is an optimization to avoid selecting the active transcript as a search hit).

#### Plugin version sync (must not drift)

Phase 2 expects `plugin.json.version` to track the Contextify app version.

Implementation requirement:

- Update `contextify-query/claude-plugin/.claude-plugin/plugin.json` version at build/release time from the app version source of truth (for example `MARKETING_VERSION`) so manual edits do not drift.

### 3) Bundle `contextify-query` + skills into the app

Pin down the bundling and executability details (this is production-critical):

- Choose a bundle location that supports nested code signing and direct execution:
  - Prefer `Contextify.app/Contents/MacOS/contextify-query` (or another executable-friendly location).
- Add an Xcode build phase to copy:
  - the `contextify-query` CLI binary into the chosen bundle location
  - `contextify-query/skills/` into `Contextify.app/Contents/Resources/contextify-query/skills/`
  - `contextify-query/claude-plugin/` into `Contextify.app/Contents/Resources/contextify-query/claude-plugin/`
- Add QA assertions:
  - run the bundled binary directly (not via shim) and confirm it executes
  - confirm the nested binary is signed/valid in the final DMG/App Store build

Acceptance checks (copy/paste):

- Direct execution:
  - `\"<Contextify.app>/Contents/MacOS/contextify-query\" status --json`
- Code-sign validity:
  - `codesign --verify --deep --strict \"<Contextify.app>\"`
- Gatekeeper assessment (best-effort; can vary by environment):
  - `spctl --assess --type execute \"<Contextify.app>/Contents/MacOS/contextify-query\"`
- Architecture sanity:
  - `file \"<Contextify.app>/Contents/MacOS/contextify-query\"`

### 4) Implement CLI entrypoint install: shim + repair

Implement “Install/Repair CLI…” in the app (DMG + App Store):

- DMG:
  - Target selection: `/opt/homebrew/bin` → `/usr/local/bin` → `~/bin`
  - Authorization: attempt direct write; otherwise provide copy/paste `sudo` command
- App Store:
  - Folder picker for install dir (recommend `~/bin`)
  - Persist security-scoped bookmark and reuse for repair/uninstall
- Shim format:
  - deterministic, includes a Contextify marker
  - execs the bundled `contextify-query` binary
  - prints actionable remediation if the app/binary cannot be found

#### Shim app discovery strategy (must be pinned)

Define how the shim locates the app bundle:

- Primary: LaunchServices lookup by bundle identifier (`sh.contextify.Contextify`).
- Multi-install tie-break (must be deterministic and unit-testable):
  1) Prefer App Store install by checking for `Contents/_MASReceipt/receipt`.
  2) Prefer highest `CFBundleVersion` (then `CFBundleShortVersionString`).
  3) Prefer lexicographically smallest bundle path.
  4) If still ambiguous, fail with remediation that lists candidates and instructs uninstall/repair.
- Fallback if LaunchServices returns no candidates:
  - check `/Applications/Contextify.app`, then fail with a clear error if missing.

Repair behavior for root-owned installs:

- If the shim is installed via `sudo` into `/opt/homebrew/bin` or `/usr/local/bin`, repairs must either:
  - present a new copy/pasteable `sudo` snippet to re-install the updated shim, or
  - offer switching to a user-writable install location (`~/bin`) and explain the tradeoff.

Unit tests:

- Given an app bundle path, generate shim text deterministically (marker present, path quoting safe).
- Recognize “our shim” vs third-party `contextify-query` executable for safe uninstall.

### 5) Implement Claude Code plugin onboarding UI

Add a Settings pane or onboarding affordance that:

- Shows the plugin install commands (copy button):
  - `/plugin marketplace add PeterPym/contextify`
  - `/plugin install query@contextify`
- Provides stable verification checks (cache path + installed plugin record) and notes restart requirement; treat `claude --debug` as an optional diagnostic.
- Handles “Contextify not installed” messaging (skills already guide, but app should also be clear).

### 6) QA hardening

- Update/extend the Phase 2 QA checklist (`build/notes/todo-support/CONTEXT-REINJECTION-phase2-qa-checklist.md`) with any newly-implemented UI flows.
- Keep QA scripts alongside Phase 2 supporting docs while active.

### 6.1 Skill branches (completeness pass)

Tighten skill guidance to cover real-world branches (keep concise):

- `search` returns 0 results:
  - widen `--days`
  - try without `--project .` if the cwd isn’t a known Contextify project
  - consult `contextify-query projects --json` for discovery
- `dbProjectNotFound`:
  - prompt user to pick from suggestions (when present) or explicitly pick a project
- `featureUnavailable`:
  - explain the missing capability; do not imply a fallback search exists
- “current session dominates results”:
  - if `CONTEXTIFY_CLAUDE_TRANSCRIPT_ID` is missing and the request is not about “this chat”, avoid auto-selecting anchors from the last 30 minutes when multiple plausible hits exist

### 7) Validation and review gate

Before merging:

- `swift test`
- `bash scripts/xc.sh build` (zero warnings)
- Run the Phase 2 checklist manually:
  - `build/notes/todo-support/CONTEXT-REINJECTION-phase2-qa-checklist.md`
