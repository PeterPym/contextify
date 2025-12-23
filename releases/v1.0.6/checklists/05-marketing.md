# Marketing Checklist

**Release:** 1.0.6
**Phase:** 5 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

**Note:** Marketing tasks can begin after submission (Phase 4), before App Store approval.

**Reference:** See `build/docs/operations/PUBLIC-SURFACES.md` for complete inventory of public surfaces.

## Changelog (App Only)

### Verify Scope
- [ ] Confirm `releases/config/app-paths.txt` lists correct app directories

### Generate Draft
- [ ] Run: `./scripts/release/generate-release-notes.sh 1.0.6 --from v{prev_version}`
- [ ] If "No app changes" reported, verify this is expected or adjust `--from`

### Edit and Finalize
- [ ] Review: `releases/v1.0.6/assets/changelog.llm.md`
- [ ] Edit for clarity and user focus
- [ ] Save as: `releases/v1.0.6/assets/changelog.final.md`

### Update CHANGELOG.md
- [ ] Rename `[Unreleased]` to `[1.0.6] - YYYY-MM-DD`
- [ ] Insert content from `changelog.final.md`
- [ ] Add new empty `[Unreleased]` section
- [ ] Commit: `chore(release): update changelog for 1.0.6`

### Generate Derived Formats
- [ ] Copy to App Store: `appstore-metadata/fastlane/metadata/en-US/release_notes.txt`

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
- [ ] Announcements posted (after approval)
- [ ] Ready for Phase 6: Post-Release

**Completed by:** ____
**Date:** ____
