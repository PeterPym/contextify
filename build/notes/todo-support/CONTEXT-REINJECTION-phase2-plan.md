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

- Create `contextify-query/skills/claude/` and move skill templates there:
  - `contextify-query/skills/claude/contextify-reinject/SKILL.md`
  - `contextify-query/skills/claude/contextify-query-debug/SKILL.md`
- Move Codex templates into `contextify-query/skills/codex/` for symmetry, but treat Codex usage as Phase 2.1.
- Update references:
  - `build/notes/todo-support/CONTEXT-REINJECTION-phase2-spec.md`
  - `build/notes/todo-support/CONTEXT-REINJECTION-phase2-qa-checklist.md`

### 2) Add Claude Code plugin + marketplace files (repo-hosted)

- Add plugin root at `contextify-query/claude-plugin/` with:
  - `.claude-plugin/plugin.json` (name/version/description)
  - `skills/` populated from `contextify-query/skills/claude/`
- Add marketplace manifest at repo root:
  - `.claude-plugin/marketplace.json` with marketplace id `banagale-contextify`
  - entry for plugin id `contextify` with source `./contextify-query/claude-plugin`
- Add a short plugin README with install commands and “Contextify not installed” onboarding guidance.
- Update `build/notes/todo-support/CONTEXT-REINJECTION-claude-code-skills-installation.md` if commands differ from the spec.

### 3) Bundle `contextify-query` + skills into the app

- Add an Xcode build phase to copy:
  - the `contextify-query` CLI binary (existing build artifact) into the app bundle
  - `contextify-query/skills/` into `Contextify.app/Contents/Resources/contextify-query/skills/`
  - `contextify-query/claude-plugin/` into `Contextify.app/Contents/Resources/contextify-query/claude-plugin/` (for easy “open in Finder” / “copy commands” UX)
- Ensure this build phase is deterministic and does not require network access.

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

Unit tests:

- Given an app bundle path, generate shim text deterministically (marker present, path quoting safe).
- Recognize “our shim” vs third-party `contextify-query` executable for safe uninstall.

### 5) Implement Claude Code plugin onboarding UI

Add a Settings pane or onboarding affordance that:

- Shows the plugin install commands (copy button):
  - `/plugin marketplace add banagale/contextify`
  - `/plugin install contextify@banagale-contextify`
- Shows how to verify plugin loading (`claude --debug`) and notes restart requirement.
- Handles “Contextify not installed” messaging (skills already guide, but app should also be clear).

### 6) QA hardening

- Update/extend the Phase 2 QA checklist (`build/notes/todo-support/CONTEXT-REINJECTION-phase2-qa-checklist.md`) with any newly-implemented UI flows.
- Keep QA scripts alongside Phase 2 supporting docs while active.

### 7) Validation and review gate

Before merging:

- `swift test`
- `bash scripts/xc.sh build` (zero warnings)
- Run the Phase 2 checklist manually:
  - `build/notes/todo-support/CONTEXT-REINJECTION-phase2-qa-checklist.md`
