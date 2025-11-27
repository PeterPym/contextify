# Marketing Checklist

**Release:** 1.0.0
**Phase:** 5 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

**Note:** Marketing tasks can begin after submission (Phase 4), before App Store approval.

## Changelog

### Write Changelog
- [ ] Create changelog entry for 1.0.0
- [ ] Include: New features, improvements, bug fixes
- [ ] Save to: `releases/v1.0.0/assets/changelog.md`

### Publish Changelog
- [ ] Update public changelog (when public repo exists)
- [ ] Update website release notes: `website/release-notes/1.0.0.html`

## Appcast (Sparkle)

### Update Appcast
- [ ] Edit: `website/appcast.xml`
- [ ] Add new `<item>` for 1.0.0
- [ ] Include Sparkle signature from Phase 2
- [ ] Verify XML is valid

### Deploy Appcast
- [ ] Deploy website: `./scripts/deploy-website.sh`
- [ ] Verify appcast accessible: https://contextify.sh/appcast.xml

## GitHub Release (DMG)

### Create GitHub Release
- [ ] Go to: https://github.com/banagale/contextify/releases/new
- [ ] Tag: v1.0.0
- [ ] Title: Contextify 1.0.0
- [ ] Body: Copy from changelog
- [ ] Attach DMG: `dist/Contextify-1.0.0.dmg`
- [ ] Publish release

### Verify GitHub Release
- [ ] Release page accessible
- [ ] DMG downloadable
- [ ] Release notes render correctly

## Announcements (After App Store Approval)

**Wait for App Store approval before announcing publicly.**

### Social Media
- [ ] Twitter/X announcement drafted
- [ ] Twitter/X posted: [ ] Yes / [ ] Skipped
- [ ] Mastodon announcement drafted
- [ ] Mastodon posted: [ ] Yes / [ ] Skipped

### Community Posts
- [ ] Hacker News post drafted
- [ ] Hacker News posted: [ ] Yes / [ ] Skipped
- [ ] Reddit (r/MacApps) post drafted
- [ ] Reddit posted: [ ] Yes / [ ] Skipped

### Other Channels
- [ ] Product Hunt: [ ] Yes / [ ] Skipped / [ ] Deferred
- [ ] Dev.to article: [ ] Yes / [ ] Skipped / [ ] Deferred
- [ ] Indie Hackers: [ ] Yes / [ ] Skipped / [ ] Deferred

## Sign-off

- [ ] Changelog published
- [ ] Appcast updated and deployed
- [ ] GitHub release created
- [ ] Announcements posted (after approval)
- [ ] Ready for Phase 6: Post-Release

**Completed by:** ____
**Date:** ____
