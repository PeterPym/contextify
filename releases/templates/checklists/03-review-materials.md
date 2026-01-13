# Review Materials Checklist

**Release:** 1.0.0
**Phase:** 3 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## Changelog Analysis (Do First)

Generate comprehensive changelog before other review materials. This informs what to highlight in demos and release notes.

### Run Changelog Analysis

Use the release notes builder prompt with an AI assistant:

```bash
# View the prompt
cat releases/templates/prompts/release-notes-builder.md

# Provide these inputs when prompted:
# 1. Compare range: Check manifest.json for previous release per channel
# 2. include_merges: false (for ledger)
# 3. Channel baselines: App Store, DMG, Linux (check releases/manifest.json)
# 4. Exclusions: CI-only for external notes
```

- [ ] Run changelog analysis prompt with AI assistant
- [ ] Review generated outputs for accuracy

### Save Changelog Artifacts

Copy outputs to release directory:

```bash
mkdir -p releases/v{version}/changelog
cp /tmp/*-release-analysis.md releases/v{version}/changelog/internal-analysis.md
cp /tmp/*-release-notes-external.md releases/v{version}/changelog/external-notes.md
```

- [ ] Internal analysis saved: `releases/v{version}/changelog/internal-analysis.md`
- [ ] External notes saved: `releases/v{version}/changelog/external-notes.md`

### Verify Known Features

Cross-check that major features appear in the analysis:
- [ ] All user-facing features from this release are documented
- [ ] Channel availability (App Store vs DMG vs Linux) is accurate
- [ ] Commit counts verified (ledger matches git rev-list)
- [ ] No features missing from the analysis

**Outputs feed into:**
- Phase 4: App Store "What's New" text (from external-notes.md)
- Phase 5: Marketing announcements (from external-notes.md)
- Audit trail: Internal analysis preserved for future reference

---

## Sample Data

### Generate Sample Data
- [ ] Sample transcripts exist: `ls appstore-metadata/review-materials/sample-data.zip`
- [ ] If needed, regenerate sample data
- [ ] Copy to website: `cp appstore-metadata/review-materials/sample-data.zip website/review-4a125b1d/`

### Deploy Sample Data
- [ ] Deploy website: `./scripts/deploy-website.sh`
- [ ] Verify URL: https://contextify.sh/review-4a125b1d/sample-data.zip
- [ ] Test download works

## Demo Video

### Record Demo Video

**Automated script (recommended):**
```bash
./scripts/release/demo-recording.sh
```

This script handles: backup real transcripts, install sample data, clean sandboxed DB, reset TCC permissions, launch archived app, guide through scenes, restore real data.

**Manual steps (if needed):**
- [ ] Read script: `appstore-metadata/review-materials/DEMO-VIDEO-SCRIPT.md`
- [ ] Launch archived app: `open build/archives/v{version}/appstore/Contextify.xcarchive/Products/Applications/Contextify.app`
- [ ] Set up sample data per script instructions
- [ ] Record screen capture (QuickTime or similar)
- [ ] Video duration: ____ seconds (target: 60-90 seconds)

### Process Demo Video
- [ ] Export as MP4 (H.264, 1080p or higher)
- [ ] Save to: `website/review-4a125b1d/demo-video.mp4`
- [ ] File size: ____ MB

### Deploy Demo Video
- [ ] Deploy website: `./scripts/deploy-website.sh`
- [ ] Verify URL: https://contextify.sh/review-4a125b1d/demo-video.mp4
- [ ] Test video plays in browser

## Review Notes

### Update Review Notes
- [ ] Review notes file: `appstore-metadata/fastlane/metadata/review_information/notes.txt`
- [ ] Verify sample data URL is correct
- [ ] Verify demo video URL is correct
- [ ] Copy notes for App Store Connect:

```
(paste current notes here for reference)
```

## Validation

- [ ] Sample data URL accessible
- [ ] Demo video URL accessible
- [ ] Review notes are accurate and complete

## Sign-off

- [ ] All items complete
- [ ] Materials deployed and verified
- [ ] Ready for Phase 4: Submission

**Completed by:** ____
**Date:** ____
