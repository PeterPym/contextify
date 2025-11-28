# Build Checklist

**Release:** 1.0.0
**Phase:** 2 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## Automated Build (Recommended)

Run the release build script:

```bash
./scripts/release/build.sh 1.0.0
```

This script:
- Validates tests pass
- Builds App Store archive (Release, sandboxed)
- Builds DMG (Release, signed, notarized)
- Archives to `build/archives/v1.0.0/`
- Updates `release.json` with results

### Verify Build Output

- [ ] Check archive directory: `ls -la build/archives/v1.0.0/`
- [ ] Verify App Store archive exists: `Contextify-AppStore.xcarchive`
- [ ] Verify DMG exists: `Contextify-1.0.0.dmg`
- [ ] Verify .pkg exists: `Contextify-1.0.0.pkg`

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
python3 scripts/release.py --version 1.0.0 --yes
./scripts/sparkle/sign.sh dist/Contextify-1.0.0.dmg
```

- [ ] DMG created: `dist/Contextify-1.0.0.dmg`
- [ ] Sparkle signature copied

### App Store Build

```bash
bash scripts/xc.sh --dist=appstore Release archive
bash scripts/xc.sh export-pkg
```

- [ ] Archive created: `build/Contextify.xcarchive`
- [ ] Package exported: `build/appstore/Contextify.pkg`

### Archive Artifacts

```bash
mkdir -p build/archives/v1.0.0
cp -R build/Contextify.xcarchive build/archives/v1.0.0/Contextify-AppStore.xcarchive
cp dist/Contextify-1.0.0.dmg build/archives/v1.0.0/
cp build/appstore/Contextify.pkg build/archives/v1.0.0/Contextify-1.0.0.pkg
```

</details>

---

## Validation

Run validation script:
```bash
./scripts/release/validate-build.sh 1.0.0
```

## Sign-off

- [ ] All items complete
- [ ] Validation passed
- [ ] Ready for Phase 3: Review Materials

**Completed by:** ____
**Date:** ____
