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
<!-- IF:appstore -->
- Builds App Store archive (Release, sandboxed)
<!-- ENDIF:appstore -->
<!-- IF:dmg -->
- Builds DMG (Release, signed, notarized)
<!-- ENDIF:dmg -->
- Archives to `build/archives/v{version}/`
- Updates `release.json` with results

### Verify Build Output

- [ ] Check archive directory: `ls -la build/archives/v{version}/`
<!-- IF:appstore -->
- [ ] Verify App Store archive: `build/archives/v{version}/appstore/Contextify.xcarchive`
- [ ] Verify .pkg: `build/archives/v{version}/appstore/Contextify-{version}.pkg`
<!-- ENDIF:appstore -->
<!-- IF:dmg -->
- [ ] Verify DMG: `build/archives/v{version}/dmg/Contextify-{version}.dmg`
<!-- ENDIF:dmg -->

### Record Build Info

- [ ] Build number: ____
- [ ] Commit: ____
<!-- IF:dmg -->
- [ ] DMG SHA256: ____
<!-- ENDIF:dmg -->

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

<!-- IF:dmg -->
### DMG Build

```bash
python3 scripts/release.py --version {version} --yes
./scripts/sparkle/sign.sh dist/Contextify-{version}.dmg
```

- [ ] DMG created: `dist/Contextify-{version}.dmg`
- [ ] Sparkle signature copied
<!-- ENDIF:dmg -->

<!-- IF:appstore -->
### App Store Build

```bash
# dev-archive creates a scratch build at build/Contextify.xcarchive
# This is for manual/partial builds only - prefer release/build.sh for official releases
bash scripts/xc.sh --dist=appstore Release dev-archive
bash scripts/xc.sh export-pkg
```

- [ ] Archive created: `build/Contextify.xcarchive`
- [ ] Package exported: `build/appstore/Contextify.pkg`
<!-- ENDIF:appstore -->

### Archive Artifacts

```bash
# Copy dev build to release location (only needed for manual builds)
mkdir -p build/archives/v{version}/{appstore,dmg}
<!-- IF:appstore -->
cp -R build/Contextify.xcarchive build/archives/v{version}/appstore/Contextify.xcarchive
cp build/appstore/Contextify.pkg build/archives/v{version}/appstore/Contextify-{version}.pkg
<!-- ENDIF:appstore -->
<!-- IF:dmg -->
cp dist/Contextify-{version}.dmg build/archives/v{version}/dmg/
<!-- ENDIF:dmg -->
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
<!-- IF:appstore -->
- [ ] Ready for Phase 3: Review Materials
<!-- ENDIF:appstore -->
<!-- IF:dmg -->
<!-- UNLESS:appstore -->
- [ ] Ready for Phase 5: Marketing (DMG-only release)
<!-- ENDUNLESS:appstore -->
<!-- ENDIF:dmg -->

**Completed by:** ____
**Date:** ____
