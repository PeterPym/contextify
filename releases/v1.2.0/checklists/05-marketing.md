# Marketing Checklist

**Release:** 1.2.0
**Phase:** 5 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

**Note:** Marketing tasks can begin after submission (Phase 4), before App Store approval.

**Reference:** See `build/docs/operations/PUBLIC-SURFACES.md` for complete inventory of public surfaces.

## Pre-Submission Content Review

Review App Store listing content before submission. Easier to fix now than after rejection.

### App Store Listing
- [x] Parse `appstore-metadata/metadata.json` - source of truth for all metadata
- [ ] System requirements still accurate?
- [ ] Feature list reflects current capabilities?
- [ ] Screenshots show current UI? (if UI changed significantly)
- [ ] Keywords still relevant?
- [ ] Required updates: ____

### Upload Updated Metadata
If changes were made:
```bash
FASTLANE_API_KEY_PATH=".secrets/fastlane_api_key.json" fastlane deliver \
  --skip_binary_upload --skip_screenshots --force --run_precheck_before_submit false
```
- [x] Metadata uploaded to App Store Connect

## Changelog (App Only)

### Verify Scope
- [ ] Confirm `releases/config/app-paths.txt` lists correct app directories

### Generate Draft
- [ ] Run: `./scripts/release/generate-release-notes.sh 1.2.0 --from v{prev_version}`
- [ ] If "No app changes" reported, verify this is expected or adjust `--from`

### Edit and Finalize
- [ ] Review: `releases/v1.2.0/assets/changelog.llm.md`
- [ ] Edit for clarity and user focus
- [ ] Save as: `releases/v1.2.0/assets/changelog.final.md`

### Update CHANGELOG.md
- [ ] Rename `[Unreleased]` to `[1.2.0] - YYYY-MM-DD`
- [ ] Insert content from `changelog.final.md`
- [ ] Add new empty `[Unreleased]` section
- [ ] Commit: `chore(release): update changelog for 1.2.0`

### Generate Derived Formats
- [ ] Copy to App Store: `appstore-metadata/fastlane/metadata/en-US/release_notes.txt`
- [ ] Generate HTML: `website/release-notes/1.2.0.html`
- [ ] Verify Sparkle appcast will use: `<sparkle:releaseNotesLink>`

## Appcast (Sparkle)

### Update Appcast
- [ ] Edit: `website/appcast.xml`
- [ ] Add new `<item>` for 1.2.0
- [ ] Include Sparkle signature from Phase 2
- [ ] Verify XML is valid

### Deploy Appcast
- [ ] Deploy website: `./scripts/deploy-website.sh`
- [ ] Verify appcast accessible: https://contextify.sh/appcast.xml

## GitHub Release (DMG)

### Create GitHub Release
- [ ] Go to: https://github.com/banagale/contextify/releases/new
- [ ] Tag: v1.2.0
- [ ] Title: Contextify 1.2.0
- [ ] Body: Copy from changelog
- [ ] Attach DMG: `dist/Contextify-1.2.0.dmg`
- [ ] Publish release

### Verify GitHub Release
- [ ] Release page accessible
- [ ] DMG downloadable
- [ ] Release notes render correctly

## Announcements

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
