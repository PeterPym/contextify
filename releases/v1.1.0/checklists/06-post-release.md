# Post-Release Checklist

**Release:** 1.1.0
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
- [ ] New release notes page created? `website/release-notes/1.1.0.html`
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
cat dist/Contextify-1.1.0.dmg.sha256

# Download and hash the public DMG
curl -sL "https://github.com/PeterPym/contextify/releases/download/v1.1.0/Contextify-1.1.0.dmg" | shasum -a 256
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
- [ ] Verify Sparkle updates work for existing users
- [ ] Test update from previous version

## Homebrew Formula Update

**Repo:** `~/code/projects/homebrew-contextify`
**Branch:** `feature/codex-skill-support` (pre-staged with caveats update)

### Update Formula
```bash
cd ~/code/projects/homebrew-contextify
git checkout feature/codex-skill-support

# Update version
sed -i '' 's/version ".*"/version "1.1.0"/' Formula/contextify-query.rb

# Get SHA256 from release tarball
curl -sL "https://github.com/PeterPym/contextify/releases/download/v1.1.0/contextify-query-arm64.tar.gz" | shasum -a 256
# Update sha256 in formula with the output

# Commit version bump
git add -A && git commit -m "chore(formula): bump to v1.1.0"
```

### Merge and Push
- [ ] Version updated to 1.1.0
- [ ] SHA256 updated for new tarball
- [ ] Merge branch to main
- [ ] Push to origin: `git push origin main`

### Verification
```bash
brew update
brew upgrade contextify-query  # or brew install if not installed
contextify-query --version     # Should show 1.1.0
contextify-query install-plugin
ls ~/.claude/skills/total-recall/SKILL.md  # Should exist
ls ~/.codex/skills/total-recall/SKILL.md   # Should exist (new in 1.1.0)
```

- [ ] Homebrew install/upgrade works
- [ ] Both Claude and Codex skills installed
- [ ] Codex skill is real file (not symlink)

## Cleanup

### Archive Release Materials
- [ ] Ensure `releases/v1.1.0/` is complete
- [ ] All artifacts documented
- [ ] All checklists filled out

### Update Manifest
- [ ] Update `releases/manifest.json` with final status
- [ ] Set `status: "complete"` for this release

### Git Housekeeping
- [ ] Release tag exists: `git tag -l v1.1.0`
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

**Version:** 1.1.0
**Released:** ____
**DMG:** https://github.com/banagale/contextify/releases/tag/v1.1.0
**App Store:** https://apps.apple.com/app/contextify/id6753190666

**Highlights:**
- (list key changes)

**Known Issues:**
- (none, or list)

**Next Release Planning:**
- (notes for next version)
