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
**Status: IN PROGRESS**

Run the app UI QA script:
```bash
./scripts/qa/codex-support/interactive-qa-app.sh
```

**Basic Flow (DONE):**
- [x] Auto-install on launch creates both skills
- [x] Click "Disable" - removes both skills
- [x] Click "Enable" - reinstalls both skills
- [x] Verify Codex skill is real file (not symlink)

**Edge Cases (TESTS ADDED, PENDING RUN):**
- [ ] Remove just Codex skill → verify app shows Repair button
- [ ] Click Repair → verify both restored
- [ ] Remove just Claude skill → verify app shows Repair button
- [ ] Click Repair → verify both restored

**Bugs fixed during validation:**
- `removeShimAndPlugin()` was not removing skill directories (fixed)
- `computeState()` was not checking skill file existence (fixed with repair state)

**Implementation complete:**
- Added `RepairReason` enum with cases: `claudeSkillMissing`, `codexSkillMissing`, `bothSkillsMissing`, `manifestMissing`
- Updated `State.enabled` to include `repairIssue: RepairReason?`
- Updated `computeState()` to detect partial installs and return appropriate repair reason
- Added `repair()` method that runs `contextify-query install-plugin`
- Updated UI to show yellow warning icon and "Repair" button when repair needed

**Outcome:** Implementation complete. QA script updated with edge case tests. Ready to run.

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

## Phase 8: Final Merge Readiness (macOS)
**Status: PENDING EDGE CASE TESTS**

Pre-merge checklist:
- [x] Build passes (0 warnings)
- [x] Tests pass (314 tests)
- [x] Code reviewed and approved
- [x] Functional validation passed (interactive QA script)
- [x] CLI integration tested (Codex discovers and executes skill)
- [x] Bug fix cherry-picked to main
- [x] Branch rebased on main
- [ ] **Settings UI toggle tested** - basic flow done, edge cases pending

**Pending:** Add edge case tests (partial install states) to QA script, then run again.

Note: Linux phases (10-13) are tracked separately as P0 blockers for v1.1.0 release.

---

## Phase 9: Homebrew Formula Update (Post-Release)
**Status: PENDING RELEASE**

The Homebrew formula must be updated AFTER the release is tagged and built.

**Pre-release prep (DONE):**
- [x] Formula caveats drafted in `~/code/projects/homebrew-contextify`
- [x] Branch: `feature/codex-skill-support`
- [x] Commit: `feat(formula): update caveats for Codex CLI support`

**Post-release steps:**
- [ ] Update `version` in Formula to match release tag
- [ ] Update `sha256` with hash from release tarball
- [ ] Merge branch to main
- [ ] Push to origin

**Why post-release:** The formula downloads a pre-built binary from GitHub releases. The caveats must match the binary's behavior. Updating caveats before the binary exists would mislead users.

**Verification after push:**
```bash
brew update
brew upgrade contextify-query
contextify-query install-plugin
ls ~/.codex/skills/total-recall/SKILL.md  # Should exist
```

---

## Phase 10: Linux Build Validation
**Status: NOT STARTED**

**Prerequisite:** contextify-query must be added to Linux Package.swift targets.

### 10.1 Package.swift Updates
- [ ] Add ContextifyQueryCLI to Linux products
- [ ] Add required sources to linuxSources array
- [ ] Add Platform/* adapters if needed

### 10.2 Local Build Test
```bash
# Docker-based Linux build
bash scripts/docker-linux-build.sh

# Verify binary exists
ls build/linux/contextify-query
```
- [ ] Build succeeds without errors
- [ ] Binary is executable

### 10.3 CI Integration
- [ ] Add contextify-query to `.github/workflows/linux-build.yml`
- [ ] CI builds both contextify-ingest AND contextify-query
- [ ] CI runs E2E test for contextify-query

---

## Phase 11: Linux Skill Installation
**Status: NOT STARTED**

Verify `install-plugin` works correctly on Linux.

### 11.1 Skill Installation
```bash
# In Docker or Linux VM
./contextify-query install-plugin

# Verify skills created
ls -la ~/.claude/skills/total-recall/SKILL.md
ls -la ~/.codex/skills/total-recall/SKILL.md
```
- [ ] install-plugin exits 0
- [ ] Claude skill file created
- [ ] Codex skill file created
- [ ] Codex skill is real file (not symlink)

### 11.2 Skill Uninstallation
```bash
./contextify-query uninstall-plugin

ls ~/.claude/skills/total-recall/  # Should not exist
ls ~/.codex/skills/total-recall/   # Should not exist
```
- [ ] uninstall-plugin exits 0
- [ ] Both skill directories removed

### 11.3 Database Connectivity (Linux)
```bash
# Create test database
./contextify-ingest ingest --db /tmp/test.db --input ~/.claude/projects/

# Query via contextify-query
./contextify-query --db /tmp/test.db status
./contextify-query --db /tmp/test.db search "test"
```
- [ ] contextify-query can read Linux-created database
- [ ] Search returns results

---

## Phase 12: CLI Doctor Command
**Status: NOT STARTED**

**Spec:** `build/notes/todo-support/LINUX-TOTAL-RECALL-spec.md`

### 12.1 Implementation
- [ ] Add `doctor` command to ContextifyQueryCLI
- [ ] Check shim on PATH
- [ ] Check plugin manifest entry
- [ ] Check Claude skill file
- [ ] Check Codex skill file
- [ ] Check database connectivity
- [ ] JSON output (`--json` flag)
- [ ] Self-repair option (`--fix` flag)

### 12.2 Validation (macOS)
```bash
# Full install - should be healthy
contextify-query install-plugin
contextify-query doctor
contextify-query doctor --json

# Remove one skill - should detect
rm -rf ~/.codex/skills/total-recall/
contextify-query doctor  # Should show degraded

# Repair
contextify-query doctor --fix
contextify-query doctor  # Should show healthy
```
- [ ] Reports healthy on full install
- [ ] Detects missing Codex skill
- [ ] `--fix` repairs missing skill
- [ ] JSON output is valid and parseable

### 12.3 Validation (Linux)
```bash
# In Docker
./contextify-query install-plugin
./contextify-query doctor
./contextify-query doctor --json
```
- [ ] Doctor works on Linux
- [ ] Reports correct status for Linux environment
- [ ] JSON output matches macOS format

---

## Phase 13: Linux Release Artifacts
**Status: NOT STARTED**

### 13.1 Release Tarball Contents
- [ ] Linux tarball includes BOTH binaries:
  - `contextify-ingest` (existing)
  - `contextify-query` (new)
- [ ] Both x86_64 and arm64 architectures

### 13.2 Installation Verification
```bash
# Simulate user installation
tar xzf contextify-linux-arm64.tar.gz
./contextify-query --version
./contextify-query install-plugin
./contextify-query doctor
```
- [ ] Extraction succeeds
- [ ] Both binaries work
- [ ] Skill installation works

---

## Summary

| Phase | Status |
|-------|--------|
| 1. Code Review | COMPLETE |
| 2. Build Validation | COMPLETE |
| 3. Unit Tests | COMPLETE |
| 4. Functional Validation | IN PROGRESS (edge cases) |
| 5. CLI Integration | COMPLETE |
| 6. Edge Cases | COMPLETE |
| 7. Documentation | COMPLETE |
| 8. Merge Readiness | PENDING EDGE CASES |
| 9. Homebrew Update | PENDING RELEASE |
| 10. Linux Build | NOT STARTED |
| 11. Linux Skill Install | NOT STARTED |
| 12. CLI Doctor | NOT STARTED |
| 13. Linux Release | NOT STARTED |

---

## Related Files

- **Codex Spec:** `build/docs/specifications/total-recall-codex-support.md`
- **Linux/Doctor Spec:** `build/notes/todo-support/LINUX-TOTAL-RECALL-spec.md`
- **QA Script (CLI):** `scripts/qa/codex-support/interactive-qa.sh`
- **QA Script (App UI):** `scripts/qa/codex-support/interactive-qa-app.sh`
- **State Clearing:** `scripts/qa/codex-support/clear-state.sh`
- **Validation Script:** `scripts/qa/codex-support/validate-install.sh`
- **Unit Tests:** `Tests/ContextifyCoreTests/PluginManifestDecodingTests.swift`
- **Homebrew Formula:** `~/code/projects/homebrew-contextify/Formula/contextify-query.rb`
- **Docker Build:** `scripts/docker-linux-build.sh`
- **Linux CI:** `.github/workflows/linux-build.yml`
