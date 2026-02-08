# Pre-Release Checklist

**Release:** 1.2.0
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
- [ ] Confirm version: 1.2.0
- [ ] Follows semantic versioning (MAJOR.MINOR.PATCH)
- [ ] Current version in Xcode: `grep MARKETING_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1`

### Build Number (App Store)
- [ ] Get highest build number ever used:
  ```bash
  grep '"build_number"' releases/manifest.json | grep -o '[0-9]*' | sort -n | tail -1
  ```
- [ ] Increment by 1 for this release (build numbers NEVER reset, always increment globally)
- [ ] Current build in Xcode: `grep CURRENT_PROJECT_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1`
- [ ] Update `CURRENT_PROJECT_VERSION` to the new build number

### Release Notes
- [ ] Draft release notes content
- [ ] Save to: `releases/v1.2.0/assets/release-notes-draft.md`

## Blockers Check

- [ ] Review P0 issues: `grep "P0" TODOS.md`
- [ ] All P0 issues resolved: [ ] Yes / [ ] No (list blockers below)

**Blockers:**
- (none)

## Validation

Run validation script:
```bash
./scripts/release/validate-pre-release.sh 1.2.0
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
