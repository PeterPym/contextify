---
feature: codex-skill-support
branch: feature/codex-skill-support
date: 2026-01-10
status: complete
---

# Codex Skill Support - Validation Plan

This document tracks the validation phases for the Codex CLI skill support feature.

**QA Script:** [`interactive-qa.sh`](./interactive-qa.sh)

---

## Phase 1: Code Review (External)
**Status: COMPLETE**

- [x] Submit to ChatGPT for review (iteration 1)
- [x] Address P0/P1 feedback
- [x] Submit iteration 2 for re-review
- [x] Receive "Ship" approval

**Outcome:** Approved after 2 iterations. All P0/P1 issues addressed.

---

## Phase 2: Build Validation
**Status: COMPLETE**

- [x] `bash scripts/xc.sh build` succeeds
- [x] Zero compiler warnings

**Outcome:** Build succeeds with 0 warnings.

---

## Phase 3: Unit Test Suite
**Status: COMPLETE**

- [x] `swift test` passes (all 314 tests)
- [x] New tests added for bug discovered during validation:
  - `PluginManifestDecodingTests` (5 test cases)

**Outcome:** 314 tests, 0 failures.

---

## Phase 4: Functional Validation (QA Scripts)
**Status: COMPLETE**

Run the interactive QA script:
```bash
./scripts/qa/codex-support/interactive-qa.sh
```

### 4.1 Install Plugin
- [x] `contextify-query install-plugin` exits 0
- [x] Success message displayed

### 4.2 Claude Skill Installation
- [x] `~/.claude/skills/total-recall/SKILL.md` exists
- [x] File is readable

### 4.3 Codex Skill Installation
- [x] `~/.codex/skills/total-recall/SKILL.md` exists
- [x] File is NOT a symlink (critical - Codex ignores symlinks)
- [x] Content identical to Claude skill

### 4.4 Uninstall Plugin
- [x] `contextify-query uninstall-plugin` exits 0
- [x] `~/.claude/skills/total-recall/` removed
- [x] `~/.codex/skills/total-recall/` removed

### 4.5 Settings UI Toggle (DMG Build Only)
- [ ] Open Contextify.app > Settings > CLI tab
- [ ] Click "Disable" - verify both skills removed
- [ ] Click "Enable" - verify both skills installed
- [ ] Verify Codex skill is real file (not symlink) after Enable

**Outcome:** All checks pass via interactive QA script. Settings UI toggle pending manual verification.

---

## Phase 5: CLI Integration Tests
**Status: COMPLETE**

Codex CLI integration verified via interactive QA script:

- [x] Codex CLI discovers total-recall skill
- [x] Codex CLI executes total-recall skill (returns search results)
- [x] Skill file read by Codex (proves not a symlink)

**Outcome:** Codex discovered skill, executed contextify-query, returned results.

---

## Phase 6: Edge Case Testing
**Status: COMPLETE**

### 6.1 Manifest Compatibility (Bug Found & Fixed)
- [x] Handles manifests with external plugins (swift-lsp)
- [x] Handles manifests with unknown fields (gitCommitSha)
- [x] Handles manifests with missing optional fields (isLocal)

**Bug found:** `PluginEntry.isLocal` was non-optional, causing decode failures when other plugins were installed. Fixed with test coverage in `PluginManifestDecodingTests`.

---

## Phase 7: Documentation Updates
**Status: COMPLETE**

- [x] Spec updated with validation proof requirements (`build/docs/specifications/total-recall-codex-support.md`)
- [x] AGENTS.md updated with CLI tool work section
- [x] Settings UI text updated for Codex compatibility

---

## Phase 8: Final Merge Readiness
**Status: READY**

Pre-merge checklist:
- [x] Build passes (0 warnings)
- [x] Tests pass (314 tests)
- [x] Code reviewed and approved
- [x] Functional validation passed (interactive QA script)
- [x] CLI integration tested (Codex discovers and executes skill)
- [x] Bug fix cherry-picked to main
- [x] Branch rebased on main

**Ready for merge to main.**

---

## Summary

| Phase | Status |
|-------|--------|
| 1. Code Review | COMPLETE |
| 2. Build Validation | COMPLETE |
| 3. Unit Tests | COMPLETE |
| 4. Functional Validation | COMPLETE |
| 5. CLI Integration | COMPLETE |
| 6. Edge Cases | COMPLETE |
| 7. Documentation | COMPLETE |
| 8. Merge Readiness | READY |

---

## Related Files

- **Spec:** `build/docs/specifications/total-recall-codex-support.md`
- **QA Script:** `scripts/qa/codex-support/interactive-qa.sh`
- **State Clearing:** `scripts/qa/codex-support/clear-state.sh`
- **Validation Script:** `scripts/qa/codex-support/validate-install.sh`
- **Unit Tests:** `Tests/ContextifyCoreTests/PluginManifestDecodingTests.swift`
