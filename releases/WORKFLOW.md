# Release Workflow

This document guides you through releasing a new version of Contextify.

## Prerequisites

Before starting any release work:

1. Read `releases/config.json` to understand the release configuration
2. Check `releases/manifest.json` for current release state
3. Ensure you're on the correct git branch (usually `main`)
4. Verify working directory is clean: `git status`

## Release Phases

Each release goes through 6 phases. Work through them in order:

| Phase | Checklist | Description |
|-------|-----------|-------------|
| 1 | `01-pre-release.md` | Tests, warnings, clean state, version planning |
| 2 | `02-build.md` | DMG and App Store archive builds |
| 3 | `03-review-materials.md` | Demo video, sample data for App Store |
| 4 | `04-submission.md` | Upload, metadata, review notes |
| 5 | `05-marketing.md` | Changelog, announcements, press |
| 6 | `06-post-release.md` | Monitoring, feedback, documentation |

## Starting a New Release

### 1. Initialize Release Directory

```bash
./scripts/release/init.sh X.Y.Z
```

This creates `releases/vX.Y.Z/` with:
- `release.json` (from template)
- `checklists/` (from templates)
- `README.md` (generated)

### 2. Follow Phase Checklists

Work through each checklist in `releases/vX.Y.Z/checklists/`:

1. Open the checklist for the current phase
2. Complete each task, marking `[x]` when done
3. Run validation scripts where indicated
4. Update `release.json` with results
5. Proceed to next phase

### 3. Update Release State

After completing each phase:
1. Update `releases/vX.Y.Z/release.json` with results
2. Mark checklist items complete
3. Run validation script for that phase

## Resuming Work on a Release

1. Read `releases/vX.Y.Z/release.json` to see current state
2. Find the first incomplete phase in `phases`
3. Continue from that checklist

## Quick Commands

```bash
# Check overall release status
./scripts/release/status.sh X.Y.Z

# Validate specific phase
./scripts/release/validate-pre-release.sh X.Y.Z
./scripts/release/validate-build.sh X.Y.Z
./scripts/release/validate-deployment.sh X.Y.Z
```

## Handling Rejections

If App Store rejects the submission:

1. Add rejection note to `release.json` notes array
2. Update `checklists/04-submission.md` with rejection details
3. Address issues per rejection reason:
   - Metadata issue? Fix in App Store Connect, resubmit same build
   - Code issue? Fix code, increment build number, rebuild
4. Re-run relevant checklist items
5. Update `release.json` with new build number and resubmission

## Two-Channel Release Strategy

Contextify ships via two channels:

| Channel | Target | Updates | Status |
|---------|--------|---------|--------|
| **DMG** | Contextify | Sparkle auto-updates | Ships immediately |
| **App Store** | Contextify AppStore | Apple updates | Ships after Apple review |

**Strategy:** DMG leads, App Store follows. Both built from same commit.

### DMG Release (ships immediately)

```bash
python3 scripts/release.py --version X.Y.Z --yes
./scripts/sparkle/sign.sh dist/Contextify-X.Y.Z.dmg
# Then: update appcast.xml, deploy to website
```

### App Store Release (ships after review)

```bash
bash scripts/xc.sh --dist=appstore Release archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload
# Then: complete submission in App Store Connect
```

## Version Sync Requirement

After release, all sources must match:
- Xcode project (`MARKETING_VERSION`)
- Git tag (`vX.Y.Z`)
- Appcast (`sparkle:shortVersionString`)
- App Store Connect
- GitHub Release

## File Locations

| File | Purpose |
|------|---------|
| `releases/config.json` | Static release configuration |
| `releases/manifest.json` | Release history and current state |
| `releases/vX.Y.Z/release.json` | Per-release complete state |
| `releases/vX.Y.Z/checklists/` | Task tracking with checkboxes |
| `releases/templates/` | Templates for new releases |

## Detailed Documentation

For more detailed procedures, see:
- `build/docs/operations/release/RELEASE-CHECKLIST.md` - Master checklist
- `build/docs/guides/APP-STORE-SUBMISSION.md` - App Store process
- `build/docs/operations/release/sparkle-updates.md` - Sparkle auto-updates
