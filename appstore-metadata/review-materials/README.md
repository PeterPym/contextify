# App Store Review Materials

Materials required for App Store review when Apple requests additional information (Guideline 2.1).

## When These Are Needed

Apple may request review materials when:
- App accesses external data sources (like transcript files)
- Features require specific setup to test
- App behavior isn't immediately apparent from screenshots

## Directory Structure

```
review-materials/
├── README.md                      # This file
├── DEMO-VIDEO-SCRIPT.md           # Recording script for demo video
├── REJECTION-RESPONSE-PLAN.md     # Response strategy (for reference)
├── SAMPLE-TRANSCRIPT-PLAN.md      # Conversation scripts used to generate samples
├── SESSION-NOTES.md               # Work session history
├── generate-transcripts.sh        # Script to regenerate sample data
├── sample-data.zip                # Packaged sample transcripts
└── sample-transcripts/            # Raw transcript files (57 files)
```

## Required Materials

### 1. Demo Video

**Purpose:** Show all app features on physical Mac device

**Script:** `DEMO-VIDEO-SCRIPT.md`

**Hosting:** `https://contextify.sh/review-4a125b1d/demo-video.mp4`

**When to update:**
- Major UI changes
- New features added
- Apple requests updated video
- Each submission (per Apple's requirements)

### 2. Sample Data

**Purpose:** Allow Apple to test the summarize feature with real transcript files

**Package:** `sample-data.zip` (100KB)

**Contents:**
- 54 Claude Code transcripts across 3 sample projects
- 3 Codex CLI sessions
- README.txt with setup instructions

**Hosting:** `https://contextify.sh/review-4a125b1d/sample-data.zip`

**When to update:**
- Transcript format changes
- Parser changes that affect compatibility
- Apple requests different sample data

## Hosted Files

Files are deployed to `https://contextify.sh/review-4a125b1d/` via:

```bash
./scripts/deploy-website.sh
```

Source files in `website/review/`:
- `index.html` - Instructions page for Apple reviewers
- `sample-data.zip` - Sample transcript package
- `demo-video.mp4` - Demo video (add after recording)

## Workflow for New Submissions

### First-Time Setup

1. Generate sample transcripts:
   ```bash
   ./appstore-metadata/review-materials/generate-transcripts.sh
   ```

2. Package sample data:
   ```bash
   cd appstore-metadata/review-materials
   zip -r sample-data.zip sample-transcripts/ -x "*.DS_Store"
   cp sample-data.zip ../../website/review/
   ```

3. Record demo video following `DEMO-VIDEO-SCRIPT.md`

4. Deploy to website:
   ```bash
   ./scripts/deploy-website.sh
   ```

5. Add URLs to App Store Connect review notes

### For Subsequent Submissions

1. Check if sample data needs updating (transcript format changes?)
2. Record new demo video if UI/features changed
3. Deploy any updated files
4. Update App Store Connect review notes if URLs changed

## App Store Connect Review Notes

Add to **App Review Information > Notes**:

```
DEMO VIDEO:
https://contextify.sh/review-4a125b1d/demo-video.mp4

SAMPLE DATA:
https://contextify.sh/review-4a125b1d/sample-data.zip

SETUP INSTRUCTIONS:
https://contextify.sh/review-4a125b1d/

The sample data contains Claude Code transcript files. Extract and copy to
~/.claude/projects/ to test the app's summarization features.
```

## Rejection History

| Date | Version | Issue | Resolution |
|------|---------|-------|------------|
| 2025-11-26 | 1.0 (3) | Guideline 2.1 - Need sample files and demo video | Created sample transcripts and video script |

## Future Materials

When adding new review materials:

1. Add files to this directory
2. Update this README with description
3. If hosted, add to `website/review/` and redeploy
4. Update App Store Connect review notes

## Related Documentation

- `../README.md` - Main App Store metadata guide
- `../app-previews/APP-PREVIEW-SPECIFICATIONS.md` - Marketing video specs (different from review demo)
- `../../build/docs/operations/release/RELEASE-PROCESS.md` - Release process including App Store submission
