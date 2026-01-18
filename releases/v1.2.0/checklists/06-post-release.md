# Post-Release Checklist

**Release:** 1.2.0
**Phase:** 6 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

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

## Public Surfaces Review

**Reference:** `build/docs/operations/PUBLIC-SURFACES.md`

Review each public surface and determine if this release requires updates.

### App Store Listing
- [ ] Parse `appstore-metadata/fastlane/metadata/en-US/description.txt`
- [ ] System requirements still accurate?
- [ ] Feature list reflects current capabilities?
- [ ] Screenshots show current UI? (if UI changed)
- [ ] Required updates: ____

### Website (contextify.sh)
- [ ] Parse `website/index.html` - landing page current?
- [ ] Parse `website/help/index.html` - help docs current?
- [ ] Parse `website/privacy.html` - privacy policy still accurate?
- [ ] Parse `website/support.html` - support links working?
- [ ] New release notes page created? `website/release-notes/1.2.0.html`
- [ ] Required updates: ____

### Public Repository
- [ ] Parse `~/code/projects/contextify-public-repo/README.md`
- [ ] Download links current? (or using dynamic forwarder)
- [ ] Feature list accurate?
- [ ] System requirements correct?
- [ ] Required updates: ____

### Appcast (Sparkle)
- [ ] New `<item>` added to `website/appcast.xml`?
- [ ] Download URL correct?
- [ ] Signature included?

### DMG Integrity Verification
Verify the publicly downloadable DMG matches the built artifact:
```bash
# Get expected hash from build
cat dist/Contextify-1.2.0.dmg.sha256

# Download and hash the public DMG
curl -sL "https://github.com/PeterPym/contextify/releases/download/v1.2.0/Contextify-1.2.0.dmg" | shasum -a 256
```
- [ ] Hashes match? [ ] Yes / [ ] No (STOP - investigate before proceeding)

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
- [ ] Monitor App Store reviews
- [ ] Monitor GitHub issues (when public)
- [ ] Monitor support email
- [ ] Any urgent issues? [ ] No / [ ] Yes (describe below)

### Auto-Updates (Sparkle)
**CRITICAL:** The 1.1.0 release had a broken Sparkle update due to build number mismatch.

#### Build Number Verification
Before announcing the release, verify the DMG build number matches appcast:
```bash
# 1. Download and mount the release DMG
curl -sL "https://github.com/PeterPym/contextify/releases/download/v1.2.0/Contextify-1.2.0.dmg" -o /tmp/verify.dmg
hdiutil attach /tmp/verify.dmg -nobrowse -quiet

# 2. Check build number in DMG
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Volumes/Contextify/Contextify.app/Contents/Info.plist

# 3. Check build number in appcast
curl -s https://contextify.sh/appcast.xml | grep -A5 "Version 1.2.0" | grep "sparkle:version"

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

## Cleanup

### Archive Release Materials
- [ ] Ensure `releases/v1.2.0/` is complete
- [ ] All artifacts documented
- [ ] All checklists filled out

### Update Manifest
- [ ] Update `releases/manifest.json` with final status
- [ ] Set `status: "complete"` for this release

### Git Housekeeping
- [ ] Release tag exists: `git tag -l v1.2.0`
- [ ] Release branch merged (if applicable)
- [ ] Working directory clean

## Issues Found

**Critical issues (if any):**
- (none)

**Non-critical issues to address in next release:**
- (none)

## Sign-off

- [ ] App Store approved and live
- [ ] DMG available via GitHub and website
- [ ] Sparkle updates working
- [ ] Documentation updated
- [ ] Monitoring in place
- [ ] Release complete

**Completed by:** ____
**Date:** ____

---

## Release Summary

**Version:** 1.2.0
**Released:** ____
**DMG:** https://github.com/banagale/contextify/releases/tag/v1.2.0
**App Store:** https://apps.apple.com/app/contextify/id6753190666

**Highlights:**
- (list key changes)

**Known Issues:**
- (none, or list)

**Next Release Planning:**
- (notes for next version)
