# Marketing Checklist

**Release:** 1.0.1
**Phase:** 5 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

**Reference:** See `build/docs/operations/PUBLIC-SURFACES.md` for complete inventory of public surfaces.

## Changelog (App Only)

### Verify Scope
- [ ] Confirm `releases/config/app-paths.txt` lists correct app directories

### Generate Draft
- [ ] Run: `./scripts/release/generate-release-notes.sh 1.0.1 --from v{prev_version}`
- [ ] If "No app changes" reported, verify this is expected or adjust `--from`

### Edit and Finalize
- [ ] Review: `releases/v1.0.1/assets/changelog.llm.md`
- [ ] Edit for clarity and user focus
- [ ] Save as: `releases/v1.0.1/assets/changelog.final.md`

### Update CHANGELOG.md
- [ ] Rename `[Unreleased]` to `[1.0.1] - YYYY-MM-DD`
- [ ] Insert content from `changelog.final.md`
- [ ] Add new empty `[Unreleased]` section
- [ ] Commit: `chore(release): update changelog for 1.0.1`

### Generate Derived Formats
- [ ] Generate HTML: `website/release-notes/1.0.1.html`
- [ ] Verify Sparkle appcast will use: `<sparkle:releaseNotesLink>`

## Appcast (Sparkle)

### Update Appcast
- [ ] Edit: `website/appcast.xml`
- [ ] Add new `<item>` for 1.0.1
- [ ] Include Sparkle signature from Phase 2
- [ ] Verify XML is valid

### Deploy Appcast
- [ ] Deploy website: `./scripts/deploy-website.sh`
- [ ] Verify appcast accessible: https://contextify.sh/appcast.xml

## GitHub Release (DMG)

### Create GitHub Release
- [ ] Go to: https://github.com/banagale/contextify/releases/new
- [ ] Tag: v1.0.1
- [ ] Title: Contextify 1.0.1
- [ ] Body: Copy from changelog
- [ ] Attach DMG: `dist/Contextify-1.0.1.dmg`
- [ ] Publish release

### Verify GitHub Release
- [ ] Release page accessible
- [ ] DMG downloadable
- [ ] Release notes render correctly

## Announcements

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
- [ ] Ready for Phase 6: Post-Release

**Completed by:** ____
**Date:** ____
