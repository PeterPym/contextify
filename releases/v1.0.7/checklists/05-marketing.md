# Marketing Checklist

**Release:** 1.0.7
**Phase:** 5 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

**Reference:** See `build/docs/operations/PUBLIC-SURFACES.md` for complete inventory of public surfaces.

## Changelog (App Only)

### Verify Scope
- [ ] Confirm `releases/config/app-paths.txt` lists correct app directories

### Generate Draft
- [ ] Run: `./scripts/release/generate-release-notes.sh 1.0.7 --from v{prev_version}`
- [ ] If "No app changes" reported, verify this is expected or adjust `--from`

### Edit and Finalize
- [ ] Review: `releases/v1.0.7/assets/changelog.llm.md`
- [ ] Edit for clarity and user focus
- [ ] Save as: `releases/v1.0.7/assets/changelog.final.md`

### Update CHANGELOG.md
- [ ] Rename `[Unreleased]` to `[1.0.7] - YYYY-MM-DD`
- [ ] Insert content from `changelog.final.md`
- [ ] Add new empty `[Unreleased]` section
- [ ] Commit: `chore(release): update changelog for 1.0.7`

### Generate Derived Formats
- [ ] Generate HTML: `website/release-notes/1.0.7.html`
- [ ] Verify Sparkle appcast will use: `<sparkle:releaseNotesLink>`

## Appcast (Sparkle)

### Update Appcast
- [ ] Edit: `website/appcast.xml`
- [ ] Add new `<item>` for 1.0.7
- [ ] Include Sparkle signature from Phase 2
- [ ] Verify XML is valid

### Deploy Appcast
- [ ] Deploy website: `./scripts/deploy-website.sh`
- [ ] Verify appcast accessible: https://contextify.sh/appcast.xml

## GitHub Release (DMG)

### Create GitHub Release
- [ ] Go to: https://github.com/banagale/contextify/releases/new
- [ ] Tag: v1.0.7
- [ ] Title: Contextify 1.0.7
- [ ] Body: Copy from changelog
- [ ] Attach DMG: `dist/Contextify-1.0.7.dmg`
- [ ] Publish release

### Verify GitHub Release
- [ ] Release page accessible
- [ ] DMG downloadable
- [ ] Release notes render correctly

## Announcements

### Social Media
- [x] Twitter/X announcement drafted
- [x] Twitter/X posted: https://x.com/Contextify_sh/status/2003567517034512796
- [ ] Mastodon announcement drafted
- [ ] Mastodon posted: [ ] Yes / [ ] Skipped

### Community Posts
- [x] Hacker News post drafted
- [x] Hacker News posted: https://news.ycombinator.com/item?id=42369252
- [ ] Reddit (r/MacApps) post drafted
- [ ] Reddit posted: [ ] Yes / [ ] Skipped
- [ ] Reddit (r/ClaudeAI) post drafted
- [ ] Reddit (r/ClaudeAI) posted: [ ] Yes / [ ] Skipped

### Facebook
- [x] Facebook posted: https://www.facebook.com/share/p/15uGNFQ9Mg/
- [x] Facebook posted: https://www.facebook.com/share/p/16cjvNbjEi/

### Other Channels
- [x] LinkedIn: https://www.linkedin.com/feed/update/urn:li:share:7409336165499232257/
- [ ] Product Hunt: [ ] Yes / [ ] Skipped / [ ] Deferred
- [ ] Dev.to article: [ ] Yes / [ ] Skipped / [ ] Deferred
- [ ] Indie Hackers: [ ] Yes / [ ] Skipped / [ ] Deferred

## Sign-off

- [ ] Changelog published
- [ ] Appcast updated and deployed
- [ ] GitHub release created
- [ ] Ready for Phase 6: Post-Release

**Completed by:** ____
**Date:** ____
