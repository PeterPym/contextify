# Build Checklist

**Release:** 1.0.6
**Phase:** 2 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## Automated Build (Recommended)

Run the release build script:

```bash
./scripts/release/build.sh 1.0.6
```

This script:
- Validates tests pass
- Builds App Store archive (Release, sandboxed)
- Archives to `build/archives/v1.0.6/`
- Updates `release.json` with results

### Verify Build Output

- [ ] Check archive directory: `ls -la build/archives/v1.0.6/`
- [ ] Verify App Store archive: `build/archives/v1.0.6/appstore/Contextify.xcarchive`
- [ ] Verify .pkg: `build/archives/v1.0.6/appstore/Contextify-1.0.6.pkg`

### Record Build Info

- [ ] Build number: ____
- [ ] Commit: ____

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

### App Store Build

```bash
# dev-archive creates a scratch build at build/Contextify.xcarchive
# This is for manual/partial builds only - prefer release/build.sh for official releases
bash scripts/xc.sh --dist=appstore Release dev-archive
bash scripts/xc.sh export-pkg
```

- [ ] Archive created: `build/Contextify.xcarchive`
- [ ] Package exported: `build/appstore/Contextify.pkg`

### Archive Artifacts

```bash
# Copy dev build to release location (only needed for manual builds)
mkdir -p build/archives/v1.0.6/appstore
cp -R build/Contextify.xcarchive build/archives/v1.0.6/appstore/Contextify.xcarchive
cp build/appstore/Contextify.pkg build/archives/v1.0.6/appstore/Contextify-1.0.6.pkg
```

</details>

---

## Validation

Run validation script:
```bash
./scripts/release/validate-build.sh 1.0.6
```

## Sign-off

- [ ] All items complete
- [ ] Validation passed
- [ ] Ready for Phase 3: Review Materials

**Completed by:** ____
**Date:** ____
