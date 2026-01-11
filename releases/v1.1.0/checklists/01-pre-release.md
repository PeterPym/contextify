# Pre-Release Checklist

**Release:** 1.1.0
**Phase:** 1 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## Code Quality

### Tests
- [ ] Run test suite: `swift test`
- [ ] Expected: All tests pass
- [ ] Actual result: ____

### Build Warnings
- [ ] Run build: `bash scripts/xc.sh build`
- [ ] Expected: 0 warnings
- [ ] Actual warnings: ____
- [ ] If warnings > 0, fix before proceeding

### Working Directory
- [ ] Check status: `git status`
- [ ] Expected: Clean (nothing to commit)
- [ ] If dirty, commit or stash changes

## Version Planning

### Version Number
- [ ] Confirm version: 1.1.0
- [ ] Follows semantic versioning (MAJOR.MINOR.PATCH)
- [ ] Current version in Xcode: `grep MARKETING_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1`

### Build Number (App Store)
- [ ] Check if this version was ever submitted to App Store:
  ```bash
  grep -A5 '"1.1.0"' releases/manifest.json | grep -q '"submitted"' && echo "Was submitted" || echo "Never submitted"
  ```
- [ ] If **never submitted**: Reset `CURRENT_PROJECT_VERSION` to `1`
- [ ] If **resubmitting after rejection**: Increment from last submitted build
- [ ] Current build in Xcode: `grep CURRENT_PROJECT_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1`

### Release Notes
- [ ] Draft release notes content
- [ ] Save to: `releases/v1.1.0/assets/release-notes-draft.md`

## Blockers Check

- [ ] Review P0 issues: `grep "P0" TODOS.md`
- [ ] All P0 issues resolved: [ ] Yes / [ ] No (list blockers below)

**Blockers:**
- (none)

---

## v1.1.0 Feature Blockers (P0)

This release targets Linux. Linux requires Total Recall to be useful.

**Spec:** `build/notes/todo-support/LINUX-TOTAL-RECALL-spec.md`

### Linux Total Recall Support

- [ ] #LINUX-QUERY-SOURCES: Add contextify-query to Linux Package.swift targets
- [ ] #LINUX-QUERY-BUILD: Get contextify-query building on Linux
- [ ] #LINUX-QUERY-CI: Add contextify-query to Linux CI workflow
- [ ] #LINUX-SKILL-INSTALL: Verify install-plugin creates both skill files on Linux

### CLI Installation Health Check

- [ ] #CLI-DOCTOR: Implement `contextify-query doctor` command
  - Check shim on PATH
  - Check plugin manifest
  - Check skill files (Claude + Codex)
  - Check database connectivity
  - JSON output for app integration (`--json`)
  - Self-repair option (`--fix`)

### Validation

```bash
# Linux build test (Docker)
bash scripts/docker-linux-build.sh --e2e

# Doctor command test
contextify-query doctor
contextify-query doctor --json

# Linux skill installation test (in Docker)
./contextify-query install-plugin
ls ~/.claude/skills/total-recall/SKILL.md
ls ~/.codex/skills/total-recall/SKILL.md
```

- [ ] Linux contextify-query builds successfully
- [ ] Doctor command reports healthy on full install
- [ ] Doctor command detects missing skills
- [ ] install-plugin creates both skill files on Linux

## Validation

Run validation script:
```bash
./scripts/release/validate-pre-release.sh 1.1.0
```

Paste output:
```
(paste here)
```

## Sign-off

- [ ] All items complete
- [ ] Validation passed
- [ ] Ready for Phase 2: Build

**Completed by:** ____
**Date:** ____
