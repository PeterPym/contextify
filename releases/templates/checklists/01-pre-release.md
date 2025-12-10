# Pre-Release Checklist

**Release:** {version}
**Phase:** 1 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## Code Quality

### Tests
- [ ] Run test suite: `swift test`
- [ ] Expected: All tests pass (currently 46 tests)
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
- [ ] Confirm version: {version}
- [ ] Follows semantic versioning (MAJOR.MINOR.PATCH)
- [ ] Current version in Xcode: `grep MARKETING_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1`

### Build Number (App Store)
- [ ] Check if this version was ever submitted to App Store:
  ```bash
  grep -A5 '"{version}"' releases/manifest.json | grep -q '"submitted"' && echo "Was submitted" || echo "Never submitted"
  ```
- [ ] If **never submitted**: Reset `CURRENT_PROJECT_VERSION` to `1`
- [ ] If **resubmitting after rejection**: Increment from last submitted build
- [ ] Current build in Xcode: `grep CURRENT_PROJECT_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1`

### Release Notes
- [ ] Draft release notes content
- [ ] Save to: `releases/v{version}/assets/release-notes-draft.md`

## Blockers Check

- [ ] Review P0 issues: `grep "P0" TODOS.md`
- [ ] All P0 issues resolved: [ ] Yes / [ ] No (list blockers below)

**Blockers:**
- (none)

## Validation

Run validation script:
```bash
./scripts/release/validate-pre-release.sh {version}
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
