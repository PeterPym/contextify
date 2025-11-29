# Release Guide

Complete guide for creating and distributing signed DMG releases of Contextify.

> **Note:** For managed releases with state tracking, use the workflow scripts in `scripts/release/`.
> See `releases/WORKFLOW.md` for the recommended approach with status tracking, guards, and consistency checking.

## Prerequisites

### Required Tools

All commands must be run on **macOS** (signing/notarization require macOS):

- `git` - Version control
- `gh` - GitHub CLI (logged in: `gh auth login`)
- `create-dmg` - DMG creation tool (install: `brew install create-dmg`)
- `python3` - Release automation scripts
- Xcode Command Line Tools

### Required Certificates & Credentials

1. **Developer ID Application Certificate**
   - Installed in macOS Keychain
   - Obtainable from: https://developer.apple.com/account/resources/certificates/list
   - Team: J8P5B23FK7 (Perch Innovations, Inc.)

2. **Notarization Credentials**
   - Stored in keychain as "NotaryProfile"
   - Setup once:
     ```bash
     xcrun notarytool store-credentials NotaryProfile \
       --apple-id your@email.com \
       --team-id J8P5B23FK7 \
       --password <app-specific-password>
     ```
   - App-specific password from: https://appleid.apple.com/account/manage

## Quick Start

### Full Release (Interactive)

```bash
make release
```

This runs the complete workflow:
1. Prompts for version number (auto-suggests patch bump)
2. Updates Xcode project version
3. Creates and pushes git tag
4. Builds Release configuration
5. Signs and notarizes DMG
6. Creates GitHub release with DMG + SHA256

### Automated Release (Non-Interactive)

Perfect for CI/CD or when you know the exact version:

```bash
# Fully automated - no prompts
python3 scripts/release.py --version 1.0.1 --yes

# Or via make
make release
```

**Available Arguments:**
- `--version X.Y.Z` - Specify exact version to release
- `--yes` / `-y` - Skip all confirmation prompts (auto-confirm)
- `--dry-run` - Preview what would happen without making changes
- `--no-notarize` - Skip notarization (faster testing, but DMG will show warnings)
- `--allow-dirty` - Allow uncommitted changes in working directory

**Examples:**

```bash
# Preview release of version 1.0.1
python3 scripts/release.py --version 1.0.1 --dry-run

# Fully automated release (for CI/CD)
python3 scripts/release.py --version 1.0.1 --yes

# Fast testing without notarization
python3 scripts/release.py --version 1.0.1 --yes --no-notarize

# Release with uncommitted changes (not recommended)
python3 scripts/release.py --version 1.0.1 --yes --allow-dirty
```

### Preview Only (Dry Run)

```bash
# Via make
make release-dry-run

# Or directly with specific version
python3 scripts/release.py --version 1.0.1 --dry-run
```

Shows what would happen without making any changes.

## Manual Workflow

If you need more control, run each step separately:

### Step 1: Build Release Configuration

```bash
# Build in Release mode (not Debug!)
make build-release

# Or directly:
bash scripts/xc.sh Release build
```

**Output:** `.derived/Build/Products/Release/Contextify.app`

**⚠️ IMPORTANT:** The default `make build` uses **Debug** configuration. Always use `make build-release` for distribution builds!

### Step 2: Sign and Create DMG

```bash
# With notarization (production)
make sign-dmg

# Without notarization (faster testing)
make sign-dmg-no-notarize

# Or directly:
python3 scripts/sign_and_notarize.py              # Full signing + notarization
python3 scripts/sign_and_notarize.py --no-notarize # Skip notarization
python3 scripts/sign_and_notarize.py --no-sign     # Skip signing (layout preview)
```

**Output:** `dist/Contextify.dmg`

The signing script:
- Signs all Mach-O binaries with hardened runtime
- Applies entitlements to main executable
- Signs outer app bundle
- Verifies signatures
- Creates DMG with custom background and layout
- Optionally notarizes via Apple's servers (~4 minutes)
- Staples notarization ticket to DMG

### Step 3: Create GitHub Release

```bash
# Generate SHA256 checksum
cd dist
shasum -a 256 Contextify.dmg > Contextify.dmg.sha256

# Create release (replace 1.0.0 with actual version)
gh release create v1.0.0 \
  Contextify.dmg \
  Contextify.dmg.sha256 \
  --title "Contextify 1.0.0" \
  --notes "Release notes here"
```

## Build Configuration Details

### Debug vs Release

| Configuration | Use Case | Optimizations | Outputs Path |
|--------------|----------|---------------|--------------|
| **Debug** | Development, testing | Disabled, includes debug symbols | `.derived/Build/Products/Debug/` |
| **Release** | Distribution, production | Enabled, stripped symbols | `.derived/Build/Products/Release/` |

### How to Specify Configuration

```bash
# Via xc.sh script (recommended)
bash scripts/xc.sh Debug build      # Debug (default)
bash scripts/xc.sh Release build    # Release

# Via Makefile
make build                          # Debug (default)
make build-release                  # Release

# Direct xcodebuild
xcodebuild -project Contextify/Contextify.xcodeproj \
  -scheme Contextify \
  -configuration Release \
  -derivedDataPath .derived \
  build
```

## Version Management

### Where Version is Stored

**Single Source of Truth:** Xcode project file
**Location:** `Contextify/Contextify.xcodeproj/project.pbxproj`
**Field:** `MARKETING_VERSION = "1.0.0";`

### How to Update Version

**Automated (Recommended):**
```bash
# Release script prompts for new version and updates automatically
python3 scripts/release.py
```

**Manual:**
```bash
# Edit in Xcode
open Contextify/Contextify.xcodeproj
# Navigate to: Project → Contextify → Build Settings → Marketing Version

# Or edit directly in project.pbxproj (search for MARKETING_VERSION)
```

**Version Format:** Semantic versioning `MAJOR.MINOR.PATCH` (e.g., `1.2.3`)

### Git Tags

Tags follow format: `v{VERSION}` (e.g., `v1.0.0`)

```bash
# List tags
git tag -l "v*"

# Create tag manually
git tag v1.0.0
git push origin v1.0.0
```

## Notarization Details

### What is Notarization?

Apple's security process that:
- Scans app for malware
- Validates code signatures
- Issues a "notarization ticket" if approved
- Prevents Gatekeeper warnings on user Macs

### Timeline

- **Submission:** Instant (via `create-dmg --notarize`)
- **Processing:** ~3-7 minutes (varies by Apple server load)
- **Stapling:** Instant (embeds ticket in DMG)

### Verification

```bash
# Check if DMG is notarized
spctl --assess --type install dist/Contextify.dmg

# Expected output:
# dist/Contextify.dmg: accepted
# source=Notarized Developer ID
```

### Troubleshooting Failed Notarization

```bash
# Get submission history
xcrun notarytool history --keychain-profile NotaryProfile

# Get detailed log for a submission
xcrun notarytool log <submission-id> --keychain-profile NotaryProfile
```

Common issues:
- **Unsigned binaries:** Ensure all Mach-O files are signed
- **Invalid entitlements:** Check `Contextify/Contextify.entitlements`
- **Hardened runtime violations:** All binaries need `--options runtime`

## DMG Customization

### Layout Configuration

**File:** `build/assets/dmg_settings.json`

```json
{
  "title": "Contextify",
  "background": "build/assets/dmg_background.png",
  "icon-size": 120,
  "window": {
    "size": {"width": 700, "height": 400}
  },
  "contents": [
    {"type": "file", "path": "Contextify.app", "x": 160, "y": 140},
    {"type": "link", "path": "/Applications", "x": 530, "y": 140}
  ]
}
```

### Background Image

**Location:** `build/assets/dmg_background.png`
**Dimensions:** 700×400 pixels
**Generator:** `scripts/generate_dmg_background.swift`

To regenerate:
```bash
swift scripts/generate_dmg_background.swift
```

## Release Checklist

Before running `make release`:

- [ ] All changes committed to git
- [ ] Tests passing (`make test`)
- [ ] Build succeeds in Release mode (`make build-release`)
- [ ] No P0 blockers in `build/notes/future-features.md`
- [ ] Release notes prepared
- [ ] Version number decided (follows semantic versioning)

After release:

- [ ] Download DMG from GitHub release
- [ ] Test installation on fresh Mac (or clean test account)
- [ ] Verify app launches without Gatekeeper warnings
- [ ] Verify core functionality works
- [ ] Announce release (optional)

## Troubleshooting

### "✖ Developer-ID certificate not found"

**Problem:** No Developer ID Application certificate in keychain

**Solution:**
1. Download certificate from https://developer.apple.com/account/resources/certificates/list
2. Double-click to install in Keychain Access
3. Verify: `security find-identity -p codesigning -v`

### "✖ Bundle not found: .derived/Build/Products/Release/Contextify.app"

**Problem:** Built in Debug mode instead of Release

**Solution:**
```bash
# Clean and rebuild in Release mode
make clean
make build-release
```

### "Gatekeeper: rejected (pre-notarization)"

**Problem:** This is EXPECTED before notarization

**Solution:** Continue with notarization. After stapling, run:
```bash
spctl --assess --type install dist/Contextify.dmg
# Should show "accepted" after notarization
```

### "codesign --verify --deep --strict" fails

**Problem:** Symlinks in Python venv point outside bundle

**Current Workaround:** Using `strict=False` mode (see line 173 in sign_and_notarize.py)

**Long-term Fix:** Phase 1 from `build/docs/operations/release/release-readiness.md` (venv auto-repair implemented)

## Reference

### FileKitty Comparison

Contextify's release infrastructure is adapted from FileKitty but differs:

| Aspect | FileKitty | Contextify |
|--------|-----------|------------|
| Language | Python (py2app) | Swift (Xcode) |
| Build Tool | `poetry + setup.py` | `xcodebuild` |
| Version Source | `pyproject.toml` | Xcode `MARKETING_VERSION` |
| Archive Format | ZIP | DMG |
| Distribution | GitHub + Homebrew | GitHub (App Store future) |

### Key Files

| File | Purpose |
|------|---------|
| `scripts/release.py` | End-to-end release automation |
| `scripts/sign_and_notarize.py` | DMG signing and notarization |
| `scripts/xc.sh` | Xcode build wrapper |
| `build/assets/dmg_settings.json` | DMG layout config |
| `build/assets/dmg_background.png` | DMG background image |
| `Contextify/Contextify.entitlements` | Code signing entitlements |
| `Makefile` | Convenience targets |

### Documentation

- Release readiness: `build/docs/operations/release/release-readiness.md`
- Distribution strategy: `build/docs/operations/marketing/distribution-strategy.md`
- Build scripts: `scripts/QUICK-REFERENCE.md`

## Advanced Usage

### Skip Specific Steps

```bash
# Build + sign, but skip GitHub release
python3 scripts/release.py --dry-run  # See what would happen
# Then manually upload DMG

# Sign existing build without rebuilding
python3 scripts/sign_and_notarize.py

# Create DMG layout preview without signing
python3 scripts/sign_and_notarize.py --no-sign
```

### Custom Version

Edit `Contextify/Contextify.xcodeproj/project.pbxproj` before running release script:

```bash
# Find and replace MARKETING_VERSION
sed -i '' 's/MARKETING_VERSION = "1.0.0"/MARKETING_VERSION = "2.0.0"/g' \
  Contextify/Contextify.xcodeproj/project.pbxproj

# Then run release
make release
```

### Environment Variables

```bash
# Skip app launch after build
CTX_NO_RUN=1 bash scripts/xc.sh Release build

# Use specific Xcode version
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  bash scripts/xc.sh Release build
```

---

## App Store Releases

For App Store submissions, **both distributions must be built from the same commit** to ensure version parity.

### Two-Target Architecture

Contextify uses **two separate Xcode targets** for different distribution channels:

| Target | Flag | Distribution | Sparkle | Sandbox |
|--------|------|--------------|---------|---------|
| **Contextify** | `--dist=dmg` | DMG (GitHub) | ✓ Included | No |
| **Contextify AppStore** | `--dist=appstore` | App Store | ✗ Excluded | Yes |

**Why?** Apple rejects App Store builds containing Sparkle.framework (unsandboxed executables). The `--dist` flag selects the correct target automatically.

### Complete Release Workflow (App Store + DMG)

When submitting a new version to the App Store:

```bash
# Recommended: Use the release build script (handles both App Store + DMG)
./scripts/release/build.sh X.Y.Z

# Then upload to App Store Connect
bash scripts/xc.sh upload

# Create GitHub release
gh release create vX.Y.Z build/archives/vX.Y.Z/dmg/Contextify-X.Y.Z.dmg --title "Contextify X.Y.Z"
```

**Alternative (manual builds):**
```bash
# 1. Ensure all changes committed
git status

# 2. Build and upload App Store version (dev-archive for scratch builds)
bash scripts/xc.sh --dist=appstore Release dev-archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload

# 3. Build and sign DMG (MUST do after App Store build to match)
bash scripts/xc.sh Release build
make sign-dmg

# 4. Create GitHub release (if not already done)
gh release create vX.Y.Z dist/Contextify.dmg --title "Contextify X.Y.Z"
```

### App Store Submission Steps

After uploading, complete these in App Store Connect:

1. **Wait** 5-15 min for Apple to process the build
2. **Select build** in App Store → macOS App → version
3. **Export compliance** (answer encryption questions, or skip if `ITSAppUsesNonExemptEncryption=false` in Info.plist)
4. **Submit for review**

Full guide: `build/docs/guides/APP-STORE-SUBMISSION.md`

### Re-submission Checklist

If you need to upload a new build (e.g., after fixing an issue):

- [ ] Fix the issue and commit
- [ ] Rebuild App Store version (`archive` → `export-pkg` → `upload`)
- [ ] **Rebuild DMG** (easy to forget - DMG must match App Store binary)
- [ ] Update GitHub release if needed
- [ ] Select new build in App Store Connect
- [ ] Re-submit for review

### Key Files

| File | Purpose |
|------|---------|
| `build/docs/guides/APP-STORE-SUBMISSION.md` | Full App Store submission guide |
| `appstore-metadata/metadata.json` | App Store metadata (description, screenshots, etc.) |
| `ExportOptions-AppStore.plist` | App Store export configuration |
| `build/releases/vX.Y.Z/` | Release artifacts archive |

---

**Last Updated:** 2025-11-25
**Maintained by:** Contextify Development Team
**Questions?** Open an issue at https://github.com/banagale/contextify/issues
