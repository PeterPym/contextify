# Post-Release Checklist

**Release:** {version}
**Phase:** 6 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

<!-- IF:appstore -->
## App Store Approval

### Monitor Review
- [ ] Check App Store Connect daily for status updates
- [ ] Review started: ____
- [ ] Review completed: ____
- [ ] Final status: [ ] Approved / [ ] Rejected

### If Rejected
- [ ] Return to Phase 4 (Submission) to handle rejection
- [ ] Document rejection in `release.json`

### If Approved
- [ ] App live on App Store: [ ] Yes
- [ ] Approval date: ____
- [ ] Proceed with remaining post-release tasks
<!-- ENDIF:appstore -->

## Public Surfaces Review

**Reference:** `build/docs/operations/PUBLIC-SURFACES.md`

Review each public surface and determine if this release requires updates.

**Note:** App Store listing content review moved to Phase 5 (Marketing) - should be done before submission.

### Website (contextify.sh)
- [ ] Parse `website/index.html` - landing page current?
- [ ] Parse `website/help/index.html` - help docs current?
- [ ] Parse `website/privacy.html` - privacy policy still accurate?
- [ ] Parse `website/support.html` - support links working?
- [ ] New release notes page created? `website/release-notes/{version}.html`
- [ ] Required updates: ____

### Public Repository
- [ ] Parse `~/code/projects/contextify-public-repo/README.md`
- [ ] Download links current? (or using dynamic forwarder)
- [ ] Feature list accurate?
- [ ] System requirements correct?
- [ ] Required updates: ____

<!-- IF:dmg -->
### Appcast (Sparkle)
- [ ] New `<item>` added to `website/appcast.xml`?
- [ ] Download URL correct?
- [ ] Signature included?

### Download Infrastructure Verification
Verify the download link, appcast, and GitHub are all in sync:
```bash
./scripts/release/check-dmg-consistency.sh --strict
```
- [ ] All checks passed? [ ] Yes / [ ] No (fix before proceeding)

### DMG Integrity Verification
Verify the publicly downloadable DMG matches the built artifact:
```bash
# Get expected hash from build
cat dist/Contextify-{version}.dmg.sha256

# Download and hash the public DMG
curl -sL "https://github.com/PeterPym/contextify/releases/download/v{version}/Contextify-{version}.dmg" | shasum -a 256
```
- [ ] Hashes match? [ ] Yes / [ ] No (STOP - investigate before proceeding)
<!-- ENDIF:dmg -->

## Documentation Updates

### Update Website
- [ ] Verify download links work
- [ ] Update any version-specific documentation
- [ ] Check all external links

### Update Support Docs
- [ ] FAQ updated for new features
- [ ] Known issues documented
- [ ] Troubleshooting guides current

### Update README
- [ ] Version badge updated (if applicable)
- [ ] Feature list current
- [ ] Installation instructions current

## Monitoring

### Crash Reporting
- [ ] Monitor for crash reports (first 24-48 hours)
- [ ] Any critical issues? [ ] No / [ ] Yes (describe below)

### User Feedback
<!-- IF:appstore -->
- [ ] Monitor App Store reviews
<!-- ENDIF:appstore -->
- [ ] Monitor GitHub issues (when public)
- [ ] Monitor support email
- [ ] Any urgent issues? [ ] No / [ ] Yes (describe below)

<!-- IF:dmg -->
### Auto-Updates (Sparkle)
**CRITICAL:** The 1.1.0 release had a broken Sparkle update due to build number mismatch.

#### Build Number Verification
Before announcing the release, verify the DMG build number matches appcast:
```bash
# 1. Download and mount the release DMG
curl -sL "https://github.com/PeterPym/contextify/releases/download/v{version}/Contextify-{version}.dmg" -o /tmp/verify.dmg
hdiutil attach /tmp/verify.dmg -nobrowse -quiet

# 2. Check build number in DMG
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Volumes/Contextify/Contextify.app/Contents/Info.plist

# 3. Check build number in appcast
curl -s https://contextify.sh/appcast.xml | grep -A5 "Version {version}" | grep "sparkle:version"

# 4. Cleanup
hdiutil detach /Volumes/Contextify -quiet
rm /tmp/verify.dmg
```
- [ ] DMG build number: ____
- [ ] Appcast build number: ____
- [ ] Numbers match? [ ] Yes / [ ] No (STOP - rebuild DMG with correct build number)

#### Live Update Test
- [ ] Install previous version (e.g., from `/Applications/` backup or previous DMG)
- [ ] Launch app and trigger "Check for Updates..."
- [ ] Update dialog shows correct version?
- [ ] Click "Install Update" - completes successfully?
- [ ] App relaunches with new version?
<!-- ENDIF:dmg -->

## Cleanup

### Archive Release Materials
- [ ] Ensure `releases/v{version}/` is complete
- [ ] All artifacts documented
- [ ] All checklists filled out

### Update Manifest

Record each channel as shipped. The script updates `releases/manifest.json`, `release.json`, `current_version`, and overall status automatically.

<!-- IF:dmg -->
- [ ] DMG shipped:
  ```bash
  ./scripts/release/mark-shipped.sh {version} --dmg
  ```
<!-- ENDIF:dmg -->
<!-- IF:appstore -->
- [ ] App Store approved:
  ```bash
  ./scripts/release/mark-shipped.sh {version} --appstore --build <BUILD_NUMBER>
  ```
<!-- ENDIF:appstore -->
<!-- IF:linux -->
- [ ] Linux shipped:
  ```bash
  ./scripts/release/mark-shipped.sh {version} --linux
  ```
<!-- ENDIF:linux -->
- [ ] Verify manifest is correct: `cat releases/manifest.json | python3 -m json.tool | grep -A20 '"{version}"'`

### Git Housekeeping
- [ ] Release tag exists: `git tag -l v{version}`
- [ ] Release branch merged (if applicable)
- [ ] Working directory clean

## Issues Found

**Critical issues (if any):**
- (none)

**Non-critical issues to address in next release:**
- (none)

## Sign-off

<!-- IF:appstore -->
- [ ] App Store approved and live
<!-- ENDIF:appstore -->
<!-- IF:dmg -->
- [ ] DMG available via GitHub and website
- [ ] Sparkle updates working
<!-- ENDIF:dmg -->
- [ ] Documentation updated
- [ ] Monitoring in place
- [ ] Release complete

**Completed by:** ____
**Date:** ____

---

## Release Summary

**Version:** {version}
**Released:** ____
<!-- IF:dmg -->
**DMG:** https://github.com/banagale/contextify/releases/tag/v{version}
<!-- ENDIF:dmg -->
<!-- IF:appstore -->
**App Store:** https://apps.apple.com/app/contextify/id6753190666
<!-- ENDIF:appstore -->

**Highlights:**
- (list key changes)

**Known Issues:**
- (none, or list)

**Next Release Planning:**
- (notes for next version)
