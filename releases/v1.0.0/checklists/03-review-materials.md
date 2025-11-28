# Review Materials Checklist

**Release:** 1.0.0
**Phase:** 3 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

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
- [ ] Launch archived app: `open build/archives/v1.0.0/appstore/Contextify.xcarchive/Products/Applications/Contextify.app`
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
