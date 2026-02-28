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
| 3 | `03-review-materials.md` | **Changelog analysis**, demo video, sample data |
| 4 | `04-submission.md` | Upload, metadata, review notes |
| 5 | `05-marketing.md` | Publish changelog, announcements, press |
| 6 | `06-post-release.md` | Monitoring, feedback, documentation, Homebrew |

## Starting a New Release

### 1. Initialize Release Directory

```bash
# DMG-only release (direct download)
./scripts/release/init.sh X.Y.Z --dmg

# App Store-only release
./scripts/release/init.sh X.Y.Z --appstore

# Linux-only release (CLI tool)
./scripts/release/init.sh X.Y.Z --linux

# DMG + App Store (no Linux)
./scripts/release/init.sh X.Y.Z --both

# All channels (DMG + App Store + Linux)
./scripts/release/init.sh X.Y.Z --all
```

**You must specify which channels to target.** This is immutable after initialization.

This creates `releases/vX.Y.Z/` with:
- `release.json` (from template, with target_channels)
- `checklists/` (from templates, channel-appropriate)
- `README.md` (generated)

**Note:** For DMG-only releases, Phases 3 and 4 are automatically marked complete (no App Store review materials or submission needed).

### Incremental Shipping

If you need to ship channels separately (e.g., App Store first, DMG later):
- Use skip flags: `./scripts/release/build.sh 1.0.0 --skip-dmg --skip-linux`
- Or re-initialize with subset: `./scripts/release/init.sh 1.0.0 --appstore --reset`

The release remains valid for later channel builds - just run build.sh again without the skip flags.

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
./scripts/release/init.sh 1.0.0 --linux      # Linux CLI only
./scripts/release/init.sh 1.0.0 --both       # DMG + App Store
./scripts/release/init.sh 1.0.0 --all        # All channels (DMG + App Store + Linux)

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
# Build all targeted channels (recommended)
./scripts/release/build.sh 1.0.0

# Build App Store only (skip DMG and Linux)
./scripts/release/build.sh 1.0.0 --skip-dmg --skip-linux

# Build DMG only (skip App Store and Linux)
./scripts/release/build.sh 1.0.0 --skip-appstore --skip-linux

# Build macOS only (skip Linux)
./scripts/release/build.sh 1.0.0 --skip-linux

# Dry run (preview without building)
./scripts/release/build.sh 1.0.0 --dry-run
```

**Note:** Linux builds are done via GitHub Actions CI. The build script triggers the workflow, waits for completion (10-20 minutes), and downloads the artifacts. Both x86_64 and arm64 architectures are built.

### Status & Tracking

```bash
# Summary of all releases
./scripts/release/status.sh

# Details for specific version
./scripts/release/status.sh 1.0.0

# What's currently in production?
./scripts/release/status.sh --shipped

# What's in production for a specific channel?
./scripts/release/status.sh --shipped --dmg
./scripts/release/status.sh --shipped --appstore
./scripts/release/status.sh --shipped --linux

# What releases need work? (in progress, rejected, etc.)
./scripts/release/status.sh --active

# Channel status across all versions
./scripts/release/status.sh --dmg
./scripts/release/status.sh --appstore
./scripts/release/status.sh --linux
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

# Mark Linux as shipped (creates GitHub Release with artifacts)
./scripts/release/mark-shipped.sh 1.0.0 --linux

# Bypass guards if needed
./scripts/release/mark-shipped.sh 1.0.0 --dmg --force

# Mark as skipped (decided not to ship this version)
./scripts/release/mark-shipped.sh 1.0.0 --dmg --skipped
```

**Note:** The `--linux` option creates a GitHub Release (or uploads to an existing one) with both x86_64 and arm64 tarballs. This requires `gh` CLI to be authenticated.

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

### Version Audit (Post-Release)

After shipping, verify all channels are consistent:

```bash
# Query all live versions and check integrity
./scripts/release/version-audit.sh

# JSON output (for CI/automation)
./scripts/release/version-audit.sh --json

# Quiet mode (exit code only, for cron jobs)
./scripts/release/version-audit.sh --quiet
```

This verifies:
- GitHub DMG URL matches Sparkle appcast URL (binary integrity)
- Version numbers match across GitHub and Sparkle
- Linux CLI version matches DMG version (if applicable)
- DMG download infrastructure (macos-version + appcast + GitHub asset)

### DMG Download Consistency

After uploading a DMG to GitHub or before deploying the website:

```bash
# Check macos-version, appcast.xml, and GitHub are in sync
./scripts/release/check-dmg-consistency.sh

# Strict mode (appcast lag = error)
./scripts/release/check-dmg-consistency.sh --strict
```

This catches the case where `website/macos-version` points to a DMG that doesn't exist on GitHub (which causes a 404 on the download page). Also run automatically by `deploy-website.sh`.

**Exit codes:** 0 = all OK, 1 = inconsistencies found, 2 = fetch error

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

### macOS 15 (Lite Mode) Validation

If the release touches LLM features, run Lite Mode validation:

```bash
# Quick validation on macOS 26 (simulate Lite Mode)
./Contextify.app/Contents/MacOS/Contextify -simulate-legacy-macos
```

**Full validation (before any major release):**
1. Set up macOS 15 VM: `build/docs/testing/macos-vm-setup.md`
2. Run the 24-point checklist: `build/docs/testing/lite-mode-qa-checklist.md`
3. Seed test data: `scripts/qa/vm-bootstrap.sh`

**What to verify:**
- [ ] App launches without dyld crash
- [ ] Status bar shows "Lite Mode"
- [ ] Timeline displays with fallback content
- [ ] Core features work (search, indexing, project switching)
- [ ] No FoundationModels errors in Console

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
| `scripts/release/build-release.sh` | Release builds (DMG + App Store) | Standalone release build |
| `scripts/release/build.sh` | Release workflow build | Building with version tracking |
| `scripts/release/sign_cli.sh` | macOS CLI tarball (sign + notarize) | Homebrew distribution |

The release workflow script `scripts/release/build.sh` wraps `build-release.sh` with version tracking and archiving to `build/archives/v{VERSION}/`.

## CLI Artifact Build Matrix

The CLI binary ships as pre-built tarballs for Homebrew (macOS) and direct install (Linux).

| Artifact | Arch | Where Built | How | Output |
|----------|------|-------------|-----|--------|
| macOS CLI | arm64 | Local Mac (Apple Silicon) | `scripts/release/sign_cli.sh` | `build/cli-release/contextify-arm64.tar.gz` |
| macOS CLI | x86_64 | Local Mac (`swift build --arch x86_64`) | `scripts/release/sign_cli.sh --arch x86_64` | `build/cli-release/contextify-x86_64.tar.gz` |
| Linux CLI | x86_64 | GitHub Actions CI | `linux-release.yml` | `contextify-linux-x86_64.tar.gz` |
| Linux CLI | arm64 | GitHub Actions CI (QEMU, slow) | `linux-release.yml` | `contextify-linux-arm64.tar.gz` |

**macOS CLI builds** are produced by `scripts/release/sign_cli.sh`, which:
1. Runs `swift build -c release` for the target architecture
2. Signs with Developer ID certificate
3. Notarizes with Apple
4. Packages into a tarball with plugin files and user skill

By default it builds for the host machine's architecture (`uname -m`). To cross-compile for x86_64 on an Apple Silicon Mac, pass `--arch x86_64` to the script (e.g. `scripts/release/sign_cli.sh --arch x86_64`).

**Both macOS tarballs must be uploaded** to the GitHub release for Homebrew to work on both Intel and Apple Silicon Macs. The Homebrew formula selects the correct tarball based on `Hardware::CPU.arm?`.

**Linux CLI builds** are triggered by `scripts/release/build.sh` via `linux-release.yml` on GitHub Actions. x86_64 builds in ~10 minutes. arm64 uses QEMU and is slow (~60+ min), so it is typically skipped for minor releases.

## Handling Rejections

If App Store rejects the submission:

1. Add rejection note to `release.json` notes array
2. Update `checklists/04-submission.md` with rejection details
3. Address issues per rejection reason:
   - Metadata issue? Fix in App Store Connect, resubmit same build
   - Code issue? Fix code, increment build number, rebuild
4. Re-run relevant checklist items
5. Update `release.json` with new build number and resubmission

## Release Strategy

Contextify ships via three channels:

| Channel | Distribution | Ships |
|---------|--------------|-------|
| **DMG** | GitHub releases (+ Sparkle updates) | Immediately |
| **App Store** | App Store | After Apple review |
| **Linux CLI** | GitHub releases | With DMG |

**Strategy:** All channels built from same commit, same version. DMG and Linux ship immediately when built. Marketing waits for App Store approval.

### Build Both Distributions (Recommended)

```bash
# Build both DMG and App Store in one command
./scripts/release/build.sh X.Y.Z

# Or use the standalone build script (no release tracking)
./scripts/release/build-release.sh

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
python3 scripts/release/release.py --version X.Y.Z --yes
./scripts/sparkle/sign.sh dist/Contextify.dmg
```

**Note:** DMG uses stable filename `Contextify.dmg` (not versioned) to support GitHub's `/releases/latest/download/` URL.

**App Store Release:**
```bash
bash scripts/xc.sh --dist=appstore Release dev-archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload
```
</details>

## App Store Metadata (fastlane)

Fastlane automates uploading App Store metadata (description, release notes, promotional text) to App Store Connect.

### Single Source of Truth

All metadata lives in one file: `appstore-metadata/metadata.json`

This includes:
- App name, subtitle, description, keywords
- Promotional text, release notes
- Support/marketing/privacy URLs
- Copyright, categories
- Review information (contact, notes with sample data URLs)

### Metadata Snapshots

During Phase 4 (Submission), snapshot `metadata.json` into the release directory:

```bash
cp appstore-metadata/metadata.json releases/v{VERSION}/metadata.json
```

This preserves the exact metadata submitted for each version alongside other release artifacts, without needing to dig through git history. After the App Store version reaches "Ready for Sale," verify the working `metadata.json` reflects the approved state (it usually already does since it was the source for submission).

### Setup

```
appstore-metadata/
├── metadata.json          # Canonical source for all metadata
└── fastlane/
    ├── Deliverfile        # Reads from ../metadata.json
    └── Appfile            # App identification
```

API credentials in `.secrets/` (gitignored, see First-Time Setup below):
- `fastlane_api_key.json` - App Store Connect API key wrapper
- `AuthKey_AG868N57U6.p8` - The actual private key file

### First-Time Setup (`.secrets/`)

The `.secrets/` directory is gitignored. On a fresh clone or new machine, create it:

```bash
mkdir -p .secrets

# Copy the .p8 key (download from App Store Connect if needed:
# Users and Access > Integrations > Keys > AG868N57U6)
cp /path/to/AuthKey_AG868N57U6.p8 .secrets/

# Create the fastlane API key JSON wrapper.
# IMPORTANT: The "key" field must contain the .p8 file contents inline,
# NOT a file path. Fastlane rejects "key_filepath".
cat > .secrets/fastlane_api_key.json << 'JSONEOF'
{
  "key_id": "AG868N57U6",
  "issuer_id": "69a6de89-2083-47e3-e053-5b8c7c11a4d1",
  "key": "<paste contents of AuthKey_AG868N57U6.p8 here, including BEGIN/END lines>",
  "in_house": false
}
JSONEOF

# Or generate it automatically from the .p8 file:
python3 -c "
import json
key = open('.secrets/AuthKey_AG868N57U6.p8').read().strip()
json.dump({
    'key_id': 'AG868N57U6',
    'issuer_id': '69a6de89-2083-47e3-e053-5b8c7c11a4d1',
    'key': key,
    'in_house': False
}, open('.secrets/fastlane_api_key.json', 'w'), indent=2)
"
```

### Uploading Metadata

```bash
# IMPORTANT: Must run from the fastlane directory (Deliverfile resolves
# ../metadata.json relative to itself)
cd appstore-metadata/fastlane
fastlane deliver --skip_binary_upload --skip_screenshots
```

**Requirements:**
- An editable App Store version must exist (not in review, not approved)
- `.secrets/fastlane_api_key.json` must exist with inline key content (see above)
- `appstore-metadata/metadata.json` must have the current release_notes

**Notes:**
- Binary upload still uses `bash scripts/xc.sh upload` (altool, uses keychain profile)
- Screenshots are managed manually in App Store Connect
- Fastlane won't work while a version is in review
- The precheck step may warn but metadata uploads still succeed

### Workflow Integration

During release:
1. Update release_notes in `releases/v{VERSION}/metadata.json`
2. Copy to canonical location: `cp releases/v{VERSION}/metadata.json appstore-metadata/metadata.json`
3. Build and upload binary: `bash scripts/xc.sh --dist=appstore Release dev-archive && bash scripts/xc.sh export-pkg && bash scripts/xc.sh upload`
4. Upload metadata: `cd appstore-metadata/fastlane && fastlane deliver --skip_binary_upload --skip_screenshots`
5. Submit for review in App Store Connect
6. Snapshot: `cp appstore-metadata/metadata.json releases/v{VERSION}/metadata.json` (usually already done from step 1-2)

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

### App Store Version Display Quirk

App Store Connect mangles versions with 0 as the middle component:

| You enter | App Store shows | OK? |
|-----------|-----------------|-----|
| 2.0.0     | 2.0             | ✓ (truncated but fine) |
| 1.1.0     | 1.1             | ✓ (truncated but fine) |
| 1.1.1     | 1.1.1           | ✓ |
| 1.0.1     | 1.01            | ✗ (broken) |
| 1.0.2     | 1.02            | ✗ (broken) |

**Rule: Never use `x.0.y` where y > 0.**

Use standard semver, but expect Apple to truncate trailing `.0`:
- Major: `2.0.0` → displays as `2.0`
- Minor: `1.1.0` → displays as `1.1`
- Patch: `1.1.1` → displays as `1.1.1`

After a major release (`2.0.0`), go directly to `2.1.0` for the first minor/patch. Never `2.0.1`.

### Build Number Strategy

Apple requires build numbers to be unique **within a version**, not globally. Best practice:

**For a NEW version (never submitted to App Store):**
- Reset `CURRENT_PROJECT_VERSION` to `1` in Xcode project
- Start fresh - cleaner for App Store Connect history

**For a RESUBMISSION (same version, after rejection):**
- Increment from last submitted build number
- e.g., if build 2 was rejected, submit build 3

**How to check before bumping version:**
```bash
# Check if this version was ever submitted
grep -A5 '"X.Y.Z"' releases/manifest.json | grep -q '"submitted"' && echo "Was submitted" || echo "Never submitted"
```

**When to reset vs increment:**
| Scenario | Action |
|----------|--------|
| New version, never uploaded | Reset to build 1 |
| Rejected, metadata fix only | Increment build |
| Rejected, code fix needed | Increment build |
| DMG-only release, no App Store | Build number doesn't matter |

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

ghi789   1       1.0.1     DMG          Bug fix, ships to DMG users
                                        ← Tag v1.0.1 created at ghi789
ghi789   1       1.0.1     App Store    Submit bug fix (reset to build 1!)
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

### Binary Integrity Requirement

**CRITICAL:** The published DMG binary MUST match what Sparkle uses for auto-updates.

When shipping a DMG release:
1. The DMG uploaded to GitHub Releases is the canonical binary
2. The Sparkle appcast `<enclosure url="...">` MUST point to this exact file
3. The EdDSA signature in appcast must be generated from this same binary

**Why this matters:** If the URLs differ, users downloading from GitHub get a different binary than users updating via Sparkle. This breaks the chain of trust and can cause signature verification failures.

**Verification:** Run `./scripts/release/version-audit.sh` after any release to verify consistency. This should be part of Phase 6 (Post-Release) checklist.

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

## Homebrew Formula Updates

The CLI tool (`contextify-query`) is distributed via Homebrew for App Store users who can't get it bundled with the app (sandbox restrictions).

**Repo:** `~/code/projects/homebrew-contextify` (public: `github.com/PeterPym/homebrew-contextify`)

### When to Update

Update the Homebrew formula in Phase 6 (Post-Release), after:
1. Release tarball is uploaded to GitHub Releases
2. SHA256 is known
3. Caveats text matches new binary behavior

### Update Process

```bash
cd ~/code/projects/homebrew-contextify

# Update version
sed -i '' 's/version ".*"/version "X.Y.Z"/' Formula/contextify-query.rb

# Get SHA256 from release tarballs
curl -sL "https://github.com/PeterPym/contextify/releases/download/vX.Y.Z/contextify-arm64.tar.gz" | shasum -a 256
curl -sL "https://github.com/PeterPym/contextify/releases/download/vX.Y.Z/contextify-x86_64.tar.gz" | shasum -a 256

# Update sha256 in Formula with output
# Edit Formula/contextify-query.rb manually

# Commit and push
git add -A && git commit -m "chore(formula): bump to vX.Y.Z"
git push origin main
```

### Verification

```bash
brew update
brew upgrade contextify-query
contextify-query --version
contextify-query install-plugin
```

### Important Notes

- **Caveats must match binary behavior** - don't update caveats before the release binary exists
- **Pre-stage caveats changes** - for feature releases (new CLI behavior), create a branch with caveats updates ready to merge post-release
- **SHA256 is critical** - wrong hash = broken installs

## Known Gaps

**App Store Version Status Polling:** The current `poll-appstore-status.sh` only queries the live version via `altool --list-apps`. It cannot check pending/inflight version status (e.g., v1.1.0 while v1.0 is live). Need to:
- Add App Store Connect REST API integration (JWT auth with p8 key)
- Accept `--version X.Y.Z` parameter to query specific version
- Show status for all versions, not just the live one

Currently requires manual check in App Store Connect UI.

## Detailed Documentation

For more detailed procedures, see:
- `build/docs/operations/release/RELEASE-CHECKLIST.md` - Master checklist
- `build/docs/guides/APP-STORE-SUBMISSION.md` - App Store process
- `build/docs/operations/release/sparkle-updates.md` - Sparkle auto-updates
