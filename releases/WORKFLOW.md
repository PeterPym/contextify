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
# DMG-only release (direct download)
./scripts/release/init.sh X.Y.Z --dmg

# App Store-only release
./scripts/release/init.sh X.Y.Z --appstore

# Both channels
./scripts/release/init.sh X.Y.Z --both
```

**You must specify which channels to target.** This is immutable after initialization.

This creates `releases/vX.Y.Z/` with:
- `release.json` (from template, with target_channels)
- `checklists/` (from templates, channel-appropriate)
- `README.md` (generated)

**Note:** For DMG-only releases, Phases 3 and 4 are automatically marked complete (no App Store review materials or submission needed).

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

## Release Scripts Reference

### Initialization

```bash
# Start a new release (must specify target channels)
./scripts/release/init.sh 1.0.0 --dmg        # DMG only
./scripts/release/init.sh 1.0.0 --appstore   # App Store only
./scripts/release/init.sh 1.0.0 --both       # Both channels

# Reset existing release for new build (preserves notes, target_channels, bumps build number)
./scripts/release/init.sh 1.0.0 --reset
```

### Session Context

```bash
# Quick summary of current release state (for Claude Code sessions)
./scripts/release/context.sh
```

### Building

```bash
# Build both DMG and App Store (recommended)
./scripts/release/build.sh 1.0.0

# Build App Store only
./scripts/release/build.sh 1.0.0 --skip-dmg

# Build DMG only
./scripts/release/build.sh 1.0.0 --skip-appstore

# Dry run (preview without building)
./scripts/release/build.sh 1.0.0 --dry-run
```

### Status & Tracking

```bash
# Summary of all releases
./scripts/release/status.sh

# Details for specific version
./scripts/release/status.sh 1.0.0

# What's currently in production?
./scripts/release/status.sh --shipped

# What's in production for DMG only?
./scripts/release/status.sh --shipped --dmg

# What's in production for App Store only?
./scripts/release/status.sh --shipped --appstore

# What releases need work? (in progress, rejected, etc.)
./scripts/release/status.sh --active

# App Store status across all versions
./scripts/release/status.sh --appstore
```

### Recording App Store Submissions

```bash
# Record that build was submitted to App Store Connect
./scripts/release/mark-submitted.sh 1.0.0 --build 5

# With custom date
./scripts/release/mark-submitted.sh 1.0.0 --build 5 --date 2025-11-28
```

### Recording App Store Rejections

```bash
# Interactive mode (prompts for guideline and reason)
./scripts/release/mark-rejected.sh 1.0.0 --interactive

# Non-interactive
./scripts/release/mark-rejected.sh 1.0.0 --guideline "2.1" --reason "Needs demo video"
```

After rejection, fix the issues and reset for a new build:
```bash
./scripts/release/init.sh 1.0.0 --reset
```

### Marking Releases as Shipped

```bash
# Mark DMG as shipped to production (requires built status + artifact)
./scripts/release/mark-shipped.sh 1.0.0 --dmg

# Mark App Store as approved (requires submitted status)
./scripts/release/mark-shipped.sh 1.0.0 --appstore --build 5

# Bypass guards if needed
./scripts/release/mark-shipped.sh 1.0.0 --dmg --force

# Mark as skipped (decided not to ship this version)
./scripts/release/mark-shipped.sh 1.0.0 --dmg --skipped
```

### Validation

```bash
# Check state consistency between files
./scripts/release/check-consistency.sh

# Check specific version
./scripts/release/check-consistency.sh 1.0.0
```

### Pre-Release Validation

```bash
# Validate pre-release requirements
./scripts/release/validate-pre-release.sh 1.0.0

# Validate build artifacts exist
./scripts/release/validate-build.sh 1.0.0
```

### Demo Recording

```bash
# Interactive demo recording (guides through setup)
./scripts/release/demo-recording.sh

# For specific version
./scripts/release/demo-recording.sh 1.0.0
```

### QA Testing

```bash
# Launch App Store build in clean state (full reset)
./scripts/release/test-app.sh

# Test DMG build instead
./scripts/release/test-app.sh --dmg

# Test specific version
./scripts/release/test-app.sh 1.1.0
./scripts/release/test-app.sh 1.1.0 --dmg

# Keep existing database (just relaunch)
./scripts/release/test-app.sh --keep-db

# Keep TCC permissions (skip permission dialog)
./scripts/release/test-app.sh --keep-tcc
```

### Release Notes Generation

Release notes are generated via LLM analysis of git history, scoped to app code only.

```bash
# Generate LLM draft from app changes
./scripts/release/generate-release-notes.sh 1.0.1

# Specify base ref (default: previous tag)
./scripts/release/generate-release-notes.sh 1.0.1 --from v1.0.0

# Include full diff for more context
./scripts/release/generate-release-notes.sh 1.0.1 --include-diff

# Preview without generating
./scripts/release/generate-release-notes.sh 1.0.1 --dry-run
```

**Scope:** Only changes to paths in `releases/config/app-paths.txt` are included.
Website, docs, and marketing changes are automatically excluded.

**Output:** `releases/vX.Y.Z/assets/changelog.llm.md`

**Workflow:**
1. Run generator to create LLM draft
2. Review and edit draft
3. Save as `changelog.final.md`
4. Update `CHANGELOG.md` with final content
5. Generate HTML for Sparkle and App Store text

## Build Scripts

Two build scripts serve different purposes:

| Script | Purpose | Use When |
|--------|---------|----------|
| `scripts/xc.sh` | Development builds, Xcode operations | Day-to-day development |
| `scripts/build-release.sh` | Release builds (DMG + App Store) | Standalone release build |
| `scripts/release/build.sh` | Release workflow build | Building with version tracking |

The release workflow script `scripts/release/build.sh` wraps `build-release.sh` with version tracking and archiving to `build/archives/v{VERSION}/`.

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

### Build Both Distributions (Recommended)

```bash
# Build both DMG and App Store in one command
./scripts/release/build.sh X.Y.Z

# Or use the standalone build script (no release tracking)
./scripts/build-release.sh

# Then:
# - DMG: update appcast.xml, deploy to website
# - App Store: upload and complete submission
bash scripts/xc.sh upload
```

### Manual Build (Alternative)

<details>
<summary>Individual commands if needed</summary>

**DMG Release:**
```bash
python3 scripts/release.py --version X.Y.Z --yes
./scripts/sparkle/sign.sh dist/Contextify-X.Y.Z.dmg
```

**App Store Release:**
```bash
bash scripts/xc.sh --dist=appstore Release dev-archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload
```
</details>

## Versions, Builds, and Tags

Three distinct concepts:

| Concept | Purpose | Example |
|---------|---------|---------|
| **Version** | User-facing release number | `1.0.0` |
| **Build** | Apple's per-submission counter | `4` |
| **Tag** | Git commit hash reference | `v1.0.0` → `82cd3dff` |

**Key rules:**
- Version = what users see (MARKETING_VERSION)
- Build = increments with each App Store upload (CURRENT_PROJECT_VERSION)
- Tag = points to exact commit hash, created once code is final
- Multiple builds can share the same version (rejected → fixed → resubmit)
- Tag captures the code, not the build number

### Example Timeline

```
Commit   Build   Version   Channel      Event
───────────────────────────────────────────────────────────
abc123   1       1.0.0     App Store    Initial submission
abc123   2       1.0.0     App Store    Rejected (metadata), resubmit same code
abc123   3       1.0.0     App Store    Rejected (needs demo video)
def456   4       1.0.0     App Store    Fixed, rebuilt, resubmit
                                        ← Tag v1.0.0 created at def456
def456   -       1.0.0     DMG          Ships immediately (same commit)
                                        ← App Store approved

ghi789   5       1.0.1     DMG          Bug fix, ships to DMG users
                                        ← Tag v1.0.1 created at ghi789
ghi789   6       1.0.1     App Store    Submit bug fix to App Store
```

**When channels diverge:**
- DMG can ship updates faster than App Store review cycle
- Each version gets its own tag pointing to its commit
- App Store may lag behind DMG by one or more versions
- Both channels eventually converge on same version

### Version Sync Requirement

After a version ships, these must match for that version:
- Xcode project (`MARKETING_VERSION`)
- Git tag (`vX.Y.Z`)
- Appcast (`sparkle:shortVersionString`) - DMG only
- App Store Connect - App Store only
- GitHub Release (optional)

## File Locations

| File | Purpose |
|------|---------|
| `releases/config.json` | Static release configuration |
| `releases/manifest.json` | Release history and current state |
| `releases/vX.Y.Z/release.json` | Per-release complete state |
| `releases/vX.Y.Z/checklists/` | Task tracking with checkboxes |
| `releases/templates/` | Templates for new releases |

## Canonical State Sources

When state appears in multiple places, these are the authoritative sources:

| Data | Canonical Source | Notes |
|------|------------------|-------|
| **Channel status** | `manifest.json` | `releases[version].dmg.status`, `releases[version].appstore.status` |
| **Artifact existence** | Filesystem | `build/archives/v{VERSION}/dmg/`, `build/archives/v{VERSION}/appstore/` |
| **Detailed history** | `release.json` | Phase statuses, notes, rejection details |

When files disagree, `manifest.json` wins for guards; `release.json` wins for human review.

See `STATUS-VALUES.md` for allowed status values.

## Detailed Documentation

For more detailed procedures, see:
- `build/docs/operations/release/RELEASE-CHECKLIST.md` - Master checklist
- `build/docs/guides/APP-STORE-SUBMISSION.md` - App Store process
- `build/docs/operations/release/sparkle-updates.md` - Sparkle auto-updates
