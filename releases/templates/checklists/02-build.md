# Build Checklist

**Release:** {version}
**Phase:** 2 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## Automated Build (Recommended)

Run the release build script:

```bash
./scripts/release/build.sh {version}
```

This script:
- Validates tests pass
- Builds App Store archive (Release, sandboxed)
- Builds DMG (Release, signed, notarized)
- Archives to `build/archives/v{version}/`
- Updates `release.json` with results

### Verify Build Output

- [ ] Check archive directory: `ls -la build/archives/v{version}/`
- [ ] Verify App Store archive exists: `Contextify-AppStore.xcarchive`
- [ ] Verify DMG exists: `Contextify-{version}.dmg`
- [ ] Verify .pkg exists: `Contextify-{version}.pkg`

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
python3 scripts/release.py --version {version} --yes
./scripts/sparkle/sign.sh dist/Contextify-{version}.dmg
```

- [ ] DMG created: `dist/Contextify-{version}.dmg`
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
mkdir -p build/archives/v{version}
cp -R build/Contextify.xcarchive build/archives/v{version}/Contextify-AppStore.xcarchive
cp dist/Contextify-{version}.dmg build/archives/v{version}/
cp build/appstore/Contextify.pkg build/archives/v{version}/Contextify-{version}.pkg
```

</details>

---

## Validation

Run validation script:
```bash
./scripts/release/validate-build.sh {version}
```

## Sign-off

- [ ] All items complete
- [ ] Validation passed
- [ ] Ready for Phase 3: Review Materials

**Completed by:** ____
**Date:** ____
