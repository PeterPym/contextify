# Build Checklist

**Release:** 1.0.1
**Phase:** 2 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## Automated Build (Recommended)

Run the release build script:

```bash
./scripts/release/build.sh 1.0.1
```

This script:
- Validates tests pass

- Builds DMG (Release, signed, notarized)

- Archives to `build/archives/v1.0.1/`
- Updates `release.json` with results

### Verify Build Output

- [ ] Check archive directory: `ls -la build/archives/v1.0.1/`

- [ ] Verify DMG: `build/archives/v1.0.1/dmg/Contextify-1.0.1.dmg`

### Record Build Info

- [ ] Build number: ____
- [ ] Commit: ____

- [ ] DMG SHA256: ____

---

## Build Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/xc.sh` | Development builds, Xcode operations |
| `scripts/build-release.sh` | Standalone release build (no tracking) |
| `scripts/release/build.sh` | Release workflow build (with tracking) |

---

## Manual Build (Alternative)

<details>
<summary>Use if automated build fails or for partial builds</summary>

### DMG Build

```bash
python3 scripts/release.py --version 1.0.1 --yes
./scripts/sparkle/sign.sh dist/Contextify-1.0.1.dmg
```

- [ ] DMG created: `dist/Contextify-1.0.1.dmg`
- [ ] Sparkle signature copied

### Archive Artifacts

```bash
# Copy dev build to release location (only needed for manual builds)
mkdir -p build/archives/v1.0.1/{appstore,dmg}

cp dist/Contextify-1.0.1.dmg build/archives/v1.0.1/dmg/

```

</details>

---

## Validation

Run validation script:
```bash
./scripts/release/validate-build.sh 1.0.1
```

## Sign-off

- [ ] All items complete
- [ ] Validation passed

- [ ] Ready for Phase 5: Marketing (DMG-only release)

**Completed by:** ____
**Date:** ____
