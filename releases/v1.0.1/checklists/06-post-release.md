# Post-Release Checklist

**Release:** 1.0.1
**Phase:** 6 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## Public Surfaces Review

**Reference:** `build/docs/operations/PUBLIC-SURFACES.md`

Review each public surface and determine if this release requires updates.

### Website (contextify.sh)
- [ ] Parse `website/index.html` - landing page current?
- [ ] Parse `website/help/index.html` - help docs current?
- [ ] Parse `website/privacy.html` - privacy policy still accurate?
- [ ] Parse `website/support.html` - support links working?
- [ ] New release notes page created? `website/release-notes/1.0.1.html`
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
- [ ] Monitor GitHub issues (when public)
- [ ] Monitor support email
- [ ] Any urgent issues? [ ] No / [ ] Yes (describe below)

### Auto-Updates (Sparkle)
- [ ] Verify Sparkle updates work for existing users
- [ ] Test update from previous version

## Cleanup

### Archive Release Materials
- [ ] Ensure `releases/v1.0.1/` is complete
- [ ] All artifacts documented
- [ ] All checklists filled out

### Update Manifest
- [ ] Update `releases/manifest.json` with final status
- [ ] Set `status: "complete"` for this release

### Git Housekeeping
- [ ] Release tag exists: `git tag -l v1.0.1`
- [ ] Release branch merged (if applicable)
- [ ] Working directory clean

## Issues Found

**Critical issues (if any):**
- (none)

**Non-critical issues to address in next release:**
- (none)

## Sign-off

- [ ] DMG available via GitHub and website
- [ ] Sparkle updates working
- [ ] Documentation updated
- [ ] Monitoring in place
- [ ] Release complete

**Completed by:** ____
**Date:** ____

---

## Release Summary

**Version:** 1.0.1
**Released:** ____
**DMG:** https://github.com/banagale/contextify/releases/tag/v1.0.1

**Highlights:**
- (list key changes)

**Known Issues:**
- (none, or list)

**Next Release Planning:**
- (notes for next version)
