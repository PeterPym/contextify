# App Store Rejection Response Plan

**Submission ID:** 4a125b1d-7e23-4cb4-be80-09aaa29168cf
**Date:** November 26, 2025
**Version:** 1.0

---

## Rejection Issues

### Issue 1: Sample Files (Guideline 2.1)
Apple needs sample Claude project files to test the summarize feature. Must be hosted at a permanent URL.

### Issue 2: Demo Video (Guideline 2.1)
Apple needs a video demonstrating the app on a physical macOS device showing all features and permission requests.

---

## Action Items

### 1. Create Sample Data Package

**Location:** `appstore-metadata/review-materials/sample-data/`

**Contents:**
- Synthetic Claude Code transcript files (`.jsonl` format)
- README with setup instructions for reviewers
- Should demonstrate:
  - Multiple conversations in a project
  - User/assistant message exchanges
  - Enough content to trigger LLM summarization

**Hosting:**
- Upload to `https://contextify.sh/review-4a125b1d/sample-data.zip`
- Alternative: GitHub release asset (permanent URL)

**File structure to create:**
```
sample-data/
├── README.txt                    # Setup instructions
├── claude-projects/
│   └── sample-project/
│       ├── session-001.jsonl     # Sample conversation 1
│       ├── session-002.jsonl     # Sample conversation 2
│       └── session-003.jsonl     # Sample conversation 3
```

### 2. Create Demo Video

**Requirements:**
- Screen recording on physical Mac (not simulator)
- Show ALL features:
  - First launch / permissions grant
  - Project detection and switching
  - Timeline view with real-time updates
  - LLM-powered summarization
  - Search functionality (Quick Search + Deep Search)
  - File ingestion (drag & drop)
  - Settings panel
  - Database location options
- Duration: 2-4 minutes recommended
- Format: MP4 or MOV (H.264)

**Location:** `appstore-metadata/review-materials/demo-video/`

**Hosting:**
- Upload to `https://contextify.sh/review-4a125b1d/demo-video.mp4`
- Add URL to App Review Information in App Store Connect

**Script outline:**
1. Launch app (show dock icon, menu bar)
2. Grant transcript access permission
3. Show project auto-detection
4. View timeline with conversations
5. Demonstrate search (type query, show results)
6. Open Deep Search window
7. Show LLM summaries generating
8. Drag & drop a file (show ingestion)
9. Open Settings, show database options
10. Switch projects

### 3. Update App Review Notes

**Location:** App Store Connect → App Review Information → Notes

**Content to add:**
```
DEMO VIDEO:
https://contextify.sh/review-4a125b1d/demo-video.mp4

SAMPLE DATA:
Download sample Claude Code transcript files:
https://contextify.sh/review-4a125b1d/sample-data.zip

SETUP INSTRUCTIONS:
1. Download sample-data.zip from URL above
2. Extract to ~/.claude/projects/sample-project/
3. Launch Contextify
4. App will detect the sample project and display timeline
5. LLM summaries will generate automatically (requires network)

PERMISSIONS:
The app requires access to ~/.claude/ directory to read Claude Code transcripts.
A permission dialog will appear on first launch.

FEATURES TO TEST:
- Timeline view (shows conversation history)
- LLM summaries (auto-generated for each conversation)
- Search (Cmd+F for quick search, Cmd+Shift+F for deep search)
- File ingestion (drag files onto the HUD)
- Project switching (if multiple projects exist)
```

---

## Documentation Updates

### 1. Update `scripts/RELEASE.md`

Add to "App Store Releases" section:

```markdown
### App Review Materials

Before submitting to App Store, ensure these materials are prepared:

#### Required: Demo Video
- Location: `https://contextify.sh/review-4a125b1d/demo-video.mp4`
- Update video when significant UI/feature changes occur
- Must show: permissions, timeline, search, summaries, file ingestion

#### Required: Sample Data
- Location: `https://contextify.sh/review-4a125b1d/sample-data.zip`
- Synthetic Claude Code transcripts for testing
- Update if transcript format changes

#### App Review Notes Template
Copy to App Store Connect → App Review Information:
[Include template from above]
```

### 2. Update `build/docs/guides/APP-STORE-SUBMISSION.md`

Add new section before "Submit for Review":

```markdown
## App Review Materials

Apple requires demonstration materials for apps that access external data.

### Demo Video (Required)
- Hosted at: `https://contextify.sh/review-4a125b1d/demo-video.mp4`
- Add URL to App Review Information → Notes
- Must be updated for each submission with significant changes
- Shows: permissions, all features, real device usage

### Sample Data (Required)
- Hosted at: `https://contextify.sh/review-4a125b1d/sample-data.zip`
- Synthetic Claude Code transcript files
- Instructions in README.txt for Apple reviewers
- Place in ~/.claude/projects/sample-project/

### App Review Notes
Include in App Store Connect → App Review Information:
- Demo video URL
- Sample data URL
- Setup instructions
- List of features to test
- Permission explanations
```

### 3. Update `appstore-metadata/README.md`

Update submission checklist to include:

```markdown
### Before First Submission
- [ ] Create demo video showing all features
- [ ] Upload demo video to contextify.sh/review-4a125b1d/
- [ ] Create sample data package with synthetic transcripts
- [ ] Upload sample data to contextify.sh/review-4a125b1d/
- [ ] Add demo video URL to App Review Notes
- [ ] Add sample data URL and setup instructions to App Review Notes
```

### 4. Create `appstore-metadata/review-materials/README.md`

New file documenting the review materials structure and maintenance.

---

## Implementation Order

1. **Create sample data** - Synthetic transcript files
2. **Upload to contextify.sh** - Deploy sample data
3. **Record demo video** - Screen capture of full workflow
4. **Upload demo video** - Deploy to contextify.sh
5. **Update App Review Notes** - Add URLs and instructions to App Store Connect
6. **Update documentation** - All the docs listed above
7. **Resubmit** - Reply to rejection with materials ready

---

## Hosting Details

### contextify.sh Server
- Location: web@banagale.com (DigitalOcean)
- Deploy script: `scripts/deploy-website.sh`
- Files go in: `/var/www/contextify/review/`

### File URLs
- `https://contextify.sh/review-4a125b1d/demo-video.mp4`
- `https://contextify.sh/review-4a125b1d/sample-data.zip`
- `https://contextify.sh/review-4a125b1d/README.txt` (optional - instructions page)

---

## Notes

- Demo video must be re-recorded for each submission if UI/features changed significantly
- Sample data should rarely need updates (transcript format is stable)
- Keep review materials permanently hosted - Apple may re-review during updates
