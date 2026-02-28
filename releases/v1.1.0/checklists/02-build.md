# Build Checklist

**Release:** 1.1.0
**Phase:** 2 of 6
**Status:** [x] In Progress (macOS complete, Linux blocked)

## Automated Build (Recommended)

Run the release build script:

```bash
./scripts/release/build.sh 1.1.0
```

This script:
- Validates tests pass
- Builds App Store archive (Release, sandboxed)
- Builds DMG (Release, signed, notarized)
- Archives to `build/archives/v1.1.0/`
- Updates `release.json` with results

### Verify Build Output

- [x] Check archive directory: `ls -la build/archives/v1.1.0/`
- [x] Verify App Store archive: `build/archives/v1.1.0/appstore/Contextify.xcarchive`
- [x] Verify .pkg: `build/archives/v1.1.0/appstore/Contextify-1.1.0.pkg`
- [x] Verify DMG: `build/archives/v1.1.0/dmg/Contextify-1.1.0.dmg`

### Record Build Info

- [x] Build number: 1
- [x] Commit: fe177c811120d0543434ada34a948873c198d0a8
- [x] DMG SHA256: aa75a64ba878ac26935aa37c5eb267a8a3df4c941e33b182ea51c66ddcb3e03a

---

## macOS Build Results

| Channel | Artifact | Size | Status |
|---------|----------|------|--------|
| DMG | `Contextify-1.1.0.dmg` | 22 MB | Signed, notarized, stapled |
| App Store | `Contextify-1.1.0.pkg` | 20 MB | Ready for upload |
| App Store | `Contextify.xcarchive` | 135 MB | Includes dSYMs |

## Linux Build Status

**BLOCKED:** The `linux-release.yml` workflow fails on GitHub with "workflow file issue"

- All workflow runs fail before execution starts
- No logs generated (fails at parse/validation stage)
- The `linux-build.yml` (CI workflow) works correctly
- Only the release workflow is affected

**Investigation needed:**
- Check GitHub Actions web UI for detailed error
- Compare linux-release.yml with working linux-build.yml
- Try forcing GitHub to re-parse by making trivial change

---

## Build Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/xc.sh` | Development builds, Xcode operations |
| `scripts/release/build-release.sh` | Standalone release build (no tracking) |
| `scripts/release/build.sh` | Release workflow build (with tracking) |

---

## Manual Build (Alternative)

<details>
<summary>Use if automated build fails or for partial builds</summary>

### DMG Build

```bash
python3 scripts/release/release.py --version 1.1.0 --yes
./scripts/sparkle/sign.sh dist/Contextify-1.1.0.dmg
```

- [x] DMG created: `dist/Contextify-1.1.0.dmg`
- [ ] Sparkle signature copied

### App Store Build

```bash
# dev-archive creates a scratch build at build/Contextify.xcarchive
# This is for manual/partial builds only - prefer release/build.sh for official releases
bash scripts/xc.sh --dist=appstore Release dev-archive
bash scripts/xc.sh export-pkg
```

- [x] Archive created: `build/Contextify.xcarchive`
- [x] Package exported: `build/appstore/Contextify.pkg`

### Archive Artifacts

```bash
# Copy dev build to release location (only needed for manual builds)
mkdir -p build/archives/v1.1.0/appstore
cp -R build/Contextify.xcarchive build/archives/v1.1.0/appstore/Contextify.xcarchive
cp build/appstore/Contextify.pkg build/archives/v1.1.0/appstore/Contextify-1.1.0.pkg
mkdir -p build/archives/v1.1.0/dmg
cp dist/Contextify-1.1.0.dmg build/archives/v1.1.0/dmg/
```

</details>

---

## Validation

Run validation script:
```bash
./scripts/release/validate-build.sh 1.1.0
```

## Sign-off

- [x] macOS builds complete (DMG + App Store)
- [ ] Linux builds complete (BLOCKED)
- [ ] Validation passed
- [ ] Ready for Phase 3: Review Materials

**Completed by:** Claude
**Date:** 2026-01-11
**Note:** macOS ready to proceed. Linux requires workflow fix.
