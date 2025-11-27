# Build Checklist

**Release:** 1.0.0
**Phase:** 2 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## DMG Build

### Build DMG
- [ ] Run: `python3 scripts/release.py --version 1.0.0 --yes`
- [ ] Verify DMG exists: `ls -la dist/Contextify-1.0.0.dmg`
- [ ] DMG size (bytes): ____

### Sign for Sparkle
- [ ] Run: `./scripts/sparkle/sign.sh dist/Contextify-1.0.0.dmg`
- [ ] Copy signature for appcast: ____

### Verify DMG
- [ ] Mount and test app launches
- [ ] Check code signature: `codesign -dv dist/Contextify-1.0.0.dmg`
- [ ] Check notarization: `spctl -a -vv dist/Contextify-1.0.0.dmg`

## App Store Build

### Archive
- [ ] Run: `bash scripts/xc.sh --dist=appstore Release archive`
- [ ] Verify archive: `ls -la build/Contextify.xcarchive`
- [ ] Preserve archive: `cp -R build/Contextify.xcarchive build/archives/v1.0.0.xcarchive`

### Export Package
- [ ] Run: `bash scripts/xc.sh export-pkg`
- [ ] Verify package: `ls -la build/appstore/Contextify.pkg`

### Record Build Number
- [ ] Build number: ____
- [ ] Update `release.json` with build number

## Validation

Run validation script:
```bash
./scripts/release/validate-build.sh 1.0.0
```

Paste output:
```
(paste here)
```

## Artifacts Reference

Update `releases/v1.0.0/artifacts/`:

```json
// dmg.json
{
  "path": "dist/Contextify-1.0.0.dmg",
  "sha256": "____",
  "sparkle_signature": "____"
}

// appstore.json
{
  "archive_path": "build/archives/v1.0.0.xcarchive",
  "build_number": ____
}
```

## Sign-off

- [ ] All items complete
- [ ] Validation passed
- [ ] Ready for Phase 3: Review Materials

**Completed by:** ____
**Date:** ____
