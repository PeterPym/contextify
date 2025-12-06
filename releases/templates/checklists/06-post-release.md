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

<!-- IF:appstore -->
### App Store Listing
- [ ] Parse `appstore-metadata/fastlane/metadata/en-US/description.txt`
- [ ] System requirements still accurate?
- [ ] Feature list reflects current capabilities?
- [ ] Screenshots show current UI? (if UI changed)
- [ ] Required updates: ____
<!-- ENDIF:appstore -->

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
- [ ] Verify Sparkle updates work for existing users
- [ ] Test update from previous version
<!-- ENDIF:dmg -->

## Cleanup

### Archive Release Materials
- [ ] Ensure `releases/v{version}/` is complete
- [ ] All artifacts documented
- [ ] All checklists filled out

### Update Manifest
- [ ] Update `releases/manifest.json` with final status
- [ ] Set `status: "complete"` for this release

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
