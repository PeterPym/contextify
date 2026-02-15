# Marketing Checklist

**Release:** {version}
**Phase:** 5 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

<!-- IF:appstore -->
**Note:** Marketing tasks can begin after submission (Phase 4), before App Store approval.
<!-- ENDIF:appstore -->

**Reference:** See `build/docs/operations/PUBLIC-SURFACES.md` for complete inventory of public surfaces.

## Changelog (App Only)

### Verify Scope
- [ ] Confirm `releases/config/app-paths.txt` lists correct app directories

### Generate Draft
- [ ] Run: `./scripts/release/generate-release-notes.sh {version} --from v{prev_version}`
- [ ] If "No app changes" reported, verify this is expected or adjust `--from`

### Edit and Finalize
- [ ] Review: `releases/v{version}/assets/changelog.llm.md`
- [ ] Edit for clarity and user focus
- [ ] Save as: `releases/v{version}/assets/changelog.final.md`

### Update CHANGELOG.md
- [ ] Rename `[Unreleased]` to `[{version}] - YYYY-MM-DD`
- [ ] Insert content from `changelog.final.md`
- [ ] Add new empty `[Unreleased]` section
- [ ] Commit: `chore(release): update changelog for {version}`

### Generate Derived Formats
<!-- IF:appstore -->
- [ ] Copy to App Store: `appstore-metadata/fastlane/metadata/en-US/release_notes.txt`
<!-- ENDIF:appstore -->
<!-- IF:dmg -->
- [ ] Generate HTML: `website/release-notes/{version}.html`
- [ ] Verify Sparkle appcast will use: `<sparkle:releaseNotesLink>`
<!-- ENDIF:dmg -->

<!-- IF:dmg -->
## Appcast (Sparkle)

### Update Appcast
- [ ] Edit: `website/appcast.xml`
- [ ] Add new `<item>` for {version}
- [ ] Include Sparkle signature from Phase 2
- [ ] Verify XML is valid

### Deploy Appcast
- [ ] Deploy website: `./scripts/deploy-website.sh`
- [ ] Verify appcast accessible: https://contextify.sh/appcast.xml

## GitHub Release (DMG)

### Create GitHub Release
- [ ] Go to: https://github.com/banagale/contextify/releases/new
- [ ] Tag: v{version}
- [ ] Title: Contextify {version}
- [ ] Body: Copy from changelog
- [ ] Attach DMG: `dist/Contextify-{version}.dmg`
- [ ] Publish release

### Verify GitHub Release
- [ ] Release page accessible
- [ ] DMG downloadable
- [ ] Release notes render correctly

### Update Download Pointers
- [ ] Update `website/macos-version` to `{version}`
- [ ] Deploy website: `./scripts/deploy-website.sh --force`
- [ ] Verify: `curl -fsSL https://contextify.sh/macos-version` returns `{version}`
- [ ] Verify: `https://contextify.sh/go/dmg/` triggers correct download
- [ ] Run: `./scripts/release/version-audit.sh`
<!-- ENDIF:dmg -->

## Announcements

<!-- IF:appstore -->
**Wait for App Store approval before announcing publicly.**
<!-- ENDIF:appstore -->

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
<!-- IF:dmg -->
- [ ] Appcast updated and deployed
- [ ] GitHub release created
<!-- ENDIF:dmg -->
<!-- IF:appstore -->
- [ ] Announcements posted (after approval)
<!-- ENDIF:appstore -->
- [ ] Ready for Phase 6: Post-Release

**Completed by:** ____
**Date:** ____
